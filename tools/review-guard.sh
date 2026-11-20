#!/usr/bin/env bash
# Lists what in a pull request needs a maintainer's look before it merges, by fixed rules that read
# the diff as data and run nothing from it. CONTRIBUTING.md "Security review" is what it enforces.
#
#   bash tools/review-guard.sh BASE HEAD
#
# Reads `git diff BASE...HEAD`: the lines HEAD adds or removes since it left BASE, and the paths it
# changes. Exit 0: nothing found. Exit 1: findings, one per line. Exit 2: it could not check.
#
# The rules match text, so they flag lines that look like what they name; quoting or splitting a
# word (e\val, c''url) gets past them, which is why the review checklist still applies. A file is
# "data" when it is *.md, *.txt, data/*.tsv, LICENSE or NOTICE; any other file is code, so a kind
# of file this list does not know is held to the code rules.
#   hidden    in *.ps1, an added byte that is not printable ASCII, space or tab; in any other file,
#             a control character (CR included), an invisible or direction-changing character, or
#             bytes that are not UTF-8; in any file, a NUL byte; a changed path with a byte that is
#             not printable ASCII; a binary file, unless it is a png, jpg, gif or webp image under
#             docs/ whose first bytes are that kind of image; a file named as an image that is not
#             one; a symbolic link or a submodule
#   mode      a file whose mode changed, such as one made executable
#   run       in code, an added line that runs text as code: eval and its kin; a shell, interpreter
#             or trap given text built from a variable (sh -c "$x", su -c "$x", PowerShell
#             -Command "$x", cmd /c "$x"); a here-string or heredoc into a shell, or /dev/stdin;
#             PowerShell reading its code from stdin or -EncodedCommand; a pipe into a shell; a
#             decoder; outside tests/ a shell running a script a variable names (see RUN_SH,
#             SHELL_FILE, PSRUN and RUN_PS below); any inline interpreter code (python -c, perl
#             -e). A shell or interpreter counts wherever its name starts a word, so after sudo,
#             timeout or nohup too, and a tool counts with its folder (/bin/sh) or .exe. A line that
#             is only a # comment is skipped, unless it holds $( ${ or a backtick: inside a heredoc
#             or a here-string such a line runs. In *.ps1, & on a variable is flagged unless the
#             file assigns that variable a { script block }; & on an expression, a string with a
#             variable in it or $env: is always flagged, and so are assigning Get-Command,
#             [Diagnostics.Process]::Start and Import-Module given a variable. Running or sourcing
#             a file named as data or an image (sh docs/x.png, . notes.txt) is flagged too.
#   network   in code, an added line that names a network tool where a command starts (after
#             sudo, timeout, env and the like too, and with its folder or .exe), or a network API
#             (NET_SH and NET_PS below), comments included; and an http(s) URL in a line
#             that is not only a # comment, in any code but tests/ and the blocks tools/gen.sh
#             writes from data/: a URL in a test is fixture data, and a test that calls out is
#             caught by the tool it calls with. In *.md, a network tool in a fenced code block,
#             since people run a doc's commands.
#   shrink    a removed line in data/*.tsv, other than a # comment or a blank line
#   protected a change under .github/, to a .gitattributes or .gitmodules file, to this guard, its
#             decision script or its tests, or, at any depth, to what an AI coding agent, editor or
#             shell opening this repository reads or runs: anything under .claude/ .codex/ .cursor/
#             .gemini/ .windsurf/ .vscode/ .devcontainer/ .roo/ .kiro/ .zed/ .idea/ .clinerules/,
#             and any file named .mcp.json, AGENTS.md, CLAUDE.md, GEMINI.md, .cursorrules,
#             .clinerules, .envrc or .pre-commit-config.yaml
# *.ps1 lines are matched without case, as PowerShell reads them; other code with case.
set -u
export LC_ALL=C
cd "$(dirname "$0")/.." || exit 2

