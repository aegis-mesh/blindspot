# Fleet mode: running Blindspot from an MDM

Status: built for macOS (phase 1), as `gird-check.sh --all-users`, with the admin guide in
`docs/fleet.md` and the MDM pages in `docs/mdm/` (each marked untested until run end to end on a real
Mac). Linux is phase 2: until then `--all-users` on Linux exits 13 with a message. `gird-check.ps1`
has no fleet mode; Windows needs a design of its own (see Not covered). What the build adds to this
design, or settles where it was open, is under "As built" at the end.

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
5. `--list`: with `--all-users`, prints which accounts would be checked and why any are skipped,
   and checks nothing, so an admin can see what a run will do before rolling it out.
6. A guide for admins, `docs/fleet.md`, and one page per MDM in `docs/mdm/`.

`--all-users` turns off everything a run with nobody watching must not do: the game, the menu, the
browser, colours, saving a report, and every network request (as `--offline`). It refuses `--all`,
because Desktop and Documents may hold cloud placeholder files that download when read.

## Root does little, and trusts nothing it does not control

The root part only lists accounts, checks machine-wide places, starts one run per account and
assembles the result. Before running any command it sets `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and
calls every tool by its full path, so a tool a person can replace (`/usr/local/bin`,
`/opt/homebrew/bin`) never runs as root. Test-only `GIRD_CHECK_*` settings are ignored.

## Each account is checked as that account

Accounts are checked one after another, never at once, so a run does not load a Mac someone is
working on, and one stuck account only spends its own time limit. For each account, root starts the checks as that account, with that account's home and a fixed
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
- An account run reads only regular files, and leaves out any over a size limit. A fifo, socket,
  device or oversized file is counted as not checked. Session files are the exception to the size
  limit: the session check, which uses the system's perl, never ripgrep, reads them in 1 MB pieces
  whatever their size.
- An account run cannot speak for anyone else. It writes a fixed line format (`key=value`, known keys
  only, numbers, and names from the fixed lists) to a pipe root created. Root reads at most a set
  number of bytes, checks every line against the format, and builds the account's row itself. Any
  line that does not fit makes that account not checked. Root never copies an account run's output
  into the result.
- Nothing an account run starts inherits the MDM's output. Its output goes only to root's pipe. Each
  account has a time limit enforced by root with a background timer (macOS has no `timeout`); at the
  limit root kills the run's process group, stops reading, reports the account as partly checked and
  moves on, so a read stuck on a network home cannot hold up the others or the MDM. A process that
  survives the kill is reported. The whole run aims to finish before a deadline below the MDM's own
  timeout, set by a flag each MDM page gives.
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
because any account can create files there. What phase 1 checks of these is under "As built".

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
- `outcome` is the worst of `failed`, `act`, `not_checked`, `review`, `clear`, in that order, so a
  finding to act on is never hidden by a partial check, and a partial check never reads as clear.
- The summary line is `blindspot <outcome> accounts=<n> act=<n> review=<n> not_checked=<n>
  v=<script version> at=<UTC time>`.
- The inventory value is a compact form of the whole result, one line, short enough for an MDM's
  inventory field (each MDM page gives that MDM's limit), with no path, file name or key:
  `v1 act 2026-10-25T09:12Z | asha: act tanstack; run-without-asking claude-code; keys 2
  anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear`. If it would not fit, it keeps the
  outcome and the accounts' outcomes and ends with `+more`; the full result is in the saved file.
- The inventory script an MDM runs at check-in only reads the saved file, never scans, and reports
  `stale` when the last run is older than the age the admin sets (default 3 days), so a scan that
  stopped running never shows an old `clear`.
- The saved file is `/var/db/blindspot/last.json`. The folder must be a real folder owned by root,
  mode 0700, or root recreates it; the file is written to a temporary name and renamed into place.

### Exit codes

New codes, clear of the ones the script already uses (1 when HOME is not set, which `--all-users` does
not need; 2 for an unknown option; 130 when interrupted): 0 `clear`, 10 `act`, 11 `review`, 12
`not_checked`, 13 `failed`. With `--exit-zero`, a finished run exits 0 and only `failed` exits 13. An
MDM that stops the script on its own timeout gets no code, so each page treats a missing summary, or
any code it does not expect, as not checked.

## A person checking it in Terminal

An admin trying it on one Mac (`sudo bash gird-check.sh --all-users`, with a terminal) gets a
readable report per account, in Blindspot's usual style, then where the result was saved:

```
  This Mac: 2 accounts checked

  asha                                        act now
    x  TanStack worm, May 2026: stole cloud, GitHub, npm and SSH credentials
    !  Claude Code set to run commands without asking
    x  Keys in plain text: 2 files (Anthropic, AWS)
    x  Keys in agent sessions: 3 files
    !  1 SSH key without a passphrase

  itadmin                                     nothing found

  Saved: /var/db/blindspot/last.json
```

No path or file name: to see which files, the person runs Blindspot on their own account. After the
report, once, a short note on Argus, using only what gird.ai/argus says:

```
  This is one Mac, checked once. Argus shows every AI agent on every Mac as it
  runs, who owns it and what it may reach. Roll it out through the MDM you
  already use: gird.ai/argus
