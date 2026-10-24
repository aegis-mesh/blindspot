#!/usr/bin/env bash
# Keeps the two test suites in step, from the names they record as they run: every test that
# tests/run.sh (gird-check.sh) ran or skipped needs a test of the same name in tests/run-ps.sh
# (gird-check.ps1), or a line in tests/bash-only.txt: the name, a tab, and why it can't or need
# not run for PowerShell. PowerShell tests with no bash twin are listed, not failed.
#
#   bash tests/parity.sh BASH_NAMES PS_NAMES [bash-only.txt [ps-skips.txt]]
#
# The lists come from running the suites with PARITY_LOG set (tests/lib.sh writes one line per
# test: its name, or "S<tab>name" when it was skipped); tests/parity-run.sh does both runs and
# calls this. A skipped PowerShell test is a twin only where bash did not run its test either,
# or where tests/ps-skips.txt says why gird-check.ps1's test can't run there. It fails when:
#   - a list is missing or empty, or names a test twice (each test reports once);
#   - a bash test has no PowerShell twin and no bash-only line;
#   - PowerShell skipped a test bash ran, and ps-skips.txt does not list it;
#   - a bash-only or ps-skips line has no tab and reason, is listed twice, or names no test of
#     its suite, or a bash-only line names a test that has a twin.
# Before names are compared, "bash 3: " and the like are dropped (tests/run.sh runs its first
# section once per bash), "perl: " and "net: " become "<engine>: " (perl is gird-check.sh's own
# session engine, .NET is gird-check.ps1's), and gird-check.ps1's options are written as
# gird-check.sh's: -Offline is --offline.
set -u
BL=${1:-}; PL=${2:-}; ONLY=${3:-$(dirname "$0")/bash-only.txt}; PSK=${4:-$(dirname "$0")/ps-skips.txt}
FAIL=0
for f in "$BL" "$PL"; do
  if [ -z "$f" ] || [ ! -f "$f" ]; then echo "  no list of test names: ${f:-(none given)}. Run tests/parity-run.sh, or the suites with PARITY_LOG set."; exit 1; fi
  if [ ! -s "$f" ]; then echo "  the list of test names is empty: $f"; exit 1; fi
done
for f in "$ONLY" "$PSK"; do [ -f "$f" ] || { echo "  $f not found"; exit 1; }; done
W=$(mktemp -d 2>/dev/null || mktemp -d -t parity)
trap 'rm -rf "$W"' EXIT
T=$(printf '\t')
for x in "bash:$BL" "PowerShell:$PL"; do
  d=$(sed "s/^S$T//" "${x#*:}" | LC_ALL=C sort | LC_ALL=C uniq -d)
  if [ -n "$d" ]; then FAIL=1; printf '%s\n' "$d" | sed "s/^/  reported twice in the ${x%%:*} run: /"; fi
done
norm() { # one name per line in, the name parity compares out
  LC_ALL=C sed -e 's/^bash [0-9][0-9]*: //' -e 's/^perl: /<engine>: /' -e 's/^net: /<engine>: /' \
    -e 's/ -Offline\([ ,]\)/ --offline\1/g' -e 's/ -Offline$/ --offline/' -e 's/^-Offline /--offline /' \
    -e 's/^-Help /--help /' -e 's/^-Full /--full /' -e 's/^-Save /--save /' \
    -e 's/ -AllSessions\([ ,]\)/ --all-sessions\1/g' | LC_ALL=C sort -u
}
sed "s/^S$T//" "$BL" | norm > "$W/bash"; sed "s/^S$T//" "$PL" | norm > "$W/ps"
grep -v "^S$T" "$BL" | norm > "$W/bash-ran"; sed -n "s/^S$T//p" "$PL" | norm > "$W/ps-skipped"
reasons() { # file label out: checks name<tab>reason lines, writes the sorted names
  grep -v '^#' "$1" | grep -v '^[[:space:]]*$' > "$W/lines" || true
  while IFS= read -r l; do
    case "$l" in
      *"$T"*) r=${l#*"$T"}; [ -n "$(printf '%s' "$r" | tr -d ' \t')" ] || { echo "  $2 gives no reason: ${l%%"$T"*}"; FAIL=1; } ;;
      *) echo "  $2 needs the name, a tab and the reason: $l"; FAIL=1 ;;
    esac
  done < "$W/lines"
  cut -f1 "$W/lines" | LC_ALL=C sort > "$W/all"
  d=$(LC_ALL=C uniq -d "$W/all")
  if [ -n "$d" ]; then FAIL=1; printf '%s\n' "$d" | sed "s/^/  $2 lists twice: /"; fi
  norm < "$W/all" > "$3"
}
reasons "$ONLY" bash-only.txt "$W/only"
reasons "$PSK" ps-skips.txt "$W/psk"
LC_ALL=C comm -12 "$W/ps-skipped" "$W/bash-ran" | LC_ALL=C comm -23 - "$W/psk" > "$W/badskip"
LC_ALL=C comm -23 "$W/psk" "$W/ps" > "$W/psk-stale"
sed 's/^/  PowerShell skipped a test bash ran, and ps-skips.txt does not say why: /' "$W/badskip"
sed 's/^/  ps-skips.txt names a test run-ps.sh does not have: /' "$W/psk-stale"
if [ -s "$W/badskip" ] || [ -s "$W/psk-stale" ]; then FAIL=1; fi
# bash tests with neither a twin nor a bash-only line
LC_ALL=C comm -23 "$W/bash" "$W/ps" | LC_ALL=C comm -23 - "$W/only" > "$W/missing"
LC_ALL=C comm -23 "$W/only" "$W/bash" > "$W/stale"
LC_ALL=C comm -12 "$W/only" "$W/ps" | LC_ALL=C comm -12 - "$W/bash" > "$W/twinned"
LC_ALL=C comm -13 "$W/bash" "$W/ps" > "$W/psonly"
sed 's/^/  no PowerShell twin: /' "$W/missing"
sed 's/^/  bash-only.txt names a test run.sh does not have: /' "$W/stale"
sed 's/^/  bash-only.txt lists a test run-ps.sh has, remove the line: /' "$W/twinned"
if [ -s "$W/missing" ] || [ -s "$W/stale" ] || [ -s "$W/twinned" ]; then FAIL=1; fi
echo "  $(grep -c '' < "$BL") names from run.sh, $(grep -c '' < "$PL") from run-ps.sh, $(grep -c '' < "$W/only") bash-only, $(grep -c '' < "$W/psk") PowerShell skips with a reason"
if [ -s "$W/psonly" ]; then
  echo "  $(grep -c '' < "$W/psonly") PowerShell tests with no bash twin:"
  sed 's/^/    /' "$W/psonly"
fi
exit "$FAIL"
