#!/usr/bin/env bash
# Blindspot, the GIRD AI key check, version 1.1.0 (22 October 2026)
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
# Key formats come from Argus.
#
#   bash gird-check.sh             a short summary; press 1 to 5 for details
#   bash gird-check.sh --full      every detail, no summary
#   bash gird-check.sh --all       also scans Desktop, Documents and Downloads
#   bash gird-check.sh --offline   shares nothing (DO_NOT_TRACK=1 works too)
#   bash gird-check.sh --save      saves the full report as a text file
#   bash gird-check.sh --no-game   skips the game while it scans
#   NO_COLOR=1 bash gird-check.sh  plain text, no colors

ORIG_LANG=${LC_ALL:-${LANG:-}}
export LC_ALL=C

ALL=0; SAVE=0; NOGAME=0; OFFLINE=0; FULL=0
[ "${DO_NOT_TRACK:-0}" = 1 ] && OFFLINE=1
for arg in "$@"; do
  case "$arg" in
    --all) ALL=1 ;;
    --full) FULL=1 ;;
    --save) SAVE=1 ;;
    --no-game) NOGAME=1 ;;
    --offline) OFFLINE=1 ;;
    --no-color) NO_COLOR=1 ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s (try --help)\n' "$arg"; exit 2 ;;
  esac
