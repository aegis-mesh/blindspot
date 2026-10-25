#!/usr/bin/env bash
# Blindspot, the GIRD AI key check, version 1.2.0 (25 October 2026)
# https://gird.ai/blindspot
#
# Shows the AI coding agents and MCP servers on this machine, AI and cloud keys
# stored in plain text, keys saved in Claude Code allow lists, and signs of this
# week's LiteLLM, OpenCode, Railway and Zeabur incidents.
#
# It never uses sudo, starts an agent, an MCP server or Python, or prints a key.
# It reads files and prints paths and counts. It asks gird.ai for public totals
# when it starts. When it finishes it shares counts and a hashed device ID, never
# paths or keys, and gets back how you compare. --offline stops all of that.
# Key types and agent session locations come from data/keys.tsv and data/sessions.tsv.
#
#   bash gird-check.sh             a short summary; press 1 to 5 for details
#   bash gird-check.sh --full      every detail, no summary
#   bash gird-check.sh --all       also scans Desktop, Documents and Downloads
#   bash gird-check.sh --offline   shares nothing (DO_NOT_TRACK=1 works too)
#   bash gird-check.sh --save      saves the full report as a text file
#   bash gird-check.sh --no-game   skips the game while it scans
#   bash gird-check.sh --all-sessions  waits until every agent session is checked
#   NO_COLOR=1 bash gird-check.sh  plain text, no colors
#   For IT teams: gird-fleet.sh checks every account on a Mac (docs/fleet.md)

ORIG_LANG=${LC_ALL:-${LANG:-}}
export LC_ALL=C

ALL=0; SAVE=0; NOGAME=0; OFFLINE=0; FULL=0; ALLSESS=0
ACCTRUN=0
[ "${DO_NOT_TRACK:-0}" = 1 ] && OFFLINE=1
for arg in "$@"; do
  case "$arg" in
    --all-users) printf 'blindspot: to check every account, run gird-fleet.sh as root (docs/fleet.md)\n' >&2; exit 2 ;;
    --account-run) ACCTRUN=1 ;;
    --all) ALL=1 ;;
    --full) FULL=1 ;;
    --save) SAVE=1 ;;
    --no-game) NOGAME=1 ;;
    --all-sessions) ALLSESS=1 ;;
    --offline) OFFLINE=1 ;;
    --no-color) NO_COLOR=1 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed -n 's/^# \{0,1\}//p'; exit 0 ;;
    *) printf 'Unknown option: %s (try --help)\n' "$arg"; exit 2 ;;
  esac
done
# Run as root, the test settings are ignored. Checking every account is gird-fleet.sh's job.
if [ "$EUID" -eq 0 ]; then for _v in ${!GIRD_CHECK_*}; do unset "$_v"; done; fi
# An account run: started by root as one account, with a clean environment. Its only output is
# the fixed lines gird-fleet.sh reads, printed where the checks end; everything else goes nowhere.
if [ "$ACCTRUN" -eq 1 ]; then
  [ "$EUID" -ne 0 ] || exit 13
  OFFLINE=1; NOGAME=1; SAVE=0; NO_COLOR=1; FULL=1; ALL=0; ALLSESS=1
  exec 3>&1 >/dev/null 2>&1 </dev/null
  cd "${HOME:-/}" 2>/dev/null || cd / || exit 13
fi
VERSION=1
WEB=${GIRD_CHECK_WEB:-https://gird.ai}   # the overrides here are for testing
API=${GIRD_CHECK_API:-$WEB/api/check}

H=${HOME:-}
if [ -z "$H" ] || [ ! -d "$H" ]; then echo "HOME is not set."; exit 1; fi
OS=$(uname -s); ARCH=$(uname -m)
# Apple Silicon even when Terminal runs under Rosetta
if [ "$OS" = Darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then ARCH=arm64; fi
# WIN: Git Bash, MSYS2 or Cygwin on Windows. WSL: a Linux system inside Windows,
# scanned as Linux; its Windows-side files are not.
WIN=0; WSL=0
case "$OS" in
  MINGW*|MSYS*|CYGWIN*) WIN=1 ;;
  Linux) _pr=${GIRD_CHECK_PROC:-/proc}
         grep -qi microsoft "$_pr/sys/kernel/osrelease" "$_pr/version" 2>/dev/null && WSL=1 ;;
esac
# A Windows path such as C:\Users\me as this shell writes it: /c/Users/me, or
# /cygdrive/c/Users/me on Cygwin, where cygpath knows which.
winpath() {
  case "$1" in '') return 0 ;; /*) printf '%s' "$1"; return 0 ;; esac
  if command -v cygpath >/dev/null 2>&1; then _wp=$(cygpath -u "$1" 2>/dev/null) && [ -n "$_wp" ] && { printf '%s' "$_wp"; return 0; }; fi
  _wp=${1//\\//}
  case "$_wp" in
    [A-Za-z]:*) printf '/%s%s' "$(printf '%s' "${_wp%%:*}" | tr 'A-Z' 'a-z')" "${_wp#?:}" ;;
    *) printf '%s' "$_wp" ;;
  esac
}
# HH is the shell's own home, for its dotfiles. On Windows the agents keep theirs
# in the Windows profile, which can differ (Cygwin's /home/me, a HOME on another drive).
HH=$H
if [ "$WIN" -eq 1 ]; then
  _up=$(winpath "${USERPROFILE:-}"); _up=${_up%/}
  [ -n "$_up" ] && [ -d "$_up" ] && H=$_up
  WAPP=$(winpath "${APPDATA:-}"); WAPP=${WAPP%/}; [ -n "$WAPP" ] || WAPP="$H/AppData/Roaming"
  WLAPP=$(winpath "${LOCALAPPDATA:-}"); WLAPP=${WLAPP%/}; [ -n "$WLAPP" ] || WLAPP="$H/AppData/Local"
  WTEMP=$(winpath "${TEMP:-${TMP:-}}"); WTEMP=${WTEMP%/}; [ -n "$WTEMP" ] || WTEMP="$WLAPP/Temp"
  AS=$WAPP
  # Install folders of the per-user Windows installers, and Goose's config, which
  # follows the Windows layout rather than ~/.config.
  APP_CLAUDE="$WLAPP/AnthropicClaude"; APP_CURSOR="$WLAPP/Programs/cursor"
  APP_WINDSURF="$WLAPP/Programs/Windsurf"; APP_ANTIGRAVITY="$WLAPP/Programs/Antigravity"
  GOOSE_CFG="$WAPP/Block/goose/config"; GOOSE_DATA="$WAPP/Block/goose/data"; GOOSE_STATE=$GOOSE_DATA
  # Goose keeps its data and state under GOOSE_PATH_ROOT instead when that is an absolute path
  # (crates/goose/src/config/paths.rs).
  case "${GOOSE_PATH_ROOT:-}" in [A-Za-z]:[\\/]*) _gr=$(winpath "$GOOSE_PATH_ROOT"); GOOSE_DATA="${_gr%/}/data"; GOOSE_STATE="${_gr%/}/state" ;; esac
  PSRL="$WAPP/Microsoft/Windows/PowerShell/PSReadLine"
else
  if [ "$OS" = Darwin ]; then AS="$H/Library/Application Support"; else AS="$H/.config"; fi
  APP_CLAUDE=/Applications/Claude.app; APP_CURSOR=/Applications/Cursor.app
  APP_WINDSURF=/Applications/Windsurf.app; APP_ANTIGRAVITY=/Applications/Antigravity.app
  GOOSE_CFG="$H/.config/goose"
  # Goose keeps its data and state under GOOSE_PATH_ROOT when that is an absolute path, else in the
  # XDG folders, on a Mac too, each taken only when absolute (crates/goose/src/config/paths.rs).
  _gd=${XDG_DATA_HOME:-}; case "$_gd" in /*) ;; *) _gd="$H/.local/share" ;; esac
  _gs=${XDG_STATE_HOME:-}; case "$_gs" in /*) ;; *) _gs="$H/.local/state" ;; esac
  case "${GOOSE_PATH_ROOT:-}" in
    /*) GOOSE_DATA="${GOOSE_PATH_ROOT%/}/data"; GOOSE_STATE="${GOOSE_PATH_ROOT%/}/state" ;;
    *) GOOSE_DATA="$_gd/goose"; GOOSE_STATE="$_gs/goose" ;;
  esac
  WAPP=""; WLAPP=""; WTEMP=""; PSRL=""
fi
# An account run reads only regular files up to FLEET_MAX bytes: a fifo, socket, device or bigger
# file is not read and is counted, one line each in FLEET_NR, as not checked. Apps in /Applications
# and the shared temp folder are the Mac's, checked once by root, never as an account's.
FLEET_NR=""; FLEET_MAX=16777216; FLEET_PROT=ok
if [ "$ACCTRUN" -eq 1 ]; then
  APP_CLAUDE=""; APP_CURSOR=""; APP_WINDSURF=""; APP_ANTIGRAVITY=""
  case "${GIRD_CHECK_FLEET_MAX_BYTES:-}" in ''|*[!0-9]*) ;; *) FLEET_MAX=$GIRD_CHECK_FLEET_MAX_BYTES ;; esac
  FLEET_NR=$(/usr/bin/mktemp /tmp/blindspot.XXXXXX) || exit 13
  # Full Disk Access: a folder macOS protects is tried first. Refused means the protected folders
  # are not checked for this account, never that they are clear. With none of them there, there is
  # nothing protected to miss.
  FLEET_PROT=ok
  if [ -n "${GIRD_CHECK_FLEET_PROTECTED:-}" ]; then set -- "$GIRD_CHECK_FLEET_PROTECTED"
  else set -- "$H/Library/Safari" "$H/Library/Mail" "$H/Library/Messages"; fi
  for _fp in "$@"; do
    [ -d "$_fp" ] || continue
    if /bin/ls "$_fp" >/dev/null 2>&1; then FLEET_PROT=ok; else FLEET_PROT=refused; fi
    break
  done
fi
fleet_ok() { # file: 0 when it may be read; outside an account run, always
  [ "$ACCTRUN" -eq 1 ] || return 0
  # A file this account can't read counts as not checked, never as holding nothing.
  if [ -f "$1" ] && [ -r "$1" ]; then
    _fs=$(/usr/bin/stat -L -f %z -- "$1" 2>/dev/null)
    case "$_fs" in ''|*[!0-9]*) ;; *) [ "$_fs" -le "$FLEET_MAX" ] && return 0 ;; esac
  elif [ ! -e "$1" ]; then return 1; fi
  printf '%s\n' "$1" >> "$FLEET_NR"; return 1
}
fleet_filter() { # the paths on stdin that may be read; folders and the scan's "L path" lines pass
  if [ "$ACCTRUN" -ne 1 ]; then cat; return; fi
  while IFS= read -r _ff; do
    case "$_ff" in '') continue ;; 'L '*|'N '*) printf '%s\n' "$_ff"; continue ;; esac
    # A linked settings, tasks or planted file comes as "S path": the file it leads to is the one read.
    case "$_ff" in 'S '*) fleet_ok "${_ff#S }" && printf '%s\n' "$_ff"; continue ;; esac
    if [ -d "$_ff" ] || fleet_ok "$_ff"; then printf '%s\n' "$_ff"; fi
  done
}

# ---------------------------------------------------------------------------
# Look and feel. Colors only on a terminal, never with NO_COLOR or when piped.
# Text uses the terminal's own palette, so it reads on light and dark themes.
# ---------------------------------------------------------------------------
TTY=0; [ -t 1 ] && TTY=1
# A summary on a terminal, with details on request. Every detail with --full or
# when the output goes to a file or a pipe. GIRD_CHECK_COMPACT=1 is for tests.
COMPACT=0; [ "$TTY" -eq 1 ] && COMPACT=1
[ "${GIRD_CHECK_COMPACT:-}" = 1 ] && COMPACT=1
[ "$FULL" -eq 1 ] && COMPACT=0
E=$(printf '\033'); CR=$'\r'; NL=$'\n'
if [ "$TTY" -eq 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  RST="${E}[0m"; B="${E}[1m"; DIM="${E}[2m"; RED="${E}[31m"; GRN="${E}[32m"; YEL="${E}[33m"
  if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ] 2>/dev/null; then
    TEAL="${E}[38;5;44m"; GOLD="${E}[38;5;179m"
  else
    TEAL="${E}[36m"; GOLD="${E}[33m"
  fi
else
  RST=; B=; DIM=; RED=; GRN=; YEL=; TEAL=; GOLD=
fi
if [ "$TTY" -eq 1 ]; then HIDE="${E}[?25l"; SHOW="${E}[?25h"; else HIDE=; SHOW=; fi
W=80
if [ "$TTY" -eq 1 ]; then
  W=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
  case "$W" in ''|*[!0-9]*) W=80 ;; esac
  [ "$W" -gt 96 ] && W=96
  [ "$W" -lt 60 ] && W=60
fi
RULE=$(printf '%*s' $((W - 4)) '' | sed 's/ /─/g')

# Everything shown is also kept in REPORT, so it can be saved at the end. While
# CAPTURE=1, lines go to CAP instead, so the report can be built in parts and
# shown as a summary or in full.
REPORT=""; CAPTURE=0; CAP=""
emit() {
  if [ "$CAPTURE" -eq 1 ]; then CAP="$CAP$1
"; return 0; fi
  printf '%s\n' "$1"; REPORT="$REPORT$1
"
}
blank() { emit ""; }
# Paths are shown with control characters replaced, so a hostile file name
# can't send escape sequences to your terminal.
# shellcheck disable=SC2088  # prints a literal ~ for home paths, on purpose
short() {
  _s=${1//$'\xc2'[$'\x80'-$'\x9f']/?}; _s=${_s//[[:cntrl:]]/?}
  case "$_s" in "$H"/*) printf '~/%s' "${_s#"$H"/}" ;; *) printf '%s' "$_s" ;; esac
}
# A path or name read from disk, made safe to put in a report row: control characters become ?, as
# short() shows them anyway, so a TAB or a newline in a file name can't split the row it sits in.
rowsafe() { _r=${1//$'\xc2'[$'\x80'-$'\x9f']/?}; printf '%s' "${_r//[[:cntrl:]]/?}"; }
plural() { if [ "$1" = 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }
count_lines() { if [ -n "$1" ]; then printf '%s\n' "$1" | grep -c .; else printf 0; fi; }
sha_hex() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum 2>/dev/null; fi | cut -c1-64; }
# 1234567 -> 1,234,567
commas() {
  _cn=$1; _co=""
  while [ "${#_cn}" -gt 3 ]; do _co=",${_cn: -3}$_co"; _cn=${_cn:0:$((${#_cn} - 3))}; done
  printf '%s%s' "$_cn" "$_co"
}
# "a, b, c, d" 2 -> "a, b +2"
first_names() {
  _fo=""; _fc=0; _fr=0; _fifs=$IFS; IFS=','
  for _fx in $1; do
    _fx=${_fx# }; _fc=$((_fc + 1))
    if [ "$_fc" -le "$2" ]; then _fo="${_fo:+$_fo, }$_fx"; else _fr=$((_fr + 1)); fi
  done
  IFS=$_fifs
  [ "$_fr" -gt 0 ] && _fo="$_fo +$_fr"
  printf '%s' "$_fo"
}
# A whole number from a small JSON reply, or nothing. Only digits ever come out,
# so a reply can't put anything else on your screen.
jnum() {
  _jv=$(printf '%s' "$2" | grep -oE "\"$1\":[0-9]{1,12}([,}]|\$)" | head -n 1 | cut -d: -f2 | tr -d ',}')
  case "$_jv" in ''|*[!0-9]*) _jv="" ;; esac
  printf '%s' "$_jv"
}
# wrap TEXT INDENT_WIDTH FIRST_PREFIX REST_PREFIX [COLOR]
wrap() {
  _w=$((W - $2 - 3)); [ "$_w" -lt 20 ] && _w=20
  _folded=$(printf '%s\n' "$1" | fold -s -w "$_w" | sed 's/[[:space:]]*$//')
  _n=0
  while IFS= read -r _l; do
    if [ "$_n" -eq 0 ]; then emit "$3${5:-}$_l${5:+$RST}"; else emit "$4${5:-}$_l${5:+$RST}"; fi
    _n=1
  done <<EOF
$_folded
EOF
}
section() {
  blank
  _pad=$((W - 8 - ${#2} - ${#3})); [ "$_pad" -lt 2 ] && _pad=2
  emit "  ${TEAL}${B}$1${RST}  ${B}$2${RST}$(printf '%*s' "$_pad" '')${DIM}$3${RST}"
  emit "  ${DIM}${RULE}${RST}"
}
heading() {
  blank
  _pad=$((W - 4 - ${#1} - ${#2})); [ "$_pad" -lt 2 ] && _pad=2
  emit "  ${B}$1${RST}$(printf '%*s' "$_pad" '')${DIM}$2${RST}"
  emit "  ${DIM}${RULE}${RST}"
}
# pair GLYPH NAME NAME_WIDTH DETAIL: one aligned row; long names push detail down
pair() {
  if [ "${#2}" -gt "$3" ]; then
    emit "     $1  $2"
    emit "$(printf '%*s' $(($3 + 10)) '')$4"
  else
    printf -v _x '%-*s' "$3" "$2"
    emit "     $1  $_x  $4"
  fi
}

banner() {
  _wm=" ██████╗ ██╗██████╗ ██████╗
██╔════╝ ██║██╔══██╗██╔══██╗
██║  ███╗██║██████╔╝██║  ██║
██║   ██║██║██╔══██╗██║  ██║
╚██████╔╝██║██║  ██║██████╔╝
 ╚═════╝ ╚═╝╚═╝  ╚═╝╚═════╝"
  [ -n "$TEAL" ] && _wm=$(printf '%s\n' "$_wm" | sed -E "s/(╗|║|╔|═|╝|╚)+/${TEAL}&${RST}${B}/g")
  _r=0
  blank
  while IFS= read -r _row; do
    case $_r in
      0) _m="    ⢠⣤⣴⣶⣤⠄    " ;;
      1) _m=" ⢀⣴⣇⠘⣿⣿⠟⢁⣴⣿⣦⡀ " ;;
      2) _m=" ⣾⣿⣿⡀⠉⠁ ⠙⠻⠿⣿⣷ " ;;
      3) _m=" ⠙⠛⠻⠁ ${GOLD}⠰⠆${TEAL} ⢀⣦⣤⣄⡀" ;;
      4) _m=" ⢿⣿⣶⣦⣄ ⢀⣀⠈⣿⣿⡿ " ;;
      *) _m=" ⠈⠻⣿⠟⢁⣴⣿⣿⡄⢹⠟⠁ " ;;
    esac
    emit "  ${TEAL}${_m}${RST}   ${B}${_row}${RST}"
    _r=$((_r + 1))
  done <<EOF
$_wm
EOF
  emit "  ${TEAL}    ⠐⠛⠿⠿⠛⠃    ${RST}   ${B}BLINDSPOT${RST}  ${DIM}v1.2.0 · 25 Oct 2026 · gird.ai/blindspot${RST}"
  blank
  emit "  ${DIM}Read-only. Prints paths and counts, never a key.${RST}"
  if [ "$OFFLINE" -eq 0 ]; then
    emit "  ${DIM}Shares counts and a hashed device ID with gird.ai. --offline skips it.${RST}"
  fi
  if [ "$ALL" -eq 0 ]; then
    emit "  ${DIM}Skips Desktop, Documents and Downloads. Add --all to include them.${RST}"
  fi
}
# One line of real, public totals under the banner, picked at random from the
# ones big enough to mean something. Nothing when they don't arrive in time.
# Below 1,000 developers it shows nothing: the header says you're one of the
# first 1,000 instead, with your number once the reply brings it.
proof_line() {
  [ -n "$SP_PID" ] || return 0
  wait "$SP_PID" 2>/dev/null; SP_PID=""
  _pj=$(head -c 65536 "$SP_FILE" 2>/dev/null | tr -d ' \n\r\t')
  _dv=$(jnum devices "$_pj"); _d7=$(jnum devices_7d "$_pj"); _kf=$(jnum key_files "$_pj")
  _cl=$(printf '%s' "$_pj" | grep -oE '"clean":(0(\.[0-9]{1,6})?|1(\.0{1,6})?)([,}]|$)' | head -n 1 | sed -E 's/"clean":([0-9.]+).*/\1/')
  [ -n "$_dv" ] || return 0
  if [ "$_dv" -lt 1000 ]; then EARLY=1; return 0; fi
  _pm=()
  _pm[0]="$(commas "$_dv") AI builders have run Blindspot."
  if [ -n "$_d7" ] && [ "$_d7" -ge 50 ]; then _pm[${#_pm[@]}]="$(commas "$_d7") AI builders ran it this week."; fi
  if [ -n "$_kf" ] && [ "$_kf" -ge 100 ]; then _pm[${#_pm[@]}]="Blindspot has found $(commas "$_kf") files with AI keys in plain text so far."; fi
  if [ -n "$_cl" ]; then
    _cp=$(awk -v c="$_cl" 'BEGIN { printf "%d", c * 100 + 0.5 }')
    if [ "$_cp" -ge 1 ] && [ "$_cp" -le 99 ]; then _pm[${#_pm[@]}]="$_cp% of AI builders had no keys in plain text. Let's see about you."; fi
  fi
  printf '\n  %s★%s %s%s%s\n' "$GOLD" "$RST" "$B" "${_pm[$((RANDOM % ${#_pm[@]}))]}" "$RST"
}

# ---------------------------------------------------------------------------
# A spinner, used when the game can't run. It draws on the terminal only.
# ---------------------------------------------------------------------------
SPIN_PID=""
spin_start() {
  [ "$TTY" -eq 1 ] || return 0
  printf '%s' "$HIDE"
  (
    trap 'exit 0' TERM
    _i=0; _s=$SECONDS; _f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; _lbl=$1; _mx=$((W - 16))
    while :; do
      if [ -n "$PROG_FILE" ] && [ $((_i % 5)) -eq 0 ]; then # the latest finding, twice a second
        _tk=""; IFS= read -r _tk 2>/dev/null < "$PROG_FILE"
        if [ -n "$_tk" ]; then _lbl=${_tk#?|}; [ "${#_lbl}" -gt "$_mx" ] && _lbl="${_lbl:0:$((_mx - 3))}..."; fi
      fi
      printf '\r  %s%s%s  %s  %s%ss%s%s' "$TEAL" "${_f:$(( (_i % 10) * 3 )):3}" "$RST" "$_lbl" "$DIM" "$((SECONDS - _s))" "$RST" "${E}[K"
      _i=$((_i + 1)); sleep 0.1
    done
  ) &
  SPIN_PID=$!
}
spin_stop() {
  [ -n "$SPIN_PID" ] || return 0
  kill "$SPIN_PID" 2>/dev/null; wait "$SPIN_PID" 2>/dev/null; SPIN_PID=""
  printf '\r%s%s' "${E}[K" "$SHOW"
}

# ---------------------------------------------------------------------------
# GIRD Runner, a small game for the wait. It runs in a background process while
# the scan runs in the foreground. When the scan is done the game gets USR1 and
# asks whether to show the results, or just leaves if it hasn't been drawn yet. Its exit code says whether it was played
# and roughly the best score. How it keeps time depends on the bash running it:
#   A  bash 5+   reads keys with timeouts against the microsecond clock
#   B  bash 4    reads keys with a frame-long timeout
#   C  bash 3.2  a helper reads keys and signals the game, which sleeps per frame.
#                The main script sets the terminal up once for both of them and puts
#                it back after both have stopped, so they never race over its mode.
# The runner is drawn with half-height blocks, so it moves in half-row steps.
# ---------------------------------------------------------------------------
GAME_PID=""; KEYS_PID=""; GAME_RC=0; SAVED_TTY=""
if [ -n "${EPOCHREALTIME:-}" ]; then G_MODE=A; elif [ "${BASH_VERSINFO[0]:-3}" -ge 4 ]; then G_MODE=B; else G_MODE=C; fi
# stty must work on /dev/tty too: some Windows terminals (mintty without a console)
# have a terminal on stdin that stty can't set, and then the spinner is shown instead.
game_ok() {
  [ "$NOGAME" -eq 0 ] && [ "$TTY" -eq 1 ] && [ -t 0 ] && [ -n "$TEAL" ] && [ "$W" -ge 64 ] && command -v stty >/dev/null 2>&1 &&
    stty -g </dev/tty >/dev/null 2>&1
}
g_act() { # a typed character to an action
  case "$1" in
    ' '|w|W|k|K|A) _a=jump ;; q|Q) _a=quit ;; c|C) _a=cont ;; r|R|"$CR"|'') _a=enter ;; *) _a="" ;;
  esac
}
g_merge() { # keep the most important action seen during a frame
  [ -n "$1" ] || return 0
  if [ -z "$G_K" ] || [ "$G_K" = jump ]; then G_K=$1; fi
}
g_keys() { # mode C helper: forward keys to the game ($1) as signals; stops when the game does.
  # It reads raw bytes and never changes the terminal. Each read returns after half
  # a second at most, with or without a key, so it notices quickly when to stop.
  trap 'exit 0' TERM INT
  while kill -0 "$1" 2>/dev/null; do
    _k=$(dd bs=1 count=1 2>/dev/null | od -An -tu1); _k=${_k// /}
    case "$_k" in
      32|119|87|107|75|65) kill -USR2 "$1" 2>/dev/null ;;   # space w k, or the up arrow
      10|13|114|82) kill -ALRM "$1" 2>/dev/null ;;          # enter r
      99|67) kill -VTALRM "$1" 2>/dev/null ;;               # c
      113|81) kill -PROF "$1" 2>/dev/null ;;                # q
    esac
  done
}
g_wait() { # wait out the frame on a steady clock, collecting the action typed meanwhile
  G_K=""
  case "$G_MODE" in
    A)
      while :; do
        _rem=$((G_NEXT_US - ${EPOCHREALTIME/./}))
        [ "$_rem" -le 0 ] && break
        [ "$_rem" -gt 999999 ] && _rem=999999
        printf -v _t '0.%06d' "$_rem"
        _c=x
        if IFS= read -rsn1 -t "$_t" _c; then g_act "$_c"; g_merge "$_a"; fi
      done
      G_NEXT_US=$((G_NEXT_US + G_FRAME_US))
      _lag=$((${EPOCHREALTIME/./} - G_NEXT_US))
      [ "$_lag" -gt $((G_FRAME_US * 3)) ] && G_NEXT_US=$((${EPOCHREALTIME/./} + G_FRAME_US)) ;;
    B)
      _c=x
      if IFS= read -rsn1 -t 0.033 _c; then g_act "$_c"; g_merge "$_a"; fi ;;
    *)
      sleep "$G_SLEEP"
      G_K=$G_SIG; G_SIG="" ;;
  esac
}
g_preset() { # physics tuned to the frame rate: jump speed, gravity, run speed (tenths)
  if [ "$1" -ge 24 ]; then G_V=22; G_G=3; G_SPD0=10; G_SPDMAX=19
  elif [ "$1" -ge 16 ]; then G_V=27; G_G=5; G_SPD0=14; G_SPDMAX=26
  else G_V=33; G_G=7; G_SPD0=19; G_SPDMAX=34; fi
}
g_build() { # borders and scrolling layers; all three-byte characters, so bytes map to columns
  G_TOP="╭"; _i=0
  while [ "$_i" -lt "$G_W" ]; do G_TOP="$G_TOP─"; _i=$((_i + 1)); done
  G_TOP="$G_TOP╮"
  G_STARS=""; G_CITY=""; G_GND=""; _i=0; _run=0; _h=0
  RANDOM=7
  while [ "$_i" -lt $((G_W + 64)) ]; do
    if [ $(( (_i * 7) % 23 )) -eq 3 ]; then G_STARS="$G_STARS⠂"
    elif [ $(( (_i * 11) % 37 )) -eq 5 ]; then G_STARS="$G_STARS⠈"
    else G_STARS="$G_STARS⠀"; fi
    if [ "$_run" -le 0 ]; then _run=$((2 + RANDOM % 5)); _h=$((RANDOM % 6)); fi
    case $_h in 0) G_CITY="$G_CITY⠀" ;; 1) G_CITY="$G_CITY▁" ;; 2|5) G_CITY="$G_CITY▂" ;; 3) G_CITY="$G_CITY▃" ;; *) G_CITY="$G_CITY▄" ;; esac
    _run=$((_run - 1))
    if [ $((_i % 9)) -eq 4 ]; then G_GND="$G_GND╌"; else G_GND="$G_GND─"; fi
    _i=$((_i + 1))
  done
}
g_reset() {
  G_SCORE=0; G_DIST10=0; G_OX=(); G_OT=(); G_NEXT10=220; G_Y10=0; G_VY=0; G_BUF=0
  G_SPD=$G_SPD0; G_NEWBEST=0; G_START_BEST=$G_BEST; G_MILE=0; G_FLASH=0
}
g_jump() { # jump from the ground; a press just before landing is kept for a few frames
  if [ "$G_Y10" -eq 0 ] && [ "$G_VY" -eq 0 ]; then G_VY=$G_V; G_Y10=1
  elif [ "$G_VY" -lt 0 ]; then G_BUF=5; fi
}
g_tick() {
  G_DIST10=$((G_DIST10 + G_SPD)); G_SCORE=$((G_DIST10 / 10))
  if [ "$G_SCORE" -gt "$G_BEST" ]; then G_BEST=$G_SCORE; [ "$G_START_BEST" -gt 0 ] && G_NEWBEST=1; fi
  if [ $((G_SCORE / 100)) -gt "$G_MILE" ]; then G_MILE=$((G_SCORE / 100)); G_FLASH=12; fi
  _sp=$((G_SPD0 + G_SCORE / 120)); [ "$_sp" -gt "$G_SPDMAX" ] && _sp=$G_SPDMAX; G_SPD=$_sp
  if [ "$G_Y10" -gt 0 ] || [ "$G_VY" -gt 0 ]; then
    G_VY=$((G_VY - G_G)); G_Y10=$((G_Y10 + G_VY))
    if [ "$G_Y10" -le 0 ]; then
      G_Y10=0; G_VY=0
      if [ "$G_BUF" -gt 0 ]; then G_VY=$G_V; G_Y10=1; G_BUF=0; fi
    fi
  fi
  [ "$G_BUF" -gt 0 ] && G_BUF=$((G_BUF - 1))
  _nx=(); _nt=(); _n=0
  for _i in "${!G_OX[@]}"; do
    _x=$((G_OX[_i] - G_SPD)); _t=${G_OT[_i]}
    if [ $((_x / 10 + ${#_t})) -gt 0 ]; then _nx[_n]=$_x; _nt[_n]=$_t; _n=$((_n + 1)); fi
  done
  G_OX=("${_nx[@]}"); G_OT=("${_nt[@]}")
  G_NEXT10=$((G_NEXT10 - G_SPD))
  if [ "$G_NEXT10" -le 0 ]; then
    _n=${#G_OX[@]}
    G_OX[_n]=$(( (G_W - 1) * 10 )); G_OT[_n]=${G_TOKS[$((RANDOM % ${#G_TOKS[@]}))]}
    G_NEXT10=$(( (24 + RANDOM % 21) * 10 ))
  fi
  if [ $((G_Y10 / 10)) -le 1 ]; then # the runner's lowest pixel is in the key row
    for _i in "${!G_OX[@]}"; do
      _x=$((G_OX[_i] / 10)); _t=${G_OT[_i]}
      if [ "$_x" -le $((G_PX + 1)) ] && [ $((_x + ${#_t} - 1)) -ge "$G_PX" ]; then G_STATE=over; G_SINCE=$SECONDS; fi
    done
  fi
}
g_center() { # text visible-length color: centre the text in the arena row being built
  _cx=$((3 + (G_W - $2) / 2)); [ "$_cx" -lt 3 ] && _cx=3
  _r="$_r$CR${E}[${_cx}C$3$1$RST"
}
g_row() { # level (5 top .. 0 ground): build one arena row in _r
  case "$1" in
    5|4) _bg=${G_STARS:$(( (G_DIST10 / 80 + $1 * 7) % 64 * 3 )):$((G_W * 3))} ;;
    1)   _bg=${G_CITY:$(( (G_DIST10 / 30) % 64 * 3 )):$((G_W * 3))} ;;
    *)   _bg="" ;;
  esac
  _r="$CR${E}[K  ${TEAL}│${RST}${DIM}${_bg}${RST}$CR${E}[$((G_W + 3))C${TEAL}│${RST}"
  if [ "$1" -eq 0 ]; then
    for _i in "${!G_OX[@]}"; do
      _x=$((G_OX[_i] / 10)); _t=${G_OT[_i]}
      if [ "$_x" -lt 0 ]; then _t=${_t:$((0 - _x))}; _x=0; fi
      if [ $((_x + ${#_t})) -gt "$G_W" ]; then _t=${_t:0:$((G_W - _x))}; fi
      [ -n "$_t" ] && _r="$_r$CR${E}[$((3 + _x))C${RED}${B}${_t}${RST}"
    done
    if [ "$G_STATE" = run ] && [ "$G_Y10" -eq 0 ]; then
      if [ $((G_F % 2)) -eq 0 ]; then _du="⠤⠀"; else _du="⠀⠒"; fi
      _r="$_r$CR${E}[$((1 + G_PX))C${DIM}${_du}${RST}"
    fi
  fi
  _y=$((G_Y10 / 10)); _bp=$((2 * $1)); _tp=$((_bp + 1)); _lo=0; _hi=0
  [ "$_y" -le "$_bp" ] && [ "$_bp" -le $((_y + 1)) ] && _lo=1
  [ "$_y" -le "$_tp" ] && [ "$_tp" -le $((_y + 1)) ] && _hi=1
  _gl=""
  if [ "$_lo" -eq 1 ] && [ "$_hi" -eq 1 ]; then _gl="██"; elif [ "$_lo" -eq 1 ]; then _gl="▄▄"; elif [ "$_hi" -eq 1 ]; then _gl="▀▀"; fi
  if [ -n "$_gl" ]; then
    if [ "$G_STATE" = over ]; then _gc=$RED; else _gc=$TEAL; fi
    _r="$_r$CR${E}[$((3 + G_PX))C${_gc}${B}${_gl}${RST}"
  fi
  case "$G_STATE:$G_READY:$1" in
    idle:0:3)    g_center "Press SPACE to jump the leaked keys" 35 "$B" ;;
    idle:0:2)    g_center "your scan keeps running underneath" 34 "$DIM" ;;
    over:*:5)    [ "$G_NEWBEST" -eq 1 ] && g_center "NEW BEST $_bs5" 14 "$GOLD$B" ;;
    over:1:4)    g_center "✓ Your results are ready" 24 "$GRN$B" ;;
    over:0:4)    [ "$G_NEWBEST" -eq 1 ] && g_center "NEW BEST $_bs5" 14 "$GOLD$B" ;;
    over:*:3)    g_center "✗ A leaked key got you" 22 "$RED$B" ;;
    over:0:2)    g_center "SPACE to run again" 18 "$DIM" ;;
    over:1:2)    g_center "SPACE run again    ENTER see results" 36 "$B" ;;
    stopped:*:3) g_center "Paused" 6 "$B" ;;
    stopped:*:2) g_center "SPACE to play again" 19 "$DIM" ;;
    ask:*:4)     g_center "✓ Your results are ready" 24 "$GRN$B" ;;
    ask:*:3)     g_center "We know you loved the game." 27 "" ;;
    ask:*:2)     g_center "ENTER see results    C keep playing" 35 "$B" ;;
  esac
}
g_draw() {
  G_F=$((G_F + 1))
  printf -v _sc ' score %05d   best %05d ' "$G_SCORE" "$G_BEST"
  printf -v _bs5 '%05d' "$G_BEST"
  if [ "$G_FLASH" -gt 0 ]; then _scol="$GOLD$B"; G_FLASH=$((G_FLASH - 1))
  elif [ "$G_NEWBEST" -eq 1 ] && [ "$G_STATE" = run ]; then _scol=$GOLD; else _scol=""; fi
  _o="${E}[${G_H}A$CR${E}[K  ${TEAL}${G_TOP}${RST}$CR${E}[4C${TEAL}${B} GIRD RUNNER ${RST}${DIM}jump the leaked keys ${RST}"
  _o="$_o$CR${E}[$((G_W + 2 - ${#_sc}))C${_scol}${_sc}${RST}$NL"
  for _L in 5 4 3 2 1 0; do g_row "$_L"; _o="$_o$_r$NL"; done
  _o="$_o$CR${E}[K  ${TEAL}╰${DIM}${G_GND:$(( (G_DIST10 / 10) % 64 * 3 )):$((G_W * 3))}${RST}${TEAL}╯${RST}$NL"
  _sp=${G_SPIN:$(( (G_F % 10) * 3 )):3}; _el=$((SECONDS - G_T0)); _rt=""
  if [ "$G_READY" -eq 0 ]; then
    _m="${TEAL}${_sp}${RST} ${DIM}Scanning your home folder, ${_el}s${RST}"; _rt="SPACE jump   Q stop"
  elif [ "$G_STATE" = run ]; then
    _m="${GRN}✓${RST} ${DIM}Results ready. ENTER shows them, or we'll ask again in $((G_REMIND - SECONDS))s.${RST}"
  else
    _m="${GRN}✓${RST} ${DIM}Results ready${RST}"; [ "$G_STATE" = ask ] && _rt="C keeps playing, with a reminder in a minute"
  fi
  _o="$_o$CR${E}[K  $_m"
  [ -n "$_rt" ] && _o="$_o$CR${E}[$((G_W + 4 - ${#_rt}))C${DIM}${_rt}${RST}"
  # The latest thing the scan found, read from its progress file a few times a second.
  if [ -n "$PROG_FILE" ] && [ $((G_F % 10)) -eq 1 ]; then
    _tk=""; IFS= read -r _tk 2>/dev/null < "$PROG_FILE"; [ -n "$_tk" ] && G_TICK=$_tk
  fi
  _o="$_o$NL$CR${E}[K"
  if [ -n "$G_TICK" ]; then
    case "$G_TICK" in x\|*) _tg="${RED}✗${RST}" ;; w\|*) _tg="${YEL}!${RST}" ;; o\|*) _tg="${GRN}✓${RST}" ;; *) _tg="${TEAL}·${RST}" ;; esac
    _tt=${G_TICK#?|}; [ "${#_tt}" -gt $((G_W - 2)) ] && _tt="${_tt:0:$((G_W - 5))}..."
    _o="$_o    $_tg ${DIM}${_tt}${RST}"
  fi
  printf '%s' "$_o$NL"
}
g_step() { # returns 1 when the game should end
  case "$G_STATE" in
    idle|stopped)
      [ "$G_READY" -eq 1 ] && return 1
      if [ "$G_K" = jump ]; then G_STATE=run; G_PLAYED=1; g_reset; g_jump; fi ;;
    run)
      if [ "$G_READY" -eq 1 ] && [ "$G_K" = enter ]; then return 1; fi
      if [ "$G_K" = quit ]; then [ "$G_READY" -eq 1 ] && return 1; G_STATE=stopped; return 0; fi
      [ "$G_K" = jump ] && g_jump
      g_tick
      if [ "$G_READY" -eq 1 ] && [ "$G_STATE" = run ] && [ "$SECONDS" -ge "$G_REMIND" ]; then G_STATE=ask; G_SINCE=$SECONDS; fi ;;
    over)
      if [ "$G_READY" -eq 1 ]; then
        case "$G_K" in enter|quit) return 1 ;; esac
        [ $((SECONDS - G_SINCE)) -ge 120 ] && return 1
      elif [ "$G_K" = quit ]; then
        G_STATE=stopped; return 0
      fi
      if [ "$G_K" = jump ] && [ $((SECONDS - G_SINCE)) -ge 1 ]; then G_STATE=run; g_reset; g_jump; fi ;;
    ask)
      case "$G_K" in
        enter|quit) return 1 ;;
        cont|jump) G_STATE=run; G_REMIND=$((SECONDS + 60)) ;;
      esac
      [ $((SECONDS - G_SINCE)) -ge 120 ] && return 1 ;;
  esac
  return 0
}
g_end() {
  [ -n "$G_DONE" ] && return 0
  G_DONE=1
  if [ "$G_HOLDING" -eq 1 ]; then printf '%s' "$CR${E}[K"   # the game's rows are not drawn yet
  else
    _o="${E}[${G_H}A"; _i=0
    while [ "$_i" -lt "$G_H" ]; do _o="$_o$CR${E}[K$NL"; _i=$((_i + 1)); done
    printf '%s%s' "$_o" "${E}[${G_H}A"
  fi
  [ "$G_MODE" = C ] || stty "$G_SAVED" 2>/dev/null || stty sane 2>/dev/null
  printf '%s' "$SHOW"
}
game_loop() {
  trap 'G_READY=1' USR1
  trap 'g_end; exit 0' TERM INT
  G_SIG=""
  if [ "$G_MODE" = C ]; then
    trap '[ -z "$G_SIG" ] && G_SIG=jump' USR2
    trap 'G_SIG=enter' ALRM; trap 'G_SIG=cont' VTALRM; trap 'G_SIG=quit' PROF
  fi
  G_READY=0; G_HOLDING=1; G_PLAYED=0; G_STATE=idle; G_BEST=0; G_F=0; G_REMIND=0; G_SINCE=0; G_DONE=""
  G_W=$((W - 6)); [ "$G_W" -gt 72 ] && G_W=72
  G_PX=6; G_H=10; G_TICK=""
  G_TOKS=("sk-ant" "AKIA" "ghp_" ".env" "sk-" "npm_" "xai-")
  G_SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  G_T0=$SECONDS
  g_build
  _seed=${EPOCHREALTIME/./}; [ -n "$_seed" ] || _seed=$(date +%s)
  RANDOM=$((_seed % 32768))
  if [ "$G_MODE" = C ]; then g_preset 18; G_SLEEP=0.03; G_FPS_AT=$((SECONDS + 1)); G_FPS_N=0; G_FPS_DONE=0
  else g_preset 30; G_FPS_DONE=1; fi
  g_reset
  G_FRAME_US=33333; G_NEXT_US=0
  [ "$G_MODE" = A ] && G_NEXT_US=$((${EPOCHREALTIME/./} + G_FRAME_US))
  # Modes A and B read keys right here, so the game owns the terminal. In mode C
  # the main script has already set it up and will put it back.
  if [ "$G_MODE" != C ]; then G_SAVED=$(stty -g 2>/dev/null); stty -echo -icanon -icrnl min 0 time 0 2>/dev/null; fi
  printf '%s' "$HIDE"
  # A fast scan never shows the game: it waits out G_HOLD seconds behind a one-line
  # spinner, and leaves without drawing if the results are ready first.
  G_HOLD=2; _hi=0
  while [ "$G_READY" -eq 0 ] && [ $((SECONDS - G_T0)) -le "$G_HOLD" ]; do
    printf '%s  %s%s%s  %sChecking your agents, configs and keys%s' "$CR${E}[K" "$TEAL" "${G_SPIN:$(( (_hi % 10) * 3 )):3}" "$RST" "$DIM" "$RST"
    _hi=$((_hi + 1)); sleep 0.1
  done
  printf '%s' "$CR${E}[K"
  if [ "$G_READY" -eq 1 ]; then
    [ "$G_MODE" = C ] || stty "$G_SAVED" 2>/dev/null || stty sane 2>/dev/null
    printf '%s' "$SHOW"; exit 0
  fi
  G_HOLDING=0
  _i=0; while [ "$_i" -lt "$G_H" ]; do printf '\n'; _i=$((_i + 1)); done
  while :; do
    g_wait
    if [ "$G_FPS_DONE" -eq 0 ] && [ "$SECONDS" -ge "$G_FPS_AT" ]; then # mode C: measure the real frame rate once
      G_FPS_N=$((G_FPS_N + 1))
      if [ "$SECONDS" -ge $((G_FPS_AT + 2)) ]; then
        g_preset $((G_FPS_N / 2)); G_FPS_DONE=1
        [ "$G_STATE" = run ] || G_SPD=$G_SPD0
      fi
    fi
    g_step || break
    g_draw
  done
  g_end
  if [ "$G_PLAYED" -eq 1 ]; then _b=$((G_BEST / 50 + 1)); [ "$_b" -gt 100 ] && _b=100; exit "$_b"; fi
  exit 0
}

