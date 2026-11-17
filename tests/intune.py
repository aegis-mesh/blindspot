# The mock tenants and the checks for tests/intune.sh.
#
#   python3 tests/intune.py state NAME STATE_FILE                writes a fresh mock tenant
#   python3 tests/intune.py check MODE WORK_DIR                    prints ok|name or bad|name|detail
import base64, csv, datetime, glob, json, os, re, sys

BASE = '/beta/deviceManagement/deviceHealthScripts'
MARK = 'b' * 32
NOW = datetime.datetime.now(datetime.timezone.utc)
def at(**kw): return (NOW + datetime.timedelta(**kw)).strftime('%Y-%m-%dT%H:%MZ')
T0 = at(hours=-2)

GROUPS = [
    {'id': 'g-eng', 'displayName': 'Engineering'},
    {'id': 'g-twin-1', 'displayName': 'Twins'},
    {'id': 'g-twin-2', 'displayName': 'twins'},
    {'id': 'g-obrien', 'displayName': "O'Brien team"},
    {'id': 'g-sales', 'displayName': 'Sales'},
]
OTHER = {'id': 'other-1', 'displayName': 'Printer fix', 'publisher': 'IT', 'description': 'not ours', 'isGlobalScript': False}
GLOBAL = {'id': 'global-1', 'displayName': 'Restart Office', 'publisher': 'Microsoft', 'description': '', 'isGlobalScript': True}
def ours(i, mark=MARK):
    return {'id': i, 'displayName': 'Blindspot fleet check', 'publisher': 'Blindspot', 'isGlobalScript': False,
            'description': 'Finds AI keys. Made by gird-intune.ps1, which finds it again by this mark (blindspot-intune-id: %s)' % mark,
            'createdDateTime': '2026-11-01T10:00:00Z',
            'assignments': [{'target': {'@odata.type': '#microsoft.graph.groupAssignmentTarget', 'groupId': 'g-eng'}}]}
LOOKALIKE = {'id': 'look-1', 'displayName': 'Blindspot fleet check', 'publisher': 'Someone', 'description': 'made by hand', 'isGlobalScript': False}
COPYCAT = dict(ours('copy-1'), publisher='Other')
GLOBAL_MARKED = dict(ours('global-2'), isGlobalScript=True)