done
VERSION=1
WEB=${GIRD_CHECK_WEB:-https://gird.ai}   # the overrides here are for testing
API=${GIRD_CHECK_API:-$WEB/api/check}

H=${HOME:-}
if [ -z "$H" ] || [ ! -d "$H" ]; then echo "HOME is not set."; exit 1; fi
OS=$(uname -s); ARCH=$(uname -m)
# Apple Silicon even when Terminal runs under Rosetta
if [ "$OS" = Darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then ARCH=arm64; fi
if [ "$OS" = Darwin ]; then AS="$H/Library/Application Support"; else AS="$H/.config"; fi

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
plural() { if [ "$1" = 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }
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
  emit "  ${TEAL}    ⠐⠛⠿⠿⠛⠃    ${RST}   ${B}BLINDSPOT${RST}  ${DIM}v1.1.0 · 22 Oct 2026 · gird.ai/blindspot${RST}"
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
  _pm[0]="$(commas "$_dv") people have run Blindspot."
  if [ -n "$_d7" ] && [ "$_d7" -ge 50 ]; then _pm[${#_pm[@]}]="$(commas "$_d7") people ran it this week."; fi
  if [ -n "$_kf" ] && [ "$_kf" -ge 100 ]; then _pm[${#_pm[@]}]="Blindspot has found $(commas "$_kf") files with AI keys in plain text so far."; fi
  if [ -n "$_cl" ]; then
    _cp=$(awk -v c="$_cl" 'BEGIN { printf "%d", c * 100 + 0.5 }')
    if [ "$_cp" -ge 1 ] && [ "$_cp" -le 99 ]; then _pm[${#_pm[@]}]="$_cp% of people had no keys in plain text. Let's see about you."; fi
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
game_ok() {
  [ "$NOGAME" -eq 0 ] && [ "$TTY" -eq 1 ] && [ -t 0 ] && [ -n "$TEAL" ] && [ "$W" -ge 64 ] && command -v stty >/dev/null 2>&1
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
cleanup() {
  spin_stop
  if [ -n "$SP_PID" ]; then kill "$SP_PID" 2>/dev/null; wait "$SP_PID" 2>/dev/null; SP_PID=""; fi
  if [ -n "$GAME_PID" ]; then kill "$GAME_PID" 2>/dev/null; wait "$GAME_PID" 2>/dev/null; GAME_PID=""; fi
  if [ -n "$KEYS_PID" ]; then kill "$KEYS_PID" 2>/dev/null; wait "$KEYS_PID" 2>/dev/null; KEYS_PID=""; fi
  if [ -n "$SAVED_TTY" ]; then stty "$SAVED_TTY" </dev/tty 2>/dev/null; SAVED_TTY=""; fi
  [ -n "$PROG_FILE" ] && rm -f "$PROG_FILE"
  [ -n "$SP_FILE" ] && rm -f "$SP_FILE"
  printf '%s' "$SHOW"
}
trap cleanup EXIT
trap 'cleanup; printf "\n"; exit 130' INT TERM

# ---------------------------------------------------------------------------
# Key formats. Matching uses grep -q or grep -o into a pipe, so a key is never
# printed, kept in a shell variable or sent anywhere.
# ---------------------------------------------------------------------------
P_ANTHROPIC='sk-ant-[A-Za-z0-9_-]{90,}'
P_OPENAI='sk-proj-[A-Za-z0-9_-]{120,}|sk-svcacct-[A-Za-z0-9_-]{60,}|(^|[^A-Za-z0-9-])sk-[A-Za-z0-9]{48}([^A-Za-z0-9]|$)'
P_GOOGLE='AIza[0-9A-Za-z_-]{35}|(^|[^A-Za-z0-9])AQ\.[A-Za-z0-9_-]{40,}'
P_OPENROUTER='sk-or-v1-[a-f0-9]{64}'
P_GROQ='gsk_[A-Za-z0-9]{52}'
P_XAI='xai-[A-Za-z0-9]{64,}'
P_HF='(^|[^A-Za-z0-9_])hf_[A-Za-z0-9]{34,40}([^A-Za-z0-9_]|$)'
P_PPLX='pplx-[A-Za-z0-9]{40,52}'
P_REPLICATE='r8_[A-Za-z0-9]{37}'
P_AWS='(^|[^A-Z0-9])AKIA[0-9A-Z]{16}([^A-Z0-9]|$)|bedrock-api-key-YmVkcm9jay5hbWF6b25hd3MuY29t'
P_GITHUB='gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}'
P_NPM='npm_[A-Za-z0-9]{36}'
ALL_KEYS="$P_ANTHROPIC|$P_OPENAI|$P_GOOGLE|$P_OPENROUTER|$P_GROQ|$P_XAI|$P_HF|$P_PPLX|$P_REPLICATE|$P_AWS|$P_GITHUB|$P_NPM"

# A secret written as a value: KEY=value in a command, or "token": "value" in a config.
P_ASSIGN='[A-Z][A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*=[^[:space:]"$\\]{12,}'
P_JSONSECRET='"([A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*|apiKey|api_key|accessToken|access_token|authToken|token|secret)"[[:space:]]*:[[:space:]]*"[^"$<{][^"]{11,}"'
P_TOMLSECRET='[A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*[[:space:]]*=[[:space:]]*"[^"$<{][^"]{11,}"'
P_PLACEHOLDER='your|xxxx|here|example|placeholder|changeme|dummy|<|[$][{]'

providers_in() {
  grep -aoE "$ALL_KEYS" "$1" 2>/dev/null | awk '
    { s = $0; sub(/^[^A-Za-z]+/, "", s)
      if (s ~ /^sk-ant-/) p = "Anthropic"
      else if (s ~ /^sk-or-v1-/) p = "OpenRouter"
      else if (s ~ /^sk-/) p = "OpenAI"
      else if (s ~ /^(AIza|AQ[.])/) p = "Google"
      else if (s ~ /^gsk_/) p = "Groq"
      else if (s ~ /^xai-/) p = "xAI"
      else if (s ~ /^hf_/) p = "Hugging Face"
      else if (s ~ /^pplx-/) p = "Perplexity"
      else if (s ~ /^r8_/) p = "Replicate"
      else if (s ~ /^(AKIA|bedrock-api-key)/) p = "AWS"
      else if (s ~ /^(gh[pousr]_|github_pat_)/) p = "GitHub"
      else if (s ~ /^npm_/) p = "npm"
      else next
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
PROVIDER_IDS="anthropic openai google openrouter groq xai huggingface perplexity replicate aws github npm"

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

# One pass over the home folder, depth-limited, skipping heavy and system folders:
# dependency caches, build output, model and VM images, cloud sync folders.
scan_home() {
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
    -o -path "$H/.windsurf" -o -path "$H/.local/share" -o -path "$H/Dropbox" -o -path "$H/Google Drive" \
    -o -path "$H/OneDrive*"
  if [ "$ALL" -eq 0 ]; then set -- "$@" -o -path "$H/Desktop" -o -path "$H/Documents" -o -path "$H/Downloads"; fi
  find "$H" -maxdepth 6 \( -type d \( "$@" \) -prune \) -o \
    \( -type d -name site-packages -print -prune \) -o \
    \( -type f \( -name .env -o -name '.env.*' -o -name .envrc -o -name .mcp.json -o -name pyvenv.cfg \
       -o -path '*/.claude/settings.local.json' -o -path '*/.claude/settings.json' \
       -o -path '*/.cursor/mcp.json' -o -path '*/.vscode/mcp.json' \) -print \) 2>/dev/null
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
    _s=${_l//$'\xc2'[$'\x80'-$'\x9f']/?}; _s=${_s//[[:cntrl:]]/?}
    # shellcheck disable=SC2088  # a literal ~ for home paths, as short() prints
    case "$_s" in "$H"/*) _s="~/${_s#"$H"/}" ;; esac
    progress i "Checking $_s"
  done
}

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

progress i "Looking through your home folder"
FOUND=$(scan_home | scan_progress)
ENV_FILES=$(printf '%s\n' "$FOUND" | grep -E '/\.env(rc|\.[^/]*)?$')
ALLOW_FILES=$(printf '%s\n' "$FOUND" | grep -E '/\.claude/settings(\.local)?\.json$')
PROJECT_MCP=$(printf '%s\n' "$FOUND" | grep -E '/(\.mcp\.json|\.cursor/mcp\.json|\.vscode/mcp\.json)$')
SITES=$(printf '%s\n' "$FOUND" | grep -E '/site-packages$')
VENVS=$(printf '%s\n' "$FOUND" | grep -E '/pyvenv\.cfg$' | sed 's#/pyvenv\.cfg$##')

# --- 1. Coding agents --------------------------------------------------------
# name | commands | install paths | folders that change when it is used | id
AGENTS="Claude Code|claude|$H/.claude|$H/.claude/projects|claude-code
Claude Desktop||/Applications/Claude.app;$AS/Claude|$AS/Claude|claude-desktop
Codex|codex|$H/.codex|$H/.codex/sessions|codex
Gemini CLI|gemini|$H/.gemini|$H/.gemini/tmp|gemini-cli
Cursor|cursor|/Applications/Cursor.app;$H/.cursor|$AS/Cursor/User/workspaceStorage|cursor
Windsurf|windsurf|/Applications/Windsurf.app;$H/.codeium/windsurf|$AS/Windsurf/User/workspaceStorage|windsurf
Antigravity|antigravity|/Applications/Antigravity.app|$AS/Antigravity/User/workspaceStorage|antigravity
GitHub Copilot CLI|copilot|$H/.copilot|$H/.copilot|copilot-cli
OpenCode|opencode|$H/.config/opencode;$H/.local/share/opencode|$H/.local/share/opencode|opencode
Goose|goose|$H/.config/goose|$H/.local/share/goose|goose
Aider|aider|||aider
Cline||$AS/Code/User/globalStorage/saoudrizwan.claude-dev;$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev|$AS/Code/User/globalStorage/saoudrizwan.claude-dev/tasks;$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks|cline
Continue||$H/.continue|$H/.continue/sessions|continue"

AG_ROWS=""; AGENT_IDS=""; AG_NAMES=""; N_AG=0; N_IDLE=0; IDLE_NAMES=""; IDLE_IDS=""
while IFS='|' read -r name bins paths acts aid; do
  [ -n "$name" ] || continue
  inst=0; old_ifs=$IFS; IFS=';'
  for b in $bins; do [ -n "$b" ] && command -v "$b" >/dev/null 2>&1 && inst=1; done
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
Goose|goose|$H/.config/goose/config.yaml
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
MCP_FLAGGED="|$(printf '%s\n' "$MCP_LIST" | files_matching "$ALL_KEYS|$P_JSONSECRET|$P_TOMLSECRET" | tr '\n' '|')"
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
  MCP_ROWS="$MCP_ROWS$1|$_f|$_c|$_tok|$_pl
"
}
while IFS='|' read -r who cid f; do
  [ -n "$who" ] && [ -f "$f" ] && mcp_row "$who" "$f" "$cid"
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
    printf '%s\n' "$PROJECT_FILES"
  } | awk 'NF && !seen[$0]++'
)
MATCHED=$(printf '%s\n' "$CANDIDATES" | files_matching "$ALL_KEYS")
# For the report: one place id per file, and one provider id per file and provider.
KEY_PLACES=""; PROV_TALLY=""
MCP_SET="|$(printf '%s\n' "$MCP_LIST" | tr '\n' '|')"; PROJECT_SET="|$(printf '%s\n' "$PROJECT_FILES" | tr '\n' '|')"
key_place() { # file: sets KP to its place, the first in KEY_PLACE_IDS that fits
  case "$1" in
    "$H/.zshrc"|"$H/.zprofile"|"$H/.zshenv"|"$H/.zlogin"|"$H/.bashrc"|"$H/.bash_profile"|"$H/.profile"|"$H/.config/fish/config.fish")
      KP=shell_rc; return 0 ;;
    "$H/.zsh_history"|"$H/.bash_history"|"$H/.local/share/fish/fish_history"|"$H/.python_history"|"$H/.node_repl_history")
      KP=shell_history; return 0 ;;
  esac
  case "${1##*/}" in .env|.env.*|.envrc) KP=env_file; return 0 ;; esac
  case "$MCP_SET" in *"|$1|"*) KP=mcp_config; return 0 ;; esac
  case "$1" in
    "$H"/.claude/*|"$H"/.codex/*|"$H"/.gemini/*|"$H"/.cursor/*|"$H"/.codeium/*|"$H"/.continue/*) KP=agent_config; return 0 ;;
    "$H"/.copilot/*|"$H"/.config/goose/*|"$H"/.config/opencode/*|"$H"/.local/share/opencode/*|"$H"/.aider*|"$AS"/Claude/*) KP=agent_config; return 0 ;;
  esac
  case "$PROJECT_SET" in *"|$1|"*) KP=project_file; return 0 ;; esac
  KP=other
}
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _p=$(providers_in "$f")
  [ -n "$_p" ] || continue
  KEY_FILES=$((KEY_FILES + 1)); [ -n "$KEY_FIRST" ] || KEY_FIRST="$f|$_p"
  progress x "Key in plain text: $(short "$f") ($_p)"
  key_place "$f"; KEY_PLACES="$KEY_PLACES$KP
"
  [ "$KP" = shell_history ] && HIST_KEYS=$((HIST_KEYS + 1))
  old_ifs=$IFS; IFS=','
  for _nm in $_p; do
    _nm=${_nm# }
    case "$_nm" in "Hugging Face") _id=huggingface ;; *) _id=$(printf '%s' "$_nm" | tr 'A-Z' 'a-z') ;; esac
    case " $PROV_IDS " in *" $_id "*) ;; *) PROV_IDS="${PROV_IDS:+$PROV_IDS }$_id" ;; esac
    PROV_TALLY="$PROV_TALLY$_id
"
  done
  IFS=$old_ifs
  KEY_ROWS="$KEY_ROWS$f|$_p
"
done <<EOF
$MATCHED
EOF
[ "$KEY_FILES" -eq 0 ] && progress o "No keys in shell profiles, history, agent configs or .env files"

# Login files any agent you run can read.
LOGINS=""; LOGIN_IDS=""
login() { # file label id [marker regex]
  [ -f "$1" ] || return
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
N_SSH=0; N_SSH_OPEN=0
for k in "$H"/.ssh/*; do
  [ -f "$k" ] || continue
  case "$k" in *.pub|*known_hosts*|*config|*authorized_keys*) continue ;; esac
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
ALLOW_ALL=$(printf '%s\n%s\n%s\n' "$ALLOW_FILES" "$H/.claude/settings.json" "$H/.claude/settings.local.json" | grep -v '^$' | sort -u | files_matching "$ALL_KEYS|$P_ASSIGN")
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  command_secret "$f" || continue
  N_ALLOW=$((N_ALLOW + 1)); [ -n "$ALLOW_FIRST" ] || ALLOW_FIRST=$f
  progress x "Saved Claude Code command with a key: $(short "$f")"
  npm=0; npm_would_ship "${f%/.claude/*}" && { npm=1; N_ALLOW_NPM=$((N_ALLOW_NPM + 1)); }
  ALLOW_ROWS="$ALLOW_ROWS$f|$npm
"
done <<EOF
$ALLOW_ALL
EOF
[ "$N_ALLOW" -eq 0 ] && progress o "No saved Claude Code commands with keys"

# --- 5. This week's key leaks ------------------------------------------------
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
progress i "Checking $(plural "$(printf '%s\n' "$SITES_ALL" | grep -c .)" "Python environment" "Python environments") for the LiteLLM malware"
N_PY=0; N_LITE=0; LITE_VERS=""; LITE_BAD=""; LITE_PYC=""
while IFS= read -r sp; do
  [ -n "$sp" ] && [ -d "$sp" ] || continue
  N_PY=$((N_PY + 1))
  for d in "$sp"/litellm-*.dist-info; do
    [ -d "$d" ] || continue
    v=${d##*/litellm-}; v=${v%.dist-info}
    N_LITE=$((N_LITE + 1))
    case " $LITE_VERS " in *" $v "*) ;; *) LITE_VERS="${LITE_VERS:+$LITE_VERS }$v" ;; esac
  done
  bad=""
  [ -d "$sp/litellm-1.107.0.dist-info" ] && bad="litellm 1.107.0"
  [ -f "$sp/cook.pth" ] && bad="${bad:+$bad, }cook.pth"
  [ -f "$sp/cook.py" ] && bad="${bad:+$bad, }cook.py"
  for _pyc in "$sp"/__pycache__/cook.*.pyc; do [ -f "$_pyc" ] && { LITE_PYC="$LITE_PYC$(short "$sp"): cook.pyc
"; break; }; done
  [ -n "$bad" ] && LITE_BAD="$LITE_BAD$(short "$sp"): $bad
"
done <<EOF
$SITES_ALL
EOF
MARKS=""
for t in /tmp "${TMPDIR%/}"; do
  [ -n "$t" ] && [ -d "$t" ] || continue
  for m in "$t/remote_code_loader.lock" "$t"/.pc_once_* "$t"/.pc_sq_* "$t"/.pc_e_*; do
    [ -e "$m" ] && MARKS="$MARKS$m
"
  done
done
[ -n "${PRIVCOLLECT_ACTIVE:-}" ] && MARKS="${MARKS}PRIVCOLLECT_ACTIVE is set in this shell
"
LOADER=0
if [ -e /tmp/remote_code_loader.lock ] && command -v lsof >/dev/null 2>&1; then
  [ -n "$(lsof -t /tmp/remote_code_loader.lock 2>/dev/null)" ] && LOADER=1
fi
UV_BAD=$(find "$H/.cache/uv" -maxdepth 6 -name 'litellm-1.107.0*' -print -quit 2>/dev/null)
LITELLM_HIT=0
if [ -n "$LITE_BAD" ] || [ -n "$MARKS" ] || [ "$LOADER" -eq 1 ]; then LITELLM_HIT=1; fi
if [ "$LITELLM_HIT" -eq 1 ]; then progress x "Signs of the LiteLLM malware found"
elif [ -n "$LITE_PYC" ]; then progress w "A leftover cook.pyc may come from the LiteLLM malware"
else progress o "No signs of the LiteLLM malware in $(plural "$N_PY" "Python environment" "Python environments")"; fi
OC=0
if command -v opencode >/dev/null 2>&1 || [ -d "$H/.config/opencode" ] || [ -d "$H/.local/share/opencode" ]; then OC=1; fi
RW=0
if command -v railway >/dev/null 2>&1 || [ -f "$H/.railway/config.json" ]; then RW=1; fi
ZB=0
if command -v zeabur >/dev/null 2>&1 || [ -d "$H/.config/zeabur" ]; then ZB=1; fi

# --- What to do, and the score -----------------------------------------------
# Each fix also belongs to a section, so that section's details can end with it.
TODO=""; ISSUES=0; FIX1=""; FIX2=""; FIX3=""; FIX4=""; FIX5=""
todo() { # section text
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
[ "$LITELLM_HIT" -eq 0 ] && [ -n "$LITE_PYC" ] && todo 5 "A leftover cook.pyc can come from the LiteLLM 1.107.0 malware. If litellm 1.107.0 was ever installed there, treat this machine as compromised, follow LiteLLM's advisory and rotate every key it could reach."
[ "$LITELLM_HIT" -eq 1 ] && todo 5 "Treat this machine as compromised. Don't run Python in the affected environments, follow LiteLLM's advisory, and rotate every key the machine could reach."
case "$OS" in
  Darwin) _store="the macOS Keychain or a secrets manager" ;;
  Linux)  _store="your desktop keyring (GNOME Keyring or KWallet) or a secrets manager" ;;
  MINGW*|MSYS*|CYGWIN*) _store="Windows Credential Manager or a secrets manager" ;;
  *)      _store="a secrets manager" ;;
esac
[ "$KEY_FILES" -gt 0 ] && todo 3 "Move keys out of shell profiles, history and .env files into $_store, then rotate them."
[ "$HIST_KEYS" -gt 0 ] && todo 3 "Keys in shell history were typed into a command. Treat them as exposed and rotate them."
[ "$N_MCP_TOKEN" -gt 0 ] && todo 2 "Replace tokens written into MCP configs with environment variable references, then rotate them."
[ "$N_ALLOW" -gt 0 ] && todo 4 "Delete the saved Claude Code commands that contain keys, add .claude/ to .npmignore, and rotate those keys."
[ "$N_SSH_OPEN" -gt 0 ] && todo 3 "Add a passphrase to SSH keys that have none, with ssh-keygen -p -f followed by the key file."
[ "$N_IDLE" -gt 0 ] && todo 1 "Remove agents you no longer use: $IDLE_NAMES. A poisoned package can drive an installed agent, which is how the Nx attack stole keys."
if [ "$OC" -eq 1 ] || [ "$RW" -eq 1 ] || [ "$ZB" -eq 1 ]; then todo 5 "If you used OpenCode Console or deploy on Railway or Zeabur, rotate the keys stored there, even if nothing above looks wrong."; fi

SCORE=100
[ "$LITELLM_HIT" -eq 1 ] && SCORE=$((SCORE - 40))
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
if [ "$LITELLM_HIT" -eq 1 ]; then progress x "Scan done. Signs of the LiteLLM malware: act now"
elif [ "$ISSUES" -gt 0 ]; then progress w "Scan done: $(plural "$ISSUES" "thing" "things") to fix"
else progress o "Scan done: no findings"; fi

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
# one-way SHA-256 of the hardware UUID (Linux: machine-id) salted for this
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
sha_hex() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum 2>/dev/null; fi | cut -c1-64; }
HWID=""
if [ "$OS" = Darwin ]; then HWID=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/ {print $4; exit}')
elif [ -r /etc/machine-id ]; then HWID=$(head -c 64 /etc/machine-id 2>/dev/null); fi
DEVICE_ID=""; [ -n "$HWID" ] && DEVICE_ID=$(printf 'gird-check-v1:%s' "$HWID" | sha_hex)
HWID=""
case "$DEVICE_ID" in *[!0-9a-f]*) DEVICE_ID="" ;; esac; [ "${#DEVICE_ID}" -eq 64 ] || DEVICE_ID=""
RUN_ID=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
case "$RUN_ID" in *[!0-9a-f]*) RUN_ID="" ;; esac; [ "${#RUN_ID}" -eq 16 ] || RUN_ID=""
OSV=Linux
if [ "$OS" = Darwin ]; then OSV="macOS $(sw_vers -productVersion 2>/dev/null | tr -cd '0-9.' | cut -d. -f1-2)"; OSV=${OSV% }; fi
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
TMUXED=0; [ -n "${TMUX:-}" ] && TMUXED=1
case "${SHELL##*/}" in zsh|bash|fish|sh|dash|ksh|tcsh|nu|elvish|xonsh) SHELLNAME=${SHELL##*/} ;; '') SHELLNAME=unknown ;; *) SHELLNAME=other ;; esac
LANGCODE=${ORIG_LANG%%.*}
case "$LANGCODE" in [a-z][a-z]|[a-z][a-z]_[A-Z][A-Z]) ;; *) LANGCODE=other ;; esac
VIA=none; [ -n "${CLAUDECODE:-}" ] && VIA=claude-code
count_lines() { if [ -n "$1" ]; then printf '%s\n' "$1" | grep -c .; else printf 0; fi; }
N_FOUND=$(count_lines "$FOUND"); N_ENVF=$(count_lines "$ENV_FILES"); N_ALLOWF=$(count_lines "$ALLOW_FILES"); N_MCPF=$(printf '%s' "$MCP_ROWS" | grep -c '|0$')
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
# The reply holds p, the share of developers whose latest run scored lower, n,
# how many developers that is, and r, this device's place in line when it is one
# of the first 1,000 to run Blindspot. Only digits are read from it.
PCT=""; PCT_N=""; RANK=""; LINK_RUN_ID=""
if [ "$OFFLINE" -eq 0 ] && command -v curl >/dev/null 2>&1; then
  LINK_RUN_ID=$RUN_ID   # the certificate link carries the run ID only when a report did
  [ "$TTY" -eq 1 ] && printf '  %sComparing with other people...%s' "$DIM" "$RST"
  _rp=$(send_stats "$PAYLOAD" 3 | head -c 4096 | tr -d ' \n\r\t')
  [ "$TTY" -eq 1 ] && printf '\r%s' "${E}[K"
  _p=$(jnum p "$_rp"); _n=$(jnum n "$_rp"); _rank=$(jnum r "$_rp")
  if [ -n "$_p" ] && [ -n "$_n" ] && [ "${#_n}" -le 9 ] && [ "$_p" -ge 1 ] && [ "$_p" -le 99 ] && [ "$_n" -ge 1 ]; then PCT=$_p; PCT_N=$_n; fi
  case "$_rank" in [1-9]|[1-9][0-9]|[1-9][0-9][0-9]|1000) RANK=$_rank ;; esac   # a whole number from 1 to 1000, or unknown
fi


# ===========================================================================
# The report. Every part is built first, then shown: a summary on a terminal,
# with each section's details a key press away, or every detail with --full or
# when the output isn't a terminal. A saved report always has every detail.
# ===========================================================================
if [ "$LITELLM_HIT" -eq 1 ]; then SEV=$RED
elif [ "$KEY_FILES" -gt 0 ] || [ "$N_ALLOW" -gt 0 ] || [ "$N_MCP_TOKEN" -gt 0 ]; then SEV=$RED
elif [ "$ISSUES" -gt 0 ]; then SEV=$YEL
else SEV=$GRN; fi
if [ "$ISSUES" -gt 0 ]; then FIXN="$(plural "$ISSUES" "thing" "things") to fix"; else FIXN="No findings in this scan"; fi
PCT_TXT=""; [ -n "$PCT" ] && PCT_TXT="Safer than $PCT% of $(commas "$PCT_N") people who ran Blindspot"
STATS="$(plural "$N_AG" "coding agent" "coding agents"), $N_IDLE not used in 30 days, $(plural "$N_MCP" "MCP server" "MCP servers"), $(plural "$KEY_FILES" "file" "files") with keys in plain text, $(plural "$N_ALLOW" "key" "keys") in allow lists"
upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }
CAPTURE=1; CAP=""
# The first 1,000 get their place in line, above either header.
if [ -n "$RANK" ]; then
  wrap "You're AI builder #$(commas "$RANK") to run Blindspot. One of the first 1,000." 4 "  ${GOLD}★${RST} " "    " "$B"; blank
