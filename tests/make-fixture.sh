#!/usr/bin/env bash
# Builds a fake home folder for the tests: agents, MCP configs, planted test keys,
# a Claude Code allow list with a key, LiteLLM malware markers and SSH keys.
# Keys are random and assembled from pieces at runtime, so no key-shaped string
# is ever committed to this repository.
#
#   bash tests/make-fixture.sh HOME_DIR KEYS_FILE [full|clean]
set -e
F=$1; KEYS=$2; MODE=${3:-full}
rm -rf "$F"; mkdir -p "$F"
rnd()   { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }
upper() { LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c "$1"; }
s='sk'; d='-'
ANTH="${s}${d}ant${d}api03${d}$(rnd 95)"
OPENAI="${s}${d}proj${d}$(rnd 130)"
GH="g""hp_$(rnd 36)"
AWSK="AK""IA$(upper 16)"
GROQ="gs""k_$(rnd 52)"
printf '%s\n' "$ANTH" "$OPENAI" "$GH" "$AWSK" "$GROQ" > "$KEYS"

printf 'export ANTHROPIC_API_KEY=%s\nexport OPENAI_API_KEY=%s\n' "$ANTH" "$OPENAI" > "$F/.zshrc"
printf ": 1729000000:0;curl -H 'Authorization: token %s' https://api.github.com/user\n" "$GH" > "$F/.zsh_history"

mkdir -p "$F/code/app/.claude" "$F/code/lib/.claude"
printf 'AWS_ACCESS_KEY_ID=%s\nGROQ_API_KEY=%s\nOPENAI_API_KEY=your-key-here\n' "$AWSK" "$GROQ" > "$F/code/app/.env"
printf 'OPENAI_API_KEY=%s-your-key\n' "$s" > "$F/code/app/.env.example"
printf '{"permissions":{"allow":["Bash(npm test)","Bash(OPENAI_API_KEY=%s npm run eval)"]}}\n' "$OPENAI" > "$F/code/app/.claude/settings.local.json"
printf '{"name":"app","version":"1.0.0"}\n' > "$F/code/app/package.json"
printf 'node_modules\n' > "$F/code/app/.gitignore"
printf '{"permissions":{"allow":["Bash(TOKEN=your_token_here make)"]}}\n' > "$F/code/lib/.claude/settings.local.json"
printf '{"name":"lib","private":true}\n' > "$F/code/lib/package.json"

printf '{"mcpServers":{"github":{"command":"npx"},"fs":{"command":"node"}},"projects":{"/x":{"mcpServers":{"linear":{},"github":{}}}}}\n' > "$F/.claude.json"
mkdir -p "$F/.claude/projects/p1"; printf '{}\n' > "$F/.claude/projects/p1/s.jsonl"
mkdir -p "$F/.codex/sessions/2026/08"; printf '{}\n' > "$F/.codex/sessions/2026/08/old.jsonl"
touch -t 202608200000 "$F/.codex/sessions/2026/08/old.jsonl"
printf '[mcp_servers.fs]\ncommand = "x"\n[mcp_servers.fs.env]\nX = "1"\n[mcp_servers."web search"]\ncommand = "y"\n' > "$F/.codex/config.toml"
mkdir -p "$F/.cursor"
printf '{"mcpServers":{"github":{"command":"npx","env":{"GITHUB_PERSONAL_ACCESS_TOKEN":"%s"}}}}\n' "$GH" > "$F/.cursor/mcp.json"
# More MCP configs for the case-study counts: well-known servers written in
# different ways, and names of your own that must never leave the machine.
printf '{"mcpServers":{"acme-internal-db":{"command":"node"},"@modelcontextprotocol/server-postgres":{"command":"npx"},"MCP_DOCKER":{"command":"docker"}}}\n' > "$F/code/app/.mcp.json"
mkdir -p "$F/code/lib/.vscode"
printf '{"servers":{"Playwright":{"command":"npx"},"gh":{"type":"http"}}}\n' > "$F/code/lib/.vscode/mcp.json"
if [ "$(uname -s)" = Darwin ]; then AS="$F/Library/Application Support"; else AS="$F/.config"; fi
mkdir -p "$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings"
printf '{"mcpServers":{"github.com/upstash/context7-mcp":{"command":"npx"},"Figma Dev Mode MCP":{"url":"http://127.0.0.1:3845/sse"},"my notes":{"command":"node"}}}\n' \
  > "$AS/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
mkdir -p "$F/.config/goose"
printf 'extensions:\n  github:\n    enabled: true\n' > "$F/.config/goose/config.yaml"
mkdir -p "$F/.gemini"
mkdir -p "$F/.local/share/opencode"; printf '{}\n' > "$F/.local/share/opencode/auth.json"

mkdir -p "$F/work/org/repo/.venv/lib/python3.11/site-packages/litellm-1.106.2.dist-info"
printf 'home = /usr\n' > "$F/work/org/repo/.venv/pyvenv.cfg"
if [ "$MODE" = full ]; then
  mkdir -p "$F/code/py/.venv/lib/python3.12/site-packages/litellm-1.107.0.dist-info"
  printf 'home = /usr\n' > "$F/code/py/.venv/pyvenv.cfg"
  printf 'import cook\n' > "$F/code/py/.venv/lib/python3.12/site-packages/cook.pth"
  mkdir -p "$F/.cache/uv/wheels-v5/pypi/litellm/litellm-1.107.0-py3-none-any"
fi

mkdir -p "$F/.ssh"
h1='-----BEGIN OPENSSH '; h2='PRIVATE KEY-----'
printf '%s%s\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAA\n' "$h1" "$h2" > "$F/.ssh/id_ed25519"
printf '%s%s\nProc-Type: 4,ENCRYPTED\n' '-----BEGIN RSA ' "$h2" > "$F/.ssh/id_rsa_work"
printf 'ssh-ed25519 AAAA test\n' > "$F/.ssh/id_ed25519.pub"
