#!/usr/bin/env bash
# Writes the data files into gird-check.sh and gird-check.ps1 (and the tables root reads into
# gird-fleet.sh, with gird-check.sh's agents table), between each block's "# >>> <name>"
# and "# <<< <name>" markers: key types (data/keys.tsv), published example and emulator values
# that are not keys (data/public-values.tsv), agent session locations
# (data/sessions.tsv), bad npm packages (data/bad-npm.tsv), incidents (data/incidents.tsv), bad
# Python packages (data/bad-pypi.tsv), files malware leaves on disk (data/indicators.tsv), files
# worms plant in a project (data/planted.tsv), hosted platforms that leaked stored secrets
# (data/platforms.tsv), agents set to run commands without asking (data/auto-approve.tsv), agent
# versions with a published fix (data/outdated.tsv) and extensions that shipped malware
# (data/bad-extensions.tsv). The scripts stay single files people can download and check.
#
#   bash tools/gen.sh           rewrite the blocks
#   bash tools/gen.sh --check   exit 1 if a block differs from the data files
set -eu
cd "$(dirname "$0")/.."
CHECK=0; [ "${1:-}" = --check ] && CHECK=1
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

rows() { grep -v '^#' "$1" | grep -v '^[[:space:]]*$'; }
IDS=" $(rows data/incidents.tsv | cut -f1 | tr '\n' ' ')"
ACT_IDS=" $(rows data/incidents.tsv | awk -F '\t' '$6 == "act" { printf "%s ", $1 }')"
# A leak is a hosted platform's (data/platforms.tsv): it never means a compromised machine, so a platform
# names only a leak, a leak is a platform's, and no package, extension or file of a leak is looked for.
LEAK_IDS=" $(rows data/incidents.tsv | awk -F '\t' '$6 == "leak" { printf "%s ", $1 }')"
PLAT_IDS=" $(rows data/platforms.tsv | cut -f1 | tr '\n' ' ')"
# The Python incidents: those with a bad version or a site or temp line, as PY_INCIDENTS lists them.
PY_IDS=" $( { rows data/bad-pypi.tsv | cut -f3; rows data/indicators.tsv | awk -F '\t' '$3 ~ /^(site|temp)$/ { print $1 }'; } | sort -u | tr '\n' ' ')"
# What to do shows an incident's advice only for a package or extension found (bad-npm, bad-pypi,
# bad-extensions), so advice on any other incident would never be shown: it is refused.
PKG_IDS=" $(cat data/bad-npm.tsv data/bad-pypi.tsv data/bad-extensions.tsv | grep -v '^#' | awk -F '\t' 'NF >= 3 { printf "%s ", $3 }')"
# A path for a file check: ~, an absolute path or one of the tokens sh() and ps() below translate
# first ({AS}, {LOCALAPPDATA}, {XDG_DATA}, {GOOSE_DATA}, {GOOSE_STATE}, {PROGRAMDATA}, or
# {ENV:NAME:fallback} whose fallback is ~ or a path), at least one folder or file after it (an ENV
# token may stand alone when its fallback is a folder below ~ or /: the variable names the place),
# and nothing a shell or PowerShell string would read as code, a glob or a separator. Anything else,
# such as a token the generators do not know or {ENV:NAME} with no fallback, would come out as a
# PowerShell parse error or a bash "bad substitution" for everyone, so it is refused.
PATH_OK='function path_ok(p,   r, k, v) {
    if (p ~ /[\047"`$|\\*?[;]/ || p ~ /\{ENV:[^}]*\{/) return 0
    if (p ~ /^\{ENV:/) {
      k = index(p, "}"); if (k == 0) return 0
      v = substr(p, 6, k - 6); r = substr(p, k + 1)
      if (v !~ /^[A-Za-z_][A-Za-z0-9_]*:/) return 0
      v = substr(v, index(v, ":") + 1)
      if (v != "~" && v !~ /^~\/[^\/]/ && v !~ /^\/[^\/]/) return 0
      if (r == "" && v != "~") return 1
    } else if (p ~ /^\{/) {
      if (p !~ /^\{(AS|LOCALAPPDATA|XDG_DATA|GOOSE_DATA|GOOSE_STATE|PROGRAMDATA)\}/) return 0
      r = substr(p, index(p, "}") + 1)
    } else if (p ~ /^~/) r = substr(p, 2)
    else if (p ~ /^\//) r = p
    else return 0
    return r ~ /^\/[^\/]/
  }'
# A key line: id, name, starts, pattern, at and max (see data/keys.tsv).
# The id travels in the shared counts, the result link and gird-fleet.sh's output, and fleet_ids in
# gird-check.sh keeps only ids of lowercase letters, digits and -: any other id would be dropped there
# without a word, so it is refused here. A start is plain characters and one-character choices such
# as [.], so it reads the same in awk, perl and .NET and the perl and .NET pre-filter stays a quick
# search for fixed text. A pattern runs in grep -E (BSD and GNU), ripgrep, perl and .NET: no POSIX
# class or \s-style escape, and no count above 255, which BSD grep refuses.
KEYS_OK='function starts_ok(s,   i, c, inb, n) {
    if (s == "" || s ~ /[\047"`\/]/) return 0
    inb = 0; n = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (inb) { if (c == "]") { if (n == 0) return 0; inb = 0 } else if (c == "^" || c == "[") return 0; else n++; continue }
      if (c == "[") { inb = 1; n = 0; continue }
      if (c == "|") { if (i == 1 || i == length(s) || substr(s, i - 1, 1) == "|") return 0; continue }
      if (c !~ /[A-Za-z0-9_~=:-]/) return 0
    }
    return !inb
  }
  # An in line names each start as TEXT@N: fixed text, its one-character choices single characters
  # such as [+], and where it is in the key; TEXT@N&TEXT@N needs all its parts. A start line names none.
  function marks_ok(s, inl,   n, a, i, t, m, b, j) {
    n = split(s, a, "|")
    for (i = 1; i <= n; i++) {
      if (!inl) { if (a[i] ~ /[@&]/) return 0; continue }
      m = split(a[i], b, "&")
      for (j = 1; j <= m; j++) {
        if (b[j] !~ /^[^@]+@[0-9]+$/) return 0
        t = b[j]; sub(/@[0-9]+$/, "", t)
        if (!starts_ok(t) || t ~ /\[[^]][^]]+\]/) return 0
      }
    }
    return 1
  }
  function pattern_ok(p,   s, b, q) {
    if (p == "" || p ~ /[\047`]/ || index(p, "[:") > 0 || p ~ /\\[sdwtSDWT]/) return 0
    s = p
    while (match(s, /\{[0-9]+(,[0-9]*)?\}/)) {
      b = substr(s, RSTART + 1, RLENGTH - 2); split(b, q, ",")
      if (q[1] + 0 > 255 || q[2] + 0 > 255) return 0
      s = substr(s, RSTART + RLENGTH)
    }
    return 1
  }
  function plain(s) { gsub(/@[0-9]+/, "", s); gsub(/&[^|]*/, "", s); return s }
  function key_ok() {
    return NF == 6 && $1 ~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/ && $2 != "" && $2 !~ /[\047"`$\\]/ && starts_ok(plain($3)) && marks_ok($3, $5 == "in") && pattern_ok($4) &&
      $5 ~ /^(start|in)$/ && ($6 == "-" || ($6 ~ /^[0-9]+$/ && $6 + 0 >= 20 && $6 + 0 <= 1024))
  }'
# No regex intervals ({n}) in the awk programs: older mawk (Ubuntu 22.04) does not support them.
# Characters that would break the generated bash, awk or PowerShell are refused, and so is an
# incident id no line of data/incidents.tsv has. A key id names its provider once: gird.ai's counts
# are keyed on it. The regexes spell out counts
# ([0-9][0-9][0-9][0-9], not [0-9]{4}): Debian 12's mawk has no {n} intervals and would refuse every line.
bad=$(awk '/^#pass$/ { if (!rows || last) print "data/keys.tsv: a #pass line with no key line before it"; last = 1; next } /^#/ || !NF { next } { rows = 1; last = 0 } END { if (last) print "data/keys.tsv: a #pass line with no key line after it" }' data/keys.tsv
      rows data/keys.tsv | awk -F '\t' "$KEYS_OK"'
        { if (!key_ok() || seen[$1]++ || ($5 == "start" && inl)) print "data/keys.tsv: " $0; n++; if ($5 == "in") inl = 1 }
        END { if (n > 40) print "data/keys.tsv: " n " key types, more than the 40 gird-fleet.sh takes from one account (fl_ids_ok)" }'
      rows data/incidents.tsv | awk -F '\t' -v pkg="$PKG_IDS" -v plat="$PLAT_IDS" '(NF < 6 || NF > 8) || ($6 == "leak") != (index(plat, " " $1 " ") > 0) || (NF >= 7 && ($7 == "" || $7 ~ /[\047"`$|\\]/ || index(pkg, " " $1 " ") == 0 || ($7 ~ /^First / && ($6 != "act" || $7 ~ /[Rr]otate|[Rr]evoke/)))) || (NF == 8 && ($6 != "update" || $8 == "" || $8 ~ /[\047"`$|\\]/ || length($8) > 49)) || $1 !~ /^[a-z0-9]+$/ || $2 ~ /[\047"`$|\\]/ || $3 !~ /^[A-Z][a-z]+ [0-9][0-9][0-9][0-9]$/ || $4 ~ /[\047"`$\\]/ || $5 !~ /^https:\/\/[^ \047"`$]+$/ || $6 !~ /^(act|update|leak)$/ || seen[$1]++ { print "data/incidents.tsv: " $0 }'
      # npm's placeholder for a removed package (0.0.1-security, or 0.0.1-security.0 for a few names) is never malware, and the scripts skip it.
      rows data/bad-npm.tsv | awk -F '\t' -v ids="$IDS" -v leaks="$LEAK_IDS" 'NF != 3 || index(leaks, " " $3 " ") > 0 || $1 !~ /^(@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/ || $2 !~ /^(\*|[0-9][0-9A-Za-z.+-]*)$/ || $2 ~ /^0\.0\.1-security(\.[0-9]+)?$/ || $3 !~ /^[a-z0-9]+$/ || index(ids, " " $3 " ") == 0 { print "data/bad-npm.tsv: " $0 }'
      rows data/sessions.tsv | awk -F '\t' "$PATH_OK"'
        NF != 5 || $1 !~ /^(all|mac|linux|win)$/ || $2 !~ /^(read|db|sealed)$/ || $3 ~ /[\047"`$|\\]/ || !path_ok($4) { print "data/sessions.tsv: " $0 }'
      # A Python incident means a compromised machine: one whose level is update is refused. The os
      # column says where the malware of that version could run; elsewhere it is a version to update,
      # and everywhere for none, when the package's maintainer says its malware could not run.
      rows data/bad-pypi.tsv | awk -F '\t' -v ids="$ACT_IDS" 'NF != 4 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9_.]*$/ || $2 !~ /^[0-9][0-9A-Za-z.+!]*$/ || index(ids, " " $3 " ") == 0 || $4 !~ /^(all|mac|linux|win|none)$/ { print "data/bad-pypi.tsv: " $0 }'
      # A startup line carries a note, a temp line the advice of its incident (the same on each of its
      # temp lines); wiper and site lines carry -. PowerShell gets the note quoted, so it may hold a quote.
      # A Python incident's startup file is shown in its row in section 5, checked before the ownership
      # rules: it must be in the home folder, the person's own, with owner no.
      rows data/indicators.tsv | awk -F '\t' -v ids="$IDS" -v acts="$ACT_IDS" -v leaks="$LEAK_IDS" -v py="$PY_IDS" "$PATH_OK"'
        { ok = NF == 6 && index(ids, " " $1 " ") > 0 && index(leaks, " " $1 " ") == 0 && $2 ~ /^(all|mac|linux|win)$/ && $3 ~ /^(wiper|startup|site|temp)$/ && $4 ~ /^(yes|no)$/
          if ($3 ~ /^(wiper|startup)$/) ok = ok && path_ok($5)
          if ($3 == "wiper") ok = ok && $5 ~ /gh-token-monitor/
          if ($3 == "startup" && index(py, " " $1 " ") > 0) ok = ok && $4 == "no" && $5 ~ /^~\//
          if ($3 == "site") ok = ok && $5 ~ /^[A-Za-z0-9._-]+$/
          if ($3 == "temp") ok = ok && $5 ~ /^[A-Za-z0-9._-]+\*?$/
          if ($3 ~ /^(site|temp)$/) ok = ok && $5 !~ /^\.+\*?$/ && index(acts, " " $1 " ") > 0
          if ($3 ~ /^(startup|temp)$/) ok = ok && $6 != "-" && $6 != "" && $6 !~ /["`$|\\]/; else ok = ok && $6 == "-"
          if ($3 == "temp") { if (($1 in tn) && tn[$1] != $6) ok = 0; tn[$1] = $6 }
          if (!ok) print "data/indicators.tsv: " $0 }'
      # A planted file's alone is yes or no, and its sha256 a comma-separated list of SHA-256 values
      # or -; a yes file counts on its name, so it carries none.
      rows data/planted.tsv | awk -F '\t' -v ids="$IDS" '
        function shas_ok(s,   n, a, i) { if (s == "-") return 1; n = split(s, a, ","); for (i = 1; i <= n; i++) if (a[i] !~ /^[0-9a-f]+$/ || length(a[i]) != 64) return 0; return 1 }
        NF != 6 || $1 !~ /^\.(claude|vscode)$/ || $2 !~ /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$/ || index(ids, " " $3 " ") == 0 || $4 == "" || $4 ~ /[\047"`$|\\]/ ||
        $5 !~ /^(yes|no)$/ || !shas_ok($6) || ($5 == "yes" && $6 != "-") || seen[$1 "/" $2]++ { print "data/planted.tsv: " $0 }'
      # A pattern !key (a key no line of the file may set) is a .toml file's only, and a line needs one other.
      rows data/auto-approve.tsv | awk -F '\t' "$PATH_OK"'
        function pat_ok(s) { return s ~ /[^[:space:]]/ && s !~ /[\047`$|\\]/ && (s !~ /^!/ || (s ~ /^![A-Za-z0-9_.-]+$/ && $3 ~ /\.toml$/)) }
        { ok = NF >= 5 && $1 != "" && $1 !~ /[\047"`$|\\]/ && $2 ~ /^(all|mac|linux|win)$/ && $4 != "" && $4 !~ /[\047"`$|\\]/
          if ($3 ~ /^\{PROJECT\}/) ok = ok && $3 ~ /^\{PROJECT\}(\/[A-Za-z0-9_.-]+)(\/[A-Za-z0-9_.-]+)+$/ && $3 !~ /\/\.\.?(\/|$)/
          # One folder may be *, for every folder there; the scripts expand it, and a * anywhere else is refused.
          else { p = $3; ok = ok && gsub(/\/\*\//, "/x/", p) <= 1 && path_ok(p) }
          pos = 0; for (i = 5; i <= NF; i++) { if (!pat_ok($i)) ok = 0; if ($i !~ /^!/) pos++ }; if (pos == 0) ok = 0
          if (!ok) print "data/auto-approve.tsv: " $0 }'
      # Lines of one tool must agree on its name, and lines of one advisory of a tool on its range and hole.
      rows data/outdated.tsv | awk -F '\t' "$PATH_OK"'
        function ver(s) { return s ~ /^[0-9]+(\.[0-9]+)*$/ }
        { ok = NF == 8 && $1 ~ /^[a-z0-9]+$/ && $2 != "" && $2 !~ /[\047"`$|\\]/ && $3 ~ /^(all|mac|linux|win)$/ && $4 ~ /^(plist|folder|npm|mcparg)$/
          if ($4 ~ /^(plist|folder)$/) ok = ok && path_ok($5); else ok = ok && $5 ~ /^(@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/
          if ($4 == "plist") ok = ok && $5 ~ /\/Info\.plist$/
          n = split($6, r, " ")
          # >=first <=last: an advisory that names first to last and that no version fixes.
          ok = ok && ((n == 1 && r[1] ~ /^</ && ver(substr(r[1], 2))) || (n == 2 && r[1] ~ /^>=/ && ver(substr(r[1], 3)) && ((r[2] ~ /^<[0-9]/ && ver(substr(r[2], 2))) || (r[2] ~ /^<=/ && ver(substr(r[2], 3))))))
          ok = ok && $7 != "" && $7 !~ /[\047"`$|\\]/ && $8 ~ /^https:\/\/[^ \047"`$|\\]+$/
          if (($1 in same) && same[$1] != $2) ok = 0; same[$1] = $2
          a = $1 "\t" $8; k = $6 "\t" $7; if ((a in adv) && adv[a] != k) ok = 0; adv[a] = k
          if (!ok) print "data/outdated.tsv: " $0 }'
      # An extension that shipped malware means a compromised machine: an update-level incident is refused.
      # The os column says where its malware could run; elsewhere it is a malicious extension to remove.
      # It is all, one OS, or two of them separated by a comma (mac,win): never one twice, and never all
      # three, which is all.
      rows data/bad-extensions.tsv | awk -F '\t' -v ids="$ACT_IDS" '
        function os_ok(s,   n, a, i, got) { if (s == "all") return 1; n = split(s, a, ","); if (n < 1 || n > 2) return 0
          for (i = 1; i <= n; i++) { if (a[i] !~ /^(mac|linux|win)$/ || (a[i] in got)) return 0; got[a[i]] = 1 }; return 1 }
        NF != 5 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$/ || $2 !~ /^(\*|[0-9]+(\.[0-9]+)*)$/ || index(ids, " " $3 " ") == 0 || $4 !~ /^(openvsx|any)$/ || !os_ok($5) || seen[tolower($1) " " $2]++ { print "data/bad-extensions.tsv: " $0 }'
      rows data/platforms.tsv | awk -F '\t' -v ids="$LEAK_IDS" "$PATH_OK"'
        function paths_ok(s,   n, a, i) { if (s == "-") return 1; n = split(s, a, ";"); for (i = 1; i <= n; i++) if (!path_ok(a[i])) return 0; return 1 }
        NF != 7 || index(ids, " " $1 " ") == 0 || $2 == "" || $2 ~ /[\047"`$|\\]/ || $3 !~ /^(-|[A-Za-z0-9_][A-Za-z0-9._+-]*( [A-Za-z0-9_][A-Za-z0-9._+-]*)*)$/ ||
        !paths_ok($4) || $5 !~ /^(installed|CLI found)$/ || $6 == "" || $6 ~ /["`$|\\]/ || $7 == "" || $7 ~ /["`$|\\]/ || seen[$1]++ { print "data/platforms.tsv: " $0 }')
# A published value names a key type of data/keys.tsv and holds only key characters. It is a part of
# the value, never one its key pattern matches by itself: the list must not hold a whole key.
KEY_IDS=" $(rows data/keys.tsv | cut -f1 | tr '\n' ' ')"
_pv=$(rows data/public-values.tsv | awk -F '\t' -v ids="$KEY_IDS" 'NF != 3 || index(ids, " " $1 " ") == 0 || $2 !~ /^[A-Za-z0-9+\/=%._-]+$/ || length($2) < 20 || $3 !~ /^https:\/\/[^ \047"`$|\\]+$/ || seen[$2]++ { print "data/public-values.tsv: " $0 }'
  rows data/public-values.tsv | while IFS="$(printf '\t')" read -r _i _v _s; do
    _re=$(rows data/keys.tsv | awk -F '\t' -v i="$_i" '$1 == i { print $4 }')
    [ -n "$_re" ] && printf '%s\n' "$_v" | grep -qE -- "$_re" && printf 'data/public-values.tsv: %s is a whole %s key\n' "$_v" "$_i"
  done || :)
bad="$bad${bad:+${_pv:+
}}$_pv"
# The scripts are ASCII only (PowerShell 5.1 reads a file without a BOM as the ANSI code page).
_na=$(LC_ALL=C grep -n '[^ -~	]' data/*.tsv | sed 's/^/not ASCII (or a CRLF line end): /')
bad="$bad${bad:+${_na:+
}}$_na"
# gird-check.sh hands the bad npm versions to awk in four environment strings of 1,000 lines each:
# Linux caps one at 128 KiB, so a longer list needs a fifth piece there first.
_nn=$(rows data/bad-npm.tsv | grep -c .)
[ "$_nn" -le 4000 ] || bad="${bad:+$bad
}data/bad-npm.tsv: $_nn lines, more than the 4,000 gird-check.sh hands to awk (BAD_NPM_P1 to BAD_NPM_P4)"
if [ -n "$bad" ]; then printf 'Lines with a field gen.sh cannot write safely:\n%s\n' "$bad" >&2; exit 2; fi

# Path tokens (see data/sessions.tsv) as bash and as PowerShell. A trailing / is kept in bash.
PATH_SH='function sh(p,   v, fb, rest, k) {
    if (p ~ /^\{ENV:/) {
      k = index(p, "}"); v = substr(p, 6, k - 6); rest = substr(p, k + 1)
      fb = substr(v, index(v, ":") + 1); v = substr(v, 1, index(v, ":") - 1)
      return "${" v ":-" sh(fb) "}" rest
    }
    if (p ~ /^\{PROGRAMDATA\}/) return "${_pd:+$_pd" substr(p, 14) "}"
    sub(/^~/, "$H", p); sub(/^\{AS\}/, "$AS", p); sub(/^\{LOCALAPPDATA\}/, "$WLAPP", p)
    sub(/^\{XDG_DATA\}/, "${XDG_DATA_HOME:-$H/.local/share}", p); sub(/^\{GOOSE_DATA\}/, "$GOOSE_DATA", p); sub(/^\{GOOSE_STATE\}/, "$GOOSE_STATE", p)
    return p
  }'
PATH_PS='function ps(p,   v, fb, rest, k, base) {
    if (p ~ /^\//) return "\047" p "\047"
    if (p ~ /^\{PROGRAMDATA\}/) return "$(if ($env:ProgramData) { J $env:ProgramData \047" substr(p, 15) "\047 } else { \047\047 })"
    if (p ~ /^\{ENV:/) {
      k = index(p, "}"); v = substr(p, 6, k - 6); rest = substr(p, k + 1)
      fb = substr(v, index(v, ":") + 1); v = substr(v, 1, index(v, ":") - 1)
      base = "(Env-Or \047" v "\047 " ps(fb) ")"
    } else if (p ~ /^~/) { base = "$HomeDir"; rest = substr(p, 2) }
    else if (p ~ /^\{AS\}/) { base = "$AppData"; rest = substr(p, 5) }
    else if (p ~ /^\{LOCALAPPDATA\}/) { base = "$LocalAppData"; rest = substr(p, 15) }
    else if (p ~ /^\{XDG_DATA\}/) { base = "(Env-Or \047XDG_DATA_HOME\047 (J $HomeDir \047.local/share\047))"; rest = substr(p, 11) }
    else if (p ~ /^\{GOOSE_DATA\}/) { base = "$GooseData"; rest = substr(p, 13) }
    else if (p ~ /^\{GOOSE_STATE\}/) { base = "$GooseState"; rest = substr(p, 14) }
    sub(/^\//, "", rest)
    return rest == "" ? base : "(J " base " \047" rest "\047)"
  }
  function psq(s) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }'

# --- keys -------------------------------------------------------------------
# ALL_KEYS is every pattern joined into one regex, for a yes or no. A line #pass in data/keys.tsv
# starts the next pass: each pass is matched on its own, so a key of a later pass never hides one of
# an earlier pass (KEY_PASSES, one regex a pass, for ripgrep and .NET). KEY_ALTS is the patterns cut
# at each top-level |, one a line, an empty line between passes: grep gets one -e each and perl one
# regex each, because BSD grep and perl read one long alternation many times slower than its parts
# one by one. PASS_FIXED is each pass's starts as fixed strings, one a line, an empty line between
# passes: grep skips a later pass in a file that holds none of them. KEY_STARTS is every start once,
# as one regex, which the session engines test a piece of a file against before its patterns; a
# start keeps its pattern's boundary there where it can (prestart), so SG. in MSG. starts nothing.
# A match is named by the in lines
# first, each start tested at its place in the whole match (at() and Key-At, which allow the one or
# two characters in front of a key), then by the start lines, tested against the start of the match
# as in 1.2.0; max is the longest match kept for that provider (- for 300).
KPASS=$(awk -F '\t' '/^#pass$/ { p++; next } /^#/ || !NF { next } { printf "%d ", p + 1 }' data/keys.tsv)
KEYS_GEN='function alts(p,   n, i, c, d, inb, cl, neg, cur, o) {
    n = 0; d = 0; inb = 0; cur = ""; o = ""
    for (i = 1; i <= length(p); i++) {
      c = substr(p, i, 1)
      if (c == "\\") { cur = cur c substr(p, i + 1, 1); i++; continue }
      if (inb) { cur = cur c; if (c == "^" && cl == 0 && !neg) { neg = 1; continue }; if (c == "]" && cl > 0) inb = 0; cl++; continue }
      if (c == "[") { inb = 1; cl = 0; neg = 0; cur = cur c; continue }
      if (c == "(") d++; else if (c == ")") d--
      if (c == "|" && d == 0) { o = o (n++ ? "\n" : "") cur; cur = ""; continue }
      cur = cur c
    }
    return o (n ? "\n" : "") cur
  }
  BEGIN { split(kp, ps, " ") }
  { id[NR] = $1; nm[NR] = $2; mk[NR] = $3; st[NR] = $3; gsub(/@[0-9]+/, "", st[NR]); gsub(/&[^|]*/, "", st[NR]); pat[NR] = $4; at[NR] = $5; mx[NR] = $6; n = NR }
  # The fixed strings a start stands for: [abc] is a, b or c.
  function fixed(s,   o, a, k, i, j, b, e, pre, post, m, c) {
    o = ""; k = split(s, a, "|")
    for (i = 1; i <= k; i++) {
      b = index(a[i], "[")
      if (!b) { o = o a[i] "\n"; continue }
      e = index(a[i], "]"); pre = substr(a[i], 1, b - 1); post = substr(a[i], e + 1); m = substr(a[i], b + 1, e - b - 1)
      for (j = 1; j <= length(m); j++) o = o fixed(pre substr(m, j, 1) post) 
    }
    return o
  }
  # For an in line: one test a start, TEXT at its place N, as the at() call (bash) or Key-At (.NET).
  function marks(r, ps1,   o, k, a, i, t, pos, m, b, j, c) {
    o = ""; k = split(mk[r], a, "|")
    for (i = 1; i <= k; i++) {
      c = ""; m = split(a[i], b, "&")
      for (j = 1; j <= m; j++) {
        t = b[j]; pos = t; sub(/@[0-9]+$/, "", t); sub(/^.*@/, "", pos); gsub(/[][]/, "", t)
        if (ps1) c = c (c == "" ? "" : " -and ") "(Key-At $s \047" t "\047 " pos ")"
        else c = c (c == "" ? "" : " && ") "at(s, \"" t "\", " pos ")"
      }
      if (m > 1) c = "(" c ")"
      o = o (o == "" ? "" : (ps1 ? " -or " : " || ")) c
    }
    return o
  }
  # A start for KEY_STARTS: a start that is one fixed text, of a pattern that is one alternative behind
  # a boundary (^|[^...]), is tested after the start, by looking back: not after a character of that
  # class, or after an escape \n, \t or \r, as a session reads the boundary. Written after the
  # start, the start stays fixed text that perl and .NET look for fast.
  function prestart(i,   j, s) {
    s = st[i]
    if (at[i] != "start" || index(s, "|") || index(alts(pat[i]), "\n") || substr(pat[i], 1, 5) != "(^|[^") return s
    j = index(pat[i], "])"); if (!j) return s
    return s "(?:(?<![" substr(pat[i], 6, j - 6) "]" s ")|(?<=\\\\[ntr]" s "))"
  }
  function allstarts(   i, o, s, seen) {
    o = ""
    for (i = 1; i <= n; i++) { s = prestart(i); if (s in seen) continue; seen[s] = 1; o = o (o == "" ? "" : "|") s }
    return o
  }
  # PASS_FIXED: each fixed string once in its pass.
  function passfixed(   i, o, k, a, j, seen) {
    o = ""
    for (i = 1; i <= n; i++) {
      if (i > 1 && ps[i] != ps[i - 1]) { o = o "\n"; split("", seen) }
      k = split(fixed(st[i]), a, "\n")
      for (j = 1; j <= k; j++) if (a[j] != "" && !(a[j] in seen)) { seen[a[j]] = 1; o = o a[j] "\n" }
    }
    sub(/\n$/, "", o); return o
  }
  function passes(q,   i, o, cur) {
    o = ""; cur = ""
    for (i = 1; i <= n; i++) {
      if (i > 1 && ps[i] != ps[i - 1]) { o = o cur q; cur = "" }
      cur = cur (cur == "" ? "" : "|") pat[i]
    }
    return o cur
  }'
rows data/keys.tsv | awk -F '\t' -v kp="$KPASS" "$KEYS_GEN"'
  END {
    print "# >>> keys: generated from data/keys.tsv by tools/gen.sh. Edit that file, then run it."
    all = ""; ids = ""; ka = ""
    for (i = 1; i <= n; i++) { all = all (i > 1 ? "|" : "") pat[i]; ids = ids (i > 1 ? " " : "") id[i]; ka = ka (i > 1 ? (ps[i] != ps[i - 1] ? "\n\n" : "\n") : "") alts(pat[i]) }
    print "ALL_KEYS=\047" all "\047"
    print "KEY_PASSES=\047" passes("\n") "\047"
    print "KEY_ALTS=\047" ka "\047"
    print "PROVIDER_IDS=\"" ids "\""
    print "KEY_STARTS=\047" allstarts() "\047"
    print "PASS_FIXED=\047" passfixed() "\047"
    print "PROV_AWK=\047"
    print "function at(s, t, o,   b) { for (b = 0; b <= 2; b++) if (substr(s, b + o + 1, length(t)) == t) return 1; return 0 }"
    print "function prov(s) {"
    for (i = 1; i <= n; i++) if (at[i] == "in") print "  if (" marks(i, 0) ") return \"" nm[i] "\""
    print "  sub(/^[^A-Za-z]*\\\\[ntr\"]/, \"\", s); sub(/^[^A-Za-z]+/, \"\", s)"
    for (i = 1; i <= n; i++) if (at[i] == "start") print "  if (s ~ /^(" st[i] ")/) return \"" nm[i] "\""
    print "  return \"\""
    print "}"
    printf "function pmax(p) {"
    for (i = 1; i <= n; i++) if (mx[i] != "-") printf " if (p == \"%s\") return %s;", nm[i], mx[i]
    print " return 300 }\047"
    printf "prov_id() { case \"$1\" in"
    for (i = 1; i <= n; i++) printf " \"%s\") printf %s ;;", nm[i], id[i]
    print " esac; }"
    print "# <<< keys"
  }' > "$WORK/keys.sh"

rows data/keys.tsv | awk -F '\t' -v kp="$KPASS" "$KEYS_GEN"'
  END {
    print "# >>> keys: generated from data/keys.tsv by tools/gen.sh. Edit that file, then run it."
    all = ""; ids = ""
    for (i = 1; i <= n; i++) { all = all (i > 1 ? "|" : "") pat[i]; ids = ids (i > 1 ? " " : "") id[i]; }
    print "$ALL_KEYS = \047" all "\047"
    print "$KEY_PASSES = @(\047" passes("\047, \047") "\047)"
    print "$PROVIDER_IDS = \047" ids "\047"
    print "$KEY_STARTS = \047" allstarts() "\047"
    print "$KeyProviderFn = @\047"
    print "function Key-At([string]$s, [string]$t, [int]$o) { for ($b = 0; $b -le 2; $b++) { if ($s.Length -ge $b + $o + $t.Length -and $s.Substring($b + $o, $t.Length) -ceq $t) { return $true } }; $false }"
    print "function Key-Provider([string]$s) {"
    for (i = 1; i <= n; i++) if (at[i] == "in") print "  if (" marks(i, 1) ") { return \047" nm[i] "\047 }"
    print "  $s = $s -replace \047^[^A-Za-z]*\\\\[ntr\"]\047, \047\047 -replace \047^[^A-Za-z]+\047, \047\047"
    for (i = 1; i <= n; i++) if (at[i] == "start") print "  if ($s -cmatch \047^(" st[i] ")\047) { return \047" nm[i] "\047 }"
    print "  $null"
    print "}"
    printf "function Key-Max([string]$p) { switch -CaseSensitive ($p) {"
    for (i = 1; i <= n; i++) if (mx[i] != "-") printf " \047%s\047 { %s }", nm[i], mx[i]
    print " default { 300 } } }"
    printf "function Provider-Id([string]$n) { switch -CaseSensitive ($n) {"
    for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", nm[i], id[i]
    print " default { $null } } }"
    print "\047@"
    print "# <<< keys"
  }' > "$WORK/keys.ps1"

# --- published values -----------------------------------------------------------
# public(k) in sess_filter's madeup and Is-Public in gird-check.ps1's Made-Up: a match that holds a
# published value is not a key.
rows data/public-values.tsv | awk -F '\t' '
  { v[NR] = $2; n = NR }
  END {
    print "# >>> public-values: generated from data/public-values.tsv by tools/gen.sh. Edit that file, then run it."
    print "PUBLIC_AWK=\047"
    printf "function public(k) { return 0"
    for (i = 1; i <= n; i++) printf " || index(k, \"%s\")", v[i]
    print " }\047"
    print "# <<< public-values"
    print "# >>> public-values: generated from data/public-values.tsv by tools/gen.sh. Edit that file, then run it." > "/dev/stderr"
    print "$PublicValuesFn = @\047" > "/dev/stderr"
    printf "function Is-Public([string]$k) { $false" > "/dev/stderr"
    for (i = 1; i <= n; i++) printf " -or $k.Contains(\047%s\047)", v[i] > "/dev/stderr"
    print " }" > "/dev/stderr"
    print "\047@" > "/dev/stderr"
    print "# <<< public-values" > "/dev/stderr"
  }' > "$WORK/public-values.sh" 2> "$WORK/public-values.ps1"

# --- sessions ---------------------------------------------------------------
rows data/sessions.tsv | awk -F '\t' "$PATH_SH"'
  BEGIN { print "# >>> sessions: generated from data/sessions.tsv by tools/gen.sh. Edit that file, then run it."
          printf "SESS_TABLE=\"" }
  { printf "%s%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, $3, sh($4) }
  END { print "\""; print "# <<< sessions" }' > "$WORK/sessions.sh"

rows data/sessions.tsv | awk -F '\t' "$PATH_PS"'
  BEGIN { print "# >>> sessions: generated from data/sessions.tsv by tools/gen.sh. Edit that file, then run it."
          print "$SessTable = @(" }
  $1 == "all" || $1 == "win" { if (n++) print ","; printf "  @(\047%s\047, \047%s\047, %s)", $2, $3, ps($4) }
  END { print ")"; print "# <<< sessions" }' > "$WORK/sessions.ps1"

# --- incidents ---------------------------------------------------------------
# npm_label gives "name, month year"; incident_line adds what it did and the source's site;
# incident_level says whether a hit means a compromised machine (act) or a version to update;
# incident_name is the name alone, incident_source the source without https://, incident_advice
# the incident's own fix, if it has one, and incident_summary its row 05, if it has one.
rows data/incidents.tsv | awk -F '\t' '
  function host(u) { sub(/^https:\/\//, "", u); sub(/\/.*/, "", u); sub(/^www\./, "", u); return u }
  { id[NR] = $1; nm[NR] = $2; lab[NR] = $2 ", " $3; line[NR] = $2 ", " $3 ": " $4 ". " host($5); src[NR] = substr($5, 9); lv[NR] = $6; adv[NR] = $7; sm[NR] = $8; n = NR }
  END {
    print "# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it."
    printf "npm_label() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], lab[i]; print " esac; }"
    printf "incident_line() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], line[i]; print " esac; }"
    printf "incident_level() { case \"$1\" in"; for (i = 1; i <= n; i++) if (lv[i] != "act") printf " %s) printf %s ;;", id[i], lv[i]; print " *) printf act ;; esac; }"
    printf "incident_name() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], nm[i]; print " esac; }"
    printf "incident_source() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], src[i]; print " esac; }"
    printf "incident_advice() { case \"$1\" in"; for (i = 1; i <= n; i++) if (adv[i] != "") printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], adv[i]; print " esac; }"
    printf "incident_summary() { case \"$1\" in"; for (i = 1; i <= n; i++) if (sm[i] != "") printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], sm[i]; print " esac; }"
    print "# <<< incidents"
  }' > "$WORK/incidents.sh"
rows data/incidents.tsv | awk -F '\t' '
  function host(u) { sub(/^https:\/\//, "", u); sub(/\/.*/, "", u); sub(/^www\./, "", u); return u }
  { id[NR] = $1; nm[NR] = $2; lab[NR] = $2 ", " $3; line[NR] = $2 ", " $3 ": " $4 ". " host($5); src[NR] = substr($5, 9); lv[NR] = $6; adv[NR] = $7; sm[NR] = $8; n = NR }
  END {
    print "# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it."
    printf "function Npm-Label([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], lab[i]; print " default { $t } } }"
    printf "function Incident-Line([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], line[i]; print " default { $t } } }"
    printf "function Incident-Level([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) if (lv[i] != "act") printf " \047%s\047 { \047%s\047 }", id[i], lv[i]; print " default { \047act\047 } } }"
    printf "function Incident-Name([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], nm[i]; print " default { $t } } }"
    printf "function Incident-Source([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], src[i]; print " default { $t } } }"
    printf "function Incident-Advice([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) if (adv[i] != "") printf " \047%s\047 { \047%s\047 }", id[i], adv[i]; print " default { \047\047 } } }"
    printf "function Incident-Summary([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) if (sm[i] != "") printf " \047%s\047 { \047%s\047 }", id[i], sm[i]; print " default { \047\047 } } }"
    print "# <<< incidents"
  }' > "$WORK/incidents.ps1"

