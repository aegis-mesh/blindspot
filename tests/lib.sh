# shellcheck shell=bash
# The result helpers both suites use (tests/run.sh, tests/run-ps.sh). Every result goes through
# ok, bad or skip, and each writes its test's name to $PARITY_LOG when it is set, one line per
# test, so tests/parity.sh can compare what the two suites test. A test that can't run on this
# machine still records its name: it calls skip, or runs with SKIPPING set to the reason. A skip
# is recorded as "S<tab>name", so parity.sh can tell a skipped twin from one that ran.
# PARITY_LOG must name an empty or new file: one that already holds names is refused, so a child
# that sources this with the parent's PARITY_LOG exported can't wipe or add to its list.
# Unsetting or emptying PARITY_LOG part-way through a suite turns recording and the count check off.
#
#   ok NAME [DETAIL]    bad NAME [DETAIL]    skip NAME WHY
#   has NAME REGEX FILE    hasnot NAME REGEX FILE    hasi NAME REGEX FILE    nokeys NAME KEYS FILE
#
# NAME is the test's name and nothing else; a measured value or the reason it failed goes in
# DETAIL, which is printed and not recorded. PFX, when set, starts every name (the bash version
# in tests/run.sh's per-bash loop).
PASS=0; FAIL=0; SKIP=0; SKIPPING=""; PFX=""
if [ -n "${PARITY_LOG:-}" ] && [ -s "$PARITY_LOG" ]; then
  echo "tests/lib.sh: PARITY_LOG ($PARITY_LOG) already holds names; give each suite run a new file" >&2; exit 1
fi
record() { [ -z "${PARITY_LOG:-}" ] || printf '%s\n' "$PFX$1" >> "$PARITY_LOG"; }
skip() { SKIP=$((SKIP + 1)); [ -z "${PARITY_LOG:-}" ] || printf 'S\t%s\n' "$PFX$1" >> "$PARITY_LOG"; printf '  skip  %s: %s\n' "$PFX$1" "$2"; }
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
# Prints PATH with every folder that holds a hosted platform's CLI (data/platforms.tsv) swapped for a
# folder under DIR of links to everything else in it, so a CLI installed on the tester's machine never
# shows in a report. A test that wants one puts its own fake ahead of PATH.
#   PATH=$(hide_platform_clis DIR)
hide_platform_clis() {
  _hc=" $(awk -F '\t' '!/^#/ && NF > 2 && $3 != "-" { printf "%s ", $3 }' data/platforms.tsv)"
  # Split by hand, not by IFS: a folder name with * or ? stays as it is, and empty entries are kept.
  # A folder that is relative or can't be listed is kept whole: linking only part of it would hide
  # tools the tests need.
  _hp=""; _hn=0; _hrest=$PATH; _hfirst=1
  while :; do
    _hd=${_hrest%%:*}; _hhit=0
    for _hx in $_hc; do case "$_hd" in /*) [ -r "$_hd" ] && [ -e "$_hd/$_hx" ] && _hhit=1 ;; esac; done
    if [ "$_hhit" -eq 1 ]; then
      _hn=$((_hn + 1)); mkdir -p "$1/$_hn"
      for _hf in "$_hd"/* "$_hd"/.[!.]*; do
        _hb=${_hf##*/}
        case "$_hc" in *" $_hb "*) ;; *) [ -e "$_hf" ] && ln -s "$_hf" "$1/$_hn/$_hb" ;; esac
      done
      _hd=$1/$_hn
    fi
    if [ "$_hfirst" -eq 1 ]; then _hp=$_hd; _hfirst=0; else _hp="$_hp:$_hd"; fi
    case "$_hrest" in *:*) _hrest=${_hrest#*:} ;; *) break ;; esac
  done
  printf '%s\n' "$_hp"
}
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
