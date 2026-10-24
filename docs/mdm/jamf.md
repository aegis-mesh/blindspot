# Blindspot with Jamf Pro

**Untested:** this page has not yet been run end to end on a real Mac. Menu paths and limits were
checked on 2026-10-25 against Jamf's documentation, linked at each step.

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

You add two things: a script that a policy runs daily, and an extension attribute that shows the
result in each computer's inventory.

## Full Disk Access

Grant Full Disk Access to the Jamf agent with a Privacy Preferences Policy Control profile
(`SystemPolicyAllFiles`), never to `/bin/bash`. Read the identifier and code requirement on one of
your enrolled Macs:

```sh
codesign -dr - /usr/local/jamf/bin/jamf
```

Jamf Pro also has a setting that installs a Privacy Preferences profile for its own framework. Check
the result either way: each account's `protected_folders` is `checked` once access works.

## Add the check

1. Download `gird-check.sh` from a tagged release and check its SHA-256 against the release notes:

   ```sh
   shasum -a 256 gird-check.sh
   ```

2. Add this line under the script's first line, so it runs with these options whatever arguments
   Jamf passes:

   ```sh
   [ "${1:-}" = --account-run ] || set -- --all-users --exit-zero --summary-to-stdout --deadline=3000
   ```

3. In Jamf Pro, click **Settings**, then in **Computer management** click **Scripts**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Adding_a_Script_to_Jamf_Pro)).
4. In the **General** pane, name it `Blindspot check`.
5. Click the **Script** tab and paste the script.
6. Click **Save**.

## Run it daily

1. Click **Computers**, then **Policies**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-11.24.0/Creating_a_Policy)).
2. In the **General** payload, choose a trigger such as recurring check-in, and the execution
   frequency **Once every day**
   ([execution frequency](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Execution_Frequency_for_Policies)).
3. Add the `Blindspot check` script to the policy.
4. Click the **Scope** tab and choose the Macs.
5. Click **Save**.

## Show the result in inventory

1. Make a second copy of `gird-check.sh` with this line under its first line instead. It only reads
   the saved result, and wraps it in the `<result>` tag Jamf stores:

   ```sh
   [ "${1:-}" = --account-run ] || set -- --inventory --stale-days=3 --result-tags
   ```

2. Click **Settings**, then in **Computer management** click **Extension attributes**, then **New**
   ([Jamf's guide](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Manually_Creating_a_Computer_Extension_Attribute)).
3. Name it `Blindspot`.
4. In **Data Type**, choose **String**.
5. In **Inventory Display**, choose where it shows.
6. In **Input Type**, choose **Script**, and paste the second copy.
7. Click **Save**.

## What you should see

After a Mac has run the policy and then submitted inventory, the `Blindspot` extension attribute
shows one line, such as:

```
v1 act 2026-10-25T09:12Z | asha: act tanstack; keys 2 anthropic,aws | itadmin: clear
```

It starts with the Mac's outcome: `act`, `update`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). `stale: last run <time>` means no check in 3 days,
`none` means the check has not run yet, and `unreadable` means the saved result could not be
trusted. Treat each of those, and an empty value, as not checked. The extension attribute can be used
as smart group criteria, for example values that start with `v1 act`.

## Jamf's limits

Checked 2026-10-25:

- An extension attribute with the Script input type stores the text between `<result>` and
  `</result>`, and runs each time the computer submits inventory
  ([Computer Extension Attributes](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Computer_Extension_Attributes)).
  Its data types are String, Integer and Date. Jamf's documentation does not state a maximum length;
  the value Blindspot prints is at most 250 characters.
- A policy runs once per computer, once every day, week or month, or on every trigger ("Ongoing")
  ([Execution Frequency for Policies](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/Execution_Frequency_for_Policies)).
- Jamf's documentation does not state a time limit for a policy's script, which account it runs as,
  or what it does with the script's exit code. The check needs root, so `--exit-zero` keeps a
  finding from reading as a failed policy, and `--deadline=3000` stops it within 50 minutes. If the
  policy log shows `needs root`, the script did not run as root.

## Seeing all your Macs, all the time

This is one check, once a day. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
