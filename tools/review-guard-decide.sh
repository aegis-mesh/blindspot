#!/usr/bin/env bash
# Decides the review-guard check from the guard's exit code and the event that ran it. Reads no
# network and no pull request code: the owners come from the base branch's CODEOWNERS.
#
#   bash tools/review-guard-decide.sh GUARD-EXIT ACTION LABEL SENDER CODEOWNERS
#
# Exit 0 passes the check: the guard found nothing, or this run is the event of SENDER adding the
# security-reviewed label (ACTION labeled, LABEL security-reviewed) and SENDER is named as @SENDER
# on the * line of CODEOWNERS. Every other run with findings fails, so a label added before the
# latest push, or before any later event, never clears the commit this run checks.
set -u
[ $# -eq 5 ] || { echo "usage: bash tools/review-guard-decide.sh GUARD-EXIT ACTION LABEL SENDER CODEOWNERS" >&2; exit 2; }
RC=$1; ACTION=$2; LABEL=$3; SENDER=$4; OWNERS=$5
case "$RC" in
  0) echo "Nothing found."; exit 0 ;;
  1) ;;
  *) echo "The guard could not check this pull request (exit $RC)."; exit 1 ;;
esac
if [ "$ACTION" != labeled ] || [ "$LABEL" != security-reviewed ]; then
  echo "Findings. A code owner reviews them, then adds the security-reviewed label (remove it first if it is already there)."
  exit 1
fi
case "$SENDER" in
  ''|*[!A-Za-z0-9-]*) echo "security-reviewed was added by an account this check cannot read."; exit 1 ;;
esac
[ -f "$OWNERS" ] || { echo "No CODEOWNERS on the base branch: nobody can clear findings."; exit 1; }
# The last * line wins, as in GitHub's reading of the file. Teams (@org/team) and emails don't count.
owners=$(LC_ALL=C awk '
  { sub(/\r$/, ""); sub(/#.*/, "") }
  $1 == "*" { line = $0 }
  END {
    n = split(line, f, /[ \t]+/)
    for (i = 1; i <= n; i++) if (f[i] ~ /^@[A-Za-z0-9-]+$/) print tolower(substr(f[i], 2))
  }' "$OWNERS")
me=$(printf '%s' "$SENDER" | LC_ALL=C tr 'A-Z' 'a-z')
if printf '%s\n' "$owners" | grep -qxF -- "$me"; then
  echo "Findings cleared: $SENDER, a code owner, added security-reviewed."
  exit 0
fi
echo "security-reviewed was added by $SENDER, who is not a code owner on the * line of CODEOWNERS."
exit 1
