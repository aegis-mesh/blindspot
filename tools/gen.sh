#!/usr/bin/env bash
# Writes the data files into gird-check.sh and gird-check.ps1, between each block's "# >>> <name>"
# and "# <<< <name>" markers: key types (data/keys.tsv), agent session locations
# (data/sessions.tsv), bad npm packages (data/bad-npm.tsv) and incidents (data/incidents.tsv). The scripts stay single files people
# can download and check.
#
#   bash tools/gen.sh           rewrite the blocks
#   bash tools/gen.sh --check   exit 1 if a block differs from the data files
set -eu
cd "$(dirname "$0")/.."
CHECK=0; [ "${1:-}" = --check ] && CHECK=1
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

rows() { grep -v '^#' "$1" | grep -v '^[[:space:]]*$'; }
# Characters that would break the generated bash, awk or PowerShell are refused.
bad=$(rows data/keys.tsv | awk -F '\t' 'NF != 4 || $2 ~ /[\047"`$\\]/ || $3 ~ /[\047"`\/]/ || $4 ~ /[\047`]/ { print "data/keys.tsv: " $0 }'
      rows data/incidents.tsv | awk -F '\t' 'NF != 6 || $1 !~ /^[a-z0-9]+$/ || $2 ~ /[\047"`$\\]/ || $3 !~ /^[A-Z][a-z]+ [0-9]{4}$/ || $4 ~ /[\047"`$\\]/ || $5 !~ /^https:\/\/[^ \047"`$]+$/ || $6 !~ /^(act|update)$/ { print "data/incidents.tsv: " $0 }'
      rows data/bad-npm.tsv | awk -F '\t' 'NF != 3 || $1 !~ /^(@[a-z0-9._~-]+\/)?[a-z0-9._~-]+$/ || $2 !~ /^(\*|[0-9][0-9A-Za-z.+-]*)$/ || $3 !~ /^[a-z0-9]+$/ { print "data/bad-npm.tsv: " $0 }'
      rows data/sessions.tsv | awk -F '\t' 'NF != 5 || $1 !~ /^(all|mac|linux|win)$/ || $2 !~ /^(read|sealed)$/ || $3 ~ /[\047"`$|\\]/ || $4 ~ /[\047"`$|\\]/ || $4 ~ /\{ENV:[^}]*\{/ { print "data/sessions.tsv: " $0 }')
if [ -n "$bad" ]; then printf 'Lines with a field gen.sh cannot write safely:\n%s\n' "$bad" >&2; exit 2; fi

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
rows data/sessions.tsv | awk -F '\t' '
  function sh(p,   v, fb, rest, k) {
    if (p ~ /^\{ENV:/) {
      k = index(p, "}"); v = substr(p, 6, k - 6); rest = substr(p, k + 1)
      fb = substr(v, index(v, ":") + 1); v = substr(v, 1, index(v, ":") - 1)
      return "${" v ":-" sh(fb) "}" rest
    }
    sub(/^~/, "$H", p); sub(/^\{AS\}/, "$AS", p); sub(/^\{LOCALAPPDATA\}/, "$WLAPP", p)
    sub(/^\{XDG_DATA\}/, "${XDG_DATA_HOME:-$H/.local/share}", p); sub(/^\{GOOSE_DATA\}/, "$GOOSE_DATA", p)
    return p
  }
  BEGIN { print "# >>> sessions: generated from data/sessions.tsv by tools/gen.sh. Edit that file, then run it."
          printf "SESS_TABLE=\"" }
  { printf "%s%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, $3, sh($4) }
  END { print "\""; print "# <<< sessions" }' > "$WORK/sessions.sh"

rows data/sessions.tsv | awk -F '\t' '
  function ps(p,   v, fb, rest, k, base) {
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
  BEGIN { print "# >>> sessions: generated from data/sessions.tsv by tools/gen.sh. Edit that file, then run it."
          print "$SessTable = @(" }
  $1 == "all" || $1 == "win" { if (n++) print ","; printf "  @(\047%s\047, \047%s\047, %s)", $2, $3, ps($4) }
  END { print ")"; print "# <<< sessions" }' > "$WORK/sessions.ps1"

# --- incidents ---------------------------------------------------------------
# npm_label gives "name, month year"; incident_line adds what it did and the source's site;
# incident_level says whether a hit means a compromised machine (act) or a version to update.
rows data/incidents.tsv | awk -F '\t' '
  function host(u) { sub(/^https:\/\//, "", u); sub(/\/.*/, "", u); sub(/^www\./, "", u); return u }
  { id[NR] = $1; lab[NR] = $2 ", " $3; line[NR] = $2 ", " $3 ": " $4 ". " host($5); lv[NR] = $6; n = NR }
  END {
    print "# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it."
    printf "npm_label() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], lab[i]; print " esac; }"
    printf "incident_line() { case \"$1\" in"; for (i = 1; i <= n; i++) printf " %s) printf \047%%s\047 \047%s\047 ;;", id[i], line[i]; print " esac; }"
    printf "incident_level() { case \"$1\" in"; for (i = 1; i <= n; i++) if (lv[i] != "act") printf " %s) printf %s ;;", id[i], lv[i]; print " *) printf act ;; esac; }"
    print "# <<< incidents"
  }' > "$WORK/incidents.sh"
rows data/incidents.tsv | awk -F '\t' '
  function host(u) { sub(/^https:\/\//, "", u); sub(/\/.*/, "", u); sub(/^www\./, "", u); return u }
  { id[NR] = $1; lab[NR] = $2 ", " $3; line[NR] = $2 ", " $3 ": " $4 ". " host($5); lv[NR] = $6; n = NR }
  END {
    print "# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it."
    printf "function Npm-Label([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], lab[i]; print " default { $t } } }"
    printf "function Incident-Line([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) printf " \047%s\047 { \047%s\047 }", id[i], line[i]; print " default { $t } } }"
    printf "function Incident-Level([string]$t) { switch ($t) {"; for (i = 1; i <= n; i++) if (lv[i] != "act") printf " \047%s\047 { \047%s\047 }", id[i], lv[i]; print " default { \047act\047 } } }"
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
  ext=${f##*.}
  splice "$f" keys "$WORK/keys.$ext" > "$WORK/a" && splice "$WORK/a" sessions "$WORK/sessions.$ext" > "$WORK/c" &&
    splice "$WORK/c" bad-npm "$WORK/bad-npm.$ext" > "$WORK/d" && splice "$WORK/d" incidents "$WORK/incidents.$ext" > "$WORK/b" || { RC=1; continue; }
  if [ "$CHECK" -eq 1 ]; then
    if ! cmp -s "$f" "$WORK/b"; then echo "$f is out of date with data/: run bash tools/gen.sh"; diff "$f" "$WORK/b" | head -n 8; RC=1; fi
  elif ! cmp -s "$f" "$WORK/b"; then cat "$WORK/b" > "$f"; echo "updated $f"; fi
done
exit "$RC"
