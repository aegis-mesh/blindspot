# OWASP Agentic Top 10 tags

Status: built. The plan review's findings are folded in below ("Decisions on the open questions" and
"Changes from the plan review").

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
- ASI05 is "Unexpected Code Execution" on both pages (checked again on 28 October 2026). Neither page
  writes "(RCE)" after it; the downloadable document, which was not read, may.
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
   tag themselves; the findings in a partly checked home or account keep their tags. A partly checked report or account with no tags never reads as having no risks: every
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
| `agents_run_remote_commands` | `remote` | ASI02 | remote commands without asking | 01 |
| `tools_to_update` | `tools` | ASI04 | tools with a security fix | 01 |
| `mcp_token_files` | `mcp_token_files` | ASI03 | tokens in MCP configs | 02 |
| `authorized_keys_links` | `ak_links` | ASI03 | links to authorized_keys | 02 |
| `project_settings_on_open` | `on_open` | ASI05 | settings that act on opening | 02 |
| `scripts_started_like_worms` | `autostart` | ASI05 | scripts started like worms | 02 |
| `key_files` | `key_files` | ASI03 | keys in plain text | 03 |
| `history_keys` | `history_keys` | ASI03 | keys in shell history | 03 |
| `session_files_with_keys` | `session_files` | ASI03 | keys in agent sessions | 03 |
| `ssh_keys_no_passphrase` | `ssh_open` | ASI03 | SSH keys without a passphrase | 03 |
| `allow_list_keys` | `allow_list_keys` | ASI03 | keys in allow lists | 04 |
| `incidents` | `incidents:act` | ASI04 | malware signs | 05 |
| `incidents_to_update` | `incidents:update` | ASI04 | versions to update | 05 |
| `wiper` | `wiper` | ASI04 | gh-token-monitor | 05 |
| `planted_files` | `planted` | ASI04 | files a worm plants | 05 |
| `authorized_keys_planted_keys` | `ssh_planted` | ASI04 | SSH keys malware adds | 05 |
| `lockfile_only_incidents` | `lock_only` | ASI04 | npm malware in a lockfile | 05 |
| `versions_to_update` | `updates` | ASI04 | Python versions to update | 05 |
| `extensions_to_remove` | `remove` | ASI04 | extensions to remove | 05 |
| `platforms_found` | `platforms` | ASI04 | platforms with a leak | 05 |
| `machine.incidents` | `machine:incidents` | ASI04 | malware signs | (fleet only) |

`incidents:update` is an incident whose level is not `act`, as `gird-fleet.sh` splits an account's
incidents into act and the rest (`_ia` and `_iu` in `fleet_main`). The Mac's own incidents are all
act level: they come from `data/indicators.tsv`, whose lines `gen.sh` refuses for an incident that is
not act level, and from a running LiteLLM loader. So `machine.incidents` is always malware signs.

No risk, each with its reason:

