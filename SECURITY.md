# Security policy

Please report vulnerabilities privately. Use **Report a vulnerability** on this repository's Security tab, or email [security@gird.ai](mailto:security@gird.ai). Please don't open a public issue.

We acknowledge reports within 2 business days, triage within 5, and fix high-severity issues within 30 days. Good-faith research is welcome under the safe harbour in our [responsible disclosure policy](https://gird.ai/responsible-disclosure).

## In scope

- The script printing, storing or sending a key, a key fragment, a path, a username or a hostname.
- File names or file contents that make the script run a command, or send escape sequences to your terminal.
- The script writing or changing a file other than the report you asked it to save.
- The script starting an agent, an MCP server or Python, or using sudo outside `--all-users`.
- In `--all-users`, run as root: anything an account can do to change what root runs, reads or reports for another account.
- The shared counts carrying anything not listed in [TELEMETRY.md](TELEMETRY.md).

## How it is built to stay safe

- Keys are matched inside `grep` and `awk` pipes. A key value never lands in a shell variable or in the output.
- Paths it shows have control characters replaced, so a hostile file name can't drive your terminal.
- It never runs code it finds: no Python, no agents, no MCP servers, no git inside your repos.
- The report is saved with `umask 077` and noclobber, so it can't follow a planted link.
- Counts go over https only, with a 5-second timeout, in the background.

## Supported versions

Only the latest release.
