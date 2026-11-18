#!/usr/bin/env bash
# Writes the data files into gird-check.sh and gird-check.ps1 (and the tables the fleet scripts read
# into gird-fleet.sh and gird-fleet.ps1), between each block's "# >>> <name>"
# and "# <<< <name>" markers: key types (data/keys.tsv), agent session locations
# (data/sessions.tsv), bad npm packages (data/bad-npm.tsv), incidents (data/incidents.tsv), bad
# Python packages (data/bad-pypi.tsv), files malware leaves on disk (data/indicators.tsv), files
# worms plant in a project (data/planted.tsv), hosted platforms that leaked stored secrets
# (data/platforms.tsv), agents set to run commands without asking (data/auto-approve.tsv), agent
# versions with a published fix (data/outdated.tsv), extensions that shipped malware
# (data/bad-extensions.tsv), variables that move an agent's or a tool's folders
# (data/folder-vars.tsv), coding agents (data/agents.tsv), the fixed lists the report sends
# (data/mcp-clients.tsv, data/mcp-servers.tsv, data/key-places.tsv), MCP configs (data/mcp-files.tsv)
# and the lines an account run prints (data/account-run.tsv, written into the fleet scripts, and
# checked against what gird-check.sh and gird-check.ps1 print). The scripts stay single files people
# can download and check.
#
#   bash tools/gen.sh           rewrite the blocks, and build blindspot-fleet.sh and blindspot-fleet.ps1
#   bash tools/gen.sh --check   exit 1 if a block differs from the data files, or a one-file build
#                               would not be under its MDM's size limit or is not what gen.sh builds
#
# Building blindspot-fleet.ps1 needs PowerShell: pwsh on PATH, or PWSH=/path/to/pwsh. Without it the
# blocks and blindspot-fleet.sh are still written or checked, and the exit code is 3 when they are right.
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
# No regex intervals ({n}) in the awk programs: older mawk (Ubuntu 22.04) does not support them.
# Characters that would break the generated bash, awk or PowerShell are refused, and so is an
# incident id no line of data/incidents.tsv has. A key id is lowercase letters, digits and _, and
# names its provider once: gird.ai's counts are keyed on it. The regexes spell out counts
# ([0-9][0-9][0-9][0-9], not [0-9]{4}): Debian 12's mawk has no {n} intervals and would refuse every line.
bad=$(rows data/keys.tsv | awk -F '\t' 'NF != 4 || $1 !~ /^[a-z0-9_]+$/ || seen[$1]++ || $2 ~ /[\047"`$\\]/ || $3 ~ /[\047"`\/]/ || $4 ~ /[\047`]/ { print "data/keys.tsv: " $0 }'
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
        !paths_ok($4) || $5 !~ /^(installed|CLI found)$/ || $6 == "" || $6 ~ /["`$|\\]/ || $7 == "" || $7 ~ /["`$|\\]/ || seen[$1]++ { print "data/platforms.tsv: " $0 }'
      # A folder is from ~ (or, for Windows, {LOCALAPPDATA} or {APPDATA}), below it, and holds nothing a
      # shell or PowerShell string would read as code; a script is a path below the tool's folder.
      rows data/folder-vars.tsv | awk -F '\t' '
        function dirs_ok(s, win,   n, a, i) { if (s == "-") return 1; n = split(s, a, ";"); for (i = 1; i <= n; i++) {
            if (a[i] ~ /[\047"`$\\*?;]/ || a[i] ~ /\/\.\.?(\/|$)/ || a[i] ~ /\/$/) return 0
            if (a[i] !~ /^~\/[^\/]/ && !(win && a[i] ~ /^\{(LOCALAPPDATA|APPDATA)\}\/[^\/]/)) return 0 }
          return 1 }
        function scripts_ok(s,   n, a, i) { if (s == "-") return 1; n = split(s, a, ";"); for (i = 1; i <= n; i++) if (a[i] !~ /^[A-Za-z0-9_][A-Za-z0-9_.-]*(\/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$/) return 0; return 1 }
        NF != 5 || $1 !~ /^[A-Za-z_][A-Za-z0-9_]*$/ || $2 !~ /^(agent|tool)$/ || !dirs_ok($3, 0) || !dirs_ok($4, 1) || !scripts_ok($5) || seen[$1]++ { print "data/folder-vars.tsv: " $0 }'
      # A path is a token or ~, then folders and files made of plain characters; - is none.
      rows data/agents.tsv | awk -F '\t' '
        function paths_ok(s, toks,   n, a, i, t) { if (s == "-") return 1; n = split(s, a, ";"); for (i = 1; i <= n; i++) {
            if (a[i] ~ /^\{[A-Z_]+\}/) { t = substr(a[i], 2, index(a[i], "}") - 2); if (index(" " toks " ", " " t " ") == 0) return 0; r = substr(a[i], length(t) + 3) }
            else if (a[i] ~ /^~\//) r = substr(a[i], 2); else return 0
            if (r != "" && r !~ /^(\/[A-Za-z0-9 ._-]+)+$/) return 0
            if (r == "" && a[i] ~ /^~/) return 0 }
          return 1 }
        NF != 7 || $1 == "" || $1 ~ /[\047"`$|\\;]/ || $2 !~ /^(-|[a-z0-9._-]+(;[a-z0-9._-]+)*)$/ ||
        !paths_ok($3, "AS GOOSE_CFG GOOSE_DATA APP_CLAUDE APP_CURSOR APP_WINDSURF APP_DEVIN APP_ANTIGRAVITY") || !paths_ok($4, "AS GOOSE_CFG GOOSE_DATA") ||
        !paths_ok($5, "LOCALAPPDATA APPDATA GOOSE_DATA") || !paths_ok($6, "LOCALAPPDATA APPDATA GOOSE_DATA") ||
        $7 !~ /^[a-z0-9-]+$/ || seen[$7]++ { print "data/agents.tsv: " $0 }'
      # other, for any other file, is the last client and the only one no config of data/mcp-files.tsv names.
      rows data/mcp-clients.tsv | awk -F '\t' 'NF != 2 || $1 !~ /^[a-z0-9-]+$/ || $2 == "" || seen[$1]++ { print "data/mcp-clients.tsv: " $0 } { last = $1 } END { if (last != "other") print "data/mcp-clients.tsv: other is not the last line" }'
      rows data/mcp-servers.tsv | awk -F '\t' '{ n = split($2, a, ","); ok = NF == 2 && $1 ~ /^[a-z0-9-]+$/ && !seen[$1]++ && ($2 == "-" || n > 0)
          if ($2 != "-") for (i = 1; i <= n; i++) { if (a[i] !~ /^[a-z0-9-]+$/ || (a[i] in seen) || (a[i] in al)) ok = 0; al[a[i]] = 1 }
          if (!ok) print "data/mcp-servers.tsv: " $0 }
        END { for (x in al) if (x in seen) print "data/mcp-servers.tsv: " x " is an id and an alias" }'
      rows data/key-places.tsv | awk -F '\t' 'NF != 2 || $1 !~ /^[a-z_]+$/ || $2 == "" || seen[$1]++ { print "data/key-places.tsv: " $0 }'
      _cl=" $(rows data/mcp-clients.tsv | cut -f1 | tr '\n' ' ')"
      rows data/mcp-files.tsv | awk -F '\t' -v cl="$_cl" '
        function path_ok(p, toks,   t, r) {
          if (p ~ /^\{[A-Z_]+\}\//) { t = substr(p, 2, index(p, "}") - 2); if (index(" " toks " ", " " t " ") == 0) return 0; r = substr(p, length(t) + 3) }
          else if (p ~ /^~\//) r = substr(p, 2); else return 0
          return r ~ /^(\/[A-Za-z0-9 ._-]+)+$/ }
        NF != 4 || $1 == "" || $1 ~ /[\047"`$|\\;]/ || $2 == "other" || index(cl, " " $2 " ") == 0 || !path_ok($3, "AS GOOSE_CFG") || !path_ok($4, "APPDATA LOCALAPPDATA") { print "data/mcp-files.tsv: " $0 }'
      rows data/account-run.tsv | awk -F '\t' 'NF != 2 || $1 !~ /^[a-z_]+$/ || $2 !~ /^(one|ids|number|flag|word)$/ || seen[$1]++ { print "data/account-run.tsv: " $0 }
        NR == 1 { first = $1 } { last = $1 } END { if (first != "v" || last != "end") print "data/account-run.tsv: the first key is not v or the last not end" }')
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

# --- variables that move an agent's or a tool's folders, for an account run ---------------
# gird-check.sh gets the list of each kind, fleet_dflt, the folders of the sh column, and fleet_scripts,
# the tools' own scripts; gird-check.ps1 the lists, the folders of the windows column and the tools' own
# scripts. Windows reads a variable's name in any case, so a PowerShell table keeps a name's first line
# (npm_config_prefix's).
rows data/folder-vars.tsv | awk -F '\t' '
  { L[$2] = L[$2] (L[$2] == "" ? "" : "|") $1
    if ($3 != "-") { n = split($3, a, ";"); d = ""; for (i = 1; i <= n; i++) d = d " \"$H" substr(a[i], 2) "\""; D = D "      " $1 ") printf \047%s\\n\047" d " ;;\n" }
    if ($5 != "-") { n = split($5, a, ";"); d = ""; for (i = 1; i <= n; i++) d = d " " a[i]; S = S "      " $1 ") printf \047%s\\n\047" d " ;;\n" } }
  END { print "# >>> folder-vars: generated from data/folder-vars.tsv by tools/gen.sh. Edit that file, then run it."
        print "  _mv_agent=\047" L["agent"] "\047"; print "  _mv_tool=\047" L["tool"] "\047"
        print "  fleet_dflt() { # variable: the folders the run reads when it is not set"; print "    case \"$1\" in"; printf "%s", D; print "    esac"; print "  }"
        print "  fleet_scripts() { # variable: its tool\047s own scripts in its folder, which set it to that folder"; print "    case \"$1\" in"; printf "%s", S; print "    esac"; print "  }"
        print "# <<< folder-vars" }' > "$WORK/folder-vars.sh"
rows data/folder-vars.tsv | awk -F '\t' '
  function ps(p) { if (p ~ /^~\//) return "(J $HomeDir \047" substr(p, 3) "\047)"; if (p ~ /^\{LOCALAPPDATA\}/) return "(J $LocalAppData \047" substr(p, 16) "\047)"; return "(J $AppData \047" substr(p, 11) "\047)" }
  function list(s, f,   n, a, i, o) { n = split(s, a, ";"); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? ", " : "") (f ? ps(a[i]) : "\047" a[i] "\047"); return "@(" o ")" }
  { L[$2] = L[$2] (L[$2] == "" ? "" : ", ") "\047" $1 "\047"
    if ($4 != "-" && !(tolower($1) in w)) W = W (W == "" ? "" : "; ") "\047" $1 "\047 = " list($4, 1)
    w[tolower($1)] = 1
    if ($5 != "-") S = S (S == "" ? "" : "; ") "\047" $1 "\047 = " list($5, 0) }
  END { print "# >>> folder-vars: generated from data/folder-vars.tsv by tools/gen.sh. Edit that file, then run it."
        print "$FolderVarsAgent = @(" L["agent"] ")"; print "$FolderVarsTool = @(" L["tool"] ")"
        print "$FolderVarsDefault = @{ " W " }"; print "$FolderVarsScripts = @{ " S " }"; print "# <<< folder-vars" }' > "$WORK/folder-vars.ps1"

# --- coding agents -------------------------------------------------------------
# Rows are name|commands|install paths|folders that change when it is used|id, paths separated by ;.
rows data/agents.tsv | awk -F '\t' '
  function sh(s,   n, a, i, o, p) { if (s == "-") return ""; n = split(s, a, ";"); o = ""
    for (i = 1; i <= n; i++) { p = a[i]; if (p ~ /^~/) p = "$H" substr(p, 2); else { sub(/^\{/, "$", p); sub(/\}/, "", p) }; o = o (i > 1 ? ";" : "") p }
    return o }
  BEGIN { print "# >>> agents: generated from data/agents.tsv by tools/gen.sh. Edit that file, then run it."; printf "AGENTS=\"" }
  { printf "%s%s|%s|%s|%s|%s", (NR > 1 ? "\n" : ""), $1, ($2 == "-" ? "" : $2), sh($3), sh($4), $7 }
  END { print "\""; print "# <<< agents" }' > "$WORK/agents.sh"
rows data/agents.tsv | awk -F '\t' '
  function ps(p,   r) {
    if (p == "{GOOSE_DATA}") return "$GooseData"
    if (p ~ /^~\//) return "(J $HomeDir \047" substr(p, 3) "\047)"
    if (p ~ /^\{LOCALAPPDATA\}\//) return "(J $LocalAppData \047" substr(p, 16) "\047)"
    return "(J $AppData \047" substr(p, 11) "\047)" }
  function list(s,   n, a, i, o) { if (s == "-") return "@()"; n = split(s, a, ";"); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? ", " : "") ps(a[i]); return "@(" o ")" }
  { r[NR] = sprintf("  @(\047%s\047, \047%s\047, %s, %s, \047%s\047)", $1, ($2 == "-" ? "" : $2), list($5), list($6), $7); n = NR }
  END { print "# >>> agents: generated from data/agents.tsv by tools/gen.sh. Edit that file, then run it."; print "$Agents = @("
        for (i = 1; i <= n; i++) print r[i] (i < n ? "," : ""); print ")"; print "# <<< agents" }' > "$WORK/agents.ps1"

# --- the fixed lists the report sends ------------------------------------------------
# MCP apps (data/mcp-clients.tsv), well-known MCP servers and their aliases (data/mcp-servers.tsv),
# and kinds of file (data/key-places.tsv), as space-separated strings, aliases as alias=id.
{ rows data/mcp-clients.tsv | awk -F '\t' '{ print "C\t" $1 }'; rows data/mcp-servers.tsv | awk -F '\t' '{ print "S\t" $1 "\t" $2 }'
  rows data/key-places.tsv | awk -F '\t' '{ print "P\t" $1 }'; } | awk -F '\t' '
  $1 == "C" { c = c (c == "" ? "" : " ") $2 }
  $1 == "P" { pl = pl (pl == "" ? "" : " ") $2 }
  $1 == "S" { k = k (k == "" ? "" : " ") $2; if ($3 != "-") { n = split($3, a, ","); for (i = 1; i <= n; i++) al = al (al == "" ? "" : " ") a[i] "=" $2 } }
  END {
    print "# >>> report-lists: generated from data/mcp-clients.tsv, data/mcp-servers.tsv and data/key-places.tsv by tools/gen.sh. Edit those files, then run it."
    print "MCP_CLIENT_IDS=\"" c "\""; print "MCP_KNOWN_IDS=\"" k "\""; print "MCP_ALIASES=\"" al "\""; print "KEY_PLACE_IDS=\"" pl "\""
    print "# <<< report-lists"
    print "# >>> report-lists: generated from data/mcp-clients.tsv, data/mcp-servers.tsv and data/key-places.tsv by tools/gen.sh. Edit those files, then run it." > "/dev/stderr"
    print "$MCP_CLIENT_IDS = \047" c "\047" > "/dev/stderr"; print "$MCP_KNOWN_IDS = \047" k "\047" > "/dev/stderr"
    print "$MCP_ALIASES = \047" al "\047" > "/dev/stderr"; print "$KEY_PLACE_IDS = \047" pl "\047" > "/dev/stderr"
    print "# <<< report-lists" > "/dev/stderr"
  }' > "$WORK/report-lists.sh" 2> "$WORK/report-lists.ps1"

# --- MCP configs at home --------------------------------------------------------------
rows data/mcp-files.tsv | awk -F '\t' '
  BEGIN { print "# >>> mcp-files: generated from data/mcp-files.tsv by tools/gen.sh. Edit that file, then run it."; printf "MCP_FILES=\"" }
  { p = $3; if (p ~ /^~/) p = "$H" substr(p, 2); else { sub(/^\{/, "$", p); sub(/\}/, "", p) }
    printf "%s%s|%s|%s", (NR > 1 ? "\n" : ""), $1, $2, p }
  END { print "\""; print "# <<< mcp-files" }' > "$WORK/mcp-files.sh"
rows data/mcp-files.tsv | awk -F '\t' '
  function ps(p) {
    if (p ~ /^~\//) return "(J $HomeDir \047" substr(p, 3) "\047)"
    if (p ~ /^\{LOCALAPPDATA\}\//) return "(J $LocalAppData \047" substr(p, 16) "\047)"
    return "(J $AppData \047" substr(p, 11) "\047)" }
  { r[NR] = sprintf("  @(\047%s\047, \047%s\047, %s)", $1, $2, ps($4)); n = NR }
  END { print "# >>> mcp-files: generated from data/mcp-files.tsv by tools/gen.sh. Edit that file, then run it."; print "$McpFiles = @("
        for (i = 1; i <= n; i++) print r[i] (i < n ? "," : ""); print ")"; print "# <<< mcp-files" }' > "$WORK/mcp-files.ps1"

# --- the lines an account run prints, for the readers -----------------------------------
FL_KEYS_LIST=$(rows data/account-run.tsv | cut -f1 | tr '\n' ' ' | sed 's/ $//')
printf '# >>> account-run-keys: generated from data/account-run.tsv by tools/gen.sh. Edit that file, then run it.\nFL_KEYS="%s"\n# <<< account-run-keys\n' "$FL_KEYS_LIST" > "$WORK/account-run-keys.sh"
# The printers are code: --check fails when the keys gird-check.sh and gird-check.ps1 print, in order,
# are not those of data/account-run.tsv.
_ar_sh=$(awk '/^    echo "v=1"$/ { on = 1 } on && /^    echo "[a-z_]+=/ { k = $2; sub(/^"/, "", k); sub(/=.*/, "", k); printf "%s ", k } on && /^    echo "end=1"$/ { exit }' gird-check.sh | sed 's/ $//')
_ar_ps=$(awk '/^    .v=1.$/ { on = 1 } on && /^    [\047"][a-z_]+=/ { k = $1; sub(/^[\047"]/, "", k); sub(/=.*/, "", k); printf "%s ", k } on && /^    .end=1.$/ { exit }' gird-check.ps1 | sed 's/ $//')
AR_RC=0
[ "$_ar_sh" = "$FL_KEYS_LIST" ] || { echo "gird-check.sh --account-run prints \"$_ar_sh\", not the keys of data/account-run.tsv"; AR_RC=1; }
[ "$_ar_ps" = "$FL_KEYS_LIST" ] || { echo "gird-check.ps1 -AccountRun prints \"$_ar_ps\", not the keys of data/account-run.tsv"; AR_RC=1; }

# --- the ids gird-fleet.ps1 checks an account run's lines against ---------------------
# Every incident with its level, the key providers, the agents of data/auto-approve.tsv, the tools of
# data/outdated.tsv and the platforms, as Windows sees them, and the markers data/indicators.tsv puts in
# %ProgramData%, which the PC's own check looks at by name.
{ rows data/incidents.tsv | awk -F '\t' '{ print "I\t" $1 "\t" $6 }'; rows data/keys.tsv | awk -F '\t' '{ print "K\t" $1 }'
  rows data/auto-approve.tsv | awk -F '\t' '$2 == "all" || $2 == "win" { print "A\t" $1 }'
  rows data/outdated.tsv | awk -F '\t' '$3 == "all" || $3 == "win" { print "O\t" $1 }'; rows data/platforms.tsv | awk -F '\t' '{ print "P\t" $1 }'
  rows data/indicators.tsv | awk -F '\t' '($2 == "all" || $2 == "win") && $5 ~ /^\{PROGRAMDATA\}\// { print "D\t" $1 "\t" substr($5, 15) }'; } | awk -F '\t' -v keys="$FL_KEYS_LIST" '
  function add(k, v) { if (!((k, v) in seen)) { seen[k, v] = 1; L[k] = L[k] (L[k] == "" ? "" : (k == "I" ? "; " : ", ")) v } }
  $1 == "I" { add("I", "\047" $2 "\047 = \047" $3 "\047") } $1 == "K" { k = k (k == "" ? "" : " ") $2 }
  $1 == "A" { add("A", "\047" $2 "\047") } $1 == "O" { add("O", "\047" $2 "\047") } $1 == "P" { add("P", "\047" $2 "\047") }
  $1 == "D" { d = d "  ,@(\047" $2 "\047, \047" $3 "\047)\n" }
  END {
    print "# >>> fleet-tables: generated from data/ by tools/gen.sh. Edit those files, then run it."
    print "$FlIncidents = @{ " L["I"] " }"
    print "$FlProviders = \047" k "\047"
    print "$FlYoloNames = @(" L["A"] ")"
    print "$FlTools = @(" L["O"] ")"
    print "$FlPlatforms = @(" L["P"] ")"
    printf "$FlProgramData = @(\n%s)\n", d
    n = split(keys, ka, " "); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? ", " : "") "\047" ka[i] "\047"
    print "$FlKeys = @(" o ")"
    print "# <<< fleet-tables"
  }' > "$WORK/fleet-tables.ps1"

# --- splice -----------------------------------------------------------------
splice() { # file block-name generated-file
  awk -v name="$2" -v gen="$3" '
    $0 ~ "^# >>> " name "[: ]" || $0 == "# >>> " name { while ((getline l < gen) > 0) print l; skip = 1; found = 1; next }
    skip && $0 == "# <<< " name { skip = 0; next }
    !skip { print }
    END { if (!found) { print "no \"# >>> " name "\" marker" > "/dev/stderr"; exit 3 } }' "$1"
}
# --- the ownership walk, for gird-fleet.sh ---------------------------------------
# Its home is gird-check.sh; root in gird-fleet.sh runs the same copy. The agents table both fleet
# scripts read is written into them from data/agents.tsv, as into the checks.
awk '/^# >>> owned-walk[: ]/ { on = 1; print "# >>> owned-walk: copied from gird-check.sh by tools/gen.sh. Edit it there, then run it."; next }
  on { print } /^# <<< owned-walk$/ { exit }' gird-check.sh > "$WORK/owned-walk.sh"
grep -q '^# <<< owned-walk$' "$WORK/owned-walk.sh" || { echo "gird-check.sh has no owned-walk block"; exit 1; }

RC=$AR_RC
for f in gird-check.sh gird-check.ps1 gird-fleet.sh gird-fleet.ps1; do
  if [ "$f" = gird-fleet.sh ]; then blocks="owned-walk keys auto-approve agents incidents indicators outdated platforms account-run-keys"
  elif [ "$f" = gird-fleet.ps1 ]; then blocks="agents fleet-tables"
  else blocks="keys sessions planted auto-approve incidents bad-pypi indicators bad-npm bad-extensions outdated platforms folder-vars agents report-lists mcp-files"; fi
  ext=${f##*.}; cp "$f" "$WORK/b"
  for blk in $blocks; do
    splice "$WORK/b" "$blk" "$WORK/$blk.$ext" > "$WORK/a" && mv "$WORK/a" "$WORK/b" || { RC=1; continue 2; }
  done
  if [ "$CHECK" -eq 1 ]; then
    if ! cmp -s "$f" "$WORK/b"; then echo "$f is out of date with data/ (or, for gird-fleet.sh and gird-fleet.ps1, with gird-check.sh and gird-check.ps1): run bash tools/gen.sh"; diff "$f" "$WORK/b" | head -n 8; RC=1; fi
  elif ! cmp -s "$f" "$WORK/b"; then cat "$WORK/b" > "$f"; echo "updated $f"; fi
done

if command -v sha256sum > /dev/null 2>&1; then sha() { sha256sum | cut -c1-64; }; else sha() { shasum -a 256 | cut -c1-64; }; fi
# --- the size rule both one-file builds follow ----------------------------------
# size_ok FILE BYTES LIMIT LIMIT-WRITTEN-OUT LIMIT-IN-WORDS WHO: fails at LIMIT bytes or more, the
# tightest limit an MDM documents for the file, and warns from 80% of it, to keep 20% for growth.
size_ok() {
  if [ "$2" -ge "$3" ]; then echo "$1 is $2 bytes: $6 takes a script of under $5 ($4 bytes)"; return 1; fi
  if [ "$2" -ge $(( $3 * 8 / 10 )) ]; then echo "warning: $1 is $2 bytes, past 80% of the $4 $6 takes"; fi
  return 0
}

# --- blindspot-fleet.sh, the one file an MDM runs on a Mac -------------------------
# gird-fleet.sh with gird-check.sh after its last line, without the game (the lines from "# >>> game"
# to "# <<< game", nothing else changed), and that copy's SHA-256 in FL_PACKED_SHA. bash never reaches
# those lines: the file's own copy writes them out (fl_unpack in gird-fleet.sh). Built from the files as
# they are here and never checked in. Intune takes a macOS script of under 1 MB, so --check fails at
# 1,000,000 bytes, when the copy it unpacks is not gird-check.sh without its game byte for byte, and
# when its first line is not #!/bin/bash -p.
# A blindspot-fleet.sh already here must be that build.
if ! awk '/^# >>> game$/ { if (g || n) exit 1; g = 1; n = 1; next } /^# <<< game$/ { if (!g) exit 1; g = 0; next }
    g && /^# >>> / { exit 1 } !g { print > out } END { if (g || n != 1) exit 1 }' out="$WORK/nogame.sh" gird-check.sh; then
  echo "blindspot-fleet.sh not built: gird-check.sh needs one game block, \"# >>> game\" to \"# <<< game\", with no other block inside it"; RC=1
elif grep -qE '^# (>>>|<<<) packed-' "$WORK/nogame.sh"; then
  echo "blindspot-fleet.sh not built: gird-check.sh holds a packed- marker line, which would end the copy early"; RC=1
else
  _shs=$(sha < "$WORK/nogame.sh")
  printf '# >>> packed-sha: written into blindspot-fleet.sh by tools/gen.sh.\nFL_PACKED_SHA=\047%s\047\n# <<< packed-sha\n' "$_shs" > "$WORK/packed-sha.sh"
  { printf '# >>> packed-check: gird-check.sh without its game, written in by tools/gen.sh. bash stops at the exit above and never runs it here.\n'
    cat "$WORK/nogame.sh"; printf '# <<< packed-check\n'; } > "$WORK/packed-check.sh"
  splice gird-fleet.sh packed-sha "$WORK/packed-sha.sh" > "$WORK/bf1.sh" && splice "$WORK/bf1.sh" packed-check "$WORK/packed-check.sh" > "$WORK/blindspot-fleet.sh" || RC=1
  _szs=$(wc -c < "$WORK/blindspot-fleet.sh" | tr -d ' ')
  size_ok blindspot-fleet.sh "$_szs" 1000000 1,000,000 "1 MB" "Intune for macOS" || RC=1
  unpacked_sh() { awk '/^# >>> packed-check[: ]/ && !s { s = 1; next } s { if (n) print p; p = $0; n = 1 } END { exit !(s && p == "# <<< packed-check") }' "$1" | sha; }
  [ "$(unpacked_sh "$WORK/blindspot-fleet.sh")" = "$_shs" ] || { echo "blindspot-fleet.sh does not unpack to gird-check.sh without its game"; RC=1; }
  [ "$(head -n 1 "$WORK/blindspot-fleet.sh")" = '#!/bin/bash -p' ] || { echo "blindspot-fleet.sh must start with #!/bin/bash -p"; RC=1; }
  if [ "$CHECK" -eq 1 ] && [ -f blindspot-fleet.sh ] && ! cmp -s blindspot-fleet.sh "$WORK/blindspot-fleet.sh"; then
    echo "blindspot-fleet.sh is out of date with gird-fleet.sh and gird-check.sh, or was edited: run bash tools/gen.sh"; RC=1
  fi
  if [ "$CHECK" -eq 0 ] && [ "$RC" -eq 0 ] && ! cmp -s "$WORK/blindspot-fleet.sh" blindspot-fleet.sh; then cat "$WORK/blindspot-fleet.sh" > blindspot-fleet.sh; echo "built blindspot-fleet.sh ($_szs bytes)"; fi
fi

# --- blindspot-fleet.ps1, the one file an MDM runs ------------------------------
# gird-fleet.ps1 with gird-check.ps1 packed inside it, without its comments (tools/strip-comments.ps1,
# which needs PowerShell), gzip-compressed and base64-encoded, and the SHA-256 of that copy. Built from
# the files as they are here and never checked in: tools/gen.sh builds it for each release. Intune
# takes a script of under 200 KB, so --check builds it and fails at 200 KB or more (size_ok), or when the check
# it unpacks is not gird-check.ps1 without its comments byte for byte. A blindspot-fleet.ps1 already
# here must be that build too, apart from how gzip compressed it.
PWSH=${PWSH:-$(command -v pwsh 2> /dev/null || true)}
if [ -z "$PWSH" ] || [ ! -x "$PWSH" ]; then
  echo "blindspot-fleet.ps1 not built: removing gird-check.ps1's comments needs PowerShell. Put pwsh on PATH or set PWSH=/path/to/pwsh." >&2
  [ "$RC" -eq 0 ] && RC=3
  exit "$RC"
fi
if ! "$PWSH" -NoProfile -NonInteractive -File tools/strip-comments.ps1 gird-check.ps1 "$WORK/stripped.ps1" > /dev/null; then
  echo "blindspot-fleet.ps1 not built: tools/strip-comments.ps1 could not remove gird-check.ps1's comments"; exit 1
fi
gzip -9 -n -c < "$WORK/stripped.ps1" | base64 | tr -d '\n\r' > "$WORK/packed.b64"
_sha=$(sha < "$WORK/stripped.ps1")
{ printf '# >>> packed-check: gird-check.ps1 without its comments, written into blindspot-fleet.ps1 by tools/gen.sh.\n'
  printf '$PackedCheck = \047%s\047\n' "$(cat "$WORK/packed.b64")"
  printf '$PackedSha = \047%s\047\n# <<< packed-check\n' "$_sha"; } > "$WORK/packed-check.ps1"
splice gird-fleet.ps1 packed-check "$WORK/packed-check.ps1" > "$WORK/blindspot-fleet.ps1" || exit 1
_sz=$(wc -c < "$WORK/blindspot-fleet.ps1" | tr -d ' ')
size_ok blindspot-fleet.ps1 "$_sz" 204800 204,800 "200 KB" Intune || RC=1
unpacked() { sed -n "s|^\\\$PackedCheck = '\\([A-Za-z0-9+/=]*\\)'\$|\\1|p" "$1" | base64 -d 2> /dev/null | gzip -dc 2> /dev/null | sha; }
if [ "$(unpacked "$WORK/blindspot-fleet.ps1")" != "$_sha" ]; then echo "blindspot-fleet.ps1 does not unpack to gird-check.ps1 without its comments"; RC=1; fi
if [ "$CHECK" -eq 1 ] && [ -f blindspot-fleet.ps1 ]; then
  splice blindspot-fleet.ps1 packed-check "$WORK/packed-check.ps1" > "$WORK/here.ps1" 2> /dev/null || : > "$WORK/here.ps1"
  if ! cmp -s "$WORK/here.ps1" "$WORK/blindspot-fleet.ps1" || [ "$(unpacked blindspot-fleet.ps1)" != "$_sha" ] ||
     ! grep -qx "\\\$PackedSha = '$_sha'" blindspot-fleet.ps1; then
    echo "blindspot-fleet.ps1 is out of date with gird-fleet.ps1 and gird-check.ps1, or was edited: run bash tools/gen.sh"; RC=1
  fi
fi
if [ "$CHECK" -eq 0 ] && [ "$RC" -eq 0 ] && ! cmp -s "$WORK/blindspot-fleet.ps1" blindspot-fleet.ps1; then cat "$WORK/blindspot-fleet.ps1" > blindspot-fleet.ps1; echo "built blindspot-fleet.ps1 ($_sz bytes)"; fi
exit "$RC"
