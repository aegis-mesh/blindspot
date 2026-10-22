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
  has    "full output lists every key file"      '~/\.cursor/mcp\.json +GitHub' "$OUT"
  has    "the offline link has key counts, no run ID or rank" 'blindspot/card/#v=2&.*&u=&r=&sk=2&hk=1&ag=[a-z0-9.-]*$' "$OUT"
  if grep -aqF -f "$WORK/keys.txt" "$OUT"; then bad "never prints a planted key"; else ok "never prints a planted key"; fi
  if LC_ALL=C grep -aq "$(printf '\033')" "$OUT"; then bad "plain output has no escape codes"; else ok "plain output has no escape codes"; fi
done

echo "summary"
OUT=$WORK/compact.txt
HOME="$WORK/home" GIRD_CHECK_COMPACT=1 bash "$SCRIPT" --offline > "$OUT" 2>&1
for label in 'Coding agents' 'MCP servers' 'Keys in plain text' 'Allow lists' "This week's leaks"; do
  has "one summary line for $label" "^   0[1-5] .*$label" "$OUT"
done
has    "the keys line names the first file"    'Keys in plain text +4 files, like ~/\.zshrc \(Anthropic, OpenAI\)' "$OUT"
has    "the summary leads with the first fix"  'First fix: Treat this machine as compromised' "$OUT"
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
  has  "shows one real total under the banner" '★ (1,234 developers have run Blindspot|456 developers ran it this week|Blindspot has found 3,412 files with AI keys in plain text so far|31% of developers had no keys in plain text)' "$OUT"
  hasi "shows how this machine compares"       'safer than 72% of 1,234 developers who ran Blindspot' "$OUT"
  has  "the certificate link carries the percentile" 'blindspot/card/#v=2&.*&pc=72&pn=1234' "$OUT"
  RID=$(grep -oE '"run_id":"[0-9a-f]{16}"' "$WORK/received.log" | head -n 1 | cut -d'"' -f4)
  has  "the link carries the report's run ID, the rank and key counts" "blindspot/card/#v=2&.*&u=${RID:-no-run-id}&r=142&sk=2&hk=1&ag=[a-z0-9.-]*\$" "$OUT"
  HOME="$WORK/clean" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/clean-online.txt" 2>&1
  has  "leads with the percentile when nothing is urgent" 'SAFER THAN 72% OF 1,234 DEVELOPERS WHO RAN BLINDSPOT' "$WORK/clean-online.txt"
  PROUD="▌ ★ You're developer #142 to run Blindspot\. One of the first 1,000\."
  printf '%s' '{"devices":1234567,"devices_7d":10,"key_files":20,"clean":0}' > "$WORK/stats.json"
  for B in $BASHES; do
    V=$("$B" -c 'echo "${BASH_VERSINFO[0]}"')
    HOME="$WORK/home" GIRD_CHECK_API="$API" "$B" "$SCRIPT" > "$WORK/online-$V.txt" 2>&1
    has  "bash $V: the total gets thousands separators" '★ 1,234,567 developers have run Blindspot\.' "$WORK/online-$V.txt"
    hasi "bash $V: shows how this machine compares"     'safer than 72% of 1,234 developers who ran Blindspot' "$WORK/online-$V.txt"
    has  "bash $V: the full report shows the rank"      "$PROUD" "$WORK/online-$V.txt"
    HOME="$WORK/home" GIRD_CHECK_API="$API" GIRD_CHECK_COMPACT=1 "$B" "$SCRIPT" > "$WORK/compact-online-$V.txt" 2>&1
    has  "bash $V: the summary shows the rank"          "$PROUD" "$WORK/compact-online-$V.txt"
  done
  printf '%s' '{"p":72,"n":1234}' > "$WORK/reply.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/no-rank.txt" 2>&1
  hasnot "a reply without r shows no rank"       "developer #" "$WORK/no-rank.txt"
  has    "a reply without r leaves r empty in the link" '&pn=1234&u=[0-9a-f]{16}&r=&sk=2' "$WORK/no-rank.txt"
  SHOWN=""
  for R in null 0 1001 '"142"' 14.2; do
    printf '{"p":72,"n":1234,"r":%s}' "$R" > "$WORK/reply.json"
    HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/bad-rank.txt" 2>&1
    if grep -aqE 'developer #|&r=[^&]' "$WORK/bad-rank.txt"; then SHOWN="$SHOWN $R"; fi
  done
  if [ -z "$SHOWN" ]; then ok "a rank that isn't a whole number from 1 to 1000 shows nothing"; else bad "a rank that isn't a whole number from 1 to 1000 shows nothing"; printf '        shown for:%s\n' "$SHOWN"; fi
  printf '%s' '{"p":72,"n":1234,"r":1000}' > "$WORK/reply.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/rank-1000.txt" 2>&1
  has    "rank 1000 is still shown, with a separator" "★ You're developer #1,000 to run Blindspot\." "$WORK/rank-1000.txt"
  printf '%s' '{"p":72,"n":1234,"r":142}' > "$WORK/reply.json"
  printf '%s' '{"devices":999,"devices_7d":120,"key_files":300,"clean":0.4}' > "$WORK/stats.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/early.txt" 2>&1
  has    "says early adopter instead of a total under 1,000" "★ You're one of the first 1,000 developers to run Blindspot\." "$WORK/early.txt"
  hasnot "never shows a total under 1,000"       '★ (999 developers|120 developers|Blindspot has found|40% of developers)' "$WORK/early.txt"
  printf '%s' '{"devices":1000,"devices_7d":10,"key_files":20,"clean":0}' > "$WORK/stats.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/at-1000.txt" 2>&1
  has    "shows the total from 1,000 developers"  '★ 1,000 developers have run Blindspot\.' "$WORK/at-1000.txt"
  printf '{"devices":"\033[2J\033]0;pwned\007","key_files":99999999999999999999}' > "$WORK/stats.json"
  HOME="$WORK/home" GIRD_CHECK_API="$API" bash "$SCRIPT" > "$WORK/hostile.txt" 2>&1
  if LC_ALL=C grep -aq "$(printf '\033')\|$(printf '\007')" "$WORK/hostile.txt"; then bad "a hostile totals reply can't reach the terminal"; else ok "a hostile totals reply can't reach the terminal"; fi
  hasnot "a bad totals reply shows no total"     '^  ★' "$WORK/hostile.txt"
else
  echo "  skip  python3 not installed"
fi

echo "help"
if bash "$SCRIPT" --help | grep -q -- '--offline'; then ok "--help lists the options"; else bad "--help lists the options"; fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