# --- bad npm packages ------------------------------------------------------
rows data/bad-npm.tsv | awk -F '\t' '
  BEGIN { print "# >>> bad-npm: generated from data/bad-npm.tsv by tools/gen.sh. Edit that file, then run it."; printf "BAD_NPM=\"" }
  { printf "%s%s %s %s", (NR > 1 ? "\n" : ""), $1, $2, $3 }
  END { print "\""; print "# <<< bad-npm" }' > "$WORK/bad-npm.sh"
rows data/bad-npm.tsv | awk -F '\t' '
  BEGIN { print "# >>> bad-npm: generated from data/bad-npm.tsv by tools/gen.sh. Edit that file, then run it."; print "$BadNpm = @\047" }
  { print $1 " " $2 " " $3 }
  END { print "\047@"; print "# <<< bad-npm" }' > "$WORK/bad-npm.ps1"

# --- bad Python packages ------------------------------------------------------
# Rows are "name version incident os". PY_INCIDENTS lists every incident with a bad version or a
# site or temp indicator, in order: section 5 has one row for each.
{ rows data/bad-pypi.tsv | awk -F '\t' '{ print "P\t" $0 }'; rows data/indicators.tsv | awk -F '\t' '{ print "I\t" $0 }'; } | awk -F '\t' '
  $1 == "P" { pk[++n] = $2 " " $3 " " $4 " " $5; if (!seen[$4]++) inc[++m] = $4 }
  $1 == "I" && $4 ~ /^(site|temp)$/ && !seen[$2]++ { inc[++m] = $2 }
  END {
    print "# >>> bad-pypi: generated from data/bad-pypi.tsv by tools/gen.sh. Edit that file, then run it."
    printf "BAD_PYPI=\""; for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "\n" : ""), pk[i]; print "\""
    printf "PY_INCIDENTS=\""; for (i = 1; i <= m; i++) printf "%s%s", (i > 1 ? " " : ""), inc[i]; print "\""
    print "# <<< bad-pypi"
    print "# >>> bad-pypi: generated from data/bad-pypi.tsv by tools/gen.sh. Edit that file, then run it." > "/dev/stderr"
    print "$BadPypi = @\047" > "/dev/stderr"; for (i = 1; i <= n; i++) print pk[i] > "/dev/stderr"; print "\047@" > "/dev/stderr"
    printf "$PyIncidents = @(" > "/dev/stderr"; for (i = 1; i <= m; i++) printf "%s\047%s\047", (i > 1 ? ", " : ""), inc[i] > "/dev/stderr"; print ")" > "/dev/stderr"
    print "# <<< bad-pypi" > "/dev/stderr"
  }' > "$WORK/bad-pypi.sh" 2> "$WORK/bad-pypi.ps1"

