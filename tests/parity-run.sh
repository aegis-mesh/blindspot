#!/usr/bin/env bash
# Runs both suites, one after the other, each recording its test names, then compares the two
# lists with tests/parity.sh: every bash test needs a PowerShell twin or a line in
# tests/bash-only.txt. Run it before a pull request. The suites run gird-check.sh and
# gird-check.ps1 offline or against their local mock only.
#
#   PWSH=/path/to/pwsh bash tests/parity-run.sh
set -u
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d 2>/dev/null || mktemp -d -t parity-run)
trap 'rm -rf "$W"' EXIT
RC=0
echo "== tests/run.sh"
PARITY_LOG="$W/bash.txt" bash tests/run.sh > "$W/run.log" 2>&1; r=$?
grep -a "passed, " "$W/run.log"; [ "$r" -eq 0 ] || { RC=1; grep -a -A3 '^  FAIL' "$W/run.log"; }
echo "== tests/run-ps.sh"
PARITY_LOG="$W/ps.txt" bash tests/run-ps.sh > "$W/run-ps.log" 2>&1; r=$?
grep -a "passed, " "$W/run-ps.log"; [ "$r" -eq 0 ] || { RC=1; grep -a -A3 '^  FAIL' "$W/run-ps.log"; }
echo "== tests/parity.sh"
bash tests/parity.sh "$W/bash.txt" "$W/ps.txt" tests/bash-only.txt || RC=1
exit "$RC"
