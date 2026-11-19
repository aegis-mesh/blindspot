#!/usr/bin/env bash
# Tests tools/release.sh offline. Each case copies the repository's release inputs into a new
# throwaway repository whose origin is a local bare repository, signs with a throwaway ed25519 key
# made here with no passphrase, and puts a stand-in gh first on PATH that records its arguments.
# Nothing reaches GitHub. Git reads only a config made here, so no global hook or signing setting
# applies.
#
#   bash tests/release.sh
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
SRC=$PWD
W=$(mktemp -d 2>/dev/null || mktemp -d -t release-test)
trap 'rm -rf "$W"' EXIT
RB=/bin/bash; [ -x "$RB" ] || RB=bash

export HOME="$W/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$W/bin" "$W/tmp"
printf '[user]\n\tname = Release Test\n\temail = release-test@example.com\n[init]\n\tdefaultBranch = main\n[core]\n\thooksPath = %s/nohooks\n' "$W" > "$HOME/.gitconfig"
cat > "$W/bin/gh" <<'EOF'
#!/bin/sh
: > "$GH_LOG"
for a in "$@"; do printf '%s\n' "$a" >> "$GH_LOG"; done
n=""; for a in "$@"; do [ "$n" = 1 ] && cp "$a" "$GH_LOG.notes"; n=""; [ "$a" = --notes-file ] && n=1; done
exit 0
EOF
chmod +x "$W/bin/gh"
export GH_LOG="$W/gh.log"

# shellcheck disable=SC2034  # tests/lib.sh's helpers read SKIPPING
if ! ssh-keygen -Y sign 2>&1 | grep -q 'namespace'; then SKIPPING="ssh-keygen here has no -Y sign (OpenSSH 8.1 or later)"
elif [ "$(git version | awk '{ split($3, v, "."); print (v[1] > 2 || (v[1] == 2 && v[2] >= 34)) }')" != 1 ]; then SKIPPING="git here is older than 2.34, which signs tags with SSH keys"
fi

ssh-keygen -q -t ed25519 -N '' -C release-test -f "$W/key" < /dev/null
ssh-keygen -q -t ed25519 -N '' -C other-test -f "$W/other" < /dev/null
SIGNERLINE="release@blindspot namespaces=\"git,blindspot-release\" $(cat "$W/key.pub")"

# fresh NAME [nokey]: a repository at $W/NAME with an origin at $W/NAME.git, a v1.2.0 release and
# one commit since, which adds the 1.3.0 notes.
fresh() {
  R=$W/$1
  mkdir -p "$R/.github" "$R/tools"
  cp -R "$SRC/gird-check.sh" "$SRC/gird-check.ps1" "$SRC/gird-fleet.sh" "$SRC/data" "$SRC/.gitattributes" "$R/"
  cp "$SRC/tools/gen.sh" "$SRC/tools/release.sh" "$R/tools/"
  cp "$SRC/.github/allowed_signers" "$R/.github/"
  [ "${2:-}" = nokey ] || printf '%s\n' "$SIGNERLINE" >> "$R/.github/allowed_signers"
  cp "$SRC/CHANGELOG.md" "$R/"
  git -C "$R" init -q
  git -C "$R" add -A
  git -C "$R" commit -q -m one
  git -C "$R" tag -a v1.2.0 -m "Blindspot 1.2.0"
  { printf '# Changelog\n\n## 1.3.0, 19 November 2026\n\n- A change for the tests.\n- And a second one.\n\n'; sed 1d "$SRC/CHANGELOG.md"; } > "$R/CHANGELOG.md"
  git -C "$R" commit -q -am "Notes for 1.3.0"
  git clone -q --bare "$R" "$R.git"
  git -C "$R" remote add origin "$R.git"
  git -C "$R" fetch -q origin
}
# rel NAME ANSWER [ARGS...]: runs the release tool in $W/NAME, typing ANSWER, into $W/NAME.out.
rel() {
  _n=$1; _a=$2; shift 2; rm -f "$GH_LOG" "$GH_LOG.notes"
  (cd "$W/$_n" && printf '%s\n' "$_a" | TMPDIR="$W/tmp" PATH="$W/bin:$PATH" BLINDSPOT_SIGNING_KEY="${KEY:-$W/key}" "$RB" tools/release.sh "$@") > "$W/$_n.out" 2>&1
  RC=$?
}
refused() { [ "$RC" -ne 0 ] && grep -q "$1" "$W/$2.out" && [ -z "$(git -C "$W/$2" tag -l v1.3.0)" ] && [ ! -s "$GH_LOG" ]; }

