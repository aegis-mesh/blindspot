# Signed releases

Status: the release side is built: `tools/release.sh`, tested by `tests/release.sh`. `.github/allowed_signers`
holds no key yet, so no release has been signed. How gird.ai serves releases is not part of this
repository.

For maintainers who cut releases, and for IT teams and others who want to check that the copy of
Blindspot they downloaded is one the maintainers published.

Blindspot reaches people as a script they download and run, and in fleet mode as root on every Mac a
company manages. So what people download is only what a maintainer deliberately released and signed,
never whatever was last merged, and never an older release passed off as the newest.

## What a release is

A release is a version a maintainer has reviewed and signed. It has three parts.

- **A signed tag**, `vX.Y.Z`, on a commit of `main`, signed with the maintainer's release key (`git tag -s`
  with `gpg.format=ssh`).
- **The files people run**, attached to the GitHub release: every file `.github/release-files` names,
  for macOS, Windows and Linux, fleet and admin files included. Each is either committed, taken as it
  is in the reviewed commit, or built, made from that commit by `bash tools/gen.sh` at release. A
  pull request that adds a file people run adds its line; `bash tools/release.sh --check-list`, run by
  the tests, fails when a root-level `.sh`, `.ps1`, `.psm1`, `.bat`, `.cmd` or `.command`, or a file
  `gen.sh` builds, is missing.
- **A signed list.** `SHA256SUMS` starts with a line `version vX.Y.Z`, then holds the SHA-256 of every
  attached file. `SHA256SUMS.sig` is its signature, made with `ssh-keygen -Y sign` in the namespace
  `blindspot-release`, so a release signature can't be passed off as any other kind. The version is
  inside what is signed, so an old release's signature can't be reused under a newer number.

The keys that may sign are listed in `.github/allowed_signers`. Every line has the same name, so a
check never needs to know which maintainer signed:

```
release@blindspot namespaces="git,blindspot-release" ssh-ed25519 AAAA... <maintainer>
```

`git` lets `git tag -v` check the tag with the same file. A change to the file needs a code owner's
review, like every file here.

## Cutting a release

`tools/release.sh <version>` does every step, and publishes nothing until all of them pass.

1. It checks that no folder on `PATH` is relative or inside the checkout, before it runs any
   program, so a file the checkout holds can't run in place of `git` or another tool. It checks that
   it runs on a clean checkout at the tip of `origin/main`, that the version is higher than every
   existing release, and that `CHANGELOG.md` has a section for it. It runs nothing from the checkout
   until step 2 is confirmed.
