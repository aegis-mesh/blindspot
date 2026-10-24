# Checks the case-study counts in one report against the fixed lists in the script that sent it
# and what the fixture holds. Prints ok|label or bad|label|detail per check. Used by both suites:
# the PowerShell fixture also has a GitHub key in PowerShell's history, one more history file.
#
#   python3 tests/payload.py SCRIPT home|places|empty|nojq REPORT [REPORT]
import json, re, sys
script, mode, files = sys.argv[1], sys.argv[2], sys.argv[3:]
src = open(script, encoding='utf-8', errors='replace').read()
PS = script.endswith('.ps1')
PSH = 1 if PS else 0
def fixed(name):
    if PS: m = re.search(r'^\$' + name + r" = '([^']*)'", src, re.M)
    else: m = re.search('^' + name + '="([^"]*)"', src, re.M)
    return m.group(1).split() if m else []
CLIENTS, KNOWN, PLACES, PROVIDERS = [fixed(n) for n in ('MCP_CLIENT_IDS', 'MCP_KNOWN_IDS', 'KEY_PLACE_IDS', 'PROVIDER_IDS')]
FIELDS = ['agents_idle_ids', 'mcp_clients', 'mcp_token_clients', 'mcp_known', 'mcp_other', 'key_places', 'provider_files']
def load(path):
    try:
        with open(path) as f:
            r = json.loads(f.readline())
        return r if isinstance(r, dict) else {}
    except (OSError, ValueError):
        return {}
def check(label, cond, detail=''):
    print('%s|%s|%s' % ('ok' if cond else 'bad', label, '' if cond else detail))
def count(v): return type(v) is int and 0 <= v <= 100000
def id_list(v, allowed): return isinstance(v, list) and all(isinstance(x, str) and x in allowed for x in v) and len(set(v)) == len(v)
def counts(v, allowed): return isinstance(v, dict) and all(k in allowed and count(n) for k, n in v.items())
def obj(r, k):
    v = r.get(k)
    return v if isinstance(v, dict) else {}
def show(r, *keys): return json.dumps({k: r.get(k) for k in keys})
def common(r, tag):
    shaped = (id_list(r.get('agents_idle_ids'), r.get('agents') or []) and len(r['agents_idle_ids']) == r.get('agents_idle')
              and counts(r.get('mcp_clients'), CLIENTS) and id_list(r.get('mcp_token_clients'), CLIENTS)
              and id_list(r.get('mcp_known'), KNOWN) and count(r.get('mcp_other'))
              and counts(r.get('key_places'), PLACES) and counts(r.get('provider_files'), PROVIDERS))
    check(tag + 'every case-study field holds fixed-list ids and whole numbers', shaped, show(r, *FIELDS))
    check(tag + 'mcp_clients adds up to mcp_servers', sum(obj(r, 'mcp_clients').values()) == r.get('mcp_servers'), show(r, 'mcp_clients', 'mcp_servers'))
    check(tag + 'key_places adds up to key_files', sum(obj(r, 'key_places').values()) == r.get('key_files'), show(r, 'key_places', 'key_files'))
    check(tag + 'key_places counts the history files history_keys counts', obj(r, 'key_places').get('shell_history', 0) == r.get('history_keys'), show(r, 'key_places', 'history_keys'))
    check(tag + 'provider_files has the providers in key_providers', sorted(obj(r, 'provider_files')) == sorted(r.get('key_providers') or []), show(r, 'provider_files', 'key_providers'))
r = load(files[0])
if mode == 'home':
    check('the fixed lists are in the script', [len(CLIENTS), len(PLACES), len(PROVIDERS)] == [12, 7, 12] and len(KNOWN) >= 49,
          'clients %d, known %d, places %d, providers %d' % tuple(map(len, (CLIENTS, KNOWN, PLACES, PROVIDERS))))
    check('the report has every case-study field', all(k in r for k in FIELDS), 'missing: ' + ' '.join(k for k in FIELDS if k not in r))
    common(r, '')
    check('mcp_clients counts the servers in each app', r.get('mcp_clients') == {'claude-code': 6, 'cursor': 1, 'codex': 2, 'vscode': 2, 'cline': 3}, show(r, 'mcp_clients'))
    check('mcp_token_clients names the app with a token in its config', r.get('mcp_token_clients') == ['cursor'], show(r, 'mcp_token_clients'))
    check('mcp_known lists each well-known server once', sorted(r.get('mcp_known') or []) == sorted(['github', 'filesystem', 'postgres', 'playwright', 'linear', 'figma', 'context7', 'docker']), show(r, 'mcp_known'))
    check('mcp_other counts the servers with names of their own', r.get('mcp_other') == 3, show(r, 'mcp_other'))
    # 11 fixture servers have well-known labels: github 3 times (once as gh), fs twice,
    # and linear, postgres, docker, playwright, context7 and figma once each.
    check('well-known and other servers add up to mcp_servers', 11 + (r.get('mcp_other') or 0) == r.get('mcp_servers'), show(r, 'mcp_other', 'mcp_servers'))
    check('key_places puts each key file in its place', r.get('key_places') == {'shell_rc': 1, 'shell_history': 1 + PSH, 'env_file': 1, 'mcp_config': 1}, show(r, 'key_places'))
    check("provider_files counts the files with each provider's keys", r.get('provider_files') == {'anthropic': 1, 'openai': 1, 'groq': 1, 'aws': 1, 'github': 2 + PSH}, show(r, 'provider_files'))
    idle = set(r.get('agents_idle_ids') or [])
    check('agents_idle_ids holds the idle agents, not the active ones', {'codex', 'gemini-cli', 'cursor', 'cline', 'goose'} <= idle and not idle & {'claude-code', 'opencode'}, show(r, 'agents_idle_ids'))
elif mode == 'places':
    common(r, 'more key files: ')
    check('more key files: key_places counts each kind of file', r.get('key_places') == {'shell_rc': 2, 'shell_history': 2 + PSH, 'env_file': 2, 'mcp_config': 1, 'agent_config': 1}, show(r, 'key_places'))
    check('more key files: provider_files counts each file once per provider', r.get('provider_files') == {'anthropic': 3, 'openai': 2, 'groq': 2, 'aws': 1, 'github': 2 + PSH}, show(r, 'provider_files'))
elif mode == 'empty':
    common(r, 'an empty home: ')
    check('an empty home: empty lists and objects, and no other servers', [r.get(k) for k in FIELDS[1:]] == [{}, [], [], 0, {}, {}] and isinstance(r.get('agents_idle_ids'), list), show(r, *FIELDS))
elif mode == 'nojq':
    b = load(files[1])
    keys = ['mcp_servers', 'mcp_configs', 'mcp_token_files', 'mcp_clients', 'mcp_token_clients', 'mcp_other', 'key_places', 'provider_files']
    diff = [k for k in keys if r.get(k) != b.get(k)]
    if sorted(r.get('mcp_known') or []) != sorted(b.get('mcp_known') or []): diff.append('mcp_known')
    check("without jq, macOS's JavaScript finds the same MCP servers as jq", bool(b) and not diff, 'differs: ' + ' '.join(diff) + ' ' + show(b, *diff))