usage() { echo "usage: bash tools/review-guard.sh BASE HEAD" >&2; exit 2; }
[ $# -eq 2 ] || usage
case "$1" in -*) usage ;; esac
case "$2" in -*) usage ;; esac
BASE=$(git rev-parse --verify -q "$1^{commit}") || { echo "review-guard: not a commit: $1" >&2; exit 2; }
HEAD=$(git rev-parse --verify -q "$2^{commit}") || { echo "review-guard: not a commit: $2" >&2; exit 2; }
git merge-base "$BASE" "$HEAD" > /dev/null 2>&1 || { echo "review-guard: $1 and $2 share no history" >&2; exit 2; }

W=$(mktemp -d 2>/dev/null || mktemp -d -t review-guard) || exit 2
trap 'rm -rf "$W"' EXIT
FOUND=0
TAB=$(printf '\t')

# Diff options that keep local config and helper programs from changing what is read.
DIFF="diff --no-color --no-ext-diff --no-textconv --no-renames --no-relative --ignore-submodules=none"

# Prints text with every byte outside printable ASCII made visible (cat -v), so a finding cannot
# hide what it shows or start a line the CI log reads as a command.
vis() { printf '%s' "$1" | tr '\n' '\001' | cat -v | cut -c1-240; }
finding() { # rule path line text
  FOUND=1
  printf '%s: %s:%s: %s\n' "$1" "$(vis "$2")" "$3" "$(vis "$4")"
}

# Byte patterns for UTF-8 characters that are invisible or change text direction: C1 controls, soft
# hyphen, Arabic letter mark, Mongolian vowel separator, Hangul fillers, zero-width and direction
# marks, line and paragraph separators, embeddings and overrides, word joiner and isolates,
# variation selectors, the byte order mark, and tag characters.
o() { printf "$1"; }
BAD_UTF8="$(o '\302')[$(o '\200')-$(o '\237')$(o '\255')]|$(o '\330\234')|$(o '\341\240\216')"
BAD_UTF8="$BAD_UTF8|$(o '\341\205')[$(o '\237\240')]|$(o '\343\205\244')|$(o '\357\276\240')"
BAD_UTF8="$BAD_UTF8|$(o '\342\200')[$(o '\213')-$(o '\217')$(o '\250')-$(o '\256')]|$(o '\342\201')[$(o '\240')-$(o '\257')]"
BAD_UTF8="$BAD_UTF8|$(o '\357\270')[$(o '\200')-$(o '\217')]|$(o '\357\273\277')|$(o '\363\240')[$(o '\200')-$(o '\207')]"

