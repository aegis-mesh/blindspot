# Fleet mode: running Blindspot from an MDM

Status: proposal, not built. Phase 1 is macOS. Linux follows on the same design. Windows needs a
design of its own (see Not covered).

## Why

A company that manages its Macs with an MDM (Jamf, Iru, Intune and others) wants one answer for every
machine: which coding agents run, where AI and cloud keys sit in plain text, and whether a recent
malware incident touched any of them. Today Blindspot answers that for one person, run by that
person. An MDM runs scripts as root, with root's own home folder, so a run from an MDM checks the
wrong home and finds nothing.

Fleet mode lets an MDM run the same checks for every account on a Mac and keep a short result.
Nothing new leaves the machine.

## What it adds

1. `--all-users`: needs root, and exits 13 with a message on standard error otherwise. It lists the
   Mac's accounts and checks each one.
2. `--json`: one JSON document on standard output and nothing else there.
3. `--summary-to-stdout`: with `--all-users`, saves the full JSON to a file only root can read and
   prints a one-line summary, for an MDM that keeps only a little output.
4. `--exit-zero`: exits 0 whenever the run finished, for an MDM that treats any other code as a
   failure. The outcome is then in the summary and the file.
5. One page per MDM in `docs/mdm/`.

`--all-users` turns off everything a run with nobody watching must not do: the game, the menu, the
browser, colours, saving a report, and every network request (as `--offline`). It refuses `--all`,
because Desktop and Documents may hold cloud placeholder files that download when read.

## Root does little, and trusts nothing it does not control

