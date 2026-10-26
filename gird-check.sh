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
  # Root says how long the run has: the session check stops at three quarters of it, so what was
  # found reaches root, with the sessions partly checked, instead of the run being stopped whole.
  ACCT_END=""; case "${GIRD_CHECK_ACCOUNT_SECONDS:-}" in ''|*[!0-9]*) ;; *) ACCT_END=$((SECONDS + GIRD_CHECK_ACCOUNT_SECONDS * 3 / 4)) ;; esac
  exec 3>&1 >/dev/null 2>&1 </dev/null
  cd "${HOME:-/}" 2>/dev/null || cd / || exit 13
fi
VERSION=1
WEB=${GIRD_CHECK_WEB:-https://gird.ai}   # the overrides here are for testing
API=${GIRD_CHECK_API:-$WEB/api/check}

H=${HOME:-}
if [ -z "$H" ] || [ ! -d "$H" ]; then echo "HOME is not set."; exit 1; fi
# A trailing / would put // in every path, and the checks that tell your own files from a project's
# compare against "$H/": it comes off. A HOME that is a link is followed by the home scan (find -H).
while [ "${#H}" -gt 1 ] && [ "${H%/}" != "$H" ]; do H=${H%/}; done
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
  APP_DEVIN=""   # Devin Desktop's Windows install folder is not documented; ~/.codeium/windsurf finds it
  GOOSE_CFG="$WAPP/Block/goose/config"; GOOSE_DATA="$WAPP/Block/goose/data"; GOOSE_STATE=$GOOSE_DATA
  # Goose keeps its data and state under GOOSE_PATH_ROOT instead when that is an absolute path
  # (crates/goose/src/config/paths.rs).
  case "${GOOSE_PATH_ROOT:-}" in [A-Za-z]:[\\/]*) _gr=$(winpath "$GOOSE_PATH_ROOT"); GOOSE_DATA="${_gr%/}/data"; GOOSE_STATE="${_gr%/}/state" ;; esac
  PSRL="$WAPP/Microsoft/Windows/PowerShell/PSReadLine"
else
  # On Linux the editors and Claude Desktop (Electron apps) keep their folders in XDG_CONFIG_HOME when
  # it is an absolute path, and data/sessions.tsv's {AS} lines read them there.
  if [ "$OS" = Darwin ]; then AS="$H/Library/Application Support"
  else case "${XDG_CONFIG_HOME:-}" in /*) AS=${XDG_CONFIG_HOME%/} ;; *) AS="$H/.config" ;; esac; fi
  APP_CLAUDE=/Applications/Claude.app; APP_CURSOR=/Applications/Cursor.app
  APP_WINDSURF=/Applications/Windsurf.app; APP_ANTIGRAVITY=/Applications/Antigravity.app
  APP_DEVIN=/Applications/Devin.app   # Windsurf's name since 2 June 2026
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
# file is not read and is counted, one line each in FLEET_NR, as not checked. Agents installed in
# /Applications and the shared temp folder are the Mac's, checked once by root, never as an account's.
# Shared install folders it reads (npm's global folders outside the home, shared Python, Cursor's
# version) count on every account's row, as docs/fleet.md says.
FLEET_NR=""; FLEET_MAX=16777216; FLEET_PROT=ok
if [ "$ACCTRUN" -eq 1 ]; then
  APP_CLAUDE=""; APP_CURSOR=""; APP_WINDSURF=""; APP_DEVIN=""; APP_ANTIGRAVITY=""
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
# Breaks text at the last blank before the width, as fold -s does, but never inside a word: a link
# longer than the line stays whole on a line of its own, so it can still be copied.
wrap() {
  _w=$((W - $2 - 3)); [ "$_w" -lt 20 ] && _w=20
  _folded=$(printf '%s\n' "$1" | LC_ALL=C awk -v w="$_w" '
    function lastblank(s,   k, x) { for (k = length(s); k > 0; k--) { x = substr(s, k, 1); if (x == " " || x == "\t") return k }; return 0 }
    { buf = ""; n = length($0)
      for (i = 1; i <= n; i++) {
        ch = substr($0, i, 1); skip = 0
        while (length(buf) + 1 > w) {
          j = lastblank(buf)
          if (j > 0) { print substr(buf, 1, j); buf = substr(buf, j + 1) }
          else { if (buf != "" && (ch == " " || ch == "\t")) { print buf; buf = ""; skip = 1 }; break }
        }
        if (!skip) buf = buf ch
      }
      print buf }' | sed 's/[[:space:]]*$//')
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
# pair GLYPH NAME NAME_WIDTH DETAIL: one aligned row; long names push detail down. A detail longer
# than the line wraps under itself when it is plain or one colour throughout (wrap keeps the colour).
pair() {
  _pv=$4; _pcol=""; _pwrap=0
  if [ -n "$RST" ]; then for _c in "$RST" "$B" "$DIM" "$RED" "$GRN" "$YEL" "$TEAL" "$GOLD"; do _pv=${_pv//"$_c"/}; done; fi
  if [ "${#_pv}" -gt $((W - $3 - 10)) ]; then
    if [ "$4" = "$_pv" ]; then _pwrap=1
    else for _c in "$RED" "$GRN" "$YEL" "$DIM" "$TEAL"; do [ -n "$_c" ] && [ "$4" = "$_c$_pv$RST" ] && { _pwrap=1; _pcol=$_c; }; done; fi
  fi
  _pad=$(printf '%*s' $(($3 + 10)) '')
  if [ "${#2}" -gt "$3" ]; then
    emit "     $1  $2"
    if [ "$_pwrap" -eq 1 ]; then wrap "$_pv" $(($3 + 10)) "$_pad" "$_pad" "$_pcol"; else emit "$_pad$4"; fi
  else
    printf -v _x '%-*s' "$3" "$2"
    if [ "$_pwrap" -eq 1 ]; then wrap "$_pv" $(($3 + 10)) "     $1  $_x  " "$_pad" "$_pcol"; else emit "     $1  $_x  $4"; fi
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
# Below 1,000 AI builders it shows nothing: a line above the header says you're
# one of the first 1,000 instead. The place in line itself is never shown.
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
ALL_KEYS='sk-ant-[A-Za-z0-9_-]{90,}|sk-or-v1-[a-f0-9]{64}|sk-proj-[A-Za-z0-9_-]{120,}|sk-proj-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}([^A-Za-z0-9_-]|$)|sk-None-[A-Za-z0-9_-]{120,}|sk-None-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}([^A-Za-z0-9_-]|$)|sk-svcacct-[A-Za-z0-9_-]{60,}|sk-svcacct-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}([^A-Za-z0-9_-]|$)|sk-admin-[A-Za-z0-9_-]{120,}|(^|[^A-Za-z0-9-])sk-[A-Za-z0-9]{48}([^A-Za-z0-9]|$)|(^|[^A-Za-z0-9+/_-])AIza[0-9A-Za-z_-]{35}|(^|[^A-Za-z0-9])AQ\.[A-Za-z0-9_-]{40,}|gsk_[A-Za-z0-9]{52}|xai-[A-Za-z0-9]{64,}|(^|[^A-Za-z0-9_])hf_[A-Za-z0-9]{34,40}([^A-Za-z0-9_]|$)|pplx-[A-Za-z0-9]{40,52}|(^|[^A-Za-z0-9+/_-])r8_[A-Za-z0-9]{37}|(^|[^A-Za-z0-9])(AKIA|ASIA)[A-Z0-9]{16}([^A-Z0-9]|$)|ABSKQmVkcm9ja0FQSUtleS[A-Za-z0-9+/]{60,}|bedrock-api-key-YmVkcm9jay5hbWF6b25hd3MuY29t[A-Za-z0-9+/=]{144}|gh[pour]_[A-Za-z0-9]{36}|(^|[^A-Za-z0-9_])ghs_[A-Za-z0-9]{36}([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])ghs_[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}|npm_[A-Za-z0-9]{36}'
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
# Agent sessions and JSON configs, where a key often follows an escape such as \n: a backslash escape
# also counts as the boundary in front of a key, in every file the checks read.
TR_KEYS=$(printf '%s' "$ALL_KEYS" | sed 's/(^|\[^\([^]]*\)\])/(^|[^\1]|\\\\[ntr"])/g')

# A secret written as a value: KEY=value in a command, or "token": "value" in a config.
P_ASSIGN='[A-Z][A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*=[^[:space:]"$\\]{12,}'
P_JSONSECRET='"([A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*|apiKey|api_key|accessToken|access_token|authToken|token|secret)"[[:space:]]*:[[:space:]]*"[^"$<{][^"]{11,}"'
P_TOMLSECRET='[A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*[[:space:]]*=[[:space:]]*"[^"$<{][^"]{11,}"'
P_PLACEHOLDER='your|xxxx|here|example|placeholder|changeme|dummy|<|[$][{]'

providers_in() {
  grep -aoE "$TR_KEYS" "$1" 2>/dev/null | awk "$PROV_AWK"'
    { p = prov($0); if (p == "") next
      if (!(p in seen)) { seen[p] = 1; out = out (out == "" ? "" : ", ") p } }
    END { printf "%s", out }'
}
# Print the files in a newline list that contain a match, in order, with one grep pass.
files_matching() { # pattern; list on stdin
  tr '\n' '\0' | xargs -0 grep -alE "$1" 2>/dev/null
}
inline_secret() {
  grep -aoE "$TR_KEYS|$P_JSONSECRET|$P_TOMLSECRET" "$1" 2>/dev/null | grep -viE "$P_PLACEHOLDER" | grep -q .
}
command_secret() {
  grep -aoE "$TR_KEYS|$P_ASSIGN" "$1" 2>/dev/null | grep -viE "$P_PLACEHOLDER" | grep -q .
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
.vscode/setup.mjs
.claude/execution.js
.claude/index.js'
PLANTED_ERE='\.claude/router_runtime\.js|\.vscode/router_runtime\.js|\.claude/setup\.mjs|\.claude/math_init\.js|\.vscode/setup\.mjs|\.claude/execution\.js|\.claude/index\.js'
PLANTED_ALONE='.claude/router_runtime.js
.vscode/router_runtime.js
.claude/math_init.js'
WORM_RUN_ALONE='\.(claude|vscode)[/\\]+(router_runtime\.js|math_init\.js)'
WORM_RUN_WEAK='\.(claude|vscode)[/\\]+(setup\.mjs|execution\.js|index\.js)'
planted_note() { case "$1" in */.claude/router_runtime.js) printf '%s' 'a file the TanStack and Mini Shai-Hulud worms plant' ;; */.vscode/router_runtime.js) printf '%s' 'a file the TanStack worm plants' ;; */.claude/setup.mjs) printf '%s' 'a file the TanStack, keyv and Mini Shai-Hulud worms plant' ;; */.claude/math_init.js) printf '%s' 'a file the keyv worm plants' ;; */.vscode/setup.mjs) printf '%s' 'a file the TanStack, keyv and Mini Shai-Hulud worms plant' ;; */.claude/execution.js) printf '%s' 'a file the Mini Shai-Hulud worm plants' ;; */.claude/index.js) printf '%s' 'a file the AntV wave plants' ;; esac; }
planted_sha() { case "$1" in */.claude/setup.mjs) printf '%s' 'fd3ca4007b225fdf8de7af4345a19179d5efa8c4bb9205f88cda806e5684b1eb 54dc7ea54a1317cca0e890a2770630cf7fa6c97813e0cb9d2caa93012b350668 2258284d65f63829bd67eaba01ef6f1ada2f593f9bbe41678b2df360bd90d3df 4066781fa830224c8bbcc3aa005a396657f9c8f9016f9a64ad44a9d7f5f45e34' ;; */.vscode/setup.mjs) printf '%s' 'fd3ca4007b225fdf8de7af4345a19179d5efa8c4bb9205f88cda806e5684b1eb 54dc7ea54a1317cca0e890a2770630cf7fa6c97813e0cb9d2caa93012b350668 2258284d65f63829bd67eaba01ef6f1ada2f593f9bbe41678b2df360bd90d3df 4066781fa830224c8bbcc3aa005a396657f9c8f9016f9a64ad44a9d7f5f45e34' ;; */.claude/execution.js) printf '%s' 'eb6eb4154b03ec73218727dc643d26f4e14dfda2438112926bb5daf37ae8bcdb 6f933d00b7d05678eb43c90963a80b8947c4ae6830182f89df31da9f568fea95 80a3d2877813968ef847ae73b5eeeb70b9435254e74d7f07d8cf4057f0a710ac' ;; */.claude/index.js) printf '%s' 'a68dd1e6a6e35ec3771e1f94fe796f55dfe65a2b94560516ff4ac189390dfa1c' ;; esac; }
WORM_REF_NOTE='runs a file a worm plants'
# <<< planted
# Agents set to run commands without asking (data/auto-approve.tsv), read in section 1.
# >>> auto-approve: generated from data/auto-approve.tsv by tools/gen.sh. Edit that file, then run it.
AA_TABLE="Claude Code|all|${CLAUDE_CONFIG_DIR:-$H/.claude}/settings.json|bypassPermissions|\"permissions\": {\"defaultMode\": \"bypassPermissions\"
Codex|all|${CODEX_HOME:-$H/.codex}/config.toml|never asks, full access|approval_policy = \"never\"|sandbox_mode = \"danger-full-access\"|!default_permissions
Codex|all|${CODEX_HOME:-$H/.codex}/config.toml|never asks, full access profile|approval_policy = \"never\"|default_permissions = \":danger-full-access\"
Codex|all|{PROJECT}/.codex/config.toml|never asks, full access, when the project is trusted|approval_policy = \"never\"|sandbox_mode = \"danger-full-access\"|!default_permissions
Codex|all|{PROJECT}/.codex/config.toml|never asks, full access profile, when the project is trusted|approval_policy = \"never\"|default_permissions = \":danger-full-access\"
VS Code Copilot|all|$AS/Code/User/settings.json|chat.tools.global.autoApprove|\"chat.tools.global.autoApprove\": true
VS Code Copilot|all|$AS/Code/User/settings.json|chat.permissions.default: autoApprove|\"chat.permissions.default\": \"autoApprove\"
VS Code Copilot|all|$AS/Code/User/settings.json|chat.permissions.default: autopilot|\"chat.permissions.default\": \"autopilot\"
Claude Code|all|$AS/Code/User/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true
Claude Code|all|$AS/Cursor/User/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true
VS Code Copilot|all|$AS/Code/User/profiles/*/settings.json|chat.permissions.default: autoApprove|\"chat.permissions.default\": \"autoApprove\"
VS Code Copilot|all|$AS/Code/User/profiles/*/settings.json|chat.permissions.default: autopilot|\"chat.permissions.default\": \"autopilot\"
Claude Code|all|$AS/Code/User/profiles/*/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true
VS Code Copilot|all|$AS/Code - Insiders/User/settings.json|chat.tools.global.autoApprove|\"chat.tools.global.autoApprove\": true
VS Code Copilot|all|$AS/Code - Insiders/User/settings.json|chat.permissions.default: autoApprove|\"chat.permissions.default\": \"autoApprove\"
VS Code Copilot|all|$AS/Code - Insiders/User/settings.json|chat.permissions.default: autopilot|\"chat.permissions.default\": \"autopilot\"
Claude Code|all|$AS/Code - Insiders/User/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true
VS Code Copilot|all|$AS/Code - Insiders/User/profiles/*/settings.json|chat.permissions.default: autoApprove|\"chat.permissions.default\": \"autoApprove\"
VS Code Copilot|all|$AS/Code - Insiders/User/profiles/*/settings.json|chat.permissions.default: autopilot|\"chat.permissions.default\": \"autopilot\"
Claude Code|all|$AS/Code - Insiders/User/profiles/*/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true
Claude Code|all|$AS/Cursor/User/profiles/*/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true"
AA_PROJECT='.codex/config.toml'
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
  # A .claude or .vscode folder that is a link (not ~/.vscode, which the scan skips) is read through:
  # sh prints "S path" for each file in it the scan would read there, settings, tasks or planted, and
  # for one it can't enter, a line in find's own words, so it is named as a folder not read.
  _pc=""; _pv=""
  while IFS= read -r _pp; do case "$_pp" in .claude/*) _pc="$_pc ${_pp#.claude/}" ;; .vscode/*) _pv="$_pv ${_pp#.vscode/}" ;; esac; done <<EOF
$PLANTED
EOF
  # shellcheck disable=SC2016  # $d and the names are for the sh that find starts
  _ld='for d; do case "${d##*/}" in .claude) n="settings.json settings.local.json $BS_PC" ;; *) n="tasks.json settings.json $BS_PV" ;; esac
    if [ -d "$d" ] && [ ! -x "$d" ]; then printf "find: %s: Permission denied\n" "$d" >&2; continue; fi
    for f in $n; do if [ -e "$d/$f" ] || [ -L "$d/$f" ]; then printf "S %s\n" "$d/$f"; fi; done; done'
  if find /dev/null -maxdepth 0 -ilname x >/dev/null 2>&1; then
    _lk=(-ilname '*authorized_keys' -exec printf 'L %s\n' {} +); _ls=(-exec printf 'S %s\n' {} +); _lx=(-exec sh -c "$_ld" sh {} +)
  else _lk=(-exec printf 'L %s\n' {} \;); _ls=(-exec printf 'S %s\n' {} \;); _lx=(-exec sh -c "$_ld" sh {} \;); fi
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
  BS_PC=$_pc BS_PV=$_pv find -H "$H" -maxdepth 6 \( -type d -name "*$_nl*" -prune -exec sh -c 'printf "N %s\n" "$(printf "%s" "$1" | tr "\n" "?")"' sh {} \; \) -o \
    \( -type d \( "$@" \) -prune \) -o \
    \( -type d -name site-packages -print -prune \) -o \
    \( -type f \( -name .env -o -name '.env.*' -o -name .envrc -o -name .mcp.json -o -name pyvenv.cfg \
       -o -path '*/.claude/settings.local.json' -o -path '*/.claude/settings.json' \
       -o -path '*/.cursor/mcp.json' -o -path '*/.vscode/mcp.json' -o -path '*/.vscode/tasks.json' "${_pf[@]}" \
       -o -name package-lock.json -o -name npm-shrinkwrap.json -o -name pnpm-lock.yaml -o -name yarn.lock -o -name bun.lock \
       -o -name .aider.chat.history.md -o -name .aider.input.history -o -path '*/.vscode/settings.json' "${_aa[@]}" \) -print \) -o \
    \( -type l \( -path '*/.claude/settings.local.json' -o -path '*/.claude/settings.json' -o -path '*/.vscode/tasks.json' \
       -o -path '*/.vscode/settings.json' "${_pf[@]}" \) "${_ls[@]}" \) -o \
    \( -type l \( -name .claude -o -name .vscode \) ! -path "$H/.vscode" "${_lx[@]}" \) -o \
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
# Windsurf became Devin Desktop on 2 June 2026: Devin.app, the devin-desktop command, and editor data
# under Devin, not Windsurf, while ~/.codeium stays (docs.devin.ai/desktop/devin-desktop-faq).
# >>> agents: this table's home; tools/gen.sh copies it into gird-fleet.sh.
AGENTS="Claude Code|claude|$H/.claude|$H/.claude/projects|claude-code
Claude Desktop||$APP_CLAUDE;$AS/Claude|$AS/Claude|claude-desktop
Codex|codex|$H/.codex|$H/.codex/sessions|codex
Gemini CLI|gemini|$H/.gemini|$H/.gemini/tmp|gemini-cli
Cursor|cursor|$APP_CURSOR;$H/.cursor|$AS/Cursor/User/workspaceStorage|cursor
Windsurf|windsurf;devin-desktop|$APP_WINDSURF;$APP_DEVIN;$H/.codeium/windsurf|$AS/Windsurf/User/workspaceStorage;$AS/Devin/User/workspaceStorage|windsurf
Antigravity|antigravity|$APP_ANTIGRAVITY|$AS/Antigravity/User/workspaceStorage|antigravity
GitHub Copilot CLI|copilot|$H/.copilot|$H/.copilot|copilot-cli
OpenCode|opencode|$H/.config/opencode;$H/.local/share/opencode|$H/.local/share/opencode|opencode
Goose|goose|$GOOSE_CFG|$GOOSE_DATA|goose
Aider|aider|||aider
Cline||$AS/Code/User/globalStorage/saoudrizwan.claude-dev;$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev|$AS/Code/User/globalStorage/saoudrizwan.claude-dev/tasks;$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks|cline
Continue||$H/.continue|$H/.continue/sessions|continue"
# <<< agents
# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it.
npm_label() { case "$1" in axios) printf '%s' 'Axios takeover, March 2026' ;; tanstack) printf '%s' 'TanStack worm, May 2026' ;; mistral) printf '%s' 'Mistral AI npm packages, May 2026' ;; uipath) printf '%s' 'UiPath npm packages, May 2026' ;; mistralpy) printf '%s' 'mistralai 2.4.6, May 2026' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1, May 2026' ;; opensearch) printf '%s' 'OpenSearch client, May 2026' ;; bitwarden) printf '%s' 'Bitwarden CLI, April 2026' ;; minishai) printf '%s' 'Mini Shai-Hulud worm, April 2026' ;; lightning) printf '%s' 'lightning 2.6.2 and 2.6.3, April 2026' ;; mastra) printf '%s' 'Mastra npm packages, June 2026' ;; antv) printf '%s' 'AntV account takeover, May 2026' ;; nxconsole) printf '%s' 'Nx Console 18.95.0, May 2026' ;; redhat) printf '%s' 'Red Hat Cloud Services packages, June 2026' ;; keyv) printf '%s' 'keyv worm, August 2026' ;; keyvscope) printf '%s' 'keyv account takeover, August 2026' ;; keyvspread) printf '%s' 'keyv worm spread, August 2026' ;; sandworm) printf '%s' 'SANDWORM_MODE worm, February 2026' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages, February 2026' ;; tensorlake) printf '%s' 'tensorlake package, October 2026' ;; litellm) printf '%s' 'LiteLLM 1.107.0, October 2026' ;; litellmmar) printf '%s' 'LiteLLM 1.82.7 and 1.82.8, March 2026' ;; opencode) printf '%s' 'OpenCode Console, October 2026' ;; railway) printf '%s' 'Railway, October 2026' ;; zeabur) printf '%s' 'Zeabur, October 2026' ;; glassworm) printf '%s' 'GlassWorm extensions, January 2026' ;; glasswormmar) printf '%s' 'GlassWorm extensions, March 2026' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions, March 2026' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions, April 2026' ;; glasswormzig) printf '%s' 'GlassWorm extensions, April 2026' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes, October 2026' ;; glasswormuni) printf '%s' 'GlassWorm invisible code, March 2026' ;; glasswasm) printf '%s' 'GlassWASM extensions, June 2026' ;; injective) printf '%s' 'Injective SDK, July 2026' ;; esac; }
incident_line() { case "$1" in axios) printf '%s' 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it. cisa.gov' ;; tanstack) printf '%s' 'TanStack worm, May 2026: stole cloud, GitHub, npm and SSH credentials on install, then republished itself. github.com' ;; mistral) printf '%s' 'Mistral AI npm packages, May 2026: published with malware Mistral says could not run, as its setup script names a missing file. docs.mistral.ai' ;; uipath) printf '%s' 'UiPath npm packages, May 2026: published with malware UiPath says a bug made non-functional. trust.uipath.com' ;; mistralpy) printf '%s' 'mistralai 2.4.6, May 2026: started a credential stealer in the background when imported on Linux. docs.mistral.ai' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1, May 2026: downloaded and ran a credential stealer, on Linux only. wiz.io' ;; opensearch) printf '%s' 'OpenSearch client, May 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' ;; bitwarden) printf '%s' 'Bitwarden CLI, April 2026: stole SSH keys, npm, GitHub and cloud credentials, and AI tool configs. stepsecurity.io' ;; minishai) printf '%s' 'Mini Shai-Hulud worm, April 2026: stole GitHub, npm and cloud credentials, and tried to spread through stolen tokens. wiz.io' ;; lightning) printf '%s' 'lightning 2.6.2 and 2.6.3, April 2026: started a credential stealer when imported, then tried to spread itself. github.com' ;; mastra) printf '%s' 'Mastra npm packages, June 2026: pulled in malware that started at login and sent browser history to the attackers. socket.dev' ;; antv) printf '%s' 'AntV account takeover, May 2026: published from a hijacked maintainer account with an install hook that steals credentials. osv.dev' ;; nxconsole) printf '%s' 'Nx Console 18.95.0, May 2026: a malicious build fetched a payload that harvested credentials from disk and memory. github.com' ;; redhat) printf '%s' 'Red Hat Cloud Services packages, June 2026: published by the worm with an install hook that steals cloud, GitHub and npm credentials. osv.dev' ;; keyv) printf '%s' 'keyv worm, August 2026: stole cloud, GitHub and npm credentials, and planted hooks that run when repos open. socket.dev' ;; keyvscope) printf '%s' 'keyv account takeover, August 2026: GitHub malware advisories say to treat a computer that installed one as fully compromised. github.com' ;; keyvspread) printf '%s' 'keyv worm spread, August 2026: republished by the worm with an install hook that steals GitHub, npm and cloud credentials. osv.dev' ;; sandworm) printf '%s' 'SANDWORM_MODE worm, February 2026: stole credentials and AI provider keys, and added an MCP server to AI assistants. socket.dev' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages, February 2026: GitHub malware advisories say to treat a machine that installed one as compromised. github.com' ;; tensorlake) printf '%s' 'tensorlake package, October 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' ;; litellm) printf '%s' 'LiteLLM 1.107.0, October 2026: stole credentials and loaded remote-code execution tools on machines that installed it. docs.litellm.ai' ;; litellmmar) printf '%s' 'LiteLLM 1.82.7 and 1.82.8, March 2026: harvested SSH keys, cloud credentials and Kubernetes tokens, and sent them out. docs.litellm.ai' ;; opencode) printf '%s' 'OpenCode Console, October 2026: a breach hit 1.4% of Console users, some of those who had linked external providers. x.com' ;; railway) printf '%s' 'Railway, October 2026: an attacker may have accessed encrypted environment variables and obtained the decrypted contents of some. blog.railway.com' ;; zeabur) printf '%s' 'Zeabur, October 2026: an attacker read environment variables and secrets stored on the platform. zeabur.com' ;; glassworm) printf '%s' 'GlassWorm extensions, January 2026: malicious Open VSX extensions; on Macs, its payload stole credentials, keychains and crypto wallets. socket.dev' ;; glasswormmar) printf '%s' 'GlassWorm extensions, March 2026: ran attacker code in memory that could reach local credentials, tokens and secrets. socket.dev' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions, March 2026: installed a malicious extension from GitHub into every editor it found. socket.dev' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions, April 2026: updated cloned extensions to install malware from GitHub into VS Code, Cursor and Windsurf. socket.dev' ;; glasswormzig) printf '%s' 'GlassWorm extensions, April 2026: native code in an extension installed a GlassWorm dropper into every editor it found. aikido.dev' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes, October 2026: a VS Code theme cluster tied to GlassWorm; two of its themes ran hidden loaders. socket.dev' ;; glasswormuni) printf '%s' 'GlassWorm invisible code, March 2026: hid code in characters that show as blank, which it then decodes and runs. aikido.dev' ;; glasswasm) printf '%s' 'GlassWASM extensions, June 2026: clones of Marketplace extensions on Open VSX, built to download and run a second stage. socket.dev' ;; injective) printf '%s' 'Injective SDK, July 2026: sent out the seed phrases, and the private keys given as hex strings, that apps loaded into it. github.com' ;; esac; }
incident_level() { case "$1" in mistral) printf update ;; uipath) printf update ;; opencode) printf leak ;; railway) printf leak ;; zeabur) printf leak ;; injective) printf update ;; *) printf act ;; esac; }
incident_name() { case "$1" in axios) printf '%s' 'Axios takeover' ;; tanstack) printf '%s' 'TanStack worm' ;; mistral) printf '%s' 'Mistral AI npm packages' ;; uipath) printf '%s' 'UiPath npm packages' ;; mistralpy) printf '%s' 'mistralai 2.4.6' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1' ;; opensearch) printf '%s' 'OpenSearch client' ;; bitwarden) printf '%s' 'Bitwarden CLI' ;; minishai) printf '%s' 'Mini Shai-Hulud worm' ;; lightning) printf '%s' 'lightning 2.6.2 and 2.6.3' ;; mastra) printf '%s' 'Mastra npm packages' ;; antv) printf '%s' 'AntV account takeover' ;; nxconsole) printf '%s' 'Nx Console 18.95.0' ;; redhat) printf '%s' 'Red Hat Cloud Services packages' ;; keyv) printf '%s' 'keyv worm' ;; keyvscope) printf '%s' 'keyv account takeover' ;; keyvspread) printf '%s' 'keyv worm spread' ;; sandworm) printf '%s' 'SANDWORM_MODE worm' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages' ;; tensorlake) printf '%s' 'tensorlake package' ;; litellm) printf '%s' 'LiteLLM 1.107.0' ;; litellmmar) printf '%s' 'LiteLLM 1.82.7 and 1.82.8' ;; opencode) printf '%s' 'OpenCode Console' ;; railway) printf '%s' 'Railway' ;; zeabur) printf '%s' 'Zeabur' ;; glassworm) printf '%s' 'GlassWorm extensions' ;; glasswormmar) printf '%s' 'GlassWorm extensions' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions' ;; glasswormzig) printf '%s' 'GlassWorm extensions' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes' ;; glasswormuni) printf '%s' 'GlassWorm invisible code' ;; glasswasm) printf '%s' 'GlassWASM extensions' ;; injective) printf '%s' 'Injective SDK' ;; esac; }
incident_source() { case "$1" in axios) printf '%s' 'www.cisa.gov/news-events/alerts/2026/04/20/supply-chain-compromise-impacts-axios-node-package-manager' ;; tanstack) printf '%s' 'github.com/advisories/GHSA-g7cv-rxg3-hmpx' ;; mistral) printf '%s' 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' ;; uipath) printf '%s' 'trust.uipath.com/?tcuUid=d146e497-71c6-4d69-afac-0134100df8b0' ;; mistralpy) printf '%s' 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' ;; guardrails) printf '%s' 'www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised' ;; opensearch) printf '%s' 'github.com/advisories/GHSA-298w-vvm4-ww55' ;; bitwarden) printf '%s' 'www.stepsecurity.io/blog/bitwarden-cli-hijacked-on-npm-bun-staged-credential-stealer-targets-developers-github-actions-and-ai-tools' ;; minishai) printf '%s' 'www.wiz.io/blog/mini-shai-hulud-supply-chain-sap-npm' ;; lightning) printf '%s' 'github.com/advisories/GHSA-g4wr-mm54-799x' ;; mastra) printf '%s' 'socket.dev/blog/mastra-npm-packages-compromised' ;; antv) printf '%s' 'osv.dev/vulnerability/MAL-2026-3973' ;; nxconsole) printf '%s' 'github.com/nrwl/nx-console/security/advisories/GHSA-c9j4-9m59-847w' ;; redhat) printf '%s' 'osv.dev/vulnerability/MAL-2026-5111' ;; keyv) printf '%s' 'socket.dev/blog/popular-npm-packages-in-the-keyv-and-cacheable-namespaces-compromised-in-active-supply-chain' ;; keyvscope) printf '%s' 'github.com/advisories/GHSA-q99r-cjmf-3xrf' ;; keyvspread) printf '%s' 'osv.dev/vulnerability/MAL-2026-11952' ;; sandworm) printf '%s' 'socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning' ;; sandsleep) printf '%s' 'github.com/advisories/GHSA-9w7p-hqx2-pjjx' ;; tensorlake) printf '%s' 'github.com/advisories/GHSA-rqxj-g25x-4v9v' ;; litellm) printf '%s' 'docs.litellm.ai/blog/security-incident-oct-21-2026' ;; litellmmar) printf '%s' 'docs.litellm.ai/blog/security-update-march-2026' ;; opencode) printf '%s' 'x.com/opencode/status/2111519637049319818' ;; railway) printf '%s' 'blog.railway.com/p/security-disclosure-wednesday-october-21st' ;; zeabur) printf '%s' 'zeabur.com/blogs/october-2026-security-incident' ;; glassworm) printf '%s' 'socket.dev/blog/glassworm-loader-hits-open-vsx-via-suspected-developer-account-compromise' ;; glasswormmar) printf '%s' 'socket.dev/blog/open-vsx-transitive-glassworm-campaign' ;; glasswormvsix) printf '%s' 'socket.dev/blog/glassworm-sleeper-extensions-activated-on-open-vsx' ;; glasswormapr) printf '%s' 'socket.dev/blog/73-open-vsx-sleeper-extensions-glassworm' ;; glasswormzig) printf '%s' 'www.aikido.dev/blog/glassworm-zig-dropper-infects-every-ide-on-your-machine' ;; glasswormoct) printf '%s' 'socket.dev/blog/glassworm-vscode-themes' ;; glasswormuni) printf '%s' 'www.aikido.dev/blog/glassworm-returns-unicode-attack-github-npm-vscode' ;; glasswasm) printf '%s' 'socket.dev/blog/glasswasm-malware-open-vsx-extensions' ;; injective) printf '%s' 'github.com/advisories/GHSA-5fc4-fm2x-6f4r' ;; esac; }
incident_advice() { case "$1" in uipath) printf '%s' 'UiPath says the @uipath builds section 5 lists pose no risk of malware, as a bug left it non-functional. Update them to a version without it.' ;; keyvscope) printf '%s' 'Rotate the secrets this machine held from another computer, then remove each @keyv package listed in section 5, as the GitHub advisory says.' ;; sandworm) printf '%s' 'First find and remove what the SANDWORM_MODE worm leaves: git hooks in the folder that git config --global init.templateDir names and in the .git/hooks and .husky folders of your repositories, and MCP servers you did not add to your AI assistants. Its pre-push hook sends npm tokens out on every push.' ;; glassworm) printf '%s' 'On a Mac, also check ~/Library/LaunchAgents for unfamiliar plists such as com.user.nodestart.plist, and look for /tmp/ijewf and /tmp/out.zip, where the malware collects what it steals.' ;; glasswormvsix) printf '%s' 'Also check every editor you use, VS Code included, for extensions you did not install yourself: this malware installs one from GitHub into each editor it finds.' ;; glasswormapr) printf '%s' 'Also check every editor you use, VS Code included, for extensions you did not install yourself: this malware installs one from GitHub into each editor it finds.' ;; glasswormzig) printf '%s' 'Also check every editor you use, VS Code included, for extensions you did not install yourself: this malware installs one from GitHub into each editor it finds.' ;; injective) printf '%s' 'From a clean machine, move the funds out of every wallet whose seed phrase or private key was used with Injective SDK 1.20.21, into a new wallet.' ;; esac; }
incident_summary() { case "$1" in uipath) printf '%s' 'UiPath builds: update them, UiPath says no risk' ;; injective) printf '%s' 'Injective SDK: move the funds out of its wallets' ;; esac; }
# <<< incidents
# >>> indicators: generated from data/indicators.tsv by tools/gen.sh. Edit that file, then run it.
IND_TABLE="tanstack|all|wiper|no|$H/Library/LaunchAgents/com.user.gh-token-monitor.plist|-
tanstack|all|wiper|no|$H/.config/systemd/user/gh-token-monitor.service|-
tanstack|all|wiper|no|$H/.local/bin/gh-token-monitor.sh|-
tanstack|all|wiper|no|$H/.config/gh-token-monitor|-
tanstack|all|wiper|yes|/tmp/gh-token-monitor.out.log|-
tanstack|all|wiper|yes|/tmp/gh-token-monitor.err.log|-
tanstack|win|wiper|no|$WLAPP/gh-token-monitor|-
mastra|all|startup|no|$H/Library/LaunchAgents/com.nvm.protocal.plist|starts the Mastra malware at login
glassworm|all|startup|no|$H/Library/LaunchAgents/com.user.nodestart.plist|starts the GlassWorm malware at login
mastra|all|startup|no|$H/Library/NodePackages/protocal.cjs|the Mastra malware itself, set to run at every login
mastra|all|startup|no|$H/.config/systemd/user/nvmconf.service|starts the Mastra malware at login
mastra|all|startup|no|$H/.config/systemd/nvmconf/protocal.cjs|the Mastra malware itself, set to run at every login
mastra|win|startup|no|${_pd:+$_pd/NodePackages/protocal.cjs}|the Mastra malware itself, set to run at every login
antv|all|startup|no|$H/.config/systemd/user/kitty-monitor.service|starts the AntV wave's kitty-monitor backdoor at login
antv|all|startup|no|$H/Library/LaunchAgents/com.user.kitty-monitor.plist|starts the AntV wave's kitty-monitor backdoor at login
antv|all|startup|no|$H/.local/share/kitty/cat.py|the AntV wave's kitty-monitor backdoor, which its service starts at login
nxconsole|all|startup|no|$H/Library/LaunchAgents/com.user.kitty-monitor.plist|starts the kitty-monitor backdoor Nx Console 18.95.0 installed, at login
nxconsole|all|startup|no|$H/.local/share/kitty/cat.py|the kitty-monitor backdoor Nx Console 18.95.0 installed
antv|all|startup|no|$H/.claude/package/index.js|a copy of the AntV wave's payload, run by the hooks it adds to agent settings
antv|all|startup|no|$H/.codex/package/index.js|a copy of the AntV wave's payload, run by the hooks it adds to agent settings
litellm|all|site|no|cook.pth|-
litellm|all|site|no|cook.py|-
litellmmar|all|site|no|litellm_init.pth|-
litellmmar|all|startup|no|$H/.config/sysmon/sysmon.py|the backdoor the March LiteLLM malware leaves, which a systemd service starts at login on Linux
litellm|all|temp|yes|remote_code_loader.lock|These files mean the malware ran here, and a .pc_once_ file that it sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
litellm|all|temp|yes|.pc_once_*|These files mean the malware ran here, and a .pc_once_ file that it sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
litellm|all|temp|yes|.pc_sq_*|These files mean the malware ran here, and a .pc_once_ file that it sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
litellm|all|temp|yes|.pc_e_*|These files mean the malware ran here, and a .pc_once_ file that it sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.
mistralpy|linux|temp|yes|transformers.pyz|Mistral lists this file, and a process started through python /tmp/transformers.pyz, as signs of the stealer: clean this machine, rotate all secrets it could reach and check cloud audit logs for suspicious activity."
# <<< indicators
# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it.
OUT_TABLE="cursor|Cursor|mac|plist|/Applications/Cursor.app/Contents/Info.plist|-|3.0|a malicious agent could escape the sandbox|github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw
cursor|Cursor|mac|plist|$H/Applications/Cursor.app/Contents/Info.plist|-|3.0|a malicious agent could escape the sandbox|github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw
cursor|Cursor|mac|plist|/Applications/Cursor.app/Contents/Info.plist|-|3.1.2|an agent could replace the Python of a virtual environment to run commands outside the sandbox|github.com/cursor/cursor/security/advisories/GHSA-p9g2-cr55-cw9c
cursor|Cursor|mac|plist|$H/Applications/Cursor.app/Contents/Info.plist|-|3.1.2|an agent could replace the Python of a virtual environment to run commands outside the sandbox|github.com/cursor/cursor/security/advisories/GHSA-p9g2-cr55-cw9c
claudedesktop|Claude Desktop|mac|plist|/Applications/Claude.app/Contents/Info.plist|1.1.3918|1.15962.0|a file an agent leaves in a Cowork folder could run commands on the Mac when opened|github.com/anthropics/claude-code/security/advisories/GHSA-v234-4jrq-mgg6
claudedesktop|Claude Desktop|mac|plist|$H/Applications/Claude.app/Contents/Info.plist|1.1.3918|1.15962.0|a file an agent leaves in a Cowork folder could run commands on the Mac when opened|github.com/anthropics/claude-code/security/advisories/GHSA-v234-4jrq-mgg6
claudedesktop|Claude Desktop|mac|plist|/Applications/Claude.app/Contents/Info.plist|1.2581.0|1.4304.0|an attacker on the network could intercept its remote SSH sessions|github.com/anthropics/claude-code/security/advisories/GHSA-3rwf-2g6p-c2f9
claudedesktop|Claude Desktop|mac|plist|$H/Applications/Claude.app/Contents/Info.plist|1.2581.0|1.4304.0|an attacker on the network could intercept its remote SSH sessions|github.com/anthropics/claude-code/security/advisories/GHSA-3rwf-2g6p-c2f9
amazonq|Amazon Q language server|mac|folder|$H/Library/Caches/aws/toolkits/language-servers/AmazonQ|-|1.69.0|a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands|aws.amazon.com/security/security-bulletins/2026-047-aws/
amazonq|Amazon Q language server|linux|folder|$H/.cache/aws/toolkits/language-servers/AmazonQ|-|1.69.0|a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands|aws.amazon.com/security/security-bulletins/2026-047-aws/
amazonq|Amazon Q language server|win|folder|$WLAPP/aws/toolkits/language-servers/AmazonQ|-|1.69.0|a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands|aws.amazon.com/security/security-bulletins/2026-047-aws/
claudecode|Claude Code|all|npm|@anthropic-ai/claude-code|0.2.116|1.0.24|a web page could reach the editor connection|github.com/advisories/GHSA-9f65-56v6-gxw7
claudecode|Claude Code|all|npm|@anthropic-ai/claude-code|2.1.38|2.1.163|a malicious repository could run code outside the sandbox|github.com/advisories/GHSA-7835-87q9-rgvv
claudecode|Claude Code|all|npm|@anthropic-ai/claude-code|-|2.1.179|a plugin repository could install code that bypasses its pinned hash|github.com/advisories/GHSA-pq7j-f95f-qfcv
claudecode|Claude Code|all|npm|@anthropic-ai/claude-code|2.0.68|2.1.260|a stored API key could start sessions without the managed settings of an Enterprise or Team organization|github.com/anthropics/claude-code/security/advisories/GHSA-gfvf-j8jh-jxxw
mcpremote|mcp-remote|all|npm|mcp-remote|0.0.5|0.1.16|a hostile MCP server could run commands|github.com/advisories/GHSA-6xpm-ggf7-wc3p
mcpremote|mcp-remote|all|mcparg|mcp-remote|0.0.5|0.1.16|a hostile MCP server could run commands|github.com/advisories/GHSA-6xpm-ggf7-wc3p"
# <<< outdated
# Hosted platforms that leaked stored secrets (data/platforms.tsv): found by a command on PATH or a
# file or folder (a folder ends in /). PLAT_FOUND lists the ids found, PLAT_LIST every name.
# >>> platforms: generated from data/platforms.tsv by tools/gen.sh. Edit that file, then run it.
PLATFORMS="opencode|OpenCode|opencode|$H/.config/opencode/;$H/.local/share/opencode/|installed|OpenCode emailed the Console users its breach hit, and says those it did not email were not affected. It told those users to revoke and replace their keys directly with each provider. Keys kept only in the CLI never reach OpenCode.|OpenCode found: got its breach email? Rotate keys
railway|Railway|railway|$H/.railway/config.json|CLI found|Railway asked all users to rotate every environment variable stored there, including API keys and private registry credentials, and to review their logs for unusual activity.|Railway CLI found: rotate secrets stored there
zeabur|Zeabur|zeabur|$H/.config/zeabur/|CLI found|Zeabur said on 19 October that an attacker read the service environment variables stored on the platform, and asked users to replace every password and key stored there. Revoke each old key at its provider first.|Zeabur CLI found: rotate secrets stored there"
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
# The home scan's find errors, which name the folders it could not read: in /tmp when TMPDIR can't
# be written to, and with neither, every row it feeds reads partly checked (SCAN_LOST).
SCAN_ERR=$(mktemp "$TMPD/blindspot.XXXXXX" 2>/dev/null || mktemp /tmp/blindspot.XXXXXX 2>/dev/null) || SCAN_ERR=""
SCAN_LOST=0; [ -n "$SCAN_ERR" ] || SCAN_LOST=1
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
win|read|Claude Desktop|$WLAPP/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/local-agent-mode-sessions
all|read|Claude Desktop|$AS/Claude-3p/local-agent-mode-sessions
win|read|Claude Desktop|$WLAPP/Claude-3p/local-agent-mode-sessions
all|read|Codex|${CODEX_HOME:-$H/.codex}/sessions
all|read|Codex|${CODEX_HOME:-$H/.codex}/archived_sessions
all|read|Codex|${CODEX_HOME:-$H/.codex}/history.jsonl
all|read|Codex|${CODEX_HOME:-$H/.codex}/thread_history_1.sqlite
all|read|Codex|${CODEX_HOME:-$H/.codex}/thread_history_1.sqlite-wal
all|read|Codex|${CODEX_SQLITE_HOME:-$H/.codex}/thread_history_1.sqlite
all|read|Codex|${CODEX_SQLITE_HOME:-$H/.codex}/thread_history_1.sqlite-wal
all|read|Gemini CLI|${GEMINI_CLI_HOME:-$H}/.gemini/tmp
mac|read|Gemini CLI|${GEMINI_CLI_HOME:-$H}/.cache/.gemini/tmp
all|read|Qwen Code|${QWEN_HOME:-$H/.qwen}/projects
all|read|Qwen Code|${QWEN_HOME:-$H/.qwen}/tmp
all|read|Qwen Code|${QWEN_RUNTIME_DIR:-$H/.qwen}/projects
all|read|Qwen Code|${QWEN_RUNTIME_DIR:-$H/.qwen}/tmp
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
all|read|Roo Code|$AS/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks
all|read|Cline|$AS/Code/User/globalStorage/saoudrizwan.claude-dev/tasks
all|read|Cline|$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks
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
# A location whose folder variable is written with a doubled or trailing / is spelled with single
# slashes, as ripgrep prints the paths under it, so each hit keeps its place: otherwise it reads as
# Other, shown by the folder it is in, whose name can spell out a project and a username.
SESS_TABLE=$(printf '%s\n' "$SESS_TABLE" | sed -e 's#\([^|]\)//*#\1/#g' -e 's#\([^|]\)/$#\1#')
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
# (a match) and then D (done) for a file, Z for a compressed one (.zst, as Codex compresses a session
# older than a week, or .gz) or U for one it can't open; the
# parent prints T (the total) first, and S (the folders it could not open, whose files are not in
# the total) when there are any. Before printing, control characters become ? in a file name and a
# space in a match, so neither a hostile folder name nor a newline or tab that happens to be the
# boundary byte of a match can split a line or shift its fields. Files are read 1 MB at a time and
# cut just after the last character that can't be in a key (Bedrock's long-term keys hold + and /)
# or start an escape such as \n (a backslash never ends a piece), so a huge database file never loads at once and a piece never ends
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
      if ($file =~ /\.(zst|gz)$/) { print "Z\t$fn\n"; next }
      my $h; unless (open($h, "<", $file)) { print "U\t$fn\n"; next }
      binmode $h; local $/ = \1048576; my $buf = "";
      my $scan = sub { my $t = shift; if ($t =~ $pre) { while ($t =~ /$re/g) { (my $k = $&) =~ tr/\x00-\x1f\x7f/ /; print "K\t$fn\t$k\n" } } };
      while (defined(my $c = <$h>)) {
        exit 0 unless $alive->();
        select(undef, undef, undef, 0.3) if $ENV{GIRD_CHECK_SESSIONS_SLOW};  # tests only
        $buf .= $c;
        my $cut = $buf =~ /[^A-Za-z0-9_.+\/=\\-][A-Za-z0-9_.+\/=\\-]*\z/ ? $-[0] + 1 : -1;
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
# the longest fixed format, OpenAI project keys run to about 170) but GitHub's stateless ghs_ tokens,
# about 520 with two dots: a longer run of key characters is data, not a key, and would make madeup()
# slow. Always called in a subshell (a pipe or a
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
      if (length(k) > 1024 || (length(k) > 300 && k !~ /ghs_[A-Za-z0-9_-]+\./)) next
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
    # --no-unicode: in its default Unicode mode a class such as [^A-Z0-9] matches no byte that is not
    # UTF-8, so a key right after one (a SQLite value after a binary column) would be missed. The
    # patterns are byte patterns, as perl and grep read them under LC_ALL=C.
    "$RG_BIN" -a --no-unicode --hidden --no-ignore --no-config --no-messages -o --no-line-number --with-filename --null \
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
HOME_PARTIAL=0; [ $((N_NL_DIRS + N_UNREAD_DIRS + SCAN_LOST + SCAN_FAILED)) -gt 0 ] && HOME_PARTIAL=1
# Linked settings, tasks and planted files, and those files in a linked .claude or .vscode folder,
# come marked "S path" and are checked like the files, but files_found counts files, as it always has.
# A link counts only when it ends at a regular file: a repo can link a settings file to /dev/zero or
# /dev/tty, which a reader would never get to the end of.
LINKED=$(printf '%s\n' "$FOUND" | sed -n 's/^S //p' | while IFS= read -r _f; do [ -f "$_f" ] && printf '%s\n' "$_f"; done)
# A settings, tasks or planted file bigger than READ_MAX, the bound an account run keeps for every file,
# is not read: a project can link one to a large system file, which would hold the scan for minutes
# (about a second a megabyte on macOS's awk). A settings or tasks file is then named as not read; a
# planted file is not hashed, so one that projects name too stays a file to read.
READ_MAX=$FLEET_MAX
too_big() { _tb=$({ wc -c < "$1"; } 2>/dev/null); _tb=${_tb//[!0-9]/}; [ -n "$_tb" ] && [ "$_tb" -gt "$READ_MAX" ]; }
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
# A link named like a settings, tasks or planted file comes as "S path" and can lead there too: Claude
# Code writes .claude/settings.local.json itself.
AK_LINKS=$(printf '%s\n' "$FOUND" | sed -n 's/^[LS] //p' | while IFS= read -r _f; do case "$_f" in ("$H"/.ssh/*) ;; (*) ak_link "$_f" && printf '%s\n' "$_f" ;; esac; done)
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
  if [ "$_ok" -eq 0 ] && [ -f "$_f" ] && ! too_big "$_f"; then
    _sh=$({ sha_hex < "$_f"; } 2>/dev/null)
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
VSC_SETTINGS=$(printf '%s\n%s\n' "$FOUND" "$LINKED" | grep -E '/\.vscode/settings\.json$')
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
    # Four levels down: Codex writes each session to sessions/YYYY/MM/DD/rollout-*.jsonl
    # (codex-rs/rollout/src/recorder.rs); the other agents' files sit within three.
    for a in $acts; do
      [ -d "$a" ] || continue
      [ -n "$(find "$a" -maxdepth 4 -type f -print -quit 2>/dev/null)" ] && any=1
      [ -n "$(find "$a" -maxdepth 4 -type f -mtime -30 -print -quit 2>/dev/null)" ] && recent=1
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
# Devin Desktop, Windsurf renamed, keeps its MCP config in ~/.codeium (docs.devin.ai/desktop/devin-desktop-faq).
MCP_FILES="Claude Code|claude-code|$H/.claude.json
Claude Desktop|claude-desktop|$AS/Claude/claude_desktop_config.json
Cursor|cursor|$H/.cursor/mcp.json
Windsurf|windsurf|$H/.codeium/windsurf/mcp_config.json
Devin Desktop|windsurf|$H/.codeium/mcp_config.json
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
MCP_FLAGGED="|$(printf '%s\n' "$MCP_LIST" | fleet_filter | files_matching "$TR_KEYS|$P_JSONSECRET|$P_TOMLSECRET" | tr '\n' '|')"
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
# or ||, outside shell quotes: a ; or | inside '...' or \"...\" is text, such as a grep pattern or an
# echo that names the file. A rule or a guard that only names the file, or passes it to another
# script, does not count. The file may be quoted, after $CLAUDE_PROJECT_DIR, ${workspaceFolder} or
# ./, and must end there.
worm_cmd() { # file-ERE: a command, in flattened JSON, that runs one of these files
  _wf='(\\"|'"'"')?((\\")?\$\{?(CLAUDE_PROJECT_DIR|workspaceFolder)\}?(\\")?[/\\]+|\.[/\\]+)?'"$1"'(\\"|["'"'"'[:space:];&|)])'
  _wp='(([^[:space:]"\\]|\\\\)*(/|\\\\))?'
  _wo='(--|--[A-DF-OQ-Za-df-oq-z0-9][^[:space:]"\\]*|-[A-DF-OQ-Za-df-oq-z0-9]+)[[:space:]]+'
  # One piece of a command before a separator: a character outside quotes, a JSON escape other than
  # \", a '...' span, or a \"...\" span (a shell double-quoted string, its quotes escaped in JSON).
  _wq='[^"\\'"'"']|\\[^"]|'"'"'([^'"'"'"\\]|\\.)*'"'"'|\\"([^"\\]|\\[^"])*\\"'
  _ws='"command"[[:space:]]*:[[:space:]]*"[[:space:]]*(('"$_wq"')*(;|&&?|\|\|?)[[:space:]]*)?'
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
# setting in any other file is not active either. A CR is a line break too, and a \ escapes only one:
# after \ and CRLF the LF still ends the string. Inside strings, \uXXXX for a printable character
# other than " and \, and \/, are written as that character, as JSON reads them: "\u0068ooks" is
# "hooks", and a setting can't hide behind its escapes. Each line is split on its quotes, and each piece
# outside a string on its slashes, both with a one-character separator, and every chunk is looked at
# a bounded number of times, so the time grows with the size of the file: a loop over single
# characters (substr measures the whole string on macOS's awk), a regex split or gsub with many
# matches, or a match that can restart inside a long run would be quadratic on a long minified line.
# A file that can't be opened reads as nothing, and silently: bash reports a failed < itself, with the
# raw path, before a 2>/dev/null after it takes effect, so the redirect sits inside the braces. The
# same goes for every read of a scanned path below.
flat() {
  { tr '\r\t' '\n ' < "$1"; } 2>/dev/null | awk '
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
    # A piece of a string, its escapes written as JSON reads them (above). Split on \, so each chunk is
    # looked at once: an empty chunk is an escaped \ (kept as \\), or the lone \ that ends the piece.
    function str(s,   nb, b, j, h) {
      if (index(s, "\\") == 0) { printf "%s", s; return }
      nb = split(s, b, "\\"); printf "%s", b[1]
      for (j = 2; j <= nb; j++) {
        if (b[j] == "") { if (j == nb) { printf "\\"; break }; printf "\\\\%s", b[j + 1]; j++; continue }
        h = tolower(substr(b[j], 2, 4))
        if (substr(b[j], 1, 1) == "u" && (h in U)) printf "%s%s", U[h], substr(b[j], 6)
        else if (substr(b[j], 1, 1) == "/") printf "%s", b[j]
        else printf "\\%s", b[j]
      }
    }
    BEGIN { st = 0   # 0 code, 1 string, 2 block comment
            for (c = 32; c < 127; c++) if (c != 34 && c != 92) U[sprintf("%04x", c)] = sprintf("%c", c) }
    { nq = split($0, q, "\"")
      if (nq == 0 && st == 1) st = 0   # an empty line in a string: its line break was not escaped
      for (i = 1; i <= nq; i++) {
        if (st == 1) {            # in a string: kept as it is; an odd run of \ escapes the quote or the line break
          str(q[i]); esc = (trail(q[i]) % 2 == 1)
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
  # With nothing to list (hooks turned off), only a hook that runs a worm file counts: the worm wrote it.
  [ -n "$2" ] || return 0
  # Worktrees and copies carry the same settings: one row, with how many more folders have it. The
  # row names the repo's own file, whichever one the scan listed first.
  # The path goes into TAB-separated rows and the list of settings seen, so it is made row-safe first.
  _rp=$(rowsafe "$1")
  _sum="$(printf '%s' "$3" | cksum | cut -d' ' -f1):$(printf '%s' "$_rp" | sed -E 's#/\.claude/worktrees/[^/]+/#/#')"
  case "$TAB$AUTO_SEEN" in *"$TAB$_sum$TAB"*) AUTO_ROWS="$(printf '%s' "$AUTO_ROWS" | S=$_sum F=$_rp awk -F "$TAB" -v OFS="$TAB" '
      $3 == ENVIRON["S"] { $4 = $4 + 1; if ($1 ~ /\/\.claude\/worktrees\// && ENVIRON["F"] !~ /\/\.claude\/worktrees\//) $1 = ENVIRON["F"] } { print }')
"; return ;; esac
  AUTO_SEEN="$AUTO_SEEN$_sum$TAB"
  N_AUTO=$((N_AUTO + 1))
  progress w "Project settings that $2: $(short "$1")"
  AUTO_ROWS="$AUTO_ROWS$_rp$TAB$2$TAB$_sum${TAB}0
"
}
# For aa_hit, a .json file's text (one line, spaces removed), then a line for each object that is the
# value of a top-level key a pattern names as "key": {...: the key, a tab, and that object with every
# value nested in it emptied ({} or []), so the rest of the pattern matches only directly inside it, as
# Claude Code reads defaultMode only inside permissions. Strings are split on their quotes as flat
# splits them (a key with an escaped quote in it is never one a pattern names), and the code between
# them on each kind of bracket, one character at a time, and the object is printed as it is read:
# linear on every awk, where building it up as one string is quadratic on macOS's awk.
aa_keys() { # pattern|pattern...
  AA_P=$1 awk '
    function trail(s) {
      if (s !~ /\\$/) return 0
      if (match(s, /[^\\]\\*$/)) return RLENGTH - 1
      return length(s)
    }
    function out(s) { if (cur != "" && dep == 2) printf "%s", s }
    function ob(c) { if (dep == 1 && c == "{" && (key in want)) { cur = key; printf "%s\t{", cur } else out(c); dep++ }
    function cb(c) { dep--; out(c); if (cur != "" && dep == 1) { print "}"; cur = "" } }
    # The code between two strings, its brackets in order: split on {, each part on }, then [ and ].
    function code(s,   a, b, c, d, na, nb, nc, nd, i, j, k, l) {
      na = split(s, a, "{")
      for (i = 1; i <= na; i++) {
        nb = split(a[i], b, "}")
        for (j = 1; j <= nb; j++) {
          nc = split(b[j], c, "[")
          for (k = 1; k <= nc; k++) {
            nd = split(c[k], d, "]")
            for (l = 1; l <= nd; l++) { out(d[l]); if (l < nd) cb("]") }
            if (k < nc) ob("[")
          }
          if (j < nb) cb("}")
        }
        if (i < na) ob("{")
      }
    }
    BEGIN { n = split(ENVIRON["AA_P"], p, "|")
      for (i = 1; i <= n; i++) { gsub(/[[:space:]]/, "", p[i]); if (match(p[i], /^"[A-Za-z0-9_.-]+":\{/)) { want[substr(p[i], 2, RLENGTH - 4)] = 1; nw++ } } }
    { print
      if (!nw) next
      nq = split($0, q, "\""); st = 0; dep = 0; cur = ""; key = ""; hp = 0
      for (i = 1; i <= nq; i++) {
        if (st == 0) {            # code: right after a string at the top level, a : makes it the key
          if (hp && q[i] ~ /^:/) key = pv
          hp = 0; code(q[i])
          if (i < nq) { out("\""); st = 1; one = 1 }
          continue
        }
        out(q[i])                 # a string, up to a quote that no odd run of \ escapes
        if (dep == 1) pv = one ? q[i] : ""
        esc = (i < nq && trail(q[i]) % 2 == 1)
        if (i < nq) out("\"")
        if (esc) { one = 0; continue }
        if (dep == 1) hp = 1
        st = 0
      }
      if (cur != "") print ""
    }'
}
# A setting of data/auto-approve.tsv in a file: every pattern must match, spaces ignored. A .json
# file is read as one line through flat (comments are its job), and a match starts at the text, a {
# or a , and ends at the text's end, a , } # or /, so a longer key or another value never counts; a
# pattern written "key": {... matches its rest the same way, inside that top-level key's object only
# (aa_keys). A .toml file is read line by line: a # line is skipped, a match is a whole line up to a #
# comment (so a setting inside an inline table, a profile written as one, does not count), a value in
# double quotes also matches the same value in single quotes (a TOML literal string), and only the
# lines before the first [table] count: a setting under [profiles.x] applies only when that profile
# is used, and Codex 0.134.0 and later read no such table from config.toml. tr removes the spaces in
# one pass, and each pattern becomes one regex with its boundaries in it, tried once per line:
# linear on every awk, where a gsub on the joined text, or an index() of the rest of the line at
# every near miss, is quadratic on macOS's awk for a large file.
aa_hit() { # file pattern|pattern...
  case "$1" in *.toml) _tm=1 ;; *) _tm=0 ;; esac
  if [ "$_tm" -eq 1 ]; then { tr -d ' \t\r\f\v' < "$1"; } 2>/dev/null; else flat "$1" | tr -d '[:space:]' | aa_keys "$2"; fi | AA_P=$2 awk -v toml="$_tm" '
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
      for (i = 1; i <= n; i++) { gsub(/[[:space:]]/, "", p[i]); q = p[i]; gsub(/"/, "\047", q)
        if (!toml && match(p[i], /^"[A-Za-z0-9_.-]+":\{/)) { in_[i] = 1; re[i] = "^" lit(substr(p[i], 2, RLENGTH - 4)) "\t(.*[{,])?" lit(substr(p[i], RLENGTH + 1)) "($|[,}#/])" }
        # !key in a .toml file: the line counts only when no line sets that key.
        else if (toml && substr(p[i], 1, 1) == "!") { neg[i] = 1; re[i] = "^" lit(substr(p[i], 2)) "=" }
        else re[i] = toml ? "^(" lit(p[i]) "|" lit(q) ")(#|$)" : "(^|[{,])" lit(p[i]) "($|[,}#/])" } }
    toml && /^#/ { next }
    toml && /^\[/ { exit }
    # A quoted key ("approval_policy" or 'approval_policy') is the same key as the bare one, in TOML.
    toml && match($0, "^(\"[A-Za-z0-9_-]+\"|\047[A-Za-z0-9_-]+\047)=") { $0 = substr($0, 2, RLENGTH - 3) "=" substr($0, RLENGTH + 1) }
    # A .json file: its text is the first line, the objects aa_keys printed come after it.
    { for (i = 1; i <= n; i++) if (!(i in got) && (toml || (NR == 1) == !(i in in_)) && $0 ~ re[i]) got[i] = 1 }
    END { for (i = 1; i <= n; i++) if ((i in neg) == (i in got)) exit 1; exit 0 }'
}
# The value of a top-level key of a .json file, from its text as one line with the spaces removed:
# true, false, or nothing. Strings and brackets are read as aa_keys reads them, so the same key inside
# another setting's object is not it. The last one wins, as in JSON.parse.
json_top() { # key
  K=$1 awk '
    function trail(s) {
      if (s !~ /\\$/) return 0
      if (match(s, /[^\\]\\*$/)) return RLENGTH - 1
      return length(s)
    }
    { nq = split($0, q, "\""); st = 0; dep = 0; hp = 0; pv = ""; one = 1; v = ""
      for (i = 1; i <= nq; i++) {
        if (st == 0) {            # code: right after a key at the top level, its value
          if (hp && dep == 1 && pv == ENVIRON["K"] && match(q[i], /^:(true|false)([,}]|$)/)) v = (substr(q[i], 2, 1) == "t") ? "true" : "false"
          hp = 0
          dep += split(q[i], a, "{") + split(q[i], b, "[") - split(q[i], c, "}") - split(q[i], d, "]")
          if (i < nq) { st = 1; one = 1 }
          continue
        }
        if (dep == 1) pv = one ? q[i] : ""
        if (i < nq && trail(q[i]) % 2 == 1) { one = 0; continue }
        if (dep == 1) hp = 1
        st = 0
      }
      print v; exit
    }'
}
# Keys that make Claude Code run a command: hooks and its helper commands. Claude Code's settings
# reference lists each as running your own command, set from any settings file. disableAllHooks set to
# true turns off hooks, the status line, the file suggestion command and the subagent status line, but
# not the credential helpers (CMD_ALWAYS). A hook event with an empty list runs nothing either.
CMD_ALWAYS='apiKeyHelper|awsAuthRefresh|awsCredentialExport|gcpAuthRefresh|otelHeadersHelper'
CMD_KEYS="$CMD_ALWAYS|statusLine|fileSuggestion|subagentStatusLine"
HOOK_RUN='"hooks"[[:space:]]*:[[:space:]]*\{([[:space:]]*"([^"\\]|\\.)*"[[:space:]]*:[[:space:]]*\[[[:space:]]*\][[:space:]]*,)*[[:space:]]*"([^"\\]|\\.)*"[[:space:]]*:[[:space:]]*\[[[:space:]]*[^][:space:]]'
while IFS= read -r f; do
  case "$f" in */.claude/settings.json|*/.claude/settings.local.json) ;; *) continue ;; esac
  case "$f" in "$H/.claude/settings.json"|"$H/.claude/settings.local.json"|*/.claude/plugins/*) continue ;; esac
  [ -f "$f" ] && ! too_big "$f" || continue
  _t=$(flat "$f"); _w=""
  # disableAllHooks as the project's settings leave it: settings.local.json comes before settings.json.
  # (Managed settings can set it too; they are not read here.)
  _dah=""
  for _s in "${f%/*}/settings.local.json" "${f%/*}/settings.json"; do
    if [ "$_s" = "$f" ]; then _v=$(printf '%s' "$_t" | tr -d '[:space:]' | json_top disableAllHooks)
    elif [ -f "$_s" ] && [ -r "$_s" ] && ! too_big "$_s"; then _v=$(flat "$_s" | tr -d '[:space:]' | json_top disableAllHooks)
    else continue; fi
    [ -n "$_v" ] && { _dah=$_v; break; }
  done
  if [ "$_dah" = true ]; then _rx="\"($CMD_ALWAYS)\"[[:space:]]*:"; else _rx="$HOOK_RUN|\"($CMD_KEYS)\"[[:space:]]*:"; fi
  if printf '%s' "$_t" | grep -qE "$_rx"; then
    _w="run commands while the agent works"
  fi
  if printf '%s' "$_t" | grep -qE '"enableAllProjectMcpServers"[[:space:]]*:[[:space:]]*true|"enabledMcpjsonServers"[[:space:]]*:[[:space:]]*\[[[:space:]]*"'; then
    _w="${_w:+$_w, }turn on MCP servers without asking"
  fi
  # An empty ANTHROPIC_BASE_URL sets nothing, and https://api.anthropic.com, the API host Claude Code's
  # docs call its own, is not another server.
  if printf '%s' "$_t" | grep -oE '"ANTHROPIC_BASE_URL"[[:space:]]*:[[:space:]]*"[^"]*[^"[:space:]][^"]*"' | grep -qvE ':[[:space:]]*"([A-Za-z]+://(localhost|127\.0\.0\.1|\[::1\])|https://api\.anthropic\.com)(:[0-9]+)?(/[^"]*)?"$'; then
    _w="${_w:+$_w, }send the agent's API traffic, key included, to another server"
  fi
  # Claude Code before 2.1.257 took bypassPermissions from any settings file, a project's too; later
  # versions take it only from the person's own or managed settings (Claude Code's settings docs). It
  # reads defaultMode only inside permissions (aa_hit); the grep spares the files that never name it.
  if printf '%s' "$_t" | grep -qE '"defaultMode"[[:space:]]*:[[:space:]]*"bypassPermissions"' && aa_hit "$f" '"permissions": {"defaultMode": "bypassPermissions"'; then
    _w="${_w:+$_w, }skip permission prompts with bypassPermissions. Claude Code applies it from a project only before version 2.1.257"
  fi
  auto_row "$f" "$_w" "$_t"
done <<EOF
$ALLOW_FILES
EOF
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && ! too_big "$f" || continue
  case "$f" in */.claude/plugins/*) continue ;; esac
  _t=$(flat "$f")
  printf '%s' "$_t" | grep -qE '"runOn"[[:space:]]*:[[:space:]]*"folderOpen"' && auto_row "$f" "run a task when the folder opens in VS Code or Cursor" "$_t"
done <<EOF
$TASK_FILES
EOF
# A project's .vscode/settings.json. "chat.permissions.default" set to "autoApprove" or "autopilot"
# starts new Copilot chats that run every tool call without asking, and the setting
# declares no scope, so VS Code takes it from a project too: a cloned repo can bring it.
# "chat.tools.autoApprove": true is the setting the CVE-2025-53773 prompt injection made Copilot
# write so it could run commands without asking. VS Code 1.104 renamed it without migration, so
# current VS Code ignores it: a sign of that attack, or of an old VS Code, not a setting in force.
# Both are things to look at in a project, not an agent set to run without asking. A file that names
# neither setting (most do not) is skipped before it is flattened: flat only takes comments out and
# writes escapes as their characters, so a setting's name stays as written unless it has an escape.
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && ! too_big "$f" || continue
  { tr -d '[:space:]' < "$f"; } 2>/dev/null | grep -qE 'chat\.(permissions\.default|tools\.autoApprove)|\\u|\\/' || continue
  _w=""
  if aa_hit "$f" '"chat.permissions.default": "autopilot"'; then _w="run every Copilot tool call without asking in new chats, with chat.permissions.default: autopilot"
  elif aa_hit "$f" '"chat.permissions.default": "autoApprove"'; then _w="run every Copilot tool call without asking in new chats, with chat.permissions.default: autoApprove"; fi
  if aa_hit "$f" '"chat.tools.autoApprove": true'; then
    _w="${_w:+$_w, }auto-approve Copilot's tools with chat.tools.autoApprove, the setting the CVE-2025-53773 attack wrote into projects. VS Code 1.104 and later ignore it"
  fi
  [ -n "$_w" ] && auto_row "$f" "$_w" "$(flat "$f")"
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
# On Windows, PowerShell's profiles, which it runs at every start: a key set there with $env: sits in
# plain text. The same files gird-check.ps1 reads, in Documents and in the folder Windows keeps
# Documents in when it was moved (OneDrive's backup moves it), which reg reads from the user's shell
# folders as GetFolderPath('MyDocuments') gives it to PowerShell.
PS_PROFILES=""
if [ "$WIN" -eq 1 ]; then
  _md=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' reg query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' /v Personal 2>/dev/null |
    tr -d '\r' | sed -n 's/^[[:space:]]*Personal[[:space:]][[:space:]]*REG_[A-Z_]*[[:space:]][[:space:]]*//p' | head -n 1)
  _md=$(winpath "$_md"); _md=${_md%/}
  for _dd in "$H/Documents" ${_md:+"$_md"}; do
    for _pe in PowerShell WindowsPowerShell; do
      for _pn in Microsoft.PowerShell_profile.ps1 profile.ps1 Microsoft.VSCode_profile.ps1; do PS_PROFILES="$PS_PROFILES$_dd/$_pe/$_pn
"; done
    done
  done
fi
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
    # Cline 4.x keeps API keys in plain JSON in its data folder: secrets.json (its extension's store,
    # .clinerules/storage.md) and settings/providers.json (its SDK's, docs/getting-started/config.mdx),
    # under CLINE_DATA_DIR, else CLINE_DIR/data, else ~/.cline/data; providers.json at
    # CLINE_PROVIDER_SETTINGS_PATH when that is set (sdk/packages/shared/src/storage/paths.ts).
    for _cd in "${CLINE_DATA_DIR:-$H/.cline/data}" "${CLINE_DIR:-$H/.cline}/data"; do
      printf '%s\n%s\n' "$_cd/secrets.json" "$_cd/settings/providers.json"
    done
    case "${CLINE_PROVIDER_SETTINGS_PATH:-}" in (/*) printf '%s\n' "$CLINE_PROVIDER_SETTINGS_PATH" ;; esac
    if [ "$WIN" -eq 1 ]; then
      printf '%s\n' "$GOOSE_CFG/config.yaml"
      printf '%s' "$PS_PROFILES"
      for f in "$PSRL"/*_history.txt; do [ -f "$f" ] && printf '%s\n' "$f"; done
      [ "$HH" != "$H" ] && for f in .bashrc .bash_profile .profile .bash_history; do printf '%s\n' "$HH/$f"; done
    fi
    printf '%s\n' "$PROJECT_FILES"
  } | awk 'NF && !seen[$0]++'
)
# A file that is there but can't be read (a root-owned .env a container wrote, a file made 000)
# was not checked: section 3 names it and the check is partial, never "no keys". An account run
# counts these through fleet_ok, as files not checked, so its not_read leaves them out.
KEY_UNREAD=$(printf '%s\n' "$CANDIDATES" | while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && [ ! -r "$f" ] && printf '%s\n' "$f"; done)
N_KEY_UNREAD=$(count_lines "$KEY_UNREAD")
MATCHED=$(printf '%s\n' "$CANDIDATES" | fleet_filter | files_matching "$TR_KEYS")
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
  case "$NL$PS_PROFILES" in *"$NL$1$NL"*) KP=shell_rc; return 0 ;; esac
  # PowerShell's history on Windows, where typed keys most often end up
  if [ -n "$PSRL" ]; then case "$1" in "$PSRL"/*_history.txt) KP=shell_history; return 0 ;; esac; fi
  case "${1##*/}" in .env|.env.*|.envrc) KP=env_file; return 0 ;; esac
  case "$MCP_SET" in *"|$1|"*) KP=mcp_config; return 0 ;; esac
  case "$1" in
    "$H"/.claude/*|"$H"/.codex/*|"$H"/.gemini/*|"$H"/.cursor/*|"$H"/.codeium/*|"$H"/.continue/*) KP=agent_config; return 0 ;;
    "$H"/.copilot/*|"$H"/.config/goose/*|"$H"/.config/opencode/*|"$H"/.local/share/opencode/*|"$H"/.aider*|"$AS"/Claude/*|"$GOOSE_CFG"/*) KP=agent_config; return 0 ;;
    "$H"/.cline/*|"${CLINE_DATA_DIR:-$H/.cline/data}"/*|"${CLINE_DIR:-$H/.cline}"/*|"${CLINE_PROVIDER_SETTINGS_PATH:-$H/.cline/data/settings/providers.json}") KP=agent_config; return 0 ;;
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
if [ "$KEY_FILES" -eq 0 ] && [ "$N_KEY_UNREAD" -gt 0 ]; then progress w "No keys in the files read, but $(plural "$N_KEY_UNREAD" "file" "files") could not be read"
elif [ "$KEY_FILES" -eq 0 ]; then progress o "No keys in shell profiles, history, agent configs or .env files"; fi

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
unread_files() { # files on stdin that are there but can't be read, each once; with "big", or too big to read
  while IFS= read -r _uf; do [ -n "$_uf" ] && [ -f "$_uf" ] && { [ ! -r "$_uf" ] || { [ -n "${1:-}" ] && too_big "$_uf"; }; } && printf '%s\n' "$_uf"; done | awk '!s[$0]++'
}
# Section 2's files and section 4's that are there but can't be read: what they hold was not checked,
# so those sections name them and never read clean, as section 3 does for key files.
SEC2_UNREAD=$({ printf '%s\n' "$MCP_LIST" | unread_files; printf '%s\n%s\n%s\n' "$ALLOW_FILES" "$TASK_FILES" "$VSC_SETTINGS" | unread_files big; } | awk '!s[$0]++')
N_SEC2_UNREAD=$(count_lines "$SEC2_UNREAD")
ALLOW_UNREAD=$(printf '%s\n%s\n%s\n' "$ALLOW_FILES" "$H/.claude/settings.json" "$H/.claude/settings.local.json" | unread_files big)
N_ALLOW_UNREAD=$(count_lines "$ALLOW_UNREAD")
ALLOW_ALL=$(printf '%s\n%s\n%s\n' "$ALLOW_FILES" "$H/.claude/settings.json" "$H/.claude/settings.local.json" | grep -v '^$' | sort -u | fleet_filter |
  while IFS= read -r _f; do too_big "$_f" || printf '%s\n' "$_f"; done | files_matching "$TR_KEYS|$P_ASSIGN")
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
# Poetry's, pipenv's and Hatch's own folders of environments, as each documents them: Poetry's cache
# folder's virtualenvs, pipenv's XDG_DATA_HOME/virtualenvs (~/.virtualenvs on Windows, above) and
# Hatch's data folder's env/virtual, under LOCALAPPDATA on Windows, ~/Library on a Mac and the XDG
# folders on Linux.
if [ "$WIN" -eq 1 ]; then
  PY_ROOTS="$PY_ROOTS
$H/pipx
$WLAPP/pipx
$WAPP/uv
$WLAPP/Programs/Python
$WAPP/Python
$WLAPP/miniconda3
$WLAPP/anaconda3
$WLAPP/pypoetry/Cache/virtualenvs
$WLAPP/hatch/env/virtual"
  [ -n "$_pd" ] && PY_ROOTS="$PY_ROOTS
$_pd/miniconda3
$_pd/anaconda3"
else
  _xd=${XDG_DATA_HOME:-}; case "$_xd" in /*) ;; *) _xd="$H/.local/share" ;; esac
  _xc=${XDG_CACHE_HOME:-}; case "$_xc" in /*) ;; *) _xc="$H/.cache" ;; esac
  PY_ROOTS="$PY_ROOTS
$H/Library/Caches/pypoetry/virtualenvs
$H/Library/Application Support/hatch/env/virtual
$_xc/pypoetry/virtualenvs
$_xd/virtualenvs
$_xd/hatch/env/virtual"
fi
# Each tool's own setting moves its folder: POETRY_VIRTUALENVS_PATH (or POETRY_CACHE_DIR's virtualenvs),
# pipenv's WORKON_HOME and HATCH_DATA_DIR's env/virtual.
for _pv in "${POETRY_VIRTUALENVS_PATH:-}" "${POETRY_CACHE_DIR:+$POETRY_CACHE_DIR/virtualenvs}" "${WORKON_HOME:-}" "${HATCH_DATA_DIR:+$HATCH_DATA_DIR/env/virtual}"; do
  case "$_pv" in /*) PY_ROOTS="$PY_ROOTS
$_pv" ;; esac
done
# >>> bad-pypi: generated from data/bad-pypi.tsv by tools/gen.sh. Edit that file, then run it.
BAD_PYPI="litellm 1.107.0 litellm all
litellm 1.82.7 litellmmar all
litellm 1.82.8 litellmmar all
mistralai 2.4.6 mistralpy linux
guardrails_ai 0.10.1 guardrails linux
lightning 2.6.2 lightning all
lightning 2.6.3 lightning all"
PY_INCIDENTS="litellm litellmmar mistralpy guardrails lightning"
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
py_short() { # the first word of each incident's name, as "A, B and C"; two LiteLLM incidents say LiteLLM once
  _ps=""; _pn=0; _pk=0; _pw="|"
  for _pi in $1; do
    _pnm=$(incident_name "$_pi")
    case "$_pw" in *"|${_pnm%% *}|"*) ;; *) _pw="$_pw${_pnm%% *}|"; _pn=$((_pn + 1)) ;; esac
  done
  _pw=${_pw#|}
  while [ -n "$_pw" ]; do
    _w=${_pw%%|*}; _pw=${_pw#*|}; _pk=$((_pk + 1))
    if [ "$_pk" -eq 1 ]; then _ps=$_w; elif [ "$_pk" -eq "$_pn" ]; then _ps="$_ps and $_w"; else _ps="$_ps, $_w"; fi
  done
  printf '%s' "$_ps"
}
progress i "Checking $(plural "$(printf '%s\n' "$SITES_ALL" | grep -c .)" "Python environment" "Python environments") for the $(py_short "$PY_INCIDENTS") malware"
SITE_IND=$(printf '%s\n' "$IND_TABLE" | awk -F '|' -v o="$_os" '$3 == "site" && ($2 == "all" || $2 == o) { print $1 " " $5 }')
TEMP_IND=$(printf '%s\n' "$IND_TABLE" | awk -F '|' -v o="$_os" '$3 == "temp" && ($2 == "all" || $2 == o) { print $1 " " $4 " " $5 }')
# The advice shown under an incident's row when its temp files are found: the note of its temp lines.
temp_advice() { printf '%s\n' "$IND_TABLE" | awk -F '|' -v i="$1" '$1 == i && $3 == "temp" { print $6; exit }'; }
N_PY=0; N_LITE=0; LITE_VERS=""; LITE_BAD=""; LITE_PYC=""; PY_UPD=""; PY_UNREAD=0
while IFS= read -r sp; do
  [ -n "$sp" ] && [ -d "$sp" ] || continue
  # One that can't be opened was not checked: it is counted apart (an account run counts it as not
  # checked), never as an environment with no signs.
  if [ ! -r "$sp" ] || [ ! -x "$sp" ]; then
    PY_UNREAD=$((PY_UNREAD + 1)); [ -n "$FLEET_NR" ] && printf '%s\n' "$sp" >> "$FLEET_NR"; continue
  fi
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
MARKS=""; _seen_t="|"; FLEET_TMPMARK=""; FLEET_TMPWIPER=0
# An account run looks in the account's own temp folder, the one macOS gives each account under
# /var/folders, and in the shared /tmp only for markers that must be the account's own (owner yes):
# the other markers there are the Mac's, checked by root.
_utmp=""
if [ "$ACCTRUN" -eq 1 ]; then _utmp=${GIRD_CHECK_FLEET_USER_TMP:-$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null)}; _utmp=${_utmp%/}; fi
for t in /tmp "${TMPDIR%/}" "$WTEMP" "$_utmp"; do
  [ -n "$t" ] && [ -d "$t" ] || continue
  if [ "$ACCTRUN" -eq 1 ]; then case "$t" in /tmp|"$_utmp") ;; *) continue ;; esac; fi
  case "$_seen_t" in *"|$t|"*) continue ;; esac; _seen_t="$_seen_t$t|"
  while read -r _i _own _g; do
    [ -n "$_g" ] || continue
    [ "$ACCTRUN" -eq 1 ] && [ "$t" = /tmp ] && [ "$t" != "$_utmp" ] && [ "$_own" != yes ] && continue
    # shellcheck disable=SC2086  # the name may end in a glob
    for m in "$t"/$_g; do
      [ -e "$m" ] || continue
      # Another user's file in the shared /tmp is not this person's sign (owner yes in
      # data/indicators.tsv), and nor is one linked, symbolically or hard, under a marker's name; %TEMP%
      # on Windows is the person's own folder.
      if [ "$_own" = yes ] && [ "$WIN" -eq 0 ]; then
        [ -O "$m" ] && [ ! -L "$m" ] && [ -n "$(find "$m" -prune -links 1 -print 2>/dev/null)" ] || continue
        # In fleet mode, another account can leave a file of this account's under a marker's name in the
        # shared /tmp (a hard link to it, once the original is renamed away): a possible sign there.
        if [ "$ACCTRUN" -eq 1 ] && [ "$t" = /tmp ] && [ "$t" != "$_utmp" ]; then FLEET_TMPMARK="$FLEET_TMPMARK $_i"; continue; fi
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
# A startup file of a Python incident (data/indicators.tsv) is a sign of its malware, shown in its row
# with its note and never as npm malware: PY_START holds "incident<TAB>file<TAB>note". gen.sh keeps
# such a file in the home folder, the person's own.
PY_START=""
while IFS='|' read -r _ii _io _ik _iown _ip _in; do
  [ "$_ik" = startup ] || continue
  case " $PY_INCIDENTS " in *" $_ii "*) ;; *) continue ;; esac
  case "$_io" in all|"$_os") ;; *) continue ;; esac
  [ -n "$_ip" ] && [ -e "$_ip" ] && PY_START="$PY_START$_ii$TAB$(rowsafe "$_ip")$TAB$_in
"
done <<EOF
$IND_TABLE
EOF
LOADER=0
if [ "$ACCTRUN" -eq 0 ] && [ -e /tmp/remote_code_loader.lock ] && command -v lsof >/dev/null 2>&1; then
  [ -n "$(lsof -t /tmp/remote_code_loader.lock 2>/dev/null)" ] && LOADER=1
fi
# A bad version in uv's cache: "incident<TAB>name<TAB>version" for each one found. The cache is
# walked once, for every version at once; the exact version only, so 2.4.6 is not 2.4.60 or
# 2.4.6.post1. uv keeps what it installs there (and uvx runs a tool from an environment it makes
# there), so such a version counts as its incident's sign (UV_HIT), as npm's cache does for npm;
# where its malware could not run (the os column), it is a version to update (PY_UPD).
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
UV_BAD=""; UV_HIT=""
while read -r _n _v _i _o; do
  [ -n "$_i" ] || continue
  if printf '%s\n' "$_uvf" | awk -v n="$_n-$_v" '{ b = $0; sub(/.*\//, "", b)
      if (b == n || index(b, n "-") == 1 || b == n ".dist-info" || b == n ".tar.gz" || b == n ".zip") { f = 1; exit } }
    END { exit !f }'; then
    UV_BAD="$UV_BAD$_i$TAB$_n$TAB$_v
"
    case "$_o" in all|"$_os") UV_HIT="$UV_HIT$_i${TAB}uv's cache: $_n $_v
" ;; *) PY_UPD="$PY_UPD$_i$TAB$_o${TAB}uv's cache: $_n $_v
" ;; esac
  fi
done <<EOF
$BAD_PYPI
EOF
PY_HITS=""
for _pi in $PY_INCIDENTS; do
  if printf '%s' "$LITE_BAD$MARKS$UV_HIT$PY_START" | grep -q "^$_pi$TAB" || { [ "$_pi" = litellm ] && [ "$LOADER" -eq 1 ]; }; then
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
wot-api 0.8.5 tanstack
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
@cap-js/db-service 2.10.1 minishai
@cap-js/postgres 2.2.2 minishai
@cap-js/sqlite 2.2.2 minishai
mbt 1.2.48 minishai
intercom-client 7.0.4 minishai
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
mastraqqq * mastra
caspian-day-js 1.11.23 mastra
@antv/a8 0.1.1 antv
@antv/a8 0.2.1 antv
@antv/adjust 0.3.5 antv
@antv/adjust 0.4.5 antv
@antv/algorithm 0.2.26 antv
@antv/algorithm 0.3.26 antv
@antv/async-hook 2.3.9 antv
@antv/async-hook 2.4.9 antv
@antv/attr 0.4.5 antv
@antv/attr 0.5.5 antv
@antv/ava 3.5.1 antv
@antv/ava 3.6.1 antv
@antv/ava-react 3.4.2 antv
@antv/ava-react 3.5.2 antv
@antv/awards 0.1.9 antv
@antv/awards 0.2.9 antv
@antv/calendar-heatmap 1.2.2 antv
@antv/calendar-heatmap 1.3.2 antv
@antv/chart-linter 1.2.6 antv
@antv/chart-linter 1.3.6 antv
@antv/chart-node-g6 0.1.4 antv
@antv/chart-node-g6 0.2.4 antv
@antv/chart-visualization-skills 0.2.3 antv
@antv/chart-visualization-skills 0.3.3 antv
@antv/ckb 2.1.4 antv
@antv/ckb 2.2.4 antv
@antv/color-schema 0.3.3 antv
@antv/color-schema 0.4.3 antv
@antv/color-util 2.1.6 antv
@antv/color-util 2.2.6 antv
@antv/component 2.2.11 antv
@antv/component 2.3.11 antv
@antv/coord 0.5.7 antv
@antv/coord 0.6.7 antv
@antv/d3-color 1.1.0 antv
@antv/d3-color 1.2.0 antv
@antv/d3-interpolate 1.1.3 antv
@antv/d3-interpolate 1.2.3 antv
@antv/data-samples 1.1.1 antv
@antv/data-samples 1.2.1 antv
@antv/data-set 0.12.8 antv
@antv/data-set 0.13.8 antv
@antv/data-wizard 2.1.4 antv
@antv/data-wizard 2.2.4 antv
@antv/dipper-component 0.1.4 antv
@antv/dipper-component 0.2.4 antv
@antv/dipper-hooks 0.3.1 antv
@antv/dipper-hooks 0.4.1 antv
@antv/dipper-map 1.1.10 antv
@antv/dipper-map 1.2.10 antv
@antv/dom-util 2.1.4 antv
@antv/dom-util 2.2.4 antv
@antv/dumi-theme-antv 0.9.4 antv
@antv/dumi-theme-antv 0.10.4 antv
@antv/dw-analyzer 1.2.5 antv
@antv/dw-analyzer 1.3.5 antv
@antv/dw-random 1.2.7 antv
@antv/dw-random 1.3.7 antv
@antv/dw-transform 1.2.7 antv
@antv/dw-transform 1.3.7 antv
@antv/dw-util 1.2.4 antv
@antv/dw-util 1.3.4 antv
@antv/event-emitter 0.2.3 antv
@antv/event-emitter 0.3.3 antv
@antv/expr 1.1.2 antv
@antv/expr 1.2.2 antv
@antv/f-charts 0.1.0 antv
@antv/f-charts 0.2.0 antv
@antv/f-engine 1.11.0 antv
@antv/f-engine 1.12.0 antv
@antv/f-lottie 1.11.0 antv
@antv/f-lottie 1.12.0 antv
@antv/f-my 1.11.0 antv
@antv/f-my 1.12.0 antv
@antv/f-react 1.11.0 antv
@antv/f-react 1.12.0 antv
@antv/f-test-utils 1.1.9 antv
@antv/f-test-utils 1.2.9 antv
@antv/f-vue 1.11.0 antv
@antv/f-vue 1.12.0 antv
@antv/f-wx 1.11.0 antv
@antv/f-wx 1.12.0 antv
@antv/f2 5.15.0 antv
@antv/f2 5.16.0 antv
@antv/f2-algorithm 5.8.0 antv
@antv/f2-algorithm 5.9.0 antv
@antv/f2-canvas 1.1.5 antv
@antv/f2-canvas 1.2.5 antv
@antv/f2-context 0.1.1 antv
@antv/f2-context 0.2.1 antv
@antv/f2-graphic 0.1.16 antv
@antv/f2-graphic 0.2.16 antv
@antv/f2-my 4.1.52 antv
@antv/f2-my 4.2.52 antv
@antv/f2-react 5.15.0 antv
@antv/f2-react 5.16.0 antv
@antv/f2-site 4.1.42 antv
@antv/f2-site 4.2.42 antv
@antv/f2-vue 4.1.33 antv
@antv/f2-vue 4.2.33 antv
@antv/f2-wordcloud 5.15.0 antv
@antv/f2-wordcloud 5.16.0 antv
@antv/f2-wx 4.1.51 antv
@antv/f2-wx 4.2.51 antv
@antv/f6 0.1.19 antv
@antv/f6 0.2.19 antv
@antv/f6-alipay 0.1.7 antv
@antv/f6-alipay 0.2.7 antv
@antv/f6-core 0.1.2 antv
@antv/f6-core 0.2.2 antv
@antv/f6-element 0.1.1 antv
@antv/f6-element 0.2.1 antv
@antv/f6-hammerjs 0.1.2 antv
@antv/f6-hammerjs 0.2.2 antv
@antv/f6-plugin 1.1.6 antv
@antv/f6-plugin 1.2.6 antv
@antv/f6-ui 1.1.3 antv
@antv/f6-ui 1.2.3 antv
@antv/f6-wx 0.1.7 antv
@antv/f6-wx 0.2.7 antv
@antv/g 6.4.1 antv
@antv/g 6.5.1 antv
@antv/g-base 0.6.16 antv
@antv/g-base 0.7.16 antv
@antv/g-camera-api 2.1.45 antv
@antv/g-camera-api 2.2.45 antv
@antv/g-canvas 2.3.0 antv
@antv/g-canvas 2.4.0 antv
@antv/g-canvaskit 1.2.1 antv
@antv/g-canvaskit 1.3.1 antv
@antv/g-compat 1.1.11 antv
@antv/g-compat 1.2.11 antv
@antv/g-components 2.1.42 antv
@antv/g-components 2.2.42 antv
@antv/g-css-layout-api 1.1.38 antv
@antv/g-css-layout-api 1.2.38 antv
@antv/g-css-typed-om-api 1.1.38 antv
@antv/g-css-typed-om-api 1.2.38 antv
@antv/g-device-api 1.7.13 antv
@antv/g-device-api 1.8.13 antv
@antv/g-dom-mutation-observer-api 2.1.42 antv
@antv/g-dom-mutation-observer-api 2.2.42 antv
@antv/g-gesture 3.1.42 antv
@antv/g-gesture 3.2.42 antv
@antv/g-image-exporter 1.1.42 antv
@antv/g-image-exporter 1.2.42 antv
@antv/g-layout-blocklike 1.8.49 antv
@antv/g-layout-blocklike 1.9.49 antv
@antv/g-lite 2.8.0 antv
@antv/g-lite 2.9.0 antv
@antv/g-lottie-player 1.2.1 antv
@antv/g-lottie-player 1.3.1 antv
@antv/g-math 3.2.0 antv
@antv/g-math 3.3.0 antv
@antv/g-mobile 1.2.5 antv
@antv/g-mobile 1.3.5 antv
@antv/g-mobile-canvas 1.2.1 antv
@antv/g-mobile-canvas 1.3.1 antv
@antv/g-mobile-canvas-element 1.1.42 antv
@antv/g-mobile-canvas-element 1.2.42 antv
@antv/g-mobile-svg 1.2.1 antv
@antv/g-mobile-svg 1.3.1 antv
@antv/g-mobile-webgl 1.2.1 antv
@antv/g-mobile-webgl 1.3.1 antv
@antv/g-pattern 2.1.42 antv
@antv/g-pattern 2.2.42 antv
@antv/g-perf 1.1.0 antv
@antv/g-perf 1.2.0 antv
@antv/g-plugin-3d 2.2.1 antv
@antv/g-plugin-3d 2.3.1 antv
@antv/g-plugin-a11y 1.5.1 antv
@antv/g-plugin-a11y 1.6.1 antv
@antv/g-plugin-annotation 1.3.0 antv
@antv/g-plugin-annotation 1.4.0 antv
@antv/g-plugin-box2d 2.2.1 antv
@antv/g-plugin-box2d 2.3.1 antv
@antv/g-plugin-canvas-path-generator 2.2.26 antv
@antv/g-plugin-canvas-path-generator 2.3.26 antv
@antv/g-plugin-canvas-picker 2.4.1 antv
@antv/g-plugin-canvas-picker 2.5.1 antv
@antv/g-plugin-canvas-renderer 2.6.1 antv
@antv/g-plugin-canvas-renderer 2.7.1 antv
@antv/g-plugin-canvaskit-renderer 2.4.1 antv
@antv/g-plugin-canvaskit-renderer 2.5.1 antv
@antv/g-plugin-control 2.2.1 antv
@antv/g-plugin-control 2.3.1 antv
@antv/g-plugin-css-select 2.2.1 antv
@antv/g-plugin-css-select 2.3.1 antv
@antv/g-plugin-device-renderer 2.7.1 antv
@antv/g-plugin-device-renderer 2.8.1 antv
@antv/g-plugin-dom-interaction 2.2.31 antv
@antv/g-plugin-dom-interaction 2.3.31 antv
@antv/g-plugin-dragndrop 2.2.1 antv
@antv/g-plugin-dragndrop 2.3.1 antv
@antv/g-plugin-gesture 2.2.1 antv
@antv/g-plugin-gesture 2.3.1 antv
@antv/g-plugin-gpgpu 1.10.20 antv
@antv/g-plugin-gpgpu 1.11.20 antv
@antv/g-plugin-html-renderer 2.4.1 antv
@antv/g-plugin-html-renderer 2.5.1 antv
@antv/g-plugin-image-loader 2.4.1 antv
@antv/g-plugin-image-loader 2.5.1 antv
@antv/g-plugin-matterjs 2.2.1 antv
@antv/g-plugin-matterjs 2.3.1 antv
@antv/g-plugin-mobile-interaction 1.1.42 antv
@antv/g-plugin-mobile-interaction 1.2.42 antv
@antv/g-plugin-physx 2.2.1 antv
@antv/g-plugin-physx 2.3.1 antv
@antv/g-plugin-rough-canvas-renderer 2.2.1 antv
@antv/g-plugin-rough-canvas-renderer 2.3.1 antv
@antv/g-plugin-rough-svg-renderer 2.2.1 antv
@antv/g-plugin-rough-svg-renderer 2.3.1 antv
@antv/g-plugin-svg-picker 2.1.46 antv
@antv/g-plugin-svg-picker 2.2.46 antv
@antv/g-plugin-svg-renderer 2.5.1 antv
@antv/g-plugin-svg-renderer 2.6.1 antv
@antv/g-plugin-webgl-device 1.10.17 antv
@antv/g-plugin-webgl-device 1.11.17 antv
@antv/g-plugin-webgl-renderer 1.1.26 antv
@antv/g-plugin-webgl-renderer 1.2.26 antv
@antv/g-plugin-webgpu-device 1.10.17 antv
@antv/g-plugin-webgpu-device 1.11.17 antv
@antv/g-plugin-yoga 2.4.1 antv
@antv/g-plugin-yoga 2.5.1 antv
@antv/g-plugin-zdog-canvas-renderer 2.2.1 antv
@antv/g-plugin-zdog-canvas-renderer 2.3.1 antv
@antv/g-plugin-zdog-svg-renderer 2.2.1 antv
@antv/g-plugin-zdog-svg-renderer 2.3.1 antv
@antv/g-shader-components 2.1.0 antv
@antv/g-shader-components 2.2.0 antv
@antv/g-svg 2.2.1 antv
@antv/g-svg 2.3.1 antv
@antv/g-web-animations-api 2.2.32 antv
@antv/g-web-animations-api 2.3.32 antv
@antv/g-web-components 2.2.1 antv
@antv/g-web-components 2.3.1 antv
@antv/g-webgl 2.2.1 antv
@antv/g-webgl 2.3.1 antv
@antv/g-webgl-compute 0.1.1 antv
@antv/g-webgl-compute 0.2.1 antv
@antv/g-webgpu 2.2.1 antv
@antv/g-webgpu 2.3.1 antv
@antv/g-webgpu-compiler 0.8.2 antv
@antv/g-webgpu-compiler 0.9.2 antv
@antv/g-webgpu-core 0.8.2 antv
@antv/g-webgpu-core 0.9.2 antv
@antv/g-webgpu-engine 0.8.2 antv
@antv/g-webgpu-engine 0.9.2 antv
@antv/g-webgpu-raytracer 0.6.1 antv
@antv/g-webgpu-raytracer 0.7.1 antv
@antv/g-webgpu-unitchart 0.6.1 antv
@antv/g-webgpu-unitchart 0.7.1 antv
@antv/g2 5.5.8 antv
@antv/g2 5.6.8 antv
@antv/g2-brush 0.1.2 antv
@antv/g2-brush 0.2.2 antv
@antv/g2-extension-3d 0.3.0 antv
@antv/g2-extension-3d 0.4.0 antv
@antv/g2-extension-ava 0.3.0 antv
@antv/g2-extension-ava 0.4.0 antv
@antv/g2-extension-plot 0.3.2 antv
@antv/g2-extension-plot 0.4.2 antv
@antv/g2-plugin-slider 2.2.1 antv
@antv/g2-plugin-slider 2.3.1 antv
@antv/g2-ssr 0.3.0 antv
@antv/g2-ssr 0.4.0 antv
@antv/g2plot 2.5.35 antv
@antv/g2plot 2.6.35 antv
@antv/g2plot-schemas 1.3.2 antv
@antv/g2plot-schemas 1.4.2 antv
@antv/g6 5.2.1 antv
@antv/g6 5.3.1 antv
@antv/g6-alipay 0.1.1 antv
@antv/g6-alipay 0.2.1 antv
@antv/g6-cli 0.1.4 antv
@antv/g6-cli 0.2.4 antv
@antv/g6-core 0.9.24 antv
@antv/g6-core 0.10.24 antv
@antv/g6-editor 1.3.0 antv
@antv/g6-editor 1.4.0 antv
@antv/g6-element 0.9.25 antv
@antv/g6-element 0.10.25 antv
@antv/g6-extension-3d 0.2.23 antv
@antv/g6-extension-3d 0.3.23 antv
@antv/g6-extension-react 0.3.7 antv
@antv/g6-extension-react 0.4.7 antv
@antv/g6-mobile 0.2.2 antv
@antv/g6-mobile 0.3.2 antv
@antv/g6-pc 0.9.25 antv
@antv/g6-pc 0.10.25 antv
@antv/g6-plugin 0.9.25 antv
@antv/g6-plugin 0.10.25 antv
@antv/g6-plugin-map-view 0.1.4 antv
@antv/g6-plugin-map-view 0.2.4 antv
@antv/g6-plugins 1.1.9 antv
@antv/g6-plugins 1.2.9 antv
@antv/g6-react-node 1.5.8 antv
@antv/g6-react-node 1.6.8 antv
@antv/g6-ssr 0.2.1 antv
@antv/g6-ssr 0.3.1 antv
@antv/g6-wx 0.1.1 antv
@antv/g6-wx 0.2.1 antv
@antv/gatsby-theme 0.2.0 antv
@antv/gatsby-theme 0.3.0 antv
@antv/geo-coord 1.1.8 antv
@antv/geo-coord 1.2.8 antv
@antv/gi-assets-advance 2.6.22 antv
@antv/gi-assets-advance 2.7.22 antv
@antv/gi-assets-algorithm 2.4.19 antv
@antv/gi-assets-algorithm 2.5.19 antv
@antv/gi-assets-basic 2.5.40 antv
@antv/gi-assets-basic 2.6.40 antv
@antv/gi-assets-galaxybase 1.3.15 antv
@antv/gi-assets-galaxybase 1.4.15 antv
@antv/gi-assets-graphscope 2.2.15 antv
@antv/gi-assets-graphscope 2.3.15 antv
@antv/gi-assets-hugegraph 1.2.15 antv
@antv/gi-assets-hugegraph 1.3.15 antv
@antv/gi-assets-janusgraph 1.2.15 antv
@antv/gi-assets-janusgraph 1.3.15 antv
@antv/gi-assets-neo4j 2.2.15 antv
@antv/gi-assets-neo4j 2.3.15 antv
@antv/gi-assets-scene 2.3.21 antv
@antv/gi-assets-scene 2.4.21 antv
@antv/gi-assets-tugraph 2.2.15 antv
@antv/gi-assets-tugraph 2.3.15 antv
@antv/gi-assets-tugraph-analytics 0.3.15 antv
@antv/gi-assets-tugraph-analytics 0.4.15 antv
@antv/gi-assets-xlab 0.2.30 antv
@antv/gi-assets-xlab 0.3.30 antv
@antv/gi-cli 1.3.11 antv
@antv/gi-cli 1.4.11 antv
@antv/gi-common-components 1.4.16 antv
@antv/gi-common-components 1.5.16 antv
@antv/gi-mock-data 1.1.5 antv
@antv/gi-mock-data 1.2.5 antv
@antv/gi-public-data 1.1.1 antv
@antv/gi-public-data 1.2.1 antv
@antv/gi-sdk 3.1.0 antv
@antv/gi-sdk 3.2.0 antv
@antv/gi-sdk-app 1.3.10 antv
@antv/gi-sdk-app 1.4.10 antv
@antv/gi-theme-antd 0.7.11 antv
@antv/gi-theme-antd 0.8.11 antv
@antv/github-config-cli 0.2.0 antv
@antv/github-config-cli 0.3.0 antv
@antv/gl-matrix 2.8.1 antv
@antv/gl-matrix 2.9.1 antv
@antv/gpt-vis 1.1.0 antv
@antv/gpt-vis 1.2.0 antv
@antv/gpt-vis-ssr 0.4.7 antv
@antv/gpt-vis-ssr 0.5.7 antv
@antv/graphin 3.1.5 antv
@antv/graphin 3.2.5 antv
@antv/graphin-components 2.5.1 antv
@antv/graphin-components 2.6.1 antv
@antv/graphin-graphscope 1.1.5 antv
@antv/graphin-graphscope 1.2.5 antv
@antv/graphin-icons 1.1.0 antv
@antv/graphin-icons 1.2.0 antv
@antv/graphlib 2.1.4 antv
@antv/graphlib 2.2.4 antv
@antv/hierarchy 0.8.1 antv
@antv/hierarchy 0.9.1 antv
@antv/infographic 0.3.19 antv
@antv/infographic 0.4.19 antv
@antv/insight-component 1.1.0 antv
@antv/insight-component 1.2.0 antv
@antv/interaction 0.2.5 antv
@antv/interaction 0.3.5 antv
@antv/istanbul 0.1.0 antv
@antv/istanbul 0.2.0 antv
@antv/knowledge 1.2.4 antv
@antv/knowledge 1.3.4 antv
@antv/l7 2.26.10 antv
@antv/l7 2.27.10 antv
@antv/l7-component 2.26.10 antv
@antv/l7-component 2.27.10 antv
@antv/l7-composite-layers 0.18.1 antv
@antv/l7-composite-layers 0.19.1 antv
@antv/l7-core 2.26.10 antv
@antv/l7-core 2.27.10 antv
@antv/l7-district 2.4.12 antv
@antv/l7-district 2.5.12 antv
@antv/l7-draw 3.2.5 antv
@antv/l7-draw 3.3.5 antv
@antv/l7-editor 1.2.13 antv
@antv/l7-editor 1.3.13 antv
@antv/l7-extension-g-layer 1.1.0 antv
@antv/l7-extension-g-layer 1.2.0 antv
@antv/l7-layers 2.26.10 antv
@antv/l7-layers 2.27.10 antv
@antv/l7-leaflet 1.1.2 antv
@antv/l7-leaflet 1.2.2 antv
@antv/l7-map 2.26.10 antv
@antv/l7-map 2.27.10 antv
@antv/l7-mapkit 0.6.0 antv
@antv/l7-mapkit 0.7.0 antv
@antv/l7-maps 2.26.10 antv
@antv/l7-maps 2.27.10 antv
@antv/l7-mini 2.21.8 antv
@antv/l7-mini 2.22.8 antv
@antv/l7-pass 1.1.0 antv
@antv/l7-pass 1.2.0 antv
@antv/l7-react 2.5.3 antv
@antv/l7-react 2.6.3 antv
@antv/l7-renderer 2.26.10 antv
@antv/l7-renderer 2.27.10 antv
@antv/l7-scene 2.26.10 antv
@antv/l7-scene 2.27.10 antv
@antv/l7-source 2.26.10 antv
@antv/l7-source 2.27.10 antv
@antv/l7-three 2.26.10 antv
@antv/l7-three 2.27.10 antv
@antv/l7-utils 2.26.10 antv
@antv/l7-utils 2.27.10 antv
@antv/l7plot 0.6.11 antv
@antv/l7plot 0.7.11 antv
@antv/l7plot-component 0.1.11 antv
@antv/l7plot-component 0.2.11 antv
@antv/larkmap 1.6.1 antv
@antv/larkmap 1.7.1 antv
@antv/layout-gpu 1.2.7 antv
@antv/layout-gpu 1.3.7 antv
@antv/layout-wasm 1.5.2 antv
@antv/layout-wasm 1.6.2 antv
@antv/li-aiearth-assets 0.5.7 antv
@antv/li-aiearth-assets 0.6.7 antv
@antv/li-analysis-assets 1.10.1 antv
@antv/li-analysis-assets 1.11.1 antv
@antv/li-core-assets 1.4.7 antv
@antv/li-core-assets 1.5.7 antv
@antv/li-editor 1.7.1 antv
@antv/li-editor 1.8.1 antv
@antv/li-p2 1.9.2 antv
@antv/li-p2 1.10.2 antv
@antv/li-sam-assets 0.2.4 antv
@antv/li-sam-assets 0.3.4 antv
@antv/li-sdk 1.6.1 antv
@antv/li-sdk 1.7.1 antv
@antv/lite-insight 2.2.1 antv
@antv/lite-insight 2.3.1 antv
@antv/matrix-util 3.1.4 antv
@antv/matrix-util 3.2.4 antv
@antv/mcp-server-antv 0.2.8 antv
@antv/mcp-server-antv 0.3.8 antv
@antv/mcp-server-chart 0.10.10 antv
@antv/mcp-server-chart 0.11.10 antv
@antv/my-f2 2.2.7 antv
@antv/my-f2 2.3.7 antv
@antv/my-f2-pc 0.2.1 antv
@antv/my-f2-pc 0.3.1 antv
@antv/narrative-text-editor 0.3.20 antv
@antv/narrative-text-editor 0.4.20 antv
@antv/narrative-text-schema 0.4.7 antv
@antv/narrative-text-schema 0.5.7 antv
@antv/narrative-text-vis 0.4.16 antv
@antv/narrative-text-vis 0.5.16 antv
@antv/path-util 3.1.1 antv
@antv/path-util 3.2.1 antv
@antv/react-g 2.2.1 antv
@antv/react-g 2.3.1 antv
@antv/s2 2.8.1 antv
@antv/s2 2.9.1 antv
@antv/s2-react 2.4.1 antv
@antv/s2-react 2.5.1 antv
@antv/s2-react-components 2.2.2 antv
@antv/s2-react-components 2.3.2 antv
@antv/s2-ssr 0.2.1 antv
@antv/s2-ssr 0.3.1 antv
@antv/s2-vue 2.3.0 antv
@antv/s2-vue 2.4.0 antv
@antv/sam 0.3.0 antv
@antv/sam 0.4.0 antv
@antv/scale 0.6.2 antv
@antv/scale 0.7.2 antv
@antv/semantic-release-pnpm 1.1.4 antv
@antv/semantic-release-pnpm 1.2.4 antv
@antv/smart-color 0.3.1 antv
@antv/smart-color 0.4.1 antv
@antv/stat 0.1.2 antv
@antv/stat 0.2.2 antv
@antv/t8 0.4.0 antv
@antv/t8 0.5.0 antv
@antv/thumbnails 2.1.0 antv
@antv/thumbnails 2.2.0 antv
@antv/thumbnails-component 2.1.0 antv
@antv/thumbnails-component 2.2.0 antv
@antv/torch 1.1.6 antv
@antv/torch 1.2.6 antv
@antv/translator 1.1.1 antv
@antv/translator 1.2.1 antv
@antv/util 3.4.11 antv
@antv/util 3.5.11 antv
@antv/vendor 1.1.11 antv
@antv/vendor 1.2.11 antv
@antv/vis-predict-engine 0.2.1 antv
@antv/vis-predict-engine 0.3.1 antv
@antv/webgpu-graph 1.1.0 antv
@antv/webgpu-graph 1.2.0 antv
@antv/word-scale-chart 0.4.4 antv
@antv/word-scale-chart 0.5.4 antv
@antv/wx-f2 2.2.1 antv
@antv/wx-f2 2.3.1 antv
@antv/x6 3.2.7 antv
@antv/x6 3.3.7 antv
@antv/x6-angular-shape 3.1.1 antv
@antv/x6-angular-shape 3.2.1 antv
@antv/x6-common 2.1.17 antv
@antv/x6-common 2.2.17 antv
@antv/x6-components 0.11.7 antv
@antv/x6-components 0.12.7 antv
@antv/x6-geometry 2.1.5 antv
@antv/x6-geometry 2.2.5 antv
@antv/x6-plugin-clipboard 2.2.6 antv
@antv/x6-plugin-clipboard 2.3.6 antv
@antv/x6-plugin-dnd 2.2.1 antv
@antv/x6-plugin-dnd 2.3.1 antv
@antv/x6-plugin-export 2.2.6 antv
@antv/x6-plugin-export 2.3.6 antv
@antv/x6-plugin-history 2.3.4 antv
@antv/x6-plugin-history 2.4.4 antv
@antv/x6-plugin-keyboard 2.3.3 antv
@antv/x6-plugin-keyboard 2.4.3 antv
@antv/x6-plugin-minimap 2.1.7 antv
@antv/x6-plugin-minimap 2.2.7 antv
@antv/x6-plugin-scroller 2.1.10 antv
@antv/x6-plugin-scroller 2.2.10 antv
@antv/x6-plugin-selection 2.3.2 antv
@antv/x6-plugin-selection 2.4.2 antv
@antv/x6-plugin-snapline 2.2.7 antv
@antv/x6-plugin-snapline 2.3.7 antv
@antv/x6-plugin-stencil 2.2.5 antv
@antv/x6-plugin-stencil 2.3.5 antv
@antv/x6-plugin-transform 2.2.8 antv
@antv/x6-plugin-transform 2.3.8 antv
@antv/x6-react 0.2.26 antv
@antv/x6-react 0.3.26 antv
@antv/x6-react-components 2.1.9 antv
@antv/x6-react-components 2.2.9 antv
@antv/x6-react-shape 3.1.1 antv
@antv/x6-react-shape 3.2.1 antv
@antv/x6-vector 1.5.2 antv
@antv/x6-vector 1.6.2 antv
@antv/x6-vue-shape 3.1.2 antv
@antv/x6-vue-shape 3.2.2 antv
@antv/x6-vue3-shape 1.1.0 antv
@antv/x6-vue3-shape 1.2.0 antv
@antv/xflow 2.2.13 antv
@antv/xflow 2.3.13 antv
@antv/xflow-core 1.1.55 antv
@antv/xflow-core 1.2.55 antv
@antv/xflow-diff 1.1.0 antv
@antv/xflow-diff 1.2.0 antv
@antv/xflow-extension 1.1.55 antv
@antv/xflow-extension 1.2.55 antv
@antv/xflow-hook 1.1.55 antv
@antv/xflow-hook 1.2.55 antv
@cap-js/openapi 1.4.1 antv
@lint-md/cli 2.1.0 antv
@lint-md/cli 2.2.0 antv
@lint-md/core 2.1.0 antv
@lint-md/core 2.2.0 antv
@lint-md/parser 0.1.14 antv
@lint-md/parser 0.2.14 antv
@openclaw-cn/cli 1.4.1 antv
@openclaw-cn/feishu 0.2.11 antv
@openclaw-cn/libsignal 2.1.1 antv
@openclaw-cn/toutiao-ops 1.2.4 antv
@starmind/collector-cli 0.3.10 antv
ai-figure 0.5.0 antv
ai-figure 0.6.0 antv
amapcn 0.2.2 antv
amapcn 0.3.2 antv
ast-plugin 0.1.7 antv
ast-plugin 0.2.7 antv
babel-plugin-version 0.3.3 antv
babel-plugin-version 0.4.3 antv
boring-avatars-vanilla 1.1.2 antv
boring-avatars-vanilla 1.2.2 antv
byte-parser 1.1.0 antv
byte-parser 1.2.0 antv
canvas-nest.js 2.1.4 antv
canvas-nest.js 2.2.4 antv
echarts-for-react 3.0.7 antv
echarts-for-react 3.1.7 antv
echarts-for-react 3.2.7 antv
filesize.js 2.1.0 antv
filesize.js 2.2.0 antv
fixed-round 1.1.2 antv
fixed-round 1.2.2 antv
gantt-for-react 0.3.0 antv
gantt-for-react 0.4.0 antv
jest-canvas-mock 2.5.3 antv
jest-canvas-mock 2.6.3 antv
jest-canvas-mock 2.7.3 antv
jest-date-mock 1.0.11 antv
jest-date-mock 1.1.11 antv
jest-date-mock 1.2.11 antv
jest-electron 0.2.12 antv
jest-electron 0.3.12 antv
jest-expect 0.1.1 antv
jest-expect 0.2.1 antv
jest-less-loader 0.3.0 antv
jest-less-loader 0.4.0 antv
jest-random-mock 1.1.0 antv
jest-random-mock 1.2.0 antv
jest-url-loader 0.2.0 antv
jest-url-loader 0.3.0 antv
limit-size 0.2.4 antv
limit-size 0.3.4 antv
lint-md 0.3.0 antv
lint-md 0.4.0 antv
lint-md-cli 0.2.2 antv
lint-md-cli 0.3.2 antv
mcp-echarts 0.8.1 antv
mcp-echarts 0.9.1 antv
mcp-mermaid 0.5.1 antv
mcp-mermaid 0.6.1 antv
miz 1.1.1 antv
miz 1.2.1 antv
onfire.js 2.1.1 antv
onfire.js 2.2.1 antv
openclaw-cn 0.3.0 antv
react-adsense 0.2.0 antv
react-adsense 0.3.0 antv
relationship.js 1.3.9 antv
relationship.js 1.4.9 antv
ribbon.js 1.1.2 antv
size-sensor 1.0.4 antv
size-sensor 1.1.4 antv
size-sensor 1.2.4 antv
slice.js 1.2.1 antv
slice.js 1.3.1 antv
timeago-react 3.1.7 antv
timeago-react 3.2.7 antv
timeago.js 4.1.2 antv
timeago.js 4.2.2 antv
uri-parse 1.1.0 antv
uri-parse 1.2.0 antv
word-width 1.1.1 antv
word-width 1.2.1 antv
xmorse 1.1.0 antv
xmorse 1.2.0 antv
@redhat-cloud-services/chrome 2.3.1 redhat
@redhat-cloud-services/chrome 2.3.2 redhat
@redhat-cloud-services/chrome 2.3.4 redhat
@redhat-cloud-services/compliance-client 4.0.3 redhat
@redhat-cloud-services/compliance-client 4.0.4 redhat
@redhat-cloud-services/compliance-client 4.0.6 redhat
@redhat-cloud-services/config-manager-client 5.0.4 redhat
@redhat-cloud-services/config-manager-client 5.0.5 redhat
@redhat-cloud-services/config-manager-client 5.0.7 redhat
@redhat-cloud-services/entitlements-client 4.0.11 redhat
@redhat-cloud-services/entitlements-client 4.0.12 redhat
@redhat-cloud-services/entitlements-client 4.0.14 redhat
@redhat-cloud-services/eslint-config-redhat-cloud-services 3.2.1 redhat
@redhat-cloud-services/eslint-config-redhat-cloud-services 3.2.2 redhat
@redhat-cloud-services/eslint-config-redhat-cloud-services 3.2.4 redhat
@redhat-cloud-services/frontend-components 7.7.2 redhat
@redhat-cloud-services/frontend-components 7.7.3 redhat
@redhat-cloud-services/frontend-components 7.7.5 redhat
@redhat-cloud-services/frontend-components-advisor-components 3.8.2 redhat
@redhat-cloud-services/frontend-components-advisor-components 3.8.4 redhat
@redhat-cloud-services/frontend-components-advisor-components 3.8.6 redhat
@redhat-cloud-services/frontend-components-config 6.11.3 redhat
@redhat-cloud-services/frontend-components-config 6.11.4 redhat
@redhat-cloud-services/frontend-components-config 6.11.6 redhat
@redhat-cloud-services/frontend-components-config-utilities 4.11.2 redhat
@redhat-cloud-services/frontend-components-config-utilities 4.11.3 redhat
@redhat-cloud-services/frontend-components-config-utilities 4.11.5 redhat
@redhat-cloud-services/frontend-components-notifications 6.9.2 redhat
@redhat-cloud-services/frontend-components-notifications 6.9.3 redhat
@redhat-cloud-services/frontend-components-notifications 6.9.5 redhat
@redhat-cloud-services/frontend-components-remediations 4.9.2 redhat
@redhat-cloud-services/frontend-components-remediations 4.9.3 redhat
@redhat-cloud-services/frontend-components-remediations 4.9.5 redhat
@redhat-cloud-services/frontend-components-testing 1.2.1 redhat
@redhat-cloud-services/frontend-components-testing 1.2.2 redhat
@redhat-cloud-services/frontend-components-testing 1.2.4 redhat
@redhat-cloud-services/frontend-components-translations 4.4.1 redhat
@redhat-cloud-services/frontend-components-translations 4.4.2 redhat
@redhat-cloud-services/frontend-components-translations 4.4.4 redhat
@redhat-cloud-services/frontend-components-utilities 7.4.1 redhat
@redhat-cloud-services/frontend-components-utilities 7.4.2 redhat
@redhat-cloud-services/frontend-components-utilities 7.4.4 redhat
@redhat-cloud-services/hcc-feo-mcp 0.3.1 redhat
@redhat-cloud-services/hcc-feo-mcp 0.3.2 redhat
@redhat-cloud-services/hcc-feo-mcp 0.3.4 redhat
@redhat-cloud-services/hcc-kessel-mcp 0.3.1 redhat
@redhat-cloud-services/hcc-kessel-mcp 0.3.2 redhat
@redhat-cloud-services/hcc-kessel-mcp 0.3.4 redhat
@redhat-cloud-services/hcc-pf-mcp 0.6.1 redhat
@redhat-cloud-services/hcc-pf-mcp 0.6.2 redhat
@redhat-cloud-services/hcc-pf-mcp 0.6.4 redhat
@redhat-cloud-services/host-inventory-client 5.0.3 redhat
@redhat-cloud-services/host-inventory-client 5.0.4 redhat
@redhat-cloud-services/host-inventory-client 5.0.6 redhat
@redhat-cloud-services/insights-client 4.0.4 redhat
@redhat-cloud-services/insights-client 4.0.5 redhat
@redhat-cloud-services/insights-client 4.0.7 redhat
@redhat-cloud-services/integrations-client 6.0.4 redhat
@redhat-cloud-services/integrations-client 6.0.5 redhat
@redhat-cloud-services/integrations-client 6.0.7 redhat
@redhat-cloud-services/javascript-clients-shared 2.0.8 redhat
@redhat-cloud-services/javascript-clients-shared 2.0.9 redhat
@redhat-cloud-services/javascript-clients-shared 2.0.11 redhat
@redhat-cloud-services/notifications-client 6.1.4 redhat
@redhat-cloud-services/notifications-client 6.1.5 redhat
@redhat-cloud-services/notifications-client 6.1.7 redhat
@redhat-cloud-services/patch-client 4.0.4 redhat
@redhat-cloud-services/patch-client 4.0.5 redhat
@redhat-cloud-services/patch-client 4.0.7 redhat
@redhat-cloud-services/quickstarts-client 4.0.11 redhat
@redhat-cloud-services/quickstarts-client 4.0.12 redhat
@redhat-cloud-services/quickstarts-client 4.0.14 redhat
@redhat-cloud-services/rbac-client 9.0.3 redhat
@redhat-cloud-services/rbac-client 9.0.4 redhat
@redhat-cloud-services/rbac-client 9.0.6 redhat
@redhat-cloud-services/remediations-client 4.0.4 redhat
@redhat-cloud-services/remediations-client 4.0.5 redhat
@redhat-cloud-services/remediations-client 4.0.7 redhat
@redhat-cloud-services/rule-components 4.7.2 redhat
@redhat-cloud-services/rule-components 4.7.3 redhat
@redhat-cloud-services/rule-components 4.7.5 redhat
@redhat-cloud-services/sources-client 3.0.10 redhat
@redhat-cloud-services/sources-client 3.0.11 redhat
@redhat-cloud-services/sources-client 3.0.13 redhat
@redhat-cloud-services/topological-inventory-client 3.0.10 redhat
@redhat-cloud-services/topological-inventory-client 3.0.11 redhat
@redhat-cloud-services/topological-inventory-client 3.0.13 redhat
@redhat-cloud-services/tsc-transform-imports 1.2.2 redhat
@redhat-cloud-services/tsc-transform-imports 1.2.4 redhat
@redhat-cloud-services/tsc-transform-imports 1.2.6 redhat
@redhat-cloud-services/types 3.6.1 redhat
@redhat-cloud-services/types 3.6.2 redhat
@redhat-cloud-services/types 3.6.4 redhat
@redhat-cloud-services/vulnerabilities-client 2.1.8 redhat
@redhat-cloud-services/vulnerabilities-client 2.1.9 redhat
@redhat-cloud-services/vulnerabilities-client 2.1.11 redhat
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
hamus.js 0.4.1 keyv
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
@adminide-stack/clock-tik-browser 12.0.24 keyvspread
@adminide-stack/yantra-mobile 12.0.33 keyvspread
@arv-bedrock/auth 1.1.7 keyvspread
@arv-bedrock/auth 1.1.8 keyvspread
@arv-bedrock/auth-admin 1.0.2 keyvspread
@arv-bedrock/auth-admin 1.0.3 keyvspread
@arv-bedrock/auth-sso 1.6.1 keyvspread
@arv-bedrock/auth-sso 1.6.2 keyvspread
@arv-bedrock/auth-sso-backend 1.7.1 keyvspread
@arv-bedrock/auth-sso-backend 1.7.2 keyvspread
@arv-bedrock/logger 1.7.1 keyvspread
@arv-bedrock/logger 1.7.2 keyvspread
@deliveroo/determinator 0.2.1 keyvspread
@deliveroo/reevent 1.0.1 keyvspread
@hubsync/web-sdk-react 6.3.7 keyvspread
@hubsync/web-sdk-react 6.3.8 keyvspread
@hubsync/web-sdk-react 6.3.9 keyvspread
@hubsync/web-sdk-react 6.3.10 keyvspread
@hubsync/web-sdk-react 6.3.11 keyvspread
@hubsync/web-sdk-react 6.3.12 keyvspread
@hubsync/web-sdk-react 6.3.13 keyvspread
@hubsync/web-sdk-react 6.3.14 keyvspread
@hubsync/web-sdk-react 6.3.15 keyvspread
@hubsync/web-sdk-react 6.3.16 keyvspread
@hubsync/web-sdk-react 6.3.17 keyvspread
@hubsync/web-sdk-react 6.3.18 keyvspread
@hubsync/web-sdk-react 6.3.19 keyvspread
@hubsync/web-sdk-react 6.3.20 keyvspread
@hubsync/web-sdk-react 6.3.21 keyvspread
@hubsync/web-sdk-react 6.3.22 keyvspread
@hubsync/web-sdk-react 6.3.23 keyvspread
@hubsync/web-sdk-react 6.3.24 keyvspread
@hubsync/web-sdk-react 6.3.25 keyvspread
@hubsync/web-sdk-react 6.3.26 keyvspread
@hubsync/web-sdk-react 6.3.27 keyvspread
@hubsync/web-sdk-react 6.3.28 keyvspread
@hubsync/web-sdk-react 6.3.29 keyvspread
@hubsync/web-sdk-react 6.3.30 keyvspread
@hubsync/web-sdk-react 6.3.31 keyvspread
@hubsync/web-sdk-react 6.3.32 keyvspread
@hubsync/web-sdk-react 6.3.33 keyvspread
@nebula.js/cli 7.1.2 keyvspread
@nebula.js/cli-build 7.1.2 keyvspread
@nebula.js/cli-sense 7.1.2 keyvspread
@nebula.js/cli-serve 7.1.2 keyvspread
@nebula.js/locale 0.6.2 keyvspread
@nebula.js/nucleus 0.5.1 keyvspread
@nebula.js/sn-action-button 2.3.1 keyvspread
@nebula.js/sn-animator 2.13.1 keyvspread
@nebula.js/sn-distributionplot 1.0.7 keyvspread
@nebula.js/sn-layout-container 4.4.1 keyvspread
@nebula.js/sn-line-chart 2.7.1 keyvspread
@nebula.js/sn-listbox 0.19.3 keyvspread
@nebula.js/sn-map 0.12.7 keyvspread
@nebula.js/sn-nav-menu 0.14.2 keyvspread
@nebula.js/sn-org-chart 1.7.1 keyvspread
@nebula.js/sn-shape 1.5.1 keyvspread
@nebula.js/sn-slider 0.20.1 keyvspread
@nebula.js/sn-tabbed-container 2.4.1 keyvspread
@nebula.js/snapshooter 0.6.1 keyvspread
@nebula.js/stardust 7.1.2 keyvspread
@nebula.js/test-utils 0.6.1 keyvspread
@nebula.js/theme 0.6.1 keyvspread
@onereach/authorizer-helper 0.0.11 keyvspread
@onereach/authorizer-helper 0.0.12 keyvspread
@onereach/authorizer-helper 0.0.13 keyvspread
@onereach/bandwidth-steps-voice-bxml 0.1.1 keyvspread
@onereach/bandwidth-steps-voice-bxml 0.1.2 keyvspread
@onereach/bandwidth-steps-voice-bxml 0.1.3 keyvspread
@onereach/billing-dto 27.2.1 keyvspread
@onereach/billing-dto 27.2.2 keyvspread
@onereach/billing-dto 27.2.3 keyvspread
@onereach/billing-shared 27.2.1 keyvspread
@onereach/billing-shared 27.2.2 keyvspread
@onereach/billing-shared 27.2.3 keyvspread
@onereach/cb-schema-translator 1.3.1 keyvspread
@onereach/cb-schema-translator 1.3.2 keyvspread
@onereach/cb-schema-translator 1.3.3 keyvspread
@onereach/channel-transformer 0.0.66 keyvspread
@onereach/channel-transformer 0.0.67 keyvspread
@onereach/channel-transformer 0.0.68 keyvspread
@onereach/channel-transformers 0.0.5 keyvspread
@onereach/channel-transformers 0.0.6 keyvspread
@onereach/channel-transformers 0.0.7 keyvspread
@onereach/ckeditor5-build-classic 30.0.1 keyvspread
@onereach/ckeditor5-build-classic 30.0.2 keyvspread
@onereach/ckeditor5-build-classic 30.0.3 keyvspread
@onereach/condition-builder 1.0.8 keyvspread
@onereach/condition-builder 1.0.9 keyvspread
@onereach/condition-builder 1.0.10 keyvspread
@onereach/content-builder 0.0.18 keyvspread
@onereach/content-builder 0.0.19 keyvspread
@onereach/content-builder 0.0.20 keyvspread
@onereach/content-builder-template-compiler 0.0.3 keyvspread
@onereach/content-builder-template-compiler 0.0.4 keyvspread
@onereach/content-builder-template-compiler 0.0.5 keyvspread
@onereach/expression-components 9.1.1 keyvspread
@onereach/expression-components 9.1.2 keyvspread
@onereach/expression-components 9.1.3 keyvspread
@onereach/font-icons 27.0.2 keyvspread
@onereach/font-icons 27.0.3 keyvspread
@onereach/font-icons 27.0.4 keyvspread
@onereach/get-version-data 3.1.2 keyvspread
@onereach/get-version-data 3.1.3 keyvspread
@onereach/get-version-data 3.1.4 keyvspread
@onereach/idw-apps 0.1.3 keyvspread
@onereach/idw-apps 0.1.4 keyvspread
@onereach/idw-apps 0.1.5 keyvspread
@onereach/idw-contracts 0.1.2 keyvspread
@onereach/idw-contracts 0.1.3 keyvspread
@onereach/idw-contracts 0.1.4 keyvspread
@onereach/idw-init-account-resources 1.0.1 keyvspread
@onereach/idw-init-account-resources 1.0.2 keyvspread
@onereach/idw-init-account-resources 1.0.3 keyvspread
@onereach/idw-sdk 0.1.2 keyvspread
@onereach/idw-sdk 0.1.3 keyvspread
@onereach/idw-sdk 0.1.4 keyvspread
@onereach/idw-ui-components 0.1.2 keyvspread
@onereach/idw-ui-components 0.1.3 keyvspread
@onereach/idw-ui-components 0.1.4 keyvspread
@onereach/lambda-invocation 1.2.1 keyvspread
@onereach/lambda-invocation 1.2.2 keyvspread
@onereach/lambda-invocation 1.2.3 keyvspread
@onereach/messengers-infobip-sdk 0.1.1 keyvspread
@onereach/messengers-infobip-sdk 0.1.2 keyvspread
@onereach/messengers-infobip-sdk 0.1.3 keyvspread
@onereach/or-browser 0.0.48 keyvspread
@onereach/or-browser 0.0.49 keyvspread
@onereach/or-browser 0.0.50 keyvspread
@onereach/or-browser-next 0.0.11 keyvspread
@onereach/or-browser-next 0.0.12 keyvspread
@onereach/or-browser-next 0.0.13 keyvspread
@onereach/or-content-builder-renderer 0.0.2 keyvspread
@onereach/or-content-builder-renderer 0.0.3 keyvspread
@onereach/or-content-builder-renderer 0.0.4 keyvspread
@onereach/or-file-uploader-next 0.0.8 keyvspread
@onereach/or-file-uploader-next 0.0.9 keyvspread
@onereach/or-file-uploader-next 0.0.10 keyvspread
@onereach/or-pro 1.13.1 keyvspread
@onereach/or-pro 1.13.2 keyvspread
@onereach/or-pro 1.13.3 keyvspread
@onereach/or-sdk-agent-cli 0.0.6 keyvspread
@onereach/or-sdk-agent-cli 0.0.7 keyvspread
@onereach/or-sdk-agent-cli 0.0.8 keyvspread
@onereach/orest-cli 2.4.1 keyvspread
@onereach/orest-cli 2.4.2 keyvspread
@onereach/orest-cli 2.4.3 keyvspread
@onereach/orest-input-cli 1.18.1 keyvspread
@onereach/orest-input-cli 1.18.2 keyvspread
@onereach/orest-input-cli 1.18.3 keyvspread
@onereach/orest-jest-presets 0.0.3 keyvspread
@onereach/orest-jest-presets 0.0.4 keyvspread
@onereach/orest-jest-presets 0.0.5 keyvspread
@onereach/orest-vue-demi-vue2 0.0.4 keyvspread
@onereach/orest-vue-demi-vue2 0.0.5 keyvspread
@onereach/orest-vue-demi-vue2 0.0.6 keyvspread
@onereach/orest-vue-demi-vue3 0.0.4 keyvspread
@onereach/orest-vue-demi-vue3 0.0.5 keyvspread
@onereach/orest-vue-demi-vue3 0.0.6 keyvspread
@onereach/orest-vue3 0.0.4 keyvspread
@onereach/orest-vue3 0.0.5 keyvspread
@onereach/orest-vue3 0.0.6 keyvspread
@onereach/phonenumber-interpreter 0.0.18 keyvspread
@onereach/phonenumber-interpreter 0.0.19 keyvspread
@onereach/phonenumber-interpreter 0.0.20 keyvspread
@onereach/pnpm-audit-junit 1.0.3 keyvspread
@onereach/pnpm-audit-junit 1.0.4 keyvspread
@onereach/pnpm-audit-junit 1.0.5 keyvspread
@onereach/postcss-scoped-selector 1.2.1 keyvspread
@onereach/postcss-scoped-selector 1.2.2 keyvspread
@onereach/postcss-scoped-selector 1.2.3 keyvspread
@onereach/regex-helper 0.5.16 keyvspread
@onereach/regex-helper 0.5.17 keyvspread
@onereach/regex-helper 0.5.18 keyvspread
@onereach/regular-expressions 0.5.23 keyvspread
@onereach/regular-expressions 0.5.24 keyvspread
@onereach/regular-expressions 0.5.25 keyvspread
@onereach/regular-expressions-test 0.0.4 keyvspread
@onereach/regular-expressions-test 0.0.5 keyvspread
@onereach/regular-expressions-test 0.0.6 keyvspread
@onereach/rwc-client 6.4.7 keyvspread
@onereach/rwc-client 6.4.8 keyvspread
@onereach/rwc-client 6.4.9 keyvspread
@onereach/salesforce-miaw-client 0.0.3 keyvspread
@onereach/salesforce-miaw-client 0.0.4 keyvspread
@onereach/salesforce-miaw-client 0.0.5 keyvspread
@onereach/si-a-button 0.0.3 keyvspread
@onereach/si-a-button 0.0.4 keyvspread
@onereach/si-a-button 0.0.5 keyvspread
@onereach/si-alert 0.4.11 keyvspread
@onereach/si-alert 0.4.12 keyvspread
@onereach/si-alert 0.4.13 keyvspread
@onereach/si-checkbox 0.6.5 keyvspread
@onereach/si-checkbox 0.6.6 keyvspread
@onereach/si-checkbox 0.6.7 keyvspread
@onereach/si-checkbox-group 0.3.5 keyvspread
@onereach/si-checkbox-group 0.3.6 keyvspread
@onereach/si-checkbox-group 0.3.7 keyvspread
@onereach/si-code 0.6.4 keyvspread
@onereach/si-code 0.6.5 keyvspread
@onereach/si-code 0.6.6 keyvspread
@onereach/si-collapsible-group 0.6.4 keyvspread
@onereach/si-collapsible-group 0.6.5 keyvspread
@onereach/si-collapsible-group 0.6.6 keyvspread
@onereach/si-copyable-text 0.4.11 keyvspread
@onereach/si-copyable-text 0.4.12 keyvspread
@onereach/si-copyable-text 0.4.13 keyvspread
@onereach/si-datepicker 0.4.5 keyvspread
@onereach/si-datepicker 0.4.6 keyvspread
@onereach/si-datepicker 0.4.7 keyvspread
@onereach/si-divider 0.4.11 keyvspread
@onereach/si-divider 0.4.12 keyvspread
@onereach/si-divider 0.4.13 keyvspread
@onereach/si-dropdown-advanced 0.4.5 keyvspread
@onereach/si-dropdown-advanced 0.4.6 keyvspread
@onereach/si-dropdown-advanced 0.4.7 keyvspread
@onereach/si-dropdown-simple 0.4.5 keyvspread
@onereach/si-dropdown-simple 0.4.6 keyvspread
@onereach/si-dropdown-simple 0.4.7 keyvspread
@onereach/si-header 0.4.11 keyvspread
@onereach/si-header 0.4.12 keyvspread
@onereach/si-header 0.4.13 keyvspread
@onereach/si-header 0.4.14 keyvspread
@onereach/si-list 0.7.4 keyvspread
@onereach/si-list 0.7.5 keyvspread
@onereach/si-list 0.7.6 keyvspread
@onereach/si-merge-tag-input 0.4.5 keyvspread
@onereach/si-merge-tag-input 0.4.6 keyvspread
@onereach/si-merge-tag-input 0.4.7 keyvspread
@onereach/si-radio-group 0.3.5 keyvspread
@onereach/si-radio-group 0.3.6 keyvspread
@onereach/si-radio-group 0.3.7 keyvspread
@onereach/si-root 0.9.4 keyvspread
@onereach/si-root 0.9.5 keyvspread
@onereach/si-root 0.9.6 keyvspread
@onereach/si-select 0.1.3 keyvspread
@onereach/si-select 0.1.4 keyvspread
@onereach/si-select 0.1.5 keyvspread
@onereach/si-step-chooser 0.4.4 keyvspread
@onereach/si-step-chooser 0.4.5 keyvspread
@onereach/si-step-chooser 0.4.6 keyvspread
@onereach/si-switch 0.4.5 keyvspread
@onereach/si-switch 0.4.6 keyvspread
@onereach/si-switch 0.4.7 keyvspread
@onereach/si-text-message 0.4.5 keyvspread
@onereach/si-text-message 0.4.6 keyvspread
@onereach/si-text-message 0.4.7 keyvspread
@onereach/si-textinput 0.5.5 keyvspread
@onereach/si-textinput 0.5.6 keyvspread
@onereach/si-textinput 0.5.7 keyvspread
@onereach/si-validated-timestring-input 0.3.5 keyvspread
@onereach/si-validated-timestring-input 0.3.6 keyvspread
@onereach/si-validated-timestring-input 0.3.7 keyvspread
@onereach/slack-helpers 1.0.3 keyvspread
@onereach/slack-helpers 1.0.4 keyvspread
@onereach/slack-helpers 1.0.5 keyvspread
@onereach/ssml-editor 2.0.12 keyvspread
@onereach/ssml-editor 2.0.13 keyvspread
@onereach/ssml-editor 2.0.14 keyvspread
@onereach/step-components 0.1.37 keyvspread
@onereach/step-components 0.1.38 keyvspread
@onereach/step-components 0.1.39 keyvspread
@onereach/step-conversation 1.0.41 keyvspread
@onereach/step-conversation 1.0.42 keyvspread
@onereach/step-conversation 1.0.43 keyvspread
@onereach/step-run-snowflake-query 0.1.1 keyvspread
@onereach/step-run-snowflake-query 0.1.2 keyvspread
@onereach/step-run-snowflake-query 0.1.3 keyvspread
@onereach/step-voice 7.0.32 keyvspread
@onereach/step-voice 7.0.33 keyvspread
@onereach/step-voice 7.0.34 keyvspread
@onereach/styles 27.0.2 keyvspread
@onereach/styles 27.0.3 keyvspread
@onereach/styles 27.0.4 keyvspread
@onereach/time-interpreter 1.0.30 keyvspread
@onereach/time-interpreter 1.0.31 keyvspread
@onereach/time-interpreter 1.0.32 keyvspread
@onereach/ts-memoize 1.0.2 keyvspread
@onereach/ts-memoize 1.0.3 keyvspread
@onereach/ts-memoize 1.0.4 keyvspread
@onereach/types-contacts-api 9.0.8 keyvspread
@onereach/types-contacts-api 9.0.9 keyvspread
@onereach/types-contacts-api 9.0.10 keyvspread
@onereach/ui-components 27.0.2 keyvspread
@onereach/ui-components 27.0.3 keyvspread
@onereach/ui-components 27.0.4 keyvspread
@onereach/ui-components-common 27.0.2 keyvspread
@onereach/ui-components-common 27.0.3 keyvspread
@onereach/ui-components-common 27.0.4 keyvspread
@onereach/ui-components-vue2 27.0.2 keyvspread
@onereach/ui-components-vue2 27.0.3 keyvspread
@onereach/ui-components-vue2 27.0.4 keyvspread
@onereach/v-event-calendar 0.1.22 keyvspread
@onereach/v-event-calendar 0.1.23 keyvspread
@onereach/v-event-calendar 0.1.24 keyvspread
@onereach/webform 0.3.13 keyvspread
@onereach/webform 0.3.14 keyvspread
@onereach/webform 0.3.15 keyvspread
@or-sdk/account-settings 1.3.6 keyvspread
@or-sdk/account-settings 1.3.7 keyvspread
@or-sdk/account-settings 1.3.8 keyvspread
@or-sdk/accounts 2.3.5 keyvspread
@or-sdk/accounts 2.3.6 keyvspread
@or-sdk/accounts 2.3.7 keyvspread
@or-sdk/adapters 0.3.6 keyvspread
@or-sdk/adapters 0.3.7 keyvspread
@or-sdk/adapters 0.3.8 keyvspread
@or-sdk/agents 4.21.3 keyvspread
@or-sdk/agents 4.21.4 keyvspread
@or-sdk/agents 4.21.5 keyvspread
@or-sdk/api-tokens 1.4.2 keyvspread
@or-sdk/api-tokens 1.4.3 keyvspread
@or-sdk/api-tokens 1.4.4 keyvspread
@or-sdk/api-tokens-lambda 1.4.2 keyvspread
@or-sdk/api-tokens-lambda 1.4.3 keyvspread
@or-sdk/api-tokens-lambda 1.4.4 keyvspread
@or-sdk/apps 1.2.6 keyvspread
@or-sdk/apps 1.2.7 keyvspread
@or-sdk/apps 1.2.8 keyvspread
@or-sdk/auth 0.38.1 keyvspread
@or-sdk/auth 0.38.2 keyvspread
@or-sdk/auth 0.38.3 keyvspread
@or-sdk/authorizer 0.26.7 keyvspread
@or-sdk/authorizer 0.26.8 keyvspread
@or-sdk/authorizer 0.26.9 keyvspread
@or-sdk/base 0.44.4 keyvspread
@or-sdk/base 0.44.5 keyvspread
@or-sdk/base 0.44.6 keyvspread
@or-sdk/billing 27.2.1 keyvspread
@or-sdk/billing 27.2.2 keyvspread
@or-sdk/billing 27.2.3 keyvspread
@or-sdk/billing-internal 27.2.1 keyvspread
@or-sdk/billing-internal 27.2.2 keyvspread
@or-sdk/billing-internal 27.2.3 keyvspread
@or-sdk/bot-templates 2.2.5 keyvspread
@or-sdk/bot-templates 2.2.6 keyvspread
@or-sdk/bot-templates 2.2.7 keyvspread
@or-sdk/bots 1.7.1 keyvspread
@or-sdk/bots 1.7.2 keyvspread
@or-sdk/bots 1.7.3 keyvspread
@or-sdk/card-templates 2.2.5 keyvspread
@or-sdk/card-templates 2.2.6 keyvspread
@or-sdk/card-templates 2.2.7 keyvspread
@or-sdk/cards 1.2.5 keyvspread
@or-sdk/cards 1.2.6 keyvspread
@or-sdk/cards 1.2.7 keyvspread
@or-sdk/ccp 10.15.4 keyvspread
@or-sdk/ccp 10.15.5 keyvspread
@or-sdk/ccp 10.15.6 keyvspread
@or-sdk/chat 0.3.1 keyvspread
@or-sdk/chat 0.3.2 keyvspread
@or-sdk/chat 0.3.3 keyvspread
@or-sdk/contacts 4.7.5 keyvspread
@or-sdk/contacts 4.7.6 keyvspread
@or-sdk/contacts 4.7.7 keyvspread
@or-sdk/content-request 0.2.6 keyvspread
@or-sdk/content-request 0.2.7 keyvspread
@or-sdk/content-request 0.2.8 keyvspread
@or-sdk/data-hub 0.26.5 keyvspread
@or-sdk/data-hub 0.26.6 keyvspread
@or-sdk/data-hub 0.26.7 keyvspread
@or-sdk/data-hub-svc 2.3.5 keyvspread
@or-sdk/data-hub-svc 2.3.6 keyvspread
@or-sdk/data-hub-svc 2.3.7 keyvspread
@or-sdk/deployer 1.7.5 keyvspread
@or-sdk/deployer 1.7.6 keyvspread
@or-sdk/deployer 1.7.7 keyvspread
@or-sdk/deployments 2.1.5 keyvspread
@or-sdk/deployments 2.1.6 keyvspread
@or-sdk/deployments 2.1.7 keyvspread
@or-sdk/discovery 1.12.1 keyvspread
@or-sdk/discovery 1.12.2 keyvspread
@or-sdk/discovery 1.12.3 keyvspread
@or-sdk/druid 1.4.7 keyvspread
@or-sdk/druid 1.4.8 keyvspread
@or-sdk/druid 1.4.9 keyvspread
@or-sdk/event-manager 1.1.5 keyvspread
@or-sdk/event-manager 1.1.6 keyvspread
@or-sdk/event-manager 1.1.7 keyvspread
@or-sdk/files 3.11.6 keyvspread
@or-sdk/files 3.11.7 keyvspread
@or-sdk/files 3.11.8 keyvspread
@or-sdk/files-sync-node 0.1.8 keyvspread
@or-sdk/files-sync-node 0.1.9 keyvspread
@or-sdk/files-sync-node 0.1.10 keyvspread
@or-sdk/flow-templates 2.1.5 keyvspread
@or-sdk/flow-templates 2.1.6 keyvspread
@or-sdk/flow-templates 2.1.7 keyvspread
@or-sdk/flows 2.7.8 keyvspread
@or-sdk/flows 2.7.9 keyvspread
@or-sdk/flows 2.7.10 keyvspread
@or-sdk/graph 1.10.5 keyvspread
@or-sdk/graph 1.10.6 keyvspread
@or-sdk/graph 1.10.7 keyvspread
@or-sdk/hitl 0.41.1 keyvspread
@or-sdk/hitl 0.41.2 keyvspread
@or-sdk/hitl 0.41.3 keyvspread
@or-sdk/identifiers 0.27.6 keyvspread
@or-sdk/identifiers 0.27.7 keyvspread
@or-sdk/identifiers 0.27.8 keyvspread
@or-sdk/idw 9.0.4 keyvspread
@or-sdk/idw 9.0.5 keyvspread
@or-sdk/idw 9.0.6 keyvspread
@or-sdk/idw-public 1.6.6 keyvspread
@or-sdk/idw-public 1.6.7 keyvspread
@or-sdk/idw-public 1.6.8 keyvspread
@or-sdk/idw-skill 1.4.1 keyvspread
@or-sdk/idw-skill 1.4.2 keyvspread
@or-sdk/idw-skill 1.4.3 keyvspread
@or-sdk/invitations 1.4.8 keyvspread
@or-sdk/invitations 1.4.9 keyvspread
@or-sdk/invitations 1.4.10 keyvspread
@or-sdk/key-value-storage 0.28.6 keyvspread
@or-sdk/key-value-storage 0.28.7 keyvspread
@or-sdk/key-value-storage 0.28.8 keyvspread
@or-sdk/keys 1.2.6 keyvspread
@or-sdk/keys 1.2.7 keyvspread
@or-sdk/keys 1.2.8 keyvspread
@or-sdk/knowledge-models 0.25.5 keyvspread
@or-sdk/knowledge-models 0.25.6 keyvspread
@or-sdk/knowledge-models 0.25.7 keyvspread
@or-sdk/library 0.5.6 keyvspread
@or-sdk/library 0.5.7 keyvspread
@or-sdk/library 0.5.8 keyvspread
@or-sdk/library-categories 0.2.6 keyvspread
@or-sdk/library-categories 0.2.7 keyvspread
@or-sdk/library-categories 0.2.8 keyvspread
@or-sdk/library-source 0.4.5 keyvspread
@or-sdk/library-source 0.4.6 keyvspread
@or-sdk/library-source 0.4.7 keyvspread
@or-sdk/library-types-v1 9.0.1 keyvspread
@or-sdk/library-types-v1 9.0.2 keyvspread
@or-sdk/library-types-v1 9.0.3 keyvspread
@or-sdk/library-types-v2 9.0.1 keyvspread
@or-sdk/library-types-v2 9.0.2 keyvspread
@or-sdk/library-types-v2 9.0.3 keyvspread
@or-sdk/lookup 1.25.1 keyvspread
@or-sdk/lookup 1.25.2 keyvspread
@or-sdk/lookup 1.25.3 keyvspread
@or-sdk/markdowner 0.5.1 keyvspread
@or-sdk/markdowner 0.5.2 keyvspread
@or-sdk/markdowner 0.5.3 keyvspread
@or-sdk/mcp-tools 0.5.2 keyvspread
@or-sdk/mcp-tools 0.5.3 keyvspread
@or-sdk/mcp-tools 0.5.4 keyvspread
@or-sdk/notifications 1.7.5 keyvspread
@or-sdk/notifications 1.7.6 keyvspread
@or-sdk/notifications 1.7.7 keyvspread
@or-sdk/password 1.3.6 keyvspread
@or-sdk/password 1.3.7 keyvspread
@or-sdk/password 1.3.8 keyvspread
@or-sdk/payments 3.2.5 keyvspread
@or-sdk/payments 3.2.6 keyvspread
@or-sdk/payments 3.2.7 keyvspread
@or-sdk/permissions 2.8.1 keyvspread
@or-sdk/permissions 2.8.2 keyvspread
@or-sdk/permissions 2.8.3 keyvspread
@or-sdk/permissions-cli 1.4.1 keyvspread
@or-sdk/permissions-cli 1.4.2 keyvspread
@or-sdk/permissions-cli 1.4.3 keyvspread
@or-sdk/permissions-lambda 2.5.1 keyvspread
@or-sdk/permissions-lambda 2.5.2 keyvspread
@or-sdk/permissions-lambda 2.5.3 keyvspread
@or-sdk/pgsql 1.5.1 keyvspread
@or-sdk/pgsql 1.5.2 keyvspread
@or-sdk/pgsql 1.5.3 keyvspread
@or-sdk/providers 0.3.6 keyvspread
@or-sdk/providers 0.3.7 keyvspread
@or-sdk/providers 0.3.8 keyvspread
@or-sdk/qna 3.4.2 keyvspread
@or-sdk/qna 3.4.3 keyvspread
@or-sdk/qna 3.4.4 keyvspread
@or-sdk/queue-manager 1.4.6 keyvspread
@or-sdk/queue-manager 1.4.7 keyvspread
@or-sdk/queue-manager 1.4.8 keyvspread
@or-sdk/sdk-api 0.29.2 keyvspread
@or-sdk/sdk-api 0.29.3 keyvspread
@or-sdk/sdk-api 0.29.4 keyvspread
@or-sdk/settings 0.25.6 keyvspread
@or-sdk/settings 0.25.7 keyvspread
@or-sdk/settings 0.25.8 keyvspread
@or-sdk/sku-builder 2.5.1 keyvspread
@or-sdk/sku-builder 2.5.2 keyvspread
@or-sdk/sku-builder 2.5.3 keyvspread
@or-sdk/source 2.1.5 keyvspread
@or-sdk/source 2.1.6 keyvspread
@or-sdk/source 2.1.7 keyvspread
@or-sdk/source-api 1.1.1 keyvspread
@or-sdk/source-api 1.1.2 keyvspread
@or-sdk/source-api 1.1.3 keyvspread
@or-sdk/step-templates 2.2.5 keyvspread
@or-sdk/step-templates 2.2.6 keyvspread
@or-sdk/step-templates 2.2.7 keyvspread
@or-sdk/store 2.1.5 keyvspread
@or-sdk/store 2.1.6 keyvspread
@or-sdk/store 2.1.7 keyvspread
@or-sdk/tables 0.28.5 keyvspread
@or-sdk/tables 0.28.6 keyvspread
@or-sdk/tables 0.28.7 keyvspread
@or-sdk/tags 1.1.5 keyvspread
@or-sdk/tags 1.1.6 keyvspread
@or-sdk/tags 1.1.7 keyvspread
@or-sdk/tickets 1.9.5 keyvspread
@or-sdk/tickets 1.9.6 keyvspread
@or-sdk/tickets 1.9.7 keyvspread
@or-sdk/transcripts 1.2.5 keyvspread
@or-sdk/transcripts 1.2.6 keyvspread
@or-sdk/transcripts 1.2.7 keyvspread
@or-sdk/users 3.8.1 keyvspread
@or-sdk/users 3.8.2 keyvspread
@or-sdk/users 3.8.3 keyvspread
@or-sdk/view-templates 2.2.5 keyvspread
@or-sdk/view-templates 2.2.6 keyvspread
@or-sdk/view-templates 2.2.7 keyvspread
@or-sdk/views 3.1.5 keyvspread
@or-sdk/views 3.1.6 keyvspread
@or-sdk/views 3.1.7 keyvspread
@or-sdk/web-search 0.6.1 keyvspread
@or-sdk/web-search 0.6.2 keyvspread
@or-sdk/web-search 0.6.3 keyvspread
@ornikar/apollo-link-timeout 1.4.2 keyvspread
@ornikar/apollo-link-timeout 1.4.3 keyvspread
@ornikar/apollo-link-timeout 1.4.4 keyvspread
@ornikar/apollo-link-timeout 1.4.5 keyvspread
@ornikar/apollo-link-timeout 1.4.6 keyvspread
@ornikar/apollo-link-timeout 1.4.7 keyvspread
@ornikar/apollo-link-timeout 1.4.8 keyvspread
@ornikar/apollo-link-timeout 1.4.9 keyvspread
@ornikar/apollo-link-timeout 1.4.10 keyvspread
@ornikar/apollo-link-timeout 1.4.11 keyvspread
@ornikar/babel-preset-base 6.0.3 keyvspread
@ornikar/babel-preset-base 6.0.4 keyvspread
@ornikar/babel-preset-base 6.0.5 keyvspread
@ornikar/babel-preset-base 6.0.6 keyvspread
@ornikar/babel-preset-base 6.0.7 keyvspread
@ornikar/babel-preset-base 6.0.8 keyvspread
@ornikar/babel-preset-base 6.0.9 keyvspread
@ornikar/babel-preset-base 6.0.10 keyvspread
@ornikar/babel-preset-base 6.0.11 keyvspread
@ornikar/babel-preset-base 6.0.12 keyvspread
@ornikar/babel-preset-base 6.0.13 keyvspread
@ornikar/babel-preset-base 6.0.14 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.3 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.4 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.5 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.6 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.7 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.8 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.9 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.10 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.11 keyvspread
@ornikar/babel-preset-kitt-universal 8.0.12 keyvspread
@ornikar/babel-preset-react 6.1.4 keyvspread
@ornikar/babel-preset-react 6.1.5 keyvspread
@ornikar/babel-preset-react 6.1.6 keyvspread
@ornikar/babel-preset-react 6.1.7 keyvspread
@ornikar/babel-preset-react 6.1.8 keyvspread
@ornikar/babel-preset-react 6.1.9 keyvspread
@ornikar/babel-preset-react 6.1.10 keyvspread
@ornikar/babel-preset-react 6.1.11 keyvspread
@ornikar/babel-preset-react 6.1.12 keyvspread
@ornikar/babel-preset-react 6.1.13 keyvspread
@ornikar/babel-preset-react 6.1.14 keyvspread
@ornikar/browserslist-config 8.0.3 keyvspread
@ornikar/browserslist-config 8.0.4 keyvspread
@ornikar/browserslist-config 8.0.5 keyvspread
@ornikar/browserslist-config 8.0.6 keyvspread
@ornikar/browserslist-config 8.0.7 keyvspread
@ornikar/browserslist-config 8.0.8 keyvspread
@ornikar/browserslist-config 8.0.9 keyvspread
@ornikar/browserslist-config 8.0.10 keyvspread
@ornikar/browserslist-config 8.0.11 keyvspread
@ornikar/commitlint-config 8.3.2 keyvspread
@ornikar/commitlint-config 8.3.3 keyvspread
@ornikar/commitlint-config 8.3.4 keyvspread
@ornikar/commitlint-config 8.3.5 keyvspread
@ornikar/commitlint-config 8.3.6 keyvspread
@ornikar/commitlint-config 8.3.7 keyvspread
@ornikar/commitlint-config 8.3.8 keyvspread
@ornikar/commitlint-config 8.3.9 keyvspread
@ornikar/commitlint-config 8.3.10 keyvspread
@ornikar/commitlint-config 8.3.11 keyvspread
@ornikar/commitlint-config 8.3.12 keyvspread
@ornikar/eslint-config 24.0.1 keyvspread
@ornikar/eslint-config 24.0.2 keyvspread
@ornikar/eslint-config 24.0.3 keyvspread
@ornikar/eslint-config 24.0.4 keyvspread
@ornikar/eslint-config 24.0.5 keyvspread
@ornikar/eslint-config 24.0.6 keyvspread
@ornikar/eslint-config 24.0.7 keyvspread
@ornikar/eslint-config 24.0.8 keyvspread
@ornikar/eslint-config 24.0.9 keyvspread
@ornikar/eslint-config 24.0.10 keyvspread
@ornikar/eslint-config 24.0.11 keyvspread
@ornikar/eslint-config 24.0.12 keyvspread
@ornikar/eslint-config-babel 24.0.1 keyvspread
@ornikar/eslint-config-babel 24.0.2 keyvspread
@ornikar/eslint-config-babel 24.0.3 keyvspread
@ornikar/eslint-config-babel 24.0.4 keyvspread
@ornikar/eslint-config-babel 24.0.5 keyvspread
@ornikar/eslint-config-babel 24.0.6 keyvspread
@ornikar/eslint-config-babel 24.0.7 keyvspread
@ornikar/eslint-config-babel 24.0.8 keyvspread
@ornikar/eslint-config-babel 24.0.9 keyvspread
@ornikar/eslint-config-babel 24.0.10 keyvspread
@ornikar/eslint-config-babel 24.0.11 keyvspread
@ornikar/eslint-config-babel 24.0.12 keyvspread
@ornikar/eslint-config-babel-use 13.2.1 keyvspread
@ornikar/eslint-config-babel-use 13.2.2 keyvspread
@ornikar/eslint-config-babel-use 13.2.3 keyvspread
@ornikar/eslint-config-babel-use 13.2.4 keyvspread
@ornikar/eslint-config-babel-use 13.2.5 keyvspread
@ornikar/eslint-config-babel-use 13.2.6 keyvspread
@ornikar/eslint-config-babel-use 13.2.7 keyvspread
@ornikar/eslint-config-babel-use 13.2.8 keyvspread
@ornikar/eslint-config-babel-use 13.2.9 keyvspread
@ornikar/eslint-config-babel-use 13.2.10 keyvspread
@ornikar/eslint-config-babel-use 13.2.11 keyvspread
@ornikar/eslint-config-babel-use 13.2.12 keyvspread
@ornikar/eslint-config-formatjs 24.0.1 keyvspread
@ornikar/eslint-config-formatjs 24.0.2 keyvspread
@ornikar/eslint-config-formatjs 24.0.3 keyvspread
@ornikar/eslint-config-formatjs 24.0.4 keyvspread
@ornikar/eslint-config-formatjs 24.0.5 keyvspread
@ornikar/eslint-config-formatjs 24.0.6 keyvspread
@ornikar/eslint-config-formatjs 24.0.7 keyvspread
@ornikar/eslint-config-formatjs 24.0.8 keyvspread
@ornikar/eslint-config-formatjs 24.0.9 keyvspread
@ornikar/eslint-config-formatjs 24.0.10 keyvspread
@ornikar/eslint-config-node 12.2.1 keyvspread
@ornikar/eslint-config-node 12.2.2 keyvspread
@ornikar/eslint-config-node 12.2.3 keyvspread
@ornikar/eslint-config-node 12.2.4 keyvspread
@ornikar/eslint-config-node 12.2.5 keyvspread
@ornikar/eslint-config-node 12.2.6 keyvspread
@ornikar/eslint-config-node 12.2.7 keyvspread
@ornikar/eslint-config-node 12.2.8 keyvspread
@ornikar/eslint-config-node 12.2.9 keyvspread
@ornikar/eslint-config-node 12.2.10 keyvspread
@ornikar/eslint-config-react 24.0.1 keyvspread
@ornikar/eslint-config-react 24.0.2 keyvspread
@ornikar/eslint-config-react 24.0.3 keyvspread
@ornikar/eslint-config-react 24.0.4 keyvspread
@ornikar/eslint-config-react 24.0.5 keyvspread
@ornikar/eslint-config-react 24.0.6 keyvspread
@ornikar/eslint-config-react 24.0.7 keyvspread
@ornikar/eslint-config-react 24.0.8 keyvspread
@ornikar/eslint-config-react 24.0.9 keyvspread
@ornikar/eslint-config-react 24.0.10 keyvspread
@ornikar/eslint-config-react 24.0.11 keyvspread
@ornikar/eslint-config-typescript 24.0.1 keyvspread
@ornikar/eslint-config-typescript 24.0.2 keyvspread
@ornikar/eslint-config-typescript 24.0.3 keyvspread
@ornikar/eslint-config-typescript 24.0.4 keyvspread
@ornikar/eslint-config-typescript 24.0.5 keyvspread
@ornikar/eslint-config-typescript 24.0.6 keyvspread
@ornikar/eslint-config-typescript 24.0.7 keyvspread
@ornikar/eslint-config-typescript 24.0.8 keyvspread
@ornikar/eslint-config-typescript 24.0.9 keyvspread
@ornikar/eslint-config-typescript 24.0.10 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.1 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.2 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.3 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.4 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.5 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.6 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.7 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.8 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.9 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.10 keyvspread
@ornikar/eslint-config-typescript-nestjs 24.0.11 keyvspread
@ornikar/eslint-config-typescript-react 24.0.1 keyvspread
@ornikar/eslint-config-typescript-react 24.0.2 keyvspread
@ornikar/eslint-config-typescript-react 24.0.3 keyvspread
@ornikar/eslint-config-typescript-react 24.0.4 keyvspread
@ornikar/eslint-config-typescript-react 24.0.5 keyvspread
@ornikar/eslint-config-typescript-react 24.0.6 keyvspread
@ornikar/eslint-config-typescript-react 24.0.7 keyvspread
@ornikar/eslint-config-typescript-react 24.0.8 keyvspread
@ornikar/eslint-config-typescript-react 24.0.9 keyvspread
@ornikar/eslint-config-typescript-react 24.0.10 keyvspread
@ornikar/eslint-config-typescript-react 24.0.11 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.1 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.2 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.3 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.4 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.5 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.6 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.7 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.8 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.9 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.10 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.11 keyvspread
@ornikar/eslint-plugin-neverthrow 1.3.12 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.1 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.2 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.3 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.4 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.5 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.6 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.7 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.8 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.9 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.10 keyvspread
@ornikar/eslint-plugin-ornikar 24.0.11 keyvspread
@ornikar/graphql-config 1.1.1 keyvspread
@ornikar/graphql-config 1.1.2 keyvspread
@ornikar/graphql-config 1.1.3 keyvspread
@ornikar/graphql-config 1.1.4 keyvspread
@ornikar/graphql-config 1.1.5 keyvspread
@ornikar/graphql-config 1.1.6 keyvspread
@ornikar/graphql-config 1.1.7 keyvspread
@ornikar/graphql-config 1.1.8 keyvspread
@ornikar/graphql-config 1.1.9 keyvspread
@ornikar/graphql-config 1.1.10 keyvspread
@ornikar/graphql-config 1.1.11 keyvspread
@ornikar/intl-config 10.0.2 keyvspread
@ornikar/intl-config 10.0.3 keyvspread
@ornikar/intl-config 10.0.4 keyvspread
@ornikar/intl-config 10.0.5 keyvspread
@ornikar/intl-config 10.0.6 keyvspread
@ornikar/intl-config 10.0.7 keyvspread
@ornikar/intl-config 10.0.8 keyvspread
@ornikar/intl-config 10.0.9 keyvspread
@ornikar/intl-config 10.0.10 keyvspread
@ornikar/jest-config 13.0.3 keyvspread
@ornikar/jest-config 13.0.4 keyvspread
@ornikar/jest-config 13.0.5 keyvspread
@ornikar/jest-config 13.0.6 keyvspread
@ornikar/jest-config 13.0.7 keyvspread
@ornikar/jest-config 13.0.8 keyvspread
@ornikar/jest-config 13.0.9 keyvspread
@ornikar/jest-config 13.0.10 keyvspread
@ornikar/jest-config 13.0.11 keyvspread
@ornikar/jest-config 13.0.12 keyvspread
@ornikar/jest-config 13.0.13 keyvspread
@ornikar/jest-config-react 18.0.2 keyvspread
@ornikar/jest-config-react 18.0.3 keyvspread
@ornikar/jest-config-react 18.0.4 keyvspread
@ornikar/jest-config-react 18.0.5 keyvspread
@ornikar/jest-config-react 18.0.6 keyvspread
@ornikar/jest-config-react 18.0.7 keyvspread
@ornikar/jest-config-react 18.0.8 keyvspread
@ornikar/jest-config-react 18.0.9 keyvspread
@ornikar/jest-config-react 18.0.10 keyvspread
@ornikar/jest-config-react 18.0.11 keyvspread
@ornikar/jest-config-react-native 17.0.2 keyvspread
@ornikar/jest-config-react-native 17.0.3 keyvspread
@ornikar/jest-config-react-native 17.0.4 keyvspread
@ornikar/jest-config-react-native 17.0.5 keyvspread
@ornikar/jest-config-react-native 17.0.6 keyvspread
@ornikar/jest-config-react-native 17.0.7 keyvspread
@ornikar/jest-config-react-native 17.0.8 keyvspread
@ornikar/jest-config-react-native 17.0.9 keyvspread
@ornikar/jest-config-react-native 17.0.10 keyvspread
@ornikar/jest-config-react-native 17.0.11 keyvspread
@ornikar/jest-config-react-native 17.0.12 keyvspread
@ornikar/jest-config-react-native-web 12.0.3 keyvspread
@ornikar/jest-config-react-native-web 12.0.4 keyvspread
@ornikar/jest-config-react-native-web 12.0.5 keyvspread
@ornikar/jest-config-react-native-web 12.0.6 keyvspread
@ornikar/jest-config-react-native-web 12.0.7 keyvspread
@ornikar/jest-config-react-native-web 12.0.8 keyvspread
@ornikar/jest-config-react-native-web 12.0.9 keyvspread
@ornikar/jest-config-react-native-web 12.0.10 keyvspread
@ornikar/jest-config-react-native-web 12.0.11 keyvspread
@ornikar/jest-config-react-native-web 12.0.12 keyvspread
@ornikar/jest-config-react-native-web 12.0.13 keyvspread
@ornikar/kitt2 1.0.1 keyvspread
@ornikar/kitt2 1.0.2 keyvspread
@ornikar/kitt2 1.0.3 keyvspread
@ornikar/kitt2 1.0.4 keyvspread
@ornikar/kitt2 1.0.5 keyvspread
@ornikar/kitt2 1.0.6 keyvspread
@ornikar/kitt2 1.0.7 keyvspread
@ornikar/kitt2 1.0.8 keyvspread
@ornikar/kitt2 1.0.9 keyvspread
@ornikar/kitt2 1.0.10 keyvspread
@ornikar/kitt2 1.0.11 keyvspread
@ornikar/lerna-config 11.0.1 keyvspread
@ornikar/lerna-config 11.0.2 keyvspread
@ornikar/lerna-config 11.0.3 keyvspread
@ornikar/lerna-config 11.0.4 keyvspread
@ornikar/lerna-config 11.0.5 keyvspread
@ornikar/lerna-config 11.0.6 keyvspread
@ornikar/lerna-config 11.0.7 keyvspread
@ornikar/lerna-config 11.0.8 keyvspread
@ornikar/lerna-config 11.0.9 keyvspread
@ornikar/lerna-config 11.0.10 keyvspread
@ornikar/lerna-config 11.0.11 keyvspread
@ornikar/monorepo-config 14.3.2 keyvspread
@ornikar/monorepo-config 14.3.3 keyvspread
@ornikar/monorepo-config 14.3.4 keyvspread
@ornikar/monorepo-config 14.3.5 keyvspread
@ornikar/monorepo-config 14.3.6 keyvspread
@ornikar/monorepo-config 14.3.7 keyvspread
@ornikar/monorepo-config 14.3.8 keyvspread
@ornikar/monorepo-config 14.3.9 keyvspread
@ornikar/monorepo-config 14.3.10 keyvspread
@ornikar/monorepo-config 14.3.11 keyvspread
@ornikar/monorepo-config 14.3.12 keyvspread
@ornikar/monorepo-config 14.3.13 keyvspread
@ornikar/postcss-config 9.1.2 keyvspread
@ornikar/postcss-config 9.1.3 keyvspread
@ornikar/postcss-config 9.1.4 keyvspread
@ornikar/postcss-config 9.1.5 keyvspread
@ornikar/postcss-config 9.1.6 keyvspread
@ornikar/postcss-config 9.1.7 keyvspread
@ornikar/postcss-config 9.1.8 keyvspread
@ornikar/postcss-config 9.1.9 keyvspread
@ornikar/postcss-config 9.1.10 keyvspread
@ornikar/postcss-config 9.1.11 keyvspread
@ornikar/postcss-config 9.1.12 keyvspread
@ornikar/prettier-config 9.0.3 keyvspread
@ornikar/prettier-config 9.0.4 keyvspread
@ornikar/prettier-config 9.0.5 keyvspread
@ornikar/prettier-config 9.0.6 keyvspread
@ornikar/prettier-config 9.0.7 keyvspread
@ornikar/prettier-config 9.0.8 keyvspread
@ornikar/prettier-config 9.0.9 keyvspread
@ornikar/prettier-config 9.0.10 keyvspread
@ornikar/prettier-config 9.0.11 keyvspread
@ornikar/prismic-components 0.0.2 keyvspread
@ornikar/prismic-components 0.0.3 keyvspread
@ornikar/prismic-components 0.0.4 keyvspread
@ornikar/prismic-components 0.0.5 keyvspread
@ornikar/prismic-components 0.0.6 keyvspread
@ornikar/prismic-components 0.0.7 keyvspread
@ornikar/prismic-components 0.0.8 keyvspread
@ornikar/prismic-components 0.0.9 keyvspread
@ornikar/prismic-components 0.0.10 keyvspread
@ornikar/prismic-components 0.0.11 keyvspread
@ornikar/prismic-components 0.0.12 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.1 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.2 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.3 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.4 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.5 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.6 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.7 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.8 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.9 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.10 keyvspread
@ornikar/react-modern-calendar-datepicker 3.2.11 keyvspread
@ornikar/react-native-svg-transformer 1.0.6 keyvspread
@ornikar/react-native-svg-transformer 1.0.7 keyvspread
@ornikar/react-native-svg-transformer 1.0.8 keyvspread
@ornikar/react-native-svg-transformer 1.0.9 keyvspread
@ornikar/react-native-svg-transformer 1.0.10 keyvspread
@ornikar/react-native-svg-transformer 1.0.11 keyvspread
@ornikar/react-native-svg-transformer 1.0.12 keyvspread
@ornikar/react-native-svg-transformer 1.0.13 keyvspread
@ornikar/renovate-config 9.0.2 keyvspread
@ornikar/renovate-config 9.0.3 keyvspread
@ornikar/renovate-config 9.0.4 keyvspread
@ornikar/renovate-config 9.0.5 keyvspread
@ornikar/renovate-config 9.0.6 keyvspread
@ornikar/renovate-config 9.0.7 keyvspread
@ornikar/renovate-config 9.0.8 keyvspread
@ornikar/renovate-config 9.0.9 keyvspread
@ornikar/renovate-config 9.0.10 keyvspread
@ornikar/renovate-config 9.0.11 keyvspread
@ornikar/renovate-config 9.0.12 keyvspread
@ornikar/renovate-config 9.0.13 keyvspread
@ornikar/repo-config 15.3.3 keyvspread
@ornikar/repo-config 15.3.4 keyvspread
@ornikar/repo-config 15.3.5 keyvspread
@ornikar/repo-config 15.3.6 keyvspread
@ornikar/repo-config 15.3.7 keyvspread
@ornikar/repo-config 15.3.8 keyvspread
@ornikar/repo-config 15.3.9 keyvspread
@ornikar/repo-config 15.3.10 keyvspread
@ornikar/repo-config 15.3.11 keyvspread
@ornikar/repo-config 15.3.12 keyvspread
@ornikar/repo-config 15.3.13 keyvspread
@ornikar/repo-config-react 13.0.8 keyvspread
@ornikar/repo-config-react 13.0.9 keyvspread
@ornikar/repo-config-react 13.0.10 keyvspread
@ornikar/repo-config-react 13.0.11 keyvspread
@ornikar/repo-config-react 13.0.12 keyvspread
@ornikar/repo-config-react 13.0.13 keyvspread
@ornikar/repo-config-react 13.0.14 keyvspread
@ornikar/repo-config-react 13.0.15 keyvspread
@ornikar/repo-config-react 13.0.16 keyvspread
@ornikar/repo-config-react 13.0.17 keyvspread
@ornikar/repo-config-react 13.0.18 keyvspread
@ornikar/repo-config-react 13.0.19 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.2 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.3 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.4 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.5 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.6 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.7 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.8 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.9 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.10 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.11 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.12 keyvspread
@ornikar/repo-config-react-legacy-css 15.1.13 keyvspread
@ornikar/rollup-config 11.1.2 keyvspread
@ornikar/rollup-config 11.1.3 keyvspread
@ornikar/rollup-config 11.1.4 keyvspread
@ornikar/rollup-config 11.1.5 keyvspread
@ornikar/rollup-config 11.1.6 keyvspread
@ornikar/rollup-config 11.1.7 keyvspread
@ornikar/rollup-config 11.1.8 keyvspread
@ornikar/rollup-config 11.1.9 keyvspread
@ornikar/rollup-config 11.1.10 keyvspread
@ornikar/rollup-config 11.1.11 keyvspread
@ornikar/rollup-config 11.1.12 keyvspread
@ornikar/rollup-config 11.1.13 keyvspread
@ornikar/rollup-plugin-postcss 2.0.5 keyvspread
@ornikar/rollup-plugin-postcss 2.0.6 keyvspread
@ornikar/rollup-plugin-postcss 2.0.7 keyvspread
@ornikar/rollup-plugin-postcss 2.0.8 keyvspread
@ornikar/rollup-plugin-postcss 2.0.9 keyvspread
@ornikar/rollup-plugin-postcss 2.0.10 keyvspread
@ornikar/rollup-plugin-postcss 2.0.11 keyvspread
@ornikar/rollup-plugin-postcss 2.0.12 keyvspread
@ornikar/rollup-plugin-postcss 2.0.13 keyvspread
@ornikar/rollup-plugin-postcss 2.0.14 keyvspread
@ornikar/rollup-plugin-postcss 2.0.15 keyvspread
@ornikar/slate-react-fork 1.0.1 keyvspread
@ornikar/slate-react-fork 1.0.2 keyvspread
@ornikar/slate-react-fork 1.0.3 keyvspread
@ornikar/slate-react-fork 1.0.4 keyvspread
@ornikar/slate-react-fork 1.0.5 keyvspread
@ornikar/slate-react-fork 1.0.6 keyvspread
@ornikar/slate-react-fork 1.0.7 keyvspread
@ornikar/slate-react-fork 1.0.8 keyvspread
@ornikar/slate-react-fork 1.0.9 keyvspread
@ornikar/slate-react-fork 1.0.10 keyvspread
@ornikar/slate-react-fork 1.0.11 keyvspread
@ornikar/storybook-config 12.1.2 keyvspread
@ornikar/storybook-config 12.1.3 keyvspread
@ornikar/storybook-config 12.1.4 keyvspread
@ornikar/storybook-config 12.1.5 keyvspread
@ornikar/storybook-config 12.1.6 keyvspread
@ornikar/storybook-config 12.1.7 keyvspread
@ornikar/storybook-config 12.1.8 keyvspread
@ornikar/storybook-config 12.1.9 keyvspread
@ornikar/storybook-config 12.1.10 keyvspread
@ornikar/stylelint-config 14.0.3 keyvspread
@ornikar/stylelint-config 14.0.4 keyvspread
@ornikar/stylelint-config 14.0.5 keyvspread
@ornikar/stylelint-config 14.0.6 keyvspread
@ornikar/stylelint-config 14.0.7 keyvspread
@ornikar/stylelint-config 14.0.8 keyvspread
@ornikar/stylelint-config 14.0.9 keyvspread
@ornikar/stylelint-config 14.0.10 keyvspread
@ornikar/stylelint-config 14.0.11 keyvspread
@ornikar/stylelint-config 14.0.12 keyvspread
@ornikar/stylelint-config 14.0.13 keyvspread
@ornikar/typed-css-modules-loader 0.8.2 keyvspread
@ornikar/typed-css-modules-loader 0.8.3 keyvspread
@ornikar/typed-css-modules-loader 0.8.4 keyvspread
@ornikar/typed-css-modules-loader 0.8.5 keyvspread
@ornikar/typed-css-modules-loader 0.8.6 keyvspread
@ornikar/typed-css-modules-loader 0.8.7 keyvspread
@ornikar/typed-css-modules-loader 0.8.8 keyvspread
@ornikar/typed-css-modules-loader 0.8.9 keyvspread
@ornikar/typed-css-modules-loader 0.8.10 keyvspread
@ornikar/typed-css-modules-loader 0.8.11 keyvspread
@ornikar/typed-css-modules-loader 0.8.12 keyvspread
@ornikar/webpack-config 12.0.2 keyvspread
@ornikar/webpack-config 12.0.3 keyvspread
@ornikar/webpack-config 12.0.4 keyvspread
@ornikar/webpack-config 12.0.5 keyvspread
@ornikar/webpack-config 12.0.6 keyvspread
@ornikar/webpack-config 12.0.7 keyvspread
@ornikar/webpack-config 12.0.8 keyvspread
@ornikar/webpack-config 12.0.9 keyvspread
@ornikar/webpack-config 12.0.10 keyvspread
@ornikar/webpack-config 12.0.11 keyvspread
@ornikar/webpack-config 12.0.12 keyvspread
@picsart/ai-sdk 3.32.2 keyvspread
@picsart/gen-ai 2.55.11 keyvspread
@qlik/api 2.14.2 keyvspread
@qlik/browserslist-config 3.0.2 keyvspread
@qlik/carbon-core 2.1.1 keyvspread
@qlik/carboncopy 1.1.6 keyvspread
@qlik/design-tokens 1.3.13 keyvspread
@qlik/dts-bundler 2.0.3 keyvspread
@qlik/embed-react 2.5.3 keyvspread
@qlik/embed-runtime 1.6.4 keyvspread
@qlik/embed-svelte 1.1.4 keyvspread
@qlik/embed-web-components 1.7.3 keyvspread
@qlik/eslint-config 2.0.20 keyvspread
@qlik/eslint-config-base 0.1.1 keyvspread
@qlik/eslint-config-react 0.1.1 keyvspread
@qlik/eslint-config-svelte 0.1.1 keyvspread
@qlik/eslint-config-vue 0.1.1 keyvspread
@qlik/nebula-table-utils 2.6.9 keyvspread
@qlik/oxfmt-config 0.1.6 keyvspread
@qlik/oxlint-config 0.7.2 keyvspread
@qlik/prettier-config 1.0.3 keyvspread
@qlik/react-native-simple-grid 1.5.5 keyvspread
@qlik/runtime-module-loader 1.5.1 keyvspread
@qlik/sdk 0.28.1 keyvspread
@qlik/sprout-design-docs 1.0.2 keyvspread
@qlik/sprout-gesture 0.0.13 keyvspread
@qlik/sprout-icons 0.12.3 keyvspread
@qlik/sprout-react 6.45.3 keyvspread
@qlik/sprout-react-table 0.16.7 keyvspread
@qlik/tsconfig 1.0.3 keyvspread
@servicetitan/acquisition-functions 5.22.1 keyvspread
@servicetitan/acquisition-functions 5.22.2 keyvspread
@servicetitan/acquisition-functions 5.22.3 keyvspread
@servicetitan/acquisition-functions 5.22.4 keyvspread
@servicetitan/acquisition-functions 5.22.5 keyvspread
@servicetitan/acquisition-functions 5.22.6 keyvspread
@servicetitan/acquisition-functions 5.22.7 keyvspread
@servicetitan/admin-layout 2.4.3 keyvspread
@servicetitan/admin-layout 2.4.4 keyvspread
@servicetitan/admin-layout 2.4.5 keyvspread
@servicetitan/admin-layout 2.4.6 keyvspread
@servicetitan/admin-layout 2.4.7 keyvspread
@servicetitan/admin-layout 2.4.8 keyvspread
@servicetitan/admin-layout 2.4.9 keyvspread
@servicetitan/admin-sql-table 1.0.14 keyvspread
@servicetitan/admin-sql-table 1.0.15 keyvspread
@servicetitan/admin-sql-table 1.0.16 keyvspread
@servicetitan/admin-sql-table 1.0.17 keyvspread
@servicetitan/admin-sql-table 1.0.18 keyvspread
@servicetitan/admin-sql-table 1.0.19 keyvspread
@servicetitan/admin-sql-table 1.0.20 keyvspread
@servicetitan/ajax-handlers 38.1.1 keyvspread
@servicetitan/ajax-handlers 38.1.2 keyvspread
@servicetitan/ajax-handlers 38.1.3 keyvspread
@servicetitan/ajax-handlers 38.1.4 keyvspread
@servicetitan/ajax-handlers 38.1.5 keyvspread
@servicetitan/ajax-handlers 38.1.6 keyvspread
@servicetitan/ajax-handlers 38.1.7 keyvspread
@servicetitan/anvil-css-utilities 14.5.4 keyvspread
@servicetitan/anvil-css-utilities 14.5.5 keyvspread
@servicetitan/anvil-css-utilities 14.5.6 keyvspread
@servicetitan/anvil-css-utilities 14.5.7 keyvspread
@servicetitan/anvil-css-utilities 14.5.8 keyvspread
@servicetitan/anvil-css-utilities 14.5.9 keyvspread
@servicetitan/anvil-css-utilities 14.5.10 keyvspread
@servicetitan/anvil-fonts 14.5.4 keyvspread
@servicetitan/anvil-fonts 14.5.5 keyvspread
@servicetitan/anvil-fonts 14.5.6 keyvspread
@servicetitan/anvil-fonts 14.5.7 keyvspread
@servicetitan/anvil-fonts 14.5.8 keyvspread
@servicetitan/anvil-fonts 14.5.9 keyvspread
@servicetitan/anvil-fonts 14.5.10 keyvspread
@servicetitan/anvil-icon 0.5.1 keyvspread
@servicetitan/anvil-icon 0.5.2 keyvspread
@servicetitan/anvil-icon 0.5.3 keyvspread
@servicetitan/anvil-icon 0.5.4 keyvspread
@servicetitan/anvil-icon 0.5.5 keyvspread
@servicetitan/anvil-icon 0.5.6 keyvspread
@servicetitan/anvil-icon 0.5.7 keyvspread
@servicetitan/anvil-icons 14.5.4 keyvspread
@servicetitan/anvil-icons 14.5.5 keyvspread
@servicetitan/anvil-icons 14.5.6 keyvspread
@servicetitan/anvil-icons 14.5.7 keyvspread
@servicetitan/anvil-icons 14.5.8 keyvspread
@servicetitan/anvil-icons 14.5.9 keyvspread
@servicetitan/anvil-icons 14.5.10 keyvspread
@servicetitan/anvil-react 0.11.3 keyvspread
@servicetitan/anvil-react 0.11.4 keyvspread
@servicetitan/anvil-react 0.11.5 keyvspread
@servicetitan/anvil-react 0.11.6 keyvspread
@servicetitan/anvil-react 0.11.7 keyvspread
@servicetitan/anvil-react 0.11.8 keyvspread
@servicetitan/anvil-react 0.11.9 keyvspread
@servicetitan/anvil-themes 14.5.4 keyvspread
@servicetitan/anvil-themes 14.5.5 keyvspread
@servicetitan/anvil-themes 14.5.6 keyvspread
@servicetitan/anvil-themes 14.5.7 keyvspread
@servicetitan/anvil-themes 14.5.8 keyvspread
@servicetitan/anvil-themes 14.5.9 keyvspread
@servicetitan/anvil-themes 14.5.10 keyvspread
@servicetitan/anvil-token 0.4.1 keyvspread
@servicetitan/anvil-token 0.4.2 keyvspread
@servicetitan/anvil-token 0.4.3 keyvspread
@servicetitan/anvil-token 0.4.4 keyvspread
@servicetitan/anvil-token 0.4.5 keyvspread
@servicetitan/anvil-token 0.4.6 keyvspread
@servicetitan/anvil-token 0.4.7 keyvspread
@servicetitan/anvil2 3.9.1 keyvspread
@servicetitan/anvil2 3.9.2 keyvspread
@servicetitan/anvil2 3.9.3 keyvspread
@servicetitan/anvil2 3.9.4 keyvspread
@servicetitan/anvil2 3.9.5 keyvspread
@servicetitan/anvil2 3.9.6 keyvspread
@servicetitan/anvil2 3.9.7 keyvspread
@servicetitan/anvil2-codemods 0.11.2 keyvspread
@servicetitan/anvil2-codemods 0.11.3 keyvspread
@servicetitan/anvil2-codemods 0.11.4 keyvspread
@servicetitan/anvil2-codemods 0.11.5 keyvspread
@servicetitan/anvil2-codemods 0.11.6 keyvspread
@servicetitan/anvil2-codemods 0.11.7 keyvspread
@servicetitan/anvil2-codemods 0.11.8 keyvspread
@servicetitan/anvil2-ext-atlas 4.0.2 keyvspread
@servicetitan/anvil2-ext-atlas 4.0.3 keyvspread
@servicetitan/anvil2-ext-atlas 4.0.4 keyvspread
@servicetitan/anvil2-ext-atlas 4.0.5 keyvspread
@servicetitan/anvil2-ext-atlas 4.0.6 keyvspread
@servicetitan/anvil2-ext-atlas 4.0.7 keyvspread
@servicetitan/anvil2-ext-atlas 4.0.8 keyvspread
@servicetitan/anvil2-ext-charts 0.2.4 keyvspread
@servicetitan/anvil2-ext-charts 0.2.5 keyvspread
@servicetitan/anvil2-ext-charts 0.2.6 keyvspread
@servicetitan/anvil2-ext-charts 0.2.7 keyvspread
@servicetitan/anvil2-ext-charts 0.2.8 keyvspread
@servicetitan/anvil2-ext-charts 0.2.9 keyvspread
@servicetitan/anvil2-ext-charts 0.2.10 keyvspread
@servicetitan/anvil2-ext-common 0.7.1 keyvspread
@servicetitan/anvil2-ext-common 0.7.2 keyvspread
@servicetitan/anvil2-ext-common 0.7.3 keyvspread
@servicetitan/anvil2-ext-common 0.7.4 keyvspread
@servicetitan/anvil2-ext-common 0.7.5 keyvspread
@servicetitan/anvil2-ext-common 0.7.6 keyvspread
@servicetitan/anvil2-ext-common 0.7.7 keyvspread
@servicetitan/anvil2-ext-mwv 0.0.5 keyvspread
@servicetitan/anvil2-ext-mwv 0.0.6 keyvspread
@servicetitan/anvil2-ext-mwv 0.0.7 keyvspread
@servicetitan/anvil2-ext-mwv 0.0.8 keyvspread
@servicetitan/anvil2-ext-mwv 0.0.9 keyvspread
@servicetitan/anvil2-ext-mwv 0.0.10 keyvspread
@servicetitan/anvil2-ext-mwv 0.0.11 keyvspread
@servicetitan/anvil2-illustrations 1.0.2 keyvspread
@servicetitan/anvil2-illustrations 1.0.3 keyvspread
@servicetitan/anvil2-illustrations 1.0.4 keyvspread
@servicetitan/anvil2-illustrations 1.0.5 keyvspread
@servicetitan/anvil2-illustrations 1.0.6 keyvspread
@servicetitan/anvil2-illustrations 1.0.7 keyvspread
@servicetitan/anvil2-illustrations 1.0.8 keyvspread
@servicetitan/anvil2-mcp 0.0.9 keyvspread
@servicetitan/anvil2-mcp 0.0.10 keyvspread
@servicetitan/anvil2-mcp 0.0.11 keyvspread
@servicetitan/anvil2-mcp 0.0.12 keyvspread
@servicetitan/anvil2-mcp 0.0.13 keyvspread
@servicetitan/anvil2-mcp 0.0.14 keyvspread
@servicetitan/anvil2-mcp 0.0.15 keyvspread
@servicetitan/assist-ui 2.1.1 keyvspread
@servicetitan/assist-ui 2.1.2 keyvspread
@servicetitan/assist-ui 2.1.3 keyvspread
@servicetitan/assist-ui 2.1.4 keyvspread
@servicetitan/assist-ui 2.1.5 keyvspread
@servicetitan/assist-ui 2.1.6 keyvspread
@servicetitan/assist-ui 2.1.7 keyvspread
@servicetitan/assist-utils 1.1.2 keyvspread
@servicetitan/assist-utils 1.1.3 keyvspread
@servicetitan/assist-utils 1.1.4 keyvspread
@servicetitan/assist-utils 1.1.5 keyvspread
@servicetitan/assist-utils 1.1.6 keyvspread
@servicetitan/assist-utils 1.1.7 keyvspread
@servicetitan/assist-utils 1.1.8 keyvspread
@servicetitan/carto-charts-core 0.0.2 keyvspread
@servicetitan/carto-charts-core 0.0.3 keyvspread
@servicetitan/carto-charts-core 0.0.4 keyvspread
@servicetitan/carto-charts-core 0.0.5 keyvspread
@servicetitan/carto-charts-core 0.0.6 keyvspread
@servicetitan/carto-charts-core 0.0.7 keyvspread
@servicetitan/carto-charts-core 0.0.8 keyvspread
@servicetitan/carto-charts-react 0.0.2 keyvspread
@servicetitan/carto-charts-react 0.0.3 keyvspread
@servicetitan/carto-charts-react 0.0.4 keyvspread
@servicetitan/carto-charts-react 0.0.5 keyvspread
@servicetitan/carto-charts-react 0.0.6 keyvspread
@servicetitan/carto-charts-react 0.0.7 keyvspread
@servicetitan/carto-charts-react 0.0.8 keyvspread
@servicetitan/carto-charts-rn 0.0.2 keyvspread
@servicetitan/carto-charts-rn 0.0.3 keyvspread
@servicetitan/carto-charts-rn 0.0.4 keyvspread
@servicetitan/carto-charts-rn 0.0.5 keyvspread
@servicetitan/carto-charts-rn 0.0.6 keyvspread
@servicetitan/carto-charts-rn 0.0.7 keyvspread
@servicetitan/carto-charts-rn 0.0.8 keyvspread
@servicetitan/carto-react-kit 0.8.4 keyvspread
@servicetitan/carto-react-kit 0.8.5 keyvspread
@servicetitan/carto-react-kit 0.8.6 keyvspread
@servicetitan/carto-react-kit 0.8.7 keyvspread
@servicetitan/carto-react-kit 0.8.8 keyvspread
@servicetitan/carto-react-kit 0.8.9 keyvspread
@servicetitan/carto-react-kit 0.8.10 keyvspread
@servicetitan/carto-rn-kit 0.0.10 keyvspread
@servicetitan/carto-rn-kit 0.0.11 keyvspread
@servicetitan/carto-rn-kit 0.0.12 keyvspread
@servicetitan/carto-rn-kit 0.0.13 keyvspread
@servicetitan/carto-rn-kit 0.0.14 keyvspread
@servicetitan/carto-rn-kit 0.0.15 keyvspread
@servicetitan/carto-rn-kit 0.0.16 keyvspread
@servicetitan/carto-tokens 0.3.1 keyvspread
@servicetitan/carto-tokens 0.3.2 keyvspread
@servicetitan/carto-tokens 0.3.3 keyvspread
@servicetitan/carto-tokens 0.3.4 keyvspread
@servicetitan/carto-tokens 0.3.5 keyvspread
@servicetitan/carto-tokens 0.3.6 keyvspread
@servicetitan/carto-tokens 0.3.7 keyvspread
@servicetitan/component-usage 28.5.1 keyvspread
@servicetitan/component-usage 28.5.2 keyvspread
@servicetitan/component-usage 28.5.3 keyvspread
@servicetitan/component-usage 28.5.4 keyvspread
@servicetitan/component-usage 28.5.5 keyvspread
@servicetitan/component-usage 28.5.6 keyvspread
@servicetitan/component-usage 28.5.7 keyvspread
@servicetitan/confirm 41.3.1 keyvspread
@servicetitan/confirm 41.3.2 keyvspread
@servicetitan/confirm 41.3.3 keyvspread
@servicetitan/confirm 41.3.4 keyvspread
@servicetitan/confirm 41.3.5 keyvspread
@servicetitan/confirm 41.3.6 keyvspread
@servicetitan/confirm 41.3.7 keyvspread
@servicetitan/confirm-navigation 41.3.1 keyvspread
@servicetitan/confirm-navigation 41.3.2 keyvspread
@servicetitan/confirm-navigation 41.3.3 keyvspread
@servicetitan/confirm-navigation 41.3.4 keyvspread
@servicetitan/confirm-navigation 41.3.5 keyvspread
@servicetitan/confirm-navigation 41.3.6 keyvspread
@servicetitan/confirm-navigation 41.3.7 keyvspread
@servicetitan/contentful 0.0.3 keyvspread
@servicetitan/contentful 0.0.4 keyvspread
@servicetitan/contentful 0.0.5 keyvspread
@servicetitan/contentful 0.0.6 keyvspread
@servicetitan/contentful 0.0.7 keyvspread
@servicetitan/contentful 0.0.8 keyvspread
@servicetitan/contentful 0.0.9 keyvspread
@servicetitan/contentful-proxy 1.1.12 keyvspread
@servicetitan/contentful-proxy 1.1.13 keyvspread
@servicetitan/contentful-proxy 1.1.14 keyvspread
@servicetitan/contentful-proxy 1.1.15 keyvspread
@servicetitan/contentful-proxy 1.1.16 keyvspread
@servicetitan/contentful-proxy 1.1.17 keyvspread
@servicetitan/contentful-proxy 1.1.18 keyvspread
@servicetitan/cp-api 1.115.1 keyvspread
@servicetitan/cp-api 1.115.2 keyvspread
@servicetitan/cp-api 1.115.3 keyvspread
@servicetitan/cp-api 1.115.4 keyvspread
@servicetitan/cp-api 1.115.5 keyvspread
@servicetitan/cp-api 1.115.6 keyvspread
@servicetitan/cp-api 1.115.7 keyvspread
@servicetitan/cp-mfe 1.115.1 keyvspread
@servicetitan/cp-mfe 1.115.2 keyvspread
@servicetitan/cp-mfe 1.115.3 keyvspread
@servicetitan/cp-mfe 1.115.4 keyvspread
@servicetitan/cp-mfe 1.115.5 keyvspread
@servicetitan/cp-mfe 1.115.6 keyvspread
@servicetitan/cp-mfe 1.115.7 keyvspread
@servicetitan/cp-mfe-dev 1.115.1 keyvspread
@servicetitan/cp-mfe-dev 1.115.2 keyvspread
@servicetitan/cp-mfe-dev 1.115.3 keyvspread
@servicetitan/cp-mfe-dev 1.115.4 keyvspread
@servicetitan/cp-mfe-dev 1.115.5 keyvspread
@servicetitan/cp-mfe-dev 1.115.6 keyvspread
@servicetitan/cp-mfe-dev 1.115.7 keyvspread
@servicetitan/cp-react-hooks 1.115.1 keyvspread
@servicetitan/cp-react-hooks 1.115.2 keyvspread
@servicetitan/cp-react-hooks 1.115.3 keyvspread
@servicetitan/cp-react-hooks 1.115.4 keyvspread
@servicetitan/cp-react-hooks 1.115.5 keyvspread
@servicetitan/cp-react-hooks 1.115.6 keyvspread
@servicetitan/cp-react-hooks 1.115.7 keyvspread
@servicetitan/cp-ui 1.115.1 keyvspread
@servicetitan/cp-ui 1.115.2 keyvspread
@servicetitan/cp-ui 1.115.3 keyvspread
@servicetitan/cp-ui 1.115.4 keyvspread
@servicetitan/cp-ui 1.115.5 keyvspread
@servicetitan/cp-ui 1.115.6 keyvspread
@servicetitan/cp-ui 1.115.7 keyvspread
@servicetitan/culture 41.3.1 keyvspread
@servicetitan/culture 41.3.2 keyvspread
@servicetitan/culture 41.3.3 keyvspread
@servicetitan/culture 41.3.4 keyvspread
@servicetitan/culture 41.3.5 keyvspread
@servicetitan/culture 41.3.6 keyvspread
@servicetitan/culture 41.3.7 keyvspread
@servicetitan/data-query 41.3.1 keyvspread
@servicetitan/data-query 41.3.2 keyvspread
@servicetitan/data-query 41.3.3 keyvspread
@servicetitan/data-query 41.3.4 keyvspread
@servicetitan/data-query 41.3.5 keyvspread
@servicetitan/data-query 41.3.6 keyvspread
@servicetitan/data-query 41.3.7 keyvspread
@servicetitan/datadog-rum 38.1.1 keyvspread
@servicetitan/datadog-rum 38.1.2 keyvspread
@servicetitan/datadog-rum 38.1.3 keyvspread
@servicetitan/datadog-rum 38.1.4 keyvspread
@servicetitan/datadog-rum 38.1.5 keyvspread
@servicetitan/datadog-rum 38.1.6 keyvspread
@servicetitan/datadog-rum 38.1.7 keyvspread
@servicetitan/datetime-utils 41.3.1 keyvspread
@servicetitan/datetime-utils 41.3.2 keyvspread
@servicetitan/datetime-utils 41.3.3 keyvspread
@servicetitan/datetime-utils 41.3.4 keyvspread
@servicetitan/datetime-utils 41.3.5 keyvspread
@servicetitan/datetime-utils 41.3.6 keyvspread
@servicetitan/datetime-utils 41.3.7 keyvspread
@servicetitan/design-system 14.5.4 keyvspread
@servicetitan/design-system 14.5.5 keyvspread
@servicetitan/design-system 14.5.6 keyvspread
@servicetitan/design-system 14.5.7 keyvspread
@servicetitan/design-system 14.5.8 keyvspread
@servicetitan/design-system 14.5.9 keyvspread
@servicetitan/design-system 14.5.10 keyvspread
@servicetitan/docs-anvil-uikit-contrib 41.3.1 keyvspread
@servicetitan/docs-anvil-uikit-contrib 41.3.2 keyvspread
@servicetitan/docs-anvil-uikit-contrib 41.3.3 keyvspread
@servicetitan/docs-anvil-uikit-contrib 41.3.4 keyvspread
@servicetitan/docs-anvil-uikit-contrib 41.3.5 keyvspread
@servicetitan/docs-anvil-uikit-contrib 41.3.6 keyvspread
@servicetitan/docs-anvil-uikit-contrib 41.3.7 keyvspread
@servicetitan/docs-uikit 38.1.1 keyvspread
@servicetitan/docs-uikit 38.1.2 keyvspread
@servicetitan/docs-uikit 38.1.3 keyvspread
@servicetitan/docs-uikit 38.1.4 keyvspread
@servicetitan/docs-uikit 38.1.5 keyvspread
@servicetitan/docs-uikit 38.1.6 keyvspread
@servicetitan/docs-uikit 38.1.7 keyvspread
@servicetitan/document-title 2.4.1 keyvspread
@servicetitan/document-title 2.4.2 keyvspread
@servicetitan/document-title 2.4.3 keyvspread
@servicetitan/document-title 2.4.4 keyvspread
@servicetitan/document-title 2.4.5 keyvspread
@servicetitan/document-title 2.4.6 keyvspread
@servicetitan/document-title 2.4.7 keyvspread
@servicetitan/dte-pdf-editor 1.76.1 keyvspread
@servicetitan/dte-pdf-editor 1.76.2 keyvspread
@servicetitan/dte-pdf-editor 1.76.3 keyvspread
@servicetitan/dte-pdf-editor 1.76.4 keyvspread
@servicetitan/dte-pdf-editor 1.76.5 keyvspread
@servicetitan/dte-pdf-editor 1.76.6 keyvspread
@servicetitan/dte-pdf-editor 1.76.7 keyvspread
@servicetitan/dte-unlayer 0.150.1 keyvspread
@servicetitan/dte-unlayer 0.150.2 keyvspread
@servicetitan/dte-unlayer 0.150.3 keyvspread
@servicetitan/dte-unlayer 0.150.4 keyvspread
@servicetitan/dte-unlayer 0.150.5 keyvspread
@servicetitan/dte-unlayer 0.150.6 keyvspread
@servicetitan/dte-unlayer 0.150.7 keyvspread
@servicetitan/eh-module-communication 0.2.1 keyvspread
@servicetitan/eh-module-communication 0.2.2 keyvspread
@servicetitan/eh-module-communication 0.2.3 keyvspread
@servicetitan/eh-module-communication 0.2.4 keyvspread
@servicetitan/eh-module-communication 0.2.5 keyvspread
@servicetitan/eh-module-communication 0.2.6 keyvspread
@servicetitan/eh-module-communication 0.2.7 keyvspread
@servicetitan/error-boundary 38.1.1 keyvspread
@servicetitan/error-boundary 38.1.2 keyvspread
@servicetitan/error-boundary 38.1.3 keyvspread
@servicetitan/error-boundary 38.1.4 keyvspread
@servicetitan/error-boundary 38.1.5 keyvspread
@servicetitan/error-boundary 38.1.6 keyvspread
@servicetitan/error-boundary 38.1.7 keyvspread
@servicetitan/eslint-config 38.1.1 keyvspread
@servicetitan/eslint-config 38.1.2 keyvspread
@servicetitan/eslint-config 38.1.3 keyvspread
@servicetitan/eslint-config 38.1.4 keyvspread
@servicetitan/eslint-config 38.1.5 keyvspread
@servicetitan/eslint-config 38.1.6 keyvspread
@servicetitan/eslint-config 38.1.7 keyvspread
@servicetitan/eslint-plugin 38.1.1 keyvspread
@servicetitan/eslint-plugin 38.1.2 keyvspread
@servicetitan/eslint-plugin 38.1.3 keyvspread
@servicetitan/eslint-plugin 38.1.4 keyvspread
@servicetitan/eslint-plugin 38.1.5 keyvspread
@servicetitan/eslint-plugin 38.1.6 keyvspread
@servicetitan/eslint-plugin 38.1.7 keyvspread
@servicetitan/eslint-plugin-decorators-declare 12.8.15 keyvspread
@servicetitan/eslint-plugin-decorators-declare 12.8.16 keyvspread
@servicetitan/eslint-plugin-decorators-declare 12.8.17 keyvspread
@servicetitan/eslint-plugin-decorators-declare 12.8.18 keyvspread
@servicetitan/eslint-plugin-decorators-declare 12.8.19 keyvspread
@servicetitan/eslint-plugin-decorators-declare 12.8.20 keyvspread
@servicetitan/eslint-plugin-decorators-declare 12.8.21 keyvspread
@servicetitan/eslint-plugin-folder-schema 38.1.1 keyvspread
@servicetitan/eslint-plugin-folder-schema 38.1.2 keyvspread
@servicetitan/eslint-plugin-folder-schema 38.1.3 keyvspread
@servicetitan/eslint-plugin-folder-schema 38.1.4 keyvspread
@servicetitan/eslint-plugin-folder-schema 38.1.5 keyvspread
@servicetitan/eslint-plugin-folder-schema 38.1.6 keyvspread
@servicetitan/eslint-plugin-folder-schema 38.1.7 keyvspread
@servicetitan/eslint-plugin-mobx-6 12.8.15 keyvspread
@servicetitan/eslint-plugin-mobx-6 12.8.16 keyvspread
@servicetitan/eslint-plugin-mobx-6 12.8.17 keyvspread
@servicetitan/eslint-plugin-mobx-6 12.8.18 keyvspread
@servicetitan/eslint-plugin-mobx-6 12.8.19 keyvspread
@servicetitan/eslint-plugin-mobx-6 12.8.20 keyvspread
@servicetitan/eslint-plugin-processors-stub 12.8.15 keyvspread
@servicetitan/eslint-plugin-processors-stub 12.8.16 keyvspread
@servicetitan/eslint-plugin-processors-stub 12.8.17 keyvspread
@servicetitan/eslint-plugin-processors-stub 12.8.18 keyvspread
@servicetitan/eslint-plugin-processors-stub 12.8.19 keyvspread
@servicetitan/eslint-plugin-processors-stub 12.8.20 keyvspread
@servicetitan/eslint-plugin-processors-stub 12.8.21 keyvspread
@servicetitan/examples 1.2.5 keyvspread
@servicetitan/examples 1.2.6 keyvspread
@servicetitan/examples 1.2.7 keyvspread
@servicetitan/examples 1.2.8 keyvspread
@servicetitan/examples 1.2.9 keyvspread
@servicetitan/examples 1.2.10 keyvspread
@servicetitan/examples 1.2.11 keyvspread
@servicetitan/feature-spotlight 3.9.1 keyvspread
@servicetitan/feature-spotlight 3.9.2 keyvspread
@servicetitan/feature-spotlight 3.9.3 keyvspread
@servicetitan/feature-spotlight 3.9.4 keyvspread
@servicetitan/feature-spotlight 3.9.5 keyvspread
@servicetitan/feature-spotlight 3.9.6 keyvspread
@servicetitan/feature-spotlight 3.9.7 keyvspread
@servicetitan/folder-lint 38.1.1 keyvspread
@servicetitan/folder-lint 38.1.2 keyvspread
@servicetitan/folder-lint 38.1.3 keyvspread
@servicetitan/folder-lint 38.1.4 keyvspread
@servicetitan/folder-lint 38.1.5 keyvspread
@servicetitan/folder-lint 38.1.6 keyvspread
@servicetitan/folder-lint 38.1.7 keyvspread
@servicetitan/forge 0.5.1 keyvspread
@servicetitan/forge 0.5.2 keyvspread
@servicetitan/forge 0.5.3 keyvspread
@servicetitan/forge 0.5.4 keyvspread
@servicetitan/forge 0.5.5 keyvspread
@servicetitan/forge 0.5.6 keyvspread
@servicetitan/forge 0.5.7 keyvspread
@servicetitan/form 41.3.1 keyvspread
@servicetitan/form 41.3.2 keyvspread
@servicetitan/form 41.3.3 keyvspread
@servicetitan/form 41.3.4 keyvspread
@servicetitan/form 41.3.5 keyvspread
@servicetitan/form 41.3.6 keyvspread
@servicetitan/form 41.3.7 keyvspread
@servicetitan/form-state 41.3.1 keyvspread
@servicetitan/form-state 41.3.2 keyvspread
@servicetitan/form-state 41.3.3 keyvspread
@servicetitan/form-state 41.3.4 keyvspread
@servicetitan/form-state 41.3.5 keyvspread
@servicetitan/form-state 41.3.6 keyvspread
@servicetitan/form-state 41.3.7 keyvspread
@servicetitan/grid 0.0.63 keyvspread
@servicetitan/grid 0.0.64 keyvspread
@servicetitan/grid 0.0.65 keyvspread
@servicetitan/grid 0.0.66 keyvspread
@servicetitan/grid 0.0.67 keyvspread
@servicetitan/grid 0.0.68 keyvspread
@servicetitan/grid 0.0.69 keyvspread
@servicetitan/hammer-icon 1.2.1 keyvspread
@servicetitan/hammer-icon 1.2.2 keyvspread
@servicetitan/hammer-icon 1.2.3 keyvspread
@servicetitan/hammer-icon 1.2.4 keyvspread
@servicetitan/hammer-icon 1.2.5 keyvspread
@servicetitan/hammer-icon 1.2.6 keyvspread
@servicetitan/hammer-icon 1.2.7 keyvspread
@servicetitan/hammer-react 1.42.2 keyvspread
@servicetitan/hammer-react 1.42.3 keyvspread
@servicetitan/hammer-react 1.42.4 keyvspread
@servicetitan/hammer-react 1.42.5 keyvspread
@servicetitan/hammer-react 1.42.6 keyvspread
@servicetitan/hammer-react 1.42.7 keyvspread
@servicetitan/hammer-react 1.42.8 keyvspread
@servicetitan/hammer-token 3.1.1 keyvspread
@servicetitan/hammer-token 3.1.2 keyvspread
@servicetitan/hammer-token 3.1.3 keyvspread
@servicetitan/hammer-token 3.1.4 keyvspread
@servicetitan/hammer-token 3.1.5 keyvspread
@servicetitan/hammer-token 3.1.6 keyvspread
@servicetitan/hammer-token 3.1.7 keyvspread
@servicetitan/hash-browser-router 38.1.1 keyvspread
@servicetitan/hash-browser-router 38.1.2 keyvspread
@servicetitan/hash-browser-router 38.1.3 keyvspread
@servicetitan/hash-browser-router 38.1.4 keyvspread
@servicetitan/hash-browser-router 38.1.5 keyvspread
@servicetitan/hash-browser-router 38.1.6 keyvspread
@servicetitan/hash-browser-router 38.1.7 keyvspread
@servicetitan/help-center 1.0.8 keyvspread
@servicetitan/help-center 1.0.9 keyvspread
@servicetitan/help-center 1.0.10 keyvspread
@servicetitan/help-center 1.0.11 keyvspread
@servicetitan/help-center 1.0.12 keyvspread
@servicetitan/help-center 1.0.13 keyvspread
@servicetitan/help-center 1.0.14 keyvspread
@servicetitan/html-sketchapp 4.2.8 keyvspread
@servicetitan/html-sketchapp 4.2.9 keyvspread
@servicetitan/html-sketchapp 4.2.10 keyvspread
@servicetitan/html-sketchapp 4.2.11 keyvspread
@servicetitan/html-sketchapp 4.2.12 keyvspread
@servicetitan/html-sketchapp 4.2.13 keyvspread
@servicetitan/html-sketchapp 4.2.14 keyvspread
@servicetitan/install 38.1.1 keyvspread
@servicetitan/install 38.1.2 keyvspread
@servicetitan/install 38.1.3 keyvspread
@servicetitan/install 38.1.4 keyvspread
@servicetitan/install 38.1.5 keyvspread
@servicetitan/install 38.1.6 keyvspread
@servicetitan/install 38.1.7 keyvspread
@servicetitan/intl 7.2.1 keyvspread
@servicetitan/intl 7.2.2 keyvspread
@servicetitan/intl 7.2.3 keyvspread
@servicetitan/intl 7.2.4 keyvspread
@servicetitan/intl 7.2.5 keyvspread
@servicetitan/intl 7.2.6 keyvspread
@servicetitan/intl 7.2.7 keyvspread
@servicetitan/json-render-react 0.4.6 keyvspread
@servicetitan/json-render-react 0.4.7 keyvspread
@servicetitan/json-render-react 0.4.8 keyvspread
@servicetitan/json-render-react 0.4.9 keyvspread
@servicetitan/json-render-react 0.4.10 keyvspread
@servicetitan/json-render-react 0.4.11 keyvspread
@servicetitan/json-render-react 0.4.12 keyvspread
@servicetitan/kendo-theme 0.0.27 keyvspread
@servicetitan/kendo-theme 0.0.28 keyvspread
@servicetitan/kendo-theme 0.0.29 keyvspread
@servicetitan/kendo-theme 0.0.30 keyvspread
@servicetitan/kendo-theme 0.0.31 keyvspread
@servicetitan/kendo-theme 0.0.32 keyvspread
@servicetitan/kendo-theme 0.0.33 keyvspread
@servicetitan/ko-bridge 38.1.1 keyvspread
@servicetitan/ko-bridge 38.1.2 keyvspread
@servicetitan/ko-bridge 38.1.3 keyvspread
@servicetitan/ko-bridge 38.1.4 keyvspread
@servicetitan/ko-bridge 38.1.5 keyvspread
@servicetitan/ko-bridge 38.1.6 keyvspread
@servicetitan/ko-bridge 38.1.7 keyvspread
@servicetitan/launchdarkly-service 38.1.1 keyvspread
@servicetitan/launchdarkly-service 38.1.2 keyvspread
@servicetitan/launchdarkly-service 38.1.3 keyvspread
@servicetitan/launchdarkly-service 38.1.4 keyvspread
@servicetitan/launchdarkly-service 38.1.5 keyvspread
@servicetitan/launchdarkly-service 38.1.6 keyvspread
@servicetitan/launchdarkly-service 38.1.7 keyvspread
@servicetitan/lazy-module 38.1.1 keyvspread
@servicetitan/lazy-module 38.1.2 keyvspread
@servicetitan/lazy-module 38.1.3 keyvspread
@servicetitan/lazy-module 38.1.4 keyvspread
@servicetitan/lazy-module 38.1.5 keyvspread
@servicetitan/lazy-module 38.1.6 keyvspread
@servicetitan/lazy-module 38.1.7 keyvspread
@servicetitan/ld-type-generator 0.2.1 keyvspread
@servicetitan/ld-type-generator 0.2.2 keyvspread
@servicetitan/ld-type-generator 0.2.3 keyvspread
@servicetitan/ld-type-generator 0.2.4 keyvspread
@servicetitan/ld-type-generator 0.2.5 keyvspread
@servicetitan/ld-type-generator 0.2.6 keyvspread
@servicetitan/ld-type-generator 0.2.7 keyvspread
@servicetitan/line-item-editor 1.5.1 keyvspread
@servicetitan/line-item-editor 1.5.2 keyvspread
@servicetitan/line-item-editor 1.5.3 keyvspread
@servicetitan/line-item-editor 1.5.4 keyvspread
@servicetitan/line-item-editor 1.5.5 keyvspread
@servicetitan/line-item-editor 1.5.6 keyvspread
@servicetitan/line-item-editor 1.5.7 keyvspread
@servicetitan/link-item 41.3.1 keyvspread
@servicetitan/link-item 41.3.2 keyvspread
@servicetitan/link-item 41.3.3 keyvspread
@servicetitan/link-item 41.3.4 keyvspread
@servicetitan/link-item 41.3.5 keyvspread
@servicetitan/link-item 41.3.6 keyvspread
@servicetitan/link-item 41.3.7 keyvspread
@servicetitan/log-service 38.1.1 keyvspread
@servicetitan/log-service 38.1.2 keyvspread
@servicetitan/log-service 38.1.3 keyvspread
@servicetitan/log-service 38.1.4 keyvspread
@servicetitan/log-service 38.1.5 keyvspread
@servicetitan/log-service 38.1.6 keyvspread
@servicetitan/log-service 38.1.7 keyvspread
@servicetitan/marketing-direct-mail-components 20.1.1 keyvspread
@servicetitan/marketing-direct-mail-components 20.1.2 keyvspread
@servicetitan/marketing-direct-mail-components 20.1.3 keyvspread
@servicetitan/marketing-direct-mail-components 20.1.4 keyvspread
@servicetitan/marketing-direct-mail-components 20.1.5 keyvspread
@servicetitan/marketing-direct-mail-components 20.1.6 keyvspread
@servicetitan/marketing-direct-mail-components 20.1.7 keyvspread
@servicetitan/marketing-email-components 20.2.3 keyvspread
@servicetitan/marketing-email-components 20.2.4 keyvspread
@servicetitan/marketing-email-components 20.2.5 keyvspread
@servicetitan/marketing-email-components 20.2.6 keyvspread
@servicetitan/marketing-email-components 20.2.7 keyvspread
@servicetitan/marketing-email-components 20.2.8 keyvspread
@servicetitan/marketing-email-components 20.2.9 keyvspread
@servicetitan/marketing-form 0.1.2 keyvspread
@servicetitan/marketing-form 0.1.3 keyvspread
@servicetitan/marketing-form 0.1.4 keyvspread
@servicetitan/marketing-form 0.1.5 keyvspread
@servicetitan/marketing-form 0.1.6 keyvspread
@servicetitan/marketing-form 0.1.7 keyvspread
@servicetitan/marketing-form 0.1.8 keyvspread
@servicetitan/marketing-global-route 1.14.1 keyvspread
@servicetitan/marketing-global-route 1.14.2 keyvspread
@servicetitan/marketing-global-route 1.14.3 keyvspread
@servicetitan/marketing-global-route 1.14.4 keyvspread
@servicetitan/marketing-global-route 1.14.5 keyvspread
@servicetitan/marketing-global-route 1.14.6 keyvspread
@servicetitan/marketing-global-route 1.14.7 keyvspread
@servicetitan/marketing-integration-widgets 1.0.40 keyvspread
@servicetitan/marketing-integration-widgets 1.0.41 keyvspread
@servicetitan/marketing-integration-widgets 1.0.42 keyvspread
@servicetitan/marketing-integration-widgets 1.0.43 keyvspread
@servicetitan/marketing-integration-widgets 1.0.44 keyvspread
@servicetitan/marketing-integration-widgets 1.0.45 keyvspread
@servicetitan/marketing-integration-widgets 1.0.46 keyvspread
@servicetitan/marketing-route 1.2.1 keyvspread
@servicetitan/marketing-route 1.2.2 keyvspread
@servicetitan/marketing-route 1.2.3 keyvspread
@servicetitan/marketing-route 1.2.4 keyvspread
@servicetitan/marketing-route 1.2.5 keyvspread
@servicetitan/marketing-route 1.2.6 keyvspread
@servicetitan/marketing-route 1.2.7 keyvspread
@servicetitan/marketing-ui 9.3.1 keyvspread
@servicetitan/marketing-ui 9.3.2 keyvspread
@servicetitan/marketing-ui 9.3.3 keyvspread
@servicetitan/marketing-ui 9.3.4 keyvspread
@servicetitan/marketing-ui 9.3.5 keyvspread
@servicetitan/marketing-ui 9.3.6 keyvspread
@servicetitan/marketing-ui 9.3.7 keyvspread
@servicetitan/marketing-widgets 1.0.1 keyvspread
@servicetitan/marketing-widgets 1.0.2 keyvspread
@servicetitan/marketing-widgets 1.0.3 keyvspread
@servicetitan/marketing-widgets 1.0.4 keyvspread
@servicetitan/marketing-widgets 1.0.5 keyvspread
@servicetitan/marketing-widgets 1.0.6 keyvspread
@servicetitan/marketing-widgets 1.0.7 keyvspread
@servicetitan/measure-sheet-data 2.6.1 keyvspread
@servicetitan/measure-sheet-data 2.6.2 keyvspread
@servicetitan/measure-sheet-data 2.6.3 keyvspread
@servicetitan/measure-sheet-data 2.6.4 keyvspread
@servicetitan/measure-sheet-data 2.6.5 keyvspread
@servicetitan/measure-sheet-data 2.6.6 keyvspread
@servicetitan/measure-sheet-data 2.6.7 keyvspread
@servicetitan/mfe-quick-actions 0.5.49 keyvspread
@servicetitan/mfe-quick-actions 0.5.50 keyvspread
@servicetitan/mfe-quick-actions 0.5.51 keyvspread
@servicetitan/mfe-quick-actions 0.5.52 keyvspread
@servicetitan/mfe-quick-actions 0.5.53 keyvspread
@servicetitan/mfe-quick-actions 0.5.54 keyvspread
@servicetitan/mfe-quick-actions 0.5.55 keyvspread
@servicetitan/micro-frontend 0.0.4 keyvspread
@servicetitan/micro-frontend 0.0.5 keyvspread
@servicetitan/micro-frontend 0.0.6 keyvspread
@servicetitan/micro-frontend 0.0.7 keyvspread
@servicetitan/micro-frontend 0.0.8 keyvspread
@servicetitan/micro-frontend 0.0.9 keyvspread
@servicetitan/micro-frontend 0.0.10 keyvspread
@servicetitan/microfront 0.0.2 keyvspread
@servicetitan/microfront 0.0.3 keyvspread
@servicetitan/microfront 0.0.4 keyvspread
@servicetitan/microfront 0.0.5 keyvspread
@servicetitan/microfront 0.0.6 keyvspread
@servicetitan/microfront 0.0.7 keyvspread
@servicetitan/microfront 0.0.8 keyvspread
@servicetitan/microfront-auth 0.0.5 keyvspread
@servicetitan/microfront-auth 0.0.6 keyvspread
@servicetitan/microfront-auth 0.0.7 keyvspread
@servicetitan/microfront-auth 0.0.8 keyvspread
@servicetitan/microfront-auth 0.0.9 keyvspread
@servicetitan/microfront-auth 0.0.10 keyvspread
@servicetitan/microfront-auth 0.0.11 keyvspread
@servicetitan/microfront-tests 0.0.11 keyvspread
@servicetitan/microfront-tests 0.0.12 keyvspread
@servicetitan/microfront-tests 0.0.13 keyvspread
@servicetitan/microfront-tests 0.0.14 keyvspread
@servicetitan/microfront-tests 0.0.15 keyvspread
@servicetitan/microfront-tests 0.0.16 keyvspread
@servicetitan/microfront-tests 0.0.17 keyvspread
@servicetitan/microfront-utils 1.4.1 keyvspread
@servicetitan/microfront-utils 1.4.2 keyvspread
@servicetitan/microfront-utils 1.4.3 keyvspread
@servicetitan/microfront-utils 1.4.4 keyvspread
@servicetitan/microfront-utils 1.4.5 keyvspread
@servicetitan/microfront-utils 1.4.6 keyvspread
@servicetitan/microfront-utils 1.4.7 keyvspread
@servicetitan/modularpayments-webfields 1.0.53 keyvspread
@servicetitan/modularpayments-webfields 1.0.54 keyvspread
@servicetitan/modularpayments-webfields 1.0.55 keyvspread
@servicetitan/modularpayments-webfields 1.0.56 keyvspread
@servicetitan/modularpayments-webfields 1.0.57 keyvspread
@servicetitan/modularpayments-webfields 1.0.58 keyvspread
@servicetitan/modularpayments-webfields 1.0.59 keyvspread
@servicetitan/moneyout-api-client 1.29.1 keyvspread
@servicetitan/moneyout-api-client 1.29.2 keyvspread
@servicetitan/moneyout-api-client 1.29.3 keyvspread
@servicetitan/moneyout-api-client 1.29.4 keyvspread
@servicetitan/moneyout-api-client 1.29.5 keyvspread
@servicetitan/moneyout-api-client 1.29.6 keyvspread
@servicetitan/moneyout-api-client 1.29.7 keyvspread
@servicetitan/mpa-components 2.5.1 keyvspread
@servicetitan/mpa-components 2.5.2 keyvspread
@servicetitan/mpa-components 2.5.3 keyvspread
@servicetitan/mpa-components 2.5.4 keyvspread
@servicetitan/mpa-components 2.5.5 keyvspread
@servicetitan/mpa-components 2.5.6 keyvspread
@servicetitan/mpa-components 2.5.7 keyvspread
@servicetitan/navigation 14.1.1 keyvspread
@servicetitan/navigation 14.1.2 keyvspread
@servicetitan/navigation 14.1.3 keyvspread
@servicetitan/navigation 14.1.4 keyvspread
@servicetitan/navigation 14.1.5 keyvspread
@servicetitan/navigation 14.1.6 keyvspread
@servicetitan/navigation 14.1.7 keyvspread
@servicetitan/notifications 41.3.1 keyvspread
@servicetitan/notifications 41.3.2 keyvspread
@servicetitan/notifications 41.3.3 keyvspread
@servicetitan/notifications 41.3.4 keyvspread
@servicetitan/notifications 41.3.5 keyvspread
@servicetitan/notifications 41.3.6 keyvspread
@servicetitan/notifications 41.3.7 keyvspread
@servicetitan/onboarding-ui 18.5.1 keyvspread
@servicetitan/onboarding-ui 18.5.2 keyvspread
@servicetitan/onboarding-ui 18.5.3 keyvspread
@servicetitan/onboarding-ui 18.5.4 keyvspread
@servicetitan/onboarding-ui 18.5.5 keyvspread
@servicetitan/onboarding-ui 18.5.6 keyvspread
@servicetitan/onboarding-ui 18.5.7 keyvspread
@servicetitan/quick-actions 1.15.2 keyvspread
@servicetitan/quick-actions 1.15.3 keyvspread
@servicetitan/quick-actions 1.15.4 keyvspread
@servicetitan/quick-actions 1.15.5 keyvspread
@servicetitan/quick-actions 1.15.6 keyvspread
@servicetitan/quick-actions 1.15.7 keyvspread
@servicetitan/quick-actions 1.15.8 keyvspread
@servicetitan/react-hooks 7.7.1 keyvspread
@servicetitan/react-hooks 7.7.2 keyvspread
@servicetitan/react-hooks 7.7.3 keyvspread
@servicetitan/react-hooks 7.7.4 keyvspread
@servicetitan/react-hooks 7.7.5 keyvspread
@servicetitan/react-hooks 7.7.6 keyvspread
@servicetitan/react-hooks 7.7.7 keyvspread
@servicetitan/react-ioc 38.1.1 keyvspread
@servicetitan/react-ioc 38.1.2 keyvspread
@servicetitan/react-ioc 38.1.3 keyvspread
@servicetitan/react-ioc 38.1.4 keyvspread
@servicetitan/react-ioc 38.1.5 keyvspread
@servicetitan/react-ioc 38.1.6 keyvspread
@servicetitan/react-ioc 38.1.7 keyvspread
@servicetitan/responsive 6.1.1 keyvspread
@servicetitan/responsive 6.1.2 keyvspread
@servicetitan/responsive 6.1.3 keyvspread
@servicetitan/responsive 6.1.4 keyvspread
@servicetitan/responsive 6.1.5 keyvspread
@servicetitan/responsive 6.1.6 keyvspread
@servicetitan/responsive 6.1.7 keyvspread
@servicetitan/restrict-imports 38.1.1 keyvspread
@servicetitan/restrict-imports 38.1.2 keyvspread
@servicetitan/restrict-imports 38.1.3 keyvspread
@servicetitan/restrict-imports 38.1.4 keyvspread
@servicetitan/restrict-imports 38.1.5 keyvspread
@servicetitan/restrict-imports 38.1.6 keyvspread
@servicetitan/restrict-imports 38.1.7 keyvspread
@servicetitan/schema-comparison 0.1.3 keyvspread
@servicetitan/schema-comparison 0.1.4 keyvspread
@servicetitan/schema-comparison 0.1.5 keyvspread
@servicetitan/schema-comparison 0.1.6 keyvspread
@servicetitan/schema-comparison 0.1.7 keyvspread
@servicetitan/schema-comparison 0.1.8 keyvspread
@servicetitan/schema-comparison 0.1.9 keyvspread
@servicetitan/skeleton 9.2.4 keyvspread
@servicetitan/skeleton 9.2.5 keyvspread
@servicetitan/skeleton 9.2.6 keyvspread
@servicetitan/skeleton 9.2.7 keyvspread
@servicetitan/skeleton 9.2.8 keyvspread
@servicetitan/skeleton 9.2.9 keyvspread
@servicetitan/skeleton 9.2.10 keyvspread
@servicetitan/standalone-core-feature-gates 1.11.4 keyvspread
@servicetitan/standalone-core-feature-gates 1.11.5 keyvspread
@servicetitan/standalone-core-feature-gates 1.11.6 keyvspread
@servicetitan/standalone-core-feature-gates 1.11.7 keyvspread
@servicetitan/standalone-core-feature-gates 1.11.8 keyvspread
@servicetitan/standalone-core-feature-gates 1.11.9 keyvspread
@servicetitan/standalone-core-feature-gates 1.11.10 keyvspread
@servicetitan/standalone-feature-flags 2.3.2 keyvspread
@servicetitan/standalone-feature-flags 2.3.3 keyvspread
@servicetitan/standalone-feature-flags 2.3.4 keyvspread
@servicetitan/standalone-feature-flags 2.3.5 keyvspread
@servicetitan/standalone-feature-flags 2.3.6 keyvspread
@servicetitan/standalone-feature-flags 2.3.7 keyvspread
@servicetitan/standalone-feature-flags 2.3.8 keyvspread
@servicetitan/standalone-root 1.11.3 keyvspread
@servicetitan/standalone-root 1.11.4 keyvspread
@servicetitan/standalone-root 1.11.5 keyvspread
@servicetitan/standalone-root 1.11.6 keyvspread
@servicetitan/standalone-root 1.11.7 keyvspread
@servicetitan/standalone-root 1.11.8 keyvspread
@servicetitan/standalone-root 1.11.9 keyvspread
@servicetitan/standalone-tm-api 1.1.1 keyvspread
@servicetitan/standalone-tm-api 1.1.2 keyvspread
@servicetitan/standalone-tm-api 1.1.3 keyvspread
@servicetitan/standalone-tm-api 1.1.4 keyvspread
@servicetitan/standalone-tm-api 1.1.5 keyvspread
@servicetitan/standalone-tm-api 1.1.6 keyvspread
@servicetitan/standalone-tm-api 1.1.7 keyvspread
@servicetitan/standalone-ui 2.2.4 keyvspread
@servicetitan/standalone-ui 2.2.5 keyvspread
@servicetitan/standalone-ui 2.2.6 keyvspread
@servicetitan/standalone-ui 2.2.7 keyvspread
@servicetitan/standalone-ui 2.2.8 keyvspread
@servicetitan/standalone-ui 2.2.9 keyvspread
@servicetitan/standalone-ui 2.2.10 keyvspread
@servicetitan/startup 38.1.1 keyvspread
@servicetitan/startup 38.1.2 keyvspread
@servicetitan/startup 38.1.3 keyvspread
@servicetitan/startup 38.1.4 keyvspread
@servicetitan/startup 38.1.5 keyvspread
@servicetitan/startup 38.1.6 keyvspread
@servicetitan/startup 38.1.7 keyvspread
@servicetitan/startup-jest 2.2.1 keyvspread
@servicetitan/startup-jest 2.2.2 keyvspread
@servicetitan/startup-jest 2.2.3 keyvspread
@servicetitan/startup-jest 2.2.4 keyvspread
@servicetitan/startup-jest 2.2.5 keyvspread
@servicetitan/startup-jest 2.2.6 keyvspread
@servicetitan/startup-jest 2.2.7 keyvspread
@servicetitan/startup-mfe-compat 0.5.1 keyvspread
@servicetitan/startup-mfe-compat 0.5.2 keyvspread
@servicetitan/startup-mfe-compat 0.5.3 keyvspread
@servicetitan/startup-mfe-compat 0.5.4 keyvspread
@servicetitan/startup-mfe-compat 0.5.5 keyvspread
@servicetitan/startup-mfe-compat 0.5.6 keyvspread
@servicetitan/startup-mfe-compat 0.5.7 keyvspread
@servicetitan/startup-utils 38.1.1 keyvspread
@servicetitan/startup-utils 38.1.2 keyvspread
@servicetitan/startup-utils 38.1.3 keyvspread
@servicetitan/startup-utils 38.1.4 keyvspread
@servicetitan/startup-utils 38.1.5 keyvspread
@servicetitan/startup-utils 38.1.6 keyvspread
@servicetitan/startup-utils 38.1.7 keyvspread
@servicetitan/stylelint-config 38.1.1 keyvspread
@servicetitan/stylelint-config 38.1.2 keyvspread
@servicetitan/stylelint-config 38.1.3 keyvspread
@servicetitan/stylelint-config 38.1.4 keyvspread
@servicetitan/stylelint-config 38.1.5 keyvspread
@servicetitan/stylelint-config 38.1.6 keyvspread
@servicetitan/stylelint-config 38.1.7 keyvspread
@servicetitan/suppress-warnings 38.1.1 keyvspread
@servicetitan/suppress-warnings 38.1.2 keyvspread
@servicetitan/suppress-warnings 38.1.3 keyvspread
@servicetitan/suppress-warnings 38.1.4 keyvspread
@servicetitan/suppress-warnings 38.1.5 keyvspread
@servicetitan/suppress-warnings 38.1.6 keyvspread
@servicetitan/suppress-warnings 38.1.7 keyvspread
@servicetitan/table 41.3.1 keyvspread
@servicetitan/table 41.3.2 keyvspread
@servicetitan/table 41.3.3 keyvspread
@servicetitan/table 41.3.4 keyvspread
@servicetitan/table 41.3.5 keyvspread
@servicetitan/table 41.3.6 keyvspread
@servicetitan/table 41.3.7 keyvspread
@servicetitan/tanstack-query-mobx 6.2.1 keyvspread
@servicetitan/tanstack-query-mobx 6.2.2 keyvspread
@servicetitan/tanstack-query-mobx 6.2.3 keyvspread
@servicetitan/tanstack-query-mobx 6.2.4 keyvspread
@servicetitan/tanstack-query-mobx 6.2.5 keyvspread
@servicetitan/tanstack-query-mobx 6.2.6 keyvspread
@servicetitan/tanstack-query-mobx 6.2.7 keyvspread
@servicetitan/temporal-lite 3.4.1 keyvspread
@servicetitan/temporal-lite 3.4.2 keyvspread
@servicetitan/temporal-lite 3.4.3 keyvspread
@servicetitan/temporal-lite 3.4.4 keyvspread
@servicetitan/temporal-lite 3.4.5 keyvspread
@servicetitan/temporal-lite 3.4.6 keyvspread
@servicetitan/temporal-lite 3.4.7 keyvspread
@servicetitan/testing-library 6.6.1 keyvspread
@servicetitan/testing-library 6.6.2 keyvspread
@servicetitan/testing-library 6.6.3 keyvspread
@servicetitan/testing-library 6.6.4 keyvspread
@servicetitan/testing-library 6.6.5 keyvspread
@servicetitan/testing-library 6.6.6 keyvspread
@servicetitan/testing-library 6.6.7 keyvspread
@servicetitan/thoughtspot-theme 1.7.1 keyvspread
@servicetitan/thoughtspot-theme 1.7.2 keyvspread
@servicetitan/thoughtspot-theme 1.7.3 keyvspread
@servicetitan/thoughtspot-theme 1.7.4 keyvspread
@servicetitan/thoughtspot-theme 1.7.5 keyvspread
@servicetitan/thoughtspot-theme 1.7.6 keyvspread
@servicetitan/thoughtspot-theme 1.7.7 keyvspread
@servicetitan/time-zones 3.8.1 keyvspread
@servicetitan/time-zones 3.8.2 keyvspread
@servicetitan/time-zones 3.8.3 keyvspread
@servicetitan/time-zones 3.8.4 keyvspread
@servicetitan/time-zones 3.8.5 keyvspread
@servicetitan/time-zones 3.8.6 keyvspread
@servicetitan/time-zones 3.8.7 keyvspread
@servicetitan/titan-chat-ui 7.1.3 keyvspread
@servicetitan/titan-chat-ui 7.1.4 keyvspread
@servicetitan/titan-chat-ui 7.1.5 keyvspread
@servicetitan/titan-chat-ui 7.1.6 keyvspread
@servicetitan/titan-chat-ui 7.1.7 keyvspread
@servicetitan/titan-chat-ui 7.1.8 keyvspread
@servicetitan/titan-chat-ui 7.1.9 keyvspread
@servicetitan/titan-chat-ui-anvil2 9.0.1 keyvspread
@servicetitan/titan-chat-ui-anvil2 9.0.2 keyvspread
@servicetitan/titan-chat-ui-anvil2 9.0.3 keyvspread
@servicetitan/titan-chat-ui-anvil2 9.0.4 keyvspread
@servicetitan/titan-chat-ui-anvil2 9.0.5 keyvspread
@servicetitan/titan-chat-ui-anvil2 9.0.6 keyvspread
@servicetitan/titan-chat-ui-anvil2 9.0.7 keyvspread
@servicetitan/titan-chat-ui-common 9.0.1 keyvspread
@servicetitan/titan-chat-ui-common 9.0.2 keyvspread
@servicetitan/titan-chat-ui-common 9.0.3 keyvspread
@servicetitan/titan-chat-ui-common 9.0.4 keyvspread
@servicetitan/titan-chat-ui-common 9.0.5 keyvspread
@servicetitan/titan-chat-ui-common 9.0.6 keyvspread
@servicetitan/titan-chat-ui-common 9.0.7 keyvspread
@servicetitan/titan-chat-ui-cypress 2.1.3 keyvspread
@servicetitan/titan-chat-ui-cypress 2.1.4 keyvspread
@servicetitan/titan-chat-ui-cypress 2.1.5 keyvspread
@servicetitan/titan-chat-ui-cypress 2.1.6 keyvspread
@servicetitan/titan-chat-ui-cypress 2.1.7 keyvspread
@servicetitan/titan-chat-ui-cypress 2.1.8 keyvspread
@servicetitan/titan-chat-ui-cypress 2.1.9 keyvspread
@servicetitan/titan-chatbot-api 9.0.1 keyvspread
@servicetitan/titan-chatbot-api 9.0.2 keyvspread
@servicetitan/titan-chatbot-api 9.0.3 keyvspread
@servicetitan/titan-chatbot-api 9.0.4 keyvspread
@servicetitan/titan-chatbot-api 9.0.5 keyvspread
@servicetitan/titan-chatbot-api 9.0.6 keyvspread
@servicetitan/titan-chatbot-api 9.0.7 keyvspread
@servicetitan/titan-chatbot-client 2.1.3 keyvspread
@servicetitan/titan-chatbot-client 2.1.4 keyvspread
@servicetitan/titan-chatbot-client 2.1.5 keyvspread
@servicetitan/titan-chatbot-client 2.1.6 keyvspread
@servicetitan/titan-chatbot-client 2.1.7 keyvspread
@servicetitan/titan-chatbot-client 2.1.8 keyvspread
@servicetitan/titan-chatbot-client 2.1.9 keyvspread
@servicetitan/titan-chatbot-ui 7.1.3 keyvspread
@servicetitan/titan-chatbot-ui 7.1.4 keyvspread
@servicetitan/titan-chatbot-ui 7.1.5 keyvspread
@servicetitan/titan-chatbot-ui 7.1.6 keyvspread
@servicetitan/titan-chatbot-ui 7.1.7 keyvspread
@servicetitan/titan-chatbot-ui 7.1.8 keyvspread
@servicetitan/titan-chatbot-ui 7.1.9 keyvspread
@servicetitan/titan-chatbot-ui-anvil2 9.0.1 keyvspread
@servicetitan/titan-chatbot-ui-anvil2 9.0.2 keyvspread
@servicetitan/titan-chatbot-ui-anvil2 9.0.3 keyvspread
@servicetitan/titan-chatbot-ui-anvil2 9.0.4 keyvspread
@servicetitan/titan-chatbot-ui-anvil2 9.0.5 keyvspread
@servicetitan/titan-chatbot-ui-anvil2 9.0.6 keyvspread
@servicetitan/titan-chatbot-ui-anvil2 9.0.7 keyvspread
@servicetitan/titan-chatbot-ui-cypress 9.0.1 keyvspread
@servicetitan/titan-chatbot-ui-cypress 9.0.2 keyvspread
@servicetitan/titan-chatbot-ui-cypress 9.0.3 keyvspread
@servicetitan/titan-chatbot-ui-cypress 9.0.4 keyvspread
@servicetitan/titan-chatbot-ui-cypress 9.0.5 keyvspread
@servicetitan/titan-chatbot-ui-cypress 9.0.6 keyvspread
@servicetitan/titan-chatbot-ui-cypress 9.0.7 keyvspread
@servicetitan/tokens 12.9.1 keyvspread
@servicetitan/tokens 12.9.2 keyvspread
@servicetitan/tokens 12.9.3 keyvspread
@servicetitan/tokens 12.9.4 keyvspread
@servicetitan/tokens 12.9.5 keyvspread
@servicetitan/tokens 12.9.6 keyvspread
@servicetitan/tokens 12.9.7 keyvspread
@servicetitan/toolbelt-shared-registry 1.14.1 keyvspread
@servicetitan/toolbelt-shared-registry 1.14.2 keyvspread
@servicetitan/toolbelt-shared-registry 1.14.3 keyvspread
@servicetitan/toolbelt-shared-registry 1.14.4 keyvspread
@servicetitan/toolbelt-shared-registry 1.14.5 keyvspread
@servicetitan/toolbelt-shared-registry 1.14.6 keyvspread
@servicetitan/toolbelt-shared-registry 1.14.7 keyvspread
@servicetitan/uikit-docs 22.11.1 keyvspread
@servicetitan/uikit-docs 22.11.2 keyvspread
@servicetitan/uikit-docs 22.11.3 keyvspread
@servicetitan/uikit-docs 22.11.4 keyvspread
@servicetitan/uikit-docs 22.11.5 keyvspread
@servicetitan/uikit-docs 22.11.6 keyvspread
@servicetitan/uikit-docs 22.11.7 keyvspread
@servicetitan/unit-tests 0.0.2 keyvspread
@servicetitan/unit-tests 0.0.3 keyvspread
@servicetitan/unit-tests 0.0.4 keyvspread
@servicetitan/unit-tests 0.0.5 keyvspread
@servicetitan/unit-tests 0.0.6 keyvspread
@servicetitan/unit-tests 0.0.7 keyvspread
@servicetitan/unit-tests 0.0.8 keyvspread
@servicetitan/va-mfe-loader 1.1.1 keyvspread
@servicetitan/va-mfe-loader 1.1.2 keyvspread
@servicetitan/va-mfe-loader 1.1.3 keyvspread
@servicetitan/va-mfe-loader 1.1.4 keyvspread
@servicetitan/va-mfe-loader 1.1.5 keyvspread
@servicetitan/va-mfe-loader 1.1.6 keyvspread
@servicetitan/va-mfe-loader 1.1.7 keyvspread
@servicetitan/web-components 38.1.1 keyvspread
@servicetitan/web-components 38.1.2 keyvspread
@servicetitan/web-components 38.1.3 keyvspread
@servicetitan/web-components 38.1.4 keyvspread
@servicetitan/web-components 38.1.5 keyvspread
@servicetitan/web-components 38.1.6 keyvspread
@servicetitan/web-components 38.1.7 keyvspread
@servicetitan/widget-platform 5.6.1 keyvspread
@servicetitan/widget-platform 5.6.2 keyvspread
@servicetitan/widget-platform 5.6.3 keyvspread
@servicetitan/widget-platform 5.6.4 keyvspread
@servicetitan/widget-platform 5.6.5 keyvspread
@servicetitan/widget-platform 5.6.6 keyvspread
@servicetitan/widget-platform 5.6.7 keyvspread
@servicetitan/widget-platform-monolith 5.6.1 keyvspread
@servicetitan/widget-platform-monolith 5.6.2 keyvspread
@servicetitan/widget-platform-monolith 5.6.3 keyvspread
@servicetitan/widget-platform-monolith 5.6.4 keyvspread
@servicetitan/widget-platform-monolith 5.6.5 keyvspread
@servicetitan/widget-platform-monolith 5.6.6 keyvspread
@servicetitan/widget-platform-monolith 5.6.7 keyvspread
@thiennq/docs-viewer 1.6.2 keyvspread
@thiennq/docs-viewer 1.6.3 keyvspread
@thiennq/docs-viewer 1.6.4 keyvspread
@umacloud/cli-darwin-arm64 1.0.74 keyvspread
@umacloud/cli-darwin-x64 1.0.74 keyvspread
@umacloud/cli-linux-arm64 1.0.74 keyvspread
@umacloud/cli-linux-musl-arm64 1.0.74 keyvspread
@umacloud/cli-linux-musl-x64 1.0.74 keyvspread
@umacloud/cli-linux-x64 1.0.74 keyvspread
@umacloud/cli-win32-x64 1.0.74 keyvspread
@umacloud/knowledge 1.0.74 keyvspread
@workbench-stack/core 3.9.8 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.1 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.2 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.3 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.4 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.5 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.6 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.7 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.8 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.9 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.10 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.11 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.12 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.13 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.14 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.15 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.16 keyvspread
babel-plugin-linaria-css-to-undefined 0.3.17 keyvspread
conv-context-next 1.0.1 keyvspread
conv-context-next 1.0.2 keyvspread
conv-context-next 1.0.3 keyvspread
conv-context-next 1.0.4 keyvspread
conv-context-next 1.0.5 keyvspread
conv-context-next 1.0.6 keyvspread
conv-context-next 1.0.7 keyvspread
conv-context-next 1.0.8 keyvspread
conv-context-next 1.0.9 keyvspread
conv-context-next 1.0.10 keyvspread
editable-contracts 0.0.12 keyvspread
editable-contracts 0.0.13 keyvspread
editable-contracts 0.0.14 keyvspread
editable-contracts 0.0.15 keyvspread
editable-contracts 0.0.16 keyvspread
editable-contracts 0.0.17 keyvspread
editable-contracts 0.0.18 keyvspread
editable-contracts 0.0.19 keyvspread
editable-contracts 0.0.20 keyvspread
editable-contracts 0.0.21 keyvspread
editable-contracts 0.0.22 keyvspread
editable-contracts 0.0.23 keyvspread
editable-contracts 0.0.24 keyvspread
editable-contracts 0.0.25 keyvspread
editable-contracts 0.0.26 keyvspread
editable-contracts 0.0.27 keyvspread
eslint-plugin-folder-schema 1.0.6 keyvspread
eslint-plugin-folder-schema 1.0.7 keyvspread
eslint-plugin-folder-schema 1.0.8 keyvspread
eslint-plugin-folder-schema 1.0.9 keyvspread
eslint-plugin-folder-schema 1.0.10 keyvspread
eslint-plugin-folder-schema 1.0.11 keyvspread
eslint-plugin-folder-schema 1.0.12 keyvspread
eslint-plugin-folder-schema 1.0.13 keyvspread
eslint-plugin-folder-schema 1.0.14 keyvspread
eslint-plugin-folder-schema 1.0.15 keyvspread
eslint-plugin-folder-schema 1.0.16 keyvspread
eslint-plugin-folder-schema 1.0.17 keyvspread
eslint-plugin-folder-schema 1.0.18 keyvspread
eslint-plugin-folder-schema 1.0.19 keyvspread
eslint-plugin-folder-schema 1.0.20 keyvspread
eslint-plugin-folder-schema 1.0.21 keyvspread
example-js-project 1.0.2 keyvspread
example-js-project 1.0.3 keyvspread
example-js-project 1.0.4 keyvspread
example-js-project 1.0.5 keyvspread
example-js-project 1.0.6 keyvspread
example-js-project 1.0.7 keyvspread
example-js-project 1.0.8 keyvspread
example-js-project 1.0.9 keyvspread
example-js-project 1.0.10 keyvspread
example-js-project 1.0.11 keyvspread
folder-lint 1.0.6 keyvspread
folder-lint 1.0.7 keyvspread
folder-lint 1.0.8 keyvspread
folder-lint 1.0.9 keyvspread
folder-lint 1.0.10 keyvspread
folder-lint 1.0.11 keyvspread
folder-lint 1.0.12 keyvspread
folder-lint 1.0.13 keyvspread
folder-lint 1.0.14 keyvspread
folder-lint 1.0.15 keyvspread
folder-lint 1.0.16 keyvspread
folder-lint 1.0.17 keyvspread
folder-lint 1.0.18 keyvspread
folder-lint 1.0.19 keyvspread
folder-lint 1.0.20 keyvspread
folder-lint 1.0.21 keyvspread
frontend-orb 4.4.1 keyvspread
frontend-orb 4.4.2 keyvspread
frontend-orb 4.4.3 keyvspread
frontend-orb 4.4.4 keyvspread
frontend-orb 4.4.5 keyvspread
frontend-orb 4.4.6 keyvspread
frontend-orb 4.4.7 keyvspread
frontend-orb 4.4.8 keyvspread
frontend-orb 4.4.9 keyvspread
frontend-orb 4.4.10 keyvspread
frontend-orb 4.4.11 keyvspread
frontend-orb 4.4.12 keyvspread
frontend-orb 4.4.13 keyvspread
frontend-orb 4.4.14 keyvspread
frontend-orb 4.4.15 keyvspread
frontend-orb 4.4.16 keyvspread
frontend-orb 4.4.17 keyvspread
frontend-orb 4.4.18 keyvspread
http-metrics-middleware 2.2.2 keyvspread
native-frontend-orb 1.1.4 keyvspread
native-frontend-orb 1.1.5 keyvspread
native-frontend-orb 1.1.6 keyvspread
native-frontend-orb 1.1.7 keyvspread
native-frontend-orb 1.1.8 keyvspread
native-frontend-orb 1.1.9 keyvspread
native-frontend-orb 1.1.10 keyvspread
native-frontend-orb 1.1.11 keyvspread
native-frontend-orb 1.1.12 keyvspread
native-frontend-orb 1.1.13 keyvspread
native-frontend-orb 1.1.14 keyvspread
native-frontend-orb 1.1.15 keyvspread
native-frontend-orb 1.1.16 keyvspread
native-frontend-orb 1.1.17 keyvspread
native-frontend-orb 1.1.18 keyvspread
native-frontend-orb 1.1.19 keyvspread
picasso-plugin-hammer 2.11.6 keyvspread
picasso-plugin-q 2.11.6 keyvspread
picasso.js 2.11.6 keyvspread
pob-test-package-in-monorepo 5.2.1 keyvspread
pob-test-package-in-monorepo 5.2.2 keyvspread
pob-test-package-in-monorepo 5.2.3 keyvspread
pob-test-package-in-monorepo 5.2.4 keyvspread
pob-test-package-in-monorepo 5.2.5 keyvspread
pob-test-package-in-monorepo 5.2.6 keyvspread
pob-test-package-in-monorepo 5.2.7 keyvspread
pob-test-package-in-monorepo 5.2.8 keyvspread
pob-test-package-in-monorepo 5.2.9 keyvspread
pob-test-package-in-monorepo 5.2.10 keyvspread
pob-test-package-in-monorepo 5.2.11 keyvspread
pob-test-package-in-monorepo 5.2.12 keyvspread
pob-test-package-in-monorepo 5.2.13 keyvspread
pob-test-package-in-monorepo 5.2.14 keyvspread
pob-test-package-in-monorepo 5.2.15 keyvspread
pob-test-package-in-monorepo 5.2.16 keyvspread
pob-test-typescript-package-in-monorepo 4.2.1 keyvspread
pob-test-typescript-package-in-monorepo 4.2.2 keyvspread
pob-test-typescript-package-in-monorepo 4.2.3 keyvspread
pob-test-typescript-package-in-monorepo 4.2.4 keyvspread
pob-test-typescript-package-in-monorepo 4.2.5 keyvspread
pob-test-typescript-package-in-monorepo 4.2.6 keyvspread
pob-test-typescript-package-in-monorepo 4.2.7 keyvspread
pob-test-typescript-package-in-monorepo 4.2.8 keyvspread
pob-test-typescript-package-in-monorepo 4.2.9 keyvspread
pob-test-typescript-package-in-monorepo 4.2.10 keyvspread
pob-test-typescript-package-in-monorepo 4.2.11 keyvspread
pob-test-typescript-package-in-monorepo 4.2.12 keyvspread
pob-test-typescript-package-in-monorepo 4.2.13 keyvspread
pob-test-typescript-package-in-monorepo 4.2.14 keyvspread
pob-test-typescript-package-in-monorepo 4.2.15 keyvspread
pob-test-typescript-package-in-monorepo 4.2.16 keyvspread
pob-test-typescript-package-in-monorepo 4.2.17 keyvspread
qlik-chart-modules 1.1.1 keyvspread
qlik-modifiers 0.10.1 keyvspread
qlik-object-conversion 0.17.2 keyvspread
rwc-client 0.29.10 keyvspread
rwc-client 0.29.11 keyvspread
rwc-client 0.29.12 keyvspread
rwc-client 0.29.13 keyvspread
rwc-client 0.29.14 keyvspread
rwc-client 0.29.15 keyvspread
rwc-client 0.29.16 keyvspread
rwc-client 0.29.17 keyvspread
rwc-client 0.29.18 keyvspread
rwc-client 0.29.19 keyvspread
server-hemera-mongo 0.0.12 keyvspread
sn-listbox 0.3.3 keyvspread
tslint-folder-schema 1.0.6 keyvspread
tslint-folder-schema 1.0.7 keyvspread
tslint-folder-schema 1.0.8 keyvspread
tslint-folder-schema 1.0.9 keyvspread
tslint-folder-schema 1.0.10 keyvspread
tslint-folder-schema 1.0.11 keyvspread
tslint-folder-schema 1.0.12 keyvspread
tslint-folder-schema 1.0.13 keyvspread
tslint-folder-schema 1.0.14 keyvspread
tslint-folder-schema 1.0.15 keyvspread
tslint-folder-schema 1.0.16 keyvspread
tslint-folder-schema 1.0.17 keyvspread
tslint-folder-schema 1.0.18 keyvspread
tslint-folder-schema 1.0.19 keyvspread
tslint-folder-schema 1.0.20 keyvspread
tslint-folder-schema 1.0.21 keyvspread
umadev 1.0.74 keyvspread
verdaccio-okta-oauth 38.1.1 keyvspread
verdaccio-okta-oauth 38.1.2 keyvspread
verdaccio-okta-oauth 38.1.3 keyvspread
verdaccio-okta-oauth 38.1.4 keyvspread
verdaccio-okta-oauth 38.1.5 keyvspread
verdaccio-okta-oauth 38.1.6 keyvspread
verdaccio-okta-oauth 38.1.7 keyvspread
verdaccio-okta-oauth 38.1.8 keyvspread
verdaccio-okta-oauth 38.1.9 keyvspread
verdaccio-okta-oauth 38.1.10 keyvspread
verdaccio-okta-oauth 38.1.11 keyvspread
verdaccio-okta-oauth 38.1.12 keyvspread
verdaccio-okta-oauth 38.1.13 keyvspread
verdaccio-okta-oauth 38.1.14 keyvspread
verdaccio-okta-oauth 38.1.15 keyvspread
verdaccio-okta-oauth 38.1.16 keyvspread
verdaccio-tarball-local-storage 38.1.1 keyvspread
verdaccio-tarball-local-storage 38.1.2 keyvspread
verdaccio-tarball-local-storage 38.1.3 keyvspread
verdaccio-tarball-local-storage 38.1.4 keyvspread
verdaccio-tarball-local-storage 38.1.5 keyvspread
verdaccio-tarball-local-storage 38.1.6 keyvspread
verdaccio-tarball-local-storage 38.1.7 keyvspread
verdaccio-tarball-local-storage 38.1.8 keyvspread
verdaccio-tarball-local-storage 38.1.9 keyvspread
verdaccio-tarball-local-storage 38.1.10 keyvspread
verdaccio-tarball-local-storage 38.1.11 keyvspread
verdaccio-tarball-local-storage 38.1.12 keyvspread
verdaccio-tarball-local-storage 38.1.13 keyvspread
verdaccio-tarball-local-storage 38.1.14 keyvspread
verdaccio-tarball-local-storage 38.1.15 keyvspread
verdaccio-tarball-local-storage 38.1.16 keyvspread
workbench-browser-server 0.0.2 keyvspread
@opensearch-project/opensearch 3.5.3 opensearch
@opensearch-project/opensearch 3.6.2 opensearch
@opensearch-project/opensearch 3.7.0 opensearch
@opensearch-project/opensearch 3.8.0 opensearch
tensorlake 0.5.144 tensorlake
tensorlake-native-darwin-arm64 0.5.144 tensorlake
tensorlake-native-linux-arm64-gnu 0.5.144 tensorlake
tensorlake-native-linux-arm64-musl 0.5.144 tensorlake
tensorlake-native-linux-x64-gnu 0.5.144 tensorlake
tensorlake-native-linux-x64-musl 0.5.144 tensorlake
tensorlake-native-win32-x64 0.5.144 tensorlake
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
yarsg 18.0.0 sandworm
yarsg 18.0.1 sandworm
ethres * sandsleep
uudi * sandsleep
@injectivelabs/sdk-ts 1.20.21 injective
@aifabrix/miso-client 4.7.2 glasswormuni
@iflow-mcp/watercrawl-watercrawl-mcp 1.3.0 glasswormuni
@iflow-mcp/watercrawl-watercrawl-mcp 1.3.1 glasswormuni
@iflow-mcp/watercrawl-watercrawl-mcp 1.3.2 glasswormuni
@iflow-mcp/watercrawl-watercrawl-mcp 1.3.3 glasswormuni
@iflow-mcp/watercrawl-watercrawl-mcp 1.3.4 glasswormuni"
# <<< bad-npm
# >>> bad-extensions: generated from data/bad-extensions.tsv by tools/gen.sh. Edit that file, then run it.
BAD_EXT="oorzc.ssh-tools * glassworm openvsx mac
oorzc.i18n-tools-plus 1.6.8 glassworm openvsx mac
oorzc.mind-map 1.0.61 glassworm openvsx mac
oorzc.scss-to-css-compile 1.3.4 glassworm openvsx mac
Angular-studio.ng-angular-extension * glassworm openvsx all
awesome-codebase.codebase-dart-pro * glassworm openvsx all
cudra-production.vsce-prettier-pro * glassworm openvsx all
dev-studio-sense.php-comp-tools-vscode * glassworm openvsx all
ko-zu-gun-studio.synchronization-settings-vscode * glassworm openvsx all
littensy-studio.magical-icons * glassworm openvsx all
pretty-studio-advisor.prettyxml-formatter * glassworm openvsx all
sol-studio.solidity-extension * glassworm openvsx all
studio-jjalaire-team.professional-quarto-extension * glassworm openvsx all
studio-velte-distributor.pro-svelte-extension * glassworm openvsx all
sun-shine-studio.shiny-extension-for-vscode * glassworm openvsx all
tucyzirille-studio.angular-pro-tools-extension * glassworm openvsx all
vce-brendan-studio-eich.js-debuger-vscode * glassworm openvsx all
aadarkcode.one-dark-material * glasswormmar openvsx all
aligntool.extension-align-professional-tool * glasswormmar openvsx all
awesomeco.wonder-for-vscode-icons * glasswormmar openvsx all
bhbpbarn.vsce-python-indent-extension * glasswormmar openvsx all
blockstoks.easily-gitignore-manage * glasswormmar openvsx all
brategmaqendaalar-studio.pro-prettyxml-formatter * glasswormmar openvsx all
codbroks.compile-runnner-extension * glasswormmar openvsx all
codevunmis.csv-sql-tsv-rainbow * glasswormmar openvsx all
codwayexten.code-way-extension * glasswormmar openvsx all
cosmic-themes.sql-formatter * glasswormmar openvsx all
craz2team.vscode-todo-extension * glasswormmar openvsx all
crotoapp.vscode-xml-extension * glasswormmar openvsx all
daeumer-web.es-linter-for-vs-code * glasswormmar openvsx all
dark-code-studio.flutter-extension * glasswormmar openvsx all
densy-little-studio.wonder-for-vscode-icons * glasswormmar openvsx all
dep-labs-studio.dep-proffesinal-extension * glasswormmar openvsx all
devmidu-studio.svg-better-extension * glasswormmar openvsx all
dopbop-studio.vscode-tailwindcss-extension-toolkit * glasswormmar any all
errlenscre.error-lens-finder-ex * glasswormmar openvsx all
exss-studio.yaml-professional-extension * glasswormmar openvsx all
federicanc.dotenv-syntax-highlighting * glasswormmar openvsx all
flutxvs.vscode-kuberntes-extension * glasswormmar openvsx all
gvotcha.claude-code-extension * glasswormmar openvsx all
gvotcha.claude-code-extensions * glasswormmar openvsx all
intellipro.extension-json-intelligence * glasswormmar openvsx all
kharizma.vscode-extension-wakatime * glasswormmar openvsx all
kwitch-studio.auto-run-command-extension * glasswormmar any all
lavender-studio.theme-lavender-dreams * glasswormmar any all
lyu-wen-studio-web-han.better-formatter-vscode * glasswormmar openvsx all
markvalid.vscode-mdvalidator-extension * glasswormmar openvsx all
mecreation-studio.pyrefly-pro-extension * glasswormmar openvsx all
mswincx.antigravity-cockpit * glasswormmar openvsx all
mswincx.antigravity-cockpit-extension * glasswormmar openvsx all
namopins.prettier-pro-vscode-extension * glasswormmar openvsx all
oigotm.my-command-palette-extension * glasswormmar openvsx all
otoboss.autoimport-extension * glasswormmar openvsx all
ovixcode.vscode-better-comments * glasswormmar openvsx all
pessa07tm.my-js-ts-auto-commands * glasswormmar openvsx all
potstok.dotnet-runtime-extension * glasswormmar any all
prismapp.prisma-vs-code-extension * glasswormmar openvsx all
projmanager.your-project-manager-extension * glasswormmar openvsx all
pubruncode.ccoderunner * glasswormmar openvsx all
pyflowpyr.py-flowpyright-extension * glasswormmar openvsx all
pyscopexte.pyscope-extension * glasswormmar openvsx all
redcapcollective.vscode-quarkus-elite-suite * glasswormmar openvsx all
rubyideext.ruby-ide-extension * glasswormmar openvsx all
runnerpost.runner-your-code * glasswormmar openvsx all
shinypy.shiny-extension-for-vscode * glasswormmar openvsx all
ssgwysc.volar-vscode * glasswormmar openvsx all
sxatvo.jinja-extension * glasswormmar openvsx all
tamokill12.foundry-pdf-extension * glasswormmar openvsx all
thing-mn.your-flow-extension-for-icons * glasswormmar openvsx all
tima-web-wang.shell-check-utils * glasswormmar openvsx all
tokcodes.import-cost-extension * glasswormmar openvsx all
toowespace.worksets-extension * glasswormmar openvsx all
treedotree.tree-do-todoextension * glasswormmar openvsx all
turbobase.sql-turbo-tool * glasswormmar openvsx all
twilkbilk.color-highlight-css * glasswormmar openvsx all
yamaprolas.revature-labs-extension * glasswormmar openvsx all
lauracode.wrap-selected-code 0.0.2 glasswormvsix openvsx all
96-studio.json-formatter 0.0.2 glasswormvsix openvsx all
96-studio.json-formatter 0.0.4 glasswormvsix openvsx all
spacetoow.vsc-python-indent 1.21.1 glasswormvsix openvsx all
spacetoow.vsc-python-indent 1.21.3 glasswormvsix openvsx all
spacetoow.vsc-python-indent 1.21.4 glasswormvsix openvsx all
spacetoow.vsc-python-indent 1.21.5 glasswormvsix openvsx all
spacetoow.vsc-python-indent 1.21.6 glasswormvsix openvsx all
spacetoow.vsc-python-indent 1.21.7 glasswormvsix openvsx all
namop-dex.claude-code-assistant 2.1.47 glasswormvsix openvsx all
msw-tm.component-vetur-toolkit 0.37.4 glasswormvsix openvsx all
cod-vok.arko-dev-devsecops 1.0.4 glasswormvsix openvsx all
oxigener-tmp.sql-turbo-manager 0.28.10 glasswormvsix openvsx all
otobo-vs.csv-query-tsv-rainbow 3.3.4 glasswormvsix openvsx all
awesome-codespace.jinja-language-support 0.3.2 glasswormvsix openvsx all
yamal-dext.wonder-workspace-icons 0.10.4 glasswormvsix openvsx all
daeumer-web.align-format-tool 1.4.6 glasswormvsix openvsx all
baksmink.vscode-quokka-extension 1.0.756 glasswormvsix openvsx all
bansheejust22.retro-vhs-theme 1.0.1 glasswormvsix openvsx all
quickrunn.auto-run-command-quick 1.6.2 glasswormvsix openvsx all
outsidestormcommand.monochromator-theme * glasswormapr openvsx all
keyacrosslaud.auto-loop-for-antigravity * glasswormapr openvsx all
krundoven.ironplc-fast-hub * glasswormapr openvsx all
boulderzitunnel.vscode-buddies * glasswormapr openvsx mac,win
cubedivervolt.html-code-validate * glasswormapr openvsx all
winnerdomain17.version-lens-tool * glasswormapr openvsx all
specstudio.code-wakatime-activity-tracker * glasswormzig openvsx mac,win
floktokbok.autoimport * glasswormzig any all
microsoftvs.microsoftvs * glasswormoct any win
cosmic-themes.theme-cosmic-nebula * glasswormoct any all
quartz.quartz-markdown-editor 0.3.0 glasswormuni any all
exargd.vsblack 0.0.1 glasswasm openvsx all
noellee-doc.flint-debug 0.1.1 glasswasm openvsx all
nrwl.angular-console 18.95.0 nxconsole any all"
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
# Linux caps one environment string at 128 KiB, and the list of bad versions comes near that: each
# awk gets it in four pieces of 1,000 lines (tools/gen.sh refuses a list of more than 4,000).
BAD_NPM_P1=$(printf '%s\n' "$BAD_NPM" | sed -n '1,1000p'); BAD_NPM_P2=$(printf '%s\n' "$BAD_NPM" | sed -n '1001,2000p')
BAD_NPM_P3=$(printf '%s\n' "$BAD_NPM" | sed -n '2001,3000p'); BAD_NPM_P4=$(printf '%s\n' "$BAD_NPM" | sed -n '3001,4000p')
npm_awk() { BAD_NPM_P1=$BAD_NPM_P1 BAD_NPM_P2=$BAD_NPM_P2 BAD_NPM_P3=$BAD_NPM_P3 BAD_NPM_P4=$BAD_NPM_P4 awk "$@"; }
npm_hits() {
  npm_awk '
    BEGIN {
      for (pc = 1; pc <= 4; pc++) { n = split(ENVIRON["BAD_NPM_P" pc], L, "\n")
        for (i = 1; i <= n; i++) { if (split(L[i], f, " ") < 3) continue
          if (f[2] == "*") any[f[1]] = f[3]; else bad[f[1] "@" f[2]] = f[3] } }
    }
    function hit(nm, v,   k, t) {
      if (v !~ /^[0-9A-Za-z.+_-]+$/) v = "?"
      if (v ~ /^0\.0\.1-security(\.[0-9]+)?$/) return   # the empty placeholder npm puts in place of a removed package: 0.0.1-security, or 0.0.1-security.0 for a few names
      k = nm "@" v; t = ""
      if (k in bad) t = bad[k]; else if (nm in any) t = any[nm]
      if (t != "" && !((FILENAME "|" k) in seen)) { seen[FILENAME "|" k] = 1; fn = FILENAME; gsub(/[[:cntrl:]]/, "?", fn); print fn "\t" nm " " v "\t" t }
    }
    FNR == 1 { over = 0; depth = 0; pend = ""; yn = "" }
    FILENAME ~ /pnpm-lock\.yaml$/ && /^[^ #]/ { over = ($0 ~ /^overrides:/) }
    FILENAME ~ /bun\.lock$/ {
      if (over) { o = $0; depth += gsub(/\{/, "", o); o = $0; depth -= gsub(/\}/, "", o); if (depth <= 0) over = 0; next }
      if ($0 ~ /"overrides"[[:space:]]*:[[:space:]]*\{/) { over = 1; o = $0; depth = gsub(/\{/, "", o); o = $0; depth -= gsub(/\}/, "", o); if (depth <= 0) over = 0; next }
    }
    over { next }
    # A yarn.lock entry starts with what asked for it (axios@1.14.1, axios@1.14.2:), not what was
    # installed: a resolutions pin can move it to another version. That line only names the entry; its
    # version comes from its resolved URL or version line (yarn 1), or its resolution line (yarn 2 on).
    FILENAME ~ /yarn\.lock$/ && /^[^ \t\r#]/ {
      k = $0; sub(/[ \t\r]*$/, "", k); sub(/:$/, "", k); sub(/,.*$/, "", k); gsub(/"/, "", k)
      if (index(k, "@npm:")) k = substr(k, index(k, "@npm:") + 5)
      yn = ""; if (match(k, /^@?[^@]+/)) yn = substr(k, 1, RLENGTH)
      if (yn !~ /^(@[A-Za-z0-9._~-]+\/)?[A-Za-z0-9._~-]+$/) yn = ""
      next
    }
    FILENAME ~ /yarn\.lock$/ && yn != "" && match($0, /^[ \t]+version "[^"]+"/) {
      v = substr($0, RSTART, RLENGTH); sub(/^[ \t]+version "/, "", v); sub(/"$/, "", v); hit(yn, v); yn = ""
    }
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
# One awk for up to 100 lockfiles at a time: each awk loads the whole list of bad versions first,
# which once per lockfile costs a home with hundreds of projects seconds. awk stops at a file it can't
# open (one gone or locked since it was listed), so a batch that fails is read again a file at a time,
# and only that file is lost, as before.
if [ "$N_LOCK" -gt 0 ]; then
  _lf=(); while IFS= read -r f; do [ -n "$f" ] && [ -r "$f" ] && _lf+=("$f"); done <<EOF
$LOCKFILES
EOF
  NPM_ROWS=$(_i=0; while [ "$_i" -lt "${#_lf[@]}" ]; do
    _b=$(npm_hits "${_lf[@]:$_i:100}") || _b=$(for _f in "${_lf[@]:$_i:100}"; do npm_hits "$_f"; done)
    [ -n "$_b" ] && printf '%s\n' "$_b"; _i=$((_i + 100))
  done)
fi
# Global installs: npm's own folders, the version managers (nvm, volta, fnm, asdf, mise, nodenv),
# pnpm's and bun's global folders, and npx's cache. One pass: the package.json of every package
# under each root (the package itself, or a dependency of a globally installed tool) is listed by
# its folder, and one awk reads the ones whose folder names a bad package.
# A root that is not a folder can still be there, behind a folder on its way that can't be read or
# entered: that folder is printed as "?<TAB>folder" and counts as not read (NPM_GUNREAD).
npm_blocked() { # path: prints the nearest folder on its way that exists, when that can't be read
  _bd=$1
  while :; do
    case "$_bd" in */*) _bd=${_bd%/*} ;; *) return 1 ;; esac
    [ -n "$_bd" ] || return 1
    if [ -d "$_bd" ]; then { [ -r "$_bd" ] && [ -x "$_bd" ]; } && return 1; printf '?\t%s\n' "$_bd"; return 0; fi
  done
}
npm_root() { if [ -d "$1" ]; then printf '%s\n' "$1"; else npm_blocked "$1"; fi; }
npm_roots_in() { # folder holding one folder per version or package, where node_modules sits in each
  if [ ! -d "$1" ]; then npm_blocked "$1/x"; return; fi
  if [ ! -r "$1" ] || [ ! -x "$1" ]; then printf '?\t%s\n' "$1"; return; fi
  for _rv in "$1"/*/; do if [ -d "$_rv" ]; then npm_root "${_rv%/}/$2"; fi; done
}
_npm_roots=$(
  for r in /opt/homebrew/lib/node_modules /usr/local/lib/node_modules /usr/lib/node_modules "$H/.npm-global/lib/node_modules" \
           "$H/.bun/install/global/node_modules"; do
    npm_root "$r"
  done
  npm_roots_in "$H/.nvm/versions/node" lib/node_modules; npm_roots_in "$H/.volta/tools/image/node" lib/node_modules
  npm_roots_in "$H/.volta/tools/image/packages" lib/node_modules; npm_roots_in "$H/.local/share/fnm/node-versions" installation/lib/node_modules
  npm_roots_in "$H/Library/Application Support/fnm/node-versions" installation/lib/node_modules
  npm_roots_in "$H/.asdf/installs/nodejs" lib/node_modules; npm_roots_in "$H/.local/share/mise/installs/node" lib/node_modules
  npm_roots_in "$H/.nodenv/versions" lib/node_modules; npm_roots_in "$H/Library/pnpm/global" node_modules
  npm_roots_in "$H/.local/share/pnpm/global" node_modules; npm_roots_in "$H/.npm/_npx" node_modules
  if [ "$WIN" -eq 1 ]; then
    # The Windows places gird-check.ps1 reads: npm's own folder, nvm-windows (NVM_HOME), fnm (FNM_DIR), Volta, mise, pnpm and npx's cache.
    _nvm=$(winpath "${NVM_HOME:-}"); _nvm=${_nvm%/}; [ -n "$_nvm" ] || _nvm="$WAPP/nvm"
    _fnm=$(winpath "${FNM_DIR:-}"); _fnm=${_fnm%/}; [ -n "$_fnm" ] || _fnm="$WAPP/fnm"
    npm_root "$WAPP/npm/node_modules"; npm_roots_in "$_nvm" node_modules; npm_roots_in "$_fnm/node-versions" installation/node_modules
    npm_roots_in "$WLAPP/Volta/tools/image/node" node_modules; npm_roots_in "$WLAPP/Volta/tools/image/packages" node_modules
    npm_roots_in "$WLAPP/Volta/tools/image/packages" lib/node_modules; npm_roots_in "$WLAPP/mise/installs/node" node_modules
    npm_roots_in "$WLAPP/pnpm/global" node_modules; npm_roots_in "$WLAPP/npm-cache/_npx" node_modules
  fi
  # pnpm's own folder, where its setup points PNPM_HOME.
  _ph=$(winpath "${PNPM_HOME:-}"); _ph=${_ph%/}
  if [ -n "$_ph" ]; then npm_roots_in "$_ph/global" node_modules; fi
)
NPM_ROOTS=$(printf '%s\n' "$_npm_roots" | grep -v "^?$TAB" | grep -v '^$')
# Each root is read as a node_modules folder: the package.json of every package in it, and of every
# dependency in the node_modules folders nested in theirs, 16 levels deep, so a tool's dependency's own
# dependency is read too. A store in a dot folder beside them (pnpm's .pnpm/<id>/node_modules, where a
# pnpm global folder keeps every package) is read as well, its real folders only: the links in a store,
# and at the root beside it, lead to those. A linked package is otherwise read but not entered, except
# at a root without a store (npm link). Each folder that can't be read or entered, deeper than 16
# levels, or a bad package's package.json that can't be read, is printed as "?<TAB>path".
npm_global_pkg() { # package folder, kind of the folder it is in: R root, P root with a store, S store, N nested
  if [ -L "$1" ]; then case "$2" in P|S) return ;; esac; fi
  if [ -d "$1" ] && [ ! -x "$1" ]; then printf '?\t%s\n' "$1"; return; fi
  # A regular file; in an account run anything there, so fleet_filter can count what it won't read.
  if [ -f "$1/package.json" ] || { [ "$ACCTRUN" -eq 1 ] && { [ -e "$1/package.json" ] || [ -L "$1/package.json" ]; }; }; then printf '%s\n' "$1/package.json"; fi
  if { [ ! -L "$1" ] || [ "$2" = R ]; } && [ -d "$1/node_modules" ] && [ ! -L "$1/node_modules" ]; then _gnq+=("$1/node_modules"); _gnm+=(N); fi
}
npm_global_walk() {
  printf '%s\n' "$NPM_ROOTS" | while IFS= read -r r; do
    [ -n "$r" ] || continue
    _gq=(); _gm=()
    for _s in "$r"/.[!.]*; do
      [ -d "$_s" ] && [ ! -L "$_s" ] && [ "${_s##*/}" != .bin ] || continue
      if [ ! -r "$_s" ] || [ ! -x "$_s" ]; then printf '?\t%s\n' "$_s"; continue; fi
      for _sn in "$_s"/*/node_modules; do if [ -d "$_sn" ] && [ ! -L "$_sn" ]; then _gq+=("$_sn"); _gm+=(S); fi; done
    done
    if [ "${#_gq[@]}" -gt 0 ]; then _gq=("$r" "${_gq[@]}"); _gm=(P "${_gm[@]}"); else _gq=("$r"); _gm=(R); fi
    _gl=0
    while [ "${#_gq[@]}" -gt 0 ]; do
      _gnq=(); _gnm=(); _gi=0
      while [ "$_gi" -lt "${#_gq[@]}" ]; do
        _m=${_gq[$_gi]}; _md=${_gm[$_gi]}; _gi=$((_gi + 1))
        if [ "$_gl" -ge 16 ] || [ ! -r "$_m" ] || [ ! -x "$_m" ]; then printf '?\t%s\n' "$_m"; continue; fi
        for _e in "$_m"/*; do
          case "${_e##*/}" in
            @*) [ -d "$_e" ] || continue
                if [ -L "$_e" ]; then case "$_md" in P|S) continue ;; esac; fi
                if [ ! -r "$_e" ] || [ ! -x "$_e" ]; then printf '?\t%s\n' "$_e"; continue; fi
                for _e2 in "$_e"/*; do if [ -e "$_e2" ] || [ -L "$_e2" ]; then npm_global_pkg "$_e2" "$_md"; fi; done ;;
            *) if [ -e "$_e" ] || [ -L "$_e" ]; then npm_global_pkg "$_e" "$_md"; fi ;;
          esac
        done
      done
      _gq=(${_gnq[@]+"${_gnq[@]}"}); _gm=(${_gnm[@]+"${_gnm[@]}"}); _gl=$((_gl + 1))
    done
  done
}
npm_global_named() { # package.json paths on stdin; the ones whose folder names a package on the list, and the "?" lines
  npm_awk '
    BEGIN { for (pc = 1; pc <= 4; pc++) { n = split(ENVIRON["BAD_NPM_P" pc], L, "\n"); for (i = 1; i <= n; i++) if (split(L[i], f, " ") >= 3) names[f[1]] = 1 } }
    /^\?\t/ { print; next }
    { d = $0; sub(/\/package\.json$/, "", d); k = split(d, c, "/"); nm = c[k]; if (k > 1 && c[k - 1] ~ /^@/) nm = c[k - 1] "/" nm
      if (nm in names) print }'
}
npm_global_hits() { # package.json paths on stdin; prints folder|name version|tag for each bad package
  npm_awk '
    BEGIN {
      for (pc = 1; pc <= 4; pc++) { n = split(ENVIRON["BAD_NPM_P" pc], L, "\n")
        for (i = 1; i <= n; i++) { if (split(L[i], f, " ") < 3) continue
          names[f[1]] = 1; if (f[2] == "*") any[f[1]] = f[3]; else bad[f[1] "@" f[2]] = f[3] } }
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
_gw=$(npm_global_walk | npm_global_named)
_g=$(printf '%s\n' "$_gw" | grep -v "^?$TAB" | grep -v '^$' | fleet_filter | npm_global_hits)
[ -n "$_g" ] && NPM_ROWS="$NPM_ROWS
$_g"
# What of the global installs could not be read: each folder (or bad package's package.json) once. It
# counts in NPM_UNREAD, which npm's cache adds to below, so the check is never called clean over it.
NPM_GUNREAD=$( { printf '%s\n' "$_npm_roots" "$_gw" | grep "^?$TAB"
  # An account run leaves an unreadable file to fleet_filter, which counts it already.
  [ "$ACCTRUN" -eq 1 ] || printf '%s\n' "$_gw" | grep -v "^?$TAB" | while IFS= read -r _f; do [ -n "$_f" ] && [ -e "$_f" ] && [ ! -r "$_f" ] && printf '?\t%s\n' "$_f"; done
  } | sort -u | grep -c .)
NPM_UNREAD=$((NPM_UNREAD + NPM_GUNREAD))
# --- 1. Coding agents: settings and versions -------------------------------------
# Agents set to run commands without asking (data/auto-approve.tsv), matched by aa_hit (section 2).
AA_ROWS=""; AA_TRIED=""
# A path with one * folder: that file in every folder there, as VS Code keeps a settings file for each
# profile in User/profiles/<id>/.
aa_glob() { for _ag in "${1%%/\**}"/*/"${1#*/\*/}"; do [ -e "$_ag" ] && printf '%s\n' "$_ag"; done; }
while IFS='|' read -r _aa _ao _ap _as _apat; do
  [ -n "$_aa" ] || continue
  case "$_ao" in all|"$_os") ;; *) continue ;; esac
  case "$_ap" in
    # The home folder is not a project: its own file there is the user's, such as ~/.codex/config.toml.
    "{PROJECT}/"*) _rel=${_ap#"{PROJECT}/"}; _al=$(printf '%s\n' "$AA_FILES" | while IFS= read -r _f; do case "$_f" in ("$H/$_rel") ;; (*/"$_rel") printf '%s\n' "$_f" ;; esac; done) ;;
    */\*/*) _al=$(aa_glob "$_ap") ;;
    *) _al=$_ap ;;
  esac
  AA_TRIED="$AA_TRIED$_al
"
  while IFS= read -r _f; do
    [ -n "$_f" ] && fleet_ok "$_f" && [ -f "$_f" ] && ! too_big "$_f" && aa_hit "$_f" "$_apat" && AA_ROWS="$AA_ROWS$(rowsafe "$_f")$TAB$_aa$TAB$_as
"
  done <<EOF
$_al
EOF
done <<EOF
$AA_TABLE
EOF
# One of these files that is there but can't be read, or is too big to, was not checked: section 2 names
# it with the other settings files it could not read, so the summary doesn't read clean over it.
_aau=$(printf '%s\n' "$AA_TRIED" | unread_files big)
if [ -n "$_aau" ]; then SEC2_UNREAD=$(printf '%s\n%s\n' "$SEC2_UNREAD" "$_aau" | awk 'length && !s[$0]++'); N_SEC2_UNREAD=$(count_lines "$SEC2_UNREAD"); fi
# One row per file and agent: file<TAB>agent<TAB>settings. VS Code's settings file can hold two agents'.
AA_LIST=$(printf '%s' "$AA_ROWS" | awk -F "$TAB" '{ k = $1 FS $2 } !(k in o) { o[k] = ++n; f[n] = $1; ag[n] = $2; st[n] = $3; next } { st[o[k]] = st[o[k]] ", " $3 }
  END { for (i = 1; i <= n; i++) print f[i] "\t" ag[i] "\t" st[i] }')
N_YOLO=$(count_lines "$AA_LIST")
# Row 01 counts agents: one can be set so in several files.
N_YOLO_AG=$(printf '%s\n' "$AA_LIST" | cut -f2 | sort -u | grep -c .)
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
    plist) _vs=""; fleet_ok "$_ow" && [ -f "$_ow" ] && _vs=$({ tr '\n\r\t' '   ' < "$_ow"; } 2>/dev/null | sed -n 's#.*<key>CFBundleShortVersionString</key> *<string>\([^<]*\)</string>.*#\1#p') ;;
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
# One row per tool: name<TAB>versions<TAB>fixed<TAB>holes. A tool's lines can name several advisories:
# the row says to update to the highest fixed version among those its versions fall under, and holes
# holds each of their holes with its advisory, as hole|advisory|hole|advisory (gen.sh refuses a | in
# either). When that version is in the range of another of the tool's lines, the row takes that line's
# fix, until no line covers it: the version it names has no published fix of its own. A line's range
# and fix are its fields counted from the end, which a | in a path cannot shift.
OLD_LIST=$(printf '%s' "$OLD_ROWS" | OT="$OUT_TABLE" OO="$_os" awk -F "$TAB" '
  function newer(a, b,   x, y, p, q, k, i) { p = split(a, x, "."); q = split(b, y, "."); k = p > q ? p : q
    for (i = 1; i <= k; i++) if (x[i] + 0 != y[i] + 0) return ((x[i] + 0) > (y[i] + 0))
    return 0 }
  !($1 in o) { o[$1] = ++n; id[n] = $1; r[n] = $2; v[n] = $3; fx[n] = $4; h[n] = $5 "|" $6; seen[$1 "|" $3] = 1; hs[$1 "|" $5 "|" $6] = 1; next }
  { i = o[$1]
    if (!(($1 "|" $3) in seen)) { seen[$1 "|" $3] = 1; v[i] = v[i] ", " $3 }
    if (newer($4, fx[i])) fx[i] = $4
    if (!(($1 "|" $5 "|" $6) in hs)) { hs[$1 "|" $5 "|" $6] = 1; h[i] = h[i] "|" $5 "|" $6 } }
  END { nt = split(ENVIRON["OT"], t, "\n")
    for (i = 1; i <= n; i++) {
      do { ch = 0
        for (j = 1; j <= nt; j++) {
          m = split(t[j], c, "|")
          if (m < 9 || c[1] != id[i] || (c[3] != "all" && c[3] != ENVIRON["OO"])) continue
          if ((c[m - 3] == "-" || !newer(c[m - 3], fx[i])) && newer(c[m - 2], fx[i])) { fx[i] = c[m - 2]; ch = 1 }
        }
      } while (ch)
      print r[i] "\t" v[i] "\t" fx[i] "\t" h[i]
    } }')
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
# the Marketplace; Cursor, Windsurf, VSCodium, Kiro and Antigravity install from Open VSX. Windsurf
# became Devin Desktop on 2 June 2026, which keeps the extensions in ~/.devin/extensions and only reads
# the old folder (its FAQ: only the name changed), so both are read. Antigravity IDE keeps them in
# ~/.antigravity-ide/extensions (its product.json: data folder .antigravity-ide, Open VSX's gallery),
# and the Antigravity before it in ~/.antigravity/extensions. VS Code Insiders keeps them in
# ~/.vscode-insiders/extensions, and the remote servers these editors run over SSH, WSL or in a container
# in their own folders (VS Code's docs and source: ~/.vscode-server and ~/.vscode-server-insiders; the
# serverDataFolderName of each product.json: ~/.cursor-server, ~/.windsurf-server, and ~/.devin-server
# since the rename), installing from the same registry as the editor. Positron, which GlassWorm's
# dropper targets too (Socket's post of 18 March 2026, Aikido's of April), keeps them in
# ~/.positron/extensions and its server's in ~/.positron-server/extensions, from Posit's mirror of
# Open VSX (its product.json). A line whose bad build was only ever on Open VSX (registry openvsx)
# is not looked for in VS Code's own folders, where the same id is the Marketplace's own build. A
# folder that can't be read leaves the check not done in full (EXT_UNREAD), never clean, and so does
# an editor's own folder (~/.windsurf) that can't be opened, which hides its extensions folder.
ext_roots() { printf '%s\n' "$H/.vscode/extensions" "$H/.cursor/extensions" "$H/.windsurf/extensions" "$H/.devin/extensions" "$H/.vscode-oss/extensions" "$H/.kiro/extensions" "$H/.antigravity-ide/extensions" "$H/.antigravity/extensions" \
  "$H/.vscode-insiders/extensions" "$H/.vscode-server/extensions" "$H/.vscode-server-insiders/extensions" "$H/.cursor-server/extensions" "$H/.windsurf-server/extensions" "$H/.devin-server/extensions" \
  "$H/.positron/extensions" "$H/.positron-server/extensions"; }
EXT_UNREAD=0
while IFS= read -r r; do
  _xp=${r%/*}
  if [ -d "$r" ] && { [ ! -r "$r" ] || [ ! -x "$r" ]; }; then EXT_UNREAD=$((EXT_UNREAD + 1))
  elif [ ! -d "$r" ] && [ -d "$_xp" ]; then
    # Its editor's folder can't be listed, or can be listed (a glob reads it) but not entered.
    if [ ! -r "$_xp" ]; then EXT_UNREAD=$((EXT_UNREAD + 1))
    elif [ ! -x "$_xp" ]; then for _xe in "$_xp"/extension[s]; do [ "$_xe" = "$_xp/extension[s]" ] || EXT_UNREAD=$((EXT_UNREAD + 1)); done; fi
  fi
done <<EOF
$(ext_roots)
EOF
_ext_found=$(ext_roots | while IFS= read -r r; do
    [ -d "$r" ] || continue
    case "$r" in ("$H/.vscode/extensions"|"$H/.vscode-insiders/extensions"|"$H/.vscode-server/extensions"|"$H/.vscode-server-insiders/extensions") _rg=marketplace ;; (*) _rg=openvsx ;; esac
    for d in "$r"/*; do [ -d "$d" ] && printf '%s\t%s\n' "$_rg" "$d"; done
  done | BAD_EXT_LIST=$BAD_EXT awk -F '\t' '
  BEGIN { n = split(ENVIRON["BAD_EXT_LIST"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], f, " "); id[i] = tolower(f[1]); sp[i] = f[1]; v[i] = f[2]; t[i] = f[3]; rg[i] = f[4]; os[i] = f[5] } }
  { reg = $1; d = substr($0, length($1) + 2); gsub(/[[:cntrl:]]/, "?", d); b = d; sub(/.*\//, "", b); lb = tolower(b)
    # Split as VS Code splits a folder name (its ExtensionKey): the id is the longest start that leaves
    # a version of three numbers, alone or before a -, so oorzc.ssh-tools-2-0.1.0 is oorzc.ssh-tools-2.
    fid = ""
    for (p = length(lb); p > 1 && fid == ""; p--) {
      if (substr(lb, p, 1) != "-" || substr(lb, 1, p - 1) !~ /^[^.]+\../) continue
      r = substr(lb, p + 1)
      if (!match(r, /^[0-9]+\.[0-9]+\.[0-9]+/)) continue
      rest = substr(r, RLENGTH + 1)
      if (rest == "" || rest ~ /^-./) { fid = substr(lb, 1, p - 1); ver = substr(r, 1, RLENGTH) }
    }
    if (fid == "") next
    for (i = 1; i <= n; i++) {
      if (rg[i] != "any" && rg[i] != reg) continue
      if (fid != id[i]) continue
      if (v[i] == "*" || v[i] == ver) { print d "\t" sp[i] " " ver "\t" t[i] "\t" os[i]; break }
    } }')
# Where its malware could run (the os column: all, one OS, or two such as mac,win), an extension that
# shipped malware means a compromised machine (EXT_ROWS: folder, id and version, incident). Elsewhere it
# is a malicious extension to remove (EXT_UPD, with the os), with no part in EXT_HIT, the score or the
# link's ex.
EXT_ROWS=$(printf '%s\n' "$_ext_found" | awk -F '\t' -v o="$_os" 'NF >= 4 && ($4 == "all" || index("," $4 ",", "," o ",")) { print $1 "\t" $2 "\t" $3 }')
EXT_UPD=$(printf '%s\n' "$_ext_found" | awk -F '\t' -v o="$_os" 'NF >= 4 && $4 != "all" && !index("," $4 ",", "," o ",")')
# Incidents that leave the machine itself uncompromised only need the version updated; the rest mean a compromised machine.
NPM_TAGS=$(printf '%s\n' "$NPM_ROWS" | cut -f3 | grep -v '^$' | sort -u)
for _t in $NPM_TAGS; do
  if [ "$(incident_level "$_t")" = act ]; then NPM_HIT=1; else NPM_UPD=1; fi
done
# A lockfile records what some machine resolved, not what ran here. An act-level hit was installed
# when npm's cache or a global install has it, or the place that lockfile's entry installs to holds
# that version (lock_installed). A hit in a lockfile alone (NPM_LOCKPROJ lists their folders) leaves
# the headline and the fix depending on whether that project was installed; the score and the link
# stay as they are.
pkg_version() { # package.json: its first "version"
  awk 'match($0, /"version"[[:space:]]*:[[:space:]]*"[^"]+"/) { v = substr($0, RSTART, RLENGTH); sub(/^"version"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"$/, "", v); print v; exit }' "$1" 2>/dev/null
}
pkg_at() { [ -f "$1/package.json" ] && [ "$(pkg_version "$1/package.json")" = "$2" ]; } # folder version
# The folders, relative to the lockfile, that npm's lockfile (its packages section, lockfile 2 and 3)
# or bun's names for an entry: node_modules/a/node_modules/b, or a workspace's packages/w/node_modules/b.
# bun's key is that path without the node_modules (a/b), and its value starts with the name@version.
lock_paths() { # lockfile name version
  awk -v N="$2" -v V="$3" '
    FILENAME ~ /bun\.lock$/ {
      if (!match($0, /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[^"]*"/)) next
      s = substr($0, RSTART, RLENGTH); k = s; sub(/^[[:space:]]*"/, "", k); sub(/".*$/, "", k)
      v = s; sub(/^.*\[[[:space:]]*"/, "", v); sub(/"$/, "", v)
      if (v != N "@" V) next
      n = split(k, c, "/"); p = ""
      for (i = 1; i <= n; i++) { s = c[i]; if (s ~ /^@/ && i < n) { i++; s = s "/" c[i] }; p = p (p == "" ? "" : "/") "node_modules/" s }
      print p; next
    }
    match($0, /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*\{/) {
      k = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*"/, "", k); sub(/".*$/, "", k)
      pend = ""; ok = 0
      if (k ~ /(^|\/)node_modules\//) { pend = k; nm = k; sub(/^.*node_modules\//, "", nm); ok = (nm == N) }
      next
    }
    pend != "" && match($0, /"name"[[:space:]]*:[[:space:]]*"[^"]*"/) {
      x = substr($0, RSTART, RLENGTH); sub(/^"name"[[:space:]]*:[[:space:]]*"/, "", x); sub(/"$/, "", x); if (x == N) ok = 1
    }
    pend != "" && match($0, /"version"[[:space:]]*:[[:space:]]*"[^"]*"/) {
      x = substr($0, RSTART, RLENGTH); sub(/^"version"[[:space:]]*:[[:space:]]*"/, "", x); sub(/"$/, "", x)
      if (ok && x == V) print pend
      pend = ""
    }' "$1" 2>/dev/null
}
# node_modules folders nested in a project's, 16 levels deep: npm, yarn 1, yarn's node-modules linker,
# bun and pnpm's hoisted layout all put a package in one. A linked package is followed only at the top,
# where workspaces are linked, and a linked node_modules never.
lock_nm_walk() { # project folder, name, version
  _wq=("$1/node_modules"); _wl=0
  while [ "${#_wq[@]}" -gt 0 ] && [ "$_wl" -lt 16 ]; do
    _wn=()
    for _wm in "${_wq[@]}"; do
      pkg_at "$_wm/$2" "$3" && return 0
      for _wc in "$_wm"/*/node_modules "$_wm"/@*/*/node_modules; do
        [ -d "$_wc" ] && [ ! -L "$_wc" ] || continue
        [ "$_wl" -eq 0 ] || [ ! -L "${_wc%/node_modules}" ] || continue
        _wn+=("$_wc")
      done
    done
    _wq=(${_wn[@]+"${_wn[@]}"}); _wl=$((_wl + 1))
  done
  return 1
}
# A cache zip of yarn 2 and later at that version: <name>-npm-<version>-<10 hex>-<checksum or cache
# key>.zip, a scoped name written @scope-name (yarn's slugifyLocator and getVersionFilename).
yarn_zip() { # folder, name as the file spells it, version
  for _z in "$1/$2-npm-$3-"*.zip; do
    [ -f "$_z" ] || continue
    _zt=${_z##*/}; _zt=${_zt#"$2-npm-$3-"}; _zt=${_zt%.zip}
    case "$_zt" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-?*) ;; *) continue ;; esac
    case "${_zt#??????????-}" in *[!0-9a-z]*) continue ;; esac
    return 0
  done
  return 1
}
# The shared cache yarn 4 uses unless a project turns it off: <global folder>/cache, the global folder
# being %LOCALAPPDATA%/Yarn/Berry on Windows, $XDG_DATA_HOME/yarn/berry when that is set, or
# ~/.yarn/berry (yarn's getDefaultGlobalFolder and enableGlobalCache).
YARN_GCACHE="$H/.yarn/berry/cache"
case "${XDG_DATA_HOME:-}" in /*) YARN_GCACHE="${XDG_DATA_HOME%/}/yarn/berry/cache" ;; esac
[ "$WIN" -eq 1 ] && YARN_GCACHE="$WLAPP/Yarn/Berry/cache"
# The offline mirror a .yarnrc names for yarn 1, resolved from that file's folder, as yarn resolves it.
yarn_mirror() { # .yarnrc
  fleet_ok "$1" && [ -f "$1" ] || return 1
  _ym=$(awk 'match($0, /^[ \t]*"?yarn-offline-mirror"?[ \t]+/) { v = substr($0, RLENGTH + 1); sub(/[ \t\r]+$/, "", v); gsub(/^"|"$/, "", v); print v; exit }' "$1" 2>/dev/null)
  [ "$WIN" -eq 1 ] && case "$_ym" in [A-Za-z]:[\\/]*) _ym=$(winpath "$_ym") ;; esac
  case "$_ym" in ''|false) return 1 ;; /*) ;; *) _ym="${1%/*}/$_ym" ;; esac
  printf '%s' "$_ym"
}
# Whether a lockfile's entry is installed where that lockfile puts it, at its version: the folder npm's
# or bun's lockfile names, a node_modules folder nested in the project's, pnpm's node_modules/.pnpm,
# yarn 2 and later's cache zip (the project's .yarn/cache or the shared one), or yarn 1's offline mirror
# when the project's .yarnrc or yours names one. Its tarball there is <name>-<version>.tgz, a scoped name
# written @scope-name (yarn 1's tarball-fetcher).
lock_installed() { # lockfile name version
  _ld=${1%/*}
  [ "$3" != "?" ] || return 1
  case "$1" in
    */package-lock.json|*/npm-shrinkwrap.json|*/bun.lock)
      while IFS= read -r _lp; do [ -n "$_lp" ] && pkg_at "$_ld/$_lp" "$3" && return 0; done <<EOF
$(lock_paths "$1" "$2" "$3")
EOF
      ;;
  esac
  lock_nm_walk "$_ld" "$2" "$3" && return 0
  case "$1" in
    */pnpm-lock.yaml)
      for _lp in "$_ld"/node_modules/.pnpm/*/node_modules/"$2"; do pkg_at "$_lp" "$3" && return 0; done ;;
    */yarn.lock)
      _ly=$2; case "$2" in @*/*) _ly="${2%%/*}-${2#*/}" ;; esac
      yarn_zip "$_ld/.yarn/cache" "$_ly" "$3" && return 0
      yarn_zip "$YARN_GCACHE" "$_ly" "$3" && return 0
      for _yr in "$_ld/.yarnrc" "$H/.yarnrc"; do
        _ym=$(yarn_mirror "$_yr") || continue
        [ -f "$_ym/$_ly-$3.tgz" ] && return 0
      done ;;
  esac
  return 1
}
# NPM_INST_TAGS: the act-level incidents with a hit found installed, whose own fixes are worded as fact.
NPM_INST=0; NPM_LOCKPROJ=""; NPM_INST_TAGS=" "
while IFS="$TAB" read -r _f _p _t; do
  [ -n "$_t" ] && [ "$(incident_level "$_t")" = act ] || continue
  case "$_f" in
    */package-lock.json|*/npm-shrinkwrap.json|*/pnpm-lock.yaml|*/yarn.lock|*/bun.lock)
      if lock_installed "$_f" "${_p% *}" "${_p##* }"; then NPM_INST=1; NPM_INST_TAGS="$NPM_INST_TAGS$_t "
      else NPM_LOCKPROJ="$NPM_LOCKPROJ${_f%/*}
"; fi ;;
    *) NPM_INST=1; NPM_INST_TAGS="$NPM_INST_TAGS$_t " ;;
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
# A file an npm incident's line and an editor extension incident's line both name (the AntV wave's
# packages and Nx Console 18.95.0 leave the same kitty-monitor files) is listed once, by the incident
# IND_OWNER names: the extension's when it was found and none of the npm incident's packages were.
EXT_FOUND=" $(printf '%s\n' "$EXT_ROWS" | cut -f3 | sort -u | tr '\n' ' ')"
IND_OWNER=$(printf '%s\n' "$IND_TABLE" | awk -F '|' -v e="$EXT_INCS" -v n="$NPM_INCS" -v f="$EXT_FOUND" -v t=" $(printf '%s ' $NPM_TAGS)" -v o="$_os" '
  $3 == "startup" && ($2 == "all" || $2 == o) && $5 != "" {
    if (index(e, " " $1 " ") && !index(n, " " $1 " ")) { if (!($5 in xa)) xa[$5] = $1; if (index(f, " " $1 " ") && !($5 in xf)) xf[$5] = $1 }
    else { if (!($5 in m)) m[$5] = $1; if (index(t, " " $1 " ")) nf[$5] = 1 }
  }
  END { for (p in m) if (p in xa) print p "|" ((p in xf) && !(p in nf) ? xf[p] : m[p]) }')
WIPER=""; PERSIST=""; EXT_PERSIST=""; EXT_PERSIST_TAGS=""; IND_HITS=""
while IFS='|' read -r _ii _io _ik _iown _ip _in; do
  case "$_ik" in wiper|startup) ;; *) continue ;; esac
  # A Python incident's startup file is shown in its row (PY_START).
  [ "$_ik" = startup ] && case " $PY_INCIDENTS " in *" $_ii "*) continue ;; esac
  case "$_io" in all|"$_os") ;; *) continue ;; esac
  # Shared places are root's, except a marker that must be this person's own (checked just below).
  # A link there could point at any account's file, so an account run never counts one.
  if [ "$ACCTRUN" -eq 1 ]; then case "$_ip" in "$H"/*) ;; *) [ "$_iown" = yes ] && [ ! -L "$_ip" ] || continue ;; esac; fi
  [ -n "$_ip" ] && [ -e "$_ip" ] || continue
  # A marker that must be this person's own counts only under its one name: in a shared folder, a link,
  # symbolic or hard, could put another person's file under it.
  if [ "$_iown" = yes ]; then
    [ -O "$_ip" ] || continue
    case "$_ip" in "$H"/*) ;; *) { [ ! -L "$_ip" ] && [ -n "$(find "$_ip" -prune -links 1 -print 2>/dev/null)" ]; } || continue
      # As for the temp markers above: in fleet mode, a possible sign.
      if [ "$ACCTRUN" -eq 1 ]; then if [ "$_ik" = wiper ]; then FLEET_TMPWIPER=1; else FLEET_TMPMARK="$FLEET_TMPMARK $_ii"; fi; continue; fi ;; esac
  fi
  if [ "$_ik" = startup ] && [ -n "$IND_OWNER" ]; then
    _ow=$(printf '%s\n' "$IND_OWNER" | awk -F '|' -v p="$_ip" '$1 == p { print $2; exit }')
    [ -z "$_ow" ] || [ "$_ow" = "$_ii" ] || continue
  fi
  _ext=0; case "$EXT_INCS" in *" $_ii "*) case "$NPM_INCS" in *" $_ii "*) ;; *) _ext=1 ;; esac ;; esac
  # gh-token-monitor came with more than one wave, so fleet mode gets it as wiper=1, not as an incident.
  [ "$_ext" -eq 1 ] || [ "$_ik" = wiper ] || IND_HITS="$IND_HITS $_ii"
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
# The incidents of what EXT_HIT counts (EXT_ACT_TAGS), for their advice and lines, and of the extensions
# to remove (EXT_UPD_TAGS). EXT_TAGS is both: the account run sends it, so an extension to remove is
# never left out of an account's row.
EXT_ACT_TAGS=$( { printf '%s\n' "$EXT_ROWS" | cut -f3; printf '%s' "$EXT_PERSIST_TAGS"; } | grep -v '^$' | sort -u)
EXT_UPD_TAGS=$(printf '%s\n' "$EXT_UPD" | cut -f3 | grep -v '^$' | sort -u)
EXT_TAGS=$(printf '%s\n' $EXT_ACT_TAGS $EXT_UPD_TAGS | grep -v '^$' | sort -u)
ANY_MAL=0; if [ "$MAL_HIT" -eq 1 ] || [ "$EXT_HIT" -eq 1 ]; then ANY_MAL=1; fi
# MAL_SIGN: npm or extension malware found on this machine. npm malware found only in a lockfile is not
# one, so the lines that say what was found (MAL_WHAT) leave it to the npm row and the fixes.
MAL_SIGN=0; if [ "$ANY_MAL" -eq 1 ] && { [ "$MAL_LOCKONLY" -eq 0 ] || [ "$EXT_HIT" -eq 1 ]; }; then MAL_SIGN=1; fi
if [ "$MAL_HIT" -eq 1 ] && [ "$MAL_LOCKONLY" -eq 0 ] && [ "$EXT_HIT" -eq 1 ]; then MAL_WHAT="npm and editor extension malware"; MAL_SHORT="npm and editor extension"
elif [ "$EXT_HIT" -eq 1 ]; then MAL_WHAT="malware in an editor extension"; MAL_SHORT="editor extension"
else MAL_WHAT="npm malware"; MAL_SHORT="npm"; fi
if [ "$WIPER_HIT" -eq 1 ]; then progress x "A wiper waits for a GitHub token to be revoked: gh-token-monitor"
elif [ "$MAL_SIGN" -eq 1 ]; then progress x "Signs of $MAL_WHAT found"
elif [ "$MAL_LOCKONLY" -eq 1 ]; then progress x "npm malware listed in a lockfile"
elif [ -n "$EXT_CHECK" ]; then progress w "A startup file to check: $(short "$(printf '%s\n' "$EXT_CHECK" | head -n 1 | cut -f1)")"
elif [ -n "$EXT_UPD" ]; then progress w "An editor extension to remove: its malware could not run on this system"
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
if [ "$ALLSESS" -eq 1 ] && [ -n "${ACCT_END:-}" ]; then
  while [ -n "$SESS_PID" ] && kill -0 "$SESS_PID" 2>/dev/null && [ "$SECONDS" -lt "$ACCT_END" ]; do sleep 1; done
  if [ -n "$SESS_PID" ] && kill -0 "$SESS_PID" 2>/dev/null; then sess_stop; else sess_stop wait; fi
elif [ "$ALLSESS" -eq 1 ]; then sess_stop wait; else sess_stop; fi
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
    SESS_ZST=$(find -H "${_rs[@]}" -type f \( -name '*.zst' -o -name '*.gz' \) -print0 2>/dev/null | tr -cd '\000' | wc -c | tr -d ' ')
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
# scanned, the sessions were partly checked, or a key file, part of npm's cache, a Python environment
# or an extension folder could not be read. The headline then says what it can: no findings in the
# paths checked.
PARTIAL=0
if [ "$SCAN_FAILED" -eq 1 ] || [ "$HOME_PARTIAL" -eq 1 ] || [ "$SESS_PARTIAL" -eq 1 ] || [ "$N_KEY_UNREAD" -gt 0 ] || [ "$N_SEC2_UNREAD" -gt 0 ] || [ "$N_ALLOW_UNREAD" -gt 0 ] || [ "$NPM_UNREAD" -gt 0 ] || [ "$N_LOCK_UNREAD" -gt 0 ] || [ "$EXT_UNREAD" -gt 0 ] || [ "$PY_UNREAD" -gt 0 ]; then PARTIAL=1; fi
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
# A rotate in a section, and in a section's own fixes (its details page), also waits for what an
# act-level incident says to remove first (FIRST_HIT, named in FIRST_WHAT: SANDWORM_MODE's pre-push
# hook would send a new npm token out on the next push). The full fix list puts that fix ahead of
# every rotate instead, so it needs no wait for it.
rotate_wait() { # text
  case "$1" in "Don't revoke"*|First\ *) printf '%s' "$1"; return ;; *[Rr]otate*|*[Rr]evoke*) ;; *) printf '%s' "$1"; return ;; esac
  case "$WIPER_HIT$FIRST_HIT" in
    11) printf '%s %s' "$1" "Only once gh-token-monitor is stopped and removed, and what $FIRST_WHAT leaves is removed: What to do starts with both." ;;
    01) printf '%s %s' "$1" "Only once what $FIRST_WHAT leaves is removed: What to do starts with it." ;;
    *) wiper_wait "$1" ;;
  esac
}
todo() { # section text
  _ft=$(rotate_wait "$2")
  set -- "$1" "$(wiper_wait "$2")"
  TODO="$TODO$2
"; ISSUES=$((ISSUES + 1))
  set -- "$1" "$_ft"
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
# An incident's own fix (data/incidents.tsv), once for each incident found. An act-level one that
# starts with "First" is what the incident leaves behind that must go before any key is rotated
# (SANDWORM_MODE's git hooks, whose pre-push hook sends npm tokens out, and its MCP servers): right
# after the wiper's fix, ahead of every fix that says to rotate. Other act-level ones come right after
# the act-now fixes, then update-level ones, ahead of every other fix (the Injective SDK's: move the
# funds out of a wallet whose seed phrase may have been sent out). Two incidents can share a fix (two
# waves of one malware): it is said once.
# An act-level npm incident found only in lockfiles (adv_lockonly) reached this machine only if that
# project was installed, so its own fix is worded for that (adv_if), and comes after the fixes for
# what was found installed (lock), with the other fixes that depend on an install. A fix any incident
# found installed shares is worded as fact.
adv_lockonly() { # incident: 0 for an act-level npm incident with no hit found installed
  [ "$(incident_level "$1")" = act ] || return 1
  case "$NPM_INST_TAGS $(printf '%s ' $EXT_ACT_TAGS $PY_HITS)" in *" $1 "*) return 1 ;; esac
  case " $(printf '%s ' $NPM_TAGS)" in *" $1 "*) return 0 ;; esac
  return 1
}
adv_if() { # incident advice: that advice, for if the incident's packages were installed
  _a2=$2; _aw=${2%% *}
  case "${_aw#?}" in *[A-Z]*) ;; *) _a2="$(printf '%s' "${2:0:1}" | tr 'A-Z' 'a-z')${2:1}" ;; esac
  printf 'If you installed the %s packages section 5 lists, %s' "$(incident_name "$1")" "$_a2"
}
ADV_SAID="$TAB"
advice_todos() { # first, act, lock or update
  _seen=" "
  for _t in $NPM_TAGS $EXT_ACT_TAGS $PY_HITS; do
    case "$_seen" in *" $_t "*) continue ;; esac; _seen="$_seen$_t "
    _a=$(incident_advice "$_t"); [ -n "$_a" ] || continue
    case "$1:$(incident_level "$_t"):$_a" in first:act:First\ *|update:update:*) ;; act:act:First\ *|lock:act:First\ *) continue ;; act:act:*|lock:act:*) ;; *) continue ;; esac
    case "$ADV_SAID" in *"$TAB$_a$TAB"*) continue ;; esac
    _lo=1; for _u in $NPM_TAGS $EXT_ACT_TAGS $PY_HITS; do if [ "$(incident_advice "$_u")" = "$_a" ] && ! adv_lockonly "$_u"; then _lo=0; fi; done
    case "$1:$_lo" in act:1|lock:0) continue ;; esac
    ADV_SAID="$ADV_SAID$_a$TAB"
    if [ "$_lo" -eq 1 ]; then todo 5 "$(adv_if "$_t" "$_a")"; else todo 5 "$_a"; fi
  done
}
# With a fix that starts with "First" to follow, the wiper's fix leaves the rotating to the act-now fixes.
FIRST_HIT=0; FIRST_WHAT=""
for _t in $NPM_TAGS $EXT_ACT_TAGS $PY_HITS; do
  [ "$(incident_level "$_t")" = act ] || continue
  case "$(incident_advice "$_t")" in
    First\ *) FIRST_HIT=1; _fn="the $(incident_name "$_t")"
      case " and $FIRST_WHAT and " in *" and $_fn and "*) ;; *) FIRST_WHAT="${FIRST_WHAT:+$FIRST_WHAT and }$_fn" ;; esac ;;
  esac
done
if [ "$WIPER_HIT" -eq 1 ] && [ "$FIRST_HIT" -eq 1 ]; then todo 5 "Don't revoke any GitHub token yet. First stop and remove gh-token-monitor, as section 5 shows: it runs a destructive command when the stolen token stops working."
elif [ "$WIPER_HIT" -eq 1 ]; then todo 5 "Don't revoke any GitHub token yet. First stop and remove gh-token-monitor, as section 5 shows: it runs a destructive command when the stolen token stops working. Then rotate every key this machine could reach."; fi
advice_todos first
# The fixes for what was found, first. A compromised machine's keys are rotated from another computer,
# then the malware is removed, as GitHub's malware advisories say.
if [ "$MAL_HIT" -eq 1 ] && [ "$MAL_LOCKONLY" -eq 0 ]; then
  todo 5 "Treat this machine as compromised. From another computer, rotate every key this machine could reach, then delete the packages and files listed in section 5 and clear npm's cache with npm cache clean --force."
fi
if [ "$EXT_HIT" -eq 1 ]; then
  # Only what section 5 lists: the extensions, the incident's startup file, or both.
  if [ "$(printf '%s' "$EXT_PERSIST" | grep -c .)" -gt 1 ]; then _edo="Uninstall the extensions listed in section 5, delete the startup files listed there, and"
  elif [ -n "$EXT_PERSIST" ]; then _edo="Uninstall the extensions listed in section 5, delete the startup file listed there, and"
  else _edo="Uninstall the extensions listed in section 5 and"; fi
  todo 5 "Treat this machine as compromised. $_edo rotate every key this machine could reach."
fi
case "$PY_HITS" in *" "*) _adv="each advisory in section 5" ;; *) _adv="$PY_SHORT's advisory" ;; esac
# "Don't run Python" only when a Python environment holds the bad package, not for a temp file alone.
PY_ENV=0; for _pi in $PY_HITS; do printf '%s' "$LITE_BAD" | grep -q "^$_pi$TAB" && PY_ENV=1; done
if [ "$PY_HIT" -eq 1 ] && [ "$PY_ENV" -eq 1 ]; then todo 5 "Treat this machine as compromised. Don't run Python in the affected environments. From another computer, rotate every key the machine could reach, then follow $_adv to remove the malware."
elif [ "$PY_HIT" -eq 1 ] && [ -n "$UV_HIT" ] && [ -z "$MARKS$PY_START" ] && [ "$LOADER" -eq 0 ]; then todo 5 "Treat this machine as compromised. From another computer, rotate every key the machine could reach, then clear the packages section 5 lists from uv's cache and follow $_adv."
elif [ "$PY_HIT" -eq 1 ]; then todo 5 "Treat this machine as compromised. Stop any process started from the files listed in section 5. From another computer, rotate every key the machine could reach, then delete those files and follow $_adv."; fi
advice_todos act
# Then the fixes that depend on an install, or on a file you set up: a bad version found only in
# lockfiles (whether this machine is compromised depends on whether that project was installed here),
# a startup file to check, a leftover cook.pyc, and the own fixes of incidents found only in lockfiles.
if [ "$MAL_LOCKONLY" -eq 1 ]; then
  if [ "$N_LOCKPROJ" -eq 1 ]; then _lp="the project"; _ll="its lockfile"; else _lp="the projects"; _ll="their lockfiles"; fi
  todo 5 "If you ran an install in $_lp section 5 lists, treat this machine as compromised: from another computer, rotate every key this machine could reach, then clear npm's cache with npm cache clean --force. If not, update $_ll to a version without the malware."
fi
[ -n "$EXT_CHECK" ] && todo 5 "Open the startup file listed in section 5 and check what it starts at login. If you did not set it up yourself, treat this machine as compromised: delete it and rotate every key this machine could reach."
[ "$LITELLM_HIT" -eq 0 ] && [ -n "$LITE_PYC" ] && todo 5 "A leftover cook.pyc can come from the LiteLLM 1.107.0 malware. If litellm 1.107.0 was ever installed there, treat this machine as compromised, follow LiteLLM's advisory and rotate every key it could reach."
advice_todos lock
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
# A version to update needs its own fix unless the compromised-machine fix already deletes it (a
# lockfile-only hit's fix does not), or its incident's own fix already says to update it.
_upd_fix=0; for _t in $NPM_TAGS; do [ "$(incident_level "$_t")" = update ] || continue; case "$(incident_advice "$_t")" in *[Uu]pdate*) ;; *) _upd_fix=1 ;; esac; done
{ [ "$MAL_HIT" -eq 0 ] || [ "$MAL_LOCKONLY" -eq 1 ]; } && [ "$_upd_fix" -eq 1 ] && todo 5 "Update the npm packages listed in section 5 to a version without the malware, and clear npm's cache with npm cache clean --force."
[ "$PY_HIT" -eq 0 ] && [ "$PY_UPD_HIT" -eq 1 ] && todo 5 "Update the Python packages listed in section 5 to a version without the malware."
[ "$EXT_HIT" -eq 0 ] && [ -n "$EXT_UPD" ] && todo 5 "Uninstall the editor extensions listed in section 5. Their malware could not run on this system."
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
elif [ "$MAL_SIGN" -eq 1 ]; then progress x "Scan done. Signs of $MAL_WHAT: act now"
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
  # A bad npm version found only in a lockfile, nothing installed (MAL_LOCKONLY), is act-if-installed:
  # its act-level incidents go in lock_only, worded as the person's report words them.
  _npm_inc=$NPM_TAGS; _lock=""
  if [ "$MAL_LOCKONLY" -eq 1 ]; then
    _lock=$(printf '%s\n' $NPM_TAGS | while IFS= read -r _t; do [ -n "$_t" ] && [ "$(incident_level "$_t")" = act ] && printf '%s\n' "$_t"; done | fleet_ids)
    _npm_inc=$(printf '%s\n' $NPM_TAGS | while IFS= read -r _t; do [ -n "$_t" ] && [ "$(incident_level "$_t")" != act ] && printf '%s\n' "$_t"; done)
  fi
  # An extension whose malware can't run on this system (EXT_UPD) is one to remove, not a sign.
  _inc=$(printf '%s\n' $_npm_inc $EXT_ACT_TAGS $PY_HITS $IND_HITS | fleet_ids)
  # Each error find printed is a folder not read, and a find that refused the scan prints one too.
  _fe=$(grep -c . "$SCAN_ERR" 2>/dev/null); case "$_fe" in ''|*[!0-9]*) _fe=0 ;; esac
  _nr=$(sort -u "$FLEET_NR" 2>/dev/null | grep -c .); _nr=$((_nr + NPM_UNREAD + N_LOCK_UNREAD + EXT_UNREAD + N_NL_DIRS + _fe))
  # Planted files that count (WORM_HIT), as the report lists them; one named like them alone is to read.
  _planted=$(( $(count_lines "$WORM_HIT") + $(count_lines "$WORM_REFS") ))
  # Possible signs, to check: a LiteLLM leftover with nothing else of LiteLLM, and a startup file
  # named like an extension incident's with no such extension (EXT_CHECK).
  _poss=""; [ -n "$LITE_PYC" ] && [ "$LITELLM_HIT" -eq 0 ] && _poss=litellm
  _poss=$(printf '%s\n' $_poss $EXT_CHECK_TAGS | fleet_ids)
  # Root starts the run with a clean environment, so a variable a shell profile sets to move an agent's
  # folders (CLAUDE_CONFIG_DIR and the like) is not followed: the account is partly checked then. The
  # profiles are read, never run.
  _moved=0
  for _pf in "$H/.zshenv" "$H/.zprofile" "$H/.zshrc" "$H/.bash_profile" "$H/.bashrc" "$H/.profile" "$H/.config/fish/config.fish"; do
    [ -f "$_pf" ] && fleet_ok "$_pf" || continue
    grep -qE '^[[:space:]]*(export[[:space:]]+|set[[:space:]]+-[A-Za-z]*x[A-Za-z]*[[:space:]]+)?(CLAUDE_CONFIG_DIR|CODEX_HOME|CODEX_SQLITE_HOME|GEMINI_CLI_HOME|QWEN_HOME|COPILOT_HOME|CLINE_DIR|CLINE_DATA_DIR|CLINE_SESSION_DATA_DIR|CONTINUE_GLOBAL_DIR|GOOSE_PATH_ROOT|KIRO_HOME|XDG_CONFIG_HOME|XDG_DATA_HOME|XDG_STATE_HOME)([=[:space:]])' "$_pf" 2>/dev/null && _moved=1
  done
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
    echo "lock_only=$_lock"
    echo "remove=$(printf '%s\n' $EXT_UPD_TAGS | fleet_ids)"
    echo "not_read=$_nr"
    echo "moved=$_moved"
    echo "tmp_marks=$(printf '%s\n' $FLEET_TMPMARK | fleet_ids)"
    echo "tmp_wiper=$FLEET_TMPWIPER"
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
elif [ "$MAL_SIGN" -eq 1 ]; then _act="ACT NOW: SIGNS OF $(upper "$MAL_WHAT")"
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
# A home scan that failed is said in the short header too, which the summary and its pages keep.
[ "$SCAN_FAILED" -eq 1 ] && wrap "The home folder was not scanned ($SCAN_WHY): project .env files, settings, MCP configs and lockfiles were not read. Sections 2 to 5 cover only the known agent paths."
HEAD_SHORT=$CAP; CAP=""
wrap "$STATS" 4 "  ${SEV}▌${RST} " "  ${SEV}▌${RST} " "$DIM" 4 "  ${YEL}▌${RST} " "  ${YEL}▌${RST} " "$YEL"
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
if [ "$SCAN_LOST" -eq 1 ]; then
  wrap "No temp folder could be written to, so the home scan could not tell which folders it could not read, and sections 2 to 5 may have missed files in them." 4 "  ${YEL}▌${RST} " "  ${YEL}▌${RST} " "$YEL"
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
  while IFS="$TAB" read -r nm vs fx holes; do
    [ -n "$nm" ] || continue
    pair "${YEL}!${RST}" "$nm" 20 "$vs, update to $fx or later"
    while [ -n "$holes" ]; do
      hole=${holes%%|*}; holes=${holes#*|}; src=${holes%%|*}
      case "$holes" in *"|"*) holes=${holes#*|} ;; *) holes="" ;; esac
      wrap "$(printf '%s' "${hole:0:1}" | tr 'a-z' 'A-Z')${hole:1}. $src" 8 "        " "        " "$DIM"
    done
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
if [ "$N_SEC2_UNREAD" -gt 0 ]; then
  blank
  wrap "$(plural "$N_SEC2_UNREAD" "config or settings file" "config or settings files") could not be read, so the servers, tokens and settings in them were not checked:" 5 "  ${YEL}!${RST}  " "     "
  _shown=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _shown=$((_shown + 1)); [ "$_shown" -le 20 ] && emit "     $(short "$f")"
  done <<EOF
$SEC2_UNREAD
EOF
  [ "$N_SEC2_UNREAD" -gt 20 ] && emit "        ${DIM}and $(($N_SEC2_UNREAD - 20)) more${RST}"
fi

SEC2=$CAP; CAP=""
section 03 "KEYS IN PLAIN TEXT" "$(plural "$KEY_FILES" file files)"
# With files that could not be read, this line comes below, with them.
if [ "$KEY_FILES" -eq 0 ] && [ "$N_KEY_UNREAD" -eq 0 ]; then
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
# The files that could not be read, named, so none of them is taken for one without keys.
if [ "$N_KEY_UNREAD" -gt 0 ]; then
  _ku=$(plural "$N_KEY_UNREAD" "file" "files")
  if [ "$KEY_FILES" -gt 0 ]; then _kt="$_ku could not be read, so this is not the full list:"
  elif [ "$HOME_PARTIAL" -eq 1 ]; then _kt="No AI or cloud keys in the files read, but $_ku and some folders in your home could not be read:"
  else _kt="No AI or cloud keys in the files read, but $_ku could not be read:"; fi
  wrap "$_kt" 8 "     ${YEL}!${RST}  " "        "
  _shown=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _shown=$((_shown + 1)); [ "$_shown" -le 20 ] && emit "        $(short "$f")"
  done <<EOF
$KEY_UNREAD
EOF
  [ "$N_KEY_UNREAD" -gt 20 ] && emit "        ${DIM}and $((N_KEY_UNREAD - 20)) more${RST}"
fi
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
    wrap "$(rotate_wait "Treat these keys as exposed and rotate them.")" 8 "        " "        "
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
if [ "$N_ALLOW" -eq 0 ] && [ "$N_ALLOW_UNREAD" -gt 0 ]; then wrap "No saved commands with keys in the files read, but $(plural "$N_ALLOW_UNREAD" "file" "files") could not be read:" 8 "     ${YEL}!${RST}  " "        "
  _shown=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _shown=$((_shown + 1)); [ "$_shown" -le 20 ] && emit "        $(short "$f")"
  done <<EOF
$ALLOW_UNREAD
EOF
  [ "$N_ALLOW_UNREAD" -gt 20 ] && emit "        ${DIM}and $(($N_ALLOW_UNREAD - 20)) more${RST}"
elif [ "$N_ALLOW" -eq 0 ] && [ "$HOME_PARTIAL" -eq 1 ]; then wrap "No saved commands with keys, but some folders in your home were not read." 8 "     ${YEL}!${RST}  " "        "
elif [ "$N_ALLOW" -eq 0 ]; then emit "     ${GRN}✓${RST}  No saved commands with keys."; fi
while IFS='|' read -r npm f; do
  [ -n "$f" ] || continue
  emit "     ${RED}✗${RST}  $(short "$f")"
  emit "        A saved command contains a key."
  [ "$npm" = 1 ] && wrap "An npm publish from this folder would include it." 8 "        " "        " "$RED"
done <<EOF
$ALLOW_ROWS
EOF
[ "$N_ALLOW" -gt 0 ] && [ "$N_ALLOW_UNREAD" -gt 0 ] && wrap "$(plural "$N_ALLOW_UNREAD" "file" "files") could not be read, so this is not the full list." 8 "     ${YEL}!${RST}  " "        "

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
$LITE_BAD$MARKS$UV_HIT
EOF
      while IFS="$TAB" read -r _t l _n; do
        [ "$_t" = "$_pi" ] && [ -n "$l" ] && { emit "        $(short "$l")"; emit "          $_n"; }
      done <<EOF
$PY_START
EOF
      [ "$_pi" = litellm ] && [ "$LOADER" -eq 1 ] && emit "        ${RED}A process holds the loader lock. The backdoor may be running now.${RST}"
      printf '%s' "$LITE_BAD" | grep -q "^$_pi$TAB" && _do="Don't run Python or pip in these environments."
      _pmk=0; printf '%s' "$MARKS" | grep -q "^$_pi$TAB" && _pmk=1
      # Found in uv's cache alone: what uv installs stays there.
      if [ -z "$_do" ] && [ "$_pmk" -eq 0 ] && ! { [ "$_pi" = litellm ] && [ "$LOADER" -eq 1 ]; } && printf '%s' "$UV_HIT" | grep -q "^$_pi$TAB"; then
        _do="uv keeps what it installs in its cache, so treat this version as installed here."
      elif [ "$_pmk" -eq 1 ] || [ -z "$_do" ]; then _do="${_do:+$_do }$(temp_advice "$_pi")"; fi
      # A startup file it leaves: stop what it started.
      printf '%s' "$PY_START" | grep -q "^$_pi$TAB" && _do="${_do:+$_do }Stop any process started from the file listed and delete it."
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
        if [ "$PY_UNREAD" -gt 0 ] && [ "$N_PY" -gt 0 ]; then pair "${YEL}!${RST}" "$_pl" 16 "no signs in $(plural "$N_PY" "Python environment" "Python environments"), but $PY_UNREAD more could not be read"
        elif [ "$PY_UNREAD" -gt 0 ]; then pair "${YEL}!${RST}" "$_pl" 16 "$(plural "$PY_UNREAD" "Python environment" "Python environments") could not be read"
        elif [ "$HOME_PARTIAL" -eq 1 ]; then pair "${YEL}!${RST}" "$_pl" 16 "no signs in $(plural "$N_PY" "Python environment" "Python environments"), but some folders in your home were not read"
        else pair "${GRN}✓${RST}" "$_pl" 16 "no signs in $(plural "$N_PY" "Python environment" "Python environments")"; fi
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
  [ -n "$_do" ] && wrap "$(rotate_wait "$_do") Advisory: $(incident_source "$_pi")" 8 "        " "        "
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
  # The commands go one to a line, never wrapped, so each can be copied whole.
  case "$OS" in
    Darwin) _stop="launchctl bootout gui/$(id -u 2>/dev/null)/com.user.gh-token-monitor
pkill -f gh-token-monitor" ;;
    Linux)  _stop="systemctl --user disable --now gh-token-monitor.service
pkill -f gh-token-monitor" ;;
    *)      _stop="pkill -f gh-token-monitor" ;;
  esac
  # Git for Windows has no pkill: PowerShell deletes the scheduled task that starts it at logon (its name in
  # Tensorlake's advisory) and ends the process by its command line, as gird-check.ps1 says. Deleting a task
  # does not end its running program, so both. That PowerShell's own command line names gh-token-monitor, so
  # $PID leaves it out. The single quotes keep bash from expanding anything, and the * in the argument keeps
  # Git Bash from rewriting /Delete as a path.
  [ "$WIN" -eq 1 ] && _stop="powershell -NoProfile -Command 'schtasks /Delete /TN gh-token-monitor /F; Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like \"*gh-token-monitor*\" -and \$_.ProcessId -ne \$PID } | Invoke-CimMethod -MethodName Terminate'"
  wrap "Don't revoke any GitHub token until it is stopped and these files are gone: gh-token-monitor runs a destructive command when the stolen token stops working, and in the TanStack wave it tries to erase the home folder." 8 "        " "        " "$RED"
  wrap "Stop it first, one command at a time:" 8 "        " "        " "$RED"
  while IFS= read -r _c; do [ -n "$_c" ] && emit "          $_c"; done <<EOF
$_stop
EOF
  wrap "Then delete the files listed above." 8 "        " "        " "$RED"
fi
if [ "$NPM_HIT" -eq 1 ] || [ -n "$PERSIST" ] || [ "$NPM_UPD" -eq 1 ]; then
  if [ "$NPM_HIT" -eq 1 ] || [ -n "$PERSIST" ]; then
    # Found only in a lockfile, nothing installed where it puts it: not a sign on this machine.
    if [ "$MAL_LOCKONLY" -eq 1 ]; then
      _lockwhere="in a lockfile"; [ "$N_LOCKPROJ" -gt 1 ] && _lockwhere="in lockfiles"
      pair "${RED}✗${RST}" "npm malware" 16 "${RED}${_lockwhere}: act if installed${RST}"
    else [ "$WIPER_HIT" -eq 1 ] || pair "${RED}✗${RST}" "npm malware" 16 "${RED}signs of the malware found${RST}"; fi
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
# What of npm's places could not be read: part of its cache or of the global installs, lockfiles,
# folders the scan could not enter. The row is never green over them, and findings above them are not
# the full list.
_np=""; _nn=0
[ "$((NPM_UNREAD - NPM_GUNREAD))" -gt 0 ] && { _np="part of npm's cache"; _nn=1; }
[ "$NPM_GUNREAD" -gt 0 ] && { _np="${_np:+$_np|}part of the global installs"; _nn=$((_nn + 1)); }
[ "$N_LOCK_UNREAD" -gt 0 ] && { _np="${_np:+$_np|}$(plural "$N_LOCK_UNREAD" lockfile lockfiles)"; _nn=$((_nn + 1)); }
[ "$HOME_PARTIAL" -eq 1 ] && { _np="${_np:+$_np|}some folders in your home"; _nn=$((_nn + 1)); }
case "$_nn" in 2) _np=${_np/|/ and } ;; 3) _np=${_np/|/, }; _np=${_np/|/ and } ;; 4) _np=${_np/|/, }; _np=${_np/|/, }; _np=${_np/|/ and } ;; esac
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
# Extensions whose malware could not run on this OS (data/bad-extensions.tsv's os): each, and why it is
# one to remove, not a sign of a compromised machine.
ext_upd_rows() {
  _oss=""; _xn=0
  while IFS="$TAB" read -r f p t o; do
    [ -n "$f" ] || continue
    emit "        $(short "$f")"
    emit "          ${p} ${DIM}($(npm_label "$t")), installed${RST}"
    _xn=$((_xn + 1))
    _ol="$o,"
    while [ -n "$_ol" ]; do
      _o1=${_ol%%,*}; _ol=${_ol#*,}
      case " $_oss " in *" $(os_name "$_o1") "*) ;; *) _oss="${_oss:+$_oss and }$(os_name "$_o1")" ;; esac
    done
  done <<EOF
$EXT_UPD
EOF
  if [ "$_xn" -eq 1 ]; then wrap "Its malware runs on $_oss only, so it did not run here. Uninstall it." 8 "        " "        "
  else wrap "Their malware runs on $_oss only, so it did not run here. Uninstall them." 8 "        " "        "; fi
}
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
  [ -n "$EXT_UPD" ] && ext_upd_rows
  for _t in $EXT_TAGS; do wrap "$(incident_line "$_t")" 8 "        " "        " "$DIM"; done
elif [ -n "$EXT_UPD" ]; then
  pair "${YEL}!${RST}" "Editor extensions" 16 "${YEL}a malicious extension to remove${RST}"
  ext_upd_rows
  if [ -n "$EXT_CHECK" ]; then
    while IFS="$TAB" read -r f p; do
      [ -n "$f" ] || continue
      emit "        $(short "$f")"
      emit "          has the name of a file that $p"
    done <<EOF
$EXT_CHECK
EOF
    wrap "No editor extension whose malware could run here was found. Open the file and check what it starts: if you did not set it up yourself, treat this machine as compromised." 8 "        " "        "
  fi
  for _t in $(printf '%s\n' $EXT_UPD_TAGS $EXT_CHECK_TAGS | sort -u); do wrap "$(incident_line "$_t")" 8 "        " "        " "$DIM"; done
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
  wrap "checked the extension folders of VS Code, Cursor, Windsurf, Devin Desktop, VSCodium, Kiro, Antigravity and Positron" 26 "                          " "                          " "$DIM"
fi
# With findings above, a folder that could not be read still has to be said.
if [ "$EXT_UNREAD" -gt 0 ] && { [ "$EXT_HIT" -eq 1 ] || [ -n "$EXT_CHECK" ] || [ -n "$EXT_UPD" ]; }; then
  if [ "$EXT_UNREAD" -eq 1 ]; then _xm="An extension folder"; else _xm="Some extension folders"; fi
  wrap "$_xm could not be read, so this is not the full list." 8 "        " "        " "$YEL"
fi
while IFS='|' read -r _pid _pnm _pcmd _ppath _pw _padv _psum; do
  [ -n "$_pid" ] || continue
  if [ "$(plat_hit "$_pid")" = 1 ]; then
    pair "${YEL}!${RST}" "$_pnm" 16 "$_pw"
    wrap "$(rotate_wait "$_padv")" 26 "                          " "                          " "$DIM"
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
  elif [ "$MAL_LOCKONLY" -eq 1 ] && [ "$EXT_HIT" -eq 0 ] && [ "$PY_HIT" -eq 0 ] && [ "$NPM_UPD" -eq 0 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found npm malware listed in a lockfile, with no sign it was installed here. It can't tell you what your agents do after you close this window."
  elif [ "$ANY_MAL" -eq 1 ] || [ "$PY_HIT" -eq 1 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    # Each kind of malware it found, and npm malware found only in a lockfile named as that, last.
    _sig=""
    [ "$MAL_SIGN" -eq 1 ] && _sig=$MAL_WHAT
    [ "$PY_HIT" -eq 1 ] && _sig="${_sig:+$_sig and of }the $PY_SHORT malware"
    if [ -z "$_sig" ]; then _sig="npm malware"
    elif [ "$MAL_LOCKONLY" -eq 1 ]; then _sig="$_sig, and npm malware listed in a lockfile"; fi
    _p1="It found signs of $_sig. It can't tell you what the malware already took, or what your agents do after you close this window."
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
elif [ "$N_YOLO" -gt 0 ]; then G1="${YEL}!${RST}"; D1="$N_AG found, $N_YOLO_AG set to run commands without asking"
elif [ "$N_AG" -eq 0 ]; then G1="${DIM}·${RST}"; D1="none found"
elif [ "$N_IDLE" -gt 0 ]; then G1="${YEL}○${RST}"; D1="$N_AG found, $N_IDLE idle: $(first_names "$IDLE_NAMES" 2)"
else G1="${GRN}✓${RST}"; D1="$N_AG found, all used in the last 30 days"; fi
if [ "$N_AK" -gt 0 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, $(plural "$N_AK" "file links" "files link") to your SSH logins"
elif [ "$N_MCP_TOKEN" -gt 1 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, tokens in $N_MCP_TOKEN files, like $(short "$MCP_TOK_FIRST")"
elif [ "$N_MCP_TOKEN" -eq 1 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, a token in $(short "$MCP_TOK_FIRST")"
elif [ "$N_AUTO" -gt 0 ]; then G2="${YEL}!${RST}"; D2="$MCP_SUM, $(plural "$N_AUTO_PROJ" "project acts" "projects act") on opening"
elif [ "$N_LOOK" -gt 0 ]; then G2="${YEL}!${RST}"; D2="$MCP_SUM, $(plural "$N_LOOK" "project file" "project files") to read"
elif [ "$N_SEC2_UNREAD" -gt 0 ]; then G2="${YEL}!${RST}"; D2="$MCP_SUM, but $(plural "$N_SEC2_UNREAD" "file" "files") could not be read"
elif [ "$HOME_PARTIAL" -eq 1 ]; then G2="${YEL}!${RST}"; D2="$MCP_SUM, but some folders were not read"
elif [ -n "$MCP_ROWS" ]; then G2="${GRN}✓${RST}"; D2="$MCP_SUM, no tokens in their configs"
else G2="${GRN}✓${RST}"; D2="none configured"; fi
if [ "$KEY_FILES" -gt 1 ]; then G3="${RED}✗${RST}"; D3="$KEY_FILES files, like $(short "${KEY_FIRST#*|}") (${KEY_FIRST%%|*})"
elif [ "$KEY_FILES" -eq 1 ]; then G3="${RED}✗${RST}"; D3="$(short "${KEY_FIRST#*|}") holds ${KEY_FIRST%%|*} keys"
elif [ "$N_SESS" -gt 0 ]; then G3="${RED}✗${RST}"; D3="keys in $(plural "$N_SESS" "agent session file" "agent session files"): $(printf '%s' "$SESS_ROWS" | head -n 1 | cut -d'|' -f1)"
elif [ "$N_KEY_UNREAD" -gt 0 ]; then G3="${YEL}!${RST}"; D3="none found, but $(plural "$N_KEY_UNREAD" "file" "files") could not be read"
elif [ "$SESS_PARTIAL" -eq 1 ]; then G3="${YEL}!${RST}"; D3="none in files; agent sessions partly checked"
elif [ "$N_SSH_OPEN" -gt 0 ]; then G3="${YEL}○${RST}"; D3="none in plain text, but $(plural "$N_SSH_OPEN" "SSH key has" "SSH keys have") no passphrase"
elif [ "$HOME_PARTIAL" -eq 1 ]; then G3="${YEL}!${RST}"; D3="none found, but some folders were not read"
else G3="${GRN}✓${RST}"; D3="no AI or cloud keys in plain text"; fi
if [ "$N_ALLOW" -eq 0 ] && [ "$N_ALLOW_UNREAD" -gt 0 ]; then G4="${YEL}!${RST}"; D4="none found, but $(plural "$N_ALLOW_UNREAD" "file" "files") could not be read"
elif [ "$N_ALLOW" -eq 0 ] && [ "$HOME_PARTIAL" -eq 1 ]; then G4="${YEL}!${RST}"; D4="none found, but some folders were not read"
elif [ "$N_ALLOW" -eq 0 ]; then G4="${GRN}✓${RST}"; D4="no saved commands with keys"
elif [ "$N_ALLOW_NPM" -gt 0 ] && [ "$N_ALLOW" -eq 1 ]; then G4="${RED}✗${RST}"; D4="1 saved key, and an npm publish would ship it"
elif [ "$N_ALLOW_NPM" -gt 0 ]; then G4="${RED}✗${RST}"; D4="$N_ALLOW saved keys, $N_ALLOW_NPM that an npm publish would ship"
elif [ "$N_ALLOW" -eq 1 ]; then G4="${RED}✗${RST}"; D4="a saved key in $(short "$ALLOW_FIRST")"
else G4="${RED}✗${RST}"; D4="saved keys in $N_ALLOW files"; fi
if [ "$WIPER_HIT" -eq 1 ]; then G5="${RED}✗${RST}"; D5="gh-token-monitor: stop it before revoking tokens"
elif [ "$MAL_SIGN" -eq 1 ] && [ "$PY_HIT" -eq 1 ]; then G5="${RED}✗${RST}"; D5="$MAL_SHORT and $PY_SHORT malware found. Act now"
elif [ "$MAL_LOCKONLY" -eq 1 ] && [ "$EXT_HIT" -eq 0 ] && [ "$PY_HIT" -eq 0 ]; then G5="${RED}✗${RST}"; D5="npm malware in a lockfile: act if installed"
elif [ "$MAL_SIGN" -eq 1 ]; then G5="${RED}✗${RST}"; D5="signs of $MAL_WHAT. Act now"
elif [ "$PY_HIT" -eq 1 ]; then G5="${RED}✗${RST}"; D5="signs of the $PY_SHORT malware. Act now"
elif [ -n "$UPD_SUM" ]; then G5="${YEL}!${RST}"; D5=$UPD_SUM
elif [ -n "$LITE_PYC" ]; then G5="${YEL}!${RST}"; D5="possible LiteLLM leftover: check cook.pyc"
elif [ -n "$EXT_CHECK" ]; then G5="${YEL}!${RST}"; D5="a startup file to check, see section 5"
elif [ -n "$EXT_UPD" ]; then G5="${YEL}!${RST}"; D5="an editor extension to remove, see section 5"
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
elif [ "$((NPM_UNREAD - NPM_GUNREAD))" -gt 0 ]; then G5="${YEL}!${RST}"; D5="npm packages not fully checked: cache unreadable"
elif [ "$NPM_GUNREAD" -gt 0 ]; then G5="${YEL}!${RST}"; D5="npm packages not fully checked: folder unreadable"
elif [ "$EXT_UNREAD" -gt 0 ]; then G5="${YEL}!${RST}"; D5="extensions not fully checked: folder unreadable"
elif [ "$PY_UNREAD" -gt 0 ]; then G5="${YEL}!${RST}"; D5="Python not fully checked: folder unreadable"
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
