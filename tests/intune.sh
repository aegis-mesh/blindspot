#!/usr/bin/env bash
# Tests gird-intune.ps1 against a local stand-in for Microsoft Graph: a stub
# Microsoft.Graph.Authentication module whose Invoke-MgGraphRequest sends each call to a mock
# server on 127.0.0.1, never to a real tenant. tests/run-ps.sh sources this; on its own:
#
#   PWSH=/path/to/pwsh bash tests/intune.sh
#
# The values -Report reads are the ones gird-fleet.sh and gird-fleet.ps1 write: tests/intune.py
# lists every form, and the writers are run here too, each with a stand-in for the account run, so
# the reader and the writers cannot drift apart unseen. gird-fleet.ps1 runs when it is next to
# gird-intune.ps1, or at INTUNE_FLEET_PS1.
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
INTUNE_PID=""
intune_cleanup() { [ -n "$INTUNE_PID" ] && { kill "$INTUNE_PID"; wait "$INTUNE_PID"; } 2>/dev/null; chmod -R u+w "$IW" 2>/dev/null; rm -rf "$IW"; INTUNE_PID=""; }
[ "$INTUNE_ALONE" -eq 1 ] && trap intune_cleanup EXIT

echo "gird-intune.ps1"
if LC_ALL=C grep -q '[^ -~]' "$TOOL"; then bad "intune: the tool is plain ASCII"; else ok "intune: the tool is plain ASCII"; fi
sed -e 's/#.*$//' -e "s/'[^']*'//g" -e 's/"[^"]*"//g' "$TOOL" > "$IW/code.txt"
hasnot "intune: no PowerShell 7 only syntax" '\?\?|\?\.|&&|\|\||-Parallel|-AsHashtable|\$Is(Windows|MacOS|Linux)\b|-SkipHttpErrorCheck' "$IW/code.txt"
hasnot "intune: talks to nothing but Microsoft Graph" 'Invoke-WebRequest|Invoke-RestMethod|WebClient|HttpClient|WebRequest\]|Start-Process|Net\.Sockets' "$IW/code.txt"
hasnot "intune: defines no function that hides a PowerShell command" '^function (ConvertTo-Html|ConvertTo-Csv|Get-Content|Write-Host|Out-File|Get-Item|Test-Path)\b' "$TOOL"
if "$PWSH" -NoProfile -NonInteractive -Command "\$e = \$null; [void][Management.Automation.Language.Parser]::ParseFile('$TOOL', [ref]\$null, [ref]\$e); if (\$e.Count) { \$e | ForEach-Object { \$_.Message }; exit 1 }" > "$IW/parse.txt" 2>&1
then ok "intune: parses"; else bad "intune: parses" "$(head -n 3 "$IW/parse.txt")"; fi

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
# report TENANT [env...]: runs -Report on a fresh tenant and keeps its output, files and requests by name
intune_report() {
  _t=$1; shift
  intune_state "$_t"
  rm -rf "$IW/out"; mkdir -p "$IW/out"
  intune_run "$@" -- -Report -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
  if [ "$RC" -eq 0 ]; then ok "intune: -Report with the $_t tenant exits 0"; else bad "intune: -Report with the $_t tenant exits 0" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
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
intune_run PSModulePath="$IW/oldmods" -- -Report > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 3 ] && grep -q 'too old for this tool' "$IW/o.txt" && grep -q 'Update-Module Microsoft.Graph.Authentication' "$IW/o.txt" && [ ! -s "$IW/stub.log" ]; then
  ok "intune: a Graph module too old for its sign-in says so plainly and stops before signing in"
else bad "intune: a Graph module too old for its sign-in says so plainly and stops before signing in" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi

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

