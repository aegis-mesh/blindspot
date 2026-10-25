#!/usr/bin/env bash
# Runs gird-check.ps1 against a fake Windows-shaped home folder (USERPROFILE,
# APPDATA, LOCALAPPDATA and TEMP all point into it) and checks what it finds, what
# it must never print or send, and that its report matches gird-check.sh's.
#
#   PWSH=/path/to/pwsh bash tests/run-ps.sh
#
# PWSH defaults to pwsh on PATH. When GIRD_CHECK_WORKER points at the site's report validation
# (worker/check-stats.js), the report is checked against it too.
# Windows PowerShell 5.1 can't run here; the 5.1 syntax checks below are textual.
# shellcheck disable=SC2088  # the patterns match the literal ~ the script prints for home paths
set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT=$PWD/gird-check.ps1
BASH_SCRIPT=$PWD/gird-check.sh
PWSH=${PWSH:-$(command -v pwsh)}
if [ -z "$PWSH" ] || [ ! -x "$PWSH" ]; then echo "pwsh not found: set PWSH"; exit 1; fi
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t blindspot)
MOCK_PID=""
trap '[ -n "$MOCK_PID" ] && { kill "$MOCK_PID"; wait "$MOCK_PID"; } 2>/dev/null; rm -rf "$WORK"' EXIT
. tests/lib.sh
command -v python3 >/dev/null 2>&1 || { echo "tests/run-ps.sh needs python3: it builds fixtures and runs the local mock with it"; exit 1; }

# A Windows-shaped copy of tests/make-fixture.sh's home: the same planted keys, with
# the files that live under AppData on Windows moved there, and a key typed into
# PowerShell's history.
winify() { # home keys
  _f=$1; _r="$_f/AppData/Roaming"; _l="$_f/AppData/Local"
  mkdir -p "$_r" "$_l/Temp" "$_r/Microsoft/Windows/PowerShell/PSReadLine" "$_l/AnthropicClaude"
  if [ -d "$_f/Library/Application Support" ]; then cp -R "$_f/Library/Application Support/." "$_r/"; rm -rf "$_f/Library"
  else cp -R "$_f/.config/Cursor" "$_r/" 2>/dev/null; rm -rf "$_f/.config/Cursor"; fi
  mkdir -p "$_r/Block/goose/config"; mv "$_f/.config/goose/config.yaml" "$_r/Block/goose/config/config.yaml"; rm -rf "$_f/.config/goose"
  printf '$env:GITHUB_TOKEN = "%s"\ngit push\n' "$(sed -n 3p "$2")" > "$_r/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt"
}
# Runs the script with a minimal environment, so nothing on this machine leaks in.
psrun() { # home [env...] -- args...
  _h=$1; shift; _e=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do _e+=("$1"); shift; done; shift
  env -i PATH="$WORK/bin" HOME="$WORK/pshome" USERPROFILE="$_h" APPDATA="$_h/AppData/Roaming" \
    LOCALAPPDATA="$_h/AppData/Local" TEMP="$_h/AppData/Local/Temp" LANG=en_US.UTF-8 ${_e[@]+"${_e[@]}"} \
    "$PWSH" -NoProfile -NonInteractive -File "$SCRIPT" "$@"
}
mkdir -p "$WORK/bin" "$WORK/pshome"
bash tests/make-fixture.sh "$WORK/home" "$WORK/keys.txt"; winify "$WORK/home" "$WORK/keys.txt"
bash tests/make-fixture.sh "$WORK/clean" "$WORK/keys-clean.txt" clean; winify "$WORK/clean" "$WORK/keys-clean.txt"
rm -rf "$WORK/clean/.local/share/opencode" "$WORK/clean/AppData/Roaming/Microsoft"

echo "Windows PowerShell 5.1 compatibility (by reading the script)"
if LC_ALL=C grep -q '[^ -~]' "$SCRIPT"; then bad "the script is plain ASCII, so 5.1 reads it right without a BOM"; else ok "the script is plain ASCII, so 5.1 reads it right without a BOM"; fi
# Strip comments and quoted strings first, so prose can't trip the checks.
sed -e 's/#.*$//' -e "s/'[^']*'//g" -e 's/"[^"]*"//g' "$SCRIPT" > "$WORK/code.txt"
hasnot "no ?? or ?. operators (PowerShell 7 only)"     '\?\?|\?\.' "$WORK/code.txt"
hasnot "no ternary a ? b : c (PowerShell 7 only)"      ' \? [^ ]+ : ' "$WORK/code.txt"
hasnot "no && or || pipeline chains (PowerShell 7 only)" '&&|\|\|' "$WORK/code.txt"
hasnot "no -Parallel, -AsHashtable or \$IsWindows"     '-Parallel|-AsHashtable|\$Is(Windows|MacOS|Linux)\b' "$WORK/code.txt"
if "$PWSH" -NoProfile -NonInteractive -Command "\$e = \$null; [void][Management.Automation.Language.Parser]::ParseFile('$SCRIPT', [ref]\$null, [ref]\$e); if (\$e.Count) { \$e | ForEach-Object { \$_.Message }; exit 1 }" > "$WORK/parse.txt" 2>&1
then ok "parses"; else bad "parses"; sed 's/^/        /' "$WORK/parse.txt" | head -n 5; fi

echo "pwsh $("$PWSH" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
if psrun "$WORK/home" -- -Help > "$WORK/help.txt" 2>&1 && grep -q -- '-Offline' "$WORK/help.txt"; then ok "-Help lists the options"; else bad "-Help lists the options"; fi
psrun "$WORK/home" -- --bogus > "$WORK/bogus.txt" 2>&1; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'Unknown option' "$WORK/bogus.txt"; then ok "an unknown option exits 2"; else bad "an unknown option exits 2" "got $RC"; fi

OUT=$WORK/out.txt
psrun "$WORK/home" -- -Offline > "$OUT" 2> "$WORK/err.txt"; RC=$?
if [ "$RC" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got $RC"; fi
if [ -s "$WORK/err.txt" ]; then bad "writes nothing to stderr"; sed 's/^/        /' "$WORK/err.txt" | head -n 5; else ok "writes nothing to stderr"; fi
has    "finds keys in the shell profile"       '~/\.zshrc +Anthropic, OpenAI' "$OUT"
has    "finds keys in shell history"           '~/\.zsh_history +GitHub' "$OUT"
has    "flags a key in PowerShell's history"   'PSReadLine/ConsoleHost_history\.txt' "$OUT"
has    "names the provider of that key"        '^ {54}GitHub$' "$OUT"
has    "finds keys in a project .env file"     '~/code/app/\.env +AWS, Groq' "$OUT"
has    "full output lists every key file"      '~/\.cursor/mcp\.json +GitHub' "$OUT"
hasnot "ignores placeholders in .env.example"  'env\.example' "$OUT"
has    "counts Claude Code MCP servers"        'Claude Code +~/\.claude\.json +3 servers' "$OUT"
has    "counts Codex MCP servers"              '~/\.codex/config\.toml +2 servers' "$OUT"
has    "reads Cline's config under AppData"    'Cline in Cursor ~/AppData/Roaming/Cursor/User/globalStorage/' "$OUT"
has    "and counts its servers"                '^ {56}3 servers$' "$OUT"
has    "reads Goose's config under AppData"    'Goose +~/AppData/Roaming/Block/goose/config/config\.yaml' "$OUT"
has    "counts MCP servers in total"           'MCP SERVERS +14 servers' "$OUT"
has    "spots a token in an MCP config"        'Cursor +~/\.cursor/mcp\.json +1 server, token in the file' "$OUT"
has    "flags a key in a Claude allow list"    'code/app/\.claude/settings\.local\.json' "$OUT"
has    "warns an npm publish would ship it"    'npm publish from this folder would include it' "$OUT"
hasnot "ignores placeholder allow lists"       'code/lib/\.claude' "$OUT"
has    "sees an agent that is installed but idle" 'Codex +installed, not used in 30 days' "$OUT"
has    "sees an agent in use"                  'Claude Code +used in the last 30 days' "$OUT"
has    "finds Claude Desktop under AppData"    'Claude Desktop +installed, no use recorded' "$OUT"
has    "finds LiteLLM malware markers"         'signs of the malware found' "$OUT"
has    "finds the bad package in the uv cache" 'uv cache holds the 1\.107\.0 package' "$OUT"
has    "counts SSH keys with no passphrase"    '2 SSH private keys, 1 with no passphrase' "$OUT"
has    "flags project hooks and MCP auto-approval" 'Set to run commands while the agent works, turn on MCP servers' "$OUT"
has    "flags a folderOpen task"               'code/cloned/\.vscode/tasks\.json' "$OUT"
has    "flags a remote API address in project settings" 'code/proxy/\.claude/settings\.json' "$OUT"
hasnot "ignores a localhost API address"       'code/lib/\.claude/settings\.json' "$OUT"
hasnot "ignores a task that does not run on open" 'code/own/\.vscode' "$OUT"
hasnot "ignores the person's own global hooks" '^ +! +~/\.claude/settings\.json' "$OUT"
has    "finds a bad axios in a package-lock"   'axios 1\.14\.1 \(Axios takeover, March 2026\)' "$OUT"
has    "finds a bad TanStack version in pnpm-lock" '@tanstack/router-core 1\.169\.5 \(TanStack worm' "$OUT"
has    "finds a bad keyv in a yarn berry lock" 'keyv 6\.0\.0 \(keyv worm' "$OUT"
hasnot "ignores near-miss versions and names" 'axios 1\.14\.10|my-axios|keyv 6\.0\.0-|keyv 6\.0\.1|code/lib/package-lock' "$OUT"
has    "finds a bad version in a pnpm 8 lockfile" '@tanstack/history 1\.161\.9 \(TanStack worm' "$OUT"
has    "finds a planted worm file"            'code/planted/\.vscode/router_runtime\.js' "$OUT"
hasnot "a worktree with the same settings is not listed again" 'worktrees/w1' "$OUT"
has    "and is counted under its repo's row" 'The same settings are in$' "$OUT"
has    "a localhost name with a login prefix is not local" 'code/sneaky/\.claude/settings\.json' "$OUT"
has    "finds any version of a fake AI tool package" 'claud-code 1\.0\.3 \(SANDWORM_MODE worm' "$OUT"
has    "finds a bad package in npm's cache"    '@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI' "$OUT"
has    "puts the wiper first"                  'ACT NOW: REMOVE GH-TOKEN-MONITOR BEFORE YOU REVOKE ANY TOKEN' "$OUT"
has    "lists the wiper's files"               '~/\.config/gh-token-monitor' "$OUT"
has    "a hook that runs a planted worm file counts as malware" '^ +~/code/cloned/\.claude/settings\.json$' "$OUT"
tr -s ' \n' '  ' < "$OUT" > "$WORK/out-flat.txt"   # the advice wraps, so it is matched on one line
has    "off Windows it points at a secrets manager" 'files into a secrets manager, then rotate' "$WORK/out-flat.txt"
hasnot "off Windows it never points at the Keychain" 'macOS Keychain' "$WORK/out-flat.txt"
has    "other rotate fixes wait for the wiper"         'then rotate them\. Only once gh-token-monitor is stopped and removed' "$WORK/out-flat.txt"
has    "section 5's rotate fixes wait for it too"      'rotate every key this machine could reach\. Only once gh-token-monitor is stopped and removed' "$WORK/out-flat.txt"
hasnot "the wiper's own fix does not wait for itself"  'stops working\.( Then rotate every key this machine could reach\.)? Only once' "$WORK/out-flat.txt"
has    "the wiper's warning says it tries to erase the home folder, as Wiz says" 'and in the TanStack wave it tries to erase the home folder\.' "$WORK/out-flat.txt"
hasnot "and never that it erased one"                  'erased the home folder' "$WORK/out-flat.txt"
# Sentences of a report that say to rotate or revoke without waiting for gh-token-monitor. A sentence
# passes if it names gh-token-monitor, if the wait for it follows within two sentences (a platform's
# advice ends with it), or if it is the wiper's own fix, whose next sentence says to stop it first.
unwaited() { # file
  python3 -I -c '
import re, sys
t = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1], encoding="utf-8", errors="replace").read())
s = re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", t))
for i, x in enumerate(s):
    if not re.search(r"[Rr]otate|[Rr]evoke", x) or "gh-token-monitor" in x: continue
    if any(n.startswith("Only once gh-token-monitor is stopped and removed") for n in s[i + 1:i + 3]): continue
    if "revoke any GitHub token yet" in x and s[i + 1:i + 2] and s[i + 1].startswith("First stop and remove gh-token-monitor"): continue
    if x.startswith("Then rotate every key this machine could reach") and i and s[i - 1].startswith("First stop and remove gh-token-monitor"): continue
    print(x)' "$1"
}
cp -R "$WORK/home" "$WORK/wwait"; mkdir -p "$WORK/wwait/.config/zeabur" "$WORK/wwait/.railway"; printf '{}\n' > "$WORK/wwait/.railway/config.json"
psrun "$WORK/wwait" -- -Offline -Full -AllSessions > "$WORK/wwait.txt" 2>&1
psrun "$WORK/wwait" GIRD_CHECK_COMPACT=1 -- -Offline -AllSessions >> "$WORK/wwait.txt" 2>&1
_u=$(unwaited "$WORK/wwait.txt")
if grep -qE 'Zeabur +CLI found' "$WORK/wwait.txt" && grep -q 'Keys in agent sessions' "$WORK/wwait.txt" && [ -z "$_u" ]; then ok "with the wiper present, no rotate or revoke anywhere in the report goes without the wait"
else bad "with the wiper present, no rotate or revoke anywhere in the report goes without the wait" "$(printf '%s' "${_u:-the fixture lost its sessions or platforms}" | head -n 3 | tr '\n' '|')"; fi
tr -s ' \n' '  ' < "$WORK/wwait.txt" > "$WORK/wwait-flat.txt"
has    "the session keys wait for the wiper"         'Treat these keys as exposed and rotate them\. Only once gh-token-monitor is stopped and removed' "$WORK/wwait-flat.txt"
has    "the link flags npm malware and the wiper"      'nm=1&py=0&ex=0&wp=1$' "$OUT"
has    "uses the non-Mac Argus line"           'Argus, our free Mac app, shows what AI coding agents' "$OUT"
hasnot "never offers the Argus download off a Mac" 'argus/download' "$OUT"
hasnot "never shows a letter grade"            'GRADE [ABCDF]|[Gg]rade [ABCDF]\b' "$OUT"
has    "the offline link has key counts, no run ID or rank" 'blindspot/card/#v=2&.*&u=&r=&sk=2&hk=2&ag=[a-z0-9.-]*&nm=[01]&py=[01]&ex=[01]&wp=[01]$' "$OUT"
nokeys "never prints a planted key" "$WORK/keys.txt" "$OUT"
if LC_ALL=C grep -aq "$(printf '\033')" "$OUT"; then bad "plain output has no escape codes"; else ok "plain output has no escape codes"; fi

echo "keys in agent sessions"
SE=$WORK/sess; mkdir -p "$SE/rgbin"
RG=$(command -v rg 2>/dev/null); [ -n "$RG" ] && ln -s "$RG" "$SE/rgbin/rg"
# Random key pieces, as tests/make-fixture.sh builds them: no key-shaped string is written here.
rnd()   { head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c "$1"; }
upper() { head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Z0-9' | head -c "$1"; }
_tab=$(printf '\t'); _nl=$(printf '\nx'); _nl=${_nl%x}
# Without ripgrep its engine's tests are skipped. A CI job that installs ripgrep sets
# GIRD_CHECK_TEST_REQUIRE_RG, so a missing ripgrep fails there instead of skipping.
NORG=""
if [ -n "$RG" ]; then ok "ripgrep is on PATH"
elif [ -n "${GIRD_CHECK_TEST_REQUIRE_RG:-}" ]; then bad "ripgrep is on PATH" "GIRD_CHECK_TEST_REQUIRE_RG is set, so the ripgrep engine must be tested here"; NORG="ripgrep is not installed"
else skip "ripgrep is on PATH" "ripgrep is not installed, so its engine is not tested here"; NORG="ripgrep is not installed"; fi
for E in net rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  psrun "$WORK/home" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline > "$SE/$E.txt" 2>&1
  sed -n '/Keys in agent sessions/,/^$/p' "$SE/$E.txt" > "$SE/$E.block"
  tr -s ' \n' '  ' < "$SE/$E.block" > "$SE/$E.flat"   # the notes wrap
  has    "$E: a key after an escaped newline in a Claude Code session" 'Claude Code +1 file: Hugging Face' "$SE/$E.block"
  has    "$E: a key in a Codex session"            'Codex +1 file: OpenAI' "$SE/$E.block"
  has    "$E: a session in another place is listed under that place" '^ +~/\.codex/sessions +1 file$' "$SE/$E.block"
  has    "$E: a key in an Aider history"           'Aider +1 file: Groq' "$SE/$E.block"
  hasnot "$E: a made-up key is not counted"        'Claude Code .*(Anthropic|AWS|GitHub)' "$SE/$E.block"
  hasnot "$E: a key of counting digits is made up" 'Claude Code .*Groq' "$SE/$E.block"
  has    "$E: a real key with few different characters counts" 'Codex +1 file: OpenAI, AWS' "$SE/$E.block"
  has    "$E: a compressed session is named as not checked" '1 compressed session file was not checked' "$SE/$E.block"
  has    "$E: says to rotate them"                 'Treat these keys as exposed and rotate them' "$SE/$E.txt"
  has    "$E: names encrypted sessions as not checked" '1 Windsurf conversation file is encrypted, so it was not checked' "$SE/$E.flat"
  nokeys "$E: never prints a key" "$WORK/keys.txt" "$SE/$E.txt"
done
SKIPPING=$NORG
if diff -q "$SE/net.block" "$SE/rg.block" >/dev/null; then ok ".NET and ripgrep report the same"; else bad ".NET and ripgrep report the same" "$(diff "$SE/net.block" "$SE/rg.block" | head -n 6)"; fi
SKIPPING=""
bash tests/make-fixture.sh "$SE/bh" "$SE/bk" >/dev/null
# --all-sessions: without it a fast machine can finish the rest first, stop the session check
# part-way and list nothing, which is the script working as designed but not a comparison.
HOME="$SE/bh" PATH=/usr/bin:/bin bash "$BASH_SCRIPT" --offline --all-sessions 2>&1 | sed -n '/Keys in agent sessions/,/^$/p' > "$SE/bash.block"
if diff -q "$SE/bash.block" "$SE/net.block" >/dev/null; then ok "the same session block as gird-check.sh"; else bad "the same session block as gird-check.sh"; diff "$SE/bash.block" "$SE/net.block" | head -n 6; fi
# Session files are listed by place, one row each with how many of its files had keys. A place is
# the session folder an agent keeps, or the file when the location is one file.
HFK="hf""_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu"
sessfix() { # home folder:count...: that many session files with a key in each folder under home
  _d=$1; shift
  mkdir -p "$_d/AppData/Roaming" "$_d/AppData/Local/Temp"
  for _s in "$@"; do
    _p=${_s%:*}; _c=${_s##*:}; mkdir -p "$_d/$_p"
    for _i in $(seq 1 "$_c"); do printf '{"t":"%s end"}\n' "$HFK" > "$_d/$_p/agent-$_i.jsonl"; done
  done
}
LONGP=$(printf 'long-folder-name-%.0s' 1 2 3 4 5 6)tail-marker-end
sessfix "$SE/g1" .claude/projects/proj-one/s1/subagents:4
sessfix "$SE/g2" .claude/projects/p/s1:2 .codex/sessions/2026/10:5
sessfix "$SE/g3" "$LONGP/projects/p:12"
sessfix "$SE/g4"
for _n in $(seq -w 1 23); do mkdir -p "$SE/g4/code/p$_n"; printf '> %s\n' "$HFK" > "$SE/g4/code/p$_n/.aider.chat.history.md"; done
for _g in g1 g2 g3 g4; do
  _ev=(); [ "$_g" = g3 ] && _ev=(CLAUDE_CONFIG_DIR="$SE/g3/$LONGP")
  psrun "$SE/$_g" ${_ev[@]+"${_ev[@]}"} GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/$_g.txt" 2>&1
  sed -n '/Keys in agent sessions/,/^$/p' "$SE/$_g.txt" > "$SE/$_g.block"
done
has    "several files in one place collapse into one row with their count" '^ +~/\.claude/projects +4 files$' "$SE/g1.block"
hasnot "and are not listed one by one, nor their project folders" 'agent-[0-9]+\.jsonl|subagents|proj-one' "$SE/g1.block"
_lc=$(grep -an '~/\.codex/sessions ' "$SE/g2.block" | cut -d: -f1); _lp=$(grep -an '~/\.claude/projects ' "$SE/g2.block" | cut -d: -f1)
if [ -n "$_lc" ] && [ -n "$_lp" ] && [ "$_lc" -lt "$_lp" ]; then ok "two places are ordered by count"; else bad "two places are ordered by count"; fi
has    "a long place is shortened in the middle and keeps its end" '^ +~/long-.*\.\.\..*tail-marker-end/projects +12 files$' "$SE/g3.block"
has    "more than 20 places end with how many more" '^ +and 3 more$' "$SE/g4.block"
if [ "$(grep -acE '^ +~/code/p[0-9]+/\.aider\.chat\.history\.md +1 file$' "$SE/g4.block")" -eq 20 ]; then ok "and show 20 of them"; else bad "and show 20 of them"; fi
if cat "$SE"/g?.block | grep -av '✗' | LC_ALL=C awk 'length($0) > 80 { bad = 1 } END { exit bad }'; then ok "no session row is wider than 80 columns"; else bad "no session row is wider than 80 columns"; fi
for _g in g1 g2 g3 g4; do
  _ev=(); [ "$_g" = g3 ] && _ev=(CLAUDE_CONFIG_DIR="$SE/g3/$LONGP")
  env HOME="$SE/$_g" ${_ev[@]+"${_ev[@]}"} PATH=/usr/bin:/bin bash "$BASH_SCRIPT" --offline --all-sessions 2>&1 | sed -n '/Keys in agent sessions/,/^$/p' > "$SE/$_g.bash"
done
if cat "$SE"/g?.bash | diff -q - <(cat "$SE"/g?.block) >/dev/null; then ok "the same folder rows as gird-check.sh"; else bad "the same folder rows as gird-check.sh"; fi
psrun "$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_STOP_AFTER=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/part.txt"
has    "a partial check says how much it covered" 'Checked the newest 2 of 6 agent session files' "$SE/part.txt"
psrun "$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline > "$SE/clean.txt" 2>&1
has    "a full check with nothing found says so" 'No keys in 2 agent session files\.' "$SE/clean.txt"
psrun "$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_STOP_AFTER=0 -- -Offline > "$SE/clean-part.txt" 2>&1
hasnot "a partial check with nothing found never says no keys" 'No keys in .*agent session' "$SE/clean-part.txt"
has    "and says it was partial"                 'Checked the newest 0 of 2 agent session files' "$SE/clean-part.txt"
psrun "$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=none -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/none.txt"
has    "with no engine the sessions are named as not checked" 'agent session files were not checked\.' "$SE/none.txt"
# A file that can't be read is not counted as checked.
mkdir -p "$SE/unread/.claude/projects/p" "$SE/unread/AppData/Roaming" "$SE/unread/AppData/Local/Temp"
printf '{}\n' > "$SE/unread/.claude/projects/p/a.jsonl"; printf '{}\n' > "$SE/unread/.claude/projects/p/b.jsonl"; chmod 000 "$SE/unread/.claude/projects/p/b.jsonl"
psrun "$SE/unread" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/unread-net.txt"
has    "net: an unreadable session is not counted as checked" 'Agent sessions were partly checked: 1 file could not be read' "$SE/unread-net.txt"
SKIPPING=$NORG
psrun "$SE/unread" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=rg -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/unread-rg.txt"
has    "rg: an unreadable session means partly checked" 'Agent sessions were partly checked' "$SE/unread-rg.txt"
SKIPPING=""
# A long token that crosses a 1 MB piece is not mistaken for a key.
for D in piece esc esc2; do mkdir -p "$SE/$D/.claude/projects/p" "$SE/$D/AppData/Roaming" "$SE/$D/AppData/Local/Temp"; done
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 40) + 'hf_' + 'Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAuCiEoXkYnZqWdTgPrMsBvLj' + '\n')" "$SE/piece/.claude/projects/p/a.jsonl"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 2) + '\\\\n' + 'h' + 'f_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu end' + '\n')" "$SE/esc/.claude/projects/p/a.jsonl"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 1) + '\\\\' + 'nh' + 'f_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu end' + '\n')" "$SE/esc2/.claude/projects/p/a.jsonl"
psrun "$SE/esc2" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/esc2.txt" 2>&1
has    "net: a key after a backslash that ends a read is found" 'Claude Code +1 file: Hugging Face' "$SE/esc2.txt"
for E in net rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  psrun "$SE/piece" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/piece-$E.txt" 2>&1
  has    "$E: a token across a piece boundary is not a key" 'No keys in 1 agent session file' "$SE/piece-$E.txt"
  psrun "$SE/esc" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/esc-$E.txt" 2>&1
  has    "$E: a key after an escaped newline at a piece boundary is found" 'Claude Code +1 file: Hugging Face' "$SE/esc-$E.txt"
done
SKIPPING=""
# Keys at the start of a line (after a newline, not only at the start of a file), in the middle
# of one and after an escaped newline, for every format that needs a boundary in front of it:
# legacy OpenAI sk-, Google AQ., Hugging Face hf_ and AWS AKIA. One file per key and place.
mkdir -p "$SE/pos/.claude/projects/p" "$SE/pos/AppData/Roaming" "$SE/pos/AppData/Local/Temp"
_n=0
for _k in "sk""-$(rnd 48)" "AQ"".$(rnd 40)" "h""f_$(rnd 36)" "AK""IA$(upper 16)"; do
  _n=$((_n + 1))
  printf '{"a":1}\n%s was pasted\n' "$_k" > "$SE/pos/.claude/projects/p/start-$_n.jsonl"
  printf '{"a":"x %s y"}\n' "$_k" > "$SE/pos/.claude/projects/p/mid-$_n.jsonl"
  printf '{"a":"text\\n%s\\nmore"}\n' "$_k" > "$SE/pos/.claude/projects/p/esc-$_n.jsonl"
done
# A folder name with a tab or a newline in it under a session root; a 2 MB run of key characters
# (data, not a key: the longest format is under 100 characters) in a session and in an Aider
# history; and a folder under a session root that can't be read, whose files are unknown, so the
# check is not complete.
for D in tabdir nldir long urdir; do mkdir -p "$SE/$D/AppData/Roaming" "$SE/$D/AppData/Local/Temp"; done
mkdir -p "$SE/tabdir/.claude/projects/p${_tab}q" "$SE/nldir/.claude/projects/p${_nl}q" "$SE/long/.claude/projects/p" "$SE/long/code/big"
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/tabdir/.claude/projects/p${_tab}q/a.jsonl"
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/nldir/.claude/projects/p${_nl}q/a.jsonl"
python3 -c "
import sys, random
random.seed(7); cs = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
run = 'sk-' + 'proj-' + ''.join(random.choice(cs) for _ in range(2 * 1024 * 1024))
open(sys.argv[1], 'w').write('{\"x\":\"' + run + '\"}\n'); open(sys.argv[2], 'w').write('#### output\n' + run + '\n')" "$SE/long/.claude/projects/p/a.jsonl" "$SE/long/code/big/.aider.chat.history.md"
mkdir -p "$SE/urdir/.claude/projects/p" "$SE/urdir/.claude/projects/locked"; printf '{}\n' > "$SE/urdir/.claude/projects/p/a.jsonl"; printf '{}\n' > "$SE/urdir/.claude/projects/locked/b.jsonl"; chmod 000 "$SE/urdir/.claude/projects/locked"
for E in net rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  psrun "$SE/pos" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions 2>&1 | sed -n '/Keys in agent sessions/,/^$/p' > "$SE/pos-$E.block"
  has    "$E: keys at a line start, mid-line and after an escaped newline are all found" 'Claude Code +12 files: ' "$SE/pos-$E.block"
  has    "$E: and each format among them"          'Claude Code +12 files: (AWS|Google|Hugging Face|OpenAI)(, (AWS|Google|Hugging Face|OpenAI)){3}$' "$SE/pos-$E.block"
  psrun "$SE/tabdir" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/tabdir-$E.txt" 2>&1
  has    "$E: a session folder name with a tab keeps the key with its agent" 'Claude Code +1 file: AWS' "$SE/tabdir-$E.txt"
  psrun "$SE/nldir" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/nldir-$E.txt" 2>&1
  has    "$E: a session folder name with a newline keeps the key with its agent" 'Claude Code +1 file: AWS' "$SE/nldir-$E.txt"
  _t0=$SECONDS
  psrun "$SE/long" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/long-$E.txt" 2>&1
  _dt=$((SECONDS - _t0))
  if grep -aq 'No keys in 2 agent session files' "$SE/long-$E.txt" && [ "$_dt" -lt 120 ]; then ok "$E: a key-shaped run of 2 MB is not a key and does not slow the check" "${_dt}s"
  else bad "$E: a key-shaped run of 2 MB is not a key and does not slow the check" "${_dt}s: $(grep -a 'agent session' "$SE/long-$E.txt" | head -n 2 | tr -s ' \n' '  ')"; fi
  psrun "$SE/urdir" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/urdir-$E.txt"
  has    "$E: a session folder that cannot be read is named" 'Agent sessions were partly checked: (1 folder|some files or folders) could not be read' "$SE/urdir-$E.txt"
  hasnot "$E: and the sessions are not called clean" 'No keys in' "$SE/urdir-$E.txt"
