# The mock tenants, the stand-in for Microsoft Graph and the checks for tests/intune.sh.
#
#   python3 tests/intune.py state NAME STATE_FILE [FORMS_FILE]   writes a fresh mock tenant
#   python3 tests/intune.py serve STATE_FILE LOG_FILE PORT_FILE STUB_LOG
#   python3 tests/intune.py account KIND FLAVOUR                 prints one account run's output
#   python3 tests/intune.py check MODE WORK_DIR                    prints ok|name or bad|name|detail
#
# The stand-in answers only what Microsoft Graph's documentation says each request the tool makes
# gets back, for the query it was sent, and refuses anything else with 400, so a wrong request
# fails a test instead of passing against a lenient mock.
import base64, csv, datetime, glob, http.server, json, os, re, sys, urllib.parse, uuid

BASE = '/beta/deviceManagement/deviceHealthScripts'
MARK = 'b' * 32
NOW = datetime.datetime.now(datetime.timezone.utc)
def at(**kw): return (NOW + datetime.timedelta(**kw)).strftime('%Y-%m-%dT%H:%MZ')
T0 = at(hours=-2)
HERE = os.path.dirname(os.path.abspath(__file__))

GROUPS = [
    {'id': 'g-eng', 'displayName': 'Engineering', 'mail': None},
    {'id': 'g-twin-1', 'displayName': 'Twins', 'mail': None},
    {'id': 'g-twin-2', 'displayName': 'twins', 'mail': None},
    {'id': 'g-obrien', 'displayName': "O'Brien team", 'mail': None},
    {'id': 'g-sales', 'displayName': 'Sales', 'mail': None},
]
def script(i, name, publisher, description, glob_=False):
    return {'@odata.type': '#microsoft.graph.deviceHealthScript', 'id': i, 'displayName': name, 'publisher': publisher,
            'description': description, 'isGlobalScript': glob_, 'version': '1', 'runAsAccount': 'system',
            'runAs32Bit': False, 'enforceSignatureCheck': False, 'detectionScriptContent': '', 'roleScopeTagIds': ['0'],
            'createdDateTime': '2026-11-01T10:00:00Z', 'lastModifiedDateTime': '2026-11-01T10:00:00Z'}
OTHER = script('other-1', 'Printer fix', 'IT', 'not ours')
GLOBAL = script('global-1', 'Restart Office', 'Microsoft', '', True)
def ours(i, mark=MARK, name='Blindspot fleet check'):
    return script(i, name, 'Blindspot', 'Finds AI keys. Made by gird-intune.ps1, which finds it again by this mark (blindspot-intune-id: %s)' % mark)
def group_target(gid, kind='groupAssignmentTarget', **extra):
    t = {'@odata.type': 'microsoft.graph.' + kind, 'deviceAndAppManagementAssignmentFilterId': None,
         'deviceAndAppManagementAssignmentFilterType': 'none'}
    if gid is not None: t['groupId'] = gid
    t.update(extra)
    return {'@odata.type': '#microsoft.graph.deviceHealthScriptAssignment', 'id': 'a-%s-%s' % (kind, gid), 'target': t,
            'runRemediationScript': False,
            'runSchedule': {'@odata.type': 'microsoft.graph.deviceHealthScriptDailySchedule', 'interval': 1, 'useUtc': False, 'time': '09:00:00'}}
ENG = [group_target('g-eng')]
LOOKALIKE = script('look-1', 'Blindspot fleet check', 'Someone', 'made by hand')
COPYCAT = dict(ours('copy-1'), publisher='Other')
GLOBAL_MARKED = dict(ours('global-2'), isGlobalScript=True)
CTL_NAME = 'Blindspot fleet check\x1b[2J\x07\u202e'