elif [ "$EARLY" -eq 1 ]; then
  wrap "You're one of the first 1,000 people to run Blindspot." 4 "  ${GOLD}★${RST} " "    " "$B"; blank
fi
if [ "$LITELLM_HIT" -eq 1 ]; then
  emit "  ${SEV}▌${RST} ${B}ACT NOW: SIGNS OF THE LITELLM 1.107.0 MALWARE${RST}"
  if [ -n "$PCT_TXT" ]; then emit "  ${SEV}▌${RST} ${B}${PCT_TXT}.${RST} ${FIXN}."; else emit "  ${SEV}▌${RST} ${FIXN}."; fi
elif [ -n "$PCT_TXT" ]; then
  emit "  ${SEV}▌${RST} ${B}$(upper "$PCT_TXT")${RST}"
  emit "  ${SEV}▌${RST} ${FIXN}."
else
  emit "  ${SEV}▌${RST} ${B}$(upper "$FIXN")${RST}"
fi
HEAD_SHORT=$CAP; CAP=""
wrap "$STATS" 4 "  ${SEV}▌${RST} " "  ${SEV}▌${RST} " "$DIM"
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

SEC1=$CAP; CAP=""
section 02 "MCP SERVERS" "$(plural "$N_MCP" server servers)"
if [ "$N_MCP" -eq 0 ] && [ "$N_MCP_TOKEN" -eq 0 ]; then emit "     No MCP servers configured."; fi
while IFS='|' read -r who f c tok pl; do
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