done
SKIPPING=""
chmod 755 "$SE/urdir/.claude/projects/locked"
# A compressed session is not read: the check line counts only the files read, the summary row
# says partly checked, and a home whose only session is compressed is never told no keys.
for D in zst zst1 aq kiro aqk unr3 aidur; do mkdir -p "$SE/$D/AppData/Roaming" "$SE/$D/AppData/Local/Temp"; done
mkdir -p "$SE/zst/.codex/sessions/2026/10" "$SE/zst1/.codex/sessions/2026/10"
printf '{}\n' > "$SE/zst/.codex/sessions/2026/10/rollout-a.jsonl"; printf 'x' > "$SE/zst/.codex/sessions/2026/10/rollout-b.jsonl.zst"
printf 'x' > "$SE/zst1/.codex/sessions/2026/10/rollout-b.jsonl.zst"
# Amazon Q CLI keeps temporary AWS credentials for its own telemetry in its database, and so does
# Kiro CLI: an ASIA key id there is not a key an agent read. A long-term key or another provider's
# key in that database still counts. Real SQLite files, built by python3; keys from pieces.
low() { head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c "$1"; }
mkq() { # database [conversation text]
  mkdir -p "$(dirname "$1")"
  python3 -c '
import json, sqlite3, sys
db, kid, sec, tok, conv = sys.argv[1:6]
c = sqlite3.connect(db)
c.execute("CREATE TABLE state (key TEXT PRIMARY KEY, value BLOB)")
c.execute("CREATE TABLE conversations (key TEXT PRIMARY KEY, value TEXT)")
c.execute("INSERT INTO state VALUES (?, ?)", ("telemetry-cognito-credentials", json.dumps({"access_key_id": kid, "secret_key": sec, "session_token": tok, "expiration": "2026-10-25T10:00:00Z"})))
c.execute("INSERT INTO conversations VALUES (?, ?)", ("/home/me/app", json.dumps({"history": [{"user": "deploy it " + conv}]})))
c.commit(); c.close()' "$1" "AS""IA$(upper 16)" "$(low 40)" "$(low 300)" "${2:-}"
}
mkq "$SE/aq/AppData/Local/amazon-q/data.sqlite3"; mkq "$SE/kiro/AppData/Local/kiro-cli/data.sqlite3"
mkq "$SE/aqk/AppData/Local/amazon-q/data.sqlite3" "AK""IA$(upper 16) and g""hp_$(rnd 36)"
for E in net rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  psrun "$SE/zst" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/zst-$E.txt"
  has    "$E: the check line counts only the files read, not compressed ones" 'No keys in 1 agent session file\. ! 1 compressed session file was not checked' "$SE/zst-$E.txt"
  psrun "$SE/zst" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E GIRD_CHECK_COMPACT=1 -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/zst-sum-$E.txt"
  has    "$E: and a compressed session makes the summary row partly checked" 'Keys in plain text none in files; agent sessions partly checked' "$SE/zst-sum-$E.txt"
  psrun "$SE/zst1" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/zst1-$E.txt"
  hasnot "$E: a home with only compressed sessions is never told no keys" 'No keys in' "$SE/zst1-$E.txt"
  psrun "$SE/aq" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/aq-$E.txt" 2>&1
  has    "$E: Amazon Q's own telemetry key in its database is not counted" 'No keys in 1 agent session file\.' "$SE/aq-$E.txt"
  psrun "$SE/kiro" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/kiro-$E.txt" 2>&1
  has    "$E: nor Kiro CLI's" 'No keys in 1 agent session file\.' "$SE/kiro-$E.txt"
  psrun "$SE/aqk" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/aqk-$E.txt" 2>&1
  has    "$E: a long-term AWS key or another provider's in that database still counts" 'Amazon Q +1 file: (AWS, GitHub|GitHub, AWS)$' "$SE/aqk-$E.txt"
done
SKIPPING=""
# An unreadable session file is named as one, never as a time cut that ripgrep or -AllSessions
# would fix, and an unreadable Aider history is counted too instead of being skipped.
mkdir -p "$SE/unr3/.claude/projects/p" "$SE/aidur/code/aid"
for _f in a b c; do printf '{}\n' > "$SE/unr3/.claude/projects/p/$_f.jsonl"; done; chmod 000 "$SE/unr3/.claude/projects/p/b.jsonl"
printf '#### hello\n' > "$SE/aidur/code/aid/.aider.chat.history.md"; chmod 000 "$SE/aidur/code/aid/.aider.chat.history.md"
psrun "$SE/unr3" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/unr3.txt"
has    "net: an unreadable session file is named as one" 'Agent sessions were partly checked: 1 file could not be read\.' "$SE/unr3.txt"
hasnot "net: not as a time cut"                   'Checked the newest|Install ripgrep' "$SE/unr3.txt"
hasnot "net: and the sessions read are not called clean" 'No keys in' "$SE/unr3.txt"
psrun "$SE/aidur" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/aidur.txt"
has    "an unreadable Aider history is named as not read" 'Agent sessions were partly checked: 1 file could not be read\.' "$SE/aidur.txt"
chmod 644 "$SE/unr3/.claude/projects/p/b.jsonl" "$SE/aidur/code/aid/.aider.chat.history.md"
# A session location that is a link to a file is read and counted, as ripgrep reads it. A link to
# a pipe or a device, or a pipe in a session folder, is never read: the check still ends, with
# -AllSessions too, and counts the one regular file. Each run gets 60 s and is killed and failed after.
for D in lnk lnkc lnkp; do mkdir -p "$SE/$D/.claude/projects/p" "$SE/$D/.codex" "$SE/$D/AppData/Roaming" "$SE/$D/AppData/Local/Temp"; done; mkdir -p "$SE/lnkel"
printf '{}\n' | tee "$SE/lnk/.claude/projects/p/s.jsonl" "$SE/lnkc/.claude/projects/p/s.jsonl" "$SE/lnkp/.claude/projects/p/s.jsonl" "$SE/lnkel/clean.jsonl" > /dev/null
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/lnkel/key.jsonl"
ln -s "$SE/lnkel/key.jsonl" "$SE/lnk/.codex/history.jsonl"; ln -s "$SE/lnkel/clean.jsonl" "$SE/lnkc/.codex/history.jsonl"
mkfifo "$SE/lnkel/pipe" "$SE/lnkp/.claude/projects/p/f.jsonl"; ln -s "$SE/lnkel/pipe" "$SE/lnkp/.codex/history.jsonl"; ln -s /dev/null "$SE/lnkp/.claude/history.jsonl"
for E in net rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  if [ -z "$SKIPPING" ]; then
    psrun "$SE/lnk" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/lnk-$E.txt" 2>&1
    psrun "$SE/lnkc" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/lnkc-$E.txt" 2>&1
    psrun "$SE/lnkp" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/lnkp-$E.txt" 2>&1 &
    BP=$!; for _i in $(seq 1 600); do kill -0 "$BP" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$BP" 2>/dev/null; then
      pkill -9 -P "$BP" 2>/dev/null; kill -9 "$BP" 2>/dev/null; printf 'the check did not finish in 60 s\n' > "$SE/lnkp-$E.txt"
      pkill -f "with-filename.*$SE/lnkp/" 2>/dev/null
    fi
    wait "$BP" 2>/dev/null
  fi
  has    "$E: a session location that is a link to a file is read" 'Codex +1 file: AWS' "$SE/lnk-$E.txt"
  has    "$E: and counted as read"                  'No keys in 2 agent session files\.' "$SE/lnkc-$E.txt"
  has    "$E: a link to a pipe or a device, or a pipe in a session folder, is not read" 'No keys in 1 agent session file\.' "$SE/lnkp-$E.txt"
done
SKIPPING=""
# Antigravity keeps newer conversations as SQLite files (.db, and their -wal) beside the older .pb
# files: the SQLite files are read and nothing else in the folder is, only the .pb files are named
# as encrypted, and a folder with none is never called encrypted.
for D in ag ag2 new cx1 gx; do mkdir -p "$SE/$D/AppData/Roaming" "$SE/$D/AppData/Local/Temp"; done
_ag="$SE/ag/.gemini/antigravity/conversations"; mkdir -p "$_ag" "$SE/ag2/.gemini/antigravity-cli/conversations"
printf 'x' > "$_ag/a.pb"
mkdb() { # database text
  python3 -c '
import sqlite3, sys
c = sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, body BLOB)")
c.execute("INSERT INTO items (body) VALUES (?)", (sys.argv[2].encode(),)); c.commit(); c.close()' "$1" "$2"
}
mkdb "$_ag/b.db" "run with AK""IA$(upper 16)"
printf 'x %s y\n' "g""hp_$(rnd 36)" > "$_ag/b.db-wal"
printf 'x %s y\n' "sk""-ant-api03-$(rnd 95)" > "$_ag/notes.txt"
mkdb "$SE/ag2/.gemini/antigravity-cli/conversations/c.db" "hello"
for E in net rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  psrun "$SE/ag" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions 2>&1 | sed -n '/Keys in agent sessions/,/^$/p' > "$SE/ag-$E.block"
  tr -s ' \n' '  ' < "$SE/ag-$E.block" > "$SE/ag-$E.flat"
  has    "$E: Antigravity's SQLite conversations and their -wal files are read" 'Antigravity +2 files: (AWS, GitHub|GitHub, AWS)$' "$SE/ag-$E.block"
  hasnot "$E: nothing else in that folder is read"   'Anthropic' "$SE/ag-$E.block"
  has    "$E: its .pb files are counted and named as encrypted" '1 Antigravity conversation file is encrypted, so it was not checked' "$SE/ag-$E.flat"
  psrun "$SE/ag2" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline -AllSessions > "$SE/ag2-$E.txt" 2>&1
  has    "$E: a folder of SQLite conversations alone is read" 'No keys in 1 agent session file\.' "$SE/ag2-$E.txt"
  hasnot "$E: and never called encrypted"            'encrypted' "$SE/ag2-$E.txt"
done
SKIPPING=""
# A conversations folder that can't be listed is named as a folder not read, never skipped.
mkdir -p "$SE/ag3/.gemini/antigravity/conversations" "$SE/ag3/AppData/Roaming" "$SE/ag3/AppData/Local/Temp"; mkdb "$SE/ag3/.gemini/antigravity/conversations/d.db" "hello"; chmod 000 "$SE/ag3/.gemini/antigravity/conversations"
psrun "$SE/ag3" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/ag3.txt"
has    "net: an Antigravity conversations folder that can't be listed is named as not read" 'Agent sessions were partly checked: 1 folder could not be read' "$SE/ag3.txt"
chmod 755 "$SE/ag3/.gemini/antigravity/conversations"
# Session places found in the agents' source and docs: Codex's thread history database and its
# -wal, Claude Desktop's mode for Bedrock and other providers (Claude-3p), Copilot CLI's session
# store and command history, and the prompts typed into Aider, Amazon Q, Continue, Factory Droid
# and Goose. A key in each is found under its agent. Codex names its database's folder two ways;
# with neither set, the one file counts once.
mkdir -p "$SE/new/.codex" "$SE/new/AppData/Roaming/Claude/local-agent-mode-sessions" "$SE/new/AppData/Local/Claude-3p/local-agent-mode-sessions" \
  "$SE/new/.aws/amazonq" "$SE/new/.continue/dev_data/0.2.0" "$SE/new/.factory/state" "$SE/new/AppData/Roaming/Block/goose/data" \
  "$SE/cx1/.codex" "$SE/csq" "$SE/groot/state" "$SE/xs/goose"
mkdb "$SE/new/.codex/thread_history_1.sqlite" "{\"text\":\"use AK""IA$(upper 16)\"}"
printf 'x %s y\n' "AK""IA$(upper 16)" > "$SE/new/.codex/thread_history_1.sqlite-wal"
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/new/AppData/Roaming/Claude/local-agent-mode-sessions/local_b.json"
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/new/AppData/Local/Claude-3p/local-agent-mode-sessions/local_a.json"
printf 'export AWS_ACCESS_KEY_ID=%s\n' "AK""IA$(upper 16)" > "$SE/new/.aws/amazonq/.cli_bash_history"
printf '{"prompt":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/new/.continue/dev_data/0.2.0/chatInteraction.jsonl"
printf '[{"command": "use %s"}]\n' "AK""IA$(upper 16)" > "$SE/new/.factory/state/history.json"
printf '#V2\nuse %s\n' "AK""IA$(upper 16)" > "$SE/new/AppData/Roaming/Block/goose/data/history.txt"
mkdir -p "$SE/new/.copilot"; printf '{"commandHistory":["use %s"]}\n' "AK""IA$(upper 16)" > "$SE/new/.copilot/command-history-state.json"
mkdb "$SE/new/.copilot/session-store.db" "{\"text\":\"use AK""IA$(upper 16)\"}"; printf 'x %s y\n' "AK""IA$(upper 16)" > "$SE/new/.copilot/session-store.db-wal"
mkdir -p "$SE/new/code/a"; printf '\n# 2026-10-25 06:00:00.000000\n+use %s\n' "AK""IA$(upper 16)" > "$SE/new/code/a/.aider.input.history"
mkdb "$SE/cx1/.codex/thread_history_1.sqlite" "hello"
mkdb "$SE/csq/thread_history_1.sqlite" "{\"text\":\"use AK""IA$(upper 16)\"}"
printf '#V2\nuse %s\n' "AK""IA$(upper 16)" | tee "$SE/groot/state/history.txt" "$SE/xs/goose/history.txt" > /dev/null
psrun "$SE/new" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions 2>&1 | sed -n '/Keys in agent sessions/,/^$/p' > "$SE/new.block"
has    "a key in Codex's thread history database and its -wal is found" 'Codex +2 files: AWS$' "$SE/new.block"
has    "a key in Claude Desktop's sessions, there and in its Claude-3p mode, is found" 'Claude Desktop +2 files: AWS$' "$SE/new.block"
has    "a key typed into Amazon Q is found"        'Amazon Q +1 file: AWS$' "$SE/new.block"
has    "a key in Continue's chat log is found"     'Continue +1 file: AWS$' "$SE/new.block"
has    "a key typed into Factory Droid is found"   'Factory Droid +1 file: AWS$' "$SE/new.block"
has    "a key typed into Goose is found"           'Goose +1 file: AWS$' "$SE/new.block"
has    "a key typed into Aider is found"           'Aider +1 file: AWS$' "$SE/new.block"
has    "a key in Copilot CLI's session store and command history is found" 'GitHub Copilot CLI +3 files: AWS$' "$SE/new.block"
psrun "$SE/cx1" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/cx1.txt" 2>&1
has    "a place two lines name is counted once"   'No keys in 1 agent session file\.' "$SE/cx1.txt"
psrun "$SE/gx" CODEX_SQLITE_HOME="$SE/csq" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/csq.txt" 2>&1
has    "Codex's thread history under CODEX_SQLITE_HOME is found" 'Codex +1 file: AWS$' "$SE/csq.txt"
mkdir -p "$SE/cdir/data/sessions/s1" "$SE/cdir/data/tasks/t1" "$SE/csd/s2"
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/cdir/data/tasks/t1/api_conversation_history.json"
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/cdir/data/sessions/s1/m.json"; printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/csd/s2/m.json"
psrun "$SE/gx" CLINE_DIR="$SE/cdir" CLINE_SESSION_DATA_DIR="$SE/csd" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/cline.txt" 2>&1
has    "Cline's sessions and tasks under CLINE_DIR and CLINE_SESSION_DATA_DIR are found" 'Cline +3 files: AWS$' "$SE/cline.txt"
psrun "$SE/gx" GOOSE_PATH_ROOT="$SE/groot" XDG_STATE_HOME="$SE/xs" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions 2>&1 | sed -n '/Keys in agent sessions/,/^$/p' > "$SE/groot.block"
has    "Goose's prompts under GOOSE_PATH_ROOT are found" 'groot/state/history\.txt +[0-9]+ files?$' "$SE/groot.block"
has    "ahead of XDG_STATE_HOME"                    'Goose +1 file: AWS$' "$SE/groot.block"
# A tab in a cloned repo's folder name, where an Aider history sits, does not lose the key or its agent.
mkdir -p "$SE/aidtab/code/a${_tab}b" "$SE/aidtab/AppData/Roaming" "$SE/aidtab/AppData/Local/Temp"
printf '> export GROQ_API_KEY=%s\n' "gs""k_$(rnd 52)" > "$SE/aidtab/code/a${_tab}b/.aider.chat.history.md"
psrun "$SE/aidtab" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/aidtab.txt" 2>&1
has    "a tab in an Aider history's folder name keeps the key with Aider" 'Aider +1 file: Groq' "$SE/aidtab.txt"
# No temporary folder (the ripgrep engine writes its pattern to one; .NET reads TMPDIR on Linux
# and TEMP on Windows): the check can't start, and the report says so.
SKIPPING=$NORG
psrun "$SE/pos" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=rg TMPDIR=/nonexistent/blindspot TEMP=/nonexistent/blindspot -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/nostart.txt"
has    "when the check cannot start the sessions are named as not checked" '12 agent session files were not checked: the check could not start' "$SE/nostart.txt"
hasnot "and are not called clean"                 'No keys in' "$SE/nostart.txt"
SKIPPING=""
# The summary row counts session files, and the details name where they are, not the files: a
# Claude Code session's path spells out the project folder it belongs to, username included.
psrun "$SE/pos" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_COMPACT=1 -- -Offline -AllSessions 2>&1 | tr -s ' \n' '  ' > "$SE/pos-sum.txt"
has    "the summary row counts session files"    'Keys in plain text keys in 12 agent session files: Claude Code' "$SE/pos-sum.txt"
mkdir -p "$SE/priv/.claude/projects/-Users-alice-code-acme" "$SE/priv/AppData/Roaming" "$SE/priv/AppData/Local/Temp"
printf '{"a":"x %s y"}\n' "AK""IA$(upper 16)" > "$SE/priv/.claude/projects/-Users-alice-code-acme/s.jsonl"
psrun "$SE/priv" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions -Full > "$SE/priv.txt" 2>&1
has    "the report names where sessions are, not the project folders they are named after" '^ +~/\.claude/projects +[0-9]+ files?$' "$SE/priv.txt"
hasnot "and never the project path or username in a session folder name" 'alice|acme' "$SE/priv.txt"
# Key formats from the providers' own docs: OpenAI admin keys, AWS temporary key ids, Amazon
# Bedrock long-term keys (ABSK, then the base64 of BedrockAPIKey) and GitHub app tokens in the
# format of April 2026 (ghs_, the app id, then a JWT with dots and underscores). One per agent,
# so each shows on its own row, and all four in a project's .env file.
mkdir -p "$SE/fmt/.claude/projects/p" "$SE/fmt/.codex/sessions/x" "$SE/fmt/.gemini/tmp/x/chats" "$SE/fmt/.continue/sessions" "$SE/fmt/code/new" "$SE/fmt/AppData/Roaming" "$SE/fmt/AppData/Local/Temp"
_adm="sk""-admin-$(rnd 130)"; _asia="AS""IA$(upper 16)"; _absk="AB""SKQmVkcm9ja0FQSUtleS$(rnd 100)"; _ghs="gh""s_123456_$(rnd 40).$(rnd 60).$(rnd 43)"
printf '{"a":"x %s y"}\n' "$_adm" > "$SE/fmt/.claude/projects/p/a.jsonl"
printf '{"a":"x %s y"}\n' "$_asia" > "$SE/fmt/.codex/sessions/x/r.jsonl"
printf '{"a":"x %s y"}\n' "$_absk" > "$SE/fmt/.gemini/tmp/x/chats/s.jsonl"
printf '{"a":"x %s y"}\n' "$_ghs" > "$SE/fmt/.continue/sessions/s.json"
printf 'AWS_ACCESS_KEY_ID=%s\nAWS_BEARER_TOKEN_BEDROCK=%s\nGITHUB_TOKEN=%s\nOPENAI_ADMIN_KEY=%s\n' "$_asia" "$_absk" "$_ghs" "$_adm" > "$SE/fmt/code/new/.env"
printf '%s\n' "$_adm" "$_asia" "$_absk" "$_ghs" > "$SE/fmt-keys.txt"
psrun "$SE/fmt" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/fmt.txt" 2>&1
has    "an OpenAI admin key is found"                 'Claude Code +1 file: OpenAI' "$SE/fmt.txt"
has    "an AWS temporary key id is found"             'Codex +1 file: AWS' "$SE/fmt.txt"
has    "a Bedrock API key is found"                   'Gemini CLI +1 file: AWS' "$SE/fmt.txt"
has    "a GitHub app token in the new format is found" 'Continue +1 file: GitHub' "$SE/fmt.txt"
has    "and all four in a project .env file"          '~/code/new/\.env +AWS, GitHub, OpenAI' "$SE/fmt.txt"
nokeys "and none of them is printed" "$SE/fmt-keys.txt" "$SE/fmt.txt"
# OpenAI project keys from before their length grew: sk-proj-, 20 letters and digits, T3BlbkFJ
# (OpenAI in base64), 20 more; and today's 156 characters. Near misses, not keys: the old length
# without the marker, and one character short of it. Built from pieces.
mkdir -p "$SE/oai/.claude/projects/p" "$SE/oai/.codex/sessions/x" "$SE/oai/code/old" "$SE/oai/code/near" "$SE/oai/AppData/Roaming" "$SE/oai/AppData/Local/Temp"
_m="T3Blb""kFJ"; _p48="sk""-proj-$(rnd 20)$_m$(rnd 20)"; _p156="sk""-proj-$(rnd 74)$_m$(rnd 74)"
printf '{"a":"x %s y"}\n' "$_p48" > "$SE/oai/.claude/projects/p/a.jsonl"
printf '{"a":"x %s y"}\n' "$_p156" > "$SE/oai/.codex/sessions/x/r.jsonl"
printf 'OPENAI_API_KEY=%s\n' "$_p48" > "$SE/oai/code/old/.env"
printf 'OPENAI_API_KEY=%s\nOPENAI_KEY_2=%s\n' "sk""-proj-$(rnd 48)" "sk""-proj-$(rnd 19)$_m$(rnd 20)" > "$SE/oai/code/near/.env"
printf '%s\n' "$_p48" "$_p156" > "$SE/oai-keys.txt"
psrun "$SE/oai" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/oai.txt" 2>&1
has    "an OpenAI project key of 48 characters is found" 'Claude Code +1 file: OpenAI' "$SE/oai.txt"
has    "and one of 156"                                'Codex +1 file: OpenAI' "$SE/oai.txt"
has    "and the short one in a project .env file"       '~/code/old/\.env +OpenAI' "$SE/oai.txt"
hasnot "the old length without the marker, or one short of it, is not a key" 'code/near' "$SE/oai.txt"
nokeys "and no OpenAI key is printed" "$SE/oai-keys.txt" "$SE/oai.txt"
# A held engine is still running when the rest of the check is done: it is stopped.
: > "$SE/hold"
psrun "$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_HOLD="$SE/hold" -- -Offline > "$SE/held.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "a held engine does not hold up the check"; else bad "a held engine does not hold up the check" "exit $RC"; fi
has    "and the report says the sessions were not all checked" 'Checked the newest 0 of 2' "$SE/held.txt"
SKIPPING=$NORG
{
  # A pipe where a session file should be is not given to ripgrep, which would wait on it forever:
  # with -AllSessions the check would never end, so it gets 60 s and is killed and failed after.
  mkdir -p "$SE/fifo/.codex" "$SE/fifo/.claude/projects/p" "$SE/fifo/AppData/Roaming" "$SE/fifo/AppData/Local/Temp"
  mkfifo "$SE/fifo/.codex/history.jsonl"; printf '{}\n' > "$SE/fifo/.claude/projects/p/a.jsonl"
  psrun "$SE/fifo" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=rg -- -Offline -AllSessions > "$SE/fifo.txt" 2>&1 &
  BP=$!; for _i in $(seq 1 600); do kill -0 "$BP" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$BP" 2>/dev/null; then pkill -9 -P "$BP" 2>/dev/null; kill -9 "$BP" 2>/dev/null; pkill -f "with-filename.*$SE/fifo/" 2>/dev/null; bad "rg: a pipe where a session file should be is skipped" "the check did not finish in 60 s"
  else has "rg: a pipe where a session file should be is skipped" 'No keys in 1 agent session file' "$SE/fifo.txt"; fi
  wait "$BP" 2>/dev/null
  # A session ripgrep never finishes is stopped when the rest is done. A pipe nobody writes to,
  # given to rg.exe as one more root (GIRD_CHECK_SESSIONS_HOLD, tests only), keeps it reading.
  mkdir -p "$SE/stuck/.codex" "$SE/stuck/AppData/Roaming" "$SE/stuck/AppData/Local/Temp"; printf '{}\n' > "$SE/stuck/.codex/history.jsonl"; mkfifo "$SE/stuck/pipe"
  psrun "$SE/stuck" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=rg GIRD_CHECK_SESSIONS_HOLD="$SE/stuck/pipe" -- -Offline > "$SE/stuck.txt" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "rg: a stuck ripgrep does not hold up the check"; else bad "rg: a stuck ripgrep does not hold up the check" "exit $RC"; fi
  if pgrep -f "with-filename.*$SE/stuck/" >/dev/null 2>&1; then bad "rg: no ripgrep process is left running"; pkill -f "with-filename.*$SE/stuck/"; else ok "rg: no ripgrep process is left running"; fi
  # Closing the terminal sends HUP to the process group, ripgrep included. Many folders keep the
  # scan going long enough to send it while ripgrep is stuck. (gird-check.ps1 has no HUP handler:
  # a HUP to the pwsh process alone leaves ripgrep running.)
  python3 -c "
import os, sys
for d in range(300):
    p = os.path.join(sys.argv[1], 'code', 'p%d' % d); os.makedirs(p)
    for f in range(200): open(os.path.join(p, 'f%d' % f), 'w').close()" "$SE/stuck"
  # Its own session, so the HUP goes to its group and not this script's.
  "$(command -v python3)" -c 'import os, sys; os.setsid(); os.execv(sys.argv[1], sys.argv[1:])' /usr/bin/env -i PATH="$WORK/bin:$SE/rgbin" \
    HOME="$WORK/pshome" USERPROFILE="$SE/stuck" APPDATA="$SE/stuck/AppData/Roaming" LOCALAPPDATA="$SE/stuck/AppData/Local" \
    TEMP="$SE/stuck/AppData/Local/Temp" LANG=en_US.UTF-8 GIRD_CHECK_SESSIONS_ENGINE=rg GIRD_CHECK_SESSIONS_HOLD="$SE/stuck/pipe" "$PWSH" -NoProfile -NonInteractive -File "$SCRIPT" -Offline > /dev/null 2>&1 &
  BP=$!
  for _i in $(seq 1 100); do [ -n "$SKIPPING" ] && break; pgrep -f "with-filename.*$SE/stuck/" >/dev/null 2>&1 && break; sleep 0.1; done   # safety ceiling while it starts
  if pgrep -f "with-filename.*$SE/stuck/" >/dev/null 2>&1; then RGUP=1; else RGUP=0; fi
  kill -HUP -- "-$BP" 2>/dev/null; wait "$BP" 2>/dev/null
  for _i in $(seq 1 10); do pgrep -f "with-filename.*$SE/stuck/" >/dev/null 2>&1 || break; sleep 0.1; done
  if [ "$RGUP" -eq 0 ]; then bad "rg: HUP leaves no ripgrep process" "ripgrep never started"
  elif pgrep -f "with-filename.*$SE/stuck/" >/dev/null 2>&1; then bad "rg: HUP leaves no ripgrep process"; pkill -f "with-filename.*$SE/stuck/"; else ok "rg: HUP leaves no ripgrep process"; fi
}
SKIPPING=""
mkdir -p "$SE/min/.claude/projects/p" "$SE/min/AppData/Roaming" "$SE/min/AppData/Local/Temp"; printf '{}\n' > "$SE/min/.claude/projects/p/a.jsonl"
psrun "$SE/min" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_HOLD="$SE/hold" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/held-sum.txt"
has    "the summary row is not a check mark after a partial check" 'Keys in plain text none in files; agent sessions partly checked' "$SE/held-sum.txt"

