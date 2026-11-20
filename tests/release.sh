#!/usr/bin/env bash
# Tests tools/release.sh offline. Each case copies the repository's release inputs into a new
# throwaway repository whose origin reads as a GitHub URL but is rewritten (url.insteadOf) to a
# local bare repository, signs with a throwaway ed25519 key made here with no passphrase, and puts a
# stand-in gh first on PATH that records its arguments. Nothing reaches GitHub. Git reads only a config made here, so no global hook or signing setting
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
# The stand-in gh: GH_FAIL makes release create fail, GH_EXISTS makes release view find it.
cat > "$W/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "release create")
    : > "$GH_LOG"
    for a in "$@"; do printf '%s\n' "$a" >> "$GH_LOG"; case $a in */SHA256SUMS) cp "$a" "$GH_LOG.sums" ;; esac; done
    n=""; for a in "$@"; do [ "$n" = 1 ] && cp "$a" "$GH_LOG.notes"; n=""; [ "$a" = --notes-file ] && n=1; done
    [ -z "$GH_FAIL" ] ;;
  "release view") [ -n "$GH_EXISTS" ] ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$W/bin/gh"
export GH_LOG="$W/gh.log"
if command -v shasum >/dev/null 2>&1; then sha() { shasum -a 256 | awk '{ print $1 }'; }; else sha() { sha256sum | awk '{ print $1 }'; }; fi

# shellcheck disable=SC2034  # tests/lib.sh's helpers read SKIPPING
if ! ssh-keygen -Y sign 2>&1 | grep -q 'namespace'; then SKIPPING="ssh-keygen here has no -Y sign (OpenSSH 8.1 or later)"
elif [ "$(git version | awk '{ split($3, v, "."); print (v[1] > 2 || (v[1] == 2 && v[2] >= 34)) }')" != 1 ]; then SKIPPING="git here is older than 2.34, which signs tags with SSH keys"
fi
# The cases that run this repository's own tools/gen.sh to the end need PowerShell, which builds
# blindspot-fleet.ps1: they skip without it (needgen), and the rest still run.
BASESKIP=$SKIPPING
_pw=${PWSH:-$(command -v pwsh 2>/dev/null || true)}
NOGEN=""; [ -n "$_pw" ] && [ -x "$_pw" ] || NOGEN="no PowerShell here (pwsh on PATH, or PWSH): bash tools/gen.sh needs it to build blindspot-fleet.ps1"
needgen() { SKIPPING=${BASESKIP:-$NOGEN}; }
endgen() { SKIPPING=$BASESKIP; }

ssh-keygen -q -t ed25519 -N '' -C release-test -f "$W/key" < /dev/null
ssh-keygen -q -t ed25519 -N '' -C other-test -f "$W/other" < /dev/null
SIGNERLINE="release@blindspot namespaces=\"git,blindspot-release\" $(cat "$W/key.pub")"

