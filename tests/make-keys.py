# Builds key-shaped test files at run time, so no key-shaped string is ever committed: each fixed
# start below is split in two, and every key's body is random. Used by both suites.
#
#   python3 tests/make-keys.py corpus DIR N SEED
#     N files of keys of every type in data/keys.tsv and their near misses, in many contexts (quotes, escapes, glued to a
#     word, one character apart, cut short or one too long), among base64 and other noise.
#   python3 tests/make-keys.py cases HOME MANIFEST KEYS "IDS" data/public-values.tsv
#     a .env file for each case of the key types in IDS, the manifest of what each must find, and the
#     keys written, one a line.
#   python3 tests/make-keys.py home HOME KEYS "IDS" SESSION
#     a home with one .env file for each key type in IDS and all of them in one agent session file
#     (SESSION, under HOME); prints the providers' names.
#   python3 tests/make-keys.py check MANIFEST FOUND
#     compares what a script found (CASE<tab>providers a line) with the manifest.
import os, random, sys, string, base64

AN = string.ascii_letters + string.digits
HEX = '0123456789abcdef'
B64 = AN + '+/'
URL = AN + '_-'
UP = string.ascii_uppercase + string.digits
DIG = string.digits


def r(cs, k): return ''.join(random.choice(cs) for _ in range(k))


def kinds():
    return {
        'anthropic': lambda: 'sk' '-ant-api03-' + r(URL, random.choice([85, 95, 100])),
        'openrouter': lambda: 'sk' '-or-v1-' + r(HEX, 64),
        'openai-long': lambda: 'sk' '-proj-' + r(URL, random.choice([120, 130, 156])),
        'openai-48': lambda: 'sk' '-proj-' + r(AN, 20) + 'T3Blb' 'kFJ' + r(AN, 20),
        'openai-legacy': lambda: 'sk' '-' + r(AN, 48),
        'openai-svc': lambda: 'sk' '-svcacct-' + r(URL, 70),
        'google': lambda: 'AI' 'za' + r(URL, 35),
        'google-aq': lambda: 'AQ' '.' + r(URL, 50),
        'groq': lambda: 'gs' 'k_' + r(AN, 52),
        'xai': lambda: 'xa' 'i-' + r(AN, 80),
        'huggingface': lambda: 'h' 'f_' + r(AN, 36),
        'perplexity': lambda: 'pp' 'lx-' + r(AN, 48),
        'replicate': lambda: 'r' '8_' + r(AN, 37),
        'aws': lambda: random.choice(['AK' 'IA', 'AS' 'IA']) + r(UP, 16),
        'aws-absk': lambda: 'AB' 'SKQmVkcm9ja0FQSUtleS' + r(B64, 80),
        'aws-bedrock': lambda: 'bedrock' '-api-key-' 'YmVkcm9jay5hbWF6b25hd3MuY29t' + r(B64, 144),
        'github': lambda: random.choice(['gh' 'p_', 'gh' 'o_', 'gh' 'u_', 'gh' 'r_']) + r(AN, 36),
        'github-ghs': lambda: 'gh' 's_' + r(AN, 36),
        'github-jwt': lambda: 'gh' 's_' + r(URL, 200) + '.' + r(URL, 200) + '.' + r(URL, 100),
        'github-pat': lambda: 'github' '_pat_' + r(AN, 22) + '_' + r(AN, 59),
        'npm': lambda: 'np' 'm_' + r(AN, 36),
    }


CONTEXTS = ['{}', '"{}"', 'KEY={}', 'export X="{}"', '\\n{}', '\\"{}\\"', ' {} ', '({})', '{}\n', 'word{}', '{}word',
            "'{}'", '={}&', ':{}.', '\\t{}', '`{}`', '<{}>', '{}=', '+{}', '/{}', '-{}', '_{}', '.{}', '~{}', '{}~', '?{}&']
NOISE = [lambda: base64.b64encode(os.urandom(random.randint(10, 400))).decode(),
         lambda: r(AN + ' _-./+=~:;&?%', random.randint(5, 200)),
         lambda: '"integrity": "sha512-' + base64.b64encode(os.urandom(64)).decode() + '"',
         lambda: 'risk-' + r(AN, 48) + ' disk-free ~2.6.0']