2. It lists every commit and changed file since the previous release, and asks the maintainer to type
   the version to confirm they reviewed that range against the
   [security review](../../CONTRIBUTING.md#security-review), with the changes to `tools/`, `.github/`
   and `.gitattributes` in full. Every listing is shown as text whatever `.gitattributes` says, with
   control bytes made visible, so neither a commit subject nor a changed line can hide or redraw
   what is shown. A release is the second look at everything merged since the last one. Then, in a copy of the reviewed commit made with `git archive` and checked file by file
   against the commit, it runs `bash tools/gen.sh --check` and `bash tools/gen.sh`. It stops if either fails, if a listed file is missing or empty,
   if a committed file changed, or if `gen.sh` made a file the list does not name as built.
3. It writes `SHA256SUMS`, one line per listed file in name order, and signs it with the key at `BLINDSPOT_SIGNING_KEY`. `ssh-keygen` asks for
   the passphrase; the script never reads, stores or passes it.
4. It checks its own signature against `.github/allowed_signers`, and stops if it fails.
5. It creates and pushes the signed tag, checking it with `git tag -v` (`gpg.ssh.allowedSignersFile`
   set to `.github/allowed_signers`), then creates the GitHub release with the files, `SHA256SUMS`,
   `SHA256SUMS.sig` and the version's notes from `CHANGELOG.md`.

The repository keeps releases immutable, so a published release's files and tag can't be changed.
A merge to `main` no longer reaches anyone, so when a merge adds an incident or a malware version,
cut a release soon after: it is one command.

## How gird.ai serves it

gird.ai/blindspot serves the newest release it has verified, with no change to the website for each
release.

- **On a schedule, not per download,** gird.ai reads the repository's releases with a read-only token,
  skipping drafts and prereleases.
- **It verifies a release before serving it.** The signature must be valid, in the
  `blindspot-release` namespace, by one of the keys gird.ai holds itself. The signature's own key is
  never trusted; it must be one of those keys. The signed `version` line must equal the release's tag,
  and every file must match `SHA256SUMS`. gird.ai serves every file the signed list names, so a new
  file needs no change to the website.
- **It never goes backwards.** It refuses a version at or below the highest it has served, starting from
  a minimum version it holds. Deleting newer releases, or republishing an old one under a new tag, can't
  bring an older build back.
- **It keeps the verified release in durable storage,** checks it again when serving, and keeps serving
  it when GitHub fails or offers nothing newer that passes. A release that fails a check is skipped and
  the failure is logged. With no verified release at all, it says the script is unavailable and points
  to GitHub.
- **gird.ai keeps its own copy of the signing keys.** Someone who takes over the GitHub repository and
  adds a key there still can't get gird.ai to serve their release. It serves that copy as
  `allowed_signers`, with `SHA256SUMS` and `SHA256SUMS.sig`, beside the scripts, and the hash shown on
  the page comes from the verified `SHA256SUMS`.

## Checking a download

Most people run the one-line hash check on gird.ai. That shows the file arrived as gird.ai served it,
and it trusts gird.ai. The signature check below is for IT teams and anyone who wants proof the
maintainers released it.

It needs OpenSSH 8.1 or later for `ssh-keygen -Y verify`: macOS, current Linux distributions, and the
OpenSSH client on Windows 10 and 11 where its version is 8.1 or later. The README and gird.ai give the
exact commands for each system, using the files of one release by version, so a new release between
two downloads can't mix versions. On macOS or Linux:

```sh
ssh-keygen -Y verify -f allowed_signers -I release@blindspot -n blindspot-release -s SHA256SUMS.sig < SHA256SUMS
grep ' gird-check.sh$' SHA256SUMS | shasum -a 256 -c
```

On Linux without `shasum`, use `sha256sum -c`. On Windows, run the first line through `cmd /c`, which
has the `<` that PowerShell lacks, and compare the hash with `Get-FileHash`.

An IT team using fleet mode verifies once, before uploading the files to its MDM
([fleet guide](../fleet.md)).

## Keys

- **Each maintainer has a release key of their own:** `ssh-keygen -t ed25519 -C blindspot-release`,
  with a passphrase, kept on their own computer. It is not their login or git key, and it never goes
  into the repository, CI, a shared drive or a chat.
- **Adding or removing a signer** changes `.github/allowed_signers` by pull request, and gird.ai's copy
  of the keys. gird.ai serves a release signed by a new key only once both have changed.
- **A lost or stolen key:** remove its line in both places and cut a new release with another key.
  gird.ai then stops serving releases only that key signed.

## Limits

- **One laptop can be the whole chain.** A maintainer's laptop holds the key file and, usually, a
  signed-in GitHub session. With it and the passphrase, someone could sign and publish a release. A
  hardware security key would close this.
- **The release tool comes from the repository.** `tools/release.sh` runs from the checkout it releases, so a maintainer reviews every change to it since the last release before running it.
- **First trust.** The keys shown on gird.ai come from gird.ai. Someone who controlled gird.ai could
  change both the files and the keys it shows. To guard against that, compare the keys with
  `.github/allowed_signers` on GitHub.
- **Older systems.** A system with OpenSSH older than 8.1 can't check the signature, only the hash.
- **Windows code signing** is separate. Locked-down PowerShell that runs only signed scripts needs an
  Authenticode signature on `gird-check.ps1`, which this does not add.
