#!/usr/bin/env bash
# Cuts a signed release, for maintainers (docs/designs/signed-releases.md). It checks everything
# first and publishes nothing until every check has passed.
#
#   BLINDSPOT_SIGNING_KEY=~/.ssh/blindspot-release bash tools/release.sh [--dry-run] X.Y.Z
#   bash tools/release.sh --check-list
#
# --dry-run does every step up to and including checking its own signature, then stops before the
# tag, the push and the GitHub release, and keeps the files it made for you to look at.
# --check-list only checks that .github/release-files names every file people run, or exempts it
# as unreleased, and exits.
# The release signs the files .github/release-files names, taken from the reviewed commit or built
# from it by bash tools/gen.sh.
# ssh-keygen asks for the key's passphrase itself, once for SHA256SUMS and once for the tag; this
# script never reads, stores or passes it.
# This script comes from the checkout it releases: review changes to tools/ since the last release
# before running it (CONTRIBUTING.md, Releases). Nothing else from the checkout runs before you
# confirm the review.
set -u
unset CDPATH

# Before any program runs: every folder on PATH must be absolute and outside this checkout, or a
# file the checkout holds (a root-level "git", say) would run in place of the tool, before the
# review below. Only shell builtins run until this passes.
case $0 in */*) _d=${0%/*} ;; *) _d=. ;; esac
case $0 in /*) SELF=$0 ;; *) SELF=$PWD/$0 ;; esac
cd -P "$_d/.." 2>/dev/null || { printf 'release: %s\n' "can't find the repository" >&2; exit 1; }
# path_ok DIR: says what is wrong, and fails, when a folder on PATH is relative, empty or inside DIR.
path_ok() {
  case ":$PATH:" in *::*) printf 'release: PATH has an empty entry, which means the current folder: remove it\n' >&2; return 1 ;; esac
  _rest=$PATH
  while [ -n "$_rest" ]; do
    _p=${_rest%%:*}
    case $_rest in *:*) _rest=${_rest#*:} ;; *) _rest="" ;; esac
    case $_p in /*) ;; *) printf 'release: PATH holds the relative folder %s: remove it, so nothing in the checkout can run in place of a tool\n' "$_p" >&2; return 1 ;; esac
    _r=$(cd -P "$_p" 2>/dev/null && pwd) || _r=$_p
    for _x in "$_p" "$_r"; do
      case "$_x/" in "$1/"*) printf 'release: PATH holds %s, inside the repository: remove it, so nothing in the checkout can run in place of a tool\n' "$_p" >&2; return 1 ;; esac
    done
  done
}
path_ok "$PWD" || exit 1

RLIST=.github/release-files
SIGNERS=.github/allowed_signers
PRINCIPAL=release@blindspot
NS=blindspot-release

die() { printf 'release: %s\n' "$*" >&2; exit 1; }
TAB=$(printf '\t')
say() { printf '%s\n' "$*"; }

# Reads the release list on stdin and prints its entries as "name kind", or says what is wrong.
# A committed or built entry is a file name; an unreleased one is a path, where * matches any part
# of a path (tests/*).
read_list() {
  awk -v f="$RLIST" '
    function no(m) { print "release: " f ", line " NR ": " m > "/dev/stderr"; bad = 1; exit 1 }
    /^[[:space:]]*(#|$)/ { next }
    NF != 2 || ($2 != "committed" && $2 != "built" && $2 != "unreleased") { no("not a file name, a space, then committed, built or unreleased") }
    $2 != "unreleased" && ($1 !~ /^[A-Za-z0-9_][A-Za-z0-9._-]*$/ || $1 == "SHA256SUMS" || $1 == "SHA256SUMS.sig" || $1 == "allowed_signers") { no($1 " is not a name a release can carry") }
    $2 == "unreleased" && ($1 !~ /^[A-Za-z0-9_][A-Za-z0-9._-]*(\/[A-Za-z0-9._*-]+)*$/ || $1 ~ /(^|\/)\.\.?(\/|$)/) { no($1 " is not a path in the repository") }
    seen[$1]++ { no($1 " is listed twice") }
    { print $1, $2; if ($2 != "unreleased") n++ }
    END { if (!bad && !n) { print "release: " f " names no file" > "/dev/stderr"; exit 1 } }'
}
# blobs [COMMIT]: each file tracked in the index, or in COMMIT, as "mode sha<TAB>path", NUL-ended.
blobs() {
  if [ $# -eq 0 ]; then
    G ls-files -s -z | while IFS= read -r -d '' r; do set -- ${r%%"$TAB"*}; printf '%s %s\t%s\0' "$1" "$2" "${r#*"$TAB"}"; done
  else
    G ls-tree -r -z "$1" | while IFS= read -r -d '' r; do set -- ${r%%"$TAB"*}; [ "$2" = blob ] && printf '%s %s\t%s\0' "$1" "$3" "${r#*"$TAB"}"; done
  fi
}
# Prints each file people would run that the entries in $1 neither name nor exempt as unreleased:
# a tracked file (blobs on stdin) at any depth that is executable, starts with #!, or has a
# script's extension; one the .gitignore at $2 lists under a "built by bash tools/gen.sh" comment;
# or one the tools/gen.sh at $3 writes by name outside a folder it made with mktemp.
unlisted() {
  [ -f "$2" ] || { printf 'release: no .gitignore to read the built files from\n' >&2; return 1; }
  [ -f "$3" ] || { printf 'release: no tools/gen.sh to read the built files from\n' >&2; return 1; }
  _t=$(grep -oE '(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*=\$\(mktemp' "$3" | sed -E 's/^[^A-Za-z_]//; s/=.*//' | tr '\n' ' ')
  { shopt -s nocasematch
    while IFS= read -r -d '' r; do
      _p=${r#*"$TAB"}; _m=${r%%"$TAB"*}
      case ${_m%% *} in 100755) printf '%s\n' "$_p"; continue ;; 100644) ;; *) continue ;; esac
      case $_p in *.sh|*.bash|*.zsh|*.ksh|*.fish|*.ps1|*.psm1|*.psd1|*.bat|*.cmd|*.command|*.tool|*.py|*.pl|*.rb|*.js|*.mjs|*.cjs|*.vbs|*.vbe|*.jse|*.wsf|*.hta|*.csh|*.tcsh|*.lua) printf '%s\n' "$_p"; continue ;; esac
      [ "$(G cat-file blob "${_m#* }" 2>/dev/null | head -c 2)" != '#!' ] || printf '%s\n' "$_p"
    done
    awk '/^#.*built by bash tools\/gen\.sh/ { b = 1; next } /^[[:space:]]*$/ || /^#/ { b = 0; next } b { sub(/^\//, ""); print }' "$2"
    grep -oE '>[[:space:]]*"?(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)?[A-Za-z0-9._-]+\.(sh|ps1|psm1|bat|cmd|command)([^A-Za-z0-9._-]|$)' "$3" |
      sed -E 's/^>[[:space:]]*"?//; s/[^A-Za-z0-9._-]$//' |
      awk -v t=" $_t" '{ v = "" } /\// { v = $0; sub(/\/.*/, "", v); gsub(/[${}]/, "", v); sub(/^[^\/]*\//, "") } v == "" || index(t, " " v " ") == 0 { print }'
  } | LC_ALL=C sort -u | while IFS= read -r n; do
    _f=0
    while read -r _e _k; do
      # shellcheck disable=SC2254  # an unreleased entry is a pattern: tests/* exempts every test
      if [ "$_k" = unreleased ]; then case $n in $_e) _f=1; break ;; esac
      elif [ "$_e" = "$n" ]; then _f=1; break; fi
    done <<EOF
