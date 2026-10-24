<p align="center">
  <a href="docs/report-full.png"><img src="docs/report.png" alt="A Blindspot run in a terminal: better than 72% of 846 AI builders who ran it, AI builder #142, one of the first 1,000, one line per check, and the prompt to get your AI Exposure Check" width="760"></a>
</p>

# Blindspot

**See the AI keys and agents you can't.** A free, read-only check for your Mac, Linux or Windows computer, from [GIRD](https://gird.ai).

[![release](https://img.shields.io/github/v/release/aegis-mesh/blindspot?color=0D9488&label=release)](https://github.com/aegis-mesh/blindspot/releases/latest)
[![license](https://img.shields.io/badge/license-Apache--2.0-0D9488)](LICENSE)

Coding agents run with your access: your shell, your repos and the keys in your home folder. In October 2026, OpenCode, Railway, Zeabur and LiteLLM all leaked developer keys. Blindspot shows where your AI keys sit in plain text, which coding agents could read them, and whether that week's leaks touched you. It never prints a key.

## Run it

Download the script, read it, check its hash, then run it.

```sh
curl -fsSLO https://github.com/aegis-mesh/blindspot/releases/latest/download/gird-check.sh
less gird-check.sh
shasum -a 256 gird-check.sh   # compare with the release notes
bash gird-check.sh
```

You can also copy it from [gird.ai/blindspot](https://gird.ai/blindspot). It takes under a minute. While it scans, press space to play GIRD Runner and watch what it finds.

Please don't pipe it straight into a shell. Reading it first is the point.

| Option | What it does |
|---|---|
| `--full` | Prints every detail instead of the summary. |
| `--all` | Also scans Desktop, Documents and Downloads. macOS asks for permission. |
| `--offline` | Shares nothing. `DO_NOT_TRACK=1` does the same. |
| `--save` | Saves the full report as a text file without asking. |
| `--no-game` | Skips the game while it scans. |
| `NO_COLOR=1` | Plain text, no colors. |

## What it checks

1. **Coding agents.** Every agent installed, such as Claude Code, Codex, Cursor, Gemini CLI and OpenCode, and whether you used it in the last 30 days. An agent you never open can still be driven by a poisoned package. That is how the Nx attack stole keys from developer laptops.
2. **MCP servers.** The servers each agent is set up to start, and any token written straight into a config file. Configs inside plugin folders and caches, such as Codex's `.tmp/plugins`, are shown as a separate count. It also flags project settings that act as soon as an agent or editor opens the folder: Claude Code hooks, MCP servers turned on without asking, API traffic sent to another server, and VS Code or Cursor tasks that run on opening. A cloned repo brings these with it.
3. **Keys in plain text.** AI and cloud keys in shell profiles, shell history, agent configs and `.env` files, grouped by provider and file. It also lists login files any agent can read, such as AWS credentials and SSH keys without a passphrase.
4. **Keys saved in Claude Code allow lists.** Click "always allow" on a command that has a key in it, and Claude Code saves the whole command in the project's settings file. Blindspot flags each one, and whether an npm publish from that folder would ship it.
5. **Recent key leaks.** Files left by the LiteLLM 1.107.0 malware in every Python environment it finds, and the bad package in your uv cache. The npm package versions GitHub's advisory database lists as malware from the 2026 worms (SANDWORM_MODE, Axios, Bitwarden CLI, TanStack, Mistral AI, OpenSearch, Mastra, keyv and others), in your lockfiles (npm, yarn, pnpm and bun's text lockfile), global installs, npx and npm's download cache, and the files those worms leave behind. The list is not every package the worms reached. If it finds `gh-token-monitor`, it says to stop it before revoking any GitHub token, because it runs a destructive command when the stolen token stops working. And what to rotate if you use OpenCode Console, Railway or Zeabur.

At the end you get a short summary: how you compare with the other AI builders who ran it, one line per check, and the first thing to fix. Everyone who shares their result gets a number, and the first 1,000 are marked. Press 1 to 5 for the details of a check, s to save the full report, or ENTER for your AI Exposure Check: a page with your result, the steps to fix what it found, and an image to post on LinkedIn or X. `--full` prints every detail instead, and so does running it into a file or a pipe.

## What it never does

- Print a key. It names the provider, never the value.
- Use sudo or ask for your password.
- Start an agent, an MCP server or Python.
- Leave a file behind, unless you ask it to save the report. It keeps two small temp files while it runs, for the progress line and the public totals, and deletes them when it exits.
- Send a path, a key, a username, a hostname or your raw hardware ID.

## What it shares

When it starts, it asks gird.ai for public totals, such as how many AI builders have run it. That request sends nothing else. When it finishes, it sends one report to gird.ai: the counts above, which agents, key providers and well-known MCP servers it saw (from fixed lists, so no name you typed is sent), where keys sit by kind of file, a few facts about your setup such as your terminal app and macOS version, and a hashed device ID so repeat runs can be counted. The reply says how your result compares and your number. The result link carries a random run ID, and the result page sends it back only when you press a share button. Every field is listed in [TELEMETRY.md](TELEMETRY.md). Run it with `--offline`, or set `DO_NOT_TRACK=1`, and it makes no requests at all.

## GIRD Runner

<img src="docs/game.png" alt="GIRD Runner: a teal runner jumping red leaked keys such as AKIA and .env in a bordered arena, with the scan timer below" width="760">

A small jump game that runs while the scan does, with the latest finding shown under it. Jump the leaked keys. When your results are ready, it asks whether to show them or let you keep playing for another minute.

## Requirements

macOS 13 or later, Linux, or Windows. It runs on the bash that ships with macOS (3.2) and on newer versions, and uses standard tools only: find, grep, awk, sed, od and stty. curl is used only for the public totals and to share counts. jq is used if it is installed.

### Windows

Run `gird-check.sh` in Git Bash (it comes with Git for Windows), MSYS2 or Cygwin, the same way as above. It checks the Windows places: agents and MCP configs in your user folder and in `%APPDATA%` and `%LOCALAPPDATA%` (Claude Desktop, Cursor, VS Code, Windsurf, Goose), PowerShell's command history, Python installs and the uv cache under `AppData`, and the LiteLLM marker files in `%TEMP%`. Without jq, which Git Bash doesn't include, it finds MCP config files but can't count the servers in JSON ones.

In WSL it checks the Linux system you run it in, not the files on the Windows side, and says so at the end.

For plain PowerShell, with nothing to install, there is a PowerShell version, `gird-check.ps1`, with the same checks and the same report. It runs on Windows PowerShell 5.1 and PowerShell 7:

```powershell
irm https://gird.ai/blindspot/gird-check.ps1 -OutFile gird-check.ps1
Get-FileHash .\gird-check.ps1
powershell -ExecutionPolicy Bypass -File .\gird-check.ps1
```

`-ExecutionPolicy Bypass` applies to that one run. The switches are `-All`, `-Full`, `-Offline` and `-Save`, and `DO_NOT_TRACK=1` works too. It also reads PowerShell's command history. It has no game. A file that takes too long to check is listed as skipped, never counted as clean. On the same PC, Git Bash and PowerShell send the same device ID.

## Limits

Blindspot shows what could reach your keys, not what your agents did with them. Finding nothing does not prove nothing leaked. It doesn't look at containers, servers or CI.

[Argus](https://gird.ai/argus/download/) is GIRD's free Mac app. It watches what your agents actually do, tells you when one opens a key file or tries to send a key off your Mac, and can stop terminal agents from reading your keys.

## Contributing

Found a bug, or a key it missed? [Open an issue](https://github.com/aegis-mesh/blindspot/issues/new/choose). New agents, key formats and incident checks are welcome, and [CONTRIBUTING.md](CONTRIBUTING.md) has the steps for an issue or a pull request. Report security issues privately, as described in [SECURITY.md](SECURITY.md).

If Blindspot is useful to you, a star helps other developers find it.

## License

[Apache-2.0](LICENSE). Copyright 2026 GIRD AI Technologies Private Limited.
