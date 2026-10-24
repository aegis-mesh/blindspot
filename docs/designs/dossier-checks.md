# Checks from the incident dossier

Status: built (gird-check.sh, gird-check.ps1, data/auto-approve.tsv, data/outdated.tsv, data/bad-extensions.tsv). Builds on `data/` (PR #17). Nothing new is shared: the payload, the
result link and the score do not change.

## Why

GIRD's incident dossier (gird.ai/incidents) lists incidents Blindspot does not look for yet. Five
were proposed; each was checked against its primary source before this design, and one was
dropped.

| check | decision | why |
|---|---|---|
| Agents set to approve everything | build, for three agents | verified setting names for Claude Code, Codex and VS Code Copilot |
| Agent versions with a published fix | build, four tools | each has a GitHub or vendor advisory with a fixed version |
| Project files that link to `~/.ssh/authorized_keys` | build | Wiz GhostApproval: an agent edits a repo file that is a link, and writes the attacker's key into `authorized_keys` |
| GlassWorm extensions, Injective SDK | build, as data lines | Socket's GlassWorm post, GHSA-5fc4-fm2x-6f4r |
| `.env` files a repo does not ignore | dropped | the dossier does not cite it; reproducing git's ignore rules from files is unreliable, and asking git runs a repo's `core.fsmonitor` program (measured with `git check-ignore` on git 2.50.1) |

## 1. Agents set to approve everything

A new data file, `data/auto-approve.tsv`: agent, os, path (the path tokens of
`data/sessions.tsv`), one or more patterns that must all match a line of the file (lines starting
with `//` or `#` are skipped), and the setting as shown.

| agent | file | patterns | source |
|---|---|---|---|
| Claude Code | `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/settings.json` | `"defaultMode": "bypassPermissions"` | code.claude.com/docs/en/permission-modes |
| Codex | `{ENV:CODEX_HOME:~/.codex}/config.toml` | `approval_policy = "never"` and `sandbox_mode = "danger-full-access"` | Codex config reference |
| VS Code (Copilot) | user `settings.json` per OS, and every workspace `.vscode/settings.json` the home scan finds | `"chat.tools.autoApprove": true` or `"chat.tools.global.autoApprove": true` | VS Code Copilot settings reference; CVE-2025-53773 wrote this key into a workspace file |

Not built: Gemini CLI (its YOLO mode cannot be saved in settings), the Cursor editor (stored in
SQLite), Cursor CLI (the docs do not say what `unrestricted` does), Kiro (YAML rules need a parser),
Cline (the default already sets one of the two flags), Windsurf and Amazon Q (not documented).

Report, section 01, a block after the agents:

```
     Agents set to run commands without asking
     !  Claude Code   ~/.claude/settings.json      bypassPermissions
        A prompt injection in anything the agent reads can then run commands on this
        computer. Turn it off unless the agent runs in a sandbox.
```

Fix (section 01, yellow): "Turn off run-without-asking in the agents listed in section 1, unless
they run in a sandbox."

## 2. Agent versions with a published fix

A new data file, `data/outdated.tsv`: id, name, how the version is read, where, the affected
range, what the hole allows (a few words, from the advisory) and the advisory.

| tool | read from | affected | advisory |
|---|---|---|---|
| Cursor | `Cursor.app/Contents/Info.plist` `CFBundleShortVersionString`, in `/Applications` and `~/Applications` (macOS only: the other platforms' version files were not verified) | `< 3.0` | GHSA-3p48-7v9f-v5cw, GHSA-3v8f-48vw-3mjx (sandbox escape) |
| Amazon Q language server | the highest version folder under `aws/toolkits/language-servers/AmazonQ/` in `~/Library/Caches`, `~/.cache` or `%LOCALAPPDATA%` | `< 1.69.0` | AWS-2026-047 (opening a hostile workspace runs its commands) |
| Claude Code | `@anthropic-ai/claude-code/package.json` in global npm installs | `>= 0.2.116 < 1.0.24` | GHSA-9f65-56v6-gxw7 (a web page can talk to the IDE connection) |
| mcp-remote | `mcp-remote/package.json` in global installs and npx's cache, and `mcp-remote@<version>` in MCP config args | `>= 0.0.5 < 0.1.16` | GHSA-6xpm-ggf7-wc3p (a hostile MCP server runs commands) |

Versions are compared numerically, part by part. A version that does not parse is not reported.
Kiro is not built: the vendor's fixed version (0.11) and the dossier's (0.11.130) differ, and its
version file was not verified.

Report, section 01, a block "Agents with a security fix to install": one `!` row per tool, the
installed version, "update to <fixed> or later", what the hole allows and the advisory. Fix (yellow):
"Update the tools listed in section 1 that have a security fix."

## 3. Project files that link to `~/.ssh/authorized_keys`

The home scan also prints symbolic links whose target ends in `.ssh/authorized_keys`, outside
`~/.ssh` itself (`find -lname`). No source shows an agent reading a private key through a link, so
only `authorized_keys` is checked.

Report, section 02, a red block "Files that link to your SSH logins", one row per link. Advice: "An
agent that edits this file adds a login to this computer. Delete the link." Fix (red, section 02):
"Delete the links to ~/.ssh/authorized_keys listed in section 2."

## 4. GlassWorm extensions and the Injective SDK

- `data/bad-extensions.tsv`: the extension id, as its folder spells it (`publisher.name`, compared
  without case), a version or `*`, and the incident. Looked for as `<id>-<version>` folders in
  `~/.vscode/extensions`, `~/.cursor/extensions`, `~/.windsurf/extensions`,
  `~/.vscode-oss/extensions` and `~/.kiro/extensions`. A hit is a section 5 npm-worm style row with
  the incident line, level `act`.
- GlassWorm (Socket, January 2026): the four `oorzc` extensions at their malicious versions, and
  the thirteen earlier extensions Socket names, at every version. Plus the startup file
  `~/Library/LaunchAgents/com.user.nodestart.plist` (`data/indicators.tsv`, macOS).
- Injective: `@injectivelabs/sdk-ts 1.20.21` in `data/bad-npm.tsv`. Only that package carries the
  code (the advisory); the others at 1.20.21 depend on it, so a lockfile with them lists it too.
  Level `update`: the machine is not compromised, but a wallet used with it is, and the incident
  line says so. The `update` level's description changes from "nothing ran" to "the machine itself
  is not compromised".

## Not covered

- Settings saved in SQLite or a format that needs a parser (above).
- GlassWorm's later waves without a primary list of extension ids.
- An agent run with a flag on the command line (`--dangerously-skip-permissions`, `--yolo`):
  nothing on disk records it.

## Tests

For each check, both scripts: a fixture that must be found, a near miss that must not (a commented
setting; a version equal to the fixed one; an `authorized_keys` link inside `~/.ssh`; a clean
version of a GlassWorm extension), the report text, and the fix. `tests/made-up.sh` adds a made-up
row to each new data file. Each new test is reverted against its change and must fail.