SEC2=$CAP; CAP=""
section 03 "KEYS IN PLAIN TEXT" "$(plural "$KEY_FILES" file files)"
if [ "$KEY_FILES" -eq 0 ]; then
  wrap "No AI or cloud keys in shell profiles, history, agent configs or .env files." 8 "     ${GRN}✓${RST}  " "        "
fi
_shown=0
while IFS='|' read -r f p; do
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

SEC3=$CAP; CAP=""
section 04 "KEYS IN CLAUDE CODE ALLOW LISTS" "$(plural "$N_ALLOW" file files)"
if [ "$N_ALLOW" -eq 0 ]; then emit "     ${GRN}✓${RST}  No saved commands with keys."; fi
while IFS='|' read -r f npm; do
  [ -n "$f" ] || continue
  emit "     ${RED}✗${RST}  $(short "$f")"
  emit "        A saved command contains a key."
  [ "$npm" = 1 ] && wrap "An npm publish from this folder would include it." 8 "        " "        " "$RED"
done <<EOF
$ALLOW_ROWS
EOF

SEC4=$CAP; CAP=""
section 05 "THIS WEEK'S KEY LEAKS" "3 checked"
if [ "$LITELLM_HIT" -eq 1 ]; then
  pair "${RED}✗${RST}" "LiteLLM 1.107.0" 16 "${RED}signs of the malware found${RST}"
  while IFS= read -r l; do
    [ -n "$l" ] && emit "        $(short "$l")"
  done <<EOF
