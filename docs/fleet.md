# Blindspot for IT teams

`gird-fleet.sh` checks every account on a Mac for what Blindspot shows one person: coding agents, keys
in plain text and in agent sessions, agents and project settings that run commands without asking,
and signs of recent malware. Your MDM runs it daily and shows one line per Mac. macOS only for now.

**Before you deploy:**

- It runs as root, from a folder only root can change. It checks each account as that account.
- It reads files and changes nothing in any home folder.
- It sends nothing anywhere. It makes no network request.
- It keeps one result on the Mac, `/var/db/blindspot/last.json`, readable by root only. The result
  holds counts and names from fixed lists, never a path, a file name or a key.

The install step and the [MDM pages](mdm/) have not yet been run end to end on a real Mac.

## What you get

Your MDM shows one line per Mac, such as:

```
v1 act 2026-10-25T09:12Z | asha: act incidents tanstack; keys 2 anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear
```

The first word after `v1` is the Mac's outcome, the worst of its accounts:

| Outcome | Means | Exit code |
|---|---|---|
| `act` | Act now: malware signs, or keys in plain text, shell history, agent sessions, MCP configs or allow lists. | 10 |
| `not_checked` | An account, or part of one, was not checked. Never read this as clear. | 12 |
| `review` | Something to change or confirm, not urgent, such as an agent set to run without asking. | 11 |
| `clear` | Every account was checked in full and nothing was found. | 0 |
| `failed` | The run could not finish safely. | 13 |

The field can also read `stale` (no run in 3 days), `none` (no run yet), `failed` (the last run stopped
part-way or could not save) or `unreadable`. Treat each of those as not checked.

Start with the Macs whose value starts `v1 act`, then `v1 not_checked`, `failed` and `stale`.
[What to do about each finding](fleet-reference.md#act-on-a-finding).

## Set it up

You need a tagged release of `gird-check.sh` and `gird-fleet.sh`, with the SHA-256 checked against
the [release notes](https://github.com/aegis-mesh/blindspot/releases). Your MDM's agent needs Full
Disk Access, or each account reads `not_checked`: the [page for your MDM](mdm/) says how.

### 1. Install it once

In the folder with both files, run this. It adds the daily options to a copy of `gird-fleet.sh`, then
writes `blindspot-install.sh`, which installs both files in `/Library/Application Support/Blindspot`.
Set `--deadline` to the number your MDM's page gives.

```sh
opts='case " $* " in *" --inventory "*|*" --list "*|*" --help "*|*" -h "*) ;; *) set -- --all-users --exit-zero --summary-to-stdout --deadline=3000 ;; esac'
/usr/bin/awk -v l="$opts" 'NR == 1 { print; print l; next } { print }' gird-fleet.sh > gird-fleet-mdm.sh
{
  cat <<'EOF'
#!/bin/bash
set -e
umask 077   # the new files are root's alone until their modes are set
d="/Library/Application Support/Blindspot"
/bin/mkdir -p "$d"
/usr/sbin/chown root:wheel "$d"
/bin/chmod 0755 "$d"
/bin/cat > "$d/gird-check.sh.new" <<'BLINDSPOT_CHECK'
EOF
  cat gird-check.sh
  printf '%s\n' 'BLINDSPOT_CHECK' "/bin/cat > \"\$d/gird-fleet.sh.new\" <<'BLINDSPOT_FLEET'"
  cat gird-fleet-mdm.sh
  cat <<'EOF'
BLINDSPOT_FLEET
/usr/sbin/chown root:wheel "$d/gird-check.sh.new" "$d/gird-fleet.sh.new"
/bin/chmod 0755 "$d/gird-check.sh.new"
/bin/chmod 0700 "$d/gird-fleet.sh.new"
/bin/mv -f "$d/gird-check.sh.new" "$d/gird-check.sh"
/bin/mv -f "$d/gird-fleet.sh.new" "$d/gird-fleet.sh"
EOF
} > blindspot-install.sh
```

Have your MDM run `blindspot-install.sh` once, as root.

### 2. Run it daily

The MDM's daily script is this one line:

```sh
exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh"
```

### 3. Show the result

The MDM's inventory field runs this line. It only reads the saved result:

```sh
exec /usr/bin/env -i /bin/bash "/Library/Application Support/Blindspot/gird-fleet.sh" --inventory --stale-days=3
```

## More

- Your MDM, step by step: [Jamf Pro](mdm/jamf.md), [Iru](mdm/iru.md),
  [Microsoft Intune](mdm/intune.md).
- [The reference](fleet-reference.md): trying it on your own Mac, having your coding agent review it,
  timing and the deadline, ripgrep, every option, the full outcome definitions, what each account's
  check reads, files that can be left behind, and how to update or remove it.
- [The design](designs/fleet-mode.md), with what it does not cover.
