# Fleet mode: running Blindspot from an MDM

Status: built for macOS (phase 1), as `gird-fleet.sh --all-users`, with the admin guide in
`docs/fleet.md` and the MDM pages in `docs/mdm/` (each marked untested until run end to end on a real
Mac). Linux is phase 2: until then `--all-users` on Linux exits 13 with a message. Windows is
built as `gird-fleet.ps1` and `blindspot-fleet.ps1`, under "Windows" below; `gird-intune.ps1`, the
admin's tool for Intune, is not built yet. What the macOS build adds to this design, or settles where
it was open, is under "As built" at the end. A Mac is set up today with two files and an install
step, as "As built" says; "macOS: one file for the MDM" designs the single file that replaces them.

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
  `v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; run-without-asking claude-code; keys 2
  anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear`. If it would not fit, it keeps the
  outcome, then the accounts that need attention first (act, not_checked, review), then as many
  clear ones as fit, and ends with `+more`; the full result is in the saved file.
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

## macOS: one file for the MDM

For IT teams that manage Macs, and for engineers changing `gird-fleet.sh` or `tools/gen.sh`.

`blindspot-fleet.sh` is the one file an IT admin gives the MDM for a Mac. The MDM runs it as root,
once a day, with no arguments and nothing to edit. It checks every account and prints one summary
line. There is nothing to install first: no folder, no second file, no options line.

`tools/gen.sh` builds it for each release from `gird-fleet.sh` and a copy of `gird-check.sh` without
its game. It is not checked in. The copy sits inside the file as plain text, so whoever reviews the
file reads exactly the code each account runs.

### What the admin does

Downloading the file and checking its SHA-256 is step 1 for every MDM. Full Disk Access for the MDM's
agent stays as it is and is not counted.

**Jamf Pro**, 4 steps (8 before: download and check two files, add the options line, paste both into
the install script, add it as a script, a policy to run it once, a second script, a daily policy, and
the extension attribute):

1. Download `blindspot-fleet.sh` from a release and check its SHA-256.
2. **Settings** > **Scripts** > **New**: name it `Blindspot`, paste the file into **Script**, save.
3. **Computers** > **Policies** > **New**: trigger **Recurring Check-in**, frequency **Once every
   day**, add the `Blindspot` script, choose the Macs, save.
4. **Settings** > **Extension attributes** > **New**: name it `Blindspot`, type **String**, input
   **Script**, paste the reader lines under "One file, three uses", save.

**Iru**, 2 steps (5 before: download and check two files, add the options line, paste both into the
install script, a Custom Script to install once, a Custom Script to run daily):

1. Download the file and check its SHA-256.
2. Add a Custom Script named `Blindspot`, **Run daily**, with the file as its **Audit Script** and
   no remediation script. Its output, kept by Iru, is the summary line.

**Microsoft Intune**, 3 steps (6 before: download and check two files, add the options line, paste
both into the install script, a script to install once, a daily script, and the custom attribute):

1. Download the file and check its SHA-256.
2. **Devices** > **macOS** > **Scripts** > **Add**: upload the file, **Run script as signed-in user**
   **No**, frequency daily.
3. **Custom attributes for macOS** > **Add**: type **String**, with the reader lines saved as a file.

**ManageEngine Endpoint Central** has no page yet. Its Mac custom script takes a script and the exit
codes that mean success, so the one file fits it as it fits the others; a page follows a run on a
real Mac.

Updating is replacing the file in the MDM's item with the next release. Removing is deleting the
MDM's items, then `/var/db/blindspot` on each Mac.

### What is inside

1. Line 1 is `#!/bin/bash`, never `#!/usr/bin/env bash`. An MDM that starts a file by its first line
   would otherwise have `env` look for `bash` on the MDM's PATH, where a copy in `/usr/local/bin` or
   `/opt/homebrew/bin` belongs to whoever installed it, and run that copy as root.