# fresh NAME [nokey]: a repository at $W/NAME with an origin at $W/NAME.git, a v1.2.0 release and
# one commit since, which adds the 1.3.0 notes. It holds every file this repository's
# .github/release-files names as committed, and what tools/gen.sh reads to build the rest.
fresh() {
  R=$W/$1
  mkdir -p "$R/.github" "$R/tools"
  for _f in $(awk '!/^[[:space:]]*#/ && $2 == "committed" { print $1 }' "$SRC/.github/release-files"); do cp "$SRC/$_f" "$R/"; done
  cp -R "$SRC/data" "$SRC/.gitattributes" "$SRC/.gitignore" "$R/"
  cp "$SRC/tools/gen.sh" "$SRC/tools/release.sh" "$SRC/tools/strip-comments.ps1" "$R/tools/"
  cp "$SRC/.github/allowed_signers" "$SRC/.github/release-files" "$R/.github/"
  [ "${2:-}" = nokey ] || printf '%s\n' "$SIGNERLINE" >> "$R/.github/allowed_signers"
  cp "$SRC/CHANGELOG.md" "$R/"
  git -C "$R" init -q
  git -C "$R" add -A
  git -C "$R" commit -q -m one
  git -C "$R" tag -a v1.2.0 -m "Blindspot 1.2.0"
  { printf '# Changelog\n\n## 1.3.0, 19 November 2026\n\n- A change for the tests.\n- And a second one.\n\n'; sed 1d "$SRC/CHANGELOG.md"; } > "$R/CHANGELOG.md"
  git -C "$R" commit -q -am "Notes for 1.3.0"
  git clone -q --bare "$R" "$R.git"
  git -C "$W" config --global url."$R.git".insteadOf "https://github.com/test-owner/$1.git"
  git -C "$R" remote add origin "https://github.com/test-owner/$1.git"
  git -C "$R" fetch -q origin
}
# nobuilt NAME: drops the files the real tools/gen.sh builds from $W/NAME's release list and
# .gitignore, for a case that puts a gen.sh of its own in its place.
nobuilt() {
  grep -v ' built$' "$W/$1/.github/release-files" > "$W/$1.rf" && cat "$W/$1.rf" > "$W/$1/.github/release-files"
  awk '/^#.*built by bash tools\/gen\.sh/ { b = 1; next } b && (/^[[:space:]]*$/ || /^#/) { b = 0 } !b' "$W/$1/.gitignore" > "$W/$1.gi" && cat "$W/$1.gi" > "$W/$1/.gitignore"
}
# released NAME: the files a release of $W/NAME attaches, one per line, in name order.
released() { awk '!/^[[:space:]]*#/ && NF == 2 { print $1 }' "$W/$1/.github/release-files" | LC_ALL=C sort; }
# recommit NAME MESSAGE: commits every change in $W/NAME and makes it origin/main.
recommit() { git -C "$W/$1" commit -q -am "$2" && git -C "$W/$1" push -q origin HEAD:main && git -C "$W/$1" fetch -q origin; }
# rel NAME ANSWER [ARGS...]: runs the release tool in $W/NAME, typing ANSWER, into $W/NAME.out.
rel() {
  _n=$1; _a=$2; shift 2; rm -f "$GH_LOG" "$GH_LOG.notes" "$GH_LOG.sums"
  (cd "$W/$_n" && printf '%s\n' "$_a" | GH_FAIL="${GH_FAIL:-}" GH_EXISTS="${GH_EXISTS:-}" TMPDIR="$W/tmp" PATH="$W/bin:$PATH" BLINDSPOT_SIGNING_KEY="${KEY:-$W/key}" "$RB" tools/release.sh "$@") > "$W/$_n.out" 2>&1
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

needgen; fresh stranger; KEY=$W/other rel stranger 1.3.0 1.3.0
if refused 'does not verify against' stranger; then ok "refuses a key not in allowed_signers"; else bad "refuses a key not in allowed_signers" "exit $RC: $(tail -n 2 "$W/stranger.out")"; fi
endgen

fresh inside; cp "$W/key" "$W/inside/release-key"; KEY=$W/inside/release-key rel inside 1.3.0 1.3.0
if refused 'release key is inside the repository' inside; then ok "refuses a release key inside the repository"; else bad "refuses a release key inside the repository" "exit $RC: $(tail -n 2 "$W/inside.out")"; fi

fresh pinned; git -C "$W/pinned" config gpg.ssh.program "$W/pinned/evil"; rel pinned 1.3.0 1.3.0
if refused "own git config sets gpg.ssh.program" pinned; then ok "refuses a repository whose git config sets gpg.ssh.program"; else bad "refuses a repository whose git config sets gpg.ssh.program" "exit $RC: $(tail -n 2 "$W/pinned.out")"; fi
fresh filter; git -C "$W/filter" config filter.x.smudge "$W/filter/evil"; rel filter 1.3.0 1.3.0
if refused "own git config sets filter.x.smudge" filter; then ok "refuses a repository whose git config sets a filter"; else bad "refuses a repository whose git config sets a filter" "exit $RC: $(tail -n 2 "$W/filter.out")"; fi
fresh upload; git -C "$W/upload" config remote.origin.uploadpack "$W/upload/evil"; rel upload 1.3.0 1.3.0
if refused "own git config sets remote.origin.uploadpack which" upload; then ok "refuses a repository whose git config sets remote.origin.uploadpack"; else bad "refuses a repository whose git config sets remote.origin.uploadpack" "exit $RC: $(tail -n 2 "$W/upload.out")"; fi
fresh cred; git -C "$W/cred" config credential.helper "$W/cred/evil"; rel cred 1.3.0 1.3.0
if refused "own git config sets credential.helper which" cred; then ok "refuses a repository whose git config sets credential.helper"; else bad "refuses a repository whose git config sets credential.helper" "exit $RC: $(tail -n 2 "$W/cred.out")"; fi
needgen; fresh wt; git -C "$W/wt" worktree add -q --detach "$W/wt2" origin/main; rel wt2 1.3.0 --dry-run 1.3.0
if [ "$RC" -eq 0 ]; then ok "releases from a git worktree add checkout, whose config git wrote"; else bad "releases from a git worktree add checkout, whose config git wrote" "exit $RC: $(tail -n 2 "$W/wt2.out")"; fi
D=$(sed -n 's/^Files: //p' "$W/wt2.out"); [ -z "$D" ] || rm -rf "$D"
fresh ghres; git -C "$W/ghres" config remote.origin.gh-resolved base; rel ghres 1.3.0 --dry-run 1.3.0
if [ "$RC" -eq 0 ]; then ok "releases from a checkout where gh recorded its resolved remote"; else bad "releases from a checkout where gh recorded its resolved remote" "exit $RC: $(tail -n 2 "$W/ghres.out")"; fi
D=$(sed -n 's/^Files: //p' "$W/ghres.out"); [ -z "$D" ] || rm -rf "$D"
endgen
fresh iattr; printf '* export-subst\n' > "$W/iattr/.git/info/attributes"; rel iattr 1.3.0 1.3.0
if refused 'info/attributes is not empty' iattr; then ok "refuses a repository with a non-empty .git/info/attributes"; else bad "refuses a repository with a non-empty .git/info/attributes" "exit $RC: $(tail -n 2 "$W/iattr.out")"; fi
fresh subst; printf '$Format:%%H$\n' > "$W/subst/stamp.txt"; printf 'stamp.txt export-subst\n' >> "$W/subst/.gitattributes"; git -C "$W/subst" add stamp.txt; recommit subst "A file git archive rewrites"
rel subst 1.3.0 1.3.0
if refused 'is not the commit, at: stamp.txt' subst; then ok "refuses when a file git archive copied out is not the committed one"; else bad "refuses when a file git archive copied out is not the committed one" "exit $RC: $(tail -n 2 "$W/subst.out")"; fi
fresh ignore; printf 'gird-fleet.sh export-ignore\n' >> "$W/ignore/.gitattributes"; recommit ignore "A file git archive leaves out"; rel ignore 1.3.0 1.3.0
if refused 'is not the commit, at: gird-fleet.sh' ignore; then ok "refuses when git archive leaves a committed file out"; else bad "refuses when git archive leaves a committed file out" "exit $RC: $(tail -n 2 "$W/ignore.out")"; fi
needgen; fresh replace; E=$(printf 'echo replaced\n' | git -C "$W/replace" hash-object -w --stdin); git -C "$W/replace" replace "$(git -C "$W/replace" rev-parse HEAD:gird-check.sh)" "$E"
rel replace 1.3.0 1.3.0
C=$(git -C "$W/replace.git" cat-file blob HEAD:gird-check.sh | sha)
if [ "$RC" -eq 0 ] && grep -qx "$C  gird-check.sh" "$GH_LOG.sums"; then ok "a replace ref does not change what is released"; else bad "a replace ref does not change what is released" "exit $RC: $(tail -n 2 "$W/replace.out")"; fi
endgen

fresh order; printf '#!/usr/bin/env bash\n: > "%s/ran-gen"\n' "$W" > "$W/order/tools/gen.sh"; nobuilt order; recommit order "A gen.sh that leaves a mark"
rel order 1.3 1.3.0
if refused 'confirmation did not match' order && [ ! -e "$W/ran-gen" ]; then ok "runs nothing from the checkout before the review is confirmed"; else bad "runs nothing from the checkout before the review is confirmed" "exit $RC, gen.sh ran: $([ -e "$W/ran-gen" ] && echo yes || echo no)"; fi
if grep -q '^+: > ".*/ran-gen"$' "$W/order.out"; then ok "shows a change to tools/ in full before the review"; else bad "shows a change to tools/ in full before the review"; fi
rel order 1.3.0 --dry-run 1.3.0
if [ "$RC" -eq 0 ] && [ -e "$W/ran-gen" ]; then ok "runs gen.sh --check once the review is confirmed"; else bad "runs gen.sh --check once the review is confirmed" "exit $RC"; fi

fresh gen; printf '#!/usr/bin/env bash\necho "gird-check.sh is out of date"; exit 1\n' > "$W/gen/tools/gen.sh"; recommit gen "A gen.sh that fails"; rel gen 1.3.0 1.3.0
if refused 'gen.sh --check failed' gen; then ok "refuses a failing gen.sh --check"; else bad "refuses a failing gen.sh --check" "exit $RC: $(tail -n 2 "$W/gen.out")"; fi

fresh empty; { printf '# Changelog\n\n## 1.3.0, 19 November 2026\n\n'; sed 1d "$SRC/CHANGELOG.md"; } > "$W/empty/CHANGELOG.md"; recommit empty "An empty 1.3.0 section"; rel empty 1.3.0 1.3.0
if refused 'section is empty' empty; then ok "refuses an empty CHANGELOG section"; else bad "refuses an empty CHANGELOG section" "exit $RC: $(tail -n 2 "$W/empty.out")"; fi

echo "release tool: the list of released files"
# --check-list needs neither OpenSSH 8.1 nor a newer git, so these run wherever the suite does.
SKIPPED=$SKIPPING; SKIPPING=""
if (cd "$SRC" && "$RB" tools/release.sh --check-list) > "$W/list.out" 2>&1; then ok "this repository's .github/release-files names every file people run"
else bad "this repository's .github/release-files names every file people run" "$(cat "$W/list.out")"; fi
fresh unlisted; printf 'Write-Output new\n' > "$W/unlisted/gird-new.ps1"; git -C "$W/unlisted" add gird-new.ps1; recommit unlisted "A new script"
(cd "$W/unlisted" && "$RB" tools/release.sh --check-list) > "$W/unlisted.list" 2>&1; LRC=$?
if [ "$LRC" -ne 0 ] && grep -q 'does not name gird-new.ps1' "$W/unlisted.list"; then ok "the list check fails for a root-level script the list does not name"; else bad "the list check fails for a root-level script the list does not name" "exit $LRC: $(cat "$W/unlisted.list")"; fi
rel unlisted 1.3.0 1.3.0
if refused 'does not name gird-new.ps1' unlisted && ! grep -q 'Type 1.3.0' "$W/unlisted.out"; then ok "refuses, before the review, a root-level script the list does not name"; else bad "refuses, before the review, a root-level script the list does not name" "exit $RC: $(tail -n 2 "$W/unlisted.out")"; fi
fresh genlist; printf '#!/usr/bin/env bash\ncd "$(dirname "$0")/.." || exit 1\n[ "${1:-}" = --check ] || printf x > blindspot-made.sh\n' > "$W/genlist/tools/gen.sh"; recommit genlist "A gen.sh that builds a file"
(cd "$W/genlist" && "$RB" tools/release.sh --check-list) > "$W/genlist.list" 2>&1; LRC=$?
if [ "$LRC" -ne 0 ] && grep -q 'does not name blindspot-made.sh' "$W/genlist.list"; then ok "the list check fails for a file gen.sh builds that the list does not name"; else bad "the list check fails for a file gen.sh builds that the list does not name" "exit $LRC: $(cat "$W/genlist.list")"; fi
# lcheck NAME: runs --check-list in $W/NAME, into $W/NAME.list and LRC.
lcheck() { (cd "$W/$1" && "$RB" tools/release.sh --check-list) > "$W/$1.list" 2>&1; LRC=$?; }
fresh ignored; printf '\n# The fleet files, built by bash tools/gen.sh\n/blindspot-a.sh\nblindspot-b.ps1\n\nblindspot-c.sh\n' >> "$W/ignored/.gitignore"; lcheck ignored
if [ "$LRC" -ne 0 ] && grep -q 'does not name blindspot-a.sh blindspot-b.ps1 which' "$W/ignored.list"; then ok "the list check reads every name under a built-by-gen.sh comment in .gitignore"; else bad "the list check reads every name under a built-by-gen.sh comment in .gitignore" "exit $LRC: $(cat "$W/ignored.list")"; fi
fresh redir; printf '%s\n' '#!/usr/bin/env bash' 'ROOT=$(pwd); WORK=$(mktemp -d)' 'echo > "blindspot-q.ps1"' 'echo > "$ROOT/blindspot-r.cmd"' 'echo > "${ROOT}/blindspot-s.psm1"' 'echo > "$WORK/scratch.sh"' > "$W/redir/tools/gen.sh"; recommit redir "A gen.sh that writes by quoted paths"; lcheck redir
if [ "$LRC" -ne 0 ] && grep -q 'does not name blindspot-q.ps1 blindspot-r.cmd blindspot-s.psm1 which' "$W/redir.list"; then ok "the list check reads quoted and folder-prefixed files gen.sh writes, but not its mktemp folder"; else bad "the list check reads quoted and folder-prefixed files gen.sh writes, but not its mktemp folder" "exit $LRC: $(cat "$W/redir.list")"; fi
fresh kinds; for f in a.bat b.cmd c.command d.psm1; do : > "$W/kinds/$f"; done; git -C "$W/kinds" add -A; recommit kinds "Scripts of every kind"; lcheck kinds
if [ "$LRC" -ne 0 ] && grep -q 'does not name a.bat b.cmd c.command d.psm1 which' "$W/kinds.list"; then ok "the list check covers root-level .bat, .cmd, .command and .psm1 files"; else bad "the list check covers root-level .bat, .cmd, .command and .psm1 files" "exit $LRC: $(cat "$W/kinds.list")"; fi
fresh noignore; rm "$W/noignore/.gitignore"; lcheck noignore
if [ "$LRC" -ne 0 ] && grep -q 'no .gitignore' "$W/noignore.list"; then ok "the list check fails with no .gitignore"; else bad "the list check fails with no .gitignore" "exit $LRC: $(cat "$W/noignore.list")"; fi
fresh nogen; rm "$W/nogen/tools/gen.sh"; lcheck nogen
if [ "$LRC" -ne 0 ] && grep -q 'no tools/gen.sh' "$W/nogen.list"; then ok "the list check fails with no tools/gen.sh"; else bad "the list check fails with no tools/gen.sh" "exit $LRC: $(cat "$W/nogen.list")"; fi
SKIPPING=$SKIPPED

# built NAME GEN: a repository whose gen.sh is GEN and whose list adds blindspot-built.sh as built.
built() {
  fresh "$1"; printf '%s\n' "$2" > "$W/$1/tools/gen.sh"; nobuilt "$1"; printf 'blindspot-built.sh built\n' >> "$W/$1/.github/release-files"
  recommit "$1" "A built file"
}
built nobuild '#!/usr/bin/env bash
exit 0'
rel nobuild 1.3.0 1.3.0
if refused 'blindspot-built.sh, listed in .github/release-files, is missing or empty' nobuild; then ok "refuses a built file gen.sh did not make"; else bad "refuses a built file gen.sh did not make" "exit $RC: $(tail -n 2 "$W/nobuild.out")"; fi
built genfail '#!/usr/bin/env bash
[ "${1:-}" = --check ] && exit 0
echo "could not build"; exit 1'
rel genfail 1.3.0 1.3.0
if refused 'bash tools/gen.sh failed (exit 1)' genfail; then ok "refuses when gen.sh fails to build"; else bad "refuses when gen.sh fails to build" "exit $RC: $(tail -n 2 "$W/genfail.out")"; fi
built nopwsh '#!/usr/bin/env bash
echo "blindspot-fleet.ps1 not built: it needs PowerShell" >&2; exit 3'
rel nopwsh 1.3.0 1.3.0
if refused 'Install PowerShell (pwsh)' nopwsh; then ok "says to install PowerShell when gen.sh exits 3"; else bad "says to install PowerShell when gen.sh exits 3" "exit $RC: $(tail -n 2 "$W/nopwsh.out")"; fi
built stray '#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
[ "${1:-}" = --check ] && exit 0
printf "built\n" > blindspot-built.sh; : > stray.txt'
rel stray 1.3.0 1.3.0
if refused 'gen.sh made stray.txt' stray; then ok "refuses a file gen.sh made that the list does not name"; else bad "refuses a file gen.sh made that the list does not name" "exit $RC: $(tail -n 2 "$W/stray.out")"; fi

built both '#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
[ "${1:-}" = --check ] && exit 0
printf "built\n" > blindspot-built.sh'
# The working tree's list drops gird-fleet.sh and git is told not to look: the release must not notice.
git -C "$W/both" update-index --skip-worktree .github/release-files
grep -v '^gird-fleet.sh ' "$W/both/.github/release-files" > "$W/both.list" && cat "$W/both.list" > "$W/both/.github/release-files"
rel both 1.3.0 1.3.0
H=$(printf 'built\n' | sha)
C=$(git -C "$W/both" cat-file blob HEAD:gird-check.sh | sha)
if [ "$RC" -eq 0 ] && grep -qx "$H  blindspot-built.sh" "$GH_LOG.sums" && grep -qx "$C  gird-check.sh" "$GH_LOG.sums"; then ok "a committed file and a built file both land in SHA256SUMS"; else bad "a committed file and a built file both land in SHA256SUMS" "exit $RC: $(tail -n 2 "$W/both.out")"; fi
# gh's arguments after "release create v1.3.0", up to the first option, as file names.
ghfiles() { awk 'NR > 3 && /^-/ { exit } NR > 3 { sub(/.*\//, ""); print }' "$GH_LOG" 2>/dev/null; }
if [ "$(ghfiles)" = "$(git -C "$W/both" show HEAD:.github/release-files | awk '!/^[[:space:]]*#/ && NF == 2 { print $1 }' | LC_ALL=C sort; printf 'SHA256SUMS\nSHA256SUMS.sig')" ] && [ "$(head -n 3 "$GH_LOG" | tr '\n' ' ')" = "release create v1.3.0 " ]
then ok "and both go to the GitHub release, in name order"; else bad "and both go to the GitHub release, in name order" "gh got: $(tr '\n' ' ' < "$GH_LOG" 2>/dev/null)"; fi
if grep -q '  gird-fleet.sh$' "$GH_LOG.sums" 2>/dev/null; then ok "the list comes from the reviewed commit, not the working tree"; else bad "the list comes from the reviewed commit, not the working tree"; fi

echo "release tool: a dry run"
needgen
fresh dry; rel dry 1.3.0 --dry-run 1.3.0
D=$(sed -n 's/^Files: //p' "$W/dry.out")
if [ "$RC" -eq 0 ] && [ -n "$D" ] && [ -f "$D/SHA256SUMS" ]; then ok "a dry run passes and keeps its files" "$D"; else bad "a dry run passes and keeps its files" "exit $RC: $(tail -n 3 "$W/dry.out")"; D=$W/none; fi
# A committed file's SHA-256 comes from the commit; a built one's from the copy gen.sh built it in.
want() {
  printf 'version v1.3.0\n'
  for f in $(released dry); do
    if git -C "$W/dry" cat-file -e "HEAD:$f" 2>/dev/null; then printf '%s  %s\n' "$(git -C "$W/dry" cat-file blob "HEAD:$f" | sha)" "$f"
    else printf '%s  %s\n' "$(sha < "$D/src/$f")" "$f"; fi
  done
}
if [ -f "$D/SHA256SUMS" ] && want | cmp -s - "$D/SHA256SUMS"; then ok "SHA256SUMS is the version line, then each committed file's SHA-256, sorted"; else bad "SHA256SUMS is the version line, then each committed file's SHA-256, sorted" "$(cat "$D/SHA256SUMS" 2>/dev/null)"; fi
if [ -f "$D/SHA256SUMS" ] && ! LC_ALL=C grep -q "$(printf '\r')" "$D/SHA256SUMS" && [ "$(tail -c 1 "$D/SHA256SUMS" | od -An -c | tr -d ' ')" = '\n' ] && [ "$(sed 1d "$D/SHA256SUMS" | awk '{ print $2 }')" = "$(sed 1d "$D/SHA256SUMS" | awk '{ print $2 }' | LC_ALL=C sort)" ]
then ok "SHA256SUMS has LF line ends, a final newline and names in byte order"; else bad "SHA256SUMS has LF line ends, a final newline and names in byte order"; fi
if [ -f "$D/SHA256SUMS.sig" ] && ssh-keygen -Y verify -f "$W/dry/.github/allowed_signers" -I release@blindspot -n blindspot-release -s "$D/SHA256SUMS.sig" < "$D/SHA256SUMS" > /dev/null 2>&1
then ok "its signature verifies as release@blindspot in the blindspot-release namespace"; else bad "its signature verifies as release@blindspot in the blindspot-release namespace"; fi
if [ -f "$D/SHA256SUMS.sig" ] && ! ssh-keygen -Y verify -f "$W/dry/.github/allowed_signers" -I release@blindspot -n git -s "$D/SHA256SUMS.sig" < "$D/SHA256SUMS" > /dev/null 2>&1
then ok "and not in another namespace"; else bad "and not in another namespace"; fi
if [ -z "$(git -C "$W/dry" tag -l v1.3.0)" ] && [ -z "$(git -C "$W/dry.git" tag -l v1.3.0)" ] && [ ! -s "$GH_LOG" ]; then ok "a dry run makes no tag and no release"; else bad "a dry run makes no tag and no release"; fi
rm -rf "$D"

echo "release tool: a release"
fresh full; rel full 1.3.0 1.3.0
if [ "$RC" -eq 0 ] && grep -q 'Released v1.3.0' "$W/full.out"; then ok "a release runs to the end"; else bad "a release runs to the end" "exit $RC: $(tail -n 3 "$W/full.out")"; fi
if git -C "$W/full.git" -c gpg.ssh.allowedSignersFile="$W/full/.github/allowed_signers" tag -v v1.3.0 > "$W/tagv.txt" 2>&1 && [ "$(git -C "$W/full.git" rev-parse 'v1.3.0^{commit}')" = "$(git -C "$W/full" rev-parse HEAD)" ]
then ok "it pushes a signed tag on HEAD that git tag -v accepts"; else bad "it pushes a signed tag on HEAD that git tag -v accepts" "$(head -n 3 "$W/tagv.txt")"; fi
G=$(tr '\n' ' ' < "$GH_LOG" 2>/dev/null)
if [ "$(ghfiles)" = "$(released full; printf 'SHA256SUMS\nSHA256SUMS.sig')" ] && case "$G" in "release create v1.3.0 "*"SHA256SUMS.sig -R test-owner/full "*--verify-tag*) true ;; *) false ;; esac
then ok "it creates the GitHub release with every listed file, SHA256SUMS and its signature"; else bad "it creates the GitHub release with every listed file, SHA256SUMS and its signature" "gh got: $G"; fi
if [ -f "$GH_LOG.notes" ] && [ "$(cat "$GH_LOG.notes")" = "$(printf -- '- A change for the tests.\n- And a second one.')" ]; then ok "its notes are the version's CHANGELOG section"; else bad "its notes are the version's CHANGELOG section" "$(head -n 3 "$GH_LOG.notes" 2>/dev/null)"; fi