B='(^|[^A-Za-z0-9_-])'   # word start
E='([^A-Za-z0-9_-]|$)'   # word end
# A tool may be named with its folder (/usr/bin/curl; in *.ps1 C:\Windows\System32\curl.exe too)
# and .exe.
P='([^[:space:];|&<>]*/)?'
PW='([^[:space:];|&<>]*[/\\])?'
X='(\.exe)?'
# Words that run the command after them, with options of their own (sudo -n -u "$u" curl ...).
WRAP='(sudo|doas|su|runuser|timeout|nohup|nice|ionice|stdbuf|setsid|caffeinate|chrt|taskset|chroot|unbuffer|env)'
# Where a command starts: a line's start, after ; & | ( { ` = # ! or a keyword, or inside the
# quotes of a -c or -e (bash -c 'curl ...'); then any NAME=value words, and any word of WRAP with
# the words after it.
START='(^[[:space:]]*|[;&|({`=#!][[:space:]]*|(then|do|else|if|while|until|exec|command|sudo|xargs|time)[[:space:]]+|[[:space:]]-[A-Za-z]*[ceE][[:space:]]+['"'"'"][[:space:]]*)'
PRE="(($P$WRAP([[:space:]]+[^[:space:];|&]+)*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+)*"
CMD="$START$PRE$P"
CMDW="$START$PRE$PW"
# Network tools in bash and other code also start after any quote: a quoted command is often run.
QSTART='(^[[:space:]]*|[;&|({`=#!'"'"'"][[:space:]]*|(then|do|else|if|while|until|exec|command|sudo|xargs|time)[[:space:]]+)'
QCMD="$QSTART$PRE$P"
SHELLS='(ba|z|k|da)?sh|pwsh|powershell'
VAR='("[^"]*)?[$`]'   # text that expands a variable or a command
# A shell handed text to run, matched wherever its name starts a word (after sudo, timeout, nohup,
# su and the like too): -c with a variable, a here-string or heredoc, or /dev/stdin; su -c with a
# variable; sourcing a path built from a variable, or /dev/stdin.
SHRUN="$B$P($SHELLS)$X([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*c[[:space:]]+$VAR"
SHRUN="$SHRUN|$B$P($SHELLS)$X([[:space:]]+-[A-Za-z-]*)*[[:space:]]*(<<|/dev/(stdin|fd/))"
SHRUN="$SHRUN|${B}(su|runuser)[[:space:]].*[[:space:]](-[A-Za-z]*c|--command)[[:space:]=]+$VAR"
SHRUN="$SHRUN|$CMD(source|\.)[[:space:]]+[^[:space:];|&]*([\$(\`]|/dev/(stdin|fd/))"
RUN_SH="${B}eval$E|$SHRUN"
# A shell running a script a variable names. Not read in tests/, which run the scripts under test
# that way (bash "$SCRIPT").
SHELL_FILE="$CMD($SHELLS)$X([[:space:]]+-[A-Za-z]+)*[[:space:]]+(<[[:space:]]*)?$VAR"
INLINE="$B$P(python[0-9.]*|perl|ruby|node|php|osascript)$X([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*[ceE][[:space:]]"
RUN_SH="$RUN_SH|$INLINE+$VAR|${CMD}osascript$X$E"
RUN_SH="$RUN_SH|${B}trap[[:space:]]+$VAR"
RUN_SH="$RUN_SH|${B}system[[:space:]]*\(|\|[[:space:]]*getline|${B}exec\(|os\.(system|popen)|shell[[:space:]]*=[[:space:]]*True"
# Read without case, in every kind of code (gird-check.sh runs in Git Bash, where PowerShell and
# cmd are a command away): PowerShell given text (-Command with a variable, -Command - or -File -
# to read stdin, -EncodedCommand), and cmd /c with a variable.
PSRUN="${B}(pwsh|powershell)$X$E.*[[:space:]]-c(o(m(m(a(n(d)?)?)?)?)?)?[[:space:]]+($VAR|-([[:space:]]|$))"
PSRUN="$PSRUN|${B}(pwsh|powershell)$X$E.*[[:space:]]-f(i(l(e)?)?)?[[:space:]]+-([[:space:]]|$)"
PSRUN="$PSRUN|${B}(pwsh|powershell)$X$E.*[[:space:]]-(ec|e(n(c(o(d(e(d(c(o(m(m(a(n(d)?)?)?)?)?)?)?)?)?)?)?)?)?)$E"
PSRUN="$PSRUN|$B${P}cmd$X([[:space:]]+/{1,2}[a-z]+)*[[:space:]]+/{1,2}[ckr]([[:space:]].*)?[$\`]"
# Running or sourcing a file named as data (*.md, *.txt, *.tsv) or an image: none of them is code.
DATARUN="$CMD(source|\.|$SHELLS|python[0-9.]*|perl|ruby|node|php|osascript)$X([[:space:]]+-[A-Za-z]+)*[[:space:]]+(<[[:space:]]*)?[\"']?[^[:space:];|&<>\"']*\.(md|txt|tsv|png|jpe?g|gif|webp)([\"'[:space:];|&)]|$)"
# A pipe into a shell or cmd, and a decoder: read on the whole line, quotes included, in tests/ too.
PIPE="(^|[[:space:]])\|[[:space:]]*$P($SHELLS|cmd)$X([[:space:];&)\"'\\\`]|$)"
PIPE="$PIPE|${B}base64([[:space:]]+-[A-Za-z-]+)*[[:space:]]+(-[A-Za-z]*[dD][A-Za-z]*|--decode)$E|${B}xxd([[:space:]]+-[A-Za-z]+)*[[:space:]]+-r"
RUN_PS="${B}(invoke-expression|iex|invoke-command|start-process|add-type)$E|scriptblock\][[:space:]]*::[[:space:]]*create"
RUN_PS="$RUN_PS|newscriptblock|invokescript|invokecommand|reflection\.assembly\][[:space:]]*::[[:space:]]*load|\.invoke[[:space:]]*\("
RUN_PS="$RUN_PS|=[[:space:]]*(get-command|gcm)$E|frombase64string|(^|[;({=[:space:]])&[[:space:]]*(\(|\"[^\"]*[$]|[$]env:)|$CMD\.[[:space:]]+[\$(]"
RUN_PS="$RUN_PS|process\][[:space:]]*::[[:space:]]*start|processstartinfo|${B}(import-module|ipmo)([[:space:]]+-[a-z]+)*[[:space:]]+\"?[\$(]"
# A network tool where a command starts (after # too, so a commented-out call is still seen),
# followed by an argument rather than an =.
ARG='([[:space:]]+[^=[:space:]]|[[:space:]]*$)'
NET_SH="$QCMD(curl|wget|nc|ncat|netcat|socat|telnet|ssh|scp|sftp|rsync|ftp|tftp|nslookup|dig|host|drill|certutil|bitsadmin)$X$ARG"
NET_SH="$NET_SH|${B}openssl[[:space:]]+s_client|/dev/(tcp|udp)/|/inet/|urlopen|urllib\.request|http\.client|${B}requests\.(get|post|put|patch|delete|head|request|Session)[[:space:]]*\("
NET_SH="$NET_SH|${B}socket\.(socket|create_connection)|IO::Socket|LWP::|HTTP::Tiny"
NET_PS="$CMDW(curl|wget|irm|iwr|ssh|scp|sftp|nslookup|certutil|bitsadmin)$X$ARG|${B}(invoke-webrequest|invoke-restmethod|start-bitstransfer|resolve-dnsname|test-netconnection)$E"
NET_PS="$NET_PS|webclient|httpclient|webrequest\]|downloadstring|downloadfile|tcpclient|udpclient|net\.dns|net\.sockets"
URL='https?://'

