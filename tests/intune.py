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

def md(i, name, aad, os_='Windows', user=None):
    return {'id': 'md-%s' % i, 'deviceName': name, 'userPrincipalName': user or 'person-%s@example.com' % i,
            'azureADDeviceId': aad, 'operatingSystem': os_}
def member(aad, i):
    return {'@odata.type': '#microsoft.graph.device', 'id': 'obj-%s' % i, 'deviceId': aad}
SILENT_HOSTILE = '=cmd|' + HOSTILE_NAME
SILENT_MANAGED = [
    md('row', 'PC-HASROW', 'aad-row'),
    md('s1', 'PC-SILENT-1', 'aad-s1'),
    md('s2', 'PC-SILENT-2', 'aad-s2'),
    md('h', HOSTILE_NAME, 'aad-h'),
    md('f', SILENT_HOSTILE, 'aad-f'),
    md('mac', 'MAC-SILENT', 'aad-mac', 'macOS'),
    md('out', 'PC-NOTINGROUP', 'aad-out'),
]
SILENT_MEMBERS = [member('aad-row', 'row'), member('aad-s1', 's1'), member('aad-s2', 's2'), member('aad-h', 'h'),
                  member('aad-f', 'f'), member('aad-mac', 'mac'), {'@odata.type': '#microsoft.graph.group', 'id': 'nested'}]
SILENT_ROW = {'id': 'rs-row', 'detectionState': 'success', 'lastStateUpdateDateTime': NOW.isoformat(),
              'preRemediationDetectionScriptOutput': 'v1 clear %s | asha: clear' % T0,
              'managedDevice': {'id': 'md-row', 'deviceName': 'PC-HASROW', 'userPrincipalName': 'person-row@example.com', 'azureADDeviceId': 'aad-row'}}