# Keys for the menu at the end: one key, read straight from the terminal.
read_key() {
  _rs=$(stty -g </dev/tty 2>/dev/null)
  stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null
  _rk=$(dd bs=1 count=1 2>/dev/null </dev/tty | od -An -tu1)
  stty "$_rs" </dev/tty 2>/dev/null
  RK=${_rk// /}
}
# Drop anything typed during the scan, so it can't answer a question by accident.
drain_keys() {
  _rs=$(stty -g </dev/tty 2>/dev/null)
  stty -echo -icanon min 0 time 0 </dev/tty 2>/dev/null
  _n=0
  while [ "$_n" -lt 50 ] && [ -n "$(dd bs=256 count=1 2>/dev/null </dev/tty | od -An -tu1)" ]; do _n=$((_n + 1)); done
  stty "$_rs" </dev/tty 2>/dev/null
}

PROG_FILE=""; SP_FILE=""; SP_PID=""; EARLY=0
SESS_PID=""; SESS_FILTER_PID=""; SESS_DIR=""; SESS_FIFO=""; SESS_FILE=""; SESS_WIN=0
cleanup() {
  spin_stop
  sess_stop kill
  if [ -n "$SP_PID" ]; then kill "$SP_PID" 2>/dev/null; wait "$SP_PID" 2>/dev/null; SP_PID=""; fi
  if [ -n "$GAME_PID" ]; then kill "$GAME_PID" 2>/dev/null; wait "$GAME_PID" 2>/dev/null; GAME_PID=""; fi
  if [ -n "$KEYS_PID" ]; then kill "$KEYS_PID" 2>/dev/null; wait "$KEYS_PID" 2>/dev/null; KEYS_PID=""; fi
  if [ -n "$SAVED_TTY" ]; then stty "$SAVED_TTY" </dev/tty 2>/dev/null; SAVED_TTY=""; fi
  [ -n "$PROG_FILE" ] && rm -f "$PROG_FILE"
  [ -n "$SCAN_ERR" ] && rm -f "$SCAN_ERR"
  [ -n "$SP_FILE" ] && rm -f "$SP_FILE"
  [ -n "$SESS_DIR" ] && rm -rf "$SESS_DIR"
  [ -n "$FLEET_NR" ] && rm -f "$FLEET_NR"
  printf '%s' "$SHOW"
}
trap cleanup EXIT
trap 'cleanup; printf "\n"; exit 130' INT TERM
trap 'cleanup; exit 129' HUP

# ---------------------------------------------------------------------------
# Key formats. Matching uses grep -q or grep -o into a pipe, so a key is never
# printed, kept in a shell variable or sent anywhere.
# ---------------------------------------------------------------------------
# >>> keys: generated from data/keys.tsv by tools/gen.sh. Edit that file, then run it.
ALL_KEYS='sk-ant-[A-Za-z0-9_-]{90,}|sk-or-v1-[a-f0-9]{64}|sk-proj-[A-Za-z0-9_-]{120,}|sk-proj-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}([^A-Za-z0-9_-]|$)|sk-svcacct-[A-Za-z0-9_-]{60,}|sk-admin-[A-Za-z0-9_-]{120,}|(^|[^A-Za-z0-9-])sk-[A-Za-z0-9]{48}([^A-Za-z0-9]|$)|AIza[0-9A-Za-z_-]{35}|(^|[^A-Za-z0-9])AQ\.[A-Za-z0-9_-]{40,}|gsk_[A-Za-z0-9]{52}|xai-[A-Za-z0-9]{64,}|(^|[^A-Za-z0-9_])hf_[A-Za-z0-9]{34,40}([^A-Za-z0-9_]|$)|pplx-[A-Za-z0-9]{40,52}|r8_[A-Za-z0-9]{37}|(^|[^A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}([^A-Z0-9]|$)|ABSKQmVkcm9ja0FQSUtleS[A-Za-z0-9+/]{60,}|bedrock-api-key-YmVkcm9jay5hbWF6b25hd3MuY29t|gh[pour]_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9_.-]{36,}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}|npm_[A-Za-z0-9]{36}'
PROVIDER_IDS="anthropic openrouter openai google groq xai huggingface perplexity replicate aws github npm"
KEY_STARTS='sk-ant-|sk-or-v1-|sk-|AIza|AQ[.]|gsk_|xai-|hf_|pplx-|r8_|AKIA|ASIA|ABSK|bedrock-api-key|gh[pousr]_|github_pat_|npm_'
PROV_AWK='
function prov(s) {
  sub(/^[^A-Za-z]*\\[ntr"]/, "", s); sub(/^[^A-Za-z]+/, "", s)
  if (s ~ /^(sk-ant-)/) return "Anthropic"
  if (s ~ /^(sk-or-v1-)/) return "OpenRouter"
  if (s ~ /^(sk-)/) return "OpenAI"
  if (s ~ /^(AIza|AQ[.])/) return "Google"
  if (s ~ /^(gsk_)/) return "Groq"
  if (s ~ /^(xai-)/) return "xAI"
  if (s ~ /^(hf_)/) return "Hugging Face"
  if (s ~ /^(pplx-)/) return "Perplexity"
  if (s ~ /^(r8_)/) return "Replicate"
  if (s ~ /^(AKIA|ASIA|ABSK|bedrock-api-key)/) return "AWS"
  if (s ~ /^(gh[pousr]_|github_pat_)/) return "GitHub"
  if (s ~ /^(npm_)/) return "npm"
  return ""
}'
prov_id() { case "$1" in "Anthropic") printf anthropic ;; "OpenRouter") printf openrouter ;; "OpenAI") printf openai ;; "Google") printf google ;; "Groq") printf groq ;; "xAI") printf xai ;; "Hugging Face") printf huggingface ;; "Perplexity") printf perplexity ;; "Replicate") printf replicate ;; "AWS") printf aws ;; "GitHub") printf github ;; "npm") printf npm ;; esac; }
# <<< keys
# Agent sessions are JSON, where a key often follows an escape such as \n, so a backslash escape
# also counts as the boundary in front of a key.
TR_KEYS=$(printf '%s' "$ALL_KEYS" | sed 's/(^|\[^\([^]]*\)\])/(^|[^\1]|\\\\[ntr"])/g')

# A secret written as a value: KEY=value in a command, or "token": "value" in a config.
P_ASSIGN='[A-Z][A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*=[^[:space:]"$\\]{12,}'
P_JSONSECRET='"([A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*|apiKey|api_key|accessToken|access_token|authToken|token|secret)"[[:space:]]*:[[:space:]]*"[^"$<{][^"]{11,}"'
P_TOMLSECRET='[A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*[[:space:]]*=[[:space:]]*"[^"$<{][^"]{11,}"'
P_PLACEHOLDER='your|xxxx|here|example|placeholder|changeme|dummy|<|[$][{]'

providers_in() {
  grep -aoE "$ALL_KEYS" "$1" 2>/dev/null | awk "$PROV_AWK"'
    { p = prov($0); if (p == "") next
      if (!(p in seen)) { seen[p] = 1; out = out (out == "" ? "" : ", ") p } }
    END { printf "%s", out }'
}
# Print the files in a newline list that contain a match, in order, with one grep pass.
files_matching() { # pattern; list on stdin
  tr '\n' '\0' | xargs -0 grep -alE "$1" 2>/dev/null
}
inline_secret() {
  grep -aoE "$ALL_KEYS|$P_JSONSECRET|$P_TOMLSECRET" "$1" 2>/dev/null | grep -viE "$P_PLACEHOLDER" | grep -q .
}
command_secret() {
  grep -aoE "$ALL_KEYS|$P_ASSIGN" "$1" 2>/dev/null | grep -viE "$P_PLACEHOLDER" | grep -q .
}

# ---------------------------------------------------------------------------
# Fixed lists for the case-study counts in the report. Only ids from these
# lists, counts and yes/no leave the Mac: never a path, a file name or a name
# you gave an MCP server. gird.ai keeps the same lists and drops anything else,
# so change both together. Agent ids are in the table under "1. Coding agents".
# ---------------------------------------------------------------------------
# Key providers, for key_providers and provider_files (names in providers_in).

# MCP clients, for mcp_clients and mcp_token_clients, by the file the servers are in:
#   claude-code     ~/.claude.json, and .mcp.json in a project folder
#   claude-desktop  Claude Desktop's claude_desktop_config.json
#   cursor          ~/.cursor/mcp.json, and .cursor/mcp.json in a project folder
#   windsurf        ~/.codeium/windsurf/mcp_config.json
#   codex           ~/.codex/config.toml
#   gemini-cli      ~/.gemini/settings.json
#   vscode          VS Code's mcp.json, and .vscode/mcp.json in a project folder
#   cline           Cline's cline_mcp_settings.json, in VS Code or in Cursor
#   continue        ~/.continue/config.json and ~/.continue/config.yaml
#   goose           ~/.config/goose/config.yaml
#   opencode        ~/.config/opencode/opencode.json
#   other           any other file
MCP_CLIENT_IDS="claude-code claude-desktop cursor windsurf codex gemini-cli vscode cline continue goose opencode other"

# Well-known MCP servers, for mcp_known. A server's label, its name in the
# config, is lowercased and cut to the part after the last / (so @scope/name
# gives name). Spaces, dots and underscores become -, and mcp- and server- come
# off the front and -mcp and -server off the end, as often as they appear. When
# nothing is left, as with @playwright/mcp, the part before the / is used. What
# remains must equal an id below or an alias (alias=id). Any other label only
# adds one to mcp_other, and is never sent.
MCP_KNOWN_IDS="github gitlab filesystem git postgres mysql sqlite mongodb redis supabase firebase
  playwright puppeteer browserbase chrome-devtools slack linear notion jira atlassian confluence
  sentry stripe figma context7 memory fetch brave-search exa tavily perplexity sequential-thinking
  time gdrive google-maps aws cloudflare vercel docker kubernetes terraform datadog grafana
  shopify hubspot salesforce zapier n8n everything desktop-commander serena firecrawl taskmaster
  shadcn deepwiki neon prisma netlify heroku azure huggingface"
MCP_ALIASES="gh=github fs=filesystem file-system=filesystem pg=postgres postgresql=postgres
  sqlite3=sqlite mongo=mongodb browserbasehq=browserbase brave=brave-search notionhq=notion
  figma-dev-mode=figma figma-developer=figma perplexity-ask=perplexity
  sequentialthinking=sequential-thinking google-drive=gdrive k8s=kubernetes
  desktopcommander=desktop-commander taskmaster-ai=taskmaster task-master-ai=taskmaster
  task-master=taskmaster shadcn-ui=shadcn hf=huggingface hugging-face=huggingface"

# Places, for key_places. Each file counted in key_files gets the first that fits:
#   shell_rc       ~/.zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile, fish's config.fish
#   shell_history  the shell and REPL history files, the same ones history_keys counts
#   env_file       .env, .env.* and .envrc, anywhere
#   mcp_config     an MCP config from the list of clients above, at home or in a project folder
#   agent_config   other coding-agent settings, like ~/.claude/settings.json or ~/.aider.conf.yml
#   project_file   any other file found in a project folder
#   other          anything else
KEY_PLACE_IDS="shell_rc shell_history env_file mcp_config agent_config project_file other"

in_list() { for _il in $2; do [ "$_il" = "$1" ] && return 0; done; return 1; } # id list
# The well-known ids among MCP server labels ("=label" lines on stdin), in list
# order, then how many labels matched none: "github linear|2". Only ids from
# the list and a number come out, never a label.
mcp_match() {
  KNOWN="$MCP_KNOWN_IDS" ALIASES="$MCP_ALIASES" awk '
    function strip(s,   t) {
      gsub(/[ ._]+/, "-", s)
      do {
        t = s
        sub(/^-+/, "", s); sub(/-+$/, "", s)
        sub(/^mcp-/, "", s); sub(/^server-/, "", s)
        sub(/-mcp$/, "", s); sub(/-server$/, "", s)
      } while (s != t)
      if (s == "mcp" || s == "server") s = ""
      return s
    }
    function part(s) { sub(/^@+/, "", s); sub(/@.*$/, "", s); return strip(s) }
    BEGIN {
      n = split(ENVIRON["KNOWN"], id, " "); for (i = 1; i <= n; i++) ok[id[i]] = 1
      m = split(ENVIRON["ALIASES"], a, " ")
      for (i = 1; i <= m; i++) if (split(a[i], p, "=") == 2 && (p[2] in ok)) al[p[1]] = p[2]
    }
    /^=/ {
      k = split(tolower(substr($0, 2)), seg, "/")
      s = k ? part(seg[k]) : ""
      if (s == "" && k > 1) s = part(seg[k - 1])
      if (s in ok) hit[s] = 1; else if (s in al) hit[al[s]] = 1; else other++
    }
    END {
      out = ""; for (i = 1; i <= n; i++) if (id[i] in hit) out = out (out == "" ? "" : " ") id[i]
      printf "%s|%d", out, other
    }'
}

# The MCP servers in a JSON config, read without running Python: jq if present,
# otherwise macOS's built-in JavaScript (osascript), which only reads the file.
# Prints "#count", then each server's label as "=label" with any control
# character made "?", so one label is one line. Nothing if it can't be read.
json_servers() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '[ (.mcpServers // {} | objects | keys[]),
             (.servers // {} | objects | keys[]),
             (.mcp // {} | objects | if has("servers") then (.servers | objects | keys[]) else keys[] end),
             (.projects // {} | objects | to_entries[] | (.value.mcpServers // {}) | objects | keys[]) ]
           | unique | "#\(length)", (.[] | "=" + (explode | map(if . < 32 or . == 127 then 63 else . end) | implode))' "$1" 2>/dev/null
  elif [ "$OS" = Darwin ]; then
    /usr/bin/osascript -l JavaScript - "$1" 2>/dev/null <<'JXA'
function run(argv) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  if (s.isNil()) return "";
  var j; try { j = JSON.parse(s.js); } catch (e) { return ""; }
  var seen = Object.create(null);
  function add(o) { if (o && typeof o === "object" && !Array.isArray(o)) for (var k in o) seen[k] = 1; }
  add(j.mcpServers); add(j.servers);
  if (j.mcp && typeof j.mcp === "object") { if (j.mcp.servers) add(j.mcp.servers); else add(j.mcp); }
  if (j.projects && typeof j.projects === "object") for (var p in j.projects) if (j.projects[p]) add(j.projects[p].mcpServers);
  var names = Object.keys(seen);
  return ["#" + names.length].concat(names.map(function (k) { return "=" + k.replace(/[\x00-\x1f\x7f]/g, "?"); })).join("\n");
}
JXA
  fi
}

# An npm publish from this folder would ship .claude/ unless something excludes it.
npm_would_ship() {
  [ -f "$1/package.json" ] || return 1
  grep -qE '"private"[[:space:]]*:[[:space:]]*true' "$1/package.json" && return 1
  grep -qE '"files"[[:space:]]*:' "$1/package.json" && return 1
  if [ -f "$1/.npmignore" ]; then grep -qE '(^|/)\.claude' "$1/.npmignore" && return 1; return 0; fi
  if [ -f "$1/.gitignore" ]; then grep -qE '\.claude' "$1/.gitignore" && return 1; fi
  return 0
}

# >>> planted: generated from data/planted.tsv by tools/gen.sh. Edit that file, then run it.
PLANTED='.claude/router_runtime.js
.vscode/router_runtime.js
.claude/setup.mjs
.claude/math_init.js
.vscode/setup.mjs'
PLANTED_ERE='\.claude/router_runtime\.js|\.vscode/router_runtime\.js|\.claude/setup\.mjs|\.claude/math_init\.js|\.vscode/setup\.mjs'
PLANTED_ALONE='.claude/router_runtime.js
.vscode/router_runtime.js
.claude/math_init.js'
WORM_RUN_ALONE='\.(claude|vscode)[/\\]+(router_runtime\.js|math_init\.js)'
WORM_RUN_WEAK='\.(claude|vscode)[/\\]+(setup\.mjs)'
planted_note() { case "$1" in */.claude/router_runtime.js) printf '%s' 'a file the TanStack worm plants' ;; */.vscode/router_runtime.js) printf '%s' 'a file the TanStack worm plants' ;; */.claude/setup.mjs) printf '%s' 'a file the TanStack and keyv worms plant' ;; */.claude/math_init.js) printf '%s' 'a file the keyv worm plants' ;; */.vscode/setup.mjs) printf '%s' 'a file the TanStack and keyv worms plant' ;; esac; }
planted_sha() { case "$1" in */.claude/setup.mjs) printf '%s' 'fd3ca4007b225fdf8de7af4345a19179d5efa8c4bb9205f88cda806e5684b1eb 54dc7ea54a1317cca0e890a2770630cf7fa6c97813e0cb9d2caa93012b350668 2258284d65f63829bd67eaba01ef6f1ada2f593f9bbe41678b2df360bd90d3df' ;; */.vscode/setup.mjs) printf '%s' 'fd3ca4007b225fdf8de7af4345a19179d5efa8c4bb9205f88cda806e5684b1eb 54dc7ea54a1317cca0e890a2770630cf7fa6c97813e0cb9d2caa93012b350668 2258284d65f63829bd67eaba01ef6f1ada2f593f9bbe41678b2df360bd90d3df' ;; esac; }
WORM_REF_NOTE='runs a file a worm plants'
# <<< planted
# Agents set to run commands without asking (data/auto-approve.tsv), read in section 1.
# >>> auto-approve: generated from data/auto-approve.tsv by tools/gen.sh. Edit that file, then run it.
AA_TABLE="Claude Code|all|${CLAUDE_CONFIG_DIR:-$H/.claude}/settings.json|bypassPermissions|\"defaultMode\": \"bypassPermissions\"
Codex|all|${CODEX_HOME:-$H/.codex}/config.toml|never asks, full access|approval_policy = \"never\"|sandbox_mode = \"danger-full-access\"
VS Code Copilot|all|$AS/Code/User/settings.json|chat.tools.global.autoApprove|\"chat.tools.global.autoApprove\": true
VS Code Copilot|all|$AS/Code/User/settings.json|chat.permissions.default: autoApprove|\"chat.permissions.default\": \"autoApprove\"
VS Code Copilot|all|$AS/Code/User/settings.json|chat.permissions.default: autopilot|\"chat.permissions.default\": \"autopilot\""
AA_PROJECT=''
# <<< auto-approve
# One pass over the home folder, depth-limited, skipping heavy and system folders:
# dependency caches, build output, model and VM images, cloud sync folders.
scan_home() {
  # A planted file is found as a file or a link.
  _pf=(); while IFS= read -r _pp; do [ -n "$_pp" ] && _pf+=(-o -path "*/$_pp"); done <<EOF
$PLANTED
EOF
  _aa=(); while IFS= read -r _pp; do [ -n "$_pp" ] && _aa+=(-o -path "*/$_pp"); done <<EOF
$AA_PROJECT
EOF
  # Links are printed as "L path", candidates for the ~/.ssh/authorized_keys check that ak_link
  # settles in the shell with -ef. A find with -ilname (GNU, BSD) keeps only links whose text ends in
  # authorized_keys, in any case, so .ssh/./authorized_keys, .ssh//authorized_keys, a link through a
  # linked folder and, on a volume that ignores case, .SSH/Authorized_Keys all reach -ef. BusyBox's
  # find has no -ilname and rejects the whole expression over it, and its -exec ... + drops links, so
  # there every link is printed, one -exec each.
  # Linked settings, tasks and planted files are printed as "S path" the same way.
  if find /dev/null -maxdepth 0 -ilname x >/dev/null 2>&1; then
    _lk=(-ilname '*authorized_keys' -exec printf 'L %s\n' {} +); _ls=(-exec printf 'S %s\n' {} +)
  else _lk=(-exec printf 'L %s\n' {} \;); _ls=(-exec printf 'S %s\n' {} \;); fi
  set -- -name node_modules -o -name .git -o -name .Trash -o -name .cache -o -name .npm \
    -o -name .pnpm-store -o -name .yarn -o -name .cargo -o -name .rustup -o -name .gradle \
    -o -name .m2 -o -name .pyenv -o -name .rbenv -o -name .nvm -o -name .bun -o -name .deno \
    -o -name __pycache__ -o -name .tox -o -name .next -o -name dist -o -name build \
    -o -name target -o -name vendor -o -name Pods -o -name DerivedData -o -name .terraform \
    -o -name .gem -o -name .cocoapods -o -name .android -o -name .pub-cache -o -name .dartServer \
    -o -name .swiftpm -o -name .ollama -o -name .lmstudio -o -name .colima -o -name .lima \
    -o -name .orbstack -o -name .minikube -o -name .vagrant.d -o -name .docker -o -name .oh-my-zsh \
    -o -name .zsh_sessions -o -name .codeium -o -name .vscode-server \
    -o -path "$H/Library" -o -path "$H/Applications" -o -path "$H/Pictures" -o -path "$H/Movies" \
    -o -path "$H/Music" -o -path "$H/Public" -o -path "$H/go" -o -path "$H/.vscode" -o -path "$H/.cursor" \
    -o -path "$H/.windsurf" -o -path "$H/.devin" -o -path "$H/.local/share" -o -path "$H/Dropbox" -o -path "$H/Google Drive" \
    -o -path "$H/OneDrive*"
  if [ "$WIN" -eq 1 ]; then
    set -- "$@" -o -path "$H/AppData" -o -path "$H/Application Data" -o -path "$H/Local Settings" \
      -o -path "$H/Videos" -o -path "$H/Saved Games" -o -path "$H/3D Objects" -o -path "$H/scoop"
  fi
  if [ "$ALL" -eq 0 ]; then set -- "$@" -o -path "$H/Desktop" -o -path "$H/Documents" -o -path "$H/Downloads"; fi
  # A folder whose name holds a line break would split every path under it in two, so the scan
  # does not enter it. It is printed as "N path", the line break shown as ?, and named as not checked.
  _nl=$'\n'
  # shellcheck disable=SC2016  # $1 is the folder, for the sh that find starts
  find "$H" -maxdepth 6 \( -type d -name "*$_nl*" -prune -exec sh -c 'printf "N %s\n" "$(printf "%s" "$1" | tr "\n" "?")"' sh {} \; \) -o \
    \( -type d \( "$@" \) -prune \) -o \
    \( -type d -name site-packages -print -prune \) -o \
    \( -type f \( -name .env -o -name '.env.*' -o -name .envrc -o -name .mcp.json -o -name pyvenv.cfg \
       -o -path '*/.claude/settings.local.json' -o -path '*/.claude/settings.json' \
       -o -path '*/.cursor/mcp.json' -o -path '*/.vscode/mcp.json' -o -path '*/.vscode/tasks.json' "${_pf[@]}" \
       -o -name package-lock.json -o -name npm-shrinkwrap.json -o -name pnpm-lock.yaml -o -name yarn.lock -o -name bun.lock \
       -o -name .aider.chat.history.md -o -name .aider.input.history -o -path '*/.vscode/settings.json' "${_aa[@]}" \) -print \) -o \
    \( -type l \( -path '*/.claude/settings.local.json' -o -path '*/.claude/settings.json' -o -path '*/.vscode/tasks.json' \
       "${_pf[@]}" \) "${_ls[@]}" \) -o \
    \( -type l "${_lk[@]}" \) 2>>"${SCAN_ERR:-/dev/null}"
}