echo "the same findings as gird-check.sh"
# Each list is cut out of its script, then the same filter keeps only entry lines on both sides.
entries() { grep -E '^[@a-z0-9][^ ]* (\*|[0-9][^ ]*) [a-z]+$'; }
sed -n '/^BAD_NPM="/,/"$/p' "$BASH_SCRIPT" | sed -e 's/^BAD_NPM="//' -e 's/"$//' > "$WORK/bad-sh-raw.txt"
sed -n "/^\$BadNpm = @'/,/^'@/p" "$SCRIPT" | sed -e '1d' -e '$d' > "$WORK/bad-ps-raw.txt"
entries < "$WORK/bad-sh-raw.txt" > "$WORK/bad-sh.txt"; entries < "$WORK/bad-ps-raw.txt" > "$WORK/bad-ps.txt"
if [ -s "$WORK/bad-sh.txt" ] && diff -q "$WORK/bad-sh.txt" "$WORK/bad-ps.txt" >/dev/null; then ok "the same bad npm package list" "$(wc -l < "$WORK/bad-ps.txt" | tr -d ' ') entries"
else bad "the same bad npm package list"; diff "$WORK/bad-sh.txt" "$WORK/bad-ps.txt" | head -n 6; fi
if diff -q "$WORK/bad-sh-raw.txt" "$WORK/bad-sh.txt" >/dev/null && diff -q "$WORK/bad-ps-raw.txt" "$WORK/bad-ps.txt" >/dev/null; then ok "every line of both lists is an entry"
else bad "every line of both lists is an entry"; diff "$WORK/bad-sh-raw.txt" "$WORK/bad-sh.txt" | head -n 3; diff "$WORK/bad-ps-raw.txt" "$WORK/bad-ps.txt" | head -n 3; fi
# gird-check.sh, on the same home with its Mac paths, must find the same files.
bash tests/make-fixture.sh "$WORK/bhome" "$WORK/keys-b.txt" >/dev/null
HOME="$WORK/bhome" PATH=/usr/bin:/bin bash "$BASH_SCRIPT" --offline > "$WORK/bash.txt" 2>&1
for sec in 'MCP SERVERS' 'KEYS IN CLAUDE CODE ALLOW LISTS'; do
  b=$(grep -aoE "$sec +[0-9]+ [a-z]+" "$WORK/bash.txt"); p=$(grep -aoE "$sec +[0-9]+ [a-z]+" "$OUT")
  if [ -n "$b" ] && [ "$b" = "$p" ]; then ok "$sec agrees" "$p"; else bad "$sec agrees" "bash '$b', pwsh '$p'"; fi
done
b=$(grep -aoE 'KEYS IN PLAIN TEXT +[0-9]+' "$WORK/bash.txt" | grep -oE '[0-9]+$'); p=$(grep -aoE 'KEYS IN PLAIN TEXT +[0-9]+' "$OUT" | grep -oE '[0-9]+$')
if [ -n "$b" ] && [ "$p" = $((b + 1)) ]; then ok "key files agree, plus PowerShell's history" "$p"; else bad "key files agree, plus PowerShell's history" "bash $b, pwsh $p"; fi
# Only where keys go differs: the macOS Keychain there, a secrets manager here.
# gird-check.sh finds Claude Desktop in this machine's own /Applications, which a test home can't
# plant, so whether it is listed differs by machine: it is left out of both lists.
# Each fix with its wrapped lines joined, so a name left out does not move where the others wrap.
fixes() {
  sed -n '/WHAT TO DO/,$p' "$1" | awk '
    /^ +[0-9]+\. / { if (cur != "") print cur; sub(/^ *[0-9]+\. */, ""); cur = $0; next }
    cur != "" && /^ +[^ ]/ { sub(/^ +/, ""); cur = cur " " $0; next }
    { if (cur != "") print cur; cur = "" }
    END { if (cur != "") print cur }' | sed -e 's/ into .*//' -e 's/Claude Desktop, //'
}
fixes "$WORK/bash.txt" > "$WORK/bash-fixes.txt"; fixes "$OUT" > "$WORK/ps-fixes.txt"
if [ -s "$WORK/ps-fixes.txt" ] && diff -q "$WORK/bash-fixes.txt" "$WORK/ps-fixes.txt" >/dev/null; then ok "the same fixes in the same order"; else bad "the same fixes in the same order"; diff "$WORK/bash-fixes.txt" "$WORK/ps-fixes.txt" | head -n 6; fi

echo "review fixes: npm, project settings and the wiper"
RV=$WORK/rv; cp -R "$WORK/clean" "$RV"
# Lockfiles: a pnpm override pinning away, an npm lock without URLs, a shrinkwrap, pnpm 5.
mkdir -p "$RV/code/pin" "$RV/code/nourl" "$RV/code/shrink" "$RV/code/pnpm5"
printf "lockfileVersion: '9.0'\n\noverrides:\n  axios@1.14.1: 1.14.2\n\npackages:\n\n  axios@1.14.2:\n    resolution: {integrity: sha512-x}\n" > "$RV/code/pin/pnpm-lock.yaml"
printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "node_modules/keyv": {\n      "version": "6.0.0"\n    }\n  }\n}\n' > "$RV/code/nourl/package-lock.json"
printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "node_modules/@keyv/redis": {\n      "version": "6.0.0"\n    }\n  }\n}\n' > "$RV/code/shrink/npm-shrinkwrap.json"
printf "lockfileVersion: 5.4\n\npackages:\n\n  /cacheable/2.5.1:\n    resolution: {integrity: sha512-x}\n" > "$RV/code/pnpm5/pnpm-lock.yaml"
mkdir -p "$RV/code/esc"; printf '{\n  "packages": {\n    "node_modules/cloude": {\n      "version": "2.0\033[2K"\n    }\n  }\n}\n' > "$RV/code/esc/package-lock.json"
# A nested or bundled dependency in an npm lock (node_modules/<tool>/node_modules/<name>) has no resolved URL.
mkdir -p "$RV/code/nested"; printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "node_modules/some-tool": {\n      "version": "2.0.0"\n    },\n    "node_modules/some-tool/node_modules/axios": {\n      "version": "1.14.1",\n      "inBundle": true\n    },\n    "node_modules/@scope/tool/node_modules/@keyv/redis": {\n      "version": "6.0.0",\n      "inBundle": true\n    }\n  }\n}\n' > "$RV/code/nested/package-lock.json"
# Global installs: a bad dependency inside a global tool, a version manager's folder, a version with control codes.
mkdir -p "$RV/.npm-global/lib/node_modules/sometool/node_modules/axios" "$RV/.volta/tools/image/node/20.1.0/lib/node_modules/opencraw"
printf '{"name":"axios","version":"1.14.1"}\n' > "$RV/.npm-global/lib/node_modules/sometool/node_modules/axios/package.json"
printf '{"name":"opencraw","version":"1.0.3\033[2K"}\n' > "$RV/.volta/tools/image/node/20.1.0/lib/node_modules/opencraw/package.json"
# Project settings: pretty-printed, local, other command keys, a symlink, a deny rule naming a worm file,
# a plugin marketplace clone, a commented-out task, and a | in a folder name.
mkdir -p "$RV/p/pretty/.claude" "$RV/p/local/.claude" "$RV/p/aws/.claude" "$RV/p/link/.claude" "$RV/p/deny/.claude" \
  "$RV/.claude/plugins/marketplaces/m/.claude" "$RV/p/comment/.vscode" "$RV/p/a|b/.claude" "$RV/p/real/.claude"
printf '{\n  "enabledMcpjsonServers": [\n    "db"\n  ]\n}\n' > "$RV/p/pretty/.claude/settings.json"
printf '{"enableAllProjectMcpServers": true}\n' > "$RV/p/local/.claude/settings.local.json"
printf '{"awsAuthRefresh": "aws sso login"}\n' > "$RV/p/aws/.claude/settings.json"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say linked"}]}]}}\n' > "$RV/p/real/.claude/real.json"
ln -s ../../real/.claude/real.json "$RV/p/link/.claude/settings.json"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"make"}]}]},"permissions":{"deny":["Read(./.claude/router_runtime.js)"]}}\n' > "$RV/p/deny/.claude/settings.json"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]}}\n' > "$RV/.claude/plugins/marketplaces/m/.claude/settings.json"
printf '{\n  "tasks": [{\n    "label": "x",\n    // "runOptions": {"runOn": "folderOpen"}\n    "command": "make"\n  }]\n}\n' > "$RV/p/comment/.vscode/tasks.json"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"y"}]}]}}\n' > "$RV/p/a|b/.claude/settings.json"
mkdir -p "$RV/p/guard/.claude" "$RV/p/glob/.claude" "$RV/code/x|y" "$RV/p/r1/.claude" "$RV/p/r2/.claude" "$RV/code/bunpin"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"test ! -e .claude/router_runtime.js || exit 2"}]}]}}\n' > "$RV/p/guard/.claude/settings.json"
printf '{"permissions":{"allow":["Bash(ls /tmp/*)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"npx prettier --write src/**/*.ts"}]}]}}\n' > "$RV/p/glob/.claude/settings.json"
printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$RV/code/x|y/package-lock.json"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"make fmt"}]}]}}\n' | tee "$RV/p/r1/.claude/settings.json" > "$RV/p/r2/.claude/settings.json"
printf '{\n  "overrides": {\n    "axios@1.14.1": "1.14.2"\n  },\n  "packages": {\n    "axios": ["axios@1.14.2", ""]\n  }\n}\n' > "$RV/code/bunpin/bun.lock"
# Comments: a // inside a string (a label, a URL) is text; only a comment outside strings is dropped, in every settings file.
mkdir -p "$RV/p/hide/.vscode" "$RV/p/url/.vscode" "$RV/p/unhide/.vscode" "$RV/p/chook/.claude"
printf '{"tasks":[{"label":"x //","runOptions":{"runOn":"folderOpen"},"command":"make"}]}\n' > "$RV/p/hide/.vscode/tasks.json"
printf '{"tasks":[{"label":"docs","detail":"docs: //example.com/docs","runOptions":{"runOn":"folderOpen"},"command":"make"}]}\n' > "$RV/p/url/.vscode/tasks.json"
printf '{"tasks":[{"label":"x //", /*\n  "runOptions":{"runOn":"folderOpen"},\n  */ "command":"make"}]}\n' > "$RV/p/unhide/.vscode/tasks.json"
printf '{\n  // "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "x"}]}]},\n  "permissions": {"allow": ["Bash(ls)"]}\n}\n' > "$RV/p/chook/.claude/settings.json"
psrun "$RV" -- -Offline > "$WORK/rv.txt" 2>&1
tr -s ' \n' '  ' < "$WORK/rv.txt" > "$WORK/rv-flat.txt"
hasnot "a pnpm override pinning away is not a hit"     'code/pin/' "$WORK/rv.txt"
has    "an npm lock entry without a URL is read"       'keyv 6\.0\.0 \(keyv worm' "$WORK/rv.txt"
has    "a nested lock entry without a URL is read"     '~/code/nested/package-lock\.json axios 1\.14\.1 \(Axios takeover' "$WORK/rv-flat.txt"
has    "and a scoped one inside a scoped tool"         '~/code/nested/package-lock\.json @keyv/redis 6\.0\.0 \(keyv account takeover' "$WORK/rv-flat.txt"
has    "npm-shrinkwrap.json is read"                   'code/shrink/npm-shrinkwrap\.json' "$WORK/rv.txt"
has    "a pnpm 5 lockfile is read"                     'cacheable 2\.5\.1' "$WORK/rv.txt"
has    "a bad dependency inside a global tool is found" 'sometool/node_modules/axios' "$WORK/rv.txt"
has    "a version manager's global folder is read"     '\.volta/tools/image/node/20\.1\.0/lib/node_modules/opencraw' "$WORK/rv.txt"
has    "a version with control codes prints as ?"      'opencraw \? \(SANDWORM_MODE' "$WORK/rv.txt"
has    "a lockfile version with control codes prints as ?" 'cloude \? \(SANDWORM_MODE' "$WORK/rv.txt"
if LC_ALL=C grep -aq "$(printf '\033')" "$WORK/rv.txt"; then bad "no control code from a package reaches the output"; else ok "no control code from a package reaches the output"; fi
has    "pretty-printed enabledMcpjsonServers is flagged" 'p/pretty/\.claude/settings\.json' "$WORK/rv.txt"
has    "a project settings.local.json is flagged"      'p/local/\.claude/settings\.local\.json' "$WORK/rv.txt"
has    "awsAuthRefresh counts as running a command"    'p/aws/\.claude/settings\.json' "$WORK/rv.txt"
has    "a symlinked settings file is checked"          'p/link/\.claude/settings\.json' "$WORK/rv.txt"
hasnot "a deny rule naming a worm file is not malware" 'runs a file' "$WORK/rv.txt"
hasnot "plugin marketplace clones are not projects"    'plugins/marketplaces' "$WORK/rv.txt"
hasnot "a commented-out folderOpen task is not flagged" 'p/comment/' "$WORK/rv.txt"
has    "a // inside a task label does not hide a folderOpen task" 'p/hide/\.vscode/tasks\.json' "$WORK/rv.txt"
has    "a // in a URL inside a task does not hide one either" 'p/url/\.vscode/tasks\.json' "$WORK/rv.txt"
hasnot "a // inside a string does not unhide a commented-out one" 'p/unhide/' "$WORK/rv.txt"
hasnot "a commented-out hooks block in a settings file is not flagged" 'p/chook/' "$WORK/rv.txt"
has    "a | in a folder name keeps its row intact"     'p/a\|b/\.claude/settings\.json' "$WORK/rv.txt"
sed -n '/05  RECENT KEY LEAKS/,/WHAT TO DO/p' "$WORK/rv.txt" > "$WORK/rv-05.txt"
hasnot "a guard hook naming a worm file is not malware" 'p/guard/' "$WORK/rv-05.txt"
has    "a /* inside a settings string does not hide its hooks" 'p/glob/\.claude/settings\.json' "$WORK/rv.txt"
has    "a | in a lockfile's folder keeps its row intact" '~/code/x\|y/package-lock\.json$' "$WORK/rv.txt"
has    "and its package"                               'axios 1\.14\.1 \(Axios takeover' "$WORK/rv.txt"
has    "two unrelated repos with the same settings are both listed (1)" 'p/r1/\.claude/settings\.json' "$WORK/rv.txt"
has    "two unrelated repos with the same settings are both listed (2)" 'p/r2/\.claude/settings\.json' "$WORK/rv.txt"
hasnot "a bun override pinning away is not a hit"      'code/bunpin/' "$WORK/rv.txt"
# A worktree's copy listed before the repo's own file still leaves the row named for the repo's file:
# the scan reads .claude, and the worktree's tasks.json under it, before the repo's own .vscode.
mkdir -p "$WORK/wto/r/.claude/worktrees/w1/.claude" "$WORK/wto/r/.claude/worktrees/w1/.vscode" "$WORK/wto/r/.vscode" "$WORK/wto/AppData/Roaming" "$WORK/wto/AppData/Local/Temp"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"make lint"}]}]}}\n' | tee "$WORK/wto/r/.claude/settings.json" > "$WORK/wto/r/.claude/worktrees/w1/.claude/settings.json"
printf '{"tasks":[{"label":"setup","command":"make","runOptions":{"runOn":"folderOpen"}}]}\n' | tee "$WORK/wto/r/.vscode/tasks.json" > "$WORK/wto/r/.claude/worktrees/w1/.vscode/tasks.json"
psrun "$WORK/wto" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/wto.txt"
hasnot "a worktree listed before its repo is not the row's name" 'worktrees/w1' "$WORK/wto.txt"
has    "the repo's own settings file is named instead"  '~/r/\.claude/settings\.json Set to run commands while the agent works\. The same settings are in 1 more folder' "$WORK/wto.txt"
has    "and so is the repo's own tasks file"            '~/r/\.vscode/tasks\.json Set to run a task when the folder opens in VS Code or Cursor\. The same settings are in 1 more folder' "$WORK/wto.txt"
mkdir -p "$WORK/escq/p/.claude" "$WORK/escq/AppData/Roaming" "$WORK/escq/AppData/Local/Temp" "$WORK/vsp/p/.vscode" "$WORK/vsp/AppData/Roaming" "$WORK/vsp/AppData/Local/Temp"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node \\"$CLAUDE_PROJECT_DIR\\"/.claude/router_runtime.js"}]}]}}\n' > "$WORK/escq/p/.claude/settings.json"
# q and w hold the keyv worm's own math_init.js, so the setup.mjs their hooks run counts there.
mkdir -p "$WORK/escq/q/.claude" "$WORK/escq/w/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node.exe .claude/setup.mjs"}]}]}}\n' > "$WORK/escq/q/.claude/settings.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node .claude\\\\setup.mjs"}]}]}}\n' > "$WORK/escq/w/.claude/settings.json"
printf 'x\n' | tee "$WORK/escq/q/.claude/math_init.js" > "$WORK/escq/w/.claude/math_init.js"
psrun "$WORK/escq" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/escq.txt"
has    "a hook running a worm file through an escaped path is malware" '~/p/\.claude/settings\.json runs a file a worm plants' "$WORK/escq.txt"
has    "node.exe counts as running it"                 '~/q/\.claude/settings\.json runs a file a worm plants' "$WORK/escq.txt"
has    "a Windows backslash path counts"               '~/w/\.claude/settings\.json runs a file a worm plants' "$WORK/escq.txt"
mkdir -p "$WORK/vsp/p/.claude"; printf 'x\n' > "$WORK/vsp/p/.vscode/setup.mjs"; printf 'x\n' > "$WORK/vsp/p/.claude/math_init.js"
psrun "$WORK/vsp" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/vsp.txt"
has    "a planted .vscode/setup.mjs is found"          'p/\.vscode/setup\.mjs a file the TanStack and keyv worms plant' "$WORK/vsp.txt"
# A command counts only when it runs the file: a guard in node -e code, a script given the file to
# block, and a task whose first argument is another script are not malware; a task that runs node
# on the file is.
mkdir -p "$WORK/grd/p/g1/.claude" "$WORK/grd/p/g2/.claude" "$WORK/grd/p/t1/.vscode" "$WORK/grd/p/t2/.vscode" "$WORK/grd/AppData/Roaming" "$WORK/grd/AppData/Local/Temp"
printf '{\n  "hooks": {\n    "SessionStart": [{"hooks": [{"type": "command",\n      "command": "node -e \\"if (require(%s).existsSync(%s)) { console.error(%s); process.exit(2) }\\""}]}]\n  }\n}\n' "'fs'" "'.claude/router_runtime.js'" "'TanStack worm file found'" > "$WORK/grd/p/g1/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node scripts/guard.js --block .claude/router_runtime.js"}]}]}}\n' > "$WORK/grd/p/g2/.claude/settings.json"
printf '{"version":"2.0.0","tasks":[{"label":"setup","command":"node","args":[".vscode/router_runtime.js"],"runOptions":{"runOn":"folderOpen"}}]}\n' > "$WORK/grd/p/t1/.vscode/tasks.json"
printf '{"version":"2.0.0","tasks":[{"label":"check","command":"node","args":["scripts/check.js",".vscode/router_runtime.js"],"runOptions":{"runOn":"folderOpen"}}]}\n' > "$WORK/grd/p/t2/.vscode/tasks.json"
psrun "$WORK/grd" -- -Offline > "$WORK/grd.txt" 2>&1
sed -n '/05  RECENT KEY LEAKS/,/WHAT TO DO/p' "$WORK/grd.txt" | tr -s ' \n' '  ' > "$WORK/grd-05.txt"
hasnot "a node -e guard naming a worm file is not malware" 'p/g1/' "$WORK/grd-05.txt"
hasnot "a script given a worm file to block is not malware" 'p/g2/' "$WORK/grd-05.txt"
has    "a task that runs node on a worm file is malware" '~/p/t1/\.vscode/tasks\.json runs a file a worm plants' "$WORK/grd-05.txt"
hasnot "a task whose first argument is another script is not malware" 'p/t2/' "$WORK/grd-05.txt"
# setup.mjs is a name projects use too: alone it is a file to read, in section 2, and the hook that
# runs it is not malware either.
mkdir -p "$WORK/stp/code/site/.vscode" "$WORK/stp/code/tool/.claude" "$WORK/stp/AppData/Roaming" "$WORK/stp/AppData/Local/Temp"
printf '// installs dev certs for the local server\nimport { execSync } from "node:child_process";\nexecSync("mkcert -install");\n' > "$WORK/stp/code/site/.vscode/setup.mjs"
printf 'console.log("project ready")\n' > "$WORK/stp/code/tool/.claude/setup.mjs"
printf '{\n  "hooks": {\n    "SessionStart": [{"hooks": [{"type": "command", "command": "node .claude/setup.mjs"}]}]\n  }\n}\n' > "$WORK/stp/code/tool/.claude/settings.json"
psrun "$WORK/stp" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/stp.txt"
hasnot "a setup.mjs alone is not called malware" 'ACT NOW|signs of npm malware|Treat this machine as compromised|runs a file' "$WORK/stp.txt"
has    "section 2 lists it as a file to read (1)" '! ~/code/site/\.vscode/setup\.mjs Named like a file the TanStack and keyv worms plant, with nothing else of theirs beside it\.' "$WORK/stp.txt"
has    "section 2 lists it as a file to read (2)" '! ~/code/tool/\.claude/setup\.mjs Named like a file the TanStack and keyv worms plant' "$WORK/stp.txt"
has    "with a fix to read it"                        'Read the files section 2 lists as named like files worms plant, and delete any you' "$WORK/stp.txt"
rm -rf "$WORK/stp/code/tool"
psrun "$WORK/stp" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/stp-c.txt"
has    "the summary row names a project file to read" 'MCP servers 0 servers, 1 project file to read' "$WORK/stp-c.txt"
# Project settings: bypassPermissions, which Claude Code before 2.1.257 took from a project, and two
# that are not settings: the same words inside a rule's string, an empty ANTHROPIC_BASE_URL, and a
# defaultMode outside permissions, the only place Claude Code reads it.
mkdir -p "$WORK/byp/p/byp/.claude" "$WORK/byp/p/str/.claude" "$WORK/byp/p/empty/.claude" "$WORK/byp/p/top/.claude" "$WORK/byp/AppData/Roaming" "$WORK/byp/AppData/Local/Temp"
printf '{\n  "permissions": {\n    "defaultMode": "bypassPermissions"\n  }\n}\n' > "$WORK/byp/p/byp/.claude/settings.json"
printf '{"permissions":{"allow":["Bash(echo \\"defaultMode\\": \\"bypassPermissions\\")"]}}\n' > "$WORK/byp/p/str/.claude/settings.local.json"
printf '{"env":{"ANTHROPIC_BASE_URL":""}}\n' > "$WORK/byp/p/empty/.claude/settings.json"
printf '{"defaultMode":"bypassPermissions","permissions":{}}\n' > "$WORK/byp/p/top/.claude/settings.json"
psrun "$WORK/byp" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/byp.txt"
has    "a project that turns on bypassPermissions is flagged" '~/p/byp/\.claude/settings\.json Set to skip permission prompts with bypassPermissions\. Claude Code applies it from a project only before version 2\.1\.257\.' "$WORK/byp.txt"
hasnot "the words inside a rule's string are not the setting" 'p/str/' "$WORK/byp.txt"
hasnot "an empty ANTHROPIC_BASE_URL is not flagged" 'p/empty/' "$WORK/byp.txt"
hasnot "a project's defaultMode outside permissions is not the setting" 'p/top/' "$WORK/byp.txt"
# One huge minified line, a // inside every label, the folderOpen task last: read whole, in linear time.
mkdir -p "$WORK/bigjs/p/.vscode" "$WORK/bigjs/AppData/Roaming" "$WORK/bigjs/AppData/Local/Temp"
python3 - "$WORK/bigjs/p/.vscode/tasks.json" <<'PY3'
import sys
tasks = ','.join('{"label":"t%d // x","command":"make"}' % i for i in range(20000))
open(sys.argv[1], 'w').write('{"tasks":[' + tasks + ',{"label":"last","runOptions":{"runOn":"folderOpen"},"command":"make"}]}')
PY3
T0=$(date +%s); psrun "$WORK/bigjs" -- -Offline > "$WORK/bigjs.txt" 2>&1; T=$(( $(date +%s) - T0 ))
has    "a huge one-line tasks.json is read whole"      'p/\.vscode/tasks\.json' "$WORK/bigjs.txt"
if [ "$T" -le 60 ]; then ok "and in reasonable time" "${T}s"; else bad "and in reasonable time" "took ${T}s"; fi
# A cloned project's .vscode/settings.json of 4.8 MB, 100,000 near misses of the CVE-2025-53773
# setting and the setting itself last: read whole, in linear time (it took a minute on macOS's awk).
mkdir -p "$WORK/aabig/p/.vscode" "$WORK/aabig/AppData/Roaming" "$WORK/aabig/AppData/Local/Temp"
python3 - "$WORK/aabig/p/.vscode/settings.json" <<'PY3'
import sys
with open(sys.argv[1], 'w') as f:
    f.write('{\n')
    for i in range(100000): f.write('  "a%d": 1, x"chat.tools.autoApprove": true,\n' % i)
    f.write('  "chat.tools.autoApprove": true\n}\n')