2. `gird-fleet.sh`, unchanged apart from its `packed-check` block.
3. The `packed-check` block, as `tools/gen.sh` fills it:

   ```
   # >>> packed-check: gird-check.sh without its game, written in by tools/gen.sh.
   FL_PACKED_SHA='<SHA-256 of the copy>'
   fl_packed() {
     /bin/cat <<'BLINDSPOT_CHECK'
   (gird-check.sh without its game, byte for byte)
   BLINDSPOT_CHECK
   }
   # <<< packed-check
   ```

   The delimiter is quoted, so bash expands nothing in the copy. `tools/gen.sh` refuses a copy that
   holds a line equal to the delimiter. bash keeps a here-document that sits in a function's body in
   memory from the moment it reads the definition, so the copy comes from what root read at the
   start, never from the file later.

In `gird-fleet.sh` itself the block holds only `FL_PACKED_SHA=''`. With it empty, `gird-fleet.sh`
copies `gird-check.sh` from next to it, checked as today, for development and the test suites.
Everything else below is code in `gird-fleet.sh`, the same in both.

### How a run starts

1. **A clean environment.** The file's first command starts it again with nothing from the MDM's
   environment: `exec /usr/bin/env -i BLINDSPOT_CLEAN=1 /bin/bash "$0" "$@"`, unless
   `BLINDSPOT_CLEAN` is already set. From there it runs as the daily item
   `exec /usr/bin/env -i /bin/bash .../gird-fleet.sh` runs today. One thing it cannot undo: a
   `BASH_ENV` in the MDM's own environment runs before line 1, as it does for every script that MDM
   runs. That environment belongs to root and the MDM; no account can set it.
