# Blindspot with Microsoft Intune

For IT administrators. This page has two parts: macOS first, then [Windows](#windows).

**Untested:** this page has not yet been run end to end on a real Mac. Menu paths and limits were
checked on 2026-10-24 against
[Microsoft's guide to shell scripts on macOS](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos).

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

You add three things: a shell script that installs the scripts once, a shell script that runs the
check, and a custom attribute that shows the result.

## Full Disk Access

Grant Full Disk Access to the Intune agent with a Privacy Preferences Policy Control profile
(`SystemPolicyAllFiles`), never to `/bin/bash`. Read its identifier and code requirement on one of
your enrolled Macs:

```sh
codesign -dr - "/Library/Intune/Microsoft Intune Agent.app"
```

Check the result: each account's `protected_folders` is `checked` once access works.

## Install it once

1. Prepare the install script as [docs/fleet.md](../fleet.md#3-add-it-to-your-mdm) says: a tagged
   release of `gird-check.sh` and `gird-fleet.sh` whose SHA-256 you checked, with the options line
   starting the second line of `gird-fleet.sh` (`--deadline=3000` for Intune), each pasted between
   its marker lines in the install script. This install step has not yet been run end to end on a
   real Mac.
   Optional: add the lines from "Install ripgrep (optional)" in [docs/fleet.md](../fleet.md#3-add-it-to-your-mdm)
   to its end, so large agent session stores take seconds per account rather than minutes.
2. Save the install script as a file, `blindspot-install.sh`.
3. In the Microsoft Intune admin center, select **Devices** > **By platform** > **macOS** >
   **Manage devices** > **Scripts** > **Add**
   ([Microsoft's guide](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos#create-and-assign-a-shell-script-policy)).
4. In **Basics**, name it `Blindspot install`, and select **Next**.
5. In **Script settings**, upload `blindspot-install.sh`, set **Run script as signed-in user** to
   **No**, leave **Script frequency** as **Not configured** so it runs once, and select **Next**.
6. In **Assignments**, select the device groups, then **Review + add** > **Add**.

## Run it daily

1. Save these lines as a file, `blindspot-check.sh`:

   ```sh
   #!/bin/bash
   exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh"
   ```

2. Add a second script the same way, named `Blindspot check`, uploading `blindspot-check.sh`.
3. Set **Run script as signed-in user** to **No**, so it runs as root.
4. In **Script frequency**, choose how often it runs; daily is suggested.
5. Leave **Max number of times to retry if script fails** as **Not configured**.
6. Assign it to the same device groups, then **Review + add** > **Add**.

## Show the result

1. Save these lines as a file, `blindspot-inventory.sh`. They only read the saved result:

   ```sh
   #!/bin/bash
   exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh" --inventory --stale-days=3
   ```

2. Select **Devices** > **By platform** > **macOS** > **Organize devices** >
   **Custom attributes for macOS** > **Add**
   ([Microsoft's guide](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos#create-and-assign-a-custom-attribute-for-macos-devices)).
3. In **Basics**, name it `Blindspot`, and select **Next**.
4. In **Attribute settings**, set **Data type of attribute** to **String**, select
   `blindspot-inventory.sh` as the **Script**, and select **Next**.
5. In **Assignments**, select the same device groups, then **Review + add** > **Add**.

## What you should see

In **Custom attributes** > `Blindspot` > **Device status**, the **Result** column shows one line per
Mac, such as:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws | itadmin: clear
```

It starts with the Mac's outcome: `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). `stale: last run <time>` means no check in 3 days,
`none` means the check has not run yet, `failed` means the last run stopped part-way, and
`unreadable` means the saved result could not be trusted. Treat each of those, and an empty result, as not checked.

In **Scripts** > `Blindspot check` > **Device status**, **Success** means the check finished.
**Failed** means it could not run safely (`failed`), or Intune stopped it.

## Intune's limits

Checked 2026-10-24:

- A shell script file must be less than 1 MB. The install script, with both files in it, is about 0.5 MB.
- A shell script that runs longer than 60 minutes is stopped and reported as failed.
  `--deadline=3000` aims to finish the check within 50 minutes.
- A shell script runs as root unless **Run script as signed-in user** is **Yes**.
- A non-zero exit code reads **Failed**, so the check uses `--exit-zero`.
- Custom attribute scripts run every 8 hours. The value must be 20 KB or less; Blindspot's is at
  most 250 characters. A script that exits non-zero reads **Failed**.
- Microsoft's guide does not say which account a custom attribute script runs as. The reader needs
  root: run as another account, it writes `needs root` to standard error and exits 13, so the
  attribute gets no value and reads **Failed**.
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
[docs/fleet.md](../fleet.md#4-read-the-results) for what each means and
[Why a run reads `failed`](../fleet.md#why-a-run-reads-failed) for the reasons. A PC with no output,
or an exit code you do not expect, was not checked. The script exits 1 unless the outcome is
`clear`, which Intune lists as a PC with issues.

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