# Findings for the game or the spinner to show while the scan runs: a mark (x a
# problem, w worth a look, o fine, i working), a bar, then the text. Paths go
# through short() and keys are never part of it.
progress() { [ -n "$PROG_FILE" ] && printf '%s|%s\n' "$1" "$2" > "$PROG_FILE" 2>/dev/null; return 0; }
scan_progress() { # pass the home scan's output through, showing some paths as they turn up
  _n=0
  while IFS= read -r _l; do
    printf '%s\n' "$_l"
    _n=$((_n + 1)); [ $((_n % 4)) -eq 1 ] || continue
    _s=${_l#[LSN] }; _s=${_s//$'\xc2'[$'\x80'-$'\x9f']/?}; _s=${_s//[[:cntrl:]]/?}
    # shellcheck disable=SC2088  # a literal ~ for home paths, as short() prints
    case "$_s" in "$H"/*) _s="~/${_s#"$H"/}" ;; esac
    progress i "Checking $_s"
  done
}

# ---------------------------------------------------------------------------
# Tables the checks below read. tools/gen.sh writes the same tables into gird-fleet.sh.
# ---------------------------------------------------------------------------
case "$OS" in Darwin) _os=mac ;; *) _os=linux ;; esac; [ "$WIN" -eq 1 ] && _os=win
_pd=""; if [ "$WIN" -eq 1 ]; then _pd=$(winpath "${PROGRAMDATA:-}"); _pd=${_pd%/}; fi
# Coding agents: name | commands | install paths | folders that change when it is used | id
# >>> agents: this table's home; tools/gen.sh copies it into gird-fleet.sh.
AGENTS="Claude Code|claude|$H/.claude|$H/.claude/projects|claude-code
Claude Desktop||$APP_CLAUDE;$AS/Claude|$AS/Claude|claude-desktop
Codex|codex|$H/.codex|$H/.codex/sessions|codex
Gemini CLI|gemini|$H/.gemini|$H/.gemini/tmp|gemini-cli
Cursor|cursor|$APP_CURSOR;$H/.cursor|$AS/Cursor/User/workspaceStorage|cursor
Windsurf|windsurf|$APP_WINDSURF;$H/.codeium/windsurf|$AS/Windsurf/User/workspaceStorage|windsurf
Antigravity|antigravity|$APP_ANTIGRAVITY|$AS/Antigravity/User/workspaceStorage|antigravity
GitHub Copilot CLI|copilot|$H/.copilot|$H/.copilot|copilot-cli
OpenCode|opencode|$H/.config/opencode;$H/.local/share/opencode|$H/.local/share/opencode|opencode
Goose|goose|$GOOSE_CFG|$GOOSE_DATA|goose
Aider|aider|||aider
Cline||$AS/Code/User/globalStorage/saoudrizwan.claude-dev;$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev|$AS/Code/User/globalStorage/saoudrizwan.claude-dev/tasks;$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks|cline
Continue||$H/.continue|$H/.continue/sessions|continue"
# <<< agents
# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it.
npm_label() { case "$1" in axios) printf '%s' 'Axios takeover, March 2026' ;; tanstack) printf '%s' 'TanStack worm, May 2026' ;; mistral) printf '%s' 'Mistral AI npm packages, May 2026' ;; uipath) printf '%s' 'UiPath npm packages, May 2026' ;; mistralpy) printf '%s' 'mistralai 2.4.6, May 2026' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1, May 2026' ;; opensearch) printf '%s' 'OpenSearch client, May 2026' ;; bitwarden) printf '%s' 'Bitwarden CLI, April 2026' ;; mastra) printf '%s' 'Mastra npm packages, June 2026' ;; keyv) printf '%s' 'keyv worm, August 2026' ;; keyvscope) printf '%s' 'keyv account takeover, August 2026' ;; sandworm) printf '%s' 'SANDWORM_MODE worm, February 2026' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages, February 2026' ;; tensorlake) printf '%s' 'tensorlake package, October 2026' ;; litellm) printf '%s' 'LiteLLM 1.107.0, October 2026' ;; opencode) printf '%s' 'OpenCode Console, October 2026' ;; railway) printf '%s' 'Railway, October 2026' ;; zeabur) printf '%s' 'Zeabur, October 2026' ;; glassworm) printf '%s' 'GlassWorm extensions, January 2026' ;; glasswormmar) printf '%s' 'GlassWorm extensions, March 2026' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions, March 2026' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions, April 2026' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes, October 2026' ;; injective) printf '%s' 'Injective SDK, July 2026' ;; esac; }
incident_line() { case "$1" in axios) printf '%s' 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it. cisa.gov' ;; tanstack) printf '%s' 'TanStack worm, May 2026: stole cloud, GitHub, npm and SSH credentials on install, then republished itself. github.com' ;; mistral) printf '%s' 'Mistral AI npm packages, May 2026: published with malware Mistral says could not run, as its setup script names a missing file. docs.mistral.ai' ;; uipath) printf '%s' 'UiPath npm packages, May 2026: published with malware that a bug in its payload kept from working, Wiz says. wiz.io' ;; mistralpy) printf '%s' 'mistralai 2.4.6, May 2026: started a credential stealer in the background when imported on Linux. docs.mistral.ai' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1, May 2026: downloaded and ran a credential stealer, on Linux only. wiz.io' ;; opensearch) printf '%s' 'OpenSearch client, May 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' ;; bitwarden) printf '%s' 'Bitwarden CLI, April 2026: stole SSH keys, npm, GitHub and cloud credentials, and AI tool configs. stepsecurity.io' ;; mastra) printf '%s' 'Mastra npm packages, June 2026: pulled in malware that started at login and sent browser history to the attackers. socket.dev' ;; keyv) printf '%s' 'keyv worm, August 2026: stole cloud, GitHub and npm credentials, and planted hooks that run when repos open. socket.dev' ;; keyvscope) printf '%s' 'keyv account takeover, August 2026: published from the compromised keyv account, and the GitHub advisory says to treat a machine that installed one as compromised. github.com' ;; sandworm) printf '%s' 'SANDWORM_MODE worm, February 2026: stole credentials and AI provider keys, and added an MCP server to AI assistants. socket.dev' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages, February 2026: published by the SANDWORM_MODE attackers with no malware in them yet, Socket says. socket.dev' ;; tensorlake) printf '%s' 'tensorlake package, October 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' ;; litellm) printf '%s' 'LiteLLM 1.107.0, October 2026: stole credentials and loaded remote-code execution tools on machines that installed it. docs.litellm.ai' ;; opencode) printf '%s' 'OpenCode Console, October 2026: exposed AI provider keys saved in Console workspaces; users reported charges on them. techcrunch.com' ;; railway) printf '%s' 'Railway, October 2026: an attacker may have accessed encrypted environment variables and obtained the decrypted contents of some. blog.railway.com' ;; zeabur) printf '%s' 'Zeabur, October 2026: an attacker read environment variables and secrets stored on the platform. zeabur.com' ;; glassworm) printf '%s' 'GlassWorm extensions, January 2026: stole SSH keys, cloud and npm credentials, keychains and crypto wallets from Macs. socket.dev' ;; glasswormmar) printf '%s' 'GlassWorm extensions, March 2026: ran attacker code in memory that could reach local credentials, tokens and secrets. socket.dev' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions, March 2026: installed a malicious extension from GitHub into every editor it found. socket.dev' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions, April 2026: updated cloned extensions to install malware from GitHub into VS Code, Cursor and Windsurf. socket.dev' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes, October 2026: VS Code themes that ran hidden loaders, one of them tied to GlassWorm. socket.dev' ;; injective) printf '%s' 'Injective SDK, July 2026: sent the seed phrase or private key of any wallet an app created or imported with it. github.com' ;; esac; }
incident_level() { case "$1" in mistral) printf update ;; uipath) printf update ;; sandsleep) printf update ;; opencode) printf leak ;; railway) printf leak ;; zeabur) printf leak ;; injective) printf update ;; *) printf act ;; esac; }
incident_name() { case "$1" in axios) printf '%s' 'Axios takeover' ;; tanstack) printf '%s' 'TanStack worm' ;; mistral) printf '%s' 'Mistral AI npm packages' ;; uipath) printf '%s' 'UiPath npm packages' ;; mistralpy) printf '%s' 'mistralai 2.4.6' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1' ;; opensearch) printf '%s' 'OpenSearch client' ;; bitwarden) printf '%s' 'Bitwarden CLI' ;; mastra) printf '%s' 'Mastra npm packages' ;; keyv) printf '%s' 'keyv worm' ;; keyvscope) printf '%s' 'keyv account takeover' ;; sandworm) printf '%s' 'SANDWORM_MODE worm' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages' ;; tensorlake) printf '%s' 'tensorlake package' ;; litellm) printf '%s' 'LiteLLM 1.107.0' ;; opencode) printf '%s' 'OpenCode Console' ;; railway) printf '%s' 'Railway' ;; zeabur) printf '%s' 'Zeabur' ;; glassworm) printf '%s' 'GlassWorm extensions' ;; glasswormmar) printf '%s' 'GlassWorm extensions' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes' ;; injective) printf '%s' 'Injective SDK' ;; esac; }
incident_source() { case "$1" in axios) printf '%s' 'www.cisa.gov/news-events/alerts/2026/04/20/supply-chain-compromise-impacts-axios-node-package-manager' ;; tanstack) printf '%s' 'github.com/advisories/GHSA-g7cv-rxg3-hmpx' ;; mistral) printf '%s' 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' ;; uipath) printf '%s' 'www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised' ;; mistralpy) printf '%s' 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' ;; guardrails) printf '%s' 'www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised' ;; opensearch) printf '%s' 'github.com/advisories/GHSA-298w-vvm4-ww55' ;; bitwarden) printf '%s' 'www.stepsecurity.io/blog/bitwarden-cli-hijacked-on-npm-bun-staged-credential-stealer-targets-developers-github-actions-and-ai-tools' ;; mastra) printf '%s' 'socket.dev/blog/mastra-npm-packages-compromised' ;; keyv) printf '%s' 'socket.dev/blog/popular-npm-packages-in-the-keyv-and-cacheable-namespaces-compromised-in-active-supply-chain' ;; keyvscope) printf '%s' 'github.com/advisories/GHSA-q99r-cjmf-3xrf' ;; sandworm) printf '%s' 'socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning' ;; sandsleep) printf '%s' 'socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning' ;; tensorlake) printf '%s' 'github.com/advisories/GHSA-rqxj-g25x-4v9v' ;; litellm) printf '%s' 'docs.litellm.ai/blog/security-incident-oct-21-2026' ;; opencode) printf '%s' 'techcrunch.com/2026/10/19/hackers-hit-ai-coding-tool-opencode-running-up-charges-on-users-ai-accounts/' ;; railway) printf '%s' 'blog.railway.com/p/security-disclosure-wednesday-october-21st' ;; zeabur) printf '%s' 'zeabur.com/blogs/october-2026-security-incident' ;; glassworm) printf '%s' 'socket.dev/blog/glassworm-loader-hits-open-vsx-via-suspected-developer-account-compromise' ;; glasswormmar) printf '%s' 'socket.dev/blog/open-vsx-transitive-glassworm-campaign' ;; glasswormvsix) printf '%s' 'socket.dev/blog/glassworm-sleeper-extensions-activated-on-open-vsx' ;; glasswormapr) printf '%s' 'socket.dev/blog/73-open-vsx-sleeper-extensions-glassworm' ;; glasswormoct) printf '%s' 'socket.dev/blog/glassworm-vscode-themes' ;; injective) printf '%s' 'github.com/advisories/GHSA-5fc4-fm2x-6f4r' ;; esac; }
incident_advice() { case "$1" in keyvscope) printf '%s' 'Rotate the secrets this machine held from another computer, as the GitHub advisory says, then pin each @keyv package listed in section 5 to its version before 6.0.0.' ;; sandsleep) printf '%s' 'Uninstall the SANDWORM_MODE sleeper packages listed in section 5: the attackers published every version of them.' ;; glassworm) printf '%s' 'On a Mac, also check ~/Library/LaunchAgents for unfamiliar plists such as com.user.nodestart.plist, and look for /tmp/ijewf and /tmp/out.zip, where the malware collects what it steals.' ;; glasswormvsix) printf '%s' 'Also check every editor you use, VS Code included, for extensions you did not install yourself: this malware installs one from GitHub into each editor it finds.' ;; glasswormapr) printf '%s' 'Also check every editor you use, VS Code included, for extensions you did not install yourself: this malware installs one from GitHub into each editor it finds.' ;; injective) printf '%s' 'Move the funds out of any wallet created or imported with Injective SDK 1.20.21, into a new wallet.' ;; esac; }
incident_summary() { case "$1" in injective) printf '%s' 'Injective SDK: move the funds out of its wallets' ;; esac; }
# <<< incidents
# >>> indicators: generated from data/indicators.tsv by tools/gen.sh. Edit that file, then run it.
IND_TABLE="tanstack|all|wiper|no|$H/Library/LaunchAgents/com.user.gh-token-monitor.plist|-
tanstack|all|wiper|no|$H/.config/systemd/user/gh-token-monitor.service|-
tanstack|all|wiper|no|$H/.local/bin/gh-token-monitor.sh|-
tanstack|all|wiper|no|$H/.config/gh-token-monitor|-
tanstack|all|wiper|yes|/tmp/gh-token-monitor.out.log|-
tanstack|all|wiper|yes|/tmp/gh-token-monitor.err.log|-
mastra|all|startup|no|$H/Library/LaunchAgents/com.nvm.protocal.plist|starts the Mastra malware at login
glassworm|all|startup|no|$H/Library/LaunchAgents/com.user.nodestart.plist|starts the GlassWorm malware at login
mastra|all|startup|no|$H/Library/NodePackages/protocal.cjs|starts the Mastra malware at login
mastra|all|startup|no|$H/.config/systemd/user/nvmconf.service|starts the Mastra malware at login
mastra|all|startup|no|$H/.config/systemd/nvmconf/protocal.cjs|starts the Mastra malware at login
mastra|win|startup|no|${_pd:+$_pd/NodePackages/protocal.cjs}|starts the Mastra malware at login
litellm|all|site|no|cook.pth|-
litellm|all|site|no|cook.py|-
litellm|all|temp|yes|remote_code_loader.lock|These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
litellm|all|temp|yes|.pc_once_*|These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
litellm|all|temp|yes|.pc_sq_*|These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
litellm|all|temp|yes|.pc_e_*|These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
mistralpy|linux|temp|yes|transformers.pyz|Kill any python process started from transformers.pyz, then delete the file."
# <<< indicators
# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it.
OUT_TABLE="cursor|Cursor|mac|plist|/Applications/Cursor.app/Contents/Info.plist|-|3.0|a malicious agent could escape the sandbox|github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw
cursor|Cursor|mac|plist|$H/Applications/Cursor.app/Contents/Info.plist|-|3.0|a malicious agent could escape the sandbox|github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw
amazonq|Amazon Q language server|mac|folder|$H/Library/Caches/aws/toolkits/language-servers/AmazonQ|-|1.69.0|a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands|aws.amazon.com/security/security-bulletins/2026-047-aws/
amazonq|Amazon Q language server|linux|folder|$H/.cache/aws/toolkits/language-servers/AmazonQ|-|1.69.0|a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands|aws.amazon.com/security/security-bulletins/2026-047-aws/
amazonq|Amazon Q language server|win|folder|$WLAPP/aws/toolkits/language-servers/AmazonQ|-|1.69.0|a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands|aws.amazon.com/security/security-bulletins/2026-047-aws/
claudecode|Claude Code|all|npm|@anthropic-ai/claude-code|0.2.116|1.0.24|a web page could reach the editor connection|github.com/advisories/GHSA-9f65-56v6-gxw7
mcpremote|mcp-remote|all|npm|mcp-remote|0.0.5|0.1.16|a hostile MCP server could run commands|github.com/advisories/GHSA-6xpm-ggf7-wc3p
mcpremote|mcp-remote|all|mcparg|mcp-remote|0.0.5|0.1.16|a hostile MCP server could run commands|github.com/advisories/GHSA-6xpm-ggf7-wc3p"
# <<< outdated
# Hosted platforms that leaked stored secrets (data/platforms.tsv): found by a command on PATH or a
# file or folder (a folder ends in /). PLAT_FOUND lists the ids found, PLAT_LIST every name.
# >>> platforms: generated from data/platforms.tsv by tools/gen.sh. Edit that file, then run it.
PLATFORMS="opencode|OpenCode|opencode|$H/.config/opencode/;$H/.local/share/opencode/|installed|If you used OpenCode Console, rotate every provider key you saved there. Keys kept only in the CLI were not affected.|OpenCode found: used its Console? Rotate keys
railway|Railway|railway|$H/.railway/config.json|CLI found|Railway asked all users to rotate every environment variable stored there, including API keys and private registry credentials, and to review their logs for unusual activity.|Railway CLI found: rotate secrets stored there
zeabur|Zeabur|zeabur|$H/.config/zeabur/|CLI found|Zeabur said on 19 October that an attacker read service environment variables stored on the platform, and asked every customer to replace all of them. Revoke each key at its provider first.|Zeabur CLI found: rotate secrets stored there"
# <<< platforms

# ===========================================================================
# Public totals for the line under the banner, fetched while the banner prints.
# Only the request itself goes out, and nothing at all with --offline.
TMPD=${TMPDIR:-/tmp}; TMPD=${TMPD%/}
if [ "$OFFLINE" -eq 0 ] && command -v curl >/dev/null 2>&1; then
  SP_FILE=$(mktemp "$TMPD/blindspot.XXXXXX" 2>/dev/null) || SP_FILE=""
  if [ -n "$SP_FILE" ]; then
    if [ "${API#https://}" != "$API" ]; then _sp='=https'; else _sp='=http,https'; fi
    curl -fsS --proto "$_sp" --max-time 2 --max-filesize 65536 "$API/stats" > "$SP_FILE" 2>/dev/null &
    SP_PID=$!
  fi
fi
banner
proof_line
blank
PROG_FILE=$(mktemp "$TMPD/blindspot.XXXXXX" 2>/dev/null) || PROG_FILE=""
SCAN_ERR=$(mktemp "$TMPD/blindspot.XXXXXX" 2>/dev/null) || SCAN_ERR=""   # the home scan's find errors
# An account run counts each folder the scan could not read as not checked, so it needs the file.
if [ "$ACCTRUN" -eq 1 ] && [ -z "$SCAN_ERR" ]; then exit 13; fi
if game_ok; then
  SAVED_TTY=$(stty -g </dev/tty 2>/dev/null)
  [ "$G_MODE" = C ] && stty -echo -icanon min 0 time 5 </dev/tty 2>/dev/null
  game_loop </dev/tty &
  GAME_PID=$!
  if [ "$G_MODE" = C ]; then g_keys "$GAME_PID" </dev/tty & KEYS_PID=$!; fi
else
  spin_start "Checking your agents, configs and keys"
fi
SCAN_T0=$SECONDS

# --- Keys in agent sessions, checked in the background --------------------------
# docs/designs/transcripts.md. SESS_TABLE rows are os|kind|agent|path, from data/sessions.tsv.
# Kept apart from AGENTS, whose ids go into the report.
# >>> sessions: generated from data/sessions.tsv by tools/gen.sh. Edit that file, then run it.
SESS_TABLE="all|read|Claude Code|${CLAUDE_CONFIG_DIR:-$H/.claude}/projects
all|read|Claude Code|${CLAUDE_CONFIG_DIR:-$H/.claude}/history.jsonl
all|read|Claude Code|${CLAUDE_CONFIG_DIR:-$H/.claude}/paste-cache
all|read|Claude Desktop|$AS/Claude/local-agent-mode-sessions
linux|read|Claude Desktop|${XDG_CONFIG_HOME:-$H/.config}/Claude/local-agent-mode-sessions
win|read|Claude Desktop|$WLAPP/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/local-agent-mode-sessions
all|read|Claude Desktop|$AS/Claude-3p/local-agent-mode-sessions
linux|read|Claude Desktop|${XDG_CONFIG_HOME:-$H/.config}/Claude-3p/local-agent-mode-sessions
win|read|Claude Desktop|$WLAPP/Claude-3p/local-agent-mode-sessions
all|read|Codex|${CODEX_HOME:-$H/.codex}/sessions
all|read|Codex|${CODEX_HOME:-$H/.codex}/archived_sessions
all|read|Codex|${CODEX_HOME:-$H/.codex}/history.jsonl
all|read|Codex|${CODEX_HOME:-$H/.codex}/thread_history_1.sqlite
all|read|Codex|${CODEX_HOME:-$H/.codex}/thread_history_1.sqlite-wal
all|read|Codex|${CODEX_SQLITE_HOME:-$H/.codex}/thread_history_1.sqlite
all|read|Codex|${CODEX_SQLITE_HOME:-$H/.codex}/thread_history_1.sqlite-wal
all|read|Gemini CLI|${GEMINI_CLI_HOME:-$H}/.gemini/tmp
mac|read|Gemini CLI|$H/.cache/.gemini/tmp
all|read|Qwen Code|${QWEN_HOME:-$H/.qwen}/projects
all|read|Qwen Code|${QWEN_HOME:-$H/.qwen}/tmp
all|read|OpenCode|${XDG_DATA_HOME:-$H/.local/share}/opencode/opencode.db
all|read|OpenCode|${XDG_DATA_HOME:-$H/.local/share}/opencode/opencode.db-wal
all|read|OpenCode|${XDG_DATA_HOME:-$H/.local/share}/opencode/storage
all|read|GitHub Copilot CLI|${COPILOT_HOME:-$H/.copilot}/session-state
all|read|GitHub Copilot CLI|${COPILOT_HOME:-$H/.copilot}/history-session-state
all|read|GitHub Copilot CLI|${COPILOT_HOME:-$H/.copilot}/command-history-state
all|read|GitHub Copilot CLI|${COPILOT_HOME:-$H/.copilot}/session-store.db
all|read|GitHub Copilot CLI|${COPILOT_HOME:-$H/.copilot}/session-store.db-wal
all|read|GitHub Copilot CLI|${COPILOT_HOME:-$H/.copilot}/command-history-state.json
all|read|Roo Code|$AS/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks
linux|read|Roo Code|${XDG_CONFIG_HOME:-$H/.config}/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks
all|read|Roo Code|$AS/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks
linux|read|Roo Code|${XDG_CONFIG_HOME:-$H/.config}/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks
all|read|Cline|$AS/Code/User/globalStorage/saoudrizwan.claude-dev/tasks
linux|read|Cline|${XDG_CONFIG_HOME:-$H/.config}/Code/User/globalStorage/saoudrizwan.claude-dev/tasks
all|read|Cline|$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks
linux|read|Cline|${XDG_CONFIG_HOME:-$H/.config}/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks
all|read|Cline|${CLINE_DATA_DIR:-$H/.cline/data}/sessions
all|read|Cline|${CLINE_DATA_DIR:-$H/.cline/data}/tasks
all|read|Cline|${CLINE_DIR:-$H/.cline}/data/sessions
all|read|Cline|${CLINE_DIR:-$H/.cline}/data/tasks
all|read|Cline|${CLINE_SESSION_DATA_DIR:-$H/.cline/data/sessions}
all|read|Continue|${CONTINUE_GLOBAL_DIR:-$H/.continue}/sessions
all|read|Continue|${CONTINUE_GLOBAL_DIR:-$H/.continue}/dev_data/0.2.0/chatInteraction.jsonl
all|read|Goose|$GOOSE_DATA/sessions
all|read|Goose|$GOOSE_STATE/logs
all|read|Goose|$GOOSE_STATE/history.txt
all|read|Kiro CLI|${KIRO_HOME:-$H/.kiro}/sessions
mac|read|Kiro CLI|$AS/kiro-cli
linux|read|Kiro CLI|${XDG_DATA_HOME:-$H/.local/share}/kiro-cli
win|read|Kiro CLI|$WLAPP/kiro-cli
mac|read|Amazon Q|$AS/amazon-q
linux|read|Amazon Q|${XDG_DATA_HOME:-$H/.local/share}/amazon-q
win|read|Amazon Q|$WLAPP/amazon-q
all|read|Amazon Q|$H/.aws/amazonq/.cli_bash_history
all|read|Factory Droid|$H/.factory/sessions
all|read|Factory Droid|$H/.factory/projects
all|read|Factory Droid|$H/.factory/state/history.json
all|read|Cursor|$AS/Cursor/User/globalStorage/state.vscdb
linux|read|Cursor|${XDG_CONFIG_HOME:-$H/.config}/Cursor/User/globalStorage/state.vscdb
all|read|Cursor|$H/.cursor/projects
all|read|Cursor|$H/.cursor/chats
all|read|Windsurf|$H/.windsurf/transcripts
all|read|Antigravity|$H/.gemini/antigravity/brain
all|read|Antigravity|$H/.gemini/antigravity-cli/brain
all|read|Antigravity|$H/.gemini/antigravity-ide/brain
all|db|Antigravity|$H/.gemini/antigravity/conversations
all|db|Antigravity|$H/.gemini/antigravity-cli/conversations
all|db|Antigravity|$H/.gemini/antigravity-ide/conversations
all|sealed|Windsurf|$H/.codeium/windsurf/cascade
all|sealed|Antigravity|$H/.gemini/antigravity/conversations
all|sealed|Antigravity|$H/.gemini/antigravity-cli/conversations
all|sealed|Antigravity|$H/.gemini/antigravity-ide/conversations"
# <<< sessions
SESS_SOURCES=$(printf '%s\n' "$SESS_TABLE" | awk -F '|' -v o="$_os" '($1 == "all" || $1 == o) && ($2 == "read" || $2 == "db") { print $3 "|" $4 }')
# Folders whose .pb conversation files are stored encrypted: those files are counted and named as
# not checked.
SESS_SEALED=$(printf '%s\n' "$SESS_TABLE" | awk -F '|' -v o="$_os" '($1 == "all" || $1 == o) && $2 == "sealed" { print $3 "|" $4 }')
# Files and folders only: ripgrep reads a pipe or a device given as a root, and waits on it forever.
# A db folder gives its SQLite files, *.db and their *.db-wal, and nothing else in it; one that
# can't be listed is given as it is, so the engine names it as a folder not read. Such a file
# whose name holds a newline can't be a root line and is left out: only the agent writes there.
# Two lines can name one place (Codex's CODEX_HOME and CODEX_SQLITE_HOME when neither is set): it
# is listed once.
SESS_ROOTS=$(printf '%s\n' "$SESS_TABLE" | awk -F '|' -v o="$_os" '($1 == "all" || $1 == o) && ($2 == "read" || $2 == "db") { print $2 "|" $4 }' | while IFS='|' read -r _k _p; do
  if [ "$_k" = db ]; then
    if [ -d "$_p" ] && { [ ! -r "$_p" ] || [ ! -x "$_p" ]; }; then printf '%s\n' "$_p"; continue; fi
    for _f in "$_p"/*.db "$_p"/*.db-wal; do
      case "$_f" in (*"$NL"*) continue ;; esac
      [ -f "$_f" ] && printf '%s\n' "$_f"
    done
  else { [ -f "$_p" ] || [ -d "$_p" ]; } && printf '%s\n' "$_p"; fi
done | awk '!seen[$0]++')
# Lines without a key's start are skipped cheaply.
SESS_PRE=$KEY_STARTS
# A location given as a file is read as it is, following a link as ripgrep follows one, but only to
# a regular file: -f is false for a pipe or a device, whose read would block or never end. Links
# found inside a folder are not followed, as ripgrep does not follow them.
# One perl parent lists the files newest first and forks workers, each with its own pipe back to
# the parent, which is the only writer to its output, so lines never interleave. A worker prints K
# (a match) and then D (done) for a file, Z for a compressed one or U for one it can't open; the
# parent prints T (the total) first, and S (the folders it could not open, whose files are not in
# the total) when there are any. Before printing, control characters become ? in a file name and a
# space in a match, so neither a hostile folder name nor a newline or tab that happens to be the
# boundary byte of a match can split a line or shift its fields. Files are read 1 MB at a time and
# cut just after the last character that can't be in a key or start an escape such as \n (a
# backslash never ends a piece), so a huge database file never loads at once and a piece never ends
# inside a token, unless a token runs past 8 MB. On TERM, HUP or INT the parent stops its workers;
# a worker exits when its parent or the script that started everything is gone, so a kill -9 of the
# script stops them at the next piece.
SESS_PERL='
use strict; use warnings; use File::Find; use IO::Select;
my $re = qr/$ENV{SESS_KEYS}/; my $pre = qr/$ENV{SESS_PRE}/; my $owner = getppid(); my $parent = $$; my @kids;
$SIG{TERM} = $SIG{HUP} = $SIG{INT} = $SIG{PIPE} = sub { kill "TERM", @kids; exit 0 };
my @f = grep { !-d $_ && -f $_ } @ARGV; my $unread = 0;
{
  local $SIG{__WARN__} = sub { $unread++ if $_[0] =~ /^Can.t opendir/ };
  my @d = map { "$_/" } grep { -d $_ } @ARGV;
  find({ no_chdir => 1, wanted => sub { exit 0 if getppid() != $owner; push @f, $_ if -f $_ && !-l $_ } }, @d) if @d;
}
my %m; $m{$_} = (stat $_)[9] || 0 for @f;
@f = sort { $m{$b} <=> $m{$a} or $a cmp $b } @f;
$| = 1; print "T\t" . scalar(@f) . "\n"; print "S\t$unread\n" if $unread;
my $cut = $ENV{GIRD_CHECK_SESSIONS_STOP_AFTER};
@f = @f[0 .. $cut - 1] if defined $cut && $cut =~ /^[0-9]+$/ && $cut < @f;
my $n = $ENV{SESS_WORKERS} || 4; my $sel = IO::Select->new;
for my $w (0 .. $n - 1) {
  pipe(my $r, my $wr) or last;
  my $pid = fork; unless (defined $pid) { close $r; close $wr; last }
  if ($pid == 0) {
    $SIG{TERM} = $SIG{HUP} = $SIG{INT} = $SIG{PIPE} = "DEFAULT"; close $r; select $wr; $| = 1;
    if (my $hold = $ENV{GIRD_CHECK_SESSIONS_HOLD}) { my $x; open($x, "<", $hold) and <$x> }  # tests only
    my $alive = sub { getppid() == $parent && kill(0, $owner) };
    FILE: for (my $i = $w; $i < @f; $i += $n) {
      exit 0 unless $alive->();
      my $file = $f[$i]; (my $fn = $file) =~ tr/\x00-\x1f\x7f/?/;
      if ($file =~ /\.zst$/) { print "Z\t$fn\n"; next }
      my $h; unless (open($h, "<", $file)) { print "U\t$fn\n"; next }
      binmode $h; local $/ = \1048576; my $buf = "";
      my $scan = sub { my $t = shift; if ($t =~ $pre) { while ($t =~ /$re/g) { (my $k = $&) =~ tr/\x00-\x1f\x7f/ /; print "K\t$fn\t$k\n" } } };
      while (defined(my $c = <$h>)) {
        exit 0 unless $alive->();
        select(undef, undef, undef, 0.3) if $ENV{GIRD_CHECK_SESSIONS_SLOW};  # tests only
        $buf .= $c;
        my $cut = $buf =~ /[^A-Za-z0-9_.\\-][A-Za-z0-9_.\\-]*\z/ ? $-[0] + 1 : -1;
        next if $cut < 0 && length($buf) < 8388608;
        $scan->(substr($buf, 0, $cut < 0 ? length($buf) : $cut, ""));
      }
      $scan->($buf) if length $buf;
      close $h; print "D\t$fn\n";
    }
    exit 0;
  }
  close $wr; $sel->add($r); push @kids, $pid;
}
my %buf;
while ($sel->count) {
  for my $fh ($sel->can_read) {
    my $got = sysread($fh, my $chunk, 65536);
    if ($got) { $buf{$fh} .= $chunk; while ($buf{$fh} =~ s/^([^\n]*\n)//) { print $1 } }
    else { $sel->remove($fh); close $fh }
  }
}
1 while wait() != -1;'
# Turns matches into "H<tab>file<tab>provider", once per file and provider, and drops keys that
# look made up. T, D, Z, U and S lines pass through. Keys reach it through a pipe and stop here.
# With rg, the input is ripgrep's own: the file, the NUL that --null puts after it (the one byte
# a path can't hold) turned into a tab by tr, which turns every real tab into ?, then the match.
# So a line without a tab is a piece of a file name that holds a newline, and the match may hold
# any byte but a newline. No key is longer than 300 characters (GitHub's 93-character tokens are
# the longest fixed format, OpenAI project keys run to about 170): a longer run of key characters
# is data, not a key, and would make madeup() slow. Always called in a subshell (a pipe or a
# background job): exec makes awk that job's own process, the one sess_stop signals.
sess_filter() { # [rg]
  exec awk -F '\t' -v rg="${1:-}" "$PROV_AWK"'
    function madeup(k,   i, c, run, last, n, seen, len) {
      if (k ~ /EXAMPLE|xxxx|XXXX|0123456789|1234567890|abcdef|ABCDEF/) return 1
      run = 0; last = ""; n = 0; len = length(k)
      for (i = 1; i <= len; i++) {
        c = substr(k, i, 1)
        if (c == last) { if (++run >= 8) return 1 } else { run = 1; last = c }
        if (!(c in seen)) { seen[c] = 1; n++ }
      }
      return n < (len < 30 ? 8 : 12)
    }
    # Amazon Q CLI keeps temporary AWS credentials for its own telemetry in its database
    # (data.sqlite3, state entry telemetry-cognito-credentials, an ASIA key id), and so does Kiro
    # CLI, the same CLI renamed: such a key id there belongs to the CLI, it is not a key an agent
    # read. Long-term AKIA keys and every other provider in those files still count.
    function cli_own(f, k,   t) {
      if (k !~ /^ASIA/) return 0
      t = f; gsub(/\\/, "/", t)
      return t ~ /\/(amazon-q|kiro-cli)\/data\.sqlite3(-journal|-wal)?$/
    }
    rg == "" && ($1 == "T" || $1 == "D" || $1 == "Z" || $1 == "U" || $1 == "S") { print; fflush(); next }
    {
      if (rg != "") {
        i = index($0, "\t")
        if (i == 0) { part = part $0 "?"; next }
        f = part substr($0, 1, i - 1); k = substr($0, i + 1); part = ""
      } else if ($1 == "K") { f = $2; k = $3 } else next
      if (length(k) > 300) next
      p = prov(k); if (p == "") next
      sub(/^[^A-Za-z]*\\[ntr"]/, "", k); sub(/^[^A-Za-z]+/, "", k); sub(/[^A-Za-z0-9_.-]+$/, "", k)
      if (madeup(k) || cli_own(f, k) || ((f "|" p) in done)) next
      done[f "|" p] = 1; print "H\t" f "\t" p; fflush()
    }'
}
SESS_ENGINE=none; SESS_RC=""
RG_BIN=$(type -P rg 2>/dev/null); [ "$ACCTRUN" -eq 1 ] && RG_BIN=""   # an account run uses the system perl
if [ -n "$GIRD_CHECK_SESSIONS_ENGINE" ]; then SESS_ENGINE=$GIRD_CHECK_SESSIONS_ENGINE
elif [ -n "$RG_BIN" ] && [ "$("$RG_BIN" --version 2>/dev/null | sed -n '1s/^ripgrep \([0-9]*\).*/\1/p')" -ge 13 ] 2>/dev/null; then SESS_ENGINE=rg
elif type -P perl >/dev/null 2>&1; then SESS_ENGINE=perl; fi
[ "$SESS_ENGINE" = rg ] && [ -z "$RG_BIN" ] && SESS_ENGINE=none
[ "$SESS_ENGINE" = perl ] && ! type -P perl >/dev/null 2>&1 && SESS_ENGINE=none
# SESS_FAIL is set when the check could not start, so the report can say the sessions were not checked.
SESS_FAIL=0
sess_start() {
  [ -n "$SESS_ROOTS" ] && [ "$SESS_ENGINE" != none ] || return 0
  # Keys pass through a pipe inside a folder that only the owner can open, whatever the umask
  # (/tmp is shared on Linux), under a name nobody can guess in advance.
  SESS_DIR=$(mktemp -d "$TMPD/blindspot.XXXXXX" 2>/dev/null) || { SESS_DIR=""; SESS_FAIL=1; return 0; }
  SESS_FILE="$SESS_DIR/hits"; SESS_FIFO="$SESS_DIR/pipe"
  mkfifo -m 600 "$SESS_FIFO" 2>/dev/null || { rm -rf "$SESS_DIR"; SESS_DIR=""; SESS_FILE=""; SESS_FIFO=""; SESS_FAIL=1; return 0; }
  _roots=(); while IFS= read -r _r; do [ -n "$_r" ] && _roots+=("$_r"); done <<EOF
$SESS_ROOTS
EOF
  if [ "$SESS_ENGINE" = rg ]; then
    [ -n "$GIRD_CHECK_SESSIONS_HOLD" ] && _roots+=("$GIRD_CHECK_SESSIONS_HOLD")  # tests only: a pipe nobody writes to holds ripgrep
    # --null ends each file name with a NUL, the one byte a path can't hold: tr turns it into the
    # tab the filter splits on, and every real tab into ?, so a file name can't shift the fields.
    tr '\000\t' '\t?' < "$SESS_FIFO" | sess_filter rg > "$SESS_FILE" &
    SESS_FILTER_PID=$!
    "$RG_BIN" -a --hidden --no-ignore --no-config --no-messages -o --no-line-number --with-filename --null \
      -e "$TR_KEYS" -- "${_roots[@]}" > "$SESS_FIFO" 2>/dev/null &
    SESS_PID=$!
    [ "$WIN" -eq 1 ] && SESS_WIN=1
  else
    sess_filter < "$SESS_FIFO" > "$SESS_FILE" &
    SESS_FILTER_PID=$!
    _nw=$( (sysctl -n hw.ncpu || nproc || getconf _NPROCESSORS_ONLN) 2>/dev/null | head -n 1)
    case "$_nw" in ''|*[!0-9]*) _nw=4 ;; esac
    [ "$_nw" -gt 8 ] && _nw=8; [ "$_nw" -lt 1 ] && _nw=1
    SESS_KEYS=$TR_KEYS SESS_PRE=$SESS_PRE SESS_WORKERS=$_nw perl -e "$SESS_PERL" -- "${_roots[@]}" > "$SESS_FIFO" 2>/dev/null &
    SESS_PID=$!
  fi
}
# Stops the check, or waits for it with --all-sessions, and records how ripgrep ended. Then the
# filter: with the engine gone it reads what is left in the pipe and exits on its own, and gets
# five seconds to; with kill (a signal: nothing left to keep) it is stopped at once.
sess_stop() { # [wait|kill]
  if [ -n "$SESS_PID" ]; then
    if [ "${1:-}" = wait ]; then wait "$SESS_PID" 2>/dev/null; SESS_RC=$?
    elif kill -0 "$SESS_PID" 2>/dev/null; then
      if [ "$SESS_WIN" -eq 1 ] && [ -r "/proc/$SESS_PID/winpid" ]; then
        taskkill //F //PID "$(cat "/proc/$SESS_PID/winpid")" >/dev/null 2>&1
      fi
      kill -TERM "$SESS_PID" 2>/dev/null; wait "$SESS_PID" 2>/dev/null; SESS_RC=stopped
    else wait "$SESS_PID" 2>/dev/null; SESS_RC=$?; fi
    SESS_PID=""
  fi
  [ -n "$SESS_FILTER_PID" ] || return 0
  if [ "${1:-}" != kill ]; then
    _i=0; while [ "$_i" -lt 50 ] && kill -0 "$SESS_FILTER_PID" 2>/dev/null; do sleep 0.1; _i=$((_i + 1)); done
  fi
  kill -TERM "$SESS_FILTER_PID" 2>/dev/null; wait "$SESS_FILTER_PID" 2>/dev/null; SESS_FILTER_PID=""
}
sess_start

progress i "Looking through your home folder"
FOUND=$(scan_home | scan_progress | fleet_filter)
# A find that rejects the expression prints nothing, which would read as a clean home folder. The
# header says the folder was not scanned instead, and the headline does not call the scan clean.
SCAN_FAILED=0; SCAN_WHY=""
if [ -z "$FOUND" ] && [ -n "$SCAN_ERR" ] && grep -qiE '^find: .*(unrecognized|unknown|invalid|illegal|not a valid|bad option|usage)' "$SCAN_ERR" 2>/dev/null; then
  SCAN_FAILED=1; SCAN_WHY=$(grep -m 1 '^find: ' "$SCAN_ERR" | tr -d '\r' | cut -c 1-120)
fi
# Folders the scan could not enter, and so did not check: the ones find could not read (its errors,
# the path quoted or not), and the ones whose name holds a line break ("N path"). Rows the home scan
# feeds never read clean while there are any (HOME_PARTIAL).
NL_DIRS=$(printf '%s\n' "$FOUND" | sed -n 's/^N //p')
UNREAD_DIRS=""
[ -n "$SCAN_ERR" ] && UNREAD_DIRS=$(grep -E '^find: .*: (Permission denied|Operation not permitted)$' "$SCAN_ERR" 2>/dev/null |
  sed -E -e 's/^find: //' -e 's/: (Permission denied|Operation not permitted)$//' -e "s/^'(.*)'$/\\1/")
N_NL_DIRS=$(count_lines "$NL_DIRS"); N_UNREAD_DIRS=$(count_lines "$UNREAD_DIRS")
HOME_PARTIAL=0; [ $((N_NL_DIRS + N_UNREAD_DIRS)) -gt 0 ] && HOME_PARTIAL=1
# Linked settings, tasks and planted files come marked "S path" and are checked like the files, but
# files_found counts files, as it always has. A link counts only when it ends at a regular file: a
# repo can link a settings file to /dev/zero or /dev/tty, which a reader would never get to the end of.
LINKED=$(printf '%s\n' "$FOUND" | sed -n 's/^S //p' | while IFS= read -r _f; do [ -f "$_f" ] && printf '%s\n' "$_f"; done)
# Links to this user's own ~/.ssh/authorized_keys (the scan prints link candidates as "L path"),
# outside ~/.ssh itself. -ef compares the files themselves, so a link into a repo's own
# .ssh/authorized_keys fixture does not count. Before the file exists, a link that resolves to its
# place counts all the same: an agent writing through it creates the file.
ak_link() { # link
  if [ -e "$H/.ssh/authorized_keys" ]; then [ "$1" -ef "$H/.ssh/authorized_keys" ]; return; fi
  _t=$(readlink "$1" 2>/dev/null) || return 1
  [ "${_t##*/}" = authorized_keys ] || return 1
  case "$_t" in /*) ;; *) _t="${1%/*}/$_t" ;; esac
  _d=$(cd "${_t%/*}" 2>/dev/null && pwd -P) || return 1
  [ "$_d" = "$(cd "$H/.ssh" 2>/dev/null && pwd -P)" ]
}
AK_LINKS=$(printf '%s\n' "$FOUND" | sed -n 's/^L //p' | while IFS= read -r _f; do case "$_f" in ("$H"/.ssh/*) ;; (*) ak_link "$_f" && printf '%s\n' "$_f" ;; esac; done)
FOUND=$(printf '%s\n' "$FOUND" | grep -v '^[LSN] ')
LOCKFILES=$(printf '%s\n' "$FOUND" | grep -E '/(package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lock)$')
TASK_FILES=$(printf '%s\n%s\n' "$FOUND" "$LINKED" | grep -E '/\.vscode/tasks\.json$')
# Files worms plant in a project, from data/planted.tsv. A name only a worm uses counts on its own. A
# name projects use too (setup.mjs) counts in a project that also holds one of those, or when the file
# is the very one the sources publish the SHA-256 of; anywhere else section 2 lists it as a file to
# read (WORM_LOOK). WORM_PROJ lists the projects that count, each the folder holding .claude or
# .vscode: there a hook that runs such a file counts too.
WORM_FILES=$(printf '%s\n%s\n' "$FOUND" "$LINKED" | grep -E "/($PLANTED_ERE)\$")
planted_alone() { # file: is it at a path only a worm uses?
  case "
$PLANTED_ALONE
" in *"
${1#"${1%/*/*}"/}
"*) return 0 ;; esac; return 1
}
worm_proj() { # file in a .claude or .vscode folder: is its project one that counts?
  case "
$WORM_PROJ" in *"
${1%/*/*}
"*) return 0 ;; esac; return 1
}
WORM_PROJ=""; WORM_HIT=""; WORM_LOOK=""
while IFS= read -r _f; do
  [ -n "$_f" ] && planted_alone "$_f" && ! worm_proj "$_f" && WORM_PROJ="$WORM_PROJ${_f%/*/*}
"
done <<EOF
$WORM_FILES
EOF
while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  planted_alone "$_f" && continue
  worm_proj "$_f" && continue
  _pp=${_f%/*/*}; _ok=0
  while IFS= read -r _a; do [ -n "$_a" ] && [ -e "$_pp/$_a" ] && _ok=1; done <<EOF
$PLANTED_ALONE
EOF
  if [ "$_ok" -eq 0 ] && [ -f "$_f" ]; then
    _sh=$(sha_hex < "$_f" 2>/dev/null)
    case " $(planted_sha "$_f") " in *" $_sh "*) [ -n "$_sh" ] && _ok=1 ;; esac
  fi
  [ "$_ok" -eq 1 ] && WORM_PROJ="$WORM_PROJ$_pp
"
done <<EOF
$WORM_FILES
EOF
while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  if planted_alone "$_f" || worm_proj "$_f"; then WORM_HIT="$WORM_HIT$_f
"; else WORM_LOOK="$WORM_LOOK$_f
"; fi
done <<EOF
$WORM_FILES
EOF
N_LOOK=$(count_lines "$WORM_LOOK")
AIDER_FILES=$(printf '%s\n' "$FOUND" | grep -E '/\.aider\.(chat\.history\.md|input\.history)$')
# The project files of data/auto-approve.tsv, and every project's .vscode/settings.json (section 2).
AA_FILES=""; AA_ERE=""
if [ -n "$AA_PROJECT" ]; then
  AA_ERE=$(printf '%s\n' "$AA_PROJECT" | sed 's/[.]/\\./g' | paste -sd '|' -)
  AA_FILES=$(printf '%s\n' "$FOUND" | grep -E "/($AA_ERE)\$")
fi
VSC_SETTINGS=$(printf '%s\n' "$FOUND" | grep -E '/\.vscode/settings\.json$')
FOUND=$(printf '%s\n' "$FOUND" | grep -vE '/\.vscode/settings\.json$')
[ -n "$AA_ERE" ] && FOUND=$(printf '%s\n' "$FOUND" | grep -vE "/($AA_ERE)\$")
# The files added for the npm checks are left out of FOUND, so files_found counts what it always has.
FOUND=$(printf '%s\n' "$FOUND" | grep -vE '/(package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lock|\.aider\.chat\.history\.md|\.aider\.input\.history|\.vscode/tasks\.json|'"$PLANTED_ERE"')$')
ENV_FILES=$(printf '%s\n' "$FOUND" | grep -E '/\.env(rc|\.[^/]*)?$')
ALLOW_FILES=$(printf '%s\n%s\n' "$FOUND" "$LINKED" | grep -E '/\.claude/settings(\.local)?\.json$')
PROJECT_MCP=$(printf '%s\n' "$FOUND" | grep -E '/(\.mcp\.json|\.cursor/mcp\.json|\.vscode/mcp\.json)$')
SITES=$(printf '%s\n' "$FOUND" | grep -E '/site-packages$')
VENVS=$(printf '%s\n' "$FOUND" | grep -E '/pyvenv\.cfg$' | sed 's#/pyvenv\.cfg$##')

# One value from the Windows registry, read with reg.exe. The path conversion of
# Git Bash and MSYS is turned off, or it would rewrite /v into a file path. The
# 64-bit view comes first, since a 32-bit reg.exe can't see MachineGuid otherwise.
win_reg() { # key value
  for _rv in /reg:64 ""; do
    _rr=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' reg query "$1" /v "$2" $_rv 2>/dev/null | tr -d '\r' |
      awk -v n="$2" '$1 == n && $2 ~ /^REG_/ { print $NF; exit }')
    [ -n "$_rr" ] && { printf '%s' "$_rr"; return 0; }
  done
  return 1
}
# --- 1. Coding agents --------------------------------------------------------

AG_ROWS=""; AGENT_IDS=""; AG_NAMES=""; N_AG=0; N_IDLE=0; IDLE_NAMES=""; IDLE_IDS=""
while IFS='|' read -r name bins paths acts aid; do
  [ -n "$name" ] || continue
  inst=0; old_ifs=$IFS; IFS=';'
  for b in $bins; do [ -n "$b" ] && command -v "$b" >/dev/null 2>&1 && inst=1; done
  # An account run has a fixed PATH, so it looks in the account's own install folders by path.
  if [ "$ACCTRUN" -eq 1 ]; then
    for b in $bins; do
      [ -n "$b" ] || continue
      for _bd in "$H/.local/bin" "$H/bin" "$H/.npm-global/bin" "$H/.volta/bin" "$H/.bun/bin" "$H/.deno/bin" \
                 "$H/Library/pnpm" "$H/.local/share/pnpm" "$H/.asdf/shims" "$H/.local/share/mise/shims" "$H"/.nvm/versions/node/*/bin; do
        [ -e "$_bd/$b" ] && inst=1
      done
    done
  fi
  for p in $paths; do [ -n "$p" ] && [ -e "$p" ] && inst=1; done
  IFS=$old_ifs
  [ "$inst" -eq 1 ] || continue
  N_AG=$((N_AG + 1)); AGENT_IDS="${AGENT_IDS:+$AGENT_IDS }$aid"; AG_NAMES="${AG_NAMES:+$AG_NAMES, }$name"
  if [ -z "$acts" ]; then
    state=installed
  else
    any=0; recent=0; IFS=';'
    for a in $acts; do
      [ -d "$a" ] || continue
      [ -n "$(find "$a" -maxdepth 3 -type f -print -quit 2>/dev/null)" ] && any=1
      [ -n "$(find "$a" -maxdepth 3 -type f -mtime -30 -print -quit 2>/dev/null)" ] && recent=1
    done
    IFS=$old_ifs
    if [ "$recent" -eq 1 ]; then state=active
    else
      N_IDLE=$((N_IDLE + 1)); IDLE_NAMES="${IDLE_NAMES:+$IDLE_NAMES, }$name"; IDLE_IDS="${IDLE_IDS:+$IDLE_IDS }$aid"
      if [ "$any" -eq 1 ]; then state=idle; else state=unused; fi
    fi
  fi
  AG_ROWS="$AG_ROWS$name|$state
"
done <<EOF
$AGENTS
EOF
if [ "$N_AG" -gt 0 ]; then progress i "Found $(plural "$N_AG" "coding agent" "coding agents"): $(first_names "$AG_NAMES" 3)"
else progress i "No coding agents found"; fi

# --- 2. MCP servers ----------------------------------------------------------
# app | client id, from the fixed list | config file
MCP_FILES="Claude Code|claude-code|$H/.claude.json
Claude Desktop|claude-desktop|$AS/Claude/claude_desktop_config.json
Cursor|cursor|$H/.cursor/mcp.json
Windsurf|windsurf|$H/.codeium/windsurf/mcp_config.json
Codex|codex|$H/.codex/config.toml
Gemini CLI|gemini-cli|$H/.gemini/settings.json
VS Code|vscode|$AS/Code/User/mcp.json
Cline|cline|$AS/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json
Cline in Cursor|cline|$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json
Continue|continue|$H/.continue/config.json
Continue|continue|$H/.continue/config.yaml
Goose|goose|$GOOSE_CFG/config.yaml
OpenCode|opencode|$H/.config/opencode/opencode.json"

MCP_ROWS=""; N_MCP=0; N_MCP_TOKEN=0; MCP_TOK_FIRST=""; N_MCP_CACHE=0; N_MCP_CACHEF=0
# Configs inside plugin catalogs and caches (Codex's .tmp/plugins, Claude's plugins folder) are
# counted apart: they are copies of other people's configs, not servers this person set up.
is_plugin_path() {
  case "$1" in */.codex/.tmp/*|*/.claude/plugins/*|*/.cache/*|*/Library/Caches/*|*/node_modules/*) return 0 ;; esac
  return 1
}
# For the report: "client count" lines, the labels to match, and clients with a token.
MCP_TALLY=""; MCP_NAMES=""; MCP_TOK_IDS=""
MCP_LIST=$(printf '%s\n' "$MCP_FILES" | sed 's/^[^|]*|[^|]*|//'; printf '%s\n' "$PROJECT_MCP")
MCP_FLAGGED="|$(printf '%s\n' "$MCP_LIST" | fleet_filter | files_matching "$ALL_KEYS|$P_JSONSECRET|$P_TOMLSECRET" | tr '\n' '|')"
mcp_row() { # who file client-id
  _f=$2; _c=""; _nm=""
  case "$_f" in
    *.toml) # one [mcp_servers.NAME] table per server
      if [ -r "$_f" ]; then
        _nm=$(sed -nE 's/^\[mcp_servers\.("([^"]+)"|([^].]+))\][[:space:]]*$/=\2\3/p' "$_f" 2>/dev/null)
        _c=0; [ -n "$_nm" ] && _c=$(printf '%s\n' "$_nm" | grep -c '^=')
      fi ;;
    *.json)
      _js=$(json_servers "$_f")
      case "$_js" in
        '#'*) _c=${_js%%"$NL"*}; _c=${_c#\#}; case "$_js" in *"$NL"*) _nm=${_js#*"$NL"} ;; esac ;;
      esac
      case "$_c" in *[!0-9]*) _c=""; _nm="" ;; esac ;;
    *.yaml|*.yml) grep -qE '^[[:space:]]*(mcpServers|extensions):' "$_f" 2>/dev/null || _c=0 ;;
  esac
  _tok=0
  case "$MCP_FLAGGED" in *"|$_f|"*) inline_secret "$_f" && _tok=1 ;; esac
  [ "$_c" = 0 ] && [ "$_tok" -eq 0 ] && return
  _ci=$3; in_list "$_ci" "$MCP_CLIENT_IDS" || _ci=other
  _pl=0; is_plugin_path "$_f" && _pl=1
  if [ -n "$_c" ] && [ "$_pl" -eq 1 ]; then
    N_MCP_CACHE=$((N_MCP_CACHE + _c)); N_MCP_CACHEF=$((N_MCP_CACHEF + 1))
  elif [ -n "$_c" ]; then
    N_MCP=$((N_MCP + _c)); MCP_TALLY="$MCP_TALLY$_ci $_c
"
    [ -n "$_nm" ] && MCP_NAMES="$MCP_NAMES$_nm
"
  fi
  if [ "$_tok" -eq 1 ]; then
    N_MCP_TOKEN=$((N_MCP_TOKEN + 1)); [ -n "$MCP_TOK_FIRST" ] || MCP_TOK_FIRST=$_f
    case " $MCP_TOK_IDS " in *" $_ci "*) ;; *) MCP_TOK_IDS="${MCP_TOK_IDS:+$MCP_TOK_IDS }$_ci" ;; esac
    progress x "Token written in an MCP config: $(short "$_f")"
  fi
  MCP_ROWS="$MCP_ROWS$1|$_c|$_tok|$_pl|$(rowsafe "$_f")
"
}
while IFS='|' read -r who cid f; do
  [ -n "$who" ] && fleet_ok "$f" && [ -f "$f" ] && mcp_row "$who" "$f" "$cid"
done <<EOF
$MCP_FILES
EOF
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  case "$f" in
    */.cursor/mcp.json) cid=cursor ;; */.vscode/mcp.json) cid=vscode ;; */.mcp.json) cid=claude-code ;; *) cid=other ;;
  esac
  mcp_row "Project" "$f" "$cid"