$1
EOF
    [ "$_f" -eq 1 ] || printf '%s\n' "$n"
  done
}

DRY=0; CL=0; V=""
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --check-list) CL=1 ;;
    -h|--help) sed -n '2,15p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $a" ;;
    *) [ -z "$V" ] || die "give one version"; V=$a ;;
  esac
done

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$TOP" || die "can't enter $TOP"
TOP=$(pwd -P)
path_ok "$TOP" || exit 1
export GIT_NO_REPLACE_OBJECTS=1
# Hooks and the file system monitor are programs a checkout could name; no git call here runs them.
G() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }

if [ "$CL" -eq 1 ]; then
  [ -f "$RLIST" ] || die "$RLIST is missing"
  E=$(read_list < "$RLIST") || exit 1
  M=$(blobs | unlisted "$E" .gitignore tools/gen.sh) || exit 1
  [ -z "$M" ] || die "$RLIST does not name $(printf '%s\n' "$M" | tr '\n' ' ')which people could run: add each, as committed or built, or as unreleased when people never run it from a release, in the pull request that adds it"
  say "$RLIST names every file people run."; exit 0
fi

[ -n "$V" ] || die "usage: bash tools/release.sh [--dry-run] X.Y.Z"
printf '%s\n' "$V" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ||
  die "the version must be X.Y.Z, numbers only, without a leading v: got '$V'"
