#!/usr/bin/env bash
# Runs the jobs in .github/workflows/ci.yml on this machine, one at a time, and prints each job's
# result. The two Ubuntu jobs run in a Linux container when `docker` answers, as an ordinary user, the
# way the CI runner does; without docker they are listed as skipped, and the run does not count as a
# full CI run. Logs are kept in a temp folder, named at the end.
#
#   bash tools/ci-local.sh
set -u
cd "$(dirname "$0")/.." || exit 2
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
in_linux() { # image command [extra docker args]
  _img=$1; _cmd=$2; shift 2
  docker run --rm -v "$PWD:/src:ro" "$@" "$_img" bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null && apt-get install -y -qq python3 perl jq procps curl git expect file xxd ca-certificates libicu74 >/dev/null &&
    { [ ! -f /pwsh.tar.gz ] || { mkdir -p /opt/pwsh && tar -xzf /pwsh.tar.gz -C /opt/pwsh && chmod +x /opt/pwsh/pwsh && ln -s /opt/pwsh/pwsh /usr/local/bin/pwsh; }; } &&
    useradd -m -s /bin/bash ci && su -s /bin/bash ci -c 'cd /src && $_cmd'"
}

# PowerShell for the Linux container: a pinned release for this machine's chip, downloaded here (not in
# the container, which may not trust this machine's TLS setup), checked against its published SHA-256.
PWSH_VER=7.4.6
pwsh_linux() {
  case "$(docker info --format '{{.Architecture}}' 2>/dev/null)" in
    aarch64|arm64) _a=arm64; _h=c0159b03e85f44ae1e7697818a011558da6c813d0aae848bf5ac13bf435d8624 ;;
    x86_64|amd64) _a=x64; _h=6f6015203c47806c5cc444c19d8ed019695e610fbd948154264bf9ca8e157561 ;;
    *) return 1 ;;
  esac
  PWSH_TGZ="$HOME/.cache/blindspot-ci/powershell-$PWSH_VER-linux-$_a.tar.gz"
  if [ ! -f "$PWSH_TGZ" ]; then
    mkdir -p "${PWSH_TGZ%/*}"
    curl -fsSL -o "$PWSH_TGZ.part" "https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VER/powershell-$PWSH_VER-linux-$_a.tar.gz" || return 1
    mv "$PWSH_TGZ.part" "$PWSH_TGZ"
  fi
  _got=$( (shasum -a 256 "$PWSH_TGZ" 2>/dev/null || sha256sum "$PWSH_TGZ") | cut -d' ' -f1)
  [ "$_got" = "$_h" ] || { rm -f "$PWSH_TGZ"; return 1; }
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
  if pwsh_linux; then job "tests (pwsh, ubuntu)" in_linux ubuntu:24.04 "bash tests/parity-run.sh" -v "$PWSH_TGZ:/pwsh.tar.gz:ro"
  else skip "tests (pwsh, ubuntu)" "could not get PowerShell $PWSH_VER for this machine's chip, checked by SHA-256"; fi
else
  skip "tests (ubuntu)" "needs docker (for example: brew install colima docker && colima start)"
  skip "tests (pwsh, ubuntu)" "needs docker"
fi
echo "  logs: $LOGS"
if [ "$FAILED" -ne 0 ]; then echo "Local CI: FAILED"; exit 1; fi
if [ "$SKIPPED" -ne 0 ]; then echo "Local CI: passed, but not a full CI run: jobs were skipped"; exit 2; fi
echo "Local CI: passed"
