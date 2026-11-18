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

The page has eight numbered sections: 01 Summary, 02 What could get out, 03 Computers to deal with
first, 04 Findings by kind, 05 Summary by technique and function, 06 Computers not fully checked, 07 Every
computer and 08 Scope and method. Section 8 holds only text that is the same in every report; every
figure about the computers read is in sections 1 to 7. `Get-ReportData` works the figures out and
`Get-ReportPage` turns them into markup, escaping everything that came from an input file.

- Section 4, for each kind of finding: its label, the number of PCs, the relation, then each
  reference that applies to at least one of them, in a column per framework, linked to its MITRE
  page, or why there is none. Three labels carry an industry term, checked against its published
  definition: keys in plain text (unsecured credentials, MITRE ATT&CK T1552), an agent set to run
  commands without asking (excessive agency, OWASP LLM06:2025), and package versions from known
  software supply chain attacks. The term is on that row only; the lists of each computer's
  findings use the short label.
- Section 5, by technique and function: a bar for each technique a finding relates to, with the PCs
  counted once per technique in each relation; a bar for each NIST CSF 2.0 Function the findings
  relate to, with each PC counted once per Function; then the tactics of those techniques. On the
  page, CSF ids appear only here and in section 8, never on a finding's row. The CSV gives each
  computer's CSF outcomes in `nist_csf`, by the same rule, with the own-mapping sentence and NIST's
  citation beside them.
- What could get out: the PCs where an AI agent set to run commands without asking and a key in
  plain text are in the same account (with the providers the value names), the PCs with a key in an
  agent's session files, and the PCs with a token in an MCP config. Each counts what was found, never
  what happened. For each statement every computer in the report is exactly one of found, none
  found or not known, and the page shows all three counts, so they add up to the computers in the report.
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

  The computers in the report are the rows read: each row is counted as its own computer, and two
  rows are never joined, even when they share a name or a device id (an MDM device id, serial number
  or Entra device id column). Different computers can share one, such as a placeholder serial number
  like `To be filled by O.E.M.` or small ids from two MDMs, and joining them would drop one
  computer's findings. When a name or an id appears on more than one row, the limits say how many,
  and no outcome or count changes. An export with one row per computer gives the right totals.

  `Get-PathState` in `gird-report.ps1` is the table's one home. It is tested row by row in
  `tests/intune.py` (`PATHS`), with values the two writers write.
- Section 5 lists the ATT&CK and ATLAS tactics of the techniques the findings in this report relate
  to (none when nothing relates to one). Section 6 gives the limits of the results read. Section 8
  says what Blindspot does not look at (the network, the identity provider, the cloud control plane,
  data platforms, what agents do while they run, malware not on its list), every tactic a
  technique in `data/mitre.tsv` belongs to, and each CSF outcome the findings help an organization
  work toward, with its id and NIST's wording.

## NIST CSF 2.0

`data/mitre.tsv` also holds, for each finding word, a `csf` line: the CSF 2.0 Subcategory id, its
outcome as NIST CSWP 29 Appendix A words it, and its Function and Category, or `none` with the
reason (`platforms`, `on-open`, `partial`). `tools/gen.sh --check` refuses a word with no `csf` line,
an id whose Function or Category is not the one named, an outcome under Govern, Respond or Recover,
and a relation other than `supports`. The relation is
always that a finding helps an organization work toward the outcome on the computers where it was
found. The report never says an organization meets, misses or complies with the framework, and puts
the sentence that a reference does not say whether the organization meets the framework at the top
of section 5, above the first CSF reference, on every page. No finding kind shows an outcome is not
achieved: each Protect outcome turns on what the organization authorized or decided, which Blindspot
cannot see.

## Terms

ATT&CK's terms of use ask that a copy reproduce MITRE's copyright designation and its licence.
ATLAS is published under the Apache License 2.0, whose section 4 asks a redistribution to give the
licence (this repository's `LICENSE` is that text), to say what was changed, and to keep MITRE's
copyright notice; ATLAS's terms page adds its ATT&CK notice. NIST asks for its citation followed by
"Republished courtesy of the National Institute of Standards and Technology." All of it is in
`NOTICE`, and the copyright lines, citation and versions are in the report's attribution.
