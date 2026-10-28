# OWASP Agentic Top 10 tags

Status: design, not built. Nothing in the scripts, tests or docs has changed yet.

## Why

Security teams sort findings by a shared list of risks. For AI agents that list is the OWASP Top 10
for Agentic Applications (2026). Today a Blindspot finding says what was found and what to do, but
not which of those risks it falls under. This design adds a tag to every surface that shows
findings, so a person or an IT team can say "this Mac has an ASI03 finding" without reading the
whole report first.

The tags are Blindspot's own mapping from its findings to OWASP's list. OWASP does not publish a
mapping for Blindspot, and a tag is never a claim of OWASP compliance.

## The risks

Source: OWASP GenAI Security Project, "OWASP Top 10 for Agentic Applications for 2026", published
9 December 2025:
<https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/>. The resource
page itself lists no names; it links to a download. The names below come from OWASP's announcement
(<https://genai.owasp.org/2025/12/09/owasp-top-10-for-agentic-applications-the-benchmark-for-agentic-security-in-the-age-of-autonomous-ai/>)
and OWASP's Q3 2026 exploit round-up
(<https://genai.owasp.org/2026/10/08/genai-and-agentic-ai-exploit-roundup-q3-2026/>), both read on
28 October 2026. The downloadable document was not read.

| Code | Name (as Blindspot prints it) | Blindspot tags it |
|---|---|---|
| ASI01 | Agent Goal Hijack | no |
| ASI02 | Tool Misuse and Exploitation | yes |
| ASI03 | Identity and Privilege Abuse | yes |
| ASI04 | Agentic Supply Chain Vulnerabilities | yes |
| ASI05 | Unexpected Code Execution | yes |
| ASI06 | Memory and Context Poisoning | no |
| ASI07 | Insecure Inter-Agent Communication | no |
| ASI08 | Cascading Failures | no |
| ASI09 | Human-Agent Trust Exploitation | no |
| ASI10 | Rogue Agents | no |

- OWASP writes "&" in some places ("Identity & Privilege Abuse") and "and" in others. Blindspot
  prints "and": the scripts are ASCII, and "&" is a special character in PowerShell and in shell code.
- ASI02 is "Tool Misuse" in the December 2025 announcement and "Tool Misuse and Exploitation" in
  the Q3 2026 round-up. This design uses the longer name (see Open questions).
- Blindspot reads files on disk. It does not watch what an agent does, so it never tags ASI01 or
  ASI06 to ASI10. The README says so, so that a missing tag is not read as "not affected".

## Rules

1. **By finding, not by check.** A risk is tagged only where there is a finding of a kind that maps
   to it. A check that ran and found nothing tags nothing. The tag is never "none", "0" or "clear".
2. **One risk per finding kind.** Each kind maps to one risk or to none. The mapping lives in one
   data file.
3. **A lead is not a finding.** Possible signs, files named like a worm's with nothing else of it,
   and markers in the shared `/tmp` are things to check. They carry no tag (Open questions, 2).
4. **Completeness is never a risk.** Partly checked, unreadable, not checked and the like carry no
   tag. A partly checked report or account with no tags never reads as having no risks: every
   surface leaves the OWASP part out when nothing is tagged. It does not say "no risks found".
5. **Nothing new leaves the machine.** No surface sends a tag anywhere (see What is sent to gird.ai).

## Every finding kind, and its risk

The kinds are the fields the account run sends to root (`FL_KEYS` in `gird-fleet.sh`; written by
the account run in `gird-check.sh` at the `if [ "$ACCTRUN" -eq 1 ]` block), the Mac's own fields
(`fl_machine`), and what only the person's report shows. The `kind` is the field's name in the
fleet JSON, so an admin can find it in `last.json`.

| kind (JSON field) | source | risk | label | section |
|---|---|---|---|---|
| `agents_run_without_asking` | `yolo` | ASI02 | run without asking | 01 |
| `tools_to_update` | `tools` | ASI04 | tools with a security fix | 01 |
| `mcp_token_files` | `mcp_token_files` | ASI03 | tokens in MCP configs | 02 |
| `authorized_keys_links` | `ak_links` | ASI03 | links to authorized_keys | 02 |
| `project_settings_on_open` | `on_open` | ASI05 | settings that act on opening | 02 |
| `key_files` | `key_files` | ASI03 | keys in plain text | 03 |
| `history_keys` | `history_keys` | ASI03 | keys in shell history | 03 |
| `session_files_with_keys` | `session_files` | ASI03 | keys in agent sessions | 03 |
| `ssh_keys_no_passphrase` | `ssh_open` | ASI03 | SSH keys without a passphrase | 03 |
| `allow_list_keys` | `allow_list_keys` | ASI03 | keys in allow lists | 04 |
| `incidents` | `incidents:act` | ASI04 | malware signs | 05 |
| `incidents_to_update` | `incidents:update` | ASI04 | versions to update | 05 |
| `wiper` | `wiper` | ASI04 | gh-token-monitor | 05 |
| `planted_files` | `planted` | ASI04 | files a worm plants | 05 |
| `lockfile_only_incidents` | `lock_only` | ASI04 | npm malware in a lockfile | 05 |
| `versions_to_update` | `updates` | ASI04 | Python versions to update | 05 |
| `extensions_to_remove` | `remove` | ASI04 | extensions to remove | 05 |
| `platforms_found` | `platforms` | ASI04 | platforms that leaked secrets | 05 |
| `machine.incidents` | `machine:incidents` | ASI04 | malware signs | (fleet only) |

No risk, each with its reason:

| kind | source | why no risk |
|---|---|---|
| `possible_signs` | `possible` | A lead to check (a LiteLLM leftover with nothing else of it, a startup file named like an extension incident's with no such extension), not a sign. |
| `files_to_read` | `to_read` | A name match only. Projects use some of these names (`setup.mjs`). |
| `shared_tmp_markers` | `tmp_marks` | A lead: another account can link a file there. |
| `shared_tmp_wiper_logs` | `tmp_wiper` | A lead, as above. |
| `machine.possible_signs` | `machine:possible_signs` | A lead, as above. |
| `machine.shared_tmp_wiper_logs` | `machine:shared_tmp_wiper_logs` | A lead, as above. |
| `agents`, `machine.agents` | `agents` | What is installed, not a finding. |
| `mcp_servers` | `mcp_servers` | A count of servers, not a finding. |
| `key_providers` | `key_providers` | Detail of `key_files`, which is tagged. |
| `sessions_partly_checked`, `files_not_checked`, `agent_folders_moved`, `protected_folders`, `session_engine` | `sessions_partial`, `not_read`, `moved`, `protected`, `engine` | Completeness. Rule 4. |
| (protocol) | `v`, `end` | Protocol lines. |
| idle agents (row 01, fix "Remove agents you no longer use") | `report` | Housekeeping. An idle agent is not itself a finding of any risk, and root does not receive it. |
| login files any agent can read (section 03) | `report` | Shown for information, not counted as a finding (no fix, not in `ISSUES`, not sent to root). Nearly every developer machine has some. |
| tools with a published hole and no fixed version yet (section 01) | `report` | Not counted as a finding today (row 01 and the fix list count only tools with a fix), and root does not receive it. See Open questions, 3. |

Two corrections to the draft mapping, from the code:

- "SSH keys without a passphrase / login files agents can read": only the passphrase-less SSH key
  is a finding (`N_SSH_OPEN` has a fix, and is sent to root as `ssh_open`). Login files are a
  listing, so they carry no tag.
- "malware signs/incidents": the account run's `incidents` field holds both levels. An update-level
  incident (Mistral's and UiPath's npm builds, the Injective SDK) is not a sign of malware, so it
  gets its own kind and label (`incidents_to_update`, "versions to update"). Both are ASI04.

## One source of truth: `data/owasp.tsv`

One line per finding kind, tab-separated, described in the file's header like the other data
files:

```
# kind	risk	name	label	section	source	why
key_files	ASI03	Identity and Privilege Abuse	keys in plain text	03	key_files	-
possible_signs	-	-	-	-	possible	A lead to check, not a sign.
```

| Column | Rule `tools/gen.sh` enforces |
|---|---|
| `kind` | `^[a-z0-9_.]+$`, unique. The fleet JSON field name. |
| `risk` | `ASI01` to `ASI10`, or `-` for no risk. |
| `name` | The risk's name; every line of one risk must give the same name (as `data/outdated.tsv` does for a tool's name). `-` when `risk` is `-`. No `' " \` $ | \` or `&`. |
| `label` | At most 32 characters, lowercase start, none of the characters above. `-` when `risk` is `-`. |
| `section` | `01` to `05` for a kind the person's report shows; `-` for a machine kind or no risk. |
| `source` | A key in `FL_KEYS` (read from `gird-fleet.sh`), `incidents:act` or `incidents:update`, `machine:<field>` for the Mac's own fields, or `report` for what only the person's report shows. |
| `why` | Required, and the only place it is allowed, when `risk` is `-`. |

`gen.sh` also refuses: a completeness or protocol key (`v`, `end`, `sessions_partial`, `not_read`,
`moved`, `protected`, `engine`) with a risk, and a `report` line with a risk (root could not see it,
so the two reports would disagree). It requires every key in `FL_KEYS` to have exactly one line, so a
new account-run field cannot ship without a decision on its risk.

### What `gen.sh` writes

A new block `owasp` in all three scripts, from the lines with a risk only:

- `gird-check.sh` and `gird-fleet.sh` (the same text):

  ```bash
  # >>> owasp: generated from data/owasp.tsv by tools/gen.sh. Edit that file, then run it.
  OWASP_TABLE="agents_run_without_asking|ASI02|Tool Misuse and Exploitation|run without asking|01|yolo
  ...
  incidents|ASI04|Agentic Supply Chain Vulnerabilities|malware signs|05|incidents:act"
  # <<< owasp
  ```

- `gird-check.ps1`:

  ```powershell
  # >>> owasp: generated from data/owasp.tsv by tools/gen.sh. Edit that file, then run it.
  $OwaspTable = @(
    ,@('agents_run_without_asking', 'ASI02', 'Tool Misuse and Exploitation', 'run without asking', '01', 'yolo')
  )
  # <<< owasp
  ```

`gird-fleet.sh` already receives generated blocks: the `for f in gird-check.sh gird-check.ps1
gird-fleet.sh` loop at the end of `tools/gen.sh` splices `owned-walk keys auto-approve agents
incidents indicators outdated platforms` into it. `owasp` is added to both block lists, and to the
two lists of data files in `gen.sh`'s header comment and in CONTRIBUTING.md's "Lists live in
`data/`".

### One derivation, copied to root

The rule that turns field values into kinds is one function, `owasp_kinds`, whose home is
`gird-check.sh` in a block `owasp-derive`. `gen.sh` copies it into `gird-fleet.sh` the way it copies
`owned-walk`. Given a variable prefix, it walks `OWASP_TABLE` and prints each kind whose source
field is set: a number above 0, a non-empty list, or for `incidents:act` / `incidents:update` an id
of that level (`incident_level`, already in both scripts).

- In `gird-check.sh`, the values the account run computes (`_yolo`, `_inc`, `_lock`, `_planted` and
  the rest, now inside the `ACCTRUN` block) move into a function that sets `F_<key>` for each finding
  field. The account run prints from those variables, so its output is byte for byte what it is
  today, and the person's report tags from the same values. The `moved` profile walk stays inside
  the account run: it is completeness only.
- In `gird-fleet.sh`, `fl_parse` already sets `FA_<key>`, except `tools`, which it stores as
  `FA_update`. That variable is renamed `FA_tools`. Root calls `owasp_kinds FA_` per checked
  account.
- `gird-check.ps1` has no account run. It gets `Owasp-Kinds`, which builds the same field values from
  its own variables (the same names as bash's for most: `$KEY_FILES`, `$HIST_KEYS`, `$N_SESS`,
  `$N_MCP_TOKEN`, `$N_ALLOW`, `$N_SSH_OPEN`, `$N_AK`, `$N_YOLO`, `$N_OLD`, `$N_AUTO`; the planted,
  platform and extension values under its own names) and walks `$OwaspTable`. The twin tests prove
  the two scripts tag the same.

Account-run protocol: unchanged. Root derives every tag from fields it already receives and checks.
`FL_KEYS`, the account run's output and `fl_parse` stay as they are.

## The person's report (`gird-check.sh`, `gird-check.ps1`)

The summary rows 01 to 05 (`cline` in bash, `CLine` in PowerShell) are fixed width and matched by
tests; they do not change. Two things are added, both only when at least one risk is tagged.

### 1. One OWASP line after the summary rows

After row 05 and before "First fix", one blank line, then:

```
   OWASP Agentic Top 10: ASI02, ASI03, ASI05
```

Codes only, in code order. It is written with `wrap` (`Wrap` in PowerShell) at indent 3, so a narrow
terminal folds it. The longest possible line, with all four risks, is 51 characters.

In `--full` and piped output there are no summary rows (`HEAD_FULL` and the sections are printed
instead). The same line goes at the end of the full header, after the stats line and before the
section 01 heading, so a saved or piped report has it too. `HEAD_SHORT`, which the summary and
the details pages share, does not change.

### 2. One line per risk at the top of a section's details

Under a section's rule, before its first row, one dimmed line for each risk with a finding in that
section, in code order:

```
  03  KEYS IN PLAIN TEXT                                                 3 files
  ────────────────────────────────────────────────────────────────────────────
     OWASP ASI03 Identity and Privilege Abuse
     ✗  ~/.zshrc                                      OpenAI
```

The section heading's right-hand text does not change, so the heading never gets wider. The longest
line is "     OWASP ASI04 Agentic Supply Chain Vulnerabilities" (52 characters), written with `wrap` at
indent 5. These lines are part of `SEC1` to `SEC5`, so they are on the details pages (keys 1 to 5),
in `--full`, in piped output and in a saved report.

### How it looks

80 columns, a terminal, colours on:

```
   01  !  Coding agents       6 found, 1 set to run commands without asking
   02  !  MCP servers         4 servers, 1 project acts on opening
   03  ✗  Keys in plain text  3 files, like ~/.zshrc (OpenAI)
   04  ✓  Allow lists         no saved commands with keys
   05  ✓  Recent leaks        none of the 38 recent leaks or malware it checks

   OWASP Agentic Top 10: ASI02, ASI03, ASI05

   First fix: Move keys out of shell profiles, history and .env files into ...
```

"OWASP Agentic Top 10:" is bold and the codes are plain. With `NO_COLOR`, `--no-color` or piped
output, the text is the same with no escape codes. Section lines are dimmed on a terminal and plain
otherwise.

`--full` or piped, the header ends:

```
  ▌ 6 coding agents, 1 not used in 30 days, 4 MCP servers, 3 files with keys in
  ▌ plain text, 0 keys in allow lists
   OWASP Agentic Top 10: ASI02, ASI03, ASI05
```

A home with no findings: no OWASP line, no section lines. A partly checked home with no findings:
the same, and the existing partial wording ("No findings in the paths checked") is unchanged. A
partly checked home with findings: the tags of what was found, and the partial wording as today.

## Fleet mode (`gird-fleet.sh`)

Root tags each checked account with `owasp_kinds FA_`, and the Mac with its own fields
(`FM_INC` set means `machine.incidents`). An account that was not checked gets no tags, and is not
counted in any risk. An account partly checked (`complete: false`) is tagged with what was found;
its tags are a lower bound, as its outcome already says.

### Terminal report

After the "This Mac" block and before "Saved:", when at least one risk is tagged:

```
  OWASP Agentic Top 10
    ASI03 Identity and Privilege Abuse  2 of 3 accounts (keys in plain text, SSH keys without a passphrase)
    ASI04 Agentic Supply Chain Vulnerabilities  1 of 3 accounts and this Mac (malware signs)
```

- The count is of accounts whose check ran ("of 3 accounts"). When some were not checked, one more
  line follows: `    Not counted: 1 account not checked`.
- "and this Mac" is added when the Mac's own fields map to that risk; a risk only the Mac has reads
  `this Mac (malware signs)`.
- The labels are every label of that risk found in any account, once each, in the data file's order.
- Lines can be over 80 characters, as other lines of this report already are (the gh-token-monitor
  line); the report is read in an MDM's log as much as in a terminal.
- With nothing tagged, the block is left out, whatever the outcome. It never says "none".

### JSON

A top-level `owasp` object after `machine`, always present in a finished run:

```json
"owasp": {
  "accounts_counted": 3,
  "accounts_not_checked": 0,
  "risks": [
    {"id": "ASI03", "name": "Identity and Privilege Abuse", "accounts": 2, "machine": false,
     "findings": ["key_files", "ssh_keys_no_passphrase"]},
    {"id": "ASI04", "name": "Agentic Supply Chain Vulnerabilities", "accounts": 1, "machine": true,
     "findings": ["incidents", "machine.incidents"]}
  ]
}
```

An object, not a bare list, so an empty `risks` always sits next to `accounts_not_checked`: a reader
cannot take an empty list as a clean Mac without seeing how many accounts were not counted.

Each checked account's row gets `"owasp": ["ASI03", "ASI04"]` (empty list when nothing maps). A
not-checked row has no `owasp` field, so it never shows an empty list. The `machine` object gets
`"owasp": [...]` the same way.

`tests/fleet-flat.py` learns the object: `owasp.accounts_counted=3`, `owasp.ASI03.accounts=2`,
`owasp.ASI03.machine=false`, `owasp.ASI03.findings=key_files ssh_keys_no_passphrase`, and
`<account>.owasp=ASI03 ASI04` through its existing list handling.

### Summary line

With at least one risk, ` owasp=` is appended, risks in code order, each `<code>:<accounts>`, and
`+mac` when the Mac counts:

```
blindspot act accounts=3 act=1 review=1 not_checked=0 v=1.3.0 at=2026-10-25T09:12:00Z owasp=ASI03:2,ASI04:1+mac
```

A risk only the Mac has reads `ASI04:0+mac`. With nothing tagged there is no `owasp=` part. The
`failed` rewrite of `SUMMARY` (when the save fails) keeps the part.

### Inventory value

`=` is not in the character class `fl_inventory` reads back (`[A-Za-z0-9 ._:;,|+-]`), and every other
detail in the value is written "word value" ("keys 2", "incidents tanstack"). So the token is:

```
 | owasp ASI03:2,ASI04:1+mac
```

appended last. Every character is in the class, so `fl_inventory` needs no change. It cannot be
mistaken for an account: an account part is always `<name>: <outcome>`, with a colon right after
the name, and an account named `owasp` reads `owasp: clear`.

It is the first thing cut. The existing rule: the value is at most 250 characters; when longer, the
awk in `fleet_main` rebuilds it within 243 characters and adds ` +more` (6), so at most 249. The
new order:

1. Build the value as today, without the token (`base`).
2. No token: unchanged from today.
3. `base` plus the token is 250 or less: use it.
4. Otherwise the token is dropped, which counts as a cut:
   - `base` is 244 or less: `base +more`.
   - `base` is longer: run the existing awk, with a new `-v cut0=1` that makes it end with ` +more`
     even if it cut nothing else. This also covers a `base` of 245 to 250 characters, which today
     skips the awk.

So an account's outcome, wiper and incidents are never cut to make room for the token, and a value
that lost the token always says `+more`. The full tags are in `last.json`.

## What is sent to gird.ai

Nothing new, and TELEMETRY.md does not change. Checked against the code:

- The person's report sends its counts from the fixed argument list of the shared-counts payload
  (`send_stats` and the payload built above it in `gird-check.sh`) and builds the result page link in
  `card_url` from named variables. Neither reads report text, and this design adds no variable to
  either. The tags are derived on screen from counts that are already there.
- `gird-fleet.sh` sends nothing; its tags go to the terminal, `last.json` and the inventory value,
  which stay on the Mac or in the admin's own MDM.
- The account run's output to root does not change.

A test (below) asserts that the payload the suites' local server receives has no `owasp` or `ASI`
in it.

## Docs

- README.md, "What it checks": after the five numbered checks, a short paragraph and a table of risk,
  name and what Blindspot tags it with (the labels). It says Blindspot tags ASI02 to ASI05 only, from
  what it reads on disk, and that the mapping is Blindspot's, not OWASP's. The table is written by
  `gen.sh` between `<!-- >>> owasp -->` and `<!-- <<< owasp -->` markers, so README and the scripts
  share one source and `gen.sh --check` catches drift. `splice` already works on any file with the
  markers; the README's are HTML comments, so the marker match takes a comment prefix.
- README.md screenshots: remake `docs/report.png` and `docs/report-full.png` with
  `bash tools/screenshots.sh`. Its fixture (keys, MCP tokens, keys in sessions, a cloned project's
  `SessionStart` hook) shows ASI03 and ASI05, and ASI02 if the fixture's run-without-asking setting
  survives the trimming it does. Check the images show the OWASP line and a section line.
- docs/fleet.md, "4. Read the results": the summary line and inventory examples gain the token; a
  paragraph on the `owasp` JSON object, the per-row field, that `owasp` is cut first from the
  inventory value, and that no `owasp` part means nothing was tagged, never that the Mac is clear
  (read the outcome for that). "What it checks for each account" gets the same table, generated as in
  README.
- docs/mdm/jamf.md and docs/mdm/intune.md: the inventory example line (line 81 in each) gains
  ` | owasp ASI03:1,ASI04:1`. docs/mdm/iru.md: the summary example (line 59) gains
  ` owasp=ASI03:1,ASI04:1`. The smart group advice ("values that start with `v1 act`") stays; add
  "contains `ASI03`" as an example filter only where the page lists filters.
- docs/designs/fleet-mode.md, "The result": the `owasp` fields, the summary line's new part and the
  inventory token, pointing here for the mapping. "Tests": the fleet tests below.
- CHANGELOG.md: there is no "Unreleased" heading today; add one above 1.2.0 with one entry for the
  person's report and one for fleet mode.
- CONTRIBUTING.md: `data/owasp.tsv` in "Lists live in `data/`", and a line in each "Add ..." recipe
  that adds a new account-run field: give it a line in `data/owasp.tsv`.

## Tests

Bash in `tests/run.sh`, each with a twin of the same name in `tests/run-ps.sh` unless marked
bash-only. Fleet tests are bash-only with the reason the existing fleet lines in
`tests/bash-only.txt` give ("gird-check.ps1 has no fleet mode ..."). Each is reverted against the
change before review, as the review rules ask.

Person's report:

| Test | Twin |
|---|---|
| owasp: a key in plain text tags section 03 with ASI03 | yes |
| owasp: run without asking tags section 01 with ASI02 | yes |
| owasp: project settings that act on opening tag section 02 with ASI05 | yes |
| owasp: malware signs tag section 05 with ASI04 | yes |
| owasp: an update-level incident tags ASI04 as a version to update, not malware signs | yes |
| owasp: the summary lists the risks found, in code order, after row 05 | yes |
| owasp: summary rows 01 to 05 are unchanged by the tags | yes |
| owasp: a home with no findings has no OWASP line | yes |
| owasp: a partly checked home with no findings has no OWASP line and never says none | yes |
| owasp: a file named like a worm's, alone, carries no tag | yes |
| owasp: login files alone carry no tag | yes |
| owasp: --full and piped output carry the line in the header and each section's line | yes |
| owasp: with NO_COLOR the OWASP lines have no escape codes | yes |
| owasp: at 80 columns and at 50 no OWASP line is wider than the terminal | yes |
| owasp: the shared counts carry no OWASP field | yes |
| owasp: the account run's output is unchanged | bash-only: the account run is `gird-check.sh`'s |
| gen.sh: an edit to data/owasp.tsv not written into the scripts fails --check | bash-only: `tools/gen.sh` |
| gen.sh: refuses a risk outside ASI01 to ASI10, two names for one risk, a no-risk line with no reason | bash-only: `tools/gen.sh` |
| gen.sh: every account-run key has exactly one line in data/owasp.tsv | bash-only: `tools/gen.sh` |
| gen.sh: a completeness key or a report-only line with a risk is refused | bash-only: `tools/gen.sh` |
| gen.sh: a hand edit to gird-fleet.sh's copy of owasp_kinds fails --check | bash-only: `tools/gen.sh` |
| gen.sh: the README table matches data/owasp.tsv | bash-only: `tools/gen.sh` |

Fleet (`tests/run.sh`'s "fleet mode (--all-users)" part, with the stand-ins it already uses:
`GIRD_CHECK_FLEET_USERS`, `GIRD_CHECK_FLEET_LAUNCH` with `tests/fleet-launch.sh`, and
`tests/fleet-flat.py` on `last.json`):

- fleet: an account's findings map to their risks in its row (`asha.owasp=ASI03 ASI04`)
- fleet: a clear account has an empty owasp list and adds to no risk (needs a clear account in the
  fixture: `itadmin` has an SSH key without a passphrase, so it is ASI03)
- fleet: a not-checked account has no owasp field and is not counted (`accounts_not_checked`)
- fleet: the terminal block counts accounts checked and names what was found
- fleet: the terminal block says how many accounts were not counted
- fleet: a run with every account not checked has no owasp block, no `owasp=` and no inventory token
- fleet: the Mac's incidents count as +mac; its possible signs carry no tag
- fleet: the summary line ends with the owasp part; a run with nothing tagged has none. The existing
  "--summary-to-stdout prints the one summary line" regex ends at `at=...Z$` and its fixture has
  findings, so it gains the optional part.
- fleet: the inventory value ends with the owasp token when it fits
- fleet: a long inventory value drops the owasp token first and ends with +more
- fleet: a value that fits only without the token (245 to 250 characters) still ends with +more
- fleet: --inventory reads back a value with the owasp token
- fleet: the account-run keys are unchanged (FL_KEYS equals the keys the account run prints)

Screenshots are not tests; remaking them is a step in the pull request.

## Touchpoints

- `data/owasp.tsv` (new)
- `tools/gen.sh`: validation, the `owasp` block for bash and PowerShell, the `owasp-derive` copy into
  `gird-fleet.sh`, `owasp` in both block lists, the README and docs/fleet.md tables, the header comment
- `gird-check.sh`: the generated `owasp` block; the `owasp-derive` block (`owasp_kinds`); the
  account-run field values moved into a function before the `ACCTRUN` block; the OWASP line after
  `cline 05`; the line at the end of `HEAD_FULL` (before `HEAD_FULL="$HEAD_SHORT$CAP"`); a line after
  each `section 01` to `section 05` rule
- `gird-check.ps1`: the generated `owasp` block; `Owasp-Kinds`; the line after `CLine '05'`; the line
  in `$HeadFull`; a line in each `Section '01'` to `'05'`
- `gird-fleet.sh`: the two generated blocks; `FA_update` renamed `FA_tools` in `fl_parse` and its
  readers; per-account tags in `fleet_main`; the Mac's tags after `fl_machine`; the `owasp` JSON
  object, row and machine fields; the terminal block; `SUMMARY` (both assignments); the inventory
  token and the `cut0` change to the truncation awk
- `tests/run.sh`, `tests/run-ps.sh`, `tests/bash-only.txt`, `tests/fleet-flat.py`, and
  `tests/make-fixture.sh` if a clear account or a narrow-width case needs fixture data
- `README.md`, `docs/report.png`, `docs/report-full.png` (via `tools/screenshots.sh`)
- `docs/fleet.md`, `docs/mdm/jamf.md`, `docs/mdm/intune.md`, `docs/mdm/iru.md`
- `docs/designs/fleet-mode.md`, `CHANGELOG.md`, `CONTRIBUTING.md`
- Not touched: `TELEMETRY.md`, the shared-counts payload, `card_url`, the account-run protocol

## Risks

- **Read as a compliance claim.** "OWASP" next to a finding can be read as OWASP's verdict. The
  README says the mapping is Blindspot's, and no surface ever prints a risk as absent, met or clear.
- **Read as clean.** A missing tag means "nothing of this kind was found in what was read". Every
  surface leaves the OWASP part out when nothing is tagged, the JSON keeps `accounts_not_checked`
  next to the list, and the outcome (`not_checked`, partial) keeps saying what it says today.
- **The list changes.** OWASP may rename or renumber in a later edition, and its two pages already
  differ on ASI02's name. The names live in one file; the data file header names the edition and
  the source.
- **A platform found is not a confirmed leak.** `platforms_found` means the platform's CLI or files
  are on the machine. The tag sits beside that row's own words ("found"); it does not upgrade it.
- **The two reports drift.** The person's report and fleet mode derive from the same field rule
  (one function, copied), and `gen.sh` refuses report-only kinds with a risk, so one account's tags
  are the same in both. The PowerShell report is held to bash's by the twin tests.
- **Inventory budget.** On a busy Mac the value is often over 250 characters already, so the token
  is often dropped. That is by design (the outcome and accounts matter more), and `+more` says so.
- **Summary line parsers.** An MDM script that matches the summary line to its end (as the test
  does) needs the new part allowed. It is appended last so a parser reading from the start is not
  affected; the CHANGELOG says so.
- **bash 3.2.** No associative arrays: the per-risk counts are built by one `awk` over a list of
  account-risk-kind lines, as `fleet_main` already does for the inventory.

## Open questions

1. ASI02's name: "Tool Misuse" (December 2025 announcement) or "Tool Misuse and Exploitation"
   (Q3 2026 round-up and the brief)? The downloadable document was not read; it should decide.
2. Leads (possible signs, files to read, markers in the shared `/tmp`): this design gives them no
   tag. Tagging them ASI04 would make a lead look like a supply-chain finding.
3. Tools with a published hole and no fixed version yet: no tag here, since nothing counts them as a
   finding and root does not receive them. Tagging them ASI04 would need them counted as a finding
   in both reports and a new account-run field.
4. Planted files and the hooks that run them are ASI04 only. A hook that runs a planted file is
   also ASI05; this design keeps one risk per kind.
5. Fleet denominator: "2 of 3 accounts" counts accounts whose check ran, with not-checked accounts
   on their own line. Is that the reading IT teams want, or every account?
6. The README table generated by `gen.sh` (one source, drift caught) or written by hand with a
   drift test? This design generates it.

## Decisions on the open questions

1. ASI02 is named "Tool Misuse and Exploitation", as OWASP's later round-up names it.
2. Possible signs (leads) carry no risk: they are not findings.
3. Tools with no fixed version yet carry no risk; the account-run protocol does not change.
4. Files a worm plants carry ASI04 only: one risk per finding kind.
5. The fleet count is "N of M checked accounts", with not-checked accounts on a separate line.
6. The README and docs/fleet.md keep hand-written tags in this change. A generated page of every check, made by `tools/gen.sh` from `data/`, is a separate change and will include the mapping table.
