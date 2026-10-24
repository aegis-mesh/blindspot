# Fleet mode: running Blindspot from an MDM

Status: proposal, not built.

## Why

A company that manages its computers with an MDM (Jamf, Iru, Intune and others) wants one answer
for every machine: which coding agents run, where AI and cloud keys sit in plain text, and whether a
recent malware incident touched any of them. Today Blindspot answers that for one person, run by
that person. An MDM runs scripts as root (or SYSTEM on Windows), with root's own home folder, so a
run from an MDM checks the wrong home and finds nothing.

Fleet mode lets an MDM run the same checks on every account on a machine and collect a short,
structured result in its own inventory. Nothing new leaves the machine: the MDM collects the result
the way it collects any script output.

## What it adds

1. `--all-users` (`-AllUsers` in PowerShell): needs root or an elevated PowerShell, and refuses to
   run otherwise. It finds the machine's real user accounts and runs every check once per account,
   with that account's home folder, read-only.
2. `--json` (`-Json`): prints one JSON document instead of the report, and nothing else on standard
   output.
3. Ready-to-paste scripts for common MDMs in `docs/mdm/`, each with the steps to deploy it and to see
   the result.

`--all-users` turns on everything a run with nobody watching needs: no game, no menu, no browser,
no colours, and no network requests at all, as `--offline` does. The public totals and the shared
report are for people who run Blindspot themselves. A fleet run would also skew the public counts.

## Which accounts

| system | accounts | home |
|---|---|---|
| macOS | `dscl . -list /Users UniqueID`, UID 500 and above, not starting with `_` | `NFSHomeDirectory` |
| Linux | `getent passwd`, UID 1000 and above, a login shell, not `nobody` | the passwd home field |
| Windows | `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList`, S-1-5-21 SIDs | `ProfileImagePath` |

An account whose home does not exist, is not a folder, or is on a network mount that does not
answer within the per-account time limit is listed as not checked, never as clean.

## What root may and may not do here

Running as root over other people's files is the risk this mode adds, so these are rules, each with
a test:

- Read only. Nothing is created, changed, moved or deleted in any home, and file times are not
  touched beyond what reading does.
- Each account's checks see only that account's home and the machine-wide places the checks already
  read. One account's findings are never attributed to another.
- Symbolic links are not followed out of the home being checked, so a link in one person's folder
  cannot make root read another person's files or system files.
- The temp files the checks use are created readable only by their owner (here root), as today,
  and removed on exit.
- On macOS, privacy protection can keep root out of some folders unless the MDM grants Full Disk
  Access to the process running the script. A folder that cannot be read is counted and named as
  not checked. The MDM steps say how to grant access.
- Each account has a time limit, so one large or hung home cannot stop the others from being
  checked. An account that hit the limit is reported as partly checked.

## The result

The JSON holds counts and names from fixed lists, the same kinds of fields the shared report holds
today, and no file paths, file names or key values:

```json
{
  "blindspot": "1",
  "script": "<version>",
  "checked_at": "<UTC time>",
  "os": "macOS 15.5",
  "accounts": [
    {
      "account": "<local account name>",
      "complete": true,
      "agents": ["claude-code", "codex"],
      "agents_run_without_asking": ["claude-code"],
      "tools_to_update": ["mcp-remote"],
      "mcp_servers": 4,
      "mcp_token_files": 1,
      "key_files": 2,
      "key_providers": ["anthropic", "aws"],
      "history_keys": 1,
      "session_files_with_keys": 0,
      "ssh_keys_no_passphrase": 1,
      "incidents": [{"id": "tanstack", "level": "act"}]
    }
  ],
  "machine": { "incidents": [] }
}
```

- `account` is the local account name, which the MDM already knows. `--hash-accounts` replaces it
  with a hash for organisations that prefer not to collect it.
- An incident that means a compromised machine is listed with its level, so an MDM can alert on it.
- The exit code tells an MDM the outcome without parsing: 0 nothing found, 1 a finding to act on,
  2 only updates to install, 3 not fully checked. A run that fails to finish exits 4 and never
  prints a result that reads as clean.

## MDM scripts

`docs/mdm/` gets one page per MDM, each with the script to paste, where to see the result, and how
to grant Full Disk Access where that MDM supports it:

- Jamf Pro: an extension attribute that prints a one-line summary in `<result>` tags, and a policy
  that saves the full JSON to a root-only file for collection.
- Iru (formerly Kandji): a custom script and an audit script.
- Microsoft Intune: a shell script for macOS, and a detection script (remediations) for Windows.

Only an MDM that has been run end to end on a real machine is listed as supported.

## Not covered

- Collecting results from many machines in one place. The JSON is for the MDM's own inventory.
- Running as each user instead of as root, which would need each person signed in.
- Containers, servers and CI runners.

## Tests

- The account list on each system, from fixtures: a system account, a missing home, a network home.
- Two fixture accounts with different findings: each account's result holds only its own.
- A symbolic link in one fixture home to another home and to a system file: neither is read.
- Without root, `--all-users` refuses and exits non-zero.
- `--all-users` makes no network request (a local listener sees nothing).
- The JSON holds no path, file name or planted key, and both scripts produce the same JSON for the
  same fixture.
- Each exit code from a fixture that produces it, including a run stopped part-way.
