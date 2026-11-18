#!/usr/bin/env bash
# Tests gird-intune.ps1 against a local stand-in for Microsoft Graph: a stub
# Microsoft.Graph.Authentication module whose Invoke-MgGraphRequest sends each call to a mock
# server on 127.0.0.1, never to a real tenant. tests/run-ps.sh sources this; on its own:
#
#   PWSH=/path/to/pwsh bash tests/intune.sh
#
# shellcheck disable=SC2016  # the PowerShell and Python below are single-quoted on purpose
INTUNE_ALONE=0
if [ -z "${PASS+x}" ]; then
  INTUNE_ALONE=1
  set -u
  cd "$(dirname "$0")/.." || exit 1
  PWSH=${PWSH:-$(command -v pwsh)}
  if [ -z "$PWSH" ] || [ ! -x "$PWSH" ]; then echo "pwsh not found: set PWSH"; exit 1; fi
  . tests/lib.sh
fi
IW=$(mktemp -d 2>/dev/null || mktemp -d -t blindspot-intune)
TOOL=$PWD/gird-intune.ps1
INTUNE_PID=""
intune_cleanup() { [ -n "$INTUNE_PID" ] && { kill "$INTUNE_PID"; wait "$INTUNE_PID"; } 2>/dev/null; rm -rf "$IW"; INTUNE_PID=""; }
[ "$INTUNE_ALONE" -eq 1 ] && trap intune_cleanup EXIT

echo "gird-intune.ps1"
if LC_ALL=C grep -q '[^ -~]' "$TOOL"; then bad "intune: the tool is plain ASCII"; else ok "intune: the tool is plain ASCII"; fi
sed -e 's/#.*$//' -e "s/'[^']*'//g" -e 's/"[^"]*"//g' "$TOOL" > "$IW/code.txt"
hasnot "intune: no PowerShell 7 only syntax" '\?\?|\?\.|&&|\|\||-Parallel|-AsHashtable|\$Is(Windows|MacOS|Linux)\b|-SkipHttpErrorCheck' "$IW/code.txt"
hasnot "intune: talks to nothing but Microsoft Graph" 'Invoke-WebRequest|Invoke-RestMethod|WebClient|HttpClient|WebRequest\]|Start-Process|Net\.Sockets' "$IW/code.txt"
if "$PWSH" -NoProfile -NonInteractive -Command "\$e = \$null; [void][Management.Automation.Language.Parser]::ParseFile('$TOOL', [ref]\$null, [ref]\$e); if (\$e.Count) { \$e | ForEach-Object { \$_.Message }; exit 1 }" > "$IW/parse.txt" 2>&1
then ok "intune: parses"; else bad "intune: parses" "$(head -n 3 "$IW/parse.txt")"; fi

mkdir -p "$IW/mods/Microsoft.Graph.Authentication" "$IW/nomods" "$IW/home" "$IW/out"
cat > "$IW/mods/Microsoft.Graph.Authentication/Microsoft.Graph.Authentication.psm1" <<'PS'
function Connect-MgGraph {
  param([string[]]$Scopes, [switch]$NoWelcome)
  Add-Content -WhatIf:$false -LiteralPath $env:STUB_LOG -Value ('connect ' + ($Scopes -join ','))
}
function Invoke-MgGraphRequest {
  param([string]$Method = 'GET', [string]$Uri, $Body, [string]$ContentType, $OutputType)
  if (-not $Uri.StartsWith('https://graph.microsoft.com/')) {
    Add-Content -WhatIf:$false -LiteralPath $env:STUB_LOG -Value ('refused ' + $Uri)
    throw "stub: not Microsoft Graph: $Uri"
  }
  $u = $env:STUB_GRAPH + $Uri.Substring('https://graph.microsoft.com'.Length)
  $p = @{ Method = $Method; Uri = $u; UseBasicParsing = $true }
  if ($null -ne $Body) { $p.Body = [Text.Encoding]::UTF8.GetBytes([string]$Body); $p.ContentType = 'application/json' }
  $r = Invoke-WebRequest @p
  if (-not $r.Content) { return $null }
  $t = $r.Content; if ($t -is [byte[]]) { $t = [Text.Encoding]::UTF8.GetString($t) }
  if (-not $t) { return $null }
  ConvertFrom-Json -InputObject $t -AsHashtable
}
PS

