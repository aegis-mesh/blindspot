#!/usr/bin/env bash
# Keeps the two test suites in step: every test in tests/run.sh (gird-check.sh) needs a test of
# the same name in tests/run-ps.sh (gird-check.ps1), or a line in tests/bash-only.txt, the name,
# a tab and why it can't or need not run for PowerShell. A name used N times in run.sh needs N
# twins, less the bash-only lines that name it. PowerShell tests with no bash twin are listed,
# not failed. Both suites run this as their test "the two suites test the same things".
#
#   bash tests/parity.sh [run.sh run-ps.sh bash-only.txt]
#
# A test is a call to ok, has, hasnot, hasi, nokeys or gen_refuses with its name as a
# double-quoted literal, or, for each "payload_checks MODE" call, a check() of that mode in
# tests/payload.py. So that no test goes uncounted, it fails on:
#   - a call to one of those, or to bad, whose name is not a double-quoted literal;
#   - a function other than those helpers that calls them (a new wrapper hides its names);
#   - a bad "name" that no counted test of the same name starts (a test that only fails);
#   - a name with a $ it can't fill in.
# Inside the helpers' own bodies, calls with "$1" or "$label" are the helpers at work, not tests.
# Before names are compared:
#   - a trailing "($...)" is dropped: it carries a measured value, not the test;
#   - "bash $V: " is dropped, and "$E: ", "perl: " and "net: " become "<engine>: " (perl is
#     gird-check.sh's own session engine, .NET is gird-check.ps1's);
#   - $VAR is filled in from the "for VAR in ...; do" loop the call is in, one name per value;
#   - gird-check.ps1's options are written as gird-check.sh's: -Offline is --offline.
# It uses POSIX awk only, so it runs the same with macOS's awk, gawk and mawk.
set -u
cd "$(dirname "$0")/.." || exit 1
RUN=${1:-tests/run.sh}; RUNPS=${2:-tests/run-ps.sh}; ONLY=${3:-tests/bash-only.txt}; PAY=${4:-tests/payload.py}
for f in "$RUN" "$RUNPS" "$ONLY" "$PAY"; do [ -f "$f" ] || { echo "  parity: $f not found"; exit 1; }; done

