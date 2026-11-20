# Blindspot with ManageEngine Endpoint Central

**Untested:** this page has not yet been run end to end on a real Mac with Endpoint Central. Menu
paths and limits were checked on 2026-10-28 against ManageEngine's documentation, linked at each
step. Endpoint Central's documentation leaves several things out, such as which account a Mac script
runs as and its time limit; [Endpoint Central's limits](#endpoint-centrals-limits) lists them.

Read [docs/fleet.md](../fleet.md) first: what the check does and what each outcome means.
[docs/fleet-reference.md](../fleet-reference.md#act-on-a-finding) says what to do about a finding.

Using Mobile Device Manager Plus without Endpoint Central? Read
[its page](manageengine-mdm-plus.md) instead.

You add two Mac computer configurations: `Blindspot`, which runs the file once, and
`Blindspot check`, which runs at every refresh cycle and starts a full check once a day. There is
nothing to install first.

## Full Disk Access

Endpoint Central grants its own agent Full Disk Access on the Macs it manages
([macOS Agent Permissions via MDM](https://www.manageengine.com/products/desktop-central/help/device-onboarding/permissions-for-endpoint-central-agent-via-mdm.html)):
the agent service, `dcagentservice`, gets System Policy All Files. If you enrolled the Macs through
another MDM, that page lists the profile to deploy. Never grant it to `/bin/bash`.

Whether a script the agent starts keeps that access is not documented. Check the result: each
account's `protected_folders` is `checked` once access works.

## Run the file once

1. Download `blindspot-fleet.sh` from a release and check it as
   [docs/fleet.md](../fleet.md#1-download-the-file) says. Do not edit it.
2. Click **Configurations** > **Script Repository** > **Add Script**, and add `blindspot-fleet.sh`
   ([Custom Scripts](https://www.manageengine.com/products/desktop-central/help/configuring_desktop_central/managing_custom_scripts.html)).
   A script must be in the repository before a configuration can deploy it.
3. Click **Configurations**, then under **Add Configurations** click **Configurations**, open the
   **Mac** tab, and choose **Custom Scripts** > **Computer**
   ([Custom Scripts for Mac computers](https://www.manageengine.com/uk/desktop-management-msp/help/mac_configurations/executing_custom_scripts_for_computer.html)).
4. Name it `Blindspot`, and choose `blindspot-fleet.sh` from the repository. Leave the arguments and
   dependency files empty: with no options, the file runs
   `--all-users --exit-zero --summary-to-stdout --deadline=3000` and exits 0 whenever the check
   finished.
5. Set the exit code to `0`.
6. Set the frequency to run only once.
7. Choose the target Macs, and deploy it.

Its run checks every account, saves the result, and keeps a copy of the file,
`/var/db/blindspot/blindspot-fleet.sh`, root's alone, which `Blindspot check` below runs.

Optional: to read agent sessions with ripgrep, add the lines from
[Install ripgrep (optional)](../fleet-reference.md#install-ripgrep-optional) to the repository as a
script of their own, with a configuration that runs it once, as in steps 3 to 7. Large agent session
stores then take seconds per account rather than minutes.

## Run it daily

Endpoint Central can run a Mac computer script once, at startup, or at every refresh cycle, which is
every 90 minutes
([Execution Settings](https://www.manageengine.com/products/desktop-central/help/configuring_execution_settings.html)).
It has no daily setting. So the check script below runs at every refresh cycle, and starts a full
check only when the saved result is more than a day old, or the last run did not finish. Otherwise it
prints the saved result and exits with its outcome's code. It runs the copy `Blindspot` kept, with
`/bin/bash -p` as that copy's first line asks.

1. Save these lines as a file, `blindspot-check.sh`:

   ```sh
   #!/bin/bash -p
   # Blindspot for Endpoint Central: the saved result, or a full check when it is over a day old.
   f=/var/db/blindspot/blindspot-fleet.sh
   [ -f "$f" ] || { echo "not checked: Blindspot has not finished a run here, or this script does not run as root"; exit 13; }
   v=$(/usr/bin/env -i /bin/bash -p "$f" --inventory --stale-days=1 2>/dev/null)
   case "$v" in
     "v1 clear "*) printf '%s\n' "$v"; exit 0 ;;
     "v1 act "*) printf '%s\n' "$v"; exit 10 ;;
     "v1 review "*) printf '%s\n' "$v"; exit 11 ;;
     "v1 not_checked "*) printf '%s\n' "$v"; exit 12 ;;
     "v1 failed "*) printf '%s\n' "$v"; exit 13 ;;
   esac
   exec /usr/bin/env -i /bin/bash -p "$f" --all-users --summary-to-stdout --deadline=3000
   ```

   A saved result less than a day old is printed, and the script exits with its outcome's code. A
   result that reads `none`, `stale`, `unreadable` or `failed:` and why starts a full check, so after
   a run that did not finish, or stopped before it started, every refresh cycle tries again. A result
   that starts `v1 failed` came from a run that finished and saved it, so it waits a day like the
   others; the saved result says why.

   The full check gives the file its own options, which replace the defaults: the defaults without
   `--exit-zero`, so its exit code is its outcome's, 0 for `clear`, 10 for `act`, 11 for `review`, 12
   for `not_checked` and 13 for `failed`. It aims to finish within 50 minutes (`--deadline=3000`),
   before the next refresh cycle. One that runs longer is not stopped by the next cycle, which starts
   another check alongside it.
2. Add it to the Script Repository as in step 2 above.
3. Add a second Mac computer custom script the same way, named `Blindspot check`, with
   `blindspot-check.sh`.
4. Set the exit code to `0`, so only a Mac whose outcome is `clear` reads as successful.
5. Set the frequency to run during every system startup, then in its execution settings choose
   **Apply the configuration during every Refresh Cycle**. ManageEngine's documentation does not
   say how the two settings combine.
6. If the configuration offers **Enable logging for troubleshooting**, turn it on.
7. Choose the same target Macs, and deploy it.

To update, put the next release's `blindspot-fleet.sh`, checked as in step 1, in the Script
Repository in place of the old one, and deploy `Blindspot` again so it runs once more: its run keeps
the new file, which `Blindspot check` then runs. `blindspot-check.sh` stays the same.

## Moving from the two-file install

If you set Blindspot up from an earlier release, with `Blindspot install` and the old
`Blindspot check`, first remove that `Blindspot check` configuration, so two checks do not run, and
its `blindspot-check.sh` from the Script Repository. Then follow the steps above, and remove
`Blindspot install`. Then remove the old files as
[docs/fleet.md](../fleet.md#moving-from-two-files) says. Until they are gone, the result says
`old-install`, and a full check's line ends `old_install=yes`.

## What you should see

Under **Configurations** > **All Configurations** > `Blindspot check` > **Execution Status**, a Mac
whose outcome is `clear` should read as successful, and any other outcome as failed. The exit code
is 10 for `act`, 11 for `review`, 12 for `not_checked` and 13 for `failed` (see
[docs/fleet.md](../fleet.md#what-you-get)); ManageEngine's documentation does not say whether
Execution Status shows it. Treat a Mac with no status as not checked. `Blindspot` itself reads as
successful once its run has finished.

If logging is available for the configuration, the **Remarks** column shows the script's output.
For a full check that is one line:

```
blindspot act accounts=2 act=1 review=0 not_checked=0 v=1.3.0 at=2026-10-25T09:12:00Z owasp=ASI03:1,ASI04:1;counted:2
```

Between full checks it is the saved result:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws | itadmin: clear | owasp.ASI03:1 owasp.ASI04:1; counted 2
```

Either way, the word after `blindspot` or `v1` is the Mac's outcome. A Mac whose OWASP tags could not
be worked out reads `failed` even when it has findings to act on
([OWASP tags](../fleet-reference.md#owasp-tags)).

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
  limit, a size limit for a script or its output, where the agent writes a script before running
  it, or whether Endpoint Central shows the exit code of a failed run. The check needs root: run as
  another account, it says `needs root` and exits 13. `--deadline=3000` aims to finish it within 50
  minutes, inside the 90-minute refresh cycle. `blindspot-fleet.sh` is about 750 KB.
- `blindspot-fleet.sh` starts `#!/bin/bash -p`, and stops (exit 13) if it was started without `-p`.
  If the output of `Blindspot` says `start it as its first line says`, Endpoint Central did not start
  it by that line. If it says `must be owned by root and writable by no one else`, it names the
  folder the agent wrote the script in. Please
  [report either](https://github.com/aegis-mesh/blindspot/issues/new/choose)
  ([why it matters](../fleet-reference.md#how-the-one-file-runs)). `Blindspot check` starts the copy
  the file kept with `/bin/bash -p` itself, from `/var/db/blindspot`, so neither applies to it.
- The Mac's agent from Endpoint Central runs the scripts. ManageEngine's Mobile Device Manager Plus
  without Endpoint Central does not; see [its page](manageengine-mdm-plus.md).
