# Checks from the incident dossier

Status: built (gird-check.sh, gird-check.ps1, data/auto-approve.tsv, data/outdated.tsv, data/bad-extensions.tsv).
Builds on `data/` (PR #17). The payload does not change. The score drops for a GlassWorm hit as for
other act incidents, and the result link gains `ex` (malware in an editor extension, after `py`);
the other checks change neither.

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
`data/sessions.tsv`), one or more patterns that must all match, and the setting as shown. A `.json`
file is read as one line through the scripts' `flat` (comments are its job), and a match starts at
the text, a `{` or a `,` and ends at the text's end, a `,` `}` `#` or `/`. A `.toml` file is read
line by line: a `#` line is skipped, a match is a whole line up to a `#` comment (so a setting
inside an inline table, a profile written as one, does not count), and only the lines before the
first `[table]` count.

| agent | file | patterns | source |
|---|---|---|---|
| Claude Code | `{ENV:CLAUDE_CONFIG_DIR:~/.claude}/settings.json` | `"defaultMode": "bypassPermissions"` | code.claude.com/docs/en/permission-modes |
| Codex | `{ENV:CODEX_HOME:~/.codex}/config.toml` | `approval_policy = "never"` and `sandbox_mode = "danger-full-access"` | Codex config reference |
| VS Code (Copilot) | user `settings.json` per OS | `"chat.tools.global.autoApprove": true` | VS Code Copilot settings reference and the 1.104 release notes |

VS Code 1.104 renamed `chat.tools.autoApprove` to `chat.tools.global.autoApprove` without
migration, so current VS Code ignores the old name, and the setting is registered with the scope
`APPLICATION_MACHINE` (`chat.shared.contribution.ts`), so a project's `.vscode/settings.json` copy
is ignored too. Neither is a setting in force, so neither is a line here. A project's
`"chat.tools.autoApprove": true` is what the CVE-2025-53773 prompt injection made Copilot write, so
section 2 lists it under "Project settings that act as soon as the folder is opened", worded as a
sign of that attack (or of an old VS Code) that VS Code 1.104 and later ignore; it does not lower
the score.

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

Versions are compared numerically, part by part. A version that does not parse is not reported, and
neither is one of fewer than three parts in an MCP config (`mcp-remote@0.1`): that is a range npx
resolves when it runs, not a version. The Amazon Q row is named "Amazon Q language server": the
version folder is the language server's (Language Servers for AWS), which the bulletin fixes in
1.69.0; the extension's own version is not read. Kiro is not built: the vendor's fixed version
(0.11) and the dossier's (0.11.130) differ, and its version file was not verified.

Report, section 01, a block "Tools with a security fix to install": one `!` row per tool, the
installed version, "update to <fixed> or later", what the hole allows and the advisory. Fix (yellow):
"Update the tools listed in section 1 that have a security fix."

## 3. Project files that link to `~/.ssh/authorized_keys`

The home scan also prints symbolic links as candidates, and the shell keeps those that resolve to
this user's own `~/.ssh/authorized_keys`, outside `~/.ssh` itself: `-ef` in bash (the files
themselves, so a link into a repo's own `.ssh/authorized_keys` fixture does not count), the resolved
paths in PowerShell. A link to the file's place counts before the file exists, since an agent writing
through it creates it. A find with `-lname` (GNU, BSD) narrows the candidates to links whose text
names `authorized_keys`; BusyBox's find has no `-lname` and rejects the whole expression over it (so
on Alpine the scan used to print nothing and every file check read as clean), and its `-exec ... +`
drops links, so there every link is printed with one `-exec` each. If find still rejects the
expression, the header says the home folder was not scanned instead of calling it clean. No source
shows an agent reading a private key through a link, so only `authorized_keys` is checked.

Report, section 02, a red block "Files that link to your SSH logins", one row per link. Advice: "An
agent that edits this file adds a login to this computer. Delete the link." Fix (red, section 02):
"Delete the links to ~/.ssh/authorized_keys listed in section 2."

## 4. GlassWorm extensions and the Injective SDK

- `data/bad-extensions.tsv`: the extension id, as its folder spells it (`publisher.name`, compared
  without case), a version or `*`, the incident, and the registry: `openvsx` when the bad build was
  only ever published to Open VSX, `any` otherwise. Looked for as `<id>-<version>` folders in
  `~/.vscode/extensions` (VS Code, which installs from the Marketplace) and in `~/.cursor/extensions`,
  `~/.windsurf/extensions`, `~/.vscode-oss/extensions` and `~/.kiro/extensions` (Cursor, Windsurf,
  VSCodium and Kiro, which install from Open VSX); an `openvsx` line is not looked for in VS Code's
  own folder, where the same version is the Marketplace's clean build. A hit is its own section 5
  row, "Editor extensions", with the incident line, level `act`, its own headline and fix, never
  called npm malware.
- GlassWorm (Socket, January 2026): the four `oorzc` extensions at their malicious versions, and
  the thirteen earlier extensions Socket names, at every version, all `openvsx`: Socket says the
  malicious versions were published to Open VSX and that the publisher's Marketplace listings were
  not compromised, the Marketplace has a clean `oorzc.ssh-tools` 0.5.1 of March 2026, and the
  thirteen were never on the Marketplace. Its startup file,
  `~/Library/LaunchAgents/com.user.nodestart.plist`, is a `startup` indicator (Socket names it, like
  gh-token-monitor's `com.user.gh-token-monitor.plist`); as the sign of an incident whose packages are
  extensions only, it is listed with the extensions, counts as the extension finding, and the fix
  names what section 5 lists: the extensions, the startup file, or both. The incident's advice names
  the staging files Socket lists (`/tmp/ijewf`, `/tmp/out.zip`) and the LaunchAgent to remove.
- Injective: `@injectivelabs/sdk-ts 1.20.21` in `data/bad-npm.tsv`. Only that package carries the
  code (the advisory); the others at 1.20.21 depend on it, so a lockfile with them lists it too.
  Level `update`: the machine is not compromised, but a wallet used with it is, and the incident
  line says so. The `update` level's description changes from "nothing ran" to "the machine itself
  is not compromised".

## Not covered

- Settings saved in SQLite or a format that needs a parser (above).
- GlassWorm's later waves without a primary list of extension ids.
- An Open VSX build installed into VS Code by hand (a VSIX) sits in VS Code's folder, where an
  `openvsx` line is not looked for.
- Comments in a JSONC settings file are `flat`'s to remove; a setting the comment removal leaves in
  place is read if it sits at a boundary (`/*, "key": true */`).
- Codex values written in single quotes, and a `[profiles.x]` table made the default by
  `profile = "x"`, are not read.
- A link that reaches `authorized_keys` through a linked folder: bash resolves it (`-ef`),
  PowerShell compares the written paths.
- An agent run with a flag on the command line (`--dangerously-skip-permissions`, `--yolo`):
  nothing on disk records it.

## Tests

For each check, both scripts: a fixture that must be found, a near miss that must not (a commented
setting; the old or a project-level VS Code setting; a Codex profile written as an inline table; a
version equal to the fixed one; `mcp-remote@0.1`; an `authorized_keys` link inside `~/.ssh` and one
into a repo's own fixture; a clean version of a GlassWorm extension, and the Marketplace build of
0.5.1 in VS Code's folder), the report text, and the fix. The LaunchAgent is tested with and without
its extension, a link to a missing `authorized_keys`, and a `find` that rejects its options (bash
only). `tests/made-up.sh` adds a made-up row to each new data file. Each new test is reverted against
its change and must fail.
