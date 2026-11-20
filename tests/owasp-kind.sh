#!/usr/bin/env bash
# Builds a home folder with one kind of finding and nothing else, for the OWASP tests in both suites
# (tests/run.sh, tests/run-ps.sh): a tag that one script derives wrongly for one kind shows on its own.
# The key comes from KEY_FILE, written at runtime by tests/make-fixture.sh; nothing key-shaped is here.
#
#   bash tests/owasp-kind.sh HOME_DIR KIND KEY_FILE
#   KIND: tools ak_links mcp_token history sessions wiper planted remove platforms remote autostart ssh_planted
set -e
F=$1; K=$2; KEY=$(sed -n 3p "$3")
rm -rf "$F"; mkdir -p "$F/AppData/Roaming" "$F/AppData/Local/Temp"
case "$K" in
  tools)      # Claude Code 2.1.100, inside a range data/outdated.tsv lists with a fixed version.
    mkdir -p "$F/.npm-global/lib/node_modules/@anthropic-ai/claude-code"
    printf '{"name":"@anthropic-ai/claude-code","version":"2.1.100"}\n' > "$F/.npm-global/lib/node_modules/@anthropic-ai/claude-code/package.json" ;;
  ak_links)   # A link to the person's own authorized_keys, outside .ssh.
    mkdir -p "$F/.ssh" "$F/code/app"; printf 'ssh-ed25519 AAAA test\n' > "$F/.ssh/authorized_keys"
    ln -s "$F/.ssh/authorized_keys" "$F/code/app/authorized_keys" ;;
  mcp_token)  # A token written straight into an MCP server's environment.
    mkdir -p "$F/.cursor"
    printf '{"mcpServers":{"github":{"command":"npx","env":{"GITHUB_PERSONAL_ACCESS_TOKEN":"%s"}}}}\n' "$KEY" > "$F/.cursor/mcp.json" ;;
  history)    # A key in shell history: zsh's, and PowerShell's for gird-check.ps1.
    printf ": 1729000000:0;curl -H 'Authorization: token %s' https://api.github.com/user\n" "$KEY" > "$F/.zsh_history"
    mkdir -p "$F/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine"
    printf '$env:GITHUB_TOKEN = "%s"\ngit push\n' "$KEY" > "$F/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt" ;;
  sessions)   # A key in a Claude Code session transcript.
    mkdir -p "$F/.claude/projects/p1"
    printf '{"type":"tool_result","content":"token %s"}\n' "$KEY" > "$F/.claude/projects/p1/s.jsonl" ;;
  wiper)      # gh-token-monitor's folder.
    mkdir -p "$F/.config/gh-token-monitor" ;;
  planted)    # A file only a worm uses that name for, planted in a project.
    mkdir -p "$F/code/planted/.vscode"; printf 'x\n' > "$F/code/planted/.vscode/router_runtime.js" ;;
  remove)     # An extension whose malware runs on Windows only: one to remove, off Windows.
    mkdir -p "$F/.vscode/extensions/microsoftvs.microsoftvs-1.0.0" ;;
  platforms)  # A hosted platform's files: OpenCode's.
    mkdir -p "$F/.local/share/opencode"; printf '{}\n' > "$F/.local/share/opencode/auth.json" ;;
  remote)     # A saved Codex rule that lets the agent run commands in other machines' containers.
    mkdir -p "$F/.codex/rules"; printf 'prefix_rule(pattern=["kubectl", "exec"])\n' > "$F/.codex/rules/default.rules" ;;
  autostart)  # A SessionStart hook in the person's own Claude Code settings that runs the AntV wave's copy.
    mkdir -p "$F/.claude"
    printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node ~/.claude/package/index.js"}]}]}}\n' > "$F/.claude/settings.json" ;;
  ssh_planted) # The SSH key the trojanized Claude Code extension adds (data/ssh-keys.tsv), a public key.
    mkdir -p "$F/.ssh"; printf 'ssh-ed25519 %s svc-telemetry\n' "$(awk -F '\t' '!/^#/ && NF > 2 { print $3; exit }' data/ssh-keys.tsv)" > "$F/.ssh/authorized_keys" ;;
  *) echo "owasp-kind.sh: unknown kind $K" >&2; exit 2 ;;
esac