```

(after a clean run the first sentence is "Nothing found on this Mac today."). Nothing about Argus is
printed in a run without a terminal, or in the summary line or inventory value an MDM reads. The
saved JSON has one `learn_more` field with the link.

## The admin guide

`docs/fleet.md` is steps in order, each short:

1. Try it on your own Mac: download, check the SHA-256, run it with `sudo`, read the report.
2. Grant Full Disk Access to your MDM's agent (the page for your MDM has the profile settings).
3. Add it to your MDM: the script, a schedule (daily suggested), and the inventory field.
4. Read the results: what `act`, `review`, `not_checked`, `stale` and `clear` mean, and how to list
   the Macs to deal with first.
5. Act on a finding: what to ask the person to do, finding by finding.
6. Update or remove it.

Each MDM page ends with a short "Seeing all your Macs, all the time" section about Argus.

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
- Not measured: how the real `sudo` on macOS places the account run (with `use_pty` it may run the
  command in a group or session of its own, out of reach of root's kill of the process group). A run
  that leaves the group is caught only when it still holds root's pipe open, which root then reports
  as a process left running; one that let go of the pipe is not seen.
- A run as `bash /dev/fd/0 < gird-check.sh` reads its own source from a path that is not the file;
  it is not refused by name, and is left to the "run it from a file" and ownership checks.
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

## As built

- `--json`, `--summary-to-stdout`, `--exit-zero`, `--list`, `--hash-accounts` and `--deadline` work
  with `--all-users` only; elsewhere they exit 2. A run with neither `--json` nor
  `--summary-to-stdout` prints the readable report, with the Argus note only on a terminal.
- `--deadline` is 3000 seconds when not given, and the run aims to finish before it. Each account
  gets an equal share of the time left, less the 3 seconds a stop takes, so one stuck account spends
  only its own share. A tenth of the deadline, at most 10 seconds, is kept in reserve for the steps
  outside the shares (the home folder checks, the machine check, saving), which can still overrun it
  slightly.
- The inventory reader is the script itself: `--inventory` (root only) prints the saved inventory
  value, `stale: last run <time>` past `--stale-days` (3 by default), `none` before the first run
  and `unreadable` when the saved file is not root's own 0600 file in a 0700 folder.
  `--result-tags` wraps it for Jamf Pro.
- Deployment: the MDM installs the script once at `/Library/Application Support/Blindspot/gird-check.sh`
  (folder and file `root:wheel` 0755), with the options in one line that starts its second line,
  `case "${1:-}" in --account-run|--inventory) ;; *) set -- <options> ;; esac`, so the account runs it
  starts and an `--inventory` call keep their own. The MDM's daily item and its inventory field only
  `exec` that file, with no options or secret on their own line. The install step is untested on a
  real Mac.
- `review` means something to change or confirm, not urgent. It covers a tool with a security fix and an incident at the update level, and also an agent set to run without asking, an SSH key without a passphrase, a
  platform that leaked stored secrets and a leftover file that can come from malware; `act` also
  covers keys in shell history, MCP configs and Claude Code allow lists, links to
  `authorized_keys` and files a worm plants. An account with a protected folder refused, a file not
  read or agent sessions not all checked is partly checked: `act` if it found something to act on,
  otherwise `not_checked`.
- The size limit for a file an account run reads is 16 MB; session files are read in 1 MB pieces at
  any size. Root reads at most 4096 bytes of an
  account run's output. Apps in `/Applications` and agent commands in `/usr/local/bin` and
  `/opt/homebrew/bin` are the machine's agents, found by path.
- What root checks for the Mac in phase 1: apps in `/Applications` and agent commands in
  `/usr/local/bin` and `/opt/homebrew/bin`, by name; in the shared temp folder, the malware markers
  `data/indicators.tsv` lists there, by name; whether a process holds the LiteLLM loader's lock file
  open (`lsof`), the only running process it looks at; and any startup file `data/indicators.tsv`
  lists outside a home folder, of which macOS has none today. Startup items in shared folders and
  other running processes are not checked yet.
- With none of the protected folders it tries (Safari, Mail, Messages) in a home, an account run
  counts its protected folders as checked: there is nothing protected to miss.
- `--all-users` needs to run from a file, since each account runs a copy of it; from standard input
  it stops with a message. The copy leaves out an MDM's options line, which can carry the
  `--hash-accounts` secret. The result's `script` field and the summary's `v=` are the release
  version from the script's header, found in its first five lines. Root refuses to start (exit 13)
  unless the script and every folder above it are owned by root and writable by no one else.
- An account run stopped at its time limit can leave its temp files in `/tmp`: root does not know
  their names. Moved-aside saved-result folders stay until removed (`docs/fleet.md`, step 6).
- A saved-result folder that is a link, not a folder, or not root's with mode 0700 is moved aside to
  `/var/db/blindspot.replaced-<time>-<pid>` and made again, so root never deletes a tree it did not
  make.
- The tests stand in for root, dscl and sudo with `GIRD_CHECK_FLEET_*` settings that the script
  reads only when it is not running as root; as root they are unset before anything else runs.
