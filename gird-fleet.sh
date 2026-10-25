#!/usr/bin/env bash
# Blindspot for IT teams: checks every account on a Mac, run as root by an MDM (macOS).
# https://gird.ai/blindspot, docs/fleet.md
#
# It lists the Mac's accounts and checks the Mac's shared places by name. It checks each account as
# that account: a copy of gird-check.sh, made by root in a folder only root can change, runs with
# --account-run through sudo -n -u, with a clean environment, and sends back a fixed set of lines.
# Root checks every line and builds the account's row itself. The result is saved in
# /var/db/blindspot/last.json, readable by root only. Nothing is sent anywhere.
# gird-check.sh must sit next to this file; both, and every folder above them, must be root's alone.
#
#   sudo bash gird-fleet.sh --all-users             a report per account
#   sudo bash gird-fleet.sh --all-users --list      who would be checked, and why anyone is not
#   sudo bash gird-fleet.sh --all-users --json      the result as JSON (--summary-to-stdout: one line)
#     --exit-zero  --deadline=<seconds>  --hash-accounts=<secret>
#   sudo bash gird-fleet.sh --inventory             the saved inventory value (--stale-days=<days>,
#                                                    --result-tags)

# shellcheck disable=SC2034  # the generated tables carry fields only gird-check.sh reads
export LC_ALL=C
ALL=0; ALLUSERS=0; JSON=0; SUMOUT=0; EXITZERO=0; LISTONLY=0; HASHKEY=""; INVENTORY=0; RESULTTAGS=0
DEADLINE=""; STALE_DAYS=""
for arg in "$@"; do
  case "$arg" in
    --all-users) ALLUSERS=1 ;;
    --json) JSON=1 ;;
    --summary-to-stdout) SUMOUT=1 ;;
    --exit-zero) EXITZERO=1 ;;
    --list) LISTONLY=1 ;;
    --hash-accounts=?*) HASHKEY=${arg#*=} ;;
    --deadline=*) DEADLINE=${arg#*=} ;;
    --inventory) INVENTORY=1 ;;
    --stale-days=*) STALE_DAYS=${arg#*=} ;;
    --result-tags) RESULTTAGS=1 ;;
    --all) ALL=1 ;;
    -h|--help) /usr/bin/sed -n '2,/^$/p' "$0" | /usr/bin/sed -n 's/^# \{0,1\}//p'; exit 0 ;;
    *) printf 'Unknown option: %s (try --help)\n' "$arg"; exit 2 ;;
  esac
done
# Root never obeys a test setting, a function from its environment or a tool on the MDM's PATH.
while read -r _ _ _f; do [ -n "$_f" ] && unset -f "$_f"; done <<EOF
$(declare -F)
EOF
FLEET_REAL=0
# Every read of a GIRD_CHECK_* test setting below also needs FLEET_REAL=0 and EUID not 0, and each
# account's run starts with env -i, so as root no test setting is read or passed on.
if [ "$EUID" -eq 0 ] || [ "${GIRD_CHECK_FLEET_REAL_ROOT:-}" = 1 ]; then FLEET_REAL=1; fi
fleet_usage() { printf 'blindspot: %s\n' "$1" >&2; exit "${2:-2}"; }
case "$DEADLINE" in ''|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]|[1-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9]) ;; *) fleet_usage "--deadline takes a number of seconds, up to 99999" ;; esac
case "$STALE_DAYS" in ''|[1-9]|[12][0-9]|30) ;; *) fleet_usage "--stale-days takes a number of days, from 1 to 30" ;; esac
case "$HASHKEY" in *[!A-Za-z0-9._~+/=-]*) fleet_usage "--hash-accounts takes letters, digits and . _ ~ + / = - only" ;; esac
if [ "$ALLUSERS" -eq 0 ]; then
  for _o in "$JSON:--json" "$SUMOUT:--summary-to-stdout" "$EXITZERO:--exit-zero" "$LISTONLY:--list" "${HASHKEY:+1}:--hash-accounts" "${DEADLINE:+1}:--deadline"; do
    [ "${_o%%:*}" = 1 ] && fleet_usage "${_o#*:} works with --all-users only"
  done
