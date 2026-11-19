"""Prints a fleet result (gird-fleet.sh --all-users) one value per line, for tests/run.sh to match:
key=value for the top level, accounts=N, <account>.<field>=value and machine.<field>=value, and for
the owasp object owasp.<count>=N, owasp.risks=<ids> and owasp.<id>.<field>=value. Lists are
space-separated; incidents are their ids."""
import json
import sys


def val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return " ".join(x["id"] if isinstance(x, dict) else str(x) for x in v)
    return str(v)


d = json.load(open(sys.argv[1]))
for k, v in d.items():
    if k == "accounts":
        print("accounts=%d" % len(v))
        for a in v:
            for f, x in a.items():
                if f != "account":
                    print("%s.%s=%s" % (a["account"], f, val(x)))
    elif k == "machine":
        for f, x in v.items():
            print("machine.%s=%s" % (f, val(x)))
    elif k == "owasp":
        for f, x in v.items():
            if f == "risks":
                print("owasp.risks=%s" % " ".join(r["id"] for r in x))
                for r in x:
                    for rf, rx in r.items():
                        if rf != "id":
                            print("owasp.%s.%s=%s" % (r["id"], rf, val(rx)))
            else:
                print("owasp.%s=%s" % (f, val(x)))
    else:
        print("%s=%s" % (k, val(v)))