2. **Arguments.** Jamf Pro sends every script three arguments first, the mount point, the computer
   name and the user name ([Jamf's Scripting 201 guide](https://resources.jamf.com/documents/white_papers/apple-scripting-201.pdf)),
   and the options the admin may add in parameters 4 to 11. So when the first argument does not
   start with `-`, the first three are dropped, and empty arguments are dropped. Then:
   - no options, standard output not a terminal (an MDM): `--all-users --exit-zero
     --summary-to-stdout --deadline=3000`;
   - no options, standard output a terminal (an admin trying it): `--all-users`, the readable
     report;
   - any option: exactly the options given, with `--all-users` added unless `--inventory`,
     `--list` or `--help` is among them. To change one default, give them all, for example
     `--exit-zero --summary-to-stdout --deadline=1800` in Jamf's parameter 4.
3. **The fixed PATH, the test settings and the ownership checks**, as `gird-fleet.sh` does today,
   with one difference: no `gird-check.sh` needs to sit next to the file.
4. **The copy each account runs.** Where `gird-fleet.sh` copies `gird-check.sh` today, root makes
   the same folder with `/usr/bin/mktemp -d /tmp/blindspot-copy.XXXXXXXX` and writes the copy from
   memory: `TMPDIR=$FL_TMP fl_packed > "$FL_COPY"`. bash 3.2 passes a here-document through a
   temporary file (measured: a regular file, mode 0400) in `TMPDIR`; pointing `TMPDIR` at root's own
   0700 work folder keeps that file out of the shared `/tmp`. Root then sets the modes (file 0644,
   folder 0755) and compares the copy's SHA-256 with `FL_PACKED_SHA`. A mismatch fails the run
   (`copy`), as a changed copy does today.
5. **Before every account's start**, `fl_copy_ok` checks the owner, mode and that nothing is a link,
   as today, and the SHA-256 again. The SHA-256 is made by `/usr/bin/shasum -a 256`, on every
   macOS, run with the cleared environment, so no `PERL5OPT` reaches it.
6. **The version** comes from the copy's header, as it comes from `gird-check.sh` today.
7. **The copy for the inventory field.** After the result is saved, root copies the file it checked
   to `/var/db/blindspot/blindspot-fleet.sh` (written to a temporary name, compared with `cmp`,
   renamed; root's 0700 file in root's 0700 folder). See "One file, three uses".

### The safety rules, one by one

| Rule today | Still applies | How |
|---|---|---|
| A fixed PATH before the first command | Yes | Unchanged, after the clean start. |
| Every tool by its full path | Yes | Also line 1 (`/bin/bash`) and the unpack (`/bin/cat`, `/usr/bin/shasum`). |
| `env -i` before the script runs | Yes | Moved into the file: it starts itself again under `env -i`. `BASH_ENV` in the MDM's own environment still runs first. |
| Its own file and every folder above it root's alone | Yes | bash reads a script as it runs it, so a file an account could change part-way would be code root runs. See the next section. |
| `gird-check.sh` next to it, root's alone | No | There is no such file. The copy comes from root's memory. |
| Run from a file, never standard input | Yes | Needed for the ownership check and the clean start. |
| The copy in a new root-owned folder, checked before each start | Yes | Plus its SHA-256, before each start. |
| Never trust a file an account could change | Yes | The copy is written from memory; the here-document's temporary file is in root's 0700 work folder. |
| Test-only `GIRD_CHECK_*` settings ignored as root | Yes | Unchanged. |
| The copy emptied and given away before it is deleted | Yes | Unchanged. |
| Options, and any `--hash-accounts` secret, in an options line | No | There is no options line. See the open decisions. |

### Where each MDM puts the file

The ownership rule refuses a run when the file, or any folder above it, can be changed by anyone but
root. Whether an MDM's run passes depends on where it writes the script, and no vendor documents that:

| MDM | Where the script is written, and its owner | Source |
|---|---|---|
| Jamf Pro | Not in Jamf's documentation. Commonly reported as `/Library/Application Support/JAMF/tmp/`; owner not reported. | [Adding a Script](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Adding_a_Script_to_Jamf_Pro) |
| Iru | Not documented. The guide says only that custom scripts always run as root. | [Custom Scripts](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview) |
| Microsoft Intune | Not documented. Scripts run as root unless set to run as the signed-in user. | [Shell scripts on macOS](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos) |
| ManageEngine Endpoint Central | Not documented, nor the account it runs as. | [Custom scripts for computers](https://www.manageengine.com/products/desktop-central/help/mac_configurations/executing_custom_scripts_for_computer.html) |

Each needs a real Mac. A folder private to an MDM agent that runs as root passes. The shared `/tmp`
itself (mode 1777) would be refused, as would a script passed on standard input. The refusal names
the path that failed, so the first run on each MDM shows what it does. Until each has run on a real
Mac, its page stays marked untested.

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
when `blindspot-fleet.sh` reaches 1,000,000 bytes and warns from 800,000.

### Removing the game

The game is for a person running the check by hand. Fleet mode never starts it, but its code would
ship in a file root handles, so the copy leaves it out.

In `gird-check.sh`, the whole "GIRD Runner" section, from its header to the end of `game_loop`,
goes between `# >>> game` and `# <<< game`, the block markers the data blocks use. So the remaining
script still runs:

- `GAME_PID=""; KEYS_PID=""; GAME_RC=0; SAVED_TTY=""` moves above the block. `cleanup` and the end
  of the scan read them, and empty they mean no game.
- A default `game_start() { return 1; }` sits above the block. Inside it, `game_start` is defined
  again with the lines that start the game today (`game_ok`, the terminal setup, `game_loop &` and,
  in mode C, `g_keys`). The scan's start becomes `game_start || spin_start "Checking your agents,
  configs and keys"`.
- The end of the scan is unchanged: with `GAME_PID` empty it stops the spinner, and `GP` and `GB`
  stay 0. They are sent only by a person's run, never in fleet mode.
- `--no-game` stays accepted, so the same options work on both. The header keeps its `--no-game`
  line: `--help` prints the header and root reads the version from it, so the header is never cut.
- `tools/gen.sh` refuses another `# >>>` block inside the game block.

The copy is `gird-check.sh` with the lines from `# >>> game` to `# <<< game` deleted, and nothing
else changed. Anyone can print the SHA-256 the file carries in `FL_PACKED_SHA` from the published
`gird-check.sh`:

```
/usr/bin/sed '/^# >>> game$/,/^# <<< game$/d' gird-check.sh | /usr/bin/shasum -a 256
```

and see that the rest is `gird-fleet.sh` with only line 1 and the `packed-check` block different:

```
diff gird-fleet.sh blindspot-fleet.sh
```

The proof that the copy behaves the same, in the tests:

1. The copy is `gird-check.sh` minus exactly the block's lines (`diff` shows only those).
2. `bash -n` passes on the copy, on `/bin/bash` 3.2 and on a newer bash.
3. No function defined in the block is named anywhere in the copy.
4. bash's own reprint: each file is wrapped in a function, read by `/bin/bash`, and printed with
   `declare -f`, which prints the code bash parsed, every function and the top-level code, without
   comments. The original's reprint with the block's part removed equals the copy's.
5. `--account-run` prints the same lines for the suites' fixtures.
6. `--offline --full` prints the same report for the suites' fixtures, with no terminal and
   `NO_COLOR=1`.
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
| The daily check | The MDM runs the file, with no arguments (Jamf adds its three). | Checks every account, saves the result, prints the summary line, exits 0 unless the run `failed` (13). |
| The inventory field | Jamf's extension attribute and Intune's custom attribute each run a script they hold and take no arguments, so they run the reader lines below. | Prints the saved inventory value, `stale`, `none`, `failed` or `unreadable`, as `--inventory` does today. |
| An admin trying it | `sudo /usr/bin/install -m 0700 blindspot-fleet.sh /var/root/`, then `sudo /bin/bash /var/root/blindspot-fleet.sh` in Terminal. | The readable report for every account. `--list` shows who would be checked. |

The reader lines, the same for every release:

```sh
#!/bin/bash
f=/var/db/blindspot/blindspot-fleet.sh
[ -f "$f" ] || { echo none; exit 0; }
exec /usr/bin/env -i /bin/bash "$f" --inventory --stale-days=3
```

For Jamf, the last line adds `--result-tags` and the third prints `<result>none</result>`. Iru has
no inventory field: the daily check's output is the result. The admin installs the file under
`/var/root`, root's home folder, because root runs only a file in folders root alone can change; a
copy in Downloads would be refused.

### What the docs change

- `docs/fleet.md`: step 0's review prompt names one file and says the check is inside it in plain
  text, with the two commands above to confirm it; step 1 downloads one file; step 3 loses the
  options line, the install script and the marker lines, and gives the defaults and the reader
  lines; the optional ripgrep becomes its own once-only MDM item; step 6 updates by replacing the
  file and removes `/var/db/blindspot`.
- `docs/mdm/jamf.md`, `iru.md`, `intune.md`: the step lists above. Intune's limits section gives the
  file's size against the 1 MB limit.
- README: the IT teams paragraph names `blindspot-fleet.sh`, and drops the install folder.
- CONTRIBUTING, Releases: the release notes give the SHA-256 of `blindspot-fleet.sh` too.
- `.gitignore`: `blindspot-fleet.sh`.

### Parity

**Windows.** `blindspot-fleet.ps1` is the same idea: one file, built by `tools/gen.sh` at release,
not checked in, carrying the check and its SHA-256, checked before each start, and refused by
`--check` when edited. It differs where the platforms differ:

- It strips comments and compresses, because Intune takes a Windows script of under 200 KB. A Mac
  script may be under 1 MB, so the Mac copy stays plain.
- It has no game to cut: only `gird-check.sh` has one.
- It unpacks into the person's own profile, because it runs as the person. The Mac file unpacks
  into a folder only root can change, because it runs as root and starts each account through
  `sudo`.
- It prints the inventory value on every run and has no `--inventory`. A Mac's inventory field runs
  apart from the check, so the Mac file keeps a copy for it.
- It starts the check with `-NoProfile`. The Mac file starts itself again under `env -i`, and drops
  Jamf's three arguments, which Windows MDMs do not send.

**Linux.** Fleet mode does not exist on Linux yet; the file exits 13 there with the message
`gird-fleet.sh` gives today. So that the same file works when it does: line 1 is `/bin/bash`, which
the common distributions have; the copy travels as a here-document read by `/bin/cat`, with nothing
macOS-only; the SHA-256 tool is a per-OS full path (`/usr/bin/shasum` on macOS,
`/usr/bin/sha256sum` on Linux); and the saved-result folder, where the inventory copy also lives, is
one per-OS constant, not `/var/db` written out in each place. Linux fleet mode itself is not
designed here.

### One home in `tools/gen.sh`

Shared by both one-file builds: `splice` (already shared), `sha`, and one function that, given the
file's name, its built text, its size limit and the SHA-256 its copy must unpack to, checks the
size (fails at the limit, warns at 80% of it), checks that the copy unpacks to that SHA-256, with
`--check` fails when the file here is not what it builds, and otherwise writes it when it changed
and prints its size. The `.gitignore` lines sit together.

bash only: cutting the game block and refusing the here-document's delimiter in the copy. PowerShell
only: `tools/strip-comments.ps1`, gzip and base64. Each has its own small "what does it unpack to",
because one reads a here-document and the other decodes a string.

### Tests

Each has a twin for `blindspot-fleet.ps1` in `tests/run-ps.sh`, or a line in `tests/bash-only.txt`
with the reason (the game, Jamf's arguments, `env -i` and `sudo` are bash only).

- `blindspot-fleet.sh` is under 1,000,000 bytes, starts with `#!/bin/bash`, and its copy is
  `gird-check.sh` without the game block, byte for byte, with that SHA-256 in `FL_PACKED_SHA`. A
  hand-edited copy or SHA-256 fails `tools/gen.sh --check`.
- A copy holding a line equal to the delimiter: `tools/gen.sh` refuses it.
- Past 800,000 bytes `tools/gen.sh` warns, and at 1,000,000 it fails (tested on a padded build).
- The game proofs 1 to 6 above, and `tests/interactive.sh` unchanged.
- The copy root writes differs from `FL_PACKED_SHA`, before the first account or between two: that
  account is `not_checked` and the run `failed`, as a changed copy is today.
- Arguments: none and no terminal gives the summary line and exit 0 on a finding; none with a
  terminal gives the readable report; `/ mac01 asha` and eight empty strings behave as none;
  `/ mac01 asha --deadline=1800` is `--all-users --deadline=1800`.
- A `GIRD_CHECK_*`, `PERL5OPT` or exported function in the starting environment changes nothing:
  the file starts again under `env -i`.
- Started through its first line with a `bash` earlier on PATH that leaves a mark: no mark.
- In a folder another account can write to: exit 13, naming that folder.
- After a run the inventory copy is root's 0700 file in the state folder, identical to the file;
  the reader lines print `none` before any run.
- On Linux: exit 13 with the macOS-only message, and the unpack names no macOS-only tool.
- Need root or a real MDM, so skip with that reason: where each MDM writes the file and whether the
  ownership rule passes; Jamf's real arguments; whether Jamf's and Iru's script fields take 578 KB
  pasted; Intune's upload of it; Full Disk Access through `sudo`; the here-document's temporary
  file under a real root run.

### Open decisions

- Where each MDM writes the file is undocumented: build it, run it once per MDM on a real Mac,
  keep each page marked untested until then.
- If an MDM writes into a root-owned folder that anyone may add to but only owners may remove from
  (the sticky bit, as `/private/tmp`): accept such a folder above the file only then; it is sound,
  since no one else can rename or replace root's file there.
- `--hash-accounts` has no options line to live in: leave it out of the one file until someone asks,
  then read the secret from a root-only file in `/var/db/blindspot`, never from an argument.
- ripgrep stays an optional, separate once-only MDM item: keep it optional.
- The inventory copy in `/var/db/blindspot`: keep it; the alternative is a second generated file.
- The defaults depend on whether standard output is a terminal: keep it, so an admin's first try
  reads well and an MDM gets one line.
- `gird-fleet.sh` with `gird-check.sh` next to it still runs: keep it for development and tests,
  and document only the one file.
- Jamf's arguments are dropped when the first does not start with `-`: keep it; a stray word is then
  ignored rather than refused.
- Warn at 80% of the limit for both one-file builds: one number, for the 20% room asked for.

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
    the variables gives no reason to think the rest moves one. A tool's own script in its own
    folder (`$NVM_DIR/nvm.sh`, the `scripts` column of `data/folder-vars.tsv`) is not read: it sets
    the tool's variable to the folder it is in, the one the check reads. Any other file in that
    folder is read. A variable set to one of the folders in that file's `windows` column, the
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
  accepts. `tools/gen.sh --check` fails if it grows past that and warns past 90%. See "The check a
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
   The check stops the tools it started itself. Its only one is ripgrep, for the session check,
   and the check stops it at three quarters of its time, or when it ends for any other reason,
   then waits briefly for it to exit.
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
   person's own report shows it; the account run reports it. One another account owns, or whose
   owner can't be read, is a possible sign for the PC. A link is nothing. A file with more than one
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
`blindspot-fleet.ps1` must stay under 200 KB; `tools/gen.sh` warns once it passes 90% of that.

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
  files or 16 MiB read, it does only where a listed variable was named.
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
- `review` means something to change or confirm, not urgent. It covers a tool with a security fix, an incident or a package version at the update level, project settings that act when a folder opens and files named like the ones worms plant, and also an agent set to run without asking, an SSH key without a passphrase, a
  platform that leaked stored secrets and a leftover file that can come from malware; `act` also
  covers keys in shell history, MCP configs and Claude Code allow lists, links to
  `authorized_keys`, files a worm plants and the gh-token-monitor wiper, whose stop-it-first line comes before any other. An account with a protected folder refused, a file not
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
  deleting it); a running LiteLLM loader counts only when root's own process holds its lock; a
  shell profile that moves an agent's folders leaves the account partly checked; each run is told
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
  to run without asking, incidents, indicators, outdated tools, platforms) into `gird-fleet.sh` from
  `data/`, and copies `gird-check.sh`'s agents table, which has no data file; `--check` covers both.
- `gird-fleet.sh` needs to run from a file, since it copies `gird-check.sh` from its own folder for
  each account; from standard input it stops with a message. Root refuses to start (exit 13) unless
  `gird-fleet.sh`, `gird-check.sh` next to it and every folder above them are owned by root and
  writable by no one else. The options line, with any `--hash-accounts` secret, sits in
  `gird-fleet.sh`, which is never copied for an account. The result's `script` field and the
  summary's `v=` are `gird-check.sh`'s release version, from its header, so both files report one
  version.
- An account run stopped at its time limit can leave its temp files in `/tmp`: root does not know
  their names. Moved-aside saved-result folders stay until removed (`docs/fleet.md`, step 6).
- A saved-result folder that is a link, not a folder, or not root's with mode 0700 is moved aside to
  `/var/db/blindspot.replaced-<time>-<pid>` and made again, so root never deletes a tree it did not
  make.
- The tests stand in for root, dscl and sudo with `GIRD_CHECK_FLEET_*` settings that the script
  reads only when it is not running as root; as root they are unset before anything else runs.
