# Blindspot with Iru

**Untested:** this page has not yet been run end to end on a real Mac. Steps and limits were checked
on 2026-10-25 against
[Iru's Custom Scripts guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview).

Read [docs/fleet.md](../fleet.md) first: what the check does, what each outcome means and what to do
about a finding.

You add one Custom Script library item. Iru records its output, so the summary line is the result.

## Full Disk Access

Iru's agent settings profile grants its agent Full Disk Access. To check the agent's identifier and
code requirement on one of your enrolled Macs:

```sh
codesign -dr - "<path to the Iru agent app>"
```

Never grant it to `/bin/bash`. Check the result either way: each account's `protected_folders` is
`checked` once access works.

## Add the check

1. Download `gird-check.sh` from a tagged release and check its SHA-256 against the release notes:

   ```sh
   shasum -a 256 gird-check.sh
   ```

2. Add this line under the script's first line:

   ```sh
   [ "${1:-}" = --account-run ] || set -- --all-users --exit-zero --summary-to-stdout --deadline=1800
   ```

3. Add a Custom Script library item, and name it `Blindspot check`
   ([Iru's guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview)).
4. Assign it to your Blueprints.
5. In **Execution Frequency**, choose **Run daily**.
6. Paste the script into the **Audit Script** field. Leave **Remediation Script** empty.
7. Select **Save**.

## What you should see

Each run's output is in the script's audit information, on the device status page and the custom
script's status page. It is one line:

```
blindspot act accounts=2 act=1 update=0 not_checked=1 v=1 at=2026-10-25T09:12:00Z
```

The word after `blindspot` is the Mac's outcome: `act`, `update`, `not_checked` or `clear` (see
[docs/fleet.md](../fleet.md#4-read-the-results)). The status reads **Pass** whenever the check
finished. **Error** means it could not run safely (`failed`); a missing summary line also means
not checked.

To have Iru alert on every Mac that is not clear, leave out `--exit-zero`. Every outcome except
`clear` then exits non-zero, which Iru reports as **Error** with an alert.

## Iru's limits

Checked 2026-10-25:

- Custom scripts always run as root.
- They run at every check-in (about every 15 minutes), daily, once until they pass, or on demand
  from Self Service.
- Standard output and standard error are kept in the script's audit information.
- An audit script that exits 0 reads **Pass**; any other exit code reads **Error** and raises an
  alert.
- Iru's guide does not state a time limit or a size limit for a script. `--deadline=1800` stops the
  check within 30 minutes; change it to suit you.

## Seeing all your Macs, all the time

This is one check, once a day. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