FLEETSH=$PWD/gird-fleet.sh; WS=$IW/wsh; U=$(id -u)
wsh_users() { # name:mode:home:shell:uid ... (home, shell and uid optional)
  rm -rf "$WS"; mkdir -p "$WS/modes" "$WS/tmp"; : > "$WS/users.tsv"
  for _e in "$@"; do
    IFS=: read -r _n _m _h _s _u <<< "$_e"
    [ -n "$_h" ] || { _h="$WS/h-$_n"; mkdir -p "$_h"; }
    printf '%s\t%s\t%s\t%s\n' "$_n" "${_u:-$U}" "$_h" "${_s:-/bin/zsh}" >> "$WS/users.tsv"
    [ -n "$_m" ] && printf '%s' "$_m" > "$WS/modes/$_n"
  done
}
wsh_run() { # fleet options...: one --all-users run, then the --inventory line an MDM reads
  GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_USERS="$WS/users.tsv" GIRD_CHECK_FLEET_LAUNCH="$IW/launch.sh" GIRD_CHECK_FLEET_STATE="$WS/state" \
    GIRD_CHECK_FLEET_SHARED_TMP="$WS/tmp" INTUNE_MODES="$WS/modes" INTUNE_FLAVOUR=sh /bin/bash "$FLEETSH" --all-users "$@" < /dev/null > "$WS/run.out" 2>&1
  wsh_inv
}
wsh_inv() { GIRD_CHECK_FLEET_ROOT=1 GIRD_CHECK_FLEET_STATE="$WS/state" /bin/bash "$FLEETSH" --inventory 2>&1 | head -n 1; }
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
  wps act "cut to fit" "^v1 act $T other_profiles=0 \| [^ ]+: act wiper; incidents [a-z0-9,]+ \+more$" huge
  wps not_checked "output it does not read" "$P0 \| [^ ]+: not_checked bad_output$" garbage
  wps failed "an account run with no output" "^v1 failed $T other_profiles=0 reason=no_output \| [^ ]+: not_checked no_output$" empty
  wps failed "an account run in the reduced language" "^v1 failed $T other_profiles=0 reason=language_mode \| [^ ]+: not_checked language_mode$" language
  wps not_checked "an account run that sends markers in a shared folder" "$P0 \| [^ ]+: not_checked bad_output$" tmpmarks
  wps failed "an account run that does not start" "^v1 failed $T other_profiles=0 reason=start \| [^ ]+: not_checked start$" clear GIRD_CHECK_FLEET_LAUNCH="$IW/no-such-launcher"
  wps not_checked "the deadline first" "$P0 \| [^ ]+: not_checked deadline$" clear -- -Deadline 3
  wps not_checked "out of time" "$P0 \| [^ ]+: not_checked time_limit$" sleep -- -Deadline 10
  : > "$IW/notafolder"
  wps failed "nowhere to save" "^v1 failed $T other_profiles=0 reason=save \| [^ ]+: not_checked save$" clear LOCALAPPDATA="$IW/notafolder"
  rm -rf "$WP"; mkdir -p "$WP/run" "$WP/local"; cp "$FLEETPS" "$WP/run/gird-fleet.ps1"
  _v=$(env -i PATH=/usr/bin:/bin HOME="$WP" LOCALAPPDATA="$WP/local" GIRD_CHECK_FLEET_TEST=1 "$PWSH" -NoProfile -NonInteractive -File "$WP/run/gird-fleet.ps1" 2>/dev/null | head -n 1)
  form failed "gird-fleet.ps1 run: no gird-check.ps1 to unpack" "^v1 failed $T other_profiles=0 reason=unpack \| [^ ]+: not_checked unpack$" "$_v"
fi

intune_report forms
intune_check < <(python3 tests/intune.py check forms "$IW")

intune_report report
if [ "$(intune_writes)" -eq 0 ]; then ok "intune: -Report changes nothing in Intune"; else bad "intune: -Report changes nothing in Intune" "$(intune_writes) writes"; fi
intune_check < <(python3 tests/intune.py check report "$IW")

for _tn in silent usergroup othertarget exclusion alldevices filter membererror exclerror exclhidden unassigned; do intune_report "$_tn"; done
intune_report nodeviceid STUB_DENY=Device.Read.All
intune_check < <(python3 tests/intune.py check silent "$IW")