HOSTILE_NAME = '<script>alert(1)</script>'
HOSTILE_OUT = '=HYPERLINK("http://x","y")<img src=x onerror=alert(1)>'
# name, detection state, output, expected status, the test's name
PCS = [
    ('PC-ACT', 'fail', 'v1 act %s | asha: act incidents tanstack; keys 2 anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear' % T0, 'act', 'a result to act on is listed to act on'),
    ('PC-CLEAR', 'success', 'v1 clear %s | asha: clear' % T0, 'clear', 'a clear result is listed as nothing found'),
    ('PC-REVIEW', 'fail', 'v1 review %s | bo: review run-without-asking claude-code; ssh-open 1' % T0, 'review', 'a result to review is listed to review'),
    ('PC-PARTIAL', 'fail', 'v1 not_checked %s | cy: not_checked ssh-open 1; partial' % T0, 'not_checked', 'a partly checked result is not checked'),
    ('PC-MORE', 'fail', 'v1 act %s | dee: act wiper; incidents tanstack +more' % T0, 'act', 'a result cut to fit, ending in +more, is read'),
    ('PC-FAILED', 'fail', 'v1 failed %s reason=host_32bit' % T0, 'failed', 'a failed result with its reason is failed'),
    ('PC-OTHER', 'success', 'v1 clear %s other_profiles=2 | eve: clear' % T0, 'clear', 'a clear result with other profiles is read'),
    ('PC-EMPTY', 'pending', '', 'no_result', 'a PC with no output is not checked'),
    ('PC-NULL', 'scriptError', None, 'failed', 'a PC whose check errored with no output is failed'),
    ('PC-NONE', 'fail', 'none', 'no_result', 'a PC that has not finished a run is not checked'),
    ('PC-STALE', 'success', 'v1 clear %s | fay: clear' % at(days=-5), 'stale', 'a clear result older than the stale age is stale'),
    ('PC-STALELINE', 'fail', 'stale: last run %s' % at(days=-5), 'stale', 'a stale line is stale'),
    ('PC-FUTURE', 'success', 'v1 clear %s | gus: clear' % at(days=1), 'not_checked', 'a result dated in the future is not checked'),
    ('PC-V2', 'success', 'v2 clear %s | hal: clear' % T0, 'not_checked', 'an unknown format version is not checked'),
    ('PC-TWOLINES', 'success', 'v1 clear %s | ivy: clear\nv1 clear %s | ivy: clear' % (T0, T0), 'not_checked', 'output of two lines is not checked'),
    ('PC-LIE', 'success', 'v1 clear %s | jo: act keys 1' % T0, 'not_checked', 'a clear header over an act account is not checked'),
    ('PC-CLEARFAIL', 'fail', 'v1 clear %s | kim: clear' % T0, 'not_checked', 'clear output from a check Intune says failed is not checked'),
    ('PC-UNKNOWN', 'fail', 'v1 act %s | lu: act exfil 1' % T0, 'not_checked', 'an unknown finding word is not checked'),
    ('PC-CLEARDETAIL', 'success', 'v1 clear %s | mo: clear keys 1' % T0, 'not_checked', 'a clear account with findings is not checked'),
    (HOSTILE_NAME, 'success', HOSTILE_OUT, 'not_checked', 'hostile output is not checked'),
    ('=cmd|calc', 'success', '+1', 'not_checked', 'output that is only a formula is not checked'),
    ('PC-CRLF', 'success', 'v1 clear %s | asha: clear\r\n' % T0, 'clear', 'a result ending in a line break is read'),
    ('PC-NOACC', 'fail', 'v1 not_checked %s | no accounts' % T0, 'not_checked', 'a PC with no accounts is not checked'),
]
def run_states():
    out = []
    for i, (name, det, output, _, _) in enumerate(PCS):
        dev = {'deviceName': name, 'userPrincipalName': '@SUM(1)' if name.startswith('=') else 'person%d@example.com' % i}
        out.append({'id': 'rs-%d' % i, 'detectionState': det, 'lastStateUpdateDateTime': NOW.isoformat(),
                    'preRemediationDetectionScriptOutput': output, 'managedDevice': dev})
    return out

def tenant(name):
    s = {'pageSize': 2, 'groups': GROUPS, 'scripts': [OTHER, GLOBAL]}
    if name == 'lookalike': s['scripts'] = [OTHER, LOOKALIKE, GLOBAL]
    if name == 'remove': s['scripts'] = [OTHER, LOOKALIKE, COPYCAT, ours('ours-1'), GLOBAL_MARKED, GLOBAL]
    if name == 'twomarked': s['scripts'] = [ours('ours-1'), OTHER, ours('ours-2', 'c' * 32)]
    if name in ('report', 'badnext'):
        s['scripts'] = [OTHER, ours('ours-1')]
        s['runStates'] = {'ours-1': run_states()}
    if name == 'badnext': s['nextHost'] = 'https://evil.example'
    return s

R = []
def check(name, cond, detail=''):
    R.append('%s|intune: %s|%s' % ('ok' if cond else 'bad', name, '' if cond else str(detail).replace('\n', ' ')[:300]))
def requests(w):
    with open(os.path.join(w, 'requests.log')) as f: return [json.loads(l) for l in f if l.strip()]
def scripts(w):
    with open(os.path.join(w, 'state.json')) as f: return json.load(f)['scripts']

def deploy_common(w, reqs, sid):
    assigns = [r for r in reqs if r['method'] == 'POST' and r['path'] == '%s/%s/assign' % (BASE, sid)]
    want = {'deviceHealthScriptAssignments': [{
        '@odata.type': '#microsoft.graph.deviceHealthScriptAssignment',
        'target': {'@odata.type': '#microsoft.graph.groupAssignmentTarget', 'groupId': 'g-obrien'},
        'runRemediationScript': False,
        'runSchedule': {'@odata.type': '#microsoft.graph.deviceHealthScriptDailySchedule', 'interval': 1, 'useUtc': False, 'time': '09:00:00'}}]}
    return assigns, want

