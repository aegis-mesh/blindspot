# Blindspot: notes for coding agents

`gird-check.sh` (bash 3.2: macOS, Linux, Git Bash) and `gird-check.ps1` (PowerShell 5.1 and 7, ASCII
only) must find the same things and print the same report. A change to one lands in the other, with a
test in each suite. [CONTRIBUTING.md](CONTRIBUTING.md) has the rules the scripts keep and the review
checklist; read it first.

## macOS, Linux and Windows stay at par

Every feature must work on macOS, Linux and Windows. That covers the check one person runs, fleet
mode, the tools an admin uses, every kind of finding, the result formats, the mappings to outside
frameworks, and the docs. Where the three differ today, an open issue labelled `parity` says so.

- Before you build a feature, write down what each of the three platforms gets.
- A feature lands on all three in the same pull request. If one platform has to wait, the pull
  request says which and why, and an issue is opened for it before the pull request merges.
- A fix found on one platform is checked on the other two in the same pull request.
- A real platform limit is not a gap. Say what the limit is in the docs a person reads, and make
  the result show what was not checked. Never let it read as clear.
- Review checks this. A feature for one platform, with no word on the other two, is a major
  finding.

The twin rule under Tests is how the two check scripts are held to this. The same care applies to
everything else.

## One home for anything two files share

Each script is one file a person downloads, so the scripts cannot load shared code. What they share
is kept once and written into them by `tools/gen.sh`.

- A list, a table, a format or a mapping that more than one file needs has one home in `data/`.
  [CONTRIBUTING.md](CONTRIBUTING.md#lists-live-in-data) says how the lists there work.
- Never type the same list into a second file. Add it to `data/`, have `tools/gen.sh` write it
  into every file that needs it, and let `tools/gen.sh --check` fail when a copy drifts.
- This holds for a format one file writes and another reads, such as the lines an account's check
  sends and the result line a fleet run saves. The writer and the reader take their words from the
  same home.
- Logic cannot be shared between bash and PowerShell. It is written once in each, and the twin
  tests hold the two to the same behaviour.
- Each script keeps one job: `gird-check` checks one account, `gird-fleet` runs the check for a
  fleet. A new job gets its own file, not a new mode in an existing one.

## This repository is public

Everything here is published: files, comments, commit messages, pull request descriptions, review
comments and issues. Write each one for a stranger reading it, and choose what goes in on purpose.
Never include GIRD internals: names of private repositories, internal tools or agents, servers,
endpoints, tokens, customer or tenant details, or how GIRD's other products are built. Describe
only what this repo's code does. If a reason for a change is internal, state the public effect and
leave the internal part out.

## Tests

- Every test in `tests/run.sh` needs a twin of the same name in `tests/run-ps.sh`, or a line in
  `tests/bash-only.txt`: the name, a tab, and a specific reason it can't or need not run for
  PowerShell. "Not written yet" is not a reason. Tests record their names as they run (`tests/lib.sh`:
  report only through `ok`, `bad` and `skip`; a test that can't run here calls `skip`).
  `PWSH=/path/to/pwsh bash tests/parity-run.sh` runs both suites and `tests/parity.sh` on the two
  lists. Run it before a pull request; CI runs it too. A PowerShell test that skips where its bash
  twin runs needs a line in `tests/ps-skips.txt` with the reason. Report every check through `ok` or
  `bad` on both outcomes, never only on failure.
- A twin that fails because the scripts behave differently is a bug in a script: fix the script that
  is wrong. Never weaken a test to make it pass.
- Run the scripts with `--offline` / `-Offline`, or against the suites' local mock server. Never run
  them online: a run sends counts to gird.ai's live analytics.
- Run the suites one at a time, never two at once: `bash tests/run.sh`, then
  `PWSH=/path/to/pwsh bash tests/run-ps.sh`. `bash tools/gen.sh --check` must pass.
- Fixtures build keys from pieces at runtime. Never commit a key-shaped string.

## Copy in the report

- No em dashes. Use a colon, a comma or a period.
- Plain words: say what was found and what to do, then stop. No machinery, no filler.
- Never call something clean that was not fully read: partial, skipped and unreadable say so.
