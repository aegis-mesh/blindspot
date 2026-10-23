# Keys in agent sessions

Status: design, not built. Builds on PR #12 (npm worms and project settings).

## Why

A key in a coding agent's session transcript was more than stored on disk: the agent read it or
printed it, so it went to the AI service with the conversation. Blindspot already treats a key in
shell history as exposed and says to rotate it. A key in a transcript gets the same treatment.

## What it checks

Every agent Blindspot already detects, plus the ones below, one combined list of session files.

| agent | where (macOS / Linux; Windows under `%USERPROFILE%` unless given) | format | readable | source |
|---|---|---|---|---|
| Claude Code | `~/.claude/projects/*/*.jsonl` (`CLAUDE_CONFIG_DIR` moves it) | JSONL | yes | measured on a Mac; docs |
| Claude Desktop agent mode | `~/Library/Application Support/Claude/local-agent-mode-sessions/` | JSON | yes | measured on a Mac |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl`, `~/.codex/history.jsonl` (`CODEX_HOME`) | JSONL | yes | source |
| Gemini CLI | `~/.gemini/tmp/*/chats/` (`GEMINI_CLI_HOME`) | JSONL, older JSON | yes | source |
| Qwen Code | `~/.qwen/projects/*/chats/*.jsonl` (`QWEN_HOME`) | JSONL | yes | source |
| OpenCode | `~/.local/share/opencode/opencode*.db` (`XDG_DATA_HOME`) | SQLite, plain text columns | yes | source |
| GitHub Copilot CLI | `~/.copilot/session-state/` (`COPILOT_HOME`) | JSONL | yes | docs |
| Roo Code | VS Code / Cursor `globalStorage/rooveterinaryinc.roo-cline/tasks/*/` | JSON | yes | source |
| Cline | `globalStorage/saoudrizwan.claude-dev/tasks/*/`, newer `~/.cline/data/sessions/` | JSON, SQLite | yes | docs; old path from memory |
| Continue | `~/.continue/sessions/` (`CONTINUE_GLOBAL_DIR`) | JSON | yes | source |
| Goose | `~/.local/share/goose/sessions/sessions.db`; Windows `%APPDATA%\Block\goose\data\sessions\` | SQLite | yes | source; macOS path to confirm |
| Aider | `.aider.chat.history.md` in each project, found by the home scan | Markdown | yes | source |
| Amazon Q CLI | `amazon-q/data.sqlite3` in the platform data folder | SQLite | yes | source |
| Kiro CLI | `~/.kiro/sessions/`, `kiro-cli/data.sqlite3` | JSONL, SQLite | yes | docs |
| Factory Droid | `~/.factory/sessions/` | JSONL | yes | third party |
| Cursor | `Cursor/User/globalStorage/state.vscdb`, `~/.cursor/projects/*/agent-transcripts/` | SQLite, JSONL | yes | third party |
| Windsurf | `~/.codeium/windsurf/cascade/*.pb` | encrypted | no | third party |
| Antigravity | `~/.gemini/antigravity/conversations/*.pb` | appears encrypted | no | third party |

Paths marked docs or third party are confirmed on a machine that has the agent before they ship.
An agent whose sessions can't be read (Windsurf, Antigravity) is named as not checked, never
shown as clean. SQLite files are searched as bytes: text columns are stored as plain text, and a
match in a freed page is still a key that was sent.

## Matching

- Blindspot's own key list, `ALL_KEYS`, the same one used for files. Argus Enterprise's patterns
  are not copied: Blindspot is public.
- A match that looks made up is dropped: eight or more of the same character in a row, fewer than
  12 distinct characters, or `EXAMPLE`, `xxxx`, `0123456789`, `abcdef` in it.
- Per session, each distinct key counts once. Across sessions, distinct keys are counted with a
  hash salted per run, kept in memory only.
- The key never leaves the matching process. Nothing written to disk, printed or sent contains a
  key or a hash that outlives the run.

## Engines, and keeping the run time the same

Measured on one Mac, 3,003 sessions, 5.2 GB, full `ALL_KEYS`:

| engine | time |
|---|---|
| ripgrep | 1.9 s |
| perl, 8 in parallel | about 50 s |
| BSD grep | about 9 min (projected) |

1. ripgrep on `PATH`: it checks every session.
2. Otherwise perl, which macOS, most Linux and Git Bash include: newest sessions first, in parallel.
3. Neither: the agent sessions are named as not checked.

The transcript check starts in the background when the home scan starts. When the rest of the
check is done, which is the signal, it is stopped and the report states its coverage, such as
"Checked the newest 400 of 3,003 sessions". `--full` waits for it to finish. The coverage line
then gives a one-line way to check everything: install ripgrep (`brew install ripgrep`,
`winget install BurntSushi.ripgrep.MSVC`, `apt install ripgrep`) or run with `--full`.

No download by default. `--fetch-rg` downloads a pinned ripgrep release over HTTPS, checks it
against a SHA-256 written in the script for each platform, runs it from a temp folder and deletes
it. It is refused with `--offline` or `DO_NOT_TRACK=1`. It ships in a separate PR.

`gird-check.ps1`: `rg.exe` on `PATH`, otherwise a background runspace using .NET regex with the
same time limit per file as the other checks, newest first, stopped by the same signal.

## The report

Section 3, "Keys in plain text", gains a block like "Login files":

```
     Keys in agent sessions
     ✗  Claude Code       3 sessions: Anthropic, AWS
     ✗  Codex             1 session: OpenAI
        These were sent to the AI service each agent uses.
        Checked the newest 400 of 3,003 sessions. Install ripgrep or add --full to check all.
```

- Fix (section 3): "Keys in N agent sessions were sent to the AI service the agent uses. Rotate
  them." Counted like keys in shell history in the score: 6 per session, at most 12.
- `--full` and a saved report list up to 20 session files.
- The summary row for section 3 mentions sessions when there are no plain-text key files.

## What it shares

Nothing new in this PR. Adding counts (sessions with keys, by agent and provider) to the report
needs the Worker and the D1 schema to accept them: a separate decision.

## Tests

- A fixture session per readable agent format, with a planted key and a made-up one, and good
  versions that must not match.
- ripgrep and perl return the same rows on the same fixture.
- A test hook stops the perl engine after a set number of files, to test the coverage line
  (no wall clock in tests).
- Never prints a planted key; the result link and payload are unchanged.
- `gird-check.ps1` gets the same cases, and both scripts must carry the same agent path list.

## Not covered

- Codex may compress sessions older than 7 days into `.jsonl.zst`. The feature is off by
  default and not built here.
- Encrypted session stores (Windsurf, Antigravity).
- Keys that were pasted and later deleted from a session by the agent itself.