HOSTILE_NAME = '<script>alert(1)</script>'
HOSTILE_OUT = '=HYPERLINK("http://x","y")<img src=x onerror=alert(1)>'
def _ps(rest, out='not_checked', profiles=0): return 'v1 %s %s other_profiles=%d%s' % (out, T0, profiles, rest)
def _long(total, tail=' +more'):
    head = _ps(' | anna: act lockfile %s; update %s; possible ' % (','.join(['tanstack'] * 63), ','.join(['tanstack'] * 63)), 'act')
    need = total - len(tail) - len(head)
    n = -(-(need + 1) // 65)
    size, extra = divmod(need - (n - 1), n)
    return head + ','.join('a' * (size + (1 if i < extra else 0)) for i in range(n)) + tail

# name, detection state, output, expected status, the test's name
PCS = [
    ('PC-ACT', 'fail', 'v1 act %s | asha: act incidents tanstack; keys 2 anthropic,aws; sessions 3; ssh-open 1 | itadmin: clear' % T0, 'act', 'a result to act on is listed to act on'),
    ('PC-CLEAR', 'success', 'v1 clear %s | asha: clear' % T0, 'clear', 'a clear result is listed as nothing found'),
    ('PC-REVIEW', 'fail', 'v1 review %s | bo: review run-without-asking claude-code; ssh-open 1' % T0, 'review', 'a result to review is listed to review'),
    ('PC-PARTIAL', 'fail', 'v1 not_checked %s | cy: not_checked ssh-open 1; partial' % T0, 'not_checked', 'a partly checked result is not checked'),
    ('PC-MORE', 'fail', 'v1 act %s | dee: act wiper; incidents tanstack +more' % T0, 'act', 'a result cut to fit, ending in +more, is read'),
    ('PC-FAILED', 'fail', 'v1 failed %s other_profiles=0 reason=host_32bit | asha: not_checked host_32bit' % T0, 'failed', 'a failed result with its reason is failed'),
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
    ('PC-NODETECT', None, 'v1 clear %s | kit: clear' % T0, 'not_checked', 'clear output with no detection state from Intune is not checked'),
    ('PC-UNKNOWN', 'fail', 'v1 act %s | lu: act exfil 1' % T0, 'not_checked', 'an unknown finding word is not checked'),
    ('PC-CLEARDETAIL', 'success', 'v1 clear %s | mo: clear keys 1' % T0, 'not_checked', 'a clear account with findings is not checked'),
    (HOSTILE_NAME, 'success', HOSTILE_OUT, 'not_checked', 'hostile output is not checked'),
    ('=cmd|calc', 'success', '+1', 'not_checked', 'output that is only a formula is not checked'),
    (' =SUM(2)', 'success', ' -1', 'not_checked', 'output that is a formula after spaces is not checked'),
    ('PC-CRLF', 'success', 'v1 clear %s | asha: clear\r\n' % T0, 'clear', 'a result ending in a line break is read'),
    ('PC-NOACC', 'fail', 'v1 not_checked %s | no accounts' % T0, 'not_checked', 'a PC with no accounts is not checked'),
    ('PC-CUT', 'fail', ('v1 act %s other_profiles=0 | anna: act keys 1; ' % T0 + 'possible ' + ','.join(['tanstack'] * 400))[:2048], 'not_checked',
     'a result of 2,048 characters not ending in +more, which Intune may have cut, is not checked'),
    ('PC-CUTSPACE', 'fail', ('v1 act %s other_profiles=0 | anna: act keys 1' % T0).ljust(2048), 'not_checked',
     'a result of 2,048 characters ending in spaces is not checked'),
    ('PC-FULL', 'fail', _long(2047, '') + '\n', 'act', 'a full 2,047 character result and its line end is read, not called cut'),
    ('PC-FULLCRLF', 'fail', _long(2047, '') + '\r\n', 'act', 'a full 2,047 character result and its CR LF line end is read, not called cut'),
    ('PC-CUT2048', 'fail', _long(2048, ''), 'not_checked', 'a valid looking result of 2,048 characters with no line end and no +more is called cut'),
    ('PC-CUT2047NL2', 'fail', _long(2047, '') + '\n\n', 'not_checked', 'a result of 2,047 characters and two line ends is called cut: only one is the writer\'s'),
    ('PC-NEWITEM', 'fail', _ps(' | anna: review ssh-open 1; exfil 3', 'review'), 'not_checked', 'a result with a finding word this tool does not know is not checked'),
    ('PC-NEWITEMACT', 'fail', 'v1 act %s | anna: act keys 1; exfil 3 | bo: clear' % T0, 'not_checked', 'a Mac style result with a finding word this tool does not know is not checked'),
    ('PC-V3', 'fail', _ps(' | anna: act keys 1', 'act').replace('v1 ', 'v3 ', 1), 'not_checked', 'a result with a newer version header is not checked'),
]

# Every form gird-fleet.ps1 and gird-fleet.sh can write, as each writes it: an outcome, every reason
# and every account and machine row, and the cut forms ending in +more. tests/intune.sh adds to these
# the values each writer prints when it is run here. (expected status, what it is, value)
ACT_PS = 'anna: act wiper; incidents tanstack,axios; lockfile axios; planted 2; keys 3 anthropic,aws; history 1; sessions 2; mcp-tokens 1; allow-lists 1; ssh-links 1; update mistral'
REVIEW_PS = 'anna: review run-without-asking claude-code,codex; ssh-open 1; update-tools amazonq; platforms opencode; on-open 1; to-read 1; remove glassworm; update mistral; possible mastra'
FORMS = []
for r in ('host_32bit', 'system_account', 'unpack', 'start', 'language_mode', 'no_output'):
    FORMS.append(('failed', 'gird-fleet.ps1 reason %s' % r, _ps(' reason=%s | anna: not_checked %s' % (r, r), 'failed')))
for r in ('deadline', 'time_limit', 'bad_output'):
    FORMS.append(('not_checked', 'gird-fleet.ps1 account %s' % r, _ps(' | anna: not_checked %s' % r)))
FORMS += [
    ('clear', 'gird-fleet.ps1 clear', _ps(' | anna: clear', 'clear', 3)),
    ('clear', 'gird-fleet.ps1 an account name it does not read', _ps(' | invalid-name: clear', 'clear')),
    ('act', 'gird-fleet.ps1 every act item', _ps(' | ' + ACT_PS, 'act')),
    ('review', 'gird-fleet.ps1 every review item', _ps(' | ' + REVIEW_PS, 'review')),
    ('not_checked', 'gird-fleet.ps1 partly checked', _ps(' | anna: not_checked ssh-open 1; partial')),
    ('not_checked', 'gird-fleet.ps1 partly checked, nothing else', _ps(' | anna: not_checked partial')),
    ('act', 'gird-fleet.ps1 act and partly checked', _ps(' | anna: act keys 1; partial', 'act')),
    ('act', 'gird-fleet.ps1 machine incident', _ps(' | anna: clear | machine: act incidents mastra', 'act')),
    ('review', 'gird-fleet.ps1 machine possible sign', _ps(' | anna: clear | machine: review; possible mastra', 'review')),
    ('act', 'gird-fleet.ps1 machine incident and possible sign', _ps(' | anna: review ssh-open 1 | machine: act incidents mastra; possible mastra', 'act')),
    ('failed', 'gird-fleet.ps1 not saved after a full run', _ps(' reason=save | anna: act keys 1', 'failed')),
    ('failed', 'gird-fleet.ps1 not saved after a run out of time', _ps(' reason=save | anna: not_checked time_limit', 'failed')),
    ('failed', 'gird-fleet.ps1 failed with a machine row', _ps(' reason=host_32bit | anna: not_checked host_32bit | machine: review; possible mastra', 'failed')),
    ('act', 'gird-fleet.ps1 cut, keeping the wiper and incidents', _ps(' | anna: act wiper; incidents tanstack,axios +more', 'act')),
    ('act', 'gird-fleet.ps1 cut to the outcome', _ps(' | anna: act +more', 'act')),
    ('not_checked', 'gird-fleet.ps1 cut, partly checked', _ps(' | anna: not_checked +more')),
    ('act', 'gird-fleet.ps1 cut at the most characters it writes', _long(2047)),
    ('act', 'gird-fleet.ps1 cut with a machine row', _ps(' | anna: act | machine: review; possible mastra +more', 'act')),
]
for r in ('name', 'no_login_shell', 'home_missing', 'home_link', 'home_owner', 'home_shared', 'home_system', 'home_name',
          'home_no_answer', 'sudo', 'bad_output', 'time_limit', 'deadline', 'copy_changed'):
    who = 'invalid-name' if r == 'name' else 'bo'
    FORMS.append(('not_checked', 'gird-fleet.sh account %s' % r, 'v1 not_checked %s | asha: clear | %s: not_checked %s' % (T0, who, r)))
FORMS += [
    ('act', 'gird-fleet.sh act and partly checked', 'v1 act %s | asha: act sessions 1; partial | bo: clear' % T0),
    ('failed', 'gird-fleet.sh copy changed', 'v1 failed %s | asha: act keys 1 | bo: not_checked copy_changed' % T0),
    ('not_checked', 'gird-fleet.sh no accounts', 'v1 not_checked %s | no accounts' % T0),
    ('not_checked', 'gird-fleet.sh machine and no accounts', 'v1 not_checked %s | machine: review; possible litellm; tmp-wiper | no accounts' % T0),
    ('not_checked', 'gird-fleet.sh machine partly checked', 'v1 not_checked %s | asha: clear | machine: not_checked' % T0),
    ('not_checked', 'gird-fleet.sh machine partly checked, a possible sign', 'v1 not_checked %s | asha: clear | machine: not_checked; possible litellm' % T0),
    ('act', 'gird-fleet.sh machine loader as root', 'v1 act %s | asha: clear | machine: act incidents litellm' % T0),
    ('review', 'gird-fleet.sh machine wiper logs', 'v1 review %s | asha: clear | machine: review; tmp-wiper' % T0),
    ('review', 'gird-fleet.sh account wiper logs', 'v1 review %s | asha: review tmp-wiper' % T0),
    ('review', 'gird-fleet.sh account markers in a shared folder', 'v1 review %s | asha: review run-without-asking claude-code; possible mastra; tmp-wiper; tmp-marks mastra' % T0),
    ('act', 'gird-fleet.sh cut, the Mac row first', 'v1 act %s | machine: act incidents litellm | asha: act | bo: review +more' % T0),
    ('act', 'gird-fleet.sh cut, the Mac row without its details', 'v1 act %s | asha: act | machine: act +more' % T0),
    ('clear', 'gird-fleet.sh two names it does not read', 'v1 clear %s | invalid-name: clear | invalid-name: clear' % T0),
    ('clear', 'gird-fleet.sh hashed names', 'v1 clear %s | 0123456789abcdef: clear | fedcba9876543210: clear' % T0),
    ('act', 'gird-fleet.sh cut', 'v1 act %s | asha: act wiper; incidents tanstack | bo: not_checked | cy: review +more' % T0),
    ('act', 'gird-fleet.sh cut, accounts left out', 'v1 act %s | asha: act +more' % T0),
    ('not_checked', 'gird-fleet.sh an account named machine, clear, is not read as clear', 'v1 clear %s | machine: clear' % T0),
    ('not_checked', 'gird-fleet.sh an account named machine, clear, beside another', 'v1 clear %s | asha: clear | machine: clear' % T0),
    ('not_checked', 'gird-fleet.sh an account named machine, with its own findings', 'v1 act %s | machine: act keys 1' % T0),
    ('not_checked', 'gird-fleet.sh an account named machine, not checked', 'v1 not_checked %s | machine: not_checked home_missing' % T0),
    ('not_checked', 'gird-fleet.sh an account named machine, clear, beside the Mac row', 'v1 review %s | machine: clear | machine: review; possible litellm' % T0),
    ('not_checked', 'gird-fleet.sh an account named machine, review, beside the Mac row', 'v1 review %s | machine: review ssh-open 1 | machine: review; possible litellm' % T0),
    ('no_result', 'gird-fleet.sh --inventory none', 'none'),
    ('not_checked', 'gird-fleet.sh --inventory unreadable', 'unreadable'),
    ('stale', 'gird-fleet.sh --inventory stale', 'stale: last run %s' % at(days=-5)),
    ('failed', 'gird-fleet.sh --inventory failed', 'failed: the run started %s did not finish or could not save its result' % T0),
]

# Values neither writer writes: each must read as not checked, never as a result.
NOT_WRITTEN = [
    ('a failed result with no account row', 'v1 failed %s other_profiles=0 reason=language_mode' % T0),
    ('a failed Windows result with no reason', _ps(' | anna: not_checked bad_output', 'failed')),
    ('a reason on a result that did not fail', _ps(' reason=start | anna: not_checked start')),
    ('a reason the writer does not write', _ps(' reason=sleepy | anna: not_checked sleepy', 'failed')),
    ('a reason without other_profiles', 'v1 failed %s reason=start | anna: not_checked start' % T0),
    ('a reason that is not the account row', _ps(' reason=start | anna: not_checked bad_output', 'failed')),
    ('a failed reason on a result that did not fail', _ps(' | anna: not_checked language_mode')),
    ('a Mac word on a Windows result', _ps(' | anna: not_checked home_missing')),
    ('a Windows word that is a failure reason on a Mac result', 'v1 not_checked %s | anna: not_checked host_32bit' % T0),
    ('tmp-marks on Windows', _ps(' | anna: review tmp-marks mastra', 'review')),
    ('tmp-wiper on Windows', _ps(' | anna: review tmp-wiper', 'review')),
    ('tmp-wiper on the Windows machine row', _ps(' | anna: clear | machine: review; tmp-wiper', 'review')),
    ('a Windows machine row not checked', _ps(' | anna: clear | machine: not_checked')),
    ('two account rows on Windows', _ps(' | anna: clear | bo: clear', 'clear')),
    ('no accounts on Windows', _ps(' | no accounts')),
    ('items out of order', _ps(' | anna: act keys 1; wiper', 'act')),
    ('an item twice', _ps(' | anna: act keys 1; keys 2', 'act')),
    ('an act account with no act item', _ps(' | anna: act ssh-open 1', 'act')),
    ('a review account with an act item', _ps(' | anna: review keys 1', 'review')),
    ('a review account partly checked', _ps(' | anna: review ssh-open 1; partial', 'review')),
    ('a not checked account with an act item', _ps(' | anna: not_checked keys 1; partial')),
    ('a not checked account with findings and no partial', _ps(' | anna: not_checked ssh-open 1')),
    ('an act account with nothing to say why', _ps(' | anna: act', 'act')),
    ('a machine row of act with no incident', _ps(' | anna: clear | machine: act', 'act')),
    ('a machine row of review with nothing', _ps(' | anna: clear | machine: review', 'review')),
    ('a machine row with an account item', _ps(' | anna: clear | machine: review keys 1', 'review')),
    ('a machine row with its parts out of order', _ps(' | anna: clear | machine: act; possible mastra incidents mastra', 'act')),
    ('two machine rows', _ps(' | anna: clear | machine: review; possible mastra | machine: review; possible mastra', 'review')),
    ('an account after the machine row', _ps(' | machine: review; possible mastra | anna: clear', 'review')),
    ('no accounts after an account', 'v1 not_checked %s | asha: clear | no accounts' % T0),
    ('a row after no accounts', 'v1 not_checked %s | no accounts | asha: clear' % T0),
    ('a list with a character it does not write', _ps(' | anna: review possible Mastra', 'review')),
    ('a Windows result of 2,048 characters ending in +more', _long(2048)),
    ('a Mac result longer than the Mac writer writes', 'v1 act %s | asha: act wiper; incidents %s' % (T0, ','.join(['tanstack'] * 40))),
]
FORMS += [('not_checked', 'not written: ' + d, v) for d, v in NOT_WRITTEN]

# A fleet for the MITRE references and the statements of what could get out: (name, detection state, output)
MITRE_PCS = [
    ('M-ALL', 'fail', _ps(' | anna: act incidents tanstack; run-without-asking claude-code; keys 2 anthropic,aws; history 1; sessions 1; mcp-tokens 1', 'act')),
    ('M-MAC', 'fail', 'v1 act %s | asha: act incidents litellm; keys 1 openai | bo: review run-without-asking codex' % T0),
    ('M-PARTIAL', 'fail', _ps(' | anna: not_checked ssh-open 1; partial')),
    ('M-MORE', 'fail', _ps(' | anna: act wiper; incidents tanstack +more', 'act')),
    ('M-CLEAR', 'success', _ps(' | anna: clear', 'clear', 2)),
    ('M-EMPTY', 'pending', ''),
    ('M-CUT', 'fail', (_ps(' | anna: act keys 1; ', 'act') + 'possible ' + ','.join(['tanstack'] * 400))[:2048]),
    ('M-STALE', 'success', _ps(' | anna: act run-without-asking codex; keys 1 aws; sessions 1; mcp-tokens 1', 'act').replace(T0, at(days=-5))),
    ('M-REVIEW', 'fail', _ps(' | anna: review run-without-asking cursor; update-tools amazonq; on-open 1', 'review')),
    ('M-WIPER', 'fail', 'v1 act %s | asha: act wiper' % T0),
    ('M-NOPROV', 'fail', _ps(' | anna: act run-without-asking claude-code; keys 1', 'act')),
]

# Exports an MDM gives for Macs, for gird-report.ps1. Jamf Pro stores the text between <result> and </result>;
# the tags are kept here too, as a script's raw output would have them. (name, value, expected status)
MAC = 'v1 act %s | asha: act wiper; keys 1 openai; sessions 1 | bo: review run-without-asking codex; tmp-marks mastra' % T0
JAMF = [
    ('MAC-ACT', '<result>%s</result>' % MAC, 'act'),
    ('MAC-BOTH', 'v1 act %s | asha: act run-without-asking claude-code; keys 2 anthropic,github; mcp-tokens 1' % T0, 'act'),
    ('MAC-CLEAR', 'v1 clear %s | asha: clear | itadmin: clear' % T0, 'clear'),
    ('MAC-NONE', '<result>none</result>', 'no_result'),
    ('MAC-STALE', 'stale: last run %s' % at(days=-5), 'stale'),
    ('MAC-EMPTY', '', 'no_result'),
    ('MAC-LONG', 'v1 act %s | asha: act incidents %s' % (T0, ','.join(['tanstack'] * 40)), 'not_checked'),
    ('MAC-NEWLINE', 'v1 clear %s | asha: clear\nv1 act %s | asha: act keys 1' % (T0, T0), 'not_checked'),
    ('MAC-SUMMARY', 'blindspot act accounts=2 act=1 review=0 not_checked=1 v=1.2.0 at=2026-10-25T09:12:00Z', 'not_checked'),
    ('MAC-DUP', 'v1 clear %s | asha: clear' % T0, 'clear'),
    ('mac-dup', 'v1 act %s | asha: act keys 1' % T0, 'act'),
    ('=cmd|calc', '=HYPERLINK("http://x","y")', 'not_checked'),
    (HOSTILE_NAME, 'v1 review %s | asha: review "quoted" <b>' % T0, 'not_checked'),
]
# The statements of what could get out, for every way a result can be whole or not, each a value a writer
# writes: (name, value, the agent with a key in the same account, a key in agent sessions, a token in an
# MCP config). "no" needs every account the result read to be read in full; a "yes" found stands whatever
# else is missing. Other profiles on a PC are not in the result and leave "no" as it is.
U = 'unknown'
PATHS = [
    ('P-MAC-CLEAR', 'v1 clear %s | asha: clear | bo: clear' % T0, 'no', 'no', 'no'),
    ('P-WIN-CLEAR', _ps(' | anna: clear', 'clear'), 'no', 'no', 'no'),
    ('P-MAC-ALL', 'v1 act %s | asha: act run-without-asking claude-code; keys 1 aws; sessions 1; mcp-tokens 1' % T0, 'yes', 'yes', 'yes'),
    ('P-SPLIT', 'v1 act %s | asha: act keys 1 openai | bo: review run-without-asking codex' % T0, 'no', 'no', 'no'),
    ('P-AGENT-ONLY', 'v1 review %s | asha: review run-without-asking codex' % T0, 'no', 'no', 'no'),
    ('P-MACHINE-NC', 'v1 not_checked %s | asha: clear | machine: not_checked' % T0, 'no', 'no', 'no'),
    ('P-OTHERS', _ps(' | eve: clear', 'clear', 3), 'no', 'no', 'no'),
    ('P-OTHERS-YES', _ps(' | anna: act run-without-asking claude-code; keys 1 aws; sessions 1', 'act', 2), 'yes', 'yes', 'no'),
    ('P-FAILED-SAVE', _ps(' reason=save | anna: act keys 1', 'failed'), U, U, U),
    ('P-FAILED-SAVE-YES', _ps(' reason=save | anna: act sessions 1', 'failed'), U, 'yes', U),
    ('P-FAILED-REASON', _ps(' reason=host_32bit | anna: not_checked host_32bit', 'failed'), U, U, U),
    ('P-FAILED-MAC', 'v1 failed %s | asha: clear | bo: not_checked copy_changed' % T0, U, U, U),
    ('P-FAILED-MAC-YES', 'v1 failed %s | asha: act mcp-tokens 1 | bo: not_checked copy_changed' % T0, U, U, 'yes'),
    ('P-PARTIAL', 'v1 not_checked %s | cy: not_checked ssh-open 1; partial | dee: clear' % T0, U, U, U),
    ('P-ACT-PARTIAL', 'v1 act %s | a: act keys 1; partial' % T0, U, U, U),
    ('P-ACT-PARTIAL-AK', _ps(' | anna: act run-without-asking claude-code; keys 1 aws; partial', 'act'), 'yes', U, U),
    ('P-ACT-PARTIAL-SE', 'v1 act %s | asha: act sessions 1; partial | bo: clear' % T0, U, 'yes', U),
    ('P-ACT-PARTIAL-MCP', _ps(' | anna: act mcp-tokens 1; partial', 'act', 1), U, U, 'yes'),
    ('P-ACT-OTHER-PARTIAL', 'v1 act %s | asha: act sessions 1 | bo: not_checked ssh-open 1; partial' % T0, U, 'yes', U),
    ('P-ACT-NC-WORD', 'v1 act %s | asha: act keys 1 | bo: not_checked home_missing' % T0, U, U, U),
    ('P-NC-WORD', 'v1 not_checked %s | asha: clear | bo: not_checked home_missing' % T0, U, U, U),
    ('P-NC-WIN', _ps(' | anna: not_checked deadline'), U, U, U),
    ('P-NOACC', 'v1 not_checked %s | no accounts' % T0, U, U, U),
    ('P-MORE', _ps(' | anna: act wiper; incidents tanstack +more', 'act'), U, U, U),
    ('P-MORE-YES', 'v1 act %s | asha: act sessions 1 | bo: review +more' % T0, U, 'yes', U),
    ('P-STALE', 'stale: last run %s' % at(days=-5), U, U, U),
    ('P-OLD', 'v1 act %s | asha: act run-without-asking claude-code; keys 1 aws; sessions 1; mcp-tokens 1' % at(days=-5), U, U, U),
    ('P-FAILEDLINE', 'failed: the run started %s did not finish or could not save its result' % T0, U, U, U),
    ('P-NONE', 'none', U, U, U),
    ('P-EMPTY', '', U, U, U),
    ('P-UNREADABLE', 'unreadable', U, U, U),
    ('P-FUTURE', 'v1 clear %s | asha: clear' % at(days=1), U, U, U),
    ('P-NOFIT', 'v1 clear %s | asha: clear keys 1' % T0, U, U, U),
    ('P-V2', 'v2 clear %s | asha: clear' % T0, U, U, U),
    ('P-NEWWORD', 'v1 act %s | asha: act keys 1; exfil 3' % T0, U, U, U),
    ('P-CUT', (_ps(' | anna: act sessions 1; ', 'act') + 'possible ' + ','.join(['tanstack'] * 400))[:2048], U, U, U),
    ('P-TWICE', 'v1 clear %s | asha: clear' % T0, 'no', 'no', 'no'),
    ('P-TWICE', 'v1 act %s | asha: act sessions 1' % T0, 'no', 'yes', 'no'),
]
# A fleet of Windows PCs where most have a second profile: (name, value)
WINFLEET = [('W-%02d' % i, _ps(' | anna: clear', 'clear', 1 if i <= 7 else 0)) for i in range(1, 9)] + [
    ('W-09', _ps(' | anna: act run-without-asking claude-code; keys 1 aws; sessions 1; mcp-tokens 1', 'act', 1)),
    ('W-10', 'none'),
    ('W-11', _ps(' | anna: act keys 1; partial', 'act')),
]
def csv_cell(v): return '"' + v.replace('"', '""') + '"'
CLR = 'v1 clear %s | asha: clear' % T0
ACT = 'v1 act %s | asha: act keys 1' % T0
OEM = 'To be filled by O.E.M.'
DUPS = {
    'oem.csv': 'Computer Name,Serial Number,Blindspot\nPC-OEM1,%s,%s\nPC-OEM2,%s,%s\n' % (OEM, ACT, OEM, CLR),
    'mdma.csv': 'Device name,Device id,Result\nPC-MDMA,5,%s\n' % CLR,
    'mdmb.csv': 'Computer Name,UDID,Blindspot\nMAC-MDMB,5,%s\n' % ACT,
    'dupc.csv': 'Computer Name,Blindspot\nMacBook-Pro,%s\niMac,%s\nMAC-ONLY-C,%s\n' % (CLR, CLR, CLR),
    'dupd.csv': 'Computer Name,Blindspot\nMacBook-Pro,%s\nimac,%s\n' % (ACT, CLR),
}
def write_files(d):
    os.makedirs(d, exist_ok=True)
    rows = [['Computer Name', 'Serial Number', 'Blindspot', 'Last Inventory Update']]
    for i, (n, v, _) in enumerate(JAMF): rows.append([n, ('S' * 100000) if n == 'MAC-ACT' else 'C02X%04d' % i, v, '2026-11-18 09:%02d:00' % i])
    with open(os.path.join(d, 'jamf.csv'), 'w', encoding='utf-8-sig', newline='') as f:
        f.write(''.join(','.join(csv_cell(c) for c in r) + '\r\n' for r in rows))
    with open(os.path.join(d, 'plain.csv'), 'w', newline='') as f:
        f.write('name,result\n' + ''.join('%s,%s\n' % (n, v) for n, v, st in JAMF if n in ('MAC-CLEAR', 'MAC-BOTH')) + 'MAC-PLAIN,none\n')
    with open(os.path.join(d, 'twocols.csv'), 'w', newline='') as f:
        f.write('Device name,Result,Previous result\nMAC-A,%s,%s\n' % (MAC, MAC))
    with open(os.path.join(d, 'noname.csv'), 'w', newline='') as f:
        f.write('Serial,Result\nC02X,%s\n' % MAC)
    with open(os.path.join(d, 'open.csv'), 'w', newline='') as f:
        f.write('Name,Result\nMAC-OPEN,"v1 clear %s | asha: clear\n' % T0)
    two = [('MAC-1', MAC), ('MAC-2', 'v1 clear %s | asha: clear' % T0)]
    with open(os.path.join(d, 'semicolon-utf16.csv'), 'w', encoding='utf-16', newline='') as f:
        f.write('Computer Name;Blindspot\r\n' + ''.join('%s;"%s"\r\n' % r for r in two))
    with open(os.path.join(d, 'tab-utf16-nobom.csv'), 'wb') as f:
        f.write(('Device name\tResult\n' + ''.join('%s\t%s\n' % r for r in two)).encode('utf-16-le'))
    with open(os.path.join(d, 'tab-utf16be-nobom.csv'), 'wb') as f:
        f.write(('Device name\tResult\n' + ''.join('%s\t%s\n' % r for r in two)).encode('utf-16-be'))
    with open(os.path.join(d, 'twocolsnone.csv'), 'w', newline='') as f:
        f.write('Device name,Result,Old result\nMAC-A,%s,none\nMAC-B,none,none\n' % MAC)
    with open(os.path.join(d, 'paths.csv'), 'w', newline='') as f:
        f.write('Computer Name,Blindspot\r\n' + ''.join('%s,%s\r\n' % (csv_cell(n), csv_cell(v)) for n, v, _, _, _ in PATHS))
    for n, rows in DUPS.items():
        with open(os.path.join(d, n), 'w', newline='') as f: f.write(rows)
    with open(os.path.join(d, 'winfleet.csv'), 'w', newline='') as f:
        f.write('Device name,Result\n' + ''.join('%s,%s\n' % (n, csv_cell(v)) for n, v in WINFLEET))
    with open(os.path.join(d, 'clearonly.csv'), 'w', newline='') as f:
        f.write('Computer Name,Blindspot\nMAC-OK,v1 clear %s | asha: clear\n' % T0)
    with open(os.path.join(d, 'locked.csv'), 'w', newline='') as f:
        f.write('Computer Name,Blindspot\nMAC-OK,v1 clear %s | asha: clear\n' % T0)
    with open(os.path.join(d, 'semicolon-utf8bom.csv'), 'w', encoding='utf-8-sig', newline='') as f:
        f.write('Hostname;Serial;Blindspot\n' + ''.join('%s;C02X,%d;"<result>%s</result>"\n' % (r[0], i, r[1]) for i, r in enumerate(two)))
    with open(os.path.join(d, 'noresult.csv'), 'w', newline='') as f:
        f.write('Computer Name,Serial Number,FileVault\nMAC-1,C02X1,On\nMAC-2,C02X2,none of it\n')
    open(os.path.join(d, 'empty.csv'), 'w').close()
    with open(os.path.join(d, 'headeronly.csv'), 'w', newline='') as f: f.write('Computer Name,Blindspot\n')
    with open(os.path.join(d, 'workbook.csv'), 'wb') as f: f.write(b'PK\x03\x04' + bytes(range(256)) * 4)
    with open(os.path.join(d, 'binary.csv'), 'wb') as f: f.write(b'Computer Name,Blindspot\n\x00\x00\x00MAC-1,\x01\x02\x00\n')
    with open(os.path.join(d, 'big.csv'), 'w', newline='') as f:
        f.write('Computer Name,Blindspot\n' + ''.join('MAC-%05d,%s\n' % (i, MAC if i % 3 else 'none') for i in range(20000)))

def run_state(i, name, det, output, dev=None):
    s = {'@odata.type': '#microsoft.graph.deviceHealthScriptDeviceState', 'id': 'rs-%d' % i, 'lastStateUpdateDateTime': NOW.isoformat(),
         'expectedStateUpdateDateTime': None, 'lastSyncDateTime': NOW.isoformat(), 'preRemediationDetectionScriptOutput': output,
         'preRemediationDetectionScriptError': None, 'remediationScriptError': None, 'postRemediationDetectionScriptOutput': None,
         'postRemediationDetectionScriptError': None, 'remediationState': 'skipped', 'assignmentFilterIds': [],
         'managedDevice': dev if dev is not None else {'id': 'md-rs-%d' % i, 'deviceName': name, 'userPrincipalName': 'person%d@example.com' % i,
                                                         'azureADDeviceId': 'aad-rs-%d' % i, 'operatingSystem': 'Windows'}}
    if det is not None: s['detectionState'] = det
    return s
def run_states():
    out = []
    for i, (name, det, output, _, _) in enumerate(PCS):
        s = run_state(i, name, det, output)
        if name.startswith('='): s['managedDevice']['userPrincipalName'] = '@SUM(1)'
        if name.startswith(' '): s['managedDevice']['userPrincipalName'] = '  -2+3'
        out.append(s)
    return out
def form_rows(path):
    rows = list(FORMS)
    if path and os.path.exists(path):
        for l in open(path).read().splitlines():
            if l.strip(): st, label, value = l.split('\t', 2); rows.append((st, label, value))
    return rows

def md(i, name, aad, os_='Windows', user=None):
    return {'@odata.type': '#microsoft.graph.managedDevice', 'id': 'md-%s' % i, 'deviceName': name, 'userPrincipalName': user or 'person-%s@example.com' % i,
            'azureADDeviceId': aad, 'operatingSystem': os_, 'serialNumber': 'SN-%s' % i, 'model': 'Laptop'}
def member(aad, i):
    return {'@odata.type': '#microsoft.graph.device', 'id': 'obj-%s' % i, 'deviceId': aad, 'displayName': 'dev-%s' % i}
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
                  member('aad-f', 'f'), member('aad-mac', 'mac'), {'@odata.type': '#microsoft.graph.group', 'id': 'nested', 'displayName': 'nested'}]
