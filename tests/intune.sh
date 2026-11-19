#!/usr/bin/env bash
# Tests gird-intune.ps1 against a local stand-in for Microsoft Graph: a stub
# Microsoft.Graph.Authentication module whose Invoke-MgGraphRequest sends each call to a mock
# server on 127.0.0.1, never to a real tenant. tests/run-ps.sh sources this; on its own:
#
#   PWSH=/path/to/pwsh bash tests/intune.sh
#
# The values gird-report.ps1 reads are the ones gird-fleet.sh and gird-fleet.ps1 write: tests/intune.py
# lists every form, and the writers are run here too, each with a stand-in for the account run, so
# the reader and the writers cannot drift apart unseen. gird-fleet.ps1 runs when it is next to
# gird-intune.ps1, or at INTUNE_FLEET_PS1; gird-fleet.sh next to it, or at INTUNE_FLEET_SH. Given
# either path, every shape that writer's own value code makes also goes to Read-Inventory.
# shellcheck disable=SC2016  # the PowerShell below is single-quoted on purpose
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
IW=$(cd "$IW" && pwd -P)
TOOL=$PWD/gird-intune.ps1
REPORT=$PWD/gird-report.ps1
INTUNE_PID=""
intune_cleanup() { [ -n "$INTUNE_PID" ] && { kill "$INTUNE_PID"; wait "$INTUNE_PID"; } 2>/dev/null; chmod -R u+w "$IW" 2>/dev/null; rm -rf "$IW"; INTUNE_PID=""; }
[ "$INTUNE_ALONE" -eq 1 ] && trap intune_cleanup EXIT

echo "gird-intune.ps1 and gird-report.ps1"
for _f in "$TOOL" "$REPORT"; do
  _b=$(basename "$_f")
  if LC_ALL=C grep -q '[^ -~]' "$_f"; then bad "intune: $_b is plain ASCII"; else ok "intune: $_b is plain ASCII"; fi
  sed -e 's/#.*$//' -e "s/'[^']*'//g" -e 's/"[^"]*"//g' "$_f" > "$IW/code.txt"
  hasnot "intune: $_b has no PowerShell 7 only syntax" '\?\?|\?\.|&&|\|\||-Parallel|-AsHashtable|\$Is(Windows|MacOS|Linux)\b|-SkipHttpErrorCheck' "$IW/code.txt"
  hasnot "intune: $_b defines no function that hides a PowerShell command" '^function (ConvertTo-Html|ConvertTo-Csv|Get-Content|Write-Host|Out-File|Get-Item|Test-Path)\b' "$_f"
  if "$PWSH" -NoProfile -NonInteractive -Command "\$e = \$null; [void][Management.Automation.Language.Parser]::ParseFile('$_f', [ref]\$null, [ref]\$e); if (\$e.Count) { \$e | ForEach-Object { \$_.Message }; exit 1 }" > "$IW/parse.txt" 2>&1
  then ok "intune: $_b parses"; else bad "intune: $_b parses" "$(head -n 3 "$IW/parse.txt")"; fi
done
sed -e 's/#.*$//' -e "s/'[^']*'//g" -e 's/"[^"]*"//g' "$TOOL" > "$IW/code.txt"
hasnot "intune: gird-intune.ps1 talks to nothing but Microsoft Graph" 'Invoke-WebRequest|Invoke-RestMethod|WebClient|HttpClient|WebRequest\]|Start-Process|Net\.Sockets' "$IW/code.txt"
grep -v 'System\.Net\.WebUtility\]::HtmlEncode' "$REPORT" > "$IW/report-code.txt"
hasnot "intune: gird-report.ps1 holds no call that can reach the network or Microsoft Graph" 'Invoke-WebRequest|Invoke-RestMethod|WebClient|HttpClient|WebRequest|Net\.Sockets|TcpClient|UdpClient|System\.Net\.|Dns\]|Connect-MgGraph|Invoke-MgGraph|Import-Module|Install-Module|Start-Process|Invoke-Command|New-PSSession|Start-BitsTransfer|Send-MailMessage|DownloadString|DownloadFile|graph\.microsoft' "$IW/report-code.txt"
hasnot "intune: gird-report.ps1 uses nothing only Windows has" 'HKLM:|HKCU:|Registry|\$env:(LOCALAPPDATA|APPDATA|USERPROFILE|ProgramData|TEMP|windir)|Get-WmiObject|Get-CimInstance|\[Microsoft\.Win32' "$REPORT"

mkdir -p "$IW/mods/Microsoft.Graph.Authentication" "$IW/oldmods/Microsoft.Graph.Authentication" "$IW/nomods" "$IW/home" "$IW/out"
cat > "$IW/mods/Microsoft.Graph.Authentication/Microsoft.Graph.Authentication.psm1" <<'PS'
function Connect-MgGraph {
  param([string[]]$Scopes, [switch]$NoWelcome)
  $granted = @($Scopes | Where-Object { @(([string]$env:STUB_DENY).Split(',')) -notcontains $_ })
  Add-Content -WhatIf:$false -LiteralPath $env:STUB_LOG -Value ('connect ' + ($granted -join ','))
}
function Invoke-MgGraphRequest {
  param([string]$Method = 'GET', [string]$Uri, $Body, [string]$ContentType, $OutputType)
  if (-not $Uri.StartsWith('https://graph.microsoft.com/')) {
    Add-Content -WhatIf:$false -LiteralPath $env:STUB_LOG -Value ('refused ' + $Uri)
    throw "stub: not Microsoft Graph: $Uri"
  }
  $u = $env:STUB_GRAPH + $Uri.Substring('https://graph.microsoft.com'.Length)
  $p = @{ Method = $Method; Uri = $u; UseBasicParsing = $true }
  if ($null -ne $Body) { $p.Body = [Text.Encoding]::UTF8.GetBytes([string]$Body); $p.ContentType = $ContentType }
  $r = Invoke-WebRequest @p
  if (-not $r.Content) { return $null }
  $t = $r.Content; if ($t -is [byte[]]) { $t = [Text.Encoding]::UTF8.GetString($t) }
  if (-not $t) { return $null }
  ConvertFrom-Json -InputObject $t -AsHashtable
}
PS
cat > "$IW/oldmods/Microsoft.Graph.Authentication/Microsoft.Graph.Authentication.psm1" <<'PS'
function Connect-MgGraph { param([string[]]$Scopes) Add-Content -LiteralPath $env:STUB_LOG -Value 'connect old' }
function Invoke-MgGraphRequest { param([string]$Method, [string]$Uri) throw 'old' }
PS

python3 tests/intune.py serve "$IW/state.json" "$IW/requests.log" "$IW/port" "$IW/stub.log" &
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
intune_state() { python3 tests/intune.py state "$1" "$IW/state.json" "$IW/forms.tsv"; : > "$IW/requests.log"; : > "$IW/stub.log"; }
intune_writes() { grep -cE '"method": "(POST|PATCH|DELETE)"' "$IW/requests.log"; }
intune_check() { # python checks print ok|name or bad|name|detail
  while IFS='|' read -r _r _n _d; do
    case "$_r" in ok) ok "$_n" ;; bad) bad "$_n" "$_d" ;; *) bad "intune: the check script printed something unexpected" "$_r $_n" ;; esac
  done
}
# report_run [env...] -- args...: runs gird-report.ps1, with the stub Graph module on its path, which it must never touch
report_run() {
  _e=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do _e+=("$1"); shift; done; shift
  env -i PATH=/usr/bin:/bin HOME="$IW/home" PSModulePath="$IW/mods" STUB_GRAPH="http://127.0.0.1:$PORT" STUB_LOG="$IW/stub.log" \
    ${_e[@]+"${_e[@]}"} "$PWSH" -NoProfile -NonInteractive -File "$REPORT" "$@"
}
# report TENANT [env...]: gird-intune.ps1 -Export from a fresh tenant, then gird-report.ps1 on that file, keeping the
# report's output and files and the export's requests by name
intune_report() {
  _t=$1; shift
  intune_state "$_t"
  rm -rf "$IW/out" "$IW/exp-$_t"; mkdir -p "$IW/out" "$IW/exp-$_t"
  intune_run "$@" -- -Export "$IW/exp-$_t/intune.csv" > "$IW/e-$_t.txt" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "intune: -Export with the $_t tenant exits 0"; else bad "intune: -Export with the $_t tenant exits 0" "exit $RC: $(head -c 300 "$IW/e-$_t.txt")"; fi
  _r=$(wc -l < "$IW/requests.log"); _s=$(wc -l < "$IW/stub.log")
  report_run -- "$IW/exp-$_t/intune.csv" -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "intune: gird-report.ps1 on the $_t export exits 0"; else bad "intune: gird-report.ps1 on the $_t export exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
  if [ "$(wc -l < "$IW/requests.log")" -eq "$_r" ] && [ "$(wc -l < "$IW/stub.log")" -eq "$_s" ]; then ok "intune: gird-report.ps1 on the $_t export makes no request and never signs in"
  else bad "intune: gird-report.ps1 on the $_t export makes no request and never signs in" "$(tail -n 2 "$IW/stub.log")"; fi
  cp "$IW/o.txt" "$IW/o-$_t.txt"; rm -rf "$IW/out-$_t"; cp -R "$IW/out" "$IW/out-$_t"; cp "$IW/requests.log" "$IW/requests-$_t.log"
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
intune_run PSModulePath="$IW/oldmods" -- -Export "$IW/old.csv" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 3 ] && grep -q 'too old for this tool' "$IW/o.txt" && grep -q 'Update-Module Microsoft.Graph.Authentication' "$IW/o.txt" && [ ! -s "$IW/stub.log" ]; then
  ok "intune: a Graph module too old for its sign-in says so plainly and stops before signing in"
