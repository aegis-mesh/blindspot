#!/usr/bin/env bash
# Proves that a new incident of each data-only kind (and a new gh-token-monitor file, agent setting,
# agent version, extension, and extension whose malware runs on another OS) needs nothing but data lines: copies the repo
# to REPO, appends a made-up incident of each kind to the data files, runs tools/gen.sh there, and
# checks that only the generated blocks changed. Then plants matching files in HOME (a copy of a
# clean fixture home) and in HOME/tmp for the temp folder. The suites run the copy's scripts.
#
#   bash tests/made-up.sh REPO CLEAN_HOME HOME
set -eu
cd "$(dirname "$0")/.."
R=$1; C=$2; F=$3
mkdir -p "$R"; cp -R gird-check.sh gird-check.ps1 gird-fleet.sh tools data "$R/"
T=$(printf '\t')
cat >> "$R/data/incidents.tsv" <<EOF
madeplat${T}Made Platform${T}October 2026${T}a made-up platform leak for the tests${T}https://example.com/madeplat${T}leak
madeworm${T}Made worm${T}October 2026${T}a made-up worm for the tests${T}https://example.com/madeworm${T}act
madepy${T}Madepkg 9.9.9${T}October 2026${T}a made-up Python package for the tests${T}https://example.com/madepy/advisory${T}act
madenpm${T}Made npm worm${T}October 2026${T}a made-up npm worm for the tests${T}https://example.com/madenpm${T}act
madeext${T}Made extension${T}October 2026${T}a made-up extension for the tests${T}https://example.com/madeext${T}act
madeupd${T}Made npm slip${T}October 2026${T}a made-up npm version whose malware could not run${T}https://example.com/madeupd${T}update
EOF
printf 'made-npm-pkg\t1.2.3\tmadenpm\nmade-upd-pkg\t4.5.6\tmadeupd\n' >> "$R/data/bad-npm.tsv"
printf 'madeplat\tMadeplat\tmadeplat-cli\t~/.config/madeplat/;~/.madeplat.json\tCLI found\tMadeplat asked customers to rotate stored secrets.\tMadeplat CLI found: rotate secrets stored there\n' >> "$R/data/platforms.tsv"
cat >> "$R/data/indicators.tsv" <<EOF
madeworm${T}all${T}startup${T}no${T}~/.config/madeworm/boot.cjs${T}starts the Made worm at login
tanstack${T}all${T}wiper${T}no${T}~/.config/gh-token-monitor-made${T}-
madepy${T}all${T}site${T}no${T}madepy_boot.pth${T}-
madepy${T}all${T}temp${T}yes${T}.madepy_*${T}Stop any process started from these files, then delete them.
EOF
# A name only the Made worm uses, and one projects use too, which counts only as the file whose
# SHA-256 is listed (the contents planted below) or next to the first.
MADE_SHA=$(printf 'made loader\n' | { shasum -a 256 2>/dev/null || sha256sum; } | cut -c1-64)
printf '.vscode\tmadeplant.js\tmadeworm\ta file the Made worm plants\tyes\t-\n.claude\tmadeboot.mjs\tmadeworm\ta file the Made worm plants\tno\t%s\n' "$MADE_SHA" >> "$R/data/planted.tsv"
printf 'madepkg\t9.9.9\tmadepy\tall\n' >> "$R/data/bad-pypi.tsv"
printf 'Made Agent\tall\t~/.madeagent/config.json\tmadeMode\t"made": "yolo"\n' >> "$R/data/auto-approve.tsv"
printf 'Made Agent\tall\t~/.madeagent/profiles/*/config.json\tmadeMode profile\t"made": "profile"\n' >> "$R/data/auto-approve.tsv"
printf 'madetool\tMade Tool\tall\tnpm\tmade-tool\t<2.0.0\ta made-up hole for the tests\thttps://example.com/madetool\nmadetool\tMade Tool\tall\tnpm\tmade-tool\t<3.0.0\ta second made-up hole\thttps://example.com/madetool2\n' >> "$R/data/outdated.tsv"
printf 'made.ext\t1.0.0\tmadeext\tany\tall\nmade.winext\t2.0.0\tmadeext\tany\twin\n' >> "$R/data/bad-extensions.tsv"
bash "$R/tools/gen.sh" > /dev/null
# Outside the generated blocks, both scripts are unchanged.
for s in gird-check.sh gird-check.ps1; do
  if ! cmp -s <(awk '/^# >>> /{skip=1} !skip{print} /^# <<< /{skip=0}' "$s") <(awk '/^# >>> /{skip=1} !skip{print} /^# <<< /{skip=0}' "$R/$s"); then
    echo "made-up.sh: $s changed outside its generated blocks" >&2; exit 1
  fi
  if cmp -s "$s" "$R/$s"; then echo "made-up.sh: gen.sh did not change $s" >&2; exit 1; fi
done

rm -rf "$F"; cp -R "$C" "$F"
rm -rf "$F/.config/opencode" "$F/.local/share/opencode" "$F/.railway"
: > "$F/.madeplat.json"
mkdir -p "$F/.config/madeworm" "$F/.config/gh-token-monitor-made" "$F/code/venv/lib/site-packages/madepkg-9.9.9.dist-info" \
  "$F/tmp" "$F/AppData/Local/Temp" "$F/.cache/uv/wheels/madepkg-9.9.9-py3-none-any" "$F/code/made/.vscode" "$F/code/made/.claude"
: > "$F/.config/madeworm/boot.cjs"
: > "$F/code/venv/lib/site-packages/madepy_boot.pth"
: > "$F/tmp/.madepy_1"; : > "$F/AppData/Local/Temp/.madepy_1"
printf 'x\n' > "$F/code/made/.vscode/madeplant.js"
mkdir -p "$F/code/made/hash/.claude" "$F/code/made/plain/.claude"
printf 'made loader\n' > "$F/code/made/hash/.claude/madeboot.mjs"
printf 'console.log("my own setup")\n' > "$F/code/made/plain/.claude/madeboot.mjs"
printf '{"lockfileVersion":3,"packages":{"node_modules/made-npm-pkg":{"version":"1.2.3","resolved":"https://registry.npmjs.org/made-npm-pkg/-/made-npm-pkg-1.2.3.tgz"},"node_modules/made-upd-pkg":{"version":"4.5.6","resolved":"https://registry.npmjs.org/made-upd-pkg/-/made-upd-pkg-4.5.6.tgz"}}}\n' > "$F/code/made/package-lock.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node .vscode/madeplant.js"}]}]}}\n' > "$F/code/made/.claude/settings.json"
mkdir -p "$F/.madeagent" "$F/.npm-global/lib/node_modules/made-tool" "$F/.vscode/extensions/made.ext-1.0.0" "$F/.cursor/extensions/made.winext-2.0.0"
printf '{\n  "made": "yolo"\n}\n' > "$F/.madeagent/config.json"
mkdir -p "$F/.madeagent/profiles/p1"; printf '{"made": "profile"}\n' > "$F/.madeagent/profiles/p1/config.json"
printf '{"name":"made-tool","version":"1.5.0"}\n' > "$F/.npm-global/lib/node_modules/made-tool/package.json"
