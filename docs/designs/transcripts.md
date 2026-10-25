# Keys in agent sessions

Status: built in gird-check.sh and gird-check.ps1, on top of PR #12. `--fetch-rg` is not built. The
key types and session locations are in `data/keys.tsv` and `data/sessions.tsv`.

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
| Claude Code | `~/.claude/projects/*/*.jsonl`, `~/.claude/history.jsonl` (typed prompts), `~/.claude/paste-cache/` (long pastes) (`CLAUDE_CONFIG_DIR` moves all three) | JSONL, text | yes | docs (claude-directory, terminal-config) |
| Claude Desktop (Cowork) | `~/Library/Application Support/Claude/local-agent-mode-sessions/`; Windows `%APPDATA%\Claude\...` and, for the installer from Anthropic, `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\...` | JSON | yes | docs (cowork/hipaa-setup) |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl`, `~/.codex/archived_sessions/` (the same files after `/archive`), `~/.codex/history.jsonl` (`CODEX_HOME`) | JSONL | yes | source (codex-rs/rollout, message-history) |
| Gemini CLI | `~/.gemini/tmp/*/chats/` (`GEMINI_CLI_HOME`); macOS sandbox runs write under `~/.cache/.gemini/tmp` | JSONL, older JSON | yes | docs (session-management); source (storage.ts) |
| Qwen Code | `~/.qwen/projects/*/chats/*.jsonl`, older `~/.qwen/tmp/*/chats/` (`QWEN_HOME`; `QWEN_RUNTIME_DIR` takes priority and is not followed yet) | JSONL | yes | source (storage.ts) |
| OpenCode | `~/.local/share/opencode/opencode.db` and its `-wal`, older `storage/` JSON (`XDG_DATA_HOME`; `OPENCODE_DB` and channel builds' `opencode-<channel>.db` are not followed yet) | SQLite, JSON | yes | docs (troubleshooting); source (global-roots, database-path) |
| GitHub Copilot CLI | `~/.copilot/session-state/`, legacy `~/.copilot/history-session-state/` (`COPILOT_HOME`) | JSONL | yes | docs (cli-best-practices, changelog 0.0.342) |
| Roo Code | VS Code / Cursor `globalStorage/rooveterinaryinc.roo-cline/tasks/*/` | JSON | yes | source (utils/storage.ts) |
| Cline | `globalStorage/saoudrizwan.claude-dev/tasks/*/`; standalone `~/.cline/data/sessions/` and `~/.cline/data/tasks/` (`CLINE_DATA_DIR`) | JSON | yes | source (storage/disk.ts); docs (config, prompt-storage) |
| Continue | `~/.continue/sessions/` (`CONTINUE_GLOBAL_DIR`) | JSON | yes | source (util/paths.ts) |
| Goose | `~/.local/share/goose/sessions/` on macOS and Linux (the XDG strategy), `%APPDATA%\Block\goose\data\sessions\`; the last LLM requests and replies in `~/.local/state/goose/logs/` (Windows `...\data\logs\`) | SQLite, older JSONL | yes | docs (guides/logs); source (config/paths.rs) |
| Aider | `.aider.chat.history.md` in each project, found by the home scan, so only as deep as the scan goes | Markdown | yes | source |
| Amazon Q CLI | `amazon-q/data.sqlite3` in the platform data folder | SQLite | yes | source (util/paths.rs, database) |
| Kiro CLI | `~/.kiro/sessions/` (`KIRO_HOME`); `kiro-cli/data.sqlite3` in the platform data folder | JSONL, SQLite | yes | docs (cli/acp); the data folder's chat tables from issue reports only |
| Factory Droid | `~/.factory/sessions/`, `~/.factory/projects/` (the hooks docs' transcript path) | JSONL | yes | vendor repo (factory-plugins session-navigation skill); hooks docs |
| Cursor | `Cursor/User/globalStorage/state.vscdb`, `~/.cursor/projects/*/agent-transcripts/`, CLI `~/.cursor/chats/*/*/store.db` | SQLite, JSONL | yes | changelog and hooks docs for the transcripts; vendor forum staff for the two stores |
| Windsurf | `~/.windsurf/transcripts/*.jsonl` (written when the transcript hook is set up) | JSONL | yes | docs (cascade/hooks) |
| Windsurf | `~/.codeium/windsurf/cascade/*.pb` | AES-256-GCM with a fixed key, by third-party decryptors | no | third party; the vendor says nothing |
| Antigravity | `~/.gemini/antigravity{,-cli,-ide}/brain/*/.system_generated/logs/transcript.jsonl` | JSONL | yes | docs (hooks) |
| Antigravity | `~/.gemini/antigravity{,-cli,-ide}/conversations/*.pb` (newer `.db` files there are plain SQLite, not read yet) | AES-256-GCM with a fixed key, by third-party decryptors | no | third party; changelog for the `.db` format |

Conversation files that can't be read (Windsurf's and Antigravity's `.pb` stores) are named as not
checked, never shown as clean. SQLite files are searched as bytes: text columns are stored as plain text, and a
match in a freed page is still a key that was sent.

## Matching

- Blindspot's own key list, `ALL_KEYS`, the same one used for files.
- Transcripts are JSON, where a key often follows an escape such as `\n`. Three patterns need a
  non-alphanumeric character before the key (OpenAI's legacy `sk-` keys, `hf_`, `AQ.`), so the
  transcript check also accepts `\n`, `\t`, `\r` and `\"` as that boundary.
- A match that looks made up is dropped inside the matching stage: eight or more of the same
  character in a row, fewer than 12 distinct characters, or `EXAMPLE`, `xxxx`, `0123456789`,
  `abcdef` in it. Shell history is not filtered this way, because its matches come from commands
  the person typed; transcripts also hold tool output such as test fixtures.
- Amazon Q CLI caches temporary AWS credentials for its own telemetry in its `data.sqlite3` (the
  `telemetry-cognito-credentials` entry of its `state` table, an `ASIA` key id from Cognito), and
  Kiro CLI, the same CLI renamed and closed source, keeps the same entry by third-party accounts.
  An `ASIA` key id in either database (or its `-journal` or `-wal`) is not counted; long-term `AKIA`
  keys and every other provider there still are.
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
   partly checked. Under Git Bash a native `rg.exe` is handed Windows paths and prints them back
   (`C:/Users/...\...`); each hit is written the shell's way again with the script's own
   `cygpath` conversion, so it keeps its agent and its place.
2. Otherwise perl, which macOS, most Linux and Git Bash include, newest sessions first. One perl
   parent forks the workers, and each worker prints a done line for a file only after finishing
   it.
3. Neither: the agent sessions are named as not checked.

## Lifecycle and coverage

- The check starts in the background when the home scan starts, and is stopped when the rest of
  the check is done. That is the signal; there is no timer.
- `--all-sessions` waits for it to finish instead. (`--full` already means "every detail".)
- Coverage counts only files read to the end. A file in flight when stopped, unreadable, or
  compressed (`.zst`) counts as not checked, and any of them makes the check "partly checked" in
  the summary row. "No keys in N agent session files" counts only the files read, and is printed
  when nothing was stopped or unreadable; compressed files are then named on their own line. A file
  that can't be opened is named as one that could not be read (perl and .NET count them), never as
  a time cut that ripgrep or `--all-sessions` would fix. A folder that can't be opened is counted
  too (perl reports how many, ripgrep only that there were some) and makes the check "partly
  checked", never "no keys".
- Links: a location from the list that is a link is followed, as ripgrep follows a path it is
  given, but only to a regular file; links found inside a folder are not followed, as ripgrep does
  not follow them. A pipe, a socket or a device is never read: its read would wait for a writer or
  never end. (`gird-check.ps1` reads which a file is from PowerShell 7.2's `UnixMode` off Windows,
  never opens an empty file, and still reads a link to a file inside a folder.)
- ripgrep reports no per-file progress, so a stopped ripgrep run reads "partly checked", with no
  number.
- Stopping: the perl parent traps TERM, HUP and INT, kills its workers and exits. Each worker
  has its own pipe to the parent, which is the only writer, so result lines never interleave.
  Workers also exit when their parent or the script itself is gone, checked before each file and
  each 1 MB piece of one, so after a kill -9 of the script they stop within one piece. ripgrep is
  killed by its process ID, and under Git Bash with `taskkill`; after a kill -9 of the script it
  runs to its end. The pipe and the results file live in a `mktemp -d` folder (owner only, name
  not guessable) removed by the existing cleanup; if it can't be made, the report says the
  sessions were not checked. The filter the keys pass through is stopped with the engine,
  which also traps HUP from now on; a kill -9 leaves it behind, holding paths and provider names
  only.

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
- `--full` and a saved report list up to 20 places (the session folder, or the file when the
  location is one file), not session files: a Claude Code session's path spells out the project
  folder, username included, and reports get pasted into issues. Paths stay on the machine.
- A session that is also a file Blindspot reads elsewhere (none today) is listed once, here.
- The summary row for section 3 counts session files when there are no plain-text key files.

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
  default; such files are counted and named as not checked, and make the check partial.
- The encrypted `.pb` conversation stores of Windsurf and Antigravity (the plaintext transcript
  copies Antigravity keeps under `brain/` are read). Antigravity's newer `.db` conversations sit in
  the same folder as the `.pb` files and are not read yet.
- Cursor's per-workspace `workspaceStorage/*/state.vscdb` and `~/.cursor/acp-sessions`, Hugging
  Face organization tokens (`api_org_`), AWS `ABIA` and `ACCA` key ids, and the `QWEN_RUNTIME_DIR`
  and `OPENCODE_DB` overrides.
- Keys that were pasted and later deleted from a session by the agent itself.
