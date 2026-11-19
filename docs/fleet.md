# Blindspot for IT teams

`gird-fleet.sh` checks every account on a Mac for what Blindspot shows one person: coding agents, keys
in plain text and in agent sessions, agents and project settings that run commands without asking,
and signs of recent malware. Your MDM runs it daily and shows one line per Mac. This page is about
Macs up to [Windows](#windows), which has steps of its own. Linux has no fleet mode yet
([issue #39](https://github.com/aegis-mesh/blindspot/issues/39)).

**Before you deploy:**

- It runs as root, from a folder only root can change. It checks each account as that account.
- It reads files and changes nothing in any home folder.
- It sends nothing anywhere. It makes no network request.
- It keeps one result on the Mac, `/var/db/blindspot/last.json`, readable by root only. The result
  holds counts and names from fixed lists, never a path, a file name or a key. A few other files can
  remain: [what can be left behind](fleet-reference.md#files-that-can-be-left-behind).

The install step and the [MDM pages](mdm/) have not yet been run end to end on a real Mac or PC.

## What you get

Your MDM shows one line per Mac, such as:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear
```

The first word after `v1` is the Mac's outcome, the worst of its accounts:

| Outcome | Means | Exit code |
|---|---|---|
| `act` | Act now: malware signs, or keys in plain text, shell history, agent sessions, MCP configs or allow lists. | 10 |
| `not_checked` | An account, or part of one, was not checked. Never read this as clear. | 12 |
| `review` | Something to change or confirm, not urgent, such as an agent set to run without asking. | 11 |
| `clear` | Every account was checked in full and nothing was found. | 0 |
| `failed` | The run could not finish safely. | 13 |

The field can also read `stale` (no run in 3 days), `none` (no run yet), `failed` (the last run stopped
part-way or could not save) or `unreadable`. Treat each of those as not checked.

The [full definitions](fleet-reference.md#outcomes-in-full) list everything each outcome covers.
Start with the Macs whose value starts `v1 act`, then `v1 not_checked`, `failed` and `stale`.
[What to do about each finding](fleet-reference.md#act-on-a-finding).

## Set it up

You need a tagged release of `gird-check.sh` and `gird-fleet.sh`, with the SHA-256 checked against
the [release notes](https://github.com/aegis-mesh/blindspot/releases). Your MDM's agent needs Full
Disk Access, or each account reads `not_checked`: the [page for your MDM](mdm/) says how. Grant it to
the MDM's agent, never to a shell such as `/bin/bash`
([why](fleet-reference.md#full-disk-access)).

### 1. Install it once

In the folder with both files, run this. It adds the daily options to a copy of `gird-fleet.sh`, then
writes `blindspot-install.sh`, which installs both files in `/Library/Application Support/Blindspot`.
If your MDM's page gives a different deadline, change `--deadline=3000` in the first line.

```sh
opts='case " $* " in *" --inventory "*|*" --list "*|*" --help "*|*" -h "*) ;; *) set -- --all-users --exit-zero --summary-to-stdout --deadline=3000 ;; esac'
/usr/bin/awk -v l="$opts" 'NR == 1 { print; print l; next } { print }' gird-fleet.sh > gird-fleet-mdm.sh
{
  cat <<'EOF'
#!/bin/bash
set -e
umask 077   # the new files are root's alone until their modes are set
d="/Library/Application Support/Blindspot"
/bin/mkdir -p "$d"
/usr/sbin/chown root:wheel "$d"
/bin/chmod 0755 "$d"
/bin/cat > "$d/gird-check.sh.new" <<'BLINDSPOT_CHECK'
EOF
  cat gird-check.sh
  printf '%s\n' 'BLINDSPOT_CHECK' "/bin/cat > \"\$d/gird-fleet.sh.new\" <<'BLINDSPOT_FLEET'"
  cat gird-fleet-mdm.sh
  cat <<'EOF'
BLINDSPOT_FLEET
/usr/sbin/chown root:wheel "$d/gird-check.sh.new" "$d/gird-fleet.sh.new"
/bin/chmod 0755 "$d/gird-check.sh.new"
/bin/chmod 0700 "$d/gird-fleet.sh.new"
/bin/mv -f "$d/gird-check.sh.new" "$d/gird-check.sh"
/bin/mv -f "$d/gird-fleet.sh.new" "$d/gird-fleet.sh"
EOF
} > blindspot-install.sh
```

Read `blindspot-install.sh` before you upload it: it is both files, unchanged, inside a few install
lines. Have your MDM run it once, as root.

### 2. Run it daily

The MDM's daily script is this one line. `env -i` starts bash with an empty environment, so nothing
the MDM's environment names, such as `BASH_ENV`, runs first:

```sh
exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh"
```

### 3. Show the result

The MDM's inventory field runs this line. It only reads the saved result:

```sh
exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh" --inventory --stale-days=3
```

## More

- Your MDM, step by step: [Jamf Pro](mdm/jamf.md), [Iru](mdm/iru.md),
  [Microsoft Intune](mdm/intune.md), [ManageEngine Endpoint Central](mdm/manageengine-endpoint-central.md)
  ([Mobile Device Manager Plus](mdm/manageengine-mdm-plus.md)).
- [The reference](fleet-reference.md): trying it on your own Mac, having your coding agent review it,
  timing and the deadline, ripgrep, every option, the full outcome definitions, what each account's
  check reads, files that can be left behind, and how to update or remove it.
- [The design](designs/fleet-mode.md), with what it does not cover.

## Windows

For IT administrators who manage Windows PCs through an MDM. Steps 1 to 3 add the check. The sections
after them say how to read it.

On Windows, one file, `blindspot-fleet.ps1`, runs once a day as the person who is signed in. It checks
that person's account with their own rights. It needs no administrator rights and nothing runs as
SYSTEM, the Windows account that runs services. There is nothing to install first: the file carries
the check inside it.

What it never does:

- Send anything anywhere. It makes no network request.
- Show a path, a file name or a key. The result holds counts and names from fixed lists.
- Change anything in a person's files. It reads them. It writes in that person's own
  `%LOCALAPPDATA%\Blindspot` folder: the check it unpacks and the saved result, `last.json`.

### 1. Get the file and check it

Take `blindspot-fleet.ps1` from a tagged release. Check its SHA-256 against the one published for that
release:

```powershell
(Get-FileHash .\blindspot-fleet.ps1).Hash
```

The file is plain text. The part that starts the check, `gird-fleet.ps1`, keeps its comments, so you
can read it before you deploy it.

### 2. Add it to your MDM

Add `blindspot-fleet.ps1` as a script with these settings:

- Run it once a day.
- Run it as the signed-in user, not as SYSTEM. As SYSTEM the result is `failed`, reason `system_account`.
- Run it in 64-bit PowerShell. In 32-bit PowerShell the result is `failed`, reason `host_32bit`.
- Give it no arguments. It stops after 1,500 seconds (25 minutes).
  `-Deadline <seconds>` changes that.

[docs/mdm/intune.md](mdm/intune.md#windows) has these steps for Microsoft Intune.

### 3. Read the result

Each run prints one line, the inventory value, and your MDM keeps it. It is the same kind of line as
on a Mac, with the number of other profiles added after the time:

```
v1 act 2026-10-25T09:12Z other_profiles=2 | asha: act incidents tanstack; keys 2 anthropic,aws
```

The PC does not judge how old a result is: read the time in the line. A run that prints nothing, or
ends with an exit code your MDM does not expect, means the PC was not checked.

| Option | What it does |
|---|---|
| `-Json` | Prints the full result as JSON and nothing else. |
| `-Summary` | Prints one summary line. Not with `-Json`. |
| `-Deadline <seconds>` | The run aims to finish before this. 1500 if not given. |
| `-ExitZero` | Exits 0 whenever the run finished; `failed` still exits 1. |
| `-MacExitCodes` | Exits with the codes of a Mac: 0, 10, 11, 12 or 13. |

Without options the exit code is 0 for `clear` and 1 for anything else. Intune lists a PC that exits 1
as a PC with issues.

### What each outcome means

The outcomes are the five in the table in [What you get](#what-you-get), and `act`,
`review`, `not_checked` and `clear` mean the same here. The exit codes are the ones above, not the
table's. What to do about a finding is in [Act on a finding](fleet-reference.md#act-on-a-finding); read
"Keychain" as your secrets store.

### What is different on Windows

- **Only the signed-in account is checked.** SYSTEM cannot start a check as another account, and
  reading every home folder as SYSTEM would use more rights than the people have. A result speaks
  for one account, not for the PC. On a shared PC each account gets its own result the first time
  its check runs after that person signs in.
- **Other profiles are counted, not read.** `other_profiles` is the number of other people who have a
  profile on the PC. Their accounts were not checked in this run. A local account your IT team made
  for itself counts too.
- **A person can change their own result.** The check runs with that person's rights, so a person who
  sets out to can change what their check reports, and so can any program that runs as them. A
  standard account cannot change another account's result. Fleet mode shows where keys and agents sit
  across honest PCs. It is not a control against the person at the keyboard, and `clear` from a PC
  that malware already runs on proves nothing.
- **Some PCs restrict PowerShell.** Where PowerShell runs only a reduced language (Constrained
  Language Mode), the check cannot run. The result is `failed` with `reason=language_mode`. Where a
  policy stops PowerShell from running the file at all, nothing is printed.
- **Two places outside the person's folder are looked at by name.** Agents installed under
  `%ProgramFiles%`, and malware markers in `%ProgramData%`, which are judged by who owns the file.

### Why a run reads `failed`

A `failed` result ends with `reason=` and one of these:

| Reason | What happened |
|---|---|
| `host_32bit` | The MDM ran it in 32-bit PowerShell. Switch it to 64-bit. |
| `system_account` | The MDM ran it as SYSTEM, LocalService or NetworkService. Run it as the signed-in user. |
| `language_mode` | PowerShell on this PC runs only the reduced language. |
| `unpack` | The check inside the file could not be read, did not match its SHA-256, could not be written to the person's profile, or changed just before it started. Also when the file was run from standard input. |
| `save` | The result could not be saved. |
| `start` | The check could not be started. |
| `no_output` | The check ended without printing anything, for a reason other than the language mode. |

### Update or remove it

To update, replace the script in your MDM with the new release, after checking its SHA-256. To
remove it, delete the MDM's item. Each person's `%LOCALAPPDATA%\Blindspot` folder stays until it is
deleted.

The design, with what it does not cover, is in
[docs/designs/fleet-mode.md](designs/fleet-mode.md#windows).