else bad "intune: a Graph module too old for its sign-in says so plainly and stops before signing in" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi

intune_run -- -Export "$IW/x.csv" -Group x > "$IW/o.txt" 2>&1; RC=$?
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
if grep -q '^Signs in to Microsoft Graph and asks for these permissions: DeviceManagementScripts.ReadWrite.All, Group.ReadBasic.All\.$' "$IW/o.txt"; then
  ok "intune: it names the permissions it asks for before signing in"
else bad "intune: it names the permissions it asks for before signing in" "$(head -c 300 "$IW/o.txt")"; fi
intune_run -- -Deploy -Group Twins -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q "2 groups are named 'Twins'" "$IW/o.txt" && [ "$(intune_writes)" -eq 0 ]; then
  ok "intune: -Deploy stops, changing nothing, when two groups have the name"
else bad "intune: -Deploy stops, changing nothing, when two groups have the name" "exit $RC, $(intune_writes) writes: $(head -c 300 "$IW/o.txt")"; fi

intune_run -- -Deploy -Group "O'Brien team" -FleetScript "$IW/fleet.ps1" -WhatIf > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$(intune_writes)" -eq 0 ] && grep -q 'What if' "$IW/o.txt"; then ok "intune: -Deploy -WhatIf changes nothing"
else bad "intune: -Deploy -WhatIf changes nothing" "exit $RC, $(intune_writes) writes: $(head -c 300 "$IW/o.txt")"; fi

: > "$IW/requests.log"; : > "$IW/stub.log"
intune_run -- -Deploy -Group "O'Brien team" -FleetScript "$IW/fleet.ps1" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then ok "intune: -Deploy exits 0"; else bad "intune: -Deploy exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_check < <(python3 tests/intune.py check deploy "$IW")

: > "$IW/requests.log"; : > "$IW/stub.log"
head -c 3000 /dev/zero | tr '\0' '#' > "$IW/fleet.ps1"
intune_run -- -Deploy -Group "O'Brien team" -FleetScript "$IW/fleet.ps1" -WhatIf > "$IW/o-whatif.txt" 2>&1
if [ "$(intune_writes)" -eq 0 ]; then ok "intune: a second -Deploy -WhatIf changes nothing"; else bad "intune: a second -Deploy -WhatIf changes nothing" "$(intune_writes) writes"; fi
: > "$IW/requests.log"; : > "$IW/stub.log"
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
if [ "$RC" -eq 0 ] || [ "$(intune_writes)" -ne 0 ]; then bad "intune: -Remove deletes nothing when two Remediations carry its mark" "exit $RC, $(intune_writes) writes"
else ok "intune: -Remove deletes nothing when two Remediations carry its mark"; fi
intune_state ctl
intune_run -- -Remove -WhatIf > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && grep -q 'Deletes: Blindspot fleet check\[2J' "$IW/o.txt" && ! LC_ALL=C grep -q $'[\x01-\x08\x0b-\x0c\x0e-\x1f\x7f]' "$IW/o.txt" && ! grep -q $'\xe2\x80\xae' "$IW/o.txt"; then
  ok "intune: a name the tenant sends reaches the console with no control character"
else bad "intune: a name the tenant sends reaches the console with no control character" "exit $RC: $(head -c 300 "$IW/o.txt" | od -c | head -n 5)"; fi

# The values the two writers print, each run here with a stand-in for its account run.
: > "$IW/forms.tsv"
PY=$(command -v python3)
cat > "$IW/launch.sh" <<EOF
#!/bin/bash
acct=""; prev=""; for a in "\$@"; do [ "\$prev" = -u ] && acct=\$a; prev=\$a; done
# gird-fleet.sh starts itself again with only its GIRD_CHECK_ settings, so it passes these on in that name too.
INTUNE_MODES=\${INTUNE_MODES:-\$GIRD_CHECK_INTUNE_MODES}; INTUNE_FLAVOUR=\${INTUNE_FLAVOUR:-\$GIRD_CHECK_INTUNE_FLAVOUR}
mode=\$(/bin/cat "\$INTUNE_MODES/\${acct:-default}" 2>/dev/null)
case "\$mode" in
  fail) exit 1 ;;
  empty) exit 0 ;;
  language) echo language_mode=1; exit 0 ;;
  sleep) exec /bin/sleep 60 ;;
  garbage) echo v=2; exit 0 ;;
  chmod) for a in "\$@"; do case "\$a" in */gird-check.sh) /bin/chmod 666 "\$a" ;; esac; done
         exec "$PY" "$PWD/tests/intune.py" account clear "\$INTUNE_FLAVOUR" ;;
  *) exec "$PY" "$PWD/tests/intune.py" account "\${mode:-clear}" "\$INTUNE_FLAVOUR" ;;
esac
EOF
chmod 755 "$IW/launch.sh"
form() { # status label value-regex value: one value a writer printed, and the form it must have
  if printf '%s' "$4" | grep -qE -- "$3"; then ok "intune: $2 writes the form it should"; else bad "intune: $2 writes the form it should" "wanted /$3/, got: $(printf '%s' "$4" | head -c 300)"; fi
  printf '%s\t%s\t%s\n' "$1" "$2" "$4" >> "$IW/forms.tsv"
}
T='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z'

