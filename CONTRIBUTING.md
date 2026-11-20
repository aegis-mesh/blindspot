# Contributing to Blindspot

Thanks for helping. New agents, key formats and incident checks are the most useful contributions, and new leaks happen every week.

## Report a bug or a missed key

1. Search the [open issues](https://github.com/aegis-mesh/blindspot/issues) first. If yours is there, add what you see to it.
2. Open a [new issue](https://github.com/aegis-mesh/blindspot/issues/new/choose) and pick the template that fits: **Bug**, **Missed or wrong finding**, **New agent** or **New check**.
3. Say which version you ran (it's in the report's header) and where: macOS, Linux, WSL or Windows, and your terminal app.
4. Never paste a key, not even a revoked one. Describe its shape instead: the provider, the first few characters of its prefix, and its length. Blindspot never prints keys, but its paths can name your projects or your username, so read the output before you paste it.

Security problems go privately through [SECURITY.md](SECURITY.md), never into a public issue. Questions and ideas go to [Discussions](https://github.com/aegis-mesh/blindspot/discussions).

## Open a pull request

1. For anything bigger than a small fix, open or find an issue first, so we can agree on the approach before you write code.
2. Fork the repository and create a branch from `main`.
3. Make one change per pull request, and keep to the rules below.
4. Add a test for what you changed, and run everything in [Test](#test).
5. Sign off every commit with `git commit -s` (see [Sign your commits](#sign-your-commits)).
6. Open the pull request against `main`, fill in the template's checklist, and link the issue (`Fixes #123`).
7. CI runs shellcheck and the tests on macOS and Linux. It has to pass.
8. A code owner who didn't write the change reviews it. Only maintainers can merge, and nothing reaches `main` without that approval and a green CI.

## The rules the script keeps

Every change has to keep these true. Reviews check them first.

- **Read-only.** It never writes, moves or deletes a file, except the report someone asks it to save.
- **Never prints a key.** Match keys inside `grep` or `awk` pipes. Never put a key value in a variable or the output.
- **Runs nothing it finds.** No Python, no agents, no MCP servers, no git inside other people's repos, no sudo. The root side of fleet mode lives in `gird-fleet.sh` alone (`docs/designs/fleet-mode.md`).
- **No new dependencies.** Only tools that ship with macOS and common Linux distributions. It must run on bash 3.2, the version macOS ships.
- **Windows too.** `gird-check.ps1` keeps the same rules and must run on Windows PowerShell 5.1, which ships with Windows, and on PowerShell 7.
- **Shares nothing new by accident.** Anything added to the shared counts must be a number or come from a fixed list, and must be listed in [TELEMETRY.md](TELEMETRY.md).

## Lists live in `data/`

The key types, the agents' session folders, the incidents, the bad npm and Python packages, the files malware leaves on disk, the files worms plant in a project, the hosted platforms that leaked stored secrets, the agent settings that run commands without asking, the commands that run commands on other machines with the agent files whose saved rules can allow them, the agent versions with a published security fix, the editor extensions that shipped malware, the SSH keys malware adds to `~/.ssh/authorized_keys`, the GitHub Actions that were compromised, the variables that move an agent's or a tool's folders, the tools' own scripts a profile sources, the coding agents, the MCP apps, well-known MCP servers and MCP configs, the kinds of file the report counts, the terminals `TERM_PROGRAM` names and the lines an account run prints in fleet mode and the OWASP Agentic Top 10 risk of each kind of finding (`data/owasp.tsv`) each live in one file under `data/`, one line per entry, described in the file's header. `bash tools/gen.sh` writes them into both scripts and into the lists in [docs/checks.md](docs/checks.md); edit the data file, never the generated block between `# >>> name` and `# <<< name` (or `<!-- >>> checks -->` and `<!-- <<< checks -->` in the page). `tests/run.sh` fails if a script or the page and its data file disagree.

## Add an agent

1. Add a line to `data/agents.tsv`: name, commands, install paths and folders that change when it's used (for `gird-check.sh` and for `gird-check.ps1`), and an id.
2. If it has an MCP config, add a line to `data/mcp-files.tsv` (and its id to `data/mcp-clients.tsv` when it is a new MCP app). If it keeps keys in a config, add it to the candidate list in section 3.
3. If it keeps session transcripts, add a line to `data/sessions.tsv`. Run `bash tools/gen.sh`.
4. Add a fake install to `tests/make-fixture.sh`, an assertion to `tests/run.sh` and its twin to `tests/run-ps.sh` (see [Test](#test)).

## Add a key format

1. Add a line to `data/keys.tsv`, in the last pass (after its last `#pass` line): an id (lowercase letters, digits and `-`), the provider's name, the fixed text every key holds, the pattern, `start` or `in`, and the longest match to keep (`-` for 300). Anchor the pattern on fixed text so it doesn't flag random strings, and bound it at both ends. A key whose fixed part is in its middle, as Microsoft's are, is `in`, each start written `TEXT@N` with where that text is in the key, and `in` lines come last. A new key type that could hide an older one, glued to it, goes in a new pass. The file's header says what each column allows, and `tools/gen.sh` refuses the rest: a count above 255, a POSIX class, a start that is not fixed text. Run `bash tools/gen.sh`.
2. A vendor's published example or emulator value that matches the pattern goes in `data/public-values.tsv`, with where the vendor publishes it.
3. A new id also has to be added to `PROVIDERS` in gird.ai's Worker, or the shared counts drop it, and to the list in `TELEMETRY.md`. `gird-check.sh` and `gird-fleet.sh` ship together: an account run may name only the key types the `gird-fleet.sh` beside it knows.
4. Add the type's keys, near misses and published values to `tests/make-keys.py`, which builds them at runtime from pieces. Never commit a full key-shaped string.

## Add an incident check

Open an issue with the **New check** template first, with links to the vendor advisory. Checks look for files, versions or markers on disk. They never run the software they check.

A new incident of a kind Blindspot already checks is data lines only: add its line to `data/incidents.tsv` (a sourced name, impact and link, and its level: `act` when a hit means a compromised machine, `update` when the version needs updating but the machine itself is not compromised, `leak` for a hosted platform's leak (and only for one), which never means a compromised machine, and optionally a fix of its own, shown in What to do when one of its npm or Python packages or editor extensions is found; `gen.sh` refuses it on an incident that has none; an act-level fix that starts with "First" is for what the incident leaves behind that must go before any key is rotated, and comes ahead of every fix that says to rotate (`gen.sh` refuses one that says to rotate or revoke itself); an update-level incident with a fix of its own can add, last, the summary row 05 shows for it, 49 characters at most), then the lines below, and run `bash tools/gen.sh`. No code changes, and `tests/made-up.sh` proves it for every kind below. Add a fixture and an assertion to the tests all the same. The result page names LiteLLM and gh-token-monitor by name; any other Python incident reaches it as `py=1` and is shown as Python package malware.

- **A bad npm package**: one line in `data/bad-npm.tsv`: the name, the exact version (or `*` when every version is malware) and the incident's id. Take versions from a GitHub malware advisory, and sweep the whole campaign (every advisory published with it) rather than copying the first few names.
- **A bad Python package**: one line in `data/bad-pypi.tsv`: the name as its `.dist-info` folder spells it, the exact version (`*` is not supported), the incident's id, whose level must be `act`, and the OS its malware could run on (`all`, `mac`, `linux` or `win`, from the advisory, or `none` when the package's own maintainer says its malware could not run). It is looked for in every Python environment and in uv's cache, and section 5 gets a row named as `data/incidents.tsv` names the incident. On an OS where the malware could not run, and on every OS for `none`, the version is shown as one to update, not a compromised machine.
- **Files malware leaves on disk**: one line each in `data/indicators.tsv`. `startup` is a file that starts malware at login, or the malware such a file starts (or a copy of it that hooks the malware adds to an agent run at each session), shown with its note, and a Python incident's in that incident's row (it must be in the home folder, with `owner` `no`); `site` a file in site-packages and `temp` an entry in the temp folder, both counted as the Python incident's hit. A `temp` line's note is the incident's own advice for those files, from its advisory, shown under the row when they are found; one incident's temp lines carry the same note. A temp file that two incidents' lines name is listed once, with the incident whose package was found. `owner` `yes` counts a file only when this person owns it, for the shared `/tmp`. `wiper` is a new file of gh-token-monitor (gen.sh refuses a path that does not name it): its stop-it-first advice, commands and result-page step are written for that wiper, so a different wiper is code.
- **A file planted in a project**: one line in `data/planted.tsv`: `.claude` or `.vscode`, the file name, the incident, the note shown, `yes` when only the worm uses that name or `no` when projects use it too (such as `setup.mjs`), and for a `no` file the SHA-256 values its sources publish, or `-`. A `yes` file counts wherever it is found; a `no` file counts only in a project that holds a `yes` file, or when its SHA-256 is listed, and is otherwise shown in section 2 as a file to read. A hook or task that runs it, as the script an interpreter runs or the command itself, is flagged too.
- **An editor extension that shipped malware**: one line in `data/bad-extensions.tsv`: the id as its folder spells it (`publisher.name`), the exact version (or `*`), the incident's id, whose level must be `act`, the registry: `openvsx` when the bad build was only ever published to Open VSX (it is then looked for in the folders of Cursor, Windsurf, Devin Desktop, VSCodium, Kiro, Antigravity and Positron, not VS Code's own, where the same id is the Marketplace's own extension), or `any`, which an id on Microsoft's list of extensions removed from the Marketplace always is, the OS its malware could run on (`all`, `mac`, `linux` or `win`, or two of them such as `mac,win`, from its source), and, when a clean build has the same id and version as the bad one, a marker: strings its source shows only the bad build's `extension.js` holds, separated by `;`. A folder of that version then counts only when its `extension.js` holds one of them. On an OS where it could not run, the extension is shown as a malicious extension to remove, not a compromised machine. A startup file of such an incident (`data/indicators.tsv`) is shown with the extensions, never as npm malware: next to one of its extensions, or on its own when its line ends in `alone`, for a name only that malware uses. An SSH key it adds to `~/.ssh/authorized_keys` is one line in `data/ssh-keys.tsv`: the incident, the key's type, the key's base64 text and the note shown; a line of `authorized_keys` counts when the type and then the key are two of its fields, so its comment never decides.
- **An agent setting that runs commands without asking**: one line in `data/auto-approve.tsv`: the agent, the OS, the settings file (or `{PROJECT}/folder/file` for that file in every project; one folder may be `*`, for that file in every folder there, as VS Code's profiles), the setting as shown, and the patterns that must all match a line (a `.toml` file's line can add `!key`, a key the file must not set). Take the setting's name and value from the agent's own documentation.
- **A command that runs commands on another machine**: one `cmd` line in `data/remote-commands.tsv`: the words it starts with, `exact` or `any` (a PowerShell cmdlet, read without case), the label the report shows and the vendor's page that says it runs commands on another machine. An agent file whose saved rules can allow one is a `file` line there, in a format the scripts already read; a new format is code in both scripts.
- **An agent version with a published security fix**: one line per place the version is read in `data/outdated.tsv`: how it is read (an Info.plist, a version folder, an npm package or an MCP config's `name@version`), the affected range, what the hole allows and the advisory. A tool can have a line per advisory, and needs one for its newest fix: its row says to update to the highest fixed version among the lines the installed version falls under, or to a later fix when another line of the tool covers that one, and shows each of their holes. Read the advisories the vendor's repository publishes as well as GitHub's database and OSV: a repository can publish one the other two don't list.
- **A GitHub Action that was compromised**: one line in `data/actions.tsv`, with no line in `data/incidents.tsv`: the action as `owner/repo`, the tags that ran the malware as shell patterns (or `*`), the malicious commits the source lists, the commits of releases the source names safe (a pin to one is never flagged) or `-`, `safe` when the source lists the malicious commits or says a pin was safe (a pin to any other commit is not flagged) or `unsafe` when it says a pin could run the malware too, the window, the source, and the fix shown under each use found. Take the tags and commits from the advisory or the research post, and list every tag it names. Section 5 lists each workflow in `.github/workflows` that uses one, as a project to check: whether it was hit depends on when its workflows ran.
- **A hosted platform that leaked stored secrets**: one line in `data/platforms.tsv`: the incident id, whose level must be `leak`, the row's name, its commands and paths, its row word and advice, and its summary row. The shared fix names it from `data/incidents.tsv`. A leak has no packages, extensions or files to look for: `gen.sh` refuses them.

A new kind of check (a new file format, a running process, a registry value) is code: add it to section 5 of both scripts, a fixture to the tests, and a line to "What to do". A new kind of finding also needs its line in `data/owasp.tsv`, with its OWASP risk or the reason it has none: a new field the account run sends to `gird-fleet.sh` (`FL_KEYS`) is refused by `gen.sh` until it has one, and a risk needs the field's arm in `owasp_set` in `gird-check.sh` and its value in `Owasp-Set` in `gird-check.ps1`. The tags in README.md and docs/fleet.md are written by hand; a test checks they name every risk and label in the file.

## Review checklist

A reviewer starts from the person who acts on the report, not from the diff:

- **Advice that makes things worse.** Follow every finding to every place it shows: its section, the summary row, the summary's fix list, the full fix list and the result page the link opens. Nothing may tell someone to revoke or rotate a token while `gh-token-monitor` is present.
- **False comfort.** A green line or "no keys" over something that wasn't fully read is a bug. Partial, skipped and unreadable must say so.
- **False alarms.** A red "treat this machine as compromised" over something harmless costs trust. Test the near misses: a version one digit off, a name that contains another, a rule or guard that names a malware file without running it.
- **Real inputs.** Try the shapes people actually have: pretty-printed JSON, committed `settings.local.json`, worktrees, symlinks, every lockfile format, paths with spaces or `|`, Windows paths.
- **Sources.** Every incident, version and file path traces to a primary source (the vendor's advisory, a GitHub malware advisory, or a named security research post). A comment or README line the code doesn't support is a bug.
- **What a list leaves out.** For any list taken from advisories, check what the same campaign published that the list misses, and that the report's wording doesn't claim more than the list covers.
- **Both scripts.** Every change lands in `gird-check.sh` and `gird-check.ps1`, each with a test that fails without it.

## Security review

Blindspot runs on other people's computers, and in fleet mode as root on every Mac a company manages. A merge to `main` reaches everyone who downloads from gird.ai (see [Releases](#releases)). So every pull request also gets this review, from a maintainer who didn't write it, and doesn't merge until each point holds:

- **Read every line, tests and tools included.** Maintainers run the suites on their own machines, so code in `tests/` and `tools/` runs there too. For a pull request from someone who isn't a maintainer, read the whole diff before running anything, and run it first in a container or a throwaway virtual machine.
- **Nothing hidden.** No encoded blobs, minified code, binaries or downloaded code. Account for every non-ASCII or control character the change adds, in file contents and file names: invisible and right-to-left characters can make code read differently from how it runs. `gird-check.ps1` stays ASCII, so any such character there is a no. These list them:

  ```sh
  git diff --text origin/main... | LC_ALL=C tr '\000' '\001' | LC_ALL=C grep -an '^+.*[^[:print:][:blank:]]'
  git -c core.quotePath=false diff --name-only -z origin/main... | LC_ALL=C tr '\n\000' '\001\n' | LC_ALL=C grep -n '[^ -~]'
  ```

  `--text` shows files git or `.gitattributes` would call binary (an image under `docs/` included), `tr` (in the C locale, so a byte that is not UTF-8 never stops it) turns a NUL into a byte grep shows and, in the names, a line feed inside a name into one too, and `core.quotePath=false` keeps git from quoting a name into plain ASCII.

- **Runs nothing it reads** (the rule "Runs nothing it finds" above). Look for `eval`, `Invoke-Expression`, `source`, and any command built from a found name or file content. A found name reaches `sh -c` only as an argument, never inside the command text.
- **Lists match the scripts.** A change to `data/` passes `bash tools/gen.sh --check`, so the scripts carry exactly the lines you reviewed.
- **Nothing new on the network** (with "Shares nothing new by accident" above). No new host and no new call. A reply from gird.ai is data: limited in size and time, never run, and never used in a path or a command.
- **No trap for root.** In `gird-fleet.sh`, look for anything one account can plant to change what root reads, follows or reports for another: a link, a file swapped between check and use, a name with a newline.
- **A list shrinks only with a source.** Removing or narrowing a line in `data/` hides a known threat from everyone who runs the check. Link the primary source that shows the entry was wrong.
- **CI stays powerless.** A change under `.github/` keeps `permissions: contents: read`, pins every action to a full commit SHA, uses no secrets, and publishes nothing. No workflow runs on `pull_request_target` except the review guard below, which never checks out or runs the pull request's code; its only write access is to pull requests, used to remove the `security-reviewed` label after a push.
- **Review what merges.** A new push removes an approval. Review the whole diff again, not only the new commits.
- **Nothing private.** This repository is public. Code, comments, commits and pull request text name no private repository, server, token or customer.

The review guard applies the mechanical part of this review: the `review-guard` check runs on every pull request, and `tools/review-guard.sh` reads the diff, runs none of it, and lists what it finds. It is not a required check yet. After the 1.3.0 release merges, a maintainer makes `review-guard` a required check on `main` and creates the `security-reviewed` label; until both are done, a red guard is a signal to the reviewer, not a block on merging. It flags an added invisible, direction-changing, control or NUL character (and any non-ASCII in `gird-check.ps1`), a file name that is not printable ASCII, a binary file other than an image under `docs/` whose bytes are that kind of image, a link, a submodule or a changed file mode, an added line that looks like it runs text as code or calls the network (in a doc, a network command in a fenced code block), running a file named as data or an image, a removed line in `data/`, and any change to `.github/`, `.gitattributes`, the guard, or a file an AI coding agent, editor or shell opening this repository reads or runs (`.claude/`, `.vscode/`, `.mcp.json`, `AGENTS.md`, `CLAUDE.md`, `.envrc` and the others the script's header lists; an agent file it does not list gets no such finding). The script's header lists the exact rules. They match text, so a line written to dodge them (`e\val`, `c''url`, a command built from pieces) gets through: the guard is a tripwire, a red guard is never proof of harm and a green one never proof of safety, and every point above still applies. A finding is not a verdict. A code owner reads each one and, if the change is sound, adds the `security-reviewed` label; only that labeling clears the check, and only for the pull request's head commit at the moment of labeling. A push between your review and the label would be cleared unread, so after adding it, open the run the label started and confirm its line "This clears commit X only" names the commit you reviewed. If it names another, remove the label, review what changed, and add it again. An owner who wrote the pull request can clear the check too, since branch protection still needs the other owner's approval. Any later event on the pull request (a push, an edit, another label) runs the check again and blocks until a code owner adds the label again (removing it first if it is still on), so add it last. The guard and its workflow come from the base branch, so a pull request cannot change the check that judges it. To run it yourself the same way, without running the pull request's own copy of the guard or reading its `.gitattributes`, fetch its commits and run `main`'s guard from a checkout of `main`:

```sh
git fetch origin main "+pull/N/head:refs/remotes/pr/N" && git checkout --detach origin/main && bash tools/review-guard.sh origin/main refs/remotes/pr/N
```

## Test

```sh
bash tests/run.sh
bash tests/interactive.sh
shellcheck -s bash -S warning gird-check.sh gird-fleet.sh tools/review-guard.sh tools/review-guard-decide.sh tools/release.sh tests/*.sh
PWSH=/path/to/pwsh bash tests/run-ps.sh
PWSH=/path/to/pwsh bash tests/parity-run.sh
```

- `tests/run.sh` builds a fake home folder and checks what the script finds and never prints.
- `tests/interactive.sh`, on macOS, drives the game and the menu with expect.
- `tests/run-ps.sh` runs the same checks for `gird-check.ps1`, under PowerShell 7.
- `tests/parity-run.sh` runs both suites, then checks every bash test has a twin.

`bash tools/ci-local.sh` runs every job in `.github/workflows/ci.yml` on your machine, one at a time. The Ubuntu jobs run in a Linux container when `docker` answers (on a Mac, for example `brew install colima docker && colima start`); without it they are listed as skipped and the run is not a full CI run (exit 2). It exits 1 when a job fails. It runs your working tree, uncommitted changes included, and keeps PowerShell's download in `~/.cache/blindspot-ci`.

Run the suites above before you open a pull request, one at a time, never two at once. They run the scripts with `--offline` or against a local stand-in for gird.ai, so a test run never reaches the live counts. `tests/run.sh` and `tests/interactive.sh` each run on the bash that ships with macOS (3.2) and on a newer bash from your PATH if you have one. Maintainers run them again before merging.

Every test in `tests/run.sh` needs a twin in `tests/run-ps.sh`: a test with the same name that checks the same thing for `gird-check.ps1`, on the Windows-shaped home. A test that can't or need not run for PowerShell gets a line in `tests/bash-only.txt` instead: its name, a tab, and the reason. A reason names a feature only `gird-check.sh` has (the game and the menu, the perl session engine, Git Bash and WSL, `tools/gen.sh`), or something PowerShell can't fake on the test machine, such as the OS. "Not written yet" is not a reason. Each test records its name as it runs, skipped ones too (`tests/lib.sh`: report through `ok`, `bad` and `skip` only, and a test that can't run on a machine calls `skip`). Every check reports through `ok` or `bad` on both outcomes: one that reports only when it fails (`[ ... ] && bad "x"`) or ends with `exit` never reaches the list on a passing run. The text backstop catches the first shape, not the second. A PowerShell test that skips where bash runs its twin needs a line in `tests/ps-skips.txt`, the name, a tab and why `gird-check.ps1`'s test can't run there. `tests/parity-run.sh` runs both suites and `tests/parity.sh` compares the two lists; run it before you open a pull request. CI runs it in the PowerShell job, so a bash test with neither fails CI. `tests/run.sh` also runs `tests/parity-text.sh`, a backstop that reads both suites as text; the runtime check is the rule. When a twin fails because the scripts behave differently, fix the script that is wrong, never the test.

## Sign your commits

Add a Developer Certificate of Origin sign-off to each commit with `git commit -s`. It says you wrote the change, or have the right to submit it, under the project's license. See [developercertificate.org](https://developercertificate.org).

## Releases

Today gird.ai serves `main`, so a merge reaches everyone who downloads from it, and no release has been signed yet (see the end of this section). Once gird.ai serves signed releases, people download only what a maintainer released and signed, never whatever was last merged: a merge to `main` then reaches no one until the next release, so when a merge adds an incident or a malware version, cut a release soon after. How releases are signed and checked, and why: [docs/designs/signed-releases.md](docs/designs/signed-releases.md).

Every week, and before every release, a maintainer runs `bash tools/check-advisories.sh`. It compares `data/bad-npm.tsv` with OSV.dev (which includes GitHub's malware advisories and the OpenSSF Malicious Packages list) and lists withdrawn entries, versions we flag that nothing names any more, and malicious versions we miss. Treat a MISSING line as a lead: confirm it against a primary source before adding it. It also lists each incident's source to re-read, since a vendor can change what it says an incident did.

To cut a release, merge a `## X.Y.Z, <date>` section in `CHANGELOG.md`. Then, before you run anything from the checkout, read what changed since the last release in the files that release and check, since `tools/release.sh` itself comes from the checkout it releases (replace `vA.B.C` with the last release):

```sh
git fetch origin --tags && git diff vA.B.C origin/main -- tools/ .github/ .gitattributes .gitmodules
git checkout --detach origin/main
```

Check out straight after, with no fetch in between, so what runs is what you read.

Then run:

```sh
BLINDSPOT_SIGNING_KEY=/path/to/your/release/key bash tools/release.sh --dry-run X.Y.Z
BLINDSPOT_SIGNING_KEY=/path/to/your/release/key bash tools/release.sh X.Y.Z
```

The first does every check and makes no tag or release; the second releases.

It needs git, `gh` signed in, OpenSSH 8.1 or later, and PowerShell (`pwsh` on PATH, or `PWSH=/path/to/pwsh`), which `bash tools/gen.sh` needs to build the Windows one-file fleet script. It stops, running nothing, when a folder on `PATH` is relative or inside the checkout, since a file there named like `git` would run in its place. It stops, publishing nothing, unless the checkout is clean and at `origin/main`, the version is higher than every release, `CHANGELOG.md` has its section and `.github/release-files` names every file people run. It then lists every commit and file changed since the previous release, with the changes to `tools/`, `.github/` and `.gitattributes` in full, shown as text whatever `.gitattributes` says and with every control byte made visible (`^[`), so a commit subject or a changed line cannot redraw the list: review them against the [security review](#security-review) and type the version to go on. Nothing else from the checkout runs before you do. Then, in a copy of the reviewed commit, it runs `bash tools/gen.sh --check` and `bash tools/gen.sh`, and stops if either fails or if a listed file is missing or empty. It refuses a repository whose own git config sets anything `git clone` and `git worktree add` do not write: the repository format and file system settings, `origin`'s URL and fetch line and the remote `gh` records, each branch's remote and merge, and `extensions.worktreeConfig` are allowed, and it names any other setting. If it names one your own tools wrote (an editor, or a clone made with `--no-tags` or `--filter`), release from a fresh `git clone` instead. It also refuses a non-empty `.git/info/attributes`, ignores replace refs, and stops before `gen.sh` runs if any file in its copy of the reviewed commit differs from the commit, or is missing or extra. It signs `SHA256SUMS`, with a line for every listed file, checks that signature against `.github/allowed_signers`, then pushes the signed tag and creates the GitHub release. `ssh-keygen` asks for your key's passphrase itself, once for `SHA256SUMS` and once for the tag.

A release signs exactly the files `.github/release-files` names, each `committed` or `built` by `bash tools/gen.sh`. A pull request that adds a file people run, on any system, a fleet or admin script included, adds its line in the same pull request. A file people could run but never get from a release, such as a test or a maintainer tool, gets an `unreleased` line instead (a path; `tests/*` covers the folder), with the reason in a comment above it. `bash tools/release.sh --check-list` fails when a tracked file at any depth that is executable, starts with `#!`, or has a script's extension (`.sh`, `.ps1`, `.py`, `.bat` and the others the list's header names), or a file `gen.sh` builds, is in neither kind of line, and the tests run it. `tools/strip-comments.ps1` is a maintainer tool, so it is not released.

Your release key is your own, made once with a passphrase:

```sh
ssh-keygen -t ed25519 -C blindspot-release -f ~/.ssh/blindspot-release
```

It is not your login or git key. Keep it on your own computer: never in this repository, CI, a shared drive or a chat. Add its public half as a line in `.github/allowed_signers` by pull request (the file's header shows the line), and ask for it to be added to gird.ai's copy of the keys: gird.ai serves a release signed by a new key only once both have it. If a key is lost or stolen, remove its line in both places and cut a new release with another key.

Until gird.ai serves signed releases ([docs/designs/signed-releases.md](docs/designs/signed-releases.md)), it serves `gird-check.sh`, `gird-check.ps1` and `gird-fleet.sh` from `main`, so a merge to `main` reaches everyone who downloads from gird.ai.