| kind | source | why no risk |
|---|---|---|
| `possible_signs` | `possible` | A lead to check (a LiteLLM leftover with nothing else of it, a startup file named like an extension incident's with no such extension), not a sign. |
| `files_to_read` | `to_read` | A name match only. Projects use some of these names (`setup.mjs`). |
| `shared_tmp_markers` | `tmp_marks` | A lead: another account can link a file there. |
| `shared_tmp_wiper_logs` | `tmp_wiper` | A lead, as above. |
| `machine.possible_signs` | `machine:possible_signs` | A lead, as above. |
| `machine.shared_tmp_wiper_logs` | `machine:shared_tmp_wiper_logs` | A lead, as above. |
| `agents`, `machine.agents` | `agents`, `machine:agents` | What is installed, not a finding. |
| `mcp_servers` | `mcp_servers` | A count of servers, not a finding. |
| `key_providers` | `key_providers` | Detail of `key_files`, which is tagged. |
| `sessions_partly_checked`, `files_not_checked`, `agent_folders_moved`, `protected_folders`, `session_engine` | `sessions_partial`, `not_read`, `moved`, `protected`, `engine` | Completeness. Rule 4. |
| (protocol) | `v`, `end` | Protocol lines. |
| `idle_agents`: idle agents (row 01, fix "Remove agents you no longer use") | `report` | Housekeeping. An idle agent is not itself a finding of any risk, and root does not receive it. |
| `login_files`: login files any agent can read (section 03) | `report` | Shown for information, not counted as a finding (no fix, not in `ISSUES`, not sent to root). Nearly every developer machine has some. |
| `tools_with_no_fix`: tools with a published hole and no fixed version yet (section 01) | `report` | Not counted as a finding today (row 01 and the fix list count only tools with a fix), and root does not receive it. See Open questions, 3. |
| `compromised_actions`: projects whose workflows use a GitHub Action that was compromised (section 05) | `report` | Not tagged yet: the account run does not send it to root (issue #57), and a tag needs that field. |

Three kinds came after this mapping, from other changes in the same release, and were mapped the way
their neighbours are: a saved rule that lets an agent run commands on other machines without asking
is ASI02, as an agent set to run without asking is; a project or the person's own settings that start
a script the way worms do is ASI05, as settings that act on opening are; and an SSH key malware adds
to `authorized_keys` is ASI04, a sign of the supply-chain incident that adds it, as files a worm plants
are.

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
| `name` | The risk's name; every line of one risk must give the same name (as `data/outdated.tsv` does for a tool's name). `-` when `risk` is `-`. Letters, digits, spaces and `-` only. |
| `label` | At most 32 characters: letters, digits, spaces and `, . _ -`. It may start with a capital ("SSH keys without a passphrase"). `-` when `risk` is `-`. |
| `section` | `01` to `05` for a kind the person's report shows; `-` for a machine kind or no risk. |
| `source` | A key in `FL_KEYS` (read from `gird-fleet.sh`), `incidents:act` or `incidents:update` (never a bare `incidents`), `machine:<field>`, or `report` for what only the person's report shows. |
| `why` | Required, and the only place it is allowed, when `risk` is `-`. |

`machine:<field>` names a field of the `machine` object root writes: the keys of the `MACHINE=` JSON in
`gird-fleet.sh`, read by `gen.sh`, except `complete`, `outcome` and `owasp`. Its kind must be
`machine.<field>`. Every such field has exactly one line.

`gen.sh` also refuses: a completeness or protocol key (`v`, `end`, `sessions_partial`, `not_read`,
`moved`, `protected`, `engine`) with a risk; a `report` line with a risk (root could not see it, so the
two reports would disagree); a `machine:` line with a risk other than `machine:incidents`, the one Mac
field root tags; and a source with a risk that `owasp_set` (below), or `Owasp-Set` in `gird-check.ps1`,
has no arm for, which would never be tagged. It requires every key in `FL_KEYS` to have exactly one line, except `incidents`, which has
exactly two (`incidents:act` and `incidents:update`), so a new account-run field cannot ship without a
decision on its risk.

### What `gen.sh` writes

A new block `owasp` in all three scripts, from the lines with a risk only:

- `gird-check.sh` and `gird-fleet.sh` (the same text, kinds with a risk only, in the data file's order):

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
incidents indicators outdated platforms` into it. `owasp` is added to both block lists, and
`owasp-derive` to `gird-fleet.sh`'s, and `data/owasp.tsv` to the lists of data files in `gen.sh`'s
header comment and in CONTRIBUTING.md's "Lists live in `data/`". `gen.sh` writes no README or
docs/fleet.md table (decision 6).

### One derivation, copied to root

The rule that turns field values into kinds has one home, a block `owasp-derive` in `gird-check.sh`,
which `gen.sh` copies into `gird-fleet.sh` the way it copies `owned-walk`. It holds two functions:

- `owasp_set SOURCE` reads fixed variable names, `FA_<key>` (`FA_yolo`, `FA_key_files` and the rest),
  one `case` arm per source: no prefix argument, no `eval`, no `${!name}`. A source is set when its
  value is a number above 0 or a list that is not empty; `incidents:act` when `FA_incidents` holds an
  act-level incident (`incident_level`, generated in both scripts), `incidents:update` when it holds
  one of any other level.
- `owasp_kinds` walks `OWASP_TABLE` and prints `risk|kind|section|name|label` for each kind whose
  source is set, skipping `machine:` and `report` lines.

Root runs this copy, so the block must call only builtins and the generated functions. Three layers
hold it to that:

1. **A text check at build time.** `gen.sh` reads the block as text and refuses a bare command in it.
   It is an early warning for a maintainer, not a boundary: it reads text, not the shell's grammar.
2. **A check of bash's own reprint at run time.** Before each account's tags, root reads
   `declare -f owasp_kinds owasp_set incident_level`, which bash writes from what it parsed. No
   quoting can hide text in it. Root compares each line, trimmed of its indent, with a list of the
   lines the block needs (`fl_owasp_code_ok` in `gird-fleet.sh`). It is an allowlist, not a list of
   refused words: the block is small, so the list names every line shape it uses, and anything else
   is refused. That covers another command, a full path, a builtin such as `command`, `hash`, `eval`
   or `set`, a redirection other than `done <<< "$OWASP_TABLE"`, a backtick, a `$(` other than
   `$(incident_level "$_ow")`, an assignment other than `_ov=$FA_<name>`, and a call to any function
   but the three.
3. **An empty search path at run time.** Root runs `owasp_kinds` in its own subshell with
   `PATH=/private/var/empty`, so a command the block names without a full path is not found. A full
   path tool can still find one: `/usr/bin/env -i id` runs `id` from the system's default path. Layer
   2 is what refuses that. The rest of root keeps its own `PATH`. The folder is never an empty `PATH`
   value or an empty element, which would mean the current folder. macOS ships `/private/var/empty`
   empty, and it and every folder above it are root's alone, so root can check the whole path with
   `owned_only`. A folder root made under `/tmp` could not pass that check, as everyone can write to
   `/tmp`. Before each account's tags, root checks that the folder is a real folder, reached through
   no link, owned by root, writable by no one else and empty.

The tags fail when the reprint holds a line not on the list (cause `code`), when the folder fails its
check (`nopath`), or when the block exits non-zero, writes anything to standard error or prints a line
that is not one `OWASP_TABLE` gives, once and in its order (`rule`). That account is then partly
checked ("its OWASP tags could not be worked out", `owasp_failed: true` in its row), so it never
reads clear. The run reads `failed` (exit 13), even when it has findings to act on. The terminal view
has a line for each cause, `last.json` lists them in `owasp.failed_because`, and the summary line
ends with `owasp_failed=<causes>`.

What is left to code review:

- Anything a maintainer deliberately approves: a line added to the list in `fl_owasp_code_ok`, or a
  change to root's own code outside the block.
- Code in the block outside the three functions. It runs as root when `gird-fleet.sh` loads, with
  root's own `PATH`, and layers 2 and 3 never see it. Only layer 1 reads it.
- Lines on the list put in another order or nesting, such as a `while read` with no here-string,
  which reads standard input, or a function that calls itself. They can call nothing off the list.

**At build time.** `gen.sh` refuses a bare external command in the block, as an early warning. It
reads each command word of the block (after `;`, `&&`, `||`, `|`, `(`, `{`, `$(` and the shell
keywords, with single-quoted text skipped) and allows only a list of builtins and keywords,
`incident_level`, `owasp_set`, `owasp_kinds`, or a word starting with `/`. The block writes no
file: `gen.sh` refuses any `>` outside single quotes.

The guard reads the block one line at a time, so it refuses outright anything that would carry shell
text past a line or past what it reads, rather than try to follow it:

- a here-document that is not quoted (`<<X`), whose body the shell expands, and any `<<-`
  here-document, whose end line may be indented;
- a backtick (write `$( )`, which the guard reads);
- a quote, single or double, that does not close on the line it opens;
- a `(` that does not close on its line, such as a `$(` whose command starts on the next line;
- a line that ends in `\`, which joins it to the next;
- a here-document opened on a line with a `#`, where it may be part of a comment;
- a here-document whose end line never comes.

A quoted here-document (`<<'X'`, `<<"X"`, `<<\X`) is allowed: its body is text, and the guard skips
it to the first line that is exactly `X`. A here-string (`<<<`) is allowed: its word is on its line,
and the guard reads it like any other. `eval`, `exec`, `source`, `.`, `trap` and `command` are not on
the list of allowed words, so a line that calls one is refused as a bare command. Each refusal names
the line of `gird-check.sh` it found. `owasp_kinds` reads `OWASP_TABLE` through a here-string,
`done <<< "$OWASP_TABLE"`.

The guard reads text, not the shell's grammar, so it does not catch everything. These pass it:

- a command between quotes it pairs wrongly: `: "'" ; id ; "'"`;
- a command in the first arm of a case: `case x in *) id ;; esac`;
- a full-path tool: `/usr/bin/env -i id`, `/bin/sh -c id`;
- a builtin hidden by the same quote trick, such as `command -p id` or `hash -p /usr/bin/true tt`.

Layer 2 refuses each of these at run time, and the run reads `failed`.

- In `gird-check.sh`, the values the account run computed inside the `ACCTRUN` block (`_yolo`, `_inc`,
  `_lock`, `_planted` and the rest) move into a function, `finding_fields`, that sets `FA_<key>` for
  each finding field, the names `fl_parse` gives them in `gird-fleet.sh`. It runs for every report;
  the account run prints from those variables, so its output is byte for byte what it was, and the
  person's report tags from the same values. The `moved` profile walk stays inside the account run: it
  is completeness only.
- In `gird-fleet.sh`, `fl_parse` already sets `FA_<key>`, except `tools`, which it stored as
  `FA_update`. That variable is renamed `FA_tools`. Root calls `owasp_kinds` per checked account.
  It reads only values `fl_parse` has already checked.
- `gird-check.ps1` has no account run. It gets `Owasp-Set`, which builds the same field values from its
  own variables (`$KEY_FILES`, `$HIST_KEYS`, `$N_SESS`, `$N_MCP_TOKEN`, `$N_ALLOW`, `$N_SSH_OPEN`, `$N_AK`,
  `$N_YOLO`, `$N_OLD`, `$N_AUTO`, the planted, platform, Python and extension lists, and a new
  `$IndHits` for gird-check.sh's `IND_HITS`), and walks `$OwaspTable`. This is a second implementation
  of the rule, so the tests hold it to bash's: one fixture carries every finding kind the two can share,
  and both suites assert the complete set of tagged section lines and the summary line on it; and each
  kind has a home of its own (`tests/owasp-kind.sh`, or one of the small homes in Tests), so a wrong arm
  for one kind fails its own test in either suite. A key in shell history is the one exception: a
  history file with a key is always a key in a file too (`key_files`, also ASI03 in section 03), so no
  home holds it alone, and a wrong `history_keys` arm on its own would not fail a test. The two reports' tags are derived by the same rule from each run's values.

Account-run protocol: unchanged. Root derives every tag from fields it already receives and checks.
`FL_KEYS`, the account run's output and `fl_parse` stay as they are, but for the `FA_tools` name.

## The person's report (`gird-check.sh`, `gird-check.ps1`)

The summary rows 01 to 05 (`cline` in bash, `CLine` in PowerShell) are fixed width and matched by
tests; they do not change. Two things are added, both only when at least one risk is tagged.

### 1. One OWASP line after the summary rows

After row 05 and before "First fix", one blank line, then:

```
   OWASP Agentic Top 10: ASI02, ASI03, ASI05
```

Codes only, in code order. The longest possible line, with all four risks, is 51 characters, and the
report is never drawn narrower than 60 columns (`W` and `$Width` are held to 60 at least), so it is
written as one line, with no wrap.

In `--full` and piped output there are no summary rows (`HEAD_FULL` and the sections are printed
instead). The same line goes at the end of the full header, after the stats line and a blank line,
and before the section 01 heading, so a saved or piped report has it too. `HEAD_SHORT`, which the summary and
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
line is "     OWASP ASI04 Agentic Supply Chain Vulnerabilities" (52 characters), one line for the same
reason. These lines are part of `SEC1` to `SEC5`, so they are on the details pages (keys 1 to 5),
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

Root tags each checked account with `owasp_kinds`, and the Mac with its own fields (`FM_INC` set means
`machine.incidents`, whether the Mac's check was complete or not). Tags are gathered per account by
its row number in the run, never by its name, so two accounts shown under one name (a hashed name, or
`invalid-name`) still count as two.

Three numbers frame every count:

- **accounts counted**: accounts whose check ran and was read (`N_ACC - N_NC_RUN`).
- **accounts not checked**: accounts whose check never ran or was refused (`N_NC_RUN` in
  `fleet_main`): no home, no login shell, sudo refused, bad output, out of time, the deadline. They get
  no tags and are not in any count. This is not the summary line's `not_checked=`, which also counts
  accounts whose check ran but was partial.
- **accounts partly checked**: counted accounts whose row says `complete: false`. They are tagged with
  what was found, and that can be less than is there.

A risk count never reads as the other accounts being free of that risk: every surface that shows a
count also shows how many accounts were not checked and how many were partly checked, when either is
above 0.

### Terminal report

After the "This Mac" block and before "Saved:", when at least one risk is tagged:

```
  OWASP Agentic Top 10
    ASI03 Identity and Privilege Abuse  2 of 3 checked accounts (keys in plain text, SSH keys without a passphrase)
    ASI04 Agentic Supply Chain Vulnerabilities  1 of 3 checked accounts and this Mac (malware signs)
    Not counted: 1 account not checked
    1 account partly checked: its tags may be incomplete
```

- The count is of accounts counted ("of 3 checked accounts").
- "Not counted" follows when some accounts were not checked, and the partly checked line when some
  were partly checked.
- "and this Mac" is added when the Mac's own fields map to that risk; a risk only the Mac has reads
  `this Mac (malware signs)`.
- The labels are every label of that risk found in any account or the Mac, once each, in the data
  file's order.
- Lines can be over 80 characters, as other lines of this report already are (the gh-token-monitor
  line); the report is read in an MDM's log as much as in a terminal.
- With nothing tagged, the block is left out, whatever the outcome. It never says "none".

### JSON

A top-level `owasp` object after `machine`, always present in a finished run:

```json
"owasp": {
  "accounts_counted": 3,
  "accounts_not_checked": 1,
  "accounts_partly_checked": 1,
  "failed_because": [],
  "risks": [
    {"id": "ASI03", "name": "Identity and Privilege Abuse", "accounts": 2, "machine": false,
     "findings": ["key_files", "ssh_keys_no_passphrase"]},
    {"id": "ASI04", "name": "Agentic Supply Chain Vulnerabilities", "accounts": 1, "machine": true,
     "findings": ["incidents", "machine.incidents"]}
  ]
}
```

An object, not a bare list, so an empty `risks` always sits next to `accounts_not_checked` and
`accounts_partly_checked`: a reader cannot take an empty list as a clean Mac without seeing how many
accounts were not counted or not fully read.

Each checked account's row gets `"owasp": ["ASI03", "ASI04"]` (empty list when nothing maps). A
not-checked row has no `owasp` field, so it never shows an empty list. The `machine` object gets
`"owasp": [...]` the same way.

`tests/fleet-flat.py` learns the object: `owasp.accounts_counted=3`, `owasp.risks=ASI03 ASI04`,
`owasp.ASI03.accounts=2`, `owasp.ASI03.machine=false`, `owasp.ASI03.findings=key_files
ssh_keys_no_passphrase`, and `<account>.owasp=ASI03 ASI04` through its existing list handling.

### Summary line

With at least one risk, ` owasp=` is appended: risks in code order, each `<code>:<accounts>`, with
`+mac` when the Mac counts, then `;counted:<n>`, and `;not_counted:<n>` and `;partial:<n>` when either
is above 0:

```
blindspot act accounts=4 act=1 review=1 not_checked=2 v=1.3.0 at=2026-10-25T09:12:00Z owasp=ASI03:2,ASI04:1+mac;counted:3;not_counted:1;partial:1
```

A risk only the Mac has reads `ASI04:0+mac`. With nothing tagged there is no `owasp=` part, so it
never reads as 0. When the tags could not be worked out, ` owasp_failed=` follows, with each cause
comma separated (`code`, `nopath`, `rule`). When the save fails, `SUMMARY` is rewritten with `failed`
and keeps both parts.

### Inventory value

`=` is not in the character class `fl_inventory` reads back (`[A-Za-z0-9 ._:;,|+-]`), and every other
detail in the value is written "word value" ("keys 2", "incidents tanstack"). Each risk carries its
own `owasp.` prefix, so a filter for `owasp.ASI03` cannot miss a risk listed second, and cannot match an
account's name or details:

```
 | owasp.ASI03:2 owasp.ASI04:1+mac; counted 3; not-counted 1; partial 1
```

appended last, `not-counted` and `partial` only when above 0. Every character is in the class, so
`fl_inventory` needs no change. It cannot be mistaken for an account: an account part is always
`<name>: <outcome>`, with a colon and a space right after the name, and an account named `owasp` reads
`owasp: clear`. A risk only the Mac has reads `owasp.ASI04:0+mac`.

It never costs an account any content. The value is built by `fl_inv_fit HEAD PARTS TOKEN`, which
holds the truncation `fleet_main` did inline. The value is at most 250 characters:

1. Build the value as before, without the token (`base`).
2. `base` is 250 characters or less: it is kept whole, and the token is added only when `base` plus
   the token is 250 or less. Otherwise the value is `base` as it was before this change, with no
   `+more`: nothing of an account was cut.
3. `base` is longer: the truncation awk rebuilds it within 243 characters and adds ` +more`, as before.
   It has no token.

So a missing OWASP part in the inventory value means nothing was tagged or there was no room for it.
The summary line and `last.json` always carry the tags, and the docs send a complete search there.

`gird-report.ps1` reads the part and sets it aside. It accepts it only last, on a Mac value that was
not cut, in the shape above (risks in code order, none on more accounts than `counted`, `0` only with
`+mac`), and reads any other value with it as one that does not fit. It does not show the tags or
count computers by them: the part is missing wherever there was no room and on every Windows result,
so such a count would leave computers out without saying so. Each tag comes from a finding word the
same value names, and the report shows those findings with their MITRE and NIST CSF references.

### Windows

Windows fleet mode (`gird-fleet.ps1`) came in the same release and does not work out OWASP risks
yet: its rows, summary line, inventory value and `last.json` carry no `owasp` part. The person's own
report on Windows (`gird-check.ps1`) is tagged as on a Mac. The fleet tests of this section are in
`tests/bash-only.txt` with that reason until Windows has them.

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

- README.md, "What it checks": each of the five numbered checks gets a hand-written line naming the
  risks its findings are tagged with, and one sentence links OWASP's own page and says Blindspot tags
  ASI02 to ASI05 only, from what it reads on disk, and that the mapping is Blindspot's, not OWASP's.
  A test checks that every risk code, name and label in `data/owasp.tsv` appears in README.md and
  docs/fleet.md, so a new label cannot ship without its doc line (decision 6).
- README.md screenshots: remake `docs/report.png` and `docs/report-full.png` with
  `bash tools/screenshots.sh`. Check the images show the OWASP line and a section line.
- docs/fleet.md, "4. Read the results": the summary line and inventory examples gain the part; a
  paragraph on the `owasp` JSON object and its three counts, the per-row field, that the inventory
  value carries the `owasp` part only when it has room, and that no `owasp` part means nothing was
  tagged (or, in the inventory value, no room), never that the Mac is clear (read the outcome for that). "What it checks for each account" gets the same hand-written
  mapping as README.
- docs/mdm/jamf.md and docs/mdm/intune.md: the inventory example line gains
  ` | owasp.ASI03:1 owasp.ASI04:1; counted 2`. docs/mdm/iru.md: the summary example gains
  ` owasp=ASI03:1,ASI04:1;counted:1`. The smart group advice ("values that start with `v1 act`") stays;
  an inventory filter matches `owasp.ASI03`, a summary-line filter `ASI03:`, never a bare `ASI03`, and
  each page says a Mac with no room for the part does not match the inventory filter.
- docs/designs/fleet-mode.md, "The result": the `owasp` fields, the summary line's new part and the
  inventory token, pointing here for the mapping. "Tests": the fleet tests below.
- CHANGELOG.md: there is no "Unreleased" heading; add one above 1.2.0 with one entry for the person's
  report and one for fleet mode, which says the summary line can now end with the `owasp=` part.
- CONTRIBUTING.md: `data/owasp.tsv` in "Lists live in `data/`", and a line in the recipes that add a new
  account-run field: give it a line in `data/owasp.tsv`.

## Tests

Bash in `tests/run.sh`, each with a twin of the same name in `tests/run-ps.sh` unless marked
bash-only. Fleet tests are bash-only with the reason the existing fleet lines in
`tests/bash-only.txt` give. Each is reverted against the change before review, as the review rules ask.

`tests/make-fixture.sh` gets a third mode, `owasp`: the full home with one more finding of each kind
the full home lacks (Codex set to never ask with full access, Claude Code 2.1.100 installed globally,
a link to `authorized_keys`, Mistral's npm build in a lockfile, telnyx 4.87.1 in a Python environment,
an extension whose malware runs on Windows only). It carries every kind both scripts can show at once;
`lockfile_only_incidents` cannot sit beside installed malware, so its own home tests it.

Person's report:

| Test | Twin |
|---|---|
| owasp: a home with every finding kind gets exactly the section lines of its risks | yes |
| owasp: two risks in one section print in code order | yes |
| owasp: the summary lists every risk found, in code order, after row 05 | yes |
| owasp: summary rows 01 to 05 stay together, the OWASP line after them | yes |
| owasp: --full and piped output carry the line at the end of the header | yes |
| owasp: every OWASP line fits the narrowest report, 60 columns | yes |
| owasp: a key in plain text tags section 03 with ASI03 | yes |
| owasp: run without asking tags section 01 with ASI02 | yes |
| owasp: project settings that act on opening tag section 02 with ASI05 | yes |
| owasp: npm malware in a lockfile alone tags section 05 with ASI04 | yes |
| owasp: an update-level incident alone tags section 05 with ASI04 | yes |
| owasp: a home with no findings has no OWASP line | yes |
| owasp: a partly checked home with no findings has no OWASP line and never says none | yes |
| owasp: a partly checked home with findings keeps its tags | yes |
| owasp: a file named like a worm's, alone, carries no tag | yes |
| owasp: login files alone carry no tag | yes |
| owasp: --full and piped output set the line apart from the stats lines by a blank line | yes |
| owasp: one home per kind (`tests/owasp-kind.sh`): a tool with a security fix, a link to authorized_keys, a token in an MCP config, a key in an agent session, gh-token-monitor, a file a worm plants, an extension to remove, a platform with a leak, each tagging its section and risk alone | yes |
| owasp: the Mastra Run key on Windows tags section 05 with ASI04 | yes (PowerShell reads `GIRD_CHECK_TEST_RUNKEY` in place of the registry) |
| owasp: the shared counts carry no OWASP field | yes |
| owasp: every risk and label in data/owasp.tsv is in README.md and docs/fleet.md | bash-only: it reads the docs, which neither script prints |
| gen.sh refusals (`gen_refuses`): a risk outside ASI01 to ASI10, two names for one risk, a no-risk line with no reason, a label over 32 characters, a bare `incidents` source, an account-run key with no line, a completeness key with a risk, a report-only line with a risk, a Mac field other than incidents with a risk, a risk on a source `owasp_set` has no arm for, an indicator of an incident that is not act level | bash-only: `tools/gen.sh` |
| gen.sh: an edit to data/owasp.tsv not written into the scripts fails --check | bash-only: `tools/gen.sh` |
| gen.sh: a hand edit to gird-fleet.sh's copy of owasp_kinds fails --check | bash-only: `tools/gen.sh` |
| gen.sh: a bare command in the owasp-derive block is refused | bash-only: `tools/gen.sh` |
| gen.sh: an unquoted here-document, and a <<- one, in the owasp-derive block is refused, with the line (two tests) | bash-only: `tools/gen.sh` |
| gen.sh: $(id) in an unquoted here-document, a bare command after a quoted <<- here-document, and a redirection inside $( ) in an unquoted here-document of the owasp-derive block are refused (three tests) | bash-only: `tools/gen.sh` |
| gen.sh: a backtick, a ( or a quote that does not close on its line, a line that ends in a backslash, a here-document opened after a #, and a quoted here-document that never ends in the owasp-derive block are refused (six tests) | bash-only: `tools/gen.sh` |
| gen.sh: a here-string that looks like a quoted here-document in the owasp-derive block is read | bash-only: `tools/gen.sh` |
| gen.sh: a quoted here-document in the owasp-derive block is skipped and written into gird-fleet.sh | bash-only: `tools/gen.sh` |
| gen.sh: the committed owasp-derive block passes the guard | bash-only: `tools/gen.sh` |
| gen.sh: an output redirection in the owasp-derive block is refused | bash-only: `tools/gen.sh` |
| gen.sh: an OWASP source with no arm in gird-check.ps1's Owasp-Set is refused | bash-only: `tools/gen.sh` |

Fleet (`tests/run.sh`'s "fleet mode (--all-users)" part, with the stand-ins it already uses):

- fleet: the account run prints exactly FL_KEYS, in order
- fleet: an account's findings map to their risks in its row
- fleet: a clear account has an empty owasp list and adds to no risk
- fleet: a not-checked account has no owasp field and is not counted
- fleet: the JSON counts accounts not checked and partly checked apart
- fleet: the terminal block counts checked accounts and names what was found
- fleet: the terminal block says how many accounts were not counted
- fleet: the terminal block says how many accounts were partly checked
- fleet: the summary line ends with the owasp part, its counts included
- fleet: a failed save keeps the owasp part in the summary line (a state folder that cannot be made)
- fleet: an update-level incident is labelled versions to update, not malware signs
- fleet: a partly checked Mac still counts its incidents as +mac
- fleet: the Mac's possible signs carry no tag
- fleet: a run with no accounts has no owasp part, no token and an empty owasp object
- fleet: --json and --hash-accounts carry the owasp object and each row's tags
- fleet: the owasp-derive block, with an empty search path, gives each kind's line and runs no command by name
  (each source with a risk, each source with none, and all at once)
- fleet: a not-found hidden by quotes (with 2>/dev/null and with 2<&-), command -p, hash -p, /usr/bin/env -i
  and /usr/bin/env -u PATH in the owasp-derive block are refused from bash's reprint, and the run reads
  failed, never clear (six tests)
- fleet: with the reprint check set aside, a command hidden by quotes, a command in a first case arm, and
  /usr/bin/env and /bin/sh -c find no command by name, and the run reads failed (three tests)
- fleet: with the reprint check set aside, a block that exits non-zero, and one that prints a line twice,
  fail its tags (two tests)
- fleet: tags that fail for two causes name both in --json and --summary-to-stdout
- fleet: a search-path folder that is a link, not root's, writable by others or not empty makes the run
  failed (four tests), and an empty one only root's stand-in can change gives a clear run
- fleet: the inventory value ends with the owasp token when it fits, and --inventory reads it back
- fleet: a long inventory value has no owasp token and ends with +more
- fleet: an inventory value of 244 to 250 characters with findings is kept whole, without the owasp
  token (`fl_inv_fit`, cut out of `gird-fleet.sh` and called with a value of each length)
- fleet: an inventory value with room for the owasp token gets it, at 250 characters
- the existing "--summary-to-stdout prints the one summary line" regex allows the optional part

Screenshots are not tests; remaking them is a step in the pull request.

## Touchpoints

- `data/owasp.tsv` (new)
- `tools/gen.sh`: validation, the `owasp` block for bash and PowerShell, the `owasp-derive` copy into
  `gird-fleet.sh` and its bare-command check, `owasp` in both block lists, the act-level rule for
  `data/indicators.tsv`, the header comment
- `gird-check.sh`: the generated `owasp` block; the `owasp-derive` block (`owasp_set`, `owasp_kinds`);
  `finding_fields`, before the `ACCTRUN` block; the OWASP line after `cline 05`; the line at the end of
  `HEAD_FULL`; `owasp_sec` after each `section 01` to `section 05`
- `gird-check.ps1`: the generated `owasp` block; `$IndHits`; `Owasp-Set`, `$OwFound`, `$OwCodes`,
  `Owasp-Sec`; the line after `CLine '05'`; the line in `$HeadFull`; `Owasp-Sec` after each `Section`
- `gird-fleet.sh`: the two generated blocks; `FA_update` renamed `FA_tools`; `fl_codes`, `fl_owasp`,
  `fl_inv_fit`; per-account tags and `N_PART` in `fleet_main`; the Mac's tags; the `owasp` JSON
  object, row and machine fields; the terminal block; `SUMMARY` (both assignments); the inventory token
- `tests/run.sh`, `tests/run-ps.sh`, `tests/bash-only.txt`, `tests/fleet-flat.py`, `tests/make-fixture.sh`, `tests/owasp-kind.sh`
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
- **The two reports drift.** The person's report and fleet mode derive tags by the same rule from each
  run's values (one function, copied), and `gen.sh` refuses report-only kinds with a risk. The
  PowerShell report is a second implementation of the rule, held to bash's by twin tests on a home
  that carries every finding kind and on a home of each kind alone (but a key in shell history, above).
- **Read as clean for an account that was partly read.** A risk count says how many checked accounts
  have it; the accounts not checked and partly checked are counted beside it on every surface.
- **Inventory budget.** On a busy Mac the value is often near or over 250 characters already, so the
  token is often left out. That is by design (the outcome and accounts matter more), so an inventory
  filter can miss a Mac; the docs say so and point to the summary line and `last.json`.
- **Summary line parsers.** An MDM script that matches the summary line to its end (as the test
  does) needs the new part allowed. It is appended last so a parser reading from the start is not
  affected; the CHANGELOG says so.
- **bash 3.2.** No associative arrays: the per-risk counts are built by one `awk` (`fl_owasp`) over a
  list of row-risk-kind lines, as `fleet_main` already does for the inventory.

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

## Changes from the plan review

- Accounts not checked are those whose check never ran (`N_NC_RUN`); accounts partly checked are
  counted apart (`accounts_partly_checked`, a terminal line, `partial:` and `partial` in the summary
  and inventory), and the summary and inventory carry `counted` (and `not_counted` when above 0), so
  no count reads as other accounts being free of a risk.
- The README and docs/fleet.md tags are hand-written, with a test that every code, name and label of
  `data/owasp.tsv` is in both (decision 6). `gen.sh` writes no doc table.
- `gird-check.ps1`'s derivation is tested: one fixture with every finding kind, the full set of
  section lines and the summary line asserted in both suites, the order of two risks in one section,
  and a home of each kind alone but a key in shell history (see "One derivation, copied to root")
- Root reads fixed `FA_<key>` names (no prefix argument, `eval` or `${!name}`), `gen.sh` refuses a
  bare external command in the `owasp-derive` block, and root checks bash's reprint of the block
  against a list of its lines and runs it with an empty search path.
- The failed-save rewrite of `SUMMARY` keeps the OWASP part, with a test.
- `incidents:update` is defined as "level is not act"; the Mac's incidents are act level by a `gen.sh`
  rule on `data/indicators.tsv`; `machine:<field>` is checked against the `machine` object's fields;
  "platforms with a leak" replaces "platforms that leaked secrets"; filter examples use `owasp.ASI03` (inventory) and `ASI03:` (summary line);
  tags are gathered by account row number.