PY3
# gird-check.ps1 bounds each pattern in time and would list a file that hits the bound as skipped;
# the bound is raised here, so the test is about reading it whole.
T0=$(date +%s); psrun "$WORK/aabig" GIRD_CHECK_REGEX_TIMEOUT_MS=60000 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/aabig.txt"; T=$(( $(date +%s) - T0 ))
has    "a large settings file full of near misses is read whole" 'p/\.vscode/settings\.json Set to auto-approve Copilot' "$WORK/aabig.txt"
if [ "$T" -le 60 ]; then ok "and in linear time" "${T}s"; else bad "and in linear time" "took ${T}s"; fi
# A project file can hold one huge line: a string of 100,000 backslashes in settings.json, 100,000
# letters on one line of a yarn.lock. Each is read in time that grows with its size, and the
# hooks after the backslashes and the bad version after the letters are still found.
mkdir -p "$WORK/longln/p/.claude" "$WORK/longln/code/y" "$WORK/longln/AppData/Roaming" "$WORK/longln/AppData/Local/Temp"
python3 - "$WORK/longln/p/.claude/settings.json" "$WORK/longln/code/y/yarn.lock" <<'PY3'
import sys
open(sys.argv[1], 'w').write('{"permissions":{"allow":["Bash(echo ' + '\\\\' * 100000 + 'a)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"make"}]}]}}\n')
open(sys.argv[2], 'w').write('a' * 100000 + '\n"axios@^1.14.0":\n  version "1.14.1"\n  resolved "https://registry.yarnpkg.com/axios/-/axios-1.14.1.tgz#abc"\n')
PY3
T0=$(date +%s); psrun "$WORK/longln" -- -Offline > "$WORK/longln.txt" 2>&1; T=$(( $(date +%s) - T0 ))
has    "a settings file of 100,000 backslashes is read whole" 'p/\.claude/settings\.json' "$WORK/longln.txt"
has    "a lockfile line of 100,000 letters does not hide the next" 'axios 1\.14\.1 \(Axios takeover' "$WORK/longln.txt"
if [ "$T" -le 60 ]; then ok "and both in reasonable time" "${T}s"; else bad "and both in reasonable time" "took ${T}s"; fi
awk '/WHAT TO DO/{f=1} f' "$WORK/rv.txt" | tr -s ' \n' '  ' > "$WORK/rv-todo.txt"
if awk '{ a = index($0, "Delete the saved Claude Code commands"); b = index($0, "Read the settings marked"); exit !(a && b && a < b) }' "$WORK/rv-todo.txt"; then ok "a red allow-list fix comes before the yellow settings fix"; else bad "a red allow-list fix comes before the yellow settings fix"; fi
# The clean line, against gird-check.sh's count, and a folder of npm's cache that can't be read.
cp -R "$WORK/clean" "$WORK/npmok"; mkdir -p "$WORK/npmok/.npm/_cacache/index-v5/aa"
psrun "$WORK/npmok" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmok.txt"
has    "the clean line counts versions and packages apart" "npm malware none of $(awk '$2 != "*"' "$WORK/bad-sh.txt" | grep -c .) bad versions or $(awk '$2 == "*"' "$WORK/bad-sh.txt" | grep -c .) bad packages" "$WORK/npmok.txt"
# npm's cache that can't be read in full: a folder inside it, _cacache itself, or an index file. Nothing
# else is found in this home (no platform, no cook.pyc), so the cache alone decides row 05.
chmod 000 "$WORK/npmok/.npm/_cacache/index-v5/aa"
psrun "$WORK/npmok" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno.txt"
psrun "$WORK/npmok" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno-c.txt"
chmod 755 "$WORK/npmok/.npm/_cacache/index-v5/aa"
has    "an unreadable cache folder is not called clean" "npm malware not fully checked: part of npm's cache could not be read" "$WORK/npmno.txt"
has    "and the summary row is not green either"       'Recent leaks npm packages not fully checked: cache unreadable' "$WORK/npmno-c.txt"
chmod 000 "$WORK/npmok/.npm/_cacache"
psrun "$WORK/npmok" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno2.txt"
chmod 755 "$WORK/npmok/.npm/_cacache"
has    "an unreadable _cacache folder is not called clean" "npm malware not fully checked: part of npm's cache could not be read" "$WORK/npmno2.txt"
printf 'x\n' > "$WORK/npmok/.npm/_cacache/index-v5/aa/0e9"; chmod 000 "$WORK/npmok/.npm/_cacache/index-v5/aa/0e9"
psrun "$WORK/npmok" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno3.txt"
chmod 644 "$WORK/npmok/.npm/_cacache/index-v5/aa/0e9"
has    "an unreadable index file is not called clean"  "npm malware not fully checked: part of npm's cache could not be read" "$WORK/npmno3.txt"
# Windows: no launchctl or systemctl, a PowerShell way to stop the wiper.
psrun "$WORK/home" OS=Windows_NT -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/wwin.txt"
has    "Windows is told how to stop the wiper"         'Stop it with Get-CimInstance Win32_Process .* Invoke-CimMethod -MethodName Terminate, then delete the files above' "$WORK/wwin.txt"
hasnot "Windows is not given launchctl or systemctl"   'launchctl|systemctl' "$WORK/wwin.txt"
[ "$(uname -s)" = Linux ] || SKIPPING="needs pwsh on Linux, as in CI"
psrun "$WORK/home" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/wl.txt"
has    "Linux is told how to stop the wiper"         'systemctl --user disable --now gh-token-monitor\.service' "$WORK/wl.txt"
hasnot "Linux is not given the Mac command"          'launchctl bootout' "$WORK/wl.txt"
SKIPPING=""
# Where a hit was found, and npm's placeholder for a removed package.
has    "a lockfile hit says it is listed there"      'axios 1\.14\.1 \(Axios takeover, March 2026\), listed in this lockfile' "$WORK/out-flat.txt"
has    "an install hit says it is installed"         'claud-code 1\.0\.3 \(SANDWORM_MODE worm, February 2026\), installed' "$WORK/out-flat.txt"
has    "a cache hit says it was downloaded"          "@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI, April 2026\), downloaded into npm's cache" "$WORK/out-flat.txt"
# A lockfile records what some machine resolved, not what ran here: a bad version in a lockfile alone
# makes the headline and the fix depend on whether the project was installed. node_modules next to it
# holding that version is an install; another version there is not. The score and the link's nm stay.
for lk in lko lki lkd; do
  rm -rf "${WORK:?}/$lk"; cp -R "$WORK/clean" "$WORK/$lk"; mkdir -p "$WORK/$lk/code/cloned"
  printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$WORK/$lk/code/cloned/package-lock.json"
done
mkdir -p "$WORK/lki/code/cloned/node_modules/axios" "$WORK/lkd/code/cloned/node_modules/axios"
printf '{"name":"axios","version":"1.14.1"}\n' > "$WORK/lki/code/cloned/node_modules/axios/package.json"
printf '{"name":"axios","version":"1.14.2"}\n' > "$WORK/lkd/code/cloned/node_modules/axios/package.json"
for lk in lko lki lkd; do psrun "$WORK/$lk" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/$lk.txt"; done
psrun "$WORK/lko" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/lko-c.txt"
has    "a lockfile alone: the headline depends on an install" 'ACT NOW IF YOU INSTALLED IT: A LOCKFILE LISTS NPM MALWARE' "$WORK/lko.txt"
has    "and so does the fix" "If you ran an install in the project section 5 lists, treat this machine as compromised: clear npm's cache with npm cache clean --force and rotate every key this machine could reach\. If not, update its lockfile to a version without the malware\." "$WORK/lko.txt"
has    "and the summary row" 'Recent leaks npm malware in a lockfile: act if installed' "$WORK/lko-c.txt"
_s1=$(grep -o '#v=2&s=[0-9]*&' "$WORK/lko.txt"); _s2=$(grep -o '#v=2&s=[0-9]*&' "$WORK/lki.txt")
if [ -n "$_s1" ] && [ "$_s1" = "$_s2" ] && grep -q '&nm=1&' "$WORK/lko.txt"; then ok "a lockfile alone keeps the score and the link's nm"; else bad "a lockfile alone keeps the score and the link's nm" "${_s1:-no link} / ${_s2:-no link}"; fi
has    "a bad version installed next to its lockfile is act-now" 'ACT NOW: SIGNS OF NPM MALWARE .*Treat this machine as compromised\. Delete the packages and files listed in section 5' "$WORK/lki.txt"
has    "another version in node_modules leaves it depending on an install" 'ACT NOW IF YOU INSTALLED IT: A LOCKFILE LISTS NPM MALWARE' "$WORK/lkd.txt"
# A lockfile the scan found but can't read leaves npm not fully checked, as an unreadable cache does.
rm -rf "$WORK/lkr"; cp -R "$WORK/clean" "$WORK/lkr"; mkdir -p "$WORK/lkr/code/cloned"
printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$WORK/lkr/code/cloned/package-lock.json"
chmod 000 "$WORK/lkr/code/cloned/package-lock.json"
psrun "$WORK/lkr" -- -Offline > "$WORK/lkr.txt" 2>&1
psrun "$WORK/lkr" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/lkr-c.txt"
chmod 644 "$WORK/lkr/code/cloned/package-lock.json"
tr -s ' \n' '  ' < "$WORK/lkr.txt" > "$WORK/lkr-flat.txt"
has    "an unreadable lockfile is not called clean"  'npm malware not fully checked: 1 lockfile could not be read ~/code/cloned/package-lock\.json' "$WORK/lkr-flat.txt"
has    "and the summary row names unreadable files"  'Recent leaks npm packages not fully checked: files unreadable' "$WORK/lkr-c.txt"
cp -R "$WORK/clean" "$WORK/ph2"; mkdir -p "$WORK/ph2/code/ph"
printf '{"lockfileVersion":3,"packages":{"node_modules/plain-crypto-js":{"version":"0.0.1-security","resolved":"https://registry.npmjs.org/plain-crypto-js/-/plain-crypto-js-0.0.1-security.tgz"}}}\n' > "$WORK/ph2/code/ph/package-lock.json"
psrun "$WORK/ph2" -- -Offline > "$WORK/ph2.txt" 2>&1
hasnot "npm's -security placeholder is not malware" 'plain-crypto-js' "$WORK/ph2.txt"
# The placeholder is exactly 0.0.1-security, or 0.0.1-security.0 for a few names: any other -security version is a version.
cp -R "$WORK/clean" "$WORK/ph3"; mkdir -p "$WORK/ph3/code/ph" "$WORK/ph3/.npm-global/lib/node_modules/plain-crypto-js" "$WORK/ph3/.npm-global/lib/node_modules/claud-code" "$WORK/ph3/.npm-global/lib/node_modules/rimarf" "$WORK/ph3/.npm/_cacache/index-v5/aa/bb"
printf '{"lockfileVersion":3,"packages":{"node_modules/plain-crypto-js":{"version":"0.0.1-security.0","resolved":"https://registry.npmjs.org/plain-crypto-js/-/plain-crypto-js-0.0.1-security.0.tgz"},"node_modules/claud-code":{"version":"0.0.1-security","resolved":"https://registry.npmjs.org/claud-code/-/claud-code-0.0.1-security.tgz"},"node_modules/cloude-code":{"version":"1.0.0-security","resolved":"https://registry.npmjs.org/cloude-code/-/cloude-code-1.0.0-security.tgz"}}}\n' > "$WORK/ph3/code/ph/package-lock.json"
printf '{"name":"plain-crypto-js","version":"0.0.1-security.0"}\n' > "$WORK/ph3/.npm-global/lib/node_modules/plain-crypto-js/package.json"
printf '{"name":"claud-code","version":"0.0.1-security"}\n' > "$WORK/ph3/.npm-global/lib/node_modules/claud-code/package.json"
printf '{"name":"rimarf","version":"1.0.0-security"}\n' > "$WORK/ph3/.npm-global/lib/node_modules/rimarf/package.json"
printf 'a\t{"key":"make-fetch-happen:request-cache:https://registry.npmjs.org/plain-crypto-js/-/plain-crypto-js-0.0.1-security.0.tgz"}\nb\t{"key":"make-fetch-happen:request-cache:https://registry.npmjs.org/claud-code/-/claud-code-0.0.1-security.tgz"}\nc\t{"key":"make-fetch-happen:request-cache:https://registry.npmjs.org/naniod/-/naniod-1.0.0-security.tgz"}\n' > "$WORK/ph3/.npm/_cacache/index-v5/aa/bb/0e9"
psrun "$WORK/ph3" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ph3.txt"
hasnot "the real 0.0.1-security.0 placeholder of plain-crypto-js is not malware" 'plain-crypto-js' "$WORK/ph3.txt"
hasnot "0.0.1-security of another any-version name is not malware" 'claud-code' "$WORK/ph3.txt"
has    "1.0.0-security of an any-version name is malware in a lockfile" 'code/ph/package-lock\.json cloude-code 1\.0\.0-security \(SANDWORM_MODE' "$WORK/ph3.txt"
has    "and in a global install"                     'node_modules/rimarf rimarf 1\.0\.0-security \(SANDWORM_MODE' "$WORK/ph3.txt"
has    "and in npm's cache"                          "naniod 1\.0\.0-security \(SANDWORM_MODE worm, February 2026\), downloaded into npm's cache" "$WORK/ph3.txt"
# Incidents from data/incidents.tsv: a sourced line per incident, and the update level.
has    "each npm incident found gets its sourced line" 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it\. cisa\.gov' "$WORK/out-flat.txt"
cp -R "$WORK/clean" "$WORK/mis"; mkdir -p "$WORK/mis/code/m"
printf '{"lockfileVersion":3,"packages":{"node_modules/@mistralai/mistralai":{"version":"2.2.3","resolved":"https://registry.npmjs.org/@mistralai/mistralai/-/mistralai-2.2.3.tgz"}}}\n' > "$WORK/mis/code/m/package-lock.json"
psrun "$WORK/mis" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mis.txt"
psrun "$WORK/mis" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mis-c.txt"
hasnot "a version whose malware could not run is not 'compromised'" 'ACT NOW|Treat this machine as compromised' "$WORK/mis.txt"
has    "it is a version to update instead"           'npm malware a bad version to update' "$WORK/mis.txt"
has    "with the vendor's own explanation"           'Mistral AI npm packages, May 2026: published with malware Mistral says could not run, as its setup script names a missing file\. docs\.mistral\.ai' "$WORK/mis.txt"
has    "and a fix to update it"                      'Update the npm packages listed in section 5 to a version without the malware' "$WORK/mis.txt"
has    "the summary row says so in yellow"           'Recent leaks an npm package to update' "$WORK/mis-c.txt"
hasnot "it does not outrank moving keys out of plain text" 'First fix: Update the npm packages' "$WORK/mis-c.txt"
has    "the link does not call it npm malware"       '&nm=0&py=0&ex=0&wp=0( |$)' "$WORK/mis.txt"
hasnot "a Mistral hit does not get Injective's wallet fix" 'Move the funds' "$WORK/mis.txt"
# The @keyv 6.0.0 builds published without the install hook and SANDWORM_MODE's sleeper packages are
# malware, as GitHub's malware advisories say, and so are the UiPath builds, though Wiz found a bug in
# their payload. Packages the TanStack worm spread to, GitHub's second
# SANDWORM_MODE batch and the Mastra packages besides @mastra/core are found, Mastra named as Socket does.
for np in npd npa npk; do rm -rf "${WORK:?}/$np"; mkdir -p "$WORK/$np/code/x" "$WORK/$np/AppData/Roaming" "$WORK/$np/AppData/Local/Temp"; done
printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "node_modules/iru-caches": {\n      "version": "1.0.0"\n    },\n    "node_modules/@uipath/robot": {\n      "version": "1.3.4"\n    }\n  }\n}\n' > "$WORK/npd/code/x/package-lock.json"
printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "node_modules/@keyv/redis": {\n      "version": "6.0.0"\n    }\n  }\n}\n' > "$WORK/npk/code/x/package-lock.json"
printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "node_modules/@squawk/mcp": {\n      "version": "0.9.3"\n    },\n    "node_modules/veim": {\n      "version": "2.46.2"\n    },\n    "node_modules/@mastra/mcp": {\n      "version": "1.10.1"\n    }\n  }\n}\n' > "$WORK/npa/code/x/package-lock.json"
for np in npd npa npk; do psrun "$WORK/$np" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/$np.txt"; done
has    "a @keyv 6.0.0 build is npm malware, as GitHub's advisory says" '@keyv/redis 6\.0\.0 \(keyv account takeover, August 2026\).*keyv account takeover, August 2026: published from the compromised keyv account, and the GitHub advisory says to treat a machine that installed one as compromised\.' "$WORK/npk.txt"
has    "with its advice to rotate from another computer" 'Rotate the secrets this machine held from another computer, as the GitHub advisory says, then pin each @keyv package listed in section 5 to its version before 6\.0\.0\.' "$WORK/npk.txt"
has    "a SANDWORM_MODE sleeper package is malware, as GitHub's advisories say" 'iru-caches 1\.0\.0 \(SANDWORM_MODE sleeper packages, February 2026\).*SANDWORM_MODE sleeper packages, February 2026: GitHub malware advisories say to treat a machine that installed one as compromised\.' "$WORK/npd.txt"
hasnot "and no fix says its attackers published every version" 'the attackers published every version' "$WORK/npd.txt"
has    "a UiPath build is malware, as GitHub's advisory says" '@uipath/robot 1\.3\.4 \(UiPath npm packages, May 2026\).*UiPath npm packages, May 2026: published with malware, and the GitHub advisory says to treat a machine that installed one as compromised, though Wiz found a bug kept its payload from working\.' "$WORK/npd.txt"
rm -rf "$WORK/npu"; mkdir -p "$WORK/npu/code/x" "$WORK/npu/AppData/Roaming" "$WORK/npu/AppData/Local/Temp"
printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "node_modules/@uipath/robot": {\n      "version": "1.3.4"\n    }\n  }\n}\n' > "$WORK/npu/code/x/package-lock.json"
psrun "$WORK/npu" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npu.txt"
has    "a UiPath build alone in a lockfile says to act if that project was installed" 'ACT NOW IF YOU INSTALLED IT' "$WORK/npu.txt"
has    "and its fix says to rotate from another computer" 'Rotate the secrets this machine held from another computer, as the GitHub advisory says, then remove the @uipath packages section 5 lists\.' "$WORK/npu.txt"
has    "a package the TanStack worm spread to is found" '@squawk/mcp 0\.9\.3 \(TanStack worm, May 2026\)' "$WORK/npa.txt"
has    "a SANDWORM_MODE package of GitHub's second batch is found" 'veim 2\.46\.2 \(SANDWORM_MODE worm, February 2026\)' "$WORK/npa.txt"
# SANDWORM_MODE leaves git hooks behind (its pre-push hook sends npm tokens out) and MCP servers: its fix
# to remove them comes ahead of every fix that says to rotate, an incident's own advice to rotate too.
rm -rf "$WORK/sw"; mkdir -p "$WORK/sw/code/s/node_modules/suport-color" "$WORK/sw/code/s/node_modules/@keyv/redis" "$WORK/sw/AppData/Roaming" "$WORK/sw/AppData/Local/Temp"
printf '{"lockfileVersion":3,"packages":{"node_modules/suport-color":{"version":"1.0.1","resolved":"https://registry.npmjs.org/suport-color/-/suport-color-1.0.1.tgz"},"node_modules/@keyv/redis":{"version":"6.0.0","resolved":"https://registry.npmjs.org/@keyv/redis/-/redis-6.0.0.tgz"}}}\n' > "$WORK/sw/code/s/package-lock.json"
printf '{"name":"suport-color","version":"1.0.1"}\n' > "$WORK/sw/code/s/node_modules/suport-color/package.json"
printf '{"name":"@keyv/redis","version":"6.0.0"}\n' > "$WORK/sw/code/s/node_modules/@keyv/redis/package.json"
psrun "$WORK/sw" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/sw.txt"
psrun "$WORK/sw" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/sw-sum.txt"
has    "SANDWORM_MODE's fix: remove its git hooks and MCP servers first" ' 1\. First find and remove what the SANDWORM_MODE worm leaves: git hooks in the folder that git config --global init\.templateDir names and in the \.git/hooks and \.husky folders of your repositories, and MCP servers you did not add to your AI assistants\. Its pre-push hook sends npm tokens out on every push\. 2\. Treat this machine as compromised\.' "$WORK/sw.txt"
has    "ahead of an incident's own advice to rotate"  'Its pre-push hook sends npm tokens out on every push\. .*Rotate the secrets this machine held from another computer' "$WORK/sw.txt"
has    "and the summary's first fix is to remove them" 'First fix: First find and remove what the SANDWORM_MODE worm leaves' "$WORK/sw-sum.txt"
# wot-api 0.8.5, published an hour after 0.8.4, is malware by OpenSSF's entry, which Wiz's list leaves out.
rm -rf "$WORK/npw"; mkdir -p "$WORK/npw/code/w" "$WORK/npw/AppData/Roaming" "$WORK/npw/AppData/Local/Temp"
printf '{"lockfileVersion":3,"packages":{"node_modules/wot-api":{"version":"0.8.5","resolved":"https://registry.npmjs.org/wot-api/-/wot-api-0.8.5.tgz"}}}\n' > "$WORK/npw/code/w/package-lock.json"
psrun "$WORK/npw" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npw.txt"
has    "wot-api 0.8.5, which OpenSSF adds to the TanStack wave, is found" 'wot-api 0\.8\.5 \(TanStack worm, May 2026\), listed in this lockfile' "$WORK/npw.txt"
# With gh-token-monitor there too, its fix leaves the rotating to the fixes after SANDWORM_MODE's.
cp -R "$WORK/sw" "$WORK/sww"; mkdir -p "$WORK/sww/.config/gh-token-monitor"
psrun "$WORK/sww" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/sww.txt"
has    "with gh-token-monitor too, its fix does not say to rotate before SANDWORM_MODE's" ' 1\. Don.t revoke any GitHub token yet\. First stop and remove gh-token-monitor, as section 5 shows: it runs a destructive command when the stolen token stops working\. 2\. First find and remove what the SANDWORM_MODE worm leaves' "$WORK/sww.txt"
has    "a Mastra package is named as its sources name it" '@mastra/mcp 1\.10\.1 \(Mastra npm packages, June 2026\)' "$WORK/npa.txt"
# A version to update outranks an unreadable cache in row 05: a partial check never hides a finding to act on.
cp -R "$WORK/mis" "$WORK/misno"; mkdir -p "$WORK/misno/.npm/_cacache/index-v5/aa"; chmod 000 "$WORK/misno/.npm/_cacache/index-v5/aa"
psrun "$WORK/misno" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/misno.txt"
psrun "$WORK/misno" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/misno-c.txt"
chmod 755 "$WORK/misno/.npm/_cacache/index-v5/aa"
has    "an npm package to update outranks an unreadable cache in row 05" 'Recent leaks an npm package to update' "$WORK/misno-c.txt"
has    "and the hits say the cache was not read in full" "npm malware a bad version to update .*Part of npm's cache could not be read, so this is not the full list" "$WORK/misno.txt"
# mistralai 2.4.6's malware ran on Linux only (Mistral's advisory): on Linux the version is an act-now
# hit, on a Mac or Windows a version to update. gird-check.ps1 takes the OS from the machine it runs on.
cp -R "$WORK/clean" "$WORK/mpy"; mkdir -p "$WORK/mpy/code/venv/lib/site-packages/mistralai-2.4.6.dist-info"
psrun "$WORK/mpy" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mpy.txt"
psrun "$WORK/mpy" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mpy-c.txt"
[ "$(uname -s)" = Linux ] || SKIPPING="needs pwsh on Linux, as in CI"
has    "mistralai 2.4.6 from PyPI is its own act-now row" 'mistralai 2\.4\.6 +signs of the malware found ~/code/venv/lib/site-packages: mistralai 2\.4\.6' "$WORK/mpy.txt"
has    "with its fix"                                "Treat this machine as compromised\. Don't run Python in the affected environments, follow mistralai's advisory" "$WORK/mpy.txt"
has    "the link flags a Python incident, not LiteLLM" '&ll=0&.*&py=1&' "$WORK/mpy.txt"
SKIPPING=""; [ "$(uname -s)" = Darwin ] || SKIPPING="needs pwsh on macOS, which gird-check.ps1 knows by /System/Library/CoreServices"
has    "on a Mac, mistralai 2.4.6 is a version to update" 'mistralai 2\.4\.6 +a bad version to update ~/code/venv/lib/site-packages: mistralai 2\.4\.6' "$WORK/mpy.txt"
has    "and says why"                                 'Its malware runs on Linux only, so it did not run here\. Update to a version without it\. Advisory: docs\.mistral\.ai' "$WORK/mpy.txt"
hasnot "a Mac with it is not 'compromised'"           'ACT NOW|Treat this machine as compromised' "$WORK/mpy.txt"
has    "with a fix to update it"                      'Update the Python packages listed in section 5 to a version without the malware' "$WORK/mpy.txt"
has    "the link does not flag a Python incident"     '&ll=0&.*&py=0&' "$WORK/mpy.txt"
has    "row 05 says a Python package to update"       'Recent leaks a Python package to update, see section 5' "$WORK/mpy-c.txt"
SKIPPING=""
# guardrails-ai 0.10.1, published in the same wave, runs its stealer on Linux only too (Wiz).
cp -R "$WORK/clean" "$WORK/gpy"; mkdir -p "$WORK/gpy/code/venv/lib/site-packages/guardrails_ai-0.10.1.dist-info"
psrun "$WORK/gpy" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/gpy.txt"
[ "$(uname -s)" = Linux ] || SKIPPING="needs pwsh on Linux, as in CI"
has    "guardrails-ai 0.10.1 is its own act-now row on Linux" 'guardrails-ai 0\.10\.1 +signs of the malware found ~/code/venv/lib/site-packages: guardrails_ai 0\.10\.1' "$WORK/gpy.txt"
has    "with its fix, naming it"                      "Don't run Python in the affected environments, follow guardrails-ai's advisory" "$WORK/gpy.txt"
SKIPPING=""; [ "$(uname -s)" = Darwin ] || SKIPPING="needs pwsh on macOS, which gird-check.ps1 knows by /System/Library/CoreServices"
has    "on a Mac, guardrails-ai 0.10.1 is a version to update" 'guardrails-ai 0\.10\.1 +a bad version to update ~/code/venv/lib/site-packages: guardrails_ai 0\.10\.1 Its malware runs on Linux only, so it did not run here\. Update to a version without it\. Advisory: www\.wiz\.io/blog/' "$WORK/gpy.txt"
hasnot "and is not 'compromised' there"               'ACT NOW|Treat this machine as compromised' "$WORK/gpy.txt"
SKIPPING=""
# transformers.pyz in the temp folder is a Linux-only sign of mistralai 2.4.6.
cp -R "$WORK/clean" "$WORK/mpyt"; : > "$WORK/mpyt/AppData/Local/Temp/transformers.pyz"
psrun "$WORK/mpyt" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mpyt.txt"
[ "$(uname -s)" = Darwin ] || SKIPPING="needs pwsh on macOS, which gird-check.ps1 knows by /System/Library/CoreServices"
has    "on a Mac it is not looked for"                'mistralai 2\.4\.6 +no signs' "$WORK/mpyt.txt"
SKIPPING=""; [ "$(uname -s)" = Linux ] || SKIPPING="needs pwsh on Linux, as in CI"
has    "on Linux, transformers.pyz is the mistralai hit" 'mistralai 2\.4\.6 +signs of the malware found ~/AppData/Local/Temp/transformers\.pyz' "$WORK/mpyt.txt"
has    "and the link flags it"                        '&ll=0&.*&py=1&' "$WORK/mpyt.txt"
SKIPPING=""
# A version read from a folder name is printed with control characters replaced.
cp -R "$WORK/clean" "$WORK/esc"; mkdir -p "$WORK/esc/code/venv/lib/site-packages/litellm-1.0$(printf '\033')[31m.dist-info"
psrun "$WORK/esc" -- -Offline -Full > "$WORK/esc.txt" 2>&1
if grep -q "1\.0$(printf '\033')\[31m" "$WORK/esc.txt"; then bad "a hostile LiteLLM folder name sends no escape code"; else ok "a hostile LiteLLM folder name sends no escape code"; fi
has    "it is shown with a ? instead"                 'installed: 1\.0\?\[31m' "$WORK/esc.txt"
# uv's cache: the exact version only.
cp -R "$WORK/clean" "$WORK/uvn"; mkdir -p "$WORK/uvn/.cache/uv/wheels-v5/mistralai-2.4.60-py3-none-any" "$WORK/uvn/.cache/uv/archive-v0/x/mistralai-2.4.6.post1.dist-info"
psrun "$WORK/uvn" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/uvn.txt"
hasnot "uv's cache: 2.4.60 and 2.4.6.post1 are not 2.4.6" 'uv cache holds the 2\.4\.6 package' "$WORK/uvn.txt"
mkdir -p "$WORK/uvn/.cache/uv/archive-v0/y/mistralai-2.4.6.dist-info"
psrun "$WORK/uvn" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/uvn2.txt"
has    "uv's cache: 2.4.6 itself is"                  'uv cache holds the 2\.4\.6 package\. Clear it with: uv cache clean mistralai' "$WORK/uvn2.txt"
# npm malware and LiteLLM together, no wiper: the summary keeps both.
cp -R "$WORK/home" "$WORK/both"; rm -rf "$WORK/both/.config/gh-token-monitor"
psrun "$WORK/both" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/both.txt"
has    "npm and LiteLLM malware together are both named" 'npm and LiteLLM malware found' "$WORK/both.txt"
# LiteLLM alone still leads the summary.
cp -R "$WORK/clean" "$WORK/lite"; mkdir -p "$WORK/lite/code/py/.venv/lib/python3.12/site-packages/litellm-1.107.0.dist-info"; printf 'home = /usr\n' > "$WORK/lite/code/py/.venv/pyvenv.cfg"
psrun "$WORK/lite" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/lite.txt"
has    "a LiteLLM hit leads the summary"               'ACT NOW: SIGNS OF THE LITELLM 1\.107\.0 MALWARE' "$WORK/lite.txt"

echo "summary"
OUT=$WORK/compact.txt
psrun "$WORK/home" GIRD_CHECK_COMPACT=1 -- -Offline > "$OUT" 2>&1
for label in 'Coding agents' 'MCP servers' 'Keys in plain text' 'Allow lists' 'Recent leaks'; do
  has "one summary line for $label" "^   0[1-5] .*$label" "$OUT"
done
has    "the keys line names the first file"    'Keys in plain text +5 files, like ~/\.zshrc \(Anthropic, OpenAI\)' "$OUT"
has    "the summary leads with the first fix"  'First fix: Don.t revoke any GitHub token yet' "$OUT"
hasnot "the summary leaves out the other key files" '~/\.zsh_history +GitHub' "$OUT"
hasnot "the summary has no section tables"     'KEYS IN PLAIN TEXT' "$OUT"
hasnot "the summary shows no letter grade"     'GRADE [ABCDF]|[Gg]rade [ABCDF]\b' "$OUT"
nokeys "the summary never prints a planted key" "$WORK/keys.txt" "$OUT"
psrun "$WORK/home" GIRD_CHECK_COMPACT=1 -- -Offline -Full > "$WORK/full.txt" 2>&1
has    "-Full prints every section in full"    'KEYS IN PLAIN TEXT' "$WORK/full.txt"
has    "-Full lists every key file"            '~/\.zsh_history +GitHub' "$WORK/full.txt"