done <<EOF
$PROJECT_MCP
EOF
MCP_CACHE_NOTE=""; [ "$N_MCP_CACHE" -gt 0 ] && MCP_CACHE_NOTE=", $N_MCP_CACHE more in plugin folders"
MCP_SUM="$(plural "$N_MCP" server servers)$MCP_CACHE_NOTE"
[ "$N_MCP" -eq 0 ] && [ "$N_MCP_CACHE" -gt 0 ] && MCP_SUM="none set up, $N_MCP_CACHE in plugin folders"

# Project settings that make an agent or editor run something, or trust the project's MCP
# servers, as soon as the folder is opened. A cloned repo brings them along (Check Point,
# CVE-2025-59536 and CVE-2026-21852; Oasis Security on Cursor's folderOpen tasks). Both
# settings.json and settings.local.json are read, since repos commit either. Each file is read as
# one line, so pretty-printed JSON matches too, with JSONC comments removed first.
AUTO_ROWS=""; N_AUTO=0; WORM_REFS=""; AUTO_SEEN=""
# Worms plant a file in the folder (data/planted.tsv) and run it from a hook or a task. A command runs
# one when the file is the script an interpreter runs: the first word after node, bun, deno or tsx
# and their options, or after bun run or deno run, never the code of -e, -p, --eval or --print (an
# option word starting with e or p ends the match); when the file is the command itself; or when a
# task's command is the interpreter and its first argument the file. Each may come after ;, &, &&, |
# or ||. A rule or a guard that only names the file, or passes it to another script, does not count.
# The file may be quoted, after $CLAUDE_PROJECT_DIR, ${workspaceFolder} or ./, and must end there.
worm_cmd() { # file-ERE: a command, in flattened JSON, that runs one of these files
  _wf='(\\"|'"'"')?((\\")?\$\{?(CLAUDE_PROJECT_DIR|workspaceFolder)\}?(\\")?[/\\]+|\.[/\\]+)?'"$1"'(\\"|["'"'"'[:space:];&|)])'
  _wp='(([^[:space:]"\\]|\\\\)*(/|\\\\))?'
  _wo='(--|--[A-DF-OQ-Za-df-oq-z0-9][^[:space:]"\\]*|-[A-DF-OQ-Za-df-oq-z0-9]+)[[:space:]]+'
  _ws='"command"[[:space:]]*:[[:space:]]*"[[:space:]]*(([^"\\]|\\.)*(;|&&?|\|\|?)[[:space:]]*)?'
  _wi='"command"[[:space:]]*:[[:space:]]*"'"$_wp"'(node|bun|deno|tsx)(\.exe)?"'
  _wa='"args"[[:space:]]*:[[:space:]]*\[[[:space:]]*"(\$\{?(workspaceFolder|CLAUDE_PROJECT_DIR)\}?[/\\]+|\.[/\\]+)?'"$1"'"'
  _wb='([^{}]|\{[^{}]*\})*'
  printf '%s' "$_ws$_wp((node|tsx)(\\.exe)?[[:space:]]+($_wo)*|(bun|deno)(\\.exe)?[[:space:]]+($_wo)*(run[[:space:]]+($_wo)*)?)$_wf|$_ws$_wf|$_wi$_wb$_wa|$_wa$_wb$_wi"
}
WORM_CMD_ALONE=""; [ -n "$WORM_RUN_ALONE" ] && WORM_CMD_ALONE=$(worm_cmd "$WORM_RUN_ALONE")
WORM_CMD_WEAK=""; [ -n "$WORM_RUN_WEAK" ] && WORM_CMD_WEAK=$(worm_cmd "$WORM_RUN_WEAK")
TAB=$(printf '\t')
# One line of text, with comments removed first: // to the end of the line and /* */, outside
# strings only (a \" does not end a string; a line break does, unless a \ escapes it, as VS Code's
# JSONC parser reads it). tasks.json and VS Code's settings.json are JSONC, and a commented-out
# setting in any other file is not active either. Each line is split on its quotes, and each piece
# outside a string on its slashes, both with a one-character separator, and every chunk is looked at
# a bounded number of times, so the time grows with the size of the file: a loop over single
# characters (substr measures the whole string on macOS's awk), a regex split or gsub with many
# matches, or a match that can restart inside a long run would be quadratic on a long minified line.
flat() {
  tr '\r\t' '\n ' < "$1" 2>/dev/null | awk '
    # How many backslashes s ends with. A match anchored at the last other character starts once per
    # run of backslashes, where /\\+$/ restarts at every backslash of a long run.
    function trail(s) {
      if (s !~ /\\$/) return 0
      if (match(s, /[^\\]\\*$/)) return RLENGTH - 1
      return length(s)
    }
    # A piece between two quotes, in code (st 0) or inside a block comment (st 2). Split on /,
    # // is an empty chunk between two slashes, /* a chunk starting with *, and */ a chunk ending
    # in * before a slash; the * that opened the comment (a /*/) closes nothing. Returns 1 on a // comment.
    function piece(s,   nc, c, j, op) {
      nc = split(s, c, "/"); op = 0
      for (j = 1; j <= nc; j++) {
        if (st == 2) { if (j < nc && c[j] ~ /\*$/ && !(j == op && length(c[j]) == 1)) st = 0; continue }
        printf "%s", c[j]
        if (j == nc) break
        if (c[j + 1] == "") { if (j + 1 < nc) return 1; printf "/"; continue }
        if (substr(c[j + 1], 1, 1) == "*") { st = 2; op = j + 1; continue }
        printf "/"
      }
      return 0
    }
    BEGIN { st = 0 }   # 0 code, 1 string, 2 block comment
    { nq = split($0, q, "\"")
      for (i = 1; i <= nq; i++) {
        if (st == 1) {            # in a string: kept as it is; an odd run of \ escapes the quote or the line break
          printf "%s", q[i]; esc = (trail(q[i]) % 2 == 1)
          if (i < nq) printf "\""
          if (!esc) st = 0
          continue
        }
        if (piece(q[i])) break    # a // comment: the rest of the line goes
        if (st == 2) continue     # inside a block comment: so is the quote after this piece
        if (i < nq) { printf "\""; st = 1 }
      }
      printf " "
    }'
}
auto_row() { # file what flattened-text
  # A worm file counts only when a command runs it (worm_cmd), and a file projects use too only in a
  # project that counts (WORM_PROJ).
  if { [ -n "$WORM_CMD_ALONE" ] && printf '%s' "$3" | grep -qE "$WORM_CMD_ALONE"; } ||
     { [ -n "$WORM_CMD_WEAK" ] && worm_proj "$1" && printf '%s' "$3" | grep -qE "$WORM_CMD_WEAK"; }; then
    WORM_REFS="$WORM_REFS$1
"
  fi
  # Worktrees and copies carry the same settings: one row, with how many more folders have it. The
  # row names the repo's own file, whichever one the scan listed first.
  # The path goes into TAB-separated rows and the list of settings seen, so it is made row-safe first.
  _rp=$(rowsafe "$1")
  _sum="$(printf '%s' "$3" | cksum | cut -d' ' -f1):$(printf '%s' "$_rp" | sed -E 's#/\.claude/worktrees/[^/]+/#/#')"
  case "$TAB$AUTO_SEEN" in *"$TAB$_sum$TAB"*) AUTO_ROWS="$(printf '%s' "$AUTO_ROWS" | S=$_sum F=$_rp awk -F "$TAB" -v OFS="$TAB" '
      $3 == ENVIRON["S"] { $4++; if ($1 ~ /\/\.claude\/worktrees\// && ENVIRON["F"] !~ /\/\.claude\/worktrees\//) $1 = ENVIRON["F"] } { print }')
"; return ;; esac
  AUTO_SEEN="$AUTO_SEEN$_sum$TAB"
  N_AUTO=$((N_AUTO + 1))
  progress w "Project settings that $2: $(short "$1")"
  AUTO_ROWS="$AUTO_ROWS$_rp$TAB$2$TAB$_sum${TAB}0
"
}
# A setting of data/auto-approve.tsv in a file: every pattern must match, spaces ignored. A .json
# file is read as one line through flat (comments are its job), and a match starts at the text, a {
# or a , and ends at the text's end, a , } # or /, so a longer key or another value never counts. A
# .toml file is read line by line: a # line is skipped, a match is a whole line up to a # comment
# (so a setting inside an inline table, a profile written as one, does not count), and only the
# lines before the first [table] count: a setting under [profiles.x] applies only when that profile
# is used. tr removes the spaces in one pass, and each pattern becomes one regex with its boundaries
# in it, tried once per line: linear on every awk, where a gsub on the joined text, or an index() of
# the rest of the line at every near miss, is quadratic on macOS's awk for a large file.
aa_hit() { # file pattern|pattern...
  case "$1" in *.toml) _tm=1 ;; *) _tm=0 ;; esac
  if [ "$_tm" -eq 1 ]; then tr -d ' \t\r\f\v' < "$1" 2>/dev/null; else flat "$1" | tr -d '[:space:]'; fi | AA_P=$2 awk -v toml="$_tm" '
    # A pattern as a regex that matches only its own text: every character a regex reads is quoted.
    function lit(s,   o, c, j) {
      o = ""
      for (j = 1; j <= length(s); j++) {
        c = substr(s, j, 1)
        if (c == "^") o = o "\\^"; else if (c == "]") o = o "[]]"; else if (index(".[()*+?{}/", c)) o = o "[" c "]"; else o = o c
      }
      return o
    }
    BEGIN { n = split(ENVIRON["AA_P"], p, "|")
      for (i = 1; i <= n; i++) { gsub(/[[:space:]]/, "", p[i]); re[i] = toml ? "^" lit(p[i]) "(#|$)" : "(^|[{,])" lit(p[i]) "($|[,}#/])" } }
    toml && /^#/ { next }
    toml && /^\[/ { exit }
    { for (i = 1; i <= n; i++) if (!(i in got) && $0 ~ re[i]) got[i] = 1 }
    END { for (i = 1; i <= n; i++) if (!(i in got)) exit 1; exit 0 }'
}
# Keys that make Claude Code run a command: hooks and its helper commands.
CMD_KEYS='apiKeyHelper|statusLine|awsAuthRefresh|awsCredentialExport|gcpAuthRefresh|otelHeadersHelper'
while IFS= read -r f; do
  case "$f" in */.claude/settings.json|*/.claude/settings.local.json) ;; *) continue ;; esac
  case "$f" in "$H/.claude/settings.json"|"$H/.claude/settings.local.json"|*/.claude/plugins/*) continue ;; esac
  [ -f "$f" ] || continue
  _t=$(flat "$f"); _w=""
  if printf '%s' "$_t" | grep -qE "\"hooks\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"|\"($CMD_KEYS)\"[[:space:]]*:"; then
    _w="run commands while the agent works"
  fi
  if printf '%s' "$_t" | grep -qE '"enableAllProjectMcpServers"[[:space:]]*:[[:space:]]*true|"enabledMcpjsonServers"[[:space:]]*:[[:space:]]*\[[[:space:]]*"'; then
    _w="${_w:+$_w, }turn on MCP servers without asking"
  fi
  # An empty ANTHROPIC_BASE_URL sets nothing.
  if printf '%s' "$_t" | grep -oE '"ANTHROPIC_BASE_URL"[[:space:]]*:[[:space:]]*"[^"]*[^"[:space:]][^"]*"' | grep -qvE ':[[:space:]]*"[A-Za-z]+://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?(/[^"]*)?"$'; then
    _w="${_w:+$_w, }send the agent's API traffic, key included, to another server"
  fi
  # Claude Code before 2.1.257 took bypassPermissions from any settings file, a project's too; later
  # versions take it only from the person's own or managed settings (Claude Code's settings docs).
  if printf '%s' "$_t" | grep -qE '"defaultMode"[[:space:]]*:[[:space:]]*"bypassPermissions"'; then
    _w="${_w:+$_w, }skip permission prompts with bypassPermissions. Claude Code applies it from a project only before version 2.1.257"
  fi
  [ -n "$_w" ] && auto_row "$f" "$_w" "$_t"
done <<EOF
$ALLOW_FILES
EOF
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  case "$f" in */.claude/plugins/*) continue ;; esac
  _t=$(flat "$f")
  printf '%s' "$_t" | grep -qE '"runOn"[[:space:]]*:[[:space:]]*"folderOpen"' && auto_row "$f" "run a task when the folder opens in VS Code or Cursor" "$_t"
done <<EOF
$TASK_FILES
EOF
# A project's .vscode/settings.json with "chat.tools.autoApprove": true, the setting the
# CVE-2025-53773 prompt injection made Copilot write so it could run commands without asking. VS Code
# 1.104 renamed it without migration, so current VS Code ignores it: a sign of that attack, or of an
# old VS Code, not a setting in force. A thing to look at, not an agent set to run without asking.
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  aa_hit "$f" '"chat.tools.autoApprove": true' || continue
  auto_row "$f" "auto-approve Copilot's tools with chat.tools.autoApprove, the setting the CVE-2025-53773 attack wrote into projects. VS Code 1.104 and later ignore it" "$(flat "$f")"
done <<EOF
$VSC_SETTINGS
EOF
# Row 02 counts projects: the folders holding these settings.
N_AUTO_PROJ=$(printf '%s' "$AUTO_ROWS" | cut -f1 | sed -E 's#/\.(claude|vscode)/[^/]*$##' | sort -u | grep -c .)
if [ "$N_MCP_TOKEN" -eq 0 ]; then
  if [ "$N_MCP" -gt 0 ]; then progress o "Found $(plural "$N_MCP" "MCP server" "MCP servers")$MCP_CACHE_NOTE, no tokens written in their configs"
  else progress i "No MCP servers configured$MCP_CACHE_NOTE"; fi
fi

# --- 3. Keys in plain text ---------------------------------------------------
KEY_ROWS=""; KEY_FILES=0; HIST_KEYS=0; PROV_IDS=""; KEY_FIRST=""
PROJECT_FILES=$(printf '%s\n%s\n' "$ENV_FILES" "$PROJECT_MCP")
CANDIDATES=$(
  {
    for f in .zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile .config/fish/config.fish .env .envrc \
             .zsh_history .bash_history .local/share/fish/fish_history .python_history .node_repl_history \
             .claude.json .claude/settings.json .claude/settings.local.json .codex/config.toml \
             .gemini/settings.json .gemini/.env .cursor/mcp.json .codeium/windsurf/mcp_config.json \
             .continue/config.json .continue/config.yaml .config/goose/config.yaml \
             .config/opencode/opencode.json .aider.conf.yml; do
      printf '%s\n' "$H/$f"
    done
    printf '%s\n' "$AS/Claude/claude_desktop_config.json"
    if [ "$WIN" -eq 1 ]; then
      printf '%s\n' "$GOOSE_CFG/config.yaml"
      for f in "$PSRL"/*_history.txt; do [ -f "$f" ] && printf '%s\n' "$f"; done
      [ "$HH" != "$H" ] && for f in .bashrc .bash_profile .profile .bash_history; do printf '%s\n' "$HH/$f"; done
    fi
    printf '%s\n' "$PROJECT_FILES"
  } | awk 'NF && !seen[$0]++'
)
MATCHED=$(printf '%s\n' "$CANDIDATES" | fleet_filter | files_matching "$ALL_KEYS")
# For the report: one place id per file, and one provider id per file and provider.
KEY_PLACES=""; PROV_TALLY=""
MCP_SET="|$(printf '%s\n' "$MCP_LIST" | tr '\n' '|')"; PROJECT_SET="|$(printf '%s\n' "$PROJECT_FILES" | tr '\n' '|')"
key_place() { # file: sets KP to its place, the first in KEY_PLACE_IDS that fits
  case "$1" in
    "$H/.zshrc"|"$H/.zprofile"|"$H/.zshenv"|"$H/.zlogin"|"$H/.bashrc"|"$H/.bash_profile"|"$H/.profile"|"$H/.config/fish/config.fish")
      KP=shell_rc; return 0 ;;
    "$H/.zsh_history"|"$H/.bash_history"|"$H/.local/share/fish/fish_history"|"$H/.python_history"|"$H/.node_repl_history")
      KP=shell_history; return 0 ;;
    "$HH/.bashrc"|"$HH/.bash_profile"|"$HH/.profile") KP=shell_rc; return 0 ;;
    "$HH/.bash_history") KP=shell_history; return 0 ;;
  esac
  # PowerShell's history on Windows, where typed keys most often end up
  if [ -n "$PSRL" ]; then case "$1" in "$PSRL"/*_history.txt) KP=shell_history; return 0 ;; esac; fi
  case "${1##*/}" in .env|.env.*|.envrc) KP=env_file; return 0 ;; esac
  case "$MCP_SET" in *"|$1|"*) KP=mcp_config; return 0 ;; esac
  case "$1" in
    "$H"/.claude/*|"$H"/.codex/*|"$H"/.gemini/*|"$H"/.cursor/*|"$H"/.codeium/*|"$H"/.continue/*) KP=agent_config; return 0 ;;
    "$H"/.copilot/*|"$H"/.config/goose/*|"$H"/.config/opencode/*|"$H"/.local/share/opencode/*|"$H"/.aider*|"$AS"/Claude/*|"$GOOSE_CFG"/*) KP=agent_config; return 0 ;;
  esac
  case "$PROJECT_SET" in *"|$1|"*) KP=project_file; return 0 ;; esac
  KP=other
}
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _p=$(providers_in "$f")
  [ -n "$_p" ] || continue
  KEY_FILES=$((KEY_FILES + 1)); [ -n "$KEY_FIRST" ] || KEY_FIRST="$_p|$f"
  progress x "Key in plain text: $(short "$f") ($_p)"
  key_place "$f"; KEY_PLACES="$KEY_PLACES$KP
"
  [ "$KP" = shell_history ] && HIST_KEYS=$((HIST_KEYS + 1))
  old_ifs=$IFS; IFS=','
  for _nm in $_p; do
    _nm=${_nm# }
    _id=$(prov_id "$_nm")
    case " $PROV_IDS " in *" $_id "*) ;; *) PROV_IDS="${PROV_IDS:+$PROV_IDS }$_id" ;; esac
    PROV_TALLY="$PROV_TALLY$_id
"
  done
  IFS=$old_ifs
  KEY_ROWS="$KEY_ROWS$_p|$(rowsafe "$f")
"
done <<EOF
$MATCHED
EOF
[ "$KEY_FILES" -eq 0 ] && progress o "No keys in shell profiles, history, agent configs or .env files"

# Login files any agent you run can read.
LOGINS=""; LOGIN_IDS=""
login() { # file label id [marker regex]
  fleet_ok "$1" && [ -f "$1" ] || return
  if [ -n "${4:-}" ]; then grep -aqE "$4" "$1" 2>/dev/null || return; fi
  LOGINS="${LOGINS:+$LOGINS, }$2"; LOGIN_IDS="${LOGIN_IDS:+$LOGIN_IDS }$3"
}
login "$H/.aws/credentials" "AWS keys" aws
login "$H/.config/gcloud/application_default_credentials.json" "Google Cloud login" gcloud
login "$H/.azure/msal_token_cache.json" "Azure login" azure
login "$H/.kube/config" "Kubernetes logins" kube
login "$H/.docker/config.json" "Docker registry logins" docker '"auth"[[:space:]]*:[[:space:]]*"[A-Za-z0-9+/=]{8,}'
login "$H/.npmrc" "npm token" npm '_authToken'
login "$H/.netrc" "saved passwords in .netrc" netrc
login "$H/.git-credentials" "saved Git passwords" git-credentials
login "$H/.config/gh/hosts.yml" "GitHub CLI token" gh 'oauth_token'
login "$H/.pypirc" "PyPI token" pypi 'password'
login "$H/.codex/auth.json" "Codex login" codex
login "$H/.claude/.credentials.json" "Claude Code login" claude-code
login "$H/.gemini/oauth_creds.json" "Gemini CLI login" gemini
login "$H/.local/share/opencode/auth.json" "OpenCode provider keys" opencode
login "$H/.railway/config.json" "Railway login" railway
if [ "$WIN" -eq 1 ]; then # where these tools keep the same logins on Windows
  case " $LOGIN_IDS " in *" gcloud "*) ;; *) login "$WAPP/gcloud/application_default_credentials.json" "Google Cloud login" gcloud ;; esac
  case " $LOGIN_IDS " in *" netrc "*) ;; *) login "$H/_netrc" "saved passwords in _netrc" netrc ;; esac
  case " $LOGIN_IDS " in *" gh "*) ;; *) login "$WAPP/GitHub CLI/hosts.yml" "GitHub CLI token" gh 'oauth_token' ;; esac
fi
N_SSH=0; N_SSH_OPEN=0
for k in "$H"/.ssh/*; do
  case "$k" in *.pub|*known_hosts*|*config|*authorized_keys*) continue ;; esac
  [ -d "$k" ] && continue
  fleet_ok "$k" && [ -f "$k" ] || continue
  grep -q 'PRIVATE KEY-----' "$k" 2>/dev/null || continue
  N_SSH=$((N_SSH + 1))
  if grep -q 'ENCRYPTED' "$k" 2>/dev/null; then :
  elif grep -q 'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ' "$k" 2>/dev/null || grep -qE 'BEGIN (RSA|EC|DSA) PRIVATE KEY|BEGIN PRIVATE KEY' "$k" 2>/dev/null; then
    N_SSH_OPEN=$((N_SSH_OPEN + 1))
  fi
done
if [ "$N_SSH" -gt 0 ]; then
  _s=$(plural "$N_SSH" "SSH private key" "SSH private keys")
  [ "$N_SSH_OPEN" -gt 0 ] && _s="$_s, $N_SSH_OPEN with no passphrase"
  LOGINS="${LOGINS:+$LOGINS, }$_s"; LOGIN_IDS="${LOGIN_IDS:+$LOGIN_IDS }ssh"
fi
N_LOGIN=0; for _x in $LOGIN_IDS; do N_LOGIN=$((N_LOGIN + 1)); done
[ -n "$LOGINS" ] && progress w "Login files any agent you run can read: $LOGINS"

# --- 4. Keys saved in Claude Code allow lists -------------------------------
ALLOW_ROWS=""; N_ALLOW=0; N_ALLOW_NPM=0; ALLOW_FIRST=""
ALLOW_ALL=$(printf '%s\n%s\n%s\n' "$ALLOW_FILES" "$H/.claude/settings.json" "$H/.claude/settings.local.json" | grep -v '^$' | sort -u | fleet_filter | files_matching "$ALL_KEYS|$P_ASSIGN")
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  command_secret "$f" || continue
  N_ALLOW=$((N_ALLOW + 1)); [ -n "$ALLOW_FIRST" ] || ALLOW_FIRST=$f
  progress x "Saved Claude Code command with a key: $(short "$f")"
  npm=0; npm_would_ship "${f%/.claude/*}" && { npm=1; N_ALLOW_NPM=$((N_ALLOW_NPM + 1)); }
  ALLOW_ROWS="$ALLOW_ROWS$npm|$(rowsafe "$f")
"
done <<EOF
$ALLOW_ALL
EOF
[ "$N_ALLOW" -eq 0 ] && progress o "No saved Claude Code commands with keys"

# --- 5. Recent key leaks -----------------------------------------------------
# Folders that hold Python environments. Fixed system locations are read by name;
# the rest are searched a few levels deep, skipping node_modules.
PY_ROOTS="$H/.pyenv/versions
$H/miniconda3
$H/miniforge3
$H/anaconda3
$H/.conda
$H/.virtualenvs
$H/.local/pipx
$H/.local/share/pipx
$H/.local/share/uv
/opt/homebrew/anaconda3
/opt/anaconda3
/opt/miniconda3"
if [ "$WIN" -eq 1 ]; then
  PY_ROOTS="$PY_ROOTS
$H/pipx
$WLAPP/pipx
$WAPP/uv
$WLAPP/Programs/Python
$WAPP/Python
$WLAPP/miniconda3
$WLAPP/anaconda3"
  [ -n "$_pd" ] && PY_ROOTS="$PY_ROOTS
$_pd/miniconda3
$_pd/anaconda3"
fi
# >>> bad-pypi: generated from data/bad-pypi.tsv by tools/gen.sh. Edit that file, then run it.
BAD_PYPI="litellm 1.107.0 litellm all
mistralai 2.4.6 mistralpy linux
guardrails_ai 0.10.1 guardrails linux"
PY_INCIDENTS="litellm mistralpy guardrails"
# <<< bad-pypi
SITES_ALL=$(
  {
    printf '%s\n' "$SITES"
    printf '%s\n' "$VENVS" | while IFS= read -r v; do
      [ -n "$v" ] && find "$v" -maxdepth 4 -type d -name site-packages -prune -print 2>/dev/null
    done
    for sp in /opt/homebrew/lib/python3*/site-packages /usr/local/lib/python3*/site-packages \
              /Library/Frameworks/Python.framework/Versions/*/lib/python3*/site-packages \
              "$H"/Library/Python/*/lib/python/site-packages "$H"/.local/lib/python3*/site-packages \
              /usr/lib/python3/dist-packages /usr/lib/python3*/site-packages /usr/local/lib/python3*/dist-packages; do
      [ -d "$sp" ] && printf '%s\n' "$sp"
    done
    printf '%s\n' "$PY_ROOTS" | while IFS= read -r r; do
      [ -d "$r" ] && find "$r" -maxdepth 6 \( -name node_modules -prune \) -o \( -type d \( -name site-packages -o -name dist-packages \) -prune -print \) 2>/dev/null
    done
  } | grep -v '^$' | sort -u
)
# Python incidents (data/bad-pypi.tsv and the site and temp lines of data/indicators.tsv). LITE_BAD
# and MARKS hold "incident<TAB>what was found"; PY_UPD holds "incident<TAB>os<TAB>what was found" for
# a bad version installed where its malware could not run (bad-pypi's os column): a version to
# update, not a compromised machine. The names of the hit incidents' first words make "the LiteLLM
# malware".
py_short() { # the first word of each incident's name, as "A, B and C"
  _ps=""; _pn=0; _pk=0
  for _pi in $1; do _pn=$((_pn + 1)); done
  for _pi in $1; do
    _pnm=$(incident_name "$_pi"); _pk=$((_pk + 1))
    if [ "$_pk" -eq 1 ]; then _ps=${_pnm%% *}; elif [ "$_pk" -eq "$_pn" ]; then _ps="$_ps and ${_pnm%% *}"; else _ps="$_ps, ${_pnm%% *}"; fi
  done
  printf '%s' "$_ps"
}
progress i "Checking $(plural "$(printf '%s\n' "$SITES_ALL" | grep -c .)" "Python environment" "Python environments") for the $(py_short "$PY_INCIDENTS") malware"
SITE_IND=$(printf '%s\n' "$IND_TABLE" | awk -F '|' -v o="$_os" '$3 == "site" && ($2 == "all" || $2 == o) { print $1 " " $5 }')
TEMP_IND=$(printf '%s\n' "$IND_TABLE" | awk -F '|' -v o="$_os" '$3 == "temp" && ($2 == "all" || $2 == o) { print $1 " " $4 " " $5 }')
# The advice shown under an incident's row when its temp files are found: the note of its temp lines.
temp_advice() { printf '%s\n' "$IND_TABLE" | awk -F '|' -v i="$1" '$1 == i && $3 == "temp" { print $6; exit }'; }
N_PY=0; N_LITE=0; LITE_VERS=""; LITE_BAD=""; LITE_PYC=""; PY_UPD=""
while IFS= read -r sp; do
  [ -n "$sp" ] && [ -d "$sp" ] || continue
  N_PY=$((N_PY + 1))
  # The installed LiteLLM versions, shown on a clean row and counted in litellm_installed.
  for d in "$sp"/litellm-*.dist-info; do
    [ -d "$d" ] || continue
    v=${d##*/litellm-}; v=${v%.dist-info}
    N_LITE=$((N_LITE + 1))
    case " $LITE_VERS " in *" $v "*) ;; *) LITE_VERS="${LITE_VERS:+$LITE_VERS }$v" ;; esac
  done
  for _pi in $PY_INCIDENTS; do
    bad=""
    while read -r _n _v _i _o; do
      [ "$_i" = "$_pi" ] && [ -d "$sp/$_n-$_v.dist-info" ] || continue
      # Where its malware could not run (the os column), the version is one to update, not a hit.
      case "$_o" in all|"$_os") bad="${bad:+$bad, }$_n $_v" ;; *) PY_UPD="$PY_UPD$_pi$TAB$_o$TAB$(short "$sp"): $_n $_v
" ;; esac
    done <<EOF
$BAD_PYPI
EOF
    while read -r _i _f; do
      [ "$_i" = "$_pi" ] && [ -f "$sp/$_f" ] && bad="${bad:+$bad, }$_f"
    done <<EOF
$SITE_IND
EOF
    [ -n "$bad" ] && LITE_BAD="$LITE_BAD$_pi$TAB$(short "$sp"): $bad
"
  done
  # cook.pyc stays code: a compiled leftover is only a possible sign, with its own row and fix.
  for _pyc in "$sp"/__pycache__/cook.*.pyc; do [ -f "$_pyc" ] && { LITE_PYC="$LITE_PYC$(short "$sp"): cook.pyc
"; break; }; done
done <<EOF
$SITES_ALL
EOF
MARKS=""; _seen_t="|"
# An account run looks only in the account's own temp folder, the one macOS gives each account under
# /var/folders: the shared one is the Mac's, checked by root.
_utmp=""
if [ "$ACCTRUN" -eq 1 ]; then _utmp=${GIRD_CHECK_FLEET_USER_TMP:-$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null)}; _utmp=${_utmp%/}; fi
for t in /tmp "${TMPDIR%/}" "$WTEMP" "$_utmp"; do
  [ -n "$t" ] && [ -d "$t" ] || continue
  [ "$ACCTRUN" -eq 1 ] && [ "$t" != "$_utmp" ] && continue
  case "$_seen_t" in *"|$t|"*) continue ;; esac; _seen_t="$_seen_t$t|"
  while read -r _i _own _g; do
    [ -n "$_g" ] || continue
    # shellcheck disable=SC2086  # the name may end in a glob
    for m in "$t"/$_g; do
      [ -e "$m" ] || continue
      # Another user's file in the shared /tmp is not this person's sign (owner yes in
      # data/indicators.tsv), and nor is one linked, symbolically or hard, under a marker's name; %TEMP%
      # on Windows is the person's own folder.
      if [ "$_own" = yes ] && [ "$WIN" -eq 0 ]; then
        [ -O "$m" ] && [ ! -L "$m" ] && [ -n "$(find "$m" -prune -links 1 -print 2>/dev/null)" ] || continue
      fi
      MARKS="$MARKS$_i$TAB$(rowsafe "$m")
"
    done
  done <<EOF
$TEMP_IND
EOF
done
# An environment variable and a running process are not files, so these two stay code (the issue
# LiteLLM's advisory links, BerriAI/litellm#47826, names both).
[ -n "${PRIVCOLLECT_ACTIVE:-}" ] && MARKS="${MARKS}litellm${TAB}PRIVCOLLECT_ACTIVE is set in this shell
"
LOADER=0
if [ "$ACCTRUN" -eq 0 ] && [ -e /tmp/remote_code_loader.lock ] && command -v lsof >/dev/null 2>&1; then
  [ -n "$(lsof -t /tmp/remote_code_loader.lock 2>/dev/null)" ] && LOADER=1
fi
# A bad version in uv's cache: "incident<TAB>name<TAB>version" for each one found. The cache is
# walked once, for every version at once; the exact version only, so 2.4.6 is not 2.4.60 or
# 2.4.6.post1.
_uvn=()
while read -r _n _v _i _o; do
  [ -n "$_i" ] || continue
  [ "${#_uvn[@]}" -gt 0 ] && _uvn+=(-o)
  _uvn+=(-name "$_n-$_v" -o -name "$_n-$_v-*" -o -name "$_n-$_v.dist-info" -o -name "$_n-$_v.tar.gz" -o -name "$_n-$_v.zip")
done <<EOF
$BAD_PYPI
EOF
_uvf=""
if [ "${#_uvn[@]}" -gt 0 ]; then
  for _uc in "$H/.cache/uv" ${WLAPP:+"$WLAPP/uv/cache"}; do
    [ -d "$_uc" ] || continue
    _uvf="$_uvf$(find "$_uc" -maxdepth 6 \( "${_uvn[@]}" \) -print 2>/dev/null)
"
  done
fi
UV_BAD=""
while read -r _n _v _i _o; do
  [ -n "$_i" ] || continue
  if printf '%s\n' "$_uvf" | awk -v n="$_n-$_v" '{ b = $0; sub(/.*\//, "", b)
      if (b == n || index(b, n "-") == 1 || b == n ".dist-info" || b == n ".tar.gz" || b == n ".zip") { f = 1; exit } }
    END { exit !f }'; then
    UV_BAD="$UV_BAD$_i$TAB$_n$TAB$_v
"
  fi
done <<EOF
$BAD_PYPI
EOF
PY_HITS=""
for _pi in $PY_INCIDENTS; do
  if printf '%s' "$LITE_BAD$MARKS" | grep -q "^$_pi$TAB" || { [ "$_pi" = litellm ] && [ "$LOADER" -eq 1 ]; }; then
    PY_HITS="${PY_HITS:+$PY_HITS }$_pi"
  fi
