#!/usr/bin/env bash
# Runs gird-check.sh against a fake home folder and checks what it finds, what
# it must never print or send, and how it handles hostile file names. It runs
# the script under every bash it can find: /bin/bash (3.2 on macOS) and the
# bash on PATH.
# shellcheck disable=SC2088  # the patterns match the literal ~ the script prints for home paths
set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT=$PWD/gird-check.sh
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t blindspot)
MOCK_PID=""
trap '[ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
. tests/lib.sh
command -v python3 >/dev/null 2>&1 || { echo "tests/run.sh needs python3: it builds fixtures and runs the local mock with it"; exit 1; }

bash tests/make-fixture.sh "$WORK/home" "$WORK/keys.txt"
bash tests/make-fixture.sh "$WORK/clean" "$WORK/keys-clean.txt" clean

BASHES=/bin/bash
OTHER=$(command -v bash)
if [ -n "$OTHER" ] && [ "$("$OTHER" -c 'echo "$BASH_VERSION"')" != "$(/bin/bash -c 'echo "$BASH_VERSION"')" ]; then BASHES="$BASHES $OTHER"; fi

for B in $BASHES; do
  V=$("$B" -c 'echo "${BASH_VERSINFO[0]}"')
  echo "bash $V ($B)"
  PFX="bash $V: "
  if "$B" -n "$SCRIPT"; then ok "parses"; else bad "parses"; fi
  OUT=$WORK/out-$V.txt
  HOME="$WORK/home" "$B" "$SCRIPT" --offline > "$OUT" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "exits 0"; else bad "exits 0" "got $RC"; fi
  has    "finds keys in the shell profile"       '~/\.zshrc +Anthropic, OpenAI' "$OUT"
  has    "finds keys in shell history"           '~/\.zsh_history +GitHub' "$OUT"
  has    "finds keys in a project .env file"     '~/code/app/\.env +AWS, Groq' "$OUT"
  hasnot "ignores placeholders in .env.example"  'env\.example' "$OUT"
  has    "counts Claude Code MCP servers"        'Claude Code +~/\.claude\.json +3 servers' "$OUT"
  has    "counts Codex MCP servers"              '~/\.codex/config\.toml +2 servers' "$OUT"
  has    "spots a token in an MCP config"        'token in the file' "$OUT"
  has    "flags a key in a Claude allow list"    'code/app/\.claude/settings\.local\.json' "$OUT"
  has    "warns an npm publish would ship it"    'npm publish from this folder would include it' "$OUT"
  hasnot "ignores placeholder allow lists"       'code/lib/\.claude' "$OUT"
  has    "sees an agent that is installed but idle" 'Codex +installed, not used in 30 days' "$OUT"
  has    "finds LiteLLM malware markers"         'signs of the malware found' "$OUT"
  has    "finds the bad package in the uv cache" 'uv cache holds the 1\.107\.0 package' "$OUT"
  has    "counts SSH keys with no passphrase"    '2 SSH private keys, 1 with no passphrase' "$OUT"
  hasnot "never shows a letter grade"           'GRADE [ABCDF]|[Gg]rade [ABCDF]\b' "$OUT"
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
  has    "and is counted under its repo's row" 'The same settings are in' "$OUT"
  has    "a localhost name with a login prefix is not local" 'code/sneaky/\.claude/settings\.json' "$OUT"
  has    "finds any version of a fake AI tool package" 'claud-code 1\.0\.3 \(SANDWORM_MODE worm' "$OUT"
  has    "finds a bad package in npm's cache"    '@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI' "$OUT"
  has    "puts the wiper first"                  'ACT NOW: REMOVE GH-TOKEN-MONITOR BEFORE YOU REVOKE ANY TOKEN' "$OUT"
  has    "lists the wiper's files"               '~/\.config/gh-token-monitor' "$OUT"
  has    "a hook that runs a planted worm file counts as malware" '^ +~/code/cloned/\.claude/settings\.json$' "$OUT"
  has    "full output lists every key file"      '~/\.cursor/mcp\.json +GitHub' "$OUT"
  has    "the offline link has key counts, no run ID or rank" 'blindspot/card/#v=2&.*&u=&r=&sk=2&hk=1&ag=[a-z0-9.-]*&nm=[01]&py=[01]&ex=[01]&wp=[01]$' "$OUT"
  if grep -aqF -f "$WORK/keys.txt" "$OUT"; then bad "never prints a planted key"; else ok "never prints a planted key"; fi
  if LC_ALL=C grep -aq "$(printf '\033')" "$OUT"; then bad "plain output has no escape codes"; else ok "plain output has no escape codes"; fi
  tr -s ' \n' '  ' < "$OUT" > "$WORK/out-flat-incidents.txt"
done
PFX=""

echo "data files"
if bash tools/gen.sh --check > "$WORK/gen.txt" 2>&1; then ok "both scripts match the data files"; else bad "both scripts match the data files"; head -n 8 "$WORK/gen.txt"; fi
# gird-fleet.sh's copy of the ownership walk has its home in gird-check.sh: a hand edit to the copy is drift.
mkdir -p "$WORK/ow"; cp -R gird-check.sh gird-check.ps1 gird-fleet.sh tools data "$WORK/ow/"
sed 's/^    case "\${_oo_m#\* }" in ?\[2367\]?|??\[2367\]) return 1 ;; esac$/    :/' gird-fleet.sh > "$WORK/ow/gird-fleet.sh"
if cmp -s gird-fleet.sh "$WORK/ow/gird-fleet.sh"; then bad "a hand edit to gird-fleet.sh's copy of the ownership walk fails gen.sh --check" "the edit did not apply"
elif ! (cd "$WORK/ow" && bash tools/gen.sh --check > "$WORK/ow.txt" 2>&1) && grep -q 'gird-fleet.sh is out of date' "$WORK/ow.txt"; then ok "a hand edit to gird-fleet.sh's copy of the ownership walk fails gen.sh --check"
else bad "a hand edit to gird-fleet.sh's copy of the ownership walk fails gen.sh --check" "$(cat "$WORK/ow.txt")"; fi

echo "keys in agent sessions"
SE=$WORK/sess; mkdir -p "$SE"
NORG=""; command -v rg >/dev/null 2>&1 || NORG="ripgrep is not installed"
for E in perl rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  HOME="$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=$E bash "$SCRIPT" --offline > "$SE/$E.txt" 2>&1
  sed -n '/Keys in agent sessions/,/^$/p' "$SE/$E.txt" > "$SE/$E.block"
  has    "$E: a key after an escaped newline in a Claude Code session" 'Claude Code +1 file: Hugging Face' "$SE/$E.txt"
  has    "$E: a key in a Codex session"            'Codex +1 file: OpenAI' "$SE/$E.txt"
  has    "$E: a session in another root is listed under its own folder" '^ +~/\.codex/sessions/2026 +1 file$' "$SE/$E.block"
  has    "$E: a key in an Aider history"           'Aider +1 file: Groq' "$SE/$E.txt"
  hasnot "$E: a made-up key is not counted"        'Claude Code .*(Anthropic|AWS|GitHub)' "$SE/$E.block"
  has    "$E: a real key with few different characters counts" 'Codex +1 file: OpenAI, AWS' "$SE/$E.block"
  has    "$E: a compressed session is named as not checked" '1 compressed session file was not checked' "$SE/$E.block"
  has    "$E: says to rotate them"                 'Treat these keys as exposed and rotate them' "$SE/$E.txt"
  has    "$E: names encrypted sessions as not checked" 'Windsurf sessions are stored encrypted, so they were not checked' "$SE/$E.txt"
  if grep -aqF -f "$WORK/keys.txt" "$SE/$E.txt"; then bad "$E: never prints a key"; else ok "$E: never prints a key"; fi
done
SKIPPING=$NORG
if diff -q "$SE/perl.block" "$SE/rg.block" >/dev/null; then ok "perl and ripgrep report the same"; else bad "perl and ripgrep report the same" "$(diff "$SE/perl.block" "$SE/rg.block" | head -n 6)"; fi
SKIPPING=""
# Session files are listed by folder, one row each with its count.
sessfix() {
  _d=$1; shift
  mkdir -p "$_d/.claude/projects" "$_d/AppData/Roaming" "$_d/AppData/Local/Temp"
  for _s in "$@"; do
    _p=${_s%:*}; _c=${_s##*:}
    mkdir -p "$_d/.claude/projects/$_p/s1/subagents"
    for _i in $(seq 1 "$_c"); do printf '{"t":"hf_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu end"}\n' > "$_d/.claude/projects/$_p/s1/subagents/agent-$_i.jsonl"; done
  done
}
LONGP=$(printf 'long-folder-name-%.0s' 1 2 3 4 5 6)tail-marker-end
sessfix "$SE/g1" proj-one:4
sessfix "$SE/g2" proj-few:2 proj-many:5
sessfix "$SE/g3" "$LONGP:12"
G4=(); for _n in $(seq -w 1 23); do G4+=("p$_n:1"); done
sessfix "$SE/g4" "${G4[@]}"
for _g in g1 g2 g3 g4; do
  HOME="$SE/$_g" GIRD_CHECK_SESSIONS_ENGINE=perl bash "$SCRIPT" --offline --all-sessions > "$SE/$_g.txt" 2>&1
  sed -n '/Keys in agent sessions/,/^$/p' "$SE/$_g.txt" > "$SE/$_g.block"
done
has    "several files in one folder collapse into one row with their count" '^ +~/\.claude/projects/proj-one +4 files$' "$SE/g1.block"
hasnot "and are not listed one by one" 'agent-[0-9]+\.jsonl|subagents' "$SE/g1.block"
many=$(grep -an 'proj-many' "$SE/g2.block" | cut -d: -f1); few=$(grep -an 'proj-few' "$SE/g2.block" | cut -d: -f1)
if [ -n "$many" ] && [ -n "$few" ] && [ "$many" -lt "$few" ]; then ok "two folders are ordered by count"; else bad "two folders are ordered by count"; fi
has    "a long folder is shortened in the middle and keeps its end" '^ +~/\.claude/projects/long-.*\.\.\..*tail-marker-end +12 files$' "$SE/g3.block"
has    "more than 20 folders end with how many more" '^ +and 3 more folders$' "$SE/g4.block"
if [ "$(grep -acE '^ +~/\.claude/projects/p[0-9]+ +1 file$' "$SE/g4.block")" -eq 20 ]; then ok "and show 20 of them"; else bad "and show 20 of them"; fi
if cat "$SE"/g?.block | grep -av '✗' | LC_ALL=C awk 'length($0) > 80 { bad = 1 } END { exit bad }'; then ok "no session row is wider than 80 columns"; else bad "no session row is wider than 80 columns"; fi
HOME="$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_STOP_AFTER=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$SE/part.txt"
has    "a partial check says how much it covered" 'Checked the newest 2 of 6 agent session files' "$SE/part.txt"
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl bash "$SCRIPT" --offline > "$SE/clean.txt" 2>&1
has    "a full check with nothing found says so" 'No keys in 2 agent session files\.' "$SE/clean.txt"
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_STOP_AFTER=0 bash "$SCRIPT" --offline > "$SE/clean-part.txt" 2>&1
hasnot "a partial check with nothing found never says no keys" 'No keys in .*agent session' "$SE/clean-part.txt"
has    "and says it was partial"                 'Checked the newest 0 of 2 agent session files' "$SE/clean-part.txt"
HOME="$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=none bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$SE/none.txt"
has    "with no engine the sessions are named as not checked" 'agent session files were not checked: this needs perl or ripgrep' "$SE/none.txt"
# A file that can't be read is not counted as checked.
mkdir -p "$SE/unread/.claude/projects/p"; printf '{}\n' > "$SE/unread/.claude/projects/p/a.jsonl"; printf '{}\n' > "$SE/unread/.claude/projects/p/b.jsonl"; chmod 000 "$SE/unread/.claude/projects/p/b.jsonl"
HOME="$SE/unread" GIRD_CHECK_SESSIONS_ENGINE=perl bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$SE/unread-perl.txt"
has    "perl: an unreadable session is not counted as checked" 'Checked the newest 1 of 2 agent session files' "$SE/unread-perl.txt"
HOME="$SE/unread" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$SE/unread-sum.txt"
has    "the summary row is not a check mark after a partial check" 'Keys in plain text none in files; agent sessions partly checked' "$SE/unread-sum.txt"
SKIPPING=$NORG
{
  HOME="$SE/unread" GIRD_CHECK_SESSIONS_ENGINE=rg bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$SE/unread-rg.txt"
  has    "rg: an unreadable session means partly checked" 'Agent sessions were partly checked' "$SE/unread-rg.txt"
  # A session ripgrep never finishes (a pipe nobody writes to) is stopped when the rest is done.
  mkdir -p "$SE/stuck/.codex"; mkfifo "$SE/stuck/.codex/history.jsonl"
  HOME="$SE/stuck" GIRD_CHECK_SESSIONS_ENGINE=rg bash "$SCRIPT" --offline > "$SE/stuck.txt" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "rg: a stuck ripgrep does not hold up the check"; else bad "rg: a stuck ripgrep does not hold up the check" "exit $RC"; fi
  if pgrep -f 'field-match-separator' >/dev/null 2>&1; then bad "rg: no ripgrep process is left running"; pkill -f 'field-match-separator'; else ok "rg: no ripgrep process is left running"; fi
  HOME="$SE/stuck" GIRD_CHECK_SESSIONS_ENGINE=rg GIRD_CHECK_MIN_SECONDS=120 bash "$SCRIPT" --offline > /dev/null 2>&1 &
  BP=$!
  for _i in $(seq 1 100); do [ -n "$SKIPPING" ] && break; pgrep -f 'field-match-separator' >/dev/null 2>&1 && break; sleep 0.1; done   # safety ceiling while it starts
  kill -HUP "$BP" 2>/dev/null; wait "$BP" 2>/dev/null
  if pgrep -f 'field-match-separator' >/dev/null 2>&1; then bad "rg: HUP leaves no ripgrep process"; pkill -f 'field-match-separator'; else ok "rg: HUP leaves no ripgrep process"; fi
}
SKIPPING=""
# A long token that crosses a 1 MB piece is not mistaken for a key.
mkdir -p "$SE/piece/.claude/projects/p"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 40) + 'hf_' + 'Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAuCiEoXkYnZqWdTgPrMsBvLj' + '\n')" "$SE/piece/.claude/projects/p/a.jsonl"
mkdir -p "$SE/esc/.claude/projects/p"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 2) + '\\\\n' + 'hf_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu end' + '\n')" "$SE/esc/.claude/projects/p/a.jsonl"
mkdir -p "$SE/esc2/.claude/projects/p"
python3 -c "import sys; open(sys.argv[1], 'w').write(' ' * (1048576 - 1) + '\\\\' + 'nhf_Kx7Qm2Rt9Lp4Vz8Nw3Hy6Jb5Fc1Gd0SeAu end' + '\n')" "$SE/esc2/.claude/projects/p/a.jsonl"
HOME="$SE/esc2" GIRD_CHECK_SESSIONS_ENGINE=perl bash "$SCRIPT" --offline --all-sessions > "$SE/esc2.txt" 2>&1
has    "perl: a key after a backslash that ends a read is found" 'Claude Code +1 file: Hugging Face' "$SE/esc2.txt"
for E in perl rg; do
  SKIPPING=""; [ "$E" = rg ] && SKIPPING=$NORG
  HOME="$SE/piece" GIRD_CHECK_SESSIONS_ENGINE=$E bash "$SCRIPT" --offline --all-sessions > "$SE/piece-$E.txt" 2>&1
  has    "$E: a token across a piece boundary is not a key" 'No keys in 1 agent session file' "$SE/piece-$E.txt"
  HOME="$SE/esc" GIRD_CHECK_SESSIONS_ENGINE=$E bash "$SCRIPT" --offline --all-sessions > "$SE/esc-$E.txt" 2>&1
  has    "$E: a key after an escaped newline at a piece boundary is found" 'Claude Code +1 file: Hugging Face' "$SE/esc-$E.txt"
done
SKIPPING=""
# A kill -9 of the script stops the perl workers within one piece of a file.
mkdir -p "$SE/k9/.claude/projects/p"
python3 -c "import sys; open(sys.argv[1], 'w').write(('x ' * 524288 + '\n') * 32)" "$SE/k9/.claude/projects/p/a.jsonl"
HOME="$SE/k9" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_SLOW=1 bash "$SCRIPT" --offline --all-sessions > /dev/null 2>&1 &
BP=$!
K9="$SE/k9/.claude/projects"
for _i in $(seq 1 100); do pgrep -f "$K9" >/dev/null 2>&1 && break; sleep 0.1; done   # safety ceiling while it starts
if pgrep -f "$K9" >/dev/null 2>&1; then K9UP=1; else K9UP=0; fi
kill -9 "$BP" 2>/dev/null; wait "$BP" 2>/dev/null
for _i in $(seq 1 10); do pgrep -f "$K9" >/dev/null 2>&1 || break; sleep 0.1; done      # one piece takes 0.3 s here; the file has 32
if [ "$K9UP" -eq 0 ]; then bad "kill -9 of the script stops the workers" "they never started"
elif pgrep -f "$K9" >/dev/null 2>&1; then bad "kill -9 of the script stops the workers"; pkill -f "$K9"; else ok "kill -9 of the script stops the workers"; fi
pkill -f "$SE/k9" 2>/dev/null; rm -f "${TMPDIR:-/tmp}"/blindspot.?????? "${TMPDIR:-/tmp}"/blindspot.??????.fifo 2>/dev/null   # a kill -9 leaves these, as documented

# A held engine is still running when the rest of the check is done: it is stopped, and nothing is left behind.
mkfifo "$SE/hold"
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_HOLD="$SE/hold" bash "$SCRIPT" --offline > "$SE/held.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "a held engine does not hold up the check"; else bad "a held engine does not hold up the check" "exit $RC"; fi
has    "and the report says the sessions were not all checked" 'Checked the newest 0 of 2' "$SE/held.txt"
if pgrep -f GIRD_CHECK_SESSIONS_HOLD >/dev/null 2>&1 || pgrep -f 'SESS_PRE' >/dev/null 2>&1; then bad "no engine process is left running"; else ok "no engine process is left running"; fi
# Closing the terminal (HUP) mid-check stops the engine too.
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_HOLD="$SE/hold" GIRD_CHECK_MIN_SECONDS=120 bash "$SCRIPT" --offline > /dev/null 2>&1 &
BP=$!
for _i in $(seq 1 100); do pgrep -f 'SESS_PRE' >/dev/null 2>&1 && break; sleep 0.1; done   # safety ceiling while it starts
kill -HUP "$BP" 2>/dev/null; wait "$BP" 2>/dev/null
if pgrep -f 'SESS_PRE' >/dev/null 2>&1; then bad "HUP leaves no engine process"; pkill -f 'SESS_PRE'; else ok "HUP leaves no engine process"; fi
if ls "${TMPDIR:-/tmp}"/blindspot.* >/dev/null 2>&1 && ls -l "${TMPDIR:-/tmp}"/blindspot.*.fifo >/dev/null 2>&1; then bad "no fifo is left behind"; else ok "no fifo is left behind"; fi

