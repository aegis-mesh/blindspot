#!/usr/bin/env bash
# Runs gird-check.ps1 against a fake Windows-shaped home folder (USERPROFILE,
# APPDATA, LOCALAPPDATA and TEMP all point into it) and checks what it finds, what
# it must never print or send, and that its report matches gird-check.sh's.
#
#   PWSH=/path/to/pwsh bash tests/run-ps.sh
#
# PWSH defaults to pwsh on PATH. Set GIRD_CHECK_WORKER to gird-website's
# worker/check-stats.js to check the report against the Worker's validation too.
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
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
has()    { if grep -aqE -- "$2" "$3"; then ok "$1"; else bad "$1"; printf '        wanted: %s\n' "$2"; fi; }
hasnot() { if grep -aqE -- "$2" "$3"; then bad "$1"; printf '        found: %s\n' "$2"; else ok "$1"; fi; }
nokeys() { if grep -aqF -f "$2" "$3"; then bad "$1"; else ok "$1"; fi; }

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

echo "pwsh $("$PWSH" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
if psrun "$WORK/home" -- -Help > "$WORK/help.txt" 2>&1 && grep -q -- '-Offline' "$WORK/help.txt"; then ok "-Help lists the options"; else bad "-Help lists the options"; fi
psrun "$WORK/home" -- --bogus > "$WORK/bogus.txt" 2>&1; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'Unknown option' "$WORK/bogus.txt"; then ok "an unknown option exits 2"; else bad "an unknown option exits 2, got $RC"; fi

OUT=$WORK/out.txt
psrun "$WORK/home" -- -Offline > "$OUT" 2> "$WORK/err.txt"; RC=$?
if [ "$RC" -eq 0 ]; then ok "exits 0"; else bad "exits 0, got $RC"; fi
if [ -s "$WORK/err.txt" ]; then bad "writes nothing to stderr"; sed 's/^/        /' "$WORK/err.txt" | head -n 5; else ok "writes nothing to stderr"; fi
has    "finds keys in the shell profile"       '~/\.zshrc +Anthropic, OpenAI' "$OUT"
has    "finds keys in shell history"           '~/\.zsh_history +GitHub' "$OUT"
has    "flags a key in PowerShell's history"   'PSReadLine/ConsoleHost_history\.txt' "$OUT"
has    "names the provider of that key"        '^ {54}GitHub$' "$OUT"
has    "finds keys in a project .env file"     '~/code/app/\.env +AWS, Groq' "$OUT"
has    "finds a key in an MCP config"          '~/\.cursor/mcp\.json +GitHub' "$OUT"
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
has    "finds a planted worm file"            'code/planted/\.vscode/tanstack_runner\.js' "$OUT"
hasnot "a worktree with the same settings is not listed again" 'worktrees/w1' "$OUT"
has    "and is counted under its repo's row" 'The same settings are in$' "$OUT"
has    "a localhost name with a login prefix is not local" 'code/sneaky/\.claude/settings\.json' "$OUT"
has    "finds any version of a fake AI tool package" 'claud-code 1\.0\.3 \(SANDWORM_MODE worm' "$OUT"
has    "finds a bad package in npm's cache"    '@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI' "$OUT"
has    "puts the wiper first"                  'ACT NOW: REMOVE GH-TOKEN-MONITOR BEFORE YOU REVOKE ANY TOKEN' "$OUT"
has    "lists the wiper's files"               '~/\.config/gh-token-monitor' "$OUT"
has    "a hook that runs a planted worm file counts as malware" '^ +~/code/cloned/\.claude/settings\.json$' "$OUT"
tr -s ' \n' '  ' < "$OUT" > "$WORK/out-flat.txt"   # the advice wraps, so it is matched on one line
has    "points other systems at a secrets manager" 'files into a secrets manager, then rotate' "$WORK/out-flat.txt"
has    "other rotate fixes wait for the wiper"         'then rotate them\. Only once gh-token-monitor is stopped and removed' "$WORK/out-flat.txt"
has    "section 5's rotate fixes wait for it too"      'rotate every key this machine could reach\. Only once gh-token-monitor is stopped and removed' "$WORK/out-flat.txt"
hasnot "the wiper's own fix does not wait for itself"  'Then rotate every key this machine could reach\. Only once' "$WORK/out-flat.txt"
has    "the link flags npm malware and the wiper"      'nm=1&py=0&wp=1$' "$OUT"
has    "uses the non-Mac Argus line"           'Argus, our free Mac app, shows what AI coding agents' "$OUT"
hasnot "never offers the Argus download off a Mac" 'argus/download' "$OUT"
hasnot "never shows a letter grade"            'GRADE [ABCDF]|[Gg]rade [ABCDF]\b' "$OUT"
has    "the offline link has key counts, no run ID or rank" 'blindspot/card/#v=2&.*&u=&r=&sk=2&hk=2&ag=[a-z0-9.-]*&nm=[01]&py=[01]&wp=[01]$' "$OUT"
nokeys "never prints a planted key" "$WORK/keys.txt" "$OUT"
if LC_ALL=C grep -aq "$(printf '\033')" "$OUT"; then bad "redirected output has no escape codes"; else ok "redirected output has no escape codes"; fi

