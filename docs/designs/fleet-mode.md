# Fleet mode: running Blindspot from an MDM

Status: built for macOS (phase 1), as `gird-fleet.sh --all-users`, with the admin quick start in
`docs/fleet.md`, the rest in `docs/fleet-reference.md`, and the MDM pages in `docs/mdm/` (each marked untested until run end to end on a real
Mac). Linux is phase 2: until then `--all-users` on Linux exits 13 with a message. Windows is
built as `gird-fleet.ps1` and `blindspot-fleet.ps1`, under "Windows" below; `gird-intune.ps1`, the
admin's tool for Intune, is not built yet. What the macOS build adds to this design, or settles where
it was open, is under "As built" at the end. A Mac is set up with one file, `blindspot-fleet.sh`,
as "macOS: one file for the MDM" says; "As built" describes the two-file install it replaces.

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
6. A guide for admins, `docs/fleet.md` (a quick start) with `docs/fleet-reference.md`, and one page
   per MDM in `docs/mdm/`.

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
  HOME=<home> GIRD_CHECK_ACCOUNT_SECONDS=<its share> /bin/bash <copy> --account-run
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
  limit: the session check reads them whatever their size, with the system's perl (in 1 MB pieces)
  or with a ripgrep only root can change (see "As built").
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
processes. Any account can create files in the shared temp folder, and hard-link any file it can
reach there, so a malware marker there is only a possible sign: for the Mac when root owns it, on an
account's row when that account owns it. Shared install
folders an account's check reads (npm's global folders outside the home, shared Python, Cursor's
version in `/Applications`) show on every account's row. What phase 1 checks of these is under
"As built".

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
      "agents_run_remote_commands": ["codex"],
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
- `agents_run_remote_commands` lists the agents with a saved rule that lets them run commands on
  other machines without asking (`data/remote-commands.tsv`), in the inventory value as
  `remote-commands <ids>`.
- `outcome` is the worst of `failed`, `act`, `not_checked`, `review`, `clear`, in that order, so a
  finding to act on is never hidden by a partial check, and a partial check never reads as clear.
- The summary line is `blindspot <outcome> accounts=<n> act=<n> review=<n> not_checked=<n>
  v=<script version> at=<UTC time>`.