done
PY_HIT=0; [ -n "$PY_HITS" ] && PY_HIT=1
# A bad version installed where its malware could not run: a version to update (yellow), with no
# part in PY_HIT, the score or the card's py.
PY_UPD_HIT=0; [ -n "$PY_UPD" ] && PY_UPD_HIT=1
# litellm_found and the card's ll stay LiteLLM's own; the card's py is any other Python incident.
LITELLM_HIT=0; case " $PY_HITS " in *" litellm "*) LITELLM_HIT=1 ;; esac
PY_OTHER=0; for _pi in $PY_HITS; do [ "$_pi" = litellm ] || PY_OTHER=1; done
PY_SHORT=$(py_short "$PY_HITS")
if [ "$PY_HIT" -eq 1 ]; then progress x "Signs of the $PY_SHORT malware found"
elif [ -n "$LITE_PYC" ]; then progress w "A leftover cook.pyc may come from the LiteLLM malware"
elif [ "$PY_UPD_HIT" -eq 1 ]; then progress w "A Python package to update: its malware could not run on this OS"
else progress o "No signs of the $(py_short "$PY_INCIDENTS") malware in $(plural "$N_PY" "Python environment" "Python environments")"; fi
# >>> bad-npm: generated from data/bad-npm.tsv by tools/gen.sh. Edit that file, then run it.
BAD_NPM="axios 1.14.1 axios
axios 0.30.4 axios
plain-crypto-js * axios
@tanstack/arktype-adapter 1.166.12 tanstack
@tanstack/arktype-adapter 1.166.15 tanstack
@tanstack/eslint-plugin-router 1.161.9 tanstack
@tanstack/eslint-plugin-router 1.161.12 tanstack
@tanstack/eslint-plugin-start 0.0.4 tanstack
@tanstack/eslint-plugin-start 0.0.7 tanstack
@tanstack/history 1.161.9 tanstack
@tanstack/history 1.161.12 tanstack
@tanstack/nitro-v2-vite-plugin 1.154.12 tanstack
@tanstack/nitro-v2-vite-plugin 1.154.15 tanstack
@tanstack/react-router 1.169.5 tanstack
@tanstack/react-router 1.169.8 tanstack
@tanstack/react-router-devtools 1.166.16 tanstack
@tanstack/react-router-devtools 1.166.19 tanstack
@tanstack/react-router-ssr-query 1.166.15 tanstack
@tanstack/react-router-ssr-query 1.166.18 tanstack
@tanstack/react-start 1.167.68 tanstack
@tanstack/react-start 1.167.71 tanstack
@tanstack/react-start-client 1.166.51 tanstack
@tanstack/react-start-client 1.166.54 tanstack
@tanstack/react-start-rsc 0.0.47 tanstack
@tanstack/react-start-rsc 0.0.50 tanstack
@tanstack/react-start-server 1.166.55 tanstack
@tanstack/react-start-server 1.166.58 tanstack
@tanstack/router-cli 1.166.46 tanstack
@tanstack/router-cli 1.166.49 tanstack
@tanstack/router-core 1.169.5 tanstack
@tanstack/router-core 1.169.8 tanstack
@tanstack/router-devtools 1.166.16 tanstack
@tanstack/router-devtools 1.166.19 tanstack
@tanstack/router-devtools-core 1.167.6 tanstack
@tanstack/router-devtools-core 1.167.9 tanstack
@tanstack/router-generator 1.166.45 tanstack
@tanstack/router-generator 1.166.48 tanstack
@tanstack/router-plugin 1.167.38 tanstack
@tanstack/router-plugin 1.167.41 tanstack
@tanstack/router-ssr-query-core 1.168.3 tanstack
@tanstack/router-ssr-query-core 1.168.6 tanstack
@tanstack/router-utils 1.161.11 tanstack
@tanstack/router-utils 1.161.14 tanstack
@tanstack/router-vite-plugin 1.166.53 tanstack
@tanstack/router-vite-plugin 1.166.56 tanstack
@tanstack/solid-router 1.169.5 tanstack
@tanstack/solid-router 1.169.8 tanstack
@tanstack/solid-router-devtools 1.166.16 tanstack
@tanstack/solid-router-devtools 1.166.19 tanstack
@tanstack/solid-router-ssr-query 1.166.15 tanstack
@tanstack/solid-router-ssr-query 1.166.18 tanstack
@tanstack/solid-start 1.167.65 tanstack
@tanstack/solid-start 1.167.68 tanstack
@tanstack/solid-start-client 1.166.50 tanstack
@tanstack/solid-start-client 1.166.53 tanstack
@tanstack/solid-start-server 1.166.54 tanstack
@tanstack/solid-start-server 1.166.57 tanstack
@tanstack/start-client-core 1.168.5 tanstack
@tanstack/start-client-core 1.168.8 tanstack
@tanstack/start-fn-stubs 1.161.9 tanstack
@tanstack/start-fn-stubs 1.161.12 tanstack
@tanstack/start-plugin-core 1.169.23 tanstack
@tanstack/start-plugin-core 1.169.26 tanstack
@tanstack/start-server-core 1.167.33 tanstack
@tanstack/start-server-core 1.167.36 tanstack
@tanstack/start-static-server-functions 1.166.44 tanstack
@tanstack/start-static-server-functions 1.166.47 tanstack
@tanstack/start-storage-context 1.166.38 tanstack
@tanstack/start-storage-context 1.166.41 tanstack
@tanstack/valibot-adapter 1.166.12 tanstack
@tanstack/valibot-adapter 1.166.15 tanstack
@tanstack/virtual-file-routes 1.161.10 tanstack
@tanstack/virtual-file-routes 1.161.13 tanstack
@tanstack/vue-router 1.169.5 tanstack
@tanstack/vue-router 1.169.8 tanstack
@tanstack/vue-router-devtools 1.166.16 tanstack
@tanstack/vue-router-devtools 1.166.19 tanstack
@tanstack/vue-router-ssr-query 1.166.15 tanstack
@tanstack/vue-router-ssr-query 1.166.18 tanstack
@tanstack/vue-start 1.167.61 tanstack
@tanstack/vue-start 1.167.64 tanstack
@tanstack/vue-start-client 1.166.46 tanstack
@tanstack/vue-start-client 1.166.49 tanstack
@tanstack/vue-start-server 1.166.50 tanstack
@tanstack/vue-start-server 1.166.53 tanstack
@tanstack/zod-adapter 1.166.12 tanstack
@tanstack/zod-adapter 1.166.15 tanstack
@beproduct/nestjs-auth 0.1.2 tanstack
@beproduct/nestjs-auth 0.1.3 tanstack
@beproduct/nestjs-auth 0.1.4 tanstack
@beproduct/nestjs-auth 0.1.5 tanstack
@beproduct/nestjs-auth 0.1.6 tanstack
@beproduct/nestjs-auth 0.1.7 tanstack
@beproduct/nestjs-auth 0.1.8 tanstack
@beproduct/nestjs-auth 0.1.9 tanstack
@beproduct/nestjs-auth 0.1.10 tanstack
@beproduct/nestjs-auth 0.1.11 tanstack
@beproduct/nestjs-auth 0.1.12 tanstack
@beproduct/nestjs-auth 0.1.13 tanstack
@beproduct/nestjs-auth 0.1.14 tanstack
@beproduct/nestjs-auth 0.1.15 tanstack
@beproduct/nestjs-auth 0.1.16 tanstack
@beproduct/nestjs-auth 0.1.17 tanstack
@beproduct/nestjs-auth 0.1.18 tanstack
@beproduct/nestjs-auth 0.1.19 tanstack
@dirigible-ai/sdk 0.6.2 tanstack
@dirigible-ai/sdk 0.6.3 tanstack
@draftauth/client 0.2.1 tanstack
@draftauth/client 0.2.2 tanstack
@draftauth/core 0.13.1 tanstack
@draftauth/core 0.13.2 tanstack
@draftlab/auth 0.24.1 tanstack
@draftlab/auth 0.24.2 tanstack
@draftlab/auth-router 0.5.1 tanstack
@draftlab/auth-router 0.5.2 tanstack
@draftlab/db 0.16.1 tanstack
@draftlab/db 0.16.2 tanstack
@mesadev/rest 0.28.3 tanstack
@mesadev/saguaro 0.4.22 tanstack
@mesadev/sdk 0.28.3 tanstack
@ml-toolkit-ts/preprocessing 1.0.2 tanstack
@ml-toolkit-ts/preprocessing 1.0.3 tanstack
@ml-toolkit-ts/xgboost 1.0.3 tanstack
@ml-toolkit-ts/xgboost 1.0.4 tanstack
@squawk/airport-data 0.7.4 tanstack
@squawk/airport-data 0.7.5 tanstack
@squawk/airport-data 0.7.6 tanstack
@squawk/airport-data 0.7.7 tanstack
@squawk/airport-data 0.7.8 tanstack
@squawk/airports 0.6.2 tanstack
@squawk/airports 0.6.3 tanstack
@squawk/airports 0.6.4 tanstack
@squawk/airports 0.6.5 tanstack
@squawk/airports 0.6.6 tanstack
@squawk/airspace 0.8.1 tanstack
@squawk/airspace 0.8.2 tanstack
@squawk/airspace 0.8.3 tanstack
@squawk/airspace 0.8.4 tanstack
@squawk/airspace 0.8.5 tanstack
@squawk/airspace-data 0.5.3 tanstack
@squawk/airspace-data 0.5.4 tanstack
@squawk/airspace-data 0.5.5 tanstack
@squawk/airspace-data 0.5.6 tanstack
@squawk/airspace-data 0.5.7 tanstack
@squawk/airway-data 0.5.4 tanstack
@squawk/airway-data 0.5.5 tanstack
@squawk/airway-data 0.5.6 tanstack
@squawk/airway-data 0.5.7 tanstack
@squawk/airway-data 0.5.8 tanstack
@squawk/airways 0.4.2 tanstack
@squawk/airways 0.4.3 tanstack
@squawk/airways 0.4.4 tanstack
@squawk/airways 0.4.5 tanstack
@squawk/airways 0.4.6 tanstack
@squawk/fix-data 0.6.4 tanstack
@squawk/fix-data 0.6.5 tanstack
@squawk/fix-data 0.6.6 tanstack
@squawk/fix-data 0.6.7 tanstack
@squawk/fix-data 0.6.8 tanstack
@squawk/fixes 0.3.2 tanstack
@squawk/fixes 0.3.3 tanstack
@squawk/fixes 0.3.4 tanstack
@squawk/fixes 0.3.5 tanstack
@squawk/fixes 0.3.6 tanstack
@squawk/flight-math 0.5.4 tanstack
@squawk/flight-math 0.5.5 tanstack
@squawk/flight-math 0.5.6 tanstack
@squawk/flight-math 0.5.7 tanstack
@squawk/flight-math 0.5.8 tanstack
@squawk/flightplan 0.5.2 tanstack
@squawk/flightplan 0.5.3 tanstack
@squawk/flightplan 0.5.4 tanstack
@squawk/flightplan 0.5.5 tanstack
@squawk/flightplan 0.5.6 tanstack
@squawk/geo 0.4.4 tanstack
@squawk/geo 0.4.5 tanstack
@squawk/geo 0.4.6 tanstack
@squawk/geo 0.4.7 tanstack
@squawk/geo 0.4.8 tanstack
@squawk/icao-registry 0.5.2 tanstack
@squawk/icao-registry 0.5.3 tanstack
@squawk/icao-registry 0.5.4 tanstack
@squawk/icao-registry 0.5.5 tanstack
@squawk/icao-registry 0.5.6 tanstack
@squawk/icao-registry-data 0.8.4 tanstack
@squawk/icao-registry-data 0.8.5 tanstack
@squawk/icao-registry-data 0.8.6 tanstack
@squawk/icao-registry-data 0.8.7 tanstack
@squawk/icao-registry-data 0.8.8 tanstack
@squawk/mcp 0.9.1 tanstack
@squawk/mcp 0.9.2 tanstack
@squawk/mcp 0.9.3 tanstack
@squawk/mcp 0.9.4 tanstack
@squawk/mcp 0.9.5 tanstack
@squawk/navaid-data 0.6.4 tanstack
@squawk/navaid-data 0.6.5 tanstack
@squawk/navaid-data 0.6.6 tanstack
@squawk/navaid-data 0.6.7 tanstack
@squawk/navaid-data 0.6.8 tanstack
@squawk/navaids 0.4.2 tanstack
@squawk/navaids 0.4.3 tanstack
@squawk/navaids 0.4.4 tanstack
@squawk/navaids 0.4.5 tanstack
@squawk/navaids 0.4.6 tanstack
@squawk/notams 0.3.6 tanstack
@squawk/notams 0.3.7 tanstack
@squawk/notams 0.3.8 tanstack
@squawk/notams 0.3.9 tanstack
@squawk/notams 0.3.10 tanstack
@squawk/procedure-data 0.7.3 tanstack
@squawk/procedure-data 0.7.4 tanstack
@squawk/procedure-data 0.7.5 tanstack
@squawk/procedure-data 0.7.6 tanstack
@squawk/procedure-data 0.7.7 tanstack
@squawk/procedures 0.5.2 tanstack
@squawk/procedures 0.5.3 tanstack
@squawk/procedures 0.5.4 tanstack
@squawk/procedures 0.5.5 tanstack
@squawk/procedures 0.5.6 tanstack
@squawk/types 0.8.1 tanstack
@squawk/types 0.8.2 tanstack
@squawk/types 0.8.3 tanstack
@squawk/types 0.8.4 tanstack
@squawk/types 0.8.5 tanstack
@squawk/units 0.4.3 tanstack
@squawk/units 0.4.4 tanstack
@squawk/units 0.4.5 tanstack
@squawk/units 0.4.6 tanstack
@squawk/units 0.4.7 tanstack
@squawk/weather 0.5.6 tanstack
@squawk/weather 0.5.7 tanstack
@squawk/weather 0.5.8 tanstack
@squawk/weather 0.5.9 tanstack
@squawk/weather 0.5.10 tanstack
@supersurkhet/cli 0.0.2 tanstack
@supersurkhet/cli 0.0.3 tanstack
@supersurkhet/cli 0.0.4 tanstack
@supersurkhet/cli 0.0.5 tanstack
@supersurkhet/cli 0.0.6 tanstack
@supersurkhet/cli 0.0.7 tanstack
@supersurkhet/sdk 0.0.2 tanstack
@supersurkhet/sdk 0.0.3 tanstack
@supersurkhet/sdk 0.0.4 tanstack
@supersurkhet/sdk 0.0.5 tanstack
@supersurkhet/sdk 0.0.6 tanstack
@supersurkhet/sdk 0.0.7 tanstack
@tallyui/components 1.0.1 tanstack
@tallyui/components 1.0.2 tanstack
@tallyui/components 1.0.3 tanstack
@tallyui/connector-medusa 1.0.1 tanstack
@tallyui/connector-medusa 1.0.2 tanstack
@tallyui/connector-medusa 1.0.3 tanstack
@tallyui/connector-shopify 1.0.1 tanstack
@tallyui/connector-shopify 1.0.2 tanstack
@tallyui/connector-shopify 1.0.3 tanstack
@tallyui/connector-vendure 1.0.1 tanstack
@tallyui/connector-vendure 1.0.2 tanstack
@tallyui/connector-vendure 1.0.3 tanstack
@tallyui/connector-woocommerce 1.0.1 tanstack
@tallyui/connector-woocommerce 1.0.2 tanstack
@tallyui/connector-woocommerce 1.0.3 tanstack
@tallyui/core 0.2.1 tanstack
@tallyui/core 0.2.2 tanstack
@tallyui/core 0.2.3 tanstack
@tallyui/database 1.0.1 tanstack
@tallyui/database 1.0.2 tanstack
@tallyui/database 1.0.3 tanstack
@tallyui/pos 0.1.1 tanstack
@tallyui/pos 0.1.2 tanstack
@tallyui/pos 0.1.3 tanstack
@tallyui/storage-sqlite 0.2.1 tanstack
@tallyui/storage-sqlite 0.2.2 tanstack
@tallyui/storage-sqlite 0.2.3 tanstack
@tallyui/theme 0.2.1 tanstack
@tallyui/theme 0.2.2 tanstack
@tallyui/theme 0.2.3 tanstack
@taskflow-corp/cli 0.1.24 tanstack
@taskflow-corp/cli 0.1.25 tanstack
@taskflow-corp/cli 0.1.26 tanstack
@taskflow-corp/cli 0.1.27 tanstack
@taskflow-corp/cli 0.1.28 tanstack
@taskflow-corp/cli 0.1.29 tanstack
@tolka/cli 1.0.2 tanstack
@tolka/cli 1.0.3 tanstack
@tolka/cli 1.0.4 tanstack
@tolka/cli 1.0.5 tanstack
@tolka/cli 1.0.6 tanstack
agentwork-cli 0.1.4 tanstack
agentwork-cli 0.1.5 tanstack
cmux-agent-mcp 0.1.3 tanstack
cmux-agent-mcp 0.1.4 tanstack
cmux-agent-mcp 0.1.5 tanstack
cmux-agent-mcp 0.1.6 tanstack
cmux-agent-mcp 0.1.7 tanstack
cmux-agent-mcp 0.1.8 tanstack
cross-stitch 1.1.3 tanstack
cross-stitch 1.1.4 tanstack
cross-stitch 1.1.5 tanstack
cross-stitch 1.1.6 tanstack
cross-stitch 1.1.7 tanstack
git-branch-selector 1.3.3 tanstack
git-branch-selector 1.3.4 tanstack
git-branch-selector 1.3.5 tanstack
git-branch-selector 1.3.6 tanstack
git-branch-selector 1.3.7 tanstack
git-git-git 1.0.8 tanstack
git-git-git 1.0.9 tanstack
git-git-git 1.0.10 tanstack
git-git-git 1.0.11 tanstack
git-git-git 1.0.12 tanstack
ml-toolkit-ts 1.0.4 tanstack
ml-toolkit-ts 1.0.5 tanstack
nextmove-mcp 0.1.3 tanstack
nextmove-mcp 0.1.4 tanstack
nextmove-mcp 0.1.5 tanstack
nextmove-mcp 0.1.6 tanstack
nextmove-mcp 0.1.7 tanstack
safe-action 0.8.3 tanstack
safe-action 0.8.4 tanstack
ts-dna 3.0.1 tanstack
ts-dna 3.0.2 tanstack
ts-dna 3.0.3 tanstack
ts-dna 3.0.4 tanstack
ts-dna 3.0.5 tanstack
wot-api 0.8.1 tanstack
wot-api 0.8.2 tanstack
wot-api 0.8.3 tanstack
wot-api 0.8.4 tanstack
@mistralai/mistralai 2.2.2 mistral
@mistralai/mistralai 2.2.3 mistral
@mistralai/mistralai 2.2.4 mistral
@mistralai/mistralai-azure 1.7.1 mistral
@mistralai/mistralai-azure 1.7.2 mistral
@mistralai/mistralai-azure 1.7.3 mistral
@mistralai/mistralai-gcp 1.7.1 mistral
@mistralai/mistralai-gcp 1.7.2 mistral
@mistralai/mistralai-gcp 1.7.3 mistral
@uipath/access-policy-sdk 0.3.1 uipath
@uipath/access-policy-tool 0.3.1 uipath
@uipath/admin-tool 0.1.1 uipath
@uipath/agent-sdk 1.0.2 uipath
@uipath/agent-tool 1.0.1 uipath
@uipath/agent.sdk 0.0.18 uipath
@uipath/aops-policy-tool 0.3.1 uipath
@uipath/ap-chat 1.5.7 uipath
@uipath/api-workflow-tool 1.0.1 uipath
@uipath/apollo-core 5.9.2 uipath
@uipath/apollo-react 4.24.5 uipath
@uipath/apollo-wind 2.16.2 uipath
@uipath/auth 1.0.1 uipath
@uipath/case-tool 1.0.1 uipath
@uipath/cli 1.0.1 uipath
@uipath/codedagent-tool 1.0.1 uipath
@uipath/codedagents-tool 0.1.12 uipath
@uipath/codedapp-tool 1.0.1 uipath
@uipath/common 1.0.1 uipath
@uipath/context-grounding-tool 0.1.1 uipath
@uipath/data-fabric-tool 1.0.2 uipath
@uipath/docsai-tool 1.0.1 uipath
@uipath/filesystem 1.0.1 uipath
@uipath/flow-tool 1.0.2 uipath
@uipath/functions-tool 1.0.1 uipath
@uipath/gov-tool 0.3.1 uipath
@uipath/identity-tool 0.1.1 uipath
@uipath/insights-sdk 1.0.1 uipath
@uipath/insights-tool 1.0.1 uipath
@uipath/integrationservice-sdk 1.0.2 uipath
@uipath/integrationservice-tool 1.0.2 uipath
@uipath/llmgw-tool 1.0.1 uipath
@uipath/maestro-sdk 1.0.1 uipath
@uipath/maestro-tool 1.0.1 uipath
@uipath/orchestrator-tool 1.0.1 uipath
@uipath/packager-tool-apiworkflow 0.0.19 uipath
@uipath/packager-tool-bpmn 0.0.9 uipath
@uipath/packager-tool-case 0.0.9 uipath
@uipath/packager-tool-connector 0.0.19 uipath
@uipath/packager-tool-flow 0.0.19 uipath
@uipath/packager-tool-functions 0.1.1 uipath
@uipath/packager-tool-webapp 1.0.6 uipath
@uipath/packager-tool-workflowcompiler 0.0.16 uipath
@uipath/packager-tool-workflowcompiler-browser 0.0.34 uipath
@uipath/platform-tool 1.0.1 uipath
@uipath/project-packager 1.1.16 uipath
@uipath/resource-tool 1.0.1 uipath
@uipath/resourcecatalog-tool 0.1.1 uipath
@uipath/resources-tool 0.1.11 uipath
@uipath/robot 1.3.4 uipath
@uipath/rpa-legacy-tool 1.0.1 uipath
@uipath/rpa-tool 0.9.5 uipath
@uipath/solution-packager 0.0.35 uipath
@uipath/solution-tool 1.0.1 uipath
@uipath/solutionpackager-sdk 1.0.11 uipath
@uipath/solutionpackager-tool-core 0.0.34 uipath
@uipath/tasks-tool 1.0.1 uipath
@uipath/telemetry 0.0.7 uipath
@uipath/test-manager-tool 1.0.2 uipath
@uipath/tool-workflowcompiler 0.0.12 uipath
@uipath/traces-tool 1.0.1 uipath
@uipath/ui-widgets-multi-file-upload 1.0.1 uipath
@uipath/uipath-python-bridge 1.0.1 uipath
@uipath/vertical-solutions-tool 1.0.1 uipath
@uipath/vss 0.1.6 uipath
@uipath/widget.sdk 1.2.3 uipath
@bitwarden/cli 2026.4.0 bitwarden
@mastra/core 1.42.1 mastra
mastra 1.13.1 mastra
create-mastra 1.13.1 mastra
easy-day-js 1.11.22 mastra
@mastra/agent-browser 0.3.2 mastra
@mastra/agent-builder 1.0.42 mastra
@mastra/ai-sdk 1.4.6 mastra
@mastra/arize 1.2.3 mastra
@mastra/auth 1.0.3 mastra
@mastra/auth-auth0 1.0.2 mastra
@mastra/auth-better-auth 1.0.4 mastra
@mastra/auth-clerk 1.0.3 mastra
@mastra/auth-supabase 1.0.2 mastra
@mastra/auth-workos 1.5.3 mastra
@mastra/blaxel 0.4.2 mastra
@mastra/braintrust 1.1.4 mastra
@mastra/chroma 1.0.2 mastra
@mastra/claude 1.0.3 mastra
@mastra/clickhouse 1.10.1 mastra
@mastra/client-js 1.24.1 mastra
@mastra/cloudflare 1.4.2 mastra
@mastra/cloudflare-d1 1.0.7 mastra
@mastra/convex 1.2.2 mastra
@mastra/couchbase 1.0.4 mastra
@mastra/cursor 0.2.1 mastra
@mastra/datadog 1.2.5 mastra
@mastra/daytona 0.4.2 mastra
@mastra/deployer 1.42.1 mastra
@mastra/deployer-cloudflare 1.1.44 mastra
@mastra/deployer-netlify 1.1.20 mastra
@mastra/deployer-vercel 1.1.38 mastra
@mastra/docker 0.3.1 mastra
@mastra/dsql 1.0.3 mastra
@mastra/duckdb 1.4.3 mastra
@mastra/dynamodb 1.0.9 mastra
@mastra/e2b 0.3.4 mastra
@mastra/editor 0.11.3 mastra
@mastra/evals 1.3.1 mastra
@mastra/express 1.3.31 mastra
@mastra/fastembed 1.1.3 mastra
@mastra/fastify 1.3.31 mastra
@mastra/gcs 0.2.3 mastra
@mastra/github-signals 0.1.2 mastra
@mastra/google-cloud-pubsub 1.0.6 mastra
@mastra/hono 1.4.26 mastra
@mastra/inngest 1.5.2 mastra
@mastra/koa 1.5.14 mastra
@mastra/langfuse 1.3.6 mastra
@mastra/langsmith 1.2.4 mastra
@mastra/libsql 1.13.1 mastra
@mastra/loggers 1.1.3 mastra
@mastra/longmemeval 1.0.50 mastra
@mastra/mcp 1.10.1 mastra
@mastra/mcp-docs-server 1.1.47 mastra
@mastra/mcp-registry-registry 1.0.2 mastra
@mastra/mem0 0.1.14 mastra
@mastra/memory 1.20.4 mastra
@mastra/mongodb 1.9.3 mastra
@mastra/mssql 1.3.2 mastra
@mastra/nestjs 0.1.15 mastra
@mastra/node-audio 0.1.8 mastra
@mastra/node-speaker 0.1.1 mastra
@mastra/observability 1.14.2 mastra
@mastra/otel-bridge 1.2.3 mastra
@mastra/otel-exporter 1.2.3 mastra
@mastra/pg 1.13.1 mastra
@mastra/pinecone 1.0.2 mastra
@mastra/playground-ui 33.0.1 mastra
@mastra/posthog 1.0.29 mastra
@mastra/qdrant 1.0.3 mastra
@mastra/rag 2.2.2 mastra
@mastra/react 1.0.1 mastra
@mastra/redis 1.1.3 mastra
@mastra/s3 0.5.3 mastra
@mastra/s3vectors 1.0.7 mastra
@mastra/schema-compat 1.2.12 mastra
@mastra/sentry 1.1.4 mastra
@mastra/server 2.1.1 mastra
@mastra/stagehand 0.2.5 mastra
@mastra/tavily 1.0.3 mastra
@mastra/temporal 0.1.14 mastra
@mastra/turbopuffer 1.0.3 mastra
@mastra/upstash 1.1.3 mastra
@mastra/vectorize 1.0.3 mastra
@mastra/voice-aws-nova-sonic 0.1.4 mastra
@mastra/voice-deepgram 0.12.2 mastra
@mastra/voice-elevenlabs 0.12.2 mastra
@mastra/voice-google 0.12.3 mastra
@mastra/voice-google-gemini-live 0.12.2 mastra
@mastra/voice-openai 0.12.3 mastra
@mastra/voice-openai-realtime 0.12.6 mastra
@mastra/voice-playai 0.12.2 mastra
keyv 6.0.0 keyv
cacheable 2.5.1 keyv
cache-manager 7.2.10 keyv
cacheable-request 13.0.20 keyv
flat-cache 6.1.24 keyv
file-entry-cache 11.1.6 keyv
@cacheable/net 2.1.1 keyv
@cacheable/node-cache 3.1.2 keyv
@cacheable/memory 2.2.1 keyv
@cacheable/utils 2.5.1 keyv
ecto 5.0.1 keyv
claud-code * sandworm
cloude-code * sandworm
rimarf * sandworm
naniod * sandworm
suport-color * sandworm
@keyv/bigmap 6.0.0 keyvscope
@keyv/cloudflare-kv 6.0.0 keyvscope
@keyv/compress-brotli 6.0.0 keyvscope
@keyv/compress-gzip 6.0.0 keyvscope
@keyv/compress-lz4 6.0.0 keyvscope
@keyv/dynamo 6.0.0 keyvscope
@keyv/encrypt-node 6.0.0 keyvscope
@keyv/encrypt-web 6.0.0 keyvscope
@keyv/etcd 6.0.0 keyvscope
@keyv/memcache 6.0.0 keyvscope
@keyv/mongo 6.0.0 keyvscope
@keyv/mysql 6.0.0 keyvscope
@keyv/postgres 6.0.0 keyvscope
@keyv/redis 6.0.0 keyvscope
@keyv/serialize-msgpackr 6.0.0 keyvscope
@keyv/serialize-superjson 6.0.0 keyvscope
@keyv/sqlite 6.0.0 keyvscope
@keyv/test-suite 6.0.0 keyvscope
@keyv/valkey 6.0.0 keyvscope
@opensearch-project/opensearch 3.5.3 opensearch
@opensearch-project/opensearch 3.6.2 opensearch
@opensearch-project/opensearch 3.7.0 opensearch
@opensearch-project/opensearch 3.8.0 opensearch
tensorlake 0.5.144 tensorlake
cloude * sandworm
opencraw * sandworm
crypto-reader-info * sandworm
format-defaults * sandworm
hardhta * sandworm
iru-caches * sandsleep
iruchache * sandsleep
node-native-bridge * sandworm
secp256 * sandworm
crypto-locale * sandworm
detect-cache * sandworm
locale-loader-pro * sandworm
parse-compat * sandworm
scan-store * sandworm
veim * sandworm
yarsg * sandworm
ethres * sandsleep
uudi * sandsleep
@injectivelabs/sdk-ts 1.20.21 injective"
# <<< bad-npm
# >>> bad-extensions: generated from data/bad-extensions.tsv by tools/gen.sh. Edit that file, then run it.
BAD_EXT="oorzc.ssh-tools 0.5.1 glassworm openvsx
oorzc.i18n-tools-plus 1.6.8 glassworm openvsx
oorzc.mind-map 1.0.61 glassworm openvsx
oorzc.scss-to-css-compile 1.3.4 glassworm openvsx
Angular-studio.ng-angular-extension * glassworm openvsx
awesome-codebase.codebase-dart-pro * glassworm openvsx
cudra-production.vsce-prettier-pro * glassworm openvsx
dev-studio-sense.php-comp-tools-vscode * glassworm openvsx
ko-zu-gun-studio.synchronization-settings-vscode * glassworm openvsx
littensy-studio.magical-icons * glassworm openvsx
pretty-studio-advisor.prettyxml-formatter * glassworm openvsx
sol-studio.solidity-extension * glassworm openvsx
studio-jjalaire-team.professional-quarto-extension * glassworm openvsx
studio-velte-distributor.pro-svelte-extension * glassworm openvsx
sun-shine-studio.shiny-extension-for-vscode * glassworm openvsx
tucyzirille-studio.angular-pro-tools-extension * glassworm openvsx
vce-brendan-studio-eich.js-debuger-vscode * glassworm openvsx
aadarkcode.one-dark-material * glasswormmar openvsx
aligntool.extension-align-professional-tool * glasswormmar openvsx
awesomeco.wonder-for-vscode-icons * glasswormmar openvsx
bhbpbarn.vsce-python-indent-extension * glasswormmar openvsx
blockstoks.easily-gitignore-manage * glasswormmar openvsx
brategmaqendaalar-studio.pro-prettyxml-formatter * glasswormmar openvsx
codbroks.compile-runnner-extension * glasswormmar openvsx
codevunmis.csv-sql-tsv-rainbow * glasswormmar openvsx
codwayexten.code-way-extension * glasswormmar openvsx
cosmic-themes.sql-formatter * glasswormmar openvsx
craz2team.vscode-todo-extension * glasswormmar openvsx
crotoapp.vscode-xml-extension * glasswormmar openvsx
daeumer-web.es-linter-for-vs-code * glasswormmar openvsx
dark-code-studio.flutter-extension * glasswormmar openvsx
densy-little-studio.wonder-for-vscode-icons * glasswormmar openvsx
dep-labs-studio.dep-proffesinal-extension * glasswormmar openvsx
devmidu-studio.svg-better-extension * glasswormmar openvsx
dopbop-studio.vscode-tailwindcss-extension-toolkit * glasswormmar openvsx
errlenscre.error-lens-finder-ex * glasswormmar openvsx
exss-studio.yaml-professional-extension * glasswormmar openvsx
federicanc.dotenv-syntax-highlighting * glasswormmar openvsx
flutxvs.vscode-kuberntes-extension * glasswormmar openvsx
gvotcha.claude-code-extension * glasswormmar openvsx
gvotcha.claude-code-extensions * glasswormmar openvsx
intellipro.extension-json-intelligence * glasswormmar openvsx
kharizma.vscode-extension-wakatime * glasswormmar openvsx
kwitch-studio.auto-run-command-extension * glasswormmar openvsx
lavender-studio.theme-lavender-dreams * glasswormmar openvsx
lyu-wen-studio-web-han.better-formatter-vscode * glasswormmar openvsx
markvalid.vscode-mdvalidator-extension * glasswormmar openvsx
mecreation-studio.pyrefly-pro-extension * glasswormmar openvsx
mswincx.antigravity-cockpit * glasswormmar openvsx
mswincx.antigravity-cockpit-extension * glasswormmar openvsx
namopins.prettier-pro-vscode-extension * glasswormmar openvsx
oigotm.my-command-palette-extension * glasswormmar openvsx
otoboss.autoimport-extension * glasswormmar openvsx
ovixcode.vscode-better-comments * glasswormmar openvsx
pessa07tm.my-js-ts-auto-commands * glasswormmar openvsx
potstok.dotnet-runtime-extension * glasswormmar openvsx
prismapp.prisma-vs-code-extension * glasswormmar openvsx
projmanager.your-project-manager-extension * glasswormmar openvsx
pubruncode.ccoderunner * glasswormmar openvsx
pyflowpyr.py-flowpyright-extension * glasswormmar openvsx
pyscopexte.pyscope-extension * glasswormmar openvsx
redcapcollective.vscode-quarkus-elite-suite * glasswormmar openvsx
rubyideext.ruby-ide-extension * glasswormmar openvsx
runnerpost.runner-your-code * glasswormmar openvsx
shinypy.shiny-extension-for-vscode * glasswormmar openvsx
ssgwysc.volar-vscode * glasswormmar openvsx
sxatvo.jinja-extension * glasswormmar openvsx
tamokill12.foundry-pdf-extension * glasswormmar openvsx
thing-mn.your-flow-extension-for-icons * glasswormmar openvsx
tima-web-wang.shell-check-utils * glasswormmar openvsx
tokcodes.import-cost-extension * glasswormmar openvsx
toowespace.worksets-extension * glasswormmar openvsx
treedotree.tree-do-todoextension * glasswormmar openvsx
turbobase.sql-turbo-tool * glasswormmar openvsx
twilkbilk.color-highlight-css * glasswormmar openvsx
yamaprolas.revature-labs-extension * glasswormmar openvsx
lauracode.wrap-selected-code 0.0.2 glasswormvsix openvsx
96-studio.json-formatter 0.0.2 glasswormvsix openvsx
96-studio.json-formatter 0.0.4 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.1 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.3 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.4 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.5 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.6 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.7 glasswormvsix openvsx
namop-dex.claude-code-assistant 2.1.47 glasswormvsix openvsx
msw-tm.component-vetur-toolkit 0.37.4 glasswormvsix openvsx
cod-vok.arko-dev-devsecops 1.0.4 glasswormvsix openvsx
oxigener-tmp.sql-turbo-manager 0.28.10 glasswormvsix openvsx
otobo-vs.csv-query-tsv-rainbow 3.3.4 glasswormvsix openvsx
awesome-codespace.jinja-language-support 0.3.2 glasswormvsix openvsx
yamal-dext.wonder-workspace-icons 0.10.4 glasswormvsix openvsx
daeumer-web.align-format-tool 1.4.6 glasswormvsix openvsx
baksmink.vscode-quokka-extension 1.0.756 glasswormvsix openvsx
bansheejust22.retro-vhs-theme 1.0.1 glasswormvsix openvsx
quickrunn.auto-run-command-quick 1.6.2 glasswormvsix openvsx
outsidestormcommand.monochromator-theme * glasswormapr openvsx
keyacrosslaud.auto-loop-for-antigravity * glasswormapr openvsx
krundoven.ironplc-fast-hub * glasswormapr openvsx
boulderzitunnel.vscode-buddies * glasswormapr openvsx
cubedivervolt.html-code-validate * glasswormapr openvsx
winnerdomain17.version-lens-tool * glasswormapr openvsx
microsoftvs.microsoftvs * glasswormoct any
cosmic-themes.theme-cosmic-nebula * glasswormoct any"
# <<< bad-extensions
# Prints "file|name version|tag" for each bad package a lockfile or cache index names. It reads
# tarball URLs (/name/-/name-1.2.3.tgz: npm, yarn 1 and npm's cache), name@version tokens (pnpm,
# bun, yarn berry's name@npm:version), npm's "node_modules/name" entries with a "version" line,
# nested and bundled ones (node_modules/tool/node_modules/name) included, since those have no URL,
# and pnpm 5 and 7's /name/1.2.3 keys. A pin in an overrides section
# moves away from a version, so overrides are skipped. Versions are printed only if they look like
# versions, so a package can't put terminal control codes in the report. URLs and tokens are found
# by splitting each line on /-/ and on @, so the time grows with the line: a match loop over a long
# line of name characters would restart at each of them, quadratic on every awk.
npm_hits() {
  BAD_NPM_LIST=$BAD_NPM awk '
    BEGIN {
      n = split(ENVIRON["BAD_NPM_LIST"], L, "\n")
      for (i = 1; i <= n; i++) { if (split(L[i], f, " ") < 3) continue
        if (f[2] == "*") any[f[1]] = f[3]; else bad[f[1] "@" f[2]] = f[3] }
    }
    function hit(nm, v,   k, t) {
      if (v !~ /^[0-9A-Za-z.+_-]+$/) v = "?"
      if (v ~ /^0\.0\.1-security(\.[0-9]+)?$/) return   # the empty placeholder npm puts in place of a removed package: 0.0.1-security, or 0.0.1-security.0 for a few names
      k = nm "@" v; t = ""
      if (k in bad) t = bad[k]; else if (nm in any) t = any[nm]
      if (t != "" && !((FILENAME "|" k) in seen)) { seen[FILENAME "|" k] = 1; fn = FILENAME; gsub(/[[:cntrl:]]/, "?", fn); print fn "\t" nm " " v "\t" t }
    }
    FNR == 1 { over = 0; depth = 0; pend = "" }
    FILENAME ~ /pnpm-lock\.yaml$/ && /^[^ #]/ { over = ($0 ~ /^overrides:/) }
    FILENAME ~ /bun\.lock$/ {
      if (over) { o = $0; depth += gsub(/\{/, "", o); o = $0; depth -= gsub(/\}/, "", o); if (depth <= 0) over = 0; next }
      if ($0 ~ /"overrides"[[:space:]]*:[[:space:]]*\{/) { over = 1; o = $0; depth = gsub(/\{/, "", o); o = $0; depth -= gsub(/\}/, "", o); if (depth <= 0) over = 0; next }
    }
    over { next }
    FILENAME ~ /(package-lock|npm-shrinkwrap)\.json$/ {
      if (match($0, /"(node_modules\/([A-Za-z0-9._~@-]+\/)*)?(@[A-Za-z0-9._~-]+\/)?[A-Za-z0-9._~-]+"[[:space:]]*:[[:space:]]*\{/)) {
        pend = substr($0, RSTART + 1); sub(/"[[:space:]]*:.*/, "", pend); sub(/^.*node_modules\//, "", pend)
      } else if (pend != "" && match($0, /"version"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
        v = substr($0, RSTART, RLENGTH); sub(/^"version"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"$/, "", v); hit(pend, v); pend = ""
      }
    }
    FILENAME ~ /pnpm-lock\.yaml$/ && match($0, /^[[:space:]]+\/(@[A-Za-z0-9._~-]+\/)?[A-Za-z0-9._~-]+\/[0-9][^:(_\/]*/) {
      t = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]+\//, "", t); k = match(t, /\/[0-9]/); hit(substr(t, 1, k - 1), substr(t, k + 1))
    }
    {
      line = $0; gsub(/@npm:/, "@", line)
      # /name/-/name-1.2.3.tgz or /@scope/name/-/name-1.2.3.tgz: the folder before each /-/ and the
      # file after it.
      nt = split(line, T, "/-/")
      for (j = 1; j < nt; j++) {
        if (!match(T[j + 1], /^[A-Za-z0-9._~-]+\.tgz/)) continue
        base = substr(T[j + 1], 1, RLENGTH - 4)
        ns = split(T[j], S, "/"); if (ns < 2 || S[ns] !~ /^[A-Za-z0-9._~-]+$/) continue
        nm = S[ns]; b = nm
        if (ns >= 3 && S[ns - 1] ~ /^@[A-Za-z0-9._~-]+$/) nm = S[ns - 1] "/" nm
        if (substr(base, 1, length(b) + 1) == b "-") hit(nm, substr(base, length(b) + 2))
      }
      # name@1.2.3 or @scope/name@1.2.3: each piece after an @ that starts with a digit is a version,
      # and the name chars that end the piece before it its name, unless that piece was all version.
      np = split(line, P, "@"); used = 0
      for (j = 2; j <= np; j++) {
        if (!match(P[j], /^[0-9][0-9A-Za-z.+-]*/)) { used = 0; continue }
        v = substr(P[j], 1, RLENGTH); whole = (RLENGTH == length(P[j])); nm = ""
        if (!used) {
          if (j >= 3 && P[j - 1] ~ /^[A-Za-z0-9._~-]+\/[A-Za-z0-9._~-]+$/) nm = "@" P[j - 1]
          else { nw = split(P[j - 1], W, /[^A-Za-z0-9._~-]/); nm = W[nw] }
          if (nm != "") hit(nm, v)
        }
        used = (nm != "" && whole)
      }
    }' "$@" 2>/dev/null
}
NPM_ROWS=""; NPM_HIT=0; NPM_UPD=0; N_LOCK=0; NPM_UNREAD=0; LOCK_UNREAD=""
# A lockfile the scan found but can't read leaves npm not fully checked, as the cache does.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -r "$f" ]; then N_LOCK=$((N_LOCK + 1)); else LOCK_UNREAD="$LOCK_UNREAD$f
"; fi
done <<EOF
$LOCKFILES
EOF
N_LOCK_UNREAD=$(count_lines "$LOCK_UNREAD")
if [ "$N_LOCK" -gt 0 ]; then
  NPM_ROWS=$(printf '%s\n' "$LOCKFILES" | while IFS= read -r f; do [ -r "$f" ] && npm_hits "$f"; done)
fi
# Global installs: npm's own folders, the version managers (nvm, volta, fnm, asdf, mise, nodenv),
# pnpm's and bun's global folders, and npx's cache. One pass: the package.json of every package
# under each root (the package itself, or a dependency of a globally installed tool) is listed by
# its folder, and one awk reads the ones whose folder names a bad package.
NPM_ROOTS=$(
  for r in /opt/homebrew/lib/node_modules /usr/local/lib/node_modules /usr/lib/node_modules "$H/.npm-global/lib/node_modules" \
           "$H"/.nvm/versions/node/*/lib/node_modules "$H"/.volta/tools/image/node/*/lib/node_modules \
           "$H"/.volta/tools/image/packages/*/lib/node_modules "$H"/.local/share/fnm/node-versions/*/installation/lib/node_modules \
           "$H"/Library/Application\ Support/fnm/node-versions/*/installation/lib/node_modules \
           "$H"/.asdf/installs/nodejs/*/lib/node_modules "$H"/.local/share/mise/installs/node/*/lib/node_modules \
           "$H"/.nodenv/versions/*/lib/node_modules "$H"/Library/pnpm/global/*/node_modules \
           "$H"/.local/share/pnpm/global/*/node_modules "$H/.bun/install/global/node_modules" "$H"/.npm/_npx/*/node_modules; do
    [ -d "$r" ] && printf '%s\n' "$r"
  done
  if [ "$WIN" -eq 1 ]; then
    # The Windows places gird-check.ps1 reads: npm's own folder, nvm-windows (NVM_HOME), fnm (FNM_DIR), Volta, mise, pnpm and npx's cache.
    _nvm=$(winpath "${NVM_HOME:-}"); _nvm=${_nvm%/}; [ -n "$_nvm" ] || _nvm="$WAPP/nvm"
    _fnm=$(winpath "${FNM_DIR:-}"); _fnm=${_fnm%/}; [ -n "$_fnm" ] || _fnm="$WAPP/fnm"
    for r in "$WAPP/npm/node_modules" "$_nvm"/*/node_modules "$_fnm"/node-versions/*/installation/node_modules \
             "$WLAPP"/Volta/tools/image/node/*/node_modules "$WLAPP"/Volta/tools/image/packages/*/node_modules \
             "$WLAPP"/Volta/tools/image/packages/*/lib/node_modules "$WLAPP"/mise/installs/node/*/node_modules \
             "$WLAPP"/pnpm/global/*/node_modules "$WLAPP"/npm-cache/_npx/*/node_modules; do [ -d "$r" ] && printf '%s\n' "$r"; done
  fi
  # pnpm's own folder, where its setup points PNPM_HOME.
  _ph=$(winpath "${PNPM_HOME:-}"); _ph=${_ph%/}
  if [ -n "$_ph" ]; then for r in "$_ph"/global/*/node_modules; do [ -d "$r" ] && printf '%s\n' "$r"; done; fi
)
npm_global_named() { # package.json paths on stdin; the ones whose folder names a package on the list
  BAD_NPM_LIST=$BAD_NPM awk '
    BEGIN { n = split(ENVIRON["BAD_NPM_LIST"], L, "\n"); for (i = 1; i <= n; i++) if (split(L[i], f, " ") >= 3) names[f[1]] = 1 }
    { d = $0; sub(/\/package\.json$/, "", d); k = split(d, c, "/"); nm = c[k]; if (k > 1 && c[k - 1] ~ /^@/) nm = c[k - 1] "/" nm
      if (nm in names) print }'
}
npm_global_hits() { # package.json paths on stdin; prints folder|name version|tag for each bad package
  BAD_NPM_LIST=$BAD_NPM awk '
    BEGIN {
      n = split(ENVIRON["BAD_NPM_LIST"], L, "\n")
      for (i = 1; i <= n; i++) { if (split(L[i], f, " ") < 3) continue
        names[f[1]] = 1; if (f[2] == "*") any[f[1]] = f[3]; else bad[f[1] "@" f[2]] = f[3] }
    }
    {
      # The folder names the package: node_modules/<name> or node_modules/@<scope>/<name>.
      fn = $0; d = fn; sub(/\/package\.json$/, "", d)
      k = split(d, c, "/"); nm = c[k]; if (k > 1 && c[k - 1] ~ /^@/) nm = c[k - 1] "/" nm
      if (!(nm in names)) next
      v = ""
      while ((getline line < fn) > 0) {
        if (match(line, /"version"[[:space:]]*:[[:space:]]*"[^"]+"/)) { v = substr(line, RSTART, RLENGTH); sub(/^"version"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"$/, "", v); break }
      }
      close(fn)
      if (v !~ /^[0-9A-Za-z.+_-]+$/) v = "?"
      if (v ~ /^0\.0\.1-security(\.[0-9]+)?$/) next   # the empty placeholder npm puts in place of a removed package
      t = ""; if ((nm "@" v) in bad) t = bad[nm "@" v]; else if (nm in any) t = any[nm]
      if (t != "") { gsub(/[[:cntrl:]]/, "?", d); print d "\t" nm " " v "\t" t }
    }' 2>/dev/null
}
_g=$(
  printf '%s\n' "$NPM_ROOTS" | while IFS= read -r r; do
    [ -n "$r" ] || continue
    for f in "$r"/*/package.json "$r"/@*/*/package.json "$r"/*/node_modules/*/package.json "$r"/*/node_modules/@*/*/package.json \
             "$r"/@*/*/node_modules/*/package.json "$r"/@*/*/node_modules/@*/*/package.json; do
      # A regular file; in an account run anything there, so fleet_filter can count what it won't read.
      if [ -f "$f" ] || { [ "$ACCTRUN" -eq 1 ] && { [ -e "$f" ] || [ -L "$f" ]; }; }; then printf '%s\n' "$f"; fi
    done
  done | npm_global_named | fleet_filter | npm_global_hits
)
[ -n "$_g" ] && NPM_ROWS="$NPM_ROWS
$_g"
# --- 1. Coding agents: settings and versions -------------------------------------
# Agents set to run commands without asking (data/auto-approve.tsv), matched by aa_hit (section 2).
AA_ROWS=""
while IFS='|' read -r _aa _ao _ap _as _apat; do
  [ -n "$_aa" ] || continue
  case "$_ao" in all|"$_os") ;; *) continue ;; esac
  case "$_ap" in
    "{PROJECT}/"*) _rel=${_ap#"{PROJECT}/"}; _al=$(printf '%s\n' "$AA_FILES" | while IFS= read -r _f; do case "$_f" in (*/"$_rel") printf '%s\n' "$_f" ;; esac; done) ;;
    *) _al=$_ap ;;
  esac
  while IFS= read -r _f; do
    [ -n "$_f" ] && fleet_ok "$_f" && [ -f "$_f" ] && aa_hit "$_f" "$_apat" && AA_ROWS="$AA_ROWS$(rowsafe "$_f")$TAB$_aa$TAB$_as
"
  done <<EOF
$_al
EOF
done <<EOF
$AA_TABLE
EOF
# One row per file: file<TAB>agent<TAB>settings.
AA_LIST=$(printf '%s' "$AA_ROWS" | awk -F "$TAB" '!($1 in o) { o[$1] = ++n; f[n] = $1; ag[n] = $2; st[n] = $3; next } { st[o[$1]] = st[o[$1]] ", " $3 }
  END { for (i = 1; i <= n; i++) print f[i] "\t" ag[i] "\t" st[i] }')
N_YOLO=$(count_lines "$AA_LIST")
[ "$N_YOLO" -gt 0 ] && progress w "Agents set to run commands without asking: $(printf '%s\n' "$AA_LIST" | head -n 1 | cut -f2)"
# Agent versions with a published fix (data/outdated.tsv). Only a version of numbers and dots is
# compared, part by part as numbers; anything else is not reported.
ver_ok() { case "$1" in ''|*[!0-9.]*|.*|*.|*..*) return 1 ;; esac; return 0; }
ver_cmp() { # a b: prints -1, 0 or 1
  awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); k = n > m ? n : m
    for (i = 1; i <= k; i++) { if (x[i] + 0 < y[i] + 0) { print -1; exit } if (x[i] + 0 > y[i] + 0) { print 1; exit } } print 0 }'
}
# name@version in a file, where nothing that can be part of a package name comes right before it.
pkg_args() { # name files...
  _pn=$1; shift
  awk -v nm="$_pn@" '{ l = $0; off = 0
    while ((k = index(substr(l, off + 1), nm)) > 0) {
      k += off; off = k; b = k > 1 ? substr(l, k - 1, 1) : ""
      if (b ~ /[A-Za-z0-9._\/@-]/) continue
      r = substr(l, k + length(nm)); if (match(r, /^[0-9A-Za-z.+-]+/)) print substr(r, 1, RLENGTH)
    } }' "$@" 2>/dev/null
}
OLD_ROWS=""
while IFS='|' read -r _oid _onm _oos _okind _ow _olo _ohi _ohole _osrc; do
  [ -n "$_oid" ] || continue
  case "$_oos" in all|"$_os") ;; *) continue ;; esac
  case "$_okind" in
    plist) _vs=""; fleet_ok "$_ow" && [ -f "$_ow" ] && _vs=$(tr '\n\r\t' '   ' < "$_ow" 2>/dev/null | sed -n 's#.*<key>CFBundleShortVersionString</key> *<string>\([^<]*\)</string>.*#\1#p') ;;
    folder) _vs=""
      for _d in "$_ow"/*/; do
        _d=${_d%/}; _d=${_d##*/}; ver_ok "$_d" || continue
        if [ -z "$_vs" ] || [ "$(ver_cmp "$_d" "$_vs")" = 1 ]; then _vs=$_d; fi
      done ;;
    npm) _vs=$(printf '%s\n' "$NPM_ROOTS" | while IFS= read -r r; do
        [ -n "$r" ] && [ -f "$r/$_ow/package.json" ] && grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$r/$_ow/package.json" 2>/dev/null | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/'
      done) ;;
    mcparg) _vs=$(printf '%s\n' "$MCP_LIST" | while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && pkg_args "$_ow" "$f"; done) ;;
    *) _vs="" ;;
  esac
  while IFS= read -r _v; do
    ver_ok "$_v" || continue
    # name@0.1 in an MCP config is a range npx resolves when it runs, not a version: not reported.
    case "$_okind:$_v" in mcparg:*.*.*) ;; mcparg:*) continue ;; esac
    if [ "$_olo" != - ] && [ "$(ver_cmp "$_v" "$_olo")" = -1 ]; then continue; fi
    [ "$(ver_cmp "$_v" "$_ohi")" = -1 ] || continue
    OLD_ROWS="$OLD_ROWS$_oid$TAB$_onm$TAB$_v$TAB$_ohi$TAB$_ohole$TAB$_osrc
