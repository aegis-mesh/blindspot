# Blindspot with Microsoft Intune

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
   exec /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh"
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
   exec /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh" --inventory --stale-days=3
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
v1 act 2026-10-25T09:12Z | asha: act tanstack; keys 2 anthropic,aws | itadmin: clear
```

It starts with the Mac's outcome: `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). `stale: last run <time>` means no check in 3 days,
`none` means the check has not run yet, and `unreadable` means the saved result could not be
trusted. Treat each of those, and an empty result, as not checked.

In **Scripts** > `Blindspot check` > **Device status**, **Success** means the check finished.
**Failed** means it could not run safely (`failed`), or Intune stopped it.

## Intune's limits

Checked 2026-10-24:

- A shell script file must be less than 1 MB. The install script, with both files in it, is about 220 KB.
- A shell script that runs longer than 60 minutes is stopped and reported as failed.
  `--deadline=3000` aims to finish the check within 50 minutes.
- A shell script runs as root unless **Run script as signed-in user** is **Yes**.
- A non-zero exit code reads **Failed**, so the check uses `--exit-zero`.
- Custom attribute scripts run every 8 hours. The value must be 20 KB or less; Blindspot's is at
  most 250 characters. A script that exits non-zero reads **Failed**.
- Microsoft's guide does not say which account a custom attribute script runs as. The reader needs
  root: if the **Result** column shows `needs root`, it did not run as root.
- Scripts need the Intune management agent, at `/Library/Intune/Microsoft Intune Agent.app`.

## Seeing all your Macs, all the time

This is one check at a time. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
