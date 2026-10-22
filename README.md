<p align="center">
  <a href="docs/report-full.png"><img src="docs/report.png" alt="A Blindspot report in a terminal: the GIRD banner, how this Mac compares, and the coding agents, MCP servers and plain-text keys it found" width="760"></a>
</p>

# Blindspot

**See the AI keys and agents you can't.** A free, read-only check for your Mac, from [GIRD](https://gird.ai).

[![license](https://img.shields.io/badge/license-Apache--2.0-0D9488)](LICENSE)

Coding agents run with your access: your shell, your repos and the keys in your home folder. In October 2026, OpenCode, Railway and LiteLLM all leaked developer keys. Blindspot shows where your AI keys sit in plain text, which coding agents could read them, and whether that week's leaks touched you. It never prints a key.

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
2. **MCP servers.** The servers each agent is set up to start, and any token written straight into a config file.
3. **Keys in plain text.** AI and cloud keys in shell profiles, shell history, agent configs and `.env` files, grouped by provider and file. It also lists login files any agent can read, such as AWS credentials and SSH keys without a passphrase.
4. **Keys saved in Claude Code allow lists.** Click "always allow" on a command that has a key in it, and Claude Code saves the whole command in the project's settings file. Blindspot flags each one, and whether an npm publish from that folder would ship it.
5. **That week's leaks.** Files left by the LiteLLM 1.107.0 malware in every Python environment it finds, the bad package in your uv cache, and what to rotate if you use OpenCode Console or Railway.

At the end you get a short summary: how you compare with the other developers who ran it, one line per check, and the first thing to fix. Press 1 to 5 for the details of a check, s to save the full report, or ENTER for your Blindspot certificate, a card you can post. `--full` prints every detail instead, and so does running it into a file or a pipe.

## What it never does

- Print a key. It names the provider, never the value.
- Use sudo or ask for your password.
- Start an agent, an MCP server or Python.
- Leave a file behind, unless you ask it to save the report. It keeps two small temp files while it runs, for the progress line and the public totals, and deletes them when it exits.
- Send a path, a key, a username, a hostname or your raw hardware ID.

## What it shares

When it starts, it asks gird.ai for public totals, such as how many developers have run it. That request sends nothing else. When it finishes, it sends one report to gird.ai: the counts above, a few facts about your setup such as your terminal app and macOS version, and a hashed device ID so repeat runs can be counted. The reply says how your result compares. Every field is listed in [TELEMETRY.md](TELEMETRY.md). Run it with `--offline`, or set `DO_NOT_TRACK=1`, and it makes no requests at all.

## GIRD Runner

<img src="docs/game.png" alt="GIRD Runner: a teal runner jumping red leaked keys such as AKIA and .env in a bordered arena, with the scan timer below" width="760">

A small jump game that runs while the scan does, with the latest finding shown under it. Jump the leaked keys. When your results are ready, it asks whether to show them or let you keep playing for another minute.

## Requirements

macOS 13 or later, or Linux. It runs on the bash that ships with macOS (3.2) and on newer versions, and uses standard tools only: find, grep, awk, sed, od and stty. curl is used only for the public totals and to share counts. jq is used if it is installed.

## Limits

Blindspot shows what could reach your keys, not what your agents did with them. Finding nothing does not prove nothing leaked. It doesn't look at containers, servers or CI.

[Argus](https://gird.ai/argus/download/) is GIRD's free Mac app. It watches what your agents actually do, tells you when one opens a key file or tries to send a key off your Mac, and can stop terminal agents from reading your keys.

## Contributing

New agents, key formats and incident checks are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately, as described in [SECURITY.md](SECURITY.md).

## License

[Apache-2.0](LICENSE). Copyright 2026 GIRD AI Technologies Private Limited.