"
  done <<EOF
$_vs
EOF
done <<EOF
$OUT_TABLE
EOF
# One row per tool: name<TAB>versions<TAB>fixed<TAB>hole<TAB>advisory.
OLD_LIST=$(printf '%s' "$OLD_ROWS" | awk -F "$TAB" '!($1 in o) { o[$1] = ++n; r[n] = $2; v[n] = $3; rest[n] = $4 "\t" $5 "\t" $6; seen[$1 "|" $3] = 1; next }
  !(($1 "|" $3) in seen) { seen[$1 "|" $3] = 1; v[o[$1]] = v[o[$1]] ", " $3 }
  END { for (i = 1; i <= n; i++) print r[i] "\t" v[i] "\t" rest[i] }')
N_OLD=$(count_lines "$OLD_LIST")
[ "$N_OLD" -gt 0 ] && progress w "A tool with a security fix to install: $(printf '%s\n' "$OLD_LIST" | head -n 1 | cut -f1)"
# npm's download cache keeps a package after it is uninstalled. A hit there means it was downloaded
# on this machine, usually by an install; the report says which of the three places it came from.
# A folder or file that can't be read leaves the cache not fully checked, never clean: a cache
# folder on the way that exists but can't be read or entered counts, and so do find's and cat's
# errors, which come back unmarked next to the hits, which are marked with H.
_caches="$H/.npm"; [ "$WIN" -eq 1 ] && _caches="$_caches
$WLAPP/npm-cache"
while IFS= read -r _nc; do
  [ -n "$_nc" ] && [ -d "$_nc" ] || continue
  c=$_nc; _ok=1
  for _part in _cacache index-v5; do
    if [ ! -r "$c" ] || [ ! -x "$c" ]; then NPM_UNREAD=$((NPM_UNREAD + 1)); _ok=0; break; fi
    c="$c/$_part"; [ -d "$c" ] || { _ok=0; break; }
  done
  [ "$_ok" -eq 1 ] || continue
  # An account run leaves out a file bigger than FLEET_MAX and counts it as not checked.
  _fz=(); if [ "$ACCTRUN" -eq 1 ]; then _fz=(-size "-$((FLEET_MAX + 1))c"); find "$c" -type f -size "+${FLEET_MAX}c" 2>/dev/null >> "$FLEET_NR"; fi
  _r=$( { find "$c" -type f ${_fz[@]+"${_fz[@]}"} -print0 2>&9 | xargs -0 cat 2>&9 | npm_hits | P="$(rowsafe "$_nc") (npm's download cache)" awk -F '\t' -v OFS='\t' '{ $1 = ENVIRON["P"]; print }' | sort -u | sed 's/^/H/'; } 9>&1)
  _h=$(printf '%s\n' "$_r" | sed -n 's/^H//p')
  NPM_UNREAD=$((NPM_UNREAD + $(printf '%s\n' "$_r" | grep -c '^[^H]')))
  [ -n "$_h" ] && NPM_ROWS="$NPM_ROWS
$_h"
done <<EOF
$_caches
EOF
NPM_ROWS=$( { printf '%s\n' "$NPM_ROWS" | grep -v "(npm's download cache)$TAB" | grep -v '^$' | sort -u
              printf '%s\n' "$NPM_ROWS" | grep "(npm's download cache)$TAB" | sort -u; } )
# Editor extensions that shipped malware (data/bad-extensions.tsv): <id>-<version> folders, perhaps
# with a platform suffix such as -darwin-arm64, the id compared without case. VS Code installs from
# the Marketplace; Cursor, Windsurf, VSCodium and Kiro install from Open VSX. Windsurf became Devin
# Desktop on 2 June 2026, which keeps the extensions in ~/.devin/extensions and only reads the old
# folder (its FAQ: only the name changed), so both are read. A line whose bad build
# was only ever on Open VSX (registry openvsx) is not looked for in VS Code's own folder, where the
# same version is the Marketplace's clean build. A folder that can't be read leaves the check not
# done in full (EXT_UNREAD), never clean.
ext_roots() { printf '%s\n' "$H/.vscode/extensions" "$H/.cursor/extensions" "$H/.windsurf/extensions" "$H/.devin/extensions" "$H/.vscode-oss/extensions" "$H/.kiro/extensions"; }
EXT_UNREAD=0
while IFS= read -r r; do
  if [ -d "$r" ] && { [ ! -r "$r" ] || [ ! -x "$r" ]; }; then EXT_UNREAD=$((EXT_UNREAD + 1)); fi
done <<EOF
$(ext_roots)
EOF
EXT_ROWS=$(ext_roots | while IFS= read -r r; do
    [ -d "$r" ] || continue
    case "$r" in ("$H/.vscode/extensions") _rg=marketplace ;; (*) _rg=openvsx ;; esac
    for d in "$r"/*; do [ -d "$d" ] && printf '%s\t%s\n' "$_rg" "$d"; done
  done | BAD_EXT_LIST=$BAD_EXT awk -F '\t' '
  BEGIN { n = split(ENVIRON["BAD_EXT_LIST"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], f, " "); id[i] = tolower(f[1]); sp[i] = f[1]; v[i] = f[2]; t[i] = f[3]; rg[i] = f[4] } }
  { reg = $1; d = substr($0, length($1) + 2); gsub(/[[:cntrl:]]/, "?", d); b = d; sub(/.*\//, "", b); lb = tolower(b)
    for (i = 1; i <= n; i++) {
      if (rg[i] != "any" && rg[i] != reg) continue
      if (substr(lb, 1, length(id[i]) + 1) != id[i] "-") continue
      r = substr(b, length(id[i]) + 2)
      if (!match(r, /^[0-9]+(\.[0-9]+)*/)) continue
      ver = substr(r, 1, RLENGTH); rest = substr(r, RLENGTH + 1)
      if (rest != "" && rest !~ /^-/) continue
      if (v[i] == "*" || v[i] == ver) { print d "\t" sp[i] " " ver "\t" t[i]; break }
    } }')
# Incidents that leave the machine itself uncompromised only need the version updated; the rest mean a compromised machine.
NPM_TAGS=$(printf '%s\n' "$NPM_ROWS" | cut -f3 | grep -v '^$' | sort -u)
for _t in $NPM_TAGS; do
  if [ "$(incident_level "$_t")" = act ]; then NPM_HIT=1; else NPM_UPD=1; fi
done
# A lockfile records what some machine resolved, not what ran here. An act-level hit was installed
# when npm's cache or a global install has it, or node_modules next to the lockfile holds that
# version. A hit in a lockfile alone (NPM_LOCKPROJ lists their folders) leaves the headline and the
# fix depending on whether that project was installed; the score and the link stay as they are.
pkg_version() { # package.json: its first "version"
  awk 'match($0, /"version"[[:space:]]*:[[:space:]]*"[^"]+"/) { v = substr($0, RSTART, RLENGTH); sub(/^"version"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"$/, "", v); print v; exit }' "$1" 2>/dev/null
}
NPM_INST=0; NPM_LOCKPROJ=""
while IFS="$TAB" read -r _f _p _t; do
  [ -n "$_t" ] && [ "$(incident_level "$_t")" = act ] || continue
  case "$_f" in
    */package-lock.json|*/npm-shrinkwrap.json|*/pnpm-lock.yaml|*/yarn.lock|*/bun.lock)
      _pj="${_f%/*}/node_modules/${_p% *}/package.json"
      if [ -f "$_pj" ] && [ "$(pkg_version "$_pj")" = "${_p##* }" ]; then NPM_INST=1
      else NPM_LOCKPROJ="$NPM_LOCKPROJ${_f%/*}
"; fi ;;
    *) NPM_INST=1 ;;
  esac
done <<EOF
$NPM_ROWS
EOF
N_LOCKPROJ=$(printf '%s' "$NPM_LOCKPROJ" | sort -u | grep -c .)
# What these worms leave behind (data/indicators.tsv). gh-token-monitor runs a destructive command
# when the stolen GitHub token stops working (in the TanStack wave it tries to run rm -rf ~/, Wiz; in
# the keyv wave it evaluates a handler string the attacker supplied, Socket), so it must be stopped
# before any token is revoked. A file in the shared /tmp counts only if this person owns it.
# A startup file of an incident whose packages are editor extensions only (GlassWorm's LaunchAgent)
# is that incident's sign, shown with the extensions (EXT_PERSIST), never called npm malware, and only
# next to an extension that shipped malware: GlassWorm's is named com.user.nodestart.plist, the kind
# of name people give their own LaunchAgents, and Socket gives the name as an example. Alone, it is a
# file to check (EXT_CHECK), not a compromised machine.
EXT_INCS=" $(printf '%s\n' "$BAD_EXT" | awk '{ print $3 }' | sort -u | tr '\n' ' ')"
NPM_INCS=" $(printf '%s\n' "$BAD_NPM" | awk '{ print $3 }' | sort -u | tr '\n' ' ')"
WIPER=""; PERSIST=""; EXT_PERSIST=""; EXT_PERSIST_TAGS=""; IND_HITS=""
while IFS='|' read -r _ii _io _ik _iown _ip _in; do
  case "$_ik" in wiper|startup) ;; *) continue ;; esac
  case "$_io" in all|"$_os") ;; *) continue ;; esac
  # Shared places are root's, except a marker that must be this person's own (checked just below).
  # A link there could point at any account's file, so an account run never counts one.
  if [ "$ACCTRUN" -eq 1 ]; then case "$_ip" in "$H"/*) ;; *) [ "$_iown" = yes ] && [ ! -L "$_ip" ] || continue ;; esac; fi
  [ -n "$_ip" ] && [ -e "$_ip" ] || continue
  # A marker that must be this person's own counts only under its one name: in a shared folder, a link,
  # symbolic or hard, could put another person's file under it.
  if [ "$_iown" = yes ]; then
    [ -O "$_ip" ] || continue
    case "$_ip" in "$H"/*) ;; *) { [ ! -L "$_ip" ] && [ -n "$(find "$_ip" -prune -links 1 -print 2>/dev/null)" ]; } || continue ;; esac
  fi
  _ext=0; case "$EXT_INCS" in *" $_ii "*) case "$NPM_INCS" in *" $_ii "*) ;; *) _ext=1 ;; esac ;; esac
  [ "$_ext" -eq 1 ] || IND_HITS="$IND_HITS $_ii"
  if [ "$_ik" = wiper ]; then WIPER="$WIPER$_ip
"
  elif [ "$_ext" -eq 1 ]; then EXT_PERSIST="$EXT_PERSIST$(rowsafe "$_ip")$TAB$_in
"; EXT_PERSIST_TAGS="$EXT_PERSIST_TAGS$_ii
"
  else PERSIST="$PERSIST$(rowsafe "$_ip")$TAB$_in
"; fi
done <<EOF
$IND_TABLE
EOF
# A registry value is not a file, so the Mastra malware's Run key stays code.
if [ "$WIN" -eq 1 ]; then
  win_reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' NvmProtocal >/dev/null && PERSIST="${PERSIST}NvmProtocal in your startup programs${TAB}starts the Mastra malware at login
"
fi
[ -n "$WORM_HIT" ] && PERSIST="$PERSIST$(printf '%s' "$WORM_HIT" | while IFS= read -r _f; do printf '%s\t%s\n' "$(rowsafe "$_f")" "$(planted_note "$_f")"; done)
"
[ -n "$WORM_REFS" ] && PERSIST="$PERSIST$(printf '%s\n' "$WORM_REFS" | while IFS= read -r _f; do [ -n "$_f" ] && printf '%s\t%s\n' "$(rowsafe "$_f")" "$WORM_REF_NOTE"; done)
"
EXT_CHECK=""; EXT_CHECK_TAGS=""
if [ -z "$EXT_ROWS" ] && [ -n "$EXT_PERSIST" ]; then
  EXT_CHECK=$EXT_PERSIST; EXT_CHECK_TAGS=$EXT_PERSIST_TAGS; EXT_PERSIST=""; EXT_PERSIST_TAGS=""
fi
WIPER_HIT=0; [ -n "$WIPER" ] && WIPER_HIT=1
MAL_HIT=0; if [ "$NPM_HIT" -eq 1 ] || [ -n "$PERSIST" ] || [ "$WIPER_HIT" -eq 1 ]; then MAL_HIT=1; fi
MAL_LOCKONLY=0; if [ "$MAL_HIT" -eq 1 ] && [ "$NPM_INST" -eq 0 ] && [ -z "$PERSIST" ] && [ "$WIPER_HIT" -eq 0 ]; then MAL_LOCKONLY=1; fi
# Editor extension malware is its own finding, never called npm malware: EXT_HIT, the link's ex. An
# extension incident's startup file next to it is its sign too.
EXT_HIT=0; if [ -n "$EXT_ROWS" ] || [ -n "$EXT_PERSIST" ]; then EXT_HIT=1; fi
EXT_TAGS=$( { printf '%s\n' "$EXT_ROWS" | cut -f3; printf '%s' "$EXT_PERSIST_TAGS"; } | grep -v '^$' | sort -u)
ANY_MAL=0; if [ "$MAL_HIT" -eq 1 ] || [ "$EXT_HIT" -eq 1 ]; then ANY_MAL=1; fi
if [ "$MAL_HIT" -eq 1 ] && [ "$EXT_HIT" -eq 1 ]; then MAL_WHAT="npm and editor extension malware"; MAL_SHORT="npm and editor extension"
elif [ "$EXT_HIT" -eq 1 ]; then MAL_WHAT="malware in an editor extension"; MAL_SHORT="editor extension"
else MAL_WHAT="npm malware"; MAL_SHORT="npm"; fi
if [ "$WIPER_HIT" -eq 1 ]; then progress x "A wiper waits for a GitHub token to be revoked: gh-token-monitor"
elif [ "$ANY_MAL" -eq 1 ]; then progress x "Signs of $MAL_WHAT found"
elif [ -n "$EXT_CHECK" ]; then progress w "A startup file to check: $(short "$(printf '%s\n' "$EXT_CHECK" | head -n 1 | cut -f1)")"
elif [ "$NPM_UPD" -eq 1 ]; then progress w "An npm package to update"
elif [ $((NPM_UNREAD + N_LOCK_UNREAD)) -gt 0 ] || [ "$HOME_PARTIAL" -eq 1 ]; then progress w "npm packages not fully checked"
else progress o "No npm malware in $(plural "$N_LOCK" lockfile lockfiles), global installs or npm's cache"; fi
PLAT_FOUND=" "; N_PLAT=0; N_PLAT_FOUND=0; PLAT_LIST=""; PLAT_FIX=""
while IFS='|' read -r _pid _pnm _pcmd _ppath _pw _padv _psum; do
  [ -n "$_pid" ] || continue
  N_PLAT=$((N_PLAT + 1)); PLAT_LIST="${PLAT_LIST:+$PLAT_LIST, }$_pnm"
  _hit=0
  [ "$_pcmd" = - ] || for _c in $_pcmd; do command -v "$_c" >/dev/null 2>&1 && _hit=1; done
  _ifs=$IFS; IFS=';'
  for _p in $_ppath; do
    case "$_p" in -) ;; */) [ -d "$_p" ] && _hit=1 ;; *) [ -f "$_p" ] && _hit=1 ;; esac
  done
  IFS=$_ifs
  if [ "$_hit" -eq 1 ]; then
    PLAT_FOUND="$PLAT_FOUND$_pid "; N_PLAT_FOUND=$((N_PLAT_FOUND + 1))
    PLAT_FIX="${PLAT_FIX:+$PLAT_FIX$TAB}$(incident_name "$_pid")"
  fi
done <<EOF
$PLATFORMS
EOF
# "If you used A, B or C": the names of the platforms found.
PLAT_FIX=$(printf '%s' "$PLAT_FIX" | awk -F '\t' '{ for (i = 1; i <= NF; i++) printf "%s%s", (i == 1 ? "" : i == NF ? " or " : ", "), $i }')
plat_hit() { case "$PLAT_FOUND" in *" $1 "*) printf 1 ;; *) printf 0 ;; esac; }
# The report's fixed fields opencode and railway.
OC=$(plat_hit opencode); RW=$(plat_hit railway)

# --- Keys in agent sessions: the results --------------------------------------
# Stopped here, when the rest of the check is done, unless --all-sessions asked to wait.
if [ "$ALLSESS" -eq 1 ]; then sess_stop wait; else sess_stop; fi
# SESS_DONE counts the files read to the end; SESS_UNREAD the folders that could not be read (-1:
# some, ripgrep gives no count) and SESS_UNREAD_FILES the files; SESS_NOTRUN the files no engine
# looked at, because there is none or the check could not start.
SESS_TOTAL=0; SESS_DONE=0; SESS_ZST=0; SESS_HITS=""; SESS_UNREAD=0; SESS_UNREAD_FILES=0; SESS_NOTRUN=0
if [ -n "$SESS_FILE" ] && [ -r "$SESS_FILE" ]; then
  SESS_HITS=$(awk -F '\t' '$1 == "H" { print $2 "\t" $3 }' "$SESS_FILE")
  # Under Git Bash a native rg.exe is handed Windows paths and prints them back (C:/Users/...\...):
  # each is written the shell's way again, as the session locations are, so it keeps its agent.
  if [ "$SESS_WIN" -eq 1 ] && [ -n "$SESS_HITS" ]; then
    SESS_HITS=$(printf '%s\n' "$SESS_HITS" | while IFS="$(printf '\t')" read -r _f _p; do
      case "$_f" in ([A-Za-z]:*) _f=$(winpath "$_f") ;; esac
      printf '%s\t%s\n' "$_f" "$_p"
    done)
  fi
  if [ "$SESS_ENGINE" = perl ]; then
    SESS_TOTAL=$(awk -F '\t' '$1 == "T" { print $2; exit }' "$SESS_FILE")
    SESS_DONE=$(grep -c '^D' "$SESS_FILE")
    # Stopped while still listing the files: count them here, none were checked.
    if [ -z "$SESS_TOTAL" ]; then
      SESS_TOTAL=$(printf '%s\n' "$SESS_ROOTS" | while IFS= read -r _r; do [ -d "$_r" ] && _r="$_r/"; [ -n "$_r" ] && find -H "$_r" -type f -print0 2>/dev/null; done | tr -cd '\000' | wc -c | tr -d ' ')
    fi
    SESS_ZST=$(grep -c '^Z' "$SESS_FILE")
    SESS_UNREAD_FILES=$(grep -c '^U' "$SESS_FILE")
    SESS_UNREAD=$(awk -F '\t' '$1 == "S" { print $2; exit }' "$SESS_FILE")
  else
    _roots=(); while IFS= read -r _r; do [ -n "$_r" ] && _roots+=("$_r"); done <<EOF
$SESS_ROOTS
EOF
    _rs=(); for _r in "${_roots[@]}"; do if [ -d "$_r" ]; then _rs+=("$_r/"); else _rs+=("$_r"); fi; done
    # Counted by the NUL after each name, so a newline in a file name counts once. -H follows a
    # location that is a link, as ripgrep does, and no link found inside a folder.
    SESS_TOTAL=$(find -H "${_rs[@]}" -type f -print0 2>/dev/null | tr -cd '\000' | wc -c | tr -d ' ')
    SESS_ZST=$(find -H "${_rs[@]}" -type f -name '*.zst' -print0 2>/dev/null | tr -cd '\000' | wc -c | tr -d ' ')
    # ripgrep reports no progress per file: it finished (0 or 1), finished but could not read
    # some file or folder (2), or was stopped before the end.
    case "$SESS_RC" in 0|1) SESS_DONE=$((SESS_TOTAL - SESS_ZST)) ;; 2) SESS_DONE=$((SESS_TOTAL - SESS_ZST)); SESS_UNREAD=-1 ;; *) SESS_DONE=-1 ;; esac
  fi
elif [ -n "$SESS_ROOTS" ] && { [ "$SESS_ENGINE" = none ] || [ "$SESS_FAIL" -eq 1 ]; }; then
  SESS_NOTRUN=$(printf '%s\n' "$SESS_ROOTS" | tr '\n' '\0' | xargs -0 -I{} find -H {} -type f -print0 2>/dev/null | tr -cd '\000' | wc -c | tr -d ' ')
  case "$SESS_NOTRUN" in ''|*[!0-9]*) SESS_NOTRUN=0 ;; esac
  SESS_TOTAL=$SESS_NOTRUN
fi
case "$SESS_TOTAL" in ''|*[!0-9]*) SESS_TOTAL=0 ;; esac
case "$SESS_UNREAD" in ''|*[!0-9-]*) SESS_UNREAD=0 ;; esac
case "$SESS_UNREAD_FILES" in ''|*[!0-9]*) SESS_UNREAD_FILES=0 ;; esac
# Aider keeps its chat and the prompts typed into it (.aider.chat.history.md, .aider.input.history)
# in each project, found by the home scan, and they are checked here. The file name and the match
# are cleaned of control characters as the perl engine cleans its own, so a tab in a cloned repo's
# folder name can't shift the fields.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  SESS_TOTAL=$((SESS_TOTAL + 1))
  if [ ! -r "$f" ]; then SESS_UNREAD_FILES=$((SESS_UNREAD_FILES + 1)); continue; fi
  [ "$SESS_DONE" -ge 0 ] && SESS_DONE=$((SESS_DONE + 1))
  _h=$(grep -aoE "$TR_KEYS" "$f" 2>/dev/null | SESS_F=$f awk '{ f = ENVIRON["SESS_F"]; gsub(/[\001-\037\177]/, "?", f); gsub(/[\001-\037\177]/, " "); print "K\t" f "\t" $0 }' | sess_filter | awk -F '\t' '$1 == "H" { print $2 "\t" $3 }')
  [ -n "$_h" ] && SESS_HITS="$SESS_HITS