# Keys pass through the fifo, so only the person running the check can open it, whatever the umask.
mkdir -p "$SE/tmpd"
( umask 022; HOME="$WORK/clean" TMPDIR="$SE/tmpd" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_HOLD="$SE/hold" GIRD_CHECK_MIN_SECONDS=120 bash "$SCRIPT" --offline > /dev/null 2>&1 ) &
BP=$!
for _i in $(seq 1 100); do ls "$SE/tmpd"/blindspot.*.fifo >/dev/null 2>&1 && break; sleep 0.1; done   # safety ceiling while it starts
_fm=$(ls -l "$SE/tmpd"/blindspot.*.fifo 2>/dev/null | cut -c1-10)
if [ "$_fm" = "prw-------" ]; then ok "the fifo keys pass through is the owner's only"; else bad "the fifo keys pass through is the owner's only" "${_fm:-no fifo}"; fi
kill -HUP "$BP" 2>/dev/null; wait "$BP" 2>/dev/null; pkill -f 'SESS_PRE' 2>/dev/null
echo "one version"
# The release version is written in both headers and in every banner: they must all agree, and match
# the newest CHANGELOG release.
_v() { grep -oE 'version [0-9]+\.[0-9]+\.[0-9]+ \([0-9]+ [A-Z][a-z]+ [0-9]{4}\)' "$1" | head -n 1; }
VSH=$(_v gird-check.sh); VPS=$(_v gird-check.ps1)
VNUM=$(printf '%s' "$VSH" | awk '{print $2}')
VDAY=$(printf '%s' "$VSH" | sed -E 's/.*\(([0-9]+) ([A-Z][a-z][a-z])[a-z]* ([0-9]{4})\)/\1 \2 \3/')
if [ -n "$VSH" ] && [ "$VSH" = "$VPS" ]; then ok "both scripts carry the same version and date"; else bad "both scripts carry the same version and date"; fi
BAN=$(grep -ohE 'v[0-9]+\.[0-9]+\.[0-9]+ (·|\$gMid) [0-9]+ [A-Z][a-z]{2} [0-9]{4}' gird-check.sh gird-check.ps1)
NB=$(printf '%s\n' "$BAN" | grep -c .); NGOOD=$(printf '%s\n' "$BAN" | grep -cE "^v$VNUM .* $VDAY\$")
if [ "$NB" -ge 3 ] && [ "$NB" -eq "$NGOOD" ]; then ok "every banner shows that version and date"; else bad "every banner shows that version and date"; fi
if [ "$(grep -m1 -E '^## [0-9]' CHANGELOG.md | awk '{print $2}' | tr -d ,)" = "$VNUM" ]; then ok "the newest CHANGELOG release is that version"; else bad "the newest CHANGELOG release is that version"; fi

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
HOME="$RV" bash "$SCRIPT" --offline > "$WORK/rv.txt" 2>&1
tr -s ' \n' '  ' < "$WORK/rv.txt" > "$WORK/rv-flat.txt"
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
has    "and its package"                               'axios 1\.14\.1 \(Axios takeover' "$WORK/rv.txt"
has    "two unrelated repos with the same settings are both listed (1)" 'p/r1/\.claude/settings\.json' "$WORK/rv.txt"
has    "two unrelated repos with the same settings are both listed (2)" 'p/r2/\.claude/settings\.json' "$WORK/rv.txt"
hasnot "a bun override pinning away is not a hit"      'code/bunpin/' "$WORK/rv.txt"
mkdir -p "$WORK/escq/p/.claude" "$WORK/vsp/p/.vscode"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node \\"$CLAUDE_PROJECT_DIR\\"/.claude/router_runtime.js"}]}]}}\n' > "$WORK/escq/p/.claude/settings.json"
mkdir -p "$WORK/escq/q/.claude" "$WORK/escq/w/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node.exe .claude/setup.mjs"}]}]}}\n' > "$WORK/escq/q/.claude/settings.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node .claude\\\\setup.mjs"}]}]}}\n' > "$WORK/escq/w/.claude/settings.json"
HOME="$WORK/escq" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/escq.txt"
has    "a hook running a worm file through an escaped path is malware" '~/p/\.claude/settings\.json runs a file the TanStack' "$WORK/escq.txt"
has    "node.exe counts as running it"                 '~/q/\.claude/settings\.json runs a file the TanStack' "$WORK/escq.txt"
has    "a Windows backslash path counts"               '~/w/\.claude/settings\.json runs a file the TanStack' "$WORK/escq.txt"
printf 'x\n' > "$WORK/vsp/p/.vscode/setup.mjs"
HOME="$WORK/vsp" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/vsp.txt"
has    "a planted .vscode/setup.mjs is found"          'p/\.vscode/setup\.mjs a file the TanStack and keyv worms plant' "$WORK/vsp.txt"
HOME="$WORK/clean" bash "$SCRIPT" --offline > "$WORK/clean-npm.txt" 2>&1
has    "the clean line counts versions and packages apart" 'none of [0-9]+ bad versions or [0-9]+ bad packages' "$WORK/clean-npm.txt"
# A folder of npm's cache that can't be read.
cp -R "$WORK/clean" "$WORK/npmno"; mkdir -p "$WORK/npmno/.npm/_cacache/index-v5/aa"; chmod 000 "$WORK/npmno/.npm/_cacache/index-v5/aa"
HOME="$WORK/npmno" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno.txt"
HOME="$WORK/npmno" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/npmno-c.txt"
chmod 755 "$WORK/npmno/.npm/_cacache/index-v5/aa"
has    "an unreadable cache folder is not called clean" "npm worms not fully checked: part of npm's cache could not be read" "$WORK/npmno.txt"
has    "and the summary row is not green either"       'Recent leaks npm packages not fully checked: cache unreadable' "$WORK/npmno-c.txt"
awk '/WHAT TO DO/{f=1} f' "$WORK/rv.txt" | tr -s ' \n' '  ' > "$WORK/rv-todo.txt"
if awk '{ a = index($0, "Delete the saved Claude Code commands"); b = index($0, "Read the settings marked"); exit !(a && b && a < b) }' "$WORK/rv-todo.txt"; then ok "a red allow-list fix comes before the yellow settings fix"; else bad "a red allow-list fix comes before the yellow settings fix"; fi
# Wiper: Linux steps, and every other rotate waits for it.
cp -R "$WORK/home" "$WORK/wl"; mkdir -p "$WORK/fakebin"
printf '#!/bin/sh\nif [ "$1" = -s ]; then echo Linux; else exec /usr/bin/uname "$@"; fi\n' > "$WORK/fakebin/uname"; chmod +x "$WORK/fakebin/uname"
HOME="$WORK/wl" PATH="$WORK/fakebin:$PATH" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/wl.txt"
has    "Linux is told how to stop the wiper"           'systemctl --user disable --now gh-token-monitor\.service' "$WORK/wl.txt"
hasnot "Linux is not given the Mac command"            'launchctl bootout' "$WORK/wl.txt"
has    "other rotate fixes wait for the wiper"         'then rotate them\. Only once gh-token-monitor is stopped and removed' "$WORK/wl.txt"
has    "section 5's rotate fixes wait for it too"      'rotate every key this machine could reach\. Only once gh-token-monitor is stopped and removed' "$WORK/wl.txt"
hasnot "the wiper's own fix does not wait for itself"  'Then rotate every key this machine could reach\. Only once' "$WORK/wl.txt"
has    "the link flags npm malware and the wiper"      'nm=1&py=0&ex=0&wp=1$' "$WORK/out-$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}').txt"
# npm malware and LiteLLM together, no wiper: the summary keeps both.
cp -R "$WORK/home" "$WORK/both"; rm -rf "$WORK/both/.config/gh-token-monitor"
HOME="$WORK/both" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/both.txt"
has    "npm and LiteLLM malware together are both named" 'npm and LiteLLM malware found' "$WORK/both.txt"
# LiteLLM alone still leads the summary.
cp -R "$WORK/clean" "$WORK/lite"; mkdir -p "$WORK/lite/code/py/.venv/lib/python3.12/site-packages/litellm-1.107.0.dist-info"; printf 'home = /usr\n' > "$WORK/lite/code/py/.venv/pyvenv.cfg"
HOME="$WORK/lite" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/lite.txt"
has    "a LiteLLM hit leads the summary"               'ACT NOW: SIGNS OF THE LITELLM 1\.107\.0 MALWARE' "$WORK/lite.txt"

# Where a hit was found, and npm's placeholder for a removed package.
has    "a lockfile hit says it is listed there"      'axios 1\.14\.1 \(Axios takeover, March 2026\), listed in this lockfile' "$WORK/out-flat-incidents.txt"
has    "an install hit says it is installed"         'claud-code 1\.0\.3 \(SANDWORM_MODE worm, February 2026\), installed' "$WORK/out-flat-incidents.txt"
has    "a cache hit says it was downloaded"          "@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI, April 2026\), downloaded into npm's cache" "$WORK/out-flat-incidents.txt"
cp -R "$WORK/clean" "$WORK/ph2"; mkdir -p "$WORK/ph2/code/ph"
printf '{"lockfileVersion":3,"packages":{"node_modules/plain-crypto-js":{"version":"0.0.1-security","resolved":"https://registry.npmjs.org/plain-crypto-js/-/plain-crypto-js-0.0.1-security.tgz"}}}\n' > "$WORK/ph2/code/ph/package-lock.json"
HOME="$WORK/ph2" bash "$SCRIPT" --offline > "$WORK/ph2.txt" 2>&1
hasnot "npm's -security placeholder is not malware" 'plain-crypto-js' "$WORK/ph2.txt"
echo "incidents from data/incidents.tsv"
has    "each npm incident found gets its sourced line" 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it\. cisa\.gov' "$WORK/out-flat-incidents.txt"
cp -R "$WORK/clean" "$WORK/mis"; mkdir -p "$WORK/mis/code/m"
printf '{"lockfileVersion":3,"packages":{"node_modules/@mistralai/mistralai":{"version":"2.2.3","resolved":"https://registry.npmjs.org/@mistralai/mistralai/-/mistralai-2.2.3.tgz"}}}\n' > "$WORK/mis/code/m/package-lock.json"
HOME="$WORK/mis" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mis.txt"
HOME="$WORK/mis" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mis-c.txt"
hasnot "a version whose malware could not run is not 'compromised'" 'ACT NOW|Treat this machine as compromised' "$WORK/mis.txt"
has    "it is a version to update instead"           'npm worms a bad version to update' "$WORK/mis.txt"
has    "with the vendor's own explanation"           'Mistral AI packages, May 2026: published with malware that Mistral says could not run\. docs\.mistral\.ai' "$WORK/mis.txt"
has    "and a fix to update it"                      'Update the npm packages listed in section 5 to a version without the malware' "$WORK/mis.txt"
has    "the summary row says so in yellow"           'Recent leaks an npm package to update' "$WORK/mis-c.txt"
hasnot "it does not outrank moving keys out of plain text" 'First fix: Update the npm packages' "$WORK/mis-c.txt"
has    "the link does not call it npm malware"       '&nm=0&py=0&ex=0&wp=0( |$)' "$WORK/mis.txt"
hasnot "a Mistral hit does not get Injective's wallet fix" 'Move the funds' "$WORK/mis.txt"
cp -R "$WORK/clean" "$WORK/mpy"; mkdir -p "$WORK/mpy/code/venv/lib/site-packages/mistralai-2.4.6.dist-info"
HOME="$WORK/mpy" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mpy.txt"
has    "mistralai 2.4.6 from PyPI is its own act-now row" 'mistralai 2\.4\.6 +signs of the malware found ~/code/venv/lib/site-packages: mistralai 2\.4\.6' "$WORK/mpy.txt"
has    "with its fix"                                "Treat this machine as compromised\. Don't run Python in the affected environments, follow mistralai's advisory" "$WORK/mpy.txt"
has    "the link flags a Python incident, not LiteLLM" '&ll=0&.*&py=1&' "$WORK/mpy.txt"
# /tmp/transformers.pyz is a Linux-only sign: the uname is faked, the temp folder is the fixture's.
cp -R "$WORK/clean" "$WORK/mpyt"; mkdir -p "$WORK/mpyt/tmp" "$WORK/linbin"; : > "$WORK/mpyt/tmp/transformers.pyz"
printf '#!/bin/sh\nif [ "$1" = -s ]; then echo Linux; else exec /usr/bin/uname "$@"; fi\n' > "$WORK/linbin/uname"; chmod +x "$WORK/linbin/uname"
HOME="$WORK/mpyt" TMPDIR="$WORK/mpyt/tmp" PATH="$WORK/linbin:$PATH" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mpyt-linux.txt"
mkdir -p "$WORK/macbin2"; printf '#!/bin/sh\nif [ "$1" = -s ]; then echo Darwin; else exec /usr/bin/uname "$@"; fi\n' > "$WORK/macbin2/uname"; chmod +x "$WORK/macbin2/uname"
HOME="$WORK/mpyt" TMPDIR="$WORK/mpyt/tmp" PATH="$WORK/macbin2:$PATH" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mpyt-mac.txt"
has    "on Linux, transformers.pyz is the mistralai hit" 'mistralai 2\.4\.6 +signs of the malware found ~/tmp/transformers\.pyz' "$WORK/mpyt-linux.txt"
has    "and the link flags it"                        '&ll=0&.*&py=1&' "$WORK/mpyt-linux.txt"
has    "on a Mac it is not looked for"                'mistralai 2\.4\.6 +no signs' "$WORK/mpyt-mac.txt"
has    "a temp file alone: stop and delete, in section 5" 'Stop any process started from these files, then delete them\. Advisory: docs\.mistral\.ai' "$WORK/mpyt-linux.txt"
has    "and in the fix"                               'Stop any process started from the files listed in section 5, delete them, follow mistralai.s advisory' "$WORK/mpyt-linux.txt"
hasnot "no environment to stop running Python in"    "Don't run Python" "$WORK/mpyt-linux.txt"
# A version read from a folder name is printed with control characters replaced.
cp -R "$WORK/clean" "$WORK/esc"; mkdir -p "$WORK/esc/code/venv/lib/site-packages/litellm-1.0$(printf '\033')[31m.dist-info"
HOME="$WORK/esc" bash "$SCRIPT" --offline --full > "$WORK/esc.txt" 2>&1
if grep -q "1\.0$(printf '\033')\[31m" "$WORK/esc.txt"; then bad "a hostile LiteLLM folder name sends no escape code"; else ok "a hostile LiteLLM folder name sends no escape code"; fi
has    "it is shown with a ? instead"                 'installed: 1\.0\?\[31m' "$WORK/esc.txt"
# uv's cache: the exact version only.
cp -R "$WORK/clean" "$WORK/uvn"; mkdir -p "$WORK/uvn/.cache/uv/wheels-v5/mistralai-2.4.60-py3-none-any" "$WORK/uvn/.cache/uv/archive-v0/x/mistralai-2.4.6.post1.dist-info"
HOME="$WORK/uvn" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/uvn.txt"
hasnot "uv's cache: 2.4.60 and 2.4.6.post1 are not 2.4.6" 'uv cache holds the 2\.4\.6 package' "$WORK/uvn.txt"
mkdir -p "$WORK/uvn/.cache/uv/archive-v0/y/mistralai-2.4.6.dist-info"
HOME="$WORK/uvn" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/uvn2.txt"
has    "uv's cache: 2.4.6 itself is"                  'uv cache holds the 2\.4\.6 package\. Clear it with: uv cache clean mistralai' "$WORK/uvn2.txt"

echo "advice by OS"
mkdir -p "$WORK/fakebin"
for O in Darwin Linux FreeBSD MINGW64_NT-10.0; do
  printf '#!/bin/sh\nif [ "$1" = -s ]; then echo %s; else exec /usr/bin/uname "$@"; fi\n' "$O" > "$WORK/fakebin/uname"; chmod +x "$WORK/fakebin/uname"
  HOME="$WORK/home" PATH="$WORK/fakebin:$PATH" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/os-$O.txt"   # the advice wraps, so it is matched on one line
done
has    "Linux is pointed at its keyring"        'GNOME Keyring or KWallet' "$WORK/os-Linux.txt"
hasnot "Linux is not told to use the Keychain"  'macOS Keychain' "$WORK/os-Linux.txt"
has    "another OS is pointed at a secrets manager" 'files into a secrets manager, then rotate' "$WORK/os-FreeBSD.txt"
hasnot "another OS is not told to use the Keychain" 'macOS Keychain' "$WORK/os-FreeBSD.txt"
has    "Windows bash is pointed at Credential Manager" 'into Windows Credential Manager or a secrets manager' "$WORK/os-MINGW64_NT-10.0.txt"
has    "macOS is pointed at the Keychain"       'into the macOS Keychain' "$WORK/os-Darwin.txt"

echo "Windows: Git Bash, MSYS, Cygwin"
# A fake C: drive under $WORK/win, with the Windows profile at C:\Users\me. Fake
# uname, reg and cygpath stand in for Windows, and a minimal PATH hides any agent
# installed on this machine. Git Bash's HOME is a different folder here, as on Cygwin.
WR=$WORK/win; WP=$WR/Users/me; WB=$WORK/winbin
mkdir -p "$WB" "$WR/Temp" "$WR/msyshome"
K_ANT=$(sed -n 1p "$WORK/keys.txt"); K_AWS=$(sed -n 4p "$WORK/keys.txt"); K_GROQ=$(sed -n 5p "$WORK/keys.txt")
mkdir -p "$WP/.claude/projects/p" "$WP/AppData/Roaming/Claude" "$WP/AppData/Roaming/Code/User" "$WP/AppData/Local/Programs/cursor" \
  "$WP/AppData/Roaming/Block/goose/config" "$WP/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine" \
  "$WP/AppData/Roaming/GitHub CLI" "$WP/AppData/Local/Programs/Python/Python312/Lib/site-packages" \
  "$WP/AppData/Local/uv/cache/wheels-v5/pypi/litellm/litellm-1.107.0-py3-none-any"
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
: > "$WR/Temp/.pc_once_1"
printf 'export GROQ_API_KEY=%s\n' "$K_GROQ" > "$WR/msyshome/.bash_history"
printf '#!/bin/sh\n[ "$1" = -s ] && { echo "${FAKE_UNAME:-MINGW64_NT-10.0}"; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$WB/uname"
# reg query KEY /v NAME [/reg:64], printed the way reg.exe prints, with CRLF line ends.
cat > "$WB/reg" <<'SH'
#!/bin/sh
[ "$1" = query ] && [ "$3" = /v ] || exit 1
case "$2|$4" in
  'HKLM\SOFTWARE\Microsoft\Cryptography|MachineGuid') v=$FAKE_GUID ;;
  'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion|CurrentBuildNumber') v=${FAKE_BUILD:-} ;;
  *) exit 1 ;;
