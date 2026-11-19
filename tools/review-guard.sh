#!/usr/bin/env bash
# Lists what in a pull request needs a maintainer's look before it merges, by fixed rules that read
# the diff as data and run nothing from it. CONTRIBUTING.md "Security review" is what it enforces.
#
#   bash tools/review-guard.sh BASE HEAD
#
# Reads `git diff BASE...HEAD`: the lines HEAD adds or removes since it left BASE, and the paths it
# changes. Exit 0: nothing found. Exit 1: findings, one per line. Exit 2: it could not check.
#
# Rules (a file is "data" when it is *.md, *.txt, data/*.tsv, LICENSE or NOTICE; any other file
# is code, so a kind of file this list does not know is held to the stricter rules):
#   hidden    in code, an added byte that is not printable ASCII, space or tab (CR included);
#             in data, a control character, an invisible or direction-changing character, or bytes
#             that are not UTF-8 (other non-ASCII text is allowed there); a changed path with any
#             byte that is not printable ASCII; a binary file, symbolic link or submodule
#   run       in code, an added line that runs text as code
#   network   in code, an added line that makes a network call or names an http(s) URL; a line that
#             is only a # comment is skipped (a URL in a comment, in docs or in data is not a call)
#   shrink    a removed line in data/*.tsv, other than a # comment or a blank line
#   protected a change under .github/, to a .gitattributes or .gitmodules file, to this guard or
#             its tests, or to what an AI coding agent or editor opening this repository reads or runs:
#             at any depth, anything under .claude/ .codex/ .cursor/ .gemini/ .windsurf/ .vscode/
#             .devcontainer/, and any file named .mcp.json, AGENTS.md, CLAUDE.md, GEMINI.md or
#             .cursorrules
set -u
export LC_ALL=C
cd "$(dirname "$0")/.." || exit 2

usage() { echo "usage: bash tools/review-guard.sh BASE HEAD" >&2; exit 2; }
[ $# -eq 2 ] || usage
case "$1" in -*) usage ;; esac
case "$2" in -*) usage ;; esac
BASE=$(git rev-parse --verify -q "$1^{commit}") || { echo "review-guard: not a commit: $1" >&2; exit 2; }
HEAD=$(git rev-parse --verify -q "$2^{commit}") || { echo "review-guard: not a commit: $2" >&2; exit 2; }
git merge-base "$BASE" "$HEAD" > /dev/null 2>&1 || { echo "review-guard: $1 and $2 share no history" >&2; exit 2; }

W=$(mktemp -d 2>/dev/null || mktemp -d -t review-guard) || exit 2
trap 'rm -rf "$W"' EXIT
FOUND=0
TAB=$(printf '\t')

# Diff options that keep local config and helper programs from changing what is read.
DIFF="diff --no-color --no-ext-diff --no-textconv --no-renames --no-relative --ignore-submodules=none"

# Prints text with every byte outside printable ASCII made visible (cat -v), so a finding cannot
# hide what it shows or start a line the CI log reads as a command.
vis() { printf '%s' "$1" | tr '\n' '\001' | cat -v | cut -c1-240; }
finding() { # rule path line text
  FOUND=1
  printf '%s: %s:%s: %s\n' "$1" "$(vis "$2")" "$3" "$(vis "$4")"
}

# Byte patterns for UTF-8 characters that are invisible or change text direction: C1 controls, soft
# hyphen, Arabic letter mark, Mongolian vowel separator, Hangul fillers, zero-width and direction
# marks, line and paragraph separators, embeddings and overrides, word joiner and isolates,
# variation selectors, the byte order mark, and tag characters.
o() { printf "$1"; }
BAD_UTF8="$(o '\302')[$(o '\200')-$(o '\237')$(o '\255')]|$(o '\330\234')|$(o '\341\240\216')"
BAD_UTF8="$BAD_UTF8|$(o '\341\205')[$(o '\237\240')]|$(o '\343\205\244')|$(o '\357\276\240')"
BAD_UTF8="$BAD_UTF8|$(o '\342\200')[$(o '\213')-$(o '\217')$(o '\250')-$(o '\256')]|$(o '\342\201')[$(o '\240')-$(o '\257')]"
BAD_UTF8="$BAD_UTF8|$(o '\357\270')[$(o '\200')-$(o '\217')]|$(o '\357\273\277')|$(o '\363\240')[$(o '\200')-$(o '\207')]"