SILENT_ROW = run_state(0, 'PC-HASROW', 'success', 'v1 clear %s | asha: clear' % T0,
                       {'@odata.type': '#microsoft.graph.managedDevice', 'id': 'md-row', 'deviceName': 'PC-HASROW', 'userPrincipalName': 'person-row@example.com',
                        'azureADDeviceId': 'aad-row', 'operatingSystem': 'Windows'})
SILENT_ROW['id'] = 'rs-row'
SILENT_TENANTS = ('silent', 'usergroup', 'othertarget', 'exclusion', 'alldevices', 'filter', 'membererror', 'exclerror',
                  'nodeviceid', 'exclhidden', 'unassigned')

def tenant(name, forms=None):
    s = {'pageSize': 2, 'groups': GROUPS, 'scripts': [OTHER, GLOBAL], 'assignments': {}, 'runStates': {}}
    if name == 'lookalike': s['scripts'] = [OTHER, LOOKALIKE, GLOBAL]
    if name == 'remove': s['scripts'] = [OTHER, LOOKALIKE, COPYCAT, ours('ours-1'), GLOBAL_MARKED, GLOBAL]
    if name == 'ctl': s['scripts'] = [OTHER, ours('ours-1', name=CTL_NAME)]
    if name == 'twomarked': s['scripts'] = [ours('ours-1'), OTHER, ours('ours-2', 'c' * 32)]
    if name in ('remove', 'twomarked', 'ctl'): s['assignments'] = {'ours-1': ENG}
    if name in ('report', 'badnext', 'novalue', 'forms'):
        s['scripts'] = [OTHER, ours('ours-1')]
        s['assignments'] = {'ours-1': [group_target('g-sales')]}
        s['members'] = {'g-sales': []}
        s['runStates'] = {'ours-1': run_states()}
    if name == 'forms':
        s['pageSize'] = 50
        s['runStates'] = {'ours-1': [run_state(i, 'FORM-%03d' % i, 'success' if st == 'clear' or ' clear ' in v[:12] else 'fail', v) for i, (st, _, v) in enumerate(form_rows(forms))]}
    if name == 'novalue': s['noValue'] = BASE + '/ours-1/deviceRunStates'
    if name == 'mitre':
        s['scripts'] = [OTHER, ours('ours-1')]
        s['assignments'] = {'ours-1': [group_target('g-sales')]}
        s['members'] = {'g-sales': []}
        s['runStates'] = {'ours-1': [run_state(i, n, d, o) for i, (n, d, o) in enumerate(MITRE_PCS)]}
    if name in SILENT_TENANTS:
        s['scripts'] = [OTHER, ours('ours-1')]
        s['assignments'] = {'ours-1': list(ENG)}
        s['runStates'] = {'ours-1': [SILENT_ROW]}
        s['managed'] = SILENT_MANAGED
        s['members'] = {'g-eng': SILENT_MEMBERS, 'g-excl': [member('aad-s2', 'x2')]}
    if name == 'usergroup':
        s['members']['g-eng'] = [{'@odata.type': '#microsoft.graph.user', 'id': 'u1'}, {'@odata.type': '#microsoft.graph.user', 'id': 'u2'}]
    if name == 'othertarget':
        s['assignments']['ours-1'] = [dict(group_target(None, 'allLicensedUsersAssignmentTarget'))]
    if name == 'exclusion':
        s['assignments']['ours-1'] = ENG + [group_target('g-excl', 'exclusionGroupAssignmentTarget')]
    if name == 'alldevices':
        s['assignments']['ours-1'] = [group_target(None, 'allDevicesAssignmentTarget')]
    if name == 'filter':
        s['assignments']['ours-1'] = [group_target('g-eng', deviceAndAppManagementAssignmentFilterId='f-1', deviceAndAppManagementAssignmentFilterType='include'),
                                      group_target(None, 'oddTarget\x1b[2J')]
    if name == 'membererror': s['memberErrors'] = ['g-eng']
    if name == 'exclerror':
        s['assignments']['ours-1'] = ENG + [group_target('g-excl', 'exclusionGroupAssignmentTarget')]
        s['memberErrors'] = ['g-excl']
    if name == 'exclhidden':
        s['assignments']['ours-1'] = ENG + [group_target('g-excl', 'exclusionGroupAssignmentTarget')]
        s['members']['g-excl'] = [{'@odata.type': '#microsoft.graph.device', 'id': 'obj-x2', 'deviceId': None, 'displayName': None}]
    if name == 'unassigned':
        s['assignments']['ours-1'] = []
        s['runStates']['ours-1'] = []
    if name == 'badnext': s['nextHost'] = 'https://evil.example'
    return s