esac
[ -n "$v" ] || exit 1
printf '\r\nHKEY_LOCAL_MACHINE\\x\r\n    %s    REG_SZ    %s\r\n\r\n' "$4" "$v"
SH
cat > "$WB/cygpath" <<'SH'
#!/bin/sh
[ "$1" = -u ] || exit 1
printf '%s\n' "$2" | tr '\\' / | sed "s#^[Cc]:#$FAKE_ROOT#"
SH
chmod +x "$WB/uname" "$WB/reg" "$WB/cygpath"
JQ=$(command -v jq 2>/dev/null); [ -n "$JQ" ] && ln -sf "$JQ" "$WB/jq"
GUID='3F2504E0-4f89-11D3-9A0C-0305E82C3301'
winrun() { # runs the script as Git Bash on Windows 11, x64, in Windows Terminal; extra args go to the script
  env -u __CFBundleIdentifier -u TERM_PROGRAM -u TMPDIR HOME="$WR/msyshome" USERPROFILE='C:\Users\me' \
    APPDATA='C:\Users\me\AppData\Roaming' LOCALAPPDATA='C:\Users\me\AppData\Local' TEMP='C:\Temp' \
    FAKE_ROOT="$WR" FAKE_GUID="$GUID" FAKE_BUILD="${FAKE_BUILD-22631}" PROCESSOR_ARCHITECTURE=AMD64 WT_SESSION=1 \
    PATH="$WB:/usr/bin:/bin" bash "$SCRIPT" "$@"
}
winrun --offline > "$WORK/win.txt" 2>&1
tr -s ' \n' '  ' < "$WORK/win.txt" > "$WORK/win1.txt"
has    "Windows: finds Claude Desktop in AppData"       'Claude Desktop +used in the last 30 days' "$WORK/win.txt"
has    "Windows: finds Cursor and its use in AppData"   'Cursor +used in the last 30 days' "$WORK/win.txt"
has    "Windows: finds Goose in its Windows config"     'Goose +installed' "$WORK/win.txt"
has    "Windows: Claude Code in the Windows profile"    'Claude Code +used in the last 30 days' "$WORK/win.txt"
has    "Windows: reads Claude Desktop's MCP config"     'Claude Desktop +~/AppData/Roaming/Claude/claude_desktop_config\.json.*token in the file' "$WORK/win1.txt"
has    "Windows: reads VS Code's MCP config"            'VS Code +~/AppData/Roaming/Code/User/mcp\.json' "$WORK/win1.txt"
has    "Windows: reads Goose's MCP config"              'Goose +~/AppData/Roaming/Block/goose/config/config\.yaml' "$WORK/win1.txt"
has    "Windows: flags a key in PowerShell history"     '~/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history\.txt +AWS' "$WORK/win1.txt"
has    "Windows: keys in the shell's own home too"      'msyshome/\.bash_history +Groq' "$WORK/win1.txt"
has    "Windows: finds LiteLLM files in Windows Python" 'Programs/Python/Python312/Lib/site-packages: cook\.pth' "$WORK/win1.txt"
has    "Windows: finds the markers in %TEMP%"           'Temp/\.pc_once_1' "$WORK/win1.txt"
has    "Windows: finds the bad package in uv's cache"   'uv cache holds the 1\.107\.0 package' "$WORK/win1.txt"
has    "Windows: finds _netrc"                          'saved passwords in _netrc' "$WORK/win1.txt"
has    "Windows: finds the GitHub CLI login in AppData" 'GitHub CLI token' "$WORK/win1.txt"
if grep -aqF -f "$WORK/keys.txt" "$WORK/win.txt"; then bad "Windows: never prints a planted key"; else ok "Windows: never prints a planted key"; fi

echo "WSL"
mkdir -p "$WORK/proc-wsl/sys/kernel" "$WORK/proc-linux/sys/kernel"
printf '5.15.153.1-microsoft-standard-WSL2\n' > "$WORK/proc-wsl/sys/kernel/osrelease"
printf '6.8.0-45-generic\n' > "$WORK/proc-linux/sys/kernel/osrelease"
printf 'Linux version 6.8.0-45-generic (buildd@ubuntu)\n' > "$WORK/proc-linux/version"
wslrun() { # proc-dir: runs the script as Linux with that /proc
  HOME="$WORK/home" FAKE_UNAME=Linux GIRD_CHECK_PROC="$1" PATH="$WB:/usr/bin:/bin" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  '
}
wslrun "$WORK/proc-wsl" > "$WORK/wsl.txt"
wslrun "$WORK/proc-linux" > "$WORK/notwsl.txt"
has    "WSL is pointed at a secrets manager"            'files into a secrets manager, then rotate' "$WORK/wsl.txt"
hasnot "WSL is not told to use a desktop keyring"       'GNOME Keyring' "$WORK/wsl.txt"
has    "WSL says Windows-side files were not checked"   'inside WSL, so files on the Windows side were not checked' "$WORK/wsl.txt"
if grep -q 'inside WSL' "$WORK/wsl.txt" && ! grep -q 'inside WSL' "$WORK/notwsl.txt" && grep -q 'GNOME Keyring or KWallet' "$WORK/notwsl.txt"; then
  ok "only WSL, not plain Linux, gets the WSL note and loses the keyring advice"
else bad "only WSL, not plain Linux, gets the WSL note and loses the keyring advice"; fi

echo "placeholders"
mkdir -p "$WORK/ph/code/ph/.claude"
printf '{"mcpServers":{"x":{"command":"npx","env":{"API_KEY":"your-api-key-goes-here"}}}}\n' > "$WORK/ph/code/ph/.mcp.json"
# A placeholder shaped like a real command key, which only the placeholder screen stops.
printf '{"name":"ph","private":true}\n' > "$WORK/ph/code/ph/package.json"
printf '{"permissions":{"allow":["Bash(OPENAI_API_KEY=your-openai-key-goes-here npm test)"]}}\n' > "$WORK/ph/code/ph/.claude/settings.local.json"
HOME="$WORK/ph" PATH=/usr/bin:/bin GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ph.txt"
has    "a placeholder token is not a token"    'MCP servers +1 server, no tokens in their configs' "$WORK/ph.txt"
has    "a placeholder key in an allow list is not a key" 'Allow lists +no saved commands with keys' "$WORK/ph.txt"