intune_state badnext
rm -rf "$IW/out"; mkdir -p "$IW/out"
intune_run -- -Report -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && ! grep -q '^refused' "$IW/stub.log" && [ -z "$(ls "$IW/out")" ]; then
  ok "intune: -Report stops, saving nothing, at a next-page link to another address"
else bad "intune: -Report stops, saving nothing, at a next-page link to another address" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi

intune_state novalue
rm -rf "$IW/out"; mkdir -p "$IW/out"
intune_run -- -Report -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'Stopped: Microsoft Graph sent a page of results with no list in it' "$IW/o.txt" && ! grep -q 'Stopped: Stopped' "$IW/o.txt" && [ -z "$(ls "$IW/out")" ]; then
  ok "intune: -Report stops, saving nothing, at a page with no list of results"
else bad "intune: -Report stops, saving nothing, at a page with no list of results" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi

# -OutDir: one path, resolved once from PowerShell's location, which is not the process's folder.
intune_state report
mkdir -p "$IW/loc/rel" "$IW/cwd/rel"
( cd "$IW/cwd" && env -i PATH=/usr/bin:/bin HOME="$IW/home" PSModulePath="$IW/mods" STUB_GRAPH="http://127.0.0.1:$PORT" STUB_LOG="$IW/stub.log" \
    "$PWSH" -NoProfile -NonInteractive -Command "Set-Location -LiteralPath '$IW/loc'; & '$TOOL' -Report -OutDir rel; exit \$LASTEXITCODE" ) > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$(ls "$IW/loc/rel" | grep -c '^blindspot-intune-.*\.\(csv\|html\)$')" -eq 2 ] && [ -z "$(ls "$IW/cwd/rel")" ] && grep -q "^Saved: $IW/loc/rel/blindspot-intune-" "$IW/o.txt"; then
  ok "intune: a relative -OutDir is the folder PowerShell is in, for the check and the files alike"
else bad "intune: a relative -OutDir is the folder PowerShell is in, for the check and the files alike" "exit $RC; loc: $(ls "$IW/loc/rel" | tr '\n' ' '); cwd: $(ls "$IW/cwd/rel" | tr '\n' ' '); $(head -c 300 "$IW/o.txt")"; fi
: > "$IW/requests.log"; : > "$IW/stub.log"
intune_run -- -Report -OutDir 'Env:' > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'is not a folder on disk' "$IW/o.txt" && [ ! -s "$IW/stub.log" ]; then
  ok "intune: an -OutDir that is not a folder on disk is refused before signing in"
else bad "intune: an -OutDir that is not a folder on disk is refused before signing in" "exit $RC: $(head -c 300 "$IW/o.txt")"; fi
rm -rf "$IW/out" "$IW/elsewhere"; mkdir -p "$IW/out" "$IW/elsewhere"
python3 - "$IW/out" "$IW/elsewhere" <<'PY'
import datetime, os, sys
now = datetime.datetime.now(datetime.timezone.utc)
for m in (0, 1):
    stamp = (now + datetime.timedelta(minutes=m)).strftime('%Y%m%d-%H%M')
    for ext in ('csv', 'html'):
        os.symlink(os.path.join(sys.argv[2], '%d.%s' % (m, ext)), os.path.join(sys.argv[1], 'blindspot-intune-%s.%s' % (stamp, ext)))
PY
intune_run -- -Report -OutDir "$IW/out" > "$IW/o.txt" 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ -z "$(ls "$IW/elsewhere")" ] && [ "$(ls "$IW/out" | grep -c -- '-2\.\(csv\|html\)$')" -eq 2 ]; then
  ok "intune: -Report writes only new files, never through a name already there"
else bad "intune: -Report writes only new files, never through a name already there" "exit $RC; elsewhere: $(ls "$IW/elsewhere" | tr '\n' ' '); out: $(ls "$IW/out" | tr '\n' ' ')"; fi
fi

if [ "$INTUNE_ALONE" -eq 1 ]; then finish; else intune_cleanup; fi