echo "keys in agent sessions"
SE=$WORK/sess; mkdir -p "$SE/rgbin"
RG=$(command -v rg 2>/dev/null); [ -n "$RG" ] && ln -s "$RG" "$SE/rgbin/rg"
for E in net rg; do
  if [ "$E" = rg ] && [ -z "$RG" ]; then echo "  skip  ripgrep is not installed"; continue; fi
  psrun "$WORK/home" PATH="$WORK/bin:$SE/rgbin" GIRD_CHECK_SESSIONS_ENGINE=$E -- -Offline > "$SE/$E.txt" 2>&1
  sed -n '/Keys in agent sessions/,/^$/p' "$SE/$E.txt" > "$SE/$E.block"
  has    "$E: a key after an escaped newline in a Claude Code session" 'Claude Code +1 file: Hugging Face' "$SE/$E.block"
  has    "$E: a key in a Codex session"            'Codex +1 file: OpenAI' "$SE/$E.block"
  has    "$E: a key in an Aider history"           'Aider +1 file: Groq' "$SE/$E.block"
  hasnot "$E: a made-up key is not counted"        'Claude Code .*(Anthropic|AWS|GitHub)' "$SE/$E.block"
  has    "$E: a real key with few different characters counts" 'Codex +1 file: OpenAI, AWS' "$SE/$E.block"
  has    "$E: a compressed session is named as not checked" '1 compressed session file was not checked' "$SE/$E.block"
  has    "$E: names encrypted sessions as not checked" 'Windsurf sessions are stored encrypted, so they were not checked' "$SE/$E.block"
  nokeys "$E: never prints a key" "$WORK/keys.txt" "$SE/$E.txt"
done
if [ -s "$SE/rg.block" ]; then
  if diff -q "$SE/net.block" "$SE/rg.block" >/dev/null; then ok ".NET and ripgrep report the same"; else bad ".NET and ripgrep report the same"; diff "$SE/net.block" "$SE/rg.block" | head -n 6; fi
fi
bash tests/make-fixture.sh "$SE/bh" "$SE/bk" >/dev/null
HOME="$SE/bh" PATH=/usr/bin:/bin bash "$BASH_SCRIPT" --offline 2>&1 | sed -n '/Keys in agent sessions/,/^$/p' > "$SE/bash.block"
if diff -q "$SE/bash.block" "$SE/net.block" >/dev/null; then ok "the same session block as gird-check.sh"; else bad "the same session block as gird-check.sh"; diff "$SE/bash.block" "$SE/net.block" | head -n 6; fi
psrun "$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_STOP_AFTER=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/part.txt"
has    "a partial check says how much it covered" 'Checked the newest 2 of 6 agent session files' "$SE/part.txt"
psrun "$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline > "$SE/clean.txt" 2>&1
has    "a full check with nothing found says so" 'No keys in 2 agent session files\.' "$SE/clean.txt"
mkdir -p "$SE/piece/.claude/projects/p" "$SE/piece/AppData/Roaming" "$SE/piece/AppData/Local/Temp"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 40) + 'hf_' + 'Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAuCiEoXkYnZqWdTgPrMsBvLj' + '\n')" "$SE/piece/.claude/projects/p/a.jsonl"
psrun "$SE/piece" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/piece.txt" 2>&1
has    "a token across a piece boundary is not a key" 'No keys in 1 agent session file' "$SE/piece.txt"
mkdir -p "$SE/esc/.claude/projects/p" "$SE/esc/AppData/Roaming" "$SE/esc/AppData/Local/Temp"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 2) + '\\\\n' + 'hf_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu end' + '\n')" "$SE/esc/.claude/projects/p/a.jsonl"
psrun "$SE/esc" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/esc.txt" 2>&1
has    "a key after an escaped newline at a piece boundary is found" 'Claude Code +1 file: Hugging Face' "$SE/esc.txt"
mkdir -p "$SE/esc2/.claude/projects/p" "$SE/esc2/AppData/Roaming" "$SE/esc2/AppData/Local/Temp"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 1) + '\\\\' + 'nhf_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu end' + '\n')" "$SE/esc2/.claude/projects/p/a.jsonl"
psrun "$SE/esc2" GIRD_CHECK_SESSIONS_ENGINE=net -- -Offline -AllSessions > "$SE/esc2.txt" 2>&1
has    "a key after a backslash that ends a read is found" 'Claude Code +1 file: Hugging Face' "$SE/esc2.txt"
: > "$SE/hold"
psrun "$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_HOLD="$SE/hold" -- -Offline > "$SE/held.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "a held check does not hold up the report"; else bad "a held check does not hold up the report, exit $RC"; fi
hasnot "a partial check with nothing found never says no keys" 'No keys in .*agent session' "$SE/held.txt"
has    "and says it was partial"                 'Checked the newest 0 of 2 agent session files' "$SE/held.txt"
mkdir -p "$SE/min/.claude/projects/p" "$SE/min/AppData/Roaming" "$SE/min/AppData/Local/Temp"; printf '{}\n' > "$SE/min/.claude/projects/p/a.jsonl"
psrun "$SE/min" GIRD_CHECK_SESSIONS_ENGINE=net GIRD_CHECK_SESSIONS_HOLD="$SE/hold" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$SE/held-sum.txt"
has    "the summary row is not a check mark after a partial check" 'Keys in plain text none in files; agent sessions partly checked' "$SE/held-sum.txt"