B='(^|[^A-Za-z0-9_-])'   # word start
E='([^A-Za-z0-9_-]|$)'   # word end
CMD='(^[[:space:]]*|[;&|({][[:space:]]*|(then|do|else)[[:space:]]+)'   # command position
RUN="${B}eval$E|invoke-expression|${B}iex$E|scriptblock\][[:space:]]*::[[:space:]]*create|newscriptblock|invokescript|invokecommand|add-type"
RUN="$RUN|$CMD(source|\.)[[:space:]]+[^[:space:];|&]*[\$(\`]"
RUN="$RUN|${B}(ba|z|k|da)?sh([[:space:]]+-[a-z]+)*[[:space:]]+-[a-z]*c[[:space:]]+(\"[^\"]*)?[\$\`]"
RUN="$RUN|${B}(pwsh|powershell)(\.exe)?$E.*[[:space:]]-(c|command)[[:space:]]+(\"[^\"]*)?[\$\`]|${B}(pwsh|powershell)(\.exe)?$E.*[[:space:]]-(e|ec|enc|encodedcommand)$E"
RUN="$RUN|\|[[:space:]]*(ba|z|k|da)?sh$E|\|[[:space:]]*(pwsh|powershell)$E|frombase64string|${B}base64[[:space:]]+(.*[[:space:]])?(-d|-D|--decode)$E"
RUN="$RUN|${B}exec\(|os\.system|shell[[:space:]]*=[[:space:]]*true"
NET="${B}(curl|wget|irm|iwr|nc|ncat|netcat|socat|telnet|nslookup|dig|resolve-dnsname|invoke-webrequest|invoke-restmethod|start-bitstransfer)$E"
NET="$NET|webclient|httpclient|webrequest\]|downloadstring|downloadfile|tcpclient|udpclient|/dev/(tcp|udp)/|urlopen|urllib|http\.client|${B}requests\.|${B}socket\.|https?://"

is_data() {
  case "$1" in
    *.md|*.txt|LICENSE|NOTICE) return 0 ;;
    data/*/*) return 1 ;;
    data/*.tsv) return 0 ;;
  esac
  return 1
}
# Compared lowercased: a case-insensitive file system opens .Claude/ as .claude/.
is_protected() {
  case "/$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    /.github/*|*/.gitattributes|/.gitmodules|/tools/review-guard.sh|/tests/review-guard.sh) return 0 ;;
    */.claude/*|*/.codex/*|*/.cursor/*|*/.gemini/*|*/.windsurf/*|*/.vscode/*|*/.devcontainer/*) return 0 ;;
    */.mcp.json|*/agents.md|*/claude.md|*/gemini.md|*/.cursorrules) return 0 ;;
  esac
  return 1
}

# One record per changed path: ":oldmode newmode oldsha newsha status" NUL path NUL.
git $DIFF --raw -z "$BASE...$HEAD" > "$W/raw" || { echo "review-guard: git diff failed" >&2; exit 2; }
git $DIFF --numstat -z "$BASE...$HEAD" > "$W/num" || { echo "review-guard: git diff failed" >&2; exit 2; }
# Paths git counts as binary (numstat shows - - for them).
: > "$W/binary"
while IFS= read -r -d '' rec; do
  case "$rec" in "-$TAB-$TAB"*) printf '%s\0' "${rec#-"$TAB"-"$TAB"}" >> "$W/binary" ;; esac