- The inventory value is a compact form of the whole result, one line, short enough for an MDM's
  inventory field (each MDM page gives that MDM's limit), with no path, file name or key:
  `v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; run-without-asking claude-code; keys 2
  anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear`. Its parts, as both writers produce
  them, in this order:
  - `v1 <outcome> <YYYY-MM-DDTHH:MMZ>`, and on Windows ` other_profiles=<n>`, then for `failed`
    ` reason=<why>`.
  - The account rows, ` | <name>: <outcome>` and the account's findings, or the word that says why
    it was not checked. A Mac lists every account, a PC the signed-in one.
  - The machine's own row when its outcome is not `clear`: ` | machine: <act|review|not_checked>`,
    then ` incidents <ids>`, `; possible <ids>` and, on a Mac, `; tmp-wiper`, each when it has one.
    The PC writes `machine: not_checked` when a marker's owner can't be read and no finding makes it
    `act`, and the Mac when a check of its own did not answer in time or a lock holder's account
    can't be read.
  - On a Mac, ` | old-install` while the two-file install is still there.
  - On a Mac, ` | no accounts` when it has no account to check, always last.
  - ` +more` when anything was cut.

  If it would not fit, it keeps the outcome, `old-install` and `no accounts`, then chooses the rows
  by need (act, not_checked, review, then as many clear ones as fit, the machine's row before an
  account at the same level), and writes them in the order above. Details go before rows: an account
  whose details don't fit keeps its outcome, an `act` one its `wiper` and `incidents` too, and the
  machine's row drops its last parts first, never leaving a `;` at its end. It ends with `+more`;
  the full result is in the saved file.
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

An admin trying it on one Mac (`sudo bash gird-fleet.sh --all-users`, with a terminal) gets a
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

`docs/fleet.md` is a one-screen quick start:

1. What it does and the security facts an admin needs before deploying (runs as root, reads, sends
   nothing, the result readable by root only).
2. What you get: an example inventory line, one line per outcome, and the Macs to deal with first.
3. The steps: install once, run daily, show the result in the inventory field.

`docs/fleet-reference.md` has the rest: the agent review prompt, trying it on your own Mac, Full Disk
Access, how the install works, ripgrep, the deadline, the options, the full outcome definitions, what
to ask the person to do finding by finding, what each account's check reads, files that can be left
behind, and how to update or remove it.

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

## macOS: one file for the MDM

For IT teams that manage Macs, and for engineers changing `gird-fleet.sh` or `tools/gen.sh`. Built
as described here; revised after a review that found three majors in the first draft (the start
reopened itself by a name bash could look up, the here-document's temporary file was said to follow
`TMPDIR`, and `--hash-accounts` had nowhere safe to live), and again after a review of the build
(bash took functions and settings from the MDM's environment before the first line, the removal
command for leftover work folders matched anyone's, and a stale size threshold).

`blindspot-fleet.sh` is the one file an IT admin gives the MDM for a Mac. The MDM runs it as root,
once a day, with no arguments and nothing to edit. It checks every account and prints one summary
line. There is nothing to install first: no folder, no second file, no options line. A mistake in it
is a root mistake on every Mac in a company, so its start is the part reviewed hardest.

`tools/gen.sh` builds it for each release from `gird-fleet.sh` and a copy of `gird-check.sh` without
its game. It is not checked in. The copy sits after the file's last line as plain text, so whoever
reviews the file reads exactly the code each account runs.

### What the admin does

Downloading the file and checking its SHA-256 is step 1 for every MDM. Full Disk Access for the MDM's
agent stays as it is and is not counted.

**Jamf Pro**, 4 steps (8 before):

1. Download `blindspot-fleet.sh` from a release and check its SHA-256.
2. **Settings** > **Scripts** > **New**: name it `Blindspot`, paste the file into **Script**, save.
3. **Computers** > **Policies** > **New**: trigger **Recurring Check-in**, frequency **Once every
   day**, add the `Blindspot` script, choose the Macs, save.
4. **Settings** > **Extension attributes** > **New**: name it `Blindspot`, type **String**, input
   **Script**, paste the reader lines (`docs/fleet.md`, step 3) with Jamf's last line, save.

**Iru**, 2 steps (5 before):

1. Download the file and check its SHA-256.
2. Add a Custom Script named `Blindspot`, **Run daily**, with the file as its **Audit Script** and
   no remediation script. Its output, kept by Iru, is the summary line.

**Microsoft Intune**, 3 steps (6 before):

1. Download the file and check its SHA-256.
2. **Devices** > **macOS** > **Scripts** > **Add**: upload the file, **Run script as signed-in user**
   **No**, frequency daily.
3. **Custom attributes for macOS** > **Add**: type **String**, with the reader lines saved as a file.

**ManageEngine Endpoint Central** has no page yet. Its Mac custom script takes a script and the exit
codes that mean success, so the one file fits it as it fits the others; a page follows a run on a
real Mac.

Updating is replacing the file in the MDM's item with the next release. Removing is deleting the
MDM's items, then one command on each Mac:
`sudo /bin/rm -rf /var/db/blindspot /var/db/blindspot.replaced-* "/Library/Application Support/Blindspot"`
(the saved result, the copy kept for the inventory field, saved-result folders moved aside, and
ripgrep if it was installed). Root's work folders a killed run leaves in `/private/tmp` are removed
by the `find` command in `docs/fleet.md`, step 6, which picks only folders root owns, at depth 1,
named exactly as `mktemp` names them (each prefix and 8 characters), and never follows a link.

### What is inside

1. Line 1 is `#!/bin/bash -p`, never `#!/usr/bin/env bash`, in `gird-fleet.sh` too. An MDM that
   starts a file by its first line would otherwise have `env` look for `bash` on the MDM's PATH, where
   a copy in `/usr/local/bin` or `/opt/homebrew/bin` belongs to whoever installed it, and run that copy
   as root. `-p` is step 1 of the start.
2. `gird-fleet.sh`, unchanged apart from its two packed blocks.
3. The `packed-sha` block, near the top: `FL_PACKED_SHA='<SHA-256 of the copy>'`.
4. The `packed-check` block, after the file's last line of code (`exit $?`): the marker line,
   `gird-check.sh` without its game byte for byte, and the closing marker, which is the file's last
   line. bash reads a script as it runs it and stops at `exit`, so it never parses these lines as
   part of the file. `tools/gen.sh` refuses a copy that holds a `packed-` marker line.

In `gird-fleet.sh` both blocks are empty. With `FL_PACKED_SHA` empty, `gird-fleet.sh` copies
`gird-check.sh` from next to it, checked as below, for development and the test suites. Everything
else is code in `gird-fleet.sh`, the same in both.

How the copy reaches the disk: the file's own copy (step 4 of the start) is read with `/usr/bin/awk`,
which writes the lines between the markers into the start's folder, which only root can open. No
here-document is used, so no temporary file is made in a shared folder. (The first draft used a
quoted here-document and said `TMPDIR` moves its temporary file. On `/bin/bash` 3.2.57 it does not:
the file goes to `/private/var/tmp/sh-thd-*`, a sticky folder, created by root alone; the SHA-256
check would still have caught a changed copy.)

What the SHA-256 proves: that the copy written out is the one `tools/gen.sh` built, byte for byte. It
does not prove the file is authentic, because the same file carries both the copy and its SHA-256:
anyone who changes one can change the other. Authenticity comes from the admin checking the
published file's SHA-256 before uploading it to the MDM.

### How a run starts

In this order, before anything else:

1. **Started with `-p`.** Without `-p`, bash takes four things from its environment before the file's
   first line can act:
   - `BASH_FUNC_<name>%%`: a function that stands in for any command of that name but the special
     builtins: `declare`, `export`, `[` or `printf`, so the file's own commands run someone else's
     code;
   - `BASH_ENV`: a file bash runs before the first line;
   - `SHELLOPTS`: options turned on from the start, such as `xtrace`;
   - `PS4`: with `xtrace` on, expanded before each command, so a `$(...)` in it runs.

   With `-p`, bash ignores `BASH_FUNC_<name>%%`, `BASH_ENV` and `SHELLOPTS`, and imports no function
   (measured on `/bin/bash` 3.2.57). It still reads `PS4` from the environment, which runs only if `-x`
   is on the command line; the documented commands never use `-x`. The file's first lines check
   that it was started so, using only an assignment, `case` and special builtins: `POSIXLY_CORRECT=1`
   makes bash find the special builtins `set`, `unset` and `exit` before any function; `set` turns off
   `xtrace`, `verbose`, `keyword`, `allexport`, `errexit`, `nounset`, `noglob`, `noclobber`,
   `errtrace` and `functrace` (`set +xvkaeufCET`), not every option `SHELLOPTS` can turn on: `monitor`, `physical`,
   `histexpand`, `pipefail` and `posix` survive this stage, which is harmless because stage 2 starts
   clean with `env -i /bin/bash -p`; `unset -f declare`, then `declare -F` must
   print nothing, `$-` must hold `p` and must not hold `x`. `$-` alone is not enough:
   `SHELLOPTS=privileged` puts `p` in it while the functions are still imported, and only a real
   `-p` start imports none. Otherwise it runs `unset -f printf`, prints why, and exits 13.

   Why it refuses rather than carry on or start itself again: Intune's guide requires a script to
   start with `#!` and a shell, Iru's lets a script name its shell, and Jamf's writes its scripts with
   one, so an MDM that starts the file by its first line loses nothing, and one that runs
   `bash <file>` gets a plain failure, not a run nobody can vouch for. Starting itself again with `-p`
   would reopen the file by its path before any check, which the first review rejected.

   What happens when an MDM starts it without `-p`: it usually stops (exit 13). A run whose environment sets
   `SHELLOPTS=privileged` and imports no function goes on normally, which is safe because nothing
   foreign is loaded. `SHELLOPTS=noexec` or `onecmd` makes bash exit 0 without running the script, and
   nothing is recorded. What remains: whatever `BASH_ENV`, or `PS4` with
   `SHELLOPTS=xtrace`, names has already run as root by the time the first line can act, and no script
   can stop that. The file then runs nothing of its own: no imported function is ever called, so
   `BASH_FUNC_*` runs nothing. The refusal is not recorded in `/var/db/blindspot`,
   because recording needs commands that are not yet safe to call: the MDM keeps the exit code and
   message. Only root and the MDM set that environment; no account can.
2. **A fixed PATH and full-path tools.** `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `BASH_ENV`, `ENV`,
   `CDPATH`, `GLOBIGNORE` and `TMPDIR` unset, `IFS` and `umask 077` set. Every tool from here on is
   named by its full path. Jamf Pro's three arguments are dropped here (see Arguments), and a Mac
   that is not macOS stops here (exit 13).
3. **The file's own path, from `BASH_SOURCE`.** bash sets `BASH_SOURCE` to the file it reads. Empty,
   it read standard input or `bash -c`; with no `/`, bash may have found the name in the current
   folder or on PATH. Either is refused, exit 13, with a plain message. The path is made absolute
   with `cd -P` and `/bin/pwd -P` in a subshell; a link is refused.
4. **The ownership check** on that absolute path and every folder above it: `owned_only` with
   `sticky` (below). In `gird-fleet.sh`, `gird-check.sh` next to it too. A failure stops the run
   (exit 13) and names the first path, from `/` down, that failed.
5. **The copy.** `/usr/bin/mktemp -d /private/tmp/blindspot-run.XXXXXXXX` makes a new folder, root's,
   mode 0700. The file's SHA-256 is read, the file is copied in (mode 0600), and the copy's SHA-256
   must equal it, or the run stops (exit 13) and the folder is removed.
6. **The copy, started again.** `exec /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin
   BLINDSPOT_STAGE=<folder> /bin/bash -p <folder>/blindspot-fleet.sh <arguments>`. `/bin/bash` by its
   full path, never a name, and with `-p`, which the copy's step 1 checks too. A test run (not root) also passes its `GIRD_CHECK_*` settings on.

The first draft started with `exec /usr/bin/env -i ... /bin/bash "$0"` before any check. Run from
standard input or with `-c`, `$0` is `sh` or `bash`, and bash then looks for a script of that name in
the current folder and on a default PATH that includes `/usr/local/bin` and `.`: a reviewer planted a
file named `bash` and it ran as root. Reopening by name also gave a swapped file its chance. Now
nothing runs before the checks, and what runs after them is a copy no one else can change.

**The copy's own checks.** With `BLINDSPOT_STAGE` set, the file runs only if that folder's name is
`/private/tmp/blindspot-run.` and eight characters, it is not a link, it is root's with mode 0700,
`BASH_SOURCE` is `blindspot-fleet.sh` in it, root's with mode 0600, and the ownership walk passes. A
`BLINDSPOT_STAGE` carried in from an MDM's environment therefore stops the run rather than skip the
copy. Once the folder's name, owner and mode check out and `BASH_SOURCE` is in it, the folder is
removed however the run ends, a refusal at the copy's remaining checks included; before that, the
folder may not be the start's, so it is left alone. Everything after, the check each account runs, the version, and the copy kept for the inventory
reader, comes from this copy. The folder is removed when the run ends.

**A root-owned sticky folder above the file.** `owned_only UID PATH sticky` accepts a folder root owns
with mode exactly 1777 (`/private/tmp`); the mode is read in full (`%Mp%03Lp`), since `%03Lp` alone
drops the sticky bit. It is sound only because of the copy: in a sticky folder another account
cannot write, rename, unlink or replace a file root owns, so the file root checked is the file root
copies, and from then on bash reads the copy, in a folder no one else can open. Any other folder that
others can write to, a sticky folder another account owns, and a file with mode 1777 are refused. The
link count is not checked: an account can hard-link root's file in a shared folder, but the link
changes nothing in it.

**Arguments.** Jamf Pro sends every script three arguments first, the mount point, the computer
name and the user name, which may be empty
([Jamf's Scripting 201 guide](https://resources.jamf.com/documents/white_papers/apple-scripting-201.pdf)),
and the options the admin may add in parameters 4 to 11. When the first argument is `/` and there
are at least three, exactly three are dropped; then empty arguments are dropped. With none left, the
file runs the MDM defaults: `--all-users --exit-zero --summary-to-stdout --deadline=3000`. It does not
guess from a terminal: an admin trying it by hand types `--all-users` for the readable report. Any
other options are taken exactly as given, and a word it does not take is refused (exit 2) with a plain
message that repeats the word up to any `=`, never a value.

**A refusal is recorded.** A run refused before it checks anything writes
`/var/db/blindspot/refused`, root's 0600 file in root's 0700 folder: one line,
`refused <time>: <reason>`, from a fixed set of reasons with no path, and its time in seconds. The
inventory reads `failed: refused <time>: <reason>` while that is newer than the last result, and the
next finished run removes it. A run that only reads (`--inventory`, `--list`, `--help`) records
nothing, and a run that is not root cannot.

**`--hash-accounts`: a root-only file, never an argument.** An MDM parameter puts the secret in root's
process arguments, which every account can read with `ps` while the run lasts, and in the MDM's logs.
So `--hash-accounts` as an argument is refused (exit 2), and the secret is read only from
`/var/db/blindspot/hash-key`: a regular file, not a link, root's with mode 0600, in the saved-result
folder (root's, 0700), passing the ownership walk without `sticky`, at most 200 bytes and exactly one line of
`A-Z a-z 0-9 . _ ~ + / = -`, with or without a final newline: the whole file is read, so a second
line, with or without its own newline, a carriage return or an empty file is refused, never cut. A `hash-key` that fails any of these stops the run (exit 13): showing the
names an admin meant to hide would be worse than no result. Chosen over leaving the feature out
because the saved-result folder is already root's alone and checked on every run, the checks are the
ones the rest of the start uses, and admins who hash names today keep doing so.

**What differs by OS.** Each platform call sits in one small function: `oo_mode` (owner and full
mode) and `oo_acl_open` (an ACL entry that lets anyone write) in the ownership walk, and `fl_um`,
`fl_ul`, `fl_size` and `fl_sha256` in `gird-fleet.sh`, with the paths `FL_TMPROOT`, `FL_STATE` and
`FL_OLD` as constants. They use macOS's `stat -f`, `ls -le` and `shasum`. A Linux fleet mode would add
its own versions of these (`stat -c`, `getfacl`, `sha256sum`); it is not built, and on Linux the file
exits 13 at step 2, before any of them runs.

### The safety rules, one by one

| Rule | How |
|---|---|
| Nothing taken from the environment before the first line | `-p` on line 1 and on the exec, checked in step 1. |
| A fixed PATH before the first command | Step 2. |
| Every tool by its full path | Also line 1 (`/bin/bash -p`), the exec (`/usr/bin/env`, `/bin/bash`), the copy out (`/usr/bin/awk`) and the SHA-256 (`/usr/bin/shasum` under `env -i`, so no `PERL5OPT` reaches it). |
| `env -i` before the work starts | Step 6, after the checks. |
| Its own file and every folder above it root's alone | Step 4, plus the sticky rule, because of step 5. |
| Run from a file, never standard input or `-c` | Step 3. |
| Never trust a file an account could change | The copy in step 5; the check's copy written from it into the same folder. |
| The copy each account runs in a new root-owned folder, checked before each start | As before, plus its SHA-256 before each start. |
| Test-only `GIRD_CHECK_*` settings ignored as root | Unchanged; the exec passes them on only when not root. |
| The copy emptied and given away before it is deleted | Unchanged. |
| No secret in an argument | `--hash-accounts` refused; the secret lives in a root-only file. |

### Where each MDM puts the file

No vendor documents where it writes the script, or its owner:

| MDM | Where the script is written, and its owner | Source |
|---|---|---|
| Jamf Pro | Not in Jamf's documentation. Commonly reported as `/Library/Application Support/JAMF/tmp/`; owner not reported. | [Adding a Script](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Adding_a_Script_to_Jamf_Pro) |
| Iru | Not documented. The guide says only that custom scripts always run as root. | [Custom Scripts](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview) |
| Microsoft Intune | Not documented. Scripts run as root unless set to run as the signed-in user. | [Shell scripts on macOS](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos) |
| ManageEngine Endpoint Central | Not documented, nor the account it runs as. | [Custom scripts for computers](https://www.manageengine.com/products/desktop-central/help/mac_configurations/executing_custom_scripts_for_computer.html) |

A folder private to an MDM agent that runs as root passes, and so does a root-owned file directly in
`/private/tmp`. A script handed over on standard input or with `-c` is refused. The refusal names the
path that failed and is recorded, so the first run on each MDM shows what it does. Until each has run
on a real Mac, its page stays marked untested.

### Size

Each MDM's own limit on a script, from its documentation, checked 18 November 2026:

| MDM | Limit | Source |
|---|---|---|
| Microsoft Intune (macOS) | "The script file must be less than 1 MB in size." A custom attribute's result: 20 KB or less. | [Shell scripts on macOS](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos) |
| Jamf Pro | Not stated. | [Adding a Script](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Adding_a_Script_to_Jamf_Pro) |
| Iru | Not stated. | [Custom Scripts](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview) |
| ManageEngine Endpoint Central | Not stated. | [Custom scripts for computers](https://www.manageengine.com/products/desktop-central/help/mac_configurations/executing_custom_scripts_for_computer.html) |

The tightest stated limit is Intune's, read as 1,000,000 bytes. Keeping 20% for growth means at most
800,000 bytes.

Measured on this branch, in bytes, on macOS 26.5. Compressed with `/usr/bin/gzip -9 -n`,
`/usr/bin/bzip2 -9`, xz at level 9 through `/usr/bin/tar -cJ` (one file in a tar archive) and lzma
through `/usr/bin/compression_tool`, then `/usr/bin/base64` with no line breaks:

| File | Plain | gzip + base64 | bzip2 + base64 | xz + base64 | lzma + base64 |
|---|---|---|---|---|---|
| `gird-check.sh` | 501,594 | 173,197 | 147,973 | 150,189 | 140,929 |
| without the game | 487,023 | 165,841 | 141,949 | 136,537 | 135,321 |
| without the game and comments | 411,524 | 127,593 | 113,769 | 109,229 | 104,113 |
| `gird-fleet.sh` | 90,692 | 32,933 | 31,653 | 40,961 | 30,385 |

The game is 14,571 bytes. The comments that can go without changing the code (see "If comments
must go") are 75,499 bytes.

`gzip`, `bzip2` and `base64` are in `/usr/bin` on every macOS. macOS has no `xz` command:
`/usr/bin/tar` (bsdtar) reads and writes `.tar.xz` through its own library, and
`/usr/bin/compression_tool` writes lzma; both are on this Mac, and the first macOS version that has
each is not established. On Linux, `gzip` and `base64` come with every distribution; `bzip2` and `xz`
often do not in minimal installs, and `compression_tool` never does.

`gird-fleet.sh` plus the copy without the game, plain, is 577,715 bytes, 58% of 1,000,000. That
leaves 222,285 bytes before the 800,000 line: about 27 branches the size of a new set of key types
(about 8 KB each).

So the copy goes in plain: no compression, no encoding, comments kept. `tools/gen.sh --check` fails
when `blindspot-fleet.sh` reaches 1,000,000 bytes and warns from 800,000 (`size_ok`, the one rule
both one-file builds follow: fail at the MDM's documented limit, warn from 80% of it). As built, the
file is 589,754 bytes, 59% of the limit; the start and the inventory copy added about 11 KB to
`gird-fleet.sh`.

### Removing the game

The game is for a person running the check by hand. Fleet mode never starts it, but its code would
ship in a file root handles, so the copy leaves it out.

In `gird-check.sh`, the whole "GIRD Runner" section, from its header to the end of `game_loop`, sits
between `# >>> game` and `# <<< game`, the block markers the data blocks use. So the rest still runs
without it:

- `GAME_PID=""; KEYS_PID=""; GAME_RC=0; SAVED_TTY=""` sit above the block. `cleanup` and the end of
  the scan read them, and empty they mean no game.
- A default `game_start() { return 1; }` sits above the block. Inside it, `game_start` is defined
  again: it sets `G_MODE` (which was a top-level line), checks `game_ok`, and starts the game as the
  scan's start did. The scan's start is `game_start || spin_start "Checking your agents, configs and
  keys"`.
- `read_key` and `drain_keys` stay outside: the end menu uses them. Nothing else calls into the game.
- The end of the scan is unchanged: with `GAME_PID` empty it stops the spinner, and `GP` and `GB`
  stay 0.
- `--no-game` stays accepted, and the header keeps its line: `--help` prints the header and root
  reads the version from it.
- `tools/gen.sh` refuses a second game block, an unclosed one, and another `# >>> ` block inside it.
- `tests/made-up.sh`, which checks that new data changes only generated blocks, compares the game
  block's lines too: it is code, not a generated block.

The copy is `gird-check.sh` with the lines from `# >>> game` to `# <<< game` deleted, and nothing
else changed. Anyone can print the SHA-256 the file carries from the published `gird-check.sh`:

```
/usr/bin/sed '/^# >>> game$/,/^# <<< game$/d' gird-check.sh | /usr/bin/shasum -a 256
```

The proof that the copy behaves the same, in `tests/run.sh`:

1. The copy is `gird-check.sh` minus exactly the block's lines, byte for byte.
2. `/bin/bash -n` passes on it.
3. No function defined in the block is named in the copy, but the default `game_start`.
4. bash's own reprint: each file is wrapped in a function, read by `/bin/bash` and printed with
   `declare -f`, which prints the code bash parsed without comments. The original's reprint is the
   copy's with the block's reprint inserted at one place, and nothing else different.
5. `--account-run` prints the same lines from both for a suite fixture.
6. `--offline --full` prints the same report from both, with no terminal and `NO_COLOR=1`.
7. `tests/interactive.sh` still drives the game in `gird-check.sh`.

### If comments must go

Not needed at 58% of the limit. If the file nears 800,000 bytes, this is the way to make it smaller
that keeps it readable.

bash has no parser a script can call, but it prints what it parsed. The method:

1. Delete only lines whose first character that is not a space is `#`, and blank lines. Keep line 1
   and the header up to its first blank line.
2. Wrap the original and the result each in a function, read both with `/bin/bash`, print both
   with `declare -f`, and compare. Equal output means bash parsed the same code: the reprint keeps
   strings, here-documents and every command, and drops only comments.
3. A deleted line that was inside a quoted string or a here-document changes the reprint. Such
   lines are kept: an awk program in single quotes has `#` comments of its own. In
   `gird-check.sh` without the game, 74 lines are of that kind. Keeping them, the two reprints are
   identical on `/bin/bash` 3.2.57, and the result is 411,524 bytes. A build whose reprints differ
   is refused.
4. Then the output comparisons above, on the stripped copy.

What it cannot prove: anything that reads the file's own text (the header for `--help` and the
version, both kept); the line numbers in bash's error messages, which an account run sends nowhere;
a construct bash's reprint leaves out, since both sides are printed by the same bash and would lose
it alike; and how another bash parses it, unless the comparison runs on that bash too.

If even that is not enough, the order is: this stripping first, then compression with `gzip` and
`base64`, which every macOS and Linux has. A security team's review asks about encoded blobs, and a
compressed copy needs a command to read where a plain one needs none. A download with a hash check,
which this design allows where an MDM limits size, comes last: it is a network request at every
install, and the MDM pages would differ.

### One file, three uses

| Use | How it starts | What it does |
|---|---|---|
| The daily check | The MDM runs the file, with no arguments (Jamf adds its three). | Checks every account, saves the result, keeps a copy of itself for the inventory reader, prints the summary line, exits 0 unless the run `failed` (13). |
| The inventory field | Jamf's extension attribute and Intune's custom attribute each run lines they hold. | The reader lines below run the kept copy with `--inventory`. |
| An admin trying it | `sudo /usr/bin/install -o root -g wheel -m 0700 blindspot-fleet.sh /var/root/`, then `sudo /bin/bash -p /var/root/blindspot-fleet.sh --all-users`. | The readable report for every account. `--all-users --list` shows who would be checked. |

The copy kept for the inventory field is `/var/db/blindspot/blindspot-fleet.sh`, root's 0700 file in
root's 0700 folder, written from the run's own copy to a temporary name, compared with `cmp` and
renamed, after the result is saved, and only when it differs.

The reader lines, the same for every release (`docs/fleet.md`, step 3), are a function,
`blindspot_inventory`: `none` when `/var/db/blindspot` does not exist; `unreadable` when the reader
cannot open it, as when an MDM runs them as another account, never `none`; the kept copy's
`--inventory` when there is one, or `unreadable` when that fails; `failed: ` and the recorded refusal
when a run was refused before any run finished; `old-install: the saved result is from an earlier
release` when only the two-file install's `last.json` is there, which a one-file run that saved but
could not keep its copy, or a killed first run on a Mac with an old install, also leaves; `failed: the run started <time> did
not finish or could not save its result` when the first run's `attempt` is older than its deadline
(`unreadable` when that file is not two numbers); `none` otherwise, a first run still under way
included. The reader starts the kept copy with `/bin/bash -p` and starts with `#!/bin/bash -p`. Jamf's last line wraps the function's
output in `<result>` tags. Iru has no inventory field: the daily check's output is the result.

**An older two-file install.** When `/Library/Application Support/Blindspot` still holds
`gird-fleet.sh` or `gird-check.sh`, the result says so: `"old_install": true` in the JSON,
`old_install=yes` at the end of the summary line, `old-install` in the inventory value, and a line in
the readable report. `docs/fleet.md` gives the steps, removing the old daily item first.

### Parity

**Windows.** `blindspot-fleet.ps1` is the same idea: one file, built by `tools/gen.sh` at release,
not checked in, carrying the check and its SHA-256, checked before each start, and refused by
`--check` when edited. Both builds follow one size rule, `size_ok` in `tools/gen.sh`: fail at the
MDM's documented limit, warn from 80% of it. It differs where the platforms differ:

- It strips comments and compresses, because Intune takes a Windows script of under 200 KB. A Mac
  script may be under 1 MB, so the Mac copy stays plain.
- It has no game to cut: only `gird-check.sh` has one.
- It unpacks into the person's own profile, because it runs as the person. The Mac file copies
  itself into a folder only root can open, because it runs as root and starts each account through
  `sudo`.
- It prints the inventory value on every run and has no `--inventory`. A Mac's inventory field runs
  apart from the check, so the Mac file keeps a copy for it.
- It starts the check with `-NoProfile`. The Mac file starts its copy under `env -i`, and drops
  Jamf's three arguments, which Windows MDMs do not send.

**Linux.** Fleet mode does not exist on Linux yet; the file exits 13 there with the message
`gird-fleet.sh` gives today, before the ownership walk. The platform calls sit in the small functions
listed under "What differs by OS", so a Linux version adds its own; line 1 is `/bin/bash`, which the
common distributions have, and the copy is written out with `awk`. Linux fleet mode itself is not
designed here.

### One home in `tools/gen.sh`

Shared by both one-file builds: `splice`, `sha` and `size_ok`. bash only: cutting the game block,
refusing a nested block or a `packed-` marker in the copy, the two packed blocks, and its own "what
does it unpack to" (the same `awk` as `fl_unpack`). PowerShell only: `tools/strip-comments.ps1`, gzip
and base64. `tools/gen.sh` builds `blindspot-fleet.sh` before `blindspot-fleet.ps1`, so it is built
even where PowerShell is missing (exit 3). With `--check`, a `blindspot-fleet.sh` here must be what
it builds. `.gitignore` lists both.

### Tests

In `tests/run.sh`, under "fleet mode: one file for the MDM", each with a line in
`tests/bash-only.txt`. Root is stood in for as the other fleet tests do (`GIRD_CHECK_FLEET_ROOT`,
the users file, `tests/fleet-launch.sh` for `sudo`), with the account running the tests as owner.

- The build: under 1,000,000 bytes and `#!/bin/bash -p` first; its copy is `gird-check.sh` without the
  game block with that SHA-256; outside its two blocks it is `gird-fleet.sh`; a hand-edited copy or
  SHA-256 fails `--check`; a warning from 800,000 bytes and a failure at 1,000,000 (padded copies); a
  block inside the game block refused.
- The game proofs 2 to 6 above.
- The start: each of `BASH_FUNC_declare%%`, `BASH_FUNC_export%%`, `BASH_ENV`, `SHELLOPTS=xtrace`
  with a `PS4` that runs a command, and `SHELLOPTS=privileged` with imported functions, started with
  and without `-p`: with `-p` no code runs and the run goes on; without it the run usually stops
  (exit 13) and only `BASH_ENV` and `PS4` have run code; `SHELLOPTS=privileged` with functions is refused and
  no function runs. `bash <file>` and `sh <file>` refused. A copy refused at its own checks leaves
  no folder. Standard input, `bash -c` and a bare file name refused before any copy or exec; a `bash`
  planted in the current folder and first on PATH never runs, started by its first line or by
  `./`; a folder or file another account can write to refused, naming it; exported functions and
  `PERL5OPT` change nothing; a root-owned sticky folder (`/private/tmp`) accepted, another account's
  sticky folder refused; a `BLINDSPOT_STAGE` carried in refused; a copy whose SHA-256 differs refused;
  a packed check whose SHA-256 differs never started.
- Arguments: none gives the summary line and exit 0 on a finding; `/ mac01 ''` and `/ mac01 asha`
  behave as none; options after Jamf's three taken as given; unknown words refused; `--hash-accounts`
  refused without repeating the secret; the `hash-key` file used; a `hash-key` that is a link, a
  fifo, mode 0644, another owner's, over 200 bytes, two lines with no final newline, holding a
  carriage return, or empty, each refused with exit 13 and no account name printed.
- The inventory: the kept copy is the file, 0700; a refused run recorded and read as `failed`, a
  later finished run read as its value; the guide's reader lines print `unreadable` for a folder they
  cannot open, `none` with no folder, the recorded refusal, `old-install` for an earlier release's
  `last.json` alone (it also reads so when a one-file run saved but could not keep its copy, and for a
  killed first run on a Mac with an old install), `failed` for a first run that stopped part-way and `none` for one under way.
- The removal command in `docs/fleet.md`, step 6, taken from the guide and pointed at a scratch
  folder: as written, it selects neither the tester's own folder of a matching name nor a link of a
  matching name to a folder root owns; with the tester standing in for root, it removes only the
  folders at depth 1 named exactly so, never a longer or shorter name, a file, a link or a folder
  one level deeper.
- An older two-file install named in the JSON, the summary line, the inventory value and the report.
- On Linux: exit 13 with the macOS-only message.
- Need root or a real MDM, so not tested here: where each MDM writes the file and whether the
  ownership rule passes there; Jamf's real arguments; whether Jamf's and Iru's script fields take
  590 KB pasted; Intune's upload of it; Full Disk Access through `sudo`; the start under a real root,
  `/private/tmp` as root's folder with root's copy in it.

### Open decisions

- Where each MDM writes the file is undocumented: run it once per MDM on a real Mac, and keep each
  page marked untested until then.
- ripgrep stays an optional, separate once-only MDM item.
- `gird-fleet.sh` with `gird-check.sh` next to it still runs: kept for development and tests; the
  guide documents only the one file.

## Windows

For IT teams that manage Windows PCs, and for engineers changing `gird-check.ps1`.

On Windows the check runs as the person who is signed in, started by the MDM in that person's own
session. It reads only what that person can already read. Nothing runs as SYSTEM, the Windows
account that runs services, and nothing needs administrator rights on the PC. The result has the
same shape and outcomes as on a Mac, so one way of reading results covers both. The exit codes
differ: see "The result" under Windows.

An admin sets it up with one command and reads every PC's result with one more. See "Microsoft
Intune" below.

### Why not every account at once

A Mac's root can start a check as any account. SYSTEM cannot start a process as another account
unless that person is signed in. Reading every home folder as SYSTEM instead would read people's
files with more rights than they have: a link swapped between checking a path and opening it is
then read with SYSTEM's rights, and a file a person holds open can block the read. So the Windows
check covers the signed-in account, and an account that is not signed in is not checked.

A PC with one person, the usual case for a work laptop, is covered in full. On a shared PC each
account gets its own result the first time its check runs after sign-in.

So a result on Windows speaks for one account, not for the PC. `clear` means that account was
checked in full and nothing was found. The result says how many other people have a profile on the
PC, so an admin can see what one run left out.

### The files

- `gird-check.ps1`, the script each person runs, gains `-AccountRun`. It prints the same fixed
  lines as `gird-check.sh --account-run`: the same keys in the same order, with numbers and names
  from the fixed lists only. Five values differ on Windows:
  - `engine` is `rg`, `dotnet` or `none`. `dotnet` reads agent sessions when the person has no
    ripgrep. The person's own ripgrep is used, as in a run by hand, because the check has only the
    person's rights.
  - `protected` is always `ok`. Windows has no folders that need a grant like Full Disk Access.
  - `moved` comes from the person's profiles, read as text and never run: PowerShell's profiles in
    Documents and in the folder Windows keeps Documents in when it was moved, the Windows
    PowerShell ISE profile, the profiles every account's PowerShell runs (Windows PowerShell's, and
    PowerShell 7's in `%ProgramFiles%\PowerShell\7` and, for a preview, `7-preview`), and the
    shell profiles in the home folder, which Git Bash runs. A PowerShell 7 installed from the
    Microsoft Store has no all-users profile: its install folder can't be written. Sources:
    Microsoft's about_Profiles, about_Windows_PowerShell_ISE and "Install PowerShell 7 on Windows".
    It is `1` when a line names a variable of `data/folder-vars.tsv` other than to read it, unless
    the line is a plain assignment (`$env:X = ...`, `${env:X} = ...`, `Set-Item env:X ...`,
    `[Environment]::SetEnvironmentVariable('X', ...)`, `export X=...`, `X=...`, fish's
    `set -x X ...`) of the value the run sees. So a form the check does not know, such as `+=`,
    `New-Item -Path Env: -Name X`, `export A=1 X=2` or `declare -x X=...`, counts as `1`. A tool's
    variable that the run does not have is seen as the folder the check reads without it. A value
    the check can't work out, such as one built by a command, counts as `1`. Each file a profile
    sources is read the same way, to any depth: `. file`, `source file`, a loop that sources
    each file of a folder, and in PowerShell `& file.ps1`, `Import-Module` of a `.ps1`, `.psm1`
    or `.psd1` file and a manifest's `RootModule`. Only an existing regular file on a local disk
    is read, as text: never a link, a network path, a device or pipe, or a cloud file not on the
    disk. At most 64 files and 16 MiB in all are read, and no file over 16 MiB, the limit the
    check keeps for profiles. A sourced file that is there but can't be followed or read, or a
    limit reached, counts as `1` only when some file read names a variable of the list: an
    ordinary setup sources completion scripts and plugins by the dozen, and one that names none of
    the variables gives no reason to think the rest moves one. This is deliberately conservative:
    the check reads profiles as text, follows the loading it understands, and when it can't follow
    something and a variable of the list is named, the account reads partly checked, never clear.
    A shell file's path with a command in it, a nested `${...}` or a zsh glob qualifier other than
    `(N)`, `(.)` and `(.N)` can't be followed. A path built from a variable of a loop or a function
    (a loop variable, a shell `local` or one set from the arguments, a PowerShell `param()` or
    `foreach` variable) is let pass only inside that loop or function, as far as the words of the
    file show where it ends; outside it, it can't be followed. A tool's own script in its own
    folder (`$NVM_DIR/nvm.sh`, the `scripts` column of `data/folder-vars.tsv`) is not read: it sets
    the tool's variable to the folder it is in, the one the check reads. Any other file in that
    folder is read. nvm's and asdf's own scripts where Homebrew installs them (`data/tool-scripts.tsv`)
    are not read either, matched only by the whole path written from Homebrew's prefix
    (`/opt/homebrew/opt/nvm/nvm.sh`, `$(brew --prefix)/opt/...`, `$HOMEBREW_PREFIX/opt/...`); a file
    with such a name anywhere else is read. A variable set to one of the folders in that file's `windows` column, the
    folders the check reads, counts as not moved; `tools/gen.sh` writes them, and gird-check.sh's
    `sh` column, into the scripts. A setting made by running a command is not seen: what a command
    prints for the shell to run (`eval "$(...)"`, `source <(...)`, `... | Invoke-Expression`), or a
    module imported by name.
  - `tmp_marks` is always empty and `tmp_wiper` always `0`. Windows has no shared `/tmp`. A marker
    in `%ProgramData%` is judged by its owner instead: see step 6 under "How a run goes".
  An account run in the reduced language prints only `language_mode=1`.
- `gird-fleet.ps1` is new. It starts the account run, checks every line it sends back, and builds
  the result. It holds every fleet option. `gird-check.ps1` holds none.
- `blindspot-fleet.ps1` is the one file an MDM runs. `tools/gen.sh` builds it for each release:
  `gird-fleet.ps1` with `gird-check.ps1` packed inside it, without its comments and compressed,
  and the SHA-256 of that copy written next to it. It is under 200 KB, the largest script Intune
  accepts. `tools/gen.sh --check` fails at 200 KB and warns from 80% of it. See "The check a
  PC runs" below.
- `gird-intune.ps1` is the admin's tool for Microsoft Intune. It runs on the admin's own PC, never
  on the fleet.

`tools/gen.sh` writes the same tables from `data/` into `gird-fleet.ps1` as into `gird-fleet.sh`,
and `--check` covers it.

### No install step

The MDM delivers `blindspot-fleet.ps1` and runs it. There is nothing to install first, so a run
needs no network and no administrator.

On each run the script unpacks `gird-check.ps1` into the person's own profile, at
`%LOCALAPPDATA%\Blindspot\<version>\gird-check.ps1`, and starts it from there. Before every start
it compares the file's SHA-256 with the one it carries, and writes the file again if they differ.
Only that person, administrators and SYSTEM can write in the profile, so a standard account on a
shared PC cannot change the code another account's check runs.

`%ProgramData%` is not used: any account can create a folder there first and keep control of it.

### The check a PC runs

The check a PC runs is `gird-check.ps1` without its comments. `blindspot-fleet.ps1` must stay under
Intune's 200 KB, and `gird-check.ps1` grows with every check. Without its comments the packed copy is
about a quarter smaller, which keeps the whole file well under that. Nothing else changes: the
header at the top of the file is kept, because `-Help` prints it and `gird-fleet.ps1` reads the
version from it, and so is any `#requires` line.

`tools/strip-comments.ps1` makes the copy. It finds comments with PowerShell's own parser, so a `#`
inside a string, a here-string or a regex is never touched. A comment at the end of a line goes,
with the spaces before it. One between two pieces of code on a line becomes a space, so the two
never join. A line left empty is dropped, unless the line before it ends with a backtick that
carries it on to the next. The copy is then parsed again, and is written only if it has no errors,
the same code word for word apart from comments and blank lines, the same structure, and the same
`#requires`. A script that is signed, or has help comments outside its header, is refused.
This check is made with the PowerShell that builds the release; a Windows-only test parses the copy
with Windows PowerShell 5.1 too and compares the SHA-256 the 5.1 command below prints.

Anyone can check that the SHA-256 `blindspot-fleet.ps1` carries (`$PackedSha`) comes from the
published `gird-check.ps1`. With both files from the same release, this prints that SHA-256:

```
pwsh -NoProfile -File tools/strip-comments.ps1 gird-check.ps1
```

On Windows PowerShell 5.1: `powershell -NoProfile -ExecutionPolicy Bypass -File
tools\strip-comments.ps1 gird-check.ps1`. Adding a second path also writes the copy there.

The SHA-256 is the same on every machine that builds it. The packed text in `$PackedCheck` may not
be: gzip programs compress the same file differently. That is why `--check` compares what it
unpacks to, not the packed text.

Building `blindspot-fleet.ps1` needs PowerShell: `tools/gen.sh` uses `pwsh` on the PATH, or
`PWSH=/path/to/pwsh`. Without it, `tools/gen.sh` still writes and checks the generated blocks,
says that `blindspot-fleet.ps1` was not built, and exits with code 3.

`gird-fleet.ps1`, the rest of `blindspot-fleet.ps1`, keeps its comments. It is the part an admin
reads in Intune before deploying it, and without them it would be about 5.8 KB smaller, 3% of the
limit.

### How a run goes

The MDM runs `blindspot-fleet.ps1` once a day, as the signed-in person, in 64-bit PowerShell.

Many MDMs start scripts in 32-bit PowerShell unless told otherwise. A 32-bit process is shown a
different `Program Files` and a different set of installed tools, so its check would miss things.
The script therefore checks that it runs as a 64-bit process, and if not, the outcome is `failed`
with `reason=host_32bit`.

A company policy can stop PowerShell from running the script at all. Then nothing is printed. As
on a Mac, a missing result, or an exit code the MDM does not expect, means not checked.

The script then:

1. Turns off everything a run with nobody watching must not do: the menu, the browser, colours,
   saving a report and every network request. It refuses `-All`, for the same reason as on a Mac.
2. Starts `gird-check.ps1 -AccountRun` as a separate Windows PowerShell process, by full path,
   with `-NoProfile`, so the person's PowerShell profile does not run. The process keeps the
   person's own environment, so a variable set there that moves an agent's folders is followed, as
   in a run by hand. One set only in a profile is not: the account is then partly checked
   (`moved`, above). The test-only `GIRD_CHECK_*` settings are removed first, as on a Mac.
3. Reads at most 4096 bytes of what the account run prints and checks each line against the fixed
   format. A line that does not fit makes the account `not_checked`. Nothing the account run
   printed, on its output or its error stream, is copied into the result or reaches the MDM.
4. Stops the check it started at the time limit, or when it prints more than it may, and nothing
   else. `-Deadline` sets the limit in seconds. It is 1500 when not given, to finish inside the
   30 minutes Intune allows a script. What was found by then still counts, and the account is
   partly checked. The script stops only the process it started, through the handle Windows gave
   it when it started it. It never looks a process up by its id to stop it: Windows gives an ended
   process's id to new processes, so an id can name an unrelated program.
   The check stops the tools it started itself. Its only one is ripgrep, for the session check.
   The check stops it at three quarters of its time, or when its own run ends normally, then waits
   2 seconds for it to exit. A ripgrep still running after that, or a session check that does not
   end by the end of the run's time, leaves the sessions partly checked. When the script stops the
   check at its time limit, the check's own clean-up does not run, so ripgrep is not stopped by the
   check: it ends when its search ends or when the output it writes to has no reader left, and the
   process list below reports it if it is still running.
   A tool can still be running for a moment after the check is stopped. It is reported, not
   force-closed: the script reads the system's process list once, and a process that names the
   check as its parent and started while the check ran, or whose start time can't be read, makes
   the account report a process left running. When the list can't be read in time, a process may be left, and the account says so.
   The stop and that one read end within 10 seconds, kept back from the account run's time.
5. Looks for agents installed under `%ProgramFiles%`, by name.
6. Looks in `%ProgramData%` for the malware markers `data/indicators.tsv` lists there. Any account
   can create a file there, but on NTFS a standard account cannot give a file to another owner, so
   the owner decides. A marker that Administrators, SYSTEM or a service owns is a finding for the
   PC. One the person owns is a finding on the person's row, at its incident's level, as the
   person's own report shows it; the account run reports it. One another account owns is a possible
   sign for the PC. One whose owner can't be read is a possible sign too, and the PC reads partly
   checked, never fully checked, unless a finding already makes it `act`. A link is nothing. A file with more than one
   name is only a possible sign for the PC, whoever owns it: any account can hard-link a file it can
   reach under a marker's name.
7. Saves the result and prints the inventory value, one line, or with `-Json` the JSON and with
   `-Summary` the summary line. `-Json` and `-Summary` together are refused.

### The result

The JSON, the summary line, the inventory value and the five outcomes are the ones in "The result"
above. The differences:

- `os` reads `Windows 10` or `Windows 11`, told apart by build number: 22000 and up is 11.
- `accounts` holds one row, for the signed-in account.
- `other_profiles` is new: how many other people have a profile on the PC. Their accounts were not
  checked in this run. The summary line and the inventory value carry it as `other_profiles=<n>`.
- The saved result is `%LOCALAPPDATA%\Blindspot\last.json`, in the person's own profile.
  Nothing running as SYSTEM ever opens it.
- `other_profiles` counts the profiles of people: a local account other than the built-in ones
  (an account number of 1000 or more), or a domain or Microsoft Entra ID account, whose folder
  exists and is not one of the `defaultuser` profiles Windows setup leaves. A local account an IT
  team made for itself can't be told from a person's, so it counts.
- A `failed` result ends with `reason=<why>`, one of:
  - `host_32bit`: run in 32-bit PowerShell.
  - `system_account`: run as SYSTEM, LocalService or NetworkService, which have no person's files.
  - `language_mode`: PowerShell runs only the reduced language, here or in the account run.
  - `unpack`: the check it carries could not be read, did not match its SHA-256, could not be
    written to the person's profile, or was not the right file just before it started; also when
    `gird-fleet.ps1` was run from standard input, with no folder to read `gird-check.ps1` from.
  - `save`: the result could not be saved.
  - `start`: the account run could not be started.
  - `no_output`: the account run ended without printing anything, for a reason other than the
    language mode.
- A name that does not fit the characters an account name may have (letters, digits, `.`, `_`
  and `-`, up to 64), or that is `machine`, the name of the PC's own part of the inventory value,
  shows as `invalid-name`, so the inventory value stays readable.
- Exit codes: 0 when the outcome is `clear` and 1 otherwise, which Intune lists as a PC with
  issues. `-MacExitCodes` gives the codes of a Mac instead. `-ExitZero` exits 0 whenever the run
  finished; `failed` still exits 1, or 13 with `-MacExitCodes`.
- There is no `-Inventory` and no stale age on the PC. The MDM's script prints the inventory value
  on every run, the MDM keeps that output, and the admin's report judges how old it is.
- `-HashAccounts` is not offered. On a Mac the secret stays in a file only root can read. Here the
  script runs as the person, who could read the secret.

### What a person can change

The check runs with the person's own rights, so a person who sets out to can change what their own
check reports. So can any program that runs as that person, malware included: the unpacked check
and the saved result sit in the person's own profile. A standard account cannot change another
account's result or check. Fleet mode shows an IT team where keys and agents sit across honest
machines. It is not a control against the person at the keyboard, and a `clear` from a PC that
malware already runs on proves nothing.

### Microsoft Intune

The daily check is an Intune Remediation: a script Intune runs on a schedule and whose output it
shows for each PC. Remediations need a Windows Enterprise or Education licence.

`gird-intune.ps1` does the setup and the reading, so the admin clicks through nothing. It signs in
to Microsoft Graph, the API behind the Intune admin center, as the admin, with Microsoft's own
PowerShell module. It sends nothing anywhere else.

| Command | What it does |
|---|---|
| `gird-intune.ps1 -Deploy -Group <name>` | Creates the Remediation from `blindspot-fleet.ps1` and assigns it to that group: run as the signed-in person, 64-bit PowerShell, once a day, with no fix script. Run again with a newer release, it updates the one it made. |
| `gird-intune.ps1 -Report` | Reads each PC's latest result from Intune and writes one report on the admin's PC: how many PCs had each kind of finding, the PCs to deal with first, and the PCs that were not checked or sent nothing. |
| `gird-intune.ps1 -Remove` | Deletes the Remediation it made. |

Intune keeps at most 2,048 characters of a script's output. The inventory value is at most 2,047,
so a value of 2,048 or more without `+more` can only be one Intune cut, and is cut to fit as on a
Mac. The script exits 1 unless the outcome is `clear`, which Intune lists as a PC with issues.
`blindspot-fleet.ps1` must stay under 200 KB; `tools/gen.sh` warns from 80% of that.

The report never calls a PC clear that sent no result, sent one older than the stale age, or sent
one that does not fit the inventory value's format. Those are listed as not checked.

An admin who prefers the Intune admin center can add `blindspot-fleet.ps1` by hand as a
Remediation's detection script with the same settings. `docs/mdm/` gets a page with the steps.

### PCs that restrict PowerShell

Some companies let PowerShell run only a reduced language, called Constrained Language Mode, or
only signed scripts. `gird-check.ps1` calls .NET directly and cannot run in the reduced language.
The script checks the language mode first, with a statement the reduced language allows, and in
the reduced language prints its result in the form asked for, `failed` with
`reason=language_mode`. Its own mode does not settle the account run's, which is a separate
process. So the account run checks its own mode first too, and in the reduced language prints only
`language_mode=1`: the result is then `failed` with `reason=language_mode`. An account run that
prints nothing at all is `failed` with `reason=no_output`. A PC that could not be checked never
reads `clear`.

### Tests

Each has a twin in `tests/run.sh` where the Mac check has the same rule. Tests of Windows
permissions, the language mode and stopping a process need Windows. They run on a Windows PC and
report as skipped elsewhere. `gird-intune.ps1` is tested against a local stand-in for Microsoft
Graph, never a real tenant.

- `-AccountRun` prints the same keys, in the same order, as `--account-run` for the same fixture.
- Output for another account, a forged machine section, oversized output or a malformed line:
  the account is `not_checked`.
- An unpacked check whose SHA-256 differs is written again before it runs.
- `blindspot-fleet.ps1` is under 200 KB, the check it unpacks is `gird-check.ps1` without its
  comments, byte for byte, and the SHA-256 it carries is that copy's. A packed copy edited by hand
  fails `tools/gen.sh --check`.
- `gird-check.ps1` without its comments parses, prints the same `-AccountRun` lines and the same
  `-Offline -Full` report for the suites' fixtures, and has the same strings, here-strings and
  tables, token for token. In a small script, a `#` in a string, a here-string and a regex stays,
  `#requires` stays, and the script prints the same.
- An account run that outlives its time limit is stopped, and the account is partly checked. A
  process it started that is still running is reported and left running. When the process list
  can't be read, a process is reported as maybe left, never as none.
- A slow tool the account run started is stopped by the account run itself, before its limit.
- No network request, no browser, no saved report.
- The JSON, the summary and the inventory value hold no path, file name or planted key.
- Each outcome and exit code, from a fixture that produces it.
- A marker in `%ProgramData%` owned by an ordinary account is a possible sign, not a finding; one
  the person owns is a finding on their row; one with two names is a possible sign for the PC.
- `gird-fleet.ps1` stops no process by its id: the only process it stops is the account run,
  through the handle it started it with. The process list decides only what is reported.
- A profile that moves an agent's folders leaves the account partly checked, in a form the check
  does not know too, and in a file it sources from outside the home, two files down, by `&`,
  `Import-Module` or a manifest, in a sourcing loop, or placed in a tool's own folder. Past 64
  files or 16 MiB read, it does only where a listed variable was named. So does one that names a
  listed variable beside a loop over a zsh glob qualifier the check does not parse, or a source line
  outside the function whose `param()` builds its path; a file named like nvm's own script outside
  Homebrew's prefix is read.
- What nvm, nvm-windows, fnm, Volta, pnpm, bun, conda, mise, asdf (0.16 too), uv, pipx, Poetry,
  oh-my-posh, starship, posh-git, PSReadLine, Chocolatey, the Visual Studio developer shell and a
  corporate profile write moves nothing; nor does a default folder, a listed name in a comment,
  `source <(...)`, a file sourced from outside the home, or files that source each other.
- A session in Constrained Language Mode: `failed`, with `reason=language_mode`.
- A 32-bit PowerShell: `failed`, with `reason=host_32bit`.
- A profile that would print or change something does not run.
- A test-only `GIRD_CHECK_*` setting in the person's environment changes nothing.
- `-Deploy` sends one Remediation with the settings above, and a second `-Deploy` updates it.
- `-Report` lists a PC with no result, a stale result or a malformed result as not checked.

## Not covered

- **Windows accounts that are not signed in.** See "Why not every account at once" under Windows.
- **Linux** uses this design with `setpriv` (no shell start-up files, no login session) to drop to
  the account, the local `/etc/passwd` only (no directory lookups), and `UID_MIN` from
  `/etc/login.defs`. It is phase 2.
- Not measured: how the real `sudo` on macOS places the account run (with `use_pty` it may run the
  command in a group or session of its own, out of reach of root's kill of the process group). A run
  that leaves the group is caught only when it still holds root's pipe open, which root then reports
  as a process left running; one that let go of the pipe is not seen.
- A run as `bash /dev/fd/0 < gird-fleet.sh` reads its own source from a path that is not the file;
  it is not refused by name, and is left to the "run it from a file" and ownership checks.
- The saved result has no lock. Two runs at once can make a finished run read `failed`; a step in
  the clock can delay or hide `failed`; and a run that was killed leaves the previous result
  reading as it was until the killed run's deadline passes.
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
  only its own share. A tenth of the deadline, at most 40 seconds, is kept in reserve for the steps
  outside the shares (the home folder checks, the machine check, saving), which can still overrun it
  slightly. The machine check is timed to fit it: its temp folder finds share half the reserve and
  `lsof` gets a quarter, at most 20 and 10 seconds, and one that runs out leaves the Mac partly checked.
- The inventory reader is the script itself: `--inventory` (root only) prints the saved inventory
  value, `stale: last run <time>` past `--stale-days` (3 by default, at most 30), `none` before the
  first run, `unreadable` when the saved file is not root's own 0600 file in a 0700 folder, and
  `failed: the run started <time> did not finish or could not save its result` when a later run's start, saved as
  `/var/db/blindspot/attempt` with its deadline, is past that deadline with no newer result.
  `--result-tags` wraps it for Jamf Pro.
- Deployment: the MDM installs both files once in `/Library/Application Support/Blindspot`
  (folder `root:wheel` 0755, `gird-check.sh` 0755, `gird-fleet.sh` 0700 so any `--hash-accounts`
  secret in it is root's only), with the options in one line that starts the second line of
  `gird-fleet.sh`, `case " $* " in *" --inventory "*|*" --list "*|*" --help "*|*" -h "*) ;; *) set -- <options> ;; esac`, so an
  `--inventory` call keeps its own. The MDM's daily item and its inventory field only run
  `exec /usr/bin/env -i /bin/bash .../gird-fleet.sh`, with no options or secret on their own line,
  so no `BASH_ENV` or `ENV` from the MDM's environment runs before the script can clear it. The
  secret is never on a command line: the options line sets it inside the script, and the hash is
  computed with the secret in perl's environment, which only root can read. The install step is untested on a
  real Mac.
- `review` means something to change or confirm, not urgent. It covers a tool with a security fix, an incident or a package version at the update level, project settings that act when a folder opens, files named like the ones worms plant and projects or agent settings that start a script the way worms do (`autostart`), and also an agent set to run without asking, an agent allowed to run commands on other machines without asking, an SSH key without a passphrase, a
  platform that leaked stored secrets and a leftover file that can come from malware; `act` also
  covers keys in shell history, MCP configs and Claude Code allow lists, links to
  `authorized_keys`, an SSH key malware adds in `authorized_keys`, files a worm plants and the gh-token-monitor wiper, whose stop-it-first line comes before any other. An account with a protected folder refused, a file not
  read or agent sessions not all checked is partly checked: `act` if it found something to act on,
  otherwise `not_checked`.
- The size limit for a file an account run reads is 16 MB; session files are read in 1 MB pieces at
  any size. Root reads at most 4096 bytes of an
  account run's output. Apps in `/Applications` and agent commands in `/usr/local/bin` and
  `/opt/homebrew/bin` are the machine's agents, found by path.
- What root checks for the Mac in phase 1: apps in `/Applications` and agent commands in
  `/usr/local/bin` and `/opt/homebrew/bin`, by name; in the shared temp folder, the malware markers
  `data/indicators.tsv` lists there, by name, with one timed `find` for each, so a folder an account
  filled with such names costs root no time per file; whether a process holds the LiteLLM loader's lock file
  open (`lsof`), the only running process it looks at; and any startup file `data/indicators.tsv`
  lists outside a home folder, of which macOS has none today. Startup items in shared folders and
  other running processes are not checked yet.
- From an IT team's review of both files: an account name the account check does not read shows
  as `invalid-name` (not checked), so the inventory value stays readable; in an account run a file
  the account can't read, and a folder the home scan, npm's cache, the extension folders or the
  session check can't open, count as not checked; markers that must be the person's own
  (data/indicators.tsv) are looked for in `/tmp` under one name, never through a link, symbolic or
  hard, and are only possible signs there, for the account that owns them or, when root owns them,
  for the Mac: any account can hard-link a file it can reach under a marker's name (a review found
  that through root's own copy of gird-check.sh, which root now empties and gives away before
  deleting it); a running LiteLLM loader counts only when root's own process holds its lock, and a holder whose
  account `ps` cannot give leaves the Mac partly checked, never read as another account's; a
  shell profile that moves an agent's folders leaves the account partly checked, read the way the
  Windows account run reads it (`moved`, under Windows), with the same caps, apart from the forms only
  PowerShell has; each run is told
  its time, so its session check stops in time; every path an account or admin could make is
  tested as a link first and never followed; a `find` or `lsof` that does not answer in time
  leaves the Mac's row not complete; agents in the account's own install folders
  are found by path; and the ownership check refuses an ACL entry that lets anyone write. A
  normal run of `gird-check.sh` now names a key file it can't read and doesn't call the keys check
  clean over it.
- Session engine. An account run inherits the Full Disk Access of the MDM agent that started root:
  macOS judges it by the responsible process, and it passes through `sudo` to the account run and
  everything it starts. So the account run never runs anything an account could have written or
  re-pointed. An account can re-point any link in a folder it can write (Homebrew's `bin` belongs to
  whoever installed Homebrew), and a link to any root-owned program would run that program; some,
  such as a Python or a Ruby, then load the account's own code, inside the Full Disk Access chain.
  So ripgrep is used only from `/Library/Application Support/Blindspot/rg`, which the guide installs
  as an optional, pinned and hash-checked step: as a regular file, not a link, with every folder
  above it a real folder, all owned by root and writable by no one else, by mode or by ACL. Links
  are never resolved and no other place is looked at. Otherwise the system perl checks the
  sessions. The cost: with a large session store (5.2 GB measured on one Mac), minutes per account
  on perl, seconds with the admin-installed ripgrep. ripgrep gets no handle to root's pipe. Root
  never runs ripgrep. The account run reports `engine=rg|perl|none`, and the row carries it as
  `session_engine`; the inventory value does not.
- With none of the protected folders it tries (Safari, Mail, Messages) in a home, an account run
  counts its protected folders as checked: there is nothing protected to miss.
- Two files. `gird-fleet.sh` holds all the root work: the fixed PATH, the ownership checks, the
  account list, the machine checks, the copy, the sudo launch, the timer, the strict parsing,
  outcomes, exit codes, every fleet option, the saved result and the readable report.
  `gird-check.sh`, the script each person runs, holds no root code: it keeps `--account-run`, the
  fixed lines one account's check sends back, and given `--all-users` it points to `gird-fleet.sh`.
  Root never sources `gird-check.sh`: `tools/gen.sh` writes the tables root reads (keys, agents set
  to run without asking, the agent files whose rules can run commands on other machines, incidents, indicators, outdated tools, platforms, the agents, and the keys
  of the lines an account run sends) into `gird-fleet.sh` from `data/`; `--check` covers them, and
  fails when the lines `gird-check.sh` prints are not those of `data/account-run.tsv`.
- `gird-fleet.sh` needs to run from a file, since it copies `gird-check.sh` from its own folder for
  each account; from standard input it stops with a message. Root refuses to start (exit 13) unless
  `gird-fleet.sh`, `gird-check.sh` next to it and every folder above them are owned by root and
  writable by no one else. The options line, with any `--hash-accounts` secret, sits in
  `gird-fleet.sh`, which is never copied for an account. The result's `script` field and the
  summary's `v=` are `gird-check.sh`'s release version, from its header, so both files report one
  version.
- An account run stopped at its time limit can leave its temp files in `/tmp`: root does not know
  their names. Moved-aside saved-result folders stay until removed (`docs/fleet-reference.md`, "Update or remove it").
- A saved-result folder that is a link, not a folder, or not root's with mode 0700 is moved aside to
  `/var/db/blindspot.replaced-<time>-<pid>` and made again, so root never deletes a tree it did not
  make.
- The tests stand in for root, dscl and sudo with `GIRD_CHECK_FLEET_*` settings that the script
  reads only when it is not running as root; as root they are unset before anything else runs.
