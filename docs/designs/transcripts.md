# Keys in agent sessions

Status: design, not built. Builds on PR #12 (npm worms and project settings).

## Why

A key in a coding agent's session transcript was more than stored on disk: the agent read it,
printed it or was given it. With a hosted model it then went to the AI service with the
conversation; with a local model it at least sits in another file any agent can read. Blindspot
already treats a key in shell history as exposed and says to rotate it. A key in a transcript gets
the same advice.

## What it checks

One combined list of session files, from a transcript-source list kept apart from `AGENTS`:
`AGENTS` feeds `agent_ids` in the payload, and gird.ai drops ids it does not know.

The "source" column says how each row was established: measured on a machine, read in the agent's
source code, its docs, or third-party notes. Every row not measured is confirmed on a machine that
has the agent before it ships, and "readable" is what we expect until then.

| agent | where (macOS / Linux; Windows under `%USERPROFILE%` unless given) | format | expected readable | source |
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
| Aider | `.aider.chat.history.md` in each project, found by the home scan, so only as deep as the scan goes | Markdown | yes | source |
| Amazon Q CLI | `amazon-q/data.sqlite3` in the platform data folder | SQLite | yes | source |
| Kiro CLI | `~/.kiro/sessions/`, `kiro-cli/data.sqlite3` | JSONL, SQLite | yes | docs |
| Factory Droid | `~/.factory/sessions/` | JSONL | yes | third party |
| Cursor | `Cursor/User/globalStorage/state.vscdb`, `~/.cursor/projects/*/agent-transcripts/` | SQLite, JSONL | yes | third party |
| Windsurf | `~/.codeium/windsurf/cascade/*.pb` | reported encrypted | no | third party |
| Antigravity | `~/.gemini/antigravity/conversations/*.pb` | reported encrypted | no | third party |

An agent whose sessions can't be read (Windsurf, Antigravity) is named as not checked, never
shown as clean. SQLite files are searched as bytes: text columns are stored as plain text, and a
match in a freed page is still a key that was sent.

## Matching

- Blindspot's own key list, `ALL_KEYS`, the same one used for files. Argus Enterprise's patterns
  are not copied: Blindspot is public.
- Transcripts are JSON, where a key often follows an escape such as `\n`. Three patterns need a
  non-alphanumeric character before the key (OpenAI's legacy `sk-` keys, `hf_`, `AQ.`), so the
  transcript check also accepts `\n`, `\t`, `\r` and `\"` as that boundary.
- A match that looks made up is dropped inside the matching stage: eight or more of the same
  character in a row, fewer than 12 distinct characters, or `EXAMPLE`, `xxxx`, `0123456789`,
  `abcdef` in it. Shell history is not filtered this way, because its matches come from commands
  the person typed; transcripts also hold tool output such as test fixtures.
- Only a session path and a provider id leave the matching stage. Keys travel through a pipe from
  ripgrep to that stage, as `grep -o | awk` does today, and are never written to disk, printed or
  sent. Distinct keys are not counted: the report counts sessions.

## Engines

Measured on one Mac with a warm disk cache, 3,003 sessions, 5.2 GB, full `ALL_KEYS`. Other
machines will differ:

| engine | time |
|---|---|
| ripgrep | 1.9 s |
| perl, 8 in parallel | about 50 s |
| BSD grep | about 9 min (projected) |

1. ripgrep, found with `type -P rg` (never a shell function or alias), run as
   `rg -a --hidden --no-ignore --no-config -o`: `-a` because SQLite files look binary, `--hidden`
   and `--no-ignore` because `~/.claude` and `~/.codex` are hidden and may be gitignored, and
   `--no-config` against a person's ripgrep settings. Exit 2 (a file it could not read) means
   partly checked.
2. Otherwise perl, which macOS, most Linux and Git Bash include, newest sessions first. One perl
   parent forks the workers, and each worker prints a done line for a file only after finishing
   it.
3. Neither: the agent sessions are named as not checked.

## Lifecycle and coverage

- The check starts in the background when the home scan starts, and is stopped when the rest of
  the check is done. That is the signal; there is no timer.
- `--all-sessions` waits for it to finish instead. (`--full` already means "every detail".)
- Coverage counts only files with a done line. A file in flight when stopped, unreadable, or
  compressed (`.zst`) counts as not checked, and compressed files are named.
- ripgrep reports no per-file progress, so a stopped ripgrep run reads "partly checked", with no
  number.
- Stopping: the perl parent traps TERM and HUP, kills its workers and exits; workers also exit
  when their parent is gone (`getppid`), so nothing outlives the script even after a kill -9.
  ripgrep is killed by its process ID; under Git Bash, a native `rg.exe` is stopped with
  `taskkill`. The results file is made with `mktemp`, removed by the existing cleanup, which also
  traps HUP from now on, and holds paths and provider ids only.

## Fetching ripgrep

No download by default. `--fetch-rg`, in a separate PR, downloads a pinned ripgrep release over
HTTPS into a `mktemp -d` folder (mode 700). It checks the file against a SHA-256 written in the
script for each platform before running it, with `shasum`, `sha256sum` or `certutil`. On any
failure, including TLS errors on a machine whose traffic is inspected, it falls back to perl. It is
refused with `--offline` or `DO_NOT_TRACK=1`. The hashes ship with the script, so they guard
against a swapped download, not against a swapped script.

`gird-check.ps1`: `rg.exe` on `PATH` with the same flags, otherwise a background runspace using
.NET regex with the same time limit per file as the other checks, newest first, stopped by the
same signal. A file that hits the time limit counts as not checked.

## The report

Section 3, "Keys in plain text", gains a block like "Login files":

```
     Keys in agent sessions
     ✗  Claude Code       3 sessions: Anthropic, AWS
     ✗  Codex             1 session: OpenAI
        Treat these keys as exposed and rotate them.
        Checked the newest 400 of 3,003 sessions. Install ripgrep or add --all-sessions to check all.
```

- With nothing found and full coverage: "No keys in 3,003 agent sessions", with a check mark.
  With nothing found and partial coverage: the coverage line only, no check mark, never "no keys".
- Fix (section 3): "Keys in N agent sessions: treat them as exposed and rotate them."
- The score and the report payload do not change. A score that depended on how much was checked
  in time would differ between two runs on the same machine, and the payload needs a Worker and D1
  change first. Both are separate decisions.
- `--full` and a saved report list up to 20 session files. Paths stay on the machine.
- A session that is also a file Blindspot reads elsewhere (none today) is listed once, here.
- The summary row for section 3 mentions sessions when there are no plain-text key files.

## What it shares

Nothing new in this PR. Adding counts (sessions with keys, by agent and provider) to the report
needs the Worker and the D1 schema to accept them: a separate decision.

## Tests

- A fixture session per readable agent format, with a planted key and a made-up one, and good
  versions that must not match.
- ripgrep and perl return the same rows on the same fixture.
- A test hook stops the perl engine after a set number of files, to test the coverage line
  (no wall clock in tests). A partial run with no findings never shows a check mark.
- A key after `\n` in a JSON line is found.
- No perl or ripgrep process is left running after the script exits, including after HUP.
- Never prints a planted key; the result link and payload are unchanged.
- `gird-check.ps1` gets the same cases, and both scripts must carry the same agent path list.

## Not covered

- Codex may compress sessions older than 7 days into `.jsonl.zst`. The feature is off by
  default; such files are counted and named as not checked.
- Encrypted session stores (Windsurf, Antigravity).
- Keys that were pasted and later deleted from a session by the agent itself.
