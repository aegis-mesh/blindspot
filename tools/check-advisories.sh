#!/usr/bin/env bash
# Checks data/bad-npm.tsv against OSV.dev, for maintainers. The script itself runs offline, so a
# withdrawn or corrected advisory only reaches it through this check. OSV.dev combines GitHub's
# malware advisories, the OpenSSF Malicious Packages list and others. Its OpenSSF entries are often
# reported by automated scanners, so a MISSING line is a suggestion to confirm against a primary
# source (the vendor, a GitHub malware advisory or a named research post) before it is added.
#
#   bash tools/check-advisories.sh
#
# It checks the names already listed. Finding a campaign's other packages is a sweep by hand (see
# CONTRIBUTING.md). For each package name in data/bad-npm.tsv it lists:
#   WITHDRAWN  a version we flag whose malware entry has since been withdrawn
#   MISSING    a malicious version, or every version, that an entry lists and we don't
#   NO SOURCE  a version we flag that no current malware entry names
# and then each incident's source from data/incidents.tsv, to re-read by hand: a vendor can
# change what it says an incident did. A deliberate difference is recorded in data/bad-npm.tsv as
# "#! skip <name> <version> <reason>" and not reported. npm's x.y.z-security placeholders are safe
# and never reported. If OSV.dev can't be reached it falls back to GitHub's advisories through gh.
# Exits 1 when it finds anything to look at. Needs curl and jq.
set -u
cd "$(dirname "$0")/.." || exit 2
command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "needs curl and jq" >&2; exit 2; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
grep -v '^#' data/bad-npm.tsv | grep -v '^[[:space:]]*$' > "$WORK/ours.tsv"
sed -n 's/^#! skip \([^ ]*\) \([^ ]*\) .*/\1 \2/p' data/bad-npm.tsv > "$WORK/skip.txt"

# One line per malware entry for a name: "<withdrawn 0|1> <every version 0|1> <versions...>".
osv() { # name
  curl -fsS -m 30 -X POST https://api.osv.dev/v1/query -d "$(jq -cn --arg n "$1" '{package: {name: $n, ecosystem: "npm"}}')" 2>/dev/null |
    jq -r --arg n "$1" '.vulns[]? | select((.id | startswith("MAL-")) or ((.aliases // []) | any(startswith("MAL-"))) or ((.summary // "") | test("[Mm]alware|[Mm]alicious")))
      | [.affected[]? | select(.package.name == $n)] as $mine | select($mine | length > 0)
      | "\(if .withdrawn then 1 else 0 end) \(if ([$mine[].ranges[]? | select(([.events[]? | .fixed // .last_affected // empty] | length) == 0) | .events[]? | select(.introduced == "0")] | length) > 0 then 1 else 0 end) \([$mine[].versions[]?] | join(" "))"'
}
github() { # name: the same lines from GitHub's malware advisories
  command -v gh >/dev/null 2>&1 || return 1
  gh api "/advisories?ecosystem=npm&type=malware&affects=$(printf '%s' "$1" | jq -sRr @uri)&per_page=100" 2>/dev/null |
    jq -r --arg n "$1" '.[] | . as $a | "\(if $a.withdrawn_at then 1 else 0 end) \(if any(.vulnerabilities[]; .package.name == $n and .vulnerable_version_range == ">= 0") then 1 else 0 end) \([.vulnerabilities[] | select(.package.name == $n) | .vulnerable_version_range | select(startswith("= ")) | ltrimstr("= ")] | join(" "))"'
}

: > "$WORK/rc"
cut -f1 "$WORK/ours.tsv" | sort -u | while IFS= read -r name; do
  if ! osv "$name" > "$WORK/entries" || ! [ -s "$WORK/entries" ]; then
    if ! github "$name" > "$WORK/entries"; then echo "ERROR      $name: neither OSV.dev nor GitHub answered"; echo 1 > "$WORK/rc"; continue; fi
  fi
  awk '$1 == 0 { for (i = 3; i <= NF; i++) print $i }' "$WORK/entries" | grep -v -- '-security$' | sort -u > "$WORK/theirs.txt"
  awk '$1 == 1 { for (i = 3; i <= NF; i++) print $i }' "$WORK/entries" | sort -u > "$WORK/withdrawn.txt"
  all=0; awk '$1 == 0 && $2 == 1' "$WORK/entries" | grep -q . && all=1
  awk -F '\t' -v n="$name" '$1 == n { print $2 }' "$WORK/ours.tsv" | sort -u > "$WORK/mine.txt"
  while IFS= read -r v; do
    if [ "$v" = '*' ]; then [ "$all" -eq 1 ] || { echo "NO SOURCE  $name (every version)"; echo 1 > "$WORK/rc"; }
    elif grep -qxF "$v" "$WORK/withdrawn.txt" && ! grep -qxF "$v" "$WORK/theirs.txt"; then echo "WITHDRAWN  $name $v"; echo 1 > "$WORK/rc"
    elif ! grep -qxF "$v" "$WORK/theirs.txt" && [ "$all" -eq 0 ]; then echo "NO SOURCE  $name $v"; echo 1 > "$WORK/rc"; fi
  done < "$WORK/mine.txt"
  grep -qxF '*' "$WORK/mine.txt" && continue
  if [ "$all" -eq 1 ] && ! grep -qxF "$name *" "$WORK/skip.txt"; then echo "MISSING    $name (every version)"; echo 1 > "$WORK/rc"; fi
  while IFS= read -r v; do
    grep -qxF "$v" "$WORK/mine.txt" || grep -qxF "$name $v" "$WORK/skip.txt" || { echo "MISSING    $name $v"; echo 1 > "$WORK/rc"; }
  done < "$WORK/theirs.txt"
done
echo
echo "Re-read each source and check data/incidents.tsv still says what it says:"
grep -v '^#' data/incidents.tsv | awk -F '\t' 'NF >= 5 { printf "  %-12s %s\n", $1, $5 }'
[ -s "$WORK/rc" ] && exit 1
exit 0
