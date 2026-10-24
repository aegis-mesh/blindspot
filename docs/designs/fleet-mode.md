# Fleet mode: running Blindspot from an MDM

Status: proposal, not built.

## Why

A company that manages its computers with an MDM (Jamf, Iru, Intune and others) wants one answer for
every machine: which coding agents run, where AI and cloud keys sit in plain text, and whether a
recent malware incident touched any of them. Today Blindspot answers that for one person, run by that
person. An MDM runs scripts as root (SYSTEM on Windows), with root's own home folder, so a run from an
MDM checks the wrong home and finds nothing.

Fleet mode lets an MDM run the same checks for every account on a machine and keep a short result.
Nothing new leaves the machine.

## What it adds

1. `--all-users` (`-AllUsers` in PowerShell): needs root or an elevated 64-bit PowerShell, and exits 4
   with a message on standard error otherwise. It lists the machine's accounts and checks each one.
2. `--json` (`-Json`): one JSON document on standard output and nothing else there.
3. `--summary-to-stdout`: with `--all-users`, saves the full JSON to a file only root can read
   (`/var/db/blindspot/last.json`, `/var/lib/blindspot/last.json`, or
   `%ProgramData%\Blindspot\last.json` with an ACL for SYSTEM and Administrators) and prints a one-line
   summary for an MDM that keeps only a little output.
4. `--exit-zero`: exits 0 whenever the run finished, for an MDM that treats any other code as a
   failure. The outcome is then in the summary and the file.
5. One page per MDM in `docs/mdm/`.

`--all-users` turns off everything a run with nobody watching must not do: the game, the menu, the
browser, colours, saving a report, and every network request (as `--offline`). It refuses `--all`,
because Desktop and Documents may hold cloud placeholder files that download when read.

## Each account is checked as that account

The script, as root, only lists the accounts and checks machine-wide places. For each account it
starts the checks again as that account (with `sudo`, or `su` where `sudo` is missing), with that
account's home and a fixed environment:

```
sudo -u <account> -H env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=<home> \
  /bin/bash <script> --account-run --offline --json
```

so a person's files can only show the checks what that person can already read. A link from one home
to another person's files, or to a system file, is read with the first person's rights, and fails
where they have none. The account run's findings are attributed to that account only.

On Windows, SYSTEM cannot start a process as another account without that person's sign-in, so the
PowerShell script checks each account itself, with these extra rules: every path is built from that
account's `ProfileImagePath` (never from the environment, which points at SYSTEM's own profile), and
before a file is read, each part of its path is checked and a link or junction anywhere in it skips
the file as not checked.

Rules for every account run, each with a test:

- The tools are the system's own, at fixed paths, with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. Tools a
  person can replace (`/opt/homebrew/bin`, `/usr/local/bin`) are never used, ripgrep included: the
  session check uses perl. Test-only `GIRD_CHECK_*` settings are ignored.
- A file is read only if it is a regular file under a size limit. A fifo, socket, device or oversized
  file is counted as not checked.
- Each account run has a time limit. A run that does not finish in time is abandoned, not waited for,
  so a read stuck on a network home cannot hold up the others, and the account is reported as partly
  checked. The whole run has a deadline below the MDM's own timeout.
- Read only. Nothing is created, changed or deleted in any home. Reading does change files' access
  times.
- An agent installed in the account's own folders (`~/.local/bin`, its npm and version-manager
  folders) counts for that account. One installed in a shared folder (`/usr/local/bin`,
  `/opt/homebrew/bin`) is found by its path, never run, and reported once, for the machine.

## Which accounts

| system | accounts | home |
|---|---|---|
| macOS | `dscl . -list /Users UniqueID`, UID 500 and above, not starting with `_` | `NFSHomeDirectory` |
| Linux | local `/etc/passwd` only (no directory lookups), UID from `UID_MIN` in `/etc/login.defs`, a shell listed in `/etc/shells` | the passwd home field |
| Windows | `ProfileList` entries for local (`S-1-5-21-`) and Entra (`S-1-12-1-`) accounts | `ProfileImagePath` |

A home is checked only if it is a folder, not a link, owned by the account, not `/` or a system
folder, and not shared with an account already checked. An account whose home fails these, or does
not answer in time, is listed as not checked. A run that finds no account at all is not clean: it
reports not checked. Leftover home folders with no account are not listed.

## Machine-wide places

Checked once, as root, and reported for the machine, not for an account: the temp folders, startup
items in shared folders, and running processes. A malware marker found only in the shared temp folder
is reported as a machine finding, because any account can create files there.