# --- files malware leaves on disk ----------------------------------------------
rows data/indicators.tsv | awk -F '\t' "$PATH_SH"'
  BEGIN { print "# >>> indicators: generated from data/indicators.tsv by tools/gen.sh. Edit that file, then run it."
          printf "IND_TABLE=\"" }
  { printf "%s%s|%s|%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, $3, $4, ($3 ~ /^(site|temp)$/ ? $5 : sh($5)), $6 }
  END { print "\""; print "# <<< indicators" }' > "$WORK/indicators.sh"
rows data/indicators.tsv | awk -F '\t' "$PATH_PS"'
  BEGIN { print "# >>> indicators: generated from data/indicators.tsv by tools/gen.sh. Edit that file, then run it."
          print "$IndTable = @(" }
  { printf "  ,@(\047%s\047, \047%s\047, \047%s\047, \047%s\047, %s, %s)\n", $1, $2, $3, $4, ($3 ~ /^(site|temp)$/ ? "\047" $5 "\047" : ps($5)), psq($6) }
  END { print ")"; print "# <<< indicators" }' > "$WORK/indicators.ps1"

# --- files planted in a project ----------------------------------------------
# PLANTED_ERE matches the planted paths. WORM_RUN_ALONE matches, in either folder, the names only a
# worm uses (alone yes) and WORM_RUN_WEAK the names projects use too (alone no), as a hook or a task
# names them; either is empty when no line has that kind, and the scripts skip an empty one.
# PLANTED_ALONE lists the alone paths, planted_sha a file's published SHA-256 values. A settings
# file that runs one is shown with "runs" and the note, or a general line when the notes differ.
rows data/planted.tsv | awk -F '\t' '
  function ere(s) { gsub(/\./, "\\.", s); return s }
  function run(f) { return f == "" ? "" : "\\.(" fo ")[/\\\\]+(" f ")" }
  { p[NR] = $1 "/" $2; nt[NR] = $4; al[NR] = $5; sh[NR] = $6; n = NR
    if (!sf[$1]++) fo = fo (fo == "" ? "" : "|") substr($1, 2)
    if ($5 == "yes" && !sa[$2]++) fa = fa (fa == "" ? "" : "|") ere($2)
    if ($5 == "no" && !sw[$2]++) fw = fw (fw == "" ? "" : "|") ere($2)
    if (NR == 1) note = $4; else if (note != $4) note = "" }
  END {
    ref = note == "" ? "runs a file a worm plants" : "runs " note
    print "# >>> planted: generated from data/planted.tsv by tools/gen.sh. Edit that file, then run it."
    printf "PLANTED=\047"; for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "\n" : ""), p[i]; print "\047"
    printf "PLANTED_ERE=\047"; for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "|" : ""), ere(p[i]); print "\047"
    printf "PLANTED_ALONE=\047"; k = 0; for (i = 1; i <= n; i++) if (al[i] == "yes") printf "%s%s", (k++ ? "\n" : ""), p[i]; print "\047"
    print "WORM_RUN_ALONE=\047" run(fa) "\047"
    print "WORM_RUN_WEAK=\047" run(fw) "\047"
    printf "planted_note() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " */%s) printf \047%%s\047 \047%s\047 ;;", p[i], nt[i]; print " esac; }"
    printf "planted_sha() { case \"$1\" in"; for (i = 1; i <= n; i++) if (sh[i] != "-") { s = sh[i]; gsub(/,/, " ", s); printf " */%s) printf \047%%s\047 \047%s\047 ;;", p[i], s }; print " esac; }"
    print "WORM_REF_NOTE=\047" ref "\047"
    print "# <<< planted"
    print "# >>> planted: generated from data/planted.tsv by tools/gen.sh. Edit that file, then run it." > "/dev/stderr"
    print "$WormNameAlone = \047" run(fa) "\047" > "/dev/stderr"
    print "$WormNameWeak = \047" run(fw) "\047" > "/dev/stderr"
    printf "function Planted-Note([string]$p) { switch -CaseSensitive ($p) {" > "/dev/stderr"
    for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", p[i], nt[i] > "/dev/stderr"; print " default { $null } } }" > "/dev/stderr"
    printf "function Planted-Sha([string]$p) { switch -CaseSensitive ($p) {" > "/dev/stderr"
    for (i = 1; i <= n; i++) if (sh[i] != "-") { s = sh[i]; gsub(/,/, " ", s); printf " \047%s\047 { \047%s\047 }", p[i], s > "/dev/stderr" }; print " default { \047\047 } } }" > "/dev/stderr"
    printf "$PlantedAlone = @(" > "/dev/stderr"; k = 0; for (i = 1; i <= n; i++) if (al[i] == "yes") printf "%s\047%s\047", (k++ ? ", " : ""), p[i] > "/dev/stderr"; print ")" > "/dev/stderr"
    print "$WormRefNote = \047" ref "\047" > "/dev/stderr"
    print "# <<< planted" > "/dev/stderr"
  }' > "$WORK/planted.sh" 2> "$WORK/planted.ps1"