TAG=v$V

for t in git ssh-keygen awk; do command -v "$t" >/dev/null 2>&1 || die "needs $t"; done
[ "$DRY" -eq 1 ] || command -v gh >/dev/null 2>&1 || die "needs gh, signed in, to create the GitHub release"
if command -v shasum >/dev/null 2>&1; then sha256() { shasum -a 256 "$1" | awk '{ print $1 }'; }
elif command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$1" | awk '{ print $1 }'; }
else die "needs shasum or sha256sum"; fi
KEYGEN=$(command -v ssh-keygen)
case $KEYGEN in /*) ;; *) die "ssh-keygen must be a program on PATH, not $KEYGEN" ;; esac
KGDIR=$(cd "$(dirname "$KEYGEN")" && pwd -P) || die "can't resolve the folder of $KEYGEN"
case "$KGDIR/" in "$TOP/"*) die "ssh-keygen on PATH is inside the repository ($KEYGEN): put the system's first" ;; esac

CFG=$(git config --list --show-scope) || die "git config --show-scope failed: this needs git 2.26 or later"
BAD=$(printf '%s\n' "$CFG" | awk -F '\t' '$1 == "local" || $1 == "worktree" { k = $2; sub(/=.*/, "", k); print k }' |
  grep -vE '^(core\.(repositoryformatversion|filemode|bare|logallrefupdates|ignorecase|precomposeunicode)|remote\.origin\.(url|fetch|gh-resolved)|branch\..+\.(remote|merge)|extensions\.worktreeconfig)$' | LC_ALL=C sort -u)
[ -z "$BAD" ] || die "this repository's own git config sets $(printf '%s\n' "$BAD" | tr '\n' ' ')which git clone and git worktree add do not write: remove each, or release from a fresh clone"
IA=$(git rev-parse --git-path info/attributes) || die "can't find .git/info/attributes"
[ ! -s "$IA" ] || die "$IA is not empty: it changes how git copies files out; empty it, or release from a fresh clone"

K=${BLINDSPOT_SIGNING_KEY:-}
[ -n "$K" ] || die "set BLINDSPOT_SIGNING_KEY to the path of your release key"
[ -f "$K" ] && [ -r "$K" ] || die "BLINDSPOT_SIGNING_KEY ($K) is not a readable file"
KDIR=$(cd "$(dirname "$K")" && pwd -P) || die "can't resolve the folder of $K"
case "$KDIR/" in "$TOP/"*) die "the release key is inside the repository ($K): keep it outside, on your own computer" ;; esac

