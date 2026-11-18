# MITRE references in the fleet report

The report `gird-report.ps1` builds can name, for each kind of finding, the MITRE ATT&CK
and MITRE ATLAS techniques it relates to. A security team reads its exposure in those terms and
reports coverage to leadership in them. This page says how the mapping is made and what it may
claim.

## What a reference says

Blindspot reads files. It never sees an attack and never detects a technique in use. So a reference
is one of two relations, and never "detected":

- **Exposure**: Blindspot found something the technique could exploit. A key in a file is what
  T1552.001 Unsecured Credentials: Credentials In Files collects. Nobody may ever have used it.
- **Indicator**: Blindspot found a file, package version or extension that a published incident
  links to the technique. It does not say when, or whether the malware ran.

A reference goes in only when the result line itself carries enough to know the technique applies to
that finding, on that system. The gh-token-monitor wiper is an indicator of T1485 Data Destruction,
not a sign it is set to run: the wiper finding is any one of its files, a script or a config folder
included, and the result does not say which.

The report puts one paragraph above the first reference saying this, that the mapping is
Blindspot's own and not MITRE's, and that Blindspot does not detect any technique in use. Each CSV
row that carries a reference carries the same paragraph and the attribution.

## Where the mapping lives

`data/mitre.tsv`, one line per reference, keyed by the finding word the inventory value carries
(`keys`, `sessions`, `incidents` and the rest of `$Items` in `gird-report.ps1`, the one home of each
finding word's form, level and label). `tools/gen.sh` writes it into `gird-report.ps1` between
`# >>> mitre` and `# <<< mitre`, so the tool stays one file an admin downloads. Nothing in the scripts a computer runs carries MITRE ids, so a new ATT&CK or
ATLAS release is a data change to the report tool alone.

`tools/gen.sh --check` refuses:

- a finding word with no `attack` line or no `atlas` line. A word that fits no technique gets a
  `none` line with the reason, which the report shows instead of a reference;
- a line whose word `gird-report.ps1` does not know, and an `$Items` line whose form or level it
  cannot read;
- a `none` line beside a mapped one for the same word and framework;
- a link that is not the technique's own page on attack.mitre.org or atlas.mitre.org, a technique
  named two ways, and a scope naming an incident `data/incidents.tsv` does not have.

The file's header records the ATT&CK and ATLAS versions and the date each id and name was read from
MITRE's pages, and each reference left out on purpose with the reason.

## A reference only where the result supports it

A line can be narrower than its word:

- `os` `win` or `mac`: T1698 Indirect Prompt Injection lists SaaS and Windows as its platforms, so it
  is shown for Windows results only. T1098.004 SSH Authorized Keys does not list Windows, so it is
  shown for Mac results only.
- `scope`: a list of incidents. The ATLAS supply chain techniques fit only the AI packages among
  the incidents (LiteLLM, mistralai, guardrails-ai, lightning, Mastra). The inventory value names the
  incidents for `incidents`, `lockfile`, `update` and `remove`, so the report shows such a reference
  only for a result that names one of them, and says which.

Where the value gives only a count (`planted`), an incident-level reference is left out. Where it
does not say which file was found, a reference that fits only one of them is left out: T1543.001
Launch Agent for the wiper. Where the count takes in things the technique is not about, the word
gets no reference: `on-open` counts editor tasks as well as agent settings, and a person's own
settings as well as ones that came in a cloned project.

## What the report shows

- For each kind of finding, its plain label, the number of PCs, then each reference that applies to
  at least one of them, linked to its MITRE page, or why there is none.
- A table by technique: the PCs with a finding that relates to it, each PC counted once per
  technique, and split by relation.
- What could get out: the PCs where an AI agent set to run commands without asking and a key in
  plain text are in the same account (with the providers the value names), the PCs with a key in an
  agent's session files, and the PCs with a token in an MCP config. Each counts what was found, never
  what happened. For each statement every computer in the report is exactly one of found, none
  found or not known, and the page shows all three counts, so they add up to the computers read.
  None found speaks for the accounts the result read, and only when each of them was read in full:

  | The computer's result | Each statement |
  |---|---|
  | none, empty, `stale: ...`, `failed: ...`, `unreadable`, older than `-StaleDays`, dated ahead, a value that does not fit, a newer version or finding word, cut at 2,048 characters | not known |
  | outcome `failed` (a Windows `reason=`, or a Mac account whose script copy changed) | found if an account shows it, else not known |
  | ends in `+more` | found if an account shows it, else not known |
  | an account `not_checked`, or `no accounts` | found if an account shows it, else not known |
  | an account carrying `partial`, whatever its outcome (`act ...; partial` too) | found if an account shows it, else not known |
  | every account read in full (the Mac's own row does not count: it carries none of these items) | found or none found |

  `other_profiles=` above 0 does not change a computer's state: those profiles are not in the
  result. Under each statement the page says how many of the computers with none found have other
  accounts that were not read. That number is per statement, because a computer can be none found
  for one statement and found for another.

  Two rows are one computer only when they share a device id (an MDM device id, serial number or
  Entra device id column, matched exactly; a placeholder such as the all-zero id is ignored). The
  newer result stands, and on the same date the one that needs more attention. Rows that share only
  a name are counted as separate computers, and the limits say how many names repeat.

  `Get-PathState` in `gird-report.ps1` is the table's one home. It is tested row by row in
  `tests/intune.py` (`PATHS`), with values the two writers write.
- What the report covers and does not cover: the ATT&CK and ATLAS tactics of the techniques the
  findings in this report relate to (none when nothing relates to one), what Blindspot does not look
  at (the network, the identity provider, the cloud control plane, data platforms, what agents do
  while they run, malware not on its list), and the limits of the results read.

## Terms

ATT&CK's terms of use ask that a copy reproduce MITRE's copyright designation and its licence.
ATLAS is published under the Apache License 2.0, whose section 4 asks a redistribution to give the
licence (this repository's `LICENSE` is that text), to say what was changed, and to keep MITRE's
copyright notice; ATLAS's terms page adds its ATT&CK notice. All of it is in `NOTICE`, and the
copyright lines and versions are in the report's footer.