is_data() {
  case "$1" in
    *.md|*.txt|LICENSE|NOTICE) return 0 ;;
    data/*/*) return 1 ;;
    data/*.tsv) return 0 ;;
  esac
  return 1
}
# Compared lowercased: a case-insensitive file system opens .Claude/ as .claude/.
is_protected() {
  case "/$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    /.github/*|*/.gitattributes|/.gitmodules|/tools/review-guard.sh|/tools/review-guard-decide.sh|/tests/review-guard.sh) return 0 ;;
    */.claude/*|*/.codex/*|*/.cursor/*|*/.gemini/*|*/.windsurf/*|*/.vscode/*|*/.devcontainer/*) return 0 ;;
    */.roo/*|*/.kiro/*|*/.zed/*|*/.idea/*|*/.clinerules/*) return 0 ;;
    */.mcp.json|*/agents.md|*/claude.md|*/gemini.md|*/.cursorrules|*/.clinerules|*/.envrc|*/.pre-commit-config.yaml) return 0 ;;
  esac
  return 1
}

# One record per changed path: ":oldmode newmode oldsha newsha status" NUL path NUL.
git $DIFF --raw -z "$BASE...$HEAD" > "$W/raw" || { echo "review-guard: git diff failed" >&2; exit 2; }
git $DIFF --numstat -z "$BASE...$HEAD" > "$W/num" || { echo "review-guard: git diff failed" >&2; exit 2; }
# Paths git counts as binary (numstat shows - - for them).
: > "$W/binary"
while IFS= read -r -d '' rec; do
  case "$rec" in "-$TAB-$TAB"*) printf '%s\0' "${rec#-"$TAB"-"$TAB"}" >> "$W/binary" ;; esac