# --- The stand-in for Microsoft Graph -------------------------------------------------------

DHS_PROPS = {'@odata.type', 'id', 'publisher', 'version', 'displayName', 'description', 'detectionScriptContent',
             'remediationScriptContent', 'createdDateTime', 'lastModifiedDateTime', 'runAsAccount', 'enforceSignatureCheck',
             'runAs32Bit', 'roleScopeTagIds', 'isGlobalScript', 'highestAvailableVersion', 'deviceHealthScriptType',
             'detectionScriptParameters', 'remediationScriptParameters'}
DHS_READONLY = {'id', 'createdDateTime', 'lastModifiedDateTime'}
TARGETS = {'groupAssignmentTarget': {'groupId'}, 'exclusionGroupAssignmentTarget': {'groupId'},
           'allDevicesAssignmentTarget': set(), 'allLicensedUsersAssignmentTarget': set()}
TARGET_PROPS = {'@odata.type', 'groupId', 'deviceAndAppManagementAssignmentFilterId', 'deviceAndAppManagementAssignmentFilterType'}
SCHEDULES = {'deviceHealthScriptDailySchedule': {'interval', 'useUtc', 'time'}}
SCRIPTS_READ = {'DeviceManagementScripts.Read.All', 'DeviceManagementScripts.ReadWrite.All'}
SCRIPTS_WRITE = {'DeviceManagementScripts.ReadWrite.All'}
GROUPS_READ = {'Group.ReadBasic.All', 'Group.Read.All', 'GroupMember.Read.All', 'Directory.Read.All', 'Group.ReadWrite.All'}
MEMBERS_READ = {'GroupMember.ReadBasic.All', 'GroupMember.Read.All', 'Group.Read.All', 'Group.ReadBasic.All', 'Directory.Read.All'}
DEVICES_READ = {'Device.Read.All', 'Directory.Read.All'}
MANAGED_READ = {'DeviceManagementManagedDevices.Read.All', 'DeviceManagementManagedDevices.ReadWrite.All'}

class Refuse(Exception):
    def __init__(self, code, msg): self.code = code; self.msg = msg

def granted(stub_log):
    try: lines = [l for l in open(stub_log).read().splitlines() if l.startswith('connect ')]
    except OSError: return set()
    return set(lines[-1][len('connect '):].split(',')) if lines else set()

def need(scopes, allowed):
    if not scopes & allowed: raise Refuse(403, 'Authorization_RequestDenied: the signed-in permissions do not allow this call')

def query(url, allowed):
    q = urllib.parse.parse_qs(url.query, keep_blank_values=True)
    for k, v in q.items():
        if k != '$skiptoken' and k not in allowed: raise Refuse(400, 'BadRequest: query option %s is not supported here' % k)
        if len(v) != 1: raise Refuse(400, 'BadRequest: query option %s given twice' % k)
    return {k: v[0] for k, v in q.items()}

def select(obj, q, known):
    if '$select' not in q: return obj
    want = q['$select'].split(',')
    for w in want:
        if w not in known: raise Refuse(400, "BadRequest: could not find a property named '%s'" % w)
    return {k: v for k, v in obj.items() if k in want}

def check_body(body, props, readonly, typ, required=()):
    if not isinstance(body, dict): raise Refuse(400, 'BadRequest: the body is not a JSON object')
    for k in body:
        if k not in props: raise Refuse(400, "BadRequest: the property '%s' does not exist on type '%s'" % (k, typ))
        if k in readonly: raise Refuse(400, "BadRequest: the property '%s' is read-only" % k)
    if '@odata.type' in body and body['@odata.type'] != '#microsoft.graph.' + typ: raise Refuse(400, 'BadRequest: wrong @odata.type')
    for k in required:
        if k not in body: raise Refuse(400, "BadRequest: '%s' is required" % k)
    for k in ('runAs32Bit', 'enforceSignatureCheck', 'isGlobalScript'):
        if k in body and not isinstance(body[k], bool): raise Refuse(400, 'BadRequest: %s takes true or false' % k)
    if 'runAsAccount' in body and body['runAsAccount'] not in ('system', 'user'): raise Refuse(400, 'BadRequest: runAsAccount')
    if 'detectionScriptContent' in body:
        try: base64.b64decode(body['detectionScriptContent'], validate=True)
        except Exception: raise Refuse(400, 'BadRequest: detectionScriptContent is not base64')

def check_assign(body):
    if not isinstance(body, dict) or set(body) != {'deviceHealthScriptAssignments'} or not isinstance(body['deviceHealthScriptAssignments'], list):
        raise Refuse(400, 'BadRequest: assign takes deviceHealthScriptAssignments only')
    out = []
    for a in body['deviceHealthScriptAssignments']:
        if not isinstance(a, dict) or not set(a) <= {'@odata.type', 'id', 'target', 'runRemediationScript', 'runSchedule'}:
            raise Refuse(400, 'BadRequest: unknown deviceHealthScriptAssignment property')
        if a.get('@odata.type', '#microsoft.graph.deviceHealthScriptAssignment') != '#microsoft.graph.deviceHealthScriptAssignment':
            raise Refuse(400, 'BadRequest: wrong assignment @odata.type')
        t = a.get('target'); sch = a.get('runSchedule')
        if not isinstance(t, dict) or not set(t) <= TARGET_PROPS: raise Refuse(400, 'BadRequest: target')
        kind = str(t.get('@odata.type', '')).lstrip('#')
        if not kind.startswith('microsoft.graph.') or kind[16:] not in TARGETS: raise Refuse(400, 'BadRequest: target @odata.type')
        for k in TARGETS[kind[16:]]:
            if not t.get(k): raise Refuse(400, 'BadRequest: target needs %s' % k)
        if not isinstance(a.get('runRemediationScript'), bool): raise Refuse(400, 'BadRequest: runRemediationScript')
        if not isinstance(sch, dict): raise Refuse(400, 'BadRequest: runSchedule')
        sk = str(sch.get('@odata.type', '')).lstrip('#')
        if not sk.startswith('microsoft.graph.') or sk[16:] not in SCHEDULES or set(sch) != SCHEDULES[sk[16:]] | {'@odata.type'}:
            raise Refuse(400, 'BadRequest: runSchedule @odata.type or properties')
        if not isinstance(sch['interval'], int) or isinstance(sch['interval'], bool) or not isinstance(sch['useUtc'], bool) \
           or not re.match(r'^[0-2][0-9]:[0-5][0-9]:[0-5][0-9]$', str(sch['time'])):
            raise Refuse(400, 'BadRequest: runSchedule values')
        out.append({'@odata.type': '#microsoft.graph.deviceHealthScriptAssignment', 'id': str(uuid.uuid4()),
                    'target': dict(t, **{'@odata.type': kind}), 'runRemediationScript': a['runRemediationScript'],
                    'runSchedule': dict(sch, **{'@odata.type': sk})})
    return out

