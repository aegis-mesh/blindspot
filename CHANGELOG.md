# Changelog

## 1.1.0, 22 October 2026

- How you compare instead of a letter grade. The report opens with a line such as "Safer than 72% of 1,234 developers who ran Blindspot", taken from the reply to the report it already sends.
- The first 1,000 developers to run it see their number with the result, such as "You're developer #142 to run Blindspot."
- A short summary by default: one line per check and the first thing to fix. Press 1 to 5 for a check's details. `--full` prints everything, and so does running it into a file or a pipe. A saved report always has every detail.
- While it scans, the game or the spinner shows what it just found.
- One line of real totals under the banner, such as how many developers have run it. Until 1,000 have, it says you're one of the first 1,000 instead.
- When the results are ready, ENTER opens your Blindspot certificate. q quits.
- The certificate link also carries your number, how many SSH keys it found, how many shell history files hold keys, and the run's random ID, so the certificate can show more of what you got right. If you press a share button there, the page sends that ID back with which button and what kind of result.
- The web page moved to gird.ai/blindspot. Old gird.ai/check links redirect there.
- The banner says Blindspot, and the certificate opens at gird.ai/blindspot/card.

## 1.0.0, 22 October 2026

First public release.

- Five checks: coding agents, MCP servers, keys in plain text, keys saved in Claude Code allow lists, and signs of the October 2026 LiteLLM, OpenCode and Railway leaks.
- A grade from A to F and a list of what to fix.
- GIRD Runner, a game to play while it scans.
- A menu at the end: save the report, get a share card, or try Argus.
- Counts shared with gird.ai, listed in TELEMETRY.md. `--offline` and `DO_NOT_TRACK=1` turn them off.