def main():
    if sys.argv[1] == 'state':
        with open(sys.argv[3], 'w') as f: json.dump(tenant(sys.argv[2]), f)
        return
    mode, w = sys.argv[2], sys.argv[3]
    reqs = requests(w)
    writes = [r for r in reqs if r['method'] in ('POST', 'PATCH', 'DELETE')]
    fleet = open(os.path.join(w, 'fleet.ps1'), 'rb').read()
    stub = open(os.path.join(w, 'stub.log')).read().split('\n')
    if mode == 'deploy':
        check('-Deploy signs in with the scripts write scope and the basic group read scope only',
              stub[0] == 'connect DeviceManagementScripts.ReadWrite.All,Group.ReadBasic.All', stub[0])
        creates = [r for r in reqs if r['method'] == 'POST' and r['path'] == BASE]
        check('-Deploy creates one Remediation', len(creates) == 1, len(creates))
        b = creates[0]['body'] if creates else {}
        content = base64.b64decode(b.get('detectionScriptContent', '')) if b.get('detectionScriptContent') else b''
        check('the detection script is blindspot-fleet.ps1, byte for byte', content == fleet, '%d bytes sent, %d in the file' % (len(content), len(fleet)))
        check('it runs as the signed-in person, in 64-bit PowerShell, unsigned',
              b.get('runAsAccount') == 'user' and b.get('runAs32Bit') is False and b.get('enforceSignatureCheck') is False, b)
        check('it has no fix script', 'remediationScriptContent' not in b, list(b))
        check('it carries the mark the tool finds it by', b.get('publisher') == 'Blindspot'
              and re.search(r'\(blindspot-intune-id: [0-9a-f]{32}\)$', b.get('description', '')) is not None, b.get('description'))
        check('the create body is a deviceHealthScript', b.get('@odata.type') == '#microsoft.graph.deviceHealthScript'
              and b.get('displayName') == 'Blindspot fleet check', b.get('@odata.type'))
        mine = [s for s in scripts(w) if s.get('publisher') == 'Blindspot']
        sid = mine[0]['id'] if mine else ''
        assigns, want = deploy_common(w, reqs, sid)
        check('-Deploy assigns it to the one group, daily, with no fix script run', [a['body'] for a in assigns] == [want], [a['body'] for a in assigns])
        check('-Deploy writes nothing else', len(writes) == 2, [(r['method'], r['path']) for r in writes])
        check('-Deploy leaves the other Remediations as they were', [s for s in scripts(w) if s.get('id') != sid] == [OTHER, GLOBAL], scripts(w))
        with open(os.path.join(w, 'first.json'), 'w') as f: json.dump({'id': sid, 'description': mine[0]['description'] if mine else ''}, f)
    elif mode == 'redeploy':
        first = json.load(open(os.path.join(w, 'first.json')))
        mine = [s for s in scripts(w) if s.get('publisher') == 'Blindspot']
        check('a second -Deploy adds no Remediation', len(mine) == 1 and not [r for r in reqs if r['method'] == 'POST' and r['path'] == BASE], len(mine))
        patches = [r for r in reqs if r['method'] == 'PATCH']
        check('a second -Deploy updates the one it made', [r['path'] for r in patches] == ['%s/%s' % (BASE, first['id'])], [r['path'] for r in patches])
        b = patches[0]['body'] if patches else {}
        check('the update carries the newer script', base64.b64decode(b.get('detectionScriptContent', '')) == fleet)
        check('the update keeps the mark', b.get('description') == first['description'], b.get('description'))
        assigns, want = deploy_common(w, reqs, first['id'])
        check('a second -Deploy assigns it again to the one group', [a['body'] for a in assigns] == [want], [a['body'] for a in assigns])
        check('a second -Deploy writes nothing else', len(writes) == 2, [(r['method'], r['path']) for r in writes])
    elif mode == 'remove':
        dels = [r['path'] for r in writes]
        check('-Remove deletes only the Remediation with its mark', dels == ['%s/ours-1' % BASE], dels)
        left = [s['id'] for s in scripts(w)]
        check('-Remove leaves a same-named one, a copied mark from another publisher and a built-in script',
              left == ['other-1', 'look-1', 'copy-1', 'global-2', 'global-1'], left)
        check('-Remove signs in with the scripts write scope only', stub[0] == 'connect DeviceManagementScripts.ReadWrite.All', stub[0])
    elif mode == 'report':
        check('-Report signs in with read scopes only', stub[0] == 'connect DeviceManagementScripts.Read.All,DeviceManagementManagedDevices.Read.All', stub[0])
        pages = [r for r in reqs if r['method'] == 'GET' and r['path'].startswith('%s/ours-1/deviceRunStates' % BASE)]
        check('-Report follows every next-page link', len(pages) == (len(PCS) + 1) // 2, len(pages))
        csvs = glob.glob(os.path.join(w, 'out', '*.csv')); htmls = glob.glob(os.path.join(w, 'out', '*.html'))
        check('-Report saves one HTML file and one CSV file', len(csvs) == 1 and len(htmls) == 1, os.listdir(os.path.join(w, 'out')))
        if not csvs or not htmls:
            print('\n'.join(R)); return
        raw = open(csvs[0], encoding='utf-8-sig').read()
        rows = list(csv.DictReader(raw.splitlines(True)))
        check('the CSV has a row for every PC', len(rows) == len(PCS), len(rows))
        by = {}
        for r in rows:
            name = r['pc'][1:] if r['pc'].startswith("'") else r['pc']
            by[name] = r
        for name, _, _, status, label in PCS:
            got = by.get(name, {}).get('status')
            check('-Report: ' + label, got == status, '%s: wanted %s, got %s' % (name, status, got))
        clear = sorted(n for n, r in by.items() if r['status'] == 'clear')
        check('-Report calls only the fully read clear results clear', clear == ['PC-CLEAR', 'PC-CRLF', 'PC-OTHER'], clear)
        check('the other profiles a result names are shown', 'other accounts on this PC not checked' in by.get('PC-OTHER', {}).get('why', ''), by.get('PC-OTHER'))
        f = by.get('=cmd|calc', {})
        check('CSV cells that start like a formula are quoted', raw.count('"\'=cmd|calc"') == 1 and '"\'@SUM(1)"' in raw and '"\'+1"' in raw
              and '"\'=HYPERLINK(""http://x"",""y"")<img src=x onerror=alert(1)>"' in raw, f)
        check('no CSV cell starts with a formula character', all(not c or c[0] not in '=+-@\t\r' for r in csv.reader(raw.splitlines(True)) for c in r))
        html = open(htmls[0], encoding='utf-8').read()
        check('the HTML escapes what a PC sent', '<img' not in html and '<script>alert' not in html and 'onerror=alert(1)&gt;' in html
              and '&lt;script&gt;alert(1)&lt;/script&gt;' in html)
        check('the HTML loads nothing from outside', re.search(r'(src|href)\s*=\s*["\']?(https?:)?//', html) is None)
        check('the HTML counts the PCs with each kind of finding', '<td>Keys in plain text</td><td>1</td>' in html
              and '<td>SSH keys without a passphrase</td><td>3</td>' in html and '<td>Malware incident found</td><td>2</td>' in html)
        first = html.find('Deal with these first'); none = html.find('<h2>No result'); ok_at = html.find('<h2>Nothing found')
        check('the HTML lists the PCs to deal with first, then no result, then nothing found', 0 < first < none < ok_at)
        order = [html.find(x) for x in ('PC-ACT', 'PC-PARTIAL', 'PC-FAILED', 'PC-STALE<')]
        check('the PCs to deal with first are act, then not checked, failed, stale', all(x > 0 for x in order) and order == sorted(order), order)
    print('\n'.join(R))

main()