def serve(state_f, log_f, port_f, stub_log):
    def load():
        with open(state_f) as f: return json.load(f)
    def save(s):
        with open(state_f, 'w') as f: json.dump(s, f)
    class H(http.server.BaseHTTPRequestHandler):
        def send(self, code, obj=None):
            body = json.dumps(obj).encode() if obj is not None else b''
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            if body: self.wfile.write(body)
        def page(self, s, items, url, q):
            at_ = int(q.get('$skiptoken', '0')); n = s.get('pageSize', 100)
            out = {'@odata.context': 'https://graph.microsoft.com' + url.path, 'value': items[at_:at_ + n]}
            if at_ + n < len(items):
                nq = urllib.parse.parse_qs(url.query, keep_blank_values=True); nq['$skiptoken'] = [str(at_ + n)]
                out['@odata.nextLink'] = s.get('nextHost', 'https://graph.microsoft.com') + url.path + '?' + urllib.parse.urlencode(nq, doseq=True)
            if s.get('noValue') == url.path: del out['value']
            return out
        def answer(self, m, url, body, s, scopes):
            p = url.path
            if m == 'GET' and p == '/v1.0/groups':
                need(scopes, GROUPS_READ)
                q = query(url, {'$filter', '$select'})
                f = q.get('$filter', ''); pre = "displayName eq '"
                if not (f.startswith(pre) and f.endswith("'")): raise Refuse(400, 'BadRequest: $filter')
                want = f[len(pre):-1].replace("''", "'").lower()
                hits = [select(g, q, {'id', 'displayName', 'mail'}) for g in s['groups'] if g['displayName'].lower() == want]
                return 200, self.page(s, hits, url, q)
            m_ = re.match(r'^/v1\.0/groups/([^/]+)/transitiveMembers$', p)
            if m == 'GET' and m_:
                need(scopes, MEMBERS_READ)
                q = query(url, set())
                gid = urllib.parse.unquote(m_.group(1))
                if gid in s.get('memberErrors', []): raise Refuse(403, 'Authorization_RequestDenied: Insufficient privileges to complete the operation.')
                if gid not in s.get('members', {}): raise Refuse(404, 'Request_ResourceNotFound')
                items = []
                for x in s['members'][gid]:
                    if x.get('@odata.type') == '#microsoft.graph.device' and not scopes & DEVICES_READ:
                        x = {k: (v if k in ('@odata.type', 'id') else None) for k, v in x.items()}
                    items.append(x)
                return 200, self.page(s, items, url, q)
            if m == 'GET' and p == '/v1.0/deviceManagement/managedDevices':
                need(scopes, MANAGED_READ)
                q = query(url, {'$select', '$filter'})
                if '$filter' in q: raise Refuse(400, 'BadRequest: this stand-in answers no $filter on managedDevices')
                known = set().union(*[d.keys() for d in s.get('managed', [])]) | {'id', 'deviceName', 'userPrincipalName', 'azureADDeviceId', 'operatingSystem'}
                return 200, self.page(s, [select(d, q, known) for d in s.get('managed', [])], url, q)
            if p == BASE:
                if m == 'GET':
                    need(scopes, SCRIPTS_READ)
                    q = query(url, {'$select'})
                    return 200, self.page(s, [select(x, q, DHS_PROPS) for x in s['scripts']], url, q)
                if m == 'POST':
                    need(scopes, SCRIPTS_WRITE); query(url, set())
                    check_body(body, DHS_PROPS, DHS_READONLY, 'deviceHealthScript',
                               ('displayName', 'publisher', 'detectionScriptContent', 'runAsAccount'))
                    x = dict(body); x['id'] = str(uuid.uuid4()); x['createdDateTime'] = x['lastModifiedDateTime'] = '2026-11-01T10:00:00Z'
                    x.setdefault('isGlobalScript', False)
                    s['scripts'].append(x); s['assignments'][x['id']] = []; save(s); return 201, x
            if p.startswith('/v1.0/deviceManagement/deviceHealthScripts'):
                raise Refuse(400, "BadRequest: Resource not found for the segment 'deviceHealthScripts'")
            if p.startswith(BASE + '/'):
                parts = p[len(BASE) + 1:].split('/'); sid = urllib.parse.unquote(parts[0])
                hit = [x for x in s['scripts'] if x['id'] == sid]
                if not hit: raise Refuse(404, 'ResourceNotFound')
                sc = hit[0]
                if len(parts) == 1:
                    if m == 'GET': need(scopes, SCRIPTS_READ); q = query(url, {'$select'}); return 200, select(sc, q, DHS_PROPS)
                    if m == 'PATCH':
                        need(scopes, SCRIPTS_WRITE); query(url, set())
                        if sc.get('isGlobalScript'): raise Refuse(400, 'BadRequest: a Microsoft script is read-only')
                        check_body(body, DHS_PROPS, DHS_READONLY, 'deviceHealthScript')
                        sc.update(body); save(s); return 200, sc
                    if m == 'DELETE':
                        need(scopes, SCRIPTS_WRITE); query(url, set())
                        if body is not None: raise Refuse(400, 'BadRequest: DELETE takes no body')
                        s['scripts'] = [x for x in s['scripts'] if x['id'] != sid]; s['assignments'].pop(sid, None); save(s); return 204, None
                if parts[1:] == ['assign'] and m == 'POST':
                    need(scopes, SCRIPTS_WRITE); query(url, set())
                    s['assignments'][sid] = check_assign(body); save(s); return 204, None
                if parts[1:] == ['assignments'] and m == 'GET':
                    need(scopes, SCRIPTS_READ); q = query(url, set())
                    return 200, self.page(s, s['assignments'].get(sid, []), url, q)
                if parts[1:] == ['deviceRunStates'] and m == 'GET':
                    need(scopes, SCRIPTS_READ)
                    q = query(url, {'$expand', '$select'})
                    if '$select' in q: raise Refuse(400, 'BadRequest: this stand-in answers no $select on deviceRunStates')
                    if q.get('$expand', 'managedDevice') != 'managedDevice': raise Refuse(400, "BadRequest: could not find a navigation property named '%s'" % q['$expand'])
                    items = []
                    for r in s['runStates'].get(sid, []):
                        r = dict(r)
                        if '$expand' not in q: r.pop('managedDevice', None)
                        items.append(r)
                    return 200, self.page(s, items, url, q)
            raise Refuse(400, 'BadRequest: no such request in Microsoft Graph as this stand-in knows it: %s %s' % (m, p))
        def handle_any(self):
            n = int(self.headers.get('content-length') or 0)
            raw = self.rfile.read(n) if n else b''
            url = urllib.parse.urlparse(self.path)
            entry = {'method': self.command, 'path': self.path, 'body': None}
            try:
                try: body = json.loads(raw) if raw else None
                except ValueError: raise Refuse(400, 'BadRequest: the body is not JSON')
                entry['body'] = body
                if body is not None and self.command in ('POST', 'PATCH') and not (self.headers.get('content-type') or '').startswith('application/json'):
                    raise Refuse(415, 'UnsupportedMediaType')
                code, obj = self.answer(self.command, url, body, load(), granted(stub_log))
            except Refuse as e:
                code, obj = e.code, {'error': {'code': e.msg.split(':')[0], 'message': e.msg}}
            entry['code'] = code
            with open(log_f, 'a') as f: f.write(json.dumps(entry) + '\n')
            self.send(code, obj)
        do_GET = do_POST = do_PATCH = do_DELETE = do_PUT = handle_any
        def log_message(self, *a): pass
    srv = http.server.HTTPServer(('127.0.0.1', 0), H)
    with open(port_f, 'w') as f: f.write(str(srv.server_address[1]))
    srv.serve_forever()

# --- One account run's output, as gird-check.ps1 -AccountRun and gird-check.sh --account-run print it

KEYS = ['v', 'agents', 'yolo', 'tools', 'mcp_servers', 'mcp_token_files', 'key_files', 'key_providers', 'history_keys', 'session_files',
        'sessions_partial', 'allow_list_keys', 'ssh_open', 'ak_links', 'planted', 'possible', 'incidents', 'platforms', 'on_open', 'to_read',
        'updates', 'wiper', 'lock_only', 'remove', 'not_read', 'moved', 'tmp_marks', 'tmp_wiper', 'protected', 'engine', 'end']
def incidents():
    out = []
    for l in open(os.path.join(HERE, '..', 'data', 'incidents.tsv')):
        if l.startswith('#') or not l.strip(): continue
        f = l.rstrip('\n').split('\t'); out.append((f[0], f[5]))
    return out
def account(kind, flavour):
    a = {k: '0' for k in KEYS}
    a.update(v='1', end='1', protected='ok', engine='none', agents='', yolo='', tools='', key_providers='', possible='', incidents='',
             platforms='', updates='', lock_only='', remove='', tmp_marks='')
    if kind == 'act':
        a.update(wiper='1', incidents='tanstack mistral', lock_only='axios', planted='2', key_files='3', key_providers='anthropic aws',
                 history_keys='1', session_files='2', mcp_token_files='1', allow_list_keys='1', ak_links='1')
    elif kind == 'review':
        a.update(yolo='claude-code codex', ssh_open='1', tools='amazonq', platforms='opencode', on_open='1', to_read='1', updates='mistral',
                 remove='glassworm', possible='mastra')
        if flavour == 'sh': a.update(tmp_wiper='1', tmp_marks='mastra')
    elif kind == 'tmpmarks':
        a.update(possible='mastra', tmp_marks='mastra')
    elif kind == 'partial':
        a.update(sessions_partial='1', ssh_open='1', not_read='2')
    elif kind == 'actpartial':
        a.update(key_files='1', not_read='1')
    elif kind == 'huge':
        ids = [i for i, _ in incidents()][:40]; acts = [i for i, lv in incidents() if lv == 'act'][:40]
        a.update(wiper='1', incidents=' '.join(acts), lock_only=' '.join(ids), possible=' '.join(ids), remove=' '.join(ids),
                 updates=' '.join(ids), key_files='3', key_providers='anthropic openrouter openai google groq xai huggingface perplexity replicate aws github npm',
                 yolo='claude-code codex gemini-cli cursor windsurf antigravity copilot-cli opencode goose aider cline continue', tools='amazonq claudecode mcpremote',
                 platforms='opencode railway zeabur', planted='999999', history_keys='999999', session_files='999999')
        if flavour == 'sh': a['tmp_marks'] = ' '.join(ids)
    sys.stdout.write(''.join('%s=%s\n' % (k, a[k]) for k in KEYS))

# --- The checks ------------------------------------------------------------------------------

R = []
def check(name, cond, detail=''):
    R.append('%s|intune: %s|%s' % ('ok' if cond else 'bad', name, '' if cond else str(detail).replace('\n', ' ').replace('|', '/')[:300]))
def requests(w, f='requests.log'):
    with open(os.path.join(w, f)) as fh: return [json.loads(l) for l in fh if l.strip()]
def scripts(w):
    with open(os.path.join(w, 'state.json')) as f: return json.load(f)['scripts']
def refused(reqs): return [(r['method'], r['path'], r.get('code')) for r in reqs if r.get('code', 200) >= 400]
def unquote_cell(c): return c[1:] if c.startswith("'") else c
def formula(c): return bool(c) and c.lstrip(' ')[:1] in ('=', '+', '-', '@', '\t', '\r')
MEANING = 'MITRE ATT&amp;CK and ATLAS references show which attack technique each finding relates to.'
MEANING_CSV = 'MITRE ATT&CK and ATLAS references show which attack technique each finding relates to. Blindspot reads files on each computer. It does not watch for attacks and does not detect any technique in use.'
def bad_links(html):
    return [u for u in re.findall(r'href\s*=\s*["\']?([^"\' >]*)', html)
            if not re.match(r'^https://(attack\.mitre\.org/techniques/T[0-9]{4}(/[0-9]{3})?/|atlas\.mitre\.org/techniques/AML\.T[0-9]{4}(\.[0-9]{3})?)$', u)]
def first_ref(html):
    at = [i for i in (html.find('attack.mitre.org'), html.find('atlas.mitre.org'), html.find('>T1'), html.find('>AML.')) if i >= 0]
    return min(at) if at else len(html)
