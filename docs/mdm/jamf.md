# Blindspot with Jamf Pro

**Untested:** this page has not yet been run end to end on a real Mac. Menu paths and limits were
checked on 2026-10-24 against Jamf's documentation, linked at each step.

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

You add three things: a policy that installs the scripts once, a policy that runs it daily, and an
extension attribute that shows the result in each computer's inventory.

## Full Disk Access

Grant Full Disk Access to the Jamf agent with a Privacy Preferences Policy Control profile
(`SystemPolicyAllFiles`), never to `/bin/bash`. Read the identifier and code requirement on one of
your enrolled Macs:

```sh
codesign -dr - /usr/local/jamf/bin/jamf
```

Jamf Pro also has a setting that installs a Privacy Preferences profile for its own framework. Check
the result either way: each account's `protected_folders` is `checked` once access works.

## Install it once

1. Prepare the install script as [docs/fleet.md](../fleet.md#3-add-it-to-your-mdm) says: a tagged
   release of `gird-check.sh` and `gird-fleet.sh` whose SHA-256 you checked, with the options line
   starting the second line of `gird-fleet.sh` (`--deadline=3000` for Jamf), each pasted between its
   marker lines in the install script. This install step has not yet been run end to end on a real
   Mac.
   Optional: add the ripgrep lines from [step 3.5 of docs/fleet.md](../fleet.md#3-add-it-to-your-mdm)
   to its end, so large agent session stores take seconds per account rather than minutes.
2. In Jamf Pro, click **Settings**, then in **Computer management** click **Scripts**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Adding_a_Script_to_Jamf_Pro)).
3. In the **General** pane, name it `Blindspot install`.
4. Click the **Script** tab, paste the install script, and click **Save**.
5. Click **Computers**, then **Policies**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-11.24.0/Creating_a_Policy)).
6. In the **General** payload, choose a trigger such as recurring check-in, and the execution
   frequency **Once per computer**
   ([execution frequency](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Execution_Frequency_for_Policies)).
7. Add the `Blindspot install` script to the policy, choose the Macs on the **Scope** tab, and click
   **Save**.

## Run it daily

1. Add a second script, named `Blindspot check`, the same way, with only these lines:

   ```sh
   #!/bin/bash
   exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh"
   ```

2. Make a second policy the same way, with the execution frequency **Once every day**, the
   `Blindspot check` script and the same scope, and click **Save**.

## Show the result in inventory

1. Click **Settings**, then in **Computer management** click **Extension attributes**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Manually_Creating_a_Computer_Extension_Attribute)).
2. Name it `Blindspot`.
3. In **Data Type**, choose **String**.
4. In **Inventory Display**, choose where it shows.
5. In **Input Type**, choose **Script**, and paste these lines. They only read the saved result, and
   wrap it in the `<result>` tag Jamf stores:

   ```sh
   #!/bin/bash
   exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh" --inventory --stale-days=3 --result-tags
   ```

6. Click **Save**.

## What you should see

After a Mac has run the policy and then submitted inventory, the `Blindspot` extension attribute
shows one line, such as:

```
v1 act 2026-10-25T09:12Z | asha: act tanstack; keys 2 anthropic,aws | itadmin: clear
```

It starts with the Mac's outcome: `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). `stale: last run <time>` means no check in 3 days,
`none` means the check has not run yet, `failed` means the last run stopped part-way, and
`unreadable` means the saved result could not be trusted. Treat each of those, and an empty value, as not checked. The extension attribute can be used
as smart group criteria, for example values that start with `v1 act`.

## Jamf's limits

Checked 2026-10-24:

- An extension attribute with the Script input type stores the text between `<result>` and
  `</result>`, and runs each time the computer submits inventory
  ([Computer Extension Attributes](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Computer_Extension_Attributes)).
  Its data types are String, Integer and Date. Jamf's documentation does not state a maximum length;
  the value Blindspot prints is at most 250 characters.
- A policy runs once per computer, once every day, week or month, or on every trigger ("Ongoing")
  ([Execution Frequency for Policies](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Execution_Frequency_for_Policies)).
- Jamf's documentation does not state a time limit for a policy's script, which account it runs as,
  or what it does with the script's exit code. The check needs root, so `--exit-zero` keeps a
  finding from reading as a failed policy, and `--deadline=3000` aims to finish it within 50 minutes. If the
  policy log shows `needs root`, the script did not run as root.

## Seeing all your Macs, all the time

This is one check, once a day. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
