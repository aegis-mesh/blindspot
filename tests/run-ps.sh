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
hasnot "does not list a worktree's settings again" 'worktrees/w1' "$OUT"
has    "a localhost name with a login prefix is not local" 'code/sneaky/\.claude/settings\.json' "$OUT"
has    "finds any version of a fake AI tool package" 'claud-code 1\.0\.3 \(fake AI tool packages' "$OUT"
has    "finds a bad package in npm's cache"    '@bitwarden/cli 2026\.4\.0 \(Bitwarden CLI' "$OUT"
has    "puts the wiper first"                  'ACT NOW: REMOVE GH-TOKEN-MONITOR BEFORE YOU REVOKE ANY TOKEN' "$OUT"
has    "lists the wiper's files"               '~/\.config/gh-token-monitor' "$OUT"
has    "a hook that runs a planted worm file counts as malware" '^ +~/code/cloned/\.claude/settings\.json$' "$OUT"
tr -s ' \n' '  ' < "$OUT" > "$WORK/out-flat.txt"   # the advice wraps, so it is matched on one line
has    "points other systems at a secrets manager" 'files into a secrets manager, then rotate' "$WORK/out-flat.txt"
has    "uses the non-Mac Argus line"           'Argus, our free Mac app, shows what AI coding agents' "$OUT"
hasnot "never offers the Argus download off a Mac" 'argus/download' "$OUT"
hasnot "never shows a letter grade"            'GRADE [ABCDF]|[Gg]rade [ABCDF]\b' "$OUT"
has    "the offline link has key counts, no run ID or rank" 'blindspot/card/#v=2&.*&u=&r=&sk=2&hk=2&ag=[a-z0-9.-]*$' "$OUT"
nokeys "never prints a planted key" "$WORK/keys.txt" "$OUT"
if LC_ALL=C grep -aq "$(printf '\033')" "$OUT"; then bad "redirected output has no escape codes"; else ok "redirected output has no escape codes"; fi

echo "the same findings as gird-check.sh"
bl() { sed -n "/$2/,/$3/p" "$1" | grep -E '^[@a-z0-9].* (\*|[0-9][^ ]*) [a-z]+$'; }
sed -n '/^BAD_NPM="/,/"$/p' "$BASH_SCRIPT" | sed -e 's/^BAD_NPM="//' -e 's/"$//' > "$WORK/bad-sh.txt"
bl "$SCRIPT" "^\\\$BadNpm = @'" "^'@" > "$WORK/bad-ps.txt"
if [ -s "$WORK/bad-sh.txt" ] && diff -q "$WORK/bad-sh.txt" "$WORK/bad-ps.txt" >/dev/null; then ok "the same bad npm package list ($(wc -l < "$WORK/bad-ps.txt" | tr -d ' ') entries)"
else bad "the same bad npm package list"; diff "$WORK/bad-sh.txt" "$WORK/bad-ps.txt" | head -n 6; fi
# gird-check.sh, on the same home with its Mac paths, must find the same files.
bash tests/make-fixture.sh "$WORK/bhome" "$WORK/keys-b.txt" >/dev/null
HOME="$WORK/bhome" PATH=/usr/bin:/bin bash "$BASH_SCRIPT" --offline > "$WORK/bash.txt" 2>&1
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
has    "no malware in a clean home"            'no LiteLLM, npm, OpenCode, Railway, Zeabur leaks' "$WORK/ph.txt"

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
has    "the link carries the percentile, run ID, rank and key counts" "blindspot/card/#v=2&s=[0-9]+&g=[ABCDF]&.*&pc=72&pn=1234&u=${RID:-no-run-id}&r=142&sk=2&hk=2&ag=[a-z0-9.-]*\$" "$OUT"
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