echo "the same findings as gird-check.sh"
# Each list is cut out of its script, then the same filter keeps only entry lines on both sides.
entries() { grep -E '^[@a-z0-9][^ ]* (\*|[0-9][^ ]*) [a-z]+$'; }
sed -n '/^BAD_NPM="/,/"$/p' "$BASH_SCRIPT" | sed -e 's/^BAD_NPM="//' -e 's/"$//' > "$WORK/bad-sh-raw.txt"
sed -n "/^\$BadNpm = @'/,/^'@/p" "$SCRIPT" | sed -e '1d' -e '$d' > "$WORK/bad-ps-raw.txt"
entries < "$WORK/bad-sh-raw.txt" > "$WORK/bad-sh.txt"; entries < "$WORK/bad-ps-raw.txt" > "$WORK/bad-ps.txt"
if [ -s "$WORK/bad-sh.txt" ] && diff -q "$WORK/bad-sh.txt" "$WORK/bad-ps.txt" >/dev/null; then ok "the same bad npm package list ($(wc -l < "$WORK/bad-ps.txt" | tr -d ' ') entries)"
else bad "the same bad npm package list"; diff "$WORK/bad-sh.txt" "$WORK/bad-ps.txt" | head -n 6; fi
if diff -q "$WORK/bad-sh-raw.txt" "$WORK/bad-sh.txt" >/dev/null && diff -q "$WORK/bad-ps-raw.txt" "$WORK/bad-ps.txt" >/dev/null; then ok "every line of both lists is an entry"
else bad "every line of both lists is an entry"; diff "$WORK/bad-sh-raw.txt" "$WORK/bad-sh.txt" | head -n 3; diff "$WORK/bad-ps-raw.txt" "$WORK/bad-ps.txt" | head -n 3; fi
# gird-check.sh, on the same home with its Mac paths, must find the same files.
# The home and the run both take Mac paths whatever this host is: on Linux the fixture and the
# script would use ~/.config, and Claude Desktop and its MCP servers would be missed.
mkdir -p "$WORK/macbin"; printf '#!/bin/sh\nif [ "$1" = -s ]; then echo Darwin; else exec /usr/bin/uname "$@"; fi\n' > "$WORK/macbin/uname"; chmod +x "$WORK/macbin/uname"
PATH="$WORK/macbin:$PATH" bash tests/make-fixture.sh "$WORK/bhome" "$WORK/keys-b.txt" >/dev/null
HOME="$WORK/bhome" PATH="$WORK/macbin:/usr/bin:/bin" bash "$BASH_SCRIPT" --offline > "$WORK/bash.txt" 2>&1
for sec in 'MCP SERVERS' 'KEYS IN CLAUDE CODE ALLOW LISTS'; do
  b=$(grep -aoE "$sec +[0-9]+ [a-z]+" "$WORK/bash.txt"); p=$(grep -aoE "$sec +[0-9]+ [a-z]+" "$OUT")
  if [ -n "$b" ] && [ "$b" = "$p" ]; then ok "$sec agrees ($p)"; else bad "$sec agrees: bash '$b', pwsh '$p'"; fi