$_h"
done <<EOF
$AIDER_FILES
EOF
# Which agent each file belongs to and where it was found: the session folder it is under, or the
# file itself when the location is one file (Codex's history.jsonl, an Aider history). The report
# names places, not session files: a session file's path can spell out a project folder (Claude
# Code keeps sessions under one named after the project's full path), which would put a username
# and a project into a report pasted into an issue.
sess_where() { # file: sets S_AGENT and S_PLACE
  case "$1" in */.aider.chat.history.md|*/.aider.input.history) S_AGENT=Aider; S_PLACE=$1; return ;; esac
  while IFS='|' read -r _a _p; do
    case "$1" in "$_p"|"$_p"/*) S_AGENT=$_a; S_PLACE=$_p; return ;; esac
  done <<EOF
$SESS_SOURCES
EOF
  S_AGENT=Other; S_PLACE=${1%/*}
}
SESS_ROWS=""; SESS_FILES=""; SESS_PLACES=""; N_SESS=0; N_PLACES=0
if [ -n "$(printf '%s' "$SESS_HITS" | tr -d '[:space:]')" ]; then
  SESS_TAGGED=$(printf '%s\n' "$SESS_HITS" | while IFS="$(printf '\t')" read -r f p; do
    [ -n "$f" ] || continue
    sess_where "$f"; printf '%s\t%s\t%s\t%s\n' "$S_AGENT" "$f" "$p" "$S_PLACE"
  done)
  SESS_FILES=$(printf '%s\n' "$SESS_TAGGED" | cut -f2 | sort -u)
  N_SESS=$(count_lines "$SESS_FILES")
  # Each place with how many of its files had keys, most first, then by name. A file has one place.
  SESS_PLACES=$(printf '%s\n' "$SESS_TAGGED" | awk -F '\t' '$2 != "" && !($2 in s) { s[$2] = 1; c[$4]++ } END { for (p in c) printf "%d\t%s\n", c[p], p }' | sort -t "$TAB" -k1,1nr -k2,2)
  N_PLACES=$(count_lines "$SESS_PLACES")
  SESS_ROWS=$(printf '%s\n' "$SESS_TAGGED" | awk -F '\t' '
    !(($1 "|" $2) in f) { f[$1 "|" $2] = 1; n[$1]++; if (!($1 in o)) { o[$1] = ++k; name[k] = $1 } }
    !(($1 "|" $3) in pv) { pv[$1 "|" $3] = 1; ps[$1] = ps[$1] (ps[$1] == "" ? "" : ", ") $3 }
    END { for (i = 1; i <= k; i++) print name[i] "|" n[name[i]] "|" ps[name[i]] }' | sort -t '|' -k2,2nr -k1,1)
fi
# Partly checked: any file not read to the end (compressed, unreadable, or not reached when the
# check was stopped), or a folder that could not be read.
SESS_PARTIAL=0
if [ "$SESS_UNREAD" -ne 0 ] || { [ "$SESS_TOTAL" -gt 0 ] && { [ "$SESS_NOTRUN" -gt 0 ] || [ "$SESS_DONE" -lt "$SESS_TOTAL" ]; }; }; then SESS_PARTIAL=1; fi
# A check that was not done in full never leaves the headline green: the home folder was not
# scanned, the sessions were partly checked, or part of npm's cache or an extension folder could not
# be read. The headline then says what it can: no findings in the paths checked.
PARTIAL=0
if [ "$SCAN_FAILED" -eq 1 ] || [ "$HOME_PARTIAL" -eq 1 ] || [ "$SESS_PARTIAL" -eq 1 ] || [ "$NPM_UNREAD" -gt 0 ] || [ "$N_LOCK_UNREAD" -gt 0 ] || [ "$EXT_UNREAD" -gt 0 ]; then PARTIAL=1; fi
# The encrypted .pb files in those folders, as "agent|count" lines, one per agent. A folder that
# holds none (Antigravity's newer conversations are SQLite, read above) is never named.
SESS_SEALED_FOUND=$(printf '%s\n' "$SESS_SEALED" | while IFS='|' read -r _a _p; do
  [ -d "$_p" ] || continue
  printf '%s|%s\n' "$_a" "$(find "$_p/" -type f -name '*.pb' -print0 2>/dev/null | tr -cd '\000' | wc -c | tr -d ' ')"
done | awk -F '|' '$2 > 0 { if (!($1 in n)) o[++k] = $1; n[$1] += $2 } END { for (i = 1; i <= k; i++) print o[i] "|" n[o[i]] }')
if [ "$N_SESS" -gt 0 ]; then progress x "Keys in $(plural "$N_SESS" "agent session file" "agent session files")"; fi

# --- What to do, and the score -----------------------------------------------
# Each fix also belongs to a section, so that section's details can end with it.
TODO=""; ISSUES=0; FIX1=""; FIX2=""; FIX3=""; FIX4=""; FIX5=""
# With gh-token-monitor present, revoking a token sets it off: every rotate or revoke the report says
# waits for it, in the sections as in the fix list. The wiper's own fix is the one that says so.
wiper_wait() { # text
  case "$WIPER_HIT:$1" in
    "1:Don't revoke"*) printf '%s' "$1" ;;
    1:*[Rr]otate*|1:*[Rr]evoke*) printf '%s %s' "$1" "Only once gh-token-monitor is stopped and removed (section 5)." ;;
    *) printf '%s' "$1" ;;
  esac
}
todo() { # section text
  set -- "$1" "$(wiper_wait "$2")"
  TODO="$TODO$2
"; ISSUES=$((ISSUES + 1))
  case "$1" in
    1) FIX1="$FIX1$2
" ;;
    2) FIX2="$FIX2$2
" ;;
    3) FIX3="$FIX3$2
" ;;
    4) FIX4="$FIX4$2
" ;;
    *) FIX5="$FIX5$2
" ;;
  esac
}
[ "$WIPER_HIT" -eq 1 ] && todo 5 "Don't revoke any GitHub token yet. First stop and remove gh-token-monitor, as section 5 shows: it runs a destructive command when the stolen token stops working. Then rotate every key this machine could reach."
# A bad version found only in lockfiles: whether this machine is compromised depends on whether
# that project was installed here.
if [ "$MAL_LOCKONLY" -eq 1 ]; then
  if [ "$N_LOCKPROJ" -eq 1 ]; then _lp="the project"; _ll="its lockfile"; else _lp="the projects"; _ll="their lockfiles"; fi
  todo 5 "If you ran an install in $_lp section 5 lists, treat this machine as compromised: clear npm's cache with npm cache clean --force and rotate every key this machine could reach. If not, update $_ll to a version without the malware."
elif [ "$MAL_HIT" -eq 1 ]; then
  todo 5 "Treat this machine as compromised. Delete the packages and files listed in section 5, clear npm's cache with npm cache clean --force, and rotate every key this machine could reach."
fi
if [ "$EXT_HIT" -eq 1 ]; then
  # Only what section 5 lists: the extensions, the incident's startup file, or both.
  if [ -n "$EXT_PERSIST" ]; then _edo="Uninstall the extensions listed in section 5, delete the startup file listed there, and"
  else _edo="Uninstall the extensions listed in section 5 and"; fi
  todo 5 "Treat this machine as compromised. $_edo rotate every key this machine could reach."
fi
# An incident's own fix (data/incidents.tsv), once for each incident found, right after the act-now
# fixes: an act-level one, then an update-level one, ahead of every other fix (the Injective SDK's:
# move the funds out of a wallet whose seed phrase may have been sent out). Two incidents can share a
# fix (two waves of one malware): it is said once.
advice_todos() { # level
  _seen=" "; _said="$TAB"
  for _t in $NPM_TAGS $EXT_TAGS $PY_HITS; do
    case "$_seen" in *" $_t "*) continue ;; esac; _seen="$_seen$_t "
    [ "$(incident_level "$_t")" = "$1" ] || continue
    _a=$(incident_advice "$_t"); [ -n "$_a" ] || continue
    case "$_said" in *"$TAB$_a$TAB"*) continue ;; esac; _said="$_said$_a$TAB"
    todo 5 "$_a"
  done
}
[ -n "$EXT_CHECK" ] && todo 5 "Open the startup file listed in section 5 and check what it starts at login. If you did not set it up yourself, treat this machine as compromised: delete it and rotate every key this machine could reach."
[ "$LITELLM_HIT" -eq 0 ] && [ -n "$LITE_PYC" ] && todo 5 "A leftover cook.pyc can come from the LiteLLM 1.107.0 malware. If litellm 1.107.0 was ever installed there, treat this machine as compromised, follow LiteLLM's advisory and rotate every key it could reach."
case "$PY_HITS" in *" "*) _adv="each advisory in section 5" ;; *) _adv="$PY_SHORT's advisory" ;; esac
# "Don't run Python" only when a Python environment holds the bad package, not for a temp file alone.
PY_ENV=0; for _pi in $PY_HITS; do printf '%s' "$LITE_BAD" | grep -q "^$_pi$TAB" && PY_ENV=1; done
if [ "$PY_HIT" -eq 1 ] && [ "$PY_ENV" -eq 1 ]; then todo 5 "Treat this machine as compromised. Don't run Python in the affected environments, follow $_adv, and rotate every key the machine could reach."
elif [ "$PY_HIT" -eq 1 ]; then todo 5 "Treat this machine as compromised. Stop any process started from the files listed in section 5, delete them, follow $_adv, and rotate every key the machine could reach."; fi
advice_todos act
advice_todos update
case "$OS" in
  Darwin) _store="the macOS Keychain or a secrets manager" ;;
  Linux)  if [ "$WSL" -eq 1 ]; then _store="a secrets manager" # WSL usually has no desktop keyring
          else _store="your desktop keyring (GNOME Keyring or KWallet) or a secrets manager"; fi ;;
  MINGW*|MSYS*|CYGWIN*) _store="Windows Credential Manager or a secrets manager" ;;
  *)      _store="a secrets manager" ;;
esac
N_AK=$(count_lines "$AK_LINKS")
[ "$N_AK" -gt 0 ] && todo 2 "Delete the links to ~/.ssh/authorized_keys listed in section 2."
[ "$KEY_FILES" -gt 0 ] && todo 3 "Move keys out of shell profiles, history and .env files into $_store, then rotate them."
[ "$HIST_KEYS" -gt 0 ] && todo 3 "Keys in shell history were typed into a command. Treat them as exposed and rotate them."
[ "$N_SESS" -gt 0 ] && todo 3 "Keys turned up in $(plural "$N_SESS" "agent session file" "agent session files"). An agent read or was given them: treat them as exposed and rotate them."
[ "$N_MCP_TOKEN" -gt 0 ] && todo 2 "Replace tokens written into MCP configs with environment variable references, then rotate them."
[ "$N_ALLOW" -gt 0 ] && todo 4 "Delete the saved Claude Code commands that contain keys, add .claude/ to .npmignore, and rotate those keys."
[ "$N_SSH_OPEN" -gt 0 ] && todo 3 "Add a passphrase to SSH keys that have none, with ssh-keygen -p -f followed by the key file."
[ "$N_YOLO" -gt 0 ] && todo 1 "Turn off run-without-asking in the agents listed in section 1, unless they run in a sandbox."
[ "$N_OLD" -gt 0 ] && todo 1 "Update the tools listed in section 1 that have a security fix."
[ "$N_IDLE" -gt 0 ] && todo 1 "Remove agents you no longer use: $IDLE_NAMES. A poisoned package can drive an installed agent, which is how the Nx attack stole keys."
[ "$N_AUTO" -gt 0 ] && todo 2 "Read the settings marked in section 2 before an agent or editor opens those folders, and delete anything you didn't put there yourself. A cloned project can bring these with it."
[ "$N_LOOK" -gt 0 ] && todo 2 "Read the files section 2 lists as named like files worms plant, and delete any you didn't put there yourself."
[ "$MAL_HIT" -eq 0 ] && [ "$NPM_UPD" -eq 1 ] && todo 5 "Update the npm packages listed in section 5 to a version without the malware, and clear npm's cache with npm cache clean --force."
[ "$PY_HIT" -eq 0 ] && [ "$PY_UPD_HIT" -eq 1 ] && todo 5 "Update the Python packages listed in section 5 to a version without the malware."
[ "$N_PLAT_FOUND" -gt 0 ] && todo 5 "If you used $PLAT_FIX, rotate the keys stored there, even if nothing above looks wrong."

SCORE=100
[ "$PY_HIT" -eq 1 ] && SCORE=$((SCORE - 40))
[ "$ANY_MAL" -eq 1 ] && SCORE=$((SCORE - 40))
_d=$((KEY_FILES * 8)); [ "$_d" -gt 32 ] && _d=32; SCORE=$((SCORE - _d))
_d=$((HIST_KEYS * 6)); [ "$_d" -gt 12 ] && _d=12; SCORE=$((SCORE - _d))
_d=$((N_ALLOW * 10)); [ "$_d" -gt 20 ] && _d=20; SCORE=$((SCORE - _d))
_d=$((N_MCP_TOKEN * 6)); [ "$_d" -gt 12 ] && _d=12; SCORE=$((SCORE - _d))
_d=$((N_IDLE * 3)); [ "$_d" -gt 12 ] && _d=12; SCORE=$((SCORE - _d))
[ "$N_SSH_OPEN" -gt 0 ] && SCORE=$((SCORE - 4))
[ "$SCORE" -lt 0 ] && SCORE=0
if [ "$SCORE" -ge 90 ]; then GRADE=A; elif [ "$SCORE" -ge 78 ]; then GRADE=B
elif [ "$SCORE" -ge 64 ]; then GRADE=C; elif [ "$SCORE" -ge 50 ]; then GRADE=D; else GRADE=F; fi
# GRADE only goes in the research counts. People see how they compare instead.
if [ "$WIPER_HIT" -eq 1 ]; then progress x "Scan done. Don't revoke GitHub tokens yet: act now"
elif [ "$MAL_LOCKONLY" -eq 1 ] && [ "$EXT_HIT" -eq 0 ] && [ "$PY_HIT" -eq 0 ]; then progress x "Scan done. npm malware in a lockfile: act if you installed it"
elif [ "$ANY_MAL" -eq 1 ]; then progress x "Scan done. Signs of $MAL_WHAT: act now"
elif [ "$PY_HIT" -eq 1 ]; then progress x "Scan done. Signs of the $PY_SHORT malware: act now"
elif [ "$ISSUES" -gt 0 ]; then progress w "Scan done: $(plural "$ISSUES" "thing" "things") to fix"
elif [ "$PARTIAL" -eq 1 ]; then progress w "Scan done: no findings in the paths checked"
else progress o "Scan done: no findings"; fi

# An account run ends here: the fixed lines root reads, on the pipe root gave it, and nothing else.
# Only numbers and ids from the fixed lists; root checks every line again and builds the row itself.
fleet_ids() { tr ' ' '\n' | grep -E '^[a-z0-9-]+$' | awk '!s[$0]++' | paste -sd ' ' -; }
fleet_agent_id() { # an agent's name in data/auto-approve.tsv: its id in AGENTS, or the name made an id
  _fa=$(printf '%s\n' "$AGENTS" | awk -F '|' -v n="$1" '$1 == n { print $5; exit }')
  [ -n "$_fa" ] || _fa=$(printf '%s' "$1" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-')
  printf '%s' "$_fa"
}
if [ "$ACCTRUN" -eq 1 ]; then
  _yolo=$(printf '%s\n' "$AA_LIST" | cut -f2 | while IFS= read -r _n; do [ -n "$_n" ] && fleet_agent_id "$_n" && echo; done | fleet_ids)
  _inc=$(printf '%s\n' $NPM_TAGS $EXT_TAGS $PY_HITS $IND_HITS | fleet_ids)
  # Each error find printed is a folder not read, and a find that refused the scan prints one too.
  _fe=$(grep -c . "$SCAN_ERR" 2>/dev/null); case "$_fe" in ''|*[!0-9]*) _fe=0 ;; esac
  _nr=$(sort -u "$FLEET_NR" 2>/dev/null | grep -c .); _nr=$((_nr + NPM_UNREAD + N_LOCK_UNREAD + EXT_UNREAD + N_NL_DIRS + _fe))
  # Planted files that count (WORM_HIT), as the report lists them; one named like them alone is to read.
  _planted=$(( $(count_lines "$WORM_HIT") + $(count_lines "$WORM_REFS") ))
  # Possible signs, to check: a LiteLLM leftover with nothing else of LiteLLM, and a startup file
  # named like an extension incident's with no such extension (EXT_CHECK).
  _poss=""; [ -n "$LITE_PYC" ] && [ "$LITELLM_HIT" -eq 0 ] && _poss=litellm
  _poss=$(printf '%s\n' $_poss $EXT_CHECK_TAGS | fleet_ids)
  {
    echo "v=1"
    echo "agents=$(printf '%s' "$AGENT_IDS" | fleet_ids)"
    echo "yolo=$_yolo"
    echo "tools=$(printf '%s' "$OLD_ROWS" | cut -f1 | fleet_ids)"
    echo "mcp_servers=$N_MCP"
    echo "mcp_token_files=$N_MCP_TOKEN"
    echo "key_files=$KEY_FILES"
    echo "key_providers=$(printf '%s' "$PROV_IDS" | fleet_ids)"
    echo "history_keys=$HIST_KEYS"
    echo "session_files=$N_SESS"
    echo "sessions_partial=$SESS_PARTIAL"
    echo "allow_list_keys=$N_ALLOW"
    echo "ssh_open=$N_SSH_OPEN"
    echo "ak_links=$N_AK"
    echo "planted=$_planted"
    echo "possible=$_poss"
    echo "incidents=$_inc"
    echo "platforms=$(printf '%s' "$PLAT_FOUND" | fleet_ids)"
    echo "on_open=$N_AUTO"
    echo "to_read=$N_LOOK"
    echo "updates=$(printf '%s\n' "$PY_UPD" | cut -f1 | fleet_ids)"
    echo "wiper=$WIPER_HIT"
    echo "not_read=$_nr"
    echo "protected=$FLEET_PROT"
    echo "end=1"
  } >&3
  exit 0
fi
# For demos and tests: keep the scan phase running for at least this many seconds.
case "${GIRD_CHECK_MIN_SECONDS:-}" in
  ''|*[!0-9]*) ;;
  *) while [ $((SECONDS - SCAN_T0)) -lt "$GIRD_CHECK_MIN_SECONDS" ]; do sleep 1; done ;;
esac
SCAN_SECS=$((SECONDS - SCAN_T0)); WAIT_SECS=0
if [ -n "$GAME_PID" ]; then
  [ "$SCAN_SECS" -lt 1 ] && sleep 1   # let the game set up before it is told
  _w0=$SECONDS
  kill -USR1 "$GAME_PID" 2>/dev/null
  wait "$GAME_PID" 2>/dev/null; GAME_RC=$?
  WAIT_SECS=$((SECONDS - _w0)); GAME_PID=""
  if [ -n "$KEYS_PID" ]; then kill "$KEYS_PID" 2>/dev/null; wait "$KEYS_PID" 2>/dev/null; KEYS_PID=""; fi
  if [ -n "$SAVED_TTY" ]; then stty "$SAVED_TTY" </dev/tty 2>/dev/null; SAVED_TTY=""; fi
else
  spin_stop
fi
GP=0; GB=0
if [ "$GAME_RC" -ge 1 ] && [ "$GAME_RC" -le 100 ]; then GP=1; GB=$(( (GAME_RC - 1) * 50 )); fi

# ---------------------------------------------------------------------------
# Counts for GIRD's research, sent once when the scan is done unless --offline or
# DO_NOT_TRACK=1. The reply says how this machine compares with other developers.
# They are the numbers above plus a few facts about the setup,
# each squeezed into a fixed list or a strict pattern before it goes. Never a
# path, a file name, a key, a name you gave an MCP server, a username, a
# hostname or the raw hardware ID. The device ID is a
# one-way SHA-256 of the hardware UUID (Linux and WSL: machine-id, Windows: MachineGuid) salted for this
# script, so repeat runs can be counted; it can't be turned back into the ID.
# The server keeps the country, not the IP address.
# ---------------------------------------------------------------------------
json_list() { _o=""; for _x in $1; do _o="${_o:+$_o,}\"$_x\""; done; printf '[%s]' "$_o"; }
# {"id":n,...} over the ids of a fixed list, in its order, from lines of "id"
# (counts one) or "id n" (adds n). An id outside the list is dropped.
json_tally() { # list lines
  printf '%s\n' "$2" | IDS="$1" awk '
    NF { t[$1] += (NF > 1 ? $2 : 1); seen[$1] = 1 }
    END {
      n = split(ENVIRON["IDS"], id, " "); out = ""
      for (i = 1; i <= n; i++) if (id[i] in seen) out = out (out == "" ? "" : ",") "\"" id[i] "\":" (t[id[i]] + 0)
      printf "{%s}", out
    }'
}
HWID=""
if [ "$OS" = Darwin ]; then HWID=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/ {print $4; exit}')
elif [ "$WIN" -eq 1 ]; then # as stored, no case change, so gird-check.ps1 gets the same ID on this PC
  HWID=$(win_reg 'HKLM\SOFTWARE\Microsoft\Cryptography' MachineGuid)
  case "$HWID" in *[!0-9A-Fa-f-]*) HWID="" ;; esac
elif [ -r /etc/machine-id ]; then HWID=$(head -c 64 /etc/machine-id 2>/dev/null); fi
DEVICE_ID=""; [ -n "$HWID" ] && DEVICE_ID=$(printf 'gird-check-v1:%s' "$HWID" | sha_hex)
HWID=""
case "$DEVICE_ID" in *[!0-9a-f]*) DEVICE_ID="" ;; esac; [ "${#DEVICE_ID}" -eq 64 ] || DEVICE_ID=""
RUN_ID=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
case "$RUN_ID" in *[!0-9a-f]*) RUN_ID="" ;; esac; [ "${#RUN_ID}" -eq 16 ] || RUN_ID=""
OSV=Linux
if [ "$OS" = Darwin ]; then OSV="macOS $(sw_vers -productVersion 2>/dev/null | tr -cd '0-9.' | cut -d. -f1-2)"; OSV=${OSV% }; fi
if [ "$WIN" -eq 1 ]; then
  # Windows 11 still says 10.0; its build number starts at 22000. uname -s ends
  # in the build on newer Git Bash, MSYS2 and Cygwin (MINGW64_NT-10.0-22631).
  _wb=$(win_reg 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' CurrentBuildNumber)
  case "$_wb" in ''|*[!0-9]*) _wb=${OS##*-} ;; esac
  case "$_wb" in ''|*[!0-9]*) _wb=0 ;; esac
  _wb=${_wb:0:9}
  if [ "$_wb" -ge 22000 ]; then OSV="Windows 11"; elif [ "$_wb" -ge 10240 ]; then OSV="Windows 10"; else OSV=Windows; fi
  case "${PROCESSOR_ARCHITEW6432:-${PROCESSOR_ARCHITECTURE:-}}" in
    AMD64|amd64) ARCH=x86_64 ;; ARM64|arm64) ARCH=arm64 ;; '') ;; *) ARCH=other ;;
  esac
fi
case "$ARCH" in arm64|aarch64) ARCH_ID=arm64 ;; x86_64) ARCH_ID=x86_64 ;; *) ARCH_ID=other ;; esac
MODEL=""; [ "$OS" = Darwin ] && MODEL=$(sysctl -n hw.model 2>/dev/null | tr -cd 'A-Za-z0-9,' | cut -c1-20)
case "${__CFBundleIdentifier:-}" in
  com.apple.Terminal) TERMAPP=terminal ;; com.googlecode.iterm2) TERMAPP=iterm2 ;;
  com.microsoft.VSCode*) TERMAPP=vscode ;; com.todesktop.230313mzl4w4u92) TERMAPP=cursor ;;
  com.exafunction.windsurf) TERMAPP=windsurf ;; dev.warp.*) TERMAPP=warp ;; com.mitchellh.ghostty) TERMAPP=ghostty ;;
  net.kovidgoyal.kitty) TERMAPP=kitty ;; com.github.wez.wezterm) TERMAPP=wezterm ;; org.alacritty|io.alacritty) TERMAPP=alacritty ;;
  co.zeit.hyper) TERMAPP=hyper ;; com.jetbrains.*) TERMAPP=jetbrains ;;
  *) case "${TERM_PROGRAM:-}" in
       Apple_Terminal) TERMAPP=terminal ;; iTerm.app) TERMAPP=iterm2 ;; vscode) TERMAPP=vscode ;; WarpTerminal) TERMAPP=warp ;;
       ghostty) TERMAPP=ghostty ;; WezTerm) TERMAPP=wezterm ;; Hyper) TERMAPP=hyper ;; tmux) TERMAPP=tmux ;;
       '') TERMAPP=unknown ;; *) TERMAPP=other ;;
     esac ;;
esac
if [ "$WIN" -eq 1 ] || [ "$WSL" -eq 1 ]; then
  case "$TERMAPP" in unknown|other) [ -n "${WT_SESSION:-}" ] && TERMAPP=windows-terminal ;; esac
fi
TMUXED=0; [ -n "${TMUX:-}" ] && TMUXED=1
case "${SHELL##*/}" in zsh|bash|fish|sh|dash|ksh|tcsh|nu|elvish|xonsh) SHELLNAME=${SHELL##*/} ;; '') SHELLNAME=unknown ;; *) SHELLNAME=other ;; esac
LANGCODE=${ORIG_LANG%%.*}
case "$LANGCODE" in [a-z][a-z]|[a-z][a-z]_[A-Z][A-Z]) ;; *) LANGCODE=other ;; esac
VIA=none; [ -n "${CLAUDECODE:-}" ] && VIA=claude-code
# files_found counts files, as TELEMETRY.md says: the site-packages folders the scan lists are not files.
N_FOUND=$(printf '%s\n' "$FOUND" | grep -v '/site-packages$' | grep -c .); N_ENVF=$(count_lines "$ENV_FILES"); N_ALLOWF=$(count_lines "$ALLOW_FILES"); N_MCPF=$(printf '%s\n' "$MCP_ROWS" | awk -F '|' '$4 == "0" { n++ } END { print n + 0 }')
BASHV=${BASH_VERSINFO[0]:-0}
# For case studies: ids from the fixed lists near the top, and counts. Labels go
# in, but only list ids and a number come out of mcp_match.
MCP_MATCH=$(printf '%s' "$MCP_NAMES" | mcp_match)
case "$MCP_MATCH" in *[![:lower:][:digit:]\ \|-]*|'') MCP_MATCH="|0" ;; esac
MCP_KNOWN=${MCP_MATCH%|*}; MCP_OTHER=${MCP_MATCH##*|}
case "$MCP_OTHER" in ''|*[!0-9]*) MCP_OTHER=0 ;; esac
J_IDLE=$(json_list "$IDLE_IDS"); J_MCPC=$(json_tally "$MCP_CLIENT_IDS" "$MCP_TALLY"); J_MCPT=$(json_list "$MCP_TOK_IDS")
J_KNOWN=$(json_list "$MCP_KNOWN"); J_PLACES=$(json_tally "$KEY_PLACE_IDS" "$KEY_PLACES"); J_PROVF=$(json_tally "$PROVIDER_IDS" "$PROV_TALLY")
PAYLOAD="{\"v\":\"1\",\"kind\":\"report\",\"run_id\":\"$RUN_ID\",\"device_id\":\"$DEVICE_ID\",\"script\":\"$VERSION\",\"os\":\"$OSV\",\"arch\":\"$ARCH_ID\",\"model\":\"$MODEL\",\"terminal\":\"$TERMAPP\",\"tmux\":$TMUXED,\"shell\":\"$SHELLNAME\",\"bash\":$BASHV,\"lang\":\"$LANGCODE\",\"via\":\"$VIA\",\"grade\":\"$GRADE\",\"score\":$SCORE,\"agents\":$(json_list "$AGENT_IDS"),\"agents_idle\":$N_IDLE,\"agents_idle_ids\":$J_IDLE,\"mcp_servers\":$N_MCP,\"mcp_configs\":$N_MCPF,\"mcp_token_files\":$N_MCP_TOKEN,\"mcp_clients\":$J_MCPC,\"mcp_token_clients\":$J_MCPT,\"mcp_known\":$J_KNOWN,\"mcp_other\":$MCP_OTHER,\"key_files\":$KEY_FILES,\"key_places\":$J_PLACES,\"key_providers\":$(json_list "$PROV_IDS"),\"provider_files\":$J_PROVF,\"history_keys\":$HIST_KEYS,\"env_files\":$N_ENVF,\"allow_list_files\":$N_ALLOWF,\"allow_list_keys\":$N_ALLOW,\"allow_list_npm\":$N_ALLOW_NPM,\"login_files\":$(json_list "$LOGIN_IDS"),\"ssh_keys\":$N_SSH,\"ssh_no_passphrase\":$N_SSH_OPEN,\"python_envs\":$N_PY,\"litellm_installed\":$N_LITE,\"litellm_found\":$LITELLM_HIT,\"opencode\":$OC,\"railway\":$RW,\"files_found\":$N_FOUND,\"scan_seconds\":$SCAN_SECS,\"all_folders\":$ALL,\"game_played\":$GP,\"game_best\":$GB,\"results_wait_seconds\":$WAIT_SECS}"
send_stats() { # payload [seconds]: POST it with a short timeout, https only when the API is; prints the reply
  if [ "${API#https://}" != "$API" ]; then _pp='=https'; else _pp='=http,https'; fi
  curl -fsS --proto "$_pp" --max-time "${2:-5}" --max-filesize 65536 -X POST -H 'Content-Type: application/json' --data "$1" "$API" 2>/dev/null
}
# The reply holds p, the share of people whose latest run scored lower, n, how
# many people that is, and r, this device's place in line. Only digits are read from it.
PCT=""; PCT_N=""; RANK=""; LINK_RUN_ID=""
if [ "$OFFLINE" -eq 0 ] && command -v curl >/dev/null 2>&1; then
  LINK_RUN_ID=$RUN_ID   # the result link carries the run ID only when a report did
  [ "$TTY" -eq 1 ] && printf '  %sComparing with other AI builders...%s' "$DIM" "$RST"
  _rp=$(send_stats "$PAYLOAD" 3 | head -c 4096 | tr -d ' \n\r\t')
  [ "$TTY" -eq 1 ] && printf '\r%s' "${E}[K"
  _p=$(jnum p "$_rp"); _n=$(jnum n "$_rp"); _rank=$(jnum r "$_rp")
  if [ -n "$_p" ] && [ -n "$_n" ] && [ "${#_n}" -le 9 ] && [ "$_p" -ge 1 ] && [ "$_p" -le 99 ] && [ "$_n" -ge 1 ]; then PCT=$_p; PCT_N=$_n; fi
  case "$_rank" in ""|0*|*[!0-9]*) ;; *) [ "${#_rank}" -le 9 ] && RANK=$_rank ;; esac   # a whole number from 1, or unknown
fi


# ===========================================================================
# The report. Every part is built first, then shown: a summary on a terminal,
# with each section's details a key press away, or every detail with --full or
# when the output isn't a terminal. A saved report always has every detail.
# ===========================================================================
if [ "$PY_HIT" -eq 1 ] || [ "$ANY_MAL" -eq 1 ]; then SEV=$RED
elif [ "$KEY_FILES" -gt 0 ] || [ "$N_ALLOW" -gt 0 ] || [ "$N_MCP_TOKEN" -gt 0 ] || [ "$N_AK" -gt 0 ]; then SEV=$RED
elif [ "$ISSUES" -gt 0 ] || [ "$PARTIAL" -eq 1 ]; then SEV=$YEL
else SEV=$GRN; fi
if [ "$ISSUES" -gt 0 ]; then FIXN="$(plural "$ISSUES" "thing" "things") to fix"
elif [ "$PARTIAL" -eq 1 ]; then FIXN="No findings in the paths checked"
else FIXN="No findings in this scan"; fi
PCT_TXT=""; [ -n "$PCT" ] && PCT_TXT="Better than $PCT% of AI builders who ran Blindspot"
STATS="$(plural "$N_AG" "coding agent" "coding agents"), $N_IDLE not used in 30 days, $(plural "$N_MCP" "MCP server" "MCP servers"), $(plural "$KEY_FILES" "file" "files") with keys in plain text, $(plural "$N_ALLOW" "key" "keys") in allow lists"
upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }
CAPTURE=1; CAP=""
# The first 1,000 are told so, above either header. The place in line itself is never shown.
if { [ -n "$RANK" ] && [ "$RANK" -le 1000 ]; } || { [ -z "$RANK" ] && [ "$EARLY" -eq 1 ]; }; then
  wrap "You're one of the first 1,000 AI builders to run Blindspot." 4 "  ${GOLD}★${RST} " "    " "$B"; blank
fi
_act=""
if [ "$WIPER_HIT" -eq 1 ]; then _act="ACT NOW: REMOVE GH-TOKEN-MONITOR BEFORE YOU REVOKE ANY TOKEN"
elif [ "$ANY_MAL" -eq 1 ] && { [ "$MAL_LOCKONLY" -eq 0 ] || [ "$EXT_HIT" -eq 1 ]; }; then _act="ACT NOW: SIGNS OF $(upper "$MAL_WHAT")"
elif [ "$PY_HIT" -eq 1 ]; then
  _act=""; for _pi in $PY_HITS; do _act="${_act:+$_act AND }$(incident_name "$_pi")"; done
  _act="ACT NOW: SIGNS OF THE $(upper "$_act") MALWARE"
elif [ "$MAL_LOCKONLY" -eq 1 ]; then
  if [ "$N_LOCKPROJ" -eq 1 ]; then _act="ACT NOW IF YOU INSTALLED IT: A LOCKFILE LISTS NPM MALWARE"
  else _act="ACT NOW IF YOU INSTALLED THEM: LOCKFILES LIST NPM MALWARE"; fi
fi
if [ -n "$_act" ]; then
  emit "  ${SEV}▌${RST} ${B}${_act}${RST}"
  if [ -n "$PCT_TXT" ]; then emit "  ${SEV}▌${RST} ${B}${PCT_TXT}.${RST} ${FIXN}."; else emit "  ${SEV}▌${RST} ${FIXN}."; fi
elif [ -n "$PCT_TXT" ]; then
  emit "  ${SEV}▌${RST} ${B}$(upper "$PCT_TXT")${RST}"
  emit "  ${SEV}▌${RST} ${FIXN}."
else
  emit "  ${SEV}▌${RST} ${B}$(upper "$FIXN")${RST}"
fi
HEAD_SHORT=$CAP; CAP=""
wrap "$STATS" 4 "  ${SEV}▌${RST} " "  ${SEV}▌${RST} " "$DIM"
[ "$SCAN_FAILED" -eq 1 ] && wrap "The home folder was not scanned ($SCAN_WHY): project .env files, settings, MCP configs and lockfiles were not read. Sections 2 to 5 cover only the known agent paths." 4 "  ${YEL}▌${RST} " "  ${YEL}▌${RST} " "$YEL"
# Folders the home scan could not enter, so sections 2 to 5 did not read the files in them.
dir_list() { # paths, one a line: the first three as short() shows them, then how many more
  _dl=""; _dn=0
  while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    _dn=$((_dn + 1)); [ "$_dn" -le 3 ] && _dl="${_dl:+$_dl, }$(short "$_d")"
  done <<EOF
$1
EOF
  [ "$_dn" -gt 3 ] && _dl="$_dl and $((_dn - 3)) more"
  printf '%s' "$_dl"
}
if [ "$N_UNREAD_DIRS" -gt 0 ]; then
  if [ "$N_UNREAD_DIRS" -eq 1 ]; then _it="1 folder in your home could not be read, so sections 2 to 5 did not check the files in it"
  else _it="$N_UNREAD_DIRS folders in your home could not be read, so sections 2 to 5 did not check the files in them"; fi
  wrap "$_it: $(dir_list "$UNREAD_DIRS")." 4 "  ${YEL}▌${RST} " "  ${YEL}▌${RST} " "$YEL"
fi
if [ "$N_NL_DIRS" -gt 0 ]; then
  if [ "$N_NL_DIRS" -eq 1 ]; then _it="1 folder has a line break in its name, so sections 2 to 5 did not check the files in it"
  else _it="$N_NL_DIRS folders have a line break in their name, so sections 2 to 5 did not check the files in them"; fi
  wrap "$_it: $(dir_list "$NL_DIRS"), the line break shown as ?." 4 "  ${YEL}▌${RST} " "  ${YEL}▌${RST} " "$YEL"
fi
HEAD_FULL="$HEAD_SHORT$CAP"; CAP=""

section 01 "CODING AGENTS" "$N_AG found, $N_IDLE idle"
if [ "$N_AG" -eq 0 ]; then emit "     No coding agents found."; fi
while IFS='|' read -r n st; do
  [ -n "$n" ] || continue
  case "$st" in
    active) pair "${GRN}●${RST}" "$n" 20 "used in the last 30 days" ;;
    idle)   pair "${YEL}○${RST}" "$n" 20 "${DIM}installed, not used in 30 days${RST}" ;;
    unused) pair "${YEL}○${RST}" "$n" 20 "${DIM}installed, no use recorded${RST}" ;;
    *)      pair "${DIM}•${RST}" "$n" 20 "${DIM}installed${RST}" ;;
  esac
done <<EOF
$AG_ROWS
EOF
if [ "$N_YOLO" -gt 0 ]; then
  blank
  emit "     ${B}Agents set to run commands without asking${RST}"
  while IFS="$TAB" read -r f a st; do
    [ -n "$f" ] || continue
    printf -v nm '%-16s %s' "$a" "$(short "$f")"
    pair "${YEL}!${RST}" "$nm" 46 "$st"
  done <<EOF
$AA_LIST
EOF
  wrap "A prompt injection in anything the agent reads can then run commands on this computer. Turn it off unless the agent runs in a sandbox." 8 "        " "        " "$DIM"
fi
if [ "$N_OLD" -gt 0 ]; then
  blank
  emit "     ${B}Tools with a security fix to install${RST}"
  while IFS="$TAB" read -r nm vs fx hole src; do
    [ -n "$nm" ] || continue
    pair "${YEL}!${RST}" "$nm" 20 "$vs, update to $fx or later"
    wrap "$(printf '%s' "${hole:0:1}" | tr 'a-z' 'A-Z')${hole:1}. $src" 8 "        " "        " "$DIM"
  done <<EOF
$OLD_LIST
EOF
fi

SEC1=$CAP; CAP=""
section 02 "MCP SERVERS" "$(plural "$N_MCP" server servers)"
if [ "$N_MCP" -eq 0 ] && [ "$N_MCP_TOKEN" -eq 0 ]; then emit "     No MCP servers configured."; fi
while IFS='|' read -r who c tok pl f; do
  [ -n "$who" ] || continue
  [ "$pl" = 1 ] && [ "$tok" != 1 ] && continue
  if [ -n "$c" ]; then d=$(plural "$c" server servers); else d="servers configured"; fi
  printf -v nm '%-14s %s' "$who" "$(short "$f")"
  if [ "$tok" = 1 ]; then pair "${RED}✗${RST}" "$nm" 46 "$d, ${RED}token in the file${RST}"
  else pair "${TEAL}•${RST}" "$nm" 46 "$d"; fi
done <<EOF
$MCP_ROWS
EOF
if [ "$N_MCP_CACHE" -gt 0 ]; then
  pair "${DIM}·${RST}" "Plugin folders" 46 "${DIM}$(plural "$N_MCP_CACHE" server servers) in $(plural "$N_MCP_CACHEF" file files), not counted above${RST}"
fi
if [ "$N_AUTO" -gt 0 ]; then
  blank
  emit "     ${B}Project settings that act as soon as the folder is opened${RST}"
  while IFS="$TAB" read -r f w _s n; do
    [ -n "$f" ] || continue
    emit "     ${YEL}!${RST}  $(short "$f")"
    _more=""; [ "${n:-0}" -gt 0 ] && _more=" The same settings are in $(plural "$n" "more folder" "more folders"), such as worktrees."
    wrap "Set to $w.$_more" 8 "        " "        " "$DIM"
  done <<EOF
$AUTO_ROWS
EOF
fi
if [ "$N_LOOK" -gt 0 ]; then
  blank
  emit "     ${B}Files named like the ones worms plant${RST}"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    emit "     ${YEL}!${RST}  $(short "$f")"
    wrap "Named like $(planted_note "$f"), with nothing else of theirs beside it. If you didn't put it there, read it before an agent or editor opens this folder." 8 "        " "        " "$DIM"
  done <<EOF
$WORM_LOOK
EOF
fi
if [ "$N_AK" -gt 0 ]; then
  blank
  emit "     ${B}Files that link to your SSH logins${RST}"
  while IFS= read -r f; do [ -n "$f" ] && emit "     ${RED}✗${RST}  $(short "$f")"; done <<EOF
$AK_LINKS
EOF
  wrap "An agent that edits this file adds a login to this computer. Delete the link." 8 "        " "        " "$RED"
fi

SEC2=$CAP; CAP=""
section 03 "KEYS IN PLAIN TEXT" "$(plural "$KEY_FILES" file files)"
if [ "$KEY_FILES" -eq 0 ]; then
  if [ "$HOME_PARTIAL" -eq 1 ]; then wrap "No AI or cloud keys in shell profiles, history, agent configs or .env files, but some folders in your home were not read." 8 "     ${YEL}!${RST}  " "        "
  else wrap "No AI or cloud keys in shell profiles, history, agent configs or .env files." 8 "     ${GRN}✓${RST}  " "        "; fi
fi
_shown=0
while IFS='|' read -r p f; do
  [ -n "$f" ] || continue
  _shown=$((_shown + 1)); [ "$_shown" -le 20 ] || continue
  pair "${RED}✗${RST}" "$(short "$f")" 44 "$p"
done <<EOF
$KEY_ROWS
EOF
[ "$KEY_FILES" -gt 20 ] && emit "        ${DIM}and $((KEY_FILES - 20)) more${RST}"
if [ -n "$LOGINS" ]; then
  blank
  emit "     ${B}Login files any agent you run can read${RST}"
  wrap "$LOGINS" 8 "        " "        "
fi
if [ "$SESS_TOTAL" -gt 0 ] || [ "$SESS_UNREAD" -ne 0 ] || [ -n "$SESS_SEALED_FOUND" ]; then
  blank
  emit "     ${B}Keys in agent sessions${RST}"
  while IFS='|' read -r a n pv; do
    [ -n "$a" ] || continue
    pair "${RED}✗${RST}" "$a" 20 "$(plural "$n" file files): $pv"
  done <<EOF
