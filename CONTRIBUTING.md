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
- **Runs nothing it finds.** No Python, no agents, no MCP servers, no git inside other people's repos, no sudo.
- **No new dependencies.** Only tools that ship with macOS and common Linux distributions. It must run on bash 3.2, the version macOS ships.
- **Windows too.** `gird-check.ps1` keeps the same rules and must run on Windows PowerShell 5.1, which ships with Windows, and on PowerShell 7.
- **Shares nothing new by accident.** Anything added to the shared counts must be a number or come from a fixed list, and must be listed in [TELEMETRY.md](TELEMETRY.md).

## Lists live in `data/`

The key types, the agents' session folders, the incidents, the bad npm and Python packages, the files malware leaves on disk, the files worms plant in a project, the hosted platforms that leaked stored secrets, the agent settings that run commands without asking, the agent versions with a published security fix and the editor extensions that shipped malware each live in one file under `data/`, one line per entry, described in the file's header. `bash tools/gen.sh` writes them into both scripts; edit the data file, never the generated block between `# >>> name` and `# <<< name`. `tests/run.sh` fails if a script and its data file disagree.

## Add an agent

1. Add a line to the `AGENTS` table in `gird-check.sh`: name, commands, install paths, folders that change when it's used, and an id.
2. If it has an MCP config, add it to `MCP_FILES`. If it keeps keys in a config, add it to the candidate list in section 3.
3. If it keeps session transcripts, add a line to `data/sessions.tsv` and run `bash tools/gen.sh`.
4. Add a fake install to `tests/make-fixture.sh`, an assertion to `tests/run.sh` and its twin to `tests/run-ps.sh` (see [Test](#test)).

## Add a key format

1. Add a line to `data/keys.tsv`: an id, the provider's name, the prefix it starts with, and the pattern. Anchor the pattern on a prefix so it doesn't flag random strings. More specific prefixes go first. Run `bash tools/gen.sh`.
2. A new id also has to be added to `PROVIDERS` in gird.ai's Worker, or the shared counts drop it.
3. In `tests/make-fixture.sh`, build a fake key at runtime from pieces, as the existing ones do. Never commit a full key-shaped string.

## Add an incident check

Open an issue with the **New check** template first, with links to the vendor advisory. Checks look for files, versions or markers on disk. They never run the software they check.

A new incident of a kind Blindspot already checks is data lines only: add its line to `data/incidents.tsv` (a sourced name, impact and link, and its level: `act` when a hit means a compromised machine, `update` when the version needs updating but the machine itself is not compromised, and optionally a fix of its own, shown in What to do when one of its npm or Python packages or editor extensions is found; `gen.sh` refuses it on an incident that has none), then the lines below, and run `bash tools/gen.sh`. No code changes, and `tests/made-up.sh` proves it for every kind below. Add a fixture and an assertion to the tests all the same. The result page names LiteLLM and gh-token-monitor by name; any other Python incident reaches it as `py=1` and is shown as Python package malware.

- **A bad npm package**: one line in `data/bad-npm.tsv`: the name, the exact version (or `*` when every version is malware) and the incident's id. Take versions from a GitHub malware advisory, and sweep the whole campaign (every advisory published with it) rather than copying the first few names.
- **A bad Python package**: one line in `data/bad-pypi.tsv`: the name as its `.dist-info` folder spells it, the exact version (`*` is not supported), the incident's id, whose level must be `act`, and the OS its malware could run on (`all`, `mac`, `linux` or `win`, from the advisory). It is looked for in every Python environment and in uv's cache, and section 5 gets a row named as `data/incidents.tsv` names the incident. On an OS where the malware could not run, the version is shown as one to update, not a compromised machine.
- **Files malware leaves on disk**: one line each in `data/indicators.tsv`. `startup` is a file that starts malware at login, shown with its note; `site` a file in site-packages and `temp` an entry in the temp folder, both counted as the Python incident's hit. A `temp` line's note is the incident's own advice for those files, from its advisory, shown under the row when they are found; one incident's temp lines carry the same note. `owner` `yes` counts a file only when this person owns it, for the shared `/tmp`. `wiper` is a new file of gh-token-monitor (gen.sh refuses a path that does not name it): its stop-it-first advice, commands and result-page step are written for that wiper, so a different wiper is code.
- **A file planted in a project**: one line in `data/planted.tsv`: `.claude` or `.vscode`, the file name, the incident, the note shown, `yes` when only the worm uses that name or `no` when projects use it too (such as `setup.mjs`), and for a `no` file the SHA-256 values its sources publish, or `-`. A `yes` file counts wherever it is found; a `no` file counts only in a project that holds a `yes` file, or when its SHA-256 is listed, and is otherwise shown in section 2 as a file to read. A hook or task that runs it, as the script an interpreter runs or the command itself, is flagged too.
- **An editor extension that shipped malware**: one line in `data/bad-extensions.tsv`: the id as its folder spells it (`publisher.name`), the exact version (or `*`), the incident's id, whose level must be `act`, and the registry: `openvsx` when the bad build was only ever published to Open VSX (it is then looked for in the folders of Cursor, Windsurf, VSCodium and Kiro, not VS Code's own, whose Marketplace build of that version is clean), or `any`. A startup file of such an incident (`data/indicators.tsv`) is shown with the extensions, never as npm malware.
- **An agent setting that runs commands without asking**: one line in `data/auto-approve.tsv`: the agent, the OS, the settings file (or `{PROJECT}/folder/file` for that file in every project), the setting as shown, and the patterns that must all match a line. Take the setting's name and value from the agent's own documentation.
- **An agent version with a published security fix**: one line per place the version is read in `data/outdated.tsv`: how it is read (an Info.plist, a version folder, an npm package or an MCP config's `name@version`), the affected range, what the hole allows and the advisory.
- **A hosted platform that leaked stored secrets**: one line in `data/platforms.tsv`: the incident id, the row's name, its commands and paths, its row word and advice, and its summary row. The shared fix names it from `data/incidents.tsv`.

A new kind of check (a new file format, a running process, a registry value) is code: add it to section 5 of both scripts, a fixture to the tests, and a line to "What to do".

## Review checklist

A reviewer starts from the person who acts on the report, not from the diff:

- **Advice that makes things worse.** Follow every finding to every place it shows: its section, the summary row, "First fix", the fix list and the result page the link opens. Nothing may tell someone to revoke or rotate a token while `gh-token-monitor` is present.
- **False comfort.** A green line or "no keys" over something that wasn't fully read is a bug. Partial, skipped and unreadable must say so.
- **False alarms.** A red "treat this machine as compromised" over something harmless costs trust. Test the near misses: a version one digit off, a name that contains another, a rule or guard that names a malware file without running it.
- **Real inputs.** Try the shapes people actually have: pretty-printed JSON, committed `settings.local.json`, worktrees, symlinks, every lockfile format, paths with spaces or `|`, Windows paths.
- **Sources.** Every incident, version and file path traces to a primary source (the vendor's advisory, a GitHub malware advisory, or a named security research post). A comment or README line the code doesn't support is a bug.
- **What a list leaves out.** For any list taken from advisories, check what the same campaign published that the list misses, and that the report's wording doesn't claim more than the list covers.
- **Both scripts.** Every change lands in `gird-check.sh` and `gird-check.ps1`, each with a test that fails without it.

## Test

```sh
bash tests/run.sh            # builds a fake home folder and checks what the script finds and never prints
bash tests/interactive.sh    # macOS: drives the game and the menu with expect
shellcheck -s bash -S warning gird-check.sh tests/*.sh
PWSH=/path/to/pwsh bash tests/run-ps.sh   # the same checks for gird-check.ps1, under PowerShell 7
PWSH=/path/to/pwsh bash tests/parity-run.sh   # both suites, then checks every bash test has a twin
```

Run them before you open a pull request, one at a time, never two at once. They run the scripts with `--offline` or against a local stand-in for gird.ai, so a test run never reaches the live counts. `tests/run.sh` and `tests/interactive.sh` each run on the bash that ships with macOS (3.2) and on a newer bash from your PATH if you have one. Maintainers run them again before merging.

Every test in `tests/run.sh` needs a twin in `tests/run-ps.sh`: a test with the same name that checks the same thing for `gird-check.ps1`, on the Windows-shaped home. A test that can't or need not run for PowerShell gets a line in `tests/bash-only.txt` instead: its name, a tab, and the reason. A reason names a feature only `gird-check.sh` has (the game and the menu, the perl session engine, Git Bash and WSL, `tools/gen.sh`), or something PowerShell can't fake on the test machine, such as the OS. "Not written yet" is not a reason. Each test records its name as it runs, skipped ones too (`tests/lib.sh`: report through `ok`, `bad` and `skip` only, and a test that can't run on a machine calls `skip`). Every check reports through `ok` or `bad` on both outcomes: one that reports only when it fails (`[ ... ] && bad "x"`) or ends with `exit` never reaches the list on a passing run. The text backstop catches the first shape, not the second. A PowerShell test that skips where bash runs its twin needs a line in `tests/ps-skips.txt`, the name, a tab and why `gird-check.ps1`'s test can't run there. `tests/parity-run.sh` runs both suites and `tests/parity.sh` compares the two lists; run it before you open a pull request. CI runs it in the PowerShell job, so a bash test with neither fails CI. `tests/run.sh` also runs `tests/parity-text.sh`, a backstop that reads both suites as text; the runtime check is the rule. When a twin fails because the scripts behave differently, fix the script that is wrong, never the test.

## Sign your commits

Add a Developer Certificate of Origin sign-off to each commit with `git commit -s`. It says you wrote the change, or have the right to submit it, under the project's license. See [developercertificate.org](https://developercertificate.org).

## Releases

Every week, and before a merge to `main`, a maintainer runs `bash tools/check-advisories.sh`. It compares `data/bad-npm.tsv` with OSV.dev (which includes GitHub's malware advisories and the OpenSSF Malicious Packages list) and lists withdrawn entries, versions we flag that nothing names any more, and malicious versions we miss. Treat a MISSING line as a lead: confirm it against a primary source before adding it. It also lists each incident's source to re-read, since a vendor can change what it says an incident did.

Maintainers cut tagged releases and publish the SHA-256 of `gird-check.sh` in the release notes. gird.ai/blindspot serves `gird-check.sh` and `gird-check.ps1` from `main`, so a merge to `main` is a release to everyone who downloads from gird.ai.
