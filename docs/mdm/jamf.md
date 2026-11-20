# Blindspot with Jamf Pro

**Untested:** this page has not yet been run end to end on a real Mac with Jamf Pro. Menu paths and
limits were checked on 2026-10-24 against Jamf's documentation, linked at each step.

Read [docs/fleet.md](../fleet.md) first: what the check does and what each outcome means.
[docs/fleet-reference.md](../fleet-reference.md#act-on-a-finding) says what to do about a finding.

You add three things: the file as a script, a policy that runs it daily, and an extension attribute
that shows the result in each computer's inventory. There is nothing to install first.

## Full Disk Access

Grant Full Disk Access to the Jamf agent with a Privacy Preferences Policy Control profile
(`SystemPolicyAllFiles`), never to `/bin/bash`. Read the identifier and code requirement on one of
your enrolled Macs:

```sh
codesign -dr - /usr/local/jamf/bin/jamf
```

Jamf Pro also has a setting that installs a Privacy Preferences profile for its own framework. Check
the result either way: each account's `protected_folders` is `checked` once access works.

## Add the file

1. Download `blindspot-fleet.sh` from a release and check it as
   [docs/fleet.md](../fleet.md#1-download-the-file) says. Do not edit it.
2. In Jamf Pro, click **Settings**, then in **Computer management** click **Scripts**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Adding_a_Script_to_Jamf_Pro)).
3. In the **General** pane, name it `Blindspot`.
4. Click the **Script** tab, paste the whole file, and click **Save**.

Leave its parameters empty: with none, it runs
`--all-users --exit-zero --summary-to-stdout --deadline=3000`. The three arguments Jamf sends every
script first are dropped. To change one option, give all four, one in each of parameters 4 to 7:
`--all-users`, `--exit-zero`, `--summary-to-stdout` and, for example, `--deadline=1800`.

## Run it daily

1. Click **Computers**, then **Policies**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-11.24.0/Creating_a_Policy)).
2. In the **General** payload, choose the trigger **Recurring Check-in** and the execution frequency
   **Once every day**
   ([execution frequency](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Execution_Frequency_for_Policies)).
3. Add the `Blindspot` script to the policy, choose the Macs on the **Scope** tab, and click **Save**.

Optional: to read agent sessions with ripgrep, add a second script with the lines from
[Install ripgrep (optional)](../fleet-reference.md#install-ripgrep-optional), and a policy that runs
it **Once per computer**, so large agent session stores take seconds per account rather than
minutes.

## Show the result in inventory

1. Click **Settings**, then in **Computer management** click **Extension attributes**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Manually_Creating_a_Computer_Extension_Attribute)).
2. Name it `Blindspot`.
3. In **Data Type**, choose **String**.
4. In **Inventory Display**, choose where it shows.
5. In **Input Type**, choose **Script**, and paste the lines from
   [step 3 of docs/fleet.md](../fleet.md#3-show-the-result), with their last line changed to
   `echo "<result>$(blindspot_inventory)</result>"`. They only read the saved result, and wrap it in
   the `<result>` tag Jamf stores.
6. Click **Save**.

## Moving from the two-file install

If you set Blindspot up with `Blindspot install` and `Blindspot check` policies from an earlier
release, first disable or delete the `Blindspot check` policy, so two checks do not run. Then follow
the steps above, replace the extension attribute's lines with the ones in step 5, and delete the
install policy. Then remove the old files as [docs/fleet.md](../fleet.md#moving-from-two-files) says.
Until they are gone, the value says `old-install`.

## What you should see

After a Mac has run the policy and then submitted inventory, the `Blindspot` extension attribute
shows one line, such as:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws | itadmin: clear | owasp.ASI03:1 owasp.ASI04:1; counted 2
```

It starts with the Mac's outcome: `failed`, `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#what-you-get)). A Mac whose OWASP tags could not be worked out reads
`v1 failed` even when it has findings to act on. `stale: last run <time>` means no check in 3 days,
`none` means the check has not run yet, `failed` means the last run stopped part-way or refused to
start (the reason follows), `old-install` means the one file has not yet finished a run where an
earlier install saved a result, and `unreadable` means the saved result could not be trusted or read.
Treat each of those, and an empty value, as not checked.

The extension attribute can be used as smart group criteria: values that start with `v1 act` or
`v1 failed`, or that contain `owasp.ASI03` for the Macs with a finding tagged with that OWASP risk
([OWASP tags](../fleet-reference.md#owasp-tags)). The value carries the OWASP part only when it has
room, so a Mac with no room for it does not match. The summary line in the policy log, and
`last.json` on the Mac, always carry it.

To see every Mac in one report, export the computers with the `Blindspot` extension attribute as a
CSV file and run `gird-report.ps1` on it:
[one report for every computer](../fleet.md#one-report-for-every-computer).

## Jamf's limits

Checked 2026-10-24:

- An extension attribute with the Script input type stores the text between `<result>` and
  `</result>`, and runs each time the computer submits inventory
  ([Computer Extension Attributes](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Computer_Extension_Attributes)).
  Its data types are String, Integer and Date. Jamf's documentation does not state a maximum length;
  the value Blindspot prints is at most 250 characters.
- A policy runs once per computer, once every day, week or month, or on every trigger ("Ongoing")
  ([Execution Frequency for Policies](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Execution_Frequency_for_Policies)).
- Jamf's [Scripting 201 guide](https://resources.jamf.com/documents/white_papers/apple-scripting-201.pdf)
  writes its scripts with a `#!` line naming the shell, and says a script gets three arguments first:
  the mount point, the computer's name and the user's name (checked 2026-11-18). The file starts
  `#!/bin/bash -p`, and stops (exit 13) if it was started without `-p`. If the policy log shows
  `start it as its first line says`, Jamf did not start it by that line; please
  [report it](https://github.com/aegis-mesh/blindspot/issues/new/choose).
- Jamf's documentation does not state a time limit for a policy's script, which account it runs as,
  what it does with the script's exit code, a size limit for a script, or where it writes the script
  before running it. The file is about 750 KB. The check needs root, so `--exit-zero` keeps a finding
  from reading as a failed policy, and `--deadline=3000` aims to finish it within 50 minutes. If the
  policy log shows `needs root`, the script did not run as root. If it shows
  `must be owned by root and writable by no one else`, it names the folder Jamf wrote the script in;
  please report it ([why it matters](../fleet-reference.md#how-the-one-file-runs)).

## Seeing all your Macs, all the time

This is one check, once a day. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