echo "the spend limit tip"
psrun "$WORK/home" -- -Offline > "$WORK/tip.txt" 2>&1
has    "the spend limit tip is a plain line"      '^     Also: set a monthly spend limit on every AI provider key' "$WORK/tip.txt"
hasnot "the spend limit tip is not numbered"      '^ *[0-9]+\. +.*spend limit' "$WORK/tip.txt"
LAST=$(grep -aE '^ +[0-9]+\.  ' "$WORK/tip.txt" | tail -n 1 | grep -aoE '^ +[0-9]+' | tr -d ' ')
ISS=$(grep -aoE '[0-9]+ things? to fix' "$WORK/tip.txt" | head -n 1 | grep -aoE '^[0-9]+')
if [ -n "$LAST" ] && [ "$LAST" = "$ISS" ]; then ok "the numbered list matches the fix count" "$ISS"; else bad "the numbered list matches the fix count" "list ends at $LAST, header says $ISS"; fi
rm -rf "$WORK/tip-empty"; mkdir -p "$WORK/tip-empty"
psrun "$WORK/tip-empty" -- -Offline > "$WORK/tip-empty.txt" 2>&1
has    "on a near-empty home the tip is still a plain line" '^     Also: set a monthly spend limit' "$WORK/tip-empty.txt"

echo "hostile file names"
EVIL="$WORK/home/code/evil$(printf '\033[2J\033]0;pwned\007\302\233')31m"
mkdir -p "$EVIL"
printf 'AWS_ACCESS_KEY_ID=AK%s\n' "IA$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Z0-9' | head -c 16)" > "$EVIL/.env"
psrun "$WORK/home" -- -Offline > "$WORK/evil.txt" 2>&1
if LC_ALL=C grep -aq "$(printf '\033')\|$(printf '\007')\|$(printf '\302\233')" "$WORK/evil.txt"; then bad "control characters in file names never reach the terminal"; else ok "control characters in file names never reach the terminal"; fi
has "the hostile folder is still reported" 'code/evil\?' "$WORK/evil.txt"
rm -rf "$EVIL"
# A TAB in a folder name would split gird-check.sh's rows, and a | the rows it joins with |: the same
# folders through gird-check.ps1, which must list every finding the same way and send nothing raw.
bash tests/make-hostile.sh "$WORK/hostile" "$WORK/keys-hostile.txt"
mkdir -p "$WORK/hostile/AppData/Roaming" "$WORK/hostile/AppData/Local/Temp"
psrun "$WORK/hostile" -- -Offline -AllSessions > "$WORK/hostile.txt" 2>&1
if LC_ALL=C grep -aq "$(printf '\033')\|$(printf '\007')" "$WORK/hostile.txt"; then bad "a TAB in a folder name: no control character reaches the terminal"; else ok "a TAB in a folder name: no control character reaches the terminal"; fi
tr -s ' \n' '  ' < "$WORK/hostile.txt" > "$WORK/hostile-flat.txt"
X='\?\?\[2J\?\]0;pwned\?x'
has    "a TAB in a folder name: project settings keep their row"     "code/auto$X/\.claude/settings\.json Set to run commands" "$WORK/hostile-flat.txt"
has    "a TAB in a folder name: a project's VS Code settings keep their row" "p/yolo$X/\.vscode/settings\.json Set to auto-approve" "$WORK/hostile-flat.txt"
has    "a TAB in a folder name: a lockfile hit keeps its package and source" "code/lock$X/package-lock\.json axios 1\.14\.1 \(Axios takeover, March 2026\), listed in this lockfile" "$WORK/hostile-flat.txt"
has    "a TAB in a folder name: a planted file keeps its note"       "code/plant$X/\.vscode/router_runtime\.js a file the TanStack worm plants" "$WORK/hostile-flat.txt"
has    "a TAB in a folder name: a key in an Aider history is found"  "code/aider$X/\.aider\.chat\.history\.md" "$WORK/hostile-flat.txt"
has    "a TAB in a folder name: a link to authorized_keys is listed" "code/link$X/notes\.txt" "$WORK/hostile-flat.txt"
has    "a | in a folder name: an MCP config keeps its count and token" "code/mcp\|\?\[2Jpipe$X/\.mcp\.json 1 server, token in the file" "$WORK/hostile-flat.txt"
has    "a | in a folder name: a key file keeps its provider"         "code/key\|\?\[2Jpipe$X/\.env OpenAI" "$WORK/hostile-flat.txt"
has    "a | in a folder name: an allow list keeps its finding"       "code/allow\|\?\[2Jpipe$X/\.claude/settings\.local\.json A saved command contains a key" "$WORK/hostile-flat.txt"
nokeys "hostile folder names: no planted key is printed" "$WORK/keys-hostile.txt" "$WORK/hostile.txt"
hasnot "hostile folder names: no shell error" 'Exception|ParserError|At line:|is not recognized' "$WORK/hostile.txt"

echo "folders the home scan can't read"
# A folder that can't be read, holding a bad lockfile: it is named as not checked, and the rows the
# home scan feeds are not green.
rm -rf "$WORK/ud"; mkdir -p "$WORK/ud/code/locked/app" "$WORK/ud/AppData/Roaming" "$WORK/ud/AppData/Local/Temp"
printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$WORK/ud/code/locked/app/package-lock.json"
chmod 000 "$WORK/ud/code/locked"
psrun "$WORK/ud" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ud.txt"
psrun "$WORK/ud" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ud-c.txt"
chmod 755 "$WORK/ud/code/locked"
has    "an unreadable folder is named as not checked" '1 folder in your home could not be read, so sections 2 to 5 did not .*the files in it: ~/code/locked\.' "$WORK/ud.txt"
has    "and the npm row is not green"                 'npm malware not fully checked: some folders in your home could not be read' "$WORK/ud.txt"
has    "and the keys row is not green"                'Keys in plain text none found, but some folders were not read' "$WORK/ud-c.txt"
has    "and the allow lists row is not green"         'Allow lists none found, but some folders were not read' "$WORK/ud-c.txt"
has    "and the leaks row is not green"               'Recent leaks none found, but some folders were not read' "$WORK/ud-c.txt"
hasnot "and the headline does not call the scan clean" 'NO FINDINGS IN THIS SCAN' "$WORK/ud-c.txt"
# A folder whose name holds a line break: gird-check.ps1 lists folders through .NET, so it reads the
# files in it (gird-check.sh, which reads find's output a line at a time, names it as not checked).
rm -rf "$WORK/nl"; mkdir -p "$WORK/nl/code/proj${_nl}x" "$WORK/nl/AppData/Roaming" "$WORK/nl/AppData/Local/Temp"
printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$WORK/nl/code/proj${_nl}x/package-lock.json"
psrun "$WORK/nl" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/nl.txt"
has    "the files in a folder with a line break in its name are read" '~/code/proj\?x/package-lock\.json axios 1\.14\.1 \(Axios takeover' "$WORK/nl.txt"

echo "placeholders and the LiteLLM leftovers"
mkdir -p "$WORK/ph/code/ph" "$WORK/ph/AppData/Local/Temp"
printf '{"mcpServers":{"x":{"command":"npx","env":{"API_KEY":"your-api-key-goes-here"}}}}\n' > "$WORK/ph/code/ph/.mcp.json"
# A placeholder shaped like a real command key, which only the placeholder screen stops.
mkdir -p "$WORK/ph/code/ph/.claude"; printf '{"name":"ph","private":true}\n' > "$WORK/ph/code/ph/package.json"
printf '{"permissions":{"allow":["Bash(OPENAI_API_KEY=your-openai-key-goes-here npm test)"]}}\n' > "$WORK/ph/code/ph/.claude/settings.local.json"
psrun "$WORK/ph" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ph.txt"
has    "a placeholder token is not a token"    'MCP servers +1 server, no tokens in their configs' "$WORK/ph.txt"
has    "a placeholder key in an allow list is not a key" 'Allow lists +no saved commands with keys' "$WORK/ph.txt"
has    "no leaks found: row 05 counts the leaks it checks" 'none of the 8 recent leaks or malware it checks' "$WORK/ph.txt"

