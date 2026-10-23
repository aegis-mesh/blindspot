#!/usr/bin/env bash
# Drives the game, the results prompt and the menu with expect, in a real
# pseudo-terminal: on the bash that ships with macOS (3.2, where a helper reads
# the keys) and on a newer bash from PATH if there is one. Skips without expect.
set -u
cd "$(dirname "$0")/.." || exit 1
command -v expect >/dev/null 2>&1 || { echo "expect is not installed, skipping"; exit 0; }
BASHES=""
[ -x /bin/bash ] && BASHES="/bin/bash"
OTHER=$(command -v bash 2>/dev/null || true)
if [ -n "$OTHER" ] && [ "$("$OTHER" -c 'echo "$BASH_VERSION"')" != "$(/bin/bash -c 'echo "$BASH_VERSION"' 2>/dev/null)" ]; then BASHES="$BASHES $OTHER"; fi
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t blindspot)
trap 'rm -rf "$WORK"' EXIT
bash tests/make-fixture.sh "$WORK/home" "$WORK/keys.txt" clean
FAILED=0
for B in $BASHES; do
  echo "bash $("$B" -c 'echo "$BASH_VERSION"') ($B)"
  rm -rf "$WORK/cwd"; mkdir -p "$WORK/cwd"
  if FAKEHOME="$WORK/home" SCRIPT="$PWD/gird-check.sh" BASHBIN="$B" SAVEDIR="$WORK/cwd" expect tests/interactive.exp; then
    if ls "$WORK"/cwd/gird-ai-key-check-*.txt >/dev/null 2>&1; then echo "  ok    the menu saved the report"; else echo "  FAIL  the menu saved no report"; FAILED=1; fi
  else
    FAILED=1
  fi
  FAKEHOME="$WORK/home" SCRIPT="$PWD/gird-check.sh" BASHBIN="$B" expect tests/fast.exp || FAILED=1
  FAKEHOME="$WORK/home" SCRIPT="$PWD/gird-check.sh" BASHBIN="$B" expect tests/interrupt.exp || FAILED=1
done

# Opening the result on Windows (Git Bash) and in WSL, with stand-ins for uname,
# cmd.exe and wslview that log their arguments.
echo "opening the result on Windows and WSL"
WB=$WORK/openbin; mkdir -p "$WB" "$WORK/proc-wsl/sys/kernel"
printf '5.15.153.1-microsoft-standard-WSL2\n' > "$WORK/proc-wsl/sys/kernel/osrelease"
printf '#!/bin/sh\n[ "$1" = -s ] && { echo "$FAKE_UNAME"; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$WB/uname"
for c in cmd.exe wslview; do printf '#!/bin/sh\nprintf "%s" > "$OPENLOG"\nfor a in "$@"; do printf " [%%s]" "$a" >> "$OPENLOG"; done\n' "$c" > "$WB/$c"; done
chmod +x "$WB"/*
check_open() { # label wanted-regex
  if grep -qE -- "$2" "$WORK/open.log" 2>/dev/null; then echo "  ok    $1"; else echo "  FAIL  $1"; cat "$WORK/open.log" 2>/dev/null; echo; FAILED=1; fi
}
rm -f "$WORK/open.log"
FAKE_UNAME=MINGW64_NT-10.0-22631 OPENLOG="$WORK/open.log" PATH="$WB:/usr/bin:/bin" LABEL="Git Bash" \
  FAKEHOME="$WORK/home" SCRIPT="$PWD/gird-check.sh" BASHBIN=bash expect tests/open.exp || FAILED=1
check_open "Git Bash: cmd.exe start gets the link with each & escaped" '^cmd\.exe \[/d\] \[/c\] \[start\] \[\] \[https://gird\.ai/blindspot/card/#v=2\^&s=[0-9]+\^&g='
rm -f "$WORK/open.log"
FAKE_UNAME=Linux GIRD_CHECK_PROC="$WORK/proc-wsl" OPENLOG="$WORK/open.log" PATH="$WB:/usr/bin:/bin" LABEL="WSL" \
  FAKEHOME="$WORK/home" SCRIPT="$PWD/gird-check.sh" BASHBIN=bash expect tests/open.exp || FAILED=1
check_open "WSL: wslview gets the link as it is" '^wslview \[https://gird\.ai/blindspot/card/#v=2&s=[0-9]+&g='
exit "$FAILED"
