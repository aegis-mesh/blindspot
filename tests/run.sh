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
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
has()    { if grep -aqE -- "$2" "$3"; then ok "$1"; else bad "$1"; printf '        wanted: %s\n' "$2"; fi; }
hasnot() { if grep -aqE -- "$2" "$3"; then bad "$1"; printf '        found: %s\n' "$2"; else ok "$1"; fi; }
hasi()   { if grep -aqiE -- "$2" "$3"; then ok "$1"; else bad "$1"; printf '        wanted: %s\n' "$2"; fi; }

bash tests/make-fixture.sh "$WORK/home" "$WORK/keys.txt"
bash tests/make-fixture.sh "$WORK/clean" "$WORK/keys-clean.txt" clean

BASHES=/bin/bash
OTHER=$(command -v bash)
if [ -n "$OTHER" ] && [ "$("$OTHER" -c 'echo "$BASH_VERSION"')" != "$(/bin/bash -c 'echo "$BASH_VERSION"')" ]; then BASHES="$BASHES $OTHER"; fi

for B in $BASHES; do
  V=$("$B" -c 'echo "${BASH_VERSINFO[0]}"')
  echo "bash $V ($B)"
  if "$B" -n "$SCRIPT"; then ok "parses"; else bad "parses"; fi
  OUT=$WORK/out-$V.txt
  HOME="$WORK/home" "$B" "$SCRIPT" --offline > "$OUT" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "exits 0"; else bad "exits 0, got $RC"; fi
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
  hasnot "does not list a worktree's settings again" 'worktrees/w1' "$OUT"
  has    "a localhost name with a login prefix is not local" 'code/sneaky/\.claude/settings\.json' "$OUT"
  has    "finds any version of a fake AI tool package" 'claud-code 1\.0\.3 \(fake AI tool packages' "$OUT"
  has    "finds a bad package in npm's cache"    '@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI' "$OUT"
  has    "puts the wiper first"                  'ACT NOW: REMOVE GH-TOKEN-MONITOR BEFORE YOU REVOKE ANY TOKEN' "$OUT"
  has    "lists the wiper's files"               '~/\.config/gh-token-monitor' "$OUT"
  has    "a hook that runs a planted worm file counts as malware" '^ +~/code/cloned/\.claude/settings\.json$' "$OUT"
  has    "full output lists every key file"      '~/\.cursor/mcp\.json +GitHub' "$OUT"
  has    "the offline link has key counts, no run ID or rank" 'blindspot/card/#v=2&.*&u=&r=&sk=2&hk=1&ag=[a-z0-9.-]*$' "$OUT"
  if grep -aqF -f "$WORK/keys.txt" "$OUT"; then bad "never prints a planted key"; else ok "never prints a planted key"; fi
  if LC_ALL=C grep -aq "$(printf '\033')" "$OUT"; then bad "plain output has no escape codes"; else ok "plain output has no escape codes"; fi
done

echo "data files"
if bash tools/gen.sh --check > "$WORK/gen.txt" 2>&1; then ok "both scripts match data/keys.tsv and data/sessions.tsv"; else bad "both scripts match data/keys.tsv and data/sessions.tsv"; head -n 8 "$WORK/gen.txt"; fi

echo "keys in agent sessions"
SE=$WORK/sess; mkdir -p "$SE"
for E in perl rg; do
  if [ "$E" = rg ] && ! command -v rg >/dev/null 2>&1; then echo "  skip  ripgrep is not installed"; continue; fi
  HOME="$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=$E bash "$SCRIPT" --offline > "$SE/$E.txt" 2>&1
  sed -n '/Keys in agent sessions/,/^$/p' "$SE/$E.txt" > "$SE/$E.block"
  has    "$E: a key after an escaped newline in a Claude Code session" 'Claude Code +1 file: Hugging Face' "$SE/$E.txt"
  has    "$E: a key in a Codex session"            'Codex +1 file: OpenAI' "$SE/$E.txt"
  has    "$E: a key in an Aider history"           'Aider +1 file: Groq' "$SE/$E.txt"
  hasnot "$E: a made-up key is not counted"        'Anthropic' "$SE/$E.block"
  has    "$E: says to rotate them"                 'Treat these keys as exposed and rotate them' "$SE/$E.txt"
  has    "$E: names encrypted sessions as not checked" 'Windsurf sessions are stored encrypted, so they were not checked' "$SE/$E.txt"
  if grep -aqF -f "$WORK/keys.txt" "$SE/$E.txt"; then bad "$E: never prints a key"; else ok "$E: never prints a key"; fi