The root part only lists accounts, checks machine-wide places, starts one run per account and
assembles the result. Before running any command it sets `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and
calls every tool by its full path, so a tool a person can replace (`/usr/local/bin`,
`/opt/homebrew/bin`) never runs as root. Test-only `GIRD_CHECK_*` settings are ignored.

## Each account is checked as that account

For each account, root starts the checks as that account, with that account's home and a fixed
environment:

```
/usr/bin/sudo -n -u <account> -H /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  HOME=<home> /bin/bash <copy> --account-run
```

A person's files can then only show the checks what that person can already read: a link from one
home to another person's files, or to a system file, is read with the first person's rights and fails
where they have none. There is no `su` fallback, because `su` runs the account's own shell start-up
files. If `sudo` fails, the account is reported as not checked.

- The copy of the script each account runs is made once by root, in a new folder made with `mktemp
  -d` and owned by root (folder 0755, file 0644), and its owner and mode are checked again before
  each start. No account can change the code a later account runs.
- An account run reads only regular files under a size limit. A fifo, socket, device or oversized
  file is counted as not checked. The session check uses the system's perl, never ripgrep.
- An account run cannot speak for anyone else. It writes a fixed line format (`key=value`, known keys
  only, numbers, and names from the fixed lists) to a pipe root created. Root reads at most a set
  number of bytes, checks every line against the format, and builds the account's row itself. Any
  line that does not fit makes that account not checked. Root never copies an account run's output
  into the result.
- Nothing an account run starts inherits the MDM's output. Its output goes only to root's pipe. Each
  account has a time limit enforced by root with a background timer (macOS has no `timeout`); at the
  limit root kills the run's process group, stops reading, reports the account as partly checked and
  moves on, so a read stuck on a network home cannot hold up the others or the MDM. A process that
  survives the kill is reported. The whole run has a deadline below the MDM's own timeout, set by a
  flag each MDM page gives.
- Read only. Nothing is created, changed or deleted in any home, though reading changes files' access
  times. `sudo` writes one line to the system log per account.

## Full Disk Access

macOS protects some folders (Mail, Messages, Safari and others) unless the process that started the
script has Full Disk Access. An MDM can grant it to its own agent on supervised Macs. Whether an
account run started through `sudo` keeps that access has not been measured, and a refused folder can
look like an empty one. So each account run first tries a known protected folder; if that is refused,
every protected folder is reported as not checked for that account, never as clear. This stays marked
unmeasured until it is tested on a managed Mac.

## Which accounts

`dscl . -list /Users UniqueID`, UID 500 and above, not starting with `_`, home from
`NFSHomeDirectory`. A home is checked only if it is a folder, not a link, owned by the account, not
`/` or a system folder, and not shared with an account already checked. An account whose home fails
these, or does not answer in time, is listed as not checked. A run that finds no account is not clean:
it reports not checked. Leftover home folders with no account are not listed.

## Machine-wide places

Checked once, by root, and reported for the Mac, not for an account: the shared temp folder, startup
items in shared folders, agents installed in shared folders (found by path, never run), and running
processes. A malware marker found only in the shared temp folder is reported as a machine finding,
because any account can create files there.

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

- `account` is the local account name, which the MDM already knows. `--hash-accounts=<secret>`
  replaces it with a keyed hash; a plain hash of a name is easy to reverse.
- `outcome` is the worst of `failed`, `act`, `not_checked`, `update`, `clear`, in that order, so a
  finding to act on is never hidden by a partial check, and a partial check never reads as clear.
- The summary line is `blindspot <outcome> accounts=<n> act=<n> update=<n> not_checked=<n>`.
- The saved file is `/var/db/blindspot/last.json`. The folder must be a real folder owned by root,
  mode 0700, or root recreates it; the file is written to a temporary name and renamed into place.

### Exit codes

New codes, clear of the ones the script already uses (1 when HOME is not set, which `--all-users` does
not need; 2 for an unknown option; 130 when interrupted): 0 `clear`, 10 `act`, 11 `update`, 12
`not_checked`, 13 `failed`. With `--exit-zero`, a finished run exits 0 and only `failed` exits 13. An
MDM that stops the script on its own timeout gets no code, so each page treats a missing summary, or
any code it does not expect, as not checked.

## MDM pages

Each page in `docs/mdm/` gives: the script to paste, how the MDM runs it (account, environment,
timeout, how often), where the result shows, how the exit code and summary map onto what that MDM
shows, the deadline flag to set, and the Full Disk Access payload for that MDM's own agent. Access is
granted to the MDM's agent, never to a shell such as `/bin/bash`, which would give it to every script
on the Mac.

The script is embedded in the MDM's payload at a pinned version, so a run needs no network. Where an
MDM limits a script's size, the page downloads a pinned version and checks its SHA-256 first, and a
mismatch exits 13.

| MDM | runs it as | the result |
|---|---|---|
| Jamf Pro | a policy, as root, on a schedule | the policy runs the scan; an extension attribute reads the saved summary at inventory, never rescans |
| Iru | a custom script; an audit script for pass or fail | `--exit-zero` for the audit; the summary in the script's output |
| Microsoft Intune | a shell script, as root | the summary; the full result in the saved file |

Each page states that MDM's own limits (output size, timeout, frequency) from the vendor's current
documentation, with the date checked, and is marked untested until it has been run end to end on a
real Mac.

## Not covered

- **Windows.** SYSTEM cannot start a process as another account without that person's sign-in, so
  each account could not be checked as itself. Checking all accounts as SYSTEM instead needs its own
  answers: a file a person locks can block a read indefinitely in one process; a link swapped between
  checking a path and opening it is read with SYSTEM's rights; and a folder under ProgramData can be
  created by any user first. Windows gets its own design.
- **Linux** uses this design with `setpriv` (no shell start-up files, no login session) to drop to
  the account, the local `/etc/passwd` only (no directory lookups), and `UID_MIN` from
  `/etc/login.defs`. It is phase 2.
- Collecting results from many machines in one place. The result is for the MDM's own inventory.
- Containers, servers and CI runners.

## Tests

- The account list, from fixtures: a system account, a missing home, a home that is a link, a home
  owned by another account, two accounts sharing a home, no accounts.
- Two fixture accounts with different findings: each account's row holds only its own.
- An account run that prints another account's row, a forged machine section, oversized output, or a
  malformed line: that account is not checked, and no other row changes.
- A script copy that an account could write: the run refuses to start.
- An account run that holds its output open past its limit: the run finishes, that account is partly
  checked, the MDM's output closes.
- A link in one home to the other home, to a system file, and through a linked folder: never read with
  the other account's rights.
- A fifo in place of a history file, a link to a device, and an oversized file: not read, counted as
  not checked.
- A replaced `jq`, `grep` or `sudo` earlier in the MDM's PATH: never run, by root or an account run.
- A refused protected folder: not checked, never clear.
- `sudo` failing, and an account with no login shell: not checked.
- A saved-result folder that is a link or owned by someone else: recreated.
- Not root: exits 13. `--all` with `--all-users`: refused.
- No network request (a local listener sees nothing), no browser, no saved report.
- The JSON holds no path, file name or planted key; standard output holds only the JSON.
- Each outcome and exit code from a fixture that produces it, the order between them, and a run
  stopped part-way.
- An MDM-like environment: no HOME, minimal PATH, working folder `/`, no terminal.
