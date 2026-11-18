# Blindspot with Iru

**Untested:** this page has not yet been run end to end on a real Mac with Iru. Steps and limits were
checked on 2026-10-24 against
[Iru's Custom Scripts guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview).

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

You add one Custom Script library item that runs the file daily. Iru records its output, so its
summary line is the result. There is nothing to install first.

## Full Disk Access

Iru's agent settings profile grants its agent Full Disk Access. To check the agent's identifier and
code requirement on one of your enrolled Macs:

```sh
codesign -dr - "<path to the Iru agent app>"
```

Never grant it to `/bin/bash`. Check the result either way: each account's `protected_folders` is
`checked` once access works.

## Run it daily

1. Download `blindspot-fleet.sh` from a tagged release and check its SHA-256 against the release
   notes ([docs/fleet.md](../fleet.md#1-try-it-on-your-own-mac)). Do not edit it.
2. Add a Custom Script library item named `Blindspot`
   ([Iru's guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview)),
   and assign it to your Blueprints.
3. In **Execution Frequency**, choose **Run daily**.
4. Paste the whole file into the **Audit Script** field. Leave **Remediation Script** empty.
5. Select **Save**.

With no options, it runs `--all-users --exit-zero --summary-to-stdout --deadline=3000`. Iru's guide
states no time limit for a script, and a Custom Script takes no parameters, so the file runs as it is.

Optional: to read agent sessions with ripgrep, add a second Custom Script, **Install once per
device**, with the lines from "ripgrep (optional)" in
[docs/fleet.md](../fleet.md#3-add-it-to-your-mdm) as its audit script.

## Moving from the two-file install

If you set Blindspot up with `Blindspot install` and `Blindspot check` library items, first remove
`Blindspot check` from your Blueprints, then add the item above, and remove `Blindspot install`.
Then remove the old files as [docs/fleet.md](../fleet.md#moving-from-two-files) says. Until they are
gone, the summary line ends `old_install=yes`.

## What you should see

Each run's output is in the script's audit information, on the device status page. It is one line:

```
blindspot act accounts=2 act=1 review=0 not_checked=1 v=1.2.0 at=2026-10-25T09:12:00Z
```

The word after `blindspot` is the Mac's outcome: `act`, `review`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). The status reads **Pass** whenever the check
finished. **Error** means it could not run safely or refused to start (`failed`, the reason in the
output); a missing summary line also means not checked.

A finding still reads **Pass**: the word after `blindspot` is what to filter on.

## Iru's limits

Checked 2026-10-24:

- Custom scripts always run as root.
- They run at every check-in (about every 15 minutes), daily, or on demand from Self Service.
- Standard output and standard error are kept in the script's audit information.
- An audit script that exits 0 reads **Pass**; any other exit code reads **Error** and starts the
  remediation script.
- Iru's guide does not state a time limit or a size limit for a script, or where it writes the script
  before running it. The file is about 590 KB. If the output says `must be owned by root and
  writable by no one else`, it names the folder Iru wrote the script in; please report it.

## Seeing all your Macs, all the time

This is one check, once a day. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
