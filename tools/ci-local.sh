#!/usr/bin/env bash
# Runs the jobs in .github/workflows/ci.yml on this machine, one at a time, and prints each job's
# result. The two Ubuntu jobs run in a Linux container when `docker` answers, as an ordinary user, the
# way the CI runner does; without docker they are listed as skipped, and the run does not count as a
# full CI run. Logs are kept in a temp folder, named at the end.
#
#   PWSH=/path/to/pwsh bash tools/ci-local.sh
set -u
cd "$(dirname "$0")/.."
LOGS=$(mktemp -d "${TMPDIR:-/tmp}/blindspot-ci.XXXXXX")
FAILED=0; SKIPPED=0

job() { # name command...
  _n=$1; shift
  printf '  %-34s ' "$_n"
  "$@" > "$LOGS/$(printf '%s' "$_n" | tr -c 'A-Za-z0-9' '-').log" 2>&1
  _r=$?
  if [ "$_r" -eq 0 ]; then echo "pass"; else echo "FAIL (exit $_r)"; FAILED=1; fi
}
skip() { printf '  %-34s skipped: %s\n' "$1" "$2"; SKIPPED=1; }

shellcheck_run() {
  if command -v shellcheck >/dev/null 2>&1; then shellcheck -s bash -S warning gird-check.sh tests/*.sh
  else pipx run --spec shellcheck-py==0.10.0.1 shellcheck -s bash -S warning gird-check.sh tests/*.sh; fi
}
# The Ubuntu jobs: the repo mounted read-only, the tools the CI image has, run as a user, not root.
in_linux() { # image command
  docker run --rm -v "$PWD:/src:ro" "$1" bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null && apt-get install -y -qq python3 perl jq procps curl git expect file xxd ca-certificates >/dev/null &&
    useradd -m ci && su ci -c 'cd /src && $2'"
}

echo "Local CI ($(git rev-parse --short HEAD 2>/dev/null))"
if command -v shellcheck >/dev/null 2>&1 || command -v pipx >/dev/null 2>&1; then job "shellcheck" shellcheck_run
else skip "shellcheck" "needs shellcheck or pipx"; fi
if [ "$(uname -s)" = Darwin ]; then
  job "tests (macos)" bash tests/run.sh
  if command -v expect >/dev/null 2>&1; then job "game and menu (macOS)" bash tests/interactive.sh
  else skip "game and menu (macOS)" "needs expect"; fi
else
  skip "tests (macos)" "needs macOS"; skip "game and menu (macOS)" "needs macOS"
fi
if docker info >/dev/null 2>&1; then
  job "tests (ubuntu)" in_linux ubuntu:24.04 "bash tests/run.sh"
  job "tests (pwsh, ubuntu)" in_linux mcr.microsoft.com/powershell:7.4-ubuntu-22.04 "PWSH=pwsh bash tests/parity-run.sh"
else
  skip "tests (ubuntu)" "needs docker (for example: brew install colima docker && colima start)"
  skip "tests (pwsh, ubuntu)" "needs docker"
fi
echo "  logs: $LOGS"
if [ "$FAILED" -ne 0 ]; then echo "Local CI: FAILED"; exit 1; fi
if [ "$SKIPPED" -ne 0 ]; then echo "Local CI: passed, but not a full CI run: jobs were skipped"; exit 2; fi
echo "Local CI: passed"