echo "Zeabur and the LiteLLM leftovers"
# A minimal PATH hides any opencode, railway or zeabur command on this machine, so
# only the files in the fake home decide.
lp() { HOME="$1" PATH=/usr/bin:/bin GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  '; }
lpf() { HOME="$1" PATH=/usr/bin:/bin bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  '; }
cp -R "$WORK/clean" "$WORK/zb-none"; rm -rf "$WORK/zb-none/.config/opencode" "$WORK/zb-none/.local/share/opencode" "$WORK/zb-none/.railway"
lp "$WORK/zb-none" > "$WORK/zb-none.txt"
has    "no leaks found: row 05 counts the leaks it checks" 'none of the 6 recent leaks it checks' "$WORK/zb-none.txt"
cp -R "$WORK/zb-none" "$WORK/zb-one"; mkdir -p "$WORK/zb-one/.config/zeabur"
lp "$WORK/zb-one" > "$WORK/zb-one.txt"
lpf "$WORK/zb-one" > "$WORK/zb-one-full.txt"
has    "Zeabur alone is flagged"               'Zeabur CLI found: rotate secrets stored there' "$WORK/zb-one.txt"
has    "Zeabur adds a fix naming only what was found" 'If you used Zeabur, rotate the keys stored there' "$WORK/zb-one-full.txt"
has    "Zeabur has its own detail line"        'Zeabur CLI found' "$WORK/zb-one-full.txt"
cp -R "$WORK/zb-one" "$WORK/zb-two"; mkdir -p "$WORK/zb-two/.railway"; printf '{}\n' > "$WORK/zb-two/.railway/config.json"
lp "$WORK/zb-two" > "$WORK/zb-two.txt"
has    "Railway and Zeabur are named together" 'Railway and Zeabur found: rotate their keys' "$WORK/zb-two.txt"
cp -R "$WORK/zb-two" "$WORK/zb-three"; mkdir -p "$WORK/zb-three/.config/opencode"
lp "$WORK/zb-three" > "$WORK/zb-three.txt"
has    "all three are named in order"          'OpenCode, Railway and Zeabur found: rotate keys' "$WORK/zb-three.txt"
cp -R "$WORK/zb-none" "$WORK/zb-pyc"; mkdir -p "$WORK/zb-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__"
: > "$WORK/zb-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__/cook.cpython-312.pyc"
lp "$WORK/zb-pyc" > "$WORK/zb-pyc.txt"
lpf "$WORK/zb-pyc" > "$WORK/zb-pyc-full.txt"
has    "a leftover cook.pyc is listed as a possible leftover" 'possible leftover.*site-packages: cook\.pyc' "$WORK/zb-pyc-full.txt"
has    "and row 05 asks to check it"           'possible LiteLLM leftover: check cook\.pyc' "$WORK/zb-pyc.txt"
hasnot "but it is not an act-now hit"          'Act now|ACT NOW' "$WORK/zb-pyc-full.txt"
hasnot "no pyc, no malware flag"               'Act now|possible LiteLLM leftover' "$WORK/zb-none.txt"
cp -R "$WORK/zb-pyc" "$WORK/zb-pyc-strong"; printf 'import cook\n' > "$WORK/zb-pyc-strong/code/py/.venv/lib/python3.12/site-packages/cook.pth"
lp "$WORK/zb-pyc-strong" > "$WORK/zb-pyc-strong.txt"
cp -R "$WORK/zb-pyc" "$WORK/zb-pyc-oc"; mkdir -p "$WORK/zb-pyc-oc/.config/opencode"
lpf "$WORK/zb-pyc-oc" > "$WORK/zb-pyc-oc.txt"
has    "a weak pyc and OpenCode both show in the details"  'possible leftover.*OpenCode +installed' "$WORK/zb-pyc-oc.txt"
has    "a weak pyc shows in row 05 and the fix list"       'A leftover cook\.pyc can come from the LiteLLM 1\.107\.0 malware' "$WORK/zb-pyc-oc.txt"
# Idle agents are found on any Mac (Claude Desktop is in /Applications), so a copy of the
# script that ignores them stands in for a machine with no idle agent.
sed 's/\[ "\$N_IDLE" -gt 0 \]/[ 0 -gt 1 ]/g' "$SCRIPT" > "$WORK/no-idle.sh"
rm -rf "$WORK/ni-empty"; mkdir -p "$WORK/ni-empty"
HOME="$WORK/ni-empty" PATH=/usr/bin:/bin bash "$WORK/no-idle.sh" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-empty.txt"
has    "nothing found: the header says no findings"        'NO FINDINGS IN THIS SCAN' "$WORK/ni-empty.txt"
# The closing paragraph comes with the Argus for Mac pitch, so only macOS shows it;
# other systems keep the plain no-guarantee line and the count in the header.
if [ "$(uname -s)" = Darwin ]; then
  has  "nothing found: it says this is not a guarantee"    'not a .*guarantee' "$WORK/ni-empty.txt"
else
  has  "nothing found: it says this is not a guarantee"    'does not prove nothing leaked' "$WORK/ni-empty.txt"
fi
hasnot "nothing found: no old clean-today wording"         'CLEAN TODAY|needs fixing|Nothing to fix' "$WORK/ni-empty.txt"
rm -rf "$WORK/ni-pyc"; mkdir -p "$WORK/ni-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__"; : > "$WORK/ni-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__/cook.cpython-312.pyc"
HOME="$WORK/ni-pyc" PATH=/usr/bin:/bin bash "$WORK/no-idle.sh" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-pyc.txt"
if [ "$(uname -s)" = Darwin ]; then
  has  "a pyc-only run counts its things to fix"           'It found [0-9]+ things?.*to fix' "$WORK/ni-pyc.txt"
  has  "a pyc-only run still says the scan is a snapshot"  'THIS SCAN IS A SNAPSHOT' "$WORK/ni-pyc.txt"
  skip "a pyc-only run keeps the no-guarantee line"        "needs a system other than macOS"
else
  skip "a pyc-only run still says the scan is a snapshot"  "needs macOS"
  has  "a pyc-only run counts its things to fix"           '[0-9]+ THINGS? TO FIX' "$WORK/ni-pyc.txt"
  has  "a pyc-only run keeps the no-guarantee line"        'does not prove nothing leaked' "$WORK/ni-pyc.txt"
fi
hasnot "a pyc-only run is not told there are no findings"  'NO FINDINGS IN THIS SCAN' "$WORK/ni-pyc.txt"
has    "cook.pth next to the pyc is an act-now hit" 'signs of the LiteLLM malware\. Act now' "$WORK/zb-pyc-strong.txt"

echo "checks from the incident dossier"
# As macOS on any host: the Cursor check reads a macOS app, and the paths below are the Mac's.
DAS="Library/Application Support"
mkdir -p "$WORK/dzbin"; printf '#!/bin/sh\nif [ "$1" = -s ]; then echo Darwin; else exec /usr/bin/uname "$@"; fi\n' > "$WORK/dzbin/uname"; chmod +x "$WORK/dzbin/uname"
for M in hit miss; do
  rm -rf "$WORK/dz-$M"; cp -R "$WORK/clean" "$WORK/dz-$M"; bash tests/make-dossier.sh "$WORK/dz-$M" "$WORK/dz-$M/$DAS" "$M"
  HOME="$WORK/dz-$M" PATH="$WORK/dzbin:/usr/bin:/bin" bash "$SCRIPT" --offline > "$WORK/dz-$M.txt" 2>&1
  tr -s ' \n' '  ' < "$WORK/dz-$M.txt" > "$WORK/dz-$M-flat.txt"
  HOME="$WORK/dz-$M" PATH="$WORK/dzbin:/usr/bin:/bin" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/dz-$M-sum.txt"
done
D=$WORK/dz-hit-flat.txt
has    "Claude Code set to bypass permissions"        '! Claude Code ~/\.claude/settings\.json bypassPermissions' "$D"
has    "Codex set to never ask, with full access"     '! Codex ~/\.codex/config\.toml never asks, full access' "$D"
has    "VS Code's user settings: the global key, not the commented one" 'Code/User/settings\.json chat\.tools\.global\.autoApprove !' "$D"
has    "a workspace .vscode/settings.json the home scan finds" '! VS Code Copilot ~/p/yolo/\.vscode/settings\.json chat\.tools\.autoApprove' "$D"
hasnot "a workspace set to false is not listed"       'p/calm/' "$D"
has    "with the advice"                              'A prompt injection in anything the agent reads can then run commands on this computer\. Turn it off unless the agent runs in a sandbox\.' "$D"
has    "and the fix"                                  'Turn off run-without-asking in the agents listed in section 1, unless they run in a sandbox\.' "$D"
has    "Cursor below the fixed version"               '! Cursor 2\.9\.1, update to 3\.0 or later A prompt injection could escape the sandbox\. github\.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw' "$D"
has    "Amazon Q: the highest version folder, compared as numbers" '! Amazon Q 1\.68\.0, update to 1\.69\.0 or later Opening a hostile workspace' "$D"
has    "Claude Code installed with npm"               '! Claude Code 1\.0\.3, update to 1\.0\.24 or later A web page could reach the editor connection\.' "$D"
has    "mcp-remote installed and in an MCP config's args" '! mcp-remote 0\.0\.5, 0\.1\.10, update to 0\.1\.16 or later A hostile MCP server could run commands\. github\.com/advisories/GHSA-6xpm-ggf7-wc3p' "$D"
has    "with the fix"                                 'Update the tools listed in section 1 that have a security fix\.' "$D"
has    "a link to authorized_keys"                    'Files that link to your SSH logins ✗ ~/code/links/notes\.txt An agent that edits this file adds a login to this computer\. Delete the link\.' "$D"
has    "with the fix to delete the link"              'Delete the links to ~/\.ssh/authorized_keys listed in section 2\.' "$D"
has    "a GlassWorm extension at its bad version, with a platform suffix" '~/\.vscode/extensions/oorzc\.ssh-tools-0\.5\.1-darwin-arm64 oorzc\.ssh-tools 0\.5\.1 \(GlassWorm extensions, January 2026\), installed' "$D"
has    "a GlassWorm extension at any version, its id in another case" '~/\.cursor/extensions/Sol-Studio\.Solidity-Extension-2\.0\.0 sol-studio\.solidity-extension 2\.0\.0 \(GlassWorm' "$D"
has    "with GlassWorm's sourced line"                'GlassWorm extensions, January 2026: stole SSH keys, cloud and npm credentials, keychains and crypto wallets from Macs\. socket\.dev' "$D"
has    "the Injective fix: move the funds out of its wallets" 'Move the funds out of any wallet created or imported with Injective SDK 1\.20\.21, into a new wallet\.' "$D"
has    "the Injective SDK in a lockfile"              '@injectivelabs/sdk-ts 1\.20\.21 \(Injective SDK, July 2026\), listed in this lockfile' "$D"
has    "with its sourced line"                        'Injective SDK, July 2026: sent the seed phrase or private key of any wallet an app created or imported with it\. github\.com' "$D"
dzrun() { _h=$1; shift; env HOME="$_h" PATH="$WORK/dzbin:/usr/bin:/bin" "$@" bash "$SCRIPT" --offline 2>&1; }
has    "an extension hit is not npm malware in the link" '&nm=0&py=0&ex=1&wp=0' "$D"
# Editor extensions: a row, headline and fix of their own, never called npm malware.
rm -rf "$WORK/dz-ext"; cp -R "$WORK/clean" "$WORK/dz-ext"; mkdir -p "$WORK/dz-ext/.vscode/extensions/oorzc.mind-map-1.0.61"
dzrun "$WORK/dz-ext" > "$WORK/dz-ext.txt"; tr -s ' \n' '  ' < "$WORK/dz-ext.txt" > "$WORK/dz-ext-flat.txt"
dzrun "$WORK/dz-ext" GIRD_CHECK_COMPACT=1 | tr -s ' \n' '  ' > "$WORK/dz-ext-sum.txt"
has    "extensions alone: their own row"              'Editor extensions signs of the malware found ~/\.vscode/extensions/oorzc\.mind-map-1\.0\.61 oorzc\.mind-map 1\.0\.61 \(GlassWorm' "$WORK/dz-ext-flat.txt"
has    "extensions alone: their own headline"         'ACT NOW: SIGNS OF MALWARE IN AN EDITOR EXTENSION' "$WORK/dz-ext.txt"
hasnot "extensions alone: no npm in the headline"     'ACT NOW.*NPM' "$WORK/dz-ext.txt"
hasnot "extensions alone: no npm malware row or fix"  'npm worms +signs of the malware|Delete the packages and files listed in section 5|signs of npm malware' "$WORK/dz-ext.txt"
has    "extensions alone: their own fix"              'Treat this machine as compromised\. Uninstall the extensions listed in section 5, delete the files listed there, and rotate every key this machine could reach\.' "$WORK/dz-ext-flat.txt"
has    "extensions alone: their own summary row"      'Recent leaks +signs of malware in an editor extension\. Act now' "$WORK/dz-ext-sum.txt"
has    "extensions alone: the link says ex, not nm"   '&nm=0&py=0&ex=1&wp=0' "$WORK/dz-ext.txt"
cp -R "$WORK/dz-ext" "$WORK/dz-both"; mkdir -p "$WORK/dz-both/code/ax"
printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$WORK/dz-both/code/ax/package-lock.json"
dzrun "$WORK/dz-both" | tr -s ' \n' '  ' > "$WORK/dz-both.txt"
has    "npm and extensions: both rows, each with its own findings" 'npm worms signs of the malware found ~/code/ax/package-lock\.json axios 1\.14\.1 .*Editor extensions signs of the malware found ~/\.vscode/extensions/oorzc\.mind-map' "$WORK/dz-both.txt"
has    "npm and extensions: one headline names both"  'ACT NOW: SIGNS OF NPM AND EDITOR EXTENSION MALWARE' "$WORK/dz-both.txt"
has    "npm and extensions: both fixes"               'Delete the packages and files listed in section 5.*Uninstall the extensions listed in section 5' "$WORK/dz-both.txt"
has    "npm and extensions: the link says both"       '&nm=1&py=0&ex=1&wp=0' "$WORK/dz-both.txt"
has    "summary row 01 names the fixes to install"    '01 . Coding agents +[0-9]+ found, 4 security fixes to install' "$WORK/dz-hit-sum.txt"
has    "summary row 02 names the link"                '02 . MCP servers .* 1 file links to your SSH' "$WORK/dz-hit-sum.txt"
D=$WORK/dz-miss-flat.txt
hasnot "near misses: no agent set to run without asking" 'Agents set to run commands without asking|run-without-asking' "$D"
hasnot "near misses: no version to update (fixed, below the range, unparseable, another package)" 'Tools with a security fix|that have a security fix' "$D"
hasnot "near misses: no link inside ~/.ssh, none to another file" 'link to your SSH logins|links to ~/\.ssh' "$D"
hasnot "near misses: a clean or longer version, a longer name" 'GlassWorm|oorzc' "$D"
# Known limits, as they are today (docs/designs/dossier-checks.md, Not covered): a setting inside a
# /* */ block comment is still read; Codex values in single quotes, and a profile made the default
# with profile = "x", are not.
for L in 1 2; do rm -rf "$WORK/dz-lim$L"; cp -R "$WORK/clean" "$WORK/dz-lim$L"; mkdir -p "$WORK/dz-lim$L/$DAS/Code/User" "$WORK/dz-lim$L/.codex"; done
printf '{\n  /*\n  "chat.tools.autoApprove": true\n  */\n}\n' > "$WORK/dz-lim1/$DAS/Code/User/settings.json"
printf "approval_policy = 'never'\nsandbox_mode = 'danger-full-access'\n" > "$WORK/dz-lim1/.codex/config.toml"
printf 'profile = "yolo"\n[profiles.yolo]\napproval_policy = "never"\nsandbox_mode = "danger-full-access"\n' > "$WORK/dz-lim2/.codex/config.toml"
dzrun "$WORK/dz-lim1" | tr -s ' \n' '  ' > "$WORK/dz-lim1.txt"; dzrun "$WORK/dz-lim2" | tr -s ' \n' '  ' > "$WORK/dz-lim2.txt"
has    "known limit: a setting in a /* */ block comment is still read" '! VS Code Copilot ~/.*Code/User/settings\.json chat\.tools\.autoApprove' "$WORK/dz-lim1.txt"
hasnot "known limit: Codex values in single quotes are not read" '! Codex ' "$WORK/dz-lim1.txt"
hasnot "known limit: a profile made the default with profile = is not read" '! Codex ' "$WORK/dz-lim2.txt"
cp -R "$WORK/dz-miss" "$WORK/dz-calm"; rm -rf "$WORK/dz-calm/code/mr"
printf '{"permissions":{"defaultMode":"bypassPermissions"}}\n' > "$WORK/dz-calm/.claude/settings.json"
HOME="$WORK/dz-calm" PATH="$WORK/dzbin:/usr/bin:/bin" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/dz-calm.txt"
has    "a one-line settings file is read too"         '! Claude Code ~/\.claude/settings\.json bypassPermissions' "$WORK/dz-calm.txt"

echo "a new incident of each kind is data lines only"
# tests/made-up.sh appends a made-up platform, startup file, wiper file, planted file and Python
# package to a copy's data files and runs gen.sh there; it fails if any code changed.
if bash tests/made-up.sh "$WORK/mu" "$WORK/clean" "$WORK/mu-home" 2> "$WORK/mu-err.txt"; then ok "made-up incidents need only data lines and gen.sh"
else bad "made-up incidents need only data lines and gen.sh"; sed 's/^/        /' "$WORK/mu-err.txt"; fi
mu() { env HOME="$1" TMPDIR="$1/tmp" PATH=/usr/bin:/bin ${3:+GIRD_CHECK_COMPACT=1} bash "$WORK/mu/gird-check.sh" --offline 2>&1 | tr -s ' \n' '  ' > "$2"; }
mu "$WORK/mu-home" "$WORK/mu.txt"
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
has    "made-up Python package: its own row"          'Madepkg 9\.9\.9 +signs of the malware found ~/code/venv/lib/site-packages: madepkg 9\.9\.9, madepy_boot\.pth ~/tmp/\.madepy_1 ' "$WORK/mu.txt"
has    "made-up Python package: its advisory"         'Advisory: example\.com/madepy/advisory' "$WORK/mu.txt"
has    "made-up Python package: in uv's cache"        'uv cache holds the 9\.9\.9 package\. Clear it with: uv cache clean madepkg' "$WORK/mu.txt"
has    "made-up Python package: its fix"              "follow Madepkg's advisory" "$WORK/mu.txt"
hasnot "LiteLLM is not blamed for it"                 'LITELLM 1\.107\.0 MALWARE|signs of the LiteLLM malware' "$WORK/mu.txt"
# Without the wiper and the npm files, the Python package leads; with only the platform, it does.
cp -R "$WORK/mu-home" "$WORK/mu-py"; rm -rf "$WORK/mu-py/.config/gh-token-monitor-made" "$WORK/mu-py/.config/madeworm" "$WORK/mu-py/code/made" "$WORK/mu-py/.madeplat.json" "$WORK/mu-py/.vscode/extensions/made.ext-1.0.0"
mu "$WORK/mu-py" "$WORK/mu-py.txt" compact
has    "made-up Python package leads the summary"     'ACT NOW: SIGNS OF THE MADEPKG 9\.9\.9 MALWARE' "$WORK/mu-py.txt"
has    "and row 05 names it"                          'signs of the Madepkg malware\. Act now' "$WORK/mu-py.txt"
rm -rf "$WORK/mu-plat"; cp -R "$WORK/clean" "$WORK/mu-plat"; rm -rf "$WORK/mu-plat/.config/opencode" "$WORK/mu-plat/.local/share/opencode" "$WORK/mu-plat/.railway"
mu "$WORK/mu-plat" "$WORK/mu-none.txt" compact
# The summary row is cut at 80 columns, so only its start is checked.
has    "a clean home: row 05 counts the made-up ones" 'none of the 8 recent leaks it checks' "$WORK/mu-none.txt"
mkdir -p "$WORK/mu-plat/.config/madeplat"
mu "$WORK/mu-plat" "$WORK/mu-plat.txt" compact
has    "a made-up platform alone gives its summary"   'Madeplat CLI found: rotate secrets stored there' "$WORK/mu-plat.txt"
rm -rf "$WORK/mu-upd"; cp -R "$WORK/clean" "$WORK/mu-upd"; mkdir -p "$WORK/mu-upd/code/u"
printf '{"lockfileVersion":3,"packages":{"node_modules/made-upd-pkg":{"version":"4.5.6","resolved":"https://registry.npmjs.org/made-upd-pkg/-/made-upd-pkg-4.5.6.tgz"}}}\n' > "$WORK/mu-upd/code/u/package-lock.json"
mu "$WORK/mu-upd" "$WORK/mu-upd.txt"
has    "a made-up update-level hit is a version to update" 'npm worms a bad version to update' "$WORK/mu-upd.txt"
hasnot "and not a compromised machine"                'ACT NOW|Treat this machine as compromised' "$WORK/mu-upd.txt"
rm -rf "$WORK/mu-act"; cp -R "$WORK/clean" "$WORK/mu-act"; mkdir -p "$WORK/mu-act/code/a"
printf '{"lockfileVersion":3,"packages":{"node_modules/made-npm-pkg":{"version":"1.2.3","resolved":"https://registry.npmjs.org/made-npm-pkg/-/made-npm-pkg-1.2.3.tgz"}}}\n' > "$WORK/mu-act/code/a/package-lock.json"
mu "$WORK/mu-act" "$WORK/mu-act.txt"
has    "a made-up act-level npm hit alone: compromised" 'Treat this machine as compromised\. Delete the packages and files listed in section 5' "$WORK/mu-act.txt"
has    "and the link says npm malware"                '&nm=1&py=0&ex=0&wp=0' "$WORK/mu-act.txt"
has    "made-up agent set to run without asking"      '! Made Agent ~/\.madeagent/config\.json madeMode' "$WORK/mu.txt"
has    "made-up tool with a security fix"             '! Made Tool 1\.5\.0, update to 2\.0\.0 or later A made-up hole for the tests\. example\.com/madetool' "$WORK/mu.txt"
has    "made-up extension that shipped malware"       '~/\.vscode/extensions/made\.ext-1\.0\.0 made\.ext 1\.0\.0 \(Made extension, October 2026\), installed' "$WORK/mu.txt"

echo "gen.sh refuses what it cannot write safely"
gen_refuses() { # what file line
  rm -rf "$WORK/gr"; mkdir -p "$WORK/gr"; cp -R gird-check.sh gird-check.ps1 tools data "$WORK/gr/"
  printf '%s\n' "$3" >> "$WORK/gr/data/$2"
  bash "$WORK/gr/tools/gen.sh" > "$WORK/gr.txt" 2>&1; _rc=$?
  if [ "$_rc" -eq 2 ] && grep -q "data/$2" "$WORK/gr.txt"; then ok "$1"; else bad "$1" "exit $_rc"; fi
}
T=$(printf '\t')
gen_refuses "a platform with an unknown incident"       platforms.tsv "nosuch${T}X${T}x${T}~/.x/${T}CLI found${T}advice${T}summary"
gen_refuses "a platform advice with a \$"               platforms.tsv "railway${T}X${T}x${T}~/.x/${T}CLI found${T}costs \$5${T}summary"
gen_refuses "a platform with another found word"        platforms.tsv "railway${T}X${T}x${T}~/.x/${T}present${T}advice${T}summary"
gen_refuses "a platform path that is only the home"     platforms.tsv "railway${T}X${T}x${T}~${T}CLI found${T}advice${T}summary"
gen_refuses "a startup path with a glob"                indicators.tsv "mastra${T}all${T}startup${T}no${T}~/.config/*.cjs${T}note"
gen_refuses "a startup line with no note"               indicators.tsv "mastra${T}all${T}startup${T}no${T}~/.config/x.cjs${T}-"
gen_refuses "a site file with a slash"                  indicators.tsv "litellm${T}all${T}site${T}no${T}a/cook.pth${T}-"
gen_refuses "a temp name of dots"                       indicators.tsv "litellm${T}all${T}temp${T}no${T}..${T}-"
gen_refuses "a Python incident that is only an update"  bad-pypi.tsv "mistralai${T}1.0.0${T}mistral"
gen_refuses "a Python name with a hyphen"               bad-pypi.tsv "lite-llm${T}1.0.0${T}litellm"
gen_refuses "a planted file in another folder"          planted.tsv ".git${T}x.js${T}tanstack${T}note"
gen_refuses "a planted file listed twice"               planted.tsv ".claude${T}setup.mjs${T}keyv${T}note"
gen_refuses "an npm package with an unknown incident"   bad-npm.tsv "left-pad${T}1.0.0${T}nosuch"
gen_refuses "an incident listed twice"                  incidents.tsv "litellm${T}X${T}October 2026${T}x${T}https://example.com${T}act"
gen_refuses "an incident advice with a quote"          incidents.tsv "newone${T}X${T}October 2026${T}x${T}https://example.com${T}update${T}Don't"
gen_refuses "an incident with an empty advice"         incidents.tsv "newone${T}X${T}October 2026${T}x${T}https://example.com${T}update${T}"
gen_refuses "an incident with another level"            incidents.tsv "newone${T}X${T}October 2026${T}x${T}https://example.com${T}remove"
gen_refuses "an incident with no month"                 incidents.tsv "newone${T}X${T}2026${T}x${T}https://example.com${T}act"
gen_refuses "an incident source that is not https"      incidents.tsv "newone${T}X${T}October 2026${T}x${T}http://example.com${T}act"
gen_refuses "advice on an incident with no package to show it" incidents.tsv "newone${T}X${T}October 2026${T}x${T}https://example.com${T}act${T}Do this."
gen_refuses "a wiper file that is not gh-token-monitor" indicators.tsv "tanstack${T}all${T}wiper${T}no${T}~/.config/otherwiper${T}-"
gen_refuses "npm's -security placeholder"               bad-npm.tsv "left-pad${T}0.0.1-security${T}axios"
gen_refuses "an auto-approve line with another os"    auto-approve.tsv "X${T}mac os${T}~/.x/settings.json${T}s${T}\"a\": true"
gen_refuses "an auto-approve pattern with a quote"     auto-approve.tsv "X${T}all${T}~/.x/settings.json${T}s${T}it's"
gen_refuses "an auto-approve line with no pattern"     auto-approve.tsv "X${T}all${T}~/.x/settings.json${T}s"
gen_refuses "an auto-approve path with a glob"         auto-approve.tsv "X${T}all${T}~/.x/*.json${T}s${T}\"a\": true"
gen_refuses "an auto-approve project path that climbs" auto-approve.tsv "X${T}all${T}{PROJECT}/../.x/settings.json${T}s${T}\"a\": true"
gen_refuses "an outdated line of another kind"         outdated.tsv "newtool${T}New${T}all${T}exe${T}new-tool${T}<1.0${T}a hole${T}https://example.com"
gen_refuses "an outdated range that does not parse"    outdated.tsv "newtool${T}New${T}all${T}npm${T}new-tool${T}<=1.0${T}a hole${T}https://example.com"
gen_refuses "an outdated line that disagrees with its tool" outdated.tsv "cursor${T}Cursor${T}mac${T}plist${T}~/x/Info.plist${T}<4.0${T}a prompt injection could escape the sandbox${T}https://github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw"
gen_refuses "an outdated plist that is not Info.plist" outdated.tsv "newtool${T}New${T}mac${T}plist${T}~/x/Other.plist${T}<1.0${T}a hole${T}https://example.com"
gen_refuses "an extension with an unknown incident"    bad-extensions.tsv "pub.ext${T}1.0.0${T}nosuch"
gen_refuses "an extension whose incident is only an update" bad-extensions.tsv "pub.ext${T}1.0.0${T}injective"
gen_refuses "an extension version that is not a version" bad-extensions.tsv "pub.ext${T}1.0.0-beta${T}glassworm"
gen_refuses "an extension listed twice, in another case" bad-extensions.tsv "OORZC.ssh-tools${T}0.5.1${T}glassworm"
gen_refuses "a line that is not ASCII"                  incidents.tsv "newone${T}$(printf 'X\303\251')${T}October 2026${T}x${T}https://example.com${T}act"

echo "MCP configs in plugin folders"
cp -R "$WORK/clean" "$WORK/mcp-pl"
mkdir -p "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a" "$WORK/mcp-pl/.claude/plugins/synced/b"
printf '{"mcpServers":{"one":{"command":"x"},"two":{"command":"y"}}}\n' > "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a/.mcp.json"
printf '{"mcpServers":{"three":{"command":"z"}}}\n' > "$WORK/mcp-pl/.claude/plugins/synced/b/.mcp.json"
HOME="$WORK/clean" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-base.txt"
HOME="$WORK/mcp-pl" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-pl.txt"
HOME="$WORK/mcp-pl" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-pl-full.txt"
BASE=$(grep -aoE '02 . MCP servers +[0-9]+ servers' "$WORK/mcp-base.txt" | grep -aoE '[0-9]+ servers')
if [ -n "$BASE" ]; then ok "the baseline has a server count" "$BASE"; else bad "the baseline has a server count"; fi
has    "plugin-folder servers are counted apart" "02 . MCP servers +$BASE, 3 more in plugin folders" "$WORK/mcp-pl.txt"
hasnot "the baseline mentions no plugin folders" 'plugin folders' "$WORK/mcp-base.txt"
has    "the details total only the servers set up" "MCP SERVERS +$BASE " "$WORK/mcp-pl-full.txt"
has    "the details give one plugin-folders line" 'Plugin folders +3 servers in 2 files, not counted above' "$WORK/mcp-pl-full.txt"
hasnot "plugin-folder files are not listed one by one" 'plugins/a/\.mcp\.json' "$WORK/mcp-pl-full.txt"
cp -R "$WORK/mcp-pl" "$WORK/mcp-tok"; KEY1=$(head -n 1 "$WORK/keys.txt")
printf '{"mcpServers":{"t":{"command":"x","env":{"ANTHROPIC_API_KEY":"%s"}}}}\n' "$KEY1" > "$WORK/mcp-tok/.claude/plugins/synced/b/.mcp.json"
HOME="$WORK/mcp-tok" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-tok.txt"
has    "a token in a plugin-folder config is still flagged" 'plugins/synced/b/\.mcp\.json.*token in the file' "$WORK/mcp-tok.txt"
has    "and it still counts as a thing to fix"             'Replace tokens written into MCP configs' "$WORK/mcp-tok.txt"
rm -rf "$WORK/mcp-only"; mkdir -p "$WORK/mcp-only"
mkdir -p "$WORK/mcp-only/.codex/.tmp/plugins/plugins/a"; cp "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a/.mcp.json" "$WORK/mcp-only/.codex/.tmp/plugins/plugins/a/.mcp.json"
HOME="$WORK/mcp-only" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-only.txt"
has    "with only plugin-folder configs the row says none set up" '02 . MCP servers +none set up, 2 in plugin folders' "$WORK/mcp-only.txt"

echo "the spend limit tip"
OUT=$WORK/tip.txt
HOME="$WORK/home" bash "$SCRIPT" --offline > "$OUT" 2>&1
has    "the spend limit tip is a plain line"      '^     Also: set a monthly spend limit on every AI provider key' "$OUT"
hasnot "the spend limit tip is not numbered"      '^ *[0-9]+\. +.*spend limit' "$OUT"
LAST=$(grep -aE '^ +[0-9]+\.  ' "$OUT" | tail -n 1 | grep -aoE '^ +[0-9]+' | tr -d ' ')
ISS=$(grep -aoE '[0-9]+ things? to fix' "$OUT" | head -n 1 | grep -aoE '^[0-9]+')
if [ -n "$LAST" ] && [ "$LAST" = "$ISS" ]; then ok "the numbered list matches the fix count" "$ISS"; else bad "the numbered list matches the fix count" "list ends at $LAST, header says $ISS"; fi

rm -rf "$WORK/tip-empty"; mkdir -p "$WORK/tip-empty"
HOME="$WORK/tip-empty" PATH=/usr/bin:/bin bash "$SCRIPT" --offline > "$WORK/tip-empty.txt" 2>&1
has    "on a near-empty home the tip is still a plain line" '^     Also: set a monthly spend limit' "$WORK/tip-empty.txt"

echo "summary"
OUT=$WORK/compact.txt
HOME="$WORK/home" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline > "$OUT" 2>&1
for label in 'Coding agents' 'MCP servers' 'Keys in plain text' 'Allow lists' 'Recent leaks'; do
  has "one summary line for $label" "^   0[1-5] .*$label" "$OUT"
done
has    "the keys line names the first file"    'Keys in plain text +4 files, like ~/\.zshrc \(Anthropic, OpenAI\)' "$OUT"
has    "the summary leads with the first fix"  'First fix: Don.t revoke any GitHub token yet' "$OUT"
hasnot "the summary leaves out the other key files" '~/\.zsh_history +GitHub' "$OUT"
hasnot "the summary has no section tables"     'KEYS IN PLAIN TEXT' "$OUT"
hasnot "the summary shows no letter grade"     'GRADE [ABCDF]|[Gg]rade [ABCDF]\b' "$OUT"
if grep -aqF -f "$WORK/keys.txt" "$OUT"; then bad "the summary never prints a planted key"; else ok "the summary never prints a planted key"; fi
HOME="$WORK/home" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline --full > "$WORK/full.txt" 2>&1
has    "--full prints every section in full"   'KEYS IN PLAIN TEXT' "$WORK/full.txt"
has    "--full lists every key file"           '~/\.zsh_history +GitHub' "$WORK/full.txt"

echo "hostile file names"
EVIL="$WORK/home/code/evil$(printf '\033[2J\033]0;pwned\007\302\233')31m"
mkdir -p "$EVIL"
printf 'AWS_ACCESS_KEY_ID=AK%s\n' "IA$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Z0-9' | head -c 16)" > "$EVIL/.env"
HOME="$WORK/home" bash "$SCRIPT" --offline > "$WORK/evil.txt" 2>&1
if LC_ALL=C grep -aq "$(printf '\033')\|$(printf '\007')\|$(printf '\302\233')" "$WORK/evil.txt"; then bad "control characters in file names never reach the terminal"; else ok "control characters in file names never reach the terminal"; fi
has "the hostile folder is still reported" 'code/evil\?' "$WORK/evil.txt"
rm -rf "$EVIL"

echo "saving the report"
mkdir -p "$WORK/cwd"
(cd "$WORK/cwd" && HOME="$WORK/home" bash "$SCRIPT" --offline --save > "$WORK/save.txt" 2>&1)
SAVED=$(ls "$WORK"/cwd/gird-ai-key-check-*.txt 2>/dev/null | head -n 1)
if [ -n "$SAVED" ]; then ok "--save writes a report"; else bad "--save writes a report"; fi
if [ -n "$SAVED" ] && [ -n "$(find "$SAVED" -perm 600)" ]; then ok "the report is readable only by you"; else bad "the report is readable only by you"; fi
if [ -n "$SAVED" ] && ! grep -aqF -f "$WORK/keys.txt" "$SAVED"; then ok "the saved report holds no planted key"; else bad "the saved report holds no planted key"; fi

echo "shared counts and how you compare"
{
  printf '%s' '{"devices":1234,"runs":2345,"devices_7d":456,"key_files":3412,"agents":5678,"clean":0.31,"hist":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"min_n":25,"updated":1792680000000}' > "$WORK/stats.json"
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
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" --offline > /dev/null 2>&1
  HOME="$WORK/home" GIRD_CHECK_API="$API" DO_NOT_TRACK=1 bash "$SCRIPT" > /dev/null 2>&1
  if [ ! -s "$WORK/received.log" ]; then ok "--offline and DO_NOT_TRACK=1 send nothing"; else bad "--offline and DO_NOT_TRACK=1 send nothing"; fi
  if [ ! -s "$WORK/gets.log" ]; then ok "--offline and DO_NOT_TRACK=1 ask for nothing"; else bad "--offline and DO_NOT_TRACK=1 ask for nothing"; fi
  OUT=$WORK/online.txt
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$OUT" 2>&1
  if [ "$(grep -c . "$WORK/received.log")" -eq 1 ]; then ok "a normal run sends one report"; else bad "a normal run sends one report"; fi
  if [ "$(grep -c . "$WORK/gets.log")" -eq 1 ] && grep -q '/api/check/stats$' "$WORK/gets.log"; then ok "a normal run asks for the totals once"; else bad "a normal run asks for the totals once"; fi
  if python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1]) if l.strip()]' "$WORK/received.log" 2>/dev/null; then ok "the report is valid JSON"; else bad "the report is valid JSON"; fi
  has "the device ID is a 64-character hash or empty" '"device_id":"([0-9a-f]{64})?"' "$WORK/received.log"
  hasnot "the report holds no path"     '/(Users|home|private|tmp)/|~/' "$WORK/received.log"
  if grep -aqF -f "$WORK/keys.txt" "$WORK/received.log"; then bad "the report holds no planted key"; else ok "the report holds no planted key"; fi
  if grep -aqF "\"$(id -un)\"" "$WORK/received.log"; then bad "the report holds no username"; else ok "the report holds no username"; fi
  has  "shows one real total under the banner" '★ (1,234 AI builders have run Blindspot|456 AI builders ran it this week|Blindspot has found 3,412 files with AI keys in plain text so far|31% of AI builders had no keys in plain text)' "$OUT"
  hasi "shows how this machine compares"       'better than 72% of AI builders who ran Blindspot' "$OUT"
  hasnot "the percentile line carries no count" 'of 1,234 AI builders' "$OUT"
  has  "the result link carries the percentile" 'blindspot/card/#v=2&.*&pc=72&pn=1234' "$OUT"
  RID=$(grep -oE '"run_id":"[0-9a-f]{16}"' "$WORK/received.log" | head -n 1 | cut -d'"' -f4)
  has  "the link carries the report's run ID, the rank and key counts" "blindspot/card/#v=2&.*&u=${RID:-no-run-id}&r=142&sk=2&hk=1&ag=[a-z0-9.-]*&nm=[01]&py=[01]&ex=[01]&wp=[01]\$" "$OUT"
  head -n 1 "$WORK/received.log" > "$WORK/report-home.json"   # its case-study counts are checked below
  HOME="$WORK/clean" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/clean-online.txt" 2>&1
  has  "leads with the percentile when nothing is urgent" 'BETTER THAN 72% OF AI BUILDERS WHO RAN BLINDSPOT' "$WORK/clean-online.txt"
  PROUD="^  ★ You're one of the first 1,000 AI builders to run Blindspot\."
  printf '%s' '{"devices":1234567,"devices_7d":10,"key_files":20,"clean":0}' > "$WORK/stats.json"
  for B in $BASHES; do
    V=$("$B" -c 'echo "${BASH_VERSINFO[0]}"')
    HOME="$WORK/home" GIRD_CHECK_API="$API" "$B" "$SCRIPT" > "$WORK/online-$V.txt" 2>&1
    has  "bash $V: the total gets thousands separators" '★ 1,234,567 AI builders have run Blindspot\.' "$WORK/online-$V.txt"
    hasi "bash $V: shows how this machine compares"     'better than 72% of AI builders who ran Blindspot' "$WORK/online-$V.txt"
    has  "bash $V: the full report shows the rank"      "$PROUD" "$WORK/online-$V.txt"
    HOME="$WORK/home" GIRD_CHECK_API="$API" GIRD_CHECK_COMPACT=1 "$B" "$SCRIPT" > "$WORK/compact-online-$V.txt" 2>&1
    has  "bash $V: the summary shows the rank"          "$PROUD" "$WORK/compact-online-$V.txt"
  done
  printf '%s' '{"p":72,"n":1234}' > "$WORK/reply.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/no-rank.txt" 2>&1
  hasnot "the place in line is never shown"       "AI builder #|#142" "$WORK/no-rank.txt"
  has    "a reply without r leaves r empty in the link" '&pn=1234&u=[0-9a-f]{16}&r=&sk=2' "$WORK/no-rank.txt"
  SHOWN=""
  for R in null 0 '"142"' 14.2 0142 1234567890; do
    printf '{"p":72,"n":1234,"r":%s}' "$R" > "$WORK/reply.json"
    HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/bad-rank.txt" 2>&1
    if grep -aqE '&r=[^&]' "$WORK/bad-rank.txt"; then SHOWN="$SHOWN $R"; fi
  done
  if [ -z "$SHOWN" ]; then ok "a rank that isn't a whole number from 1 shows nothing"; else bad "a rank that isn't a whole number from 1 shows nothing"; printf '        shown for:%s\n' "$SHOWN"; fi
  printf '%s' '{"p":72,"n":1234,"r":1000}' > "$WORK/reply.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/rank-1000.txt" 2>&1
  has    "rank 1000 is one of the first 1,000"       "★ You're one of the first 1,000 AI builders to run Blindspot\." "$WORK/rank-1000.txt"
  printf '%s' '{"p":72,"n":1234,"r":1001}' > "$WORK/reply.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/rank-1001.txt" 2>&1
  hasnot "rank 1001 shows no early line"           "first 1,000" "$WORK/rank-1001.txt"
  hasnot "rank 1001 never shows the number"        "1,001|AI builder #" "$WORK/rank-1001.txt"
  has    "rank 1001 goes in the result link"        '&r=1001&' "$WORK/rank-1001.txt"
  hasnot "rank 1000 never shows the number"        "AI builder #|#1,000" "$WORK/rank-1000.txt"
  printf '%s' '{"p":72,"n":1234,"r":142}' > "$WORK/reply.json"
  printf '%s' '{"devices":999,"devices_7d":120,"key_files":300,"clean":0.4}' > "$WORK/stats.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/early.txt" 2>&1
  has    "under 1,000 the early line sits above the header" "^  ★ You're one of the first 1,000 AI builders to run Blindspot\." "$WORK/early.txt"
  if [ "$(grep -c 'first 1,000' "$WORK/early.txt")" -eq 1 ]; then ok "under 1,000 the first 1,000 are named once"; else bad "under 1,000 the first 1,000 are named once"; fi
  if grep -aA2 "one of the first 1,000 AI builders" "$WORK/early.txt" | grep -aqE '▌ .*(THINGS TO FIX|BETTER THAN|ACT NOW)'; then ok "the header follows the rank line"; else bad "the header follows the rank line"; fi
  printf '%s' '{"p":72,"n":1234}' > "$WORK/reply.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/early-no-rank.txt" 2>&1
  has    "says early adopter when the reply has no rank" "^  ★ You're one of the first 1,000 AI builders to run Blindspot\." "$WORK/early-no-rank.txt"
  printf '%s' '{"p":72,"n":1234,"r":142}' > "$WORK/reply.json"
  hasnot "never shows a total under 1,000"       '★ (999 AI builders|120 AI builders|Blindspot has found|40% of AI builders)' "$WORK/early.txt"
  printf '%s' '{"devices":1000,"devices_7d":10,"key_files":20,"clean":0}' > "$WORK/stats.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/at-1000.txt" 2>&1
  has    "shows the total from 1,000 people"  '★ 1,000 AI builders have run Blindspot\.' "$WORK/at-1000.txt"
  printf '{"devices":"\033[2J\033]0;pwned\007","key_files":99999999999999999999}' > "$WORK/stats.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/hostile.txt" 2>&1
  if LC_ALL=C grep -aq "$(printf '\033')\|$(printf '\007')" "$WORK/hostile.txt"; then bad "a hostile totals reply can't reach the terminal"; else ok "a hostile totals reply can't reach the terminal"; fi
  hasnot "a bad totals reply shows no total"     '^  ★ ([0-9]|Blindspot has found)' "$WORK/hostile.txt"

  echo "case-study counts in the report"
  # tests/payload.py checks one report against the script's fixed lists and the fixture.
  payload_checks() { # mode report [report]
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
  payload_checks home "$WORK/report-home.json"
  # One more key file in a shell config, a history file and an .env file, and one
  # in agent settings, which the fixture lacks.
  bash tests/make-fixture.sh "$WORK/places" "$WORK/keys-places.txt"
  printf 'export OPENAI_API_KEY=%s\n' "$(sed -n 2p "$WORK/keys-places.txt")" > "$WORK/places/.bash_profile"
  printf 'client = Anthropic(api_key="%s")\n' "$(sed -n 1p "$WORK/keys-places.txt")" > "$WORK/places/.python_history"
  printf 'GROQ_API_KEY=%s\n' "$(sed -n 5p "$WORK/keys-places.txt")" > "$WORK/places/.gemini/.env"
  printf 'anthropic-api-key: %s\n' "$(sed -n 1p "$WORK/keys-places.txt")" > "$WORK/places/.aider.conf.yml"
  report_of "$WORK/report-places.json" env HOME="$WORK/places" GIRD_CHECK_API="$API" bash "$SCRIPT"
  payload_checks places "$WORK/report-places.json"
  mkdir -p "$WORK/empty"
  report_of "$WORK/report-empty.json" env HOME="$WORK/empty" GIRD_CHECK_API="$API" bash "$SCRIPT"
  payload_checks empty "$WORK/report-empty.json"
  # The dossier checks share nothing: the same report, link and score with or without them.
  rm -rf "$WORK/pl-base" "$WORK/pl-dz"; cp -R "$WORK/clean" "$WORK/pl-base"; cp -R "$WORK/clean" "$WORK/pl-dz"
  bash tests/make-dossier.sh "$WORK/pl-dz" "$WORK/pl-dz/$DAS" calm
  report_of "$WORK/report-pl-base.json" env HOME="$WORK/pl-base" PATH=/usr/bin:/bin GIRD_CHECK_API="$API" bash "$SCRIPT"
  report_of "$WORK/report-pl-dz.json" env HOME="$WORK/pl-dz" PATH=/usr/bin:/bin GIRD_CHECK_API="$API" bash "$SCRIPT"
  if python3 -c 'import json,sys
a, b = (json.loads(open(f).readline()) for f in sys.argv[1:3])
for r in (a, b):
    for k in ("run_id", "scan_seconds", "results_wait_seconds"): r.pop(k, None)
sys.exit(0 if a == b and a else 1)' "$WORK/report-pl-base.json" "$WORK/report-pl-dz.json"; then ok "the dossier findings leave the report unchanged"
  else bad "the dossier findings leave the report unchanged"; fi
  HOME="$WORK/pl-dz" PATH=/usr/bin:/bin bash "$SCRIPT" --offline > "$WORK/pl-dz.txt" 2>&1
  HOME="$WORK/pl-base" PATH=/usr/bin:/bin bash "$SCRIPT" --offline > "$WORK/pl-base.txt" 2>&1
  has    "and they were found"                         'Tools with a security fix to install' "$WORK/pl-dz.txt"
  if [ "$(grep -aoE 'blindspot/card/#[^ ]*' "$WORK/pl-dz.txt")" = "$(grep -aoE 'blindspot/card/#[^ ]*' "$WORK/pl-base.txt")" ]; then ok "and the result link, score included, is the same"
  else bad "and the result link, score included, is the same"; fi
  if [ "$(uname -s)" = Darwin ] && [ -x /usr/bin/osascript ]; then
    # Without jq on PATH, the script reads JSON configs with macOS's JavaScript.
    mkdir -p "$WORK/nojq"; ln -s /usr/bin/* /bin/* /usr/sbin/* /sbin/* "$WORK/nojq/" 2>/dev/null; rm -f "$WORK/nojq/jq"
    report_of "$WORK/report-nojq.json" env PATH="$WORK/nojq" HOME="$WORK/home" GIRD_CHECK_API="$API" /bin/bash "$SCRIPT"
    payload_checks nojq "$WORK/report-home.json" "$WORK/report-nojq.json"
  else
    skip "without jq, macOS's JavaScript finds the same MCP servers as jq" "needs macOS's osascript"
  fi
  hasnot "no report holds a name you gave an MCP server" 'acme|my notes|web.search' "$WORK/received.log"
  hasnot "no report holds a server label as written"     '@modelcontextprotocol|MCP_DOCKER|Figma Dev Mode|upstash|Playwright|"gh"|"fs"' "$WORK/received.log"
  hasnot "no report holds a file name" '\.zshrc|zsh_history|python_history|bash_profile|\.env|\.mcp|mcp\.json|config\.(toml|yaml)|cline_mcp|claude_desktop|settings(\.local)?\.json|\.aider' "$WORK/received.log"
  hasnot "no report holds a path"                        '/(Users|home|private|tmp|var)/|~/' "$WORK/received.log"
  if grep -aqF -f "$WORK/keys-places.txt" "$WORK/received.log"; then bad "no report holds the extra planted keys"; else ok "no report holds the extra planted keys"; fi
  # After the checks above: the Windows run has a GitHub CLI login, so its report says "gh".
  GIRD_CHECK_API="$API" report_of "$WORK/report-win.json" winrun
  GIRD_CHECK_API="$API" FAKE_BUILD='' FAKE_UNAME=MINGW64_NT-10.0-19045 report_of "$WORK/report-win10.json" winrun
  report_of "$WORK/report-wsl.json" env HOME="$WORK/home" FAKE_UNAME=Linux GIRD_CHECK_PROC="$WORK/proc-wsl" GIRD_CHECK_API="$API" PATH="$WB:/usr/bin:/bin" bash "$SCRIPT"
  WANT_ID=$(printf 'gird-check-v1:%s' "$GUID" | shasum -a 256 | cut -c1-64)
  has    "Windows: os is Windows 11 for build 22000 and up" '"os":"Windows 11"' "$WORK/report-win.json"
  has    "Windows: os is Windows 10 from uname's build when reg has none" '"os":"Windows 10"' "$WORK/report-win10.json"
  has    "Windows: device_id is sha256 of the salt and MachineGuid as stored" "\"device_id\":\"$WANT_ID\"" "$WORK/report-win.json"
  has    "Windows: arch from PROCESSOR_ARCHITECTURE"      '"arch":"x86_64"' "$WORK/report-win.json"
  has    "Windows: terminal is windows-terminal with WT_SESSION" '"terminal":"windows-terminal"' "$WORK/report-win.json"
  has    "Windows: the agents found in Windows places are reported" '"agents":\["claude-code","claude-desktop","cursor",.*"goose"' "$WORK/report-win.json"
  has    "Windows: PowerShell history counts as shell history" '"history_keys":2,.*' "$WORK/report-win.json"
  has    "Windows: key_places puts PSReadLine history in shell_history" '"shell_history":2' "$WORK/report-win.json"
  hasnot "Windows: the report holds no Windows path or file name" 'AppData|PSReadLine|ConsoleHost|Users/me|msyshome|_netrc' "$WORK/report-win.json"
  if grep -q '"os":"Linux"' "$WORK/report-wsl.json" && [ -s "$WORK/wsl.txt" ] && grep -q 'files into a secrets manager' "$WORK/wsl.txt"; then
    ok "WSL reports os Linux while giving the WSL advice"
  else bad "WSL reports os Linux while giving the WSL advice"; fi
}

echo "help"
if bash "$SCRIPT" --help | grep -q -- '--offline'; then ok "--help lists the options"; else bad "--help lists the options"; fi
if bash "$SCRIPT" --help | grep -q -- 'gird-fleet.sh checks every account'; then ok "--help shows the whole header, gird-fleet.sh included"; else bad "--help shows the whole header, gird-fleet.sh included"; fi

echo "fleet mode (--all-users)"
# The suites never run as root. GIRD_CHECK_FLEET_ROOT stands in for root, GIRD_CHECK_FLEET_USERS
# for dscl's account list, GIRD_CHECK_FLEET_LAUNCH for sudo (tests/fleet-launch.sh records what
# root would run, then runs what follows sudo's -H), and GIRD_CHECK_FLEET_STATE for
# /var/db/blindspot. The script reads them only when it is not running as root.
FL=$WORK/fleet; mkdir -p "$FL"
FSKIP=""; [ "$(uname -s)" = Darwin ] || FSKIP="fleet mode is built for macOS only so far: its root side reads dscl and BSD stat"
U=$(id -u); FLL=$PWD/tests/fleet-launch.sh; FLEETSH=$PWD/gird-fleet.sh
fl_home() { mkdir -p "$FL/$1/Library/Safari"; }
for h in asha itadmin clean upd linker odd shared keeper; do fl_home "$h"; done
bash tests/make-fixture.sh "$FL/asha" "$FL/keys-asha.txt" > /dev/null; mkdir -p "$FL/asha/Library/Safari"
# itadmin: one SSH key with no passphrase and nothing else; upd: the same, so it has something to review only.
for h in itadmin upd; do
  mkdir -p "$FL/$h/.ssh"; printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ\n-----END OPENSSH PRIVATE KEY-----\n' > "$FL/$h/.ssh/id_ed25519"
done
# A key in a file the linking account can't read, and links to it, to a system file and through a linked folder.
KEYX="AK""IA$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Z0-9' | head -c 16)"; printf '%s\n' "$KEYX" >> "$FL/keys-asha.txt"
mkdir -p "$FL/keeper/private"; printf 'export AWS_ACCESS_KEY_ID=%s\n' "$KEYX" > "$FL/keeper/private/zshrc"; chmod 000 "$FL/keeper/private"
ln -s "$FL/keeper/private/zshrc" "$FL/linker/.zshrc"; ln -s /etc/master.passwd "$FL/linker/.bash_profile"
ln -s "$FL/keeper/private" "$FL/linker/.config"
# odd: a fifo in place of a history file, a link to a device, and a file over the size limit.
mkfifo "$FL/odd/.zsh_history"; ln -s /dev/zero "$FL/odd/.bash_history"
python3 -c "import sys; open(sys.argv[1], 'w').write('export OPENAI_API_KEY=x\n' + '#' * 5000 + '\n')" "$FL/odd/.zshrc"
ln -s "$FL/clean" "$FL/homelink"; mkdir -p "$FL/notmine"
mkdir -p "$FL/noprot"; chmod 000 "$FL/noprot"; mkdir -p "$FL/prot"
users() { # name:home:uid:shell ... -> the users file
  : > "$FL/users.tsv"; for _e in "$@"; do printf '%s\n' "$_e" | tr ':' '\t' >> "$FL/users.tsv"; done
}
fl_run() { # out-prefix args...: a simulated root run; stdout, stderr, exit code, flat JSON
  _p=$1; shift; : > "$FL/argv.log"
  GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" \
    GIRD_CHECK_FLEET_STATE="$FL/state" GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" \
    bash "$FLEETSH" --all-users "$@" > "$FL/$_p.out" 2> "$FL/$_p.err" < /dev/null
  echo "$?" > "$FL/$_p.rc"
  python3 tests/fleet-flat.py "$FL/state/last.json" > "$FL/$_p.flat" 2>/dev/null || : > "$FL/$_p.flat"
}
mkdir -p "$FL/sharedtmp"
SKIPPING=$FSKIP
{
users "asha:$U:$FL/asha:/bin/zsh" "itadmin:$U:$FL/itadmin:/bin/zsh" "_spotlight:$U:$FL/clean:/bin/zsh" "daemon2:2:$FL/clean:/bin/sh"
fl_run two --json
has    "fleet: system accounts are left out" '^accounts=2$' "$FL/two.flat"
hasnot "fleet: and are not in the result" '_spotlight|daemon2' "$FL/two.flat"
has    "fleet: each account's row holds its own findings" '^asha\.key_files=4$' "$FL/two.flat"
if grep -q '^itadmin\.key_files=0$' "$FL/two.flat" && grep -q '^itadmin\.incidents=$' "$FL/two.flat" && grep -q '^itadmin\.ssh_keys_no_passphrase=1$' "$FL/two.flat"; then ok "fleet: and only its own"; else bad "fleet: and only its own" "$(grep '^itadmin' "$FL/two.flat" | tr '\n' ' ')"; fi
if [ "$(grep -c . "$FL/argv.log")" -eq 2 ] && grep -qE "^/usr/bin/sudo -n -u asha -H /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=$FL/asha /bin/bash /tmp/blindspot-copy\.[A-Za-z0-9]+/gird-check\.sh --account-run\$" "$FL/argv.log" \
   && grep -qE "^/usr/bin/sudo -n -u itadmin -H /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=$FL/itadmin /bin/bash " "$FL/argv.log"
then ok "fleet: each account is checked through sudo -n as itself, with a clean environment"
else bad "fleet: each account is checked through sudo -n as itself, with a clean environment" "$(cat "$FL/argv.log")"; fi
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$FL/two.out" 2>/dev/null; then ok "fleet: --json prints one JSON document and nothing else"; else bad "fleet: --json prints one JSON document and nothing else" "$(head -c 300 "$FL/two.out")"; fi
hasnot "fleet: the JSON holds no path or file name" '/(Users|home|private|tmp|var)/|~/|\.zshrc|zsh_history|\.env|settings(\.local)?\.json|mcp\.json' "$FL/two.out"
nokeys "fleet: the JSON holds no planted key" "$FL/keys-asha.txt" "$FL/two.out"
has    "fleet: act exits 10" '^10$' "$FL/two.rc"
if [ -d "$FL/state" ] && [ "$(stat -f '%u %Lp' "$FL/state")" = "$U 700" ] && [ "$(stat -f '%Lp' "$FL/state/last.json")" = 600 ]; then ok "fleet: the result is saved for its owner only"; else bad "fleet: the result is saved for its owner only" "$(ls -la "$FL/state" 2>&1 | head -n 3)"; fi
if diff -q <(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$FL/two.out") <(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$FL/state/last.json") > /dev/null 2>&1
then ok "fleet: the saved file is the JSON printed"; else bad "fleet: the saved file is the JSON printed"; fi
has    "fleet: the JSON names where to learn more" '^learn_more=https://gird.ai/argus$' "$FL/two.flat"
fl_run twoz --exit-zero --summary-to-stdout
has    "fleet: --exit-zero exits 0 on act" '^0$' "$FL/twoz.rc"
if [ "$(grep -c '' "$FL/twoz.out")" -eq 1 ] && grep -qE '^blindspot act accounts=2 act=1 review=1 not_checked=0 v=[0-9]+\.[0-9]+\.[0-9]+ at=20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$FL/twoz.out"
then ok "fleet: --summary-to-stdout prints the one summary line"; else bad "fleet: --summary-to-stdout prints the one summary line" "$(cat "$FL/twoz.out")"; fi
fl_run term
has    "fleet: the readable report lists each account" '^  asha +act now$' "$FL/term.out"
has    "fleet: and where the result was saved" "^  Saved: $FL/state/last.json\$" "$FL/term.out"
hasnot "fleet: no Argus note without a terminal" 'gird\.ai/argus|Argus' "$FL/term.out"
if command -v script > /dev/null 2>&1; then
  GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
    GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" script -q /dev/null bash "$FLEETSH" --all-users < /dev/null > "$FL/tty.out" 2>&1
  has  "fleet: the Argus note once, with a terminal" 'Roll it out through the MDM you' "$FL/tty.out"
  if LC_ALL=C grep -aq "$(printf '\033')" "$FL/tty.out"; then bad "fleet: no colours, even on a terminal"; else ok "fleet: no colours, even on a terminal"; fi
else skip "fleet: the Argus note once, with a terminal" "needs script(1) for a terminal"; skip "fleet: no colours, even on a terminal" "needs script(1) for a terminal"; fi
grep -v '^  Saved: ' "$FL/term.out" > "$FL/term-nosave.out"
hasnot "fleet: the readable report has no path or file name" '/|~|\.zshrc|\.env' "$FL/term-nosave.out"

# Which accounts: from fixtures.
users "gone:$U:$FL/nothere:/bin/zsh" "linked:$U:$FL/homelink:/bin/zsh" "other:$((U + 1)):$FL/notmine:/bin/zsh" \
      "first:$U:$FL/clean:/bin/zsh" "second:$U:$FL/clean:/bin/zsh" "noshell:$U:$FL/upd:/usr/bin/false" "sys:$U:/System:/bin/zsh"
fl_run list --list
if grep -q '^first  *will be checked$' "$FL/list.out" && [ ! -s "$FL/argv.log" ]; then ok "fleet: --list says who will be checked, and checks nothing"; else bad "fleet: --list says who will be checked, and checks nothing" "$(cat "$FL/list.out" "$FL/argv.log")"; fi
fl_run homes
has    "fleet: a missing home is not checked" '^gone\.not_checked=home_missing$' "$FL/homes.flat"
has    "fleet: a home that is a link is not checked" '^linked\.not_checked=home_link$' "$FL/homes.flat"
has    "fleet: a home owned by another account is not checked" '^other\.not_checked=home_owner$' "$FL/homes.flat"
has    "fleet: a home shared with an account above is not checked" '^second\.not_checked=home_shared$' "$FL/homes.flat"
has    "fleet: an account with no login shell is not checked" '^noshell\.not_checked=no_login_shell$' "$FL/homes.flat"
has    "fleet: a system folder as a home is not checked" '^sys\.not_checked=home_system$' "$FL/homes.flat"
has    "fleet: the one good account is checked" '^first\.outcome=clear$' "$FL/homes.flat"
if [ "$(grep -c . "$FL/argv.log")" -eq 1 ]; then ok "fleet: and only it is started"; else bad "fleet: and only it is started" "$(cat "$FL/argv.log")"; fi
has    "fleet: accounts not checked make the run not_checked" '^outcome=not_checked$' "$FL/homes.flat"
has    "fleet: not_checked exits 12" '^12$' "$FL/homes.rc"
users "_only:$U:$FL/clean:/bin/zsh"
fl_run none
if grep -q '^outcome=not_checked$' "$FL/none.flat" && grep -q '^accounts=0$' "$FL/none.flat" && grep -q '^12$' "$FL/none.rc"; then ok "fleet: no accounts is not_checked, never clear"; else bad "fleet: no accounts is not_checked, never clear" "$(cat "$FL/none.flat" "$FL/none.rc")"; fi

# An account run cannot speak for anyone else: any line out of place refuses its whole output.
users "asha:$U:$FL/asha:/bin/zsh" "itadmin:$U:$FL/itadmin:/bin/zsh"
grep '^itadmin\.' "$FL/two.flat" > "$FL/it-ok.txt"
for M in other-row machine oversize malformed; do
  printf '%s\n' "$M" > "$FL/mode-asha"
  fl_run "forge-$M"
  grep '^itadmin\.' "$FL/forge-$M.flat" > "$FL/it-$M.txt"
  has "fleet: $M output makes that account not checked" '^asha\.not_checked=bad_output$' "$FL/forge-$M.flat"
  if diff -q "$FL/it-ok.txt" "$FL/it-$M.txt" > /dev/null; then ok "fleet: $M output changes no other row"; else bad "fleet: $M output changes no other row" "$(diff "$FL/it-ok.txt" "$FL/it-$M.txt" | head -n 4)"; fi
done
printf 'endless\n' > "$FL/mode-asha"
T0=$SECONDS; fl_run endless --deadline=60; T1=$((SECONDS - T0))
if grep -q '^asha\.not_checked=bad_output$' "$FL/endless.flat" && [ "$T1" -lt 20 ]; then ok "fleet: root reads a set number of bytes, then stops the run" "${T1}s"; else bad "fleet: root reads a set number of bytes, then stops the run" "${T1}s $(grep '^asha' "$FL/endless.flat")"; fi
rm -f "$FL/mode-asha"
hasnot "fleet: nothing an account run sent reaches the result" 'forged|99999' "$FL/forge-malformed.flat"
printf 'fail\n' > "$FL/mode-asha"; fl_run sudofail
has    "fleet: sudo failing means not checked" '^asha\.not_checked=sudo$' "$FL/sudofail.flat"
printf 'chmod\n' > "$FL/mode-asha"; fl_run copy
if grep -q '^13$' "$FL/copy.rc" && grep -q '^outcome=failed$' "$FL/copy.flat" && grep -q '^itadmin\.not_checked=copy_changed$' "$FL/copy.flat"; then ok "fleet: a script copy an account could write stops the run"; else bad "fleet: a script copy an account could write stops the run" "$(cat "$FL/copy.rc"; grep -E '^(outcome|itadmin\.not)' "$FL/copy.flat")"; fi
rm -f "$FL/mode-asha"

# A run that holds its output open past its limit, and a process that leaves its group.
printf 'hold\n' > "$FL/mode-asha"
T0=$SECONDS
( GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
    GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" bash "$FLEETSH" --all-users --deadline=40 --summary-to-stdout < /dev/null 2>&1; echo "rc=$?" ) | cat > "$FL/hold.out"
T1=$((SECONDS - T0))
python3 tests/fleet-flat.py "$FL/state/last.json" > "$FL/hold.flat" 2>/dev/null
if [ "$T1" -lt 40 ] && grep -q '^rc=12$' "$FL/hold.out"; then ok "fleet: a stuck account run is stopped and the MDM's output closes" "${T1}s"; else bad "fleet: a stuck account run is stopped and the MDM's output closes" "${T1}s, $(cat "$FL/hold.out")"; fi
has    "fleet: that account is partly checked" '^asha\.not_checked=time_limit$' "$FL/hold.flat"
has    "fleet: a process that outlives the stop is reported" '^asha\.processes_left=true$' "$FL/hold.flat"
has    "fleet: the other account is still checked" '^itadmin\.outcome=review$' "$FL/hold.flat"
pkill -f 'fleet-hold-escapee' 2>/dev/null; rm -f "$FL/mode-asha"
users "asha:$U:$FL/asha:/bin/zsh"
fl_run late --deadline=1
if grep -q '^asha\.not_checked=deadline$' "$FL/late.flat" && grep -q '^deadline_reached=true$' "$FL/late.flat" && grep -q '^12$' "$FL/late.rc"; then ok "fleet: a run stopped by its deadline is not_checked"; else bad "fleet: a run stopped by its deadline is not_checked" "$(cat "$FL/late.flat" | head -n 5)"; fi

# What an account run reads.
users "linker:$U:$FL/linker:/bin/zsh"
fl_run links
if grep -q '^linker\.key_files=0$' "$FL/links.flat" && grep -q '^linker\.history_keys=0$' "$FL/links.flat"; then ok "fleet: links to another home or a system file are read with the account's own rights"; else bad "fleet: links to another home or a system file are read with the account's own rights" "$(grep '^linker' "$FL/links.flat" | tr '\n' ' ')"; fi
nokeys "fleet: and the key behind them is never in the result" "$FL/keys-asha.txt" "$FL/state/last.json"
users "odd:$U:$FL/odd:/bin/zsh"
printf 'maxbytes\n' > "$FL/mode-odd"
T0=$SECONDS; fl_run odd --deadline=60; T1=$((SECONDS - T0))
if grep -q '^odd\.files_not_checked=3$' "$FL/odd.flat" && grep -q '^odd\.key_files=0$' "$FL/odd.flat" && [ "$T1" -lt 30 ]; then ok "fleet: a fifo, a link to a device and an oversized file are not read, and are counted"; else bad "fleet: a fifo, a link to a device and an oversized file are not read, and are counted" "${T1}s $(grep '^odd' "$FL/odd.flat" | tr '\n' ' ')"; fi
has    "fleet: so the account is not_checked, never clear" '^odd\.outcome=not_checked$' "$FL/odd.flat"
rm -f "$FL/mode-odd"
users "clean:$U:$FL/clean:/bin/zsh"
printf 'noprot\n' > "$FL/mode-clean"; fl_run prot
if grep -q '^clean\.protected_folders=not_checked$' "$FL/prot.flat" && grep -q '^clean\.outcome=not_checked$' "$FL/prot.flat"; then ok "fleet: a refused protected folder is not checked, never clear"; else bad "fleet: a refused protected folder is not checked, never clear" "$(grep '^clean' "$FL/prot.flat" | tr '\n' ' ')"; fi
rm -f "$FL/mode-clean"
fl_run clear
mkdir -p "$FL/noprotdirs"; users "bare:$U:$FL/noprotdirs:/bin/zsh"
fl_run bare
if grep -q '^bare\.protected_folders=checked$' "$FL/bare.flat" && grep -q '^bare\.outcome=clear$' "$FL/bare.flat"; then ok "fleet: with no protected folder in the home, there is nothing protected to miss"; else bad "fleet: with no protected folder in the home, there is nothing protected to miss" "$(grep '^bare' "$FL/bare.flat" | tr '\n' ' ')"; fi
users "clean:$U:$FL/clean:/bin/zsh"
if grep -q '^outcome=clear$' "$FL/clear.flat" && grep -q '^0$' "$FL/clear.rc" && grep -q '^clean\.protected_folders=checked$' "$FL/clear.flat"; then ok "fleet: clear exits 0"; else bad "fleet: clear exits 0" "$(cat "$FL/clear.rc"; head -n 4 "$FL/clear.flat")"; fi
users "upd:$U:$FL/upd:/bin/zsh"
fl_run upd
if grep -q '^outcome=review$' "$FL/upd.flat" && grep -q '^11$' "$FL/upd.rc"; then ok "fleet: review exits 11"; else bad "fleet: review exits 11" "$(cat "$FL/upd.rc")"; fi
users "upd:$U:$FL/upd:/bin/zsh" "gone:$U:$FL/nothere:/bin/zsh"
fl_run order1
has    "fleet: not_checked comes before review" '^outcome=not_checked$' "$FL/order1.flat"
users "asha:$U:$FL/asha:/bin/zsh" "gone:$U:$FL/nothere:/bin/zsh"
fl_run order2
has    "fleet: act comes before not_checked" '^outcome=act$' "$FL/order2.flat"

# Root runs nothing a person can replace.
FAKE=$FL/fakebin; mkdir -p "$FAKE"
for t in jq rg grep sudo dscl stat perl find awk sed cat head mktemp open curl uname sysctl tput tr cut date; do
  printf '#!/bin/sh\necho %s >> "%s/fake-ran"\nexit 1\n' "$t" "$FL" > "$FAKE/$t"; chmod +x "$FAKE/$t"
done
users "asha:$U:$FL/asha:/bin/zsh" "itadmin:$U:$FL/itadmin:/bin/zsh"
rm -f "$FL/fake-ran"
PATH="$FAKE:$PATH" fl_run fakes
if [ ! -e "$FL/fake-ran" ] && grep -q '^asha\.key_files=4$' "$FL/fakes.flat" && [ "$(cat "$FL/launch-path")" = /usr/bin:/bin:/usr/sbin:/sbin ]; then ok "fleet: a replaced jq, grep or sudo earlier in PATH is never run"; else bad "fleet: a replaced jq, grep or sudo earlier in PATH is never run" "$(cat "$FL/fake-ran" 2>/dev/null | tr '\n' ' ') PATH at sudo: $(cat "$FL/launch-path" 2>/dev/null)"; fi
# No network request, no browser, no saved report.
mkdir -p "$FL/cwd"; : > "$WORK/received.log"; : > "$WORK/gets.log"
( cd "$FL/cwd" && GIRD_CHECK_API="$API" FLL_API="$API" PATH="$FAKE:$PATH" fl_run net )
if [ ! -s "$WORK/received.log" ] && [ ! -s "$WORK/gets.log" ] && grep -q '^10$' "$FL/net.rc"; then ok "fleet: makes no network request"; else bad "fleet: makes no network request" "exit $(cat "$FL/net.rc")"; fi
if [ ! -e "$FL/fake-ran" ] && [ -z "$(ls "$FL/cwd")" ]; then ok "fleet: opens no browser and saves no report"; else bad "fleet: opens no browser and saves no report" "$(ls "$FL/cwd"; cat "$FL/fake-ran" 2>/dev/null)"; fi
# An MDM-like run: no HOME, a minimal PATH, / as the working folder, no terminal.
( cd / && env -i PATH=/usr/bin:/bin GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" \
    GIRD_CHECK_FLEET_STATE="$FL/state" GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" /bin/bash "$FLEETSH" --all-users --summary-to-stdout < /dev/null > "$FL/mdm.out" 2>&1 )
has    "fleet: runs with no HOME, a minimal PATH and / as its folder" '^blindspot act accounts=2 ' "$FL/mdm.out"
# An MDM item passes its options in one line under the first line (docs/fleet.md), whatever arguments the MDM adds.
mkdir -p "$FL/inst"; cp "$SCRIPT" "$FL/inst/gird-check.sh"
python3 -c "import sys; l = open(sys.argv[1]).read().split('\n', 1); open(sys.argv[2], 'w').write(l[0] + '\ncase \"\${1:-}\" in --inventory) ;; *) set -- --all-users --summary-to-stdout --deadline=600 ;; esac\n' + l[1])" "$FLEETSH" "$FL/inst/mdm-item.sh"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" bash "$FL/inst/mdm-item.sh" / "$(hostname)" root < /dev/null > "$FL/mdm-item.out" 2>&1
FLVER=$(sed -n '2s/^# Blindspot, .*, version \([0-9][0-9.]*\) .*/\1/p' "$SCRIPT")
has    "fleet: an MDM item's options line works whatever arguments the MDM adds" "^blindspot act accounts=2 act=1 review=1 not_checked=0 v=${FLVER:-no-version} at=" "$FL/mdm-item.out"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FL/inst/mdm-item.sh" --inventory < /dev/null > "$FL/mdm-inv.out" 2>&1
has    "fleet: with the options line in the file, --inventory still only reads the result" '^v1 act ' "$FL/mdm-inv.out"
python3 -c "import sys; l = open(sys.argv[1]).read().split('\n', 1); open(sys.argv[2], 'w').write(l[0] + '\ncase \"\${1:-}\" in --inventory) ;; *) set -- --all-users --summary-to-stdout --hash-accounts=fleet-test-secret-42 ;; esac\n' + l[1])" "$FLEETSH" "$FL/inst/mdm-secret.sh"
rm -f "$FL/copycheck"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" FLL_COPYCHECK=fleet-test-secret-42 bash "$FL/inst/mdm-secret.sh" < /dev/null > "$FL/mdm-secret.out" 2>&1
if [ "$(tr -d '\n' < "$FL/copycheck" 2>/dev/null)" = 00 ] && grep -q '^blindspot act ' "$FL/mdm-secret.out"; then ok "fleet: the copy each account runs leaves out the options line and its secret"; else bad "fleet: the copy each account runs leaves out the options line and its secret" "$(cat "$FL/copycheck" 2>/dev/null)"; fi
if cmp -s "$FL/copy-seen.sh" "$SCRIPT"; then ok "fleet: and removes nothing else"; else bad "fleet: and removes nothing else" "$(diff "$SCRIPT" "$FL/copy-seen.sh" 2>&1 | head -n 4)"; fi
# Root runs for every account only what root alone can change.
mkdir -p "$FL/gw"; cp "$SCRIPT" "$FLEETSH" "$FL/gw/"; chmod 775 "$FL/gw"; : > "$FL/argv.log"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  FLL_DIR="$FL" bash "$FL/gw/gird-fleet.sh" --all-users < /dev/null > "$FL/gw.out" 2> "$FL/gw.err"; RC=$?
if [ "$RC" -eq 13 ] && [ ! -s "$FL/argv.log" ] && grep -q 'every folder above them must be owned by root and writable by no one else' "$FL/gw.err"; then ok "fleet: a script in a folder others can write to is refused"; else bad "fleet: a script in a folder others can write to is refused" "exit $RC $(cat "$FL/gw.err")"; fi
chmod 755 "$FL/gw"
mkdir -p "$FL/gw2"; cp "$SCRIPT" "$FLEETSH" "$FL/gw2/"; chmod 664 "$FL/gw2/gird-check.sh"; : > "$FL/argv.log"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  FLL_DIR="$FL" bash "$FL/gw2/gird-fleet.sh" --all-users < /dev/null > "$FL/gw2.out" 2> "$FL/gw2.err"; RC=$?
if [ "$RC" -eq 13 ] && [ ! -s "$FL/argv.log" ] && grep -q 'every folder above them must be owned by root and writable by no one else' "$FL/gw2.err"; then ok "fleet: a gird-check.sh others can write to is refused"; else bad "fleet: a gird-check.sh others can write to is refused" "exit $RC $(cat "$FL/gw2.err")"; fi
mkdir -p "$FL/alone"; cp "$FLEETSH" "$FL/alone/"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  FLL_DIR="$FL" bash "$FL/alone/gird-fleet.sh" --all-users < /dev/null > /dev/null 2> "$FL/alone.err"; RC=$?
if [ "$RC" -eq 13 ] && grep -q 'gird-check.sh must sit next to gird-fleet.sh' "$FL/alone.err"; then ok "fleet: without gird-check.sh next to it, it stops and says why"; else bad "fleet: without gird-check.sh next to it, it stops and says why" "exit $RC $(cat "$FL/alone.err")"; fi
# Modes with no owner bits, read with three digits: 002 and 020 are writable by others, not "2" and "20".
# Nobody but root can run a script that sits in or below such a mode, so a test run adds one such path
# to the paths root checks (GIRD_CHECK_FLEET_CHECK_ALSO, read only when not root).
for M in 002 020; do
  : > "$FL/mode$M"; chmod "$M" "$FL/mode$M"
  GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
    GIRD_CHECK_FLEET_CHECK_ALSO="$FL/mode$M" FLL_DIR="$FL" bash "$FLEETSH" --all-users < /dev/null > "$FL/m$M.out" 2> "$FL/m$M.err"
  has "fleet: a path with mode $M is refused as writable by others" 'every folder above them must be owned by root and writable by no one else' "$FL/m$M.err"
done
# Run by a relative path from the script's folder, as the guide shows; from standard input it can't copy itself.
( cd "$(dirname "$FLEETSH")" && GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" bash gird-fleet.sh --all-users --summary-to-stdout < /dev/null > "$FL/rel.out" 2>&1 )
has    "fleet: runs by a relative path from the script's folder" '^blindspot act accounts=2 act=1 review=1 not_checked=0 ' "$FL/rel.out"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  FLL_DIR="$FL" bash -s -- --all-users < "$FLEETSH" > "$FL/stdin.out" 2> "$FL/stdin.err"; RC=$?
if [ "$RC" -eq 13 ] && grep -q 'run it from a file: it copies gird-check.sh from its own folder' "$FL/stdin.err"; then ok "fleet: from standard input it fails, and says why"; else bad "fleet: from standard input it fails, and says why" "exit $RC $(cat "$FL/stdin.err")"; fi

# The Mac's shared places.
: > "$FL/sharedtmp/.pc_once_x"; : > "/tmp/.pc_once_blindspot-fleet-test-$$"
fl_run machine
rm -f "$FL/sharedtmp/.pc_once_x" "/tmp/.pc_once_blindspot-fleet-test-$$"
has    "fleet: a malware marker in the shared temp folder is a machine finding" '^machine\.incidents=litellm$' "$FL/machine.flat"
hasnot "fleet: and never an account's" '^itadmin\.incidents=.*litellm' "$FL/machine.flat"

# The saved result's folder.
users "itadmin:$U:$FL/itadmin:/bin/zsh"
rm -rf "$FL/state" "$FL/elsewhere"; mkdir -p "$FL/elsewhere"; ln -s "$FL/elsewhere" "$FL/state"
fl_run slink
if [ -d "$FL/state" ] && [ ! -L "$FL/state" ] && [ "$(stat -f %Lp "$FL/state")" = 700 ] && [ -f "$FL/state/last.json" ] && [ -z "$(ls "$FL/elsewhere")" ]; then ok "fleet: a saved-result folder that is a link is made again"; else bad "fleet: a saved-result folder that is a link is made again" "$(ls -la "$FL/state" "$FL/elsewhere" 2>&1 | head -n 6)"; fi
rm -rf "$FL"/state*; mkdir -m 700 "$FL/state"; printf 'keep\n' > "$FL/target"; ln -s "$FL/target" "$FL/state/last.json"
fl_run swrite
if [ "$(cat "$FL/target")" = keep ] && [ -f "$FL/state/last.json" ] && [ ! -L "$FL/state/last.json" ]; then ok "fleet: the result is written to a new file and renamed into place"; else bad "fleet: the result is written to a new file and renamed into place"; fi
rm -rf "$FL"/state*; mkdir -m 755 "$FL/state"
fl_run smode
if [ "$(stat -f %Lp "$FL/state")" = 700 ] && [ -f "$FL/state/last.json" ]; then ok "fleet: a saved-result folder anyone can read is made again"; else bad "fleet: a saved-result folder anyone can read is made again"; fi
: > "$FL/argv.log"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE=/var/empty \
  GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" bash "$FLEETSH" --all-users --summary-to-stdout < /dev/null > "$FL/sother.out" 2>&1; RC=$?
if [ "$RC" -eq 13 ] && grep -q '^blindspot failed ' "$FL/sother.out" && [ ! -e /var/empty/last.json ]; then ok "fleet: a saved-result folder owned by someone else is never written to"; else bad "fleet: a saved-result folder owned by someone else is never written to" "exit $RC $(cat "$FL/sother.out")"; fi

# The inventory value and the reader an MDM runs at check-in.
users "asha:$U:$FL/asha:/bin/zsh" "itadmin:$U:$FL/itadmin:/bin/zsh"
rm -rf "$FL/state"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory > "$FL/inv0.out" 2>&1
has    "fleet: --inventory says none before the first run" '^none$' "$FL/inv0.out"
fl_run inv
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory > "$FL/inv1.out" 2>&1
if [ "$(cat "$FL/inv1.out")" = "$(sed -n 's/^inventory=//p' "$FL/inv.flat")" ] && grep -qE '^v1 act 20[0-9-]{8}T[0-9]{2}:[0-9]{2}Z \| asha: act ' "$FL/inv1.out"; then ok "fleet: --inventory prints the saved inventory value"; else bad "fleet: --inventory prints the saved inventory value" "$(cat "$FL/inv1.out")"; fi
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory --result-tags > "$FL/inv-tags.out" 2>&1
has    "fleet: --result-tags puts the value between Jamf's result tags" '^<result>v1 act .*</result>$' "$FL/inv-tags.out"
if [ "$(wc -c < "$FL/inv1.out")" -le 256 ] && ! grep -qE '/|\.zshrc|\.env' "$FL/inv1.out"; then ok "fleet: the inventory value fits and holds no path or file name"; else bad "fleet: the inventory value fits and holds no path or file name"; fi
python3 - "$FL/state/last.json" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, 'w').write(re.sub(r'"checked_epoch": \d+', '"checked_epoch": 1000000000', s))
PY
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory --stale-days=3 > "$FL/inv2.out" 2>&1
has    "fleet: --inventory says stale when the last run is too old" '^stale: last run 2001-09-09T' "$FL/inv2.out"
FLU=(); for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do FLU+=("person$i:$U:$FL/many$i:/bin/zsh"); fl_home "many$i"; done
users "${FLU[@]}"
fl_run many --deadline=600
if grep -qE ' \+more$' "$FL/many.out" 2>/dev/null || grep -qE '^inventory=.* \+more$' "$FL/many.flat"; then ok "fleet: a long inventory value ends with +more"; else bad "fleet: a long inventory value ends with +more" "$(grep '^inventory' "$FL/many.flat")"; fi
if [ "$(sed -n 's/^inventory=//p' "$FL/many.flat" | wc -c)" -le 256 ]; then ok "fleet: and still fits"; else bad "fleet: and still fits"; fi

# Names: a keyed hash on request.
users "asha:$U:$FL/asha:/bin/zsh" "itadmin:$U:$FL/itadmin:/bin/zsh"
fl_run hash1 --hash-accounts=first-secret
fl_run hash2 --hash-accounts=other-secret
if grep -qE '^[0-9a-f]{16}\.outcome=act$' "$FL/hash1.flat" && ! grep -q 'asha' "$FL/state/last.json" && [ "$(grep -cE '^[0-9a-f]{16}\.outcome=' "$FL/hash1.flat")" -eq 2 ] \
   && [ "$(grep -E '^[0-9a-f]{16}\.outcome=act$' "$FL/hash1.flat")" != "$(grep -E '^[0-9a-f]{16}\.outcome=act$' "$FL/hash2.flat")" ]
then ok "fleet: --hash-accounts shows a keyed hash, never the name"; else bad "fleet: --hash-accounts shows a keyed hash, never the name" "$(grep outcome "$FL/hash1.flat" "$FL/hash2.flat")"; fi

# Refusals.
bash "$FLEETSH" --all-users > "$FL/noroot.out" 2> "$FL/noroot.err"; RC=$?
if [ "$RC" -eq 13 ] && [ ! -s "$FL/noroot.out" ] && grep -q 'needs root' "$FL/noroot.err"; then ok "fleet: not root exits 13"; else bad "fleet: not root exits 13" "exit $RC"; fi
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" FLL_DIR="$FL" \
  bash "$FLEETSH" --all-users --all > /dev/null 2> "$FL/all.err"; RC=$?
if [ "$RC" -eq 13 ] && grep -q -- '--all is refused' "$FL/all.err"; then ok "fleet: --all with --all-users is refused"; else bad "fleet: --all with --all-users is refused" "exit $RC"; fi
# As root, every test setting is ignored: GIRD_CHECK_FLEET_REAL_ROOT takes the path a real root run takes.
: > "$FL/argv.log"; rm -rf "$FL/state-root"
GIRD_CHECK_FLEET_REAL_ROOT=1 GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" \
  GIRD_CHECK_FLEET_STATE="$FL/state-root" FLL_DIR="$FL" bash "$FLEETSH" --all-users > /dev/null 2> "$FL/realroot.err"; RC=$?
if [ "$RC" -eq 13 ] && [ ! -s "$FL/argv.log" ] && [ ! -e "$FL/state-root" ] && grep -q 'needs root' "$FL/realroot.err"; then ok "fleet: run as root, the test settings are ignored"; else bad "fleet: run as root, the test settings are ignored" "exit $RC"; fi
bash "$FLEETSH" --json > /dev/null 2>&1; RC=$?
if [ "$RC" -eq 2 ]; then ok "fleet: --json without --all-users is refused"; else bad "fleet: --json without --all-users is refused" "exit $RC"; fi
}
SKIPPING=""
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_OS=Linux bash "$FLEETSH" --all-users > "$FL/linux.out" 2> "$FL/linux.err"; RC=$?
if [ "$RC" -eq 13 ] && [ ! -s "$FL/linux.out" ] && grep -q 'macOS only so far; Linux comes next' "$FL/linux.err"; then ok "fleet: on Linux --all-users exits 13 with a message"; else bad "fleet: on Linux --all-users exits 13 with a message" "exit $RC"; fi
chmod 755 "$FL/keeper/private" "$FL/noprot" 2>/dev/null
# From an IT team's review: what an account can do to a result, and what an account run can miss.
SKIPPING=$FSKIP
{
users "bad name:$U:$FL/clean:/bin/zsh" "itadmin:$U:$FL/itadmin:/bin/zsh"
fl_run badname
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory > "$FL/badname-inv.out" 2>&1
if grep -q '^invalid-name\.not_checked=name$' "$FL/badname.flat" && grep -qE '^v1 [a-z_]+ .*\| invalid-name: not_checked name' "$FL/badname-inv.out"; then ok "fleet: an account name it can't read is shown as invalid-name, and the inventory still reads"; else bad "fleet: an account name it can't read is shown as invalid-name, and the inventory still reads" "$(cat "$FL/badname-inv.out")"; fi
mkdir -p "$FL/unread/Library/Safari" "$FL/unread/code/locked"; printf 'export OPENAI_API_KEY=x\n' > "$FL/unread/.zshrc"; chmod 000 "$FL/unread/.zshrc" "$FL/unread/code/locked"
users "unread:$U:$FL/unread:/bin/zsh"
fl_run unread
chmod 755 "$FL/unread/code/locked"; chmod 644 "$FL/unread/.zshrc"
if grep -qE '^unread\.files_not_checked=([2-9]|[1-9][0-9]+)$' "$FL/unread.flat" && grep -q '^unread\.outcome=not_checked$' "$FL/unread.flat"; then ok "fleet: a file or folder the account can't read is not checked, never clear"; else bad "fleet: a file or folder the account can't read is not checked, never clear" "$(grep '^unread' "$FL/unread.flat" | tr '\n' ' ')"; fi
mkdir -p "$FL/binhome/Library/Safari" "$FL/binhome/.local/bin"; : > "$FL/binhome/.local/bin/aider"; chmod 755 "$FL/binhome/.local/bin/aider"
users "binhome:$U:$FL/binhome:/bin/zsh"
fl_run binhome
has    "fleet: an agent in the account's own ~/.local/bin is found" '^binhome\.agents=.*aider' "$FL/binhome.flat"
# A marker that must be the person's own (gh-token-monitor's /tmp logs) is never the Mac's: any account could leave one.
users "itadmin:$U:$FL/itadmin:/bin/zsh"
: > "$FL/sharedtmp/gh-token-monitor.out.log"
fl_run ownmark
rm -f "$FL/sharedtmp/gh-token-monitor.out.log"
hasnot "fleet: a marker that must be its owner's never counts for the Mac" '^machine\.incidents=.*tanstack' "$FL/ownmark.flat"
if [ -e /tmp/gh-token-monitor.out.log ] || [ -L /tmp/gh-token-monitor.out.log ]; then
  skip "fleet: and counts for the account that owns it" "/tmp/gh-token-monitor.out.log is already on this Mac; the test leaves it alone"
  skip "fleet: but a link there never counts" "/tmp/gh-token-monitor.out.log is already on this Mac; the test leaves it alone"
  skip "fleet: nor a hard link there" "/tmp/gh-token-monitor.out.log is already on this Mac; the test leaves it alone"
else
  : > /tmp/gh-token-monitor.out.log; fl_run ownmark2; rm -f /tmp/gh-token-monitor.out.log
  has  "fleet: and counts for the account that owns it" '^itadmin\.incidents=.*tanstack' "$FL/ownmark2.flat"
  : > "$FL/itadmin-file"; ln -s "$FL/itadmin-file" /tmp/gh-token-monitor.out.log; fl_run ownmark3; rm -f /tmp/gh-token-monitor.out.log
  hasnot "fleet: but a link there never counts" '^itadmin\.incidents=.*tanstack' "$FL/ownmark3.flat"
  : > "$FL/itadmin-file2"; ln "$FL/itadmin-file2" /tmp/gh-token-monitor.out.log 2>/dev/null; HL=$?
  fl_run ownmark4; rm -f /tmp/gh-token-monitor.out.log
  if [ "$HL" -ne 0 ]; then skip "fleet: nor a hard link there" "can't make a hard link into /tmp from the test folder here"
  else hasnot "fleet: nor a hard link there" '^itadmin\.incidents=.*tanstack' "$FL/ownmark4.flat"; fi
fi
# A machine check that does not answer in time leaves the Mac partly checked.
users "clean:$U:$FL/clean:/bin/zsh"
: > "$FL/sharedtmp/remote_code_loader.lock"; printf '#!/bin/sh\nexec /bin/sleep 60\n' > "$FL/slow-lsof"; chmod +x "$FL/slow-lsof"
GIRD_CHECK_FLEET_LSOF="$FL/slow-lsof" fl_run slowlsof
rm -f "$FL/sharedtmp/remote_code_loader.lock"
if grep -q '^machine\.complete=false$' "$FL/slowlsof.flat" && ! grep -q '^outcome=clear$' "$FL/slowlsof.flat"; then ok "fleet: a machine check that runs out of time leaves the Mac not checked"; else bad "fleet: a machine check that runs out of time leaves the Mac not checked" "$(grep -E '^(machine|outcome)' "$FL/slowlsof.flat" | tr '\n' ' ')"; fi
# A run the MDM stopped part-way is not hidden behind the last finished result.
fl_run attempt1
python3 - "$FL/state" <<'PY2'
import re, sys, time
d = sys.argv[1]; now = int(time.time())
s = open(d + '/last.json').read(); open(d + '/last.json', 'w').write(re.sub(r'"checked_epoch": \d+', '"checked_epoch": %d' % (now - 100), s))
open(d + '/attempt', 'w').write('%d 10\n' % (now - 50))
PY2
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory > "$FL/attempt-old.out" 2>&1
has    "fleet: --inventory says failed when a later run did not finish by its deadline" '^failed: the run started 20[0-9-]{8}T[0-9:]{5}Z did not finish or could not save its result$' "$FL/attempt-old.out"
python3 -c "import sys, time; open(sys.argv[1], 'w').write('%d 3000\n' % (int(time.time()) - 5))" "$FL/state/attempt"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory > "$FL/attempt-run.out" 2>&1
has    "fleet: and the last result while that run still has time" '^v1 ' "$FL/attempt-run.out"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$FL/state" bash "$FLEETSH" --inventory --stale-days=31 > /dev/null 2>&1; RC=$?
if [ "$RC" -eq 2 ]; then ok "fleet: --stale-days is at most 30"; else bad "fleet: --stale-days is at most 30" "exit $RC"; fi
# An account run uses ripgrep only from the admin path (FLL_RG_ADMIN in tests), as a regular file
# whose folders are real folders, all root's (FLL_RG_ROOTUID stands in for root); otherwise perl.
users "asha:$U:$FL/asha:/bin/zsh"
mk_rg() { mkdir -p "$1"; printf '#!/bin/sh\ncase "$1" in --version) echo "ripgrep 14.1.0"; exit 0 ;; esac\n: > "$(dirname "$0")/ran"\nexit 1\n' > "$1/rg"; chmod 755 "$1/rg"; }
FLP=$(cd "$FL" && pwd -P)   # the test folder without links above it, as /Library is
for d in rgok rgmine rgw rgacl rgfolder; do mk_rg "$FLP/$d/bin"; done
chmod 775 "$FLP/rgw/bin"
mkdir -p "$FLP/rglinkroot/bin"; ln -s /usr/bin/true "$FLP/rglinkroot/bin/rg"
mkdir -p "$FLP/rgviafolder"; ln -s "$FLP/rgfolder/bin" "$FLP/rgviafolder/bin"
FLL_RG_ADMIN="$FLP/rgmine/bin/rg" fl_run rgmine
if grep -q '^asha\.session_engine=perl$' "$FL/rgmine.flat" && [ ! -e "$FLP/rgmine/bin/ran" ]; then ok "fleet: a ripgrep the account owns is never run"; else bad "fleet: a ripgrep the account owns is never run" "$(grep session_engine "$FL/rgmine.flat")"; fi
FLL_RG_ADMIN="$FLP/rgok/bin/rg" FLL_RG_ROOTUID=$U fl_run rgok
if grep -q '^asha\.session_engine=rg$' "$FL/rgok.flat" && [ -e "$FLP/rgok/bin/ran" ]; then ok "fleet: a ripgrep root alone can change is used"; else bad "fleet: a ripgrep root alone can change is used" "$(grep session_engine "$FL/rgok.flat")"; fi
FLL_RG_ADMIN="$FLP/rglinkroot/bin/rg" FLL_RG_ROOTUID=$U fl_run rglinkroot
has    "fleet: a link at the ripgrep path is never run, even to a root-owned program" '^asha\.session_engine=perl$' "$FL/rglinkroot.flat"
FLL_RG_ADMIN="$FLP/rgviafolder/bin/rg" FLL_RG_ROOTUID=$U fl_run rgviafolder
if grep -q '^asha\.session_engine=perl$' "$FL/rgviafolder.flat" && [ ! -e "$FLP/rgfolder/bin/ran" ]; then ok "fleet: a ripgrep reached through a linked folder is never run"; else bad "fleet: a ripgrep reached through a linked folder is never run" "$(grep session_engine "$FL/rgviafolder.flat")"; fi
FLL_RG_ADMIN="$FLP/rgw/bin/rg" FLL_RG_ROOTUID=$U fl_run rgw
has    "fleet: a ripgrep in a folder others can write to is not used" '^asha\.session_engine=perl$' "$FL/rgw.flat"
if chmod +a "everyone allow write" "$FLP/rgacl/bin/rg" 2>/dev/null; then
  FLL_RG_ADMIN="$FLP/rgacl/bin/rg" FLL_RG_ROOTUID=$U fl_run rgacl; chmod -N "$FLP/rgacl/bin/rg"
  has  "fleet: a ripgrep whose ACL lets anyone write is not used" '^asha\.session_engine=perl$' "$FL/rgacl.flat"
else skip "fleet: a ripgrep whose ACL lets anyone write is not used" "chmod +a is not available here"; fi
# Only the admin path is ever looked at: no Homebrew or /usr/local ripgrep, which an account may re-point.
sed -n '/^fleet_rg() {/,/^}/p' "$SCRIPT" > "$FL/fleet_rg.txt"
if grep -q 'Library/Application Support/Blindspot/rg' "$FL/fleet_rg.txt" && ! grep -qE 'homebrew|/usr/local|\.local/bin|\.cargo|abs_path|realpath|readlink' "$FL/fleet_rg.txt"; then ok "fleet: a Homebrew or /usr/local ripgrep is never looked at"; else bad "fleet: a Homebrew or /usr/local ripgrep is never looked at" "$(grep -nE 'homebrew|/usr/local|abs_path' "$FL/fleet_rg.txt")"; fi
fl_run rgnone
if grep -q '^asha\.session_engine=perl$' "$FL/rgnone.flat" && grep -q '^asha\.session_files_with_keys=3$' "$FL/rgnone.flat"; then ok "fleet: with no ripgrep that qualifies, perl checks the sessions"; else bad "fleet: with no ripgrep that qualifies, perl checks the sessions" "$(grep -E 'session' "$FL/rgnone.flat" | tr '\n' ' ')"; fi
# A real ripgrep, where this Mac has one, finds what perl finds (a copy at a test admin path).
RRG=$(command -v rg 2>/dev/null)
if [ -z "$RRG" ]; then skip "fleet: a real ripgrep finds the same session keys as perl" "ripgrep is not installed here"
else
  mkdir -p "$FLP/rgreal/bin"; cp "$RRG" "$FLP/rgreal/bin/rg"; chmod 755 "$FLP/rgreal/bin/rg"
  FLL_RG_ADMIN="$FLP/rgreal/bin/rg" FLL_RG_ROOTUID=$U fl_run rgreal
  if grep -q '^asha\.session_engine=rg$' "$FL/rgreal.flat" && [ "$(grep '^asha\.session_files_with_keys=' "$FL/rgreal.flat")" = "$(grep '^asha\.session_files_with_keys=' "$FL/rgnone.flat")" ] && grep -q '^asha\.sessions_partly_checked=false$' "$FL/rgreal.flat"; then ok "fleet: a real ripgrep finds the same session keys as perl"
  else bad "fleet: a real ripgrep finds the same session keys as perl" "$(grep -E 'session' "$FL/rgreal.flat" | tr '\n' ' ')"; fi
fi
# Installed as the guide says: gird-fleet.sh readable by root only (0700), gird-check.sh 0755.
users "asha:$U:$FL/asha:/bin/zsh" "itadmin:$U:$FL/itadmin:/bin/zsh"
mkdir -p "$FL/inst700"; cp "$SCRIPT" "$FLEETSH" "$FL/inst700/"; chmod 755 "$FL/inst700/gird-check.sh"; chmod 700 "$FL/inst700/gird-fleet.sh"
GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
  GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" /usr/bin/env -i PATH=/usr/bin:/bin GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" \
  GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" GIRD_CHECK_FLEET_SHARED_TMP="$FL/sharedtmp" FLL_DIR="$FL" \
  /bin/bash "$FL/inst700/gird-fleet.sh" --all-users --summary-to-stdout < /dev/null > "$FL/inst700.out" 2>&1; RC=$?
if [ "$RC" -eq 10 ] && grep -q '^blindspot act accounts=2 ' "$FL/inst700.out"; then ok "fleet: installed as the guide says, run with env -i, it runs"; else bad "fleet: installed as the guide says, run with env -i, it runs" "exit $RC $(cat "$FL/inst700.out")"; fi
# An ACL that lets anyone write counts as writable by someone else.
mkdir -p "$FL/acl"; cp "$SCRIPT" "$FLEETSH" "$FL/acl/"
if chmod +a "everyone allow add_file,delete_child" "$FL/acl" 2>/dev/null; then
  : > "$FL/argv.log"
  GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$FL/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$FLL" GIRD_CHECK_FLEET_STATE="$FL/state" \
    FLL_DIR="$FL" bash "$FL/acl/gird-fleet.sh" --all-users < /dev/null > /dev/null 2> "$FL/acl.err"; RC=$?
  chmod -N "$FL/acl"
  if [ "$RC" -eq 13 ] && [ ! -s "$FL/argv.log" ] && grep -q 'writable by no one else' "$FL/acl.err"; then ok "fleet: a folder whose ACL lets anyone write is refused"; else bad "fleet: a folder whose ACL lets anyone write is refused" "exit $RC"; fi
else skip "fleet: a folder whose ACL lets anyone write is refused" "chmod +a is not available here"; fi
}
SKIPPING=""
# Root tests a path anyone could make as a link before anything that would follow it.
if python3 - "$FLEETSH" > "$FL/linkorder.txt" <<'PY2'
import re, sys
src = open(sys.argv[1]).read()
bad = []
for m in re.finditer(r'\[ (!? ?)-[efdrO] "(\$[A-Za-z_][A-Za-z0-9_/.$"{}-]*?)" \] (&&|\|\|) \[ !? ?-L "\2" \]', src):
    bad.append(m.group(0))
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY2
then ok "fleet: gird-fleet.sh tests a path for a link before it stats it"; else bad "fleet: gird-fleet.sh tests a path for a link before it stats it" "$(head -n 3 "$FL/linkorder.txt")"; fi
# gird-check.sh, the script each person runs, carries no root work.
if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -qE '(^|[^A-Za-z0-9_.-])(sudo|dscl)([^A-Za-z0-9_-]|$)'; then bad "gird-check.sh runs no sudo or dscl" "$(grep -v '^[[:space:]]*#' "$SCRIPT" | grep -nE '(^|[^A-Za-z0-9_.-])(sudo|dscl)([^A-Za-z0-9_-]|$)' | head -n 3)"; else ok "gird-check.sh runs no sudo or dscl"; fi
bash "$SCRIPT" --all-users > "$FL/cs-all.out" 2> "$FL/cs-all.err"; RC=$?
if [ "$RC" -eq 2 ] && [ ! -s "$FL/cs-all.out" ] && grep -q 'run gird-fleet.sh as root' "$FL/cs-all.err"; then ok "gird-check.sh --all-users points to gird-fleet.sh"; else bad "gird-check.sh --all-users points to gird-fleet.sh" "exit $RC"; fi