$LITE_BAD$MARKS
EOF
  [ "$LOADER" -eq 1 ] && emit "        ${RED}A process holds the loader lock. The backdoor may be running now.${RST}"
  wrap "Don't run Python or pip in these environments. Advisory: docs.litellm.ai/blog/security-incident-oct-21-2026" 8 "        " "        "
elif [ -n "$LITE_PYC" ]; then
  pair "${YEL}!${RST}" "LiteLLM 1.107.0" 16 "${YEL}possible leftover${RST}"
  while IFS= read -r l; do
    [ -n "$l" ] && emit "        $(short "$l")"
  done <<EOF
$LITE_PYC
EOF
  wrap "A compiled cook file stays behind when cook.py is deleted, which is what the 1.107.0 malware ships. If litellm 1.107.0 was ever installed here, treat this as a hit. Advisory: docs.litellm.ai/blog/security-incident-oct-21-2026" 8 "        " "        "
else
  pair "${GRN}✓${RST}" "LiteLLM 1.107.0" 16 "no signs in $(plural "$N_PY" "Python environment" "Python environments")"
  [ "$N_LITE" -gt 0 ] && emit "                          ${DIM}installed: $LITE_VERS${RST}"
fi
[ -n "$UV_BAD" ] && wrap "Your uv cache holds the 1.107.0 package. Clear it with: uv cache clean litellm" 8 "        " "        " "$YEL"
if [ "$OC" -eq 1 ]; then
  pair "${YEL}!${RST}" "OpenCode" 16 "installed"
  wrap "If you used OpenCode Console, the hosted gateway, rotate every provider key you saved there. Keys kept only in the CLI were not affected." 26 "                          " "                          " "$DIM"