def found_cell(html, label):
    m = re.search(r'<tr><td>%s</td><td>([0-9]+)</td><td class="ref">(.*?)</td></tr>' % re.escape(label), html)
    return (int(m.group(1)), m.group(2)) if m else (None, '')
def tech_row(html, tid): # (computers, exposure, indicator)
    m = re.search(r'<tr><td>[^<]*<span class="muted"><a href="[^"]*"[^>]*>%s</a></span></td><td>([^<]*)</td><td>([0-9]+)</td><td>([0-9]+)</td><td>([0-9]+)</td></tr>' % re.escape(tid), html)
    return tuple(int(x) for x in m.groups()[1:]) if m else None
AK = 'An AI agent set to run commands without asking, with a key in plain text in the same account'
SE = 'A key in an AI agent&#39;s saved session files'
MC = 'A token written in an MCP server&#39;s config'
def path_line(html, text): # (found, none found, not known, the rest of the line)
    m = re.search(r'<li>%s: found on ([0-9]+) computers?, none found on ([0-9]+) computers?, not known for ([0-9]+) computers?\.(.*?)</li>' % re.escape(text), html)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4).strip()) if m else None
def adds_up(html):
    m = re.search(r'<b>([0-9]+)</b>Computers', html); n = int(m.group(1)) if m else -1
    got = [path_line(html, t) for t in (AK, SE, MC)]
    return n > 0 and all(g is not None and g[0] + g[1] + g[2] == n for g in got) and ('every one of the %d computers in this report once' % n) in html, (n, got)
def tactics(html):
    i = html.find('<h2>What this report covers')
    return html[i:html.find('<b>What Blindspot does not look at', i)] if i >= 0 else ''
def load_out(w, t):
    csvs = glob.glob(os.path.join(w, 'out-' + t, '*.csv')); htmls = glob.glob(os.path.join(w, 'out-' + t, '*.html'))
    out = open(os.path.join(w, 'o-%s.txt' % t)).read()
    if len(csvs) != 1 or len(htmls) != 1: return None, out
    raw = open(csvs[0], encoding='utf-8-sig').read()
    rows = list(csv.DictReader(raw.splitlines(True)))
    by = {unquote_cell(r['pc']): r for r in rows}
    return (raw, rows, by, open(htmls[0], encoding='utf-8').read()), out

WANT_ASSIGN = {'deviceHealthScriptAssignments': [{
    '@odata.type': '#microsoft.graph.deviceHealthScriptAssignment',
    'target': {'@odata.type': '#microsoft.graph.groupAssignmentTarget', 'groupId': 'g-obrien'},
    'runRemediationScript': False,
    'runSchedule': {'@odata.type': '#microsoft.graph.deviceHealthScriptDailySchedule', 'interval': 1, 'useUtc': False, 'time': '09:00:00'}}]}