echo "the text backstop to tests/parity.sh"
# Each case is a copy of a suite with lines added through a heredoc, which the backstop skips here.
pcase() { # run.sh-copy run-ps.sh-copy
  bash tests/parity-text.sh "$1" "$2" tests/bash-only.txt > "$WORK/pcase.txt" 2>&1
}
cp tests/run.sh "$WORK/pr1.sh"; cat >> "$WORK/pr1.sh" <<'EOF'
ok 'a single-quoted name'
EOF
if ! pcase "$WORK/pr1.sh" tests/run-ps.sh && grep -q 'ok with a name that is not a double-quoted literal' "$WORK/pcase.txt"; then ok "the text backstop fails on a single-quoted name"; else bad "the text backstop fails on a single-quoted name"; fi
cp tests/run.sh "$WORK/pr2.sh"; cat >> "$WORK/pr2.sh" <<'EOF'
myhas() { if grep -q "$2" "$3"; then ok "$1"; else bad "$1"; fi; }
myhas "a name in a new helper" x y
EOF
if ! pcase "$WORK/pr2.sh" tests/run-ps.sh && grep -q 'function myhas calls ok' "$WORK/pcase.txt"; then ok "the text backstop fails on a new helper that calls ok"; else bad "the text backstop fails on a new helper that calls ok"; fi
cp tests/run.sh "$WORK/pr3.sh"; cat >> "$WORK/pr3.sh" <<'EOF'
while read -r label; do ok "$label"; done < /dev/null
EOF
if ! pcase "$WORK/pr3.sh" tests/run-ps.sh && grep -q 'not a loop value: \$label' "$WORK/pcase.txt"; then ok "the text backstop fails on a variable name outside the helpers"; else bad "the text backstop fails on a variable name outside the helpers"; fi
cp tests/run.sh "$WORK/pr4.sh"; cat >> "$WORK/pr4.sh" <<'EOF'
for M in a b; do has "one loop $M" x y; done
for M in c d; do has "two loop $M" x y; done
EOF
cp tests/run-ps.sh "$WORK/pp4.sh"; cat >> "$WORK/pp4.sh" <<'EOF'
has "one loop a" x y; has "one loop b" x y; has "two loop c" x y; has "two loop d" x y
EOF
if pcase "$WORK/pr4.sh" "$WORK/pp4.sh"; then ok "the text backstop fills in each loop's own values"; else bad "the text backstop fills in each loop's own values"; sed 's/^/        /' "$WORK/pcase.txt" | head -n 4; fi
cp tests/run-ps.sh "$WORK/pp4b.sh"; cat >> "$WORK/pp4b.sh" <<'EOF'
has "one loop a" x y; has "one loop b" x y; has "two loop c" x y
EOF
if ! pcase "$WORK/pr4.sh" "$WORK/pp4b.sh" && grep -q 'no PowerShell twin: two loop d$' "$WORK/pcase.txt"; then ok "the text backstop fails on a twin missing from the second loop"; else bad "the text backstop fails on a twin missing from the second loop"; fi
cp tests/run.sh "$WORK/pr5.sh"; cat >> "$WORK/pr5.sh" <<'EOF'
if false; then bad "a test that only says when it fails"; fi
EOF
if ! pcase "$WORK/pr5.sh" tests/run-ps.sh && grep -q 'a test that only fails is not counted' "$WORK/pcase.txt"; then ok "the text backstop fails on a test that only fails"; else bad "the text backstop fails on a test that only fails"; fi
cp tests/run.sh "$WORK/pr6.sh"; cat >> "$WORK/pr6.sh" <<'EOF'
has "a new bash test with no twin" x y
EOF
if ! pcase "$WORK/pr6.sh" tests/run-ps.sh && grep -q 'no PowerShell twin: a new bash test with no twin$' "$WORK/pcase.txt"; then ok "the text backstop fails on a bash test with no twin"; else bad "the text backstop fails on a bash test with no twin"; fi
grep -v '"Windows: finds _netrc"' tests/run-ps.sh > "$WORK/pp7.sh"
if ! pcase tests/run.sh "$WORK/pp7.sh" && grep -q 'no PowerShell twin: Windows: finds _netrc$' "$WORK/pcase.txt"; then ok "the text backstop fails on a deleted twin"; else bad "the text backstop fails on a deleted twin"; fi