echo "Zeabur and the LiteLLM leftovers"
lp()  { psrun "$1" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  '; }
lpf() { psrun "$1" -- -Offline 2>&1 | tr -s ' \n' '  '; }
cp -R "$WORK/clean" "$WORK/zb-none"; rm -rf "$WORK/zb-none/.config/opencode" "$WORK/zb-none/.local/share/opencode" "$WORK/zb-none/.railway"
lp "$WORK/zb-none" > "$WORK/zb-none.txt"
hasnot "no pyc, no malware flag"               'Act now|possible LiteLLM leftover' "$WORK/zb-none.txt"
# The editor-extension check is counted and has a row when clean; a folder that can't be read is said.
lpf "$WORK/zb-none" > "$WORK/zb-none-full.txt"
has    "a clean run shows the editor-extension check" 'Editor extensions +none of [0-9]+ bad versions or [0-9]+ bad extensions checked the extension folders of VS Code, Cursor, Windsurf, Devin Desktop, VSCodium, Kiro and Antigravity' "$WORK/zb-none-full.txt"
has    "and section 5 counts it"                      'RECENT KEY LEAKS +8 checked' "$WORK/zb-none-full.txt"
cp -R "$WORK/zb-none" "$WORK/zb-ext"; mkdir -p "$WORK/zb-ext/.cursor/extensions/some.theme-1.0.0"; chmod 000 "$WORK/zb-ext/.cursor/extensions"
lpf "$WORK/zb-ext" > "$WORK/zb-ext.txt"; lp "$WORK/zb-ext" > "$WORK/zb-ext-c.txt"
chmod 755 "$WORK/zb-ext/.cursor/extensions"
has    "an extension folder that cannot be read is not called clean" 'Editor extensions +not fully checked: 1 extension folder could not be read' "$WORK/zb-ext.txt"
has    "and row 05 says so"                           'Recent leaks +extensions not fully checked: folder unreadable' "$WORK/zb-ext-c.txt"
cp -R "$WORK/zb-none" "$WORK/zb-one"; mkdir -p "$WORK/zb-one/.config/zeabur"
lp "$WORK/zb-one" > "$WORK/zb-one.txt"
lpf "$WORK/zb-one" > "$WORK/zb-one-full.txt"
has    "Zeabur alone is flagged"               'Zeabur CLI found: rotate secrets stored there' "$WORK/zb-one.txt"
has    "Zeabur adds a fix naming only what was found" 'If you used Zeabur, rotate the keys stored there' "$WORK/zb-one-full.txt"
has    "Zeabur has its own detail line"        'Zeabur CLI found' "$WORK/zb-one-full.txt"
has    "Zeabur's line gives the date of its post" 'Zeabur said on 19 October that an attacker read the service environment variables stored on the platform, and asked users to replace every password and key stored there\. Revoke each old key at its provider first\.' "$WORK/zb-one-full.txt"
cp -R "$WORK/zb-one" "$WORK/zb-two"; mkdir -p "$WORK/zb-two/.railway"; printf '{}\n' > "$WORK/zb-two/.railway/config.json"
lp "$WORK/zb-two" > "$WORK/zb-two.txt"
has    "Railway and Zeabur are named together" 'Railway and Zeabur found: rotate their keys' "$WORK/zb-two.txt"
cp -R "$WORK/zb-two" "$WORK/zb-three"; mkdir -p "$WORK/zb-three/.config/opencode"
lp "$WORK/zb-three" > "$WORK/zb-three.txt"
has    "all three are named in order"          'OpenCode, Railway and Zeabur found: rotate keys' "$WORK/zb-three.txt"
# No agent and nothing found. A minimal PATH and no AppData hide every agent, so nothing is idle.
rm -rf "$WORK/ni-empty"; mkdir -p "$WORK/ni-empty"
lpf "$WORK/ni-empty" > "$WORK/ni-empty.txt"
has    "nothing found: the header says no findings"        'NO FINDINGS IN THIS SCAN' "$WORK/ni-empty.txt"
has    "nothing found: it says this is not a guarantee"    'does not prove nothing leaked' "$WORK/ni-empty.txt"
hasnot "nothing found: no old clean-today wording"         'CLEAN TODAY|needs fixing|Nothing to fix' "$WORK/ni-empty.txt"
rm -rf "$WORK/ni-pyc"; mkdir -p "$WORK/ni-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__"; : > "$WORK/ni-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__/cook.cpython-312.pyc"
lpf "$WORK/ni-pyc" > "$WORK/ni-pyc.txt"
has    "a pyc-only run counts its things to fix"           '[0-9]+ THINGS? TO FIX' "$WORK/ni-pyc.txt"
has    "a pyc-only run keeps the no-guarantee line"        'does not prove nothing leaked' "$WORK/ni-pyc.txt"
hasnot "a pyc-only run is not told there are no findings"  'NO FINDINGS IN THIS SCAN' "$WORK/ni-pyc.txt"
# A check that was not done in full, with nothing found, never gets the green headline: sessions
# partly checked, or part of npm's cache unreadable.
rm -rf "$WORK/ni-part"; mkdir -p "$WORK/ni-part/.claude/projects/p"; printf '{}\n' > "$WORK/ni-part/.claude/projects/p/a.jsonl"; printf '{}\n' > "$WORK/ni-part/.claude/projects/p/b.jsonl"
psrun "$WORK/ni-part" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_STOP_AFTER=0 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-part.txt"
has    "sessions partly checked: the headline says no findings in the paths checked" 'NO FINDINGS IN THE PATHS CHECKED' "$WORK/ni-part.txt"
hasnot "and never no findings in this scan"           'NO FINDINGS IN THIS SCAN' "$WORK/ni-part.txt"
rm -rf "$WORK/ni-npm"; mkdir -p "$WORK/ni-npm/.npm/_cacache/index-v5/aa"; chmod 000 "$WORK/ni-npm/.npm/_cacache/index-v5/aa"
psrun "$WORK/ni-npm" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-npm.txt"
chmod 755 "$WORK/ni-npm/.npm/_cacache/index-v5/aa"
has    "npm's cache partly read: the headline says no findings in the paths checked" 'NO FINDINGS IN THE PATHS CHECKED' "$WORK/ni-npm.txt"
hasnot "and never no findings in this scan either"    'NO FINDINGS IN THIS SCAN' "$WORK/ni-npm.txt"
# A key file that is there but can't be read is named, never taken for one with no keys: section 3,
# row 03 and the headline say the check was partial. A link to nothing is not such a file.
rm -rf "$WORK/ni-key"; mkdir -p "$WORK/ni-key/code/app"; printf 'export X=1\n' > "$WORK/ni-key/.zshrc"; printf 'A=1\n' > "$WORK/ni-key/code/app/.env"
ln -s "$WORK/ni-key/nowhere" "$WORK/ni-key/.bashrc"; chmod 000 "$WORK/ni-key/.zshrc" "$WORK/ni-key/code/app/.env"
psrun "$WORK/ni-key" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-key.txt"
psrun "$WORK/ni-key" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-key-c.txt"
chmod 644 "$WORK/ni-key/.zshrc" "$WORK/ni-key/code/app/.env"
has    "a key file that can't be read is named as not read" '! No AI or cloud keys in the files read, but [0-9]+ files? could not be read: ~/\.zshrc ' "$WORK/ni-key.txt"
has    "a link to nothing is not counted as a file that could not be read" 'but 2 files could not be read: ~/\.zshrc ~/code/app/\.env ' "$WORK/ni-key.txt"
hasnot "and section 3 never says there are no keys"   '✓ No AI or cloud keys' "$WORK/ni-key.txt"
has    "and row 03 says files could not be read"      'Keys in plain text none found, but 2 files could not be read' "$WORK/ni-key-c.txt"
has    "a key file that can't be read: the headline says no findings in the paths checked" 'NO FINDINGS IN THE PATHS CHECKED' "$WORK/ni-key.txt"
# With a key found in another file, the list says it is not the full one.
printf 'AWS_ACCESS_KEY_ID=AK%s\n' "IA$(upper 16)" > "$WORK/ni-key/code/app/.envrc"; chmod 000 "$WORK/ni-key/.zshrc"
psrun "$WORK/ni-key" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-key2.txt"
chmod 644 "$WORK/ni-key/.zshrc"
has    "next to a key found, a file that can't be read says the list is not full" '~/code/app/\.envrc AWS ! 1 file could not be read, so this is not the full list: ~/\.zshrc ' "$WORK/ni-key2.txt"
# Section 2's and section 4's files are named too when they can't be read: an MCP config, a project's
# settings and Claude Code's own settings file, which holds the allow list.
rm -rf "$WORK/ni-s24"; mkdir -p "$WORK/ni-s24/.claude" "$WORK/ni-s24/code/p/.claude" "$WORK/ni-s24/AppData/Roaming" "$WORK/ni-s24/AppData/Local/Temp"
printf '{"mcpServers":{}}\n' > "$WORK/ni-s24/.claude.json"; printf '{"hooks":{}}\n' > "$WORK/ni-s24/code/p/.claude/settings.json"
printf '{"permissions":{"allow":[]}}\n' > "$WORK/ni-s24/.claude/settings.local.json"
chmod 000 "$WORK/ni-s24/.claude.json" "$WORK/ni-s24/code/p/.claude/settings.json" "$WORK/ni-s24/.claude/settings.local.json"
psrun "$WORK/ni-s24" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-s24.txt"
psrun "$WORK/ni-s24" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-s24-c.txt"
chmod 644 "$WORK/ni-s24/.claude.json" "$WORK/ni-s24/code/p/.claude/settings.json" "$WORK/ni-s24/.claude/settings.local.json"
has    "an MCP config or a project's settings that can't be read is named in section 2" '! [0-9]+ config or settings files? could not be read, so the servers, tokens and settings in them were not checked: .*~/code/p/\.claude/settings\.json' "$WORK/ni-s24.txt"
has    "and row 02 says files could not be read"       'MCP servers .*but [0-9]+ files? could not be read' "$WORK/ni-s24-c.txt"
has    "an allow list that can't be read is named in section 4" '! No saved commands with keys in the files read, but [0-9]+ files? could not be read: .*~/\.claude/settings\.local\.json' "$WORK/ni-s24.txt"
has    "and row 04 says files could not be read"       'Allow lists none found, but [0-9]+ files? could not be read' "$WORK/ni-s24-c.txt"
hasnot "and neither section reads clean"               '✓ No saved commands with keys' "$WORK/ni-s24.txt"
# PowerShell's own partial check: a file that hit the time limit.
rm -rf "$WORK/ni-slow"; mkdir -p "$WORK/ni-slow/code/s"
python3 -c "import sys; open(sys.argv[1], 'w').write(('sk-' + 'a' * 40 + ' ') * 150000)" "$WORK/ni-slow/code/s/.env"
psrun "$WORK/ni-slow" GIRD_CHECK_REGEX_TIMEOUT_MS=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-slow.txt"
has    "a file that took too long: the headline says no findings in the paths checked" 'NO FINDINGS IN THE PATHS CHECKED' "$WORK/ni-slow.txt"

echo "checks from the incident dossier"
for M in hit miss; do
  rm -rf "$WORK/dz-$M"; cp -R "$WORK/clean" "$WORK/dz-$M"; bash tests/make-dossier.sh "$WORK/dz-$M" "$WORK/dz-$M/AppData/Roaming" "$M"
  psrun "$WORK/dz-$M" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/dz-$M-flat.txt"
  psrun "$WORK/dz-$M" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/dz-$M-sum.txt"
done
D=$WORK/dz-hit-flat.txt
has    "Claude Code set to bypass permissions"        '! Claude Code ~/\.claude/settings\.json bypassPermissions' "$D"
has    "Codex set to never ask, with full access"     '! Codex ~/\.codex/config\.toml never asks, full access' "$D"
has    "VS Code's user settings: the global key, not the commented one" 'AppData/Roaming/Code/User/settings\.json chat\.tools\.global\.autoApprove A prompt injection' "$D"
has    "a project's chat.tools.autoApprove: the setting CVE-2025-53773 wrote, which VS Code now ignores" '! ~/p/yolo/\.vscode/settings\.json Set to auto-approve Copilot.s tools with chat\.tools\.autoApprove, the setting the CVE-2025-53773 attack wrote into projects\. VS Code 1\.104 and later ignore it\.' "$D"
hasnot "a project's chat.tools.autoApprove is not an agent set to run without asking" '! VS Code Copilot ~/p/' "$D"
hasnot "a workspace set to false is not listed"       'p/calm/' "$D"
has    "with the advice"                              'A prompt injection in anything the agent reads can then run commands on this computer\. Turn it off unless the agent runs in a sandbox\.' "$D"
has    "and the fix"                                  'Turn off run-without-asking in the agents listed in section 1, unless they run in a sandbox\.' "$D"
[ "$(uname -s)" = Darwin ] || SKIPPING="needs pwsh on macOS: Cursor's version is read from its app bundle"
has    "Cursor below the fixed version" '! Cursor 2\.9\.1, update to 3\.1\.2 or later A malicious agent could escape the sandbox\. github\.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw An agent could replace the Python of a virtual environment to run commands outside the sandbox\. github\.com/cursor/cursor/security/advisories/GHSA-p9g2-cr55-cw9c' "$D"
SKIPPING=""
has    "Amazon Q language server: the highest version folder, compared as numbers" '! Amazon Q language server 1\.68\.0, update to 1\.69\.0 or later A link in a workspace can reach files outside it' "$D"
has    "Claude Code installed with npm"               '! Claude Code 1\.0\.3, update to 2\.1\.260 or later A web page could reach the editor connection\. github\.com/advisories/GHSA-9f65-56v6-gxw7 A plugin repository could install code that bypasses its pinned hash\. github\.com/advisories/GHSA-pq7j-f95f-qfcv' "$D"
has    "mcp-remote installed and in an MCP config's args" '! mcp-remote 0\.0\.5, 0\.1\.10, update to 0\.1\.16 or later A hostile MCP server could run commands\. github\.com/advisories/GHSA-6xpm-ggf7-wc3p' "$D"
has    "with the fix"                                 'Update the tools listed in section 1 that have a security fix\.' "$D"
has    "a link to authorized_keys"                    'Files that link to your SSH logins ✗ ~/code/links/notes\.txt An agent that edits this file adds a login to this computer\. Delete the link\.' "$D"
has    "with the fix to delete the link"              'Delete the links to ~/\.ssh/authorized_keys listed in section 2\.' "$D"
has    "a GlassWorm extension at its bad version, with a platform suffix, in an Open VSX editor's folder" '~/\.vscode-oss/extensions/oorzc\.ssh-tools-0\.5\.1-darwin-arm64 oorzc\.ssh-tools 0\.5\.1 \(GlassWorm extensions, January 2026\), installed' "$D"
has    "a GlassWorm extension at any version, its id in another case" '~/\.cursor/extensions/Sol-Studio\.Solidity-Extension-2\.0\.0 sol-studio\.solidity-extension 2\.0\.0 \(GlassWorm' "$D"
has    "with GlassWorm's sourced line"                'GlassWorm extensions, January 2026: stole SSH keys, cloud and npm credentials, keychains and crypto wallets from Macs\. socket\.dev' "$D"
has    "the GlassWorm fix names only what section 5 lists: the extensions" 'Treat this machine as compromised\. Uninstall the extensions listed in section 5 and rotate every key this machine could reach\.' "$D"
has    "the GlassWorm advice says to check the files its source names" 'On a Mac, also check ~/Library/LaunchAgents for unfamiliar plists such as com\.user\.nodestart\.plist, and look for /tmp/ijewf and /tmp/out\.zip, where the malware collects what it steals\.' "$D"
hasnot "and never to delete every LaunchAgent not recognized" 'delete [^.]*LaunchAgents|you do not recognize' "$D"
has    "the Injective fix: move the funds out of its wallets" 'From a clean machine, move the funds out of every wallet whose seed phrase or private key was used with Injective SDK 1\.20\.21, into a new wallet\.' "$D"
has    "the Injective fix comes before the update it has to come before" 'into a new wallet\. .*Update the npm packages listed in section 5' "$D"
has    "the Injective SDK in a lockfile"              '@injectivelabs/sdk-ts 1\.20\.21 \(Injective SDK, July 2026\), listed in this lockfile' "$D"
has    "with its sourced line"                        'Injective SDK, July 2026: sent out the seed phrases, and the private keys given as hex strings, that apps loaded into it\. github\.com' "$D"
# Injective alone: moving the funds outranks every fix that is not act-now, and row 05 names the wallets.
rm -rf "$WORK/dz-inj"; cp -R "$WORK/clean" "$WORK/dz-inj"; mkdir -p "$WORK/dz-inj/code/inj"
printf '{"lockfileVersion":3,"packages":{"node_modules/@injectivelabs/sdk-ts":{"version":"1.20.21","resolved":"https://registry.npmjs.org/@injectivelabs/sdk-ts/-/sdk-ts-1.20.21.tgz"}}}\n' > "$WORK/dz-inj/code/inj/package-lock.json"
psrun "$WORK/dz-inj" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/dz-inj.txt"
psrun "$WORK/dz-inj" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/dz-inj-sum.txt"
has    "Injective's wallet fix comes first, ahead of moving keys out of plain text" ' 1\. From a clean machine, move the funds out of every wallet whose seed phrase or private key was used with Injective SDK 1\.20\.21, into a new wallet\. 2\. Move keys out of shell profiles' "$WORK/dz-inj.txt"
has    "and it is the summary's first fix"             'First fix: From a clean machine, move the funds out of every wallet whose seed phrase or private key was used with Injective SDK 1\.20\.21' "$WORK/dz-inj-sum.txt"
has    "row 05 names the wallets"                      'Recent leaks +Injective SDK: move the funds out of its wallets' "$WORK/dz-inj-sum.txt"
dzrun() { _h=$1; shift; psrun "$_h" "$@" -- -Offline 2>&1; }
has    "an extension hit is not npm malware in the link" '&nm=0&py=0&ex=1&wp=0' "$D"
# Editor extensions: a row, headline and fix of their own, never called npm malware. The LaunchAgent
# GlassWorm leaves is that incident's sign, listed with its extension, never as npm malware.
rm -rf "$WORK/dz-ext"; cp -R "$WORK/clean" "$WORK/dz-ext"; mkdir -p "$WORK/dz-ext/.cursor/extensions/oorzc.mind-map-1.0.61" "$WORK/dz-ext/Library/LaunchAgents"
: > "$WORK/dz-ext/Library/LaunchAgents/com.user.nodestart.plist"
dzrun "$WORK/dz-ext" > "$WORK/dz-ext.txt"; tr -s ' \n' '  ' < "$WORK/dz-ext.txt" > "$WORK/dz-ext-flat.txt"
dzrun "$WORK/dz-ext" GIRD_CHECK_COMPACT=1 | tr -s ' \n' '  ' > "$WORK/dz-ext-sum.txt"
has    "extensions alone: their own row"              'Editor extensions signs of the malware found ~/\.cursor/extensions/oorzc\.mind-map-1\.0\.61 oorzc\.mind-map 1\.0\.61 \(GlassWorm' "$WORK/dz-ext-flat.txt"
has    "extensions alone: the LaunchAgent GlassWorm leaves is listed with the extension" 'oorzc\.mind-map 1\.0\.61 \(GlassWorm extensions, January 2026\), installed ~/Library/LaunchAgents/com\.user\.nodestart\.plist starts the GlassWorm malware at login' "$WORK/dz-ext-flat.txt"
has    "extensions alone: their own headline"         'ACT NOW: SIGNS OF MALWARE IN AN EDITOR EXTENSION' "$WORK/dz-ext.txt"
hasnot "extensions alone: no npm in the headline"     'ACT NOW.*NPM' "$WORK/dz-ext.txt"
hasnot "extensions alone: no npm malware row or fix"  'npm malware +signs of the malware|Delete the packages and files listed in section 5|signs of npm malware' "$WORK/dz-ext.txt"
has    "extensions alone: their own fix names the extensions and the startup file" 'Treat this machine as compromised\. Uninstall the extensions listed in section 5, delete the startup file listed there, and rotate every key this machine could reach\.' "$WORK/dz-ext-flat.txt"
has    "extensions alone: their own summary row"      'Recent leaks +signs of malware in an editor extension\. Act now' "$WORK/dz-ext-sum.txt"
has    "extensions alone: the link says ex, not nm"   '&nm=0&py=0&ex=1&wp=0' "$WORK/dz-ext.txt"
# GlassWorm's LaunchAgent name alone, with no extension that shipped malware, is a file to check, not
# malware: com.user. is how people name their own LaunchAgents, and this one starts a node server.
rm -rf "$WORK/dz-la"; cp -R "$WORK/clean" "$WORK/dz-la"; mkdir -p "$WORK/dz-la/Library/LaunchAgents"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>Label</key>\n\t<string>com.user.nodestart</string>\n\t<key>ProgramArguments</key>\n\t<array>\n\t\t<string>/opt/homebrew/bin/node</string>\n\t\t<string>/Users/me/projects/homelab/server.js</string>\n\t</array>\n</dict>\n</plist>\n' > "$WORK/dz-la/Library/LaunchAgents/com.user.nodestart.plist"
dzrun "$WORK/dz-la" | tr -s ' \n' '  ' > "$WORK/dz-la.txt"
dzrun "$WORK/dz-la" GIRD_CHECK_COMPACT=1 | tr -s ' \n' '  ' > "$WORK/dz-la-sum.txt"
has    "the LaunchAgent alone: a startup file to check, with its sourced line" 'Editor extensions a startup file to check ~/Library/LaunchAgents/com\.user\.nodestart\.plist has the name of a file that starts the GlassWorm malware at login No editor extension that shipped malware was found\. Open the file and check what it starts: if you did not set it up yourself, treat this machine as compromised\. GlassWorm extensions, January 2026:' "$WORK/dz-la.txt"
hasnot "the LaunchAgent alone: no act-now headline, malware row or compromised verdict" 'ACT NOW|SIGNS OF MALWARE|signs of the malware found|Treat this machine as compromised\.' "$WORK/dz-la.txt"
has    "the LaunchAgent alone: the fix says to check it" 'Open the startup file listed in section 5 and check what it starts at login\. If you did not set it up yourself, treat this machine as compromised: delete it and rotate every key this machine could reach\.' "$WORK/dz-la.txt"
has    "the LaunchAgent alone: row 05 asks to check it" 'Recent leaks +a startup file to check, see section 5' "$WORK/dz-la-sum.txt"
has    "the LaunchAgent alone: the link says neither ex nor nm" '&nm=0&py=0&ex=0&wp=0' "$WORK/dz-la.txt"
cp -R "$WORK/dz-ext" "$WORK/dz-both"; mkdir -p "$WORK/dz-both/code/ax"
printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$WORK/dz-both/code/ax/package-lock.json"
# Installed next to its lockfile: a lockfile alone would leave the npm fix depending on an install.
mkdir -p "$WORK/dz-both/code/ax/node_modules/axios"; printf '{"name":"axios","version":"1.14.1"}\n' > "$WORK/dz-both/code/ax/node_modules/axios/package.json"
dzrun "$WORK/dz-both" | tr -s ' \n' '  ' > "$WORK/dz-both.txt"
has    "npm and extensions: both rows, each with its own findings" 'npm malware signs of the malware found ~/code/ax/package-lock\.json axios 1\.14\.1 .*Editor extensions signs of the malware found ~/\.cursor/extensions/oorzc\.mind-map' "$WORK/dz-both.txt"
has    "npm and extensions: one headline names both"  'ACT NOW: SIGNS OF NPM AND EDITOR EXTENSION MALWARE' "$WORK/dz-both.txt"
has    "npm and extensions: both fixes"               'Delete the packages and files listed in section 5.*Uninstall the extensions listed in section 5' "$WORK/dz-both.txt"
has    "npm and extensions: the link says both"       '&nm=1&py=0&ex=1&wp=0' "$WORK/dz-both.txt"
# GlassWorm's later waves, one extension of each in another editor's folder: Socket's 13 March list
# (every version), a version the 18 March post shows delivering malware, one of the six the April post
# confirms, and a malicious Marketplace theme of October in VS Code's own folder. Near misses: a version
# the 18 March post does not name, and an Open VSX extension's id in VS Code's own folder.
rm -rf "$WORK/dz-waves"; cp -R "$WORK/clean" "$WORK/dz-waves"
mkdir -p "$WORK/dz-waves/.cursor/extensions/aadarkcode.one-dark-material-3.20.1" "$WORK/dz-waves/.windsurf/extensions/spacetoow.vsc-python-indent-1.21.4" \
  "$WORK/dz-waves/.kiro/extensions/boulderzitunnel.vscode-buddies-1.35.3" "$WORK/dz-waves/.vscode/extensions/cosmic-themes.theme-cosmic-nebula-1.0.0" \
  "$WORK/dz-waves/.vscode-oss/extensions/spacetoow.vsc-python-indent-1.21.0" "$WORK/dz-waves/.vscode/extensions/aadarkcode.one-dark-material-3.20.1" \
  "$WORK/dz-waves/.devin/extensions/oorzc.i18n-tools-plus-1.6.8"
dzrun "$WORK/dz-waves" | tr -s ' \n' '  ' > "$WORK/dz-waves.txt"
has    "a GlassWorm extension of Socket's 13 March list, at any version" '~/\.cursor/extensions/aadarkcode\.one-dark-material-3\.20\.1 aadarkcode\.one-dark-material 3\.20\.1 \(GlassWorm extensions, March 2026\), installed' "$WORK/dz-waves.txt"
has    "a version the 18 March post shows delivering malware" '~/\.windsurf/extensions/spacetoow\.vsc-python-indent-1\.21\.4 spacetoow\.vsc-python-indent 1\.21\.4 \(GlassWorm sleeper extensions, March 2026\), installed' "$WORK/dz-waves.txt"
has    "Devin Desktop's extension folder is read, as an Open VSX editor's" '~/\.devin/extensions/oorzc\.i18n-tools-plus-1\.6\.8 oorzc\.i18n-tools-plus 1\.6\.8 \(GlassWorm extensions, January 2026\), installed' "$WORK/dz-waves.txt"
has    "one of the six the April post confirms"      '~/\.kiro/extensions/boulderzitunnel\.vscode-buddies-1\.35\.3 boulderzitunnel\.vscode-buddies 1\.35\.3 \(GlassWorm sleeper extensions, April 2026\), installed' "$WORK/dz-waves.txt"
has    "a GlassWorm-linked Marketplace theme, in VS Code's own folder" '~/\.vscode/extensions/cosmic-themes\.theme-cosmic-nebula-1\.0\.0 cosmic-themes\.theme-cosmic-nebula 1\.0\.0 \(GlassWorm-linked themes, October 2026\), installed' "$WORK/dz-waves.txt"
has    "each wave with its own sourced line"         'GlassWorm sleeper extensions, April 2026: updated cloned extensions to install malware from GitHub into VS Code, Cursor and Windsurf\. socket\.dev GlassWorm extensions, March 2026: ran attacker code in memory that could reach local credentials, tokens and secrets\. socket\.dev GlassWorm-linked themes, October 2026: a VS Code theme cluster tied to GlassWorm; two of its themes ran hidden loaders\. socket\.dev GlassWorm sleeper extensions, March 2026: installed a malicious extension from GitHub into every editor it found\. socket\.dev' "$WORK/dz-waves.txt"
if [ "$(grep -o 'Also check every editor you use, VS Code included, for extensions you did not install yourself' "$WORK/dz-waves.txt" | grep -c .)" -eq 1 ]; then ok "the fix two waves share is said once"; else bad "the fix two waves share is said once"; fi
hasnot "a version the 18 March post does not name is not flagged" 'spacetoow\.vsc-python-indent 1\.21\.0' "$WORK/dz-waves.txt"
hasnot "an Open VSX extension's id in VS Code's own folder is not flagged" '~/\.vscode/extensions/aadarkcode' "$WORK/dz-waves.txt"
# Antigravity installs from Open VSX: Antigravity IDE keeps its extensions in ~/.antigravity-ide, the
# Antigravity before it in ~/.antigravity. A GlassWorm extension that names Antigravity, in each.
rm -rf "$WORK/dz-ag"; cp -R "$WORK/clean" "$WORK/dz-ag"
mkdir -p "$WORK/dz-ag/.antigravity-ide/extensions/mswincx.antigravity-cockpit-1.2.0-universal" "$WORK/dz-ag/.antigravity/extensions/keyacrosslaud.auto-loop-for-antigravity-0.4.1"
dzrun "$WORK/dz-ag" | tr -s ' \n' '  ' > "$WORK/dz-ag.txt"
has    "Antigravity IDE's extension folder is read, as an Open VSX editor's" '~/\.antigravity-ide/extensions/mswincx\.antigravity-cockpit-1\.2\.0-universal mswincx\.antigravity-cockpit 1\.2\.0 \(GlassWorm extensions, March 2026\), installed' "$WORK/dz-ag.txt"
has    "and the earlier Antigravity's folder too"     '~/\.antigravity/extensions/keyacrosslaud\.auto-loop-for-antigravity-0\.4\.1 keyacrosslaud\.auto-loop-for-antigravity 0\.4\.1 \(GlassWorm sleeper extensions, April 2026\), installed' "$WORK/dz-ag.txt"
# Microsoft's list of extensions removed from the Marketplace: a GlassWorm theme it removed as malware and
# an extension it removed as impersonation are looked for in VS Code's own folder too. Open VSX removed
# every oorzc.ssh-tools version, so any of them in an Open VSX editor's folder counts. And a theme of the
# October cluster that Microsoft removed as malware.
rm -rf "$WORK/dz-ms"; cp -R "$WORK/clean" "$WORK/dz-ms"
mkdir -p "$WORK/dz-ms/.vscode/extensions/lavender-studio.theme-lavender-dreams-1.0.2" "$WORK/dz-ms/.vscode/extensions/kwitch-studio.auto-run-command-extension-1.4.0" \
  "$WORK/dz-ms/.cursor/extensions/oorzc.ssh-tools-0.5.2" "$WORK/dz-ms/.cursor/extensions/holiday-themes.theme-coca-cola-christmas-1.0.2"
dzrun "$WORK/dz-ms" | tr -s ' \n' '  ' > "$WORK/dz-ms.txt"
has    "a theme Microsoft removed from its Marketplace as malware, in VS Code's own folder" '~/\.vscode/extensions/lavender-studio\.theme-lavender-dreams-1\.0\.2 lavender-studio\.theme-lavender-dreams 1\.0\.2 \(GlassWorm extensions, March 2026\), installed' "$WORK/dz-ms.txt"
has    "one it removed as impersonation, in VS Code's own folder too" '~/\.vscode/extensions/kwitch-studio\.auto-run-command-extension-1\.4\.0 kwitch-studio\.auto-run-command-extension 1\.4\.0 \(GlassWorm extensions, March 2026\), installed' "$WORK/dz-ms.txt"
has    "any oorzc.ssh-tools version in an Open VSX editor's folder, as Open VSX removed them all" '~/\.cursor/extensions/oorzc\.ssh-tools-0\.5\.2 oorzc\.ssh-tools 0\.5\.2 \(GlassWorm extensions, January 2026\), installed' "$WORK/dz-ms.txt"
has    "a theme of the October cluster that Microsoft removed as malware" '~/\.cursor/extensions/holiday-themes\.theme-coca-cola-christmas-1\.0\.2 holiday-themes\.theme-coca-cola-christmas 1\.0\.2 \(GlassWorm-linked themes, October 2026\), installed' "$WORK/dz-ms.txt"
# microsoftvs.microsoftvs hid a Windows downloader (Socket): elsewhere it is a malicious extension to
# remove, not a compromised machine. Next to an extension whose malware could run here, both are listed.
rm -rf "$WORK/dz-os"; cp -R "$WORK/clean" "$WORK/dz-os"; mkdir -p "$WORK/dz-os/.vscode/extensions/microsoftvs.microsoftvs-1.0.2"
dzrun "$WORK/dz-os" | tr -s ' \n' '  ' > "$WORK/dz-os.txt"
dzrun "$WORK/dz-os" GIRD_CHECK_COMPACT=1 | tr -s ' \n' '  ' > "$WORK/dz-os-sum.txt"
has    "an extension whose malware runs on Windows only is one to remove elsewhere" 'Editor extensions a malicious extension to remove ~/\.vscode/extensions/microsoftvs\.microsoftvs-1\.0\.2 microsoftvs\.microsoftvs 1\.0\.2 \(GlassWorm-linked themes, October 2026\), installed Its malware runs on Windows only, so it did not run here\. Uninstall it\.' "$WORK/dz-os.txt"
hasnot "and is not a compromised machine there"     'ACT NOW|Treat this machine as compromised|signs of the malware found' "$WORK/dz-os.txt"
has    "with a fix to uninstall the extension"      'Uninstall the editor extensions listed in section 5\. Their malware could not run on this system\.' "$WORK/dz-os.txt"
has    "row 05 says an editor extension to remove"  'Recent leaks +an editor extension to remove, see section 5' "$WORK/dz-os-sum.txt"
has    "the link does not flag an extension hit"    '&nm=0&py=0&ex=0&wp=0' "$WORK/dz-os.txt"
# A tool's newest fix is what its row says to update to, with each hole its version has: Cursor between
# its two fixes, and Claude Code in the range of a sandbox escape, which the newest fix covers too.
rm -rf "$WORK/dz-old"; cp -R "$WORK/clean" "$WORK/dz-old"; mkdir -p "$WORK/dz-old/Applications/Cursor.app/Contents" "$WORK/dz-old/.npm-global/lib/node_modules/@anthropic-ai/claude-code"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>CFBundleShortVersionString</key>\n\t<string>3.0.5</string>\n</dict>\n</plist>\n' > "$WORK/dz-old/Applications/Cursor.app/Contents/Info.plist"
printf '{\n  "name": "@anthropic-ai/claude-code",\n  "version": "2.1.100"\n}\n' > "$WORK/dz-old/.npm-global/lib/node_modules/@anthropic-ai/claude-code/package.json"
dzrun "$WORK/dz-old" | tr -s ' \n' '  ' > "$WORK/dz-old.txt"
[ "$(uname -s)" = Darwin ] || SKIPPING="needs pwsh on macOS: Cursor's version is read from its app bundle"
has    "Cursor between two fixes is told the newest" '! Cursor 3\.0\.5, update to 3\.1\.2 or later An agent could replace the Python of a virtual environment to run commands outside the sandbox\. github\.com/cursor/cursor/security/advisories/GHSA-p9g2-cr55-cw9c' "$WORK/dz-old.txt"
hasnot "and not the hole its version already has the fix for" 'update to 3\.1\.2 or later A malicious agent' "$WORK/dz-old.txt"
SKIPPING=""
has    "Claude Code in a sandbox escape's range: its hole, the newest fix's, and that fix" '! Claude Code 2\.1\.100, update to 2\.1\.260 or later A malicious repository could run code outside the sandbox\. github\.com/advisories/GHSA-7835-87q9-rgvv A plugin repository could install code that bypasses its pinned hash\. github\.com/advisories/GHSA-pq7j-f95f-qfcv A stored API key could start sessions without the managed settings of an Enterprise or Team organization\. github\.com/anthropics/claude-code/security/advisories/GHSA-gfvf-j8jh-' "$WORK/dz-old.txt"
# The newest fix covers 2.0.68 and later: 2.1.259 has only its hole. Below 2.0.68 the highest fix of the
# lines a version falls under is 2.1.179, which that range covers, so the row names 2.1.260 there too.
for V in 2.1.259 2.0.67; do
  rm -rf "$WORK/dz-cc$V"; cp -R "$WORK/clean" "$WORK/dz-cc$V"; mkdir -p "$WORK/dz-cc$V/.npm-global/lib/node_modules/@anthropic-ai/claude-code"
  printf '{\n  "name": "@anthropic-ai/claude-code",\n  "version": "%s"\n}\n' "$V" > "$WORK/dz-cc$V/.npm-global/lib/node_modules/@anthropic-ai/claude-code/package.json"
  dzrun "$WORK/dz-cc$V" | tr -s ' \n' '  ' > "$WORK/dz-cc$V.txt"
done
has    "Claude Code past 2.1.179 is told the newest fix, with its hole" '! Claude Code 2\.1\.259, update to 2\.1\.260 or later A stored API key could start sessions without the managed settings of an Enterprise or Team organization\. github\.com/anthropics/claude-code/security/advisories/GHSA-gfvf-j8jh-' "$WORK/dz-cc2.1.259.txt"
has    "below the newest fix's range the row still names it, not 2.1.179, which has a hole of its own" '! Claude Code 2\.0\.67, update to 2\.1\.260 or later A plugin repository could install code that bypasses its pinned hash\. github\.com/advisories/GHSA-pq7j-f95f-qfcv' "$WORK/dz-cc2.0.67.txt"
hasnot "and it does not show the newest fix's hole, which that version does not have" 'A stored API key could start sessions' "$WORK/dz-cc2.0.67.txt"
mkdir -p "$WORK/dz-os/.cursor/extensions/oorzc.mind-map-1.0.61"
dzrun "$WORK/dz-os" | tr -s ' \n' '  ' > "$WORK/dz-os2.txt"
has    "next to malware that could run here, it is listed with why" 'Editor extensions signs of the malware found ~/\.cursor/extensions/oorzc\.mind-map-1\.0\.61 .*~/\.vscode/extensions/microsoftvs\.microsoftvs-1\.0\.2 microsoftvs\.microsoftvs 1\.0\.2 \(GlassWorm-linked themes, October 2026\), installed Its malware runs on Windows only, so it did not run here\. Uninstall it\.' "$WORK/dz-os2.txt"
hasnot "and the fix to uninstall it alone is not given then" 'Their malware could not run on this system' "$WORK/dz-os2.txt"
has    "summary row 02 names the link"                '02 . MCP servers .* 1 file links to your SSH' "$WORK/dz-hit-sum.txt"
has    "summary row 01 names the fixes to install"    '01 . Coding agents +[0-9]+ found, [34] security fixes to install' "$WORK/dz-hit-sum.txt"
D=$WORK/dz-miss-flat.txt
hasnot "near misses: no agent set to run without asking" 'Agents set to run commands without asking|run-without-asking' "$D"
hasnot "near misses: no version to update (fixed, below the range, unparseable, another package)" 'Tools with a security fix|that have a security fix' "$D"
hasnot "near misses: no link inside ~/.ssh, none to another file" 'link to your SSH logins|links to ~/\.ssh' "$D"
hasnot "a link to a repo's own .ssh/authorized_keys fixture is not this user's file" 'code/repo/sample' "$D"
hasnot "near misses: a clean or longer version, a longer name" 'GlassWorm|oorzc' "$D"
hasnot "the Marketplace build of oorzc.ssh-tools 0.5.1 in VS Code's own folder is not the bad build" 'oorzc\.ssh-tools 0\.5\.1' "$D"
hasnot "Codex: a profile written as an inline table is not the top level" '! Codex ' "$D"
hasnot "mcp-remote@0.1 in an MCP config is a range, not a version" 'mcp-remote 0\.1,|mcp-remote 0\.1 ' "$D"
hasnot "the old chat.tools.autoApprove in user settings is not reported: VS Code 1.104 and later ignore it" 'Code/User/settings\.json' "$D"
hasnot "a project's chat.tools.global.autoApprove is not reported: VS Code reads it from user settings only" 'p/global/' "$D"
# A link to an authorized_keys that does not exist yet still counts: an agent writing through it
# creates the file.
cp -R "$WORK/dz-hit" "$WORK/dz-dangle"; rm "$WORK/dz-dangle/.ssh/authorized_keys"
dzrun "$WORK/dz-dangle" | tr -s ' \n' '  ' > "$WORK/dz-dangle.txt"
has    "a link to an authorized_keys that does not exist yet still counts" 'Files that link to your SSH logins ✗ ~/code/links/notes\.txt' "$WORK/dz-dangle.txt"
# Every link that resolves to authorized_keys is listed, whatever its text: through ./ or //, through a
# linked folder, and in another case where the volume ignores it. A link to another file whose name
# ends the same way is not.
rm -rf "$WORK/ak"; cp -R "$WORK/clean" "$WORK/ak"; mkdir -p "$WORK/ak/.ssh" "$WORK/ak/code/a" "$WORK/ak/code/b" "$WORK/ak/code/c" "$WORK/ak/code/d" "$WORK/ak/code/e" "$WORK/ak/code/repo"
: > "$WORK/ak/.ssh/authorized_keys"; : > "$WORK/ak/.ssh/my_authorized_keys"
ln -s ../../.ssh/authorized_keys "$WORK/ak/code/a/plain.txt"; ln -s ../../.ssh/./authorized_keys "$WORK/ak/code/b/dot.txt"
ln -s ../../.ssh//authorized_keys "$WORK/ak/code/c/dslash.txt"; ln -s ../../.ssh "$WORK/ak/code/repo/sshdir"; ln -s sshdir/authorized_keys "$WORK/ak/code/repo/keys.txt"
ln -s ../../.SSH/Authorized_Keys "$WORK/ak/code/d/case.txt"; ln -s ../../.ssh/my_authorized_keys "$WORK/ak/code/e/other.txt"
dzrun "$WORK/ak" | tr -s ' \n' '  ' > "$WORK/ak.txt"
has    "a link to authorized_keys still counts"        '✗ ~/code/a/plain\.txt' "$WORK/ak.txt"
has    "a link through ./ counts"                     '✗ ~/code/b/dot\.txt' "$WORK/ak.txt"
has    "a link through // counts"                     '✗ ~/code/c/dslash\.txt' "$WORK/ak.txt"
has    "a link through a linked folder counts"        '✗ ~/code/repo/keys\.txt' "$WORK/ak.txt"
if [ -e "$WORK/ak/.SSH/AUTHORIZED_KEYS" ]; then has "a link in another case counts where the volume ignores case" '✗ ~/code/d/case\.txt' "$WORK/ak.txt"
else skip "a link in another case counts where the volume ignores case" "this volume tells case apart, so the link does not reach the file"; fi
hasnot "a link to another file named like it does not count" 'code/e/other\.txt' "$WORK/ak.txt"
# A settings file is read as one line (Flat-Text), so a setting inside a /* */ block comment is not
# at a boundary and is not read. Codex values in single quotes, TOML's literal strings, count as the
# same values in double quotes, alone or next to them. Known limit (docs/designs/dossier-checks.md,
# Not covered): a profile made the default with profile = "x", before Codex 0.134.0, is not read.
for L in 1 2 3; do rm -rf "$WORK/dz-lim$L"; cp -R "$WORK/clean" "$WORK/dz-lim$L"; mkdir -p "$WORK/dz-lim$L/AppData/Roaming/Code/User" "$WORK/dz-lim$L/.codex"; done
printf '{\n  /*\n  "chat.tools.global.autoApprove": true\n  */\n}\n' > "$WORK/dz-lim1/AppData/Roaming/Code/User/settings.json"
printf "approval_policy = 'never'\nsandbox_mode = 'danger-full-access'\n" > "$WORK/dz-lim1/.codex/config.toml"
printf 'profile = "yolo"\n[profiles.yolo]\napproval_policy = "never"\nsandbox_mode = "danger-full-access"\n' > "$WORK/dz-lim2/.codex/config.toml"
printf "approval_policy = 'never' # no prompts\nsandbox_mode = \"danger-full-access\"\n" > "$WORK/dz-lim3/.codex/config.toml"
for L in 1 2 3; do dzrun "$WORK/dz-lim$L" | tr -s ' \n' '  ' > "$WORK/dz-lim$L.txt"; done
hasnot "a setting in a /* */ block comment is not read" '! VS Code Copilot ' "$WORK/dz-lim1.txt"
has    "Codex values in single quotes, TOML's literal strings, are read" '! Codex ~/\.codex/config\.toml never asks, full access' "$WORK/dz-lim1.txt"
has    "a literal string and a basic one in one Codex file both count" '! Codex ~/\.codex/config\.toml never asks, full access' "$WORK/dz-lim3.txt"
hasnot "known limit: a profile made the default with profile = is not read" '! Codex ' "$WORK/dz-lim2.txt"
# Codex's permission profiles: default_permissions = ":danger-full-access" with approval_policy = "never"
# runs every command without asking and without a sandbox. Another profile, approvals left on, or the
# key under a [table] is not that.
for L in dfa dfal ws ask tbl; do rm -rf "$WORK/dz-cx-$L"; cp -R "$WORK/clean" "$WORK/dz-cx-$L"; mkdir -p "$WORK/dz-cx-$L/.codex"; done
printf 'approval_policy = "never"\ndefault_permissions = ":danger-full-access"\n' > "$WORK/dz-cx-dfa/.codex/config.toml"
printf "approval_policy = 'never'\ndefault_permissions = ':danger-full-access' # no sandbox\n" > "$WORK/dz-cx-dfal/.codex/config.toml"
printf 'approval_policy = "never"\ndefault_permissions = ":workspace"\n' > "$WORK/dz-cx-ws/.codex/config.toml"
printf 'approval_policy = "on-request"\ndefault_permissions = ":danger-full-access"\n' > "$WORK/dz-cx-ask/.codex/config.toml"
printf 'approval_policy = "never"\n[profiles.yolo]\ndefault_permissions = ":danger-full-access"\n' > "$WORK/dz-cx-tbl/.codex/config.toml"
for L in dfa dfal ws ask tbl; do dzrun "$WORK/dz-cx-$L" | tr -s ' \n' '  ' > "$WORK/dz-cx-$L.txt"; done
has    "Codex's full access profile with approvals off runs without asking" '! Codex ~/\.codex/config\.toml never asks, full access profile' "$WORK/dz-cx-dfa.txt"
has    "the full access profile in TOML's literal strings counts too" '! Codex ~/\.codex/config\.toml never asks, full access profile' "$WORK/dz-cx-dfal.txt"
hasnot "the workspace profile is not full access" '! Codex ~/\.codex/config\.toml never asks' "$WORK/dz-cx-ws.txt"
hasnot "the full access profile with approvals on is not reported" '! Codex ~/\.codex/config\.toml never asks' "$WORK/dz-cx-ask.txt"
hasnot "the full access profile under a [table] is not the top level" '! Codex ~/\.codex/config\.toml never asks' "$WORK/dz-cx-tbl.txt"
cp -R "$WORK/dz-miss" "$WORK/dz-calm"; rm -rf "$WORK/dz-calm/code/mr"
printf '{"permissions":{"defaultMode":"bypassPermissions"}}\n' > "$WORK/dz-calm/.claude/settings.json"
dzrun "$WORK/dz-calm" | tr -s ' \n' '  ' > "$WORK/dz-calm.txt"
has    "a one-line settings file is read too"         '! Claude Code ~/\.claude/settings\.json bypassPermissions' "$WORK/dz-calm.txt"
# Claude Code reads defaultMode only inside permissions: one at the top of the file, in an object inside
# permissions, or under a permissions key below the top is not the setting; one after rules with
# brackets in their strings is.
for L in top deep env rules; do rm -rf "$WORK/dz-dm-$L"; cp -R "$WORK/dz-calm" "$WORK/dz-dm-$L"; done
printf '{"defaultMode": "bypassPermissions", "permissions": {}}\n' > "$WORK/dz-dm-top/.claude/settings.json"
printf '{"permissions": {"x": {"defaultMode": "bypassPermissions"}}}\n' > "$WORK/dz-dm-deep/.claude/settings.json"
printf '{"env": {"permissions": {"defaultMode": "bypassPermissions"}}}\n' > "$WORK/dz-dm-env/.claude/settings.json"
printf '{\n  "permissions": {\n    "allow": ["Bash(find . -exec echo {} +)", "Read(src/[a]*)"],\n    "defaultMode": "bypassPermissions"\n  }\n}\n' > "$WORK/dz-dm-rules/.claude/settings.json"
for L in top deep env rules; do dzrun "$WORK/dz-dm-$L" | tr -s ' \n' '  ' > "$WORK/dz-dm-$L.txt"; done
hasnot "a defaultMode at the top of the file is not Claude Code's setting" '! Claude Code ~/\.claude/settings\.json' "$WORK/dz-dm-top.txt"
hasnot "nor one in an object inside permissions"  '! Claude Code ~/\.claude/settings\.json' "$WORK/dz-dm-deep.txt"
hasnot "nor one under a permissions key below the top" '! Claude Code ~/\.claude/settings\.json' "$WORK/dz-dm-env.txt"
has    "one after rules with brackets in their strings is" '! Claude Code ~/\.claude/settings\.json bypassPermissions' "$WORK/dz-dm-rules.txt"
# chat.permissions.default: autoApprove and autopilot run every tool call without asking.
# In the user settings the agent is set to run without asking; the default level and a commented line
# are not reported. The setting declares no scope, so a project's copy is in force too: section 2 lists
# it, as a setting a cloned project brings, and a project at the default level is not counted.
for L in pilot allow none proj; do rm -rf "$WORK/dz-perm-$L"; cp -R "$WORK/clean" "$WORK/dz-perm-$L"; mkdir -p "$WORK/dz-perm-$L/AppData/Roaming/Code/User"; done
printf '{\n  // "chat.permissions.default": "autoApprove",\n  "chat.permissions.default": "autopilot"\n}\n' > "$WORK/dz-perm-pilot/AppData/Roaming/Code/User/settings.json"
printf '{"chat.permissions.default": "autoApprove"}\n' > "$WORK/dz-perm-allow/AppData/Roaming/Code/User/settings.json"
printf '{\n  // "chat.permissions.default": "autoApprove",\n  "chat.permissions.default": "default"\n}\n' > "$WORK/dz-perm-none/AppData/Roaming/Code/User/settings.json"
mkdir -p "$WORK/dz-perm-proj/p/w/.vscode" "$WORK/dz-perm-proj/p/x/.vscode" "$WORK/dz-perm-proj/p/d/.vscode"; rm -f "$WORK/dz-perm-proj/.cursor/mcp.json"   # no MCP token, so row 02 shows the projects
printf '{"chat.permissions.default": "autoApprove"}\n' > "$WORK/dz-perm-proj/p/w/.vscode/settings.json"
printf '{\n  // "chat.permissions.default": "autoApprove",\n  "chat.permissions.default": "autopilot"\n}\n' > "$WORK/dz-perm-proj/p/x/.vscode/settings.json"
printf '{\n  // "chat.permissions.default": "autopilot",\n  "chat.permissions.default": "default"\n}\n' > "$WORK/dz-perm-proj/p/d/.vscode/settings.json"
for L in pilot allow none proj; do dzrun "$WORK/dz-perm-$L" | tr -s ' \n' '  ' > "$WORK/dz-perm-$L.txt"; done
dzrun "$WORK/dz-perm-proj" GIRD_CHECK_COMPACT=1 | tr -s ' \n' '  ' > "$WORK/dz-perm-proj-c.txt"
has    "VS Code set to start chats in Autopilot"      '! VS Code Copilot ~/AppData/Roaming/Code/User/settings\.json chat\.permissions\.default: autopilot' "$WORK/dz-perm-pilot.txt"
has    "VS Code set to start chats allowing all"      '! VS Code Copilot ~/AppData/Roaming/Code/User/settings\.json chat\.permissions\.default: autoApprove' "$WORK/dz-perm-allow.txt"
hasnot "the default level or a commented one is not reported" 'chat\.permissions\.default' "$WORK/dz-perm-none.txt"
has    "a project's chat.permissions.default: autoApprove is listed in section 2" '! ~/p/w/\.vscode/settings\.json Set to run every Copilot tool call without asking in new chats, with chat\.permissions\.default: autoApprove\.' "$WORK/dz-perm-proj.txt"
has    "and a project's autopilot"                    '! ~/p/x/\.vscode/settings\.json Set to run every Copilot tool call without asking in new chats, with chat\.permissions\.default: autopilot\.' "$WORK/dz-perm-proj.txt"
has    "a project at the default level is not counted: row 02 counts the other 2" '02 . MCP servers .*, 2 projects act on opening' "$WORK/dz-perm-proj-c.txt"
has    "and the fix says to read those settings before an editor opens the folder" 'Read the settings marked in section 2 before an agent or editor opens those folders' "$WORK/dz-perm-proj.txt"
# gird-check.sh, on the same home with its Mac paths, must find the same things in the same order.
rm -rf "$WORK/dz-b"; bash tests/make-fixture.sh "$WORK/dz-b" "$WORK/keys-dz.txt" clean > /dev/null
if [ "$(uname -s)" = Darwin ]; then DAS="Library/Application Support"; else DAS=".config"; fi
bash tests/make-dossier.sh "$WORK/dz-b" "$WORK/dz-b/$DAS" hit
HOME="$WORK/dz-b" PATH=/usr/bin:/bin bash "$BASH_SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/dz-b-flat.txt"
dz_blocks() { grep -aoE 'Agents set to run commands without asking.*02 MCP SERVERS|Files that link to your SSH logins.*03 KEYS IN PLAIN TEXT' "$1" | sed -E 's#~/(Library/Application Support|\.config|AppData/Roaming)/Code#~/AS/Code#g'; }
if [ -n "$(dz_blocks "$WORK/dz-hit-flat.txt")" ] && [ "$(dz_blocks "$WORK/dz-hit-flat.txt")" = "$(dz_blocks "$WORK/dz-b-flat.txt")" ]; then ok "sections 1 and 2 read the same as gird-check.sh's"
else bad "sections 1 and 2 read the same as gird-check.sh's"; diff <(dz_blocks "$WORK/dz-b-flat.txt" | tr '!' '\n') <(dz_blocks "$WORK/dz-hit-flat.txt" | tr '!' '\n') | head -n 6; fi

echo "a new incident of each kind is data lines only"
# tests/made-up.sh appends a made-up platform, startup file, wiper file, planted file and Python
# package to a copy's data files and runs gen.sh there; it fails if any code changed.
if bash tests/made-up.sh "$WORK/mu" "$WORK/clean" "$WORK/mu-home" 2> "$WORK/mu-err.txt"; then ok "made-up incidents need only data lines and gen.sh"
else bad "made-up incidents need only data lines and gen.sh"; sed 's/^/        /' "$WORK/mu-err.txt"; fi
mups() { # home out [compact]
  env -i PATH="$WORK/bin" HOME="$WORK/pshome" USERPROFILE="$1" APPDATA="$1/AppData/Roaming" LOCALAPPDATA="$1/AppData/Local" \
    TEMP="$1/AppData/Local/Temp" LANG=en_US.UTF-8 ${3:+GIRD_CHECK_COMPACT=1} \
    "$PWSH" -NoProfile -NonInteractive -File "$WORK/mu/gird-check.ps1" -Offline 2>&1 | tr -s ' \n' '  ' > "$2"
}
mups "$WORK/mu-home" "$WORK/mu.txt"
has    "made-up platform: its row and advice"         'Madeplat +CLI found Madeplat asked customers to rotate stored secrets\.' "$WORK/mu.txt"
has    "made-up platform: named in the shared fix"    'If you used .*Made Platform, rotate the keys stored there' "$WORK/mu.txt"
has    "made-up platform: section 5 counts its row"   'RECENT KEY LEAKS +10 checked' "$WORK/mu.txt"
has    "made-up startup file and its note"            '~/\.config/madeworm/boot\.cjs starts the Made worm at login' "$WORK/mu.txt"
has    "a new gh-token-monitor file is a waiting wiper" 'a wiper is waiting ~/\.config/gh-token-monitor-made ' "$WORK/mu.txt"
has    "made-up npm incident: its sourced line"       'Made npm worm, October 2026: a made-up npm worm for the tests\. example\.com' "$WORK/mu.txt"
has    "made-up update-level npm incident: its line"  'Made npm slip, October 2026: a made-up npm version whose malware could not run\. example\.com' "$WORK/mu.txt"
has    "made-up Python package: the link flags it"    '&ll=0&.*&py=1&' "$WORK/mu.txt"
has    "made-up planted file and its note"            '~/code/made/\.vscode/madeplant\.js a file the Made worm plants' "$WORK/mu.txt"
has    "a hook that runs it, with the general note"   '~/code/made/\.claude/settings\.json runs a file a worm plants' "$WORK/mu.txt"
has    "a made-up planted file with its published SHA-256 counts on its own" '~/code/made/hash/\.claude/madeboot\.mjs a file the Made worm plants' "$WORK/mu.txt"
has    "and the same name with other contents is a file to read" '! ~/code/made/plain/\.claude/madeboot\.mjs Named like a file the Made worm plants, with nothing else of theirs beside it' "$WORK/mu.txt"
has    "made-up Python package: its own row"          'Madepkg 9\.9\.9 +signs of the malware found ~/code/venv/lib/site-packages: madepkg 9\.9\.9, madepy_boot\.pth ~/AppData/Local/Temp/\.madepy_1 ' "$WORK/mu.txt"
has    "made-up Python package: its advisory"         'Advisory: example\.com/madepy/advisory' "$WORK/mu.txt"
has    "made-up Python package: in uv's cache"        'uv cache holds the 9\.9\.9 package\. Clear it with: uv cache clean madepkg' "$WORK/mu.txt"
has    "made-up Python package: its fix"              "follow Madepkg's advisory" "$WORK/mu.txt"
hasnot "LiteLLM is not blamed for it"                 'LITELLM 1\.107\.0 MALWARE|signs of the LiteLLM malware' "$WORK/mu.txt"
cp -R "$WORK/mu-home" "$WORK/mu-py"; rm -rf "$WORK/mu-py/.config/gh-token-monitor-made" "$WORK/mu-py/.config/madeworm" "$WORK/mu-py/code/made" "$WORK/mu-py/.madeplat.json" "$WORK/mu-py/.vscode/extensions/made.ext-1.0.0" "$WORK/mu-py/.cursor/extensions/made.winext-2.0.0"
mups "$WORK/mu-py" "$WORK/mu-py.txt" compact
has    "made-up Python package leads the summary"     'ACT NOW: SIGNS OF THE MADEPKG 9\.9\.9 MALWARE' "$WORK/mu-py.txt"
has    "and row 05 names it"                          'signs of the Madepkg malware\. Act now' "$WORK/mu-py.txt"
rm -rf "$WORK/mu-plat"; cp -R "$WORK/clean" "$WORK/mu-plat"; rm -rf "$WORK/mu-plat/.config/opencode" "$WORK/mu-plat/.railway"
mups "$WORK/mu-plat" "$WORK/mu-none.txt" compact
# The summary row is cut at 80 columns, so only its start is checked.
has    "a clean home: row 05 counts the made-up ones" 'none of the 10 recent leaks or malware it checks' "$WORK/mu-none.txt"
mkdir -p "$WORK/mu-plat/.config/madeplat"
mups "$WORK/mu-plat" "$WORK/mu-plat.txt" compact
has    "a made-up platform alone gives its summary"   'Madeplat CLI found: rotate secrets stored there' "$WORK/mu-plat.txt"
rm -rf "$WORK/mu-upd"; cp -R "$WORK/clean" "$WORK/mu-upd"; mkdir -p "$WORK/mu-upd/code/u"
printf '{"lockfileVersion":3,"packages":{"node_modules/made-upd-pkg":{"version":"4.5.6","resolved":"https://registry.npmjs.org/made-upd-pkg/-/made-upd-pkg-4.5.6.tgz"}}}\n' > "$WORK/mu-upd/code/u/package-lock.json"
mups "$WORK/mu-upd" "$WORK/mu-upd.txt"
has    "a made-up update-level hit is a version to update" 'npm malware a bad version to update' "$WORK/mu-upd.txt"
hasnot "and not a compromised machine"                'ACT NOW|Treat this machine as compromised' "$WORK/mu-upd.txt"
rm -rf "$WORK/mu-act"; cp -R "$WORK/clean" "$WORK/mu-act"; mkdir -p "$WORK/mu-act/code/a"
printf '{"lockfileVersion":3,"packages":{"node_modules/made-npm-pkg":{"version":"1.2.3","resolved":"https://registry.npmjs.org/made-npm-pkg/-/made-npm-pkg-1.2.3.tgz"}}}\n' > "$WORK/mu-act/code/a/package-lock.json"
mkdir -p "$WORK/mu-act/code/a/node_modules/made-npm-pkg"; printf '{"name":"made-npm-pkg","version":"1.2.3"}\n' > "$WORK/mu-act/code/a/node_modules/made-npm-pkg/package.json"
mups "$WORK/mu-act" "$WORK/mu-act.txt"
has    "a made-up act-level npm hit alone: compromised" 'Treat this machine as compromised\. Delete the packages and files listed in section 5' "$WORK/mu-act.txt"
has    "and the link says npm malware"                '&nm=1&py=0&ex=0&wp=0' "$WORK/mu-act.txt"
has    "made-up agent set to run without asking"      '! Made Agent ~/\.madeagent/config\.json madeMode' "$WORK/mu.txt"
has    "made-up tool with a security fix"             '! Made Tool 1\.5\.0, update to 3\.0\.0 or later A made-up hole for the tests\. example\.com/madetool A second made-up hole\. example\.com/madetool2' "$WORK/mu.txt"
has    "made-up extension that shipped malware"       '~/\.vscode/extensions/made\.ext-1\.0\.0 made\.ext 1\.0\.0 \(Made extension, October 2026\), installed' "$WORK/mu.txt"
has    "a made-up extension whose malware runs on Windows only is one to remove here" '~/\.cursor/extensions/made\.winext-2\.0\.0 made\.winext 2\.0\.0 \(Made extension, October 2026\), installed Its malware runs on Windows only, so it did not run here\. Uninstall it\.' "$WORK/mu.txt"
# A Python incident's temp file alone: stop and delete, not "don't run Python".
rm -rf "$WORK/mu-tmp"; cp -R "$WORK/clean" "$WORK/mu-tmp"; mkdir -p "$WORK/mu-tmp/AppData/Local/Temp"; : > "$WORK/mu-tmp/AppData/Local/Temp/.madepy_1"
mups "$WORK/mu-tmp" "$WORK/mu-tmp.txt"
has    "a temp file alone: the incident's own advice, in section 5" 'Stop any process started from these files, then delete them\. Advisory: example\.com' "$WORK/mu-tmp.txt"
has    "and in the fix"                               "Stop any process started from the files listed in section 5, delete them, follow Madepkg's advisory" "$WORK/mu-tmp.txt"
hasnot "no environment to stop running Python in"    "Don't run Python" "$WORK/mu-tmp.txt"

echo "MCP configs in plugin folders"
cp -R "$WORK/clean" "$WORK/mcp-pl"
mkdir -p "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a" "$WORK/mcp-pl/.claude/plugins/synced/b"
printf '{"mcpServers":{"one":{"command":"x"},"two":{"command":"y"}}}\n' > "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a/.mcp.json"
printf '{"mcpServers":{"three":{"command":"z"}}}\n' > "$WORK/mcp-pl/.claude/plugins/synced/b/.mcp.json"
psrun "$WORK/clean" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-base.txt"
psrun "$WORK/mcp-pl" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-pl.txt"
psrun "$WORK/mcp-pl" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-pl-full.txt"
BASE=$(grep -aoE '02 . MCP servers +[0-9]+ servers' "$WORK/mcp-base.txt" | grep -aoE '[0-9]+ servers')
if [ -n "$BASE" ]; then ok "the baseline has a server count" "$BASE"; else bad "the baseline has a server count"; fi
has    "plugin-folder servers are counted apart" "02 . MCP servers +$BASE, 3 more in plugin folders" "$WORK/mcp-pl.txt"
hasnot "the baseline mentions no plugin folders" 'plugin folders' "$WORK/mcp-base.txt"
has    "the details total only the servers set up" "MCP SERVERS +$BASE " "$WORK/mcp-pl-full.txt"
has    "the details give one plugin-folders line" 'Plugin folders +3 servers in 2 files, not counted above' "$WORK/mcp-pl-full.txt"
hasnot "plugin-folder files are not listed one by one" 'plugins/a/\.mcp\.json' "$WORK/mcp-pl-full.txt"
cp -R "$WORK/mcp-pl" "$WORK/mcp-tok"; KEY1=$(head -n 1 "$WORK/keys.txt")
printf '{"mcpServers":{"t":{"command":"x","env":{"ANTHROPIC_API_KEY":"%s"}}}}\n' "$KEY1" > "$WORK/mcp-tok/.claude/plugins/synced/b/.mcp.json"
psrun "$WORK/mcp-tok" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-tok.txt"
has    "a token in a plugin-folder config is still flagged" 'plugins/synced/b/\.mcp\.json.*token in the file' "$WORK/mcp-tok.txt"
has    "and it still counts as a thing to fix"             'Replace tokens written into MCP configs' "$WORK/mcp-tok.txt"
rm -rf "$WORK/mcp-only"; mkdir -p "$WORK/mcp-only/.codex/.tmp/plugins/plugins/a"
cp "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a/.mcp.json" "$WORK/mcp-only/.codex/.tmp/plugins/plugins/a/.mcp.json"
psrun "$WORK/mcp-only" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-only.txt"
has    "with only plugin-folder configs the row says none set up" '02 . MCP servers +none set up, 2 in plugin folders' "$WORK/mcp-only.txt"

echo "files built to make a pattern backtrack"
# Long runs of capitals and of KEY, with and without the = or quote a match needs,
# next to a real key. gird-check.sh's patterns, run as they are in .NET, took
# seconds to forever on these.
mkdir -p "$WORK/slow/code/s/.claude" "$WORK/slow/AppData/Local/Temp"
python3 - "$WORK/slow/code/s" "$(sed -n 5p "$WORK/keys.txt")" <<'PY2'
import sys
d, key = sys.argv[1], sys.argv[2]
k = 'KEY' * 7000; a = 'A' * 20000
lines = [a, k, '"' + k, k + ' = "abc', '_' * 5000 + 'A' + k, 'GROQ_API_KEY=' + key]
open(d + '/.env', 'w').write('\n'.join(lines) + '\n')
open(d + '/.claude/settings.local.json', 'w').write('{"permissions":{"allow":["Bash(' + a + k + ')"]}}\n')
open(d + '/.mcp.json', 'w').write('{"mcpServers":{"x":{"command":"' + k + '"}}, "' + k + '": "' + a + '\n')
PY2
T0=$(date +%s)
psrun "$WORK/slow" -- -Offline > "$WORK/slow.txt" 2>&1
T=$(( $(date +%s) - T0 ))
if [ "$T" -le 20 ]; then ok "it finishes quickly" "${T}s"; else bad "it finishes quickly" "took ${T}s"; fi
hasnot "no file is skipped"                    'skipped: took too long' "$WORK/slow.txt"
has    "the real key next to them is found"    '~/code/s/\.env +Groq' "$WORK/slow.txt"
# With a limit too short for a large file, the file is listed, not taken as clean.
python3 -c "import sys; open(sys.argv[1], 'w').write(('sk-' + 'a' * 40 + ' ') * 150000)" "$WORK/slow/code/s/.env.big"
mkdir -p "$WORK/slow/.npm/_cacache/index-v5/aa"
python3 -c "import sys; open(sys.argv[1], 'w').write('pkg-name@1.2.3 /pkg-name/-/pkg-name-1.2.3.tgz ' * 200000)" "$WORK/slow/.npm/_cacache/index-v5/aa/big"
psrun "$WORK/slow" GIRD_CHECK_REGEX_TIMEOUT_MS=1 -- -Offline > "$WORK/slow-to.txt" 2>&1
psrun "$WORK/slow" GIRD_CHECK_REGEX_TIMEOUT_MS=1 GIRD_CHECK_COMPACT=1 -- -Offline > "$WORK/slow-to-c.txt" 2>&1
has    "a file that hits the time limit is listed" '[0-9]+ files? skipped: took too long to check' "$WORK/slow-to.txt"
has    "with its path"                         '^ +~/code/s/\.env\.big$' "$WORK/slow-to.txt"
has    "and the summary says so"               'skipped: took too long to check, like' "$WORK/slow-to-c.txt"
has    "npm's cache that hits the limit is not called clean" 'npm malware +not fully checked: 1 file took too long' "$WORK/slow-to.txt"
has    "and the summary row is not green"      'Recent leaks +npm packages not fully checked' "$WORK/slow-to-c.txt"
cp -R "$WORK/clean" "$WORK/pyc"
SP="$WORK/pyc/code/winpy/.venv/Lib/site-packages"; mkdir -p "$SP/__pycache__"; printf 'home = C:\\Python312\n' > "$WORK/pyc/code/winpy/.venv/pyvenv.cfg"
: > "$SP/__pycache__/cook.cpython-312.pyc"
psrun "$WORK/pyc" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/pyc.txt"
psrun "$WORK/pyc" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/pyc-full.txt"
has    "and row 05 asks to check it"           'possible LiteLLM leftover: check cook\.pyc' "$WORK/pyc.txt"
has    "a leftover cook.pyc is listed as a possible leftover" 'possible leftover ~/code/winpy/\.venv/Lib/site-packages: cook\.pyc' "$WORK/pyc-full.txt"
hasnot "but it is not an act-now hit"          'Act now|ACT NOW' "$WORK/pyc-full.txt"
cp -R "$WORK/pyc" "$WORK/pyc-oc"; mkdir -p "$WORK/pyc-oc/.config/opencode"
psrun "$WORK/pyc-oc" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/pyc-oc.txt"
has    "a weak pyc and OpenCode both show in the details"  'possible leftover.*OpenCode +installed' "$WORK/pyc-oc.txt"
has    "OpenCode's line says only the users it emailed were affected" 'OpenCode +installed OpenCode emailed the Console users its breach hit, and says those it did not email were not affected\. If you got that email, rotate every provider key you saved in the Console\. Keys kept only in the CLI never reach OpenCode\.' "$WORK/pyc-oc.txt"
has    "a weak pyc shows in row 05 and the fix list"       'A leftover cook\.pyc can come from the LiteLLM 1\.107\.0 malware' "$WORK/pyc-oc.txt"
printf 'import cook\n' > "$SP/cook.pth"
psrun "$WORK/pyc" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/pth.txt"
has    "cook.pth next to the pyc is an act-now hit" 'signs of the LiteLLM malware\. Act now' "$WORK/pth.txt"
rm -rf "$WORK/conda"; cp -R "$WORK/clean" "$WORK/conda"
mkdir -p "$WORK/conda/tools/miniconda3/Lib/site-packages/litellm-1.107.0.dist-info"
psrun "$WORK/conda" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/conda.txt"
has    "LiteLLM 1.107.0 in a conda install outside the usual places is found" 'signs of the LiteLLM malware\. Act now' "$WORK/conda.txt"
cp -R "$WORK/clean" "$WORK/inst"; mkdir -p "$WORK/inst/AppData/Local/Programs/Python/Python312/Lib/site-packages/litellm-1.107.0.dist-info"
psrun "$WORK/inst" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/inst.txt"
has    "finds 1.107.0 in the python.org install folder" 'signs of the LiteLLM malware\. Act now' "$WORK/inst.txt"
# A LiteLLM marker alone: the row carries LiteLLM's own advice (data/indicators.tsv), not the environment one.
cp -R "$WORK/clean" "$WORK/mark"; : > "$WORK/mark/AppData/Local/Temp/.pc_once_1"
psrun "$WORK/mark" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mark.txt"
has    "finds a malware marker in TEMP"        'LiteLLM 1\.107\.0 +signs of the malware found ~/AppData/Local/Temp/\.pc_once_1' "$WORK/mark.txt"
has    "with LiteLLM's own advice"             'These files mean the malware ran here, and a \.pc_once_ file that it sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader\.lock\. Don.t run Python or pip in the environment that had litellm 1\.107\.0 until cook\.pth, cook\.py, sitecustomize\.py and their compiled copies in __pycache__ are deleted from it\. Advisory: docs\.litellm\.ai' "$WORK/mark.txt"
hasnot "a marker alone names no environment to stop" "Don't run Python or pip in these environments" "$WORK/mark.txt"
# Another user's file in the shared temp folder is not this person's sign: a link to a root-owned file stands in for one.
cp -R "$WORK/clean" "$WORK/lmo"; ln -s /etc/passwd "$WORK/lmo/AppData/Local/Temp/.pc_once_1"
psrun "$WORK/lmo" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/lmo.txt"
has    "a temp file owned by someone else is not this person's hit" 'LiteLLM 1\.107\.0 +no signs' "$WORK/lmo.txt"
hasnot "and the file is not listed"            'pc_once' "$WORK/lmo.txt"
# Nor is a file of this person's put under a marker's name by a link, hard or symbolic: in a shared
# temp folder anyone can make one.
cp -R "$WORK/clean" "$WORK/lmh"; : > "$WORK/lmh/notes.txt"; ln "$WORK/lmh/notes.txt" "$WORK/lmh/AppData/Local/Temp/.pc_once_1"
psrun "$WORK/lmh" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/lmh.txt"
has    "a hard link to this person's own file under a marker's name is not a hit" 'LiteLLM 1\.107\.0 +no signs' "$WORK/lmh.txt"
cp -R "$WORK/clean" "$WORK/lms"; : > "$WORK/lms/notes.txt"; ln -s "$WORK/lms/notes.txt" "$WORK/lms/AppData/Local/Temp/.pc_once_1"
psrun "$WORK/lms" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/lms.txt"
has    "nor a symbolic link to it" 'LiteLLM 1\.107\.0 +no signs' "$WORK/lms.txt"

echo "saving the report"
mkdir -p "$WORK/cwd"
(cd "$WORK/cwd" && psrun "$WORK/home" -- -Offline -Save > "$WORK/save.txt" 2>&1)
SAVED=$(find "$WORK/cwd" -name 'gird-ai-key-check-*.txt' | head -n 1)
if [ -n "$SAVED" ]; then ok "-Save writes a report"; else bad "-Save writes a report"; fi
if [ -n "$SAVED" ] && [ -n "$(find "$SAVED" -perm 600)" ]; then ok "the report is readable only by you"; else bad "the report is readable only by you"; fi
if [ -n "$SAVED" ] && grep -q 'KEYS IN PLAIN TEXT' "$SAVED"; then ok "the report has every detail"; else bad "the report has every detail"; fi
if [ -n "$SAVED" ] && ! grep -aqF -f "$WORK/keys.txt" "$SAVED"; then ok "the saved report holds no planted key"; else bad "the saved report holds no planted key"; fi
# PowerShell before 7.3 has no UnixCreateMode; the test switch takes the path it uses.
mkdir -p "$WORK/cwd72"
(cd "$WORK/cwd72" && psrun "$WORK/home" GIRD_CHECK_TEST_NO_UNIXMODE=1 -- -Offline -Save > /dev/null 2>&1)
SAVED=$(find "$WORK/cwd72" -name 'gird-ai-key-check-*.txt' | head -n 1)
if [ -n "$SAVED" ] && [ -n "$(find "$SAVED" -perm 600)" ] && grep -q 'KEYS IN PLAIN TEXT' "$SAVED"; then ok "before PowerShell 7.3 the report is readable only by you too"
else bad "before PowerShell 7.3 the report is readable only by you too"; fi

echo "shared counts and how you compare"
printf '%s' '{"devices":1234,"runs":2345,"devices_7d":456,"key_files":3412,"agents":5678,"clean":0.31}' > "$WORK/stats.json"
printf '%s' '{"p":72,"n":1234,"r":142}' > "$WORK/reply.json"
python3 - "$WORK/received.log" "$WORK/gets.log" "$WORK/port" "$WORK/stats.json" "$WORK/reply.json" <<'PY' &
import http.server, sys
log, gets, portfile, stats, reply = sys.argv[1:6]
class H(http.server.BaseHTTPRequestHandler):
    def reply(self, code, body=b''):
        self.send_response(code)
        if body:
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if body: self.wfile.write(body)
    def do_POST(self):
        n = int(self.headers.get('content-length') or 0)
        body = self.rfile.read(n)
        with open(log, 'ab') as f: f.write(body + b'\n')
        if b'"kind":"report"' in body: self.reply(200, open(reply, 'rb').read())
        else: self.reply(204)
    def do_GET(self):
        with open(gets, 'ab') as f: f.write(self.path.encode() + b'\n')
        if self.path.endswith('/stats'): self.reply(200, open(stats, 'rb').read())
        else: self.reply(404)
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
with open(portfile, 'w') as f: f.write(str(srv.server_address[1]))
srv.serve_forever()
PY
MOCK_PID=$!
i=0; while [ ! -s "$WORK/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
API="http://127.0.0.1:$(cat "$WORK/port")/api/check"
: > "$WORK/received.log"; : > "$WORK/gets.log"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- -Offline > /dev/null 2>&1
psrun "$WORK/home" GIRD_CHECK_API="$API" DO_NOT_TRACK=1 -- > /dev/null 2>&1
if [ ! -s "$WORK/received.log" ]; then ok "-Offline and DO_NOT_TRACK=1 send nothing"; else bad "-Offline and DO_NOT_TRACK=1 send nothing"; fi
if [ ! -s "$WORK/gets.log" ]; then ok "-Offline and DO_NOT_TRACK=1 ask for nothing"; else bad "-Offline and DO_NOT_TRACK=1 ask for nothing"; fi
GUID=1b3e5f7a-2c4d-4e6f-8a9b-0c1d2e3f4a5b
OUT=$WORK/online.txt
psrun "$WORK/home" GIRD_CHECK_API="$API" GIRD_CHECK_TEST_MACHINEGUID="$GUID" WT_SESSION=x -- > "$OUT" 2>&1
if [ "$(grep -c . "$WORK/received.log")" -eq 1 ]; then ok "a normal run sends one report"; else bad "a normal run sends one report"; fi
if [ "$(grep -c . "$WORK/gets.log")" -eq 1 ] && grep -q '/api/check/stats$' "$WORK/gets.log"; then ok "a normal run asks for the totals once"; else bad "a normal run asks for the totals once"; fi
head -n 1 "$WORK/received.log" > "$WORK/report-ps.json"
WANT=$(printf 'gird-check-v1:%s' "$GUID" | shasum -a 256 | cut -c1-64)
has    "device_id is SHA-256 of gird-check-v1: and the MachineGuid" "\"device_id\":\"$WANT\"" "$WORK/report-ps.json"
has    "terminal is windows-terminal when WT_SESSION is set" '"terminal":"windows-terminal"' "$WORK/report-ps.json"
has    "shell is pwsh under PowerShell 7"      '"shell":"pwsh"' "$WORK/report-ps.json"
hasnot "the report holds no path"              '/(Users|home|private|tmp|var)/|~/|AppData' "$WORK/report-ps.json"
nokeys "the report holds no planted key" "$WORK/keys.txt" "$WORK/report-ps.json"
has    "shows one real total under the banner" '(1,234 AI builders have run Blindspot|456 AI builders ran it this week|Blindspot has found 3,412 files with AI keys in plain text so far|31% of AI builders had no keys in plain text)' "$OUT"
hasi   "shows how this machine compares"       'better than 72% of AI builders who ran Blindspot' "$OUT"
hasnot "the percentile line carries no count"  'of 1,234 AI builders' "$OUT"
if python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1]) if l.strip()]' "$WORK/received.log" 2>/dev/null; then ok "the report is valid JSON"; else bad "the report is valid JSON"; fi
has    "the device ID is a 64-character hash or empty" '"device_id":"([0-9a-f]{64})?"' "$WORK/report-ps.json"
if grep -aqF "\"$(id -un)\"" "$WORK/received.log"; then bad "the report holds no username"; else ok "the report holds no username"; fi
RID=$(grep -oE '"run_id":"[0-9a-f]{16}"' "$WORK/report-ps.json" | cut -d'"' -f4)
has    "the result link carries the percentile" 'blindspot/card/#v=2&s=[0-9]+&g=[ABCDF]&.*&pc=72&pn=1234' "$OUT"
has    "the link carries the report's run ID, the rank and key counts" "blindspot/card/#v=2&.*&u=${RID:-no-run-id}&r=142&sk=2&hk=2&ag=[a-z0-9.-]*&nm=[01]&py=[01]&ex=[01]&wp=[01]\$" "$OUT"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > /dev/null 2>&1
if grep -q '"device_id":""' "$(printf '%s' "$WORK/received.log")" && [ "$(grep -c . "$WORK/received.log")" -eq 2 ]; then ok "with no MachineGuid the device ID is empty"; else bad "with no MachineGuid the device ID is empty"; fi
psrun "$WORK/clean" GIRD_CHECK_API="$API" -- > "$WORK/clean-online.txt" 2>&1
has    "leads with the percentile when nothing is urgent" 'BETTER THAN 72% OF AI BUILDERS WHO RAN BLINDSPOT' "$WORK/clean-online.txt"
PROUD="^  ★ You're one of the first 1,000 AI builders to run Blindspot\."
cp "$WORK/stats.json" "$WORK/stats-0.json"
printf '%s' '{"devices":1234567,"devices_7d":10,"key_files":20,"clean":0}' > "$WORK/stats.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/online-big.txt" 2>&1
has    "the total gets thousands separators"  '★ 1,234,567 AI builders have run Blindspot\.' "$WORK/online-big.txt"
has    "the full report shows the rank"       "$PROUD" "$WORK/online-big.txt"
psrun "$WORK/home" GIRD_CHECK_API="$API" GIRD_CHECK_COMPACT=1 -- > "$WORK/compact-online.txt" 2>&1
has    "the summary shows the rank"           "$PROUD" "$WORK/compact-online.txt"
printf '%s' '{"p":72,"n":1234}' > "$WORK/reply.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/no-rank.txt" 2>&1
hasnot "the place in line is never shown"     "AI builder #|#142" "$WORK/no-rank.txt"
has    "a reply without r leaves r empty in the link" '&pn=1234&u=[0-9a-f]{16}&r=&sk=2' "$WORK/no-rank.txt"
SHOWN=""
for R in null 0 '"142"' 14.2 0142 1234567890; do
  printf '{"p":72,"n":1234,"r":%s}' "$R" > "$WORK/reply.json"
  psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/bad-rank.txt" 2>&1
  if grep -aqE '&r=[^&]' "$WORK/bad-rank.txt"; then SHOWN="$SHOWN $R"; fi
