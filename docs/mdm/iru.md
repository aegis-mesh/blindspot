# Blindspot with Iru

**Untested:** this page has not yet been run end to end on a real Mac with Iru. Steps and limits were
checked on 2026-10-24 against
[Iru's Custom Scripts guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview).

Read [docs/fleet.md](../fleet.md) first: what the check does and what each outcome means.
[docs/fleet-reference.md](../fleet-reference.md#act-on-a-finding) says what to do about a finding.

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

1. Download `blindspot-fleet.sh` from a release and check it as
   [docs/fleet.md](../fleet.md#1-download-the-file) says. Do not edit it.
2. Add a Custom Script library item named `Blindspot`
   ([Iru's guide](https://docs.iru.com/en/endpoint/library/library-items-profiles/custom-scripts-overview)),
   and assign it to your Blueprints.
3. In **Execution Frequency**, choose **Run daily**.
4. Paste the whole file into the **Audit Script** field. Leave **Remediation Script** empty.
5. Select **Save**.

A Custom Script takes no options, so the file runs with its defaults:
`--all-users --exit-zero --summary-to-stdout --deadline=3000`.

Optional: to read agent sessions with ripgrep, add a second Custom Script, **Install once per
device**, with the lines from [Install ripgrep (optional)](../fleet-reference.md#install-ripgrep-optional)
as its audit script, so large agent session stores take seconds per account rather than minutes.

## Moving from the two-file install

If you set Blindspot up with `Blindspot install` and `Blindspot check` library items from an earlier
release, first remove `Blindspot check` from your Blueprints, so two checks do not run. Then add the
item above, and remove `Blindspot install`. Then remove the old files as
[docs/fleet.md](../fleet.md#moving-from-two-files) says. Until they are gone, the summary line ends
`old_install=yes`.

## What you should see

Each run's output is in the script's audit information, on the device status page. It is one line:

```
blindspot act accounts=2 act=1 review=0 not_checked=1 v=1.3.0 at=2026-10-25T09:12:00Z owasp=ASI03:1,ASI04:1;counted:1;not_counted:1
```

The word after `blindspot` is the Mac's outcome: `failed`, `act`, `review`, `not_checked` or `clear`
(see [docs/fleet.md](../fleet.md#what-you-get) and
[the summary line](../fleet-reference.md#the-summary-line)). A Mac whose OWASP tags could not be
worked out reads `failed` even when it has findings to act on, so a search for `blindspot act` misses
it, and its line ends with `owasp_failed=` and the causes. The `owasp=` part names the OWASP risks
found ([OWASP tags](../fleet-reference.md#owasp-tags)); to find the Macs with one, search the output
for `ASI03:`.

The status reads **Pass** whenever the check finished, a finding included: the word after
`blindspot` is what to filter on. **Error** means it could not run safely or stopped before it
started (`failed`, with the reason in the output). A missing summary line also means not checked.

The summary line names no findings, only counts. To see which findings an account has, read
`/var/db/blindspot/last.json` on that Mac as root, or ask the person to run Blindspot on their own
account. For the same reason, `gird-report.ps1` lists an Iru Mac as not checked
([the fleet report](../fleet-reference.md#the-fleet-report)).

## Iru's limits

Checked 2026-10-24:

- Custom scripts always run as root.
- A script may name its own shell; one that names none runs with `/bin/sh` (checked 2026-11-18). The
  file names `/bin/bash -p` on its first line, and stops (exit 13) if it was started without `-p`. If
  the output says `start it as its first line says`, Iru did not start it by that line; please
  [report it](https://github.com/aegis-mesh/blindspot/issues/new/choose).
- They run at every check-in (about every 15 minutes), daily, or on demand from Self Service.
- Standard output and standard error are kept in the script's audit information.
- An audit script that exits 0 reads **Pass**; any other exit code reads **Error** and starts the
  remediation script.
- Iru's guide does not state a time limit or a size limit for a script, or where it writes the script
  before running it. The file is about 750 KB. `--deadline=3000` aims to finish the check within 50
  minutes. If the output says `must be owned by root and writable by no one else`, it names the
  folder Iru wrote the script in; please report it
  ([why it matters](../fleet-reference.md#how-the-one-file-runs)).

## Seeing all your Macs, all the time

This is one check, once a day. Argus shows every AI agent on every Mac as it runs, who owns it and
what it may reach. Roll it out through the MDM you already use: [gird.ai/argus](https://gird.ai/argus).