done
if [ -s "$SE/rg.block" ]; then
  if diff -q "$SE/perl.block" "$SE/rg.block" >/dev/null; then ok "perl and ripgrep report the same"; else bad "perl and ripgrep report the same"; diff "$SE/perl.block" "$SE/rg.block" | head -n 6; fi
fi
HOME="$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_STOP_AFTER=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$SE/part.txt"
has    "a partial check says how much it covered" 'Checked the newest 2 of 5 agent session files' "$SE/part.txt"
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl bash "$SCRIPT" --offline > "$SE/clean.txt" 2>&1
has    "a full check with nothing found says so" 'No keys in 2 agent session files\.' "$SE/clean.txt"
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_STOP_AFTER=0 bash "$SCRIPT" --offline > "$SE/clean-part.txt" 2>&1
hasnot "a partial check with nothing found never says no keys" 'No keys in .*agent session' "$SE/clean-part.txt"
has    "and says it was partial"                 'Checked the newest 0 of 2 agent session files' "$SE/clean-part.txt"
HOME="$WORK/home" GIRD_CHECK_SESSIONS_ENGINE=none bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$SE/none.txt"
has    "with no engine the sessions are named as not checked" 'agent session files were not checked: this needs perl or ripgrep' "$SE/none.txt"
# A held engine is still running when the rest of the check is done: it is stopped, and nothing is left behind.
mkfifo "$SE/hold"
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_HOLD="$SE/hold" bash "$SCRIPT" --offline > "$SE/held.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "a held engine does not hold up the check"; else bad "a held engine does not hold up the check, exit $RC"; fi
has    "and the report says the sessions were not all checked" 'Checked the newest 0 of 2' "$SE/held.txt"
if pgrep -f GIRD_CHECK_SESSIONS_HOLD >/dev/null 2>&1 || pgrep -f 'SESS_PRE' >/dev/null 2>&1; then bad "no engine process is left running"; else ok "no engine process is left running"; fi
# Closing the terminal (HUP) mid-check stops the engine too.
HOME="$WORK/clean" GIRD_CHECK_SESSIONS_ENGINE=perl GIRD_CHECK_SESSIONS_HOLD="$SE/hold" GIRD_CHECK_MIN_SECONDS=120 bash "$SCRIPT" --offline > /dev/null 2>&1 &
BP=$!
for _i in $(seq 1 100); do pgrep -f 'SESS_PRE' >/dev/null 2>&1 && break; sleep 0.1; done   # safety ceiling while it starts
kill -HUP "$BP" 2>/dev/null; wait "$BP" 2>/dev/null
if pgrep -f 'SESS_PRE' >/dev/null 2>&1; then bad "HUP leaves no engine process"; pkill -f 'SESS_PRE'; else ok "HUP leaves no engine process"; fi
if ls "${TMPDIR:-/tmp}"/blindspot.* >/dev/null 2>&1 && ls -l "${TMPDIR:-/tmp}"/blindspot.*.fifo >/dev/null 2>&1; then bad "no fifo is left behind"; else ok "no fifo is left behind"; fi

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
K_ANT=$(sed -n 1p "$WORK/keys.txt"); K_GH=$(sed -n 3p "$WORK/keys.txt"); K_AWS=$(sed -n 4p "$WORK/keys.txt"); K_GROQ=$(sed -n 5p "$WORK/keys.txt")
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