# --- hosted platforms -------------------------------------------------------
# Rows are id|name|commands|paths|found|advice|summary, paths separated by ; (a folder ends in /).
rows data/platforms.tsv | awk -F '\t' "$PATH_SH"'
  function shs(s,   a, k, i, o) { if (s == "-") return "-"; k = split(s, a, ";"); for (i = 1; i <= k; i++) o = o (i > 1 ? ";" : "") sh(a[i]); return o }
  BEGIN { print "# >>> platforms: generated from data/platforms.tsv by tools/gen.sh. Edit that file, then run it."
          printf "PLATFORMS=\"" }
  { printf "%s%s|%s|%s|%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, $3, shs($4), $5, $6, $7 }
  END { print "\""; print "# <<< platforms" }' > "$WORK/platforms.sh"
rows data/platforms.tsv | awk -F '\t' "$PATH_PS"'
  function list(s, want,   a, k, i, o, p, d) {
    if (s == "-") return "@()"; k = split(s, a, ";")
    for (i = 1; i <= k; i++) { p = a[i]; d = p ~ /\/$/; if (d != want) continue; sub(/\/$/, "", p); o = o (o == "" ? "" : ", ") ps(p) }
    return "@(" o ")"
  }
  function cmds(s,   a, k, i, o) { if (s == "-") return "@()"; k = split(s, a, " "); for (i = 1; i <= k; i++) o = o (i > 1 ? ", " : "") "\047" a[i] "\047"; return "@(" o ")" }
  BEGIN { print "# >>> platforms: generated from data/platforms.tsv by tools/gen.sh. Edit that file, then run it."
          print "$Platforms = @(" }
  { if (n++) print ","
    printf "  @{ Id = \047%s\047; Name = \047%s\047; Cmds = %s; Dirs = %s; Files = %s; Found = \047%s\047; Advice = %s; Summary = %s }", $1, $2, cmds($3), list($4, 1), list($4, 0), $5, psq($6), psq($7) }
  END { print ")"; print "# <<< platforms" }' > "$WORK/platforms.ps1"

# --- agents set to run commands without asking ---------------------------------------
# Rows are agent|os|path|setting|pattern|pattern..., a {PROJECT}/ path kept as it is.
rows data/auto-approve.tsv | awk -F '\t' "$PATH_SH"'
  BEGIN { print "# >>> auto-approve: generated from data/auto-approve.tsv by tools/gen.sh. Edit that file, then run it."
          printf "AA_TABLE=\"" }
  { printf "%s%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, ($3 ~ /^\{PROJECT\}/ ? $3 : sh($3)), $4
    for (i = 5; i <= NF; i++) { p = $i; gsub(/"/, "\\\"", p); printf "|%s", p }
    if ($3 ~ /^\{PROJECT\}\//) { q = substr($3, 11); if (!(q in pj)) { pj[q] = 1; po = po (po == "" ? "" : "\n") q } } }
  END { print "\""; print "AA_PROJECT=\047" po "\047"; print "# <<< auto-approve" }' > "$WORK/auto-approve.sh"
rows data/auto-approve.tsv | awk -F '\t' "$PATH_PS"'
  BEGIN { print "# >>> auto-approve: generated from data/auto-approve.tsv by tools/gen.sh. Edit that file, then run it."
          print "$AaTable = @(" }
  { o = ""; for (i = 5; i <= NF; i++) o = o (i > 5 ? ", " : "") "\047" $i "\047"
    printf "  ,@(\047%s\047, \047%s\047, %s, \047%s\047, @(%s))\n", $1, $2, ($3 ~ /^\{PROJECT\}/ ? "\047" $3 "\047" : ps($3)), $4, o
    if ($3 ~ /^\{PROJECT\}\//) { q = substr($3, 11); if (!(q in pj)) { pj[q] = 1; po = po (po == "" ? "" : ", ") "\047" q "\047" } } }
  END { print ")"; print "$AaProject = @(" po ")"; print "# <<< auto-approve" }' > "$WORK/auto-approve.ps1"

# --- agent versions with a published fix -----------------------------------------
# Rows are id|name|os|kind|where|first|fixed|hole|advisory, first - when the range has none, fixed !last
# for an advisory that no version fixes (>=first <=last), and the advisory without https://.
rows data/outdated.tsv | awk -F '\t' "$PATH_SH"'
  BEGIN { print "# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it."
          printf "OUT_TABLE=\"" }
  { n = split($6, r, " "); lo = n == 2 ? substr(r[1], 3) : "-"; hi = r[n] ~ /^<=/ ? "!" substr(r[n], 3) : substr(r[n], 2)
    printf "%s%s|%s|%s|%s|%s|%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, $3, $4, ($4 ~ /^(plist|folder)$/ ? sh($5) : $5), lo, hi, $7, substr($8, 9) }
  END { print "\""; print "# <<< outdated" }' > "$WORK/outdated.sh"
rows data/outdated.tsv | awk -F '\t' "$PATH_PS"'
  BEGIN { print "# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it."
          print "$OutTable = @(" }
  { n = split($6, r, " "); lo = n == 2 ? substr(r[1], 3) : "-"; hi = r[n] ~ /^<=/ ? "!" substr(r[n], 3) : substr(r[n], 2)
    printf "  ,@(\047%s\047, \047%s\047, \047%s\047, \047%s\047, %s, \047%s\047, \047%s\047, \047%s\047, \047%s\047)\n", $1, $2, $3, $4, ($4 ~ /^(plist|folder)$/ ? ps($5) : "\047" $5 "\047"), lo, hi, $7, substr($8, 9) }
  END { print ")"; print "# <<< outdated" }' > "$WORK/outdated.ps1"

# --- extensions that shipped malware ------------------------------------------------
# Rows are "id version incident registry os", registry openvsx or any and os where the malware could
# run (see the data file).
rows data/bad-extensions.tsv | awk -F '\t' '
  BEGIN { print "# >>> bad-extensions: generated from data/bad-extensions.tsv by tools/gen.sh. Edit that file, then run it."; printf "BAD_EXT=\"" }
  { printf "%s%s %s %s %s %s", (NR > 1 ? "\n" : ""), $1, $2, $3, $4, $5 }
  END { print "\""; print "# <<< bad-extensions" }' > "$WORK/bad-extensions.sh"
rows data/bad-extensions.tsv | awk -F '\t' '
  BEGIN { print "# >>> bad-extensions: generated from data/bad-extensions.tsv by tools/gen.sh. Edit that file, then run it."; print "$BadExt = @\047" }
  { print $1 " " $2 " " $3 " " $4 " " $5 }
  END { print "\047@"; print "# <<< bad-extensions" }' > "$WORK/bad-extensions.ps1"

# --- splice -----------------------------------------------------------------
splice() { # file block-name generated-file
  awk -v name="$2" -v gen="$3" '
    $0 ~ "^# >>> " name "[: ]" || $0 == "# >>> " name { while ((getline l < gen) > 0) print l; skip = 1; found = 1; next }
    skip && $0 == "# <<< " name { skip = 0; next }
    !skip { print }
    END { if (!found) { print "no \"# >>> " name "\" marker" > "/dev/stderr"; exit 3 } }' "$1"
}
# --- the agents table and the ownership walk, for gird-fleet.sh ---------------------
# Their home is gird-check.sh; root in gird-fleet.sh runs the same copies.
awk '/^# >>> agents[: ]/ { on = 1; print "# >>> agents: copied from gird-check.sh by tools/gen.sh. Edit it there, then run it."; next }
  on { print } /^# <<< agents$/ { exit }' gird-check.sh > "$WORK/agents.sh"
grep -q '^# <<< agents$' "$WORK/agents.sh" || { echo "gird-check.sh has no agents block"; exit 1; }
awk '/^# >>> owned-walk[: ]/ { on = 1; print "# >>> owned-walk: copied from gird-check.sh by tools/gen.sh. Edit it there, then run it."; next }
  on { print } /^# <<< owned-walk$/ { exit }' gird-check.sh > "$WORK/owned-walk.sh"
grep -q '^# <<< owned-walk$' "$WORK/owned-walk.sh" || { echo "gird-check.sh has no owned-walk block"; exit 1; }

RC=0
for f in gird-check.sh gird-check.ps1 gird-fleet.sh; do
  if [ "$f" = gird-fleet.sh ]; then blocks="owned-walk keys auto-approve agents incidents indicators outdated platforms"
  else blocks="keys public-values sessions planted auto-approve incidents bad-pypi indicators bad-npm bad-extensions outdated platforms"; fi
  ext=${f##*.}; cp "$f" "$WORK/b"
  for blk in $blocks; do
    splice "$WORK/b" "$blk" "$WORK/$blk.$ext" > "$WORK/a" && mv "$WORK/a" "$WORK/b" || { RC=1; continue 2; }
  done
  if [ "$CHECK" -eq 1 ]; then
    if ! cmp -s "$f" "$WORK/b"; then echo "$f is out of date with data/ (or, for gird-fleet.sh, with gird-check.sh): run bash tools/gen.sh"; diff "$f" "$WORK/b" | head -n 8; RC=1; fi
  elif ! cmp -s "$f" "$WORK/b"; then cat "$WORK/b" > "$f"; echo "updated $f"; fi
done
exit "$RC"