done
b=$(grep -aoE 'KEYS IN PLAIN TEXT +[0-9]+' "$WORK/bash.txt" | grep -oE '[0-9]+$'); p=$(grep -aoE 'KEYS IN PLAIN TEXT +[0-9]+' "$OUT" | grep -oE '[0-9]+$')
if [ -n "$b" ] && [ "$p" = $((b + 1)) ]; then ok "key files agree, plus PowerShell's history ($p)"; else bad "key files agree: bash $b, pwsh $p"; fi
# Only where keys go differs: the macOS Keychain there, a secrets manager here.
fixes() { sed -n '/WHAT TO DO/,$p' "$1" | grep -aE '^ +[0-9]+\.' | sed -e 's/^ *[0-9]*\. *//' -e 's/ into .*//'; }
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
psrun "$RV" -- -Offline > "$WORK/rv.txt" 2>&1
hasnot "a pnpm override pinning away is not a hit"     'code/pin/' "$WORK/rv.txt"
has    "an npm lock entry without a URL is read"       'keyv 6\.0\.0 \(keyv worm' "$WORK/rv.txt"
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
hasnot "a deny rule naming a worm file is not malware" 'runs a file the TanStack and keyv worms plant' "$WORK/rv.txt"
hasnot "plugin marketplace clones are not projects"    'plugins/marketplaces' "$WORK/rv.txt"
hasnot "a commented-out folderOpen task is not flagged" 'p/comment/' "$WORK/rv.txt"
has    "a | in a folder name keeps its row intact"     'p/a\|b/\.claude/settings\.json' "$WORK/rv.txt"
sed -n '/05  RECENT KEY LEAKS/,/WHAT TO DO/p' "$WORK/rv.txt" > "$WORK/rv-05.txt"
hasnot "a guard hook naming a worm file is not malware" 'p/guard/' "$WORK/rv-05.txt"
has    "a /* inside a settings string does not hide its hooks" 'p/glob/\.claude/settings\.json' "$WORK/rv.txt"
has    "a | in a lockfile's folder keeps its row intact" '~/code/x\|y/package-lock\.json$' "$WORK/rv.txt"
has    "two unrelated repos with the same settings are both listed (1)" 'p/r1/\.claude/settings\.json' "$WORK/rv.txt"
has    "two unrelated repos with the same settings are both listed (2)" 'p/r2/\.claude/settings\.json' "$WORK/rv.txt"
hasnot "a bun override pinning away is not a hit"      'code/bunpin/' "$WORK/rv.txt"
mkdir -p "$WORK/escq/p/.claude" "$WORK/escq/AppData/Roaming" "$WORK/escq/AppData/Local/Temp" "$WORK/vsp/p/.vscode" "$WORK/vsp/AppData/Roaming" "$WORK/vsp/AppData/Local/Temp"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node \\"$CLAUDE_PROJECT_DIR\\"/.claude/router_runtime.js"}]}]}}\n' > "$WORK/escq/p/.claude/settings.json"
mkdir -p "$WORK/escq/q/.claude" "$WORK/escq/w/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node.exe .claude/setup.mjs"}]}]}}\n' > "$WORK/escq/q/.claude/settings.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node .claude\\\\setup.mjs"}]}]}}\n' > "$WORK/escq/w/.claude/settings.json"
psrun "$WORK/escq" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/escq.txt"
has    "a hook running a worm file through an escaped path is malware" '~/p/\.claude/settings\.json runs a file the TanStack' "$WORK/escq.txt"
has    "node.exe counts as running it"                 '~/q/\.claude/settings\.json runs a file the TanStack' "$WORK/escq.txt"
has    "a Windows backslash path counts"               '~/w/\.claude/settings\.json runs a file the TanStack' "$WORK/escq.txt"
printf 'x\n' > "$WORK/vsp/p/.vscode/setup.mjs"
psrun "$WORK/vsp" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/vsp.txt"
has    "a planted .vscode/setup.mjs is found"          'p/\.vscode/setup\.mjs a file the TanStack and keyv worms plant' "$WORK/vsp.txt"
awk '/WHAT TO DO/{f=1} f' "$WORK/rv.txt" | tr -s ' \n' '  ' > "$WORK/rv-todo.txt"
if awk '{ a = index($0, "Delete the saved Claude Code commands"); b = index($0, "Read the settings marked"); exit !(a && b && a < b) }' "$WORK/rv-todo.txt"; then ok "a red allow-list fix comes before the yellow settings fix"; else bad "a red allow-list fix comes before the yellow settings fix"; fi
# The clean line, against gird-check.sh's count, and a folder of npm's cache that can't be read.
cp -R "$WORK/clean" "$WORK/npmok"; mkdir -p "$WORK/npmok/.npm/_cacache/index-v5/aa"
psrun "$WORK/npmok" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmok.txt"
has    "the clean line counts versions and packages apart, as gird-check.sh's list" "npm worms none of $(awk '$2 != "*"' "$WORK/bad-sh.txt" | grep -c .) bad versions or $(awk '$2 == "*"' "$WORK/bad-sh.txt" | grep -c .) bad packages" "$WORK/npmok.txt"
chmod 000 "$WORK/npmok/.npm/_cacache/index-v5/aa"
psrun "$WORK/npmok" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno.txt"
psrun "$WORK/npmok" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno-c.txt"
chmod 755 "$WORK/npmok/.npm/_cacache/index-v5/aa"
has    "an unreadable cache folder is not called clean" "npm worms not fully checked: part of npm's cache could not be read" "$WORK/npmno.txt"
has    "and the summary row is not green either"       'Recent leaks npm packages not fully checked: cache unreadable' "$WORK/npmno-c.txt"
# Windows: no launchctl or systemctl, a PowerShell way to stop the wiper.
psrun "$WORK/home" OS=Windows_NT -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/wwin.txt"
has    "Windows is told how to stop the wiper"         'Stop it with Get-CimInstance Win32_Process .* Invoke-CimMethod -MethodName Terminate, then delete the files above' "$WORK/wwin.txt"
hasnot "Windows is not given launchctl or systemctl"   'launchctl|systemctl' "$WORK/wwin.txt"
# Where a hit was found, and npm's placeholder for a removed package.
has    "a lockfile hit says it is listed there"      'axios 1\.14\.1 \(Axios takeover, March 2026\), listed in this lockfile' "$WORK/out-flat.txt"
has    "an install hit says it is installed"         'claud-code 1\.0\.3 \(SANDWORM_MODE worm, February 2026\), installed' "$WORK/out-flat.txt"
has    "a cache hit says it was downloaded"          "@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI, April 2026\), downloaded into npm's cache" "$WORK/out-flat.txt"
cp -R "$WORK/clean" "$WORK/ph2"; mkdir -p "$WORK/ph2/code/ph"
printf '{"lockfileVersion":3,"packages":{"node_modules/plain-crypto-js":{"version":"0.0.1-security","resolved":"https://registry.npmjs.org/plain-crypto-js/-/plain-crypto-js-0.0.1-security.tgz"}}}\n' > "$WORK/ph2/code/ph/package-lock.json"
psrun "$WORK/ph2" -- -Offline > "$WORK/ph2.txt" 2>&1
hasnot "npm's -security placeholder is not malware" 'plain-crypto-js' "$WORK/ph2.txt"
# Incidents from data/incidents.tsv: a sourced line per incident, and the update level.
has    "each npm incident found gets its sourced line" 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it\. cisa\.gov' "$WORK/out-flat.txt"
cp -R "$WORK/clean" "$WORK/mis"; mkdir -p "$WORK/mis/code/m"
printf '{"lockfileVersion":3,"packages":{"node_modules/@mistralai/mistralai":{"version":"2.2.3","resolved":"https://registry.npmjs.org/@mistralai/mistralai/-/mistralai-2.2.3.tgz"}}}\n' > "$WORK/mis/code/m/package-lock.json"
psrun "$WORK/mis" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mis.txt"
psrun "$WORK/mis" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mis-c.txt"
hasnot "a version whose malware could not run is not 'compromised'" 'ACT NOW|Treat this machine as compromised' "$WORK/mis.txt"
has    "it is a version to update instead"           'npm worms a bad version to update' "$WORK/mis.txt"
has    "with the vendor's own explanation"           'Mistral AI packages, May 2026: published with malware that Mistral says could not run\. docs\.mistral\.ai' "$WORK/mis.txt"
has    "the summary row says so in yellow"           'Recent leaks an npm package to update' "$WORK/mis-c.txt"
has    "the link does not call it npm malware"       '&nm=0&py=0&wp=0( |$)' "$WORK/mis.txt"
cp -R "$WORK/clean" "$WORK/mpy"; mkdir -p "$WORK/mpy/code/venv/lib/site-packages/mistralai-2.4.6.dist-info"
psrun "$WORK/mpy" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mpy.txt"
has    "mistralai 2.4.6 from PyPI is its own act-now row" 'mistralai 2\.4\.6 +signs of the malware found ~/code/venv/lib/site-packages: mistralai 2\.4\.6' "$WORK/mpy.txt"
has    "with its fix"                                "Treat this machine as compromised\. Don't run Python in the affected environments, follow mistralai's advisory" "$WORK/mpy.txt"
has    "the link flags a Python incident, not LiteLLM" '&ll=0&.*&py=1&' "$WORK/mpy.txt"
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
hasnot "the summary has no section tables"     'KEYS IN PLAIN TEXT' "$OUT"
psrun "$WORK/home" GIRD_CHECK_COMPACT=1 -- -Offline -Full > "$WORK/full.txt" 2>&1
has    "-Full shows every detail"              'KEYS IN PLAIN TEXT' "$WORK/full.txt"