names() { # suite: "N<tab>name" per test, "L<tab>problem" per call it can't count
  LC_ALL=C awk -v pay="$PAY" -v src="$1" '
    BEGIN {
      split("ok bad has hasnot hasi nokeys gen_refuses payload_checks", hl, " ")
      for (i in hl) helper[hl[i]] = 1
      SQ = "\047"; DQ = "\""; st = ""; hd = ""; sp = 0; fn = ""; nr = 0; nb = 0
    }
    function lint(m) { print "L\t" src ":" (pl ? pl : FNR) ": " m }
    function words(s, out,   n, w, c, q, i, inw) { # a shell word list: plain and quoted words
      n = 0; w = ""; q = ""; inw = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == q) q = ""; else w = w c; continue }
        if (c == SQ || c == DQ) { q = c; inw = 1; continue }
        if (c == " " || c == "\t") { if (inw) { out[++n] = w; w = ""; inw = 0 } continue }
        w = w c; inw = 1
      }
      if (inw) out[++n] = w
      return n
    }
    function push(v, l) { sp++; sv[sp] = v; sl[sp] = l }
    function pop() { if (sp > 0) sp-- }
    function loopvals(v,   k) { for (k = sp; k > 0; k--) if (sv[k] == v) return sl[k]; return "\001none" }
    function kebab(o,   i, c, k) { k = ""; for (i = 1; i <= length(o); i++) { c = substr(o, i, 1); if (c ~ /[A-Z]/) k = k (i > 1 ? "-" : "") tolower(c); else k = k c }; return k }
    function emit(nm,   i, v, n, vals, rest, o, l) {
      sub(/ \(\$.*$/, "", nm)
      sub(/^bash \$V: /, "", nm)
      sub(/^(\$E|perl|net): /, "<engine>: ", nm)
      if (match(nm, /\$[A-Za-z_][A-Za-z0-9_]*/) && substr(nm, RSTART - 1, 1) != "\\") {
        v = substr(nm, RSTART + 1, RLENGTH - 1); l = loopvals(v)
        if (l != "\001none") {
          n = words(l, vals)
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
      if (nm ~ /\$/) { gsub(/\001/, "$", nm); lint("a name with a $ that is not a loop value: " nm); return }
      gsub(/\001/, "$", nm)
      print "N\t" nm
    }
    function skipdq(s, i,   c, d, v, j) { # reads a double-quoted string from i, just after its quote
      v = ""; d = 0
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (c == "\\") { v = v substr(s, i, 2); i += 2; continue }
        if (c == "$" && substr(s, i + 1, 1) == "(") { d++; v = v "$("; i += 2; continue }
        if (d > 0 && c == ")") { d--; v = v c; i++; continue }
        if (d > 0 && c == DQ) { j = index(substr(s, i + 1), DQ); if (j == 0) j = length(s) - i; v = v substr(s, i, j + 1); i += j + 1; continue }
        if (c == DQ) { DQV = v; return i + 1 }
        v = v c; i++
      }
      DQV = v; return i
    }
    function call(w, s, i,   c, m) {
      while (substr(s, i, 1) == " " || substr(s, i, 1) == "\t") i++
      c = substr(s, i, 1)
      if (fn != "" && (fn in helper)) { if (c == DQ) i = skipdq(s, i + 1); return i }
      if (fn != "") { lint("function " fn " calls " w ": call the helpers directly, or add it to parity.sh with its names"); return i }
      if (w == "payload_checks") {
        if (match(substr(s, i), /^[a-z]+/)) { modes[substr(s, i, RLENGTH)] = 1; return i + RLENGTH }
        lint("payload_checks needs its mode as a plain word"); return i
      }
      if (c != DQ) { lint(w " with a name that is not a double-quoted literal"); return i }
      i = skipdq(s, i + 1)
      if (w == "bad") { nb++; bad[nb] = DQV; badat[nb] = src ":" FNR; return i }
      nr++; raw[nr] = DQV; emit(DQV)
      return i
    }
    function scan(s,   i, n, c, w, nx, rest, lst, v, m) {
      i = 1; n = length(s)
      while (i <= n) {
        c = substr(s, i, 1)
        if (st == "s") { m = index(substr(s, i), SQ); if (m == 0) return; i += m; st = ""; continue }
        if (c == "\\") { i += 2; continue }
        if (c == SQ) { st = "s"; i++; continue }
        if (c == DQ) { i = skipdq(s, i + 1); continue }
        if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) return
        if (substr(s, i, 2) == "<<") {
          rest = substr(s, i + 2); hdash = 0
          if (substr(rest, 1, 1) == "-") { hdash = 1; rest = substr(rest, 2) }
          sub(/^[ \t]*/, "", rest)
          if (match(rest, "^[\"" SQ "]?[A-Za-z_][A-Za-z0-9_]*")) { m = substr(rest, 1, RLENGTH); gsub("[\"" SQ "]", "", m); pend = m; pdash = hdash }
          i += 2; continue
        }
        if (c ~ /[A-Za-z_]/ && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;&|(!{]/)) {
          match(substr(s, i), /^[A-Za-z_][A-Za-z0-9_]*/); w = substr(s, i, RLENGTH); i += RLENGTH
          nx = substr(s, i, 1)
          if (w == "for" && (nx == " " || nx == "\t")) {
            rest = substr(s, i)
            if (match(rest, /;[ \t]*do([ \t;]|$)/)) { lst = substr(rest, 1, RSTART - 1); i += RSTART + RLENGTH - 1 } else { lst = rest; i = n + 1 }
            sub(/^[ \t]*/, "", lst); v = lst; sub(/[ \t].*/, "", v); sub(/^[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+/, "", lst)
            push(v, lst); continue
          }
          if ((w == "while" || w == "until") && (nx == " " || nx == "\t")) { push("", ""); continue }
          if (w == "done" && (nx == "" || nx ~ /[ \t;)<>|&]/)) { pop(); continue }
          if ((w in helper) && (nx == " " || nx == "\t")) { i = call(w, s, i); continue }
          continue
        }
        i++
      }
    }
    function pre(r,   k) { # the start a bad "..." of the same test shares with its counted name
      k = index(r, " ($"); if (k) return substr(r, 1, k - 1)
      if (match(r, /\$[A-Za-z_][A-Za-z0-9_]*/)) return substr(r, 1, RSTART + RLENGTH - 1)
      return r
    }
    {
      if (hd != "") { t = $0; if (hdpdash) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
      if (st == "" && $0 ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/) {
        fn = $0; sub(/^[ \t]*/, "", fn); sub(/\(.*/, "", fn)
        fnind = $0; sub(/[^ \t].*/, "", fnind)
        t = $0; sub(/[ \t]+#.*$/, "", t); sub(/[ \t]+$/, "", t); single = (t ~ /\}$/)
      } else if (fn != "" && !single && st == "" && $0 ~ ("^" fnind "\\}")) { fn = ""; next }
      pend = ""
      scan($0)
      if (pend != "") { hd = pend; hdpdash = pdash }
      if (fn != "" && single) fn = ""
    }
    END {
      for (b = 1; b <= nb; b++) {
        okb = 0
        for (r = 1; r <= nr && !okb; r++) { p = pre(raw[r]); if (p != "" && index(bad[b], p) == 1) okb = 1 }
        if (!okb) print "L\t" badat[b] ": bad \"" bad[b] "\" with no counted test of that name: a test that only fails is not counted"
      }
      # tests/payload.py: the checks in def common() run once per common(r, TAG) in a mode block.
      mode = ""; incommon = 0; nc = 0; pl = 0
      while ((getline p < pay) > 0) {
        pl++
        if (p ~ /^def common/) { incommon = 1; continue }
        if (p ~ /^[^ \t#]/) incommon = 0
        if (p ~ ("^(el)?if mode == " SQ "[a-z]+" SQ)) { mode = p; sub("^(el)?if mode == " SQ, "", mode); sub(SQ ".*", "", mode) }
        nm = ""
        if (match(p, "check\\((tag \\+ )?" SQ "[^" SQ "]*" SQ)) { nm = substr(p, RSTART, RLENGTH); sub("^check\\((tag \\+ )?" SQ, "", nm); sub(SQ "$", "", nm) }
        else if (match(p, /check\((tag \+ )?"[^"]*"/)) { nm = substr(p, RSTART, RLENGTH); sub(/^check\((tag \+ )?"/, "", nm); sub(/"$/, "", nm) }
        else if (p ~ /(^|[^A-Za-z0-9_])check\(/ && p !~ /def check\(/) { src = pay; lint("check() with a name that is not a literal") }
        if (incommon && nm != "") { cn[++nc] = nm; continue }
        if (mode != "" && (mode in modes)) {
          if (nm != "") print "N\t" nm
          if (match(p, "common\\(r, " SQ "[^" SQ "]*" SQ "\\)")) { t = substr(p, RSTART + 11, RLENGTH - 13); for (i = 1; i <= nc; i++) print "N\t" t cn[i] }
        }
      }
    }' "$1"
}

W=$(mktemp -d 2>/dev/null || mktemp -d -t parity)
trap 'rm -rf "$W"' EXIT
names "$RUN" > "$W/bash.all"; names "$RUNPS" > "$W/ps.all"
FAIL=0
T=$(printf '\t')
for s in bash ps; do
  sed -n "s/^N$T//p" "$W/$s.all" | LC_ALL=C sort > "$W/$s"
  if grep -q "^L$T" "$W/$s.all"; then FAIL=1; sed -n "s/^L$T/  can't count: /p" "$W/$s.all"; fi
done
grep -v '^#' "$ONLY" | grep -v '^[[:space:]]*$' > "$W/only-lines" || true
while IFS= read -r l; do
  case "$l" in
    *"$T"*) r=${l#*"$T"}; [ -n "$(printf '%s' "$r" | tr -d ' \t')" ] || { echo "  bash-only.txt gives no reason: ${l%%"$T"*}"; FAIL=1; } ;;
    *) echo "  bash-only.txt needs the name, a tab and the reason: $l"; FAIL=1 ;;
  esac
done < "$W/only-lines"
cut -f1 "$W/only-lines" | LC_ALL=C sort > "$W/only"
counts() { LC_ALL=C uniq -c "$1" | sed "s/^ *\([0-9][0-9]*\) /\1$T/"; }
counts "$W/bash" > "$W/bash.c"; counts "$W/ps" > "$W/ps.c"; counts "$W/only" > "$W/only.c"
LC_ALL=C awk -F'\t' -v OFS='\t' '
  FILENAME == ARGV[1] { b[$2] = $1; next }
  FILENAME == ARGV[2] { p[$2] = $1; next }
  { o[$2] = $1 }
  END {
    for (n in b) {
      ob = 0; if (n in o) ob = o[n]
      pb = 0; if (n in p) pb = p[n]
      if (b[n] - ob > pb) print "missing", n, b[n], pb, ob
    }
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