echo "Zeabur and the LiteLLM leftovers"
# A minimal PATH hides any opencode, railway or zeabur command on this machine, so
# only the files in the fake home decide.
lp() { HOME="$1" PATH=/usr/bin:/bin GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  '; }
lpf() { HOME="$1" PATH=/usr/bin:/bin bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  '; }
cp -R "$WORK/clean" "$WORK/zb-none"; rm -rf "$WORK/zb-none/.config/opencode" "$WORK/zb-none/.local/share/opencode" "$WORK/zb-none/.railway"
lp "$WORK/zb-none" > "$WORK/zb-none.txt"
has    "no leaks found: row 05 names all five" 'no LiteLLM, npm, OpenCode, Railway, Zeabur leaks' "$WORK/zb-none.txt"
cp -R "$WORK/zb-none" "$WORK/zb-one"; mkdir -p "$WORK/zb-one/.config/zeabur"
lp "$WORK/zb-one" > "$WORK/zb-one.txt"
lpf "$WORK/zb-one" > "$WORK/zb-one-full.txt"
has    "Zeabur alone is flagged"               'Zeabur CLI found: rotate secrets stored there' "$WORK/zb-one.txt"
has    "Zeabur adds a fix"                     'deploy on Railway or Zeabur, rotate the keys stored there' "$WORK/zb-one-full.txt"
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
has    "nothing found: it says this is not a guarantee"    'not a .*guarantee' "$WORK/ni-empty.txt"
hasnot "nothing found: no old clean-today wording"         'CLEAN TODAY|needs fixing|Nothing to fix' "$WORK/ni-empty.txt"
rm -rf "$WORK/ni-pyc"; mkdir -p "$WORK/ni-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__"; : > "$WORK/ni-pyc/code/py/.venv/lib/python3.12/site-packages/__pycache__/cook.cpython-312.pyc"
HOME="$WORK/ni-pyc" PATH=/usr/bin:/bin bash "$WORK/no-idle.sh" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/ni-pyc.txt"
has    "a pyc-only run counts its things to fix"           'It found [0-9]+ things?.*to fix' "$WORK/ni-pyc.txt"
has    "a pyc-only run still says the scan is a snapshot"  'THIS SCAN IS A SNAPSHOT' "$WORK/ni-pyc.txt"
hasnot "a pyc-only run is not told there are no findings"  'NO FINDINGS IN THIS SCAN' "$WORK/ni-pyc.txt"
has    "cook.pth next to the pyc is an act-now hit" 'signs of the LiteLLM malware\. Act now' "$WORK/zb-pyc-strong.txt"

echo "MCP configs in plugin folders"
cp -R "$WORK/clean" "$WORK/mcp-pl"
mkdir -p "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a" "$WORK/mcp-pl/.claude/plugins/synced/b"
printf '{"mcpServers":{"one":{"command":"x"},"two":{"command":"y"}}}\n' > "$WORK/mcp-pl/.codex/.tmp/plugins/plugins/a/.mcp.json"
printf '{"mcpServers":{"three":{"command":"z"}}}\n' > "$WORK/mcp-pl/.claude/plugins/synced/b/.mcp.json"
HOME="$WORK/clean" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-base.txt"
HOME="$WORK/mcp-pl" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-pl.txt"
HOME="$WORK/mcp-pl" bash "$SCRIPT" --offline 2>&1 | tr -s ' \n' '  ' > "$WORK/mcp-pl-full.txt"
BASE=$(grep -aoE '02 . MCP servers +[0-9]+ servers' "$WORK/mcp-base.txt" | grep -aoE '[0-9]+ servers')
if [ -n "$BASE" ]; then ok "the baseline has a server count ($BASE)"; else bad "the baseline has a server count"; fi
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
if [ -n "$LAST" ] && [ "$LAST" = "$ISS" ]; then ok "the numbered list matches the fix count ($ISS)"; else bad "the numbered list matches the fix count"; printf '        list ends at %s, header says %s\n' "$LAST" "$ISS"; fi

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
printf 'AWS_ACCESS_KEY_ID=AK%s\n' "IA$(LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c 16)" > "$EVIL/.env"
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
if [ -n "$SAVED" ] && ! grep -aqF -f "$WORK/keys.txt" "$SAVED"; then ok "the report holds no planted key"; else bad "the report holds no planted key"; fi

echo "shared counts and how you compare"
if command -v python3 >/dev/null 2>&1; then
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
  hasi "shows how this machine compares"       'better than 72% of 1,234 AI builders who ran Blindspot' "$OUT"
  has  "the result link carries the percentile" 'blindspot/card/#v=2&.*&pc=72&pn=1234' "$OUT"
  RID=$(grep -oE '"run_id":"[0-9a-f]{16}"' "$WORK/received.log" | head -n 1 | cut -d'"' -f4)
  has  "the link carries the report's run ID, the rank and key counts" "blindspot/card/#v=2&.*&u=${RID:-no-run-id}&r=142&sk=2&hk=1&ag=[a-z0-9.-]*\$" "$OUT"
  head -n 1 "$WORK/received.log" > "$WORK/report-home.json"   # its case-study counts are checked below
  HOME="$WORK/clean" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/clean-online.txt" 2>&1
  has  "leads with the percentile when nothing is urgent" 'BETTER THAN 72% OF 1,234 AI BUILDERS WHO RAN BLINDSPOT' "$WORK/clean-online.txt"
  PROUD="^  ★ You're one of the first 1,000 AI builders to run Blindspot\."
  printf '%s' '{"devices":1234567,"devices_7d":10,"key_files":20,"clean":0}' > "$WORK/stats.json"
  for B in $BASHES; do
    V=$("$B" -c 'echo "${BASH_VERSINFO[0]}"')
    HOME="$WORK/home" GIRD_CHECK_API="$API" "$B" "$SCRIPT" > "$WORK/online-$V.txt" 2>&1
    has  "bash $V: the total gets thousands separators" '★ 1,234,567 AI builders have run Blindspot\.' "$WORK/online-$V.txt"
    hasi "bash $V: shows how this machine compares"     'better than 72% of 1,234 AI builders who ran Blindspot' "$WORK/online-$V.txt"
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
  # Checks one report against the fixed lists in the script and what the
  # fixture holds. Prints ok|label or bad|label|detail per check.
  cat > "$WORK/payload.py" <<'PY'
import json, re, sys
script, mode, files = sys.argv[1], sys.argv[2], sys.argv[3:]
src = open(script, encoding='utf-8', errors='replace').read()
def fixed(name):
    m = re.search('^' + name + '="([^"]*)"', src, re.M)
    return m.group(1).split() if m else []
CLIENTS, KNOWN, PLACES, PROVIDERS = [fixed(n) for n in ('MCP_CLIENT_IDS', 'MCP_KNOWN_IDS', 'KEY_PLACE_IDS', 'PROVIDER_IDS')]
FIELDS = ['agents_idle_ids', 'mcp_clients', 'mcp_token_clients', 'mcp_known', 'mcp_other', 'key_places', 'provider_files']
def load(path):
    try:
        with open(path) as f:
            r = json.loads(f.readline())
        return r if isinstance(r, dict) else {}
    except (OSError, ValueError):
        return {}
def check(label, cond, detail=''):
    print('%s|%s|%s' % ('ok' if cond else 'bad', label, '' if cond else detail))
def count(v): return type(v) is int and 0 <= v <= 100000
def id_list(v, allowed): return isinstance(v, list) and all(isinstance(x, str) and x in allowed for x in v) and len(set(v)) == len(v)
def counts(v, allowed): return isinstance(v, dict) and all(k in allowed and count(n) for k, n in v.items())
def obj(r, k):
    v = r.get(k)
    return v if isinstance(v, dict) else {}
def show(r, *keys): return json.dumps({k: r.get(k) for k in keys})
def common(r, tag):
    shaped = (id_list(r.get('agents_idle_ids'), r.get('agents') or []) and len(r['agents_idle_ids']) == r.get('agents_idle')
              and counts(r.get('mcp_clients'), CLIENTS) and id_list(r.get('mcp_token_clients'), CLIENTS)
              and id_list(r.get('mcp_known'), KNOWN) and count(r.get('mcp_other'))
              and counts(r.get('key_places'), PLACES) and counts(r.get('provider_files'), PROVIDERS))
    check(tag + 'every case-study field holds fixed-list ids and whole numbers', shaped, show(r, *FIELDS))
    check(tag + 'mcp_clients adds up to mcp_servers', sum(obj(r, 'mcp_clients').values()) == r.get('mcp_servers'), show(r, 'mcp_clients', 'mcp_servers'))
    check(tag + 'key_places adds up to key_files', sum(obj(r, 'key_places').values()) == r.get('key_files'), show(r, 'key_places', 'key_files'))
    check(tag + 'key_places counts the history files history_keys counts', obj(r, 'key_places').get('shell_history', 0) == r.get('history_keys'), show(r, 'key_places', 'history_keys'))
    check(tag + 'provider_files has the providers in key_providers', sorted(obj(r, 'provider_files')) == sorted(r.get('key_providers') or []), show(r, 'provider_files', 'key_providers'))
r = load(files[0])
if mode == 'home':
    check('the fixed lists are in the script', [len(CLIENTS), len(PLACES), len(PROVIDERS)] == [12, 7, 12] and len(KNOWN) >= 49,
          'clients %d, known %d, places %d, providers %d' % tuple(map(len, (CLIENTS, KNOWN, PLACES, PROVIDERS))))
    check('the report has every case-study field', all(k in r for k in FIELDS), 'missing: ' + ' '.join(k for k in FIELDS if k not in r))
    common(r, '')
    check('mcp_clients counts the servers in each app', r.get('mcp_clients') == {'claude-code': 6, 'cursor': 1, 'codex': 2, 'vscode': 2, 'cline': 3}, show(r, 'mcp_clients'))
    check('mcp_token_clients names the app with a token in its config', r.get('mcp_token_clients') == ['cursor'], show(r, 'mcp_token_clients'))
    check('mcp_known lists each well-known server once', sorted(r.get('mcp_known') or []) == sorted(['github', 'filesystem', 'postgres', 'playwright', 'linear', 'figma', 'context7', 'docker']), show(r, 'mcp_known'))
    check('mcp_other counts the servers with names of their own', r.get('mcp_other') == 3, show(r, 'mcp_other'))
    # 11 fixture servers have well-known labels: github 3 times (once as gh), fs twice,
    # and linear, postgres, docker, playwright, context7 and figma once each.
    check('well-known and other servers add up to mcp_servers', 11 + (r.get('mcp_other') or 0) == r.get('mcp_servers'), show(r, 'mcp_other', 'mcp_servers'))
    check('key_places puts each key file in its place', r.get('key_places') == {'shell_rc': 1, 'shell_history': 1, 'env_file': 1, 'mcp_config': 1}, show(r, 'key_places'))
    check("provider_files counts the files with each provider's keys", r.get('provider_files') == {'anthropic': 1, 'openai': 1, 'groq': 1, 'aws': 1, 'github': 2}, show(r, 'provider_files'))
    idle = set(r.get('agents_idle_ids') or [])
    check('agents_idle_ids holds the idle agents, not the active ones', {'codex', 'gemini-cli', 'cursor', 'cline', 'goose'} <= idle and not idle & {'claude-code', 'opencode'}, show(r, 'agents_idle_ids'))
elif mode == 'places':
    common(r, 'more key files: ')
    check('more key files: key_places counts each kind of file', r.get('key_places') == {'shell_rc': 2, 'shell_history': 2, 'env_file': 2, 'mcp_config': 1, 'agent_config': 1}, show(r, 'key_places'))
    check('more key files: provider_files counts each file once per provider', r.get('provider_files') == {'anthropic': 3, 'openai': 2, 'groq': 2, 'aws': 1, 'github': 2}, show(r, 'provider_files'))
elif mode == 'empty':
    common(r, 'an empty home: ')
    check('an empty home: empty lists and objects, and no other servers', [r.get(k) for k in FIELDS[1:]] == [{}, [], [], 0, {}, {}] and isinstance(r.get('agents_idle_ids'), list), show(r, *FIELDS))
elif mode == 'nojq':
    b = load(files[1])
    keys = ['mcp_servers', 'mcp_configs', 'mcp_token_files', 'mcp_clients', 'mcp_token_clients', 'mcp_other', 'key_places', 'provider_files']
    diff = [k for k in keys if r.get(k) != b.get(k)]
    if sorted(r.get('mcp_known') or []) != sorted(b.get('mcp_known') or []): diff.append('mcp_known')
    check("without jq, macOS's JavaScript finds the same MCP servers as jq", bool(b) and not diff, 'differs: ' + ' '.join(diff) + ' ' + show(b, *diff))
PY
  payload_checks() { # mode report [report]
    python3 "$WORK/payload.py" "$SCRIPT" "$@" > "$WORK/checks.txt" 2>&1
    while IFS='|' read -r st label detail; do
      case "$st" in
        ok)  ok "$label" ;;
        bad) bad "$label"; [ -n "$detail" ] && printf '        %s\n' "$detail" ;;
        *)   bad "the case-study checks ran: $st$label" ;;
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
  if [ "$(uname -s)" = Darwin ] && [ -x /usr/bin/osascript ]; then
    # Without jq on PATH, the script reads JSON configs with macOS's JavaScript.
    mkdir -p "$WORK/nojq"; ln -s /usr/bin/* /bin/* /usr/sbin/* /sbin/* "$WORK/nojq/" 2>/dev/null; rm -f "$WORK/nojq/jq"
    report_of "$WORK/report-nojq.json" env PATH="$WORK/nojq" HOME="$WORK/home" GIRD_CHECK_API="$API" /bin/bash "$SCRIPT"
    payload_checks nojq "$WORK/report-home.json" "$WORK/report-nojq.json"
  fi
  hasnot "no report holds a name you gave an MCP server" 'acme|my notes|web.search' "$WORK/received.log"
  hasnot "no report holds a server label as written"     '@modelcontextprotocol|MCP_DOCKER|Figma Dev Mode|upstash|Playwright|"gh"|"fs"' "$WORK/received.log"
  hasnot "no report holds a file name" '\.zshrc|zsh_history|python_history|bash_profile|\.env|\.mcp|mcp\.json|config\.(toml|yaml)|cline_mcp|claude_desktop|settings(\.local)?\.json|\.aider' "$WORK/received.log"
  hasnot "no report holds a path"                        '/(Users|home|private|tmp|var)/|~/' "$WORK/received.log"
  if grep -aqF -f "$WORK/keys-places.txt" "$WORK/received.log"; then bad "no report holds the extra planted keys"; else ok "no report holds the extra planted keys"; fi
  # After the checks above: the Windows run has a GitHub CLI login, so its report says "gh".
  GIRD_CHECK_API="$API" report_of "$WORK/report-win.json" winrun
  GIRD_CHECK_API="$API" FAKE_BUILD= FAKE_UNAME=MINGW64_NT-10.0-19045 report_of "$WORK/report-win10.json" winrun
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
else
  echo "  skip  python3 not installed"
fi

echo "help"
if bash "$SCRIPT" --help | grep -q -- '--offline'; then ok "--help lists the options"; else bad "--help lists the options"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