done
if [ -z "$SHOWN" ]; then ok "a rank that isn't a whole number from 1 shows nothing"; else bad "a rank that isn't a whole number from 1 shows nothing"; printf '        shown for:%s\n' "$SHOWN"; fi
printf '%s' '{"p":72,"n":1234,"r":1000}' > "$WORK/reply.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/rank-1000.txt" 2>&1
has    "rank 1000 is one of the first 1,000"  "★ You're one of the first 1,000 AI builders to run Blindspot\." "$WORK/rank-1000.txt"
printf '%s' '{"p":72,"n":1234,"r":1001}' > "$WORK/reply.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/rank-1001.txt" 2>&1
hasnot "rank 1001 shows no early line"        "first 1,000" "$WORK/rank-1001.txt"
hasnot "rank 1001 never shows the number"     "1,001|AI builder #" "$WORK/rank-1001.txt"
has    "rank 1001 goes in the result link"    '&r=1001&' "$WORK/rank-1001.txt"
hasnot "rank 1000 never shows the number"     "AI builder #|#1,000" "$WORK/rank-1000.txt"
printf '%s' '{"p":72,"n":1234,"r":142}' > "$WORK/reply.json"
printf '%s' '{"devices":999,"devices_7d":120,"key_files":300,"clean":0.4}' > "$WORK/stats.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/early.txt" 2>&1
has    "under 1,000 the early line sits above the header" "^  ★ You're one of the first 1,000 AI builders to run Blindspot\." "$WORK/early.txt"
if [ "$(grep -c 'first 1,000' "$WORK/early.txt")" -eq 1 ]; then ok "under 1,000 the first 1,000 are named once"; else bad "under 1,000 the first 1,000 are named once"; fi
if grep -aA2 "one of the first 1,000 AI builders" "$WORK/early.txt" | grep -aqE '▌ .*(THINGS TO FIX|BETTER THAN|ACT NOW)'; then ok "the header follows the rank line"; else bad "the header follows the rank line"; fi
hasnot "never shows a total under 1,000"      '★ (999 AI builders|120 AI builders|Blindspot has found|40% of AI builders)' "$WORK/early.txt"
printf '%s' '{"p":72,"n":1234}' > "$WORK/reply.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/early-no-rank.txt" 2>&1
has    "says early adopter when the reply has no rank" "^  ★ You're one of the first 1,000 AI builders to run Blindspot\." "$WORK/early-no-rank.txt"
printf '%s' '{"p":72,"n":1234,"r":142}' > "$WORK/reply.json"
printf '%s' '{"devices":1000,"devices_7d":10,"key_files":20,"clean":0}' > "$WORK/stats.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/at-1000.txt" 2>&1
has    "shows the total from 1,000 people"    '★ 1,000 AI builders have run Blindspot\.' "$WORK/at-1000.txt"
printf '{"devices":"\033[2J\033]0;pwned\007","key_files":99999999999999999999}' > "$WORK/stats.json"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > "$WORK/hostile.txt" 2>&1
if LC_ALL=C grep -aq "$(printf '\033')\|$(printf '\007')" "$WORK/hostile.txt"; then bad "a hostile totals reply can't reach the terminal"; else ok "a hostile totals reply can't reach the terminal"; fi
hasnot "a bad totals reply shows no total"    '^  ★ ([0-9]|Blindspot has found)' "$WORK/hostile.txt"
cp "$WORK/stats-0.json" "$WORK/stats.json"

