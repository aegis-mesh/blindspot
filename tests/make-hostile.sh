#!/usr/bin/env bash
# Builds a home whose project folders have a TAB, terminal escape sequences and, for the rows the
# scripts join with |, a | in their names: one folder for each kind of row a project can put in the
# report. Keys are built from pieces at runtime and written to KEYS, one per line, so the suites can
# check that none is ever printed.
#
#   bash tests/make-hostile.sh HOME KEYS
set -eu
H=$1; K=$2
rm -rf "$H"; mkdir -p "$H"; : > "$K"
T=$(printf '\t'); E=$(printf '\033'); BEL=$(printf '\007')
INJ="${T}${E}[2J${E}]0;pwned${BEL}x"
PIPE="|${E}[2Jpipe"
rnd() { head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c "$1"; }
key() { printf '%s\n' "$1" >> "$K"; printf '%s' "$1"; }
# Project settings that act when the folder opens.
mkdir -p "$H/code/auto$INJ/.claude"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"make lint"}]}]}}\n' > "$H/code/auto$INJ/.claude/settings.json"
# A project's VS Code settings with the old auto-approve key.
mkdir -p "$H/p/yolo$INJ/.vscode"
printf '{"chat.tools.autoApprove": true}\n' > "$H/p/yolo$INJ/.vscode/settings.json"
# A bad npm version in a lockfile.
mkdir -p "$H/code/lock$INJ"
printf '{"lockfileVersion":3,"packages":{"node_modules/axios":{"version":"1.14.1","resolved":"https://registry.npmjs.org/axios/-/axios-1.14.1.tgz"}}}\n' > "$H/code/lock$INJ/package-lock.json"
# A file worms plant in a project.
mkdir -p "$H/code/plant$INJ/.vscode"; : > "$H/code/plant$INJ/.vscode/router_runtime.js"
# A project MCP config with a token, a key file and a Claude Code allow list, under a | as well.
mkdir -p "$H/code/mcp$PIPE$INJ" "$H/code/key$PIPE$INJ" "$H/code/allow$PIPE$INJ/.claude"
printf '{"mcpServers":{"gh":{"command":"npx","env":{"GITHUB_TOKEN":"%s"}}}}\n' "$(key "gh""p_$(rnd 36)")" > "$H/code/mcp$PIPE$INJ/.mcp.json"
printf 'OPENAI_API_KEY=%s\n' "$(key "sk-""proj-$(rnd 130)")" > "$H/code/key$PIPE$INJ/.env"
printf '{"permissions":{"allow":["Bash(curl -H \\"x-api-key: %s\\" https://api.anthropic.com)"]}}\n' "$(key "sk-""ant-api03-$(rnd 95)")" > "$H/code/allow$PIPE$INJ/.claude/settings.local.json"
# A key in an Aider history, read by the session check.
mkdir -p "$H/code/aider$INJ"
printf '> run with OPENAI_API_KEY=%s\n' "$(key "sk-""proj-$(rnd 130)")" > "$H/code/aider$INJ/.aider.chat.history.md"
# A link to this user's authorized_keys.
mkdir -p "$H/.ssh" "$H/code/link$INJ"; : > "$H/.ssh/authorized_keys"
ln -s ../../.ssh/authorized_keys "$H/code/link$INJ/notes.txt"
# Files the scan reads but can't open: a project's settings file that links to one, and a VS Code
# settings file, a tasks file and a planted setup.mjs, each mode 000. Each is named as not read, and
# nothing about them reaches stderr, where a failed read once printed the raw path.
mkdir -p "$H/sealed" "$H/code/unread$INJ/.claude" "$H/code/unread$INJ/.vscode"
printf '{}\n' > "$H/sealed/settings.json"; ln -s ../../../sealed/settings.json "$H/code/unread$INJ/.claude/settings.json"
for f in settings.json tasks.json setup.mjs; do printf '{}\n' > "$H/code/unread$INJ/.vscode/$f"; done
chmod 000 "$H/sealed/settings.json" "$H/code/unread$INJ/.vscode/settings.json" "$H/code/unread$INJ/.vscode/tasks.json" "$H/code/unread$INJ/.vscode/setup.mjs"