echo "release tool: refusals"
fresh nokey nokey; rel nokey 1.3.0 1.3.0
if refused 'has no key line' nokey; then ok "refuses to release while allowed_signers has no key"; else bad "refuses to release while allowed_signers has no key" "exit $RC: $(tail -n 2 "$W/nokey.out")"; fi
if grep -v '^#' "$SRC/.github/allowed_signers" | grep -q .; then bad "the repository's allowed_signers holds only comments until a maintainer adds a key"; else ok "the repository's allowed_signers holds only comments until a maintainer adds a key"; fi

fresh eq; rel eq 1.2.0 1.2.0
if refused 'not higher than the existing release v1.2.0' eq; then ok "refuses a version equal to a release"; else bad "refuses a version equal to a release" "exit $RC: $(tail -n 2 "$W/eq.out")"; fi
git -C "$W/eq" tag -a v1.10.0 -m x; git -C "$W/eq" push -q origin v1.10.0 2>/dev/null
rel eq 1.9.0 1.9.0
if refused 'not higher than the existing release v1.10.0' eq; then ok "refuses a version below a release, compared as numbers"; else bad "refuses a version below a release, compared as numbers" "exit $RC: $(tail -n 2 "$W/eq.out")"; fi
rel eq v1.11.0 v1.11.0
if refused 'must be X.Y.Z' eq; then ok "refuses a version that is not X.Y.Z"; else bad "refuses a version that is not X.Y.Z" "exit $RC: $(tail -n 2 "$W/eq.out")"; fi

fresh dirty; printf '\n' >> "$W/dirty/gird-check.sh"; rel dirty 1.3.0 1.3.0
if refused 'working tree is not clean' dirty; then ok "refuses a working tree with changes"; else bad "refuses a working tree with changes" "exit $RC: $(tail -n 2 "$W/dirty.out")"; fi
fresh untracked; : > "$W/untracked/stray.txt"; rel untracked 1.3.0 1.3.0
if refused 'working tree is not clean' untracked; then ok "refuses a working tree with an untracked file"; else bad "refuses a working tree with an untracked file" "exit $RC: $(tail -n 2 "$W/untracked.out")"; fi

fresh ahead; git -C "$W/ahead" commit -q --allow-empty -m local; rel ahead 1.3.0 1.3.0
if refused 'HEAD is not origin/main' ahead; then ok "refuses a HEAD that is not origin/main"; else bad "refuses a HEAD that is not origin/main" "exit $RC: $(tail -n 2 "$W/ahead.out")"; fi

fresh nolog; rel nolog 1.4.0 1.4.0
if refused "no '## 1.4.0, <date>' section" nolog; then ok "refuses a version with no CHANGELOG section"; else bad "refuses a version with no CHANGELOG section" "exit $RC: $(tail -n 2 "$W/nolog.out")"; fi

fresh confirm; rel confirm 1.3 1.3.0
if refused 'confirmation did not match' confirm && grep -q 'Changes since v1.2.0' "$W/confirm.out" && grep -q 'Notes for 1.3.0' "$W/confirm.out" && grep -q 'CHANGELOG.md *| *[0-9]' "$W/confirm.out"; then ok "lists the changes and refuses a wrong confirmation"; else bad "lists the changes and refuses a wrong confirmation" "exit $RC: $(tail -n 2 "$W/confirm.out")"; fi

fresh stranger; KEY=$W/other rel stranger 1.3.0 1.3.0
if refused 'does not verify against' stranger; then ok "refuses a key not in allowed_signers"; else bad "refuses a key not in allowed_signers" "exit $RC: $(tail -n 2 "$W/stranger.out")"; fi

fresh inside; cp "$W/key" "$W/inside/release-key"; KEY=$W/inside/release-key rel inside 1.3.0 1.3.0
if refused 'release key is inside the repository' inside; then ok "refuses a release key inside the repository"; else bad "refuses a release key inside the repository" "exit $RC: $(tail -n 2 "$W/inside.out")"; fi