## The result

The JSON holds counts and names from fixed lists, the same kinds of fields the shared report holds
today, and no file paths, file names or key values:

```json
{
  "blindspot": "1",
  "script": "<version>",
  "checked_at": "<UTC time>",
  "os": "macOS 15.5",
  "outcome": "act",
  "accounts": [
    {
      "account": "<local account name>",
      "complete": true,
      "agents": ["claude-code", "codex"],
      "agents_run_without_asking": ["claude-code"],
      "tools_to_update": ["mcp-remote"],
      "mcp_servers": 4,
      "mcp_token_files": 1,
      "key_files": 2,
      "key_providers": ["anthropic", "aws"],
      "history_keys": 1,
      "session_files_with_keys": 0,
      "ssh_keys_no_passphrase": 1,
      "incidents": [{"id": "tanstack", "level": "act"}]
    }
  ],
  "machine": { "complete": true, "agents": [], "incidents": [] }
}
```

- `account` is the local account name, which the MDM already knows. `--hash-accounts` replaces it
  with a hash.
- `outcome` is the worst of: `failed`, `act`, `not_checked`, `update`, `clear`, in that order, so a
  finding to act on is never hidden by a partial check, and a partial check never reads as clear.
- The summary line is `blindspot <outcome> accounts=<n> act=<n> update=<n> not_checked=<n>`.

### Exit codes

New codes, kept clear of the ones the script already uses (2 for an unknown option, 130 when
interrupted): 0 `clear`, 10 `act`, 11 `update`, 12 `not_checked`, 13 `failed`. With `--exit-zero`, a
finished run exits 0 and only `failed` exits 13. An MDM that stops the script on its own timeout
gets no code at all, so each MDM page treats a missing summary, or any code it does not expect, as
not checked.

## MDM pages

Each page in `docs/mdm/` gives: the script to paste, how the MDM runs it (account, environment,
timeout, how often), where the result shows, how the exit code and the summary map onto what that
MDM shows, and the Full Disk Access payload for that MDM's own agent on macOS. Access is granted to
the MDM's agent, never to a shell such as `/bin/bash`, which would give it to every script on the
Mac. Without Full Disk Access, which an MDM can grant only on supervised Macs, protected folders are
reported as not checked.

The script is embedded in the MDM's payload at a pinned version, so a run needs no network. Where an
MDM limits a script's size, the page downloads a pinned version and checks its SHA-256 first, and a
mismatch exits 13.

| MDM | runs it as | the result |
|---|---|---|
| Jamf Pro | a policy, as root, on a schedule | the policy runs the scan; an extension attribute reads the saved summary at inventory, never rescans |
| Iru | a custom script; an audit script for pass or fail | `--exit-zero` for the audit; the summary in the script's output |
| Microsoft Intune, macOS | a shell script, as root | the summary; the full result in the saved file |
| Microsoft Intune, Windows | a remediation detection script, 64-bit PowerShell, as SYSTEM | exit 0 or 1 only (the page maps 10, 11, 12 to 1); the summary, kept short |

Each page states the MDM's own limits (output size, timeout, frequency) from that vendor's current
documentation, with the date checked. A page is marked tested only after it has been run end to end
on a real machine; until then it says untested.

## Not covered

- Collecting results from many machines in one place. The result is for the MDM's own inventory.
- Running as each account on Windows (it needs that person's sign-in).
- Containers, servers and CI runners.

## Tests

- The account list on each system, from fixtures: a system account, a missing home, a home that is a
  link, a home owned by another account, two accounts sharing a home, an Entra SID, no accounts.
- Two fixture accounts with different findings: each account's result holds only its own.
- A link in one home to the other home, to a system file, and through a linked folder: never read
  with the other account's rights; on Windows, skipped as not checked.
- A fifo in place of a history file, a link to a device, and an oversized file: not read, counted as
  not checked, and the run finishes.
- A replaced `jq` or `grep` earlier in the MDM's PATH: never run.
- Not root: exits 4. `--all` with `--all-users`: refused.
- No network request (a local listener sees nothing), no browser, no saved report.
- The JSON holds no path, file name or planted key; standard output holds only the JSON; both scripts
  give the same JSON for the same fixture.
- Each outcome and exit code from a fixture that produces it, the order between them, and a run
  stopped part-way.
- An MDM-like environment: no HOME, minimal PATH, working folder `/`, no terminal.
