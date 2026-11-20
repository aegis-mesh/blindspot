# Blindspot with Microsoft Intune

For IT administrators. This page has two parts: macOS first, then [Windows](#windows).

**Untested:** this page has not yet been run end to end on a real Mac with Intune. Menu paths and
limits were checked on 2026-10-24 against
[Microsoft's guide to shell scripts on macOS](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos).

Read [docs/fleet.md](../fleet.md) first: what the check does and what each outcome means.
[docs/fleet-reference.md](../fleet-reference.md#act-on-a-finding) says what to do about a finding.

You add two things: the file as a shell script that runs daily, and a custom attribute that shows the
result. There is nothing to install first.

## Full Disk Access

Grant Full Disk Access to the Intune agent with a Privacy Preferences Policy Control profile
(`SystemPolicyAllFiles`), never to `/bin/bash`. Read its identifier and code requirement on one of
your enrolled Macs:

```sh
codesign -dr - "/Library/Intune/Microsoft Intune Agent.app"
```

Check the result: each account's `protected_folders` is `checked` once access works.

## Run it daily

1. Download `blindspot-fleet.sh` from a release and check it as
   [docs/fleet.md](../fleet.md#1-download-the-file) says. Do not edit it.
2. In the Microsoft Intune admin center, select **Devices** > **By platform** > **macOS** >
   **Manage devices** > **Scripts** > **Add**
   ([Microsoft's guide](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos#create-and-assign-a-shell-script-policy)).
3. In **Basics**, name it `Blindspot`, and select **Next**.
4. In **Script settings**, upload `blindspot-fleet.sh` and set **Run script as signed-in user** to
   **No**, so it runs as root. In **Script frequency**, choose once a day. Leave **Max number of times
   to retry if script fails** as **Not configured**. Select **Next**.
5. In **Assignments**, select the device groups, then **Review + add** > **Add**.

With no options, the file runs `--all-users --exit-zero --summary-to-stdout --deadline=3000`.

Optional: to read agent sessions with ripgrep, add a second script the same way, with the lines from
[Install ripgrep (optional)](../fleet-reference.md#install-ripgrep-optional) saved as a file, and
leave its **Script frequency** as **Not configured** so it runs once. Large agent session stores then
take seconds per account rather than minutes.

## Show the result

1. Save the lines from [step 3 of docs/fleet.md](../fleet.md#3-show-the-result) as a file,
   `blindspot-inventory.sh`. They only read the saved result.
2. Select **Devices** > **By platform** > **macOS** > **Organize devices** >
   **Custom attributes for macOS** > **Add**
   ([Microsoft's guide](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos#create-and-assign-a-custom-attribute-for-macos-devices)).
3. In **Basics**, name it `Blindspot`, and select **Next**.
4. In **Attribute settings**, set **Data type of attribute** to **String**, select
   `blindspot-inventory.sh` as the **Script**, and select **Next**.
5. In **Assignments**, select the same device groups, then **Review + add** > **Add**.

## Moving from the two-file install

If you set Blindspot up with `Blindspot install` and `Blindspot check` scripts from an earlier
release, first remove the `Blindspot check` script's assignments, so two checks do not run. Then add
the script above, replace the custom attribute's file with `blindspot-inventory.sh`, and remove
`Blindspot install`. Then remove the old files as
[docs/fleet.md](../fleet.md#moving-from-two-files) says. Until they are gone, the result says
`old-install`.

## What you should see

In **Custom attributes** > `Blindspot` > **Device status**, the **Result** column shows one line per
Mac, such as:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws | itadmin: clear | owasp.ASI03:1 owasp.ASI04:1; counted 2
```

It starts with the Mac's outcome: `failed`, `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#what-you-get)). A Mac whose OWASP tags could not be worked out reads
`v1 failed` even when it has findings to act on, so a filter on `v1 act` misses it: filter for
`v1 failed` too. `stale: last run <time>` means no check in 3 days, `none` means the check has not run
yet, `failed` means the last run stopped part-way or refused to start (the reason follows),
`old-install` means the one file has not yet finished a run where an earlier install saved a result,
and `unreadable` means the saved result could not be trusted or read. Treat each of those, and an
empty result, as not checked.

The `owasp.` part at the end names the OWASP risks found
([OWASP tags](../fleet-reference.md#owasp-tags)); to list the Macs with one, filter for values that
contain `owasp.ASI03`. The value carries the part only when it has room, so a Mac with no room for it
does not match; the saved result, `last.json`, always carries it.

In **Scripts** > `Blindspot` > **Device status**, **Success** means the check finished. **Failed**
means it could not run safely or stopped before it started (`failed`), or Intune stopped it.

To see every Mac in one report, export the **Result** column as a CSV file and run `gird-report.ps1`
on it: [one report for every computer](../fleet.md#one-report-for-every-computer).

## Intune's limits

Checked 2026-10-24:

- A shell script file must be less than 1 MB. `blindspot-fleet.sh` is about 750 KB. `tools/gen.sh`
  warns when a release's file reaches 800,000 bytes, and does not build one of 1,000,000 bytes or
  more.
- A shell script that runs longer than 60 minutes is stopped and reported as failed.
  `--deadline=3000` aims to finish the check within 50 minutes.
- A shell script runs as root unless **Run script as signed-in user** is **Yes**.
- A shell script must start with `#!` and a shell (checked 2026-11-18). The file starts
  `#!/bin/bash -p`, and stops (exit 13) if it was started without `-p`. The guide does not say
  outright that the agent starts the file by that line; if the output says
  `start it as its first line says`, it did not.
- Microsoft's guide does not say where the agent writes a script before running it. If the output
  says `must be owned by root and writable by no one else`, it names that folder; please
  [report it](https://github.com/aegis-mesh/blindspot/issues/new/choose)
  ([why it matters](../fleet-reference.md#how-the-one-file-runs)).
- A non-zero exit code reads **Failed**. With no options the file exits 0 whenever the check
  finished, so only a run that `failed` reads **Failed**.
- Custom attribute scripts run every 8 hours. The value must be 20 KB or less; Blindspot's is at
  most 250 characters. A script that exits non-zero reads **Failed**.
- Microsoft's guide does not say which account a custom attribute script runs as. The lines need
  root: run as another account, they print `unreadable`.
- Scripts need the Intune management agent, at `/Library/Intune/Microsoft Intune Agent.app`.

## Windows

**Untested:** this section has not yet been run end to end on a real PC through Intune. Menu paths,
setting names and limits were checked on 2026-11-18 against
[Microsoft's guide to Remediations](https://learn.microsoft.com/en-us/intune/device-management/tools/deploy-remediations),
which Microsoft last updated on 2026-11-04.

Read [docs/fleet.md](../fleet.md#windows) first: what the check does and what each outcome means.

The daily check is an Intune Remediation: a script that Intune runs on a schedule and whose output it
shows for each PC. You add one script, `blindspot-fleet.ps1`, as the detection script. There is no
remediation script, and nothing to install first.

### What you need

- Each PC is Microsoft Entra joined or Microsoft Entra hybrid joined, enrolled in Intune, and runs
  Windows Enterprise, Professional or Education.
- A licence for the people who use the PCs: Windows Enterprise E3 or E5 (included in Microsoft 365 F3,
  E3 or E5), Windows Education A3 or A5 (included in Microsoft 365 A3 or A5), or Windows Virtual
  Desktop Access (VDA) per user.
- `blindspot-fleet.ps1` from a tagged release whose SHA-256 you checked, as in
  [docs/fleet.md](../fleet.md#1-get-the-file-and-check-it).

### Add the Remediation

1. In the [Microsoft Intune admin center](https://go.microsoft.com/fwlink/?linkid=2109431), select
   **Devices** > **Manage devices** > **Scripts and remediations** > **Create script package**.
2. In **Basics**, give it a **Name**, such as `Blindspot`, and select **Next**.
3. In **Settings**, select the folder icon next to **Detection script file** and upload
   `blindspot-fleet.ps1`. Leave **Remediation script file** empty.
4. Set these three:
   - **Run this script using the logged-on credentials**: **Yes**.
   - **Enforce script signature check**: **No**. The file is not signed.
   - **Run script in 64-bit PowerShell**: **Yes**.
5. Select **Next**, add any **Scope tags** you use, and select **Next**.
6. In **Assignments**, select the device groups. Set the **Schedule** to **Daily** and choose a time.
7. Select **Next**, then **Create**.

Microsoft's page recommends **No** for **Run script in 64-bit PowerShell** in general. Here it must be
**Yes**: in 32-bit PowerShell the result is `failed` with `reason=host_32bit`.

### What you should see

Select **Devices** > **Manage devices** > **Scripts and remediations**, open the script package and
select **Device status**. It shows the output of each PC's run, such as:

```
v1 act 2026-10-25T09:12Z other_profiles=2 | asha: act incidents tanstack; keys 2 anthropic,aws
```

**Export** saves the outputs as a `.csv` file. For one PC, select **Devices** > **By platform** >
**Windows**, select the PC, then **Remediations** in the **Monitor** section.

The line starts with the outcome: `act`, `review`, `not_checked`, `clear` or `failed`. See
[docs/fleet.md](../fleet.md#what-you-get) for what each means and
[Why a run reads `failed`](../fleet.md#why-a-run-reads-failed) for the reasons. A PC with no output,
or an exit code you do not expect, was not checked. The script exits 1 unless the outcome is
`clear`, which Intune lists as a PC with issues.

### Or let gird-intune.ps1 do it

`gird-intune.ps1`, from the same release, is an optional tool that does the steps above for you and
exports the results for [the fleet report](../fleet.md#one-report-for-every-computer). It runs on
your own PC, in Windows PowerShell 5.1 or PowerShell 7. It signs in to Microsoft Graph as you, with
Microsoft's own module, `Microsoft.Graph.Authentication`, and sends nothing anywhere else. Before it
signs in, it prints the permissions it will ask for: the fewest each command needs. It has not yet
been run against a real Intune tenant: its tests use a stand-in for Microsoft Graph.

| Command | What it does |
|---|---|
| `gird-intune.ps1 -Deploy -Group <name>` | Adds `blindspot-fleet.ps1`, from next to it or from `-FleetScript <path>`, as a Remediation for that group only: run as the signed-in person, in 64-bit PowerShell, once a day, with no remediation script. Run again with a newer release, it updates the one it made. |
| `gird-intune.ps1 -Export <file.csv>` | Writes each PC's latest result to a new CSV file, with a row for each Windows PC in the assigned groups that has no result yet. |
| `gird-intune.ps1 -Remove` | Shows the Remediation it made and asks before deleting it. `-Force` skips the question. |

`-WhatIf` with `-Deploy` or `-Remove` shows what would change and changes nothing. On Windows, run it
as `powershell -ExecutionPolicy Bypass -File .\gird-intune.ps1 -Deploy -Group "<name>"`.

### Intune's limits

Checked 2026-11-18:

- The output is kept to 2,048 characters. Blindspot's line is at most 2,047.
- A script package can hold a detection script on its own. Scripts must be encoded in UTF-8.
- Intune reruns the scripts every 24 hours. A PC gets new settings after a restart, after a person
  signs in, and every 8 hours.
- A recurring script reports within its first six days only when its output changes, and every seven
  days even if it does not. Blindspot's line carries the time of the check, so it changes on each run.
- A missed run happens as soon as the PC is back online.

## Seeing all your Macs, all the time

This is one check at a time. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
