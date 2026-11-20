# Blindspot for IT teams

`blindspot-fleet.sh` checks every account on a Mac for what Blindspot shows one person: coding agents,
keys in plain text and in agent sessions, agents and project settings that run commands without
asking, and signs of recent malware. It is one file. Your MDM runs it as root once a day, with no
options, and shows one line per Mac. This page is about Macs up to [Windows](#windows), which has
steps of its own. Linux has no fleet mode yet
([issue #39](https://github.com/aegis-mesh/blindspot/issues/39)).

**Before you deploy:**

- It runs as root, and only from a file that root alone can change. It checks each account as that
  account.
- It reads files and changes nothing in any home folder.
- It sends nothing anywhere. It makes no network request.
- It keeps its result in `/var/db/blindspot`, readable by root only, with a copy of itself for your
  MDM's inventory field. The result holds counts and names from fixed lists, never a path, a file
  name or a key. A few other files can remain:
  [what can be left behind](fleet-reference.md#files-that-can-be-left-behind).

`blindspot-fleet.sh` has not yet been run under a real MDM, and the [MDM pages](mdm/) have not been
run end to end, so each is marked untested. Try it on a few Macs before the whole fleet.

## What you get

Your MDM shows one line per Mac, such as:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear | owasp.ASI03:1 owasp.ASI04:1; counted 2
```

The first word after `v1` is the Mac's outcome, the worst of its accounts and of the Mac's own check:

| Outcome | Means | Exit code |
|---|---|---|
| `act` | Act now: malware signs, or keys in plain text, shell history, agent sessions, MCP configs or allow lists. | 10 |
| `not_checked` | An account, or part of one, was not checked. Never read this as clear. | 12 |
| `review` | Something to change or confirm, not urgent, such as an agent set to run without asking. | 11 |
| `clear` | Every account was checked in full and nothing was found. | 0 |
| `failed` | The run could not finish safely. | 13 |

The exit codes are for a run whose options leave out `--exit-zero`. Run as your MDM runs it, with no
options, the file exits 0 whenever the run finished and 13 when it `failed`, and the outcome is in
the line it prints.

The field can also read `stale` (no run in 3 days), `none` (no run yet), `failed` (a run stopped
part-way, could not save its result or refused to start, and why), `old-install` (an
[earlier install](#moving-from-two-files) saved a result and the one file has not yet finished a run)
or `unreadable`. Treat each of those as not checked.

The [full definitions](fleet-reference.md#outcomes-in-full) list everything each outcome covers.
Start with the Macs whose value starts `v1 act`, then `v1 failed`, `v1 not_checked`, `failed` and
`stale`. A run whose OWASP tags could not be worked out reads `v1 failed` even when it has findings to
act on. [What to do about each finding](fleet-reference.md#act-on-a-finding).

### OWASP Agentic Top 10 tags

Each finding is also tagged with the risk of the
[OWASP Top 10 for Agentic Applications (2026)](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
it falls under. The mapping is Blindspot's own, not OWASP's, and covers ASI02 to ASI05, the risks
files on disk can show, so a missing tag never means a risk is absent. A Mac's summary line and saved
result always carry the tags. The line above ends with them only when they fit: `owasp.ASI03:1` is
the number of checked accounts with that risk. [More on the tags](fleet-reference.md#owasp-tags).
Windows fleet mode does not tag them yet.

| Risk | Tagged on |
|---|---|
| ASI02 Tool Misuse and Exploitation | run without asking, remote commands without asking |
| ASI03 Identity and Privilege Abuse | tokens in MCP configs, links to authorized_keys, keys in plain text, keys in shell history, keys in agent sessions, SSH keys without a passphrase, keys in allow lists |
| ASI04 Agentic Supply Chain Vulnerabilities | tools with a security fix, malware signs (an account's, or the Mac's own), versions to update, gh-token-monitor, files a worm plants, SSH keys malware adds, npm malware in a lockfile, Python versions to update, extensions to remove, platforms with a leak |
| ASI05 Unexpected Code Execution | settings that act on opening, scripts started like worms |

## Set it up

Your MDM's agent needs Full Disk Access, or each account reads `not_checked`: the
[page for your MDM](mdm/) says how. Grant it to the MDM's agent, never to a shell such as `/bin/bash`
([why](fleet-reference.md#full-disk-access)).

### 1. Download the file

Download `blindspot-fleet.sh` and `SHA256SUMS` from the same
[release](https://github.com/aegis-mesh/blindspot/releases), then check the file:

```sh
grep ' blindspot-fleet.sh$' SHA256SUMS | shasum -a 256 -c   # prints blindspot-fleet.sh: OK
```

When the release also carries `SHA256SUMS.sig`,
[checking a download](designs/signed-releases.md#checking-a-download) shows how to check that the
maintainers signed `SHA256SUMS`. The file is plain text: `gird-fleet.sh`, which holds all the root
code, with `gird-check.sh`, less its game, after its last line. Use it as it is, with nothing to
edit. You can [have your coding agent review it](fleet-reference.md#have-your-coding-agent-review-it)
and [try it on your own Mac](fleet-reference.md#try-it-on-your-own-mac) first.

### 2. Run it daily

Add the file to your MDM as a script that runs as root once a day, with no options. That is the whole
install: there is no folder to make and no second file. With no options it runs
`--all-users --exit-zero --summary-to-stdout --deadline=3000`: it checks every account, saves the
result, prints one summary line and exits 0 whenever it finished, 13 when it failed. Your MDM must
start the file by its first line, `#!/bin/bash -p`, from a place only root can change. Otherwise it
stops before it does anything (exit 13) and says why:
[how the one file runs](fleet-reference.md#how-the-one-file-runs).

### 3. Show the result

Where your MDM has an inventory field (Jamf Pro's extension attribute, Intune's custom attribute),
give it these lines. They only read the saved result, through the copy of the file the last run kept,
and never check anything:

```sh
#!/bin/bash -p
# Blindspot: prints the saved result. It never checks anything.
blindspot_inventory() {
  d=/var/db/blindspot
  [ -e "$d" ] || { echo none; return; }
  [ -r "$d" ] && [ -x "$d" ] || { echo unreadable; return; }
  if [ -f "$d/blindspot-fleet.sh" ]; then
    /usr/bin/env -i /bin/bash -p "$d/blindspot-fleet.sh" --inventory --stale-days=3 2>/dev/null || echo unreadable
  elif [ -f "$d/refused" ]; then echo "failed: $(/usr/bin/head -n 1 "$d/refused")"
  elif [ -f "$d/last.json" ]; then echo "old-install: the saved result is from an earlier release"
  elif [ -f "$d/attempt" ]; then
    a=$(/usr/bin/head -n 1 "$d/attempt"); s=${a%% *}; l=${a#* }
    case "$s" in ''|*[!0-9]*) echo unreadable; return ;; esac
    case "$l" in ''|*[!0-9]*) echo unreadable; return ;; esac
    if [ "${#s}" -le 12 ] && [ "${#l}" -le 5 ] && s=$((10#$s)) && [ $(( $(/bin/date -u +%s) - s )) -gt "$l" ]; then
      echo "failed: the run started $(/bin/date -u -r "$s" +%Y-%m-%dT%H:%MZ) did not finish or could not save its result"
    else echo none; fi
  else echo none; fi
}
blindspot_inventory
```

For Jamf Pro, the last line is `echo "<result>$(blindspot_inventory)</result>"`. Run as an account
that cannot open `/var/db/blindspot`, they print `unreadable`, never `none`. Iru has no inventory
field: the summary line each daily run prints, which Iru keeps, is the result.

### 4. Update or remove it

To update, check the next release's file as in step 1 and replace the file in your MDM's item. The
lines in step 3 stay the same.

To remove it, delete the MDM's items, then on each Mac remove the saved result, the copy kept for the
inventory field, any saved-result folder that was moved aside, and ripgrep if you installed it:

```sh
sudo /bin/rm -rf /var/db/blindspot /var/db/blindspot.replaced-* "/Library/Application Support/Blindspot"
```

A run your MDM stopped can leave root's work folders in `/private/tmp`. Once no Blindspot check is
running, remove them with:

```sh
sudo /usr/bin/find /private/tmp -mindepth 1 -maxdepth 1 -type d -user 0 \( -name 'blindspot-run.????????' -o -name 'blindspot-fleet.????????' -o -name 'blindspot-copy.????????' \) -exec /bin/rm -rf {} +
```

It removes only folders root owns, directly in `/private/tmp`, named exactly so, and follows no link
([why that is safe](fleet-reference.md#update-or-remove-it)).

### Moving from two files

An earlier release installed `gird-fleet.sh` and `gird-check.sh` in
`/Library/Application Support/Blindspot`, with an install item, a daily item and an inventory item.
While either file is still there, the result says so: `old-install` in the inventory value,
`old_install=yes` at the end of the summary line. To move to the one file:

1. Remove the old daily item from your MDM first, so two checks do not run.
2. Add the one file as in step 2, and replace the inventory item's lines with the ones in step 3.
3. Remove the old install item, then the two files on each Mac. Keep `rg` in that folder if you
   installed ripgrep: the one file uses it from there.

   ```sh
   sudo /bin/rm -f "/Library/Application Support/Blindspot/gird-fleet.sh" "/Library/Application Support/Blindspot/gird-check.sh"
   ```

## More

- Your MDM, step by step: [Jamf Pro](mdm/jamf.md), [Iru](mdm/iru.md),
  [Microsoft Intune](mdm/intune.md), [ManageEngine Endpoint Central](mdm/manageengine-endpoint-central.md)
  ([Mobile Device Manager Plus](mdm/manageengine-mdm-plus.md)).
- [One report for every computer](#one-report-for-every-computer), Macs and Windows PCs together.
- [The reference](fleet-reference.md): having your coding agent review the file, trying it on your
  own Mac, how the one file runs, ripgrep, timing and the deadline, every option, the full outcome
  definitions, the OWASP tags, what each account's check reads, and files that can be left behind.
- [The design](designs/fleet-mode.md), with what it does not cover.

## Windows

For IT administrators who manage Windows PCs through an MDM. Steps 1 to 3 add the check. The sections
after them say how to read it.

On Windows, one file, `blindspot-fleet.ps1`, runs once a day as the person who is signed in. It checks
that person's account with their own rights. It needs no administrator rights and nothing runs as
SYSTEM, the Windows account that runs services. There is nothing to install first: the file carries
the check inside it. It has not yet been run on a real Windows PC.

What it never does:

- Send anything anywhere. It makes no network request.
- Show a path, a file name or a key. The result holds counts and names from fixed lists.
- Change anything in a person's files. It reads them. It writes in that person's own
  `%LOCALAPPDATA%\Blindspot` folder: the check it unpacks and the saved result, `last.json`.

### 1. Get the file and check it

Download `blindspot-fleet.ps1` and `SHA256SUMS` from the same
[release](https://github.com/aegis-mesh/blindspot/releases), then check the file. This prints `True`
when its SHA-256 matches its line in `SHA256SUMS`:

```powershell
(Get-FileHash .\blindspot-fleet.ps1).Hash -eq ((Select-String -Path .\SHA256SUMS -Pattern ' blindspot-fleet.ps1$').Line -split ' ')[0]
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

[docs/mdm/intune.md](mdm/intune.md#windows) has these steps for Microsoft Intune, and
`gird-intune.ps1`, an optional tool that does them for you.

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
- **No OWASP tags yet.** The PC's result carries no `owasp` part. A person's own report on Windows,
  `gird-check.ps1`, shows the tags as on a Mac.

### Why a run reads `failed`

A `failed` result ends with `reason=` and one of these:

| Reason | What happened |
|---|---|
| `host_32bit` | The MDM ran it in 32-bit PowerShell. Switch it to 64-bit. |
| `system_account` | The MDM ran it as SYSTEM, LocalService or NetworkService. Run it as the signed-in user. |
| `language_mode` | PowerShell on this PC runs only the reduced language. |
| `unpack` | The check inside the file could not be read, did not match its SHA-256, could not be written to the person's profile, or changed just before it started. Also when `gird-fleet.ps1` on its own, without the check packed in, was run from standard input. |
| `save` | The result could not be saved. |
| `start` | The check could not be started. |
| `no_output` | The check ended without printing anything, for a reason other than the language mode. |

### Update or remove it

To update, replace the script in your MDM with the new release, after checking its SHA-256. To
remove it, delete the MDM's item. Each person's `%LOCALAPPDATA%\Blindspot` folder stays until it is
deleted.

The design, with what it does not cover, is in
[docs/designs/fleet-mode.md](designs/fleet-mode.md#windows).

## One report for every computer

`gird-report.ps1` turns your MDM's results, from Macs and Windows PCs, into one report: what was found
on how many computers, the computers to deal with first, the ones not checked, and how the findings
relate to MITRE ATT&CK, MITRE ATLAS and NIST CSF 2.0. It runs on your own computer and reads only the
files you give it. It does not sign in anywhere and makes no network request.

1. In your MDM, export the computer list with the column that shows the Blindspot result, as a CSV
   file: Jamf Pro's `Blindspot` extension attribute, or the **Result** column of Intune's custom
   attribute for Macs. For Intune on Windows, `gird-intune.ps1 -Export intune.csv` writes that file
   for you ([the Intune page](mdm/intune.md#windows)); an export from the Intune admin center works
   too.
2. Download `gird-report.ps1` from the same release as the fleet file, check it against `SHA256SUMS`
   as in [step 1](#1-download-the-file), and run it in the folder that holds both:

   ```sh
   pwsh ./gird-report.ps1 export.csv
   ```

   On a Mac or Linux this needs PowerShell 7: see Microsoft's
   [Install PowerShell 7 on macOS](https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-macos).
   On Windows, run `powershell -ExecutionPolicy Bypass -File .\gird-report.ps1 export.csv`.

It saves an HTML and a CSV report in that folder and prints where. A computer with no result, an old
result or one it cannot read is listed as not checked, never as clear. Iru keeps the summary line,
which names no findings, so the report lists an Iru Mac as not checked. This release's report does
not yet read every part a result can hold:
[what it does not read](fleet-reference.md#the-fleet-report).
