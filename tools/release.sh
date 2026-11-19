#!/usr/bin/env bash
# Cuts a signed release, for maintainers (docs/designs/signed-releases.md). It checks everything
# first and publishes nothing until every check has passed.
#
#   BLINDSPOT_SIGNING_KEY=~/.ssh/blindspot-release bash tools/release.sh [--dry-run] X.Y.Z
#
# --dry-run does every step up to and including checking its own signature, then stops before the
# tag, the push and the GitHub release, and keeps the files it made for you to look at.
# ssh-keygen asks for the key's passphrase itself, once for SHA256SUMS and once for the tag; this
# script never reads, stores or passes it.
set -u

FILES="gird-check.ps1 gird-check.sh gird-fleet.sh"
SIGNERS=.github/allowed_signers
PRINCIPAL=release@blindspot
NS=blindspot-release

die() { printf 'release: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

DRY=0; V=""
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $a" ;;
    *) [ -z "$V" ] || die "give one version"; V=$a ;;
  esac
done
[ -n "$V" ] || die "usage: bash tools/release.sh [--dry-run] X.Y.Z"
printf '%s\n' "$V" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ||
  die "the version must be X.Y.Z, numbers only, without a leading v: got '$V'"
TAG=v$V

cd "$(dirname "$0")/.." || die "can't find the repository"
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$TOP" || die "can't enter $TOP"

for t in git ssh-keygen awk; do command -v "$t" >/dev/null 2>&1 || die "needs $t"; done
[ "$DRY" -eq 1 ] || command -v gh >/dev/null 2>&1 || die "needs gh, signed in, to create the GitHub release"
if command -v shasum >/dev/null 2>&1; then sha256() { shasum -a 256 "$1" | awk '{ print $1 }'; }
elif command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$1" | awk '{ print $1 }'; }
else die "needs shasum or sha256sum"; fi

K=${BLINDSPOT_SIGNING_KEY:-}
[ -n "$K" ] || die "set BLINDSPOT_SIGNING_KEY to the path of your release key"
[ -f "$K" ] && [ -r "$K" ] || die "BLINDSPOT_SIGNING_KEY ($K) is not a readable file"
KDIR=$(cd "$(dirname "$K")" && pwd -P) || die "can't resolve the folder of $K"
case "$KDIR/" in "$(pwd -P)/"*) die "the release key is inside the repository ($K): keep it outside, on your own computer" ;; esac

[ -f "$SIGNERS" ] || die "$SIGNERS is missing"
grep -Eq "^${PRINCIPAL}[[:space:]]+namespaces=\"[^\"]*${NS}[^\"]*\"[[:space:]]+ssh-" "$SIGNERS" ||
  die "$SIGNERS has no key line for $PRINCIPAL in the $NS namespace: add your public key by pull request first"

[ -z "$(git status --porcelain --untracked-files=all)" ] ||
  die "the working tree is not clean: commit, stash or remove these first: $(git status --porcelain --untracked-files=all | head -n 5 | tr '\n' ' ')"
# A tag that already exists here with other content makes the fetch fail rather than move it.
git fetch --quiet origin '+refs/heads/main:refs/remotes/origin/main' 'refs/tags/*:refs/tags/*' ||
  die "git fetch from origin failed"
[ "$(git rev-parse HEAD)" = "$(git rev-parse refs/remotes/origin/main)" ] ||
  die "HEAD is not origin/main: check out the tip of origin/main ($(git rev-parse --short refs/remotes/origin/main))"