python3 - "$IW/state.json" "$IW/requests.log" "$IW/port" <<'PY' &
import http.server, json, sys, uuid, urllib.parse
state_f, log_f, port_f = sys.argv[1:4]
BASE = '/beta/deviceManagement/deviceHealthScripts'
def load():
    with open(state_f) as f: return json.load(f)
def save(s):
    with open(state_f, 'w') as f: json.dump(s, f)
class H(http.server.BaseHTTPRequestHandler):
    def send(self, code, obj=None):
        body = json.dumps(obj).encode() if obj is not None else b''
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if body: self.wfile.write(body)
    def note(self, body):
        with open(log_f, 'a') as f:
            f.write(json.dumps({'method': self.command, 'path': self.path, 'body': body}) + '\n')
    def page(self, s, items, url):
        q = urllib.parse.parse_qs(url.query, keep_blank_values=True)
        at = int(q.pop('$skiptoken', ['0'])[0]); n = s.get('pageSize', 100)
        out = {'value': items[at:at + n]}
        if at + n < len(items):
            q['$skiptoken'] = [str(at + n)]
            host = s.get('nextHost', 'https://graph.microsoft.com')
            out['@odata.nextLink'] = host + url.path + '?' + urllib.parse.urlencode(q, doseq=True)
        return out
    def handle_any(self):
        n = int(self.headers.get('content-length') or 0)
        raw = self.rfile.read(n) if n else b''
        body = json.loads(raw) if raw else None
        self.note(body)
        s = load(); url = urllib.parse.urlparse(self.path); p = url.path; m = self.command
        if m == 'GET' and p.startswith('/v1.0/groups/') and p.endswith('/transitiveMembers'):
            gid = p[len('/v1.0/groups/'):-len('/transitiveMembers')]
            if gid in s.get('memberErrors', []): return self.send(403, {'error': 'forbidden'})
            return self.send(200, self.page(s, s.get('members', {}).get(gid, []), url))
        if m == 'GET' and p == '/v1.0/deviceManagement/managedDevices':
            return self.send(200, self.page(s, s.get('managed', []), url))
        if m == 'GET' and p == '/v1.0/groups':
            f = urllib.parse.parse_qs(url.query).get('$filter', [''])[0]
            pre = "displayName eq '"
            if not (f.startswith(pre) and f.endswith("'")): return self.send(400, {'error': 'filter'})
            want = f[len(pre):-1].replace("''", "'").lower()
            return self.send(200, self.page(s, [g for g in s['groups'] if g['displayName'].lower() == want], url))
        if p == BASE:
            if m == 'GET': return self.send(200, self.page(s, s['scripts'], url))
            if m == 'POST':
                body = dict(body); body['id'] = str(uuid.uuid4()); body['createdDateTime'] = '2026-11-01T10:00:00Z'
                s['scripts'].append(body); save(s); return self.send(201, body)
        if p.startswith(BASE + '/'):
            parts = p[len(BASE) + 1:].split('/'); sid = parts[0]
            hit = [x for x in s['scripts'] if x['id'] == sid]
            if not hit: return self.send(404, {'error': 'not found'})
            sc = hit[0]
            if len(parts) == 1:
                if m == 'GET': return self.send(200, sc)
                if m == 'PATCH': sc.update(body); save(s); return self.send(200, sc)
                if m == 'DELETE': s['scripts'] = [x for x in s['scripts'] if x['id'] != sid]; save(s); return self.send(204)
            if parts[1:] == ['assign'] and m == 'POST':
                sc['assignments'] = body['deviceHealthScriptAssignments']; save(s); return self.send(204)
            if parts[1:] == ['assignments'] and m == 'GET':
                return self.send(200, self.page(s, sc.get('assignments', []), url))
            if parts[1:] == ['deviceRunStates'] and m == 'GET':
                return self.send(200, self.page(s, s.get('runStates', {}).get(sid, []), url))
        self.send(404, {'error': 'no such endpoint'})
    do_GET = do_POST = do_PATCH = do_DELETE = handle_any
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
with open(port_f, 'w') as f: f.write(str(srv.server_address[1]))
srv.serve_forever()
PY
INTUNE_PID=$!
i=0; while [ ! -s "$IW/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
PORT=$(cat "$IW/port" 2>/dev/null)

intune_run() { # [env...] -- args...
  _e=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do _e+=("$1"); shift; done; shift
  env -i PATH=/usr/bin:/bin HOME="$IW/home" PSModulePath="$IW/mods" STUB_GRAPH="http://127.0.0.1:$PORT" STUB_LOG="$IW/stub.log" \
    ${_e[@]+"${_e[@]}"} "$PWSH" -NoProfile -NonInteractive -File "$TOOL" "$@"
}
# state NAME: writes a fresh mock tenant and empties the request logs
intune_state() { python3 tests/intune.py state "$1" "$IW/state.json"; : > "$IW/requests.log"; : > "$IW/stub.log"; }
intune_writes() { grep -cE '"method": "(POST|PATCH|DELETE)"' "$IW/requests.log"; }
intune_check() { # python checks print ok|name or bad|name|detail
  while IFS='|' read -r _r _n _d; do
    case "$_r" in ok) ok "$_n" ;; bad) bad "$_n" "$_d" ;; *) bad "intune: the check script printed something unexpected" "$_r $_n" ;; esac
  done
}

