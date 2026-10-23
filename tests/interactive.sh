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
exit "$FAILED"
