# Contributing to Blindspot

Thanks for helping. New agents, key formats and incident checks are the most useful contributions, and new leaks happen every week.

## The rules the script keeps

Every change has to keep these true. Reviews check them first.

- **Read-only.** It never writes, moves or deletes a file, except the report someone asks it to save.
- **Never prints a key.** Match keys inside `grep` or `awk` pipes. Never put a key value in a variable or the output.
- **Runs nothing it finds.** No Python, no agents, no MCP servers, no git inside other people's repos, no sudo.
- **No new dependencies.** Only tools that ship with macOS and common Linux distributions. It must run on bash 3.2, the version macOS ships.
- **Shares nothing new by accident.** Anything added to the shared counts must be a number or come from a fixed list, and must be listed in [TELEMETRY.md](TELEMETRY.md).

## Add an agent

1. Add a line to the `AGENTS` table in `gird-check.sh`: name, commands, install paths, folders that change when it's used, and an id.
2. If it has an MCP config, add it to `MCP_FILES`. If it keeps keys in a config, add it to the candidate list in section 3.
3. Add a fake install to `tests/make-fixture.sh` and an assertion to `tests/run.sh`.

## Add a key format

1. Add a `P_` pattern with the other key formats and include it in `ALL_KEYS`. Anchor it on a prefix so it doesn't flag random strings.
2. Map its prefix to a provider name in `providers_in`.
3. In `tests/make-fixture.sh`, build a fake key at runtime from pieces, as the existing ones do. Never commit a full key-shaped string.

## Add an incident check

Open an issue with the **New check** template first, with links to the vendor advisory. Checks look for files, versions or markers on disk. They never run the software they check. Add the check to section 5, a fixture to the tests, and a line to "What to do".

## Test

```sh
bash tests/run.sh            # builds a fake home folder and checks what the script finds and never prints
bash tests/interactive.sh    # macOS: drives the game and the menu with expect
shellcheck -s bash -S warning gird-check.sh tests/*.sh
```

Run all three before you open a pull request. `tests/run.sh` and `tests/interactive.sh` each run on the bash that ships with macOS (3.2) and on a newer bash from your PATH if you have one. Maintainers run them again before merging.

## Sign your commits

Add a Developer Certificate of Origin sign-off to each commit with `git commit -s`. It says you wrote the change, or have the right to submit it, under the project's license. See [developercertificate.org](https://developercertificate.org).

## Releases

Maintainers cut tagged releases and publish the SHA-256 of `gird-check.sh` in the release notes. gird.ai/blindspot serves the released file, never `main`.