# The same fields as gird-check.sh's report, in the same order.
: > "$WORK/received.log"
HOME="$WORK/bhome" PATH=/usr/bin:/bin GIRD_CHECK_API="$API" bash "$BASH_SCRIPT" > "$WORK/bash-online.txt" 2>&1
head -n 1 "$WORK/received.log" > "$WORK/report-bash.json"
python3 - "$WORK/report-bash.json" "$WORK/report-ps.json" > "$WORK/cmp.txt" 2>&1 <<'PY'
import json, sys
b, p = (json.loads(open(f).readline(), object_pairs_hook=lambda kv: kv) for f in sys.argv[1:3])
bk, pk = [k for k, _ in b], [k for k, _ in p]
print('order' if bk == pk else 'differ: ' + ' '.join(sorted(set(bk) ^ set(pk))) + ' | ' + ' '.join(k for k, l in zip(bk, pk) if k != l))
bd, pd = dict(b), dict(p)
# agents_idle is left out: gird-check.sh also sees apps installed on this Mac.
same = ['mcp_servers', 'mcp_configs', 'mcp_token_files', 'mcp_clients', 'mcp_token_clients', 'mcp_known', 'mcp_other',
        'allow_list_keys', 'allow_list_npm', 'ssh_keys', 'ssh_no_passphrase', 'litellm_found', 'env_files', 'allow_list_files']
def norm(v): return sorted(dict(v).items()) if isinstance(v, list) and v and isinstance(v[0], tuple) else v
print('same: ' + ' '.join(k for k in same if norm(bd.get(k)) != norm(pd.get(k))))
print('types: ' + ' '.join(k for k in bd if type(norm(bd[k])) != type(norm(pd.get(k)))))
PY
if grep -qx 'order' "$WORK/cmp.txt"; then ok "the report has gird-check.sh's fields in its order"; else bad "the report has gird-check.sh's fields in its order"; sed 's/^/        /' "$WORK/cmp.txt"; fi
if grep -qx 'same: ' "$WORK/cmp.txt"; then ok "the counts match gird-check.sh's on the same home"; else bad "the counts match gird-check.sh's on the same home"; grep same "$WORK/cmp.txt" | sed 's/^/        /'; fi
if grep -qx 'types: ' "$WORK/cmp.txt"; then ok "every field has the same JSON type"; else bad "every field has the same JSON type"; grep types "$WORK/cmp.txt" | sed 's/^/        /'; fi
has    "key_places counts PowerShell's history as shell history" '"key_places":\{"shell_rc":1,"shell_history":2,"env_file":1,"mcp_config":1\}' "$WORK/report-ps.json"
has    "history_keys counts it too"            '"history_keys":2,' "$WORK/report-ps.json"
B_LINK=$(grep -aoE 'blindspot/card/#[^ ]*' "$WORK/bash-online.txt" | tail -n 1 | tr '&' '\n' | sed 's/=.*//' | tr '\n' ' ')
P_LINK=$(grep -aoE 'blindspot/card/#[^ ]*' "$OUT" | tail -n 1 | tr '&' '\n' | sed 's/=.*//' | tr '\n' ' ')
if [ -n "$B_LINK" ] && [ "$B_LINK" = "$P_LINK" ]; then ok "the result link has gird-check.sh's parameters in its order"; else bad "the result link has gird-check.sh's parameters in its order"; printf '        bash: %s\n        pwsh: %s\n' "$B_LINK" "$P_LINK"; fi

# The dossier checks share nothing: the same report, link and score with or without them.
rm -rf "$WORK/pl-base" "$WORK/pl-dz"; cp -R "$WORK/clean" "$WORK/pl-base"; cp -R "$WORK/clean" "$WORK/pl-dz"
bash tests/make-dossier.sh "$WORK/pl-dz" "$WORK/pl-dz/AppData/Roaming" calm
: > "$WORK/received.log"
psrun "$WORK/pl-base" GIRD_CHECK_API="$API" GIRD_CHECK_TEST_MACHINEGUID="$GUID" -- > "$WORK/pl-base.txt" 2>&1
psrun "$WORK/pl-dz" GIRD_CHECK_API="$API" GIRD_CHECK_TEST_MACHINEGUID="$GUID" -- > "$WORK/pl-dz.txt" 2>&1
if python3 -c 'import json,sys
rs = [json.loads(l) for l in open(sys.argv[1]) if "\"kind\":\"report\"" in l]
for r in rs:
    for k in ("run_id", "scan_seconds", "results_wait_seconds"): r.pop(k, None)
sys.exit(0 if len(rs) == 2 and rs[0] == rs[1] else 1)' "$WORK/received.log"; then ok "the dossier findings leave the report unchanged"
else bad "the dossier findings leave the report unchanged"; fi
has    "and they were found"                         'Tools with a security fix to install' "$WORK/pl-dz.txt"
if [ "$(grep -aoE 'blindspot/card/#[^ ]*' "$WORK/pl-dz.txt" | sed 's/&u=[0-9a-f]*&/\&u=\&/')" = "$(grep -aoE 'blindspot/card/#[^ ]*' "$WORK/pl-base.txt" | sed 's/&u=[0-9a-f]*&/\&u=\&/')" ]; then ok "and the result link, score included, is the same"
else bad "and the result link, score included, is the same"; fi

echo "case-study counts in the report"
payload_checks() { # mode report
  python3 tests/payload.py "$SCRIPT" "$@" > "$WORK/checks.txt" 2>&1
  while IFS='|' read -r st label detail; do
    case "$st" in
      ok)  ok "$label" ;;
      bad) bad "$label" "$detail" ;;
      *)   bad "the case-study checks ran" "$st$label" ;;
    esac
  done < "$WORK/checks.txt"
}
report_of() { # file command...: runs the command and keeps the one report it sent
  _n0=$(grep -c . "$WORK/received.log"); _rf=$1; shift
  "$@" > /dev/null 2>&1
  sed -n "$((_n0 + 1))p" "$WORK/received.log" > "$_rf"
}
: > "$WORK/received.log"
payload_checks home "$WORK/report-ps.json"
# One more key file in a shell config, a history file and an .env file, and one in agent settings.
bash tests/make-fixture.sh "$WORK/places" "$WORK/keys-places.txt"; winify "$WORK/places" "$WORK/keys-places.txt"
printf 'export OPENAI_API_KEY=%s\n' "$(sed -n 2p "$WORK/keys-places.txt")" > "$WORK/places/.bash_profile"
printf 'client = Anthropic(api_key="%s")\n' "$(sed -n 1p "$WORK/keys-places.txt")" > "$WORK/places/.python_history"
printf 'GROQ_API_KEY=%s\n' "$(sed -n 5p "$WORK/keys-places.txt")" > "$WORK/places/.gemini/.env"
printf 'anthropic-api-key: %s\n' "$(sed -n 1p "$WORK/keys-places.txt")" > "$WORK/places/.aider.conf.yml"
report_of "$WORK/report-places.json" psrun "$WORK/places" GIRD_CHECK_API="$API" --
payload_checks places "$WORK/report-places.json"
mkdir -p "$WORK/empty"
report_of "$WORK/report-empty.json" psrun "$WORK/empty" GIRD_CHECK_API="$API" --
payload_checks empty "$WORK/report-empty.json"
# files_found counts the files the scan found, as it always has: a linked settings file is checked, not counted.
mkdir -p "$WORK/fcount/p/.claude" "$WORK/fcount/q/.claude" "$WORK/fcount/AppData/Roaming" "$WORK/fcount/AppData/Local/Temp"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]}}\n' > "$WORK/fcount/p/.claude/settings.json"
printf 'X=1\n' > "$WORK/fcount/p/.env"; ln -s ../../p/.claude/settings.json "$WORK/fcount/q/.claude/settings.json"
report_of "$WORK/report-fcount.json" psrun "$WORK/fcount" GIRD_CHECK_API="$API" --
has    "files_found counts files, not a linked settings file" '"files_found":2,' "$WORK/report-fcount.json"
psrun "$WORK/fcount" -- -Offline > "$WORK/fcount.txt" 2>&1
has    "and the linked settings file is still checked" 'q/\.claude/settings\.json' "$WORK/fcount.txt"
# files_found counts files: a site-packages folder the scan lists is not one.
mkdir -p "$WORK/fcount/v/lib/python3.12/site-packages"; printf 'home = /usr\n' > "$WORK/fcount/v/pyvenv.cfg"
report_of "$WORK/report-fsite.json" psrun "$WORK/fcount" GIRD_CHECK_API="$API" --
has    "files_found counts no site-packages folder" '"files_found":3,' "$WORK/report-fsite.json"
rm -rf "$WORK/fcount/v"
# A settings file a repo links to a device: /dev/zero never ends and /dev/tty waits for the keyboard.
# Only a link that ends at a regular file is a settings file, and the allow list after it is still
# read. A heap limit keeps a regression from eating the machine's memory on /dev/zero.
for dv in zero tty; do
  rm -rf "${WORK:?}/dev$dv"; mkdir -p "$WORK/dev$dv/code/a-repo/.claude" "$WORK/dev$dv/code/b-mine/.claude" "$WORK/dev$dv/AppData/Roaming" "$WORK/dev$dv/AppData/Local/Temp"
  ln -s "/dev/$dv" "$WORK/dev$dv/code/a-repo/.claude/settings.local.json"
  printf '{"permissions":{"allow":["Bash(OPENAI_API_KEY=%s npm run eval)"]}}\n' "$(sed -n 2p "$WORK/keys.txt")" > "$WORK/dev$dv/code/b-mine/.claude/settings.local.json"
  report_of "$WORK/report-dev$dv.json" psrun "$WORK/dev$dv" GIRD_CHECK_API="$API" DOTNET_GCHeapHardLimit=0x40000000 --
  has    "a settings link to /dev/$dv is not a settings file" '"allow_list_files":1,' "$WORK/report-dev$dv.json"
  psrun "$WORK/dev$dv" DOTNET_GCHeapHardLimit=0x40000000 -- -Offline > "$WORK/dev$dv.txt" 2>&1
  has    "and the allow list after a /dev/$dv link is still read" '~/code/b-mine/\.claude/settings\.local\.json' "$WORK/dev$dv.txt"
done
# -All reaches the report as all_folders 1.
report_of "$WORK/report-all.json" psrun "$WORK/fcount" GIRD_CHECK_API="$API" -- -All
has    "--all is all_folders 1 in the report" '"all_folders":1,' "$WORK/report-all.json"
hasnot "no report holds a name you gave an MCP server" 'acme|my notes|web.search' "$WORK/received.log"
hasnot "no report holds a server label as written"     '@modelcontextprotocol|MCP_DOCKER|Figma Dev Mode|upstash|Playwright|"gh"|"fs"' "$WORK/received.log"
hasnot "no report holds a file name" '\.zshrc|zsh_history|python_history|bash_profile|\.env|\.mcp|mcp\.json|config\.(toml|yaml)|cline_mcp|claude_desktop|settings(\.local)?\.json|\.aider|PSReadLine|ConsoleHost' "$WORK/received.log"
hasnot "no report holds a path"                        '/(Users|home|private|tmp|var)/|~/|AppData' "$WORK/received.log"
nokeys "no report holds the extra planted keys" "$WORK/keys-places.txt" "$WORK/received.log"

echo "a Windows profile"
# The profile tests/run.sh builds for Git Bash, with OS=Windows_NT so gird-check.ps1 takes the
# Windows paths. The Windows version can't be faked here: gird-check.ps1 reads it from .NET.
WP=$WORK/winp
K_ANT=$(sed -n 1p "$WORK/keys.txt"); K_AWS=$(sed -n 4p "$WORK/keys.txt")
mkdir -p "$WP/.claude/projects/p" "$WP/AppData/Roaming/Claude" "$WP/AppData/Roaming/Code/User" "$WP/AppData/Local/Programs/cursor" \
  "$WP/AppData/Roaming/Block/goose/config" "$WP/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine" \
  "$WP/AppData/Roaming/GitHub CLI" "$WP/AppData/Local/Programs/Python/Python312/Lib/site-packages" \
  "$WP/AppData/Local/uv/cache/wheels-v5/pypi/litellm/litellm-1.107.0-py3-none-any" "$WP/AppData/Local/Temp"
printf '{}\n' > "$WP/.claude/projects/p/s.jsonl"
mkdir -p "$WP/AppData/Roaming/Cursor/User/workspaceStorage/w"; printf '{}\n' > "$WP/AppData/Roaming/Cursor/User/workspaceStorage/w/state.json"
printf '{"mcpServers":{"github":{"command":"npx"}}}\n' > "$WP/.claude.json"
printf '{"mcpServers":{"slack":{"command":"npx","env":{"SLACK_BOT_TOKEN":"%s"}}}}\n' "$K_ANT" > "$WP/AppData/Roaming/Claude/claude_desktop_config.json"
printf '{"servers":{"playwright":{"command":"npx"},"memory":{"command":"npx"}}}\n' > "$WP/AppData/Roaming/Code/User/mcp.json"
printf 'extensions:\n  github:\n    enabled: true\n' > "$WP/AppData/Roaming/Block/goose/config/config.yaml"
printf 'git status\n$env:AWS_ACCESS_KEY_ID = "%s"\n' "$K_AWS" > "$WP/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt"
printf 'github.com:\n    oauth_token: x\n' > "$WP/AppData/Roaming/GitHub CLI/hosts.yml"
printf 'machine example.com login me password x\n' > "$WP/_netrc"
printf 'import cook\n' > "$WP/AppData/Local/Programs/Python/Python312/Lib/site-packages/cook.pth"
mkdir -p "$WP/AppData/Local/Programs/Python/Python312/Lib/site-packages/mistralai-2.4.6.dist-info"   # its malware ran on Linux only
: > "$WP/AppData/Local/Temp/.pc_once_1"
# Global installs in the Windows places: npm's own folder, nvm-windows, fnm, Volta, mise, pnpm and npx's cache.
for d in AppData/Roaming/npm/node_modules/opencraw AppData/Roaming/nvm/v20.1.0/node_modules/claud-code \
         AppData/Roaming/fnm/node-versions/v22.0.0/installation/node_modules/cloude-code \
         AppData/Local/Volta/tools/image/node/20.1.0/node_modules/rimarf AppData/Local/Volta/tools/image/packages/tool/lib/node_modules/naniod \
         AppData/Local/mise/installs/node/22.0.0/node_modules/suport-color AppData/Local/pnpm/global/5/node_modules/cloude \
         AppData/Local/npm-cache/_npx/abc123/node_modules/iruchache; do
  mkdir -p "$WP/$d"; printf '{"name":"%s","version":"1.0.0"}\n' "${d##*/}" > "$WP/$d/package.json"
done
WGUID='3F2504E0-4f89-11D3-9A0C-0305E82C3301'
winps() { psrun "$WP" OS=Windows_NT PROCESSOR_ARCHITECTURE=AMD64 WT_SESSION=1 GIRD_CHECK_TEST_MACHINEGUID="$WGUID" "$@"; }
winps -- -Offline > "$WORK/win.txt" 2>&1
tr -s ' \n' '  ' < "$WORK/win.txt" > "$WORK/win1.txt"
has    "Windows: finds Claude Desktop in AppData"       'Claude Desktop +used in the last 30 days' "$WORK/win.txt"
has    "Windows: finds Cursor and its use in AppData"   'Cursor +used in the last 30 days' "$WORK/win.txt"
has    "Windows: finds Goose in its Windows config"     'Goose +installed' "$WORK/win.txt"
has    "Windows: Claude Code in the Windows profile"    'Claude Code +used in the last 30 days' "$WORK/win.txt"
has    "Windows: reads Claude Desktop's MCP config"     'Claude Desktop +~/AppData/Roaming/Claude/claude_desktop_config\.json.*token in the file' "$WORK/win1.txt"
has    "Windows: reads VS Code's MCP config"            'VS Code +~/AppData/Roaming/Code/User/mcp\.json' "$WORK/win1.txt"
has    "Windows: reads Goose's MCP config"              'Goose +~/AppData/Roaming/Block/goose/config/config\.yaml' "$WORK/win1.txt"
has    "Windows: flags a key in PowerShell history"     '~/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history\.txt +AWS' "$WORK/win1.txt"
has    "Windows: finds LiteLLM files in Windows Python" 'Programs/Python/Python312/Lib/site-packages: cook\.pth' "$WORK/win1.txt"
has    "Windows: finds the markers in %TEMP%"           'Temp/\.pc_once_1' "$WORK/win1.txt"
has    "Windows: mistralai 2.4.6 is a version to update" 'mistralai 2\.4\.6 +a bad version to update ~/AppData/Local/Programs/Python/Python312/Lib/site-packages: mistralai 2\.4\.6' "$WORK/win1.txt"
# An extension whose malware runs on Windows only (data/bad-extensions.tsv's os) is malware here.
mkdir -p "$WP/.vscode/extensions/microsoftvs.microsoftvs-1.0.2"
winps -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/win-ext.txt"
rm -rf "$WP/.vscode/extensions/microsoftvs.microsoftvs-1.0.2"
has    "Windows: an extension whose malware runs on Windows is malware here" 'Editor extensions signs of the malware found ~/\.vscode/extensions/microsoftvs\.microsoftvs-1\.0\.2 microsoftvs\.microsoftvs 1\.0\.2 \(GlassWorm-linked themes, October 2026\), installed' "$WORK/win-ext.txt"
has    "Windows: finds the bad package in uv's cache"   'uv cache holds the 1\.107\.0 package' "$WORK/win1.txt"
has    "Windows: finds _netrc"                          'saved passwords in _netrc' "$WORK/win1.txt"
has    "Windows: finds the GitHub CLI login in AppData" 'GitHub CLI token' "$WORK/win1.txt"
has    "Windows: a bad package in npm's AppData folder"  'AppData/Roaming/npm/node_modules/opencraw' "$WORK/win1.txt"
has    "Windows: a bad package under nvm-windows"        'AppData/Roaming/nvm/v20\.1\.0/node_modules/claud-code' "$WORK/win1.txt"
has    "Windows: a bad package under fnm"                'AppData/Roaming/fnm/node-versions/v22\.0\.0/installation/node_modules/cloude-code' "$WORK/win1.txt"
has    "Windows: a bad package under Volta"              'AppData/Local/Volta/tools/image/node/20\.1\.0/node_modules/rimarf' "$WORK/win1.txt"
has    "Windows: a bad dependency of a Volta tool"       'AppData/Local/Volta/tools/image/packages/tool/lib/node_modules/naniod' "$WORK/win1.txt"
has    "Windows: a bad package under mise"               'AppData/Local/mise/installs/node/22\.0\.0/node_modules/suport-color' "$WORK/win1.txt"
has    "Windows: a bad package in pnpm's global folder"  'AppData/Local/pnpm/global/5/node_modules/cloude ' "$WORK/win1.txt"
has    "Windows: a bad package in npx's cache"           'AppData/Local/npm-cache/_npx/abc123/node_modules/iruchache' "$WORK/win1.txt"
has    "Windows is pointed at Credential Manager"       'into Windows Credential Manager or a secrets manager' "$WORK/win1.txt"
nokeys "Windows: never prints a planted key" "$WORK/keys.txt" "$WORK/win.txt"
report_of "$WORK/report-win.json" winps GIRD_CHECK_API="$API" --
WANT_ID=$(printf 'gird-check-v1:%s' "$WGUID" | shasum -a 256 | cut -c1-64)
has    "Windows: device_id is sha256 of the salt and MachineGuid as stored" "\"device_id\":\"$WANT_ID\"" "$WORK/report-win.json"
has    "Windows: arch from PROCESSOR_ARCHITECTURE"      '"arch":"x86_64"' "$WORK/report-win.json"
has    "Windows: terminal is windows-terminal with WT_SESSION" '"terminal":"windows-terminal"' "$WORK/report-win.json"
has    "Windows: the agents found in Windows places are reported" '"agents":\["claude-code","claude-desktop","cursor",.*"goose"' "$WORK/report-win.json"
has    "Windows: PowerShell history counts as shell history" '"history_keys":1,' "$WORK/report-win.json"
has    "Windows: key_places puts PSReadLine history in shell_history" '"shell_history":1' "$WORK/report-win.json"
hasnot "Windows: the report holds no Windows path or file name" 'AppData|PSReadLine|ConsoleHost|Users/me|winp|_netrc' "$WORK/report-win.json"

# The Worker's own validation. It must keep the Windows values as sent, not turn
# them into 'other', and they must be the plan's values.
WORKER=${GIRD_CHECK_WORKER:-}
if [ -n "$WORKER" ] && [ -f "$WORKER" ] && command -v node >/dev/null 2>&1; then
  node --no-warnings --input-type=module - "$WORKER" "$WORK/report-ps.json" > "$WORK/worker.txt" 2>&1 <<'JS'
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
const { validateEvent } = await import(pathToFileURL(process.argv[2]).href)
const r = JSON.parse(readFileSync(process.argv[3], 'utf8').split('\n')[0])
const plan = { os: /^(Windows( 10| 11)?|macOS|Linux)$/, shell: /^(pwsh|powershell)$/, terminal: /^(windows-terminal|conhost|vscode|other|unknown)$/ }
const bad = Object.entries(plan).filter(([k, re]) => !re.test(r[k])).map(([k]) => k)
const v = validateEvent(r)
const dropped = v.ok ? Object.keys(r).filter((k) => JSON.stringify(v.event[k]) !== JSON.stringify(r[k])) : []
console.log(v.ok && !bad.length && !dropped.length ? 'valid' : `invalid: ${v.why || ''} plan: ${bad} dropped: ${dropped}`)
JS
  if grep -qx valid "$WORK/worker.txt"; then ok "the Worker accepts the report and keeps every field"; else bad "the Worker accepts the report and keeps every field" "$(cat "$WORK/worker.txt")"; fi
else
  skip "the Worker accepts the report and keeps every field" "needs GIRD_CHECK_WORKER pointing at the site's report validation (worker/check-stats.js), and node"
fi

finish