FLEETSH=${INTUNE_FLEET_SH:-$PWD/gird-fleet.sh}; WS=$IW/wsh; U=$(id -u)
wsh_users() { # name:mode:home:shell:uid ... (home, shell and uid optional)
  rm -rf "$WS"; mkdir -p "$WS/modes" "$WS/tmp" "$WS/old"; : > "$WS/users.tsv"
  for _e in "$@"; do
    IFS=: read -r _n _m _h _s _u <<< "$_e"
    [ -n "$_h" ] || { _h="$WS/h-$_n"; mkdir -p "$_h"; }
    printf '%s\t%s\t%s\t%s\n' "$_n" "${_u:-$U}" "$_h" "${_s:-/bin/zsh}" >> "$WS/users.tsv"
    [ -n "$_m" ] && printf '%s' "$_m" > "$WS/modes/$_n"
  done
}
wsh_run() { # fleet options...: one --all-users run, then the --inventory line an MDM reads
  GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$WS/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$IW/launch.sh" GIRD_CHECK_FLEET_STATE="$WS/state" \
    GIRD_CHECK_FLEET_SHARED_TMP="$WS/tmp" GIRD_CHECK_FLEET_OLD="$WS/old" GIRD_CHECK_INTUNE_MODES="$WS/modes" GIRD_CHECK_INTUNE_FLAVOUR=sh /bin/bash -p "$FLEETSH" --all-users "$@" < /dev/null > "$WS/run.out" 2>&1
  wsh_inv
}
wsh_inv() { GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$WS/state" /bin/bash -p "$FLEETSH" --inventory 2>&1 | head -n 1; }
wsh_epoch() { python3 - "$WS/state/last.json" "$1" <<'PY'
import re, sys, time
p = sys.argv[1]; t = open(p).read()
t = re.sub(r'"checked_epoch": [0-9]+,', '"checked_epoch": %d,' % (int(time.time()) - int(sys.argv[2])), t)
with open(p, 'r+') as f: f.seek(0); f.write(t); f.truncate()
PY
}
if [ "$(uname -s)" != Darwin ]; then
  skip "intune: gird-fleet.sh runs here to write its forms" "gird-fleet.sh is built for macOS only so far"
else
  wsh_users asha:act; form act "gird-fleet.sh run: every act item" "^v1 act $T \| asha: act wiper; incidents tanstack; lockfile axios; planted 2; keys 3 anthropic,aws" "$(wsh_run)"
  wsh_users bo:review; form review "gird-fleet.sh run: every review item" "^v1 review $T \| bo: review run-without-asking .*tmp-wiper; tmp-marks mastra$" "$(wsh_run)"
  wsh_users asha:actpartial bo:clear; form act "gird-fleet.sh run: act and partly checked" "^v1 act $T \| asha: act keys 1; partial \| bo: clear$" "$(wsh_run)"
  wsh_users cy:partial dee:clear; form not_checked "gird-fleet.sh run: partly checked and clear" "^v1 not_checked $T \| cy: not_checked ssh-open 1; partial \| dee: clear$" "$(wsh_run)"
  mkdir -p "$IW/linked"; ln -s "$IW/linked" "$IW/homelink"
  wsh_users asha:clear 'bad!name:clear' 'nosh:clear::/usr/bin/false' "gone:clear:$IW/nothere" 'sysh:clear:/usr' "lnk:clear:$IW/homelink"
  form not_checked "gird-fleet.sh run: accounts it does not check, first set" "^v1 not_checked $T \| asha: clear \| invalid-name: not_checked name \| nosh: not_checked no_login_shell \| gone: not_checked home_missing \| sysh: not_checked home_system \| lnk: not_checked home_link$" "$(wsh_run)"
  mkdir -p "$IW/we+ird" "$IW/shared"
  wsh_users "own:clear:$IW/linked::$((U + 1))" "odd:clear:$IW/we+ird" "sha:clear:$IW/shared" "shb:clear:$IW/shared" fl:fail gb:garbage
  form not_checked "gird-fleet.sh run: accounts it does not check, second set" "^v1 not_checked $T \| own: not_checked home_owner \| odd: not_checked home_name \| sha: clear \| shb: not_checked home_shared \| fl: not_checked sudo \| gb: not_checked bad_output$" "$(wsh_run)"
  wsh_users asha:clear; form not_checked "gird-fleet.sh run: the deadline first" "^v1 not_checked $T \| asha: not_checked deadline( \| machine: not_checked)?$" "$(wsh_run --deadline=3)"
  wsh_users asha:sleep; form not_checked "gird-fleet.sh run: out of time" "^v1 not_checked $T \| asha: not_checked time_limit( \| machine: not_checked)?$" "$(wsh_run --deadline=8)"
  wsh_users a1:chmod a2:clear; form failed "gird-fleet.sh run: the script copy changed" "^v1 failed $T \| a1: clear \| a2: not_checked copy_changed$" "$(wsh_run)"
  wsh_users; form not_checked "gird-fleet.sh run: no accounts" "^v1 not_checked $T \| no accounts$" "$(wsh_run)"
  wsh_users asha:clear; : > "$WS/tmp/.pc_sq_1"; : > "$WS/tmp/gh-token-monitor.out.log"
  form review "gird-fleet.sh run: the Mac's own row" "^v1 review $T \| asha: clear \| machine: review; possible litellm; tmp-wiper$" "$(wsh_run)"
  wsh_users ann:act bob:act cat:act dan:act eve:review fay:partial gus:clear
  form act "gird-fleet.sh run: cut to fit" "^v1 act $T \| .* \+more$" "$(wsh_run)"
  wsh_users; form no_result "gird-fleet.sh --inventory: before the first run" '^none$' "$(wsh_inv)"
  wsh_users asha:clear; wsh_run > /dev/null; chmod 644 "$WS/state/last.json"; form not_checked "gird-fleet.sh --inventory: a file not root's own" '^unreadable$' "$(wsh_inv)"
  wsh_users asha:clear; wsh_run > /dev/null; wsh_epoch 432000; form stale "gird-fleet.sh --inventory: an old run" "^stale: last run $T$" "$(wsh_inv)"
  wsh_users asha:clear; wsh_run > /dev/null; wsh_epoch 600; printf '%s 10' "$(( $(date -u +%s) - 300 ))" > "$WS/state/attempt"; chmod 600 "$WS/state/attempt"
  form failed "gird-fleet.sh --inventory: a run that did not finish" "^failed: the run started $T did not finish or could not save its result$" "$(wsh_inv)"
  _ol="gird-fleet.sh runs here with an older install beside it"
  if [ -z "${INTUNE_FLEET_SH:-}" ]; then skip "intune: $_ol" "INTUNE_FLEET_SH is not set"
  else
    wsh_users asha:clear; : > "$WS/old/gird-check.sh"
    form clear "gird-fleet.sh run: an older install" "^v1 clear $T \| asha: clear \| old-install$" "$(wsh_run)"
    wsh_users; : > "$WS/old/gird-fleet.sh"
    form not_checked "gird-fleet.sh run: an older install and no accounts" "^v1 not_checked $T \| old-install \| no accounts$" "$(wsh_run)"
    wsh_users asha:clear; : > "$WS/old/gird-check.sh"; : > "$WS/tmp/.pc_sq_1"; : > "$WS/tmp/gh-token-monitor.out.log"
    form review "gird-fleet.sh run: the Mac's own row, then an older install" "^v1 review $T \| asha: clear \| machine: review; possible litellm; tmp-wiper \| old-install$" "$(wsh_run)"
    wsh_users; : > "$WS/old/gird-check.sh"; : > "$WS/tmp/.pc_sq_1"
    form not_checked "gird-fleet.sh run: the Mac's own row, an older install, no accounts" "^v1 not_checked $T \| machine: review; possible litellm \| old-install \| no accounts$" "$(wsh_run)"
    wsh_users ann:act bob:act cat:act dan:act eve:review fay:partial gus:clear; : > "$WS/old/gird-check.sh"
    form act "gird-fleet.sh run: cut to fit, keeping an older install" "^v1 act $T \| [^|]+: act.* \| old-install \+more$" "$(wsh_run)"
  fi
fi

FLEETPS=${INTUNE_FLEET_PS1:-$PWD/gird-fleet.ps1}; WP=$IW/wps
wps() { # status label value-regex mode [env...] [-- args...]: one gird-fleet.ps1 run
  _st=$1; _lb=$2; _rx=$3; _md=$4; shift 4
  _e=(); while [ "$#" -gt 0 ] && [ "$1" != -- ]; do _e+=("$1"); shift; done; [ "$#" -gt 0 ] && shift
  rm -rf "$WP"; mkdir -p "$WP/run" "$WP/local" "$WP/modes"
  cp "$FLEETPS" "$WP/run/gird-fleet.ps1"
  _ck=$(dirname "$FLEETPS")/gird-check.ps1; [ -f "$_ck" ] || _ck=$PWD/gird-check.ps1
  cp "$_ck" "$WP/run/gird-check.ps1"
  printf '%s' "$_md" > "$WP/modes/default"
  _v=$(env -i PATH=/usr/bin:/bin HOME="$WP" LOCALAPPDATA="$WP/local" APPDATA="$WP/roaming" GIRD_CHECK_FLEET_TEST=1 \
    GIRD_CHECK_FLEET_LAUNCH="$IW/launch.sh" INTUNE_MODES="$WP/modes" INTUNE_FLAVOUR=ps ${_e[@]+"${_e[@]}"} \
    "$PWSH" -NoProfile -NonInteractive -File "$WP/run/gird-fleet.ps1" "$@" 2>/dev/null | head -n 1)
  form "$_st" "gird-fleet.ps1 run: $_lb" "$_rx" "$_v"
}
if [ ! -f "$FLEETPS" ]; then
  skip "intune: gird-fleet.ps1 runs here to write its forms" "gird-fleet.ps1 is not next to gird-intune.ps1 and INTUNE_FLEET_PS1 is not set"
else
  P0="^v1 [a-z_]+ $T other_profiles=0"
  wps clear "clear, other profiles" "^v1 clear $T other_profiles=2 \| [A-Za-z0-9._-]+: clear$" clear GIRD_CHECK_FLEET_PROFILES=2
  wps act "every act item" "$P0 \| [^ ]+: act wiper; incidents tanstack; lockfile axios; planted 2; keys 3 anthropic,aws; history 1; sessions 2; mcp-tokens 1; allow-lists 1; ssh-links 1; update mistral$" act
  wps review "every review item" "$P0 \| [^ ]+: review run-without-asking claude-code,codex; ssh-open 1; update-tools amazonq; platforms opencode; on-open 1; to-read 1; remove glassworm; update mistral; possible mastra$" review
  wps not_checked "partly checked" "$P0 \| [^ ]+: not_checked ssh-open 1; partial$" partial
  wps act "act and partly checked" "$P0 \| [^ ]+: act keys 1; partial$" actpartial
  wps act "cut to fit" "^v1 act $T other_profiles=0 \| [^ ]+: act wiper; incidents [a-z0-9,]+ \+more$" huge
  wps not_checked "output it does not read" "$P0 \| [^ ]+: not_checked bad_output$" garbage
  wps failed "an account run with no output" "^v1 failed $T other_profiles=0 reason=no_output \| [^ ]+: not_checked no_output$" empty
  wps failed "an account run in the reduced language" "^v1 failed $T other_profiles=0 reason=language_mode \| [^ ]+: not_checked language_mode$" language
  wps not_checked "an account run that sends markers in a shared folder" "$P0 \| [^ ]+: not_checked bad_output$" tmpmarks
  wps failed "an account run that does not start" "^v1 failed $T other_profiles=0 reason=start \| [^ ]+: not_checked start$" clear GIRD_CHECK_FLEET_LAUNCH="$IW/no-such-launcher"
  wps not_checked "the deadline first" "$P0 \| [^ ]+: not_checked deadline$" clear -- -Deadline 3
  # gird-fleet.ps1 keeps a tenth of the deadline back, and 10 seconds more for stopping the account run, so
  # the account run gets -Deadline 20 less 12 seconds and is stopped at its time limit; -Deadline 12 leaves
  # it less than a second, and the run is not started.
  wps not_checked "out of time" "$P0 \| [^ ]+: not_checked time_limit$" sleep -- -Deadline 20
  wps not_checked "a deadline that leaves no time once the stop is held back" "$P0 \| [^ ]+: not_checked deadline$" sleep -- -Deadline 12
  : > "$IW/notafolder"
  wps failed "nowhere to save" "^v1 failed $T other_profiles=0 reason=save \| [^ ]+: not_checked save$" clear LOCALAPPDATA="$IW/notafolder"
  rm -rf "$WP"; mkdir -p "$WP/run" "$WP/local"; cp "$FLEETPS" "$WP/run/gird-fleet.ps1"
  _v=$(env -i PATH=/usr/bin:/bin HOME="$WP" LOCALAPPDATA="$WP/local" GIRD_CHECK_FLEET_TEST=1 "$PWSH" -NoProfile -NonInteractive -File "$WP/run/gird-fleet.ps1" 2>/dev/null | head -n 1)
  form failed "gird-fleet.ps1 run: no gird-check.ps1 to unpack" "^v1 failed $T other_profiles=0 reason=unpack \| [^ ]+: not_checked unpack$" "$_v"
fi

# Every shape each writer's own value code makes, read by Read-Inventory as the writer meant it: the
# outcome, each row the reader returns with the outcome the writer gave it, and old-install. The Mac's
# values come from fl_value in gird-fleet.sh, at every length either side of its 250 characters; the
# PC's from Machine-Outcome, Machine-Part and Fit-Value in gird-fleet.ps1, either side of 2,047.
DR=$IW/drift; mkdir -p "$DR"
{ sed -n '/^\$Outcomes = @{/,/^function Get-UtcTime/p' "$REPORT" | sed '$d'; cat <<'PS'
function Read-As([string]$v) {
  $r = Read-Inventory $v
  if (-not $r.Ok -or $r.Special) { return 'unread' }
  $r.Outcome + ' old=' + ([string]$r.OldInstall).ToLower() + ' ' + ((@($r.Accounts) | ForEach-Object { $_.Name + '=' + $_.Outcome + ',' }) -join '')
}
if ($args[0] -eq 'mac') { foreach ($v in [IO.File]::ReadAllLines($args[1])) { Read-As $v }; return }
. $args[1]
$T = '2026-10-25T09:12Z'; $rank = @{ 'failed' = 5; 'act' = 4; 'not_checked' = 3; 'review' = 2; 'clear' = 1 }
$n = 0; $bad = New-Object System.Collections.ArrayList
$accts = @(
  @('clear', 'anna: clear', '', ''), @('review', 'anna: review ssh-open 1', '', ''), @('not_checked', 'anna: not_checked ssh-open 1; partial', '', ''),
  @('not_checked', 'anna: not_checked time_limit', '', ''), @('act', 'anna: act wiper; incidents tanstack; keys 3 anthropic,aws; possible ', 'anna: act wiper; incidents tanstack', ''),
  @('review', 'anna: review possible ', '', ''), @('act', 'anna: act keys 1', '', 'save'), @('not_checked', 'anna: not_checked host_32bit', '', 'host_32bit'))
foreach ($a in $accts) { foreach ($inc in @(@(), @('mastra'))) { foreach ($pos in @(@(), @('mastra'))) { foreach ($done in @($true, $false)) {
  $st = @{ Inc = $inc; Poss = $pos; Complete = $done }
  $mo = Machine-Outcome $inc $pos $done
  $out = $a[0]; if ($rank[$mo] -gt $rank[$out]) { $out = $mo }; if ($a[3]) { $out = 'failed' }
  $head = "v1 $out $T other_profiles=0"; if ($a[3]) { $head += " reason=$($a[3])" }
  $tail = Machine-Part $st $mo
  $lens = @(0); if ($a[1].EndsWith(' ')) { $lens = 1940..2100 }
  foreach ($l in $lens) {
    $acc = $a[1]
    if ($l) { $ids = ''; while ($ids.Length -lt $l) { if ($ids) { $ids += ',' }; $ids += 'p' + ('a' * 40) }; $acc += $ids.Substring(0, $l).TrimEnd(',') }
    $key = $a[2]; if (-not $key) { $key = 'anna: ' + $a[0] }
    $v = Fit-Value $head $acc $key ('anna: ' + $a[0]) $tail
    $want = @{ 'anna' = $a[0] }; if ($tail) { $want['machine'] = $mo }
    $n++; $got = Read-As $v; $ok = $got -ne 'unread' -and $v.Length -le 2047
    if ($ok) {
      $f = $got.Split(' '); $ok = $f[0] -ceq $out -and $f[1] -ceq 'old=false'
      foreach ($kv in ($f[2].Split(',') | Where-Object { $_ })) { $p = $kv.Split('='); if ($want[$p[0]] -cne $p[1]) { $ok = $false } }
      if (@($f[2].Split(',') | Where-Object { $_ }).Count -ne $want.Count) { $ok = $false }
    }
    if (-not $ok -and $bad.Count -lt 3) { [void]$bad.Add($v.Substring(0, [Math]::Min(160, $v.Length)) + ' => ' + $got) }
    elseif (-not $ok) { [void]$bad.Add('') }
  }
} } } }
"$($bad.Count) of $n not read as meant; " + (($bad | Where-Object { $_ }) -join '; ')
PS
} > "$DR/read.ps1"
_dn="the report reads every value gird-fleet.sh's own value code makes, of every shape and length, as the writer meant"
if [ -z "${INTUNE_FLEET_SH:-}" ]; then skip "intune: $_dn" "INTUNE_FLEET_SH is not set"
else
  for _fn in fl_value fl_worst; do sed -n "/^$_fn() {/,/^}\$/p" "$INTUNE_FLEET_SH"; done > "$DR/value.sh"; . "$DR/value.sh"
  : > "$DR/mac.in"; _da40=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  dpad() { # n: clear account rows, " | name: clear" each, n characters in all (n is 0, or 11 and more)
    _dr=$1; _di=10; DP=""
    while [ "$_dr" -gt 60 ]; do _di=$((_di + 1)); DP="$DP | c$_di${_da40:0:37}: clear"; _dr=$((_dr - 50)); done
    [ "$_dr" -ge 11 ] && DP="$DP | e${_da40:0:$((_dr - 11))}: clear"
  }
  dids() { # n: a comma list of ids, n characters in all (n is 3 or more)
    _dr=$1; _di=10; DI=""
    while [ "$_dr" -gt 50 ]; do _di=$((_di + 1)); DI="$DI${DI:+,}i$_di${_da40:0:44}"; _dr=$((_dr - 48)); done
    DI="$DI${DI:+,}j${_da40:0:$((_dr - 1))}"
  }
  dcase() { printf '%s\t%s\t%s\t%s\n' "$@" >> "$DR/mac.in"; } # outcome accounts old parts
  # The lengths either side of the 250 a Mac value keeps, and one far on each side.
  _dls="200 $(seq 236 264 | tr '\n' ' ')300"
  for _do in 0 1; do
    _dt=""; [ "$_do" -eq 1 ] && _dt=" | old-install"
    for _dm in "" "machine: act incidents litellm; possible @; tmp-wiper" "machine: review; possible @" "machine: review; tmp-wiper" "machine: not_checked" "machine: not_checked incidents @; possible litellm" "machine: act incidents @"; do
      _mo=${_dm#machine: }; _mo=${_mo%%[ ;]*}; _mr=""; [ -n "$_dm" ] && _mr=" | $_dm"
      # No accounts: the machine's row grows.
      _o=$(printf '%s\n' "${_mo:-clear}" not_checked | fl_worst); _b=$((21 + ${#_o} + ${#_mr} - 1 + 14 + ${#_dt}))
      case "$_mr" in *@*) for _l in $_dls; do dids $((_l - _b)); dcase "$_o" 0 "$_do" "${_mr/@/$DI}$_dt"; done ;;
        *) dcase "$_o" 0 "$_do" "$_mr$_dt" ;; esac
      for _da in "act| | asha: act wiper; incidents litellm; keys 3 openai | bob: review ssh-open 1 | carol: not_checked sudo" "clear| | dee: clear" \
                 "not_checked| | eve: not_checked ssh-open 1; partial" "failed| | a1: clear | a2: not_checked copy_changed"; do
        _ao=${_da%%|*}; _ar=${_da#*|}; _o=$_ao; [ "$_ao" = failed ] || _o=$(printf '%s\n' "$_ao" "${_mo:-clear}" | fl_worst)
        _ms=${_mr/@/litellm}; _b=$((21 + ${#_o} + ${#_ar} + ${#_ms} + ${#_dt}))
        dcase "$_o" 1 "$_do" "$_ar$_ms$_dt"
        for _l in $_dls; do _p=$((_l - _b)); [ "$_p" -ge 11 ] && { dpad "$_p"; dcase "$_o" 1 "$_do" "$_ar$DP$_ms$_dt"; }; done
      done
    done
  done
  while IFS="$(printf '\t')" read -r _o _n _x _ps; do printf '%s\n' "$(fl_value "v1 $_o 2026-10-25T09:12Z" "$_ps" "$_n")"; done < "$DR/mac.in" > "$DR/mac.txt"
  # What the writer meant: the outcome, old-install, and each row's outcome as the parts give it.
  awk -F '\t' '{ printf "%s old=%s ", $1, ($3 == 1 ? "true" : "false"); n = split($4, s, / [|] /)
    for (i = 2; i <= n; i++) if (s[i] != "old-install") { split(s[i], p, "[ ;]"); k = p[1]; sub(/:$/, "", k); printf "%s=%s,", k, p[2] }
    if ($2 == 0) printf "(no accounts)=not_checked,"; print "" }' "$DR/mac.in" > "$DR/mac.want"
  "$PWSH" -NoProfile -NonInteractive -File "$DR/read.ps1" mac "$DR/mac.txt" > "$DR/mac.got" 2>&1
  _drd=$(paste -d '\t' "$DR/mac.want" "$DR/mac.got" "$DR/mac.txt" | awk -F '\t' '
    { split($1, w, " "); split($2, g, " "); bad = 0
      if ($2 == "unread" || g[1] != w[1] || g[2] != w[2] || length($3) > 250) bad = 1
      n = split(w[3], a, ","); for (i = 1; i < n; i++) { split(a[i], kv, "="); want[kv[1]] = kv[2] }
      m = split(g[3], b, ","); for (i = 1; i < m; i++) { split(b[i], kv, "="); if (!(kv[1] in want) || want[kv[1]] != kv[2]) bad = 1 }
      if ($3 !~ / \+more$/ && m != n) bad = 1
      delete want
      if (bad) { nb++; if (nb <= 3) printf "%s => %s; ", $3, $2 } }
    END { printf "%d of %d not read as meant, %d cut", nb, NR, cut }
    $3 ~ / \+more$/ { cut++ }')
  if [ "$(wc -l < "$DR/mac.txt" | tr -d ' ')" -eq "$(wc -l < "$DR/mac.got" | tr -d ' ')" ] && [ "${_drd#0 of }" != "$_drd" ] && [ "${_drd% 0 cut}" = "$_drd" ]; then ok "intune: $_dn" "$_drd"
  else bad "intune: $_dn" "$_drd"; fi
fi
_dn="the report reads every value gird-fleet.ps1's own value code makes, of every shape and length, as the writer meant"
if [ ! -f "$FLEETPS" ]; then skip "intune: $_dn" "gird-fleet.ps1 is not next to gird-intune.ps1 and INTUNE_FLEET_PS1 is not set"
else
  { sed -n '/^\$FlIncidents = @{/p' "$FLEETPS"
    for _fn in Commas Machine-Outcome Machine-Part Fit-Value; do sed -n "/^function $_fn(/,/^}/p" "$FLEETPS" | awk 'NR == 1 && /}$/ { print; exit } { print } /^}/ { exit }'; done; } > "$DR/writer.ps1"
  _drd=$("$PWSH" -NoProfile -NonInteractive -File "$DR/read.ps1" pc "$DR/writer.ps1" 2>&1 | tail -n 1)
  if [ "$(grep -c '^function ' "$DR/writer.ps1")" -eq 4 ] && [ "${_drd#0 of }" != "$_drd" ]; then ok "intune: $_dn" "${_drd%%;*}"
  else bad "intune: $_dn" "$_drd"; fi
fi

intune_report forms
intune_check < <(python3 tests/intune.py check forms "$IW")

intune_report report
if [ "$(intune_writes)" -eq 0 ]; then ok "intune: -Export changes nothing in Intune"; else bad "intune: -Export changes nothing in Intune" "$(intune_writes) writes"; fi
if grep -q "^Next: gird-report.ps1 \"$IW/exp-report/intune.csv\"$" "$IW/e-report.txt" && [ "$(head -c 3 "$IW/exp-report/intune.csv" | od -An -tx1 | tr -d ' \n')" = efbbbf ] \
  && head -n 1 "$IW/exp-report/intune.csv" | grep -q '"Device name","Device id","User","OS","Result","Detection state","Last reported","Note"'; then
  ok "intune: -Export writes the columns gird-report.ps1 reads and says the command to run next"
else bad "intune: -Export writes the columns gird-report.ps1 reads and says the command to run next" "$(head -c 300 "$IW/e-report.txt")"; fi
intune_check < <(python3 tests/intune.py check report "$IW")

intune_report mitre
intune_check < <(python3 tests/intune.py check mitre "$IW")

for _tn in silent usergroup othertarget exclusion alldevices filter membererror exclerror exclhidden unassigned; do intune_report "$_tn"; done
intune_report nodeviceid STUB_DENY=Device.Read.All
intune_check < <(python3 tests/intune.py check silent "$IW")

intune_state badnext; rm -rf "$IW/exp"; mkdir -p "$IW/exp"
intune_run -- -Export "$IW/exp/intune.csv" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && ! grep -q '^refused' "$IW/stub.log" && [ -z "$(ls "$IW/exp")" ]; then
  ok "intune: -Export stops, saving nothing, at a next-page link to another address"
else bad "intune: -Export stops, saving nothing, at a next-page link to another address" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_state novalue; rm -rf "$IW/exp"; mkdir -p "$IW/exp"
intune_run -- -Export "$IW/exp/intune.csv" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'Stopped: Microsoft Graph sent a page of results with no list in it' "$IW/o.txt" && ! grep -q 'Stopped: Stopped' "$IW/o.txt" && [ -z "$(ls "$IW/exp")" ]; then
  ok "intune: -Export stops, saving nothing, at a page with no list of results"
else bad "intune: -Export stops, saving nothing, at a page with no list of results" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_state report; : > "$IW/exp/taken.csv"
intune_run -- -Export "$IW/exp/taken.csv" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'is already there' "$IW/o.txt" && [ ! -s "$IW/stub.log" ] && [ ! -s "$IW/exp/taken.csv" ]; then
  ok "intune: -Export refuses a file already there, before signing in"
else bad "intune: -Export refuses a file already there, before signing in" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_run -- -Export 'Env:/x.csv' > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'not a file name in a folder on disk' "$IW/o.txt" && [ ! -s "$IW/stub.log" ]; then
  ok "intune: an -Export path that is not a folder on disk is refused before signing in"
else bad "intune: an -Export path that is not a folder on disk is refused before signing in" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
intune_state report; rm -rf "$IW/exp"; mkdir -p "$IW/exp"
intune_run -- -Export "$IW/exp/intune.csv" > /dev/null 2>&1
fi

# gird-report.ps1 on its own: exports an MDM gives, read with no sign-in and no network request.
python3 tests/intune.py files "$IW/files"
report_file() { # NAME [env...] -- args...: one gird-report.ps1 run into a fresh folder, kept by name
  _t=$1; shift
  : > "$IW/requests.log"; : > "$IW/stub.log"; rm -rf "$IW/out"; mkdir -p "$IW/out"
  _f=(); while [ "$#" -gt 0 ] && [ "$1" != -- ]; do _f+=("$1"); shift; done; shift
  report_run ${_f[@]+"${_f[@]}"} -- "$@" -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
  cp "$IW/o.txt" "$IW/o-$_t.txt"; rm -rf "$IW/out-$_t"; cp -R "$IW/out" "$IW/out-$_t"; cp "$IW/requests.log" "$IW/requests-$_t.log"; cp "$IW/stub.log" "$IW/stub-$_t.log"
}
plain_fail() { # name text: exit 1 or 2, the text on screen, no PowerShell error record, nothing saved
  if [ "$RC" -ge 1 ] && [ "$RC" -le 2 ] && ! grep -qE 'Exception|At line|CategoryInfo|FullyQualifiedErrorId|\+ +~|ParameterBinding|System\.' "$IW/o.txt" && [ -z "$(ls "$IW/out")" ] && grep -qF -- "$2" "$IW/o.txt"; then ok "$1"
  else bad "$1" "exit $RC: $(head -c 400 "$IW/o.txt")"; fi
}
report_file jamf PSModulePath="$IW/nomods" -- "$IW/files/jamf.csv" -SeenColumn 'Last Inventory Update'
if [ "$RC" -eq 0 ]; then ok "intune: gird-report.ps1 reads a Jamf Pro export with result tags, with no Graph module"; else bad "intune: gird-report.ps1 reads a Jamf Pro export with result tags, with no Graph module" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
if [ "$(wc -l < "$IW/o.txt" | tr -d ' ')" -eq 4 ] && grep -q '^Read 13 computers from jamf.csv\.$' "$IW/o.txt" && grep -q '^Need attention now: 3\. To review: 0\. Clear: 2\.$' "$IW/o.txt" \
  && grep -q '^Not checked: 8 ' "$IW/o.txt" && grep -q "^Report: $IW/out/blindspot-report-[0-9-]*\.html " "$IW/o.txt"; then
  ok "intune: gird-report.ps1 ends with four lines: computers read, attention now, not checked, and the report's path"
else bad "intune: gird-report.ps1 ends with four lines: computers read, attention now, not checked, and the report's path" "$(cat "$IW/o.txt")"; fi
report_file plain -- "$IW/files/plain.csv"
if [ "$RC" -eq 0 ] && [ ! -s "$IW/stub.log" ] && [ ! -s "$IW/requests.log" ]; then ok "intune: gird-report.ps1 reads a plain two-column CSV and never calls the Graph module"
else bad "intune: gird-report.ps1 reads a plain two-column CSV and never calls the Graph module" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
if [ -f "$IW/exp/intune.csv" ]; then
  report_file mixed -- "$IW/exp/intune.csv" "$IW/files/jamf.csv"
  if [ "$RC" -eq 0 ]; then ok "intune: gird-report.ps1 reads an Intune export and a Jamf Pro export into one report"; else bad "intune: gird-report.ps1 reads an Intune export and a Jamf Pro export into one report" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
else skip "intune: gird-report.ps1 reads an Intune export and a Jamf Pro export into one report" "the mock Microsoft Graph did not start, so there is no Intune export"; fi
for _enc in semicolon-utf16 tab-utf16-nobom tab-utf16be-nobom semicolon-utf8bom; do
  report_file "$_enc" -- "$IW/files/$_enc.csv"
  if [ "$RC" -eq 0 ] && grep -q '^Read 2 computers' "$IW/o.txt" && grep -q '^Need attention now: 1\.' "$IW/o.txt"; then ok "intune: gird-report.ps1 finds the delimiter and the encoding: $_enc"
  else bad "intune: gird-report.ps1 finds the delimiter and the encoding: $_enc" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
done
_s=$(date +%s); report_file big -- "$IW/files/big.csv"; _s=$(( $(date +%s) - _s ))
if [ "$RC" -eq 0 ]; then ok "intune: gird-report.ps1 reads a file of 20,000 computers"; echo "        ($(wc -c < "$IW/files/big.csv" | tr -d ' ') bytes in ${_s}s)"
else bad "intune: gird-report.ps1 reads a file of 20,000 computers" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
report_file twocols -- "$IW/files/twocols.csv"
plain_fail "intune: gird-report.ps1 says plainly which columns look like the result, with a value from each, and the command to run next" 'Run it again naming the one to read:'
if grep -q '^  Previous result: v1 act ' "$IW/o.txt" && grep -qF "  gird-report.ps1 \"$IW/files/twocols.csv\" -ResultColumn \"Result\"" "$IW/o.txt"; then ok "intune: the command it suggests names the file and the column"
else bad "intune: the command it suggests names the file and the column" "$(cat "$IW/o.txt")"; fi
report_file twocolsnone -- "$IW/files/twocolsnone.csv"
plain_fail "intune: a second column that only reads none is not passed over quietly: it stops and names both" 'has 2 columns that look like the Blindspot result, so it does not pick one.'
if grep -qF 'The ones that look like the result: "Result", "Old result".' "$IW/o.txt" && grep -qF -- '-ResultColumn "Result"' "$IW/o.txt"; then ok "intune: it names both columns and suggests the one with a real result"
else bad "intune: it names both columns and suggests the one with a real result" "$(cat "$IW/o.txt")"; fi
report_file twocolsnamed -- "$IW/files/twocols.csv" -ResultColumn result
if [ "$RC" -eq 0 ]; then ok "intune: -ResultColumn settles which column holds the result"; else bad "intune: -ResultColumn settles which column holds the result" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
report_file paths -- "$IW/files/paths.csv"
if [ "$RC" -eq 0 ]; then ok "intune: gird-report.ps1 reads the file of every way a result can be whole or not"; else bad "intune: gird-report.ps1 reads the file of every way a result can be whole or not" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
report_file oem -- "$IW/files/oem.csv"
report_file mdmid -- "$IW/files/mdma.csv" "$IW/files/mdmb.csv"
report_file dupname -- "$IW/files/dupc.csv" "$IW/files/dupd.csv"
report_file dupws -- "$IW/files/dupws.csv"
report_file winfleet -- "$IW/files/winfleet.csv"
report_file clearonly -- "$IW/files/clearonly.csv"
report_file csf -- "$IW/files/csf.csv"
report_file page -- "$IW/files/page.csv" -Organisation "$(cat "$IW/files/org.txt")"
report_file pagebare -- "$IW/files/page.csv"
report_file noname -- "$IW/files/noname.csv"
plain_fail "intune: gird-report.ps1 says plainly when no column holds the computer's name" "holds the computer's name. Its columns, with a value from each:"
report_file noresult -- "$IW/files/noresult.csv"
plain_fail "intune: gird-report.ps1 says plainly when a file holds no Blindspot result, and where it looked" 'noresult.csv holds no Blindspot result. It looked in every column'
report_file open -- "$IW/files/open.csv"
plain_fail "intune: a quoted cell that is never closed stops the report in plain words, saving nothing" 'never closed'
report_file missing -- "$IW/files/nothere.csv"
plain_fail "intune: gird-report.ps1 says plainly when there is no file at the path" 'There is no file at'
report_file folder -- "$IW/files"
plain_fail "intune: gird-report.ps1 says plainly when it is given a folder" 'is a folder. Give the export file in it'
report_file empty -- "$IW/files/empty.csv"
plain_fail "intune: gird-report.ps1 says plainly when the file is empty" 'empty.csv is empty.'
report_file headeronly -- "$IW/files/headeronly.csv"
plain_fail "intune: gird-report.ps1 says plainly when the file lists no computers" 'lists no computers'
report_file workbook -- "$IW/files/workbook.csv"
plain_fail "intune: gird-report.ps1 says plainly when the file is an Excel workbook" 'is an Excel workbook, not a CSV file'
report_file binary -- "$IW/files/binary.csv"
plain_fail "intune: gird-report.ps1 says plainly when the file is not text" 'is not a text file'
# A file another program holds open with no sharing, as Excel does on Windows. PowerShell 7 on macOS
# refuses the second open too, so this runs off Windows.
cat > "$IW/hold.ps1" <<'PS'
param($File, $Report, $Pw, $Out)
$fs = New-Object IO.FileStream -ArgumentList $File, ([IO.FileMode]::Open), ([IO.FileAccess]::ReadWrite), ([IO.FileShare]::None)
try { & $Pw -NoProfile -NonInteractive -File $Report $File -OutDir $Out; exit $LASTEXITCODE } finally { $fs.Dispose() }
PS
rm -rf "$IW/out"; mkdir -p "$IW/out"
env -i PATH=/usr/bin:/bin HOME="$IW/home" PSModulePath="$IW/mods" "$PWSH" -NoProfile -NonInteractive -File "$IW/hold.ps1" "$IW/files/locked.csv" "$REPORT" "$PWSH" "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
plain_fail "intune: a file another program holds open says so in plain words" 'locked.csv is open in another program, such as Excel'
# Windows PowerShell before 5.1 cannot be run here, so the version check is taken from the file and
# run with the version it reads set to 4: it must be the script's first statement, and say it plainly.
cat > "$IW/oldps.ps1" <<'PS'
param($Report)
$ast = [Management.Automation.Language.Parser]::ParseFile($Report, [ref]$null, [ref]$null)
$first = $ast.EndBlock.Statements[0].Extent.Text
if (-not $first.StartsWith('if ($PSVersionTable.PSVersion.Major -lt 5)')) { 'the version check is not the first statement'; exit 9 }
$v = 4
. ([scriptblock]::Create($first.Replace('$PSVersionTable.PSVersion.Major', '$v')))
'went on past the version check'
PS
env -i PATH=/usr/bin:/bin HOME="$IW/home" "$PWSH" -NoProfile -NonInteractive -File "$IW/oldps.ps1" "$REPORT" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 2 ] && [ "$(cat "$IW/o.txt")" = 'This report needs Windows PowerShell 5.1 or PowerShell 7. This PowerShell is version 4.' ]; then
  ok "intune: an older PowerShell is told plainly which version it needs, before anything else runs"
else bad "intune: an older PowerShell is told plainly which version it needs, before anything else runs" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
report_file badopt -- "$IW/files/jamf.csv" -Colour red
plain_fail "intune: gird-report.ps1 says plainly when an option does not exist" 'There is no option -Colour'
report_file baddays -- "$IW/files/jamf.csv" -StaleDays many
plain_fail "intune: gird-report.ps1 says plainly when -StaleDays is not a number of days" 'StaleDays takes a number of days'
rm -rf "$IW/out"; mkdir -p "$IW/out"
report_run -- "$IW/files/jamf.csv" -NameColumn > "$IW/o.txt" 2>&1; RC=$?
plain_fail "intune: gird-report.ps1 says plainly when an option has no value" '-NameColumn needs a value after it'
if [ "$(id -u)" -ne 0 ]; then
  rm -rf "$IW/out" "$IW/ro"; mkdir -p "$IW/out" "$IW/ro"; chmod 555 "$IW/ro"
  report_run -- "$IW/files/plain.csv" -OutDir "$IW/ro" > "$IW/o.txt" 2>&1; RC=$?
  plain_fail "intune: gird-report.ps1 says plainly when it may not write the report" 'No permission to save the report in'
  chmod 755 "$IW/ro"
else skip "intune: gird-report.ps1 says plainly when it may not write the report" "root can write to any folder"; fi
report_run -- > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && grep -qF 'powershell -ExecutionPolicy Bypass -File .\gird-report.ps1 export.csv' "$IW/o.txt" && grep -qF 'pwsh ./gird-report.ps1 export.csv' "$IW/o.txt" && ! grep -qiE 'error|exception' "$IW/o.txt"; then
  ok "intune: gird-report.ps1 with nothing after it prints a short usage with the line to run, not an error"
else bad "intune: gird-report.ps1 with nothing after it prints a short usage with the line to run, not an error" "exit $RC: $(head -c 400 "$IW/o.txt")"; fi
intune_check < <(python3 tests/intune.py check files "$IW")
intune_check < <(python3 tests/intune.py check page "$IW")

# -OutDir: one path, resolved once from PowerShell's location, which is not the process's folder.
mkdir -p "$IW/loc/rel" "$IW/cwd/rel"
( cd "$IW/cwd" && env -i PATH=/usr/bin:/bin HOME="$IW/home" PSModulePath="$IW/mods" STUB_LOG="$IW/stub.log" \
    "$PWSH" -NoProfile -NonInteractive -Command "Set-Location -LiteralPath '$IW/loc'; & '$REPORT' '$IW/files/plain.csv' -OutDir rel; exit \$LASTEXITCODE" ) > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$(find "$IW/loc/rel" -maxdepth 1 \( -name 'blindspot-report-*.csv' -o -name 'blindspot-report-*.html' \) | grep -c .)" -eq 2 ] && [ -z "$(ls "$IW/cwd/rel")" ] && grep -q "^Report: $IW/loc/rel/blindspot-report-" "$IW/o.txt"; then
  ok "intune: a relative -OutDir is the folder PowerShell is in, for the check and the files alike"
else bad "intune: a relative -OutDir is the folder PowerShell is in, for the check and the files alike" "exit $RC; loc: $(ls "$IW/loc/rel" | tr '\n' ' '); cwd: $(ls "$IW/cwd/rel" | tr '\n' ' '); $(head -c 300 "$IW/o.txt")"; fi
rm -rf "$IW/out"; mkdir -p "$IW/out"
report_run -- "$IW/files/plain.csv" -OutDir 'Env:' > "$IW/o.txt" 2>&1; RC=$?
plain_fail "intune: an -OutDir that is not a folder on disk is refused in plain words" 'is not a folder on disk'
rm -rf "$IW/out" "$IW/elsewhere"; mkdir -p "$IW/out" "$IW/elsewhere"
python3 - "$IW/out" "$IW/elsewhere" <<'PY'
import datetime, os, sys
now = datetime.datetime.now(datetime.timezone.utc)
for m in (0, 1):
    stamp = (now + datetime.timedelta(minutes=m)).strftime('%Y%m%d-%H%M')
    for ext in ('csv', 'html'):
        os.symlink(os.path.join(sys.argv[2], '%d.%s' % (m, ext)), os.path.join(sys.argv[1], 'blindspot-report-%s.%s' % (stamp, ext)))
PY
report_run -- "$IW/files/plain.csv" -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ -z "$(ls "$IW/elsewhere")" ] && [ "$(find "$IW/out" -maxdepth 1 \( -name '*-2.csv' -o -name '*-2.html' \) | grep -c .)" -eq 2 ]; then
  ok "intune: gird-report.ps1 writes only new files, never through a name already there"
else bad "intune: gird-report.ps1 writes only new files, never through a name already there" "exit $RC; elsewhere: $(ls "$IW/elsewhere" | tr '\n' ' '); out: $(ls "$IW/out" | tr '\n' ' ')"; fi

# data/mitre.tsv: tools/gen.sh --check refuses a finding word with no line, and a line for no finding word.
gen_copy() { rm -rf "$IW/gen"; mkdir -p "$IW/gen/tools"; cp -R data "$IW/gen/data"; cp tools/gen.sh "$IW/gen/tools/"; cp gird-check.sh gird-check.ps1 gird-fleet.sh gird-report.ps1 gird-intune.ps1 "$IW/gen/"; }
gen_check() { bash "$IW/gen/tools/gen.sh" --check > "$IW/gen.txt" 2>&1; }
gen_copy; gen_check; RC=$?
if [ "$RC" -eq 0 ]; then ok "intune: gen.sh --check passes on a copy of the repository"; else bad "intune: gen.sh --check passes on a copy of the repository" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; awk -F '\t' '!($1 == "sessions" && $4 == "attack")' data/mitre.tsv > "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'no attack line for the finding word sessions' "$IW/gen.txt"; then ok "intune: gen.sh --check fails when a finding word has no ATT&CK line"
else bad "intune: gen.sh --check fails when a finding word has no ATT&CK line" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; awk -F '\t' '!($1 == "update-tools" && $4 == "atlas")' data/mitre.tsv > "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'no atlas line for the finding word update-tools' "$IW/gen.txt"; then ok "intune: gen.sh --check fails when a finding word has no ATLAS decision, not even none"
else bad "intune: gen.sh --check fails when a finding word has no ATLAS decision, not even none" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; awk -F '\t' '!($1 == "sessions" && $4 == "csf")' data/mitre.tsv > "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'no csf line for the finding word sessions' "$IW/gen.txt"; then ok "intune: gen.sh --check fails when a finding word has no NIST CSF decision"
else bad "intune: gen.sh --check fails when a finding word has no NIST CSF decision" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "keys" && $4 == "csf" { $7 = "Protect,Risk Assessment" } { print }' data/mitre.tsv > "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q '^data/mitre.tsv: keys	all	all	csf' "$IW/gen.txt"; then ok "intune: gen.sh --check fails on a CSF id filed under another Function"
else bad "intune: gen.sh --check fails on a CSF id filed under another Function" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
for _cf in 'GV.OC-01|Govern,Organizational Context' 'RS.MA-01|Respond,Incident Management' 'RC.RP-01|Recover,Incident Recovery Plan Execution'; do
  _dn="intune: gen.sh --check fails on a CSF outcome under ${_cf#*|}"; _dn=${_dn%%,*}
  gen_copy; awk -F '\t' -v id="${_cf%%|*}" -v tc="${_cf#*|}" 'BEGIN { OFS = "\t" } $1 == "keys" && $4 == "csf" { $5 = id; $7 = tc } { print }' data/mitre.tsv > "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
  if [ "$RC" -eq 2 ] && grep -q '^data/mitre.tsv: keys	all	all	csf' "$IW/gen.txt"; then ok "$_dn"; else bad "$_dn" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
done
# Every ID.RA-01 line renamed alike, so only the Category's name can refuse it.
gen_copy; awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "csf" && $5 == "ID.RA-01" { $7 = "Identify,Continuous Monitoring" } { print }' data/mitre.tsv > "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q '^data/mitre.tsv: keys	all	all	csf' "$IW/gen.txt"; then ok "intune: gen.sh --check fails on a CSF Category name that is not its id's"
else bad "intune: gen.sh --check fails on a CSF Category name that is not its id's" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; awk '{ print } /^  @\{ Word = .partial.;/ { print "  @{ Word = \047exfil\047; Arg = \047count\047; Level = \047review\047; Label = \047Data sent out\047 }" }' gird-report.ps1 > "$IW/gen/gird-report.ps1"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'no attack line for the finding word exfil' "$IW/gen.txt"; then ok "intune: gen.sh --check fails when the tool learns a finding word data/mitre.tsv has no line for"
else bad "intune: gen.sh --check fails when the tool learns a finding word data/mitre.tsv has no line for" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; sed "s/@{ Word = 'history'; Arg = 'count'/@{ Word = 'history'; Arg = 'number'/" gird-report.ps1 > "$IW/gen/gird-report.ps1"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q "an \$Items line it cannot read, or a word twice:   @{ Word = 'history'" "$IW/gen.txt"; then ok "intune: gen.sh --check fails on a finding word whose form the report does not know"
else bad "intune: gen.sh --check fails on a finding word whose form the report does not know" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; printf 'exfil\tall\tall\tattack\t-\t-\t-\tnone\t-\tA word no result carries.\n' >> "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q '^data/mitre.tsv: exfil' "$IW/gen.txt"; then ok "intune: gen.sh --check fails on a line for a finding word the tool does not know"
else bad "intune: gen.sh --check fails on a line for a finding word the tool does not know" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi
gen_copy; awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "keys" && $4 == "attack" { $9 = "https://example.com/techniques/T1552/001/" } { print }' data/mitre.tsv > "$IW/gen/data/mitre.tsv"; gen_check; RC=$?
if [ "$RC" -eq 2 ] && grep -q '^data/mitre.tsv: keys' "$IW/gen.txt"; then ok "intune: gen.sh --check fails on a link that is not the technique's MITRE page"
else bad "intune: gen.sh --check fails on a link that is not the technique's MITRE page" "exit $RC: $(head -c 300 "$IW/gen.txt")"; fi

# New-ReportFile, taken from the tool's own source and called directly: Test-Taken is not in the way.
rm -rf "$IW/nrf"; mkdir -p "$IW/nrf/gone"
printf 'keep' > "$IW/nrf/existing.csv"
ln -s "$IW/nrf/gone/target.csv" "$IW/nrf/dangling.csv"
"$PWSH" -NoProfile -NonInteractive -Command "
\$ErrorActionPreference = 'Stop'
\$ast = [Management.Automation.Language.Parser]::ParseFile('$REPORT', [ref]\$null, [ref]\$null)
\$fn = \$ast.Find({ param(\$n) \$n -is [Management.Automation.Language.FunctionDefinitionAst] -and \$n.Name -eq 'New-ReportFile' }, \$true)
. ([scriptblock]::Create(\$fn.Extent.Text))
foreach (\$name in 'existing.csv', 'dangling.csv') {
  try { New-ReportFile ('$IW/nrf/' + \$name) 'new text' \$true; 'wrote ' + \$name } catch { 'threw ' + \$name }
}
New-ReportFile '$IW/nrf/fresh.csv' 'abc' \$true
[IO.File]::ReadAllBytes('$IW/nrf/fresh.csv') -join ','
" > "$IW/nrf.txt" 2>&1
if grep -q '^threw existing.csv$' "$IW/nrf.txt" && grep -q '^threw dangling.csv$' "$IW/nrf.txt" && [ "$(cat "$IW/nrf/existing.csv")" = keep ] \
  && [ ! -e "$IW/nrf/gone/target.csv" ] && [ -z "$(ls "$IW/nrf/gone")" ]; then
  ok "intune: New-ReportFile throws on an existing file and on a dangling link, keeps the file and creates no link target"
else bad "intune: New-ReportFile throws on an existing file and on a dangling link, keeps the file and creates no link target" "$(head -c 300 "$IW/nrf.txt"); gone: $(ls "$IW/nrf/gone" | tr '\n' ' ')"; fi
# Get-InUseCodes, taken from the tool's source: errno 11 and 35 swap meanings between macOS and Linux.
"$PWSH" -NoProfile -NonInteractive -Command "
\$ast = [Management.Automation.Language.Parser]::ParseFile('$REPORT', [ref]\$null, [ref]\$null)
\$fn = \$ast.Find({ param(\$n) \$n -is [Management.Automation.Language.FunctionDefinitionAst] -and \$n.Name -eq 'Get-InUseCodes' }, \$true)
. ([scriptblock]::Create(\$fn.Extent.Text))
'mac=' + (@(Get-InUseCodes 'Unix' 'Darwin 25.5.0 Darwin Kernel Version 25.5.0') -join ',')
'linux=' + (@(Get-InUseCodes 'Unix' 'Linux 6.8.0-45-generic #45-Ubuntu SMP') -join ',')
'win=' + (@(Get-InUseCodes 'Win32NT' '') -join ',')
'other=' + (@(Get-InUseCodes 'Unix' 'FreeBSD 14.1') -join ',')
" > "$IW/inuse.txt" 2>&1
if [ "$(tr -d '\r' < "$IW/inuse.txt")" = "$(printf 'mac=35\nlinux=11\nwin=-2147024864,-2147024863\nother=')" ]; then
  ok "intune: a file open in another program is told by the code of this system only: 35 on macOS, 11 on Linux"
else bad "intune: a file open in another program is told by the code of this system only: 35 on macOS, 11 on Linux" "$(head -c 300 "$IW/inuse.txt")"; fi
if grep -q '^239,187,191,97,98,99$' "$IW/nrf.txt"; then ok "intune: New-ReportFile writes the byte order mark and then the text"
else bad "intune: New-ReportFile writes the byte order mark and then the text" "$(tail -c 200 "$IW/nrf.txt")"; fi

if [ "$INTUNE_ALONE" -eq 1 ]; then finish; else intune_cleanup; fi