echo "release tool: a dry run"
fresh dry; rel dry 1.3.0 --dry-run 1.3.0
D=$(sed -n 's/^Files: //p' "$W/dry.out")
if [ "$RC" -eq 0 ] && [ -n "$D" ] && [ -f "$D/SHA256SUMS" ]; then ok "a dry run passes and keeps its files" "$D"; else bad "a dry run passes and keeps its files" "exit $RC: $(tail -n 3 "$W/dry.out")"; D=$W/none; fi
want() { printf 'version v1.3.0\n'; for f in gird-check.ps1 gird-check.sh gird-fleet.sh; do printf '%s  %s\n' "$(git -C "$W/dry" cat-file blob "HEAD:$f" | shasum -a 256 | awk '{ print $1 }')" "$f"; done; }
if [ -f "$D/SHA256SUMS" ] && want | cmp -s - "$D/SHA256SUMS"; then ok "SHA256SUMS is the version line, then each committed file's SHA-256, sorted"; else bad "SHA256SUMS is the version line, then each committed file's SHA-256, sorted" "$(cat "$D/SHA256SUMS" 2>/dev/null)"; fi
if [ -f "$D/SHA256SUMS" ] && ! LC_ALL=C grep -q "$(printf '\r')" "$D/SHA256SUMS" && [ "$(tail -c 1 "$D/SHA256SUMS" | od -An -c | tr -d ' ')" = '\n' ] && [ "$(sed 1d "$D/SHA256SUMS" | awk '{ print $2 }')" = "$(sed 1d "$D/SHA256SUMS" | awk '{ print $2 }' | LC_ALL=C sort)" ]
then ok "SHA256SUMS has LF line ends, a final newline and names in byte order"; else bad "SHA256SUMS has LF line ends, a final newline and names in byte order"; fi
if [ -f "$D/SHA256SUMS.sig" ] && ssh-keygen -Y verify -f "$W/dry/.github/allowed_signers" -I release@blindspot -n blindspot-release -s "$D/SHA256SUMS.sig" < "$D/SHA256SUMS" > /dev/null 2>&1
then ok "its signature verifies as release@blindspot in the blindspot-release namespace"; else bad "its signature verifies as release@blindspot in the blindspot-release namespace"; fi
if [ -f "$D/SHA256SUMS.sig" ] && ! ssh-keygen -Y verify -f "$W/dry/.github/allowed_signers" -I release@blindspot -n git -s "$D/SHA256SUMS.sig" < "$D/SHA256SUMS" > /dev/null 2>&1
then ok "and not in another namespace"; else bad "and not in another namespace"; fi
if [ -z "$(git -C "$W/dry" tag -l v1.3.0)" ] && [ -z "$(git -C "$W/dry.git" tag -l v1.3.0)" ] && [ ! -s "$GH_LOG" ]; then ok "a dry run makes no tag and no release"; else bad "a dry run makes no tag and no release"; fi

echo "release tool: a release"
fresh full; rel full 1.3.0 1.3.0
if [ "$RC" -eq 0 ] && grep -q 'Released v1.3.0' "$W/full.out"; then ok "a release runs to the end"; else bad "a release runs to the end" "exit $RC: $(tail -n 3 "$W/full.out")"; fi
if git -C "$W/full.git" -c gpg.ssh.allowedSignersFile="$W/full/.github/allowed_signers" tag -v v1.3.0 > "$W/tagv.txt" 2>&1 && [ "$(git -C "$W/full.git" rev-parse 'v1.3.0^{commit}')" = "$(git -C "$W/full" rev-parse HEAD)" ]
then ok "it pushes a signed tag on HEAD that git tag -v accepts"; else bad "it pushes a signed tag on HEAD that git tag -v accepts" "$(head -n 3 "$W/tagv.txt")"; fi
G=$(tr '\n' ' ' < "$GH_LOG" 2>/dev/null)
case "$G" in
  "release create v1.3.0 "*/gird-check.ps1\ */gird-check.sh\ */gird-fleet.sh\ */SHA256SUMS\ */SHA256SUMS.sig\ *--verify-tag*) ok "it creates the GitHub release with the five files" ;;
  *) bad "it creates the GitHub release with the five files" "gh got: $G" ;;
esac
if [ -f "$GH_LOG.notes" ] && [ "$(cat "$GH_LOG.notes")" = "$(printf -- '- A change for the tests.\n- And a second one.')" ]; then ok "its notes are the version's CHANGELOG section"; else bad "its notes are the version's CHANGELOG section" "$(head -n 3 "$GH_LOG.notes" 2>/dev/null)"; fi

finish