else
  pair "${DIM}·${RST}" "OpenCode" 16 "${DIM}not installed${RST}"
fi
if [ "$RW" -eq 1 ]; then
  pair "${YEL}!${RST}" "Railway" 16 "CLI found"
  wrap "Railway asked every customer to rotate all secrets stored on the platform and to check their logs." 26 "                          " "                          " "$DIM"
else
  pair "${DIM}·${RST}" "Railway" 16 "${DIM}CLI not found${RST}"
fi
if [ "$ZB" -eq 1 ]; then
  pair "${YEL}!${RST}" "Zeabur" 16 "CLI found"
  wrap "Zeabur said on 15 October that attackers read service environment variables stored on the platform, and asked every customer to replace all of them. Revoke each key at its provider first." 26 "                          " "                          " "$DIM"
else
  pair "${DIM}·${RST}" "Zeabur" 16 "${DIM}CLI not found${RST}"
fi

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
  elif [ "$LITELLM_HIT" -eq 1 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found signs of the LiteLLM malware. It can't tell you what the malware already took, or what your agents do after you close this window."
  elif [ "$N_IDLE" -gt 0 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="$(plural "$N_IDLE" "agent you haven't used in 30 days is" "agents you haven't used in 30 days are") still installed. A poisoned package can drive an installed agent, and nothing on your Mac would tell you."
  elif [ "$ISSUES" -gt 0 ]; then
    _t="THIS SCAN IS A SNAPSHOT"
    _p1="It found $(plural "$ISSUES" "thing" "things") to fix. It can't tell you whether an agent already used what it found, or what your agents do after you close this window."
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
if [ "$N_AG" -eq 0 ]; then G1="${DIM}·${RST}"; D1="none found"
elif [ "$N_IDLE" -gt 0 ]; then G1="${YEL}○${RST}"; D1="$N_AG found, $N_IDLE idle: $(first_names "$IDLE_NAMES" 2)"
else G1="${GRN}✓${RST}"; D1="$N_AG found, all used in the last 30 days"; fi
if [ "$N_MCP_TOKEN" -gt 1 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, tokens in $N_MCP_TOKEN files, like $(short "$MCP_TOK_FIRST")"
elif [ "$N_MCP_TOKEN" -eq 1 ]; then G2="${RED}✗${RST}"; D2="$MCP_SUM, a token in $(short "$MCP_TOK_FIRST")"
elif [ -n "$MCP_ROWS" ]; then G2="${GRN}✓${RST}"; D2="$MCP_SUM, no tokens in their configs"
else G2="${GRN}✓${RST}"; D2="none configured"; fi
if [ "$KEY_FILES" -gt 1 ]; then G3="${RED}✗${RST}"; D3="$KEY_FILES files, like $(short "${KEY_FIRST%%|*}") (${KEY_FIRST#*|})"
elif [ "$KEY_FILES" -eq 1 ]; then G3="${RED}✗${RST}"; D3="$(short "${KEY_FIRST%%|*}") holds ${KEY_FIRST#*|} keys"
elif [ "$N_SSH_OPEN" -gt 0 ]; then G3="${YEL}○${RST}"; D3="none in plain text, but $(plural "$N_SSH_OPEN" "SSH key has" "SSH keys have") no passphrase"
else G3="${GRN}✓${RST}"; D3="no AI or cloud keys in plain text"; fi
if [ "$N_ALLOW" -eq 0 ]; then G4="${GRN}✓${RST}"; D4="no saved commands with keys"
elif [ "$N_ALLOW_NPM" -gt 0 ] && [ "$N_ALLOW" -eq 1 ]; then G4="${RED}✗${RST}"; D4="1 saved key, and an npm publish would ship it"
elif [ "$N_ALLOW_NPM" -gt 0 ]; then G4="${RED}✗${RST}"; D4="$N_ALLOW saved keys, $N_ALLOW_NPM that an npm publish would ship"
elif [ "$N_ALLOW" -eq 1 ]; then G4="${RED}✗${RST}"; D4="a saved key in $(short "$ALLOW_FIRST")"
else G4="${RED}✗${RST}"; D4="saved keys in $N_ALLOW files"; fi
if [ "$LITELLM_HIT" -eq 1 ]; then G5="${RED}✗${RST}"; D5="signs of the LiteLLM malware. Act now"
elif [ -n "$LITE_PYC" ]; then G5="${YEL}!${RST}"; D5="possible LiteLLM leftover: check cook.pyc"
elif [ $((OC + RW + ZB)) -ge 2 ]; then
  G5="${YEL}!${RST}"; _l=""; _n=$((OC + RW + ZB)); _i=0
  for _p in "OpenCode:$OC" "Railway:$RW" "Zeabur:$ZB"; do
    [ "${_p#*:}" -eq 1 ] || continue
    _i=$((_i + 1)); if [ "$_i" -eq 1 ]; then _l=${_p%:*}; elif [ "$_i" -eq "$_n" ]; then _l="$_l and ${_p%:*}"; else _l="$_l, ${_p%:*}"; fi
  done
  if [ "$_n" -eq 3 ]; then D5="$_l found: rotate keys"; else D5="$_l found: rotate their keys"; fi
elif [ "$OC" -eq 1 ]; then G5="${YEL}!${RST}"; D5="OpenCode found: used its Console? Rotate keys"
elif [ "$RW" -eq 1 ]; then G5="${YEL}!${RST}"; D5="Railway CLI found: rotate secrets stored there"
elif [ "$ZB" -eq 1 ]; then G5="${YEL}!${RST}"; D5="Zeabur CLI found: rotate secrets stored there"
else G5="${GRN}✓${RST}"; D5="no LiteLLM, OpenCode, Railway or Zeabur leaks"; fi
blank
cline 01 "$G1" "Coding agents" "$D1"
cline 02 "$G2" "MCP servers" "$D2"
cline 03 "$G3" "Keys in plain text" "$D3"
cline 04 "$G4" "Allow lists" "$D4"
cline 05 "$G5" "This week's leaks" "$D5"
if [ "$ISSUES" -gt 0 ]; then
  blank
  wrap "$(printf '%s' "$TODO" | head -n 1)" 14 "   ${B}First fix:${RST} " "              "
fi
# Argus in two lines, with the same claims as the full report.
if [ "$OS" = Darwin ]; then
  if [ "$ARCH" = arm64 ]; then _how="Free for individuals: gird.ai/argus/download"
  else _how="It runs on Apple Silicon Macs today: gird.ai/argus/download"; fi
  if [ "$LITELLM_HIT" -eq 1 ] || [ "$KEY_FILES" -gt 0 ]; then _lead="This scan is a snapshot."
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
SUMMARY=$CAP; CAP=""; CAPTURE=0

REPORT="$REPORT$HEAD_FULL$SEC1$SEC2$SEC3$SEC4$SEC5$SEC_TODO$SEC_ARGUS$SEC_FOOT"
if [ "$COMPACT" -eq 1 ]; then printf '%s' "$HEAD_SHORT$SUMMARY"
else printf '%s' "$HEAD_FULL$SEC1$SEC2$SEC3$SEC4$SEC5$SEC_TODO$SEC_ARGUS$SEC_FOOT"; fi

# ---------------------------------------------------------------------------
# What next: the certificate first, then details, save and Argus. One key each,
# nothing happens unasked.
# ---------------------------------------------------------------------------
# u is the run ID, so a share from the certificate can be matched to its run, r the
# early rank, sk the SSH private keys and hk the shell history files with keys.
card_url() {
  printf '%s/blindspot/card/#v=2&s=%s&g=%s&a=%s&i=%s&m=%s&mt=%s&k=%s&p=%s&al=%s&an=%s&ll=%s&lf=%s&sp=%s&d=%s&pc=%s&pn=%s&u=%s&r=%s&sk=%s&hk=%s&ag=%s' \
    "$WEB" "$SCORE" "$GRADE" "$N_AG" "$N_IDLE" "$N_MCP" "$N_MCP_TOKEN" "$KEY_FILES" "$(printf '%s' "$PROV_IDS" | tr ' ' '.')" \
    "$N_ALLOW" "$N_ALLOW_NPM" "$LITELLM_HIT" "$N_LOGIN" "$N_SSH_OPEN" "$(date +%Y-%m-%d)" "$PCT" "$PCT_N" \
    "$LINK_RUN_ID" "$RANK" "$N_SSH" "$HIST_KEYS" "$(printf '%s' "$AGENT_IDS" | tr ' ' '.')"
}
open_url() {
  [ -n "${GIRD_CHECK_NO_OPEN:-}" ] && return 1
  if [ "$OS" = Darwin ] && command -v open >/dev/null 2>&1; then open "$1" >/dev/null 2>&1 && return 0; fi
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
  if [ -n "$PCT" ]; then HERO="Press ENTER to see how you rank and get your AI Exposure Check"
  else HERO="Press ENTER to get your AI Exposure Check"; fi
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
