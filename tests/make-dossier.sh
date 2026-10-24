#!/usr/bin/env bash
# Adds the checks from the incident dossier (docs/designs/dossier-checks.md) to a fixture home:
#   hit   agents set to run without asking, agent versions with a published fix, a link to
#         ~/.ssh/authorized_keys, GlassWorm extensions, the Injective SDK
#   calm  the hits that change no shared count: no MCP config, no malware
#   miss  near misses that must not be reported
# APPDATA is the folder VS Code's user settings live under (Application Support, ~/.config or
# AppData/Roaming).
#
#   bash tests/make-dossier.sh HOME APPDATA hit|calm|miss
set -e
F=$1; AD=$2; MODE=$3
L=aws/toolkits/language-servers/AmazonQ
mkdir -p "$F/.claude" "$F/.codex" "$AD/Code/User" "$F/p/yolo/.vscode" "$F/p/calm/.vscode" "$F/Applications/Cursor.app/Contents" \
  "$F/.npm-global/lib/node_modules/@anthropic-ai/claude-code" "$F/.npm-global/lib/node_modules/mcp-remote" "$F/.ssh" "$F/code/links"
[ -f "$F/.codex/config.toml" ] || : > "$F/.codex/config.toml"
toml=$(cat "$F/.codex/config.toml")
plist() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>CFBundleShortVersionString</key>\n\t<string>%s</string>\n</dict>\n</plist>\n' "$1" > "$F/Applications/Cursor.app/Contents/Info.plist"; }
pkg() { printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$2" "$3" > "$1/package.json"; }
: > "$F/.ssh/authorized_keys"
if [ "$MODE" = miss ]; then
  printf '{\n  "permissions": {\n    "defaultMode": "default"\n  },\n  "note": "defaultMode: bypassPermissions"\n}\n' > "$F/.claude/settings.json"
  # One of the two settings at the top, both of them only in a profile.
  printf 'approval_policy = "never"\n[profiles.yolo]\napproval_policy = "never"\nsandbox_mode = "danger-full-access"\n%s\n' "$toml" > "$F/.codex/config.toml"
  printf '{\n  // "chat.tools.autoApprove": true,\n  "chat.tools.autoApprove": false\n}\n' > "$AD/Code/User/settings.json"
  printf '{"chat.tools.autoApproveEdits": true, "chat.tools.global.autoApprove": "true"}\n' > "$F/p/calm/.vscode/settings.json"
  plist 3.0
  mkdir -p "$F/Library/Caches/$L/1.69.0" "$F/Library/Caches/$L/1.10.0" "$F/.cache/$L/1.69.0" "$F/.cache/$L/1.10.0"
  pkg "$F/.npm-global/lib/node_modules/@anthropic-ai/claude-code" @anthropic-ai/claude-code 1.0.24
  pkg "$F/.npm-global/lib/node_modules/mcp-remote" mcp-remote 0.1.16-beta.1
  mkdir -p "$F/.npm/_npx/a1/node_modules/@anthropic-ai/claude-code"; pkg "$F/.npm/_npx/a1/node_modules/@anthropic-ai/claude-code" @anthropic-ai/claude-code 0.2.115
  mkdir -p "$F/code/mr"
  printf '{"mcpServers":{"r":{"command":"npx","args":["-y","mcp-remote@0.1.16"]},"s":{"command":"npx","args":["my-mcp-remote@0.0.9"]}}}\n' > "$F/code/mr/.mcp.json"
  ln -s authorized_keys "$F/.ssh/keys-link"
  ln -s ../../.ssh/known_hosts "$F/code/links/hosts"
  # A repo's own .ssh/authorized_keys fixture and a link to it: not this user's file.
  mkdir -p "$F/code/repo/fixtures/.ssh"; : > "$F/code/repo/fixtures/.ssh/authorized_keys"
  ln -s fixtures/.ssh/authorized_keys "$F/code/repo/sample"
  # VS Code's own folder holds the Marketplace's clean 0.5.1; the near-miss versions and name sit in an
  # Open VSX editor's folder, where the bad build is looked for.
  mkdir -p "$F/.vscode/extensions/oorzc.ssh-tools-0.5.1" "$F/.cursor/extensions/oorzc.ssh-tools-0.5.2" "$F/.cursor/extensions/oorzc.ssh-tools-0.5.10" "$F/.cursor/extensions/oorzc.ssh-tools-pro-0.5.1"
  exit 0
fi
printf '{\n  "permissions": {\n    "defaultMode": "bypassPermissions"\n  }\n}\n' > "$F/.claude/settings.json"
printf 'approval_policy = "never"\nsandbox_mode = "danger-full-access"\n%s\n' "$toml" > "$F/.codex/config.toml"
printf '{\n  // "chat.tools.autoApprove": true,\n  "chat.tools.global.autoApprove": true\n}\n' > "$AD/Code/User/settings.json"
printf '{"chat.tools.autoApprove": true}\n' > "$F/p/yolo/.vscode/settings.json"
printf '{"chat.tools.autoApprove": false}\n' > "$F/p/calm/.vscode/settings.json"
plist 2.9.1
mkdir -p "$F/Library/Caches/$L/1.68.0" "$F/Library/Caches/$L/1.9.0" "$F/.cache/$L/1.68.0" "$F/.cache/$L/1.9.0"
pkg "$F/.npm-global/lib/node_modules/@anthropic-ai/claude-code" @anthropic-ai/claude-code 1.0.3
pkg "$F/.npm-global/lib/node_modules/mcp-remote" mcp-remote 0.0.5
ln -s ../../.ssh/authorized_keys "$F/code/links/notes.txt"
[ "$MODE" = calm ] && exit 0
# The oorzc build is looked for in the Open VSX editors' folders (VSCodium's here), not VS Code's.
mkdir -p "$F/code/mr" "$F/code/inj" "$F/.vscode-oss/extensions/oorzc.ssh-tools-0.5.1-darwin-arm64" "$F/.cursor/extensions/Sol-Studio.Solidity-Extension-2.0.0"
printf '{"mcpServers":{"r":{"command":"npx","args":["-y","mcp-remote@0.1.10","https://example.com/sse"]}}}\n' > "$F/code/mr/.mcp.json"
printf '{"lockfileVersion":3,"packages":{"node_modules/@injectivelabs/sdk-ts":{"version":"1.20.21","resolved":"https://registry.npmjs.org/@injectivelabs/sdk-ts/-/sdk-ts-1.20.21.tgz"}}}\n' > "$F/code/inj/package-lock.json"