def corpus(out, n):
    g = kinds()
    for i, (_, makers, near) in new_kinds().items():
        for j, (mk, _) in enumerate(makers):
            g['%s-%d' % (i, j)] = mk
        for j, (_, mk) in enumerate(near):
            g['%s-near-%d' % (i, j)] = mk
    names = sorted(g)
    os.makedirs(out, exist_ok=True)
    for i in range(n):
        parts = []
        for _ in range(random.randint(1, 12)):
            x = random.random()
            if x < 0.55:
                k = g[random.choice(names)]()
                if random.random() < 0.2:
                    k = k[:-1] if random.random() < 0.5 else k + random.choice(AN)
                parts.append(random.choice(CONTEXTS).format(k))
            elif x < 0.7:
                parts.append(g[random.choice(names)]() + random.choice(['', ' ', '.', '-', '_', '~', '=', '&', '\\n']) + g[random.choice(names)]())
            else:
                parts.append(random.choice(NOISE)())
        sep = random.choice(['', ' ', '\n', ',', '\\n'])
        with open(os.path.join(out, 'f%05d.txt' % i), 'w') as f:
            f.write(sep.join(parts) + random.choice(['', '\n']))


# The new key types: for each, keys in many places (cases), near misses that are not keys, and
# published example values (built from data/public-values.tsv and random characters). A case is a
# file and the provider the scripts must name in it, or - for none.
def sas(order='sv', long=False):
    sig = 'sig=' + r(AN, 40) + '%2B' + r(AN, 3) + '%3D'
    q = 'sv=2024-11-04&ss=b&srt=sco&sp=rl&se=2026-01-01T00%3A00%3A00Z&spr=https'
    if long:
        q = 'sv=2024-11-04&sr=c&sp=rl&skoid=' + r(HEX, 8) + '-' + r(HEX, 4) + '-' + r(HEX, 4) + '-' + r(HEX, 4) + '-' + r(HEX, 12) + \
            '&sktid=' + r(HEX, 8) + '-' + r(HEX, 4) + '-' + r(HEX, 4) + '-' + r(HEX, 4) + '-' + r(HEX, 12) + \
            '&skt=2026-01-01T00%3A00%3A00Z&ske=2026-01-02T00%3A00%3A00Z&sks=b&skv=2024-11-04&st=2026-01-01T00%3A00%3A00Z&se=2026-01-02T00%3A00%3A00Z&spr=https'
    return 'https://' + r(string.ascii_lowercase, 10) + '.blob.core.windows.net/c/f.txt?' + (q + '&' + sig if order == 'sv' else sig + '&' + q)


def msft(tag):
    return r(AN, 52) + 'JQQ' 'J99' + r(AN, 1) + random.choice('ABCDEFGHIJKL') + r(AN, 12) + tag + r(AN, 4)


def b64n(k): return ''.join(random.choice(AN + '+/') for _ in range(k))


def storage_cs(key): return 'DefaultEndpointsProtocol=https;AccountName=' + r(string.ascii_lowercase, 12) + ';Account' 'Key=' + key + ';EndpointSuffix=core.windows.net'


