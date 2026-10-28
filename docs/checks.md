# What Blindspot checks

The [README](../README.md#what-it-checks) says what each of the five checks is for. This page lists
everything they look for, and how they read it.

- [The lists](#1-coding-agents): agents, settings, versions, key types, session folders, incidents,
  packages, extensions and files. They are generated from the data files.
- [How each check reads](#how-each-check-reads): the rules the lists do not show.
- [What it does not read](#what-it-does-not-read).
- [Windows](#windows).

<!-- >>> checks: generated from data/*.tsv and the agents table in gird-check.sh by tools/gen.sh. Edit those, then run it. -->
_This part of the page is written by `tools/gen.sh` from the files in [`data/`](../data) and the agents table in `gird-check.sh`, the same sources the scripts are built from. Edit those, not this page._

Paths: `~` is your home folder, `{AS}` the app data folder (Application Support on a Mac, `%APPDATA%` on Windows, `XDG_CONFIG_HOME` or `~/.config` on Linux), `{LOCALAPPDATA}` `%LOCALAPPDATA%` on Windows, `{XDG_DATA}` `XDG_DATA_HOME` or `~/.local/share`, `{GOOSE_DATA}` and `{GOOSE_STATE}` Goose's data and state folders, `{PROGRAMDATA}` `%ProgramData%` on Windows, `{PROJECT}` each project folder the home scan finds, and `{ENV:NAME:fallback}` the folder the variable `NAME` names, or the fallback. A path marked for one system is looked for there only.

## 1. Coding agents

### Agents it looks for

- Claude Code (`claude`)
- Claude Desktop
- Codex (`codex`)
- Gemini CLI (`gemini`)
- Cursor (`cursor`)
- Windsurf (`windsurf`, `devin-desktop`)
- Antigravity (`antigravity`)
- GitHub Copilot CLI (`copilot`)
- OpenCode (`opencode`)
- Goose (`goose`)
- Aider (`aider`)
- Cline
- Continue

### Settings that run commands without asking

- Claude Code, bypassPermissions: `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/settings.json`
- Claude Code, permissions.allow: Bash: `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/settings.json`
- Claude Code, permissions.allow: Bash(\*): `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/settings.json`
- Codex, never asks, full access: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, never asks, full access profile: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, never asks, full access, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, never asks, full access profile, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access, default approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access, on-request approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access, on-failure approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access, granular approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access profile, default approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access profile, on-request approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access profile, on-failure approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access profile, granular approvals: `{ENV:CODEX_HOME:~/.codex}/config.toml`
- Codex, full access, default approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access, on-request approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access, on-failure approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access, granular approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access profile, default approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access profile, on-request approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access profile, on-failure approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- Codex, full access profile, granular approvals, when the project is trusted: `{PROJECT}/.codex/config.toml`
- VS Code Copilot, chat.tools.global.autoApprove: `{AS}/Code/User/settings.json`, `{AS}/Code - Insiders/User/settings.json`
- VS Code Copilot, chat.permissions.default: autoApprove: `{AS}/Code/User/settings.json`, `{AS}/Code/User/profiles/*/settings.json`, `{AS}/Code - Insiders/User/settings.json`, `{AS}/Code - Insiders/User/profiles/*/settings.json`
- VS Code Copilot, chat.permissions.default: autopilot: `{AS}/Code/User/settings.json`, `{AS}/Code/User/profiles/*/settings.json`, `{AS}/Code - Insiders/User/settings.json`, `{AS}/Code - Insiders/User/profiles/*/settings.json`
- VS Code Copilot, chat.defaultConfiguration: allowAll: `{AS}/Code/User/settings.json`, `{AS}/Code/User/profiles/*/settings.json`, `{AS}/Code - Insiders/User/settings.json`, `{AS}/Code - Insiders/User/profiles/*/settings.json`
- VS Code Copilot, chat.defaultConfiguration: autoApprove: `{AS}/Code/User/settings.json`, `{AS}/Code/User/profiles/*/settings.json`, `{AS}/Code - Insiders/User/settings.json`, `{AS}/Code - Insiders/User/profiles/*/settings.json`
- Claude Code, claudeCode.initialPermissionMode: bypassPermissions: `{AS}/Code/User/settings.json`, `{AS}/Cursor/User/settings.json`, `{AS}/Code/User/profiles/*/settings.json`, `{AS}/Code - Insiders/User/settings.json`, `{AS}/Code - Insiders/User/profiles/*/settings.json`, `{AS}/Cursor/User/profiles/*/settings.json`

### Versions with a published security fix

| Tool | Versions | What the hole allows | Read from | Advisory |
|---|---|---|---|---|
| Cursor (macOS) | below 3.0 | a malicious agent could escape the sandbox | the app | [GHSA-3p48-7v9f-v5cw](https://github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw) |
| Cursor (macOS) | below 3.1.2 | an agent could replace the Python of a virtual environment to run commands outside the sandbox | the app | [GHSA-p9g2-cr55-cw9c](https://github.com/cursor/cursor/security/advisories/GHSA-p9g2-cr55-cw9c) |
| Claude Desktop (macOS) | 1.1.3918 to below 1.15962.0 | a file an agent leaves in a Cowork folder could run commands on the Mac when opened | the app | [GHSA-v234-4jrq-mgg6](https://github.com/anthropics/claude-code/security/advisories/GHSA-v234-4jrq-mgg6) |
| Claude Desktop (macOS) | 1.2581.0 to below 1.4304.0 | an attacker on the network could intercept its remote SSH sessions | the app | [GHSA-3rwf-2g6p-c2f9](https://github.com/anthropics/claude-code/security/advisories/GHSA-3rwf-2g6p-c2f9) |
| Amazon Q language server (macOS, Linux, Windows) | below 1.69.0 | a link in a workspace can let the agent write files outside it, and before 1.65.0 a workspace you trust can run its commands | its version folder | [2026-047-aws](https://aws.amazon.com/security/security-bulletins/2026-047-aws/) |
| Claude Code | 0.2.116 to below 1.0.24 | a web page could reach the editor connection | npm installs | [GHSA-9f65-56v6-gxw7](https://github.com/advisories/GHSA-9f65-56v6-gxw7) |
| Claude Code | 2.1.38 to below 2.1.163 | a malicious repository could run code outside the sandbox | npm installs | [GHSA-7835-87q9-rgvv](https://github.com/advisories/GHSA-7835-87q9-rgvv) |
| Claude Code | below 2.1.179 | a plugin repository could install code that bypasses its pinned hash | npm installs | [GHSA-pq7j-f95f-qfcv](https://github.com/advisories/GHSA-pq7j-f95f-qfcv) |
| Claude Code | 2.0.68 to below 2.1.260 | a stored API key could start sessions without the managed settings of an Enterprise or Team organization | npm installs | [GHSA-gfvf-j8jh-jxxw](https://github.com/anthropics/claude-code/security/advisories/GHSA-gfvf-j8jh-jxxw) |
| mcp-remote | 0.0.5 to below 0.1.16 | a hostile MCP server could run commands | npm installs, MCP configs | [GHSA-6xpm-ggf7-wc3p](https://github.com/advisories/GHSA-6xpm-ggf7-wc3p) |
| mcp-remote | 0.1.16 to 0.1.38, no fixed version yet | a hostile server could open an internal address in your browser | npm installs, MCP configs | [GHSA-v65w-6crh-cp3h](https://github.com/advisories/GHSA-v65w-6crh-cp3h) |
| mcp-remote | 0.1.16 to 0.1.38, no fixed version yet | a weak hash, MD5, keeps the saved tokens of each server apart | npm installs, MCP configs | [GHSA-mvq8-g2rm-4rhm](https://github.com/advisories/GHSA-mvq8-g2rm-4rhm) |
| mcp-remote | 0.1.32 to 0.1.38, no fixed version yet | a hostile server could make it send requests to local and private network addresses | npm installs, MCP configs | [GHSA-8rrr-xx35-4q6h](https://github.com/advisories/GHSA-8rrr-xx35-4q6h) |
| mcp-remote | 0.1.32 to 0.1.38, no fixed version yet | a hostile server could make it probe services on your network | npm installs, MCP configs | [GHSA-5wmf-76f4-cg47](https://github.com/advisories/GHSA-5wmf-76f4-cg47) |
| mcp-remote | 0.8.0 to 0.14.3, no fixed version yet | with --device-code, a server can make it send its client secret and tokens over plain HTTP | npm installs, MCP configs | [GHSA-jrvg-vw6c-rp59](https://github.com/advisories/GHSA-jrvg-vw6c-rp59) |

## 2. MCP servers and project settings

### Files worms plant in a project

- `.claude/router_runtime.js`: a file the TanStack and Mini Shai-Hulud worms plant (TanStack worm). Counts wherever it is found.
- `.vscode/router_runtime.js`: a file the TanStack worm plants (TanStack worm). Counts wherever it is found.
- `.claude/setup.mjs`: a file the TanStack, keyv and Mini Shai-Hulud worms plant (keyv worm). Counts beside a file only a worm uses, or when its SHA-256 matches one its sources publish; otherwise listed as a file to read.
- `.claude/math_init.js`: a file the keyv worm plants (keyv worm). Counts wherever it is found.
- `.vscode/setup.mjs`: a file the TanStack, keyv and Mini Shai-Hulud worms plant (keyv worm). Counts beside a file only a worm uses, or when its SHA-256 matches one its sources publish; otherwise listed as a file to read.
- `.claude/execution.js`: a file the Mini Shai-Hulud worm plants (Mini Shai-Hulud worm). Counts beside a file only a worm uses, or when its SHA-256 matches one its sources publish; otherwise listed as a file to read.
- `.claude/index.js`: a file the AntV wave plants (AntV account takeover). Counts beside a file only a worm uses, or when its SHA-256 matches one its sources publish; otherwise listed as a file to read.

## 3. Keys in plain text

### Key types

| Provider | Starts with (as a pattern) |
|---|---|
| Anthropic | `sk-ant-` |
| OpenRouter | `sk-or-v1-` |
| OpenAI | `sk-` |
| Google | `AIza`, `AQ[.]` |
| Groq | `gsk_` |
| xAI | `xai-` |
| Hugging Face | `hf_` |
| Perplexity | `pplx-` |
| Replicate | `r8_` |
| AWS | `AKIA`, `ASIA`, `ABSK`, `bedrock-api-key` |
| GitHub | `gh[pousr]_`, `github_pat_` |
| npm | `npm_` |

### Agent session transcripts

- **Claude Code**: `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/projects`, `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/history.jsonl`, `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/paste-cache`
- **Claude Desktop**: `{AS}/Claude/local-agent-mode-sessions`, `{LOCALAPPDATA}/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/local-agent-mode-sessions` (Windows only), `{AS}/Claude-3p/local-agent-mode-sessions`, `{LOCALAPPDATA}/Claude-3p/local-agent-mode-sessions` (Windows only)
- **Codex**: `{ENV:CODEX_HOME:~/.codex}/sessions`, `{ENV:CODEX_HOME:~/.codex}/archived_sessions`, `{ENV:CODEX_HOME:~/.codex}/history.jsonl`, `{ENV:CODEX_HOME:~/.codex}/thread_history_1.sqlite`, `{ENV:CODEX_HOME:~/.codex}/thread_history_1.sqlite-wal`, `{ENV:CODEX_SQLITE_HOME:~/.codex}/thread_history_1.sqlite`, `{ENV:CODEX_SQLITE_HOME:~/.codex}/thread_history_1.sqlite-wal`
- **Gemini CLI**: `{ENV:GEMINI_CLI_HOME:~}/.gemini/tmp`, `{ENV:GEMINI_CLI_HOME:~}/.cache/.gemini/tmp` (macOS only)
- **Qwen Code**: `{ENV:QWEN_HOME:~/.qwen}/projects`, `{ENV:QWEN_HOME:~/.qwen}/tmp`, `{ENV:QWEN_RUNTIME_DIR:~/.qwen}/projects`, `{ENV:QWEN_RUNTIME_DIR:~/.qwen}/tmp`
- **OpenCode**: `{XDG_DATA}/opencode/opencode.db`, `{XDG_DATA}/opencode/opencode.db-wal`, `{XDG_DATA}/opencode/storage`
- **GitHub Copilot CLI**: `{ENV:COPILOT_HOME:~/.copilot}/session-state`, `{ENV:COPILOT_HOME:~/.copilot}/history-session-state`, `{ENV:COPILOT_HOME:~/.copilot}/command-history-state`, `{ENV:COPILOT_HOME:~/.copilot}/session-store.db`, `{ENV:COPILOT_HOME:~/.copilot}/session-store.db-wal`, `{ENV:COPILOT_HOME:~/.copilot}/command-history-state.json`
- **Roo Code**: `{AS}/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks`, `{AS}/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks`
- **Cline**: `{AS}/Code/User/globalStorage/saoudrizwan.claude-dev/tasks`, `{AS}/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks`, `{ENV:CLINE_DATA_DIR:~/.cline/data}/sessions`, `{ENV:CLINE_DATA_DIR:~/.cline/data}/tasks`, `{ENV:CLINE_DIR:~/.cline}/data/sessions`, `{ENV:CLINE_DIR:~/.cline}/data/tasks`, `{ENV:CLINE_SESSION_DATA_DIR:~/.cline/data/sessions}`
- **Continue**: `{ENV:CONTINUE_GLOBAL_DIR:~/.continue}/sessions`, `{ENV:CONTINUE_GLOBAL_DIR:~/.continue}/dev_data/0.2.0/chatInteraction.jsonl`
- **Goose**: `{GOOSE_DATA}/sessions`, `{GOOSE_STATE}/logs`, `{GOOSE_STATE}/history.txt`
- **Kiro CLI**: `{ENV:KIRO_HOME:~/.kiro}/sessions`, `{AS}/kiro-cli` (macOS only), `{XDG_DATA}/kiro-cli` (Linux only), `{LOCALAPPDATA}/kiro-cli` (Windows only)
- **Amazon Q**: `{AS}/amazon-q` (macOS only), `{XDG_DATA}/amazon-q` (Linux only), `{LOCALAPPDATA}/amazon-q` (Windows only), `~/.aws/amazonq/.cli_bash_history`
- **Factory Droid**: `~/.factory/sessions`, `~/.factory/projects`, `~/.factory/state/history.json`
- **Cursor**: `{AS}/Cursor/User/globalStorage/state.vscdb`, `~/.cursor/projects`, `~/.cursor/chats`
- **Windsurf**: `~/.windsurf/transcripts`, `~/.codeium/windsurf/cascade` (encrypted: counted and named as not checked)
- **Antigravity**: `~/.gemini/antigravity/brain`, `~/.gemini/antigravity-cli/brain`, `~/.gemini/antigravity-ide/brain`, `~/.gemini/antigravity/conversations` (SQLite files), `~/.gemini/antigravity-cli/conversations` (SQLite files), `~/.gemini/antigravity-ide/conversations` (SQLite files), `~/.gemini/antigravity/conversations` (encrypted: counted and named as not checked), `~/.gemini/antigravity-cli/conversations` (encrypted: counted and named as not checked), `~/.gemini/antigravity-ide/conversations` (encrypted: counted and named as not checked)

## 5. Recent key leaks

### Incidents

Level: **act** means treat the machine as compromised, **update** means update the version (the machine is not compromised), **leak** means rotate what was stored on that platform.

| Incident | When | What it did | Level | Looked for | Source |
|---|---|---|---|---|---|
| Axios takeover | March 2026 | downloaded payloads, including a remote access trojan, onto machines that installed it | act | npm: 3 versions of 2 packages | [cisa.gov](https://www.cisa.gov/news-events/alerts/2026/04/20/supply-chain-compromise-impacts-axios-node-package-manager) |
| TanStack worm | May 2026 | stole cloud, GitHub, npm and SSH credentials on install, then republished itself | act | npm: 326 versions of 100 packages, 2 files | [github.com](https://github.com/advisories/GHSA-g7cv-rxg3-hmpx) |
| Mistral AI npm packages | May 2026 | published with malware Mistral says could not run, as its setup script names a missing file | update | npm: 9 versions of 3 packages | [docs.mistral.ai](https://docs.mistral.ai/resources/security-advisories/MAI-2026-002) |
| UiPath npm packages | May 2026 | published with malware UiPath says a bug made non-functional | update | npm: 66 versions of 66 packages | [trust.uipath.com](https://trust.uipath.com/?tcuUid=d146e497-71c6-4d69-afac-0134100df8b0) |
| mistralai 2.4.6 | May 2026 | started a credential stealer in the background when imported on Linux | act | Python: 1 version, 1 file | [docs.mistral.ai](https://docs.mistral.ai/resources/security-advisories/MAI-2026-002) |
| guardrails-ai 0.10.1 | May 2026 | downloaded and ran a credential stealer, on Linux only | act | Python: 1 version, 1 file | [wiz.io](https://www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised) |
| OpenSearch client | May 2026 | GitHub says any computer that installed it should be treated as fully compromised | act | npm: 4 versions of 1 package | [github.com](https://github.com/advisories/GHSA-298w-vvm4-ww55) |
| Bitwarden CLI | April 2026 | stole SSH keys, npm, GitHub and cloud credentials, and AI tool configs | act | npm: 1 version of 1 package | [stepsecurity.io](https://www.stepsecurity.io/blog/bitwarden-cli-hijacked-on-npm-bun-staged-credential-stealer-targets-developers-github-actions-and-ai-tools) |
| Mini Shai-Hulud worm | April 2026 | stole GitHub, npm and cloud credentials, and tried to spread through stolen tokens | act | npm: 5 versions of 5 packages, 1 file | [wiz.io](https://www.wiz.io/blog/mini-shai-hulud-supply-chain-sap-npm) |
| lightning 2.6.2 and 2.6.3 | April 2026 | started a credential stealer when imported, then tried to spread itself | act | Python: 2 versions | [github.com](https://github.com/advisories/GHSA-g4wr-mm54-799x) |
| durabletask 1.4.1 to 1.4.3 | May 2026 | fetched and ran a credential-stealing payload when imported on Linux | act | Python: 3 versions, 1 file | [github.com](https://github.com/advisories/GHSA-3qf7-886j-9wrc) |
| telnyx 4.87.1 and 4.87.2 | March 2026 | stole SSH keys and cloud and Kubernetes credentials when imported, and left a backdoor | act | Python: 2 versions, 4 files | [github.com](https://github.com/advisories/GHSA-955r-262c-33jc) |
| Mastra npm packages | June 2026 | pulled in malware that started at login and sent browser history to the attackers | act | npm: 94 versions of 94 packages, 5 files | [socket.dev](https://socket.dev/blog/mastra-npm-packages-compromised) |
| AntV account takeover | May 2026 | published from a hijacked maintainer account with an install hook that steals credentials | act | npm: 644 versions of 324 packages, 6 files | [osv.dev](https://osv.dev/vulnerability/MAL-2026-3973) |
| Nx Console 18.95.0 | May 2026 | a malicious build fetched a payload that harvested credentials from disk and memory | act | 1 extension, 2 files | [github.com](https://github.com/nrwl/nx-console/security/advisories/GHSA-c9j4-9m59-847w) |
| Red Hat Cloud Services packages | June 2026 | published by the worm with an install hook that steals cloud, GitHub and npm credentials | act | npm: 96 versions of 32 packages | [osv.dev](https://osv.dev/vulnerability/MAL-2026-5111) |
| keyv worm | August 2026 | stole cloud, GitHub and npm credentials, and planted hooks that run when repos open | act | npm: 12 versions of 12 packages, 3 files | [socket.dev](https://socket.dev/blog/popular-npm-packages-in-the-keyv-and-cacheable-namespaces-compromised-in-active-supply-chain) |
| keyv account takeover | August 2026 | GitHub malware advisories say to treat a computer that installed one as fully compromised | act | npm: 19 versions of 19 packages | [github.com](https://github.com/advisories/GHSA-q99r-cjmf-3xrf) |
| keyv worm spread | August 2026 | republished by the worm with an install hook that steals GitHub, npm and cloud credentials | act | npm: 2224 versions of 432 packages | [osv.dev](https://osv.dev/vulnerability/MAL-2026-11952) |
| SANDWORM\_MODE worm | February 2026 | stole credentials and AI provider keys, and added an MCP server to AI assistants | act | npm: 20 versions of 19 packages | [socket.dev](https://socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning) |
| SANDWORM\_MODE sleeper packages | February 2026 | GitHub malware advisories say to treat a machine that installed one as compromised | act | npm: 4 versions of 4 packages | [github.com](https://github.com/advisories/GHSA-9w7p-hqx2-pjjx) |
| tensorlake package | October 2026 | GitHub says any computer that installed it should be treated as fully compromised | act | npm: 7 versions of 7 packages | [github.com](https://github.com/advisories/GHSA-rqxj-g25x-4v9v) |
| LiteLLM 1.107.0 | October 2026 | stole credentials and loaded remote-code execution tools on machines that installed it | act | Python: 1 version, 6 files | [docs.litellm.ai](https://docs.litellm.ai/blog/security-incident-oct-21-2026) |
| LiteLLM 1.82.7 and 1.82.8 | March 2026 | harvested SSH keys, cloud credentials and Kubernetes tokens, and sent them out | act | Python: 2 versions, 2 files | [docs.litellm.ai](https://docs.litellm.ai/blog/security-update-march-2026) |
| OpenCode Console | October 2026 | a breach hit 1.4% of Console users, some of those who had linked external providers | leak | its CLI or app | [x.com](https://x.com/opencode/status/2111519637049319818) |
| Railway | October 2026 | an attacker may have accessed encrypted environment variables and obtained the decrypted contents of some | leak | its CLI or app | [blog.railway.com](https://blog.railway.com/p/security-disclosure-wednesday-october-21st) |
| Zeabur | October 2026 | an attacker read environment variables and secrets stored on the platform | leak | its CLI or app | [zeabur.com](https://zeabur.com/blogs/october-2026-security-incident) |
| GlassWorm extensions | January 2026 | malicious Open VSX extensions; on Macs, its payload stole credentials, keychains and crypto wallets | act | 17 extensions, 1 file | [socket.dev](https://socket.dev/blog/glassworm-loader-hits-open-vsx-via-suspected-developer-account-compromise) |
| GlassWorm extensions | March 2026 | ran attacker code in memory that could reach local credentials, tokens and secrets | act | 59 extensions | [socket.dev](https://socket.dev/blog/open-vsx-transitive-glassworm-campaign) |
| GlassWorm sleeper extensions | March 2026 | installed a malicious extension from GitHub into every editor it found | act | 22 extensions | [socket.dev](https://socket.dev/blog/glassworm-sleeper-extensions-activated-on-open-vsx) |
| GlassWorm sleeper extensions | April 2026 | updated cloned extensions to install malware from GitHub into VS Code, Cursor and Windsurf | act | 6 extensions | [socket.dev](https://socket.dev/blog/73-open-vsx-sleeper-extensions-glassworm) |
| GlassWorm extensions | April 2026 | native code in an extension installed a GlassWorm dropper into every editor it found | act | 2 extensions | [aikido.dev](https://www.aikido.dev/blog/glassworm-zig-dropper-infects-every-ide-on-your-machine) |
| GlassWorm native extensions | November 2025 | Rust binaries in the extensions fetched and decrypted further payloads on macOS and Windows | act | 31 extensions | [paloaltonetworks.com](https://www.paloaltonetworks.com/blog/security-operations/glassworm-goes-native-rust-loader-vscode-openvsx/) |
| GlassWorm-linked themes | December 2025 | a VS Code theme cluster tied to GlassWorm; two of its themes ran hidden loaders | act | 2 extensions | [socket.dev](https://socket.dev/blog/glassworm-vscode-themes) |
| GlassWorm invisible code | March 2026 | hid code in characters that show as blank, which it then decodes and runs | act | npm: 6 versions of 2 packages, 1 extension | [aikido.dev](https://www.aikido.dev/blog/glassworm-returns-unicode-attack-github-npm-vscode) |
| GlassWASM extensions | June 2026 | clones of Marketplace extensions on Open VSX, built to download and run a second stage | act | 2 extensions | [socket.dev](https://socket.dev/blog/glasswasm-malware-open-vsx-extensions) |
| Injective SDK | July 2026 | sent out the seed phrases and hex private keys of wallets created or loaded with it | update | npm: 1 version of 1 package | [github.com](https://github.com/advisories/GHSA-5fc4-fm2x-6f4r) |

### Python packages

| Package | Version | Incident | Its malware runs on |
|---|---|---|---|
| `litellm` | 1.107.0 | LiteLLM 1.107.0 | any system |
| `litellm` | 1.82.7 | LiteLLM 1.82.7 and 1.82.8 | any system |
| `litellm` | 1.82.8 | LiteLLM 1.82.7 and 1.82.8 | any system |
| `mistralai` | 2.4.6 | mistralai 2.4.6 | Linux |
| `guardrails_ai` | 0.10.1 | guardrails-ai 0.10.1 | Linux |
| `lightning` | 2.6.2 | lightning 2.6.2 and 2.6.3 | any system |
| `lightning` | 2.6.3 | lightning 2.6.2 and 2.6.3 | any system |
| `durabletask` | 1.4.1 | durabletask 1.4.1 to 1.4.3 | Linux |
| `durabletask` | 1.4.2 | durabletask 1.4.1 to 1.4.3 | Linux |
| `durabletask` | 1.4.3 | durabletask 1.4.1 to 1.4.3 | Linux |
| `telnyx` | 4.87.1 | telnyx 4.87.1 and 4.87.2 | none: a version to update |
| `telnyx` | 4.87.2 | telnyx 4.87.1 and 4.87.2 | any system |

### Files malware leaves on disk

gh-token-monitor, the wiper: stop it before you revoke any GitHub token.

- `~/Library/LaunchAgents/com.user.gh-token-monitor.plist`
- `~/.config/systemd/user/gh-token-monitor.service`
- `~/.local/bin/gh-token-monitor.sh`
- `~/.config/gh-token-monitor`
- `/tmp/gh-token-monitor.out.log` (counts only when it is yours)
- `/tmp/gh-token-monitor.err.log` (counts only when it is yours)
- `{LOCALAPPDATA}/gh-token-monitor` (Windows only)

mistralai 2.4.6, May 2026:

- `transformers.pyz`: in the temp folder (Linux only) (counts only when it is yours)

If found: Mistral lists this file, and a process started through python /tmp/transformers.pyz, as signs of the stealer: clean this machine, rotate all secrets it could reach and check cloud audit logs for suspicious activity.

guardrails-ai 0.10.1, May 2026:

- `transformers.pyz`: in the temp folder (Linux only) (counts only when it is yours)

If found: SafeDep shows guardrails-ai 0.10.1 writing this file on Linux and running it. Guardrails AI says to treat such a machine as compromised: rotate every credential it could reach and check your GitHub account for workflows, repositories or commits you did not make.

durabletask 1.4.1 to 1.4.3, May 2026:

- `managed.pyz`: in the temp folder (Linux only) (counts only when it is yours)

If found: Wiz lists this file as the payload it downloads: stop any python3 process running /tmp/managed.pyz, then rotate every secret this machine could reach and rebuild it, as GitHub's malware advisory says.

telnyx 4.87.1 and 4.87.2, March 2026:

- `~/.config/audiomon/audiomon.py`: the backdoor the telnyx malware leaves, which a systemd service starts at login on Linux (macOS and Linux only)
- `~/.config/systemd/user/audiomon.service`: starts the backdoor the telnyx malware leaves, at login (Linux only)
- `~/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/msbuild.exe`: the telnyx malware, which Windows starts at every login from the Startup folder (Windows only)
- `.initd_state`: in the temp folder (macOS and Linux only) (counts only when it is yours)

If found: Telnyx lists this file as the malware's state file: treat every secret this machine could reach as compromised and rotate it, then remove telnyx and pin 4.87.0, as Telnyx says.

Mastra npm packages, June 2026:

- `~/Library/LaunchAgents/com.nvm.protocal.plist`: starts the Mastra malware at login
- `~/Library/NodePackages/protocal.cjs`: the Mastra malware itself, set to run at every login
- `~/.config/systemd/user/nvmconf.service`: starts the Mastra malware at login
- `~/.config/systemd/nvmconf/protocal.cjs`: the Mastra malware itself, set to run at every login
- `{PROGRAMDATA}/NodePackages/protocal.cjs`: the Mastra malware itself, set to run at every login (Windows only)

AntV account takeover, May 2026:

- `~/.config/systemd/user/kitty-monitor.service`: starts the AntV wave's kitty-monitor backdoor at login
- `~/Library/LaunchAgents/com.user.kitty-monitor.plist`: starts the AntV wave's kitty-monitor backdoor at login
- `~/.local/share/kitty/cat.py`: the AntV wave's kitty-monitor backdoor, which its service starts at login
- `~/.claude/package/index.js`: a copy of the AntV wave's payload, run by the hooks it adds to agent settings
- `~/.codex/package/index.js`: a copy of the AntV wave's payload, run by the hooks it adds to agent settings

Nx Console 18.95.0, May 2026:

- `~/Library/LaunchAgents/com.user.kitty-monitor.plist`: starts the kitty-monitor backdoor Nx Console 18.95.0 installed, at login
- `~/.local/share/kitty/cat.py`: the kitty-monitor backdoor Nx Console 18.95.0 installed

LiteLLM 1.107.0, October 2026:

- `cook.pth`: in a Python environment's site-packages
- `cook.py`: in a Python environment's site-packages
- `remote_code_loader.lock`: in the temp folder (counts only when it is yours)
- `.pc_once_*`: in the temp folder (counts only when it is yours)
- `.pc_sq_*`: in the temp folder (counts only when it is yours)
- `.pc_e_*`: in the temp folder (counts only when it is yours)

If found: These markers mean the malware ran here, and a .pc\_once\_ file that it sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote\_code\_loader.lock. Don't run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in \_\_pycache\_\_ are deleted from it.

LiteLLM 1.82.7 and 1.82.8, March 2026:

- `litellm_init.pth`: in a Python environment's site-packages
- `~/.config/sysmon/sysmon.py`: the backdoor the March LiteLLM malware leaves, which a systemd service starts at login on Linux

GlassWorm extensions, January 2026:

- `~/Library/LaunchAgents/com.user.nodestart.plist`: starts the GlassWorm malware at login

### Hosted platforms that leaked stored secrets

- **OpenCode**, found by the `opencode` command or `~/.config/opencode/`, `~/.local/share/opencode/`: OpenCode emailed the Console users its breach hit, and says those it did not email were not affected. It told those users to revoke and replace their keys directly with each provider. Keys kept only in the CLI never reach OpenCode.
- **Railway**, found by the `railway` command or `~/.railway/config.json`: Railway asked all users to rotate every environment variable stored there, including API keys and private registry credentials, and to review their logs for unusual activity.
- **Zeabur**, found by the `zeabur` command or `~/.config/zeabur/`: Zeabur said on 19 October that an attacker read the service environment variables stored on the platform, and asked users to replace every password and key stored there. Revoke each old key at its provider first.

### Editor extensions that shipped malware

<details><summary>Nx Console 18.95.0, May 2026: 1 extension</summary>

- `nrwl.angular-console` 18.95.0 (every editor)

</details>

<details><summary>GlassWorm extensions, January 2026: 17 extensions</summary>

- `oorzc.ssh-tools` 0.5.1 (Open VSX editors only; its malware runs on macOS)
- `oorzc.i18n-tools-plus` 1.6.8 (Open VSX editors only; its malware runs on macOS)
- `oorzc.mind-map` 1.0.61 (Open VSX editors only; its malware runs on macOS)
- `oorzc.scss-to-css-compile` 1.3.4 (Open VSX editors only; its malware runs on macOS)
- `Angular-studio.ng-angular-extension` every version (Open VSX editors only)
- `awesome-codebase.codebase-dart-pro` every version (Open VSX editors only)
- `cudra-production.vsce-prettier-pro` every version (Open VSX editors only)
- `dev-studio-sense.php-comp-tools-vscode` every version (Open VSX editors only)
- `ko-zu-gun-studio.synchronization-settings-vscode` every version (Open VSX editors only)
- `littensy-studio.magical-icons` every version (Open VSX editors only)
- `pretty-studio-advisor.prettyxml-formatter` every version (Open VSX editors only)
- `sol-studio.solidity-extension` every version (Open VSX editors only)
- `studio-jjalaire-team.professional-quarto-extension` every version (Open VSX editors only)
- `studio-velte-distributor.pro-svelte-extension` every version (Open VSX editors only)
- `sun-shine-studio.shiny-extension-for-vscode` every version (Open VSX editors only)
- `tucyzirille-studio.angular-pro-tools-extension` every version (Open VSX editors only)
- `vce-brendan-studio-eich.js-debuger-vscode` every version (Open VSX editors only)

</details>

<details><summary>GlassWorm extensions, March 2026: 59 extensions</summary>

- `aadarkcode.one-dark-material` every version (Open VSX editors only)
- `aligntool.extension-align-professional-tool` every version (Open VSX editors only)
- `awesomeco.wonder-for-vscode-icons` every version (Open VSX editors only)
- `bhbpbarn.vsce-python-indent-extension` every version (Open VSX editors only)
- `blockstoks.easily-gitignore-manage` every version (Open VSX editors only)
- `brategmaqendaalar-studio.pro-prettyxml-formatter` every version (Open VSX editors only)
- `codbroks.compile-runnner-extension` every version (Open VSX editors only)
- `codevunmis.csv-sql-tsv-rainbow` every version (Open VSX editors only)
- `codwayexten.code-way-extension` every version (Open VSX editors only)
- `cosmic-themes.sql-formatter` every version (Open VSX editors only)
- `craz2team.vscode-todo-extension` every version (Open VSX editors only)
- `crotoapp.vscode-xml-extension` every version (Open VSX editors only)
- `daeumer-web.es-linter-for-vs-code` every version (Open VSX editors only)
- `dark-code-studio.flutter-extension` every version (Open VSX editors only)
- `densy-little-studio.wonder-for-vscode-icons` every version (Open VSX editors only)
- `dep-labs-studio.dep-proffesinal-extension` every version (Open VSX editors only)
- `devmidu-studio.svg-better-extension` every version (Open VSX editors only)
- `dopbop-studio.vscode-tailwindcss-extension-toolkit` every version (every editor)
- `errlenscre.error-lens-finder-ex` every version (Open VSX editors only)
- `exss-studio.yaml-professional-extension` every version (Open VSX editors only)
- `federicanc.dotenv-syntax-highlighting` every version (Open VSX editors only)
- `flutxvs.vscode-kuberntes-extension` every version (Open VSX editors only)
- `gvotcha.claude-code-extension` every version (Open VSX editors only)
- `gvotcha.claude-code-extensions` every version (Open VSX editors only)
- `intellipro.extension-json-intelligence` every version (Open VSX editors only)
- `kharizma.vscode-extension-wakatime` every version (Open VSX editors only)
- `kwitch-studio.auto-run-command-extension` every version (every editor)
- `lavender-studio.theme-lavender-dreams` every version (every editor)
- `lyu-wen-studio-web-han.better-formatter-vscode` every version (Open VSX editors only)
- `markvalid.vscode-mdvalidator-extension` every version (Open VSX editors only)
- `mecreation-studio.pyrefly-pro-extension` every version (Open VSX editors only)
- `mswincx.antigravity-cockpit` every version (Open VSX editors only)
- `mswincx.antigravity-cockpit-extension` every version (Open VSX editors only)
- `namopins.prettier-pro-vscode-extension` every version (Open VSX editors only)
- `oigotm.my-command-palette-extension` every version (Open VSX editors only)
- `otoboss.autoimport-extension` every version (Open VSX editors only)
- `ovixcode.vscode-better-comments` every version (Open VSX editors only)
- `pessa07tm.my-js-ts-auto-commands` every version (Open VSX editors only)
- `potstok.dotnet-runtime-extension` every version (every editor)
- `prismapp.prisma-vs-code-extension` every version (Open VSX editors only)
- `projmanager.your-project-manager-extension` every version (Open VSX editors only)
- `pubruncode.ccoderunner` every version (Open VSX editors only)
- `pyflowpyr.py-flowpyright-extension` every version (Open VSX editors only)
- `pyscopexte.pyscope-extension` every version (Open VSX editors only)
- `redcapcollective.vscode-quarkus-elite-suite` every version (Open VSX editors only)
- `rubyideext.ruby-ide-extension` every version (Open VSX editors only)
- `runnerpost.runner-your-code` every version (Open VSX editors only)
- `shinypy.shiny-extension-for-vscode` every version (Open VSX editors only)
- `ssgwysc.volar-vscode` every version (Open VSX editors only)
- `sxatvo.jinja-extension` every version (Open VSX editors only)
- `tamokill12.foundry-pdf-extension` every version (Open VSX editors only)
- `thing-mn.your-flow-extension-for-icons` every version (Open VSX editors only)
- `tima-web-wang.shell-check-utils` every version (Open VSX editors only)
- `tokcodes.import-cost-extension` every version (Open VSX editors only)
- `toowespace.worksets-extension` every version (Open VSX editors only)
- `treedotree.tree-do-todoextension` every version (Open VSX editors only)
- `turbobase.sql-turbo-tool` every version (Open VSX editors only)
- `twilkbilk.color-highlight-css` every version (Open VSX editors only)
- `yamaprolas.revature-labs-extension` every version (Open VSX editors only)

</details>

<details><summary>GlassWorm sleeper extensions, March 2026: 22 extensions</summary>

- `lauracode.wrap-selected-code` 0.0.2 (Open VSX editors only)
- `96-studio.json-formatter` 0.0.2 (Open VSX editors only)
- `96-studio.json-formatter` 0.0.4 (Open VSX editors only)
- `spacetoow.vsc-python-indent` 1.21.1 (Open VSX editors only)
- `spacetoow.vsc-python-indent` 1.21.3 (Open VSX editors only)
- `spacetoow.vsc-python-indent` 1.21.4 (Open VSX editors only)
- `spacetoow.vsc-python-indent` 1.21.5 (Open VSX editors only)
- `spacetoow.vsc-python-indent` 1.21.6 (Open VSX editors only)
- `spacetoow.vsc-python-indent` 1.21.7 (Open VSX editors only)
- `namop-dex.claude-code-assistant` 2.1.47 (Open VSX editors only)
- `msw-tm.component-vetur-toolkit` 0.37.4 (Open VSX editors only)
- `cod-vok.arko-dev-devsecops` 1.0.4 (Open VSX editors only)
- `oxigener-tmp.sql-turbo-manager` 0.28.10 (Open VSX editors only)
- `otobo-vs.csv-query-tsv-rainbow` 3.3.4 (Open VSX editors only)
- `awesome-codespace.jinja-language-support` 0.3.2 (Open VSX editors only)
- `yamal-dext.wonder-workspace-icons` 0.10.4 (Open VSX editors only)
- `daeumer-web.align-format-tool` 1.4.6 (Open VSX editors only)
- `baksmink.vscode-quokka-extension` 1.0.756 (Open VSX editors only)
- `bansheejust22.retro-vhs-theme` 1.0.1 (Open VSX editors only)
- `quickrunn.auto-run-command-quick` 1.6.2 (Open VSX editors only)
- `craz2team.vscode-todo-extension` 1.0.9 (Open VSX editors only)
- `craz2team.vscode-todo-extension` 1.0.10 (Open VSX editors only)

</details>

<details><summary>GlassWorm sleeper extensions, April 2026: 6 extensions</summary>

- `outsidestormcommand.monochromator-theme` every version (Open VSX editors only)
- `keyacrosslaud.auto-loop-for-antigravity` every version (Open VSX editors only)
- `krundoven.ironplc-fast-hub` every version (Open VSX editors only)
- `boulderzitunnel.vscode-buddies` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `cubedivervolt.html-code-validate` every version (Open VSX editors only)
- `winnerdomain17.version-lens-tool` every version (Open VSX editors only)

</details>

<details><summary>GlassWorm extensions, April 2026: 2 extensions</summary>

- `specstudio.code-wakatime-activity-tracker` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `floktokbok.autoimport` every version (every editor)

</details>

<details><summary>GlassWorm native extensions, November 2025: 31 extensions</summary>

- `bphpburn.icons-vscode` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `clangdcode.clangd-vscode` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `csvmech.csv-sql-tsv-rainbow` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `iconkief.icon-theme-material` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `msjsdreact.react-native-vscode` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `saoudrizvsce.claude-dev` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `solblanco.svelte-vscode` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `tailwind-nuxt.tailwindcss-for-react` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `vitalik.solidity` every version (Open VSX editors only; its malware runs on macOS and Windows)
- `bphpburnsus.iconesvscode` 12.15.1 (every editor; its malware runs on macOS and Windows)
- `bphpburnsus.iconesvscode` 12.15.2 (every editor; its malware runs on macOS and Windows)
- `cweijamysq.sync-settings-vscode` every version (every editor; its malware runs on macOS and Windows)
- `eamodas.shiny-vscode` every version (every editor; its malware runs on macOS and Windows)
- `flutcode.flutter-extension` every version (every editor; its malware runs on macOS and Windows)
- `saoudrizvsce.claude-devsce` every version (every editor; its malware runs on macOS and Windows)
- `svltsweet.svetle-for-cursor` every version (every editor; its malware runs on macOS and Windows)
- `yamlcode.yaml-vscode-extension` every version (every editor; its malware runs on macOS and Windows)
- `iconkieftwo.icon-theme-materiall` every version (every editor; its malware runs on macOS and Windows)
- `clangdcode.clangd-vsce` every version (every editor; its malware runs on macOS and Windows)
- `codevsce.codelddb-vscode` every version (every editor; its malware runs on macOS and Windows)
- `csvmech.csvrainbow` every version (every editor; its malware runs on macOS and Windows)
- `dart-vsc.code-dart` every version (every editor; its malware runs on macOS and Windows)
- `klustfix.kluster-code-verify` every version (every editor; its malware runs on macOS and Windows)
- `lyywemhan.code-formatter-and-minifier-vscode` every version (every editor; its malware runs on macOS and Windows)
- `msjsdreact.react-native-vsce` every version (every editor; its malware runs on macOS and Windows)
- `prettier-vsc.vsce-prettier` every version (every editor; its malware runs on macOS and Windows)
- `prisma-inc.prisma-studio-assistance` every version (every editor; its malware runs on macOS and Windows)
- `redmat.vscode-quarkus-pro` every version (every editor; its malware runs on macOS and Windows)
- `solblanco.svetle-vsce` every version (every editor; its malware runs on macOS and Windows)
- `vims-vsce.vscode-vim` every version (every editor; its malware runs on macOS and Windows)
- `vsceue.volar-vscode` every version (every editor; its malware runs on macOS and Windows)

</details>

<details><summary>GlassWorm-linked themes, December 2025: 2 extensions</summary>

- `microsoftvs.microsoftvs` every version (every editor; its malware runs on Windows)
- `cosmic-themes.theme-cosmic-nebula` every version (every editor)

</details>

<details><summary>GlassWorm invisible code, March 2026: 1 extension</summary>

- `quartz.quartz-markdown-editor` 0.3.0 (every editor)

</details>

<details><summary>GlassWASM extensions, June 2026: 2 extensions</summary>

- `exargd.vsblack` 0.0.1 (Open VSX editors only)
- `noellee-doc.flint-debug` 0.1.1 (Open VSX editors only)

</details>

### npm packages

<details><summary>Axios takeover, March 2026: 3 versions of 2 packages</summary>

- `axios` 1.14.1, 0.30.4
- `plain-crypto-js` every version

</details>

<details><summary>TanStack worm, May 2026: 326 versions of 100 packages</summary>

- `@tanstack/arktype-adapter` 1.166.12, 1.166.15
- `@tanstack/eslint-plugin-router` 1.161.9, 1.161.12
- `@tanstack/eslint-plugin-start` 0.0.4, 0.0.7
- `@tanstack/history` 1.161.9, 1.161.12
- `@tanstack/nitro-v2-vite-plugin` 1.154.12, 1.154.15
- `@tanstack/react-router` 1.169.5, 1.169.8
- `@tanstack/react-router-devtools` 1.166.16, 1.166.19
- `@tanstack/react-router-ssr-query` 1.166.15, 1.166.18
- `@tanstack/react-start` 1.167.68, 1.167.71
- `@tanstack/react-start-client` 1.166.51, 1.166.54
- `@tanstack/react-start-rsc` 0.0.47, 0.0.50
- `@tanstack/react-start-server` 1.166.55, 1.166.58
- `@tanstack/router-cli` 1.166.46, 1.166.49
- `@tanstack/router-core` 1.169.5, 1.169.8
- `@tanstack/router-devtools` 1.166.16, 1.166.19
- `@tanstack/router-devtools-core` 1.167.6, 1.167.9
- `@tanstack/router-generator` 1.166.45, 1.166.48
- `@tanstack/router-plugin` 1.167.38, 1.167.41
- `@tanstack/router-ssr-query-core` 1.168.3, 1.168.6
- `@tanstack/router-utils` 1.161.11, 1.161.14
- `@tanstack/router-vite-plugin` 1.166.53, 1.166.56
- `@tanstack/solid-router` 1.169.5, 1.169.8
- `@tanstack/solid-router-devtools` 1.166.16, 1.166.19
- `@tanstack/solid-router-ssr-query` 1.166.15, 1.166.18
- `@tanstack/solid-start` 1.167.65, 1.167.68
- `@tanstack/solid-start-client` 1.166.50, 1.166.53
- `@tanstack/solid-start-server` 1.166.54, 1.166.57
- `@tanstack/start-client-core` 1.168.5, 1.168.8
- `@tanstack/start-fn-stubs` 1.161.9, 1.161.12
- `@tanstack/start-plugin-core` 1.169.23, 1.169.26
- `@tanstack/start-server-core` 1.167.33, 1.167.36
- `@tanstack/start-static-server-functions` 1.166.44, 1.166.47
- `@tanstack/start-storage-context` 1.166.38, 1.166.41
- `@tanstack/valibot-adapter` 1.166.12, 1.166.15
- `@tanstack/virtual-file-routes` 1.161.10, 1.161.13
- `@tanstack/vue-router` 1.169.5, 1.169.8
- `@tanstack/vue-router-devtools` 1.166.16, 1.166.19
- `@tanstack/vue-router-ssr-query` 1.166.15, 1.166.18
- `@tanstack/vue-start` 1.167.61, 1.167.64
- `@tanstack/vue-start-client` 1.166.46, 1.166.49
- `@tanstack/vue-start-server` 1.166.50, 1.166.53
- `@tanstack/zod-adapter` 1.166.12, 1.166.15
- `@beproduct/nestjs-auth` 0.1.2, 0.1.3, 0.1.4, 0.1.5, 0.1.6, 0.1.7, 0.1.8, 0.1.9, 0.1.10, 0.1.11, 0.1.12, 0.1.13, 0.1.14, 0.1.15, 0.1.16, 0.1.17, 0.1.18, 0.1.19
- `@dirigible-ai/sdk` 0.6.2, 0.6.3
- `@draftauth/client` 0.2.1, 0.2.2
- `@draftauth/core` 0.13.1, 0.13.2
- `@draftlab/auth` 0.24.1, 0.24.2
- `@draftlab/auth-router` 0.5.1, 0.5.2
- `@draftlab/db` 0.16.1, 0.16.2
- `@mesadev/rest` 0.28.3
- `@mesadev/saguaro` 0.4.22
- `@mesadev/sdk` 0.28.3
- `@ml-toolkit-ts/preprocessing` 1.0.2, 1.0.3
- `@ml-toolkit-ts/xgboost` 1.0.3, 1.0.4
- `@squawk/airport-data` 0.7.4, 0.7.5, 0.7.6, 0.7.7, 0.7.8
- `@squawk/airports` 0.6.2, 0.6.3, 0.6.4, 0.6.5, 0.6.6
- `@squawk/airspace` 0.8.1, 0.8.2, 0.8.3, 0.8.4, 0.8.5
- `@squawk/airspace-data` 0.5.3, 0.5.4, 0.5.5, 0.5.6, 0.5.7
- `@squawk/airway-data` 0.5.4, 0.5.5, 0.5.6, 0.5.7, 0.5.8
- `@squawk/airways` 0.4.2, 0.4.3, 0.4.4, 0.4.5, 0.4.6
- `@squawk/fix-data` 0.6.4, 0.6.5, 0.6.6, 0.6.7, 0.6.8
- `@squawk/fixes` 0.3.2, 0.3.3, 0.3.4, 0.3.5, 0.3.6
- `@squawk/flight-math` 0.5.4, 0.5.5, 0.5.6, 0.5.7, 0.5.8
- `@squawk/flightplan` 0.5.2, 0.5.3, 0.5.4, 0.5.5, 0.5.6
- `@squawk/geo` 0.4.4, 0.4.5, 0.4.6, 0.4.7, 0.4.8
- `@squawk/icao-registry` 0.5.2, 0.5.3, 0.5.4, 0.5.5, 0.5.6
- `@squawk/icao-registry-data` 0.8.4, 0.8.5, 0.8.6, 0.8.7, 0.8.8
- `@squawk/mcp` 0.9.1, 0.9.2, 0.9.3, 0.9.4, 0.9.5
- `@squawk/navaid-data` 0.6.4, 0.6.5, 0.6.6, 0.6.7, 0.6.8
- `@squawk/navaids` 0.4.2, 0.4.3, 0.4.4, 0.4.5, 0.4.6
- `@squawk/notams` 0.3.6, 0.3.7, 0.3.8, 0.3.9, 0.3.10
- `@squawk/procedure-data` 0.7.3, 0.7.4, 0.7.5, 0.7.6, 0.7.7
- `@squawk/procedures` 0.5.2, 0.5.3, 0.5.4, 0.5.5, 0.5.6
- `@squawk/types` 0.8.1, 0.8.2, 0.8.3, 0.8.4, 0.8.5
- `@squawk/units` 0.4.3, 0.4.4, 0.4.5, 0.4.6, 0.4.7
- `@squawk/weather` 0.5.6, 0.5.7, 0.5.8, 0.5.9, 0.5.10
- `@supersurkhet/cli` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7
- `@supersurkhet/sdk` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7
- `@tallyui/components` 1.0.1, 1.0.2, 1.0.3
- `@tallyui/connector-medusa` 1.0.1, 1.0.2, 1.0.3
- `@tallyui/connector-shopify` 1.0.1, 1.0.2, 1.0.3
- `@tallyui/connector-vendure` 1.0.1, 1.0.2, 1.0.3
- `@tallyui/connector-woocommerce` 1.0.1, 1.0.2, 1.0.3
- `@tallyui/core` 0.2.1, 0.2.2, 0.2.3
- `@tallyui/database` 1.0.1, 1.0.2, 1.0.3
- `@tallyui/pos` 0.1.1, 0.1.2, 0.1.3
- `@tallyui/storage-sqlite` 0.2.1, 0.2.2, 0.2.3
- `@tallyui/theme` 0.2.1, 0.2.2, 0.2.3
- `@taskflow-corp/cli` 0.1.24, 0.1.25, 0.1.26, 0.1.27, 0.1.28, 0.1.29
- `@tolka/cli` 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6
- `agentwork-cli` 0.1.4, 0.1.5
- `cmux-agent-mcp` 0.1.3, 0.1.4, 0.1.5, 0.1.6, 0.1.7, 0.1.8
- `cross-stitch` 1.1.3, 1.1.4, 1.1.5, 1.1.6, 1.1.7
- `git-branch-selector` 1.3.3, 1.3.4, 1.3.5, 1.3.6, 1.3.7
- `git-git-git` 1.0.8, 1.0.9, 1.0.10, 1.0.11, 1.0.12
- `ml-toolkit-ts` 1.0.4, 1.0.5
- `nextmove-mcp` 0.1.3, 0.1.4, 0.1.5, 0.1.6, 0.1.7
- `safe-action` 0.8.3, 0.8.4
- `ts-dna` 3.0.1, 3.0.2, 3.0.3, 3.0.4, 3.0.5
- `wot-api` 0.8.1, 0.8.2, 0.8.3, 0.8.4, 0.8.5

</details>

<details><summary>Mistral AI npm packages, May 2026: 9 versions of 3 packages</summary>

- `@mistralai/mistralai` 2.2.2, 2.2.3, 2.2.4
- `@mistralai/mistralai-azure` 1.7.1, 1.7.2, 1.7.3
- `@mistralai/mistralai-gcp` 1.7.1, 1.7.2, 1.7.3

</details>

<details><summary>UiPath npm packages, May 2026: 66 versions of 66 packages</summary>

- `@uipath/access-policy-sdk` 0.3.1
- `@uipath/access-policy-tool` 0.3.1
- `@uipath/admin-tool` 0.1.1
- `@uipath/agent-sdk` 1.0.2
- `@uipath/agent-tool` 1.0.1
- `@uipath/agent.sdk` 0.0.18
- `@uipath/aops-policy-tool` 0.3.1
- `@uipath/ap-chat` 1.5.7
- `@uipath/api-workflow-tool` 1.0.1
- `@uipath/apollo-core` 5.9.2
- `@uipath/apollo-react` 4.24.5
- `@uipath/apollo-wind` 2.16.2
- `@uipath/auth` 1.0.1
- `@uipath/case-tool` 1.0.1
- `@uipath/cli` 1.0.1
- `@uipath/codedagent-tool` 1.0.1
- `@uipath/codedagents-tool` 0.1.12
- `@uipath/codedapp-tool` 1.0.1
- `@uipath/common` 1.0.1
- `@uipath/context-grounding-tool` 0.1.1
- `@uipath/data-fabric-tool` 1.0.2
- `@uipath/docsai-tool` 1.0.1
- `@uipath/filesystem` 1.0.1
- `@uipath/flow-tool` 1.0.2
- `@uipath/functions-tool` 1.0.1
- `@uipath/gov-tool` 0.3.1
- `@uipath/identity-tool` 0.1.1
- `@uipath/insights-sdk` 1.0.1
- `@uipath/insights-tool` 1.0.1
- `@uipath/integrationservice-sdk` 1.0.2
- `@uipath/integrationservice-tool` 1.0.2
- `@uipath/llmgw-tool` 1.0.1
- `@uipath/maestro-sdk` 1.0.1
- `@uipath/maestro-tool` 1.0.1
- `@uipath/orchestrator-tool` 1.0.1
- `@uipath/packager-tool-apiworkflow` 0.0.19
- `@uipath/packager-tool-bpmn` 0.0.9
- `@uipath/packager-tool-case` 0.0.9
- `@uipath/packager-tool-connector` 0.0.19
- `@uipath/packager-tool-flow` 0.0.19
- `@uipath/packager-tool-functions` 0.1.1
- `@uipath/packager-tool-webapp` 1.0.6
- `@uipath/packager-tool-workflowcompiler` 0.0.16
- `@uipath/packager-tool-workflowcompiler-browser` 0.0.34
- `@uipath/platform-tool` 1.0.1
- `@uipath/project-packager` 1.1.16
- `@uipath/resource-tool` 1.0.1
- `@uipath/resourcecatalog-tool` 0.1.1
- `@uipath/resources-tool` 0.1.11
- `@uipath/robot` 1.3.4
- `@uipath/rpa-legacy-tool` 1.0.1
- `@uipath/rpa-tool` 0.9.5
- `@uipath/solution-packager` 0.0.35
- `@uipath/solution-tool` 1.0.1
- `@uipath/solutionpackager-sdk` 1.0.11
- `@uipath/solutionpackager-tool-core` 0.0.34
- `@uipath/tasks-tool` 1.0.1
- `@uipath/telemetry` 0.0.7
- `@uipath/test-manager-tool` 1.0.2
- `@uipath/tool-workflowcompiler` 0.0.12
- `@uipath/traces-tool` 1.0.1
- `@uipath/ui-widgets-multi-file-upload` 1.0.1
- `@uipath/uipath-python-bridge` 1.0.1
- `@uipath/vertical-solutions-tool` 1.0.1
- `@uipath/vss` 0.1.6
- `@uipath/widget.sdk` 1.2.3

</details>

<details><summary>OpenSearch client, May 2026: 4 versions of 1 package</summary>

- `@opensearch-project/opensearch` 3.5.3, 3.6.2, 3.7.0, 3.8.0

</details>

<details><summary>Bitwarden CLI, April 2026: 1 version of 1 package</summary>

- `@bitwarden/cli` 2026.4.0

</details>

<details><summary>Mini Shai-Hulud worm, April 2026: 5 versions of 5 packages</summary>

- `@cap-js/db-service` 2.10.1
- `@cap-js/postgres` 2.2.2
- `@cap-js/sqlite` 2.2.2
- `mbt` 1.2.48
- `intercom-client` 7.0.4

</details>

<details><summary>Mastra npm packages, June 2026: 94 versions of 94 packages</summary>

- `@mastra/core` 1.42.1
- `mastra` 1.13.1
- `create-mastra` 1.13.1
- `easy-day-js` 1.11.22
- `@mastra/agent-browser` 0.3.2
- `@mastra/agent-builder` 1.0.42
- `@mastra/ai-sdk` 1.4.6
- `@mastra/arize` 1.2.3
- `@mastra/auth` 1.0.3
- `@mastra/auth-auth0` 1.0.2
- `@mastra/auth-better-auth` 1.0.4
- `@mastra/auth-clerk` 1.0.3
- `@mastra/auth-supabase` 1.0.2
- `@mastra/auth-workos` 1.5.3
- `@mastra/blaxel` 0.4.2
- `@mastra/braintrust` 1.1.4
- `@mastra/chroma` 1.0.2
- `@mastra/claude` 1.0.3
- `@mastra/clickhouse` 1.10.1
- `@mastra/client-js` 1.24.1
- `@mastra/cloudflare` 1.4.2
- `@mastra/cloudflare-d1` 1.0.7
- `@mastra/convex` 1.2.2
- `@mastra/couchbase` 1.0.4
- `@mastra/cursor` 0.2.1
- `@mastra/datadog` 1.2.5
- `@mastra/daytona` 0.4.2
- `@mastra/deployer` 1.42.1
- `@mastra/deployer-cloudflare` 1.1.44
- `@mastra/deployer-netlify` 1.1.20
- `@mastra/deployer-vercel` 1.1.38
- `@mastra/docker` 0.3.1
- `@mastra/dsql` 1.0.3
- `@mastra/duckdb` 1.4.3
- `@mastra/dynamodb` 1.0.9
- `@mastra/e2b` 0.3.4
- `@mastra/editor` 0.11.3
- `@mastra/evals` 1.3.1
- `@mastra/express` 1.3.31
- `@mastra/fastembed` 1.1.3
- `@mastra/fastify` 1.3.31
- `@mastra/gcs` 0.2.3
- `@mastra/github-signals` 0.1.2
- `@mastra/google-cloud-pubsub` 1.0.6
- `@mastra/hono` 1.4.26
- `@mastra/inngest` 1.5.2
- `@mastra/koa` 1.5.14
- `@mastra/langfuse` 1.3.6
- `@mastra/langsmith` 1.2.4
- `@mastra/libsql` 1.13.1
- `@mastra/loggers` 1.1.3
- `@mastra/longmemeval` 1.0.50
- `@mastra/mcp` 1.10.1
- `@mastra/mcp-docs-server` 1.1.47
- `@mastra/mcp-registry-registry` 1.0.2
- `@mastra/mem0` 0.1.14
- `@mastra/memory` 1.20.4
- `@mastra/mongodb` 1.9.3
- `@mastra/mssql` 1.3.2
- `@mastra/nestjs` 0.1.15
- `@mastra/node-audio` 0.1.8
- `@mastra/node-speaker` 0.1.1
- `@mastra/observability` 1.14.2
- `@mastra/otel-bridge` 1.2.3
- `@mastra/otel-exporter` 1.2.3
- `@mastra/pg` 1.13.1
- `@mastra/pinecone` 1.0.2
- `@mastra/playground-ui` 33.0.1
- `@mastra/posthog` 1.0.29
- `@mastra/qdrant` 1.0.3
- `@mastra/rag` 2.2.2
- `@mastra/react` 1.0.1
- `@mastra/redis` 1.1.3
- `@mastra/s3` 0.5.3
- `@mastra/s3vectors` 1.0.7
- `@mastra/schema-compat` 1.2.12
- `@mastra/sentry` 1.1.4
- `@mastra/server` 2.1.1
- `@mastra/stagehand` 0.2.5
- `@mastra/tavily` 1.0.3
- `@mastra/temporal` 0.1.14
- `@mastra/turbopuffer` 1.0.3
- `@mastra/upstash` 1.1.3
- `@mastra/vectorize` 1.0.3
- `@mastra/voice-aws-nova-sonic` 0.1.4
- `@mastra/voice-deepgram` 0.12.2
- `@mastra/voice-elevenlabs` 0.12.2
- `@mastra/voice-google` 0.12.3
- `@mastra/voice-google-gemini-live` 0.12.2
- `@mastra/voice-openai` 0.12.3
- `@mastra/voice-openai-realtime` 0.12.6
- `@mastra/voice-playai` 0.12.2
- `mastraqqq` every version
- `caspian-day-js` 1.11.23

</details>

<details><summary>AntV account takeover, May 2026: 644 versions of 324 packages</summary>

- `@antv/a8` 0.1.1, 0.2.1
- `@antv/adjust` 0.3.5, 0.4.5
- `@antv/algorithm` 0.2.26, 0.3.26
- `@antv/async-hook` 2.3.9, 2.4.9
- `@antv/attr` 0.4.5, 0.5.5
- `@antv/ava` 3.5.1, 3.6.1
- `@antv/ava-react` 3.4.2, 3.5.2
- `@antv/awards` 0.1.9, 0.2.9
- `@antv/calendar-heatmap` 1.2.2, 1.3.2
- `@antv/chart-linter` 1.2.6, 1.3.6
- `@antv/chart-node-g6` 0.1.4, 0.2.4
- `@antv/chart-visualization-skills` 0.2.3, 0.3.3
- `@antv/ckb` 2.1.4, 2.2.4
- `@antv/color-schema` 0.3.3, 0.4.3
- `@antv/color-util` 2.1.6, 2.2.6
- `@antv/component` 2.2.11, 2.3.11
- `@antv/coord` 0.5.7, 0.6.7
- `@antv/d3-color` 1.1.0, 1.2.0
- `@antv/d3-interpolate` 1.1.3, 1.2.3
- `@antv/data-samples` 1.1.1, 1.2.1
- `@antv/data-set` 0.12.8, 0.13.8
- `@antv/data-wizard` 2.1.4, 2.2.4
- `@antv/dipper-component` 0.1.4, 0.2.4
- `@antv/dipper-hooks` 0.3.1, 0.4.1
- `@antv/dipper-map` 1.1.10, 1.2.10
- `@antv/dom-util` 2.1.4, 2.2.4
- `@antv/dumi-theme-antv` 0.9.4, 0.10.4
- `@antv/dw-analyzer` 1.2.5, 1.3.5
- `@antv/dw-random` 1.2.7, 1.3.7
- `@antv/dw-transform` 1.2.7, 1.3.7
- `@antv/dw-util` 1.2.4, 1.3.4
- `@antv/event-emitter` 0.2.3, 0.3.3
- `@antv/expr` 1.1.2, 1.2.2
- `@antv/f-charts` 0.1.0, 0.2.0
- `@antv/f-engine` 1.11.0, 1.12.0
- `@antv/f-lottie` 1.11.0, 1.12.0
- `@antv/f-my` 1.11.0, 1.12.0
- `@antv/f-react` 1.11.0, 1.12.0
- `@antv/f-test-utils` 1.1.9, 1.2.9
- `@antv/f-vue` 1.11.0, 1.12.0
- `@antv/f-wx` 1.11.0, 1.12.0
- `@antv/f2` 5.15.0, 5.16.0
- `@antv/f2-algorithm` 5.8.0, 5.9.0
- `@antv/f2-canvas` 1.1.5, 1.2.5
- `@antv/f2-context` 0.1.1, 0.2.1
- `@antv/f2-graphic` 0.1.16, 0.2.16
- `@antv/f2-my` 4.1.52, 4.2.52
- `@antv/f2-react` 5.15.0, 5.16.0
- `@antv/f2-site` 4.1.42, 4.2.42
- `@antv/f2-vue` 4.1.33, 4.2.33
- `@antv/f2-wordcloud` 5.15.0, 5.16.0
- `@antv/f2-wx` 4.1.51, 4.2.51
- `@antv/f6` 0.1.19, 0.2.19
- `@antv/f6-alipay` 0.1.7, 0.2.7
- `@antv/f6-core` 0.1.2, 0.2.2
- `@antv/f6-element` 0.1.1, 0.2.1
- `@antv/f6-hammerjs` 0.1.2, 0.2.2
- `@antv/f6-plugin` 1.1.6, 1.2.6
- `@antv/f6-ui` 1.1.3, 1.2.3
- `@antv/f6-wx` 0.1.7, 0.2.7
- `@antv/g` 6.4.1, 6.5.1
- `@antv/g-base` 0.6.16, 0.7.16
- `@antv/g-camera-api` 2.1.45, 2.2.45
- `@antv/g-canvas` 2.3.0, 2.4.0
- `@antv/g-canvaskit` 1.2.1, 1.3.1
- `@antv/g-compat` 1.1.11, 1.2.11
- `@antv/g-components` 2.1.42, 2.2.42
- `@antv/g-css-layout-api` 1.1.38, 1.2.38
- `@antv/g-css-typed-om-api` 1.1.38, 1.2.38
- `@antv/g-device-api` 1.7.13, 1.8.13
- `@antv/g-dom-mutation-observer-api` 2.1.42, 2.2.42
- `@antv/g-gesture` 3.1.42, 3.2.42
- `@antv/g-image-exporter` 1.1.42, 1.2.42
- `@antv/g-layout-blocklike` 1.8.49, 1.9.49
- `@antv/g-lite` 2.8.0, 2.9.0
- `@antv/g-lottie-player` 1.2.1, 1.3.1
- `@antv/g-math` 3.2.0, 3.3.0
- `@antv/g-mobile` 1.2.5, 1.3.5
- `@antv/g-mobile-canvas` 1.2.1, 1.3.1
- `@antv/g-mobile-canvas-element` 1.1.42, 1.2.42
- `@antv/g-mobile-svg` 1.2.1, 1.3.1
- `@antv/g-mobile-webgl` 1.2.1, 1.3.1
- `@antv/g-pattern` 2.1.42, 2.2.42
- `@antv/g-perf` 1.1.0, 1.2.0
- `@antv/g-plugin-3d` 2.2.1, 2.3.1
- `@antv/g-plugin-a11y` 1.5.1, 1.6.1
- `@antv/g-plugin-annotation` 1.3.0, 1.4.0
- `@antv/g-plugin-box2d` 2.2.1, 2.3.1
- `@antv/g-plugin-canvas-path-generator` 2.2.26, 2.3.26
- `@antv/g-plugin-canvas-picker` 2.4.1, 2.5.1
- `@antv/g-plugin-canvas-renderer` 2.6.1, 2.7.1
- `@antv/g-plugin-canvaskit-renderer` 2.4.1, 2.5.1
- `@antv/g-plugin-control` 2.2.1, 2.3.1
- `@antv/g-plugin-css-select` 2.2.1, 2.3.1
- `@antv/g-plugin-device-renderer` 2.7.1, 2.8.1
- `@antv/g-plugin-dom-interaction` 2.2.31, 2.3.31
- `@antv/g-plugin-dragndrop` 2.2.1, 2.3.1
- `@antv/g-plugin-gesture` 2.2.1, 2.3.1
- `@antv/g-plugin-gpgpu` 1.10.20, 1.11.20
- `@antv/g-plugin-html-renderer` 2.4.1, 2.5.1
- `@antv/g-plugin-image-loader` 2.4.1, 2.5.1
- `@antv/g-plugin-matterjs` 2.2.1, 2.3.1
- `@antv/g-plugin-mobile-interaction` 1.1.42, 1.2.42
- `@antv/g-plugin-physx` 2.2.1, 2.3.1
- `@antv/g-plugin-rough-canvas-renderer` 2.2.1, 2.3.1
- `@antv/g-plugin-rough-svg-renderer` 2.2.1, 2.3.1
- `@antv/g-plugin-svg-picker` 2.1.46, 2.2.46
- `@antv/g-plugin-svg-renderer` 2.5.1, 2.6.1
- `@antv/g-plugin-webgl-device` 1.10.17, 1.11.17
- `@antv/g-plugin-webgl-renderer` 1.1.26, 1.2.26
- `@antv/g-plugin-webgpu-device` 1.10.17, 1.11.17
- `@antv/g-plugin-yoga` 2.4.1, 2.5.1
- `@antv/g-plugin-zdog-canvas-renderer` 2.2.1, 2.3.1
- `@antv/g-plugin-zdog-svg-renderer` 2.2.1, 2.3.1
- `@antv/g-shader-components` 2.1.0, 2.2.0
- `@antv/g-svg` 2.2.1, 2.3.1
- `@antv/g-web-animations-api` 2.2.32, 2.3.32
- `@antv/g-web-components` 2.2.1, 2.3.1
- `@antv/g-webgl` 2.2.1, 2.3.1
- `@antv/g-webgl-compute` 0.1.1, 0.2.1
- `@antv/g-webgpu` 2.2.1, 2.3.1
- `@antv/g-webgpu-compiler` 0.8.2, 0.9.2
- `@antv/g-webgpu-core` 0.8.2, 0.9.2
- `@antv/g-webgpu-engine` 0.8.2, 0.9.2
- `@antv/g-webgpu-raytracer` 0.6.1, 0.7.1
- `@antv/g-webgpu-unitchart` 0.6.1, 0.7.1
- `@antv/g2` 5.5.8, 5.6.8
- `@antv/g2-brush` 0.1.2, 0.2.2
- `@antv/g2-extension-3d` 0.3.0, 0.4.0
- `@antv/g2-extension-ava` 0.3.0, 0.4.0
- `@antv/g2-extension-plot` 0.3.2, 0.4.2
- `@antv/g2-plugin-slider` 2.2.1, 2.3.1
- `@antv/g2-ssr` 0.3.0, 0.4.0
- `@antv/g2plot` 2.5.35, 2.6.35
- `@antv/g2plot-schemas` 1.3.2, 1.4.2
- `@antv/g6` 5.2.1, 5.3.1
- `@antv/g6-alipay` 0.1.1, 0.2.1
- `@antv/g6-cli` 0.1.4, 0.2.4
- `@antv/g6-core` 0.9.24, 0.10.24
- `@antv/g6-editor` 1.3.0, 1.4.0
- `@antv/g6-element` 0.9.25, 0.10.25
- `@antv/g6-extension-3d` 0.2.23, 0.3.23
- `@antv/g6-extension-react` 0.3.7, 0.4.7
- `@antv/g6-mobile` 0.2.2, 0.3.2
- `@antv/g6-pc` 0.9.25, 0.10.25
- `@antv/g6-plugin` 0.9.25, 0.10.25
- `@antv/g6-plugin-map-view` 0.1.4, 0.2.4
- `@antv/g6-plugins` 1.1.9, 1.2.9
- `@antv/g6-react-node` 1.5.8, 1.6.8
- `@antv/g6-ssr` 0.2.1, 0.3.1
- `@antv/g6-wx` 0.1.1, 0.2.1
- `@antv/gatsby-theme` 0.2.0, 0.3.0
- `@antv/geo-coord` 1.1.8, 1.2.8
- `@antv/gi-assets-advance` 2.6.22, 2.7.22
- `@antv/gi-assets-algorithm` 2.4.19, 2.5.19
- `@antv/gi-assets-basic` 2.5.40, 2.6.40
- `@antv/gi-assets-galaxybase` 1.3.15, 1.4.15
- `@antv/gi-assets-graphscope` 2.2.15, 2.3.15
- `@antv/gi-assets-hugegraph` 1.2.15, 1.3.15
- `@antv/gi-assets-janusgraph` 1.2.15, 1.3.15
- `@antv/gi-assets-neo4j` 2.2.15, 2.3.15
- `@antv/gi-assets-scene` 2.3.21, 2.4.21
- `@antv/gi-assets-tugraph` 2.2.15, 2.3.15
- `@antv/gi-assets-tugraph-analytics` 0.3.15, 0.4.15
- `@antv/gi-assets-xlab` 0.2.30, 0.3.30
- `@antv/gi-cli` 1.3.11, 1.4.11
- `@antv/gi-common-components` 1.4.16, 1.5.16
- `@antv/gi-mock-data` 1.1.5, 1.2.5
- `@antv/gi-public-data` 1.1.1, 1.2.1
- `@antv/gi-sdk` 3.1.0, 3.2.0
- `@antv/gi-sdk-app` 1.3.10, 1.4.10
- `@antv/gi-theme-antd` 0.7.11, 0.8.11
- `@antv/github-config-cli` 0.2.0, 0.3.0
- `@antv/gl-matrix` 2.8.1, 2.9.1
- `@antv/gpt-vis` 1.1.0, 1.2.0
- `@antv/gpt-vis-ssr` 0.4.7, 0.5.7
- `@antv/graphin` 3.1.5, 3.2.5
- `@antv/graphin-components` 2.5.1, 2.6.1
- `@antv/graphin-graphscope` 1.1.5, 1.2.5
- `@antv/graphin-icons` 1.1.0, 1.2.0
- `@antv/graphlib` 2.1.4, 2.2.4
- `@antv/hierarchy` 0.8.1, 0.9.1
- `@antv/infographic` 0.3.19, 0.4.19
- `@antv/insight-component` 1.1.0, 1.2.0
- `@antv/interaction` 0.2.5, 0.3.5
- `@antv/istanbul` 0.1.0, 0.2.0
- `@antv/knowledge` 1.2.4, 1.3.4
- `@antv/l7` 2.26.10, 2.27.10
- `@antv/l7-component` 2.26.10, 2.27.10
- `@antv/l7-composite-layers` 0.18.1, 0.19.1
- `@antv/l7-core` 2.26.10, 2.27.10
- `@antv/l7-district` 2.4.12, 2.5.12
- `@antv/l7-draw` 3.2.5, 3.3.5
- `@antv/l7-editor` 1.2.13, 1.3.13
- `@antv/l7-extension-g-layer` 1.1.0, 1.2.0
- `@antv/l7-layers` 2.26.10, 2.27.10
- `@antv/l7-leaflet` 1.1.2, 1.2.2
- `@antv/l7-map` 2.26.10, 2.27.10
- `@antv/l7-mapkit` 0.6.0, 0.7.0
- `@antv/l7-maps` 2.26.10, 2.27.10
- `@antv/l7-mini` 2.21.8, 2.22.8
- `@antv/l7-pass` 1.1.0, 1.2.0
- `@antv/l7-react` 2.5.3, 2.6.3
- `@antv/l7-renderer` 2.26.10, 2.27.10
- `@antv/l7-scene` 2.26.10, 2.27.10
- `@antv/l7-source` 2.26.10, 2.27.10
- `@antv/l7-three` 2.26.10, 2.27.10
- `@antv/l7-utils` 2.26.10, 2.27.10
- `@antv/l7plot` 0.6.11, 0.7.11
- `@antv/l7plot-component` 0.1.11, 0.2.11
- `@antv/larkmap` 1.6.1, 1.7.1
- `@antv/layout-gpu` 1.2.7, 1.3.7
- `@antv/layout-wasm` 1.5.2, 1.6.2
- `@antv/li-aiearth-assets` 0.5.7, 0.6.7
- `@antv/li-analysis-assets` 1.10.1, 1.11.1
- `@antv/li-core-assets` 1.4.7, 1.5.7
- `@antv/li-editor` 1.7.1, 1.8.1
- `@antv/li-p2` 1.9.2, 1.10.2
- `@antv/li-sam-assets` 0.2.4, 0.3.4
- `@antv/li-sdk` 1.6.1, 1.7.1
- `@antv/lite-insight` 2.2.1, 2.3.1
- `@antv/matrix-util` 3.1.4, 3.2.4
- `@antv/mcp-server-antv` 0.2.8, 0.3.8
- `@antv/mcp-server-chart` 0.10.10, 0.11.10
- `@antv/my-f2` 2.2.7, 2.3.7
- `@antv/my-f2-pc` 0.2.1, 0.3.1
- `@antv/narrative-text-editor` 0.3.20, 0.4.20
- `@antv/narrative-text-schema` 0.4.7, 0.5.7
- `@antv/narrative-text-vis` 0.4.16, 0.5.16
- `@antv/path-util` 3.1.1, 3.2.1
- `@antv/react-g` 2.2.1, 2.3.1
- `@antv/s2` 2.8.1, 2.9.1
- `@antv/s2-react` 2.4.1, 2.5.1
- `@antv/s2-react-components` 2.2.2, 2.3.2
- `@antv/s2-ssr` 0.2.1, 0.3.1
- `@antv/s2-vue` 2.3.0, 2.4.0
- `@antv/sam` 0.3.0, 0.4.0
- `@antv/scale` 0.6.2, 0.7.2
- `@antv/semantic-release-pnpm` 1.1.4, 1.2.4
- `@antv/smart-color` 0.3.1, 0.4.1
- `@antv/stat` 0.1.2, 0.2.2
- `@antv/t8` 0.4.0, 0.5.0
- `@antv/thumbnails` 2.1.0, 2.2.0
- `@antv/thumbnails-component` 2.1.0, 2.2.0
- `@antv/torch` 1.1.6, 1.2.6
- `@antv/translator` 1.1.1, 1.2.1
- `@antv/util` 3.4.11, 3.5.11
- `@antv/vendor` 1.1.11, 1.2.11
- `@antv/vis-predict-engine` 0.2.1, 0.3.1
- `@antv/webgpu-graph` 1.1.0, 1.2.0
- `@antv/word-scale-chart` 0.4.4, 0.5.4
- `@antv/wx-f2` 2.2.1, 2.3.1
- `@antv/x6` 3.2.7, 3.3.7
- `@antv/x6-angular-shape` 3.1.1, 3.2.1
- `@antv/x6-common` 2.1.17, 2.2.17
- `@antv/x6-components` 0.11.7, 0.12.7
- `@antv/x6-geometry` 2.1.5, 2.2.5
- `@antv/x6-plugin-clipboard` 2.2.6, 2.3.6
- `@antv/x6-plugin-dnd` 2.2.1, 2.3.1
- `@antv/x6-plugin-export` 2.2.6, 2.3.6
- `@antv/x6-plugin-history` 2.3.4, 2.4.4
- `@antv/x6-plugin-keyboard` 2.3.3, 2.4.3
- `@antv/x6-plugin-minimap` 2.1.7, 2.2.7
- `@antv/x6-plugin-scroller` 2.1.10, 2.2.10
- `@antv/x6-plugin-selection` 2.3.2, 2.4.2
- `@antv/x6-plugin-snapline` 2.2.7, 2.3.7
- `@antv/x6-plugin-stencil` 2.2.5, 2.3.5
- `@antv/x6-plugin-transform` 2.2.8, 2.3.8
- `@antv/x6-react` 0.2.26, 0.3.26
- `@antv/x6-react-components` 2.1.9, 2.2.9
- `@antv/x6-react-shape` 3.1.1, 3.2.1
- `@antv/x6-vector` 1.5.2, 1.6.2
- `@antv/x6-vue-shape` 3.1.2, 3.2.2
- `@antv/x6-vue3-shape` 1.1.0, 1.2.0
- `@antv/xflow` 2.2.13, 2.3.13
- `@antv/xflow-core` 1.1.55, 1.2.55
- `@antv/xflow-diff` 1.1.0, 1.2.0
- `@antv/xflow-extension` 1.1.55, 1.2.55
- `@antv/xflow-hook` 1.1.55, 1.2.55
- `@cap-js/openapi` 1.4.1
- `@lint-md/cli` 2.1.0, 2.2.0
- `@lint-md/core` 2.1.0, 2.2.0
- `@lint-md/parser` 0.1.14, 0.2.14
- `@openclaw-cn/cli` 1.4.1
- `@openclaw-cn/feishu` 0.2.11
- `@openclaw-cn/libsignal` 2.1.1
- `@openclaw-cn/toutiao-ops` 1.2.4
- `@starmind/collector-cli` 0.3.10
- `ai-figure` 0.5.0, 0.6.0
- `amapcn` 0.2.2, 0.3.2
- `ast-plugin` 0.1.7, 0.2.7
- `babel-plugin-version` 0.3.3, 0.4.3
- `boring-avatars-vanilla` 1.1.2, 1.2.2
- `byte-parser` 1.1.0, 1.2.0
- `canvas-nest.js` 2.1.4, 2.2.4
- `echarts-for-react` 3.0.7, 3.1.7, 3.2.7
- `filesize.js` 2.1.0, 2.2.0
- `fixed-round` 1.1.2, 1.2.2
- `gantt-for-react` 0.3.0, 0.4.0
- `jest-canvas-mock` 2.5.3, 2.6.3, 2.7.3
- `jest-date-mock` 1.0.11, 1.1.11, 1.2.11
- `jest-electron` 0.2.12, 0.3.12
- `jest-expect` 0.1.1, 0.2.1
- `jest-less-loader` 0.3.0, 0.4.0
- `jest-random-mock` 1.1.0, 1.2.0
- `jest-url-loader` 0.2.0, 0.3.0
- `limit-size` 0.2.4, 0.3.4
- `lint-md` 0.3.0, 0.4.0
- `lint-md-cli` 0.2.2, 0.3.2
- `mcp-echarts` 0.8.1, 0.9.1
- `mcp-mermaid` 0.5.1, 0.6.1
- `miz` 1.1.1, 1.2.1
- `onfire.js` 2.1.1, 2.2.1
- `openclaw-cn` 0.3.0
- `react-adsense` 0.2.0, 0.3.0
- `relationship.js` 1.3.9, 1.4.9
- `ribbon.js` 1.1.2
- `size-sensor` 1.0.4, 1.1.4, 1.2.4
- `slice.js` 1.2.1, 1.3.1
- `timeago-react` 3.1.7, 3.2.7
- `timeago.js` 4.1.2, 4.2.2
- `uri-parse` 1.1.0, 1.2.0
- `word-width` 1.1.1, 1.2.1
- `xmorse` 1.1.0, 1.2.0

</details>

<details><summary>Red Hat Cloud Services packages, June 2026: 96 versions of 32 packages</summary>

- `@redhat-cloud-services/chrome` 2.3.1, 2.3.2, 2.3.4
- `@redhat-cloud-services/compliance-client` 4.0.3, 4.0.4, 4.0.6
- `@redhat-cloud-services/config-manager-client` 5.0.4, 5.0.5, 5.0.7
- `@redhat-cloud-services/entitlements-client` 4.0.11, 4.0.12, 4.0.14
- `@redhat-cloud-services/eslint-config-redhat-cloud-services` 3.2.1, 3.2.2, 3.2.4
- `@redhat-cloud-services/frontend-components` 7.7.2, 7.7.3, 7.7.5
- `@redhat-cloud-services/frontend-components-advisor-components` 3.8.2, 3.8.4, 3.8.6
- `@redhat-cloud-services/frontend-components-config` 6.11.3, 6.11.4, 6.11.6
- `@redhat-cloud-services/frontend-components-config-utilities` 4.11.2, 4.11.3, 4.11.5
- `@redhat-cloud-services/frontend-components-notifications` 6.9.2, 6.9.3, 6.9.5
- `@redhat-cloud-services/frontend-components-remediations` 4.9.2, 4.9.3, 4.9.5
- `@redhat-cloud-services/frontend-components-testing` 1.2.1, 1.2.2, 1.2.4
- `@redhat-cloud-services/frontend-components-translations` 4.4.1, 4.4.2, 4.4.4
- `@redhat-cloud-services/frontend-components-utilities` 7.4.1, 7.4.2, 7.4.4
- `@redhat-cloud-services/hcc-feo-mcp` 0.3.1, 0.3.2, 0.3.4
- `@redhat-cloud-services/hcc-kessel-mcp` 0.3.1, 0.3.2, 0.3.4
- `@redhat-cloud-services/hcc-pf-mcp` 0.6.1, 0.6.2, 0.6.4
- `@redhat-cloud-services/host-inventory-client` 5.0.3, 5.0.4, 5.0.6
- `@redhat-cloud-services/insights-client` 4.0.4, 4.0.5, 4.0.7
- `@redhat-cloud-services/integrations-client` 6.0.4, 6.0.5, 6.0.7
- `@redhat-cloud-services/javascript-clients-shared` 2.0.8, 2.0.9, 2.0.11
- `@redhat-cloud-services/notifications-client` 6.1.4, 6.1.5, 6.1.7
- `@redhat-cloud-services/patch-client` 4.0.4, 4.0.5, 4.0.7
- `@redhat-cloud-services/quickstarts-client` 4.0.11, 4.0.12, 4.0.14
- `@redhat-cloud-services/rbac-client` 9.0.3, 9.0.4, 9.0.6
- `@redhat-cloud-services/remediations-client` 4.0.4, 4.0.5, 4.0.7
- `@redhat-cloud-services/rule-components` 4.7.2, 4.7.3, 4.7.5
- `@redhat-cloud-services/sources-client` 3.0.10, 3.0.11, 3.0.13
- `@redhat-cloud-services/topological-inventory-client` 3.0.10, 3.0.11, 3.0.13
- `@redhat-cloud-services/tsc-transform-imports` 1.2.2, 1.2.4, 1.2.6
- `@redhat-cloud-services/types` 3.6.1, 3.6.2, 3.6.4
- `@redhat-cloud-services/vulnerabilities-client` 2.1.8, 2.1.9, 2.1.11

</details>

<details><summary>keyv worm, August 2026: 12 versions of 12 packages</summary>

- `keyv` 6.0.0
- `cacheable` 2.5.1
- `cache-manager` 7.2.10
- `cacheable-request` 13.0.20
- `flat-cache` 6.1.24
- `file-entry-cache` 11.1.6
- `@cacheable/net` 2.1.1
- `@cacheable/node-cache` 3.1.2
- `@cacheable/memory` 2.2.1
- `@cacheable/utils` 2.5.1
- `ecto` 5.0.1
- `hamus.js` 0.4.1

</details>

<details><summary>keyv account takeover, August 2026: 19 versions of 19 packages</summary>

- `@keyv/bigmap` 6.0.0
- `@keyv/cloudflare-kv` 6.0.0
- `@keyv/compress-brotli` 6.0.0
- `@keyv/compress-gzip` 6.0.0
- `@keyv/compress-lz4` 6.0.0
- `@keyv/dynamo` 6.0.0
- `@keyv/encrypt-node` 6.0.0
- `@keyv/encrypt-web` 6.0.0
- `@keyv/etcd` 6.0.0
- `@keyv/memcache` 6.0.0
- `@keyv/mongo` 6.0.0
- `@keyv/mysql` 6.0.0
- `@keyv/postgres` 6.0.0
- `@keyv/redis` 6.0.0
- `@keyv/serialize-msgpackr` 6.0.0
- `@keyv/serialize-superjson` 6.0.0
- `@keyv/sqlite` 6.0.0
- `@keyv/test-suite` 6.0.0
- `@keyv/valkey` 6.0.0

</details>

<details><summary>keyv worm spread, August 2026: 2224 versions of 432 packages</summary>

- `@adminide-stack/clock-tik-browser` 12.0.24
- `@adminide-stack/yantra-mobile` 12.0.33
- `@arv-bedrock/auth` 1.1.7, 1.1.8
- `@arv-bedrock/auth-admin` 1.0.2, 1.0.3
- `@arv-bedrock/auth-sso` 1.6.1, 1.6.2
- `@arv-bedrock/auth-sso-backend` 1.7.1, 1.7.2
- `@arv-bedrock/logger` 1.7.1, 1.7.2
- `@deliveroo/determinator` 0.2.1
- `@deliveroo/reevent` 1.0.1
- `@hubsync/web-sdk-react` 6.3.7, 6.3.8, 6.3.9, 6.3.10, 6.3.11, 6.3.12, 6.3.13, 6.3.14, 6.3.15, 6.3.16, 6.3.17, 6.3.18, 6.3.19, 6.3.20, 6.3.21, 6.3.22, 6.3.23, 6.3.24, 6.3.25, 6.3.26, 6.3.27, 6.3.28, 6.3.29, 6.3.30, 6.3.31, 6.3.32, 6.3.33
- `@nebula.js/cli` 7.1.2
- `@nebula.js/cli-build` 7.1.2
- `@nebula.js/cli-sense` 7.1.2
- `@nebula.js/cli-serve` 7.1.2
- `@nebula.js/locale` 0.6.2
- `@nebula.js/nucleus` 0.5.1
- `@nebula.js/sn-action-button` 2.3.1
- `@nebula.js/sn-animator` 2.13.1
- `@nebula.js/sn-distributionplot` 1.0.7
- `@nebula.js/sn-layout-container` 4.4.1
- `@nebula.js/sn-line-chart` 2.7.1
- `@nebula.js/sn-listbox` 0.19.3
- `@nebula.js/sn-map` 0.12.7
- `@nebula.js/sn-nav-menu` 0.14.2
- `@nebula.js/sn-org-chart` 1.7.1
- `@nebula.js/sn-shape` 1.5.1
- `@nebula.js/sn-slider` 0.20.1
- `@nebula.js/sn-tabbed-container` 2.4.1
- `@nebula.js/snapshooter` 0.6.1
- `@nebula.js/stardust` 7.1.2
- `@nebula.js/test-utils` 0.6.1
- `@nebula.js/theme` 0.6.1
- `@onereach/authorizer-helper` 0.0.11, 0.0.12, 0.0.13
- `@onereach/bandwidth-steps-voice-bxml` 0.1.1, 0.1.2, 0.1.3
- `@onereach/billing-dto` 27.2.1, 27.2.2, 27.2.3
- `@onereach/billing-shared` 27.2.1, 27.2.2, 27.2.3
- `@onereach/cb-schema-translator` 1.3.1, 1.3.2, 1.3.3
- `@onereach/channel-transformer` 0.0.66, 0.0.67, 0.0.68
- `@onereach/channel-transformers` 0.0.5, 0.0.6, 0.0.7
- `@onereach/ckeditor5-build-classic` 30.0.1, 30.0.2, 30.0.3
- `@onereach/condition-builder` 1.0.8, 1.0.9, 1.0.10
- `@onereach/content-builder` 0.0.18, 0.0.19, 0.0.20
- `@onereach/content-builder-template-compiler` 0.0.3, 0.0.4, 0.0.5
- `@onereach/expression-components` 9.1.1, 9.1.2, 9.1.3
- `@onereach/font-icons` 27.0.2, 27.0.3, 27.0.4
- `@onereach/get-version-data` 3.1.2, 3.1.3, 3.1.4
- `@onereach/idw-apps` 0.1.3, 0.1.4, 0.1.5
- `@onereach/idw-contracts` 0.1.2, 0.1.3, 0.1.4
- `@onereach/idw-init-account-resources` 1.0.1, 1.0.2, 1.0.3
- `@onereach/idw-sdk` 0.1.2, 0.1.3, 0.1.4
- `@onereach/idw-ui-components` 0.1.2, 0.1.3, 0.1.4
- `@onereach/lambda-invocation` 1.2.1, 1.2.2, 1.2.3
- `@onereach/messengers-infobip-sdk` 0.1.1, 0.1.2, 0.1.3
- `@onereach/or-browser` 0.0.48, 0.0.49, 0.0.50
- `@onereach/or-browser-next` 0.0.11, 0.0.12, 0.0.13
- `@onereach/or-content-builder-renderer` 0.0.2, 0.0.3, 0.0.4
- `@onereach/or-file-uploader-next` 0.0.8, 0.0.9, 0.0.10
- `@onereach/or-pro` 1.13.1, 1.13.2, 1.13.3
- `@onereach/or-sdk-agent-cli` 0.0.6, 0.0.7, 0.0.8
- `@onereach/orest-cli` 2.4.1, 2.4.2, 2.4.3
- `@onereach/orest-input-cli` 1.18.1, 1.18.2, 1.18.3
- `@onereach/orest-jest-presets` 0.0.3, 0.0.4, 0.0.5
- `@onereach/orest-vue-demi-vue2` 0.0.4, 0.0.5, 0.0.6
- `@onereach/orest-vue-demi-vue3` 0.0.4, 0.0.5, 0.0.6
- `@onereach/orest-vue3` 0.0.4, 0.0.5, 0.0.6
- `@onereach/phonenumber-interpreter` 0.0.18, 0.0.19, 0.0.20
- `@onereach/pnpm-audit-junit` 1.0.3, 1.0.4, 1.0.5
- `@onereach/postcss-scoped-selector` 1.2.1, 1.2.2, 1.2.3
- `@onereach/regex-helper` 0.5.16, 0.5.17, 0.5.18
- `@onereach/regular-expressions` 0.5.23, 0.5.24, 0.5.25
- `@onereach/regular-expressions-test` 0.0.4, 0.0.5, 0.0.6
- `@onereach/rwc-client` 6.4.7, 6.4.8, 6.4.9
- `@onereach/salesforce-miaw-client` 0.0.3, 0.0.4, 0.0.5
- `@onereach/si-a-button` 0.0.3, 0.0.4, 0.0.5
- `@onereach/si-alert` 0.4.11, 0.4.12, 0.4.13
- `@onereach/si-checkbox` 0.6.5, 0.6.6, 0.6.7
- `@onereach/si-checkbox-group` 0.3.5, 0.3.6, 0.3.7
- `@onereach/si-code` 0.6.4, 0.6.5, 0.6.6
- `@onereach/si-collapsible-group` 0.6.4, 0.6.5, 0.6.6
- `@onereach/si-copyable-text` 0.4.11, 0.4.12, 0.4.13
- `@onereach/si-datepicker` 0.4.5, 0.4.6, 0.4.7
- `@onereach/si-divider` 0.4.11, 0.4.12, 0.4.13
- `@onereach/si-dropdown-advanced` 0.4.5, 0.4.6, 0.4.7
- `@onereach/si-dropdown-simple` 0.4.5, 0.4.6, 0.4.7
- `@onereach/si-header` 0.4.11, 0.4.12, 0.4.13, 0.4.14
- `@onereach/si-list` 0.7.4, 0.7.5, 0.7.6
- `@onereach/si-merge-tag-input` 0.4.5, 0.4.6, 0.4.7
- `@onereach/si-radio-group` 0.3.5, 0.3.6, 0.3.7
- `@onereach/si-root` 0.9.4, 0.9.5, 0.9.6
- `@onereach/si-select` 0.1.3, 0.1.4, 0.1.5
- `@onereach/si-step-chooser` 0.4.4, 0.4.5, 0.4.6
- `@onereach/si-switch` 0.4.5, 0.4.6, 0.4.7
- `@onereach/si-text-message` 0.4.5, 0.4.6, 0.4.7
- `@onereach/si-textinput` 0.5.5, 0.5.6, 0.5.7
- `@onereach/si-validated-timestring-input` 0.3.5, 0.3.6, 0.3.7
- `@onereach/slack-helpers` 1.0.3, 1.0.4, 1.0.5
- `@onereach/ssml-editor` 2.0.12, 2.0.13, 2.0.14
- `@onereach/step-components` 0.1.37, 0.1.38, 0.1.39
- `@onereach/step-conversation` 1.0.41, 1.0.42, 1.0.43
- `@onereach/step-run-snowflake-query` 0.1.1, 0.1.2, 0.1.3
- `@onereach/step-voice` 7.0.32, 7.0.33, 7.0.34
- `@onereach/styles` 27.0.2, 27.0.3, 27.0.4
- `@onereach/time-interpreter` 1.0.30, 1.0.31, 1.0.32
- `@onereach/ts-memoize` 1.0.2, 1.0.3, 1.0.4
- `@onereach/types-contacts-api` 9.0.8, 9.0.9, 9.0.10
- `@onereach/ui-components` 27.0.2, 27.0.3, 27.0.4
- `@onereach/ui-components-common` 27.0.2, 27.0.3, 27.0.4
- `@onereach/ui-components-vue2` 27.0.2, 27.0.3, 27.0.4
- `@onereach/v-event-calendar` 0.1.22, 0.1.23, 0.1.24
- `@onereach/webform` 0.3.13, 0.3.14, 0.3.15
- `@or-sdk/account-settings` 1.3.6, 1.3.7, 1.3.8
- `@or-sdk/accounts` 2.3.5, 2.3.6, 2.3.7
- `@or-sdk/adapters` 0.3.6, 0.3.7, 0.3.8
- `@or-sdk/agents` 4.21.3, 4.21.4, 4.21.5
- `@or-sdk/api-tokens` 1.4.2, 1.4.3, 1.4.4
- `@or-sdk/api-tokens-lambda` 1.4.2, 1.4.3, 1.4.4
- `@or-sdk/apps` 1.2.6, 1.2.7, 1.2.8
- `@or-sdk/auth` 0.38.1, 0.38.2, 0.38.3
- `@or-sdk/authorizer` 0.26.7, 0.26.8, 0.26.9
- `@or-sdk/base` 0.44.4, 0.44.5, 0.44.6
- `@or-sdk/billing` 27.2.1, 27.2.2, 27.2.3
- `@or-sdk/billing-internal` 27.2.1, 27.2.2, 27.2.3
- `@or-sdk/bot-templates` 2.2.5, 2.2.6, 2.2.7
- `@or-sdk/bots` 1.7.1, 1.7.2, 1.7.3
- `@or-sdk/card-templates` 2.2.5, 2.2.6, 2.2.7
- `@or-sdk/cards` 1.2.5, 1.2.6, 1.2.7
- `@or-sdk/ccp` 10.15.4, 10.15.5, 10.15.6
- `@or-sdk/chat` 0.3.1, 0.3.2, 0.3.3
- `@or-sdk/contacts` 4.7.5, 4.7.6, 4.7.7
- `@or-sdk/content-request` 0.2.6, 0.2.7, 0.2.8
- `@or-sdk/data-hub` 0.26.5, 0.26.6, 0.26.7
- `@or-sdk/data-hub-svc` 2.3.5, 2.3.6, 2.3.7
- `@or-sdk/deployer` 1.7.5, 1.7.6, 1.7.7
- `@or-sdk/deployments` 2.1.5, 2.1.6, 2.1.7
- `@or-sdk/discovery` 1.12.1, 1.12.2, 1.12.3
- `@or-sdk/druid` 1.4.7, 1.4.8, 1.4.9
- `@or-sdk/event-manager` 1.1.5, 1.1.6, 1.1.7
- `@or-sdk/files` 3.11.6, 3.11.7, 3.11.8
- `@or-sdk/files-sync-node` 0.1.8, 0.1.9, 0.1.10
- `@or-sdk/flow-templates` 2.1.5, 2.1.6, 2.1.7
- `@or-sdk/flows` 2.7.8, 2.7.9, 2.7.10
- `@or-sdk/graph` 1.10.5, 1.10.6, 1.10.7
- `@or-sdk/hitl` 0.41.1, 0.41.2, 0.41.3
- `@or-sdk/identifiers` 0.27.6, 0.27.7, 0.27.8
- `@or-sdk/idw` 9.0.4, 9.0.5, 9.0.6
- `@or-sdk/idw-public` 1.6.6, 1.6.7, 1.6.8
- `@or-sdk/idw-skill` 1.4.1, 1.4.2, 1.4.3
- `@or-sdk/invitations` 1.4.8, 1.4.9, 1.4.10
- `@or-sdk/key-value-storage` 0.28.6, 0.28.7, 0.28.8
- `@or-sdk/keys` 1.2.6, 1.2.7, 1.2.8
- `@or-sdk/knowledge-models` 0.25.5, 0.25.6, 0.25.7
- `@or-sdk/library` 0.5.6, 0.5.7, 0.5.8
- `@or-sdk/library-categories` 0.2.6, 0.2.7, 0.2.8
- `@or-sdk/library-source` 0.4.5, 0.4.6, 0.4.7
- `@or-sdk/library-types-v1` 9.0.1, 9.0.2, 9.0.3
- `@or-sdk/library-types-v2` 9.0.1, 9.0.2, 9.0.3
- `@or-sdk/lookup` 1.25.1, 1.25.2, 1.25.3
- `@or-sdk/markdowner` 0.5.1, 0.5.2, 0.5.3
- `@or-sdk/mcp-tools` 0.5.2, 0.5.3, 0.5.4
- `@or-sdk/notifications` 1.7.5, 1.7.6, 1.7.7
- `@or-sdk/password` 1.3.6, 1.3.7, 1.3.8
- `@or-sdk/payments` 3.2.5, 3.2.6, 3.2.7
- `@or-sdk/permissions` 2.8.1, 2.8.2, 2.8.3
- `@or-sdk/permissions-cli` 1.4.1, 1.4.2, 1.4.3
- `@or-sdk/permissions-lambda` 2.5.1, 2.5.2, 2.5.3
- `@or-sdk/pgsql` 1.5.1, 1.5.2, 1.5.3
- `@or-sdk/providers` 0.3.6, 0.3.7, 0.3.8
- `@or-sdk/qna` 3.4.2, 3.4.3, 3.4.4
- `@or-sdk/queue-manager` 1.4.6, 1.4.7, 1.4.8
- `@or-sdk/sdk-api` 0.29.2, 0.29.3, 0.29.4
- `@or-sdk/settings` 0.25.6, 0.25.7, 0.25.8
- `@or-sdk/sku-builder` 2.5.1, 2.5.2, 2.5.3
- `@or-sdk/source` 2.1.5, 2.1.6, 2.1.7
- `@or-sdk/source-api` 1.1.1, 1.1.2, 1.1.3
- `@or-sdk/step-templates` 2.2.5, 2.2.6, 2.2.7
- `@or-sdk/store` 2.1.5, 2.1.6, 2.1.7
- `@or-sdk/tables` 0.28.5, 0.28.6, 0.28.7
- `@or-sdk/tags` 1.1.5, 1.1.6, 1.1.7
- `@or-sdk/tickets` 1.9.5, 1.9.6, 1.9.7
- `@or-sdk/transcripts` 1.2.5, 1.2.6, 1.2.7
- `@or-sdk/users` 3.8.1, 3.8.2, 3.8.3
- `@or-sdk/view-templates` 2.2.5, 2.2.6, 2.2.7
- `@or-sdk/views` 3.1.5, 3.1.6, 3.1.7
- `@or-sdk/web-search` 0.6.1, 0.6.2, 0.6.3
- `@ornikar/apollo-link-timeout` 1.4.2, 1.4.3, 1.4.4, 1.4.5, 1.4.6, 1.4.7, 1.4.8, 1.4.9, 1.4.10, 1.4.11
- `@ornikar/babel-preset-base` 6.0.3, 6.0.4, 6.0.5, 6.0.6, 6.0.7, 6.0.8, 6.0.9, 6.0.10, 6.0.11, 6.0.12, 6.0.13, 6.0.14
- `@ornikar/babel-preset-kitt-universal` 8.0.3, 8.0.4, 8.0.5, 8.0.6, 8.0.7, 8.0.8, 8.0.9, 8.0.10, 8.0.11, 8.0.12
- `@ornikar/babel-preset-react` 6.1.4, 6.1.5, 6.1.6, 6.1.7, 6.1.8, 6.1.9, 6.1.10, 6.1.11, 6.1.12, 6.1.13, 6.1.14
- `@ornikar/browserslist-config` 8.0.3, 8.0.4, 8.0.5, 8.0.6, 8.0.7, 8.0.8, 8.0.9, 8.0.10, 8.0.11
- `@ornikar/commitlint-config` 8.3.2, 8.3.3, 8.3.4, 8.3.5, 8.3.6, 8.3.7, 8.3.8, 8.3.9, 8.3.10, 8.3.11, 8.3.12
- `@ornikar/eslint-config` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10, 24.0.11, 24.0.12
- `@ornikar/eslint-config-babel` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10, 24.0.11, 24.0.12
- `@ornikar/eslint-config-babel-use` 13.2.1, 13.2.2, 13.2.3, 13.2.4, 13.2.5, 13.2.6, 13.2.7, 13.2.8, 13.2.9, 13.2.10, 13.2.11, 13.2.12
- `@ornikar/eslint-config-formatjs` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10
- `@ornikar/eslint-config-node` 12.2.1, 12.2.2, 12.2.3, 12.2.4, 12.2.5, 12.2.6, 12.2.7, 12.2.8, 12.2.9, 12.2.10
- `@ornikar/eslint-config-react` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10, 24.0.11
- `@ornikar/eslint-config-typescript` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10
- `@ornikar/eslint-config-typescript-nestjs` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10, 24.0.11
- `@ornikar/eslint-config-typescript-react` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10, 24.0.11
- `@ornikar/eslint-plugin-neverthrow` 1.3.1, 1.3.2, 1.3.3, 1.3.4, 1.3.5, 1.3.6, 1.3.7, 1.3.8, 1.3.9, 1.3.10, 1.3.11, 1.3.12
- `@ornikar/eslint-plugin-ornikar` 24.0.1, 24.0.2, 24.0.3, 24.0.4, 24.0.5, 24.0.6, 24.0.7, 24.0.8, 24.0.9, 24.0.10, 24.0.11
- `@ornikar/graphql-config` 1.1.1, 1.1.2, 1.1.3, 1.1.4, 1.1.5, 1.1.6, 1.1.7, 1.1.8, 1.1.9, 1.1.10, 1.1.11
- `@ornikar/intl-config` 10.0.2, 10.0.3, 10.0.4, 10.0.5, 10.0.6, 10.0.7, 10.0.8, 10.0.9, 10.0.10
- `@ornikar/jest-config` 13.0.3, 13.0.4, 13.0.5, 13.0.6, 13.0.7, 13.0.8, 13.0.9, 13.0.10, 13.0.11, 13.0.12, 13.0.13
- `@ornikar/jest-config-react` 18.0.2, 18.0.3, 18.0.4, 18.0.5, 18.0.6, 18.0.7, 18.0.8, 18.0.9, 18.0.10, 18.0.11
- `@ornikar/jest-config-react-native` 17.0.2, 17.0.3, 17.0.4, 17.0.5, 17.0.6, 17.0.7, 17.0.8, 17.0.9, 17.0.10, 17.0.11, 17.0.12
- `@ornikar/jest-config-react-native-web` 12.0.3, 12.0.4, 12.0.5, 12.0.6, 12.0.7, 12.0.8, 12.0.9, 12.0.10, 12.0.11, 12.0.12, 12.0.13
- `@ornikar/kitt2` 1.0.1, 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11
- `@ornikar/lerna-config` 11.0.1, 11.0.2, 11.0.3, 11.0.4, 11.0.5, 11.0.6, 11.0.7, 11.0.8, 11.0.9, 11.0.10, 11.0.11
- `@ornikar/monorepo-config` 14.3.2, 14.3.3, 14.3.4, 14.3.5, 14.3.6, 14.3.7, 14.3.8, 14.3.9, 14.3.10, 14.3.11, 14.3.12, 14.3.13
- `@ornikar/postcss-config` 9.1.2, 9.1.3, 9.1.4, 9.1.5, 9.1.6, 9.1.7, 9.1.8, 9.1.9, 9.1.10, 9.1.11, 9.1.12
- `@ornikar/prettier-config` 9.0.3, 9.0.4, 9.0.5, 9.0.6, 9.0.7, 9.0.8, 9.0.9, 9.0.10, 9.0.11
- `@ornikar/prismic-components` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8, 0.0.9, 0.0.10, 0.0.11, 0.0.12
- `@ornikar/react-modern-calendar-datepicker` 3.2.1, 3.2.2, 3.2.3, 3.2.4, 3.2.5, 3.2.6, 3.2.7, 3.2.8, 3.2.9, 3.2.10, 3.2.11
- `@ornikar/react-native-svg-transformer` 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11, 1.0.12, 1.0.13
- `@ornikar/renovate-config` 9.0.2, 9.0.3, 9.0.4, 9.0.5, 9.0.6, 9.0.7, 9.0.8, 9.0.9, 9.0.10, 9.0.11, 9.0.12, 9.0.13
- `@ornikar/repo-config` 15.3.3, 15.3.4, 15.3.5, 15.3.6, 15.3.7, 15.3.8, 15.3.9, 15.3.10, 15.3.11, 15.3.12, 15.3.13
- `@ornikar/repo-config-react` 13.0.8, 13.0.9, 13.0.10, 13.0.11, 13.0.12, 13.0.13, 13.0.14, 13.0.15, 13.0.16, 13.0.17, 13.0.18, 13.0.19
- `@ornikar/repo-config-react-legacy-css` 15.1.2, 15.1.3, 15.1.4, 15.1.5, 15.1.6, 15.1.7, 15.1.8, 15.1.9, 15.1.10, 15.1.11, 15.1.12, 15.1.13
- `@ornikar/rollup-config` 11.1.2, 11.1.3, 11.1.4, 11.1.5, 11.1.6, 11.1.7, 11.1.8, 11.1.9, 11.1.10, 11.1.11, 11.1.12, 11.1.13
- `@ornikar/rollup-plugin-postcss` 2.0.5, 2.0.6, 2.0.7, 2.0.8, 2.0.9, 2.0.10, 2.0.11, 2.0.12, 2.0.13, 2.0.14, 2.0.15
- `@ornikar/slate-react-fork` 1.0.1, 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11
- `@ornikar/storybook-config` 12.1.2, 12.1.3, 12.1.4, 12.1.5, 12.1.6, 12.1.7, 12.1.8, 12.1.9, 12.1.10
- `@ornikar/stylelint-config` 14.0.3, 14.0.4, 14.0.5, 14.0.6, 14.0.7, 14.0.8, 14.0.9, 14.0.10, 14.0.11, 14.0.12, 14.0.13
- `@ornikar/typed-css-modules-loader` 0.8.2, 0.8.3, 0.8.4, 0.8.5, 0.8.6, 0.8.7, 0.8.8, 0.8.9, 0.8.10, 0.8.11, 0.8.12
- `@ornikar/webpack-config` 12.0.2, 12.0.3, 12.0.4, 12.0.5, 12.0.6, 12.0.7, 12.0.8, 12.0.9, 12.0.10, 12.0.11, 12.0.12
- `@picsart/ai-sdk` 3.32.2
- `@picsart/gen-ai` 2.55.11
- `@qlik/api` 2.14.2
- `@qlik/browserslist-config` 3.0.2
- `@qlik/carbon-core` 2.1.1
- `@qlik/carboncopy` 1.1.6
- `@qlik/design-tokens` 1.3.13
- `@qlik/dts-bundler` 2.0.3
- `@qlik/embed-react` 2.5.3
- `@qlik/embed-runtime` 1.6.4
- `@qlik/embed-svelte` 1.1.4
- `@qlik/embed-web-components` 1.7.3
- `@qlik/eslint-config` 2.0.20
- `@qlik/eslint-config-base` 0.1.1
- `@qlik/eslint-config-react` 0.1.1
- `@qlik/eslint-config-svelte` 0.1.1
- `@qlik/eslint-config-vue` 0.1.1
- `@qlik/nebula-table-utils` 2.6.9
- `@qlik/oxfmt-config` 0.1.6
- `@qlik/oxlint-config` 0.7.2
- `@qlik/prettier-config` 1.0.3
- `@qlik/react-native-simple-grid` 1.5.5
- `@qlik/runtime-module-loader` 1.5.1
- `@qlik/sdk` 0.28.1
- `@qlik/sprout-design-docs` 1.0.2
- `@qlik/sprout-gesture` 0.0.13
- `@qlik/sprout-icons` 0.12.3
- `@qlik/sprout-react` 6.45.3
- `@qlik/sprout-react-table` 0.16.7
- `@qlik/tsconfig` 1.0.3
- `@servicetitan/acquisition-functions` 5.22.1, 5.22.2, 5.22.3, 5.22.4, 5.22.5, 5.22.6, 5.22.7
- `@servicetitan/admin-layout` 2.4.3, 2.4.4, 2.4.5, 2.4.6, 2.4.7, 2.4.8, 2.4.9
- `@servicetitan/admin-sql-table` 1.0.14, 1.0.15, 1.0.16, 1.0.17, 1.0.18, 1.0.19, 1.0.20
- `@servicetitan/ajax-handlers` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/anvil-css-utilities` 14.5.4, 14.5.5, 14.5.6, 14.5.7, 14.5.8, 14.5.9, 14.5.10
- `@servicetitan/anvil-fonts` 14.5.4, 14.5.5, 14.5.6, 14.5.7, 14.5.8, 14.5.9, 14.5.10
- `@servicetitan/anvil-icon` 0.5.1, 0.5.2, 0.5.3, 0.5.4, 0.5.5, 0.5.6, 0.5.7
- `@servicetitan/anvil-icons` 14.5.4, 14.5.5, 14.5.6, 14.5.7, 14.5.8, 14.5.9, 14.5.10
- `@servicetitan/anvil-react` 0.11.3, 0.11.4, 0.11.5, 0.11.6, 0.11.7, 0.11.8, 0.11.9
- `@servicetitan/anvil-themes` 14.5.4, 14.5.5, 14.5.6, 14.5.7, 14.5.8, 14.5.9, 14.5.10
- `@servicetitan/anvil-token` 0.4.1, 0.4.2, 0.4.3, 0.4.4, 0.4.5, 0.4.6, 0.4.7
- `@servicetitan/anvil2` 3.9.1, 3.9.2, 3.9.3, 3.9.4, 3.9.5, 3.9.6, 3.9.7
- `@servicetitan/anvil2-codemods` 0.11.2, 0.11.3, 0.11.4, 0.11.5, 0.11.6, 0.11.7, 0.11.8
- `@servicetitan/anvil2-ext-atlas` 4.0.2, 4.0.3, 4.0.4, 4.0.5, 4.0.6, 4.0.7, 4.0.8
- `@servicetitan/anvil2-ext-charts` 0.2.4, 0.2.5, 0.2.6, 0.2.7, 0.2.8, 0.2.9, 0.2.10
- `@servicetitan/anvil2-ext-common` 0.7.1, 0.7.2, 0.7.3, 0.7.4, 0.7.5, 0.7.6, 0.7.7
- `@servicetitan/anvil2-ext-mwv` 0.0.5, 0.0.6, 0.0.7, 0.0.8, 0.0.9, 0.0.10, 0.0.11
- `@servicetitan/anvil2-illustrations` 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6, 1.0.7, 1.0.8
- `@servicetitan/anvil2-mcp` 0.0.9, 0.0.10, 0.0.11, 0.0.12, 0.0.13, 0.0.14, 0.0.15
- `@servicetitan/assist-ui` 2.1.1, 2.1.2, 2.1.3, 2.1.4, 2.1.5, 2.1.6, 2.1.7
- `@servicetitan/assist-utils` 1.1.2, 1.1.3, 1.1.4, 1.1.5, 1.1.6, 1.1.7, 1.1.8
- `@servicetitan/carto-charts-core` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8
- `@servicetitan/carto-charts-react` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8
- `@servicetitan/carto-charts-rn` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8
- `@servicetitan/carto-react-kit` 0.8.4, 0.8.5, 0.8.6, 0.8.7, 0.8.8, 0.8.9, 0.8.10
- `@servicetitan/carto-rn-kit` 0.0.10, 0.0.11, 0.0.12, 0.0.13, 0.0.14, 0.0.15, 0.0.16
- `@servicetitan/carto-tokens` 0.3.1, 0.3.2, 0.3.3, 0.3.4, 0.3.5, 0.3.6, 0.3.7
- `@servicetitan/component-usage` 28.5.1, 28.5.2, 28.5.3, 28.5.4, 28.5.5, 28.5.6, 28.5.7
- `@servicetitan/confirm` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/confirm-navigation` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/contentful` 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8, 0.0.9
- `@servicetitan/contentful-proxy` 1.1.12, 1.1.13, 1.1.14, 1.1.15, 1.1.16, 1.1.17, 1.1.18
- `@servicetitan/cp-api` 1.115.1, 1.115.2, 1.115.3, 1.115.4, 1.115.5, 1.115.6, 1.115.7
- `@servicetitan/cp-mfe` 1.115.1, 1.115.2, 1.115.3, 1.115.4, 1.115.5, 1.115.6, 1.115.7
- `@servicetitan/cp-mfe-dev` 1.115.1, 1.115.2, 1.115.3, 1.115.4, 1.115.5, 1.115.6, 1.115.7
- `@servicetitan/cp-react-hooks` 1.115.1, 1.115.2, 1.115.3, 1.115.4, 1.115.5, 1.115.6, 1.115.7
- `@servicetitan/cp-ui` 1.115.1, 1.115.2, 1.115.3, 1.115.4, 1.115.5, 1.115.6, 1.115.7
- `@servicetitan/culture` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/data-query` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/datadog-rum` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/datetime-utils` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/design-system` 14.5.4, 14.5.5, 14.5.6, 14.5.7, 14.5.8, 14.5.9, 14.5.10
- `@servicetitan/docs-anvil-uikit-contrib` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/docs-uikit` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/document-title` 2.4.1, 2.4.2, 2.4.3, 2.4.4, 2.4.5, 2.4.6, 2.4.7
- `@servicetitan/dte-pdf-editor` 1.76.1, 1.76.2, 1.76.3, 1.76.4, 1.76.5, 1.76.6, 1.76.7
- `@servicetitan/dte-unlayer` 0.150.1, 0.150.2, 0.150.3, 0.150.4, 0.150.5, 0.150.6, 0.150.7
- `@servicetitan/eh-module-communication` 0.2.1, 0.2.2, 0.2.3, 0.2.4, 0.2.5, 0.2.6, 0.2.7
- `@servicetitan/error-boundary` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/eslint-config` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/eslint-plugin` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/eslint-plugin-decorators-declare` 12.8.15, 12.8.16, 12.8.17, 12.8.18, 12.8.19, 12.8.20, 12.8.21
- `@servicetitan/eslint-plugin-folder-schema` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/eslint-plugin-mobx-6` 12.8.15, 12.8.16, 12.8.17, 12.8.18, 12.8.19, 12.8.20
- `@servicetitan/eslint-plugin-processors-stub` 12.8.15, 12.8.16, 12.8.17, 12.8.18, 12.8.19, 12.8.20, 12.8.21
- `@servicetitan/examples` 1.2.5, 1.2.6, 1.2.7, 1.2.8, 1.2.9, 1.2.10, 1.2.11
- `@servicetitan/feature-spotlight` 3.9.1, 3.9.2, 3.9.3, 3.9.4, 3.9.5, 3.9.6, 3.9.7
- `@servicetitan/folder-lint` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/forge` 0.5.1, 0.5.2, 0.5.3, 0.5.4, 0.5.5, 0.5.6, 0.5.7
- `@servicetitan/form` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/form-state` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/grid` 0.0.63, 0.0.64, 0.0.65, 0.0.66, 0.0.67, 0.0.68, 0.0.69
- `@servicetitan/hammer-icon` 1.2.1, 1.2.2, 1.2.3, 1.2.4, 1.2.5, 1.2.6, 1.2.7
- `@servicetitan/hammer-react` 1.42.2, 1.42.3, 1.42.4, 1.42.5, 1.42.6, 1.42.7, 1.42.8
- `@servicetitan/hammer-token` 3.1.1, 3.1.2, 3.1.3, 3.1.4, 3.1.5, 3.1.6, 3.1.7
- `@servicetitan/hash-browser-router` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/help-center` 1.0.8, 1.0.9, 1.0.10, 1.0.11, 1.0.12, 1.0.13, 1.0.14
- `@servicetitan/html-sketchapp` 4.2.8, 4.2.9, 4.2.10, 4.2.11, 4.2.12, 4.2.13, 4.2.14
- `@servicetitan/install` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/intl` 7.2.1, 7.2.2, 7.2.3, 7.2.4, 7.2.5, 7.2.6, 7.2.7
- `@servicetitan/json-render-react` 0.4.6, 0.4.7, 0.4.8, 0.4.9, 0.4.10, 0.4.11, 0.4.12
- `@servicetitan/kendo-theme` 0.0.27, 0.0.28, 0.0.29, 0.0.30, 0.0.31, 0.0.32, 0.0.33
- `@servicetitan/ko-bridge` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/launchdarkly-service` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/lazy-module` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/ld-type-generator` 0.2.1, 0.2.2, 0.2.3, 0.2.4, 0.2.5, 0.2.6, 0.2.7
- `@servicetitan/line-item-editor` 1.5.1, 1.5.2, 1.5.3, 1.5.4, 1.5.5, 1.5.6, 1.5.7
- `@servicetitan/link-item` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/log-service` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/marketing-direct-mail-components` 20.1.1, 20.1.2, 20.1.3, 20.1.4, 20.1.5, 20.1.6, 20.1.7
- `@servicetitan/marketing-email-components` 20.2.3, 20.2.4, 20.2.5, 20.2.6, 20.2.7, 20.2.8, 20.2.9
- `@servicetitan/marketing-form` 0.1.2, 0.1.3, 0.1.4, 0.1.5, 0.1.6, 0.1.7, 0.1.8
- `@servicetitan/marketing-global-route` 1.14.1, 1.14.2, 1.14.3, 1.14.4, 1.14.5, 1.14.6, 1.14.7
- `@servicetitan/marketing-integration-widgets` 1.0.40, 1.0.41, 1.0.42, 1.0.43, 1.0.44, 1.0.45, 1.0.46
- `@servicetitan/marketing-route` 1.2.1, 1.2.2, 1.2.3, 1.2.4, 1.2.5, 1.2.6, 1.2.7
- `@servicetitan/marketing-ui` 9.3.1, 9.3.2, 9.3.3, 9.3.4, 9.3.5, 9.3.6, 9.3.7
- `@servicetitan/marketing-widgets` 1.0.1, 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6, 1.0.7
- `@servicetitan/measure-sheet-data` 2.6.1, 2.6.2, 2.6.3, 2.6.4, 2.6.5, 2.6.6, 2.6.7
- `@servicetitan/mfe-quick-actions` 0.5.49, 0.5.50, 0.5.51, 0.5.52, 0.5.53, 0.5.54, 0.5.55
- `@servicetitan/micro-frontend` 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8, 0.0.9, 0.0.10
- `@servicetitan/microfront` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8
- `@servicetitan/microfront-auth` 0.0.5, 0.0.6, 0.0.7, 0.0.8, 0.0.9, 0.0.10, 0.0.11
- `@servicetitan/microfront-tests` 0.0.11, 0.0.12, 0.0.13, 0.0.14, 0.0.15, 0.0.16, 0.0.17
- `@servicetitan/microfront-utils` 1.4.1, 1.4.2, 1.4.3, 1.4.4, 1.4.5, 1.4.6, 1.4.7
- `@servicetitan/modularpayments-webfields` 1.0.53, 1.0.54, 1.0.55, 1.0.56, 1.0.57, 1.0.58, 1.0.59
- `@servicetitan/moneyout-api-client` 1.29.1, 1.29.2, 1.29.3, 1.29.4, 1.29.5, 1.29.6, 1.29.7
- `@servicetitan/mpa-components` 2.5.1, 2.5.2, 2.5.3, 2.5.4, 2.5.5, 2.5.6, 2.5.7
- `@servicetitan/navigation` 14.1.1, 14.1.2, 14.1.3, 14.1.4, 14.1.5, 14.1.6, 14.1.7
- `@servicetitan/notifications` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/onboarding-ui` 18.5.1, 18.5.2, 18.5.3, 18.5.4, 18.5.5, 18.5.6, 18.5.7
- `@servicetitan/quick-actions` 1.15.2, 1.15.3, 1.15.4, 1.15.5, 1.15.6, 1.15.7, 1.15.8
- `@servicetitan/react-hooks` 7.7.1, 7.7.2, 7.7.3, 7.7.4, 7.7.5, 7.7.6, 7.7.7
- `@servicetitan/react-ioc` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/responsive` 6.1.1, 6.1.2, 6.1.3, 6.1.4, 6.1.5, 6.1.6, 6.1.7
- `@servicetitan/restrict-imports` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/schema-comparison` 0.1.3, 0.1.4, 0.1.5, 0.1.6, 0.1.7, 0.1.8, 0.1.9
- `@servicetitan/skeleton` 9.2.4, 9.2.5, 9.2.6, 9.2.7, 9.2.8, 9.2.9, 9.2.10
- `@servicetitan/standalone-core-feature-gates` 1.11.4, 1.11.5, 1.11.6, 1.11.7, 1.11.8, 1.11.9, 1.11.10
- `@servicetitan/standalone-feature-flags` 2.3.2, 2.3.3, 2.3.4, 2.3.5, 2.3.6, 2.3.7, 2.3.8
- `@servicetitan/standalone-root` 1.11.3, 1.11.4, 1.11.5, 1.11.6, 1.11.7, 1.11.8, 1.11.9
- `@servicetitan/standalone-tm-api` 1.1.1, 1.1.2, 1.1.3, 1.1.4, 1.1.5, 1.1.6, 1.1.7
- `@servicetitan/standalone-ui` 2.2.4, 2.2.5, 2.2.6, 2.2.7, 2.2.8, 2.2.9, 2.2.10
- `@servicetitan/startup` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/startup-jest` 2.2.1, 2.2.2, 2.2.3, 2.2.4, 2.2.5, 2.2.6, 2.2.7
- `@servicetitan/startup-mfe-compat` 0.5.1, 0.5.2, 0.5.3, 0.5.4, 0.5.5, 0.5.6, 0.5.7
- `@servicetitan/startup-utils` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/stylelint-config` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/suppress-warnings` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/table` 41.3.1, 41.3.2, 41.3.3, 41.3.4, 41.3.5, 41.3.6, 41.3.7
- `@servicetitan/tanstack-query-mobx` 6.2.1, 6.2.2, 6.2.3, 6.2.4, 6.2.5, 6.2.6, 6.2.7
- `@servicetitan/temporal-lite` 3.4.1, 3.4.2, 3.4.3, 3.4.4, 3.4.5, 3.4.6, 3.4.7
- `@servicetitan/testing-library` 6.6.1, 6.6.2, 6.6.3, 6.6.4, 6.6.5, 6.6.6, 6.6.7
- `@servicetitan/thoughtspot-theme` 1.7.1, 1.7.2, 1.7.3, 1.7.4, 1.7.5, 1.7.6, 1.7.7
- `@servicetitan/time-zones` 3.8.1, 3.8.2, 3.8.3, 3.8.4, 3.8.5, 3.8.6, 3.8.7
- `@servicetitan/titan-chat-ui` 7.1.3, 7.1.4, 7.1.5, 7.1.6, 7.1.7, 7.1.8, 7.1.9
- `@servicetitan/titan-chat-ui-anvil2` 9.0.1, 9.0.2, 9.0.3, 9.0.4, 9.0.5, 9.0.6, 9.0.7
- `@servicetitan/titan-chat-ui-common` 9.0.1, 9.0.2, 9.0.3, 9.0.4, 9.0.5, 9.0.6, 9.0.7
- `@servicetitan/titan-chat-ui-cypress` 2.1.3, 2.1.4, 2.1.5, 2.1.6, 2.1.7, 2.1.8, 2.1.9
- `@servicetitan/titan-chatbot-api` 9.0.1, 9.0.2, 9.0.3, 9.0.4, 9.0.5, 9.0.6, 9.0.7
- `@servicetitan/titan-chatbot-client` 2.1.3, 2.1.4, 2.1.5, 2.1.6, 2.1.7, 2.1.8, 2.1.9
- `@servicetitan/titan-chatbot-ui` 7.1.3, 7.1.4, 7.1.5, 7.1.6, 7.1.7, 7.1.8, 7.1.9
- `@servicetitan/titan-chatbot-ui-anvil2` 9.0.1, 9.0.2, 9.0.3, 9.0.4, 9.0.5, 9.0.6, 9.0.7
- `@servicetitan/titan-chatbot-ui-cypress` 9.0.1, 9.0.2, 9.0.3, 9.0.4, 9.0.5, 9.0.6, 9.0.7
- `@servicetitan/tokens` 12.9.1, 12.9.2, 12.9.3, 12.9.4, 12.9.5, 12.9.6, 12.9.7
- `@servicetitan/toolbelt-shared-registry` 1.14.1, 1.14.2, 1.14.3, 1.14.4, 1.14.5, 1.14.6, 1.14.7
- `@servicetitan/uikit-docs` 22.11.1, 22.11.2, 22.11.3, 22.11.4, 22.11.5, 22.11.6, 22.11.7
- `@servicetitan/unit-tests` 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.0.8
- `@servicetitan/va-mfe-loader` 1.1.1, 1.1.2, 1.1.3, 1.1.4, 1.1.5, 1.1.6, 1.1.7
- `@servicetitan/web-components` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7
- `@servicetitan/widget-platform` 5.6.1, 5.6.2, 5.6.3, 5.6.4, 5.6.5, 5.6.6, 5.6.7
- `@servicetitan/widget-platform-monolith` 5.6.1, 5.6.2, 5.6.3, 5.6.4, 5.6.5, 5.6.6, 5.6.7
- `@thiennq/docs-viewer` 1.6.2, 1.6.3, 1.6.4
- `@umacloud/cli-darwin-arm64` 1.0.74
- `@umacloud/cli-darwin-x64` 1.0.74
- `@umacloud/cli-linux-arm64` 1.0.74
- `@umacloud/cli-linux-musl-arm64` 1.0.74
- `@umacloud/cli-linux-musl-x64` 1.0.74
- `@umacloud/cli-linux-x64` 1.0.74
- `@umacloud/cli-win32-x64` 1.0.74
- `@umacloud/knowledge` 1.0.74
- `@workbench-stack/core` 3.9.8
- `babel-plugin-linaria-css-to-undefined` 0.3.1, 0.3.2, 0.3.3, 0.3.4, 0.3.5, 0.3.6, 0.3.7, 0.3.8, 0.3.9, 0.3.10, 0.3.11, 0.3.12, 0.3.13, 0.3.14, 0.3.15, 0.3.16, 0.3.17
- `conv-context-next` 1.0.1, 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10
- `editable-contracts` 0.0.12, 0.0.13, 0.0.14, 0.0.15, 0.0.16, 0.0.17, 0.0.18, 0.0.19, 0.0.20, 0.0.21, 0.0.22, 0.0.23, 0.0.24, 0.0.25, 0.0.26, 0.0.27
- `eslint-plugin-folder-schema` 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11, 1.0.12, 1.0.13, 1.0.14, 1.0.15, 1.0.16, 1.0.17, 1.0.18, 1.0.19, 1.0.20, 1.0.21
- `example-js-project` 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11
- `folder-lint` 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11, 1.0.12, 1.0.13, 1.0.14, 1.0.15, 1.0.16, 1.0.17, 1.0.18, 1.0.19, 1.0.20, 1.0.21
- `frontend-orb` 4.4.1, 4.4.2, 4.4.3, 4.4.4, 4.4.5, 4.4.6, 4.4.7, 4.4.8, 4.4.9, 4.4.10, 4.4.11, 4.4.12, 4.4.13, 4.4.14, 4.4.15, 4.4.16, 4.4.17, 4.4.18
- `http-metrics-middleware` 2.2.2
- `native-frontend-orb` 1.1.4, 1.1.5, 1.1.6, 1.1.7, 1.1.8, 1.1.9, 1.1.10, 1.1.11, 1.1.12, 1.1.13, 1.1.14, 1.1.15, 1.1.16, 1.1.17, 1.1.18, 1.1.19
- `picasso-plugin-hammer` 2.11.6
- `picasso-plugin-q` 2.11.6
- `picasso.js` 2.11.6
- `pob-test-package-in-monorepo` 5.2.1, 5.2.2, 5.2.3, 5.2.4, 5.2.5, 5.2.6, 5.2.7, 5.2.8, 5.2.9, 5.2.10, 5.2.11, 5.2.12, 5.2.13, 5.2.14, 5.2.15, 5.2.16
- `pob-test-typescript-package-in-monorepo` 4.2.1, 4.2.2, 4.2.3, 4.2.4, 4.2.5, 4.2.6, 4.2.7, 4.2.8, 4.2.9, 4.2.10, 4.2.11, 4.2.12, 4.2.13, 4.2.14, 4.2.15, 4.2.16, 4.2.17
- `qlik-chart-modules` 1.1.1
- `qlik-modifiers` 0.10.1
- `qlik-object-conversion` 0.17.2
- `rwc-client` 0.29.10, 0.29.11, 0.29.12, 0.29.13, 0.29.14, 0.29.15, 0.29.16, 0.29.17, 0.29.18, 0.29.19
- `server-hemera-mongo` 0.0.12
- `sn-listbox` 0.3.3
- `tslint-folder-schema` 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11, 1.0.12, 1.0.13, 1.0.14, 1.0.15, 1.0.16, 1.0.17, 1.0.18, 1.0.19, 1.0.20, 1.0.21
- `umadev` 1.0.74
- `verdaccio-okta-oauth` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7, 38.1.8, 38.1.9, 38.1.10, 38.1.11, 38.1.12, 38.1.13, 38.1.14, 38.1.15, 38.1.16
- `verdaccio-tarball-local-storage` 38.1.1, 38.1.2, 38.1.3, 38.1.4, 38.1.5, 38.1.6, 38.1.7, 38.1.8, 38.1.9, 38.1.10, 38.1.11, 38.1.12, 38.1.13, 38.1.14, 38.1.15, 38.1.16
- `workbench-browser-server` 0.0.2

</details>

<details><summary>SANDWORM\_MODE worm, February 2026: 20 versions of 19 packages</summary>

- `claud-code` every version
- `cloude-code` every version
- `rimarf` every version
- `naniod` every version
- `suport-color` every version
- `cloude` every version
- `opencraw` every version
- `crypto-reader-info` every version
- `format-defaults` every version
- `hardhta` every version
- `node-native-bridge` every version
- `secp256` every version
- `crypto-locale` every version
- `detect-cache` every version
- `locale-loader-pro` every version
- `parse-compat` every version
- `scan-store` every version
- `veim` every version
- `yarsg` 18.0.0, 18.0.1

</details>

<details><summary>SANDWORM\_MODE sleeper packages, February 2026: 4 versions of 4 packages</summary>

- `iru-caches` every version
- `iruchache` every version
- `ethres` every version
- `uudi` every version

</details>

<details><summary>tensorlake package, October 2026: 7 versions of 7 packages</summary>

- `tensorlake` 0.5.144
- `tensorlake-native-darwin-arm64` 0.5.144
- `tensorlake-native-linux-arm64-gnu` 0.5.144
- `tensorlake-native-linux-arm64-musl` 0.5.144
- `tensorlake-native-linux-x64-gnu` 0.5.144
- `tensorlake-native-linux-x64-musl` 0.5.144
- `tensorlake-native-win32-x64` 0.5.144

</details>

<details><summary>GlassWorm invisible code, March 2026: 6 versions of 2 packages</summary>

- `@aifabrix/miso-client` 4.7.2
- `@iflow-mcp/watercrawl-watercrawl-mcp` 1.3.0, 1.3.1, 1.3.2, 1.3.3, 1.3.4

</details>

<details><summary>Injective SDK, July 2026: 1 version of 1 package</summary>

- `@injectivelabs/sdk-ts` 1.20.21

</details>

<!-- <<< checks -->

## How each check reads

### 1. Coding agents

- An agent counts as used when its folders changed in the last 30 days.
- Codex with full access (`danger-full-access`) runs commands without asking under its default
  approvals too. Codex reads a project's `.codex/config.toml` once you trust that project, so that file
  counts as well.
- VS Code's settings are read from VS Code's and VS Code Insiders' user settings, profiles included.
  The Claude Code extension's setting is read in Cursor's user settings too.
- Claude Code's version is read only when it was installed with npm, including the local install its
  migrate-installer makes in `~/.claude/local`. A native install's version is not read.
- A version in the range of an advisory that no version fixes (for `mcp-remote`, 0.1.16 to 0.1.38 and
  0.8.0 to 0.14.3) is listed apart, as a tool with a published hole and no fixed version yet: each
  hole with its advisory, and no version named to update to. The `mcp-remote` row for an older
  version also says no version fixes the later advisory.

### 2. MCP servers and project settings

- A token counts in a server's environment or in its HTTP headers: `Authorization`, or a header
  ending in `-Key`, `-Token` or `-Secret`. A setting that holds a path, such as
  `GITHUB_APP_PRIVATE_KEY_PATH`, is not a token.
- Configs inside plugin folders and caches, such as Codex's `.tmp/plugins`, are shown as a separate
  count.
- Project settings that act as soon as an agent or editor opens the folder are flagged. A cloned repo
  brings them with it:
  - Claude Code hooks and the other commands its settings run: a status line, a file suggestion
    command, credential helpers.
  - MCP servers turned on without asking.
  - API traffic sent to another server, through `ANTHROPIC_BASE_URL` or Claude Code's endpoint
    variables for Bedrock, Google, Foundry and Claude Platform on AWS. Localhost and the provider's own
    API host are not another server.
  - `bypassPermissions` turned on. Claude Code before 2.1.257 took it from a project's settings.
  - An allow rule for every Bash command (`Bash` or `Bash(*)`), which Claude Code applies once you
    trust the folder.
  - VS Code or Cursor tasks that run when the folder opens, or when VS Code creates a worktree of the
    project.
  - New Copilot chats set to start in `autoApprove` or `autopilot` (`chat.permissions.default`), and
    new agent sessions set to `allowAll` (`chat.defaultConfiguration`). VS Code takes both from a
    project's `.vscode/settings.json` too.
  - Claude Code's VS Code extension set to start in `bypassPermissions`. Before 2.1.225 it took that
    from a project's `.vscode/settings.json`.
- These files are read the way the editor reads them: comments, JSON escapes, line ends (U+2028 and
  U+2029 too), other whitespace and the case of a task's `runOn`. So text in a string, a
  `\u0068ooks`, a backslash before a CRLF or a `FolderOpen` can't hide one.
- A `setup.mjs` in a project's `.claude` or `.vscode` folder, a name the TanStack, keyv and Mini
  Shai-Hulud worms use for their loader, is listed as a file to read when nothing else of theirs is
  beside it.
- A project's `.vscode/settings.json` that sets the old `chat.tools.autoApprove`, the setting the
  CVE-2025-53773 attack wrote, is listed too. VS Code 1.104 and later ignore it, so it is a sign to
  look at, not a setting in force.
- Files in your projects that are links to your own `~/.ssh/authorized_keys` are flagged, however the
  link is written (through other links too). An agent that edits one adds a login to your computer.

### 3. Keys in plain text

- It reads shell profiles, shell history, agent configs and `.env` files (linked ones too), and groups
  keys by provider and file.
- A placeholder shaped like a key, such as a run of x's or AWS's documented example, is not counted.
- It reads your agents' session transcripts, and the prompts some agents keep (Aider, Amazon Q,
  Continue, Copilot CLI, Factory Droid, Goose). A key there was read by an agent or given to it.
- With [ripgrep](https://github.com/BurntSushi/ripgrep) installed it checks every session in a few
  seconds. Without it, it checks the newest sessions while the rest of the scan runs and says how
  many. `--all-sessions` waits for all of them.
- A session file that is compressed or can't be read makes the check "partly checked", never "no
  keys". A shell profile, history file, agent config or `.env` file it can't read is named as not
  read.
- Amazon Q's and Kiro CLI's own temporary AWS credentials, which the CLI keeps for its telemetry, are
  not counted as a key an agent read.
- It also lists login files any agent can read, such as AWS credentials and SSH keys without a
  passphrase.

### 4. Keys saved in Claude Code allow lists

- A key counts in an allow, ask or deny rule. Blindspot also says whether an npm publish from that
  folder would ship the settings file.
- A key elsewhere in a settings file, such as its `env`, is listed in section 3 as a key in plain
  text, for a project's settings as for your own.

### 5. Recent key leaks

Where it looks:

- Python packages: every Python environment it finds, including Poetry's, pipenv's, Hatch's, asdf's,
  mise's, micromamba's, pipx's and uv's own folders and a project's tox environments. Also your temp
  folder and your uv cache. A bad version in the uv cache counts as a sign, as one in npm's cache
  does: uv keeps what it installs there.
- npm lockfiles: npm (including nested, bundled and workspace entries, on one line or pretty-printed,
  with an alias read as the package it names), yarn, pnpm, bun's text lockfile and Deno's `deno.lock`.
  bun's binary `bun.lockb` can't be read and is named as not checked.
- npm global installs, with every nested dependency and pnpm's global store: under npm's prefix
  wherever your npmrc or `npm_config_prefix` sets it, and where `NVM_DIR`, `N_PREFIX`, `VOLTA_HOME`
  and bun's settings put them. Also npx and npm's download cache.
- Editor extensions: the ones published only to Open VSX are looked for in the folders of the editors
  that install from there (Cursor, Windsurf and Devin Desktop, VSCodium, Kiro, Antigravity and
  Positron, and the remote servers of Cursor, Windsurf, Devin Desktop and Positron). The rest are
  looked for in VS Code's folders too (Insiders and VS Code Server included). An Open VSX build's id in
  VS Code's own folder is the Marketplace's own extension and is not flagged.

How a finding reads:

- Each finding comes with a line on what that incident did, when, and its source.
- If it finds `gh-token-monitor`, it says to stop it before revoking any GitHub token, because it runs
  a destructive command when the stolen token stops working. Until then, every line of the report
  that says to rotate or revoke a key waits for it. On Windows it is in
  `%LOCALAPPDATA%\gh-token-monitor`, with a scheduled task of that name to delete.
- With a SANDWORM_MODE package, the fix to remove what that worm leaves (its git hooks and the MCP
  servers it adds) comes before any fix that says to rotate, and every other line that says to rotate
  waits for it: its pre-push hook sends npm tokens out on every push.
- A bad version found only in a lockfile, with nothing installed where that lockfile puts it (a
  project's nested `node_modules` folders, pnpm's `node_modules/.pnpm`, bun's `node_modules/.bun`,
  yarn's cache or a yarn 1 offline mirror), in a global install or in npm's cache, says to act if you
  installed that project. So does its incident's own fix, after the fixes for what was found
  installed. A folder there it can't read is named, never taken for no install.
- Next to malware found on the machine, the headline and row 05 name only what was found.
- Some builds are shown as versions to update, not a compromised machine: Mistral AI's and UiPath's
  npm builds, whose malware their maintainers say could not run, and `telnyx` 4.87.1, whose malware
  Telnyx says could not run. So are `mistralai` 2.4.6, `guardrails-ai` 0.10.1 and `durabletask` 1.4.1
  to 1.4.3 on a Mac or Windows: their malware ran on Linux only, as Mistral says, the code SafeDep
  recovered from `guardrails-ai` shows and GitHub's malware advisory for `durabletask` says.
- `mistralai` and `guardrails-ai` both write `/tmp/transformers.pyz`. It is listed once: with the one
  whose package was found, or, with neither found, as written by either.
- The `@keyv` 6.0.0 builds published without the install hook and SANDWORM_MODE's four sleeper
  packages count as malware: GitHub's malware advisories say a machine that installed one is
  compromised.
- A marker in the shared temp folder (a file or one of LiteLLM's marker folders) and the LiteLLM
  loader's lock there count only when you own them and not through a link, and a file only under its
  one name.
- An extension whose malware was made for another system is shown as a malicious extension to remove,
  not a compromised machine. The list above gives the system for each.
- GlassWorm's LaunchAgent, `~/Library/LaunchAgents/com.user.nodestart.plist`, counts next to one of
  GlassWorm's own extensions. On its own, or next to another incident's extension, it is a file to
  check, since people name their own LaunchAgents that way.
- The kitty-monitor files Nx Console 18.95.0 leaves, which the AntV packages leave too, are listed
  once: with Nx Console when no AntV package was found, else as npm malware.
- The Injective SDK version that sent out wallet seed phrases and private keys is shown as a version
  to update. Moving the funds out of its wallets, from a clean machine, is the first fix after any
  act-now one.

What is not on the lists, and why:

- The config and temp files of the Mastra malware: they start nothing.
- Three more themes of the GlassWorm-linked cluster, which Microsoft removed from its Marketplace as
  malware but in which no source shows a payload, and the cluster's two other Open VSX extensions, in
  which Socket shows none either.
- The extension the 18 March droppers install from GitHub: no source gives the id its folder takes.
- Extensions the posts call sleepers, which carried nothing yet, and the rest of the weekend wave of
  impersonation extensions the 18 March post lists without showing them deliver malware. Aikido's
  post shows one of them, `specstudio.code-wakatime-activity-tracker`, installing
  `floktokbok.autoimport` into every editor, and both are listed.
- `oorzc.ssh-tools` before 0.5.1. Open VSX removed every version, but the earlier ones are its
  developer's own.

Each data file's header gives the sources and reasons for every line.

## What it does not read

- Containers, servers and CI.
- The home scan goes 6 folders deep and skips dependency, build and cache folders (`node_modules`,
  `build`, `dist`, `target` and `vendor` among them). A lockfile or project file deeper or in one of
  those is not read, and the npm row says so.
- These are named as not checked, and the summary doesn't read clean over them:
  - folders in your home it can't read;
  - key, MCP config, settings and allow-list files it can't read, or a pipe or device in their place,
    or one behind a folder it can't open;
  - settings and tasks files over 16 MB;
  - global install and npx folders it can't read;
  - Python environments and editor extension folders it can't open;
  - in `gird-check.sh`, folders with a line break in their name.

## Windows

`gird-check.sh` in Git Bash, MSYS2 or Cygwin checks the Windows places:

- agents and MCP configs in your user folder and in `%APPDATA%` and `%LOCALAPPDATA%` (Claude Desktop,
  Cursor, VS Code, Windsurf, Goose);
- PowerShell's profiles and command history;
- Python installs (under `AppData`, in `%ProgramFiles%` and at the system drive's root, pyenv-win's and
  the Microsoft Store's) and the uv cache;
- the npm global-install folders the PowerShell version reads (npm's own, nvm-windows, fnm, Volta,
  mise, pnpm and npx's cache);
- the files Python malware leaves in `%TEMP%`.

Without jq, which Git Bash doesn't include, it finds MCP config files but can't count the servers in
JSON ones. In WSL it checks the Linux system you run it in, not the files on the Windows side, and
says so at the end.

`gird-check.ps1` has the same checks and the same report. It also reads PowerShell's command history.
A file that takes too long to check is listed as skipped, never counted as clean.
