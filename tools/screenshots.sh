#!/usr/bin/env bash
# Remakes docs/report.png (the summary) and docs/report-full.png (--full) from a run on the test
# fixture home against a local server that answers "better than 72% of 846", so the images show
# no real paths or keys. Needs python3 with Pillow, expect and Google Chrome.
#
#   bash tools/screenshots.sh
set -eu
cd "$(dirname "$0")/.."
ROOT=$PWD
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
WORK=$(mktemp -d); MOCK=""
trap '[ -n "$MOCK" ] && { kill "$MOCK"; wait "$MOCK"; } 2>/dev/null; rm -rf "$WORK"' EXIT

bash tests/make-fixture.sh "$WORK/home" "$WORK/keys.txt" >/dev/null
# A typical machine, not the worst case: keys, MCP tokens and keys in agent sessions, no malware.
( cd "$WORK/home" && rm -rf .config/gh-token-monitor code/py .cache/uv .npm .npm-global code/web code/berry \
    code/old-pnpm code/planted code/app/package-lock.json .local/share/opencode .railway .codeium )
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"make setup"}]}]}}\n' > "$WORK/home/code/cloned/.claude/settings.json"
printf '%s' '{"devices":846,"runs":1210,"devices_7d":120,"key_files":300,"clean":0.4}' > "$WORK/stats.json"
printf '%s' '{"p":72,"n":846,"r":142}' > "$WORK/reply.json"
python3 - "$WORK/port" "$WORK/stats.json" "$WORK/reply.json" <<'PY' &
import http.server, sys
portfile, stats, reply = sys.argv[1:4]
class H(http.server.BaseHTTPRequestHandler):
    def send(self, body):
        self.send_response(200); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        b = self.rfile.read(int(self.headers.get('content-length') or 0))
        if b'"kind":"report"' in b: self.send(open(reply, 'rb').read())
        else: self.send_response(204); self.end_headers()
    def do_GET(self): self.send(open(stats, 'rb').read())
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
open(portfile, 'w').write(str(srv.server_address[1])); srv.serve_forever()
PY
MOCK=$!
i=0; while [ ! -s "$WORK/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
API="http://127.0.0.1:$(cat "$WORK/port")/api/check"

run() { # log [args...]: a run in an 84-column terminal, quitting at the menu
  _log=$1; shift
  HOME="$WORK/home" GIRD_CHECK_API="$API" GIRD_CHECK_NO_OPEN=1 LOG="$_log" SCRIPT="$ROOT/gird-check.sh" expect -f - "$@" <<'EXP' >/dev/null
set stty_init "rows 200 cols 84"
set timeout 120
log_file -noappend $env(LOG)
spawn -noecho env TERM=xterm-256color bash $env(SCRIPT) --no-game {*}$argv
expect "q quit"
send "q"
expect eof
EXP
}
run "$WORK/short.log"
run "$WORK/full.log" --full

# Terminal output to HTML: SGR colours and bold, carriage returns and line clears.
python3 - "$WORK" <<'PY'
import html, re, sys
work = sys.argv[1]
BASIC = ['#1b1f2a', '#e06c75', '#7fd17f', '#e5c07b', '#61afef', '#c678dd', '#14e4d0', '#d7dae0']
def c256(n):
    if n < 8: return BASIC[n]
    if n < 16: return BASIC[n - 8]
    if n < 232:
        n -= 16; v = [0, 95, 135, 175, 215, 255]
        return '#%02x%02x%02x' % (v[n // 36], v[n // 6 % 6], v[n % 6])
    g = 8 + (n - 232) * 10; return '#%02x%02x%02x' % (g, g, g)
def render(raw):
    raw = re.sub(r'\x1b\[\?[0-9;]*[hl]|\x1b\][^\x07]*\x07|\x1b\[[0-9;]*[ABCDGJ]', '', raw)
    lines = []
    for line in raw.replace('\r\n', '\n').split('\n'):
        line = re.sub(r'.*\x1b\[2K', '', line)
        if '\r' in line: line = line.rsplit('\r', 1)[1]
        lines.append(line.replace('\x1b[K', ''))
    out = []; fg = None; bold = dim = False
    for line in lines:
        buf = ''
        for part in re.split(r'(\x1b\[[0-9;]*m)', line):
            m = re.fullmatch(r'\x1b\[([0-9;]*)m', part)
            if m:
                codes = [int(x) for x in (m.group(1) or '0').split(';') if x != '']
                i = 0
                while i < len(codes):
                    c = codes[i]
                    if c == 0: fg = None; bold = dim = False
                    elif c == 1: bold = True
                    elif c == 2: dim = True
                    elif c == 22: bold = dim = False
                    elif c == 39: fg = None
                    elif 30 <= c <= 37: fg = BASIC[c - 30]
                    elif 90 <= c <= 97: fg = BASIC[c - 90]
                    elif c == 38 and i + 2 < len(codes) and codes[i + 1] == 5: fg = c256(codes[i + 2]); i += 2
                    elif c == 38 and i + 4 < len(codes) and codes[i + 1] == 2: fg = '#%02x%02x%02x' % tuple(codes[i + 2:i + 5]); i += 4
                    i += 1
                continue
            if part:
                style = ''
                if fg: style += 'color:%s;' % fg
                if bold: style += 'font-weight:600;'
                if dim: style += 'opacity:.62;'
                buf += '<span style="%s">%s</span>' % (style, html.escape(part)) if style else html.escape(part)
        out.append(buf)
    out = [l for l in out if not re.search(r'Checking your agents, configs and keys|Comparing with other AI builders', l)]
    out = [re.sub(r'(q quit</span>|q quit)\s*q+\s*$', r'\1', l) for l in out]
    out = [l for i, l in enumerate(out) if not (i and not re.sub('<[^>]+>', '', l).strip() and not re.sub('<[^>]+>', '', out[i - 1]).strip())]
    while out and not re.sub('<[^>]+>', '', out[-1]).strip(): out.pop()
    return '\n'.join(out)
for name in ('short', 'full'):
    body = render(open('%s/%s.log' % (work, name), encoding='utf-8', errors='replace').read())
    open('%s/%s.html' % (work, name), 'w').write('''<!doctype html><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&display=block" rel="stylesheet">
<style>html,body{margin:0;background:#12161f}pre{margin:0;padding:28px 34px;color:#d7dae0;
font:15px/1.45 "IBM Plex Mono",Menlo,monospace;white-space:pre}</style><pre>%s</pre>''' % body)
PY

shot() { # html png width
  "$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --user-data-dir="$WORK/chrome" \
    --force-device-scale-factor=2 --window-size="$3,4000" --virtual-time-budget=4000 \
    --screenshot="$WORK/raw.png" "file://$1" >/dev/null 2>&1
  python3 - "$WORK/raw.png" "$2" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB'); bg = im.getpixel((2, 2)); w, h = im.size
px = im.load(); last = 0
for y in range(h - 1, -1, -1):
    if any(px[x, y] != bg for x in range(0, w, 3)): last = y; break
im.crop((0, 0, w, min(h, last + 56))).quantize(colors=256).save(sys.argv[2], optimize=True)
PY
}
shot "$WORK/short.html" docs/report.png 760
shot "$WORK/full.html" docs/report-full.png 1000
if grep -aqF -f "$WORK/keys.txt" "$WORK/short.log" "$WORK/full.log"; then echo "a planted key was printed: not keeping the images" >&2; git checkout -- docs/report.png docs/report-full.png; exit 1; fi
echo "updated docs/report.png and docs/report-full.png"
