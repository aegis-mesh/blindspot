#!/bin/bash
# Stands in for sudo in tests/run.sh's fleet tests, which never run as root: it records the command
# gird-fleet.sh --all-users would run, then runs what follows sudo's -H as the person running the
# tests. $FLL_DIR/mode-<account> picks how that account's run behaves:
#   (none)     the real account run
#   fail       sudo refused: no output, exit 1
#   chmod      makes the script copy writable by anyone, then runs normally
#   other-row  the real output with a line for another account first
#   machine    the real output with a forged machine line before its end
#   oversize   more output than root reads
#   endless    output that never stops
#   malformed  the real output with one value that is not a number
#   hold       holds its output open past any limit, with a process that leaves its group
#   maxbytes   the real run with a 1 MiB file limit (an app's Info.plist stays far below it)
#   noprot     the real run, with the protected folder it tries refusing it
#   hardlink   a hard link to root's script copy, as any account could make in /tmp, then the real run
# FLL_API, when set, is handed to the account run as GIRD_CHECK_API, to show it sends nothing.
printf '%s\n' "$*" >> "$FLL_DIR/argv.log"
printf '%s\n' "$PATH" > "$FLL_DIR/launch-path"   # the PATH root starts sudo with
# FLL_COPYCHECK, when set: whether the script copy the account runs holds that text; the copy is kept
# as copy-seen.sh.
if [ -n "${FLL_COPYCHECK:-}" ]; then
  for a in "$@"; do case "$a" in */gird-check.sh) /usr/bin/grep -cF -- "$FLL_COPYCHECK" "$a" >> "$FLL_DIR/copycheck"; /bin/cp "$a" "$FLL_DIR/copy-seen.sh" ;; esac; done
fi
acct=""; prev=""
for a in "$@"; do [ "$prev" = -u ] && acct=$a; prev=$a; done
mode=$(/bin/cat "$FLL_DIR/mode-$acct" 2>/dev/null)
while [ $# -gt 0 ] && [ "$1" != -H ]; do shift; done; shift
# "$@" is now: /usr/bin/env -i PATH=... HOME=... /bin/bash COPY --account-run
envv=$1; shift 2   # /usr/bin/env -i
# Each account's own temp folder, so an account run never looks in the real one of the person testing.
extra=("GIRD_CHECK_FLEET_USER_TMP=$FLL_DIR/usertmp-$acct")
[ -n "${FLL_API:-}" ] && extra+=("GIRD_CHECK_API=$FLL_API" "GIRD_CHECK_WEB=$FLL_API")
case "$mode" in
  fail) echo "sudo: a password is required" >&2; exit 1 ;;
  chmod) for a in "$@"; do case "$a" in */gird-check.sh) /bin/chmod 666 "$a" ;; esac; done ;;
  maxbytes) extra+=(GIRD_CHECK_FLEET_MAX_BYTES=1048576) ;;
  noprot) extra+=("GIRD_CHECK_FLEET_PROTECTED=$FLL_DIR/noprot") ;;
  hardlink) for a in "$@"; do case "$a" in */gird-check.sh) /bin/ln -f "$a" "$FLL_DIR/copy-hardlink" ;; esac; done ;;
  endless) exec /usr/bin/yes agents=claude-code ;;
  hold) /usr/bin/perl -e 'use POSIX; POSIX::setsid(); sleep 60' fleet-hold-escapee &
        echo v=1; exec /bin/sleep 300 ;;
esac
run() { "$envv" -i "${extra[@]}" "$@"; }
case "$mode" in
  other-row) echo "account=itadmin"; run "$@" ;;
  machine) run "$@" | /usr/bin/sed 's/^end=1$/machine_incidents=litellm\
end=1/' ;;
  oversize) run "$@"; i=0; while [ "$i" -lt 300 ]; do echo "agents=claude-code codex"; i=$((i + 1)); done ;;
  malformed) run "$@" | /usr/bin/sed 's/^key_files=.*/key_files=99999 forged/' ;;
  *) exec "$envv" -i "${extra[@]}" "$@" ;;
esac
