# MITRE references in the fleet report

The report `gird-intune.ps1 -Report` builds can name, for each kind of finding, the MITRE ATT&CK
and MITRE ATLAS techniques it relates to. A security team reads its exposure in those terms and
reports coverage to leadership in them. This page says how the mapping is made and what it may
claim.

## What a reference says

Blindspot reads files. It never sees an attack and never detects a technique in use. So a reference
is one of three relations, and never "detected":

- **Exposure**: Blindspot found something the technique could exploit. A key in a file is what
  T1552.001 Unsecured Credentials: Credentials In Files collects. Nobody may ever have used it.
- **Indicator**: Blindspot found a file, package version or extension that a published incident
  links to the technique. It does not say when, or whether the malware ran.
- **Armed**: something is installed that carries the technique out when it is triggered. Only the
  gh-token-monitor wiper has it, for T1485 Data Destruction.

The report puts one paragraph above the first reference saying this, that the mapping is
Blindspot's own and not MITRE's, and that Blindspot does not detect any technique in use. Each CSV
row that carries a reference carries the same paragraph and the attribution.

## Where the mapping lives

`data/mitre.tsv`, one line per reference, keyed by the finding word the inventory value carries
(`keys`, `sessions`, `incidents` and the rest of `$ItemOrder` in `gird-intune.ps1`). `tools/gen.sh`
writes it into `gird-intune.ps1` between `# >>> mitre` and `# <<< mitre`, so the tool stays one file
an admin downloads. Nothing in the scripts a computer runs carries MITRE ids, so a new ATT&CK or
ATLAS release is a data change to the report tool alone.

`tools/gen.sh --check` refuses:

- a finding word with no `attack` line or no `atlas` line. A word that fits no technique gets a
  `none` line with the reason, which the report shows instead of a reference;
- a line whose word `gird-intune.ps1` does not know;
- a `none` line beside a mapped one for the same word and framework;
- a link that is not the technique's own page on attack.mitre.org or atlas.mitre.org, a technique
  named two ways, and a scope naming an incident `data/incidents.tsv` does not have.

The file's header records the ATT&CK and ATLAS versions and the date each id and name was read from
MITRE's pages.

## A reference only where the result supports it

A line can be narrower than its word:

- `os` `win` or `mac`: T1698 Indirect Prompt Injection lists SaaS and Windows as its platforms, so it
  is shown for Windows results only. T1543.001 Launch Agent is shown for a Mac's wiper only; on
  Windows the wiper Blindspot finds is a folder.
- `scope`: a list of incidents. The ATLAS supply chain techniques fit only the AI packages among
  the incidents (LiteLLM, mistralai, guardrails-ai, lightning, Mastra). The inventory value names the
  incidents for `incidents`, `lockfile`, `update` and `remove`, so the report shows such a reference
  only for a result that names one of them, and says which.

Where the value gives only a count (`planted`), an incident-level reference is left out.

## What the report shows

- For each kind of finding, its plain label, the number of PCs, then each reference that applies to
  at least one of them, linked to its MITRE page, or why there is none.
- A table by technique: the PCs with a finding that relates to it, each PC counted once per
  technique, and split by relation.
- What could get out: the PCs where an AI agent set to run commands without asking and a key in
  plain text are in the same account (with the providers the value names), the PCs with a key in an
  agent's session files, and the PCs with a token in an MCP config. Each counts what was found, never
  what happened. A PC whose result is missing, stale, cut to fit, unreadable, or partly checked is
  counted as not known, never as no.
- What the report covers and does not cover: the ATT&CK and ATLAS tactics of the mapped
  techniques, what Blindspot does not look at (the network, the identity provider, the cloud control
  plane, data platforms, what agents do while they run, malware not on its list), and the limits of
  the results read.

## Terms

ATT&CK's terms of use ask that a copy reproduce MITRE's copyright designation and its licence.
ATLAS is published under the Apache License 2.0. Both are in `NOTICE` and in the report's footer,
with the versions used.
