# Blindspot: notes for coding agents

`gird-check.sh` (bash 3.2: macOS, Linux, Git Bash) and `gird-check.ps1` (PowerShell 5.1 and 7, ASCII
only) must find the same things and print the same report. A change to one lands in the other, with a
test in each suite. [CONTRIBUTING.md](CONTRIBUTING.md) has the rules the scripts keep and the review
checklist; read it first.

## Tests

- Every test in `tests/run.sh` needs a twin of the same name in `tests/run-ps.sh`, or a line in
  `tests/bash-only.txt`: the name, a tab, and a specific reason it can't or need not run for
  PowerShell. "Not written yet" is not a reason. `tests/parity.sh` enforces it, and both suites run it.
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