fi
[ -n "$STALE_DAYS" ] && [ "$INVENTORY" -eq 0 ] && fleet_usage "--stale-days works with --inventory only"
[ "$RESULTTAGS" -eq 1 ] && [ "$INVENTORY" -eq 0 ] && fleet_usage "--result-tags works with --inventory only"
[ "$ALLUSERS" -eq 1 ] && [ "$INVENTORY" -eq 1 ] && fleet_usage "--inventory reads the saved result: run it without --all-users"
[ "$ALLUSERS" -eq 1 ] || [ "$INVENTORY" -eq 1 ] || fleet_usage "give --all-users to check every account, or --inventory to read the saved result (try --help)"
[ "$JSON" -eq 1 ] && [ "$SUMOUT" -eq 1 ] && fleet_usage "choose --json or --summary-to-stdout, not both"
{
  PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
  unset BASH_ENV ENV CDPATH GLOBIGNORE TMPDIR
  IFS=$' \t\n'; umask 077
  # Each account runs a copy of gird-check.sh from this file's folder, found before cd /.
  FL_SELF=${BASH_SOURCE[0]:-}
  case "$FL_SELF" in ''|/*) ;; *) FL_SELF="$PWD/$FL_SELF" ;; esac
  cd / || exit 13
  _fos=$(/usr/bin/uname -s 2>/dev/null)
  [ "$FLEET_REAL" -eq 0 ] && [ -n "${GIRD_CHECK_FLEET_OS:-}" ] && _fos=$GIRD_CHECK_FLEET_OS   # tests only
  case "$_fos" in
    Darwin) ;;
    Linux) fleet_usage "checking every account is built for macOS only so far; Linux comes next" 13 ;;
    *) fleet_usage "checking every account is built for macOS only" 13 ;;
  esac
  [ "$ALL" -eq 1 ] && fleet_usage "--all is refused with --all-users: Desktop and Documents can hold cloud files that download when read" 13
  if [ "$EUID" -ne 0 ] && { [ "$FLEET_REAL" -eq 1 ] || [ "${GIRD_CHECK_FLEET_ROOT:-}" != 1 ]; }; then
    fleet_usage "$( [ "$INVENTORY" -eq 1 ] && printf '%s' '--inventory' || printf '%s' '--all-users') needs root: run it with sudo, or from your MDM" 13
  fi
  if [ "$ALLUSERS" -eq 1 ] && { [ -z "$FL_SELF" ] || [ ! -f "$FL_SELF" ]; }; then
    fleet_usage "run it from a file: it copies gird-check.sh from its own folder for each account" 13
  fi
  # What root runs, and copies for every account, must be root's alone: gird-fleet.sh, gird-check.sh
  # next to it and every folder above them owned by root (the tests' stand-in owns them in a test
  # run) and writable by nobody else. The mode is read with three digits, so 002 is not read as 2.
  # Root then copies the path it checked.
  if [ "$ALLUSERS" -eq 1 ]; then
    _own=0; [ "$FLEET_REAL" -eq 0 ] && [ "$EUID" -ne 0 ] && _own=$EUID
    _d=$(cd "${FL_SELF%/*}/" 2>/dev/null && /bin/pwd -P) || _d=""
    _bad=""; [ -n "$_d" ] && [ ! -L "$FL_SELF" ] || _bad=1
    if [ -z "$_bad" ]; then
      FL_SELF="${_d%/}/${FL_SELF##*/}"; FL_CHECK="${_d%/}/gird-check.sh"
      [ -f "$FL_CHECK" ] && [ ! -L "$FL_CHECK" ] || fleet_usage "gird-check.sh must sit next to gird-fleet.sh, as a file, not a link" 13
      set -- "$FL_SELF" "$FL_CHECK"; _p=$_d
      while :; do set -- "$@" "$_p"; [ "$_p" = / ] && break; _p=${_p%/*}; [ -n "$_p" ] || _p=/; done
      # tests only: a path whose mode a test run can't give the script or a folder it must reach
      [ "$_own" -ne 0 ] && [ -n "${GIRD_CHECK_FLEET_CHECK_ALSO:-}" ] && set -- "$@" "$GIRD_CHECK_FLEET_CHECK_ALSO"
      for _q in "$@"; do
        _m=$(/usr/bin/stat -f '%u %03Lp' "$_q" 2>/dev/null)
        case "$_m" in "0 "*|"$_own "*) ;; *) _bad=1 ;; esac
        case "${_m#* }" in [0-7][0-7][0-7]) ;; *) _bad=1 ;; esac
        case "${_m#* }" in ?[2367]?|??[2367]) _bad=1 ;; esac
        # An ACL entry that lets anyone write, add or delete counts as writable by someone else.
        /bin/ls -lde "$_q" 2>/dev/null | /usr/bin/awk 'NR > 1 && / allow / && /write|append|add_file|add_subdirectory|delete|chown/ { f = 1 } END { exit !f }' && _bad=1
      done
    fi
    [ -z "$_bad" ] || fleet_usage "gird-fleet.sh, gird-check.sh and every folder above them must be owned by root and writable by no one else: install them in such a folder and run them from there" 13
    [ -r "$FL_CHECK" ] || fleet_usage "gird-check.sh next to gird-fleet.sh could not be read" 13
  fi
  HOME=/var/empty
}

TTY=0; [ -t 1 ] && TTY=1
NL=$'\n'
# The places the tables below name, for an account that is not there: root reads none of them.
H=/var/empty; AS="$H/Library/Application Support"; WIN=0; _os=mac; _pd=""; WLAPP=""
APP_CLAUDE=/Applications/Claude.app; APP_CURSOR=/Applications/Cursor.app
APP_WINDSURF=/Applications/Windsurf.app; APP_ANTIGRAVITY=/Applications/Antigravity.app; APP_DEVIN=/Applications/Devin.app
GOOSE_CFG="$H/.config/goose"; GOOSE_DATA="$H/.local/share/goose"
unset CLAUDE_CONFIG_DIR CODEX_HOME
: "$WIN" "$_os" "$_pd" "$WLAPP" "$GOOSE_CFG" "$GOOSE_DATA"

# ---------------------------------------------------------------------------
# The tables gird-check.sh checks with, written here by tools/gen.sh: never edit them here.
# ---------------------------------------------------------------------------
# >>> keys: generated from data/keys.tsv by tools/gen.sh. Edit that file, then run it.
ALL_KEYS='sk-ant-[A-Za-z0-9_-]{90,}|sk-or-v1-[a-f0-9]{64}|sk-proj-[A-Za-z0-9_-]{120,}|sk-proj-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}([^A-Za-z0-9_-]|$)|sk-svcacct-[A-Za-z0-9_-]{60,}|sk-admin-[A-Za-z0-9_-]{120,}|(^|[^A-Za-z0-9-])sk-[A-Za-z0-9]{48}([^A-Za-z0-9]|$)|(^|[^A-Za-z0-9+/_-])AIza[0-9A-Za-z_-]{35}|(^|[^A-Za-z0-9])AQ\.[A-Za-z0-9_-]{40,}|gsk_[A-Za-z0-9]{52}|xai-[A-Za-z0-9]{64,}|(^|[^A-Za-z0-9_])hf_[A-Za-z0-9]{34,40}([^A-Za-z0-9_]|$)|pplx-[A-Za-z0-9]{40,52}|(^|[^A-Za-z0-9+/_-])r8_[A-Za-z0-9]{37}|(^|[^A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}([^A-Z0-9]|$)|ABSKQmVkcm9ja0FQSUtleS[A-Za-z0-9+/]{60,}|bedrock-api-key-YmVkcm9jay5hbWF6b25hd3MuY29t[A-Za-z0-9+/=]{144}|gh[pour]_[A-Za-z0-9]{36}|(^|[^A-Za-z0-9_])ghs_[A-Za-z0-9]{36}([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])ghs_[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}|npm_[A-Za-z0-9]{36}'
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
# >>> auto-approve: generated from data/auto-approve.tsv by tools/gen.sh. Edit that file, then run it.
AA_TABLE="Claude Code|all|${CLAUDE_CONFIG_DIR:-$H/.claude}/settings.json|bypassPermissions|\"permissions\": {\"defaultMode\": \"bypassPermissions\"
Codex|all|${CODEX_HOME:-$H/.codex}/config.toml|never asks, full access|approval_policy = \"never\"|sandbox_mode = \"danger-full-access\"|!default_permissions
Codex|all|${CODEX_HOME:-$H/.codex}/config.toml|never asks, full access profile|approval_policy = \"never\"|default_permissions = \":danger-full-access\"
VS Code Copilot|all|$AS/Code/User/settings.json|chat.tools.global.autoApprove|\"chat.tools.global.autoApprove\": true
VS Code Copilot|all|$AS/Code/User/settings.json|chat.permissions.default: autoApprove|\"chat.permissions.default\": \"autoApprove\"
VS Code Copilot|all|$AS/Code/User/settings.json|chat.permissions.default: autopilot|\"chat.permissions.default\": \"autopilot\"
Claude Code|all|$AS/Code/User/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true
Claude Code|all|$AS/Cursor/User/settings.json|claudeCode.initialPermissionMode: bypassPermissions|\"claudeCode.initialPermissionMode\": \"bypassPermissions\"|\"claudeCode.allowDangerouslySkipPermissions\": true"
AA_PROJECT=''
# <<< auto-approve
# >>> agents: copied from gird-check.sh by tools/gen.sh. Edit it there, then run it.
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
npm_label() { case "$1" in axios) printf '%s' 'Axios takeover, March 2026' ;; tanstack) printf '%s' 'TanStack worm, May 2026' ;; mistral) printf '%s' 'Mistral AI npm packages, May 2026' ;; uipath) printf '%s' 'UiPath npm packages, May 2026' ;; mistralpy) printf '%s' 'mistralai 2.4.6, May 2026' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1, May 2026' ;; opensearch) printf '%s' 'OpenSearch client, May 2026' ;; bitwarden) printf '%s' 'Bitwarden CLI, April 2026' ;; minishai) printf '%s' 'Mini Shai-Hulud worm, April 2026' ;; lightning) printf '%s' 'lightning 2.6.2 and 2.6.3, April 2026' ;; mastra) printf '%s' 'Mastra npm packages, June 2026' ;; antv) printf '%s' 'AntV account takeover, May 2026' ;; nxconsole) printf '%s' 'Nx Console 18.95.0, May 2026' ;; redhat) printf '%s' 'Red Hat Cloud Services packages, June 2026' ;; keyv) printf '%s' 'keyv worm, August 2026' ;; keyvscope) printf '%s' 'keyv account takeover, August 2026' ;; keyvspread) printf '%s' 'keyv worm spread, August 2026' ;; sandworm) printf '%s' 'SANDWORM_MODE worm, February 2026' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages, February 2026' ;; tensorlake) printf '%s' 'tensorlake package, October 2026' ;; litellm) printf '%s' 'LiteLLM 1.107.0, October 2026' ;; litellmmar) printf '%s' 'LiteLLM 1.82.7 and 1.82.8, March 2026' ;; opencode) printf '%s' 'OpenCode Console, October 2026' ;; railway) printf '%s' 'Railway, October 2026' ;; zeabur) printf '%s' 'Zeabur, October 2026' ;; glassworm) printf '%s' 'GlassWorm extensions, January 2026' ;; glasswormmar) printf '%s' 'GlassWorm extensions, March 2026' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions, March 2026' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions, April 2026' ;; glasswormzig) printf '%s' 'GlassWorm extensions, April 2026' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes, October 2026' ;; injective) printf '%s' 'Injective SDK, July 2026' ;; esac; }
incident_line() { case "$1" in axios) printf '%s' 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it. cisa.gov' ;; tanstack) printf '%s' 'TanStack worm, May 2026: stole cloud, GitHub, npm and SSH credentials on install, then republished itself. github.com' ;; mistral) printf '%s' 'Mistral AI npm packages, May 2026: published with malware Mistral says could not run, as its setup script names a missing file. docs.mistral.ai' ;; uipath) printf '%s' 'UiPath npm packages, May 2026: published with malware UiPath says a bug made non-functional. trust.uipath.com' ;; mistralpy) printf '%s' 'mistralai 2.4.6, May 2026: started a credential stealer in the background when imported on Linux. docs.mistral.ai' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1, May 2026: downloaded and ran a credential stealer, on Linux only. wiz.io' ;; opensearch) printf '%s' 'OpenSearch client, May 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' ;; bitwarden) printf '%s' 'Bitwarden CLI, April 2026: stole SSH keys, npm, GitHub and cloud credentials, and AI tool configs. stepsecurity.io' ;; minishai) printf '%s' 'Mini Shai-Hulud worm, April 2026: stole GitHub, npm and cloud credentials, and tried to spread through stolen tokens. wiz.io' ;; lightning) printf '%s' 'lightning 2.6.2 and 2.6.3, April 2026: started a credential stealer when imported, then tried to spread itself. github.com' ;; mastra) printf '%s' 'Mastra npm packages, June 2026: pulled in malware that started at login and sent browser history to the attackers. socket.dev' ;; antv) printf '%s' 'AntV account takeover, May 2026: published from a hijacked maintainer account with an install hook that steals credentials. osv.dev' ;; nxconsole) printf '%s' 'Nx Console 18.95.0, May 2026: a malicious build fetched a payload that harvested credentials from disk and memory. github.com' ;; redhat) printf '%s' 'Red Hat Cloud Services packages, June 2026: published by the worm with an install hook that steals cloud, GitHub and npm credentials. osv.dev' ;; keyv) printf '%s' 'keyv worm, August 2026: stole cloud, GitHub and npm credentials, and planted hooks that run when repos open. socket.dev' ;; keyvscope) printf '%s' 'keyv account takeover, August 2026: GitHub malware advisories say to treat a computer that installed one as fully compromised. github.com' ;; keyvspread) printf '%s' 'keyv worm spread, August 2026: republished by the worm with an install hook that steals GitHub, npm and cloud credentials. osv.dev' ;; sandworm) printf '%s' 'SANDWORM_MODE worm, February 2026: stole credentials and AI provider keys, and added an MCP server to AI assistants. socket.dev' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages, February 2026: GitHub malware advisories say to treat a machine that installed one as compromised. github.com' ;; tensorlake) printf '%s' 'tensorlake package, October 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' ;; litellm) printf '%s' 'LiteLLM 1.107.0, October 2026: stole credentials and loaded remote-code execution tools on machines that installed it. docs.litellm.ai' ;; litellmmar) printf '%s' 'LiteLLM 1.82.7 and 1.82.8, March 2026: harvested SSH keys, cloud credentials and Kubernetes tokens, and sent them out. docs.litellm.ai' ;; opencode) printf '%s' 'OpenCode Console, October 2026: a breach hit 1.4% of Console users, some of those who had linked external providers. x.com' ;; railway) printf '%s' 'Railway, October 2026: an attacker may have accessed encrypted environment variables and obtained the decrypted contents of some. blog.railway.com' ;; zeabur) printf '%s' 'Zeabur, October 2026: an attacker read environment variables and secrets stored on the platform. zeabur.com' ;; glassworm) printf '%s' 'GlassWorm extensions, January 2026: malicious Open VSX extensions; on Macs, its payload stole credentials, keychains and crypto wallets. socket.dev' ;; glasswormmar) printf '%s' 'GlassWorm extensions, March 2026: ran attacker code in memory that could reach local credentials, tokens and secrets. socket.dev' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions, March 2026: installed a malicious extension from GitHub into every editor it found. socket.dev' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions, April 2026: updated cloned extensions to install malware from GitHub into VS Code, Cursor and Windsurf. socket.dev' ;; glasswormzig) printf '%s' 'GlassWorm extensions, April 2026: native code in an extension installed a GlassWorm dropper into every editor it found. aikido.dev' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes, October 2026: a VS Code theme cluster tied to GlassWorm; two of its themes ran hidden loaders. socket.dev' ;; injective) printf '%s' 'Injective SDK, July 2026: sent out the seed phrases, and the private keys given as hex strings, that apps loaded into it. github.com' ;; esac; }
incident_level() { case "$1" in mistral) printf update ;; uipath) printf update ;; opencode) printf leak ;; railway) printf leak ;; zeabur) printf leak ;; injective) printf update ;; *) printf act ;; esac; }
incident_name() { case "$1" in axios) printf '%s' 'Axios takeover' ;; tanstack) printf '%s' 'TanStack worm' ;; mistral) printf '%s' 'Mistral AI npm packages' ;; uipath) printf '%s' 'UiPath npm packages' ;; mistralpy) printf '%s' 'mistralai 2.4.6' ;; guardrails) printf '%s' 'guardrails-ai 0.10.1' ;; opensearch) printf '%s' 'OpenSearch client' ;; bitwarden) printf '%s' 'Bitwarden CLI' ;; minishai) printf '%s' 'Mini Shai-Hulud worm' ;; lightning) printf '%s' 'lightning 2.6.2 and 2.6.3' ;; mastra) printf '%s' 'Mastra npm packages' ;; antv) printf '%s' 'AntV account takeover' ;; nxconsole) printf '%s' 'Nx Console 18.95.0' ;; redhat) printf '%s' 'Red Hat Cloud Services packages' ;; keyv) printf '%s' 'keyv worm' ;; keyvscope) printf '%s' 'keyv account takeover' ;; keyvspread) printf '%s' 'keyv worm spread' ;; sandworm) printf '%s' 'SANDWORM_MODE worm' ;; sandsleep) printf '%s' 'SANDWORM_MODE sleeper packages' ;; tensorlake) printf '%s' 'tensorlake package' ;; litellm) printf '%s' 'LiteLLM 1.107.0' ;; litellmmar) printf '%s' 'LiteLLM 1.82.7 and 1.82.8' ;; opencode) printf '%s' 'OpenCode Console' ;; railway) printf '%s' 'Railway' ;; zeabur) printf '%s' 'Zeabur' ;; glassworm) printf '%s' 'GlassWorm extensions' ;; glasswormmar) printf '%s' 'GlassWorm extensions' ;; glasswormvsix) printf '%s' 'GlassWorm sleeper extensions' ;; glasswormapr) printf '%s' 'GlassWorm sleeper extensions' ;; glasswormzig) printf '%s' 'GlassWorm extensions' ;; glasswormoct) printf '%s' 'GlassWorm-linked themes' ;; injective) printf '%s' 'Injective SDK' ;; esac; }
incident_source() { case "$1" in axios) printf '%s' 'www.cisa.gov/news-events/alerts/2026/04/20/supply-chain-compromise-impacts-axios-node-package-manager' ;; tanstack) printf '%s' 'github.com/advisories/GHSA-g7cv-rxg3-hmpx' ;; mistral) printf '%s' 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' ;; uipath) printf '%s' 'trust.uipath.com/?tcuUid=d146e497-71c6-4d69-afac-0134100df8b0' ;; mistralpy) printf '%s' 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' ;; guardrails) printf '%s' 'www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised' ;; opensearch) printf '%s' 'github.com/advisories/GHSA-298w-vvm4-ww55' ;; bitwarden) printf '%s' 'www.stepsecurity.io/blog/bitwarden-cli-hijacked-on-npm-bun-staged-credential-stealer-targets-developers-github-actions-and-ai-tools' ;; minishai) printf '%s' 'www.wiz.io/blog/mini-shai-hulud-supply-chain-sap-npm' ;; lightning) printf '%s' 'github.com/advisories/GHSA-g4wr-mm54-799x' ;; mastra) printf '%s' 'socket.dev/blog/mastra-npm-packages-compromised' ;; antv) printf '%s' 'osv.dev/vulnerability/MAL-2026-3973' ;; nxconsole) printf '%s' 'github.com/nrwl/nx-console/security/advisories/GHSA-c9j4-9m59-847w' ;; redhat) printf '%s' 'osv.dev/vulnerability/MAL-2026-5111' ;; keyv) printf '%s' 'socket.dev/blog/popular-npm-packages-in-the-keyv-and-cacheable-namespaces-compromised-in-active-supply-chain' ;; keyvscope) printf '%s' 'github.com/advisories/GHSA-q99r-cjmf-3xrf' ;; keyvspread) printf '%s' 'osv.dev/vulnerability/MAL-2026-11952' ;; sandworm) printf '%s' 'socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning' ;; sandsleep) printf '%s' 'github.com/advisories/GHSA-9w7p-hqx2-pjjx' ;; tensorlake) printf '%s' 'github.com/advisories/GHSA-rqxj-g25x-4v9v' ;; litellm) printf '%s' 'docs.litellm.ai/blog/security-incident-oct-21-2026' ;; litellmmar) printf '%s' 'docs.litellm.ai/blog/security-update-march-2026' ;; opencode) printf '%s' 'x.com/opencode/status/2111519637049319818' ;; railway) printf '%s' 'blog.railway.com/p/security-disclosure-wednesday-october-21st' ;; zeabur) printf '%s' 'zeabur.com/blogs/october-2026-security-incident' ;; glassworm) printf '%s' 'socket.dev/blog/glassworm-loader-hits-open-vsx-via-suspected-developer-account-compromise' ;; glasswormmar) printf '%s' 'socket.dev/blog/open-vsx-transitive-glassworm-campaign' ;; glasswormvsix) printf '%s' 'socket.dev/blog/glassworm-sleeper-extensions-activated-on-open-vsx' ;; glasswormapr) printf '%s' 'socket.dev/blog/73-open-vsx-sleeper-extensions-glassworm' ;; glasswormzig) printf '%s' 'www.aikido.dev/blog/glassworm-zig-dropper-infects-every-ide-on-your-machine' ;; glasswormoct) printf '%s' 'socket.dev/blog/glassworm-vscode-themes' ;; injective) printf '%s' 'github.com/advisories/GHSA-5fc4-fm2x-6f4r' ;; esac; }
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
mastra|all|startup|no|$H/Library/NodePackages/protocal.cjs|starts the Mastra malware at login
mastra|all|startup|no|$H/.config/systemd/user/nvmconf.service|starts the Mastra malware at login
mastra|all|startup|no|$H/.config/systemd/nvmconf/protocal.cjs|starts the Mastra malware at login
mastra|win|startup|no|${_pd:+$_pd/NodePackages/protocal.cjs}|starts the Mastra malware at login
antv|all|startup|no|$H/.config/systemd/user/kitty-monitor.service|starts the AntV wave's kitty-monitor backdoor at login
antv|all|startup|no|$H/Library/LaunchAgents/com.user.kitty-monitor.plist|starts the AntV wave's kitty-monitor backdoor at login
antv|all|startup|no|$H/.local/share/kitty/cat.py|the AntV wave's kitty-monitor backdoor, which its service starts at login
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
# >>> platforms: generated from data/platforms.tsv by tools/gen.sh. Edit that file, then run it.
PLATFORMS="opencode|OpenCode|opencode|$H/.config/opencode/;$H/.local/share/opencode/|installed|OpenCode emailed the Console users its breach hit, and says those it did not email were not affected. It told those users to revoke and replace their keys directly with each provider. Keys kept only in the CLI never reach OpenCode.|OpenCode found: got its breach email? Rotate keys
railway|Railway|railway|$H/.railway/config.json|CLI found|Railway asked all users to rotate every environment variable stored there, including API keys and private registry credentials, and to review their logs for unusual activity.|Railway CLI found: rotate secrets stored there
zeabur|Zeabur|zeabur|$H/.config/zeabur/|CLI found|Zeabur said on 19 October that an attacker read the service environment variables stored on the platform, and asked users to replace every password and key stored there. Revoke each old key at its provider first.|Zeabur CLI found: rotate secrets stored there"
# <<< platforms

# ===========================================================================
# Fleet mode, the root side (docs/designs/fleet-mode.md). Root lists the accounts, checks the
# Mac's shared places, starts one account run at a time as that account, and builds every row
# itself from lines it has checked. It calls every tool by its full path.
# The GIRD_CHECK_FLEET_* settings let the tests stand in for root, dscl, sudo, lsof and find. They
# are read only when the script is not running as root.
# ===========================================================================
FL_STATE=/var/db/blindspot; FL_USERS=""; FL_LAUNCH=""; FL_OWNER=0; FL_SHARED_TMP=/private/tmp; FL_LSOF=/usr/sbin/lsof
FL_FIND=/usr/bin/find
if [ "$EUID" -ne 0 ] && [ "$FLEET_REAL" -eq 0 ]; then
  FL_STATE=${GIRD_CHECK_FLEET_STATE:-$FL_STATE}; FL_USERS=${GIRD_CHECK_FLEET_USERS:-}
  FL_SHARED_TMP=${GIRD_CHECK_FLEET_SHARED_TMP:-$FL_SHARED_TMP}; FL_LSOF=${GIRD_CHECK_FLEET_LSOF:-$FL_LSOF}
  FL_FIND=${GIRD_CHECK_FLEET_FIND:-$FL_FIND}; FL_LAUNCH=${GIRD_CHECK_FLEET_LAUNCH:-}; FL_OWNER=$EUID
fi
FL_PATH=/usr/bin:/bin:/usr/sbin:/sbin
FL_OUT_MAX=4096                 # bytes root reads from one account run
FL_US=$(printf '\037'); FL_TMP=""; FL_COPYDIR=""; FL_COPY=""
fl_cleanup() {
  [ -n "$FL_TMP" ] && /bin/rm -rf -- "$FL_TMP"
  [ -n "$FL_COPYDIR" ] && /bin/rm -rf -- "$FL_COPYDIR"
  FL_TMP=""; FL_COPYDIR=""
}
# fl_timed LIMIT OUT -- COMMAND...: runs COMMAND in its own process group with no terminal, its
# output into a pipe root made and read up to FL_OUT_MAX + 1 bytes into OUT. At LIMIT seconds a
# background timer stops the group, then stops reading. Sets FL_TIMEOUT (the limit was
# reached) and FL_LEFT (something kept running, or kept the pipe open, after the group was killed).
FL_N=0
fl_timed() {
  _tl=$1; _to=$2; shift 3
  FL_N=$((FL_N + 1)); _tp="$FL_TMP/p$FL_N"; FL_TIMEOUT=0; FL_LEFT=0
  # A pipe that can't be made leaves OUT empty, never the last command's output.
  /bin/rm -f -- "$_to"
  /usr/bin/mkfifo -m 600 "$_tp" || return 1
  set -m
  /usr/bin/head -c $((FL_OUT_MAX + 1)) < "$_tp" > "$_to" 2>/dev/null &
  _tr=$!
  "$@" > "$_tp" 2>/dev/null < /dev/null &
  _tj=$!
  ( /bin/sleep "$_tl"; : > "$_tp.t"; kill -TERM -- "-$_tj"; /bin/sleep 2; kill -KILL -- "-$_tj"
    /bin/sleep 1; : > "$_tp.r"; kill -KILL "$_tr" ) > /dev/null 2>&1 < /dev/null &
  _tt=$!
  set +m
  { wait "$_tr"; } 2>/dev/null
  _ts=$(/usr/bin/stat -f %z "$_to" 2>/dev/null)
  # More than root reads: stop the run now, its output is refused anyway.
  [ "${_ts:-0}" -gt "$FL_OUT_MAX" ] && kill -KILL -- "-$_tj" 2>/dev/null
  { wait "$_tj"; } 2>/dev/null
  if [ -e "$_tp.t" ]; then
    FL_TIMEOUT=1
    { [ -e "$_tp.r" ] || kill -0 -- "-$_tj"; } 2>/dev/null && FL_LEFT=1
  fi
  kill -TERM -- "-$_tt" 2>/dev/null; { wait "$_tt"; } 2>/dev/null
  /bin/rm -f "$_tp" "$_tp.t" "$_tp.r"
  return 0
}
fl_dscl() { # account key: one value from the local directory
  /usr/bin/dscl . -read "/Users/$1" "$2" 2>/dev/null | /usr/bin/awk -v k="$2:" '
    $1 == k { if (NF > 1) { sub(/^[^:]*: /, ""); print; exit } if ((getline l) > 0) { sub(/^ +/, "", l); print l } exit }'
}
fl_list_raw() { # name<TAB>uid<TAB>home<TAB>shell for every account
  if [ -n "$FL_USERS" ]; then /bin/cat -- "$FL_USERS"; return; fi
  /usr/bin/dscl . -list /Users UniqueID 2>/dev/null | while read -r _n _u; do
    case "$_n" in _*|'') continue ;; esac
    case "$_u" in ''|*[!0-9]*) continue ;; esac
    [ "$_u" -ge 500 ] || continue
    printf '%s\t%s\t%s\t%s\n' "$_n" "$_u" "$(fl_dscl "$_n" NFSHomeDirectory)" "$(fl_dscl "$_n" UserShell)"
  done
}
# The accounts to check, each with why it is or is not checked: name, uid, home and reason, where
# reason is "ok" or a fixed word, split by the unit separator (FL_US), which unlike a TAB keeps an
# empty field a field when read. System accounts (UID below 500, a name starting with _)
# are left out. A home that does not answer in time is not checked; so is one shared with an
# account already listed.
fl_accounts() {
  _seen="|"
  fl_list_raw | /usr/bin/tr '\t' '\037' | while IFS="$FL_US" read -r _n _u _h _s; do
    case "$_n" in _*|'') continue ;; esac
    case "$_u" in ''|*[!0-9]*) continue ;; esac
    [ "$_u" -ge 500 ] || continue
    _r=ok
    case "$_n" in *[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) _r=name ;; esac
    [ "${#_n}" -le 64 ] || _r=name
    [ "$_r" = name ] && _n=invalid-name
    if [ "$_r" = ok ]; then
      case "$_s" in ''|/usr/bin/false|/bin/false|/sbin/nologin|/usr/sbin/nologin) _r=no_login_shell ;; esac
    fi
    if [ "$_r" = ok ]; then
      _h=${_h%/}
      case "$_h" in
        /*) ;;
        *) _r=home_missing ;;
      esac
      case "$_h" in
        ''|/var|/private|/tmp|/private/tmp|/private/var|/var/empty|/private/var/empty|/var/root|/private/var/root|/Users|/Volumes|/Network) _r=home_system ;;
        /System|/System/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/etc|/etc/*|/private/etc|/private/etc/*|/dev|/dev/*|/Library|/Library/*|/Applications|/Applications/*|/opt|/opt/*|/cores|/cores/*) _r=home_system ;;
        *[!A-Za-z0-9._/@\ -]*) _r=home_system ;;
      esac
    fi
    if [ "$_r" = ok ]; then
      fl_timed 10 "$FL_TMP/home" -- /usr/bin/stat -f '%u %d:%i %HT' -- "$_h"
      _st=$(/usr/bin/head -c 200 "$FL_TMP/home" 2>/dev/null)
      if [ "$FL_TIMEOUT" -eq 1 ]; then _r=home_no_answer
      else
        case "$_st" in
          *" Directory") case "$_st" in "$_u "*) ;; *) _r=home_owner ;; esac ;;
          *"Symbolic Link") _r=home_link ;;
          '') _r=home_missing ;;
          *) _r=home_missing ;;
        esac
        _di=$(printf '%s' "$_st" | /usr/bin/awk '{ print $2 }')
        if [ "$_r" = ok ]; then
          case "$_seen" in *"|$_di|"*) _r=home_shared ;; *) _seen="$_seen$_di|" ;; esac
        fi
      fi
    fi
    [ "$_r" = ok ] || _h=""   # a home is read only for an account that is checked
    printf '%s\037%s\037%s\037%s\n' "$_n" "$_u" "$_h" "$_r"
  done
}
fl_reason_text() {
  case "$1" in
    name) printf 'not checked: an account name Blindspot does not read' ;;
    no_login_shell) printf 'not checked: no login shell' ;;
    home_missing) printf 'not checked: no home folder' ;;
    home_link) printf 'not checked: the home folder is a link' ;;
    home_owner) printf 'not checked: the home folder belongs to another account' ;;
    home_shared) printf 'not checked: the home folder is shared with an account above' ;;
    home_system) printf 'not checked: the home folder is a system folder' ;;
    home_no_answer) printf 'not checked: the home folder did not answer in time' ;;
    sudo) printf 'not checked: could not start a check as this account' ;;
    bad_output) printf 'not checked: its check sent back something unexpected' ;;
    time_limit) printf 'not checked: its check ran out of time' ;;
    deadline) printf 'not checked: the run reached its deadline first' ;;
    copy_changed) printf 'not checked: the script copy was changed during the run' ;;
    *) printf 'not checked' ;;
  esac
}
# The ids an account run may send, from the tables above.
FL_AGENT_IDS=$(printf '%s\n' "$AGENTS" | /usr/bin/cut -d'|' -f5 | /usr/bin/tr '\n' ' ')
FL_YOLO_IDS="$FL_AGENT_IDS $(printf '%s\n' "$AA_TABLE" | /usr/bin/cut -d'|' -f1 | /usr/bin/tr 'A-Z ' 'a-z-' | /usr/bin/tr -cd 'a-z0-9-\n' | /usr/bin/tr '\n' ' ')"
FL_OUT_IDS=$(printf '%s\n' "$OUT_TABLE" | /usr/bin/cut -d'|' -f1 | /usr/bin/sort -u | /usr/bin/tr '\n' ' ')
FL_PLAT_IDS=$(printf '%s\n' "$PLATFORMS" | /usr/bin/cut -d'|' -f1 | /usr/bin/tr '\n' ' ')
FL_KEYS="v agents yolo tools mcp_servers mcp_token_files key_files key_providers history_keys session_files sessions_partial allow_list_keys ssh_open ak_links planted possible incidents platforms on_open to_read updates wiper lock_only remove not_read protected end"
fl_ids_ok() { # value allowed-ids: every id allowed, none twice, at most 40
  _c=0; _sn=" "
  for _x in $1; do
    _c=$((_c + 1)); [ "$_c" -le 40 ] || return 1
    case " $2 " in *" $_x "*) ;; *) return 1 ;; esac
    case "$_sn" in *" $_x "*) return 1 ;; esac; _sn="$_sn$_x "
  done
  case "$1" in ''|[a-z0-9]*[a-z0-9]|[a-z0-9]) ;; *) return 1 ;; esac
  case "$1" in *"  "*) return 1 ;; esac
  return 0
}
fl_incidents_ok() { # every id is an incident in data/incidents.tsv
  for _x in $1; do [ -n "$(incident_name "$_x")" ] || return 1; done
  fl_ids_ok "$1" "$1"
}
# Reads one account run's output. Every line must be the next key in FL_KEYS with a value of its
# kind; anything else, any other byte, or more than FL_OUT_MAX bytes refuses the whole output.
# Sets FA_<key> for each.
fl_parse() {
  _f=$1
  _sz=$(/usr/bin/stat -f %z "$_f" 2>/dev/null); case "$_sz" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_sz" -gt 0 ] && [ "$_sz" -le "$FL_OUT_MAX" ] || return 1
  [ "$(LC_ALL=C /usr/bin/tr -d '\n a-z0-9=_-' < "$_f" | /usr/bin/wc -c | /usr/bin/tr -d ' ')" = 0 ] || return 1
  [ "$(/usr/bin/tail -c 1 "$_f" | /usr/bin/od -An -tx1 | /usr/bin/tr -d ' \n')" = 0a ] || return 1
  set -- $FL_KEYS
  while IFS= read -r _l; do
    [ $# -gt 0 ] || return 1
    _k=${_l%%=*}; _v=${_l#*=}
    [ "$_k" = "$1" ] && [ "$_k=$_v" = "$_l" ] || return 1
    case "$_k" in
      v|end) [ "$_v" = 1 ] || return 1 ;;
      agents) fl_ids_ok "$_v" "$FL_AGENT_IDS" || return 1 ;;
      yolo) fl_ids_ok "$_v" "$FL_YOLO_IDS" || return 1 ;;
      tools) fl_ids_ok "$_v" "$FL_OUT_IDS" || return 1 ;;
      key_providers) fl_ids_ok "$_v" "$PROVIDER_IDS" || return 1 ;;
      platforms) fl_ids_ok "$_v" "$FL_PLAT_IDS" || return 1 ;;
      incidents) fl_incidents_ok "$_v" || return 1 ;;
      possible|updates|lock_only|remove) fl_incidents_ok "$_v" || return 1 ;;
      sessions_partial|wiper) case "$_v" in 0|1) ;; *) return 1 ;; esac ;;
      protected) case "$_v" in ok|refused|unknown) ;; *) return 1 ;; esac ;;
      *) case "$_v" in [0-9]|[1-9][0-9]|[1-9][0-9][0-9]|[1-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9][0-9]) ;; *) return 1 ;; esac ;;
    esac
    case "$_k" in
      agents) FA_agents=$_v ;; yolo) FA_yolo=$_v ;; tools) FA_update=$_v ;; mcp_servers) FA_mcp_servers=$_v ;;
      mcp_token_files) FA_mcp_token_files=$_v ;; key_files) FA_key_files=$_v ;; key_providers) FA_key_providers=$_v ;;
      history_keys) FA_history_keys=$_v ;; session_files) FA_session_files=$_v ;; sessions_partial) FA_sessions_partial=$_v ;;
      allow_list_keys) FA_allow_list_keys=$_v ;; ssh_open) FA_ssh_open=$_v ;; ak_links) FA_ak_links=$_v ;;
      planted) FA_planted=$_v ;; possible) FA_possible=$_v ;; incidents) FA_incidents=$_v ;; platforms) FA_platforms=$_v ;;
      on_open) FA_on_open=$_v ;; to_read) FA_to_read=$_v ;; updates) FA_updates=$_v ;; wiper) FA_wiper=$_v ;; lock_only) FA_lock_only=$_v ;; remove) FA_remove=$_v ;;
      not_read) FA_not_read=$_v ;; protected) FA_protected=$_v ;;
    esac
    shift
  done < "$_f"
  [ $# -eq 0 ]
}
fl_copy_ok() { # the copy each account runs: owned by root, nobody else can change it
  [ -d "$FL_COPYDIR" ] && [ ! -L "$FL_COPYDIR" ] && [ -f "$FL_COPY" ] && [ ! -L "$FL_COPY" ] || return 1
  [ "$(/usr/bin/stat -f '%u %Lp' "$FL_COPYDIR" 2>/dev/null)" = "$FL_OWNER 755" ] || return 1
  # Not its link count: any account can hard-link a file in /tmp, and a link can't change a file
  # root owns at 0644, so counting links would let one account stop every later account's check.
  [ "$(/usr/bin/stat -f '%u %Lp' "$FL_COPY" 2>/dev/null)" = "$FL_OWNER 644" ]
}
fl_json_list() { _o=""; for _x in $1; do _o="${_o:+$_o,}\"$_x\""; done; printf '[%s]' "$_o"; }
fl_json_incidents() { _o=""; for _x in $1; do _o="${_o:+$_o,}{\"id\":\"$_x\",\"level\":\"$(incident_level "$_x")\"}"; done; printf '[%s]' "$_o"; }
fl_worst() { # outcomes on stdin: the worst, in the order failed, act, not_checked, review, clear
  /usr/bin/awk 'BEGIN { r["failed"] = 5; r["act"] = 4; r["not_checked"] = 3; r["review"] = 2; r["clear"] = 1; w = "clear" }
    ($1 in r) && r[$1] > r[w] { w = $1 } END { print w }'
}
fl_name() { # the account as the result shows it: its name, or a keyed hash with --hash-accounts
  if [ -z "$HASHKEY" ] || [ "$1" = invalid-name ]; then printf '%s' "$1"; return; fi
  BS_K=$HASHKEY /usr/bin/perl -MDigest::SHA=hmac_sha256_hex -e 'print substr(hmac_sha256_hex($ARGV[0], $ENV{BS_K}), 0, 16)' -- "$1"
}
fl_agent_name() { # an id: the agent's name for the report
  _a=$(printf '%s\n' "$AGENTS" | /usr/bin/awk -F '|' -v i="$1" '$5 == i { print $1; exit }')
  [ -n "$_a" ] || _a=$(printf '%s\n' "$AA_TABLE" | /usr/bin/awk -F '|' -v i="$1" '{ n = tolower($1); gsub(/ /, "-", n); gsub(/[^a-z0-9-]/, "", n) } n == i { print $1; exit }')
  printf '%s' "${_a:-$1}"
}
fl_prov_name() { # a provider id: its name
  for _x in $(declare -f prov_id | /usr/bin/sed -n 's/.*"\([^"]*\)").*/\1/p' | /usr/bin/tr ' ' '#'); do
    _x=${_x//#/ }; [ "$(prov_id "$_x")" = "$1" ] && { printf '%s' "$_x"; return; }
  done
  printf '%s' "$1"
}
fl_join() { _o=""; for _x in "$@"; do _o="${_o:+$_o, }$_x"; done; printf '%s' "$_o"; }
fl_plural() { if [ "$1" = 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi; }

# The Mac's shared places, checked once, by root, by name only: nothing in them is read or run.
fl_machine() {
  FM_AGENTS=""; FM_INC=""; FM_COMPLETE=true; FM_WHY=""; _late=0; _tend=$((SECONDS + ${FM_FIND_S:-20}))
  while IFS='|' read -r _nm _bins _paths _acts _id; do
    [ -n "$_nm" ] || continue
    _hit=0; _ifs=$IFS; IFS=';'
    for _p in $_paths; do case "$_p" in /Applications/*) [ -e "$_p" ] && _hit=1 ;; esac; done
    for _b in $_bins; do [ -n "$_b" ] && { [ -e "/usr/local/bin/$_b" ] || [ -e "/opt/homebrew/bin/$_b" ]; } && _hit=1; done
    IFS=$_ifs
    [ "$_hit" -eq 1 ] && FM_AGENTS="$FM_AGENTS $_id"
  done <<EOF
$AGENTS
EOF
  while IFS='|' read -r _ii _io _ik _iown _ip _in; do
    case "$_io" in all|mac) ;; *) continue ;; esac
    case "$_ik" in
      temp)
        # Never through a link, which any account can make. A marker that must be someone's own counts
        # for the Mac only when root made it, under its one name; one an account owns is that
        # account's finding, which its own run looks for in /tmp. A find for each name, all of them
        # within FM_FIND_S seconds: any account can fill the folder with such names, and they must not
        # cost root a step each.
        _tl=$((_tend - SECONDS)); [ "$_tl" -ge 1 ] || { _late=1; continue; }
        set -- -name "$_ip" ! -type l
        [ "$_iown" = yes ] && set -- "$@" -user "$FL_OWNER" -links 1
        fl_timed "$_tl" "$FL_TMP/marker" -- "$FL_FIND" "$FL_SHARED_TMP/" -mindepth 1 -maxdepth 1 "$@" -print -quit || FL_TIMEOUT=1
        [ -s "$FL_TMP/marker" ] && FM_INC="$FM_INC $_ii"
        [ "$FL_TIMEOUT" -eq 1 ] && _late=1 ;;
      wiper|startup)
        # A marker that must be the person's own (data/indicators.tsv) is each account's own
        # finding, checked by its account run; any account could leave one in a shared folder.
        [ "$_iown" = yes ] && continue
        case "$_ip" in "$H"/*|'') continue ;; /tmp/*) _ip="$FL_SHARED_TMP/${_ip#/tmp/}" ;; esac
        { [ -L "$_ip" ] || [ -e "$_ip" ]; } && FM_INC="$FM_INC $_ii" ;;
    esac
  done <<EOF
$IND_TABLE
EOF
  [ "$_late" -eq 1 ] && { FM_COMPLETE=false; FM_WHY="the shared temp folder could not be looked through in time"; }
  # The LiteLLM loader holds its lock file open while it runs.
  _lk="$FL_SHARED_TMP/remote_code_loader.lock"
  # Only a lock file root made: one an account owns is that account's marker, found by its own run.
  if [ -f "$_lk" ] && [ ! -L "$_lk" ] && [ "$(/usr/bin/stat -f '%u %l' "$_lk" 2>/dev/null)" = "$FL_OWNER 1" ]; then
    fl_timed "${FM_LSOF_S:-10}" "$FL_TMP/lsof" -- "$FL_LSOF" -t "$_lk" || FL_TIMEOUT=1
    [ -s "$FL_TMP/lsof" ] && FM_INC="$FM_INC litellm"
    [ "$FL_TIMEOUT" -eq 1 ] && { FM_COMPLETE=false; FM_WHY="${FM_WHY:+$FM_WHY, and }a running LiteLLM loader could not be looked for in time"; }
  fi
  FM_AGENTS=$(printf '%s\n' $FM_AGENTS | /usr/bin/awk 'NF && !s[$0]++' | /usr/bin/paste -sd ' ' -)
  FM_INC=$(printf '%s\n' $FM_INC | /usr/bin/awk 'NF && !s[$0]++' | /usr/bin/paste -sd ' ' -)
}

# The saved result: /var/db/blindspot/last.json, readable by root only. A folder that is a link,
# not a folder, or not root's with mode 0700 is moved aside and made again.
fl_state_ok() { [ -d "$FL_STATE" ] && [ ! -L "$FL_STATE" ] && [ "$(/usr/bin/stat -f '%u %Lp' "$FL_STATE" 2>/dev/null)" = "$FL_OWNER 700" ]; }
fl_state_prep() {
  if ! fl_state_ok; then
    if [ -e "$FL_STATE" ] || [ -L "$FL_STATE" ]; then
      /bin/mv -f -- "$FL_STATE" "$FL_STATE.replaced-$(/bin/date -u +%Y%m%d%H%M%S)-$$" 2>/dev/null || return 1
    fi
    /bin/mkdir -m 700 -- "$FL_STATE" 2>/dev/null || return 1
    fl_state_ok || return 1
  fi
}
fl_write() { # name text: written to a new file, then renamed into place, root's only
  fl_state_prep || return 1
  _sf=$(/usr/bin/mktemp "$FL_STATE/.$1.XXXXXX") || return 1
  printf '%s\n' "$2" > "$_sf" && /bin/chmod 600 "$_sf" && /bin/mv -f -- "$_sf" "$FL_STATE/$1" || { /bin/rm -f -- "$_sf"; return 1; }
}
fl_save() { fl_write last.json "$1"; }
# Each run first saves when it started and its deadline, so a run the MDM stopped part-way is not
# hidden behind the last finished result.
fl_attempt() { fl_write attempt "$FL_EPOCH ${DEADLINE:-3000}"; }

# --inventory: reads the saved result, never scans. An MDM's inventory field shows the line it
# prints: the inventory value, "stale" when the last run is older than --stale-days (3 by
# default, at most 30), "none" before the first run, "unreadable" when the file is not root's own,
# and "failed" when a later run started and did not finish by its deadline.
# --result-tags puts it between <result> tags.
fl_inv_out() { if [ "$RESULTTAGS" -eq 1 ]; then printf '<result>%s</result>\n' "$1"; else printf '%s\n' "$1"; fi; }
fl_unfinished() { # epoch of the last finished run, 0 for none: prints "failed" when a later run stopped part-way
  _a="$FL_STATE/attempt"
  [ -f "$_a" ] && [ ! -L "$_a" ] && [ "$(/usr/bin/stat -f '%u %Lp' "$_a" 2>/dev/null)" = "$FL_OWNER 600" ] || return 1
  _at=$(/usr/bin/head -c 64 "$_a" | /usr/bin/sed -n '1s/^\([0-9]\{1,12\}\) \([0-9]\{1,5\}\)$/\1 \2/p')
  [ -n "$_at" ] && [ "${_at% *}" -gt "$1" ] && [ $(( $(/bin/date -u +%s) - ${_at% *} )) -gt "${_at#* }" ] || return 1
  fl_inv_out "failed: the run started $(/bin/date -u -r "${_at% *}" +%Y-%m-%dT%H:%MZ) did not finish"
}
fl_inventory() {
  _f="$FL_STATE/last.json"
  if [ ! -e "$_f" ] && [ ! -L "$_f" ]; then fl_state_ok && fl_unfinished 0 && return 0; fl_inv_out none; return 0; fi
  if ! fl_state_ok || [ -L "$_f" ] || [ ! -f "$_f" ] || [ "$(/usr/bin/stat -f '%u %Lp' "$_f" 2>/dev/null)" != "$FL_OWNER 600" ]; then fl_inv_out unreadable; return 0; fi
  _ep=$(/usr/bin/sed -n 's/^  "checked_epoch": \([0-9]\{1,12\}\),$/\1/p' "$_f" | /usr/bin/head -n 1)
  _iv=$(/usr/bin/sed -n 's/^  "inventory": "\([A-Za-z0-9 ._:;,|+-]*\)",$/\1/p' "$_f" | /usr/bin/head -n 1)
  [ "${#_iv}" -le 300 ] || _iv=""
  if [ -z "$_ep" ] || [ -z "$_iv" ]; then fl_inv_out unreadable; return 0; fi
  fl_unfinished "$_ep" && return 0
  _age=$(( $(/bin/date -u +%s) - _ep ))
  if [ "$_age" -gt $(( ${STALE_DAYS:-3} * 86400 )) ] || [ "$_age" -lt -3600 ]; then
    fl_inv_out "stale: last run $(/bin/date -u -r "$_ep" +%Y-%m-%dT%H:%MZ)"; return 0
  fi
  fl_inv_out "$_iv"
}

fleet_main() {
  trap 'fl_cleanup' EXIT
  trap 'fl_cleanup; exit 130' INT TERM HUP
  if [ "$INVENTORY" -eq 1 ]; then fl_inventory; return 0; fi
  FL_TMP=$(/usr/bin/mktemp -d /tmp/blindspot-fleet.XXXXXXXX) || { echo "blindspot failed: no work folder" >&2; return 13; }
  if [ "$LISTONLY" -eq 1 ]; then
    fl_accounts > "$FL_TMP/accounts"
    _nl=0
    while IFS="$FL_US" read -r _n _u _h _r; do
      _nl=$((_nl + 1))
      if [ "$_r" = ok ]; then printf '%-24s will be checked\n' "$_n"; else printf '%-24s %s\n' "$_n" "$(fl_reason_text "$_r")"; fi
    done < "$FL_TMP/accounts"
    [ "$_nl" -eq 0 ] && echo "No accounts to check: a run would report not_checked."
    echo "System accounts (UID below 500, or a name starting with _) are never checked."
    return 0
  fi
  # The Mac's own check comes last, within this reserve: its temp folder finds get half of it and
  # lsof a quarter, at most 20 and 10 seconds, each stopped within 3 seconds of its limit.
  _dl=${DEADLINE:-3000}; _rs=$((_dl / 10)); [ "$_rs" -gt 40 ] && _rs=40
  FM_FIND_S=$((_rs / 2)); [ "$FM_FIND_S" -gt 20 ] && FM_FIND_S=20; [ "$FM_FIND_S" -lt 1 ] && FM_FIND_S=1
  FM_LSOF_S=$((_rs / 4)); [ "$FM_LSOF_S" -gt 10 ] && FM_LSOF_S=10; [ "$FM_LSOF_S" -lt 1 ] && FM_LSOF_S=1
  FL_END=$((SECONDS + _dl - _rs)); FL_DEADLINE_HIT=0; FL_FAILED=""
  # One version for both files: gird-check.sh's release, from its header.
  FL_REL=$(/usr/bin/sed -n '1,5{s/^# Blindspot, .*, version \([0-9][0-9.]*\) .*/\1/p;}' "$FL_CHECK" | /usr/bin/head -n 1)
  [ -n "$FL_REL" ] || FL_REL=unknown
  FL_AT=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ); FL_EPOCH=$(/bin/date -u +%s)
  fl_attempt || :   # a folder that cannot be written fails the save at the end, too
  FL_OS="macOS $(/usr/bin/sw_vers -productVersion 2>/dev/null | /usr/bin/tr -cd '0-9.' | /usr/bin/cut -d. -f1-2)"; FL_OS=${FL_OS% }
  # The copy each account runs: gird-check.sh, made once, in a new folder only root can change.
  _src=$FL_CHECK
  if [ -f "$_src" ] && [ -r "$_src" ] && FL_COPYDIR=$(/usr/bin/mktemp -d /tmp/blindspot-copy.XXXXXXXX); then
    FL_COPY="$FL_COPYDIR/gird-check.sh"
    { /bin/cp -- "$_src" "$FL_COPY" && /bin/chmod 0644 "$FL_COPY" && /bin/chmod 0755 "$FL_COPYDIR" && fl_copy_ok; } || FL_FAILED=copy
  else FL_FAILED=copy; fi
  fl_accounts > "$FL_TMP/accounts"
  _left=$(/usr/bin/grep -c "${FL_US}ok\$" "$FL_TMP/accounts")
  ROWS=""; OUTS=""; N_NC_RUN=0; N_ACC=0; N_ACT=0; N_UPD=0; N_NC=0; TERM_VIEW=""; INV=""
  while IFS="$FL_US" read -r _n _u _h _r; do
    N_ACC=$((N_ACC + 1))
    _shown=$(fl_name "$_n")
    FA_stop=""; _row=""
    if [ "$_r" = ok ]; then
      # An equal share of the time left, less the 3 seconds a stop takes, so one stuck account
      # spends only its own share.
      _lim=$(( (FL_END - SECONDS) / (_left > 0 ? _left : 1) - 3 )); _left=$((_left - 1))
      if [ -n "$FL_FAILED" ]; then _r=copy_changed
      elif [ "$_lim" -lt 1 ]; then _r=deadline; FL_DEADLINE_HIT=1
      elif ! fl_copy_ok; then _r=copy_changed; FL_FAILED=copy
      else
        set -- /usr/bin/sudo -n -u "$_n" -H /usr/bin/env -i "PATH=$FL_PATH" "HOME=$_h" /bin/bash "$FL_COPY" --account-run
        [ -n "$FL_LAUNCH" ] && set -- "$FL_LAUNCH" "$@"
        fl_timed "$_lim" "$FL_TMP/out" -- "$@"
        if fl_parse "$FL_TMP/out"; then
          [ "$FL_TIMEOUT" -eq 1 ] && FA_stop=time_limit
        elif [ "$FL_TIMEOUT" -eq 1 ]; then _r=time_limit
        elif [ ! -s "$FL_TMP/out" ]; then _r=sudo
        else _r=bad_output; fi
        [ "$FL_TIMEOUT" -eq 1 ] && [ "$(( (FL_END - SECONDS) ))" -le 0 ] && FL_DEADLINE_HIT=1
      fi
    fi
    if [ "$_r" != ok ]; then
      _out=not_checked
      _row="{\"account\":\"$_shown\",\"complete\":false,\"outcome\":\"not_checked\",\"not_checked\":\"$_r\"$( [ "${FL_LEFT:-0}" = 1 ] && [ "$_r" = time_limit ] && printf ',"processes_left":true')}"
      TERM_VIEW="${TERM_VIEW:+$TERM_VIEW$NL}$(printf '\n  %-44s%s\n    %s' "$_shown" "not checked" "$(fl_reason_text "$_r")")"
      INV="$INV | $_shown: not_checked $_r"
      N_NC=$((N_NC + 1)); N_NC_RUN=$((N_NC_RUN + 1))
    else
      _act=0; _upd=0; _complete=true; _lines=""; _inv=""
      _ia=""; _iu=""; for _x in $FA_incidents; do if [ "$(incident_level "$_x")" = act ]; then _ia="$_ia $_x"; else _iu="$_iu $_x"; fi; done
      # gh-token-monitor runs a destructive command when the stolen token stops working, so stopping it
      # comes before any rotate or revoke the lines below call for, as in the one-person report.
      if [ "$FA_wiper" -eq 1 ]; then _act=1; _lines="$_lines$NL    x  gh-token-monitor is installed: stop and remove it before anyone revokes a GitHub token"; _inv="$_inv; wiper"; fi
      [ -n "$_ia" ] && _act=1
      for _x in $_ia; do _lines="$_lines$NL    x  $(incident_line "$_x" | /usr/bin/sed 's/\. [a-z0-9.-]*$//')"; done
      [ -n "$_ia" ] && _inv="$_inv; incidents$(printf ' %s' $_ia | /usr/bin/tr -s ' ' | /usr/bin/sed 's/^ //; s/ /,/g; s/^/ /')"
      # A bad npm version only in a lockfile, nothing installed: act if that project was installed.
      if [ -n "$FA_lock_only" ]; then
        _act=1; for _x in $FA_lock_only; do _lines="$_lines$NL    x  A lockfile lists $(incident_name "$_x") versions, nothing installed: act now if that project was installed"; done
        _inv="$_inv; lockfile $(printf '%s' "$FA_lock_only" | /usr/bin/tr ' ' ',')"
      fi
      for _x in $_iu; do
        _upd=1; _s=$(incident_summary "$_x")
        if [ -n "$_s" ]; then _lines="$_lines$NL    !  $_s"; else _lines="$_lines$NL    !  $(incident_line "$_x" | /usr/bin/sed 's/\. [a-z0-9.-]*$//')"; fi
      done
      if [ "$FA_planted" -gt 0 ]; then _act=1; _lines="$_lines$NL    x  Files a worm plants in a project, or settings that run one: $FA_planted"; _inv="$_inv; planted $FA_planted"; fi
      if [ -n "$FA_yolo" ]; then _upd=1; for _x in $FA_yolo; do _lines="$_lines$NL    !  $(fl_agent_name "$_x") set to run commands without asking"; done; _inv="$_inv; run-without-asking $(printf '%s' "$FA_yolo" | /usr/bin/tr ' ' ',')"; fi
      if [ "$FA_key_files" -gt 0 ]; then
        _act=1; _pn=""; for _x in $FA_key_providers; do _pn="${_pn:+$_pn, }$(fl_prov_name "$_x")"; done
        _lines="$_lines$NL    x  Keys in plain text: $(fl_plural "$FA_key_files" file files)${_pn:+ ($_pn)}"
        _inv="$_inv; keys $FA_key_files${FA_key_providers:+ $(printf '%s' "$FA_key_providers" | /usr/bin/tr ' ' ',')}"
      fi
      if [ "$FA_history_keys" -gt 0 ]; then _act=1; _lines="$_lines$NL    x  Keys typed into shell history: $(fl_plural "$FA_history_keys" file files)"; _inv="$_inv; history $FA_history_keys"; fi
      if [ "$FA_session_files" -gt 0 ]; then _act=1; _lines="$_lines$NL    x  Keys in agent sessions: $(fl_plural "$FA_session_files" file files)"; _inv="$_inv; sessions $FA_session_files"; fi
      if [ "$FA_mcp_token_files" -gt 0 ]; then _act=1; _lines="$_lines$NL    x  Tokens written in MCP configs: $(fl_plural "$FA_mcp_token_files" file files)"; _inv="$_inv; mcp-tokens $FA_mcp_token_files"; fi
      if [ "$FA_allow_list_keys" -gt 0 ]; then _act=1; _lines="$_lines$NL    x  Keys saved in Claude Code allow lists: $(fl_plural "$FA_allow_list_keys" file files)"; _inv="$_inv; allow-lists $FA_allow_list_keys"; fi
      if [ "$FA_ak_links" -gt 0 ]; then _act=1; _lines="$_lines$NL    x  Links to authorized_keys outside .ssh: $FA_ak_links"; _inv="$_inv; ssh-links $FA_ak_links"; fi
      if [ "$FA_ssh_open" -gt 0 ]; then _upd=1; _lines="$_lines$NL    !  $(fl_plural "$FA_ssh_open" "SSH key" "SSH keys") without a passphrase"; _inv="$_inv; ssh-open $FA_ssh_open"; fi
      if [ -n "$FA_update" ]; then _upd=1; _tn=""; for _x in $FA_update; do _tn="${_tn:+$_tn, }$(printf '%s\n' "$OUT_TABLE" | /usr/bin/awk -F '|' -v i="$_x" '$1 == i { print $2; exit }')"; done; _lines="$_lines$NL    !  Tools with a security fix to install: $_tn"; _inv="$_inv; update-tools $(printf '%s' "$FA_update" | /usr/bin/tr ' ' ',')"; fi
      # Found means its CLI or files are there, not that the person used the hosted service: each
      # platform's own summary says what to check, as the person's report does.
      # With gh-token-monitor there, its rotate waits for it, as every rotate in the person's report does.
      if [ -n "$FA_platforms" ]; then _upd=1; for _x in $FA_platforms; do _lines="$_lines$NL    !  $(printf '%s\n' "$PLATFORMS" | /usr/bin/awk -F '|' -v i="$_x" '$1 == i { print $7; exit }')$( [ "$FA_wiper" -eq 1 ] && printf ', once gh-token-monitor is stopped')"; done; _inv="$_inv; platforms $(printf '%s' "$FA_platforms" | /usr/bin/tr ' ' ',')"; fi
      if [ "$FA_on_open" -gt 0 ]; then _upd=1; _lines="$_lines$NL    !  Project settings that act when an agent or editor opens the folder: $FA_on_open"; _inv="$_inv; on-open $FA_on_open"; fi
      if [ "$FA_to_read" -gt 0 ]; then _upd=1; _lines="$_lines$NL    !  Files named like the ones worms plant, to read: $FA_to_read"; _inv="$_inv; to-read $FA_to_read"; fi
      for _x in $FA_updates; do _upd=1; _lines="$_lines$NL    !  A version to update: $(incident_name "$_x")"; done
      # An editor extension whose malware runs only on another system: one to remove, not a sign.
      for _x in $FA_remove; do _upd=1; _lines="$_lines$NL    !  An extension to remove, its malware made for another system: $(incident_name "$_x")"; done
      [ -n "$FA_remove" ] && _inv="$_inv; remove $(printf '%s' "$FA_remove" | /usr/bin/tr ' ' ',')"
      # Incidents and package versions at the update level, one item in the inventory value.
      _ul=$(printf '%s\n' $_iu $FA_updates | /usr/bin/awk 'NF && !s[$0]++' | /usr/bin/paste -sd ',' -)
      [ -n "$_ul" ] && _inv="$_inv; update $_ul"
      for _x in $FA_possible; do
        _upd=1
        if [ "$_x" = litellm ]; then _lines="$_lines$NL    !  A leftover file that can come from the LiteLLM malware"
        else _lines="$_lines$NL    !  A startup file named like the one the $(incident_name "$_x") install, with none of them here"; fi
      done
      [ -n "$FA_possible" ] && _inv="$_inv; possible $(printf '%s' "$FA_possible" | /usr/bin/tr ' ' ',')"
      _why=""
      [ "$FA_sessions_partial" -eq 1 ] && _why="${_why:+$_why, }agent sessions partly checked"
      [ "$FA_not_read" -gt 0 ] && _why="${_why:+$_why, }$(fl_plural "$FA_not_read" "file was" "files were") not read"
      [ "$FA_protected" != ok ] && _why="${_why:+$_why, }folders macOS protects were not checked (Full Disk Access)"
      [ -n "$FA_stop" ] && _why="${_why:+$_why, }its check ran out of time"
      [ -n "$_why" ] && _complete=false
      if [ "$_act" -eq 1 ]; then _out=act; elif [ "$_complete" = false ]; then _out=not_checked; elif [ "$_upd" -eq 1 ]; then _out=review; else _out=clear; fi
      case "$_out" in act) N_ACT=$((N_ACT + 1)) ;; review) N_UPD=$((N_UPD + 1)) ;; not_checked) N_NC=$((N_NC + 1)) ;; esac
      [ "$_complete" = false ] && { _lines="$_lines$NL    ?  Partly checked: $_why"; _inv="$_inv; partial"; }
      _prot=checked; [ "$FA_protected" = ok ] || _prot=not_checked
      _row="{\"account\":\"$_shown\",\"complete\":$_complete,\"outcome\":\"$_out\",\"agents\":$(fl_json_list "$FA_agents"),\"agents_run_without_asking\":$(fl_json_list "$FA_yolo"),\"tools_to_update\":$(fl_json_list "$FA_update"),\"mcp_servers\":$FA_mcp_servers,\"mcp_token_files\":$FA_mcp_token_files,\"key_files\":$FA_key_files,\"key_providers\":$(fl_json_list "$FA_key_providers"),\"history_keys\":$FA_history_keys,\"session_files_with_keys\":$FA_session_files,\"allow_list_keys\":$FA_allow_list_keys,\"ssh_keys_no_passphrase\":$FA_ssh_open,\"authorized_keys_links\":$FA_ak_links,\"planted_files\":$FA_planted,\"possible_signs\":$(fl_json_list "$FA_possible"),\"project_settings_on_open\":$FA_on_open,\"files_to_read\":$FA_to_read,\"versions_to_update\":$(fl_json_list "$FA_updates"),\"wiper\":$( [ "$FA_wiper" = 1 ] && echo true || echo false),\"lockfile_only_incidents\":$(fl_json_list "$FA_lock_only"),\"extensions_to_remove\":$(fl_json_list "$FA_remove"),\"platforms_found\":$(fl_json_list "$FA_platforms"),\"files_not_checked\":$FA_not_read,\"sessions_partly_checked\":$( [ "$FA_sessions_partial" = 1 ] && echo true || echo false),\"protected_folders\":\"$_prot\"$( [ -n "$FA_stop" ] && printf ',"stopped":"time_limit"')$( [ "${FL_LEFT:-0}" = 1 ] && printf ',"processes_left":true'),\"incidents\":$(fl_json_incidents "$FA_incidents")}"
      case "$_out" in act) _word="act now" ;; review) _word="review" ;; not_checked) _word="partly checked" ;; *) _word="nothing found" ;; esac
      TERM_VIEW="${TERM_VIEW:+$TERM_VIEW$NL}$(printf '\n  %-44s%s' "$_shown" "$_word")$_lines"
      INV="$INV | $_shown: $_out$( [ -n "$_inv" ] && printf ' %s' "${_inv#; }")"
    fi
    ROWS="${ROWS:+$ROWS,}$_row"; OUTS="$OUTS$_out$NL"
  done < "$FL_TMP/accounts"
  # The Mac itself.
  fl_machine
  FM_OUT=clear; _ml=""
  for _x in $FM_INC; do
    if [ "$(incident_level "$_x")" = act ]; then FM_OUT=act; _ml="$_ml$NL    x  $(incident_line "$_x" | /usr/bin/sed 's/\. [a-z0-9.-]*$//')"
    else [ "$FM_OUT" = act ] || FM_OUT=review; _ml="$_ml$NL    !  $(incident_line "$_x" | /usr/bin/sed 's/\. [a-z0-9.-]*$//')"; fi
  done
  [ -n "$_ml" ] && _ml="$_ml$NL    Found as files root made in the shared temp folder, or a running LiteLLM loader: the malware ran as root."
  # A machine check that did not answer in time leaves the Mac partly checked.
  [ "$FM_COMPLETE" = true ] || { [ "$FM_OUT" = act ] || FM_OUT=not_checked; _ml="$_ml$NL    ?  Partly checked: $FM_WHY"; }
  MACHINE="{\"complete\":$FM_COMPLETE,\"outcome\":\"$FM_OUT\",\"agents\":$(fl_json_list "$FM_AGENTS"),\"incidents\":$(fl_json_incidents "$FM_INC")}"
  [ "$FM_OUT" != clear ] && INV="$INV | machine: $FM_OUT $(printf '%s' "$FM_INC" | /usr/bin/tr ' ' ',')"
  OUTS="$OUTS$FM_OUT$NL"
  [ "$N_ACC" -eq 0 ] && OUTS="${OUTS}not_checked$NL"
  [ -n "$FL_FAILED" ] && OUTS="${OUTS}failed$NL"
  OUTCOME=$(printf '%s' "$OUTS" | fl_worst)
  _short=$(printf '%s' "$FL_AT" | /usr/bin/cut -c1-16)Z
  SUMMARY="blindspot $OUTCOME accounts=$N_ACC act=$N_ACT review=$N_UPD not_checked=$N_NC v=$FL_REL at=$FL_AT"
  # The inventory value: one line for an MDM's inventory field, no path, file name or key. Too
  # long, it keeps the accounts that need attention first and ends with +more; the saved file has the rest.
  INVENTORY_V="v1 $OUTCOME $_short$INV"; [ "$N_ACC" -eq 0 ] && INVENTORY_V="$INVENTORY_V | no accounts"
  if [ "${#INVENTORY_V}" -gt 250 ]; then
    _iv="v1 $OUTCOME $_short"
    # The accounts that need attention come first, act, then not_checked, then review, then as many
    # clear ones as fit.
    _iv=$(printf '%s' "$INV" | /usr/bin/awk -v head="$_iv" -F ' [|] ' 'BEGIN { r["act"] = 4; r["not_checked"] = 3; r["review"] = 2; r["clear"] = 1 }
      { n = 0; for (i = 2; i <= NF; i++) { split($i, p, " "); s[++n] = p[1] " " p[2]; k[n] = (p[2] in r) ? r[p[2]] : 5 }
        out = head; stop = 0
        for (lv = 5; lv >= 0 && !stop; lv--) for (j = 1; j <= n && !stop; j++) if (k[j] == lv) { t = out " | " s[j]; if (length(t) > 243) stop = 1; else out = t }
        print out " +more" }')
    INVENTORY_V=$_iv
  fi
  JSON_DOC="{
  \"blindspot\": \"1\",
  \"script\": \"$FL_REL\",
  \"checked_at\": \"$FL_AT\",
  \"checked_epoch\": $FL_EPOCH,
  \"os\": \"$FL_OS\",
  \"outcome\": \"$OUTCOME\",
  \"deadline_reached\": $( [ "$FL_DEADLINE_HIT" -eq 1 ] && echo true || echo false),
  \"accounts\": [$ROWS],
  \"machine\": $MACHINE,
  \"summary\": \"$SUMMARY\",
  \"inventory\": \"$INVENTORY_V\",
  \"learn_more\": \"https://gird.ai/argus\"
}"
  FL_SAVED=1; fl_save "$JSON_DOC" || { FL_SAVED=0; OUTCOME=failed; }
  if [ "$FL_SAVED" -eq 0 ]; then
    SUMMARY="blindspot failed accounts=$N_ACC act=$N_ACT review=$N_UPD not_checked=$N_NC v=$FL_REL at=$FL_AT"
    JSON_DOC=$(printf '%s\n' "$JSON_DOC" | /usr/bin/sed 's/^  "outcome": "[a-z_]*",$/  "outcome": "failed",/')
  fi
  if [ "$JSON" -eq 1 ]; then printf '%s\n' "$JSON_DOC"
  elif [ "$SUMOUT" -eq 1 ]; then printf '%s\n' "$SUMMARY"
  else
    _nck=$((N_ACC - N_NC_RUN))
    if [ "$_nck" -eq "$N_ACC" ]; then printf '\n  This Mac: %s checked\n' "$(fl_plural "$N_ACC" "account" "accounts")"
    else printf '\n  This Mac: %s of %s checked\n' "$_nck" "$(fl_plural "$N_ACC" "account" "accounts")"; fi
    printf '%s\n' "$TERM_VIEW"
    # The word is set first: bash 3.2, macOS's own, ends a $( ) at a case pattern's ")".
    case "$FM_OUT" in act) _mw="act now" ;; not_checked) _mw="partly checked" ;; *) _mw=review ;; esac
    if [ -n "$_ml" ]; then printf '\n  %-44s%s%s\n' "This Mac" "$_mw" "$_ml"; fi
    [ -n "$FL_FAILED" ] && printf '\n  The run stopped: the script copy each account runs was changed.\n'
    if [ "$FL_SAVED" -eq 1 ]; then printf '\n  Saved: %s/last.json\n' "$FL_STATE"; else printf '\n  Not saved: %s could not be written safely.\n' "$FL_STATE"; fi
    if [ "$TTY" -eq 1 ]; then
      if [ "$OUTCOME" = clear ]; then _a1="Nothing found on this Mac today."; else _a1="This is one Mac, checked once."; fi
      printf '\n  %s Argus shows every AI agent on every Mac as it\n  runs, who owns it and what it may reach. Roll it out through the MDM you\n  already use: gird.ai/argus\n\n' "$_a1"
    fi
  fi
  if [ "$OUTCOME" = failed ]; then return 13; fi
  [ "$EXITZERO" -eq 1 ] && return 0
  case "$OUTCOME" in clear) return 0 ;; act) return 10 ;; review) return 11 ;; *) return 12 ;; esac
}
fleet_main
exit $?