if [ -z "$PORT" ]; then
  skip "intune: the mock Microsoft Graph started" "python3 could not start the local mock"
else
ok "intune: the mock Microsoft Graph started"

head -c 2000 /dev/zero | tr '\0' '#' > "$IW/fleet.ps1"
intune_state empty
intune_run PSModulePath="$IW/nomods" -- -Deploy -Group Engineering -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 3 ] && grep -q 'Install-Module Microsoft.Graph.Authentication -Scope CurrentUser' "$IW/o.txt" && [ ! -s "$IW/requests.log" ]; then
  ok "intune: without Microsoft's Graph module it says the line that installs it and stops"
else bad "intune: without Microsoft's Graph module it says the line that installs it and stops" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi

intune_run -- -Report -Group x > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 2 ] && [ ! -s "$IW/stub.log" ]; then ok "intune: an option that does not go with the command exits 2"; else bad "intune: an option that does not go with the command exits 2" "exit $RC"; fi

head -c 204800 /dev/zero | tr '\0' '#' > "$IW/big.ps1"
intune_run -- -Deploy -Group Engineering -FleetScript "$IW/big.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'under 200 KB' "$IW/o.txt" && [ ! -s "$IW/stub.log" ] && [ ! -s "$IW/requests.log" ]; then
  ok "intune: -Deploy refuses a script of 200 KB before signing in"
else bad "intune: -Deploy refuses a script of 200 KB before signing in" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi

head -c 204799 /dev/zero | tr '\0' '#' > "$IW/fleet.ps1"
intune_state empty
intune_run -- -Deploy -Group Nobody -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q "No group is named 'Nobody'" "$IW/o.txt" && [ "$(intune_writes)" -eq 0 ]; then
  ok "intune: -Deploy stops, changing nothing, when no group has the name"
else bad "intune: -Deploy stops, changing nothing, when no group has the name" "exit $RC, $(intune_writes) writes: $(head -c 300 "$IW/o.txt")"; fi
intune_run -- -Deploy -Group Twins -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q "2 groups are named 'Twins'" "$IW/o.txt" && [ "$(intune_writes)" -eq 0 ]; then
  ok "intune: -Deploy stops, changing nothing, when two groups have the name"
else bad "intune: -Deploy stops, changing nothing, when two groups have the name" "exit $RC, $(intune_writes) writes: $(head -c 300 "$IW/o.txt")"; fi

intune_run -- -Deploy -Group "O'Brien team" -FleetScript "$IW/fleet.ps1" -WhatIf > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$(intune_writes)" -eq 0 ] && grep -q 'What if' "$IW/o.txt"; then ok "intune: -Deploy -WhatIf changes nothing"
else bad "intune: -Deploy -WhatIf changes nothing" "exit $RC, $(intune_writes) writes: $(head -c 300 "$IW/o.txt")"; fi