echo "placeholders and the LiteLLM leftovers"
mkdir -p "$WORK/ph/code/ph" "$WORK/ph/AppData/Local/Temp"
printf '{"mcpServers":{"x":{"command":"npx","env":{"API_KEY":"your-api-key-goes-here"}}}}\n' > "$WORK/ph/code/ph/.mcp.json"
# A placeholder shaped like a real command key, which only the placeholder screen stops.
mkdir -p "$WORK/ph/code/ph/.claude"; printf '{"name":"ph","private":true}\n' > "$WORK/ph/code/ph/package.json"
printf '{"permissions":{"allow":["Bash(OPENAI_API_KEY=your-openai-key-goes-here npm test)"]}}\n' > "$WORK/ph/code/ph/.claude/settings.local.json"
psrun "$WORK/ph" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ph.txt"
has    "a placeholder token is not a token"    'MCP servers +1 server, no tokens in their configs' "$WORK/ph.txt"
has    "a placeholder key in an allow list is not a key" 'Allow lists +no saved commands with keys' "$WORK/ph.txt"
has    "no malware in a clean home"            'none of the 6 recent leaks it checks' "$WORK/ph.txt"

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
has    "made-up platform: section 5 counts its row"   'RECENT KEY LEAKS +8 checked' "$WORK/mu.txt"
has    "made-up startup file and its note"            '~/\.config/madeworm/boot\.cjs starts the Made worm at login' "$WORK/mu.txt"
has    "a new gh-token-monitor file is a waiting wiper" 'a wiper is waiting ~/\.config/gh-token-monitor-made ' "$WORK/mu.txt"
has    "made-up npm incident: its sourced line"       'Made npm worm, October 2026: a made-up npm worm for the tests\. example\.com' "$WORK/mu.txt"
has    "made-up update-level npm incident: its line"  'Made npm slip, October 2026: a made-up npm version whose malware could not run\. example\.com' "$WORK/mu.txt"
has    "made-up Python package: the link flags it"    '&ll=0&.*&py=1&' "$WORK/mu.txt"
has    "made-up planted file and its note"            '~/code/made/\.vscode/madeplant\.js a file the Made worm plants' "$WORK/mu.txt"
has    "a hook that runs it, with the general note"   '~/code/made/\.claude/settings\.json runs a file a worm plants' "$WORK/mu.txt"
has    "made-up Python package: its own row"          'Madepkg 9\.9\.9 +signs of the malware found ~/code/venv/lib/site-packages: madepkg 9\.9\.9, madepy_boot\.pth ~/AppData/Local/Temp/\.madepy_1 ' "$WORK/mu.txt"
has    "made-up Python package: its advisory"         'Advisory: example\.com/madepy/advisory' "$WORK/mu.txt"
has    "made-up Python package: in uv's cache"        'uv cache holds the 9\.9\.9 package\. Clear it with: uv cache clean madepkg' "$WORK/mu.txt"
has    "made-up Python package: its fix"              "follow Madepkg's advisory" "$WORK/mu.txt"
hasnot "LiteLLM is not blamed for it"                 'LITELLM 1\.107\.0 MALWARE|signs of the LiteLLM malware' "$WORK/mu.txt"
cp -R "$WORK/mu-home" "$WORK/mu-py"; rm -rf "$WORK/mu-py/.config/gh-token-monitor-made" "$WORK/mu-py/.config/madeworm" "$WORK/mu-py/code/made" "$WORK/mu-py/.madeplat.json"
mups "$WORK/mu-py" "$WORK/mu-py.txt" compact
has    "made-up Python package leads the summary"     'ACT NOW: SIGNS OF THE MADEPKG 9\.9\.9 MALWARE' "$WORK/mu-py.txt"
has    "and row 05 names it"                          'signs of the Madepkg malware\. Act now' "$WORK/mu-py.txt"
rm -rf "$WORK/mu-plat"; cp -R "$WORK/clean" "$WORK/mu-plat"; rm -rf "$WORK/mu-plat/.config/opencode" "$WORK/mu-plat/.railway"
mups "$WORK/mu-plat" "$WORK/mu-none.txt" compact
# The summary row is cut at 80 columns, so only its start is checked.
has    "a clean home: row 05 counts the made-up ones" 'none of the 8 recent leaks it checks' "$WORK/mu-none.txt"
mkdir -p "$WORK/mu-plat/.config/madeplat"
mups "$WORK/mu-plat" "$WORK/mu-plat.txt" compact
has    "a made-up platform alone gives its summary"   'Madeplat CLI found: rotate secrets stored there' "$WORK/mu-plat.txt"
rm -rf "$WORK/mu-upd"; cp -R "$WORK/clean" "$WORK/mu-upd"; mkdir -p "$WORK/mu-upd/code/u"
printf '{"lockfileVersion":3,"packages":{"node_modules/made-upd-pkg":{"version":"4.5.6","resolved":"https://registry.npmjs.org/made-upd-pkg/-/made-upd-pkg-4.5.6.tgz"}}}\n' > "$WORK/mu-upd/code/u/package-lock.json"
mups "$WORK/mu-upd" "$WORK/mu-upd.txt"
has    "a made-up update-level hit is a version to update" 'npm worms a bad version to update' "$WORK/mu-upd.txt"
hasnot "and not a compromised machine"                'ACT NOW|Treat this machine as compromised' "$WORK/mu-upd.txt"
rm -rf "$WORK/mu-act"; cp -R "$WORK/clean" "$WORK/mu-act"; mkdir -p "$WORK/mu-act/code/a"
printf '{"lockfileVersion":3,"packages":{"node_modules/made-npm-pkg":{"version":"1.2.3","resolved":"https://registry.npmjs.org/made-npm-pkg/-/made-npm-pkg-1.2.3.tgz"}}}\n' > "$WORK/mu-act/code/a/package-lock.json"
mups "$WORK/mu-act" "$WORK/mu-act.txt"
has    "a made-up act-level npm hit alone: compromised" 'Treat this machine as compromised\. Delete the packages and files listed in section 5' "$WORK/mu-act.txt"
has    "and the link says npm malware"                '&nm=1&py=0&wp=0' "$WORK/mu-act.txt"
# A Python incident's temp file alone: stop and delete, not "don't run Python".
rm -rf "$WORK/mu-tmp"; cp -R "$WORK/clean" "$WORK/mu-tmp"; mkdir -p "$WORK/mu-tmp/AppData/Local/Temp"; : > "$WORK/mu-tmp/AppData/Local/Temp/.madepy_1"
mups "$WORK/mu-tmp" "$WORK/mu-tmp.txt"
has    "a temp file alone: stop and delete, in section 5" 'Stop any process started from these files, then delete them\. Advisory: example\.com' "$WORK/mu-tmp.txt"
has    "and in the fix"                               "Stop any process started from the files listed in section 5, delete them, follow Madepkg's advisory" "$WORK/mu-tmp.txt"
hasnot "no environment to stop running Python in"    "Don't run Python" "$WORK/mu-tmp.txt"

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
if [ "$T" -le 20 ]; then ok "it finishes quickly (${T}s)"; else bad "it finishes quickly, took ${T}s"; fi
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
has    "npm's cache that hits the limit is not called clean" 'npm worms +not fully checked: 1 file took too long' "$WORK/slow-to.txt"
has    "and the summary row is not green"      'Recent leaks +npm packages not fully checked' "$WORK/slow-to-c.txt"
cp -R "$WORK/clean" "$WORK/pyc"
SP="$WORK/pyc/code/winpy/.venv/Lib/site-packages"; mkdir -p "$SP/__pycache__"; printf 'home = C:\\Python312\n' > "$WORK/pyc/code/winpy/.venv/pyvenv.cfg"
: > "$SP/__pycache__/cook.cpython-312.pyc"
psrun "$WORK/pyc" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/pyc.txt"
psrun "$WORK/pyc" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/pyc-full.txt"
has    "a cook.pyc in a Windows venv is a possible leftover" 'possible LiteLLM leftover: check cook\.pyc' "$WORK/pyc.txt"
has    "and is listed with its folder"         'possible leftover ~/code/winpy/\.venv/Lib/site-packages: cook\.pyc' "$WORK/pyc-full.txt"
hasnot "but it is not an act-now hit"          'Act now|ACT NOW' "$WORK/pyc-full.txt"
printf 'import cook\n' > "$SP/cook.pth"
psrun "$WORK/pyc" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/pth.txt"
has    "cook.pth next to it is an act-now hit" 'signs of the LiteLLM malware\. Act now' "$WORK/pth.txt"
rm -rf "$WORK/conda"; cp -R "$WORK/clean" "$WORK/conda"
mkdir -p "$WORK/conda/tools/miniconda3/Lib/site-packages/litellm-1.107.0.dist-info"
psrun "$WORK/conda" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/conda.txt"
has    "LiteLLM 1.107.0 in a conda install outside the usual places is found" 'signs of the LiteLLM malware\. Act now' "$WORK/conda.txt"
cp -R "$WORK/clean" "$WORK/inst"; mkdir -p "$WORK/inst/AppData/Local/Programs/Python/Python312/Lib/site-packages/litellm-1.107.0.dist-info"
psrun "$WORK/inst" GIRD_CHECK_COMPACT=1 -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/inst.txt"
has    "finds 1.107.0 in the python.org install folder" 'signs of the LiteLLM malware\. Act now' "$WORK/inst.txt"
cp -R "$WORK/clean" "$WORK/mark"; : > "$WORK/mark/AppData/Local/Temp/.pc_once_1"
psrun "$WORK/mark" -- -Offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mark.txt"
has    "finds a malware marker in TEMP"        'signs of the malware found ~/AppData/Local/Temp/\.pc_once_1' "$WORK/mark.txt"

