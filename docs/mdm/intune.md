# Blindspot with Microsoft Intune

**Untested:** this page has not yet been run end to end on a real Mac with Intune. Menu paths and
limits were checked on 2026-10-24 against
[Microsoft's guide to shell scripts on macOS](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos).

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

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

1. Download `blindspot-fleet.sh` from a tagged release and check its SHA-256 against the release
   notes ([docs/fleet.md](../fleet.md#1-try-it-on-your-own-mac)). Do not edit it.
2. In the Microsoft Intune admin center, select **Devices** > **By platform** > **macOS** >
   **Manage devices** > **Scripts** > **Add**
   ([Microsoft's guide](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos#create-and-assign-a-shell-script-policy)).
3. In **Basics**, name it `Blindspot`, and select **Next**.
4. In **Script settings**, upload `blindspot-fleet.sh`, set **Run script as signed-in user** to
   **No**, so it runs as root, and in **Script frequency** choose daily. Leave **Max number of times
   to retry if script fails** as **Not configured**. Select **Next**.
5. In **Assignments**, select the device groups, then **Review + add** > **Add**.

With no options, it runs `--all-users --exit-zero --summary-to-stdout --deadline=3000`.

Optional: to read agent sessions with ripgrep, add a second script that runs once (**Script
frequency** **Not configured**) with the lines from "ripgrep (optional)" in
[docs/fleet.md](../fleet.md#3-add-it-to-your-mdm).

## Show the result

1. Save the reader lines from step 3 of [docs/fleet.md](../fleet.md#3-add-it-to-your-mdm) as a
   file, `blindspot-inventory.sh`. They only read the saved result.
2. Select **Devices** > **By platform** > **macOS** > **Organize devices** >
   **Custom attributes for macOS** > **Add**
   ([Microsoft's guide](https://learn.microsoft.com/en-us/intune/device-management/tools/run-shell-scripts-macos#create-and-assign-a-custom-attribute-for-macos-devices)).
3. In **Basics**, name it `Blindspot`, and select **Next**.
4. In **Attribute settings**, set **Data type of attribute** to **String**, select
   `blindspot-inventory.sh` as the **Script**, and select **Next**.
5. In **Assignments**, select the same device groups, then **Review + add** > **Add**.

## Moving from the two-file install

If you set Blindspot up with `Blindspot install` and `Blindspot check` scripts, first remove the
`Blindspot check` script's assignments, then add the script above, replace the custom attribute's
file with the reader lines, and remove `Blindspot install`. Then remove the old files as
[docs/fleet.md](../fleet.md#moving-from-two-files) says. Until they are gone, the result says
`old-install`.

## What you should see

In **Custom attributes** > `Blindspot` > **Device status**, the **Result** column shows one line per
Mac, such as:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws | itadmin: clear
```

It starts with the Mac's outcome: `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). `stale: last run <time>` means no check in 3 days,
`none` means the check has not run yet, `failed` means the last run stopped part-way or refused to
start (the reason follows), and `unreadable` means the saved result could not be trusted or read. Treat each of those, and an empty result, as not checked.

In **Scripts** > `Blindspot check` > **Device status**, **Success** means the check finished.
**Failed** means it could not run safely (`failed`), or Intune stopped it.

## Intune's limits

Checked 2026-10-24:

- A shell script file must be less than 1 MB. `blindspot-fleet.sh` is about 590 KB; each release
  is built to stay under 800,000 bytes, and refused at 1,000,000.
- Microsoft's guide does not say where the agent writes the script before running it. If the script's
  output says `must be owned by root and writable by no one else`, it names that folder; please
  report it.
- A shell script that runs longer than 60 minutes is stopped and reported as failed.
  `--deadline=3000` aims to finish the check within 50 minutes.
- A shell script runs as root unless **Run script as signed-in user** is **Yes**.
- A non-zero exit code reads **Failed**, so the check uses `--exit-zero`.
- Custom attribute scripts run every 8 hours. The value must be 20 KB or less; Blindspot's is at
  most 250 characters. A script that exits non-zero reads **Failed**.
- Microsoft's guide does not say which account a custom attribute script runs as. The reader needs
  root: run as another account, it prints `unreadable`.
- Scripts need the Intune management agent, at `/Library/Intune/Microsoft Intune Agent.app`.

## Seeing all your Macs, all the time

This is one check at a time. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
