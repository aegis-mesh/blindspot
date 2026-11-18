# Builds key-shaped test files at run time, so no key-shaped string is ever committed: each fixed
# start below is split in two, and every key's body is random. Used by both suites.
#
#   python3 tests/make-keys.py corpus DIR N SEED
#     N files of keys of every type in data/keys.tsv, in many contexts (quotes, escapes, glued to a
#     word, one character apart, cut short or one too long), among base64 and other noise.
import os, random, sys, string, base64

AN = string.ascii_letters + string.digits
HEX = '0123456789abcdef'
B64 = AN + '+/'
URL = AN + '_-'
UP = string.ascii_uppercase + string.digits


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


if __name__ == '__main__':
    if sys.argv[1] == 'corpus':
        random.seed(int(sys.argv[4]))
        corpus(sys.argv[2], int(sys.argv[3]))
    else:
        sys.exit('usage: make-keys.py corpus DIR N SEED')