done < "$W/num"
# rule NAME PATTERN FILE [GREP-FLAG]: one finding for each "number<TAB>text" line of FILE whose
# text matches PATTERN (an ERE; ^ is the start of the text).
rule() {
  cut -f2- "$3" > "$W/text"
  grep -an ${4:-} -E -- "$2" "$W/text" | cut -d: -f1 > "$W/hits"
  [ -s "$W/hits" ] || return 0
  awk 'NR == FNR { want[$1] = 1; next } want[FNR]' "$W/hits" "$3" > "$W/hitlines"
  while IFS= read -r l; do finding "$1" "$path" "${l%%"$TAB"*}" "${l#*"$TAB"}"; done < "$W/hitlines"
}
is_binary() { tr '\0' '\n' < "$W/binary" | grep -qxF -- "$1"; }

N=0
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  N=$((N + 1))
  set -- $meta
  newmode=$2; oldmode=${1#:}; status=$5
  if [ -n "$(printf '%s' "$path" | tr -d ' -~')" ]; then finding hidden "$path" 0 "a byte in the file name that is not printable ASCII"; fi
  if is_protected "$path"; then finding protected "$path" 0 "a change to a protected path"; fi
  case "$newmode$oldmode" in
    *120000*) finding hidden "$path" 0 "a symbolic link"; continue ;;
    *160000*) finding hidden "$path" 0 "a submodule"; continue ;;
  esac
  if is_binary "$path"; then finding hidden "$path" 0 "a binary file"; continue; fi
  [ "$status" = D ] && ! { case "$path" in data/*.tsv) true ;; *) false ;; esac; } && continue

  # Each added line as "+<TAB>number<TAB>text", each removed line as "-<TAB>number<TAB>text".
  # The ---/+++ file header comes only before the first @@, so an added line that starts with ++ is
  # still read as a line.
  git $DIFF --text -U0 "$BASE...$HEAD" -- ":(literal)$path" > "$W/d" || { echo "review-guard: git diff failed on a file" >&2; exit 2; }
  awk -v T="$TAB" '
    /^@@ / { h = 1; split($0, a, " "); o = a[2]; n = a[3]; sub(/^-/, "", o); sub(/^\+/, "", n); sub(/,.*/, "", o); sub(/,.*/, "", n); next }
    !h { next }
    /^\+/ { print "+" T n T substr($0, 2); n++; next }
    /^-/  { print "-" T o T substr($0, 2); o++; next }
  ' "$W/d" > "$W/lines"
  grep -a "^+$TAB" "$W/lines" | cut -f2- > "$W/add"
  grep -a "^-$TAB" "$W/lines" | cut -f2- > "$W/del"

  if is_data "$path"; then
    rule hidden "[$(o '\001')-$(o '\010')$(o '\013')-$(o '\037')$(o '\177')]|$BAD_UTF8" "$W/add"
    while IFS= read -r l; do
      t=${l#*"$TAB"}
      if [ -n "$(printf '%s' "$t" | tr -d ' -~\t')" ] && ! printf '%s' "$t" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; then
        finding hidden "$path" "${l%%"$TAB"*}" "$t"
      fi
    done < "$W/add"
  else
    rule hidden "[^[:print:]$TAB]" "$W/add"
    rule run "$RUN" "$W/add" -i
    grep -av "^[0-9]*${TAB}[[:space:]]*#" "$W/add" > "$W/code"
    rule network "$NET" "$W/code" -i
  fi
  case "$path" in
    data/*/*) ;;
    data/*.tsv) rule shrink "^[[:space:]]*[^#[:space:]]" "$W/del" ;;
  esac
done < "$W/raw"

[ "$N" -gt 0 ] || { echo "review-guard: no changes between $1 and $2"; exit 0; }
[ "$FOUND" -eq 0 ] || exit 1
echo "review-guard: $N changed files, nothing found"
exit 0
