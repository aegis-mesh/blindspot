#!/usr/bin/env bash
# Keeps the two test suites in step: every test in tests/run.sh (gird-check.sh) needs a test of
# the same name in tests/run-ps.sh (gird-check.ps1), or a line in tests/bash-only.txt, the name,
# a tab and why it can't or need not run for PowerShell. A name used N times in run.sh needs N
# twins, less the bash-only lines that name it. PowerShell tests with no bash twin are listed,
# not failed. Both suites run this as their test "the two suites test the same things".
#
#   bash tests/parity.sh [run.sh run-ps.sh bash-only.txt]
#
# Names are read from the has, hasnot, hasi, ok, nokeys and gen_refuses calls, and, for each
# "payload_checks MODE" call, from that mode's check() calls in tests/payload.py. Then:
#   - a trailing "($...)" is dropped: it carries a measured value, not the test;
#   - "bash $V: " is dropped, and "$E: ", "perl: " and "net: " become "<engine>: " (perl is
#     gird-check.sh's own session engine, .NET is gird-check.ps1's);
#   - $VAR is filled in from that file's "for VAR in ...; do" list, one name per value;
#   - gird-check.ps1's options are written as gird-check.sh's: -Offline is --offline.
# A name that still holds a $ can't be compared, and fails.
set -u
cd "$(dirname "$0")/.." || exit 1
RUN=${1:-tests/run.sh}; RUNPS=${2:-tests/run-ps.sh}; ONLY=${3:-tests/bash-only.txt}; PAY=tests/payload.py
for f in "$RUN" "$RUNPS" "$ONLY" "$PAY"; do [ -f "$f" ] || { echo "  parity: $f not found"; exit 1; }; done

