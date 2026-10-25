# Blindspot with Iru

**Untested:** this page has not yet been run end to end on a real Mac. Steps and limits were checked
on 2026-10-24 against
[Iru's Custom Scripts guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview).

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

You add two Custom Script library items: one installs the scripts once, the other runs it daily.
Iru records the daily run's output, so its summary line is the result.

## Full Disk Access

Iru's agent settings profile grants its agent Full Disk Access. To check the agent's identifier and
code requirement on one of your enrolled Macs:

```sh
codesign -dr - "<path to the Iru agent app>"
```

Never grant it to `/bin/bash`. Check the result either way: each account's `protected_folders` is
`checked` once access works.

## Install it once

1. Prepare the install script as [docs/fleet.md](../fleet.md#3-add-it-to-your-mdm) says: a tagged
   release of `gird-check.sh` and `gird-fleet.sh` whose SHA-256 you checked, with the options line
   starting the second line of `gird-fleet.sh` (`--deadline=1800` for Iru), each pasted between its
   marker lines in the install script. This install step has not yet been run end to end on a real
   Mac.
2. Add a Custom Script library item named `Blindspot install`
   ([Iru's guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview)),
   and assign it to your Blueprints.
3. In **Execution Frequency**, choose **Install once per device**.
4. Paste the install script into the **Audit Script** field, and select **Save**.

## Run it daily

1. Add a second Custom Script library item named `Blindspot check`, assigned to the same
   Blueprints.
2. In **Execution Frequency**, choose **Run daily**.
3. Paste only these lines into the **Audit Script** field. Leave **Remediation Script** empty:

   ```sh
   #!/bin/bash
   exec /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh"
   ```

4. Select **Save**.

## What you should see

Each run's output is in the script's audit information, on the device status page. It is one line:

```
blindspot act accounts=2 act=1 review=0 not_checked=1 v=1.1.0 at=2026-10-25T09:12:00Z
```

The word after `blindspot` is the Mac's outcome: `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). The status reads **Pass** whenever the check
finished. **Error** means it could not run safely (`failed`); a missing summary line also means
not checked.

To have every Mac that is not clear read **Error**, leave out `--exit-zero`: every outcome except
`clear` then exits non-zero.

## Iru's limits

Checked 2026-10-24:

- Custom scripts always run as root.
- They run at every check-in (about every 15 minutes), daily, or on demand from Self Service.
- Standard output and standard error are kept in the script's audit information.
- An audit script that exits 0 reads **Pass**; any other exit code reads **Error** and starts the
  remediation script.
- Iru's guide does not state a time limit or a size limit for a script. `--deadline=1800` aims to finish the
  check within 30 minutes; change it to suit you.

## Seeing all your Macs, all the time

This is one check, once a day. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
