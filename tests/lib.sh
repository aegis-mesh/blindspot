# shellcheck shell=bash
# The result helpers both suites use (tests/run.sh, tests/run-ps.sh). Every result goes through
# ok, bad or skip, and each writes its test's name to $PARITY_LOG when it is set, one line per
# test, so tests/parity.sh can compare what the two suites test. A test that can't run on this
# machine still records its name: it calls skip, or runs with SKIPPING set to the reason.
#
#   ok NAME [DETAIL]    bad NAME [DETAIL]    skip NAME WHY
#   has NAME REGEX FILE    hasnot NAME REGEX FILE    hasi NAME REGEX FILE    nokeys NAME KEYS FILE
#
# NAME is the test's name and nothing else; a measured value or the reason it failed goes in
# DETAIL, which is printed and not recorded. PFX, when set, starts every name (the bash version
# in tests/run.sh's per-bash loop).
PASS=0; FAIL=0; SKIP=0; SKIPPING=""; PFX=""
[ -z "${PARITY_LOG:-}" ] || : > "$PARITY_LOG"
record() { [ -z "${PARITY_LOG:-}" ] || printf '%s\n' "$PFX$1" >> "$PARITY_LOG"; }
skip() { SKIP=$((SKIP + 1)); record "$1"; printf '  skip  %s: %s\n' "$PFX$1" "$2"; }
ok() {
  if [ -n "$SKIPPING" ]; then skip "$1" "$SKIPPING"; return; fi
  PASS=$((PASS + 1)); record "$1"; printf '  ok    %s%s\n' "$PFX$1" "${2:+ ($2)}"
}
bad() {
  if [ -n "$SKIPPING" ]; then skip "$1" "$SKIPPING"; return; fi
  FAIL=$((FAIL + 1)); record "$1"; printf '  FAIL  %s\n' "$PFX$1"; [ -z "${2:-}" ] || printf '        %s\n' "$2"
}
has()    { if [ -n "$SKIPPING" ]; then skip "$1" "$SKIPPING"; elif grep -aqE -- "$2" "$3"; then ok "$1"; else bad "$1" "wanted: $2"; fi; }
hasnot() { if [ -n "$SKIPPING" ]; then skip "$1" "$SKIPPING"; elif grep -aqE -- "$2" "$3"; then bad "$1" "found: $2"; else ok "$1"; fi; }
hasi()   { if [ -n "$SKIPPING" ]; then skip "$1" "$SKIPPING"; elif grep -aqiE -- "$2" "$3"; then ok "$1"; else bad "$1" "wanted: $2"; fi; }
nokeys() { if [ -n "$SKIPPING" ]; then skip "$1" "$SKIPPING"; elif grep -aqF -f "$2" "$3"; then bad "$1"; else ok "$1"; fi; }
# The suite's last line. A result reported outside these helpers' shell (in a subshell or a pipe)
# leaves the recorded names and the counts apart, and that fails too.
finish() {
  echo
  echo "$PASS passed, $FAIL failed, $SKIP skipped"
  if [ -n "${PARITY_LOG:-}" ]; then
    _n=$(grep -c '' "$PARITY_LOG")
    if [ "$_n" -ne $((PASS + FAIL + SKIP)) ]; then
      echo "  FAIL  $PARITY_LOG has $_n names for $((PASS + FAIL + SKIP)) results: a test reported outside tests/lib.sh"; return 1
    fi
  fi
  [ "$FAIL" -eq 0 ]
}