cp tests/run.sh "$WORK/pr8.sh"; printf '%s\n' 'echo "a quote left open' >> "$WORK/pr8.sh"
if ! pcase "$WORK/pr8.sh" tests/run-ps.sh && grep -q 'the file ends inside a quote' "$WORK/pcase.txt"; then ok "the text backstop fails on a file that ends inside a quote"; else bad "the text backstop fails on a file that ends inside a quote"; fi
if bash tests/parity-text.sh > "$WORK/parity.txt" 2>&1; then ok "the text backstop finds a twin for every test"
else bad "the text backstop finds a twin for every test" "$(grep -v '^    ' "$WORK/parity.txt")"; fi

echo "tests/parity.sh, on the names the suites record"
# The rule: tests/parity-run.sh runs both suites with PARITY_LOG set and compares the lists.
PR=$WORK/prt; mkdir -p "$PR"; : > "$PR/only.txt"; : > "$PR/psk.txt"
printf '%s\n' 'a test' 'bash 3: a per-bash test' 'perl: an engine test' > "$PR/b.txt"
printf '%s\n' 'a test' 'a per-bash test' 'net: an engine test' 'a PowerShell test' > "$PR/p.txt"
if bash tests/parity.sh "$PR/b.txt" "$PR/p.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1; then ok "parity.sh passes two lists that agree"; else bad "parity.sh passes two lists that agree" "$(cat "$PR/out.txt")"; fi
{ cat "$PR/b.txt"; echo 'a new bash test'; } > "$PR/b2.txt"
if ! bash tests/parity.sh "$PR/b2.txt" "$PR/p.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'no PowerShell twin: a new bash test$' "$PR/out.txt"; then ok "parity.sh fails on a bash test with no twin"; else bad "parity.sh fails on a bash test with no twin"; fi
grep -v '^a test$' "$PR/p.txt" > "$PR/p2.txt"
if ! bash tests/parity.sh "$PR/b.txt" "$PR/p2.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'no PowerShell twin: a test$' "$PR/out.txt"; then ok "parity.sh fails on a deleted twin"; else bad "parity.sh fails on a deleted twin"; fi
{ cat "$PR/b.txt"; echo 'a test'; } > "$PR/b3.txt"
if ! bash tests/parity.sh "$PR/b3.txt" "$PR/p.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'reported twice in the bash run: a test$' "$PR/out.txt"; then ok "parity.sh fails on a test reported twice"; else bad "parity.sh fails on a test reported twice"; fi
: > "$PR/empty.txt"
if ! bash tests/parity.sh "$PR/empty.txt" "$PR/p.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'list of test names is empty' "$PR/out.txt"; then ok "parity.sh fails on an empty list"; else bad "parity.sh fails on an empty list"; fi
if ! bash tests/parity.sh "$PR/b.txt" "$PR/none.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'no list of test names' "$PR/out.txt"; then ok "parity.sh fails on a missing list"; else bad "parity.sh fails on a missing list"; fi
printf 'a new bash test\n' > "$PR/only2.txt"
if ! bash tests/parity.sh "$PR/b2.txt" "$PR/p.txt" "$PR/only2.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'needs the name, a tab and the reason' "$PR/out.txt"; then ok "parity.sh fails on a bash-only line with no reason"; else bad "parity.sh fails on a bash-only line with no reason"; fi
# A skipped test records its name like any other, so it still needs a twin.
cat > "$PR/skipped.sh" <<'EOF'
. tests/lib.sh
SKIPPING="not on this machine"
has "a skipped test" 'x' /nonexistent
SKIPPING=""
skip "a test skipped by name" "not on this machine"
EOF
PARITY_LOG="$PR/sk.txt" bash "$PR/skipped.sh" > /dev/null 2>&1
printf '%s\n' 'a skipped test' > "$PR/p3.txt"
if [ "$(cat "$PR/sk.txt" 2>/dev/null)" = "$(printf 'S\ta skipped test\nS\ta test skipped by name')" ] && ! bash tests/parity.sh "$PR/sk.txt" "$PR/p3.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'no PowerShell twin: a test skipped by name$' "$PR/out.txt"
then ok "parity.sh counts a skipped test"; else bad "parity.sh counts a skipped test"; fi
# A PowerShell skip is a twin only where bash did not run the test either, or with a reason.
printf '%s\n' 'a test' 'a second test' > "$PR/b4.txt"
printf 'a test\nS\ta second test\n' > "$PR/p4.txt"
if ! bash tests/parity.sh "$PR/b4.txt" "$PR/p4.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1 && grep -q 'PowerShell skipped a test bash ran, and ps-skips.txt does not say why: a second test$' "$PR/out.txt"; then ok "parity.sh fails on a PowerShell skip with no reason"; else bad "parity.sh fails on a PowerShell skip with no reason"; fi
printf 'a second test\tit needs what this machine lacks\n' > "$PR/psk2.txt"
if bash tests/parity.sh "$PR/b4.txt" "$PR/p4.txt" "$PR/only.txt" "$PR/psk2.txt" > "$PR/out.txt" 2>&1; then ok "parity.sh passes a PowerShell skip that ps-skips.txt explains"; else bad "parity.sh passes a PowerShell skip that ps-skips.txt explains" "$(cat "$PR/out.txt")"; fi
printf 'a second test\tit needs what this machine lacks\nno such test\ta reason\n' > "$PR/psk3.txt"
if ! bash tests/parity.sh "$PR/b4.txt" "$PR/p4.txt" "$PR/only.txt" "$PR/psk3.txt" > "$PR/out.txt" 2>&1 && grep -q 'ps-skips.txt names a test run-ps.sh does not have: no such test$' "$PR/out.txt"; then ok "parity.sh fails on a stale ps-skips line"; else bad "parity.sh fails on a stale ps-skips line"; fi
printf 'S\ta second test\n' > "$PR/b5.txt"; printf 'a test\n' >> "$PR/b5.txt"
if bash tests/parity.sh "$PR/b5.txt" "$PR/p4.txt" "$PR/only.txt" "$PR/psk.txt" > "$PR/out.txt" 2>&1; then ok "parity.sh passes a test both suites skipped"; else bad "parity.sh passes a test both suites skipped" "$(cat "$PR/out.txt")"; fi
# A child that sources tests/lib.sh with the parent's PARITY_LOG exported can't wipe that list.
printf 'a parent test\n' > "$PR/parent.txt"
PARITY_LOG="$PR/parent.txt" bash -c '. tests/lib.sh; ok "a child test"' > /dev/null 2>&1; RC=$?
if [ "$RC" -ne 0 ] && [ "$(cat "$PR/parent.txt")" = "a parent test" ]; then ok "a child that sources tests/lib.sh keeps the parent's list"; else bad "a child that sources tests/lib.sh keeps the parent's list" "exit $RC, list: $(tr '\n' ';' < "$PR/parent.txt")"; fi
# A result reported where tests/lib.sh's counts can't see it fails the suite.
cat > "$PR/sub.sh" <<'EOF'
. tests/lib.sh
echo x | while read -r _; do ok "a test in a pipe"; done
finish
EOF
if ! PARITY_LOG="$PR/sub.txt" bash "$PR/sub.sh" > "$PR/out.txt" 2>&1 && grep -q 'reported outside tests/lib.sh' "$PR/out.txt"; then ok "a result reported in a subshell fails the suite"; else bad "a result reported in a subshell fails the suite"; fi


finish
