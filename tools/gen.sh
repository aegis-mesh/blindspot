#!/usr/bin/env bash
# Writes the data files into gird-check.sh and gird-check.ps1, between each block's "# >>> <name>"
# and "# <<< <name>" markers: key types (data/keys.tsv), agent session locations
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
# What to do shows an incident's advice only for a package or extension found (bad-npm, bad-pypi,
# bad-extensions), so advice on any other incident would never be shown: it is refused.
PKG_IDS=" $(cat data/bad-npm.tsv data/bad-pypi.tsv data/bad-extensions.tsv | grep -v '^#' | awk -F '\t' 'NF >= 3 { printf "%s ", $3 }')"
# A path for a file check: a token or an absolute path first, at least one folder or file after
# it, and nothing a shell or PowerShell string would read as code, a glob or a separator.
PATH_OK='function path_ok(p,   r) {
    if (p ~ /[\047"`$|\\*?[;]/ || p ~ /\{ENV:[^}]*\{/ || p !~ /^(~|\{|\/)/) return 0
    r = p; sub(/^(~|\{[^}]*\})/, "", r); return r ~ /^\/[^\/]/
  }'
# Characters that would break the generated bash, awk or PowerShell are refused, and so is an
# incident id no line of data/incidents.tsv has.
bad=$(rows data/keys.tsv | awk -F '\t' 'NF != 4 || $2 ~ /[\047"`$\\]/ || $3 ~ /[\047"`\/]/ || $4 ~ /[\047`]/ { print "data/keys.tsv: " $0 }'
      rows data/incidents.tsv | awk -F '\t' -v pkg="$PKG_IDS" '(NF != 6 && NF != 7) || (NF == 7 && ($7 == "" || $7 ~ /[\047"`$|\\]/ || index(pkg, " " $1 " ") == 0)) || $1 !~ /^[a-z0-9]+$/ || $2 ~ /[\047"`$|\\]/ || $3 !~ /^[A-Z][a-z]+ [0-9]{4}$/ || $4 ~ /[\047"`$\\]/ || $5 !~ /^https:\/\/[^ \047"`$]+$/ || $6 !~ /^(act|update)$/ || seen[$1]++ { print "data/incidents.tsv: " $0 }'
      # npm's placeholder for a removed package (0.0.1-security, or 0.0.1-security.0 for a few names) is never malware, and the scripts skip it.
      rows data/bad-npm.tsv | awk -F '\t' -v ids="$IDS" 'NF != 3 || $1 !~ /^(@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/ || $2 !~ /^(\*|[0-9][0-9A-Za-z.+-]*)$/ || $2 ~ /^0\.0\.1-security(\.[0-9]+)?$/ || $3 !~ /^[a-z0-9]+$/ || index(ids, " " $3 " ") == 0 { print "data/bad-npm.tsv: " $0 }'
      rows data/sessions.tsv | awk -F '\t' 'NF != 5 || $1 !~ /^(all|mac|linux|win)$/ || $2 !~ /^(read|sealed)$/ || $3 ~ /[\047"`$|\\]/ || $4 ~ /[\047"`$|\\]/ || $4 ~ /\{ENV:[^}]*\{/ { print "data/sessions.tsv: " $0 }'
      # A Python incident means a compromised machine: one whose level is update is refused.
      rows data/bad-pypi.tsv | awk -F '\t' -v ids="$ACT_IDS" 'NF != 3 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9_.]*$/ || $2 !~ /^[0-9][0-9A-Za-z.+!]*$/ || index(ids, " " $3 " ") == 0 { print "data/bad-pypi.tsv: " $0 }'
      rows data/indicators.tsv | awk -F '\t' -v ids="$IDS" -v acts="$ACT_IDS" "$PATH_OK"'
        NF != 6 || index(ids, " " $1 " ") == 0 || $2 !~ /^(all|mac|linux|win)$/ || $3 !~ /^(wiper|startup|site|temp)$/ || $4 !~ /^(yes|no)$/ ||
        ($3 ~ /^(wiper|startup)$/ && !path_ok($5)) || ($3 == "wiper" && $5 !~ /gh-token-monitor/) || ($3 == "site" && $5 !~ /^[A-Za-z0-9._-]+$/) || ($3 == "temp" && $5 !~ /^[A-Za-z0-9._-]+\*?$/) ||
        ($3 ~ /^(site|temp)$/ && ($5 ~ /^\.+\*?$/ || index(acts, " " $1 " ") == 0)) ||
        ($3 == "startup" && ($6 == "-" || $6 ~ /[\047"`$|\\]/)) || ($3 != "startup" && $6 != "-") { print "data/indicators.tsv: " $0 }'
      rows data/planted.tsv | awk -F '\t' -v ids="$IDS" 'NF != 4 || $1 !~ /^\.(claude|vscode)$/ || $2 !~ /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$/ || index(ids, " " $3 " ") == 0 || $4 == "" || $4 ~ /[\047"`$|\\]/ || seen[$1 "/" $2]++ { print "data/planted.tsv: " $0 }'
      rows data/auto-approve.tsv | awk -F '\t' "$PATH_OK"'
        function pat_ok(s) { return s ~ /[^[:space:]]/ && s !~ /[\047`$|\\]/ }
        { ok = NF >= 5 && $1 != "" && $1 !~ /[\047"`$|\\]/ && $2 ~ /^(all|mac|linux|win)$/ && $4 != "" && $4 !~ /[\047"`$|\\]/
          if ($3 ~ /^\{PROJECT\}/) ok = ok && $3 ~ /^\{PROJECT\}(\/[A-Za-z0-9_.-]+){2,}$/ && $3 !~ /\/\.\.?(\/|$)/
          else ok = ok && path_ok($3)
          for (i = 5; i <= NF; i++) if (!pat_ok($i)) ok = 0
          if (!ok) print "data/auto-approve.tsv: " $0 }'
      # Lines of one tool must agree on its name, range, hole and advisory.
      rows data/outdated.tsv | awk -F '\t' "$PATH_OK"'
        function ver(s) { return s ~ /^[0-9]+(\.[0-9]+)*$/ }
        { ok = NF == 8 && $1 ~ /^[a-z0-9]+$/ && $2 != "" && $2 !~ /[\047"`$|\\]/ && $3 ~ /^(all|mac|linux|win)$/ && $4 ~ /^(plist|folder|npm|mcparg)$/
          if ($4 ~ /^(plist|folder)$/) ok = ok && path_ok($5); else ok = ok && $5 ~ /^(@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/
          if ($4 == "plist") ok = ok && $5 ~ /\/Info\.plist$/
          n = split($6, r, " ")
          ok = ok && ((n == 1 && r[1] ~ /^</ && ver(substr(r[1], 2))) || (n == 2 && r[1] ~ /^>=/ && ver(substr(r[1], 3)) && r[2] ~ /^</ && ver(substr(r[2], 2))))
          ok = ok && $7 != "" && $7 !~ /[\047"`$|\\]/ && $8 ~ /^https:\/\/[^ \047"`$|\\]+$/
          k = $2 "\t" $6 "\t" $7 "\t" $8; if (($1 in same) && same[$1] != k) ok = 0; same[$1] = k
          if (!ok) print "data/outdated.tsv: " $0 }'
      # An extension that shipped malware means a compromised machine: an update-level incident is refused.
      rows data/bad-extensions.tsv | awk -F '\t' -v ids="$ACT_IDS" 'NF != 3 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$/ || $2 !~ /^(\*|[0-9]+(\.[0-9]+)*)$/ || index(ids, " " $3 " ") == 0 || seen[tolower($1) " " $2]++ { print "data/bad-extensions.tsv: " $0 }'
      rows data/platforms.tsv | awk -F '\t' -v ids="$IDS" "$PATH_OK"'
        function paths_ok(s,   n, a, i) { if (s == "-") return 1; n = split(s, a, ";"); for (i = 1; i <= n; i++) if (!path_ok(a[i])) return 0; return 1 }
        NF != 7 || index(ids, " " $1 " ") == 0 || $2 == "" || $2 ~ /[\047"`$|\\]/ || $3 !~ /^(-|[A-Za-z0-9_][A-Za-z0-9._+-]*( [A-Za-z0-9_][A-Za-z0-9._+-]*)*)$/ ||
        !paths_ok($4) || $5 !~ /^(installed|CLI found)$/ || $6 == "" || $6 ~ /["`$|\\]/ || $7 == "" || $7 ~ /["`$|\\]/ || seen[$1]++ { print "data/platforms.tsv: " $0 }')
# The scripts are ASCII only (PowerShell 5.1 reads a file without a BOM as the ANSI code page).
_na=$(LC_ALL=C grep -n '[^ -~	]' data/*.tsv | sed 's/^/not ASCII (or a CRLF line end): /')
bad="$bad${bad:+${_na:+
}}$_na"
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
    sub(/^\{XDG_DATA\}/, "${XDG_DATA_HOME:-$H/.local/share}", p); sub(/^\{GOOSE_DATA\}/, "$GOOSE_DATA", p)
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
    else if (p ~ /^\{GOOSE_DATA\}/) { base = "(J $AppData \047Block/goose/data\047)"; rest = substr(p, 13) }
    sub(/^\//, "", rest)
    return rest == "" ? base : "(J " base " \047" rest "\047)"
  }
  function psq(s) { gsub(/\047/, "\047\047", s); return "\047" s "\047" }'

# --- keys -------------------------------------------------------------------
rows data/keys.tsv | awk -F '\t' '
  { id[NR] = $1; nm[NR] = $2; st[NR] = $3; pat[NR] = $4; n = NR }
  END {
    print "# >>> keys: generated from data/keys.tsv by tools/gen.sh. Edit that file, then run it."
    all = ""; ids = ""; starts = ""
    for (i = 1; i <= n; i++) { all = all (i > 1 ? "|" : "") pat[i]; ids = ids (i > 1 ? " " : "") id[i]; starts = starts (i > 1 ? "|" : "") st[i] }
    print "ALL_KEYS=\047" all "\047"
    print "PROVIDER_IDS=\"" ids "\""
    print "KEY_STARTS=\047" starts "\047"
    print "PROV_AWK=\047"
    print "function prov(s) {"
    print "  sub(/^[^A-Za-z]*\\\\[ntr\"]/, \"\", s); sub(/^[^A-Za-z]+/, \"\", s)"
    for (i = 1; i <= n; i++) print "  if (s ~ /^(" st[i] ")/) return \"" nm[i] "\""
    print "  return \"\""
    print "}\047"
    printf "prov_id() { case \"$1\" in"
    for (i = 1; i <= n; i++) printf " \"%s\") printf %s ;;", nm[i], id[i]
    print " esac; }"
    print "# <<< keys"
  }' > "$WORK/keys.sh"

rows data/keys.tsv | awk -F '\t' '
  { id[NR] = $1; nm[NR] = $2; st[NR] = $3; pat[NR] = $4; n = NR }
  END {
    print "# >>> keys: generated from data/keys.tsv by tools/gen.sh. Edit that file, then run it."
    all = ""; ids = ""; starts = ""
    for (i = 1; i <= n; i++) { all = all (i > 1 ? "|" : "") pat[i]; ids = ids (i > 1 ? " " : "") id[i]; starts = starts (i > 1 ? "|" : "") st[i] }
    print "$ALL_KEYS = \047" all "\047"
    print "$PROVIDER_IDS = \047" ids "\047"
    print "$KEY_STARTS = \047" starts "\047"
    print "$KeyProviderFn = @\047"
    print "function Key-Provider([string]$s) {"
    print "  $s = $s -replace \047^[^A-Za-z]*\\\\[ntr\"]\047, \047\047 -replace \047^[^A-Za-z]+\047, \047\047"
    for (i = 1; i <= n; i++) print "  if ($s -cmatch \047^(" st[i] ")\047) { return \047" nm[i] "\047 }"
    print "  $null"
    print "}"
    printf "function Provider-Id([string]$n) { switch -CaseSensitive ($n) {"
    for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", nm[i], id[i]
    print " default { $null } } }"
    print "\047@"
    print "# <<< keys"
  }' > "$WORK/keys.ps1"

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
# incident_name is the name alone, incident_source the source without https:// and incident_advice
# the incident's own fix, if it has one.
rows data/incidents.tsv | awk -F '\t' '
  function host(u) { sub(/^https:\/\//, "", u); sub(/\/.*/, "", u); sub(/^www\./, "", u); return u }
  { id[NR] = $1; nm[NR] = $2; lab[NR] = $2 ", " $3; line[NR] = $2 ", " $3 ": " $4 ". " host($5); src[NR] = substr($5, 9); lv[NR] = $6; adv[NR] = $7; n = NR }
  END {
    print "# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it."
    printf "npm_label() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], lab[i]; print " esac; }"
    printf "incident_line() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], line[i]; print " esac; }"
    printf "incident_level() { case \"$1\" in"; for (i = 1; i <= n; i++) if (lv[i] != "act") printf " %s) printf %s ;;", id[i], lv[i]; print " *) printf act ;; esac; }"
    printf "incident_name() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], nm[i]; print " esac; }"
    printf "incident_source() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], src[i]; print " esac; }"
    printf "incident_advice() { case \"$1\" in"; for (i = 1; i <= n; i++) if (adv[i] != "") printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], adv[i]; print " esac; }"
    print "# <<< incidents"
  }' > "$WORK/incidents.sh"
rows data/incidents.tsv | awk -F '\t' '
  function host(u) { sub(/^https:\/\//, "", u); sub(/\/.*/, "", u); sub(/^www\./, "", u); return u }
  { id[NR] = $1; nm[NR] = $2; lab[NR] = $2 ", " $3; line[NR] = $2 ", " $3 ": " $4 ". " host($5); src[NR] = substr($5, 9); lv[NR] = $6; adv[NR] = $7; n = NR }
  END {
    print "# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it."
    printf "function Npm-Label([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], lab[i]; print " default { $t } } }"
    printf "function Incident-Line([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], line[i]; print " default { $t } } }"
    printf "function Incident-Level([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) if (lv[i] != "act") printf " \047%s\047 { \047%s\047 }", id[i], lv[i]; print " default { \047act\047 } } }"
    printf "function Incident-Name([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], nm[i]; print " default { $t } } }"
    printf "function Incident-Source([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], src[i]; print " default { $t } } }"
    printf "function Incident-Advice([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) if (adv[i] != "") printf " \047%s\047 { \047%s\047 }", id[i], adv[i]; print " default { \047\047 } } }"
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
# PY_INCIDENTS lists every incident with a bad version or a site or temp indicator, in order:
# section 5 has one row for each.
{ rows data/bad-pypi.tsv | awk -F '\t' '{ print "P\t" $0 }'; rows data/indicators.tsv | awk -F '\t' '{ print "I\t" $0 }'; } | awk -F '\t' '
  $1 == "P" { pk[++n] = $2 " " $3 " " $4; if (!seen[$4]++) inc[++m] = $4 }
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
  { printf "  ,@(\047%s\047, \047%s\047, \047%s\047, \047%s\047, %s, \047%s\047)\n", $1, $2, $3, $4, ($3 ~ /^(site|temp)$/ ? "\047" $5 "\047" : ps($5)), $6 }
  END { print ")"; print "# <<< indicators" }' > "$WORK/indicators.ps1"

# --- files planted in a project ----------------------------------------------
# PLANTED_ERE matches the planted paths; WORM_RUN any planted file name in either folder, as a
# hook or a task names it. A settings file that runs one is shown with "runs" and the note, or a
# general line when the notes differ.
rows data/planted.tsv | awk -F '\t' '
  function ere(s) { gsub(/\./, "\\.", s); return s }
  { p[NR] = $1 "/" $2; nt[NR] = $4; n = NR
    if (!sf[$1]++) fo = fo (fo == "" ? "" : "|") substr($1, 2)
    if (!sn[$2]++) fi = fi (fi == "" ? "" : "|") ere($2)
    if (NR == 1) note = $4; else if (note != $4) note = "" }
  END {
    ref = note == "" ? "runs a file a worm plants" : "runs " note
    print "# >>> planted: generated from data/planted.tsv by tools/gen.sh. Edit that file, then run it."
    printf "PLANTED=\047"; for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "\n" : ""), p[i]; print "\047"
    printf "PLANTED_ERE=\047"; for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "|" : ""), ere(p[i]); print "\047"
    print "WORM_RUN=\047\\.(" fo ")[/\\\\]+(" fi ")\047"
    printf "planted_note() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " */%s) printf \047%%s\047 \047%s\047 ;;", p[i], nt[i]; print " esac; }"
    print "WORM_REF_NOTE=\047" ref "\047"
    print "# <<< planted"
    print "# >>> planted: generated from data/planted.tsv by tools/gen.sh. Edit that file, then run it." > "/dev/stderr"
    print "$WormName = \047\\.(" fo ")[/\\\\]+(" fi ")\047" > "/dev/stderr"
    printf "function Planted-Note([string]$p) { switch -CaseSensitive ($p) {" > "/dev/stderr"
    for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", p[i], nt[i] > "/dev/stderr"; print " default { $null } } }" > "/dev/stderr"
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
# Rows are id|name|os|kind|where|first|fixed|hole|advisory, first - when the range has none and the
# advisory without https://.
rows data/outdated.tsv | awk -F '\t' "$PATH_SH"'
  BEGIN { print "# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it."
          printf "OUT_TABLE=\"" }
  { n = split($6, r, " "); lo = n == 2 ? substr(r[1], 3) : "-"; hi = substr(r[n], 2)
    printf "%s%s|%s|%s|%s|%s|%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, $3, $4, ($4 ~ /^(plist|folder)$/ ? sh($5) : $5), lo, hi, $7, substr($8, 9) }
  END { print "\""; print "# <<< outdated" }' > "$WORK/outdated.sh"
rows data/outdated.tsv | awk -F '\t' "$PATH_PS"'
  BEGIN { print "# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it."
          print "$OutTable = @(" }
  { n = split($6, r, " "); lo = n == 2 ? substr(r[1], 3) : "-"; hi = substr(r[n], 2)
    printf "  ,@(\047%s\047, \047%s\047, \047%s\047, \047%s\047, %s, \047%s\047, \047%s\047, \047%s\047, \047%s\047)\n", $1, $2, $3, $4, ($4 ~ /^(plist|folder)$/ ? ps($5) : "\047" $5 "\047"), lo, hi, $7, substr($8, 9) }
  END { print ")"; print "# <<< outdated" }' > "$WORK/outdated.ps1"

# --- extensions that shipped malware ------------------------------------------------
rows data/bad-extensions.tsv | awk -F '\t' '
  BEGIN { print "# >>> bad-extensions: generated from data/bad-extensions.tsv by tools/gen.sh. Edit that file, then run it."; printf "BAD_EXT=\"" }
  { printf "%s%s %s %s", (NR > 1 ? "\n" : ""), $1, $2, $3 }
  END { print "\""; print "# <<< bad-extensions" }' > "$WORK/bad-extensions.sh"
rows data/bad-extensions.tsv | awk -F '\t' '
  BEGIN { print "# >>> bad-extensions: generated from data/bad-extensions.tsv by tools/gen.sh. Edit that file, then run it."; print "$BadExt = @\047" }
  { print $1 " " $2 " " $3 }
  END { print "\047@"; print "# <<< bad-extensions" }' > "$WORK/bad-extensions.ps1"

# --- splice -----------------------------------------------------------------
splice() { # file block-name generated-file
  awk -v name="$2" -v gen="$3" '
    $0 ~ "^# >>> " name "[: ]" || $0 == "# >>> " name { while ((getline l < gen) > 0) print l; skip = 1; found = 1; next }
    skip && $0 == "# <<< " name { skip = 0; next }
    !skip { print }
    END { if (!found) { print "no \"# >>> " name "\" marker" > "/dev/stderr"; exit 3 } }' "$1"
}
RC=0
for f in gird-check.sh gird-check.ps1; do
  ext=${f##*.}; cp "$f" "$WORK/b"
  for blk in keys sessions planted auto-approve incidents bad-pypi indicators bad-npm bad-extensions outdated platforms; do
    splice "$WORK/b" "$blk" "$WORK/$blk.$ext" > "$WORK/a" && mv "$WORK/a" "$WORK/b" || { RC=1; continue 2; }
  done
  if [ "$CHECK" -eq 1 ]; then
    if ! cmp -s "$f" "$WORK/b"; then echo "$f is out of date with data/: run bash tools/gen.sh"; diff "$f" "$WORK/b" | head -n 8; RC=1; fi
  elif ! cmp -s "$f" "$WORK/b"; then cat "$WORK/b" > "$f"; echo "updated $f"; fi
done
exit "$RC"