names() { # suite: one normalised test name per line
  LC_ALL=C awk -v pay="$PAY" '
    function words(s, out,   n, w, c, q, i, inw) { # a shell word list: plain and quoted words
      n = 0; w = ""; q = ""; inw = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == q) q = ""; else w = w c; continue }
        if (c == "\047" || c == "\"") { q = c; inw = 1; continue }
        if (c == " " || c == "\t") { if (inw) { out[++n] = w; w = ""; inw = 0 } continue }
        w = w c; inw = 1
      }
      if (inw) out[++n] = w
      return n
    }
    function kebab(o,   i, c, k) { k = ""; for (i = 1; i <= length(o); i++) { c = substr(o, i, 1); if (c ~ /[A-Z]/) k = k (i > 1 ? "-" : "") tolower(c); else k = k c }; return k }
    function emit(nm,   i, v, n, vals, rest, o) {
      if (nm == "$1" || nm == "$label") return
      sub(/ \(\$.*$/, "", nm)
      sub(/^bash \$V: /, "", nm)
      sub(/^(\$E|perl|net): /, "<engine>: ", nm)
      if (match(nm, /\$[A-Za-z_]+/) && substr(nm, RSTART - 1, 1) != "\\") {
        v = substr(nm, RSTART + 1, RLENGTH - 1)
        if (v in list) {
          n = split(list[v], vals, SUBSEP)
          for (i = 1; i <= n; i++) { rest = nm; sub("\\$" v, vals[i], rest); emit(rest) }
          return
        }
      }
      gsub(/\\\$/, "\001", nm)
      nm = " " nm
      while (match(nm, / -(Offline|Full|Save|Help|All|AllSessions|NoColor)( |,|$)/)) {
        o = substr(nm, RSTART + 2, RLENGTH - 2); sub(/[ ,]$/, "", o)
        nm = substr(nm, 1, RSTART) "--" kebab(o) substr(nm, RSTART + 2 + length(o))
      }
      nm = substr(nm, 2)
      if (nm ~ /\$/) nm = "UNREADABLE NAME: " nm
      gsub(/\001/, "$", nm)
      print nm
    }
    { line[NR] = $0 }
    /^[ \t]*for [A-Za-z_]+ in .*; do/ {
      s = $0; sub(/^[ \t]*for /, "", s); v = s; sub(/ .*/, "", v); sub(/^[A-Za-z_]+ in /, "", s); sub(/; do.*$/, "", s)
      n = words(s, w); joined = ""
      for (i = 1; i <= n; i++) joined = joined (i > 1 ? SUBSEP : "") w[i]
      list[v] = joined
    }
    /^[ \t]*payload_checks [a-z]+/ { m = $0; sub(/^[ \t]*payload_checks /, "", m); sub(/ .*/, "", m); modes[m] = 1 }
    END {
      for (r = 1; r <= NR; r++) {
        s = line[r]
        if (s ~ /^[ \t]*#/) continue
        while (match(s, /(^|[^A-Za-z0-9_.])(has|hasnot|hasi|ok|nokeys|gen_refuses) +"/)) {
          i = RSTART + RLENGTH; nm = ""; depth = 0
          for (; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "\\") { nm = nm c substr(s, i + 1, 1); i++; continue }
            if (c == "$" && substr(s, i + 1, 1) == "(") { depth++; nm = nm "$("; i++; continue }
            if (depth > 0 && c == ")") depth--
            if (c == "\"" && depth == 0) break
            nm = nm c
          }
          emit(nm)
          s = substr(s, i + 1)
        }
      }
      # tests/payload.py: the checks in def common() run once per common(r, TAG) in a mode block.
      Q = "\047"; mode = ""; incommon = 0; nc = 0
      while ((getline p < pay) > 0) {
        if (p ~ /^def common/) { incommon = 1; continue }
        if (p ~ /^[^ \t#]/) incommon = 0
        if (p ~ ("^(el)?if mode == " Q "[a-z]+" Q)) { mode = p; sub("^(el)?if mode == " Q, "", mode); sub(Q ".*", "", mode) }
        nm = ""
        if (match(p, "check\\((tag \\+ )?" Q "[^" Q "]*" Q)) { nm = substr(p, RSTART, RLENGTH); sub("^check\\((tag \\+ )?" Q, "", nm); sub(Q "$", "", nm) }
        else if (match(p, /check\((tag \+ )?"[^"]*"/)) { nm = substr(p, RSTART, RLENGTH); sub(/^check\((tag \+ )?"/, "", nm); sub(/"$/, "", nm) }
        if (incommon && nm != "") { cn[++nc] = nm; continue }
        if (mode != "" && (mode in modes)) {
          if (nm != "") print nm
          if (match(p, "common\\(r, " Q "[^" Q "]*" Q "\\)")) { t = substr(p, RSTART + 11, RLENGTH - 13); for (i = 1; i <= nc; i++) print t cn[i] }
        }
      }
    }' "$1"
}

W=$(mktemp -d 2>/dev/null || mktemp -d -t parity)
trap 'rm -rf "$W"' EXIT
names "$RUN" | LC_ALL=C sort > "$W/bash"
names "$RUNPS" | LC_ALL=C sort > "$W/ps"
grep -v '^#' "$ONLY" | grep -v '^[[:space:]]*$' > "$W/only-lines" || true
FAIL=0
T=$(printf '\t')
while IFS= read -r l; do
  case "$l" in
    *"$T"*) r=${l#*"$T"}; [ -n "$(printf '%s' "$r" | tr -d ' \t')" ] || { echo "  bash-only.txt gives no reason: ${l%%"$T"*}"; FAIL=1; } ;;
    *) echo "  bash-only.txt needs the name, a tab and the reason: $l"; FAIL=1 ;;
  esac
done < "$W/only-lines"
cut -f1 "$W/only-lines" | LC_ALL=C sort > "$W/only"
if grep -q '^UNREADABLE NAME: ' "$W/bash" "$W/ps"; then grep -h '^UNREADABLE NAME: ' "$W/bash" "$W/ps" | sed 's/^/  /'; FAIL=1; fi
counts() { LC_ALL=C uniq -c "$1" | sed -E 's/^ *([0-9]+) /\1	/'; }
counts "$W/bash" > "$W/bash.c"; counts "$W/ps" > "$W/ps.c"; counts "$W/only" > "$W/only.c"
LC_ALL=C awk -F'\t' -v OFS='\t' '
  FILENAME == ARGV[1] { b[$2] = $1; next }
  FILENAME == ARGV[2] { p[$2] = $1; next }
  { o[$2] = $1 }
  END {
    for (n in b) { need = b[n] - (n in o ? o[n] : 0); have = (n in p ? p[n] : 0); if (need > have) print "missing", n, b[n], have, (n in o ? o[n] : 0) }
    for (n in o) {
      if (!(n in b)) print "stale", n
      else if (o[n] > b[n]) print "toomany", n, b[n], 0, o[n]
      else if ((n in p) && p[n] >= b[n]) print "twinned", n
    }
    for (n in p) if (!(n in b)) print "psonly", n
  }' "$W/bash.c" "$W/ps.c" "$W/only.c" | LC_ALL=C sort > "$W/report"
while IFS="$T" read -r kind n bc pc oc; do
  case "$kind" in
    missing) FAIL=1
      if [ "$bc" -gt 1 ]; then echo "  no PowerShell twin: $n (run.sh has it $bc times, run-ps.sh $pc, bash-only.txt $oc)"; else echo "  no PowerShell twin: $n"; fi ;;
    stale)   FAIL=1; echo "  bash-only.txt names a test run.sh does not have: $n" ;;
    toomany) FAIL=1; echo "  bash-only.txt lists $n $oc times, run.sh has it $bc times" ;;
    twinned) FAIL=1; echo "  bash-only.txt lists $n, but run-ps.sh has it: remove the line" ;;
  esac
done < "$W/report"
NB=$(grep -c . "$W/bash"); NP=$(grep -c . "$W/ps"); NO=$(grep -c . "$W/only"); NPO=$(grep -c '^psonly' "$W/report")
echo "  $NB tests in run.sh, $NP in run-ps.sh, $NO of them bash-only"
if [ "$NPO" -gt 0 ]; then
  echo "  $NPO PowerShell tests with no bash twin:"
  grep '^psonly' "$W/report" | cut -f2 | sed 's/^/    /'
fi
exit "$FAIL"