# Prints 1 when $1 is newer than $2, compared as numbers.
newer() { awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, "."); for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) { print 1; exit } if (x[i] + 0 < y[i] + 0) { print 0; exit } } print 0 }'; }
PREV=""
for t in $(git tag -l 'v*'); do
  printf '%s\n' "$t" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die "tag $t is not vX.Y.Z, so it can't be compared with $TAG"
  [ "$(newer "$V" "${t#v}")" = 1 ] || die "$TAG is not higher than the existing release $t"
  if [ -z "$PREV" ] || [ "$(newer "${t#v}" "${PREV#v}")" = 1 ]; then PREV=$t; fi
done

W=$(mktemp -d 2>/dev/null || mktemp -d -t blindspot-release) || die "mktemp failed"
KEEP=0
trap '[ "$KEEP" -eq 1 ] || rm -rf "$W"' EXIT
trap 'exit 1' INT TERM HUP

git cat-file blob HEAD:CHANGELOG.md > "$W/CHANGELOG.md" 2>/dev/null || die "CHANGELOG.md is not committed"
awk -v h="## $V," 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$W/CHANGELOG.md" |
  awk 'NF { n = NR } { l[NR] = $0 } END { s = 1; while (s <= n && l[s] !~ /[^[:space:]]/) s++; for (i = s; i <= n; i++) print l[i] }' > "$W/notes.md"
grep -q "^## $V," "$W/CHANGELOG.md" || die "CHANGELOG.md has no '## $V, <date>' section"
[ -s "$W/notes.md" ] || die "CHANGELOG.md's $V section is empty"

bash tools/gen.sh --check > "$W/gen.txt" 2>&1 || { cat "$W/gen.txt" >&2; die "bash tools/gen.sh --check failed"; }

if [ -n "$PREV" ]; then
  FROM=$PREV; RANGE="$PREV..HEAD"; say "Changes since $PREV:"
else
  FROM=$(git hash-object -t tree /dev/null); RANGE=HEAD; say "First release: every commit."
fi
say ""
git --no-pager log --oneline "$RANGE"
say ""
git --no-pager diff --stat "$FROM" HEAD
say ""
say "Review every commit and file above against the security review in CONTRIBUTING.md."
printf 'Type %s to confirm you reviewed them: ' "$V"
read -r ANSWER || ANSWER=""
[ "$ANSWER" = "$V" ] || die "confirmation did not match $V: nothing was signed or published"

for f in $FILES; do
  git cat-file blob "HEAD:$f" > "$W/$f" 2>/dev/null || die "$f is not committed at HEAD"
done
{
  printf 'version %s\n' "$TAG"
  for f in $FILES; do printf '%s  %s\n' "$(sha256 "$W/$f")" "$f"; done
} > "$W/SHA256SUMS"
if sed 1d "$W/SHA256SUMS" | grep -Evq '^[0-9a-f]{64}  [a-z0-9.-]+$'; then die "a line of SHA256SUMS is not a SHA-256 and a file name"; fi

say "Signing SHA256SUMS with $K"
ssh-keygen -Y sign -n "$NS" -f "$K" "$W/SHA256SUMS" || die "ssh-keygen could not sign SHA256SUMS"
ssh-keygen -Y verify -f "$SIGNERS" -I "$PRINCIPAL" -n "$NS" -s "$W/SHA256SUMS.sig" < "$W/SHA256SUMS" ||
  die "the signature does not verify against $SIGNERS: is your key's line there? Nothing was published"

if [ "$DRY" -eq 1 ]; then
  KEEP=1
  say "Dry run: every check passed and the signature verifies. No tag, push or release was made."
  say "Files: $W"
  exit 0
fi

git -c gpg.format=ssh -c user.signingkey="$K" tag -s "$TAG" -m "Blindspot $V" HEAD || die "git could not create the signed tag $TAG"
git -c gpg.ssh.allowedSignersFile="$SIGNERS" tag -v "$TAG" || {
  git tag -d "$TAG" >/dev/null 2>&1; die "the tag $TAG does not verify against $SIGNERS; it was deleted and nothing was published"
}
git push origin "refs/tags/$TAG" || {
  git tag -d "$TAG" >/dev/null 2>&1; die "git push of $TAG failed; the local tag was deleted and nothing was published"
}
set --
for f in $FILES SHA256SUMS SHA256SUMS.sig; do set -- "$@" "$W/$f"; done
gh release create "$TAG" "$@" --title "Blindspot $V" --notes-file "$W/notes.md" --verify-tag || {
  KEEP=1
  die "$TAG is pushed but the GitHub release was not created. Its files are in $W; create it with: gh release create $TAG $* --title 'Blindspot $V' --notes-file $W/notes.md --verify-tag"
}
say "Released $TAG."
