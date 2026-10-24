# Blindspot for IT teams

`gird-check.sh --all-users` checks every account on a Mac for the same things Blindspot shows one
person: coding agents, keys in plain text, keys in agent sessions, agents set to run commands without
asking, and signs of recent malware incidents. It runs as root from your MDM, checks each account as
that account, and keeps a short result on the Mac for your MDM to read.

macOS only for now. The MDM pages in [docs/mdm/](mdm/) are marked untested until each has been run
end to end on a real Mac.

What it never does:

- Send anything anywhere. It makes no network request.
- Show a path, a file name or a key. The result holds counts and names from fixed lists.
- Change anything in a home folder. It reads files and keeps one result in
  `/var/db/blindspot/last.json`, readable by root only.
- Run a tool a person could replace. As root it calls every tool by its full path from the system
  folders.

## 1. Try it on your own Mac

Download the script and check its SHA-256:

```sh
curl -fsSLO https://gird.ai/blindspot/gird-check.sh
shasum -a 256 gird-check.sh   # compare with the SHA-256 on gird.ai/blindspot
```

See who it would check, without checking anything:

```sh
sudo bash gird-check.sh --all-users --list
```

Then run it:

```sh
sudo bash gird-check.sh --all-users
```

You get a report per account and where the result was saved. To see which files a finding is
about, the person runs Blindspot on their own account: `bash gird-check.sh`.

## 2. Grant Full Disk Access to your MDM's agent

macOS protects some folders, such as Mail, Messages and Safari, unless the process that started the
script has Full Disk Access. Without it, each account's result says its protected folders were not
checked, and the account reads `not_checked`, never `clear`.

Grant it with a Privacy Preferences Policy Control profile (Full Disk Access is
`SystemPolicyAllFiles`) for your MDM's own agent. Read the agent's identifier and code requirement
on one of your enrolled Macs:

```sh
codesign -dr - "<path to your MDM's agent>"
```

Never grant it to a shell such as `/bin/bash`: that gives it to every script on the Mac. Whether an
account's check, started through `sudo`, keeps the agent's access has not been measured yet. The
result tells you: `protected_folders` is `checked` or `not_checked` for each account.

The page for your MDM says where its agent is.

## 3. Add it to your MDM

Two items:

- **The check**, run daily. It is the script with one line added under its first line, so it runs
  with these options whatever arguments your MDM passes:

  ```sh
  [ "${1:-}" = --account-run ] || set -- --all-users --exit-zero --summary-to-stdout --deadline=3000
  ```

- **The inventory field**, run whenever the Mac reports in. It is the script with this line instead.
  It only reads the saved result and never checks anything:

  ```sh
  [ "${1:-}" = --account-run ] || set -- --inventory --stale-days=3
  ```

Paste the script from a tagged release whose SHA-256 you checked (the release notes give it), so a
run needs no download. Set
`--deadline` below your MDM's own time limit for a script; the page for your MDM gives the number.
Each account gets an equal share of the time left, so one stuck account cannot hold up the rest.

| Option | What it does |
|---|---|
| `--all-users` | Checks every account. Needs root. |
| `--list` | Lists who would be checked and why anyone is not, and checks nothing. |
| `--json` | Prints the full result as JSON and nothing else. |
| `--summary-to-stdout` | Prints one summary line. |
| `--exit-zero` | Exits 0 whenever the run finished; only `failed` exits 13. |
| `--deadline=<seconds>` | Stops the run in time. 3000 if not given. |
| `--hash-accounts=<secret>` | Shows each account as a keyed hash of its name. Keep the secret to match them later. |
| `--inventory` | Prints the saved inventory value. Needs root. |
| `--stale-days=<days>` | With `--inventory`: older than this reads `stale`. 3 if not given. |
| `--result-tags` | With `--inventory`: wraps the value in `<result></result>`, for Jamf Pro. |

## 4. Read the results

Each run has one outcome, the worst of these, in this order:

| Outcome | Means | Exit code |
|---|---|---|
| `failed` | The run could not finish safely, such as a changed script copy or a result it could not save. | 13 |
| `act` | Something to act on now: malware signs, or keys in plain text, shell history, agent sessions, MCP configs or allow lists. | 10 |
| `not_checked` | An account, or part of one, was not checked. Never read this as clear. | 12 |
| `update` | Something to change: a tool with a security fix, an agent set to run without asking, an SSH key without a passphrase, a platform that leaked stored secrets, a leftover file that can come from malware. | 11 |
| `clear` | Every account was checked in full and nothing was found. | 0 |

An account is `not_checked` when its home folder is missing, a link, shared or not its own, it has
no login shell, its check could not start or ran out of time, its check sent back something
unexpected, or part of it was not read: a protected folder, a file that is not a regular file or is
over 16 MB, or agent sessions not all checked.

The summary line:

```
blindspot act accounts=2 act=1 update=0 not_checked=1 v=1 at=2026-10-25T09:12:00Z
```

The inventory value is one line with each account's outcome and what was found, never a path, file
name or key:

```
v1 act 2026-10-25T09:12Z | asha: act tanstack; keys 2 anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear
```

If it would be too long, it keeps each account's outcome and ends with `+more`. The full result is
in `/var/db/blindspot/last.json`. The inventory field shows `stale: last run <time>` when the last run
is older than `--stale-days`, `none` before the first run, and `unreadable` when the saved file is
not root's own. Treat each of those, and any outcome your MDM does not show, as not checked.

To find the Macs to deal with first, filter the inventory field for values starting `v1 act`, then
`v1 not_checked` and `stale`.

## 5. Act on a finding

Ask the person to run Blindspot on their own account, `bash gird-check.sh`, to see which files. Then:

| Finding | What to ask them to do |
|---|---|
| A malware incident at `act` | Treat the Mac as compromised. Follow the incident's advisory, linked in their report, and rotate every key the Mac could reach. If their report names `gh-token-monitor`, remove it before revoking any GitHub token. |
| Keys in plain text | Move them into the macOS Keychain or a secrets manager, then rotate them. |
| Keys in shell history or agent sessions | Rotate them: they were typed into a command or read by an agent. |
| Tokens in MCP configs | Replace them with environment variable references, then rotate them. |
| Keys in Claude Code allow lists | Delete those saved commands and rotate the keys. |
| Files a worm plants in a project | Treat the Mac as compromised, as for malware. |
| An agent set to run without asking | Turn it off, unless the agent runs in a sandbox. |
| A tool with a security fix | Update it. |
| An SSH key without a passphrase | Add one: `ssh-keygen -p -f <key file>`. |
| A platform that leaked stored secrets | If they used it, rotate the keys stored there. |
| A finding under "This Mac" | Found in the shared temp folder, which any account can write to. Treat the Mac as compromised. |

## 6. Update or remove it

To update, paste the new release into both MDM items, after checking its SHA-256. To remove it,
delete both items from your MDM, then remove the saved result on each Mac:

```sh
sudo rm -rf /var/db/blindspot
```

## What it checks for each account

The same places as a normal run, without Desktop, Documents and Downloads (`--all` is refused: they
can hold cloud files that download when read). Each account's check runs through
`sudo -n -u <account>` with a clean environment and only that account's rights. Apps in
`/Applications`, the shared temp folder and the shared startup folders are checked once, by root,
by name only, and reported for the Mac. `sudo` writes one line to the system log for each account.

The design, with what it does not cover, is in
[docs/designs/fleet-mode.md](designs/fleet-mode.md).