[ -f "$SIGNERS" ] || die "$SIGNERS is missing"
grep -Eq "^${PRINCIPAL}[[:space:]]+namespaces=\"[^\"]*${NS}[^\"]*\"[[:space:]]+ssh-" "$SIGNERS" ||
  die "$SIGNERS has no key line for $PRINCIPAL in the $NS namespace: add your public key by pull request first"

REPO=""
if [ "$DRY" -eq 0 ]; then
  REPO=$(git config --get remote.origin.url | sed -nE 's#^(https://|ssh://git@|git@)github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\2#p' | sed 's/\.git$//')
  [ -n "$REPO" ] || die "origin is not a GitHub repository URL: $(git config --get remote.origin.url)"
fi

[ -z "$(G status --porcelain --untracked-files=all)" ] ||
  die "the working tree is not clean: commit, stash or remove these first: $(G status --porcelain --untracked-files=all | head -n 5 | tr '\n' ' ')"
# A tag that already exists here with other content makes the fetch fail rather than move it.
G fetch --quiet origin '+refs/heads/main:refs/remotes/origin/main' 'refs/tags/*:refs/tags/*' ||
  die "git fetch from origin failed"
SHA=$(G rev-parse --verify "HEAD^{commit}") || die "no commit at HEAD"
[ "$SHA" = "$(G rev-parse refs/remotes/origin/main)" ] ||
  die "HEAD is not origin/main: check out the tip of origin/main ($(G rev-parse --short refs/remotes/origin/main))"