intune_run -- -Deploy -Group "O'Brien team" -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "intune: -Deploy exits 0"; else bad "intune: -Deploy exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_check < <(python3 tests/intune.py check deploy "$IW")

: > "$IW/requests.log"; : > "$IW/stub.log"
head -c 3000 /dev/zero | tr '\0' '#' > "$IW/fleet.ps1"
intune_run -- -Deploy -Group "O'Brien team" -FleetScript "$IW/fleet.ps1" -WhatIf > "$IW/o.txt" 2>&1
if [ "$(intune_writes)" -eq 0 ]; then ok "intune: a second -Deploy -WhatIf changes nothing"; else bad "intune: a second -Deploy -WhatIf changes nothing" "$(intune_writes) writes"; fi
intune_run -- -Deploy -Group "O'Brien team" -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "intune: a second -Deploy exits 0"; else bad "intune: a second -Deploy exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_check < <(python3 tests/intune.py check redeploy "$IW")

intune_state lookalike
intune_run -- -Deploy -Group Engineering -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'this tool did not make it' "$IW/o.txt" && [ "$(intune_writes)" -eq 0 ]; then
  ok "intune: -Deploy leaves a Remediation of the same name that it did not make alone"
else bad "intune: -Deploy leaves a Remediation of the same name that it did not make alone" "exit $RC, $(intune_writes) writes"; fi

intune_state remove
intune_run -- -Remove -WhatIf > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$(intune_writes)" -eq 0 ] && grep -q 'Deletes: Blindspot fleet check' "$IW/o.txt"; then ok "intune: -Remove -WhatIf shows what it would delete and changes nothing"
else bad "intune: -Remove -WhatIf shows what it would delete and changes nothing" "exit $RC, $(intune_writes) writes"; fi
intune_run -- -Remove -Force > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "intune: -Remove exits 0"; else bad "intune: -Remove exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_check < <(python3 tests/intune.py check remove "$IW")
: > "$IW/requests.log"
intune_run -- -Remove -Force > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$(intune_writes)" -eq 0 ] && grep -q 'Nothing to remove' "$IW/o.txt"; then ok "intune: -Remove with nothing of its own deletes nothing"
else bad "intune: -Remove with nothing of its own deletes nothing" "exit $RC, $(intune_writes) writes"; fi
intune_state twomarked
intune_run -- -Remove -Force > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && [ "$(intune_writes)" -eq 0 ]; then ok "intune: -Remove deletes nothing when two Remediations carry its mark"
else bad "intune: -Remove deletes nothing when two Remediations carry its mark" "exit $RC, $(intune_writes) writes"; fi

intune_state report
intune_run -- -Report -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "intune: -Report exits 0"; else bad "intune: -Report exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
if [ "$(intune_writes)" -eq 0 ]; then ok "intune: -Report changes nothing in Intune"; else bad "intune: -Report changes nothing in Intune" "$(intune_writes) writes"; fi
intune_check < <(python3 tests/intune.py check report "$IW")

for T in silent usergroup othertarget; do
  intune_state "$T"
  rm -f "$IW/out"/*
  intune_run -- -Report -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "intune: -Report with the $T tenant exits 0"; else bad "intune: -Report with the $T tenant exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
  cp "$IW/o.txt" "$IW/o-$T.txt"
  mkdir -p "$IW/out-$T"; cp "$IW/out"/* "$IW/out-$T"/ 2>/dev/null
  cp "$IW/requests.log" "$IW/requests-$T.log"
done
intune_check < <(python3 tests/intune.py check silent "$IW")

intune_state badnext
rm -f "$IW/out"/*
intune_run -- -Report -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && ! grep -q '^refused' "$IW/stub.log" && [ -z "$(ls "$IW/out")" ]; then
  ok "intune: -Report stops, saving nothing, at a next-page link to another address"
else bad "intune: -Report stops, saving nothing, at a next-page link to another address" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
fi

if [ "$INTUNE_ALONE" -eq 1 ]; then finish; else intune_cleanup; fi