done < "$W/num"
# rule NAME PATTERN FILE [GREP-FLAG]: one finding for each "number<TAB>text" line of FILE whose
# text matches PATTERN (an ERE; ^ is the start of the text). A line already found by NAME in this
# file is not listed again.
rule() {
  cut -f2- "$3" > "$W/text"
  grep -an ${4:-} -E -- "$2" "$W/text" | cut -d: -f1 > "$W/hits"
  [ -s "$W/hits" ] || return 0
  awk 'NR == FNR { want[$1] = 1; next } want[FNR]' "$W/hits" "$3" > "$W/hitlines"
  while IFS= read -r l; do
    grep -qxF -- "$1 ${l%%"$TAB"*}" "$W/seen" && continue
    printf '%s\n' "$1 ${l%%"$TAB"*}" >> "$W/seen"
    finding "$1" "$path" "${l%%"$TAB"*}" "${l#*"$TAB"}"
  done < "$W/hitlines"
}
# fixtures IN OUT: IN's lines, with single-quoted text left out of each line that writes a fixture.
fixtures() {
  awk -v T="$TAB" '
    { i = index($0, T); t = substr($0, i + 1) }
    t !~ /(^[[:space:]]*|[;&|{][[:space:]]*)(printf|echo|cat|mv_case)[[:space:]]/ ||
    t ~ /((ba|z|k|da)?sh|pwsh|powershell|python[0-9.]*|perl|ruby|node|php|osascript)([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*[ceE][[:space:]]/ { print; next }
    {
      out = substr($0, 1, i); q = ""
      for (k = i + 1; k <= length($0); k++) {
        c = substr($0, k, 1)
        if (q == "\047") { if (c == "\047") q = ""; continue }
        if (c == "\\") { out = out c substr($0, k + 1, 1); k++; continue }
        if (c == "\"") q = (q == "\"") ? "" : "\""
        else if (c == "\047" && q == "") { q = "\047"; out = out "\047\047"; continue }
        out = out c
      }
      print out
    }' "$1" > "$2"
}
# call_operator: in a *.ps1, a run finding for each & $name whose name the file never assigns a
# { script block } (variable names are compared without case and without a scope: prefix).
call_operator() {
  grep -aiE '(^|[;({=[:space:]])&[[:space:]]*[$][A-Za-z_]' "$W/code-run" > "$W/amp" || return 0
  git show "$HEAD:$path" 2>/dev/null | tr 'A-Z' 'a-z' |
    grep -aoE '[$]((script|global|local|private):)?[a-z_][a-z0-9_]*[[:space:]]*=[[:space:]]*[{]' |
    sed -E 's/^[$]((script|global|local|private):)?([a-z_][a-z0-9_]*).*/\3/' > "$W/blocks"
  while IFS= read -r l; do
    printf '%s\n' "${l#*"$TAB"}" | tr 'A-Z' 'a-z' |
      grep -oE '(^|[;({=[:space:]])&[[:space:]]*[$][a-z_][a-z0-9_:]*' |
      sed -E 's/^.*&[[:space:]]*[$]((script|global|local|private):)?//' > "$W/called"
    while IFS= read -r n; do
      grep -qxF -- "$n" "$W/blocks" || { finding run "$path" "${l%%"$TAB"*}" "${l#*"$TAB"}"; break; }
    done < "$W/called"
  done < "$W/amp"
}
is_binary() { tr '\0' '\n' < "$W/binary" | grep -qxF -- "$1"; }
is_image() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in docs/*.png|docs/*.jpg|docs/*.jpeg|docs/*.gif|docs/*.webp) return 0 ;; esac
  return 1
}
# image_ok PATH: HEAD's copy of PATH starts with the bytes of the image kind its name says.
image_ok() {
  _m=$(git cat-file blob "$HEAD:$1" 2>/dev/null | head -c 12 | od -An -tx1 | tr -d ' \n')
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    *.png) case $_m in 89504e470d0a1a0a*) return 0 ;; esac ;;
    *.jpg|*.jpeg) case $_m in ffd8ff*) return 0 ;; esac ;;
    *.gif) case $_m in 474946383761*|474946383961*) return 0 ;; esac ;;
    *.webp) case $_m in 52494646????????57454250) return 0 ;; esac ;;
  esac
  return 1
}
# fences: "number<TAB>sh" or "number<TAB>ps" for each line of HEAD's PATH inside a fenced code
# block (``` or ~~~), ps when the block is marked powershell, pwsh, ps or ps1.
fences() {
  git show "$HEAD:$1" 2>/dev/null | awk -v T="$TAB" '
    !f && match($0, /^[[:space:]]*(```+|~~~+)/) {
      m = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", m); f = 1
      lang = tolower(substr($0, RSTART + RLENGTH)); gsub(/[^a-z0-9]/, "", lang)
      ps = (lang ~ /^(powershell|pwsh|ps|ps1)$/); next
    }
    f { t = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
        if (length(t) >= length(m) && t ~ ("^" substr(m, 1, 1) "+$")) { f = 0; next }
        print NR T (ps ? "ps" : "sh") }'
}

N=0
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  N=$((N + 1)); : > "$W/seen"
  set -- $meta
  newmode=$2; oldmode=${1#:}; status=$5
  if [ -n "$(printf '%s' "$path" | tr -d ' -~')" ]; then finding hidden "$path" 0 "a byte in the file name that is not printable ASCII"; fi
  if is_protected "$path"; then finding protected "$path" 0 "a change to a protected path"; fi
  case "$newmode$oldmode" in
    *120000*) finding hidden "$path" 0 "a symbolic link"; continue ;;
    *160000*) finding hidden "$path" 0 "a submodule"; continue ;;
  esac
  if [ "$oldmode" != 000000 ] && [ "$newmode" != 000000 ] && [ "$oldmode" != "$newmode" ]; then
    finding mode "$path" 0 "mode $oldmode to $newmode"
  fi
  # A binary file is never read, so only an image under docs/ whose first bytes are that kind of
  # image passes; a file named as an image that git reads as text is not one.
  if is_binary "$path"; then
    if [ "$status" != D ]; then
      if ! is_image "$path"; then finding hidden "$path" 0 "a binary file"
      elif ! image_ok "$path"; then finding hidden "$path" 0 "a binary file that does not start as the image its name says"; fi
    fi
    continue
  fi
  case "$(printf '%s' "$path" | tr 'A-Z' 'a-z')" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp) [ "$status" = D ] || image_ok "$path" || finding hidden "$path" 0 "a file named as an image that is not one" ;;
  esac
  [ "$status" = D ] && ! { case "$path" in data/*.tsv) true ;; *) false ;; esac; } && continue

  # Each added line as "+<TAB>number<TAB>text", each removed line as "-<TAB>number<TAB>text".
  # The ---/+++ file header comes only before the first @@, so an added line that starts with ++ is
  # still read as a line.
  git $DIFF --text -U0 "$BASE...$HEAD" -- ":(literal)$path" > "$W/d0" || { echo "review-guard: git diff failed on a file" >&2; exit 2; }
  # git reads a file as text when its first 8000 bytes hold no NUL. bash drops a NUL and runs the
  # rest (ev<NUL>al is eval), and grep and awk may stop at one, so a NUL is flagged and read from
  # here on as ^A, which the hidden rule shows on its line.
  tr '\000' '\001' < "$W/d0" > "$W/d"
  cmp -s "$W/d0" "$W/d" || finding hidden "$path" 0 "a NUL byte, shown as ^A on its line"
  awk -v T="$TAB" '
    /^@@ / { h = 1; split($0, a, " "); o = a[2]; n = a[3]; sub(/^-/, "", o); sub(/^\+/, "", n); sub(/,.*/, "", o); sub(/,.*/, "", n); next }
    !h { next }
    /^\+/ { print "+" T n T substr($0, 2); n++; next }
    /^-/  { print "-" T o T substr($0, 2); o++; next }
  ' "$W/d" > "$W/lines"
  grep -a "^+$TAB" "$W/lines" | cut -f2- > "$W/add"
  grep -a "^-$TAB" "$W/lines" | cut -f2- > "$W/del"

  case "$path" in
    *.ps1|*.psm1|*.psd1) ps=1; rule hidden "[^[:print:]$TAB]" "$W/add" ;;
    *)
      ps=0
      rule hidden "[$(o '\001')-$(o '\010')$(o '\013')-$(o '\037')$(o '\177')]|$BAD_UTF8" "$W/add"
      # One iconv for the file; only when it fails, one per non-ASCII line, to name the lines.
      grep -a "[^ -~$TAB]" "$W/add" > "$W/nonascii"
      if [ -s "$W/nonascii" ] && ! cut -f2- "$W/nonascii" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1; then
        while IFS= read -r l; do
          printf '%s\n' "${l#*"$TAB"}" | iconv -f UTF-8 -t UTF-8 > /dev/null 2>&1 || finding hidden "$path" "${l%%"$TAB"*}" "${l#*"$TAB"}"
        done < "$W/nonascii"
      fi
      ;;
  esac
  if ! is_data "$path"; then
    # A line that is only a # comment is skipped, unless it holds $( ${ or a backtick: inside a
    # heredoc or a PowerShell here-string such a line is not a comment, and runs.
    awk -v T="$TAB" '{ t = substr($0, index($0, T) + 1) } t ~ /^[[:space:]]*#/ && t !~ /[$][({]|`/ { next } { print }' "$W/add" > "$W/code"
    # Tests write shell profiles, hooks and configs as fixtures: on a line that writes one (printf,
    # echo, cat or mv_case) and hands no text to a shell or interpreter, single-quoted text is
    # left out before the run rule reads it. The pipe and decoder rules and the network rule read
    # the whole line: tests run their scripts as bash "$VAR", so a fixture that downloads, or
    # decodes text into a shell, is the only place to catch it.
    # A line is read on its own, so one inside a quoted string that spans lines is not seen as such.
    case "$path" in
      tests/*) fixtures "$W/code" "$W/code-run" ;;
      *) cp "$W/code" "$W/code-run" ;;
    esac
    cp "$W/add" "$W/add-net"
    if [ "$ps" = 1 ]; then
      rule run "$RUN_PS|$PSRUN|$DATARUN" "$W/code-run" -i
      rule run "$PIPE" "$W/code" -i
      call_operator
      rule network "$NET_PS" "$W/add-net" -i
    else
      rule run "$RUN_SH" "$W/code-run"
      rule run "$PIPE" "$W/code"
      rule run "$INLINE" "$W/code-run"
      rule run "$PSRUN|$DATARUN" "$W/code-run" -i
      case "$path" in tests/*) ;; *) rule run "$SHELL_FILE" "$W/code-run" ;; esac
      rule network "$NET_SH" "$W/add-net"
    fi
    case "$path" in
      tests/*) ;;
      *)
        # Lines tools/gen.sh writes from data/ (between "# >>> NAME: generated from data/" and
        # "# <<< NAME") carry the data's source URLs; gen.sh --check holds them to the data files.
        { echo 0; git show "$HEAD:$path" 2>/dev/null | awk '
          /^[[:space:]]*# >>> [a-z-]+: generated from data\// { g = 1; next }
          /^[[:space:]]*# <<< / { g = 0 }
          g { print NR }'; } > "$W/gen"
        awk -F "$TAB" 'NR == FNR { gen[$1] = 1; next } !($1 in gen) && $2 !~ /^[[:space:]]*#/' "$W/gen" "$W/code" > "$W/code-own"
        rule network "$URL" "$W/code-own" -i ;;
    esac
  fi
  # A doc's commands are run by the people who read it: its fenced code gets the network rule.
  case "$path" in
    *.md)
      fences "$path" > "$W/fence"
      awk -F "$TAB" 'NR == FNR { if ($2 == "sh") k[$1] = 1; next } $1 in k' "$W/fence" "$W/add" > "$W/fence-sh"
      awk -F "$TAB" 'NR == FNR { if ($2 == "ps") k[$1] = 1; next } $1 in k' "$W/fence" "$W/add" > "$W/fence-ps"
      rule network "$NET_SH" "$W/fence-sh"
      rule network "$NET_PS" "$W/fence-ps" -i ;;
  esac
  case "$path" in
    data/*/*) ;;
    data/*.tsv) rule shrink "^[[:space:]]*[^#[:space:]]" "$W/del" ;;
  esac
done < "$W/raw"

[ "$N" -gt 0 ] || { echo "review-guard: no changes between $1 and $2"; exit 0; }
[ "$FOUND" -eq 0 ] || exit 1
echo "review-guard: $N changed files, nothing found"
exit 0