echo "release tool: when publishing fails"
# The origin refuses every push, so the push fails after the tag is made.
fresh push; mkdir "$W/push-hooks"; printf '#!/bin/sh\nexit 1\n' > "$W/push-hooks/pre-receive"; chmod +x "$W/push-hooks/pre-receive"
git -C "$W/push.git" config core.hooksPath "$W/push-hooks"; rel push 1.3.0 1.3.0
if refused 'push of v1.3.0 failed' push && [ -z "$(git -C "$W/push.git" tag -l v1.3.0)" ]; then ok "a failed tag push deletes the tag and publishes nothing"; else bad "a failed tag push deletes the tag and publishes nothing" "exit $RC: $(tail -n 2 "$W/push.out")"; fi
fresh ghfail; GH_FAIL=1 rel ghfail 1.3.0 1.3.0
D=$(sed -n 's/.*Its files are in \([^;]*\);.*/\1/p' "$W/ghfail.out")
if [ "$RC" -ne 0 ] && grep -q 'create it with: gh release create v1.3.0 .*SHA256SUMS.sig -R test-owner/ghfail .*--verify-tag' "$W/ghfail.out" && [ -f "$D/SHA256SUMS.sig" ]; then ok "a failed GitHub release keeps its files and says how to create it"; else bad "a failed GitHub release keeps its files and says how to create it" "exit $RC: $(tail -n 2 "$W/ghfail.out")"; fi
[ -z "$D" ] || rm -rf "$D"
fresh ghpart; GH_FAIL=1 GH_EXISTS=1 rel ghpart 1.3.0 1.3.0
if [ "$RC" -ne 0 ] && grep -q 'finish it with: gh release upload v1.3.0 .*SHA256SUMS.sig --clobber -R test-owner/ghpart' "$W/ghpart.out"; then ok "a release left part-made says to upload its files with --clobber"; else bad "a release left part-made says to upload its files with --clobber" "exit $RC: $(tail -n 2 "$W/ghpart.out")"; fi

finish