# Prints 1 when $1 is newer than $2, compared as numbers.
newer() { awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, "."); for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) { print 1; exit } if (x[i] + 0 < y[i] + 0) { print 0; exit } } print 0 }'; }
PREV=""
for t in $(G tag -l 'v*'); do
  printf '%s\n' "$t" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die "tag $t is not vX.Y.Z, so it can't be compared with $TAG"
  [ "$(newer "$V" "${t#v}")" = 1 ] || die "$TAG is not higher than the existing release $t"
  if [ -z "$PREV" ] || [ "$(newer "${t#v}" "${PREV#v}")" = 1 ]; then PREV=$t; fi
done

W=$(mktemp -d "${TMPDIR:-/tmp}/blindspot-release.XXXXXX") || die "mktemp failed"
KEEP=0
trap '[ "$KEEP" -eq 1 ] || rm -rf "$W"' EXIT
trap 'exit 1' INT TERM HUP

G cat-file blob "$SHA:CHANGELOG.md" > "$W/CHANGELOG.md" 2>/dev/null || die "CHANGELOG.md is not committed"
awk -v h="## $V," 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$W/CHANGELOG.md" |
  awk 'NF { n = NR } { l[NR] = $0 } END { s = 1; while (s <= n && l[s] !~ /[^[:space:]]/) s++; for (i = s; i <= n; i++) print l[i] }' > "$W/notes.md"
awk -v h="## $V," 'index($0, h) == 1 { f = 1 } END { exit !f }' "$W/CHANGELOG.md" || die "CHANGELOG.md has no '## $V, <date>' section"
[ -s "$W/notes.md" ] || die "CHANGELOG.md's $V section is empty"

# The files to release come from the reviewed commit's list, never the working tree's.
G cat-file blob "$SHA:$RLIST" > "$W/release-files" 2>/dev/null || die "$RLIST is not committed at $SHA"
ENTRIES=$(read_list < "$W/release-files") || die "$RLIST can't be used: fix it by pull request"
printf '%s\n' "$ENTRIES" | awk '$2 != "unreleased"' | LC_ALL=C sort > "$W/entries"
G cat-file blob "$SHA:.gitignore" > "$W/gitignore" 2>/dev/null || die ".gitignore is not committed at $SHA"
G cat-file blob "$SHA:tools/gen.sh" > "$W/gen.sh" 2>/dev/null || die "tools/gen.sh is not committed at $SHA"
MISS=$(blobs "$SHA" | unlisted "$ENTRIES" "$W/gitignore" "$W/gen.sh") || die "can't check $RLIST"
[ -z "$MISS" ] || die "$RLIST does not name $(printf '%s\n' "$MISS" | tr '\n' ' ')which people could run: add each, or exempt it as unreleased, by pull request first"

if [ -n "$PREV" ]; then
  FROM=$PREV; RANGE="$PREV..$SHA"; say "Changes since $PREV:"
else
  FROM=$(G hash-object -t tree /dev/null); RANGE=$SHA; say "First release: every commit."
fi
say ""
# A commit subject or a changed line can hold terminal control bytes that rewrite what is shown, and
# a committed .gitattributes can turn a diff into "Binary files differ": every listing below is
# shown as text, with each byte outside printable ASCII made visible (cat -v).
G --no-pager log --no-decorate --format='%h %s' "$RANGE" | LC_ALL=C cat -v
say ""
G --no-pager diff --no-ext-diff --no-textconv --text --stat "$FROM" "$SHA" | LC_ALL=C cat -v
say ""
say "In full, the changes to what releases and checks (tools/, .github/, .gitattributes, .gitmodules):"
G --no-pager diff --no-ext-diff --no-textconv --text "$FROM" "$SHA" -- tools .github .gitattributes .gitmodules | LC_ALL=C cat -v
say ""
say "Review every commit and file above against the security review in CONTRIBUTING.md."
printf 'Type %s to confirm you reviewed them: ' "$V"
read -r ANSWER || ANSWER=""
[ "$ANSWER" = "$V" ] || die "confirmation did not match $V: nothing was run, signed or published"

# Everything from here runs on a copy of the reviewed commit, not on the checkout.
S=$W/src
mkdir "$S" && G archive --format=tar -o "$W/src.tar" "$SHA" && tar -xf "$W/src.tar" -C "$S" || die "could not copy $SHA out to build it"
# git archive applies export-subst and export-ignore, so the copy is checked against the commit's
# tree, file by file, before gen.sh runs in it.
G ls-tree -r -z "$SHA" | while IFS= read -r -d '' l; do
  case $l in *" blob "*) r=${l#* blob }; printf '%s %s\0' "${r%%$'\t'*}" "${r#*$'\t'}" ;; esac
done | LC_ALL=C sort -z > "$W/tree"
(cd "$S" && find . \( -type f -o -type l \) -print0) | while IFS= read -r -d '' p; do
  p=${p#./}
  if [ -L "$S/$p" ]; then h=$(printf '%s' "$(readlink "$S/$p")" | G hash-object --stdin)
  else h=$(G hash-object --no-filters -- "$S/$p"); fi
  printf '%s %s\0' "$h" "$p"
done | LC_ALL=C sort -z > "$W/copy"
cmp -s "$W/tree" "$W/copy" ||
  die "the copy of $SHA is not the commit, at: $(LC_ALL=C comm -3 <(tr '\0' '\n' < "$W/tree") <(tr '\0' '\n' < "$W/copy") | sed -E 's/^[[:space:]]*[0-9a-f]+ //' | LC_ALL=C sort -u | head -n 5 | tr '\n' ' ')nothing was run, signed or published"
gen() {
  (cd "$S" && bash tools/gen.sh "$@") > "$W/gen.txt" 2>&1 && return
  _r=$?; cat "$W/gen.txt" >&2
  [ "$_r" -ne 3 ] || die "bash tools/gen.sh${1:+ $1} exited 3: it needs PowerShell to build the Windows files. Install PowerShell (pwsh), or set PWSH=/path/to/pwsh, and run this again. Nothing was signed or published"
  die "bash tools/gen.sh${1:+ $1} failed (exit $_r): nothing was signed or published"
}
ls -A "$S" | LC_ALL=C sort > "$W/before"
gen --check
gen
ls -A "$S" | LC_ALL=C sort | LC_ALL=C comm -13 "$W/before" - > "$W/made"
while IFS= read -r n; do
  awk -v n="$n" '$1 == n && $2 == "built" { f = 1 } END { exit !f }' "$W/entries" ||
    die "bash tools/gen.sh made $n, which $RLIST does not name as built: nothing was signed or published"
done < "$W/made"
while read -r n kind; do
  [ -f "$S/$n" ] && [ ! -L "$S/$n" ] && [ -s "$S/$n" ] ||
    die "$n, listed in $RLIST, is missing or empty after bash tools/gen.sh: nothing was signed or published"
  if G cat-file -e "$SHA:$n" 2>/dev/null; then
    [ "$kind" = committed ] || die "$n is listed as built but is committed at $SHA: fix $RLIST"
    G cat-file blob "$SHA:$n" > "$W/blob" && cmp -s "$W/blob" "$S/$n" ||
      die "$n is not its committed copy after bash tools/gen.sh: nothing was signed or published"
  else
    [ "$kind" = built ] || die "$n is listed as committed but is not committed at $SHA"
  fi
done < "$W/entries"

G cat-file blob "$SHA:$SIGNERS" > "$W/allowed_signers" 2>/dev/null || die "$SIGNERS is not committed at $SHA"
{
  printf 'version %s\n' "$TAG"
  while read -r n _; do printf '%s  %s\n' "$(sha256 "$S/$n")" "$n"; done < "$W/entries"
} > "$W/SHA256SUMS"
if sed 1d "$W/SHA256SUMS" | grep -Evq '^[0-9a-f]{64}  [A-Za-z0-9._-]+$'; then die "a line of SHA256SUMS is not a SHA-256 and a file name"; fi

say "Signing SHA256SUMS with $K"
"$KEYGEN" -Y sign -n "$NS" -f "$K" "$W/SHA256SUMS" || die "ssh-keygen could not sign SHA256SUMS"
"$KEYGEN" -Y verify -f "$W/allowed_signers" -I "$PRINCIPAL" -n "$NS" -s "$W/SHA256SUMS.sig" < "$W/SHA256SUMS" ||
  die "the signature does not verify against $SIGNERS: is your key's line there? Nothing was published"

if [ "$DRY" -eq 1 ]; then
  KEEP=1
  say "Dry run: every check passed and the signature verifies. No tag, push or release was made."
  say "Files: $W"
  exit 0
fi

GS() { G -c gpg.format=ssh -c gpg.ssh.program="$KEYGEN" -c gpg.ssh.allowedSignersFile="$W/allowed_signers" "$@"; }
GS -c user.signingkey="$K" tag -s "$TAG" -m "Blindspot $V" "$SHA" || die "git could not create the signed tag $TAG"
if ! GS tag -v "$TAG" || [ "$(G rev-parse "$TAG^{commit}")" != "$SHA" ]; then
  G tag -d "$TAG" >/dev/null 2>&1; die "the tag $TAG does not verify against $SIGNERS; it was deleted and nothing was published"
fi
G push origin "refs/tags/$TAG" || {
  G tag -d "$TAG" >/dev/null 2>&1; die "git push of $TAG failed; the local tag was deleted and nothing was published"
}
set --
while read -r n _; do set -- "$@" "$S/$n"; done < "$W/entries"
set -- "$@" "$W/SHA256SUMS" "$W/SHA256SUMS.sig"
gh release create "$TAG" "$@" -R "$REPO" --title "Blindspot $V" --notes-file "$W/notes.md" --verify-tag || {
  KEEP=1
  if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    die "$TAG is pushed and its GitHub release exists but may be missing files. Its files are in $W; finish it with: gh release upload $(printf '%q ' "$TAG" "$@")--clobber -R $(printf '%q' "$REPO")"
  fi
  die "$TAG is pushed but the GitHub release was not created. Its files are in $W; create it with: gh release create $(printf '%q ' "$TAG" "$@")-R $(printf '%q' "$REPO") --title $(printf '%q' "Blindspot $V") --notes-file $(printf '%q' "$W/notes.md") --verify-tag"
}
say "Released $TAG."
