#!/usr/bin/env bash
# Keeps the two test suites in step, from the names they record as they run: every test that
# tests/run.sh (gird-check.sh) ran or skipped needs a test of the same name in tests/run-ps.sh
# (gird-check.ps1), or a line in tests/bash-only.txt: the name, a tab, and why it can't or need
# not run for PowerShell. PowerShell tests with no bash twin are listed, not failed.
#
#   bash tests/parity.sh BASH_NAMES PS_NAMES [bash-only.txt]
#
# The lists come from running the suites with PARITY_LOG set (tests/lib.sh writes one name per
# test, run, failed or skipped); tests/parity-run.sh does both runs and calls this. It fails when:
#   - a list is missing or empty, or names a test twice (each test reports once);
#   - a bash test has no PowerShell twin and no bash-only line;
#   - a bash-only line has no tab and reason, is listed twice, names no bash test, or names one
#     that has a twin.
# Before names are compared, "bash 3: " and the like are dropped (tests/run.sh runs its first
# section once per bash), "perl: " and "net: " become "<engine>: " (perl is gird-check.sh's own
# session engine, .NET is gird-check.ps1's), and gird-check.ps1's options are written as
# gird-check.sh's: -Offline is --offline.
set -u
BL=${1:-}; PL=${2:-}; ONLY=${3:-$(dirname "$0")/bash-only.txt}
FAIL=0
for f in "$BL" "$PL"; do
  if [ -z "$f" ] || [ ! -f "$f" ]; then echo "  no list of test names: ${f:-(none given)}. Run tests/parity-run.sh, or the suites with PARITY_LOG set."; exit 1; fi
  if [ ! -s "$f" ]; then echo "  the list of test names is empty: $f"; exit 1; fi
done
[ -f "$ONLY" ] || { echo "  $ONLY not found"; exit 1; }
W=$(mktemp -d 2>/dev/null || mktemp -d -t parity)
trap 'rm -rf "$W"' EXIT
T=$(printf '\t')
for x in "bash:$BL" "PowerShell:$PL"; do
  d=$(LC_ALL=C sort "${x#*:}" | LC_ALL=C uniq -d)
  if [ -n "$d" ]; then FAIL=1; printf '%s\n' "$d" | sed "s/^/  reported twice in the ${x%%:*} run: /"; fi
done
norm() { # one name per line in, the name parity compares out
  LC_ALL=C sed -e 's/^bash [0-9][0-9]*: //' -e 's/^perl: /<engine>: /' -e 's/^net: /<engine>: /' \
    -e 's/ -Offline\([ ,]\)/ --offline\1/g' -e 's/ -Offline$/ --offline/' -e 's/^-Offline /--offline /' \
    -e 's/^-Help /--help /' -e 's/^-Full /--full /' -e 's/^-Save /--save /' \
    -e 's/ -AllSessions\([ ,]\)/ --all-sessions\1/g' | LC_ALL=C sort -u
}
norm < "$BL" > "$W/bash"; norm < "$PL" > "$W/ps"
grep -v '^#' "$ONLY" | grep -v '^[[:space:]]*$' > "$W/only-lines" || true
while IFS= read -r l; do
  case "$l" in
    *"$T"*) r=${l#*"$T"}; [ -n "$(printf '%s' "$r" | tr -d ' \t')" ] || { echo "  bash-only.txt gives no reason: ${l%%"$T"*}"; FAIL=1; } ;;
    *) echo "  bash-only.txt needs the name, a tab and the reason: $l"; FAIL=1 ;;
  esac
done < "$W/only-lines"
cut -f1 "$W/only-lines" | LC_ALL=C sort > "$W/only-all"
d=$(LC_ALL=C uniq -d "$W/only-all")
if [ -n "$d" ]; then FAIL=1; printf '%s\n' "$d" | sed 's/^/  bash-only.txt lists twice: /'; fi
LC_ALL=C sort -u "$W/only-all" > "$W/only"
# bash tests with neither a twin nor a bash-only line
LC_ALL=C comm -23 "$W/bash" "$W/ps" | LC_ALL=C comm -23 - "$W/only" > "$W/missing"
LC_ALL=C comm -23 "$W/only" "$W/bash" > "$W/stale"
LC_ALL=C comm -12 "$W/only" "$W/ps" | LC_ALL=C comm -12 - "$W/bash" > "$W/twinned"
LC_ALL=C comm -13 "$W/bash" "$W/ps" > "$W/psonly"
sed 's/^/  no PowerShell twin: /' "$W/missing"
sed 's/^/  bash-only.txt names a test run.sh does not have: /' "$W/stale"
sed 's/^/  bash-only.txt lists a test run-ps.sh has, remove the line: /' "$W/twinned"
if [ -s "$W/missing" ] || [ -s "$W/stale" ] || [ -s "$W/twinned" ]; then FAIL=1; fi
echo "  $(grep -c '' < "$BL") names from run.sh, $(grep -c '' < "$PL") from run-ps.sh, $(grep -c '' < "$W/only") bash-only"
if [ -s "$W/psonly" ]; then
  echo "  $(grep -c '' < "$W/psonly") PowerShell tests with no bash twin:"
  sed 's/^/    /' "$W/psonly"
fi
exit "$FAIL"
