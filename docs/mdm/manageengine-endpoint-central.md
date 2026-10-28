# Blindspot with ManageEngine Endpoint Central

**Untested:** this page has not yet been run end to end on a real Mac. Menu paths and limits were
checked on 2026-10-28 against ManageEngine's documentation, linked at each step. Endpoint Central's
documentation leaves several things out, such as which account a Mac script runs as and its time
limit; [Endpoint Central's limits](#endpoint-centrals-limits) lists them.

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

Using Mobile Device Manager Plus without Endpoint Central? Read
[its page](manageengine-mdm-plus.md) instead.

You add two Mac computer configurations: a custom script that installs the scripts once, and a
custom script that runs the check.

## Full Disk Access

Endpoint Central grants its own agent Full Disk Access on the Macs it manages
([macOS Agent Permissions via MDM](https://www.manageengine.com/products/desktop-central/help/device-onboarding/permissions-for-endpoint-central-agent-via-mdm.html)):
the agent service, `dcagentservice`, gets `SystemPolicyAllFiles`. If you enrolled the Macs through
another MDM, that page lists the profile to deploy. Never grant it to `/bin/bash`.

Check the result: each account's `protected_folders` is `checked` once access works.

## Install it once

1. Prepare the install script as [docs/fleet.md](../fleet.md#3-add-it-to-your-mdm) says: a tagged
   release of `gird-check.sh` and `gird-fleet.sh` whose SHA-256 you checked, each pasted between its
   marker lines in the install script. For Endpoint Central, the options line that starts the
   second line of `gird-fleet.sh` leaves out `--exit-zero`, so the exit code carries the outcome:

   ```sh
   case " $* " in *" --inventory "*|*" --list "*|*" --help "*|*" -h "*) ;; *) set -- --all-users --summary-to-stdout --deadline=3000 ;; esac
   ```

   Optional: add the lines from "Install ripgrep (optional)" in [docs/fleet.md](../fleet.md#3-add-it-to-your-mdm)
   to its end, so large agent session stores take seconds per account rather than minutes.
2. Save the install script as a file, `blindspot-install.sh`.
3. Click **Configurations** > **Script Repository** > **Add Script**, and add
   `blindspot-install.sh`
   ([Custom Scripts](https://www.manageengine.com/products/desktop-central/help/configuring_desktop_central/managing_custom_scripts.html)).
   A configuration can only run a script that is in the repository.
4. Click **Configurations**, then under **Add Configurations** click **Configurations**, open the
   **Mac** tab, and choose **Custom Scripts** > **Computer**
   ([Custom Scripts for Mac computers](https://www.manageengine.com/uk/desktop-management-msp/help/mac_configurations/executing_custom_scripts_for_computer.html)).
5. Name it `Blindspot install`, and choose `blindspot-install.sh` from the repository. Leave the
   arguments and dependency files empty.
6. Set the exit code to `0`.
7. Set the frequency to run only once.
8. Choose the target Macs, and deploy it.

## Run it daily

Endpoint Central can run a Mac computer script once, at startup, or at every refresh cycle, which is
every 90 minutes
([Execution Settings](https://www.manageengine.com/products/desktop-central/help/configuring_execution_settings.html)).
It has no daily setting. So the check script below runs at every refresh cycle, and starts a full
check only when the saved result is more than a day old, or the last run failed. Otherwise it
prints the saved result and exits with its outcome's code.

1. Save these lines as a file, `blindspot-check.sh`:

   ```sh
   #!/bin/bash
   f="/Library/Application Support/Blindspot/gird-fleet.sh"
   v=$(/usr/bin/env -i /bin/bash "$f" --inventory --stale-days=1)
   case "$v" in
     "v1 clear "*) printf '%s\n' "$v"; exit 0 ;;
     "v1 act "*) printf '%s\n' "$v"; exit 10 ;;
     "v1 review "*) printf '%s\n' "$v"; exit 11 ;;
     "v1 not_checked "*) printf '%s\n' "$v"; exit 12 ;;
   esac
   exec /usr/bin/env -i /bin/bash "$f"
   ```

   A result that reads `none`, `stale`, `failed` or `unreadable` starts a full check. While a check
   is running, the saved result is the one before it, so a refresh cycle never starts a second
   check.
2. Add it to the Script Repository as in step 3 above.
3. Add a second Mac computer custom script the same way, named `Blindspot check`, with
   `blindspot-check.sh`.
4. Set the exit code to `0`. Only a Mac whose outcome is `clear` then reads as successful.
5. In its execution settings, choose to apply it at every refresh cycle.
6. If the configuration offers **Enable logging for troubleshooting**, turn it on.
7. Choose the same target Macs, and deploy it.

## What you should see

Under **Configurations** > **All Configurations** > `Blindspot check` > **Execution Status**, a Mac
whose outcome is `clear` reads as successful. Any other outcome reads as failed, with exit code 10
for `act`, 11 for `review`, 12 for `not_checked` and 13 for `failed` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). Treat a Mac with no status as not checked.

With logging on, the **Remarks** column shows the script's output. For a full check that is one line:

```
blindspot act accounts=2 act=1 review=0 not_checked=1 v=1.2.0 at=2026-10-25T09:12:00Z
```

Between full checks it is the saved result:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws | itadmin: clear
```

Either way, the word after `blindspot` or `v1` is the Mac's outcome.

## Endpoint Central's limits

Checked 2026-10-28:

- A Mac computer custom script runs once, at every startup, at a number of later startups, or at
  every startup until a date
  ([Custom Scripts for Mac computers](https://www.manageengine.com/uk/desktop-management-msp/help/mac_configurations/executing_custom_scripts_for_computer.html)).
  Custom scripts can also be applied at every refresh cycle, every 90 minutes
  ([Execution Settings](https://www.manageengine.com/products/desktop-central/help/configuring_execution_settings.html)).
- A configuration's exit code is the one returned when the script succeeds. The default is 0, and
  others can be added, separated by commas
  ([Custom scripts for Mac users](https://www.manageengine.com/products/desktop-central/help/mac_configurations/executing_custom_scripts_for_users.html)).
- Logging shows the script's output in **Remarks** under **Execution Status**. ManageEngine documents
  it for Mac user scripts run once; for computer scripts it does not say.
- ManageEngine's documentation does not state which account a Mac computer script runs as, a time
  limit, a size limit for a script or its output, or whether Endpoint Central shows the exit code
  of a failed run. The check needs root: run as another account, it writes `needs root` to standard
  error and exits 13. `--deadline=3000` aims to finish it within 50 minutes, inside the 90-minute
  refresh cycle. The install script, with both files in it, is about 0.6 MB.
- The Mac's agent from Endpoint Central runs the scripts. ManageEngine's Mobile Device Manager Plus
  without Endpoint Central does not; see [its page](manageengine-mdm-plus.md).