def main():
    if sys.argv[1] == 'state':
        with open(sys.argv[3], 'w') as f: json.dump(tenant(sys.argv[2], sys.argv[4] if len(sys.argv) > 4 else None), f)
        return
    if sys.argv[1] == 'serve': return serve(*sys.argv[2:6])
    if sys.argv[1] == 'files': return write_files(sys.argv[2])
    if sys.argv[1] == 'account': return account(sys.argv[2], sys.argv[3])
    mode, w = sys.argv[2], sys.argv[3]
    reqs = requests(w)
    writes = [r for r in reqs if r['method'] in ('POST', 'PATCH', 'DELETE')]
    stub = open(os.path.join(w, 'stub.log')).read().split('\n')
    if mode == 'deploy':
        fleet = open(os.path.join(w, 'fleet.ps1'), 'rb').read()
        check('-Deploy makes no request the stand-in refuses', not refused(reqs), refused(reqs))
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
        assigns = [r for r in reqs if r['method'] == 'POST' and r['path'] == '%s/%s/assign' % (BASE, sid)]
        check('-Deploy assigns it to the one group, daily, with no fix script run', [a['body'] for a in assigns] == [WANT_ASSIGN], [a['body'] for a in assigns])
        check('-Deploy writes nothing else', len(writes) == 2, [(r['method'], r['path']) for r in writes])
        check('-Deploy leaves the other Remediations as they were', [s for s in scripts(w) if s.get('id') != sid] == [OTHER, GLOBAL])
        with open(os.path.join(w, 'first.json'), 'w') as f: json.dump({'id': sid, 'description': mine[0]['description'] if mine else ''}, f)
    elif mode == 'redeploy':
        fleet = open(os.path.join(w, 'fleet.ps1'), 'rb').read()
        first = json.load(open(os.path.join(w, 'first.json')))
        out = open(os.path.join(w, 'o.txt')).read(); wi = open(os.path.join(w, 'o-whatif.txt')).read()
        check('a second -Deploy makes no request the stand-in refuses', not refused(reqs), refused(reqs))
        mine = [s for s in scripts(w) if s.get('publisher') == 'Blindspot']
        check('a second -Deploy adds no Remediation', len(mine) == 1 and not [r for r in reqs if r['method'] == 'POST' and r['path'] == BASE], len(mine))
        gets = [i for i, r in enumerate(reqs) if r['method'] == 'GET' and r['path'] == '%s/%s' % (BASE, first['id'])]
        patches = [i for i, r in enumerate(reqs) if r['method'] == 'PATCH']
        check('a second -Deploy reads the Remediation again by its id before it changes it', gets and patches and gets[0] < patches[0], (gets, patches))
        check('a second -Deploy updates the one it made', [reqs[i]['path'] for i in patches] == ['%s/%s' % (BASE, first['id'])], [reqs[i]['path'] for i in patches])
        b = reqs[patches[0]]['body'] if patches else {}
        check('the update carries the newer script', base64.b64decode(b.get('detectionScriptContent', '')) == fleet)
        check('the update keeps the mark', b.get('description') == first['description'], b.get('description'))
        assigns = [r for r in reqs if r['method'] == 'POST' and r['path'] == '%s/%s/assign' % (BASE, first['id'])]
        check('a second -Deploy assigns it again to the one group', [a['body'] for a in assigns] == [WANT_ASSIGN], [a['body'] for a in assigns])
        check('a second -Deploy writes nothing else', len(writes) == 2, [(r['method'], r['path']) for r in writes])
        check('-Deploy -WhatIf says the group replaces the groups it is assigned to now',
              'replaces the groups it is assigned to now' in wi and 'assigned to:   1 group' in wi, wi[-400:])
        check('-Deploy says it is assigned to that group only', "Assigned to 'O'Brien team' only" in out, out[-300:])
    elif mode == 'remove':
        check('-Remove makes no request the stand-in refuses', not refused(reqs), refused(reqs))
        dels = [r['path'] for r in writes]
        check('-Remove deletes only the Remediation with its mark', dels == ['%s/ours-1' % BASE], dels)
        left = [s['id'] for s in scripts(w)]
        check('-Remove leaves a same-named one, a copied mark from another publisher and a built-in script',
              left == ['other-1', 'look-1', 'copy-1', 'global-2', 'global-1'], left)
        check('-Remove signs in with the scripts write scope only', stub[0] == 'connect DeviceManagementScripts.ReadWrite.All', stub[0])
    elif mode == 'report':
        check('-Export makes no request the stand-in refuses', not refused(reqs), refused(reqs))
        check('-Export signs in with read scopes only', stub[0] == 'connect DeviceManagementScripts.Read.All,DeviceManagementManagedDevices.Read.All,GroupMember.ReadBasic.All,Device.Read.All', stub[0])
        pages = [r for r in reqs if r['method'] == 'GET' and r['path'].startswith('%s/ours-1/deviceRunStates' % BASE)]
        check('-Export follows every next-page link', len(pages) == (len(PCS) + 1) // 2, len(pages))
        got, out = load_out(w, 'report')
        check('the report saves one HTML file and one CSV file', got is not None)
        if got is None: print('\n'.join(R)); return
        raw, rows, by, html = got
        check('the CSV has a row for every PC', len(rows) == len(PCS), len(rows))
        for name, _, _, status, label in PCS:
            st = by.get(name, {}).get('status')
            check('the report: ' + label, st == status, '%s: wanted %s, got %s' % (name, status, st))
        clear = sorted(n for n, r in by.items() if r['status'] == 'clear')
        check('the report calls only the fully read clear results clear', clear == ['PC-CLEAR', 'PC-CRLF', 'PC-OTHER'], clear)
        check('the other profiles a result names are shown', 'other accounts on this PC not checked' in by.get('PC-OTHER', {}).get('why', ''), by.get('PC-OTHER'))
        check('a result Intune may have cut says so', 'may have cut it short' in by.get('PC-CUT', {}).get('why', ''), by.get('PC-CUT'))
        check('a result Intune may have cut says so, also at 2,048 characters', 'may have cut it short' in by.get('PC-CUT2048', {}).get('why', ''), by.get('PC-CUT2048'))
        check('a full result with its line end is not said to be cut', all('cut' not in by.get(n, {}).get('why', '') for n in ('PC-FULL', 'PC-FULLCRLF')), (by.get('PC-FULL'), by.get('PC-FULLCRLF')))
        newer = 'newer Blindspot'
        check('a newer version header says the PCs run a newer Blindspot and the tool needs updating',
              all(newer in by.get(n, {}).get('why', '') and 'newer format' in by[n]['why'] and 'update this tool' in by[n]['why'] for n in ('PC-V2', 'PC-V3')), (by.get('PC-V2'), by.get('PC-V3')))
        check('an item word this tool does not know says the PCs run a newer Blindspot and the tool needs updating',
              all(newer in by.get(n, {}).get('why', '') and 'does not know' in by[n]['why'] and 'update this tool' in by[n]['why'] for n in ('PC-NEWITEM', 'PC-NEWITEMACT', 'PC-UNKNOWN')),
              [by.get(n) for n in ('PC-NEWITEM', 'PC-NEWITEMACT', 'PC-UNKNOWN')])
        check('a malformed result does not claim a newer Blindspot', all(newer not in by.get(n, {}).get('why', '') for n in ('PC-LIE', 'PC-TWOLINES', 'PC-CLEARDETAIL')),
              [by.get(n) for n in ('PC-LIE', 'PC-TWOLINES', 'PC-CLEARDETAIL')])
        check('no newer-version or unknown-word PC reads as clear', not [n for n in ('PC-V2', 'PC-V3', 'PC-NEWITEM', 'PC-NEWITEMACT', 'PC-UNKNOWN') if by.get(n, {}).get('status') == 'clear'])
        check('CSV cells that start like a formula are quoted', raw.count('"\'=cmd|calc"') == 1 and '"\'@SUM(1)"' in raw and '"\'+1"' in raw
              and '"\'=HYPERLINK(""http://x"",""y"")<img src=x onerror=alert(1)>"' in raw, raw[:300])
        check('CSV cells that start like a formula after spaces are quoted', '"\' =SUM(2)"' in raw and '"\'  -2+3"' in raw and '"\' -1"' in raw)
        check('no CSV cell starts with a formula character, spaces aside', not [c for r in csv.reader(raw.splitlines(True)) for c in r if formula(c)])
        check('the HTML escapes what a PC sent', '<img' not in html and '<script>alert' not in html and 'onerror=alert(1)&gt;' in html
              and '&lt;script&gt;alert(1)&lt;/script&gt;' in html)
        check('the HTML loads nothing from outside', re.search(r'src\s*=\s*["\']?(https?:)?//', html) is None and '<link' not in html)
        check('the HTML links only to MITRE technique pages', bad_links(html) == [], bad_links(html))
        n, cell = found_cell(html, 'Malware incident found')
        check('a kind whose ATLAS reference fits only some incidents does not show it when none of them was found',
              n == 2 and 'AML.T0010.001' not in cell and 'AML.T0011.001' not in cell and 'T1195.001' in cell and 'ATLAS: none applies to what these computers sent.' in cell, cell)
        check('the MITRE sentence comes before the first MITRE reference', 0 <= html.find(MEANING) < first_ref(html), (html.find(MEANING), first_ref(html)))
        check('the HTML counts the PCs with each kind of finding', '<td>Keys in plain text</td><td>1</td>' in html
              and '<td>SSH keys without a passphrase</td><td>3</td>' in html and '<td>Malware incident found</td><td>2</td>' in html)
        first = html.find('Deal with these first'); none = html.find('<h2>No result'); ok_at = html.find('<h2>Nothing found')
        check('the HTML lists the PCs to deal with first, then no result, then nothing found', 0 < first < none < ok_at)
        order = [html.find(x) for x in ('PC-ACT', 'PC-PARTIAL', 'PC-FAILED', 'PC-STALE<')]
        check('the PCs to deal with first are act, then not checked, failed, stale', all(x > 0 for x in order) and order == sorted(order), order)
    elif mode == 'mitre':
        got, out = load_out(w, 'mitre')
        check('the report on the MITRE fleet saves its files', got is not None, out[-300:])
        if got is None: print('\n'.join(R)); return
        raw, rows, by, html = got
        check('the HTML links only to MITRE technique pages, in the MITRE fleet too', bad_links(html) == [] and 'attack.mitre.org' in html and 'atlas.mitre.org' in html, bad_links(html))
        check('the MITRE sentence comes before the first MITRE reference, in the MITRE fleet too', 0 <= html.find(MEANING) < first_ref(html), (html.find(MEANING), first_ref(html)))
        check('a PC with three findings under one technique is counted once for it, as an exposure', tech_row(html, 'T1552.001') == (3, 3, 0), tech_row(html, 'T1552.001'))
        check('project settings that act when a folder opens relate to no technique: the supply chain technique counts the incidents only',
              tech_row(html, 'T1195.001') == (3, 0, 3) and tech_row(html, 'AML.T0081') is None, (tech_row(html, 'T1195.001'), tech_row(html, 'AML.T0081')))
        n, cell = found_cell(html, 'Project settings that act when a folder opens')
        check('project settings that act when a folder opens say why there is no reference', n == 1 and 'href' not in cell and 'cannot tell those from settings a person wrote' in cell
              and 'not AI agent settings' in cell, cell)
        check('the wiper is an indicator of data destruction on every system, and never a launch agent', tech_row(html, 'T1485') == (2, 0, 2) and tech_row(html, 'T1543.001') is None
              and 'T1543' not in html and 'Armed' not in html and 'armed' not in html, (tech_row(html, 'T1485'), tech_row(html, 'T1543.001')))
        check('a Windows-only technique counts Windows PCs only', tech_row(html, 'T1698') == (3, 3, 0) and tech_row(html, 'AML.T0053') == (4, 4, 0),
              (tech_row(html, 'T1698'), tech_row(html, 'AML.T0053')))
        check('a key in agent sessions relates to ATLAS Unsecured Credentials, not to data from an AI service',
              'AML.T0085' not in html and 'AML.T0055' in found_cell(html, 'Keys in agent sessions')[1] and tech_row(html, 'AML.T0055') == (4, 4, 0), tech_row(html, 'AML.T0055'))
        check('the table of findings names the relations it uses', '<th>MITRE technique (exposure or indicator)</th>' in html and '<th>Exposure</th><th>Indicator</th></tr>' in html)
        n, cell = found_cell(html, 'Malware incident found')
        check('an ATLAS reference that fits only some incidents is shown for those, with their count, not for the whole kind',
              n == 3 and 'AML.T0010.001</a> Supply Chain Compromise: Software (only for the incidents LiteLLM 1.107.0: 1 computer)' in cell, cell)
        check('the plain label leads and the reference follows it', n == 3 and cell.startswith('ATT&amp;CK: Indicator of <a href="https://attack.mitre.org/techniques/T1195/001/"'), cell[:200])
        n, cell = found_cell(html, 'Tools with a security fix to install')
        check('a kind mapped to no technique shows no reference, and says why', n == 1 and cell.startswith('No MITRE reference: ') and 'href' not in cell and 'T1' not in cell, cell)
        check('a CSV row with no reference has none', 'T1698' in by['M-REVIEW']['mitre'] and 'AML.T0053' in by['M-REVIEW']['mitre'] and 'T1195' not in by['M-REVIEW']['mitre']
              and 'AML.T0081' not in by['M-REVIEW']['mitre'] and 'amazonq' not in by['M-REVIEW']['mitre'] and by['M-CLEAR']['mitre'] == '', (by['M-REVIEW']['mitre'], by['M-CLEAR']['mitre']))
        others = '1 of the %d computers with none found also has other accounts that were not read.'
        check('the agent with a key statement counts found, none found and not known, providers too',
              path_line(html, AK) == (2, 4, 5, 'Providers of those keys: anthropic (1 computer), aws (1 computer), not named in the result (1 computer). ' + others % 4), path_line(html, AK))
        check('the agent and the key must be in the same account', by['M-MAC']['run_without_asking_and_key'] == 'no', by['M-MAC'])
        check('the key in a session statement counts found, none found and not known', path_line(html, SE) == (1, 5, 5, others % 5), path_line(html, SE))
        check('the token in an MCP config statement counts found, none found and not known', path_line(html, MC) == (1, 5, 5, others % 5), path_line(html, MC))
        check('each statement adds up to the computers in the report', adds_up(html)[0], adds_up(html)[1])
        unk = sorted(n for n, r in by.items() if r['key_in_agent_sessions'] == 'unknown')
        check('a partly checked, cut, stale, cut-to-fit or silent PC is not known, never no', unk == ['M-CUT', 'M-EMPTY', 'M-MORE', 'M-PARTIAL', 'M-STALE'], unk)
        check('a fully read PC with nothing is no, other profiles on it or not', all(by[n]['key_in_agent_sessions'] == 'no' and by[n]['token_in_mcp_config'] == 'no' for n in ('M-MAC', 'M-REVIEW', 'M-WIPER', 'M-NOPROV', 'M-CLEAR')))
        check('the wiper is labelled by what the result supports: its files or folders, not an install', 'Files or folders of the gh-token-monitor wiper' in html and 'installed' not in html)
        check('the CSV keeps its first columns and adds the new ones after them', raw.splitlines()[0].lstrip('\ufeff') ==
              '"pc","user","status","why","checked_at","details","intune_last_report","output","mitre","mitre_note","mitre_source","run_without_asking_and_key","run_without_asking_key_providers","key_in_agent_sessions","token_in_mcp_config","os","source","last_seen"',
              raw.splitlines()[0])
        check('every CSV row with a reference carries the MITRE sentence and the attribution, and only those',
              all((r['mitre'] != '') == r['mitre_note'].startswith(MEANING_CSV) == ('The MITRE Corporation' in r['mitre_source']) for r in rows)
              and sum(1 for r in rows if r['mitre']) == 7, [(unquote_cell(r['pc']), r['mitre'][:40], r['mitre_note'][:20]) for r in rows])
        check('the footer names the versions, MITRE\'s notice and that the mapping is Blindspot\'s own',
              'MITRE ATT&amp;CK Enterprise v20.1 and MITRE ATLAS 2026.10' in html and re.search(r'(\u00a9|&#169;|&copy;) 2026 The MITRE Corporation\. This work', html) is not None and ' 2026 The MITRE Corporation. This work is reproduced and distributed with the permission of The MITRE Corporation.' in html
              and 'Copyright 2021-2026 MITRE, licensed under the Apache License, Version 2.0' in html and 'is Blindspot&#39;s own, not MITRE&#39;s' in html)
        check('the report says what it does not look at', all(x in html for x in ('The network:', 'The identity provider:', 'The cloud control plane:', 'lakehouse', 'What AI agents do while they run')))
        check('the report says one account per Windows PC and counts the PCs with others', '1 computer had other accounts that were not checked.' in html)
        tc = tactics(html)
        check('the report lists the tactics of the techniques its findings relate to, and only those',
              '<li>Credential Access: Unsecured Credentials: Credentials In Files (T1552.001)' in tc and '<li>Credential Access: Unsecured Credentials (AML.T0055); Credentials from AI Agent Configuration (AML.T0083)</li>' in tc
              and 'tactics the findings in this report relate to:' in tc and 'Persistence' not in tc and 'Collection' not in tc and 'Defense Evasion' not in tc, tc[:600])
    elif mode == 'files':
        got, out = load_out(w, 'jamf')
        check('gird-report.ps1 reads a Jamf Pro export and saves its files', got is not None, out[-300:])
        if got is None: print('\n'.join(R)); return
        raw, rows, by, html = got
        check('gird-report.ps1 makes no network request and never signs in', open(os.path.join(w, 'requests-jamf.log')).read() == '' and open(os.path.join(w, 'stub-jamf.log')).read() == '')
        for n, v, st in JAMF:
            check('gird-report.ps1: %s reads as %s' % (n, st), by.get(n, {}).get('status') == st, (n, by.get(n)))
        check('a Mac result is shown as macOS, from its file', by['MAC-ACT']['os'] == 'macOS' and by['MAC-ACT']['source'] == 'jamf.csv' and 'jamf.csv (13)' in html, by['MAC-ACT'])
        check('the time the MDM last heard from it is kept', by['MAC-ACT']['last_seen'] == '2026-11-18 09:00:00' and by['MAC-ACT']['intune_last_report'] == '', by['MAC-ACT'])
        check('a Mac summary line says it names no findings', 'summary line' in by['MAC-SUMMARY']['why'], by['MAC-SUMMARY'])
        check('a name given twice with two serial numbers is two computers, each read', by['MAC-DUP']['status'] == 'clear' and by['mac-dup']['status'] == 'act'
              and '<li>1 computer name (or device identifier) appears more than once across the rows. Each row was counted as its own computer, so some computers may be counted more than once.</li>' in html, (by['MAC-DUP'], by['mac-dup']))
        check('a Mac wiper is an indicator of data destruction and is not said to be a launch agent', tech_row(html, 'T1543.001') is None and tech_row(html, 'T1485') == (1, 0, 1), (tech_row(html, 'T1543.001'), tech_row(html, 'T1485')))
        check('a Mac agent set to run without asking relates to ATLAS only', tech_row(html, 'AML.T0053') == (2, 2, 0) and tech_row(html, 'T1698') is None, tech_row(html, 'AML.T0053'))
        tc = tactics(html)
        check('the tactics listed are those of the techniques found, not every one the tool can name',
              'Credential Access' in tc and 'Impact' in tc and 'Initial Access' not in tc and 'Persistence' not in tc and 'Collection' not in tc, tc[:600])
        n, cell = found_cell(html, 'Malware markers in a shared folder')
        check('a Mac-only finding word shows its decision', n == 1 and cell.startswith('No MITRE reference: '), cell)
        check('the path statements read Mac rows', path_line(html, AK) == (1, 4, 8, 'Providers of those keys: anthropic (1 computer), github (1 computer).'), path_line(html, AK))
        check('each statement adds up to the computers in the report, from a file too', adds_up(html)[0], adds_up(html)[1])
        check('the Windows one-account sentence is left out when no result is from Windows, and the Mac one is there',
              'Each Windows result covers one account' not in html and 'Each Mac result covers every local account' in html)
        check('hostile cells from the file are escaped in the HTML', '<script>alert' not in html and '"quoted" <b>' not in html and '&quot;quoted&quot; &lt;b&gt;' in html and '&lt;script&gt;alert(1)&lt;/script&gt;' in html)
        check('no CSV cell from the file starts with a formula character', not [c for r in csv.reader(raw.splitlines(True)) for c in r if formula(c)] and '"\'=cmd|calc"' in raw)
        check('the HTML from a file links only to MITRE technique pages', bad_links(html) == [], bad_links(html))
        got, out = load_out(w, 'plain')
        check('a plain two-column CSV is read, its columns found by header and values', got is not None and got[2].get('MAC-BOTH', {}).get('status') == 'act'
              and got[2].get('MAC-PLAIN', {}).get('status') == 'no_result' and len(got[1]) == 3, out[-300:])
        got, out = load_out(w, 'mixed')
        check('one report reads Intune and a file together and says where each came from', got is not None
              and got[2].get('PC-ACT', {}).get('source') == 'intune.csv' and got[2].get('PC-ACT', {}).get('os') == 'Windows'
              and got[2].get('MAC-ACT', {}).get('source') == 'jamf.csv' and 'intune.csv (' in got[3] and 'jamf.csv (13)' in got[3]
              and 'Each Windows result covers one account' in got[3] and 'Each Mac result covers every local account' in got[3], out[-300:])
        got, out = load_out(w, 'clearonly')
        check('a report with no finding lists no tactic as found', got is not None and '<li>' not in tactics(got[3]) and 'No finding in this report relates to a MITRE tactic.' in got[3], out[-300:])
        check('a report with no repeated name or device id has no line about repeats', got is not None and 'more than once across the rows' not in got[3] and 'Read 1 computer ' in out, out[-300:])
        got, out = load_out(w, 'paths')
        check('the paths file is read', got is not None, out[-300:])
        if got:
            by = {}
            for r in got[1]: by.setdefault(unquote_cell(r['pc']), []).append(r)
            for n in sorted(set(x[0] for x in PATHS)):
                want = sorted(set((ak, se, mc) for n_, v, ak, se, mc in PATHS if n_ == n))
                got_ = sorted(set((r['run_without_asking_and_key'], r['key_in_agent_sessions'], r['token_in_mcp_config']) for r in by.get(n, [])))
                check('what could get out, %s: %s' % (n, '; '.join(', '.join(w) for w in want)), got_ == want, (got_, [x[1][:120] for x in PATHS if x[0] == n]))
            why = lambda n: by.get(n, [{}])[0].get('why', '')
            check('an act result with an account partly checked says so', all('partly checked' in why(n) for n in ('P-ACT-PARTIAL', 'P-ACT-OTHER-PARTIAL', 'P-ACT-PARTIAL-SE')),
                  [why(n) for n in ('P-ACT-PARTIAL', 'P-ACT-OTHER-PARTIAL', 'P-ACT-PARTIAL-SE')])
            check('an act result with an account not checked says so', why('P-ACT-NC-WORD') == '1 account not checked', why('P-ACT-NC-WORD'))
            check('two rows of one name and no device id are two computers', len(by.get('P-TWICE', [])) == 2, by.get('P-TWICE'))
            check('the paths file adds up too', adds_up(got[3])[0], adds_up(got[3])[1])
        rep = lambda n: '<li>%d computer name%s more than once across the rows. Each row was counted as its own computer, so some computers may be counted more than once.</li>' % (n, ' (or device identifier) appears' if n == 1 else 's (or device identifiers) appear')
        reps = lambda html: re.findall(r'<li>[^<]*more than once across the rows[^<]*</li>', html)
        got, out = load_out(w, 'oem')
        check('two PCs sharing the serial number To be filled by O.E.M. are both counted, and the act is shown', got is not None
              and sorted((unquote_cell(r['pc']), r['status']) for r in got[1]) == [('PC-OEM1', 'act'), ('PC-OEM2', 'clear')]
              and '<b>2</b>Computers' in got[3] and '<td>Keys in plain text</td><td>1</td>' in got[3] and reps(got[3]) == [rep(1)], (out[-300:], got and reps(got[3])))
        got, out = load_out(w, 'mdmid')
        check('two MDM device ids of 5 from two files are both counted, and the finding is shown', got is not None
              and sorted((unquote_cell(r['pc']), r['status'], r['source']) for r in got[1]) == [('MAC-MDMB', 'act', 'mdmb.csv'), ('PC-MDMA', 'clear', 'mdma.csv')]
              and '<b>2</b>Computers' in got[3] and '<td>Keys in plain text</td><td>1</td>' in got[3] and reps(got[3]) == [rep(1)], (out[-300:], got and reps(got[3])))
        got, out = load_out(w, 'dupname')
        check('the same names in two files are each counted, and the limits say how many names repeat', got is not None
              and sorted((unquote_cell(r['pc']).lower(), r['status']) for r in got[1]) == [('imac', 'clear'), ('imac', 'clear'), ('mac-only-c', 'clear'), ('macbook-pro', 'act'), ('macbook-pro', 'clear')]
              and '<b>5</b>Computers' in got[3] and '<td>Keys in plain text</td><td>1</td>' in got[3] and reps(got[3]) == [rep(2)], (out[-300:], got and reps(got[3])))
        got, out = load_out(w, 'winfleet')
        check('a Windows fleet with second profiles is read', got is not None, out[-300:])
        if got:
            html = got[3]
            o = ' 7 of the 8 computers with none found also have other accounts that were not read.'
            check('a Windows fleet where most PCs have a second profile reads none found for the accounts read, and says how many have others',
                  path_line(html, AK) == (1, 8, 2, 'Providers of those keys: aws (1 computer).' + o) and path_line(html, SE) == (1, 8, 2, o.strip()) and path_line(html, MC) == (1, 8, 2, o.strip()),
                  [path_line(html, t) for t in (AK, SE, MC)])
            check('a Windows fleet adds up', adds_up(html)[0], adds_up(html)[1])
            check('a PC whose one account is act and partly checked is counted as partly checked in the limits, and says why',
                  '<li>1 computer failed or were partly checked but sent a result' in html and 'partly checked' in got[2].get('W-11', {}).get('why', ''), (got[2].get('W-11'), re.findall(r'<li>[^<]*partly[^<]*</li>', html)))
        got, out = load_out(w, 'big')
        check('a file of 20,000 computers is read in full', got is not None and len(got[1]) == 20000 and sum(1 for r in got[1] if r['status'] == 'act') == 13333, out[-300:])
    elif mode == 'forms':
        rows = form_rows(os.path.join(w, 'forms.tsv'))
        got, out = load_out(w, 'forms')
        check('the report reads every writer form, and -Export makes no refused request', got is not None and not refused(requests(w, 'requests-forms.log')), out[-300:])
        if got:
            by = got[2]
            for i, (st, label, value) in enumerate(rows):
                r = by.get('FORM-%03d' % i, {})
                check('writer form: %s' % label, r.get('status') == st, 'wanted %s, got %s (%s) for %s' % (st, r.get('status'), r.get('why'), value[:160]))
    elif mode == 'silent':
        got, out = load_out(w, 'silent')
        check('the report with a silent group saves its files', got is not None, out[-300:])
        if got:
            raw, rows, by, html = got
            names = [unquote_cell(r['pc']) for r in rows]
            check('a PC in the group with no result row is listed as no result yet',
                  all(by.get(n, {}).get('status') == 'no_result' and 'no result yet' in by[n]['why'] for n in ('PC-SILENT-1', 'PC-SILENT-2')), by)
            check('a PC with a result row is listed once, as read', names.count('PC-HASROW') == 1 and by['PC-HASROW']['status'] == 'clear', names)
            check('a Mac and a PC outside the group are not listed', 'MAC-SILENT' not in names and 'PC-NOTINGROUP' not in names, names)
            check('every PC is listed once', len(names) == len(set(names)) == 5, names)
            check('the PCs with no result are counted as not checked, never clear',
                  re.search(r'<b>4</b>Not checked: no result', html) is not None and 'Not checked: 4 ' in out and 'Nothing found: 1.' in out, out)
            check('the silent PCs are in the no result section, not under nothing found',
                  html.find('<h2>No result') < html.find('PC-SILENT-1') < html.find('<h2>Nothing found'))
            check('a hostile PC name with no result is escaped in the HTML and guarded in the CSV',
                  '<script>alert' not in html and '&lt;script&gt;alert(1)&lt;/script&gt;' in html
                  and raw.count('"\'=cmd|<script>alert(1)</script>"') == 1 and '"\'<script>' not in raw and SILENT_HOSTILE in names and HOSTILE_NAME in names, raw[:400])
            check('no CSV cell of a silent PC starts with a formula character', not [c for r in csv.reader(raw.splitlines(True)) for c in r if formula(c)])
            check('a group with every PC listed has no could-not-list note', 'Could not list' not in html and 'Note:' not in out)
        sreqs = requests(w, 'requests-silent.log')
        check('-Export follows every next-page link of the device list', len([r for r in sreqs if '/managedDevices' in r['path']]) == (len(SILENT_MANAGED) + 1) // 2)
        check('-Export follows every next-page link of the group members', len([r for r in sreqs if 'transitiveMembers' in r['path']]) == (len(SILENT_MEMBERS) + 1) // 2)
        allreqs = [r for t in SILENT_TENANTS for r in requests(w, 'requests-%s.log' % t)]
        check('-Export with any assignment changes nothing in Intune', not [r for r in allreqs if r['method'] != 'GET'])
        bad = [(t, refused(requests(w, 'requests-%s.log' % t))) for t in SILENT_TENANTS if t not in ('membererror', 'exclerror')]
        check('-Export makes no request the stand-in refuses, whatever the assignment', not [b for b in bad if b[1]], bad)
        def names_of(t):
            g, _ = load_out(w, t); return sorted(g[2]) if g else None
        got, out = load_out(w, 'usergroup')
        check('a group of people says plainly it could not list the PCs with no result', got is not None
              and 'Could not list the PCs with no result for the people in group g-eng (2)' in got[3] and 'does not mean they are clear' in got[3]
              and out.count('Note: Could not list') == 1, out)
        check('a group of people lists no PC that was not read', names_of('usergroup') == ['PC-HASROW'], names_of('usergroup'))
        got, out = load_out(w, 'othertarget')
        check('an assignment to every licensed user says it could not list the PCs with no result', got is not None
              and 'allLicensedUsersAssignmentTarget' in got[3] and 'which does not mean they are clear' in got[3], out)
        n = names_of('exclusion')
        check('a PC in an exclusion group is not listed as no result yet', n is not None and 'PC-SILENT-2' not in n and 'PC-SILENT-1' in n, n)
        n = names_of('alldevices')
        check('an assignment to all devices lists every Windows PC with no result, and no Mac',
              n == sorted(['PC-HASROW', 'PC-SILENT-1', 'PC-SILENT-2', HOSTILE_NAME, SILENT_HOSTILE, 'PC-NOTINGROUP']), n)
        got, out = load_out(w, 'filter')
        check('an assignment filter is named in a note', got is not None and 'An assignment filter is set' in got[3] and 'Note: An assignment filter is set' in out, out)
        check('a target sent by the tenant reaches the console with no control character', '\x1b' not in out and 'oddTarget[2J' in out, out[-300:])
        got, out = load_out(w, 'membererror')
        check('a group whose members cannot be read says the PCs with no result there are not listed', got is not None
              and 'because its members could not be read' in got[3] and 'does not mean they are clear' in got[3] and sorted(got[2]) == ['PC-HASROW'], out)
        got, out = load_out(w, 'exclerror')
        check('an exclusion group whose members cannot be read says a PC listed may in fact be excluded', got is not None
              and 'Could not read the members of exclusion group g-excl' in got[3] and 'may in fact be excluded' in got[3]
              and 'PC-SILENT-2' in got[2], out)
        got, out = load_out(w, 'nodeviceid')
        check('PCs sent without their device id are counted, and the note names the tool and the command to run again', got is not None
              and 'Could not read 6 PCs in group g-eng. Allow Device.Read.All for gird-intune.ps1 and run gird-intune.ps1 -Export again.' in got[3]
              and '-Report' not in got[3] and sorted(got[2]) == ['PC-HASROW'], out)
        got, out = load_out(w, 'exclhidden')
        check('an exclusion group PC sent without its device id says a PC listed may in fact be excluded', got is not None
              and 'Could not read 1 PC in exclusion group g-excl' in got[3] and 'may in fact be excluded' in got[3], out)
        got, out = load_out(w, 'unassigned')
        check('a Remediation with no assignment says plainly it is assigned to no group', got is not None
              and 'assigned to no group' in out and 'assigned to no group' in got[3], out)
        check('a Remediation with no assignment never reads as 0 PCs', '0 PCs' not in out and got is not None and '<b>0</b>PCs' not in got[3], out)
    print('\n'.join(R))

main()