def new_kinds():
    """id: (name, [(maker of a key, kept)], [(label, near miss)]), where kept says the key's own text
    carries what makes it a key, so it still counts glued to a word and inside base64 (1), or only
    glued to a word in front (2)."""
    U2 = URL + '.~'
    return {
        'azureentra': ('Microsoft Entra', [(lambda: r(U2, 3) + random.choice('78') + 'Q' '~' + r(U2, 34), 0), (lambda: r(U2, 3) + '8Q' '~' + r(U2, 31), 0)],
                       [('digit 6', lambda: r(U2, 3) + '6Q' '~' + r(U2, 34)), ('30 after', lambda: r(U2, 3) + '8Q' '~' + r(U2, 30)),
                        ('35 after', lambda: r(U2, 3) + '8Q' '~' + r(U2, 35))]),
        'azuredevops': ('Azure DevOps', [(lambda: msft('AAAAA' 'ZDO'), 0), (lambda: msft('AAAAA' 'ZDO') + r(AN, 2) + '==', 0)],
                        [('no JQQJ99', lambda: r(AN, 52) + 'XQQ' 'J99' + r(AN, 14) + 'AAAAA' 'ZDO' + r(AN, 4)),
                         ('51 before', lambda: msft('AAAAA' 'ZDO')[1:]), ('documented example shape', lambda: r(AN, 76) + 'AZ' 'DO' + r(AN, 4))]),
        'azureai': ('Azure AI', [(lambda: msft('AAA' + random.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZabdefghijklmno') + 'ACOG'), 0)],
                    [('Microsoft dummy', lambda: msft('AAA' 'cACOG')), ('past o', lambda: msft('AAA' 'pACOG'))]),
        'azurestorage': ('Azure Storage', [(lambda: b64n(76) + '+A' 'St' + b64n(5) + random.choice('AQgw') + '==', 0), (lambda: storage_cs(b64n(86) + '=='), 1)],
                         [('no +ASt', lambda: b64n(86) + '=='), ('85 in a connection string', lambda: storage_cs(b64n(85) + '==')),
                          ('Cosmos DB', lambda: 'AccountEndpoint=https://x.documents.azure.com:443/;Account' 'Key=' + b64n(86) + '==;'),
                          ('lowercase', lambda: storage_cs(b64n(86) + '==').replace('AccountKey', 'accountkey'))]),
        'azuresas': ('Azure Storage SAS', [(lambda: sas('sv'), 1), (lambda: sas('sig'), 1), (lambda: sas('sv', True), 1)],
                     [('sv=1.0', lambda: 'https://x.logic.azure.com/workflows/' + r(HEX, 32) + '/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=' + r(URL, 43)),
                      ('Service Bus', lambda: 'SharedAccessSignature sr=https%3A%2F%2Fx.servicebus.windows.net&sig=' + r(AN, 43) + '%3D&se=1700000000&skn=RootManageSharedAccessKey'),
                      ('42 sig', lambda: 'https://x.blob.core.windows.net/c?sv=2024-11-04&sp=r&sig=' + r(AN, 42))]),
        'databricks': ('Databricks', [(lambda: 'da' 'pi' + r(HEX, 32), 0), (lambda: 'da' 'pi' + r(HEX, 32) + '-2', 0)],
                       [('upper-case hex', lambda: 'da' 'pi' + r('0123456789ABCDEF', 32)), ('31 hex', lambda: 'da' 'pi' + r(HEX, 31))]),
        'gitlab': ('GitLab', [(lambda: random.choice(['gl' 'pat-', 'gl' 'dt-', 'gl' 'rt-', 'gl' 'ft-', 'gl' 'soat-']) + r(URL, 20), 0)],
                   [('19', lambda: 'gl' 'pat-' + r(URL, 19)), ('21', lambda: 'gl' 'pat-' + r(URL, 21)), ('feed token prefix glf', lambda: 'gl' 'f-' + r(URL, 20))]),
        'slack': ('Slack', [(lambda: random.choice(['xo' 'xb-', 'xo' 'xp-']) + r(DIG, 11) + '-' + r(DIG, 12) + '-' + r(AN, 24), 0),
                            (lambda: random.choice(['', 'xo' 'xe.']) + 'xa' 'pp-1-A' + r(UP, 10) + '-' + r(DIG, 13) + '-' + r(HEX, 64), 0),
                            (lambda: 'https://hooks.sl' 'ack.com/services/T' + r(UP, 10) + '/B' + r(UP, 10) + '/' + r(AN, 24), 2)],
                  [('short parts, as in the docs', lambda: 'xo' 'xp-' + r(DIG, 3) + '-' + r(DIG, 3) + '-' + r(DIG, 3) + '-' + r(HEX, 32)),
                   ('webhook of 23', lambda: 'https://hooks.sl' 'ack.com/services/T' + r(UP, 10) + '/B' + r(UP, 10) + '/' + r(AN, 23)),
                   ('workflow token', lambda: 'xw' 'fp-' + r(DIG, 11) + '-' + r(DIG, 12) + '-' + r(AN, 24))]),
        'stripe': ('Stripe', [(lambda: random.choice(['sk' '_live_', 'rk' '_live_']) + r(AN, 99), 0), (lambda: 'wh' 'sec_' + r(AN, 32), 0)],
                   [('test key', lambda: 'sk' '_test_' + r(AN, 99)), ('publishable', lambda: 'pk' '_live_' + r(AN, 99)), ('19', lambda: 'sk' '_live_' + r(AN, 19))]),
        'sendgrid': ('SendGrid', [(lambda: 'S' 'G.' + r(URL, 22) + '.' + r(URL, 43), 0)],
                     [('42 after', lambda: 'S' 'G.' + r(URL, 22) + '.' + r(URL, 42)), ('in a longer dotted name', lambda: 'S' 'G.' + r(URL, 22) + '.' + r(URL, 43) + '.' + r(URL, 5))]),
        'pypi': ('PyPI', [(lambda: 'py' 'pi-AgEIcHlwaS5vcmc' + r(URL, 150), 0), (lambda: 'py' 'pi-AgEIcHlwaS5vcmc' + r(URL, 300), 0)],
                 [('TestPyPI', lambda: 'py' 'pi-AgENdGVzdC5weXBpLm9yZw' + r(URL, 150)), ('69 after', lambda: 'py' 'pi-AgEIcHlwaS5vcmc' + r(URL, 69))]),
        'dockerhub': ('Docker Hub', [(lambda: 'dckr' '_pat_' + r(URL, 27), 0)],
                      [('organization token', lambda: 'dckr' '_oat_' + r(URL, 27)), ('26', lambda: 'dckr' '_pat_' + r(URL, 26))]),
        'digitalocean': ('DigitalOcean', [(lambda: random.choice(['do' 'p_v1_', 'do' 'o_v1_', 'do' 'r_v1_']) + r(HEX, 64), 0)],
                         [('63 hex', lambda: 'do' 'p_v1_' + r(HEX, 63)), ('upper-case hex', lambda: 'do' 'p_v1_' + r('0123456789ABCDEF', 64))]),
        'vault': ('HashiCorp Vault', [(lambda: 'hv' 's.' + r(URL, 95), 0)],
                  [('28, as in the docs', lambda: 'hv' 's.' + r(URL, 24)), ('89', lambda: 'hv' 's.' + r(URL, 89)), ('batch token', lambda: 'hv' 'b.' + r(URL, 120))]),
        'nvidia': ('NVIDIA', [(lambda: 'nv' 'api-' + r(URL, 64), 0)], [('63', lambda: 'nv' 'api-' + r(URL, 63)), ('65', lambda: 'nv' 'api-' + r(URL, 65))]),
        'langsmith': ('LangSmith', [(lambda: random.choice(['lsv2' '_pt_', 'lsv2' '_sk_']) + r(HEX, 32) + '_' + r(HEX, 10), 0)],
                      [('trace token', lambda: 'lsv2' '_tr_' + r(HEX, 32) + '_' + r(HEX, 10)), ('9 hex', lambda: 'lsv2' '_pt_' + r(HEX, 32) + '_' + r(HEX, 9))]),
        'shopify': ('Shopify', [(lambda: random.choice(['shp' 'at_', 'shp' 'pa_']) + r(HEX, 32), 0)],
                    [('custom app prefix', lambda: 'shp' 'ca_' + r(HEX, 32)), ('31 hex', lambda: 'shp' 'at_' + r(HEX, 31))]),
        'sentry': ('Sentry', [(lambda: 'sntr' 'yu_' + r(HEX, 64), 0), (lambda: 'sntr' 'ys_' + 'eyJ' + r(B64, 200) + '_' + r(B64, 43), 0)],
                   [('63 hex', lambda: 'sntr' 'yu_' + r(HEX, 63)), ('a DSN', lambda: 'https://' + r(HEX, 32) + '@o' + r(DIG, 6) + '.ingest.sentry.io/' + r(DIG, 7))]),
        'supabase': ('Supabase', [(lambda: 'sb' '_secret_' + r(URL.replace('_', ''), 22) + '_' + r(URL.replace('_', ''), 8), 0)],
                     [('publishable', lambda: 'sb' '_publishable_' + r(AN, 22) + '_' + r(AN, 8)), ('21', lambda: 'sb' '_secret_' + r(AN, 21) + '_' + r(AN, 8))]),
        'onepassword': ('1Password', [(lambda: 'op' 's_eyJ' + r(B64, 620), 0)], [('short', lambda: 'op' 's_eyJ' + r(B64, 200))]),
    }


def public_cases(pv):
    """Published values from data/public-values.tsv, completed with random characters."""
    out = []
    for line in open(pv):
        if line.startswith('#') or not line.strip():
            continue
        i, part, _ = line.rstrip('\n').split('\t')
        if i == 'azurestorage':
            out.append((i, 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;Account' 'Key=' + part + b64n(86 - len(part)) + '==;'))
        elif i == 'azuresas':
            out.append((i, 'SharedAccessSignature=sv=2015-04-05&sr=b&si=tutorial-policy-635959936145100803&sig=' + part + r(AN, 8) + '%3D'))
            out.append((i, 'SharedAccessSignature=sv=2015-07-08&sig=' + part + r(AN, 4) + '%3D&spr=https&st=2016-04-12T03%3A24%3A31Z'))
        elif i == 'slack':
            out.append((i, 'xo' 'xb-17653672481-' + part))
    return out


def cases(home, manifest, keys, ids, pv):
    """One .env file a case, in HOME/code/CASE/, and the manifest: CASE<tab>provider or -."""
    kinds = {k: v for k, v in new_kinds().items() if k in ids}
    rows, made = [], []

    def put(case, text, want):
        d = os.path.join(home, 'code', case)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, '.env'), 'w') as f:
            f.write(text)
        rows.append(case + '\t' + want)

    for i, (name, makers, near) in sorted(kinds.items()):
        for j, (mk, ctx) in enumerate(makers):
            for where, fmt in [('start', '{}\n'), ('mid', 'X_KEY=a {} b\n'), ('esc', '{{"a":"x\\n{}\\ny"}}\n'), ('quote', '{{"a":"x \\"{}\\" y"}}\n')]:
                k = mk(); made.append(k); put('%s-%d-%s' % (i, j, where), fmt.format(k), name)
            # Inside base64: the Azure keys are base64 text themselves; any other key starts with
            # characters base64 never holds, so it is put among letters and digits instead.
            pad = b64n if i.startswith('azure') else (lambda n: r(AN, n))
            k = mk(); made.append(k)
            put('%s-%d-base64' % (i, j), '{"data":"' + pad(40) + k + pad(40) + '"}\n', name if ctx == 1 else '-')
            k = mk(); made.append(k)
            put('%s-%d-glued' % (i, j), 'TOKEN=word' + k + '\n', name if ctx else '-')
        for j, (label, mk) in enumerate(near):
            k = mk(); made.append(k)
            put('%s-near-%d' % (i, j), 'X_KEY=' + k + '\n', '-')
    for j, (i, text) in enumerate(public_cases(pv)):
        if i in kinds:
            put('%s-public-%d' % (i, j), 'X=' + text + '\n', '-')
    # A key of a later pass glued to an older one, or one character before it, never hides it: the
    # older type's own pass finds it, and it is named first.
    near_old = [
        ('azuresas', 'OpenAI', 'https://x.blob.core.windows.net/c?sv=2024-11-04&sp=r&sig=' + r(AN, 42) + 'sk' '-proj-' + r(AN, 20) + 'T3Blb' 'kFJ' + r(AN, 20)),
        ('azurestorage', 'Google', 'AccountName=' + r(string.ascii_lowercase, 8) + ';Account' 'Key=' + b64n(86) + '==' + 'AI' 'za' + r(URL, 35)),
        ('databricks', 'Hugging Face', 'da' 'pi' + r(HEX, 32) + ' ' + 'h' 'f_' + r(AN, 36)),
    ]
    for j, (i, old, text) in enumerate(near_old):
        if i in kinds:
            made.append(text); put('%s-before-old-%d' % (i, j), text + '\n', old + ', ' + kinds[i][0])
    with open(manifest, 'w') as f:
        f.write('\n'.join(rows) + '\n')
    with open(keys, 'w') as f:
        f.write('\n'.join(made) + '\n')


def home(h, keys, ids, sess):
    """One .env file for each key type in IDS, in HOME/code/ID/, and every key in one agent session
    file at SESS under HOME, each after an escaped newline. Prints the providers' names."""
    kinds = {k: v for k, v in new_kinds().items() if k in ids}
    made, lines = [], []
    for i, (name, makers, _) in sorted(kinds.items()):
        k = makers[0][0](); made.append(k)
        d = os.path.join(h, 'code', i); os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, '.env'), 'w') as f:
            f.write('X_KEY=' + k + '\n')
        k = makers[-1][0](); made.append(k); lines.append(k)
        print(name)
    d = os.path.join(h, os.path.dirname(sess)); os.makedirs(d, exist_ok=True)
    with open(os.path.join(h, sess), 'w') as f:
        f.write('{"t":"' + ''.join('x\\n' + k + '\\n' for k in lines) + '"}\n')
    with open(keys, 'w') as f:
        f.write('\n'.join(made) + '\n')


def check(manifest, found):
    """found: CASE<tab>providers, one a line, from the script. Prints what does not match."""
    got = {}
    for line in open(found):
        c, _, p = line.rstrip('\n').partition('\t')
        got[c] = p
    bad = 0
    for line in open(manifest):
        c, want = line.rstrip('\n').split('\t')
        have = got.get(c, '')
        if (want == '-' and have) or (want != '-' and have != want):
            print('%s: want %s, got %s' % (c, want, have or 'none')); bad += 1
    return bad


if __name__ == '__main__':
    if sys.argv[1] == 'corpus':
        random.seed(int(sys.argv[4]))
        corpus(sys.argv[2], int(sys.argv[3]))
    elif sys.argv[1] == 'cases':
        cases(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5].split(), sys.argv[6])
    elif sys.argv[1] == 'home':
        home(sys.argv[2], sys.argv[3], sys.argv[4].split(), sys.argv[5])
    elif sys.argv[1] == 'check':
        sys.exit(1 if check(sys.argv[2], sys.argv[3]) else 0)
    else:
        sys.exit('usage: make-keys.py corpus DIR N SEED | cases HOME MANIFEST KEYS "IDS" PUBLIC_VALUES | home HOME KEYS "IDS" SESSION | check MANIFEST FOUND')
