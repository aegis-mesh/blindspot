# Signed releases

Status: designed, not built.

For maintainers who cut releases, and for anyone who wants to check that the copy of Blindspot they
downloaded is one the maintainers published.

Blindspot reaches people as a script they download and run, and in fleet mode as root on every Mac a
company manages. So what people download is only what a maintainer deliberately released and signed,
never whatever was last merged. Anyone can check the signature with a tool already on their computer.

## What a release is

A release is a version a maintainer has reviewed and signed. It has three parts.

- **A signed tag**, `vX.Y.Z`, on a commit of `main`, signed with the maintainer's release key (`git tag -s`
  with `gpg.format=ssh`).
- **The files people run**, attached to the GitHub release: `gird-check.sh`, `gird-check.ps1`,
  `gird-fleet.sh`, and any file built at release time.
- **A signed list of their hashes.** `SHA256SUMS` holds the SHA-256 of every attached file.
  `SHA256SUMS.sig` is its signature, made with `ssh-keygen -Y sign` in the namespace
  `blindspot-release`, so a release signature can't be passed off as any other kind.

The keys that may sign are listed in `.github/allowed_signers`, one line per maintainer:

```
<name>@blindspot namespaces="blindspot-release" ssh-ed25519 AAAA...
```

The file is under `.github/`, so the review guard blocks any change to it until a code owner has looked.

## Cutting a release

`tools/release.sh <version>` does every step, and publishes nothing until all of them pass.

1. It checks that it runs on a clean checkout at the tip of `origin/main`, that the version is new, and
   that `bash tools/gen.sh --check` passes.
2. It lists every commit and changed file since the previous release, and asks the maintainer to type
   the version to confirm they reviewed that range against the
   [security review](../../CONTRIBUTING.md#security-review). A release is the second look at
   everything merged since the last one.
3. It builds any file made at release time and writes `SHA256SUMS`.
4. It signs `SHA256SUMS` with the key at `BLINDSPOT_SIGNING_KEY`. `ssh-keygen` asks for the passphrase;
   the script never reads, stores or passes it.
5. It checks its own signature against `.github/allowed_signers`, and stops if it fails.
6. It creates and pushes the signed tag, then creates the GitHub release with the files, `SHA256SUMS`,
   `SHA256SUMS.sig` and the notes from `CHANGELOG.md`.

A merge to `main` no longer reaches anyone. So when a merge adds an incident or a malware version,
cut a release soon after: it is one command.

## How gird.ai serves it

gird.ai/blindspot serves the newest release whose signature it can verify, without a change to the
website for each release.

- It reads the repository's releases, newest first. It takes the first one whose `SHA256SUMS.sig` is a
  valid signature, in the `blindspot-release` namespace, by a key gird.ai holds itself, and whose every
  served file matches `SHA256SUMS`.
- gird.ai keeps its own copy of the signing keys. Someone who takes over the GitHub repository and adds
  a key there still can't get gird.ai to serve their release.
- A release that fails a check is skipped, and the failure is logged. If none passes, gird.ai keeps
  serving the last copy that did. If it never had one, it says the script is unavailable and points to
  GitHub.
- It serves `SHA256SUMS`, `SHA256SUMS.sig` and `allowed_signers` beside the scripts. The hash shown on
  the page comes from the verified `SHA256SUMS`.

## Checking a download

The signature check uses `ssh-keygen`, which ships with macOS, Linux and Windows 10 and later. The page
at gird.ai/blindspot and the README give the exact commands for each system. They do three things:

1. Download the script, `SHA256SUMS`, `SHA256SUMS.sig` and `allowed_signers`.
2. Verify the signature: `ssh-keygen -Y find-principals` names the signer from `allowed_signers`,
   then `ssh-keygen -Y verify` checks `SHA256SUMS` with that signer, in the namespace
   `blindspot-release`.
3. Check the script's SHA-256 against its line in `SHA256SUMS`.

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

- **A key file on a laptop** can sign a release if someone has the laptop and the passphrase. A
  hardware security key would close this.
- **First trust.** The keys shown on gird.ai come from gird.ai. Someone who controlled gird.ai could
  change both the files and the keys it shows. To guard against that, compare the keys with
  `.github/allowed_signers` on GitHub.
- **Windows code signing** is separate. Locked-down PowerShell that runs only signed scripts needs an
  Authenticode signature on `gird-check.ps1`, which this does not add.
