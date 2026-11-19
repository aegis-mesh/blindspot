#!/bin/bash
# Stands between gird-fleet.ps1 and the account run in tests/run-ps.sh's fleet tests, which run off
# Windows: gird-fleet.ps1's GIRD_CHECK_FLEET_LAUNCH names this file, and it gets the command
# gird-fleet.ps1 would run (PowerShell and its arguments). It records the command and the GIRD_CHECK_*
# settings it was handed, then runs the command. $FWL_DIR/mode picks how the account run behaves:
#   (none)     the real account run
#   empty      stops before its first line: no output, exit 1
#   clm        the one line gird-check.ps1 prints in the reduced language, as Windows PowerShell ends it
#   other-row  the real output with a line for another account first
#   machine    the real output with a forged machine line before its end
#   oversize   more output than gird-fleet.ps1 reads
#   bighold    more output than gird-fleet.ps1 reads, then holds it open past any limit
#   endless    output that never stops
#   malformed  the real output with one value that is not a number
#   tmpmarks   the real output naming a marker in a shared /tmp, which Windows has none of
#   maxed      output in the fixed format with every incident in each list that takes incidents, and
#              the wiper: an inventory value too long to keep whole
#   hold       prints v=1, starts a process of its own and holds its output open past any limit; the
#              process is added to $FWL_DIR/procs, the process list the tests' stand-in for ps prints
#   stuck      prints v=1 and holds its output open past any limit, with no process of its own
#   slowsess   the real run, with its session check held so it never ends on its own
# FWL_API, when set, is handed to the account run as GIRD_CHECK_API and GIRD_CHECK_WEB, to show it
# sends nothing.
# The account run keeps the PATH it was given; this file's own tools come from the system's folders.
OPATH=$PATH; PATH=/usr/bin:/bin
printf '%s\n' "$*" >> "$FWL_DIR/argv.log"
env | grep '^GIRD_CHECK_' > "$FWL_DIR/env.log"
extra=("PATH=$OPATH")
[ -n "${FWL_API:-}" ] && extra+=("GIRD_CHECK_API=$FWL_API" "GIRD_CHECK_WEB=$FWL_API")
mode=$(cat "$FWL_DIR/mode" 2>/dev/null)
[ "$mode" = slowsess ] && { : > "$FWL_DIR/sesshold"; extra+=(GIRD_CHECK_SESSIONS_ENGINE=net "GIRD_CHECK_SESSIONS_HOLD=$FWL_DIR/sesshold"); }
run() { env ${extra[@]+"${extra[@]}"} "$@"; }
case "$mode" in
  empty) exit 1 ;;
  clm) printf 'language_mode=1\r\n'; exit 13 ;;
  other-row) echo "account=itadmin"; run "$@" ;;
  machine) run "$@" | sed 's/^end=1$/machine_incidents=litellm\
end=1/' ;;
  oversize) run "$@"; i=0; while [ "$i" -lt 300 ]; do echo "agents=claude-code codex"; i=$((i + 1)); done ;;
  endless) exec yes agents=claude-code ;;
  bighold) echo "$$" > "$FWL_DIR/launcher.pid"; i=0; while [ "$i" -lt 300 ]; do echo "agents=claude-code codex"; i=$((i + 1)); done; exec sleep 300 ;;
  malformed) run "$@" | sed 's/^key_files=.*/key_files=99999 forged/' ;;
  tmpmarks) run "$@" | sed 's/^tmp_marks=.*/tmp_marks=mastra/' ;;
  maxed)
    ids=$(grep -v '^#' "$FWL_REPO/data/incidents.tsv" | grep -v '^[[:space:]]*$' | cut -f1 | head -n 40 | paste -sd ' ' -)
    provs=$(grep -v '^#' "$FWL_REPO/data/keys.tsv" | grep -v '^[[:space:]]*$' | cut -f1 | sed 's/_.*//' | awk '!s[$0]++' | paste -sd ' ' -)
    for l in v=1 agents= "yolo=claude-code codex vs-code-copilot" "tools=amazonq claudecode mcpremote" mcp_servers=0 mcp_token_files=0 key_files=1 "key_providers=$provs" history_keys=0 session_files=0 \
      sessions_partial=0 allow_list_keys=0 ssh_open=0 ak_links=0 planted=0 "possible=$ids" "incidents=$ids" "platforms=opencode railway zeabur" on_open=0 \
      to_read=0 "updates=$ids" wiper=1 "lock_only=$ids" "remove=$ids" not_read=0 moved=0 tmp_marks= tmp_wiper=0 protected=ok \
      engine=dotnet end=1; do printf '%s\n' "$l"; done ;;
  hold) sleep 120 & echo "$!" > "$FWL_DIR/hold.pid"; echo "$$" > "$FWL_DIR/launcher.pid"
    printf '%s %s %s\n' "$!" "$$" "$(LC_ALL=C date '+%a %b %e %H:%M:%S %Y')" >> "$FWL_DIR/procs"; echo v=1; exec sleep 300 ;;
  stuck) echo "$$" > "$FWL_DIR/launcher.pid"; echo v=1; exec sleep 300 ;;
  *) exec env ${extra[@]+"${extra[@]}"} "$@" ;;
esac