echo "saving the report"
mkdir -p "$WORK/cwd"
(cd "$WORK/cwd" && psrun "$WORK/home" -- -Offline -Save > "$WORK/save.txt" 2>&1)
SAVED=$(find "$WORK/cwd" -name 'gird-ai-key-check-*.txt' | head -n 1)
if [ -n "$SAVED" ]; then ok "-Save writes a report"; else bad "-Save writes a report"; fi
if [ -n "$SAVED" ] && grep -q 'KEYS IN PLAIN TEXT' "$SAVED" && ! grep -aqF -f "$WORK/keys.txt" "$SAVED"; then ok "the report has every detail and no planted key"; else bad "the report has every detail and no planted key"; fi

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
has    "shows how this computer compares"      'Better than 72% of AI builders who ran Blindspot' "$OUT"
has    "says one of the first 1,000"           "You're one of the first 1,000 AI builders to run Blindspot\." "$OUT"
hasnot "never shows the place in line"         "AI builder #|#142" "$OUT"
RID=$(grep -oE '"run_id":"[0-9a-f]{16}"' "$WORK/report-ps.json" | cut -d'"' -f4)
has    "the link carries the percentile, run ID, rank and key counts" "blindspot/card/#v=2&s=[0-9]+&g=[ABCDF]&.*&pc=72&pn=1234&u=${RID:-no-run-id}&r=142&sk=2&hk=2&ag=[a-z0-9.-]*&nm=[01]&py=[01]&wp=[01]\$" "$OUT"
psrun "$WORK/home" GIRD_CHECK_API="$API" -- > /dev/null 2>&1
if grep -q '"device_id":""' "$(printf '%s' "$WORK/received.log")" && [ "$(grep -c . "$WORK/received.log")" -eq 2 ]; then ok "with no MachineGuid the device ID is empty"; else bad "with no MachineGuid the device ID is empty"; fi

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
if [ -n "$B_LINK" ] && [ "$B_LINK" = "$P_LINK" ]; then ok "the result link has gird-check.sh's parameters in its order"; else bad "the result link has gird-check.sh's parameters"; printf '        bash: %s\n        pwsh: %s\n' "$B_LINK" "$P_LINK"; fi

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
  if grep -qx valid "$WORK/worker.txt"; then ok "the Worker accepts the report and keeps every field"; else bad "the Worker accepts the report"; sed 's/^/        /' "$WORK/worker.txt"; fi
else
  echo "  skip  the Worker check (set GIRD_CHECK_WORKER to gird-website's worker/check-stats.js)"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