def tenant(name):
    s = {'pageSize': 2, 'groups': GROUPS, 'scripts': [OTHER, GLOBAL]}
    if name == 'lookalike': s['scripts'] = [OTHER, LOOKALIKE, GLOBAL]
    if name == 'remove': s['scripts'] = [OTHER, LOOKALIKE, COPYCAT, ours('ours-1'), GLOBAL_MARKED, GLOBAL]
    if name == 'twomarked': s['scripts'] = [ours('ours-1'), OTHER, ours('ours-2', 'c' * 32)]
    if name in ('report', 'badnext'):
        s['scripts'] = [OTHER, ours('ours-1')]
        s['runStates'] = {'ours-1': run_states()}
    if name in ('silent', 'usergroup', 'othertarget'):
        s['scripts'] = [OTHER, ours('ours-1')]
        s['runStates'] = {'ours-1': [SILENT_ROW]}
        s['managed'] = SILENT_MANAGED
        s['members'] = {'g-eng': SILENT_MEMBERS}
    if name == 'usergroup':
        s['members'] = {'g-eng': [{'@odata.type': '#microsoft.graph.user', 'id': 'u1'}, {'@odata.type': '#microsoft.graph.user', 'id': 'u2'}]}
    if name == 'othertarget':
        s['scripts'][1]['assignments'] = [{'target': {'@odata.type': '#microsoft.graph.allLicensedUsersAssignmentTarget'}}]
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
        check('-Report signs in with read scopes only', stub[0] == 'connect DeviceManagementScripts.Read.All,DeviceManagementManagedDevices.Read.All,GroupMember.ReadBasic.All,Device.Read.All', stub[0])
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
    elif mode == 'silent':
        def load(t):
            csvs = glob.glob(os.path.join(w, 'out-' + t, '*.csv')); htmls = glob.glob(os.path.join(w, 'out-' + t, '*.html'))
            if len(csvs) != 1 or len(htmls) != 1: return None
            raw = open(csvs[0], encoding='utf-8-sig').read()
            rows = list(csv.DictReader(raw.splitlines(True)))
            return raw, rows, open(htmls[0], encoding='utf-8').read(), open(os.path.join(w, 'o-%s.txt' % t)).read()
        got = load('silent')
        check('-Report with a silent group saves its files', got is not None)
        if got:
            raw, rows, html, out = got
            names = [r['pc'][1:] if r['pc'].startswith("'") else r['pc'] for r in rows]
            by = dict(zip(names, rows))
            check('a PC in the group with no result row is listed as no result yet',
                  all(by.get(n, {}).get('status') == 'no_result' and 'no result yet' in by[n]['why'] for n in ('PC-SILENT-1', 'PC-SILENT-2')), by)
            check('a PC with a result row is listed once, as read', names.count('PC-HASROW') == 1 and by['PC-HASROW']['status'] == 'clear', names)
            check('a Mac and a PC outside the group are not listed', 'MAC-SILENT' not in names and 'PC-NOTINGROUP' not in names, names)
            check('every PC is listed once', len(names) == len(set(names)) == 5, names)
            check('the PCs with no result are counted as not checked, never clear',
                  'Not checked: no result' in html and re.search(r'<b>4</b>Not checked: no result', html) is not None
                  and '4 not checked' in out and '1 with nothing found' in out, out)
            check('the silent PCs are in the no result section, not under nothing found',
                  html.find('PC-SILENT-1') > html.find('<h2>No result') and html.find('PC-SILENT-1') < html.find('<h2>Nothing found'))
            check('a device list on several pages is read to the end', 'PC-SILENT-2' in names and len(names) == 5)
            check('a hostile PC name with no result is escaped in the HTML and guarded in the CSV',
                  '<script>alert' not in html and '&lt;script&gt;alert(1)&lt;/script&gt;' in html
                  and raw.count('"\'=cmd|<script>alert(1)</script>"') == 1 and '"\'<script>' not in raw and SILENT_HOSTILE in names and HOSTILE_NAME in names, raw[:400])
            check('no CSV cell of a silent PC starts with a formula character',
                  all(not c or c[0] not in '=+-@\t\r' for r in csv.reader(raw.splitlines(True)) for c in r))
            check('a group with every PC listed has no could-not-list note', 'Could not list' not in html and 'Note:' not in out)
        pages = [r for r in open(os.path.join(w, 'requests-silent.log')).read().splitlines() if '/managedDevices' in r]
        check('-Report follows every next-page link of the device list', len(pages) == (len(SILENT_MANAGED) + 1) // 2, len(pages))
        members = [r for r in open(os.path.join(w, 'requests-silent.log')).read().splitlines() if 'transitiveMembers' in r]
        check('-Report follows every next-page link of the group members', len(members) == (len(SILENT_MEMBERS) + 1) // 2, len(members))
        allreqs = [json.loads(l) for t in ('silent', 'usergroup', 'othertarget') for l in open(os.path.join(w, 'requests-%s.log' % t)) if l.strip()]
        check('-Report with a silent group changes nothing in Intune', not [r for r in allreqs if r['method'] != 'GET'])
        got = load('usergroup')
        check('-Report with a group of people saves its files', got is not None)
        if got:
            raw, rows, html, out = got
            names = [r['pc'] for r in rows]
            check('a group of people says plainly it could not list the PCs with no result',
                  'Could not list the PCs with no result for the people in group g-eng (2)' in html and 'does not mean they are clear' in html
                  and 'Could not list every PC' in html and out.count('Note: Could not list') == 1, out)
            check('a group of people lists no PC that was not read', names == ['PC-HASROW'], names)
            check('a group of people does not read the silent PCs as clear', '0 with nothing found' not in out and '1 with nothing found' in out and 'PC-SILENT' not in html, out)
        got = load('othertarget')
        check('-Report with an assignment it cannot read saves its files', got is not None)
        if got:
            raw, rows, html, out = got
            check('an assignment to every licensed user says it could not list the PCs with no result',
                  'allLicensedUsersAssignmentTarget' in html and 'which does not mean they are clear' in html, out)
    print('\n'.join(R))

main()