$SESS_ROWS
EOF
  if [ "$N_SESS" -gt 0 ]; then
    _cw=0; _shown=0; _nd=0
    while IFS="$(printf '\t')" read -r _n _g; do
      [ -n "$_g" ] || continue
      _nd=$((_nd + 1)); [ "$_nd" -le 20 ] || continue
      _t=$(plural "$_n" file files); [ "${#_t}" -gt "$_cw" ] && _cw=${#_t}
    done <<EOF
$SESS_PLACES
EOF
    _fw=$((80 - 8 - 2 - _cw))
    while IFS="$(printf '\t')" read -r _n _g; do
      [ -n "$_g" ] || continue
      _shown=$((_shown + 1)); [ "$_shown" -le 20 ] || continue
      _g=$(short "$_g")
      if [ "${#_g}" -gt "$_fw" ]; then
        # Shortened in the middle, and never inside a character of more than one byte.
        _hd=$(((_fw - 3) / 2)); _h=${_g:0:_hd}; _e=${_g: -$((_fw - 3 - _hd))}
        while case "$_h" in *[$'\x80'-$'\xbf']) true ;; *) false ;; esac; do _h=${_h%?}; done
        case "$_h" in *[$'\xc0'-$'\xff']) _h=${_h%?} ;; esac
        while case "$_e" in [$'\x80'-$'\xbf']*) true ;; *) false ;; esac; do _e=${_e#?}; done
        _g="$_h...$_e"
      fi
      printf -v _x '%-*s  %*s' "$_fw" "$_g" "$_cw" "$(plural "$_n" file files)"
      emit "        ${DIM}$_x${RST}"
    done <<EOF
$SESS_PLACES
EOF
    [ "$N_PLACES" -gt 20 ] && emit "        ${DIM}and $((N_PLACES - 20)) more${RST}"
    wrap "$(wiper_wait "Treat these keys as exposed and rotate them.")" 8 "        " "        "
  fi
  _all="Install ripgrep, or add --all-sessions, to check all of them."
  if [ "$SESS_NOTRUN" -gt 0 ]; then
    if [ "$SESS_FAIL" -eq 1 ]; then _why="the check could not start"; else _why="this needs perl or ripgrep"; fi
    wrap "$(plural "$SESS_NOTRUN" "agent session file was" "agent session files were") not checked: $_why." 8 "     ${YEL}!${RST}  " "        "
  elif [ "$SESS_DONE" -lt 0 ]; then
    wrap "Agent sessions were partly checked. Add --all-sessions to check all of them." 8 "     ${YEL}!${RST}  " "        "
  elif [ $((SESS_DONE + SESS_UNREAD_FILES)) -lt $((SESS_TOTAL - SESS_ZST)) ]; then
    wrap "Checked the newest $(commas "$SESS_DONE") of $(commas "$SESS_TOTAL") agent session files. $_all" 8 "     ${YEL}!${RST}  " "        "
  elif [ "$N_SESS" -eq 0 ] && [ "$SESS_DONE" -gt 0 ] && [ "$SESS_UNREAD" -eq 0 ] && [ "$SESS_UNREAD_FILES" -eq 0 ]; then
    # The files read, not the compressed ones, which are named below.
    emit "     ${GRN}✓${RST}  No keys in $(plural "$(commas "$SESS_DONE")" "agent session file" "agent session files")."
  fi
  _ur=""
  [ "$SESS_UNREAD" -gt 0 ] && _ur=$(plural "$SESS_UNREAD" "folder" "folders")
  [ "$SESS_UNREAD_FILES" -gt 0 ] && _ur="${_ur:+$_ur and }$(plural "$SESS_UNREAD_FILES" "file" "files")"
  if [ -n "$_ur" ]; then
    wrap "Agent sessions were partly checked: $_ur could not be read." 8 "     ${YEL}!${RST}  " "        "
  elif [ "$SESS_UNREAD" -lt 0 ]; then
    wrap "Agent sessions were partly checked: some files or folders could not be read." 8 "     ${YEL}!${RST}  " "        "
  fi
  [ "$SESS_ZST" -gt 0 ] && wrap "$(plural "$SESS_ZST" "compressed session file was" "compressed session files were") not checked." 8 "     ${YEL}!${RST}  " "        "
  if [ -n "$SESS_SEALED_FOUND" ]; then
    _sn=$(printf '%s\n' "$SESS_SEALED_FOUND" | awk -F '|' '{ s += $2 } END { print s + 0 }')
    _sa=$(printf '%s\n' "$SESS_SEALED_FOUND" | cut -d'|' -f1 | tr '\n' ',' | sed -e 's/,$//' -e 's/,/ and /g')
    if [ "$_sn" -eq 1 ]; then _sv="conversation file is encrypted, so it was"; else _sv="conversation files are encrypted, so they were"; fi
    wrap "$_sn $_sa $_sv not checked." 8 "        " "        " "$DIM"
  fi
fi

SEC3=$CAP; CAP=""
section 04 "KEYS IN CLAUDE CODE ALLOW LISTS" "$(plural "$N_ALLOW" file files)"
if [ "$N_ALLOW" -eq 0 ] && [ "$HOME_PARTIAL" -eq 1 ]; then wrap "No saved commands with keys, but some folders in your home were not read." 8 "     ${YEL}!${RST}  " "        "
elif [ "$N_ALLOW" -eq 0 ]; then emit "     ${GRN}✓${RST}  No saved commands with keys."; fi
while IFS='|' read -r npm f; do
  [ -n "$f" ] || continue
  emit "     ${RED}✗${RST}  $(short "$f")"
  emit "        A saved command contains a key."
  [ "$npm" = 1 ] && wrap "An npm publish from this folder would include it." 8 "        " "        " "$RED"
done <<EOF
$ALLOW_ROWS
EOF

SEC4=$CAP; CAP=""
N_LEAKS=$(($(printf '%s\n' $PY_INCIDENTS | grep -c .) + 2 + N_PLAT))   # the Python incidents, npm, editor extensions and each platform
section 05 "RECENT KEY LEAKS" "$N_LEAKS checked"
# One row per Python incident. cook.pyc, the installed versions and the loader are LiteLLM's. The
# advice under a hit: for a bad package in an environment, don't run Python there; for its temp
# files, the incident's own (data/indicators.tsv); for a version whose malware could not run on this
# OS (data/bad-pypi.tsv), update it.
os_name() { case "$1" in mac) printf macOS ;; linux) printf Linux ;; win) printf Windows ;; *) printf '%s' "$1" ;; esac; }
for _pi in $PY_INCIDENTS; do
  _pl=$(incident_name "$_pi")
  _upd=$(printf '%s' "$PY_UPD" | grep "^$_pi$TAB")
  _do=""
  case " $PY_HITS " in
    *" $_pi "*)
      pair "${RED}✗${RST}" "$_pl" 16 "${RED}signs of the malware found${RST}"
      while IFS="$TAB" read -r _t l; do
        [ "$_t" = "$_pi" ] && [ -n "$l" ] && emit "        $(short "$l")"
      done <<EOF
$LITE_BAD$MARKS
EOF
      [ "$_pi" = litellm ] && [ "$LOADER" -eq 1 ] && emit "        ${RED}A process holds the loader lock. The backdoor may be running now.${RST}"
      printf '%s' "$LITE_BAD" | grep -q "^$_pi$TAB" && _do="Don't run Python or pip in these environments."
      if printf '%s' "$MARKS" | grep -q "^$_pi$TAB" || [ -z "$_do" ]; then _do="${_do:+$_do }$(temp_advice "$_pi")"; fi
      ;;
    *)
      if [ -n "$_upd" ]; then
        pair "${YEL}!${RST}" "$_pl" 16 "${YEL}a bad version to update${RST}"
      elif [ "$_pi" = litellm ] && [ -n "$LITE_PYC" ]; then
        pair "${YEL}!${RST}" "$_pl" 16 "${YEL}possible leftover${RST}"
        while IFS= read -r l; do
          [ -n "$l" ] && emit "        $(short "$l")"
        done <<EOF
$LITE_PYC
EOF
        wrap "A compiled cook file stays behind when cook.py is deleted, which is what the 1.107.0 malware ships. If litellm 1.107.0 was ever installed here, treat this as a hit. Advisory: $(incident_source "$_pi")" 8 "        " "        "
      else
        pair "${GRN}✓${RST}" "$_pl" 16 "no signs in $(plural "$N_PY" "Python environment" "Python environments")"
        [ "$_pi" = litellm ] && [ "$N_LITE" -gt 0 ] && emit "                          ${DIM}installed: $(short "$LITE_VERS")${RST}"
      fi
      ;;
  esac
  if [ -n "$_upd" ]; then
    _oss=""
    while IFS="$TAB" read -r _t _o l; do
      [ -n "$l" ] || continue
      emit "        $(short "$l")"
      case " $_oss " in *" $(os_name "$_o") "*) ;; *) _oss="${_oss:+$_oss and }$(os_name "$_o")" ;; esac
    done <<EOF
$_upd
EOF
    _do="${_do:+$_do }Its malware runs on $_oss only, so it did not run here. Update to a version without it."
  fi
  [ -n "$_do" ] && wrap "$_do Advisory: $(incident_source "$_pi")" 8 "        " "        "
  while IFS="$TAB" read -r _t _un _uv; do
    [ "$_t" = "$_pi" ] && wrap "Your uv cache holds the $_uv package. Clear it with: uv cache clean $_un" 8 "        " "        " "$YEL"
  done <<EOF
$UV_BAD
EOF
done
if [ "$WIPER_HIT" -eq 1 ]; then
  pair "${RED}✗${RST}" "npm malware" 16 "${RED}a wiper is waiting${RST}"
  while IFS= read -r l; do [ -n "$l" ] && emit "        $(short "$l")"; done <<EOF
$WIPER
EOF
  case "$OS" in
    Darwin) _stop="launchctl bootout gui/$(id -u 2>/dev/null)/com.user.gh-token-monitor" ;;
    Linux)  _stop="systemctl --user disable --now gh-token-monitor.service" ;;
    *)      _stop="" ;;
  esac
  wrap "Don't revoke any GitHub token until it is stopped and these files are gone: gh-token-monitor runs a destructive command when the stolen token stops working, and in the TanStack wave it tries to erase the home folder." 8 "        " "        " "$RED"
  wrap "Stop it with ${_stop:+$_stop, then }pkill -f gh-token-monitor, then delete the files above." 8 "        " "        " "$RED"
fi
if [ "$NPM_HIT" -eq 1 ] || [ -n "$PERSIST" ] || [ "$NPM_UPD" -eq 1 ]; then
  if [ "$NPM_HIT" -eq 1 ] || [ -n "$PERSIST" ]; then
    [ "$WIPER_HIT" -eq 1 ] || pair "${RED}✗${RST}" "npm malware" 16 "${RED}signs of the malware found${RST}"
  else
    pair "${YEL}!${RST}" "npm malware" 16 "${YEL}a bad version to update${RST}"
  fi
  while IFS="$TAB" read -r f p t; do
    [ -n "$f" ] || continue
    emit "        $(short "$f")"
    case "$f" in
      *"(npm's download cache)") _w="downloaded into npm's cache" ;;
      */package-lock.json|*/npm-shrinkwrap.json|*/pnpm-lock.yaml|*/yarn.lock|*/bun.lock) _w="listed in this lockfile" ;;
      *) _w="installed" ;;
    esac
    emit "          ${p} ${DIM}($(npm_label "$t")), ${_w}${RST}"
  done <<EOF
$NPM_ROWS
EOF
  while IFS="$TAB" read -r f p; do
    [ -n "$f" ] || continue
    emit "        $(short "$f")"
    emit "          ${p}"
  done <<EOF
$PERSIST
EOF
  for _t in $NPM_TAGS; do wrap "$(incident_line "$_t")" 8 "        " "        " "$DIM"; done
fi
# What of npm's places could not be read: part of its cache, lockfiles, folders the scan could not
# enter. The row is never green over them, and findings above them are not the full list.
_np=""; _nn=0
[ "$NPM_UNREAD" -gt 0 ] && { _np="part of npm's cache"; _nn=1; }
[ "$N_LOCK_UNREAD" -gt 0 ] && { _np="${_np:+$_np|}$(plural "$N_LOCK_UNREAD" lockfile lockfiles)"; _nn=$((_nn + 1)); }
[ "$HOME_PARTIAL" -eq 1 ] && { _np="${_np:+$_np|}some folders in your home"; _nn=$((_nn + 1)); }
case "$_nn" in 2) _np=${_np/|/ and } ;; 3) _np=${_np/|/, }; _np=${_np/|/ and } ;; esac
lock_unread() { while IFS= read -r _f; do [ -n "$_f" ] && emit "        $(short "$_f")"; done <<EOF
$LOCK_UNREAD
EOF
}
if [ "$NPM_HIT" -eq 1 ] || [ -n "$PERSIST" ] || [ "$NPM_UPD" -eq 1 ]; then :
elif [ "$WIPER_HIT" -eq 0 ] && [ -n "$_np" ]; then
  pair "${YEL}!${RST}" "npm malware" 16 "${YEL}not fully checked: $_np could not be read${RST}"
  lock_unread
elif [ "$WIPER_HIT" -eq 0 ]; then
  pair "${GRN}✓${RST}" "npm malware" 16 "none of $(printf '%s\n' "$BAD_NPM" | awk '$2 != "*"' | grep -c .) bad versions or $(printf '%s\n' "$BAD_NPM" | awk '$2 == "*"' | grep -c .) bad packages"
  emit "                          ${DIM}checked $(plural "$N_LOCK" lockfile lockfiles), global installs and npm's cache${RST}"
fi
if [ -n "$_np" ] && { [ "$WIPER_HIT" -eq 1 ] || [ "$NPM_HIT" -eq 1 ] || [ -n "$PERSIST" ] || [ "$NPM_UPD" -eq 1 ]; }; then
  wrap "$(printf '%s' "${_np:0:1}" | tr 'a-z' 'A-Z')${_np:1} could not be read, so this is not the full list." 8 "        " "        " "$YEL"
  lock_unread
fi
if [ "$EXT_HIT" -eq 1 ]; then
  pair "${RED}✗${RST}" "Editor extensions" 16 "${RED}signs of the malware found${RST}"
  while IFS="$TAB" read -r f p t; do
    [ -n "$f" ] || continue
    emit "        $(short "$f")"
    emit "          ${p} ${DIM}($(npm_label "$t")), installed${RST}"
  done <<EOF
$EXT_ROWS
EOF
  while IFS="$TAB" read -r f p; do
    [ -n "$f" ] || continue
    emit "        $(short "$f")"
    emit "          ${p}"
  done <<EOF
$EXT_PERSIST
EOF
  for _t in $EXT_TAGS; do wrap "$(incident_line "$_t")" 8 "        " "        " "$DIM"; done
elif [ -n "$EXT_CHECK" ]; then
  pair "${YEL}!${RST}" "Editor extensions" 16 "${YEL}a startup file to check${RST}"
  while IFS="$TAB" read -r f p; do
    [ -n "$f" ] || continue
    emit "        $(short "$f")"
    emit "          has the name of a file that $p"
  done <<EOF
$EXT_CHECK
EOF
  wrap "No editor extension that shipped malware was found. Open the file and check what it starts: if you did not set it up yourself, treat this machine as compromised." 8 "        " "        "
  for _t in $EXT_CHECK_TAGS; do wrap "$(incident_line "$_t")" 8 "        " "        " "$DIM"; done
elif [ "$EXT_UNREAD" -gt 0 ]; then
  pair "${YEL}!${RST}" "Editor extensions" 16 "${YEL}not fully checked: $(plural "$EXT_UNREAD" "extension folder" "extension folders") could not be read${RST}"
else
  pair "${GRN}✓${RST}" "Editor extensions" 16 "none of $(printf '%s\n' "$BAD_EXT" | awk '$2 != "*"' | grep -c .) bad versions or $(printf '%s\n' "$BAD_EXT" | awk '$2 == "*"' | grep -c .) bad extensions"
  wrap "checked the extension folders of VS Code, Cursor, Windsurf, Devin Desktop, VSCodium and Kiro" 26 "                          " "                          " "$DIM"
fi
# With findings above, a folder that could not be read still has to be said.
if [ "$EXT_UNREAD" -gt 0 ] && { [ "$EXT_HIT" -eq 1 ] || [ -n "$EXT_CHECK" ]; }; then
  if [ "$EXT_UNREAD" -eq 1 ]; then _xm="An extension folder"; else _xm="Some extension folders"; fi
  wrap "$_xm could not be read, so this is not the full list." 8 "        " "        " "$YEL"
fi
while IFS='|' read -r _pid _pnm _pcmd _ppath _pw _padv _psum; do
  [ -n "$_pid" ] || continue
  if [ "$(plat_hit "$_pid")" = 1 ]; then
    pair "${YEL}!${RST}" "$_pnm" 16 "$_pw"
    wrap "$(wiper_wait "$_padv")" 26 "                          " "                          " "$DIM"
  else
    case "$_pw" in *" found") _pw="${_pw% found} not found" ;; *) _pw="not $_pw" ;; esac
    pair "${DIM}·${RST}" "$_pnm" 16 "${DIM}$_pw${RST}"
  fi
done <<EOF
$PLATFORMS
EOF

SEC5=$CAP; CAP=""
heading "WHAT TO DO" "most urgent first"
_i=0
while IFS= read -r t; do
  [ -n "$t" ] || continue
  _i=$((_i + 1)); printf -v _num '%2d' "$_i"
  wrap "$t" 10 "     ${TEAL}${_num}.${RST}  " "          "
done <<EOF
$TODO
EOF
[ "$_i" -gt 0 ] && blank
wrap "Also: set a monthly spend limit on every AI provider key, at the provider." 5 "     " "     "

SEC_TODO=$CAP; CAP=""

# Argus: said once, plainly, tied to what this scan found. Every claim matches
# gird.ai/argus/download and the Argus privacy notice.
BAR="  ${TEAL}▌${RST} "
blank
if [ "$OS" = Darwin ]; then
  if [ "$KEY_FILES" -gt 0 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found $(plural "$KEY_FILES" "file" "files") with keys that any agent you run can read. It can't tell you whether one already did, or what your agents do after you close this window."
  elif [ "$MAL_LOCKONLY" -eq 1 ] && [ "$EXT_HIT" -eq 0 ] && [ "$PY_HIT" -eq 0 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found npm malware listed in a lockfile, with no sign it was installed here. It can't tell you what your agents do after you close this window."
  elif [ "$ANY_MAL" -eq 1 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found signs of $MAL_WHAT. It can't tell you what the malware already took, or what your agents do after you close this window."
  elif [ "$PY_HIT" -eq 1 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found signs of the $PY_SHORT malware. It can't tell you what the malware already took, or what your agents do after you close this window."
  elif [ "$N_IDLE" -gt 0 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="$(plural "$N_IDLE" "agent you haven't used in 30 days is" "agents you haven't used in 30 days are") still installed. A poisoned package can drive an installed agent, and nothing on your Mac would tell you."
  elif [ "$ISSUES" -gt 0 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found $(plural "$ISSUES" "thing" "things") to fix. It can't tell you whether an agent already used what it found, or what your agents do after you close this window."
  elif [ "$PARTIAL" -eq 1 ]; then
    _t="NO FINDINGS IN THE PATHS CHECKED"
    _p1="Nothing turned up in the places this scan could check, and some it could not check in full. The next leak won't wait for you to run a scan."
  else
    _t="NO FINDINGS IN THIS SCAN"
    _p1="Nothing turned up in the places this scan covers, which is not a guarantee. The next leak won't wait for you to run a scan."
  fi
  emit "${BAR}${B}${_t}${RST}"
  wrap "$_p1" 4 "$BAR" "$BAR"
  emit "${BAR}"
  wrap "That's why we built Argus for Mac. It runs quietly in the background and tells you the moment an agent opens a key file or tries to send a key off your Mac. It can also stop terminal agents from reading your keys. Free for individuals, and your code never reaches us." 4 "$BAR" "$BAR"
  emit "${BAR}"
  if [ "$ARCH" = arm64 ]; then
    emit "${BAR}${TEAL}${B}Try it free:${RST} ${B}gird.ai/argus/download${RST}"
    wrap "Apple Silicon, macOS 13 or later, set up in a few minutes. What it sends us: gird.ai/privacy/argus-community" 4 "$BAR" "$BAR" "$DIM"
  else
    wrap "Argus runs on Apple Silicon Macs today. Intel Macs can get notified at gird.ai/argus/download" 4 "$BAR" "$BAR" "$DIM"
  fi
else
  wrap "Built by GIRD. Argus, our free Mac app, shows what AI coding agents actually do: gird.ai/argus" 2 "  " "  " "$DIM"
fi

SEC_ARGUS=$CAP; CAP=""
blank
wrap "Finding nothing does not prove nothing leaked. This shows what could reach your keys, not what your agents did with them." 2 "  " "  " "$DIM"
WSL_NOTE="This ran inside WSL, so files on the Windows side were not checked. Run it in Git Bash, or gird-check.ps1 in PowerShell, to check those."
[ "$WSL" -eq 1 ] && wrap "$WSL_NOTE" 2 "  " "  " "$DIM"
SEC_FOOT=$CAP; CAP=""

# Details for one section: the section, then its fixes.
fixes() {
  [ -n "$1" ] || return 0
  blank
  emit "     ${B}What to do${RST}"
  while IFS= read -r _t; do
    [ -n "$_t" ] && wrap "$_t" 8 "     ${TEAL}•${RST}  " "        "
  done <<EOF
$1
EOF
}
fixes "$FIX1"; DET1="$SEC1$CAP"; CAP=""
fixes "$FIX2"; DET2="$SEC2$CAP"; CAP=""
fixes "$FIX3"; DET3="$SEC3$CAP"; CAP=""
fixes "$FIX4"; DET4="$SEC4$CAP"; CAP=""
fixes "$FIX5"; DET5="$SEC5$CAP"; CAP=""

# The summary: one line per section with the most important finding in it.
cline() { # number mark label detail
  printf -v _cb '%-20s' "$3"
  _room=$((W - 31)); [ "$_room" -lt 16 ] && _room=16
  _cd=$4; [ "${#_cd}" -gt "$_room" ] && _cd="${_cd:0:$((_room - 3))}..."
  emit "   ${TEAL}${B}$1${RST}  $2  ${B}${_cb}${RST}${_cd}"
}
# An update-level incident with a fix of its own has a summary for row 05 (data/incidents.tsv).
UPD_SUM=""
for _t in $NPM_TAGS; do
  [ "$(incident_level "$_t")" = update ] || continue
  _s=$(incident_summary "$_t"); if [ -n "$_s" ]; then UPD_SUM=$_s; break; fi
done
if [ "$N_OLD" -gt 0 ]; then G1="${YEL}!${RST}"; D1="$N_AG found, $(plural "$N_OLD" "security fix" "security fixes") to install"
elif [ "$N_YOLO" -gt 0 ]; then G1="${YEL}!${RST}"; D1="$N_AG found, $N_YOLO set to run commands without asking"
elif [ "$N_AG" -eq 0 ]; then G1="${DIM}·${RST}"; D1="none found"
elif [ "$N_IDLE" -gt 0 ]; then G1="${YEL}○${RST}"; D1="$N_AG found, $N_IDLE idle: $(first_names "$IDLE_NAMES" 2)"
else G1="${GRN}✓${RST}"; D1="$N_AG found, all used in the last 30 days"; fi
if [ "$N_AK" -gt 0 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, $(plural "$N_AK" "file links" "files link") to your SSH logins"
elif [ "$N_MCP_TOKEN" -gt 1 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, tokens in $N_MCP_TOKEN files, like $(short "$MCP_TOK_FIRST")"
elif [ "$N_MCP_TOKEN" -eq 1 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, a token in $(short "$MCP_TOK_FIRST")"
elif [ "$N_AUTO" -gt 0 ]; then G2="${YEL}!${RST}"; D2="$MCP_SUM, $(plural "$N_AUTO_PROJ" "project acts" "projects act") on opening"
elif [ "$N_LOOK" -gt 0 ]; then G2="${YEL}!${RST}"; D2="$MCP_SUM, $(plural "$N_LOOK" "project file" "project files") to read"
elif [ "$HOME_PARTIAL" -eq 1 ]; then G2="${YEL}!${RST}"; D2="$MCP_SUM, but some folders were not read"
elif [ -n "$MCP_ROWS" ]; then G2="${GRN}✓${RST}"; D2="$MCP_SUM, no tokens in their configs"
else G2="${GRN}✓${RST}"; D2="none configured"; fi
if [ "$KEY_FILES" -gt 1 ]; then G3="${RED}✗${RST}"; D3="$KEY_FILES files, like $(short "${KEY_FIRST#*|}") (${KEY_FIRST%%|*})"
elif [ "$KEY_FILES" -eq 1 ]; then G3="${RED}✗${RST}"; D3="$(short "${KEY_FIRST#*|}") holds ${KEY_FIRST%%|*} keys"
elif [ "$N_SESS" -gt 0 ]; then G3="${RED}✗${RST}"; D3="keys in $(plural "$N_SESS" "agent session file" "agent session files"): $(printf '%s' "$SESS_ROWS" | head -n 1 | cut -d'|' -f1)"
elif [ "$SESS_PARTIAL" -eq 1 ]; then G3="${YEL}!${RST}"; D3="none in files; agent sessions partly checked"
elif [ "$N_SSH_OPEN" -gt 0 ]; then G3="${YEL}○${RST}"; D3="none in plain text, but $(plural "$N_SSH_OPEN" "SSH key has" "SSH keys have") no passphrase"
elif [ "$HOME_PARTIAL" -eq 1 ]; then G3="${YEL}!${RST}"; D3="none found, but some folders were not read"
else G3="${GRN}✓${RST}"; D3="no AI or cloud keys in plain text"; fi
if [ "$N_ALLOW" -eq 0 ] && [ "$HOME_PARTIAL" -eq 1 ]; then G4="${YEL}!${RST}"; D4="none found, but some folders were not read"
elif [ "$N_ALLOW" -eq 0 ]; then G4="${GRN}✓${RST}"; D4="no saved commands with keys"
elif [ "$N_ALLOW_NPM" -gt 0 ] && [ "$N_ALLOW" -eq 1 ]; then G4="${RED}✗${RST}"; D4="1 saved key, and an npm publish would ship it"
elif [ "$N_ALLOW_NPM" -gt 0 ]; then G4="${RED}✗${RST}"; D4="$N_ALLOW saved keys, $N_ALLOW_NPM that an npm publish would ship"
elif [ "$N_ALLOW" -eq 1 ]; then G4="${RED}✗${RST}"; D4="a saved key in $(short "$ALLOW_FIRST")"
else G4="${RED}✗${RST}"; D4="saved keys in $N_ALLOW files"; fi
if [ "$WIPER_HIT" -eq 1 ]; then G5="${RED}✗${RST}"; D5="gh-token-monitor: stop it before revoking tokens"
elif [ "$ANY_MAL" -eq 1 ] && [ "$PY_HIT" -eq 1 ]; then G5="${RED}✗${RST}"; D5="$MAL_SHORT and $PY_SHORT malware found. Act now"
elif [ "$MAL_LOCKONLY" -eq 1 ] && [ "$EXT_HIT" -eq 0 ]; then G5="${RED}✗${RST}"; D5="npm malware in a lockfile: act if installed"
elif [ "$ANY_MAL" -eq 1 ]; then G5="${RED}✗${RST}"; D5="signs of $MAL_WHAT. Act now"
elif [ "$PY_HIT" -eq 1 ]; then G5="${RED}✗${RST}"; D5="signs of the $PY_SHORT malware. Act now"
elif [ -n "$UPD_SUM" ]; then G5="${YEL}!${RST}"; D5=$UPD_SUM
elif [ -n "$LITE_PYC" ]; then G5="${YEL}!${RST}"; D5="possible LiteLLM leftover: check cook.pyc"
elif [ -n "$EXT_CHECK" ]; then G5="${YEL}!${RST}"; D5="a startup file to check, see section 5"
elif [ "$NPM_UPD" -eq 1 ] && [ "$PY_UPD_HIT" -eq 1 ]; then G5="${YEL}!${RST}"; D5="npm and Python packages to update, see section 5"
elif [ "$NPM_UPD" -eq 1 ]; then G5="${YEL}!${RST}"; D5="an npm package to update, see section 5"
elif [ "$PY_UPD_HIT" -eq 1 ]; then G5="${YEL}!${RST}"; D5="a Python package to update, see section 5"
elif [ "$N_PLAT_FOUND" -ge 2 ]; then
  G5="${YEL}!${RST}"; _l=""; _i=0
  while IFS='|' read -r _pid _pnm _rest; do
    [ "$(plat_hit "$_pid")" = 1 ] || continue
    _i=$((_i + 1)); if [ "$_i" -eq 1 ]; then _l=$_pnm; elif [ "$_i" -eq "$N_PLAT_FOUND" ]; then _l="$_l and $_pnm"; else _l="$_l, $_pnm"; fi
  done <<EOF
$PLATFORMS
EOF
  if [ "$N_PLAT_FOUND" -ge 3 ]; then D5="$_l found: rotate keys"; else D5="$_l found: rotate their keys"; fi
elif [ "$N_PLAT_FOUND" -eq 1 ]; then
  G5="${YEL}!${RST}"
  while IFS='|' read -r _pid _pnm _pcmd _ppath _pw _padv _psum; do [ "$(plat_hit "$_pid")" = 1 ] && D5=$_psum; done <<EOF
$PLATFORMS
EOF
# A partial check comes after every finding someone has to act on, and before the green line.
elif [ "$N_LOCK_UNREAD" -gt 0 ]; then G5="${YEL}!${RST}"; D5="npm packages not fully checked: files unreadable"
elif [ "$NPM_UNREAD" -gt 0 ]; then G5="${YEL}!${RST}"; D5="npm packages not fully checked: cache unreadable"
elif [ "$EXT_UNREAD" -gt 0 ]; then G5="${YEL}!${RST}"; D5="extensions not fully checked: folder unreadable"
elif [ "$HOME_PARTIAL" -eq 1 ]; then G5="${YEL}!${RST}"; D5="none found, but some folders were not read"
else G5="${GRN}✓${RST}"; D5="none of the $N_LEAKS recent leaks or malware it checks"; fi
blank
cline 01 "$G1" "Coding agents" "$D1"
cline 02 "$G2" "MCP servers" "$D2"
cline 03 "$G3" "Keys in plain text" "$D3"
cline 04 "$G4" "Allow lists" "$D4"
cline 05 "$G5" "Recent leaks" "$D5"
if [ "$ISSUES" -gt 0 ]; then
  blank
  wrap "$(printf '%s' "$TODO" | head -n 1)" 14 "   ${B}First fix:${RST} " "              "
fi
# Argus in two lines, with the same claims as the full report.
if [ "$OS" = Darwin ]; then
  if [ "$ARCH" = arm64 ]; then _how="Free for individuals: gird.ai/argus/download"
  else _how="It runs on Apple Silicon Macs today: gird.ai/argus/download"; fi
  if [ "$PY_HIT" -eq 1 ] || [ "$ANY_MAL" -eq 1 ] || [ "$KEY_FILES" -gt 0 ]; then _lead="This scan is a snapshot."
  elif [ "$N_IDLE" -gt 0 ]; then _lead="A poisoned package can drive an agent you no longer use."
  elif [ "$ISSUES" -gt 0 ]; then _lead="This scan is a snapshot."
  else _lead="The next leak won't wait for a scan."; fi
  blank
  wrap "$_lead Argus for Mac tells you the moment an agent opens a key file or tries to send a key off your Mac. $_how" 4 "$BAR" "$BAR"
else
  blank
  wrap "Built by GIRD. Argus, our free Mac app, shows what AI coding agents actually do: gird.ai/argus" 2 "  " "  " "$DIM"
fi
if [ "$ISSUES" -eq 0 ]; then
  blank
  wrap "Finding nothing does not prove nothing leaked. This shows what could reach your keys, not what your agents did with them." 2 "  " "  " "$DIM"
fi
if [ "$WSL" -eq 1 ]; then blank; wrap "$WSL_NOTE" 2 "  " "  " "$DIM"; fi
SUMMARY=$CAP; CAP=""; CAPTURE=0

REPORT="$REPORT$HEAD_FULL$SEC1$SEC2$SEC3$SEC4$SEC5$SEC_TODO$SEC_ARGUS$SEC_FOOT"
if [ "$COMPACT" -eq 1 ]; then printf '%s' "$HEAD_SHORT$SUMMARY"
else printf '%s' "$HEAD_FULL$SEC1$SEC2$SEC3$SEC4$SEC5$SEC_TODO$SEC_ARGUS$SEC_FOOT"; fi

# ---------------------------------------------------------------------------
# What next: the certificate first, then details, save and Argus. One key each,
# nothing happens unasked.
# ---------------------------------------------------------------------------
# u is the run ID, so a share from the certificate can be matched to its run, r the
# early rank, sk the SSH private keys and hk the shell history files with keys, nm npm malware,
# py a Python incident other than LiteLLM, ex malware in an editor extension and wp
# gh-token-monitor, so the page never says to rotate a token while it is there.
card_url() {
  printf '%s/blindspot/card/#v=2&s=%s&g=%s&a=%s&i=%s&m=%s&mt=%s&k=%s&p=%s&al=%s&an=%s&ll=%s&lf=%s&sp=%s&d=%s&pc=%s&pn=%s&u=%s&r=%s&sk=%s&hk=%s&ag=%s&nm=%s&py=%s&ex=%s&wp=%s' \
    "$WEB" "$SCORE" "$GRADE" "$N_AG" "$N_IDLE" "$N_MCP" "$N_MCP_TOKEN" "$KEY_FILES" "$(printf '%s' "$PROV_IDS" | tr ' ' '.')" \
    "$N_ALLOW" "$N_ALLOW_NPM" "$LITELLM_HIT" "$N_LOGIN" "$N_SSH_OPEN" "$(date +%Y-%m-%d)" "$PCT" "$PCT_N" \
    "$LINK_RUN_ID" "$RANK" "$N_SSH" "$HIST_KEYS" "$(printf '%s' "$AGENT_IDS" | tr ' ' '.')" "$MAL_HIT" "$PY_OTHER" "$EXT_HIT" "$WIPER_HIT"
}
# Windows' default browser, from Git Bash or WSL. cmd.exe would read each & in the
# link as a new command, so they are escaped as ^&. explorer.exe reports failure
# even when it opens the page, so its exit code is not used.
win_open() {
  if command -v cmd.exe >/dev/null 2>&1; then
    ( cd / 2>/dev/null; MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd.exe /d /c start "" "${1//&/^&}" ) >/dev/null 2>&1 && return 0
  fi
  if command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$1" >/dev/null 2>&1; return 0; fi
  return 1
}
open_url() {
  [ -n "${GIRD_CHECK_NO_OPEN:-}" ] && return 1
  if [ "$OS" = Darwin ] && command -v open >/dev/null 2>&1; then open "$1" >/dev/null 2>&1 && return 0; fi
  if [ "$WIN" -eq 1 ]; then win_open "$1"; return; fi
  if [ "$WSL" -eq 1 ]; then
    if command -v wslview >/dev/null 2>&1; then wslview "$1" >/dev/null 2>&1 && return 0; fi
    if command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$1" >/dev/null 2>&1; return 0; fi
    win_open "$1" && return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1 & return 0; fi
  return 1
}
do_save() {
  _dir=$(pwd); [ -w "$_dir" ] || _dir=$H
  _out="$_dir/gird-ai-key-check-$(date +%Y%m%d-%H%M%S).txt"
  if ( umask 077; set -C; printf '%s' "$REPORT" | sed "s/${E}\[[0-9;]*m//g" > "$_out" ) 2>/dev/null; then
    ACT_SAVED=1
    printf '  %s✓ Saved%s %s\n  %sIt lists file paths, not keys. Delete it when you are done.%s\n' "$GRN" "$RST" "$_out" "$DIM" "$RST"
  else
    printf '  Could not save to %s\n' "$_out"
  fi
}
do_card() {
  _u=$(card_url); ACT_CARD=1
  if open_url "$_u"; then printf '  %s✓ Opened your result in the browser.%s\n' "$GRN" "$RST"; else printf '  Open your result:\n'; fi
  printf '  %s%s%s\n' "$DIM" "$_u" "$RST"
  if [ -n "$LINK_RUN_ID" ]; then
    printf '  %sThe link carries only counts and a random run ID, after the #, which browsers never send.%s\n' "$DIM" "$RST"
    printf '  %sIf you press share there, the page sends back that ID, the button and the kind of result.%s\n' "$DIM" "$RST"
  else
    printf '  %sThe link carries only your counts, after the #, which browsers never send to a server.%s\n' "$DIM" "$RST"
  fi
}
do_argus() {
  _u="$WEB/argus/download/?ref=check"; ACT_ARGUS=1
  if open_url "$_u"; then printf '  %s✓ Opened the Argus download page.%s\n' "$GRN" "$RST"; else printf '  Get Argus: %s\n' "$_u"; fi
}

ACT_SAVED=0; ACT_CARD=0; ACT_ARGUS=0; MENU_SHOWN=0; MENU_T0=$SECONDS
[ "$SAVE" -eq 1 ] && do_save
if [ "$TTY" -eq 1 ] && [ -t 0 ]; then
  MENU_SHOWN=1
  drain_keys
  if [ -n "$PCT" ]; then HERO="Press ENTER to see how you rank and help spread awareness"
  else HERO="Press ENTER to get your AI Exposure Check and help spread awareness"; fi
  HINT="1-5 details   s save"; [ "$OS" = Darwin ] && HINT="$HINT   a Argus"; HINT="$HINT   q quit"
  _keys='ENTER, 1-5, s, a or q'; [ "$OS" = Darwin ] || _keys='ENTER, 1-5, s or q'
  show_menu() { printf '\n  %s%s▶ %s%s\n    %s%s%s  ' "$GOLD" "$B" "$HERO" "$RST" "$DIM" "$HINT" "$RST"; }
  show_menu
  _hint=0
  while :; do
    read_key
    [ "$OS" = Darwin ] || case "$RK" in 97|65) RK=0 ;; esac
    case "$RK" in
      10|13|99|67) printf '\n'; do_card ;;
      49) printf '1\n'; printf '%s' "$DET1" ;;
      50) printf '2\n'; printf '%s' "$DET2" ;;
      51) printf '3\n'; printf '%s' "$DET3" ;;
      52) printf '4\n'; printf '%s' "$DET4" ;;
      53) printf '5\n'; printf '%s' "$DET5" ;;
      115|83) printf 's\n'; do_save ;;
      97|65)  printf 'a\n'; do_argus ;;
      113|81|"") printf 'q\n'; break ;;
      *) # any other key, like the rest of an arrow key: hint once, then keep waiting
         [ "$_hint" -eq 0 ] && printf '%s(%s)%s ' "$DIM" "$_keys" "$RST"
         _hint=1; continue ;;
    esac
    _hint=0
    show_menu
  done
else
  printf '\n  Your AI Exposure Check: %s\n' "$(card_url)"
  [ "$OS" = Darwin ] && printf '  Try Argus free: %s/argus/download/\n' "$WEB"
fi
# What people did at the end, for the same research: one more small event.
ACT_PID=""
if [ "$OFFLINE" -eq 0 ] && [ "$MENU_SHOWN" -eq 1 ] && command -v curl >/dev/null 2>&1; then
  send_stats "{\"v\":\"1\",\"kind\":\"actions\",\"run_id\":\"$RUN_ID\",\"device_id\":\"$DEVICE_ID\",\"saved\":$ACT_SAVED,\"card\":$ACT_CARD,\"argus\":$ACT_ARGUS,\"menu_seconds\":$((SECONDS - MENU_T0))}" >/dev/null &
  ACT_PID=$!
fi
# Let it finish sending; curl gives up after 5 seconds.
[ -n "$ACT_PID" ] && wait "$ACT_PID" 2>/dev/null
printf '\n'
