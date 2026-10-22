# What Blindspot shares

When the script starts, it asks `https://gird.ai/api/check/stats` for public **totals**, with a 2-second timeout. That request carries nothing beyond what any web request does.

When the script finishes, it sends one **report** to `https://gird.ai/api/check` and waits up to 3 seconds for the reply, which says how your result compares. If you use the menu at the end, it sends one more small **actions** event when you quit, in the background with a 5-second timeout. Everything goes over https. If a request fails, nothing happens and nothing is retried.

Turn all of it off, the totals request included, with `--offline` or `DO_NOT_TRACK=1`.

Everything is built in one place near the end of [`gird-check.sh`](gird-check.sh), so you can read exactly what goes. Every field is a number or comes from a fixed list or a strict pattern. The fixed lists of MCP apps, well-known MCP servers and kinds of file are in one block in the script, under "Fixed lists for the case-study counts". The server applies the same rules and drops anything else.

## Never sent

File paths, file names, keys, key fragments, MCP server names that aren't on the fixed list, usernames, emails, hostnames, IP addresses or your raw hardware ID.

## The report

| Field | Example | What it is |
|---|---|---|
| `v`, `kind` | `"1"`, `"report"` | Format version and event type |
| `run_id` | `"4b78c51d64d15aa0"` | Random for each run. Links a report to its actions event and to shares from its certificate |
| `device_id` | 64 hex characters | One-way SHA-256 of your Mac's hardware UUID (Linux: `/etc/machine-id`), salted with `gird-check-v1:`. Lets us count repeat runs. It can't be turned back into the hardware ID |
| `script` | `"1"` | Script version |
| `os`, `arch`, `model` | `"macOS 26.4"`, `"arm64"`, `"MacBookPro18,1"` | macOS version, processor type, Mac model identifier |
| `terminal`, `tmux` | `"iterm2"`, `0` | Terminal app, from a fixed list, and whether tmux is running |
| `shell`, `bash` | `"zsh"`, `3` | Your login shell, from a fixed list, and the bash major version running the script |
| `lang` | `"en_IN"` | Language and region setting |
| `via` | `"none"` | `claude-code` when the script runs inside Claude Code |
| `grade`, `score` | `"C"`, `64` | The result. The grade is for research counts only; the script shows how you compare instead |
| `agents`, `agents_idle` | `["claude-code","codex"]`, `1` | Agents installed, from a fixed list, and how many weren't used in 30 days |
| `agents_idle_ids` | `["codex"]` | Which of those agents weren't used in 30 days |
| `mcp_servers`, `mcp_configs`, `mcp_token_files` | `6`, `3`, `1` | MCP servers, config files with servers, and configs with a token written in |
| `mcp_clients`, `mcp_token_clients` | `{"claude-code":4,"codex":2}`, `["codex"]` | How many MCP servers each app has, and which apps keep a token written in their config. Apps from a fixed list |
| `mcp_known`, `mcp_other` | `["github","playwright"]`, `3` | Which well-known MCP servers you have, from a fixed list, and how many others. Any other server name is never sent |
| `key_files`, `key_providers`, `history_keys` | `4`, `["anthropic","aws"]`, `1` | Files with keys in plain text, which providers from a fixed list, and how many shell history files hold keys |
| `key_places` | `{"shell_rc":1,"shell_history":1,"env_file":2}` | Where those files sit, by kind of file: shell config, shell history, .env files, MCP configs, agent settings, project files or other. Each file counts once |
| `provider_files` | `{"anthropic":3,"aws":1}` | How many files hold each provider's keys |
| `env_files` | `12` | `.env` files scanned |
| `allow_list_files`, `allow_list_keys`, `allow_list_npm` | `2`, `1`, `1` | Claude Code settings files, how many hold a saved command with a key, and how many an npm publish would ship |
| `login_files` | `["aws","ssh"]` | Kinds of login files present, from a fixed list |
| `ssh_keys`, `ssh_no_passphrase` | `2`, `1` | SSH private keys, and how many have no passphrase |
| `python_envs`, `litellm_installed`, `litellm_found` | `6`, `2`, `0` | Python environments checked, LiteLLM installs, and whether 1.107.0 malware signs were found |
| `opencode`, `railway` | `1`, `0` | Whether the OpenCode and Railway tools are installed |
| `files_found`, `scan_seconds`, `all_folders` | `140`, `18`, `0` | Candidate files found, scan time, and whether `--all` was used |
| `game_played`, `game_best`, `results_wait_seconds` | `1`, `150`, `40` | Whether you played GIRD Runner, a rounded best score, and how long you kept playing after the results were ready |

## The actions event

| Field | What it is |
|---|---|
| `run_id`, `device_id` | Same as the report |
| `saved`, `card`, `argus` | Whether you saved the report, opened your certificate or opened the Argus download page |
| `menu_seconds` | Time spent in the menu |

## What comes back

| From | Example | What it is |
|---|---|---|
| The totals | `{"devices":1234,"devices_7d":456,"key_files":3412,"clean":0.31,...}` | Public totals, the same for everyone. The script shows one of them under the banner. Until 1,000 developers have run it, it says you're one of the first 1,000 instead of showing a number |
| The reply to the report | `{"p":72,"n":1234,"r":142}` | `p` is the share of developers whose latest run scored lower than yours, `n` how many developers that is. No `p` until at least 25 developers have run it. `r` is your place in line: 142 means 141 devices ran it before yours. Only the first 1,000 get one, and the script shows it with your result |

The script reads only digits from either reply, so a reply can't put anything else on your screen. The certificate link carries `p`, `n` and `r` after the `#`, which browsers never send to a server.

The certificate link also carries the run's random ID, the `run_id` from the report. When someone presses a share button, the certificate page sends that ID back with which button and what kind of result, nothing else. With `--offline` the link has no run ID.

## On our side

The totals and percentiles come from each device's latest report. The server stores each event with the time it arrived and the two-letter country Cloudflare derives from the connection. It doesn't store your IP address. Events are kept for 24 months, then deleted. We use them for aggregate statistics and case studies, and never publish figures about a group smaller than 20 devices. The privacy notice is at [gird.ai/privacy](https://gird.ai/privacy).

## Deleting your data

Work out your device ID on a Mac:

```sh
printf 'gird-check-v1:%s' "$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/ {print $4}')" | shasum -a 256
```

On Linux, replace the `ioreg` part with `cat /etc/machine-id`. Email the hash to [hello@gird.ai](mailto:hello@gird.ai) and we'll delete every event with it.
