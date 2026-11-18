<#
Blindspot fleet report: one report from the Blindspot results your MDM collected.
https://gird.ai/blindspot

Export your computers from your MDM as a CSV file, with the column that holds the Blindspot
result, then run:

  gird-report.ps1 export.csv

It finds the computer name and result columns, the delimiter and the encoding by itself, and saves
an HTML and a CSV report in the folder you run it from. Several export files are fine. It reads
files only: no sign-in, no network request, no administrator rights.

-Organisation <name> puts your organisation's name on the report.

Options, only to correct a wrong guess: -NameColumn <name>, -ResultColumn <name>,
-SeenColumn <name>, -OsColumn <name>, -StaleDays <days> (default 3), -OutDir <folder>, -Open.

Runs on Windows PowerShell 5.1 and on PowerShell 7 on Windows, macOS and Linux. This file is plain
ASCII on purpose. Options are read from the command line by the script itself, so a mistyped one
gets a plain message instead of a PowerShell error.
#>
if ($PSVersionTable.PSVersion.Major -lt 5) {
  [Console]::Error.WriteLine('This report needs Windows PowerShell 5.1 or PowerShell 7. This PowerShell is version ' + $PSVersionTable.PSVersion.Major + '.')
  exit 2
}
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# >>> shared: the export format and the file writing gird-intune.ps1 -Export uses too. tools/gen.sh copies this block there.
function Get-Plain($S) {
  if ($null -eq $S) { return '' }
  return [regex]::Replace([string]$S, '[\p{Cc}\p{Cf}]', '')
}
function Stop-Tool([string]$Message, [int]$Code = 1) {
  foreach ($l in ([string]$Message).Split("`n")) { [Console]::Error.WriteLine((Get-Plain $l)) }
  exit $Code
}
function ConvertTo-CsvCell([string]$S) {
  if ($null -eq $S) { $S = '' }
  $risky = '=+-@' + "`t`r`n" + [char]0xFF1D + [char]0xFF0B + [char]0xFF0D + [char]0xFF20
  $first = $S.TrimStart(' ')
  if ($first.Length -gt 0 -and $risky.IndexOf($first[0]) -ge 0) { $S = "'" + $S }
  return '"' + $S.Replace('"', '""') + '"'
}
function Test-Taken([string]$Path) {
  if ([IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path)) { return $true }
  return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}
function New-ReportFile([string]$Path, [string]$Text, [bool]$Bom) {
  $enc = New-Object System.Text.UTF8Encoding($Bom)
  $pre = $enc.GetPreamble()
  $body = $enc.GetBytes($Text)
  $bytes = New-Object byte[] ($pre.Length + $body.Length)
  [Buffer]::BlockCopy($pre, 0, $bytes, 0, $pre.Length)
  [Buffer]::BlockCopy($body, 0, $bytes, $pre.Length, $body.Length)
  $fs = New-Object IO.FileStream -ArgumentList $Path, ([IO.FileMode]::CreateNew), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
  try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
}
$ExportColumns = @('Device name', 'Device id', 'User', 'OS', 'Result', 'Detection state', 'Last reported', 'Note')
$NoResultRow = 'no result row'
# <<< shared

$Me = 'gird-report.ps1'
if ($PSCommandPath) { $Me = [IO.Path]::GetFileName($PSCommandPath) }

function Show-Usage {
  Write-Host 'Blindspot fleet report: one report from the Blindspot results your MDM collected.'
  Write-Host ''
  Write-Host 'Export your computers from your MDM as a CSV file, with the Blindspot result column, then run:'
  Write-Host ''
  Write-Host "  On Windows:          powershell -ExecutionPolicy Bypass -File .\$Me export.csv"
  Write-Host "  On a Mac or Linux:   pwsh ./$Me export.csv"
  Write-Host ''
  Write-Host 'It saves an HTML and a CSV report in this folder and prints where. Several export files'
  Write-Host 'are fine. It reads files only: no sign-in and no network request.'
  Write-Host ''
  Write-Host '-Organisation <name> puts your organisation''s name on the report.'
  Write-Host ''
  Write-Host 'Only if it guesses wrong: -NameColumn <name>, -ResultColumn <name>, -SeenColumn <name>,'
  Write-Host '-OsColumn <name>, -StaleDays <days>, -OutDir <folder>. -Open opens the report when it is done.'
}

$Opt = @{ NameColumn = ''; ResultColumn = ''; SeenColumn = ''; OsColumn = ''; StaleDays = '3'; OutDir = ''; Organisation = ''; Open = $false; Help = $false }
$Files = New-Object System.Collections.ArrayList
$Valued = @('NameColumn', 'ResultColumn', 'SeenColumn', 'OsColumn', 'StaleDays', 'OutDir', 'Organisation', 'FromFile')
$Flags = @('Open', 'Help')
$argv = @(foreach ($x in $args) { foreach ($y in @($x)) { [string]$y } })
for ($i = 0; $i -lt $argv.Count; $i++) {
  $a = $argv[$i]
  if ($a.Length -lt 2 -or -not $a.StartsWith('-')) { [void]$Files.Add($a); continue }
  $n = $a.Substring(1); $v = $null
  $c = $n.IndexOf(':'); if ($c -ge 0) { $v = $n.Substring($c + 1); $n = $n.Substring(0, $c) }
  if (@('?', 'h') -contains $n) { $n = 'Help' }
  $hit = @($Valued + $Flags | Where-Object { $_ -eq $n })
  if ($hit.Count -ne 1) { Show-Usage; Stop-Tool ("There is no option $(Get-Plain $a). The options are listed above.") 2 }
  $n = $hit[0]
  if ($Flags -contains $n) { $Opt[$n] = $true; continue }
  if ($null -eq $v) {
    if ($i + 1 -ge $argv.Count) { Stop-Tool ("-$n needs a value after it, such as -$n " + $(if ($n -eq 'StaleDays') { '5' } elseif ($n -eq 'OutDir') { 'reports' } elseif ($n -eq 'Organisation') { '"Example Ltd"' } else { '"Computer Name"' }) + '.') 2 }
    $i++; $v = $argv[$i]
  }
  if ($n -eq 'FromFile') { foreach ($f in $v.Split(',')) { if ($f) { [void]$Files.Add($f) } }; continue }
  $Opt[$n] = $v
}
if ($Opt.Help -or $Files.Count -eq 0) { Show-Usage; exit 0 }
$StaleDays = 0
if (-not [int]::TryParse($Opt.StaleDays, [ref]$StaleDays) -or $StaleDays -lt 1 -or $StaleDays -gt 30) { Stop-Tool '-StaleDays takes a number of days, from 1 to 30.' 2 }

# The inventory value, as gird-fleet.sh writes it (docs/designs/fleet-mode.md, "The result"), and
# gird-fleet.ps1 on Windows, which adds other_profiles= and reason= to the header. Anything a writer
# does not write does not fit.
$Outcomes = @{ clear = 1; review = 2; not_checked = 3; act = 4; failed = 5 }
# Every finding word, in the order a result lists them, and the one home of each word's form, level and
# label. tools/gen.sh reads this table and refuses a line it cannot read.
#   Arg: none, count (a number), list (incident or tool ids) or keys (a number, then provider ids)
#   Level: act, review or partial
$Items = @(
  @{ Word = 'wiper'; Arg = 'none'; Level = 'act'; Label = 'Files or folders of the gh-token-monitor wiper' }
  @{ Word = 'incidents'; Arg = 'list'; Level = 'act'; Label = 'Malware incident found' }
  @{ Word = 'lockfile'; Arg = 'list'; Level = 'act'; Label = 'Malware versions in a lockfile' }
  @{ Word = 'planted'; Arg = 'count'; Level = 'act'; Label = 'Files a worm plants in a project' }
  @{ Word = 'run-without-asking'; Arg = 'list'; Level = 'review'; Label = 'Agent set to run commands without asking (excessive agency, OWASP LLM06:2025)' }
  @{ Word = 'keys'; Arg = 'keys'; Level = 'act'; Label = 'Keys in plain text (unsecured credentials, MITRE ATT&CK T1552)' }
  @{ Word = 'history'; Arg = 'count'; Level = 'act'; Label = 'Keys in shell history' }
  @{ Word = 'sessions'; Arg = 'count'; Level = 'act'; Label = 'Keys in agent sessions' }
  @{ Word = 'mcp-tokens'; Arg = 'count'; Level = 'act'; Label = 'Tokens in MCP configs' }
  @{ Word = 'allow-lists'; Arg = 'count'; Level = 'act'; Label = 'Keys in Claude Code allow lists' }
  @{ Word = 'ssh-links'; Arg = 'count'; Level = 'act'; Label = 'Links to authorized_keys' }
  @{ Word = 'ssh-open'; Arg = 'count'; Level = 'review'; Label = 'SSH keys without a passphrase' }
  @{ Word = 'update-tools'; Arg = 'list'; Level = 'review'; Label = 'Tools with a security fix to install' }
  @{ Word = 'platforms'; Arg = 'list'; Level = 'review'; Label = 'Hosted platform that leaked secrets' }
  @{ Word = 'on-open'; Arg = 'count'; Level = 'review'; Label = 'Project settings that act when a folder opens' }
  @{ Word = 'to-read'; Arg = 'count'; Level = 'review'; Label = 'Files named like worm files, to read' }
  @{ Word = 'remove'; Arg = 'list'; Level = 'review'; Label = 'Extensions to remove' }
  @{ Word = 'update'; Arg = 'list'; Level = 'review'; Label = 'Package versions from known software supply chain attacks' }
  @{ Word = 'possible'; Arg = 'list'; Level = 'review'; Label = 'Possible signs of malware' }
  @{ Word = 'tmp-wiper'; Arg = 'none'; Level = 'review'; Label = 'Wiper logs in a shared folder' }
  @{ Word = 'tmp-marks'; Arg = 'list'; Level = 'review'; Label = 'Malware markers in a shared folder' }
  @{ Word = 'partial'; Arg = 'none'; Level = 'partial'; Label = 'Partly checked' }
)
$ItemOrder = @($Items | ForEach-Object { $_.Word })
# A label that carries an industry term is shown in full once, on its row of the findings table; the
# lists of each computer's findings use these shorter names.
$ShortLabel = @{ 'run-without-asking' = 'Agent set to run commands without asking'; keys = 'Keys in plain text'; update = 'Package versions to update' }
$ActItems = @($Items | Where-Object { $_.Level -ceq 'act' } | ForEach-Object { $_.Word })
$NoArg = @($Items | Where-Object { $_.Arg -ceq 'none' } | ForEach-Object { $_.Word })
$NumArg = @($Items | Where-Object { $_.Arg -ceq 'count' } | ForEach-Object { $_.Word })
$ListArg = @($Items | Where-Object { $_.Arg -ceq 'list' } | ForEach-Object { $_.Word })
$Kinds = [ordered]@{}
foreach ($lv in @('act', 'review', 'partial')) { foreach ($it in $Items) { if ($it.Level -ceq $lv) { $Kinds[$it.Word] = $it.Label } } }
$FailReasons = @('host_32bit', 'system_account', 'language_mode', 'unpack', 'save', 'start', 'no_output')
$WinWords = @('deadline', 'time_limit', 'bad_output')
$MacWords = @('name', 'no_login_shell', 'home_missing', 'home_link', 'home_owner', 'home_shared', 'home_system', 'home_name',
  'home_no_answer', 'sudo', 'bad_output', 'time_limit', 'deadline', 'copy_changed')
$AnyWord = @($FailReasons + $WinWords + $MacWords)
# >>> mitre: generated from data/mitre.tsv by tools/gen.sh. Edit that file, then run it.
$MitreAttackVersion = 'v20.1'
$MitreAtlasVersion = '2026.10'
$MitreRows = @(
  @{ Word = 'wiper'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1485'; Name = 'Data Destruction'; Tactics = @('Impact'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1485/'; Note = '' }
  @{ Word = 'wiper'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'No ATLAS technique fits: the wiper does not act through an AI system.' }
  @{ Word = 'incidents'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1195.001'; Name = 'Supply Chain Compromise: Compromise Software Dependencies and Development Tools'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1195/001/'; Note = '' }
  @{ Word = 'incidents'; Os = 'all'; Scope = @('axios', 'tanstack', 'mistralpy', 'guardrails', 'opensearch', 'bitwarden', 'minishai', 'lightning', 'durabletask', 'telnyx', 'mastra', 'antv', 'redhat', 'keyv', 'keyvscope', 'keyvspread', 'sandworm', 'sandsleep', 'tensorlake', 'litellm', 'litellmmar', 'glasswormuni'); Fw = 'attack'; Id = 'T1204.005'; Name = 'User Execution: Malicious Library'; Tactics = @('Execution'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1204/005/'; Note = '' }
  @{ Word = 'incidents'; Os = 'all'; Scope = @('glassworm', 'glasswormmar', 'glasswormvsix', 'glasswormapr', 'glasswormzig', 'glasswormdec', 'glasswormoct', 'glasswormuni', 'glasswasm', 'nxconsole'); Fw = 'attack'; Id = 'T1176.002'; Name = 'Software Extensions: IDE Extensions'; Tactics = @('Persistence'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1176/002/'; Note = '' }
  @{ Word = 'incidents'; Os = 'all'; Scope = @('litellm', 'litellmmar', 'mistralpy', 'guardrails', 'lightning', 'mastra'); Fw = 'atlas'; Id = 'AML.T0010.001'; Name = 'Supply Chain Compromise: Software'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://atlas.mitre.org/techniques/AML.T0010.001'; Note = '' }
  @{ Word = 'incidents'; Os = 'all'; Scope = @('litellm', 'litellmmar', 'mistralpy', 'guardrails', 'lightning', 'mastra'); Fw = 'atlas'; Id = 'AML.T0011.001'; Name = 'User Execution: Malicious Package'; Tactics = @('Execution'); Rel = 'indicator'; Url = 'https://atlas.mitre.org/techniques/AML.T0011.001'; Note = '' }
  @{ Word = 'lockfile'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1195.001'; Name = 'Supply Chain Compromise: Compromise Software Dependencies and Development Tools'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1195/001/'; Note = '' }
  @{ Word = 'lockfile'; Os = 'all'; Scope = @('mastra'); Fw = 'atlas'; Id = 'AML.T0010.001'; Name = 'Supply Chain Compromise: Software'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://atlas.mitre.org/techniques/AML.T0010.001'; Note = '' }
  @{ Word = 'planted'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1195.001'; Name = 'Supply Chain Compromise: Compromise Software Dependencies and Development Tools'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1195/001/'; Note = '' }
  @{ Word = 'planted'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'The one AI package among these incidents cannot be told apart: the result gives a count, not the incident.' }
  @{ Word = 'run-without-asking'; Os = 'win'; Scope = @(); Fw = 'attack'; Id = 'T1698'; Name = 'Indirect Prompt Injection'; Tactics = @('Execution'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1698/'; Note = '' }
  @{ Word = 'run-without-asking'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0053'; Name = 'AI Agent Tool Invocation'; Tactics = @('Execution', 'Privilege Escalation', 'Lateral Movement'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0053'; Note = '' }
  @{ Word = 'keys'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.001'; Name = 'Unsecured Credentials: Credentials In Files'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/001/'; Note = '' }
  @{ Word = 'keys'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0055'; Name = 'Unsecured Credentials'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0055'; Note = '' }
  @{ Word = 'history'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.003'; Name = 'Unsecured Credentials: Shell History'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/003/'; Note = '' }
  @{ Word = 'history'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0055'; Name = 'Unsecured Credentials'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0055'; Note = '' }
  @{ Word = 'sessions'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.001'; Name = 'Unsecured Credentials: Credentials In Files'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/001/'; Note = '' }
  @{ Word = 'sessions'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0055'; Name = 'Unsecured Credentials'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0055'; Note = '' }
  @{ Word = 'mcp-tokens'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.001'; Name = 'Unsecured Credentials: Credentials In Files'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/001/'; Note = '' }
  @{ Word = 'mcp-tokens'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0083'; Name = 'Credentials from AI Agent Configuration'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0083'; Note = '' }
  @{ Word = 'allow-lists'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.001'; Name = 'Unsecured Credentials: Credentials In Files'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/001/'; Note = '' }
  @{ Word = 'allow-lists'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0083'; Name = 'Credentials from AI Agent Configuration'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0083'; Note = '' }
  @{ Word = 'ssh-links'; Os = 'mac'; Scope = @(); Fw = 'attack'; Id = 'T1098.004'; Name = 'Account Manipulation: SSH Authorized Keys'; Tactics = @('Persistence', 'Privilege Escalation'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1098/004/'; Note = '' }
  @{ Word = 'ssh-links'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'No ATLAS technique fits a link to the file of allowed SSH login keys.' }
  @{ Word = 'ssh-open'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.004'; Name = 'Unsecured Credentials: Private Keys'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/004/'; Note = '' }
  @{ Word = 'ssh-open'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0055'; Name = 'Unsecured Credentials'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0055'; Note = '' }
  @{ Word = 'update-tools'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'The security fixes differ in kind, so no one technique fits them all.' }
  @{ Word = 'update-tools'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'The security fixes differ in kind, so no one technique fits them all.' }
  @{ Word = 'update'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1195.001'; Name = 'Supply Chain Compromise: Compromise Software Dependencies and Development Tools'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1195/001/'; Note = '' }
  @{ Word = 'update'; Os = 'all'; Scope = @('mistral', 'mistralpy', 'guardrails'); Fw = 'atlas'; Id = 'AML.T0010.001'; Name = 'Supply Chain Compromise: Software'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://atlas.mitre.org/techniques/AML.T0010.001'; Note = '' }
  @{ Word = 'remove'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1176.002'; Name = 'Software Extensions: IDE Extensions'; Tactics = @('Persistence'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1176/002/'; Note = '' }
  @{ Word = 'remove'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1195.001'; Name = 'Supply Chain Compromise: Compromise Software Dependencies and Development Tools'; Tactics = @('Initial Access'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1195/001/'; Note = '' }
  @{ Word = 'remove'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'These extensions target code editors in general, not AI systems.' }
  @{ Word = 'platforms'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'The leak happened at the hosted platform. Blindspot finds only that the platform is used here.' }
  @{ Word = 'platforms'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'The leak happened at the hosted platform. Blindspot finds only that the platform is used here.' }
  @{ Word = 'on-open'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Such settings can come in a cloned project, but Blindspot cannot tell those from settings a person wrote, and the result gives only a count.' }
  @{ Word = 'on-open'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'The count takes in editor tasks that run when a folder opens, which are not AI agent settings, and the result does not say which was found.' }
  @{ Word = 'to-read'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Files to read by hand: a lead, not a finding.' }
  @{ Word = 'to-read'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Files to read by hand: a lead, not a finding.' }
  @{ Word = 'possible'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'A lead to check by hand, not a finding.' }
  @{ Word = 'possible'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'A lead to check by hand, not a finding.' }
  @{ Word = 'tmp-wiper'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Logs in a folder every account can write to: a lead, not a finding.' }
  @{ Word = 'tmp-wiper'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Logs in a folder every account can write to: a lead, not a finding.' }
  @{ Word = 'tmp-marks'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Markers in a folder every account can write to: a lead, not a finding.' }
  @{ Word = 'tmp-marks'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Markers in a folder every account can write to: a lead, not a finding.' }
  @{ Word = 'partial'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Says the account was partly checked. It is not a finding.' }
  @{ Word = 'partial'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = ''; Name = ''; Tactics = @(); Rel = 'none'; Url = ''; Note = 'Says the account was partly checked. It is not a finding.' }
)
$MitreIncidentNames = @{ 'axios' = 'Axios takeover'; 'tanstack' = 'TanStack worm'; 'mistralpy' = 'mistralai 2.4.6'; 'guardrails' = 'guardrails-ai 0.10.1'; 'opensearch' = 'OpenSearch client'; 'bitwarden' = 'Bitwarden CLI'; 'minishai' = 'Mini Shai-Hulud worm'; 'lightning' = 'lightning 2.6.2 and 2.6.3'; 'durabletask' = 'durabletask 1.4.1 to 1.4.3'; 'telnyx' = 'telnyx 4.87.1 and 4.87.2'; 'mastra' = 'Mastra npm packages'; 'antv' = 'AntV account takeover'; 'redhat' = 'Red Hat Cloud Services packages'; 'keyv' = 'keyv worm'; 'keyvscope' = 'keyv account takeover'; 'keyvspread' = 'keyv worm spread'; 'sandworm' = 'SANDWORM_MODE worm'; 'sandsleep' = 'SANDWORM_MODE sleeper packages'; 'tensorlake' = 'tensorlake package'; 'litellm' = 'LiteLLM 1.107.0'; 'litellmmar' = 'LiteLLM 1.82.7 and 1.82.8'; 'glasswormuni' = 'GlassWorm invisible code'; 'glassworm' = 'GlassWorm extensions'; 'glasswormmar' = 'GlassWorm extensions'; 'glasswormvsix' = 'GlassWorm sleeper extensions'; 'glasswormapr' = 'GlassWorm sleeper extensions'; 'glasswormzig' = 'GlassWorm extensions'; 'glasswormdec' = 'GlassWorm native extensions'; 'glasswormoct' = 'GlassWorm-linked themes'; 'glasswasm' = 'GlassWASM extensions'; 'nxconsole' = 'Nx Console 18.95.0'; 'mistral' = 'Mistral AI npm packages' }
# <<< mitre
$IntuneKeeps = 2048
$MaxWindows = 2047
$MaxMac = 250
$IdList = '^[a-z0-9][a-z0-9._-]{0,63}(,[a-z0-9][a-z0-9._-]{0,63}){0,63}$'
$IdListIn = '[a-z0-9][a-z0-9._-]{0,63}(?:,[a-z0-9][a-z0-9._-]{0,63}){0,63}'

function Test-Items([string]$Text, [bool]$Win, [System.Collections.ArrayList]$Into) {
  $last = -1
  $r = @{ Act = $false; Rev = $false; Partial = $false; Unknown = $false; Items = @{} }
  foreach ($it in $Text.Split([string[]]@('; '), [StringSplitOptions]::None)) {
    $sp = $it.IndexOf(' ')
    $k = $it; $a = $null
    if ($sp -ge 0) { $k = $it.Substring(0, $sp); $a = $it.Substring($sp + 1) }
    $ix = [Array]::IndexOf($ItemOrder, $k)
    if ($ix -lt 0 -and $k -cmatch '^[a-z][a-z0-9-]{0,30}$') { return @{ Unknown = $true } }
    if ($ix -le $last) { return $null }
    $last = $ix
    if ($Win -and $k.StartsWith('tmp-', [StringComparison]::Ordinal)) { return $null }
    if ($NoArg -ccontains $k) { if ($null -ne $a) { return $null } }
    elseif ($NumArg -ccontains $k) { if ($null -eq $a -or $a -cnotmatch '^[1-9][0-9]{0,5}$') { return $null } }
    elseif ($ListArg -ccontains $k) { if ($null -eq $a -or $a -cnotmatch $IdList) { return $null } }
    elseif ($k -ceq 'keys') {
      if ($null -eq $a -or $a -cnotmatch ('^[1-9][0-9]{0,5}( ' + $IdListIn + ')?$')) { return $null }
    }
    else { return $null }
    if ($k -ceq 'partial') { $r.Partial = $true }
    elseif ($ActItems -ccontains $k) { $r.Act = $true }
    else { $r.Rev = $true }
    $r.Items[$k] = $a
    if (-not $Into.Contains($k)) { [void]$Into.Add($k) }
  }
  return $r
}

function Read-Inventory([string]$Raw) {
  $r = @{ Ok = $false; Newer = ''; Outcome = ''; Time = $null; Accounts = @(); Kinds = @(); More = $false; OtherProfiles = 0; Reason = ''; Special = ''; Win = $false }
  if ($null -eq $Raw) { return $r }
  $t = $Raw.TrimEnd(" `t`r`n".ToCharArray())
  $kept = $Raw
  if ($kept.EndsWith("`r`n", [StringComparison]::Ordinal)) { $kept = $kept.Substring(0, $kept.Length - 2) }
  elseif ($kept.EndsWith("`n", [StringComparison]::Ordinal)) { $kept = $kept.Substring(0, $kept.Length - 1) }
  if ($kept.Length -ge $IntuneKeeps -and -not $t.EndsWith(' +more', [StringComparison]::Ordinal)) { $r.Ok = $true; $r.Special = 'cut'; return $r }
  if ($t.Length -eq 0 -or $t.Length -gt $MaxWindows) { return $r }
  if ($t -cnotmatch '^[A-Za-z0-9 ._:;,|+=-]+$') { return $r }
  if ($t -ceq 'none') { $r.Ok = $true; $r.Special = 'none'; return $r }
  if ($t -ceq 'unreadable') { $r.Ok = $true; $r.Special = 'unreadable'; return $r }
  $m = [regex]::Match($t, '^stale: last run ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z)$')
  if ($m.Success) { $r.Ok = $true; $r.Special = 'stale'; $r.Time = $m.Groups[1].Value; return $r }
  $m = [regex]::Match($t, '^failed: the run started ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z) did not finish or could not save its result$')
  if ($m.Success) { $r.Ok = $true; $r.Special = 'failed'; $r.Time = $m.Groups[1].Value; return $r }

  if ($t.EndsWith(' +more', [StringComparison]::Ordinal)) { $r.More = $true; $t = $t.Substring(0, $t.Length - 6) }
  $m = [regex]::Match($t, '^v1 (failed|act|not_checked|review|clear) ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z)( other_profiles=([0-9]{1,4})( reason=([a-z_0-9]{1,40}))?)?((?: \| [^|]+)+)$')
  if (-not $m.Success) {
    if ($t -cmatch '^v(?!1 )[0-9]{1,3} [a-z_]{1,20} [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z( |$)') { $r.Newer = 'version' }
    return $r
  }
  $out = $m.Groups[1].Value
  $win = $m.Groups[3].Success
  $reason = ''
  if ($m.Groups[6].Success) { $reason = $m.Groups[6].Value }
  if ($reason -and ($out -cne 'failed' -or $FailReasons -cnotcontains $reason)) { return $r }
  if ($win -and $out -ceq 'failed' -and -not $reason) { return $r }
  if (-not $win -and $t.Length -gt $MaxMac) { return $r }
  $r.Outcome = $out
  $r.Time = $m.Groups[2].Value
  if ($win) { $r.OtherProfiles = [int]$m.Groups[4].Value }
  $r.Reason = $reason
  $segs = $m.Groups[7].Value.Substring(3).Split([string[]]@(' | '), [StringSplitOptions]::None)
  $more = $r.More
  $kinds = New-Object System.Collections.ArrayList
  $accounts = New-Object System.Collections.ArrayList
  $worst = 0
  $names = @{}
  $rows = 0; $machine = $false; $noAcc = $false; $unknown = $false
  foreach ($s in $segs) {
    if ($noAcc) { return $r }
    if ($s -ceq 'no accounts') {
      if ($win -or $rows -gt 0) { return $r }
      $noAcc = $true
      if ($worst -lt 3) { $worst = 3 }
      [void]$accounts.Add(@{ Name = '(no accounts)'; Outcome = 'not_checked'; Detail = 'no accounts'; Items = @{}; Machine = $false })
      continue
    }
    if ($s.StartsWith('machine:', [StringComparison]::Ordinal)) {
      $mm = [regex]::Match($s, '^machine: (act|review|not_checked)( incidents (' + $IdListIn + '))?(; possible (' + $IdListIn + '))?(; tmp-wiper)?$')
      if (-not $mm.Success -or $machine) { return $r }
      $machine = $true
      $so = $mm.Groups[1].Value
      $hasInc = $mm.Groups[2].Success; $hasPos = $mm.Groups[4].Success; $hasWip = $mm.Groups[6].Success
      if ($win -and ($so -ceq 'not_checked' -or $hasWip)) { return $r }
      if (-not $more) {
        if ($so -ceq 'act' -and -not $hasInc) { return $r }
        if ($so -ceq 'review' -and -not ($hasInc -or $hasPos -or $hasWip)) { return $r }
      }
      if ($hasInc -and -not $kinds.Contains('incidents')) { [void]$kinds.Add('incidents') }
      if ($hasPos -and -not $kinds.Contains('possible')) { [void]$kinds.Add('possible') }
      if ($hasWip -and -not $kinds.Contains('tmp-wiper')) { [void]$kinds.Add('tmp-wiper') }
      $mi = @{}
      if ($hasInc) { $mi['incidents'] = $mm.Groups[3].Value }
      if ($hasPos) { $mi['possible'] = $mm.Groups[5].Value }
      if ($hasWip) { $mi['tmp-wiper'] = $null }
      $rank = $Outcomes[$so]
      if ($rank -gt $worst) { $worst = $rank }
      [void]$accounts.Add(@{ Name = 'machine'; Outcome = $so; Detail = $s.Substring(('machine: ' + $so).Length).TrimStart(';', ' '); Items = $mi; Machine = $true })
      continue
    }
    $sm = [regex]::Match($s, '^([A-Za-z0-9][A-Za-z0-9._-]{0,63}): (act|not_checked|review|clear)( (.+))?$')
    if (-not $sm.Success) { return $r }
    $who = $sm.Groups[1].Value; $so = $sm.Groups[2].Value; $rest = $sm.Groups[4].Value
    if ($machine -and -not $more) { return $r }
    if ($names.ContainsKey($who) -and $who -cne 'invalid-name') { return $r }
    $names[$who] = $true
    $rows++
    $items = @{}
    if ($sm.Groups[3].Success) {
      if ($so -ceq 'clear') { return $r }
      if ($so -ceq 'not_checked' -and $AnyWord -ccontains $rest) {
        $allowed = $MacWords
        if ($win) {
          $allowed = $WinWords
          if ($out -ceq 'failed') { if ($reason -ceq 'save') { $allowed = $WinWords + 'save' } else { $allowed = @($reason) } }
        }
        if ($allowed -cnotcontains $rest) { return $r }
      } else {
        if ($win -and $out -ceq 'failed' -and $reason -cne 'save') { return $r }
        $it = Test-Items $rest $win $kinds
        if ($null -eq $it) { return $r }
        if (-not $it.Unknown) { $items = $it.Items }
        if ($it.Unknown) { $unknown = $true }
        elseif (-not $more) {
          if ($so -ceq 'act' -and -not $it.Act) { return $r }
          if ($so -ceq 'review' -and ($it.Act -or $it.Partial -or -not $it.Rev)) { return $r }
          if ($so -ceq 'not_checked' -and ($it.Act -or -not $it.Partial)) { return $r }
        }
      }
    } elseif ($so -cne 'clear' -and -not $more) { return $r }
    elseif ($win -and $out -ceq 'failed' -and $reason -cne 'save') { return $r }
    $rank = $Outcomes[$so]
    if ($rank -gt $worst) { $worst = $rank }
    [void]$accounts.Add(@{ Name = $who; Outcome = $so; Detail = $rest; Items = $items; Machine = $false })
  }
  if ($win -and $rows -ne 1) { return $r }
  if (-not $win -and $rows -eq 0 -and -not $noAcc -and -not $more) { return $r }
  $head = $Outcomes[$out]
  if ($worst -gt $head) { return $r }
  if ($out -cne 'failed' -and -not $more -and $worst -ne $head) { return $r }
  if ($unknown) { $r.Newer = 'item'; return $r }
  $r.Accounts = $accounts.ToArray()
  $r.Kinds = $kinds.ToArray()
  $r.Win = $win
  $r.Ok = $true
  return $r
}

function Get-UtcTime([string]$T) {
  return [DateTime]::ParseExact($T, "yyyy-MM-dd'T'HH:mm'Z'", [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
}

$StatusOrder = @{ act = 0; not_checked = 1; failed = 2; stale = 3; no_result = 4; review = 5; clear = 6 }
$StatusText = [ordered]@{
  act = 'Act now'
  not_checked = 'Not checked'
  failed = 'Failed'
  stale = 'Not checked: stale'
  no_result = 'Not checked: no result'
  review = 'Review'
  clear = 'Clear'
}


$MitreMeaning = 'MITRE ATT&CK and ATLAS references show which attack technique each finding relates to. Blindspot reads files on each computer. It does not watch for attacks and does not detect any technique in use. "Exposure" means Blindspot found something a technique could exploit. "Indicator" means it found a trace that a published incident links to the technique. The mapping is Blindspot''s own, not MITRE''s.'
$MitreSource = 'References: MITRE ATT&CK Enterprise ' + $MitreAttackVersion + ' and MITRE ATLAS ' + $MitreAtlasVersion + '. ' +
  [char]0xA9 + ' 2026 The MITRE Corporation. This work is reproduced and distributed with the permission of The MITRE Corporation. ' +
  'The MITRE Corporation (MITRE) hereby grants you a non-exclusive, royalty-free license to use ATT&CK' + [char]0xAE +
  ' for research, development, and commercial purposes. Any copy you make for such purposes is authorized provided that you reproduce MITRE''s copyright designation and this license in any such copy. ' +
  'MITRE ATT&CK and ATT&CK are registered trademarks of The MITRE Corporation. MITRE ATLAS data: Copyright 2021-2026 MITRE, licensed under the Apache License, Version 2.0 (www.apache.org/licenses/LICENSE-2.0). Blindspot shows only the ids, names and tactics of the ATLAS techniques it maps. ' +
  'The mapping of findings to techniques is Blindspot''s own, not MITRE''s.'
$FwName = @{ attack = 'ATT&CK'; atlas = 'ATLAS' }
$NotCheckedWhy = 'no result, a stale or failed run, one with an account partly checked or not checked, or a result this tool could not read'
$RelText = [ordered]@{ exposure = 'Exposure for'; indicator = 'Indicator of' }
$NotLooked = @(
  'The network: no traffic, DNS or proxies. It cannot say whether a key left a computer.',
  'The identity provider: no sign-ins, sessions or account activity.',
  'The cloud control plane: no cloud permissions or audit logs, and not what a found key can reach.',
  'Data platforms, such as a lakehouse or a data warehouse.',
  'What AI agents do while they run: what they ran, read or sent. It reads their settings and files.',
  'Malware that is not on its list of incidents.')

function Get-WordIds($Row) {
  $ids = @{}
  foreach ($a in @($Row.Accts)) {
    foreach ($k in @($a.Items.PSBase.Keys)) {
      $v = $a.Items[$k]
      if (-not $v -or $ListArg -cnotcontains $k) { continue }
      if (-not $ids.ContainsKey($k)) { $ids[$k] = @() }
      $ids[$k] += $v.Split(',')
    }
  }
  return $ids
}

function Get-MitreRefs($Row) {
  if (-not $Row.Known) { return }
  $os = 'mac'; if ($Row.Win) { $os = 'win' }
  $ids = Get-WordIds $Row
  foreach ($m in $MitreRows) {
    if ($m.Rel -ceq 'none' -or @($Row.Kinds) -cnotcontains $m.Word) { continue }
    if ($m.Os -cne 'all' -and $m.Os -cne $os) { continue }
    if (@($m.Scope).Count -gt 0) {
      if (-not $ids.ContainsKey($m.Word)) { continue }
      if (@($ids[$m.Word] | Where-Object { @($m.Scope) -ccontains $_ }).Count -eq 0) { continue }
    }
    $m
  }
}

# The one home of the truth table in docs/designs/mitre.md, "What could get out". "no" (none found)
# speaks for the accounts the result read: every one of them read in full, in a fresh, whole result
# from a run that did not fail. Other profiles on a PC are not in the result and do not change the
# state; the page counts them on their own line. The Mac's own row carries none of these items.
function Get-PathState($Row, [scriptblock]$Found) {
  $r = @{ State = 'unknown'; Providers = @() }
  if (-not $Row.Known) { return $r }
  $yes = $false; $any = $false; $prov = @()
  $open = $Row.More -or $Row.Status -ceq 'failed'
  foreach ($a in @($Row.Accts)) {
    if ($a.Machine) { continue }
    $any = $true
    if ($a.Outcome -ceq 'not_checked' -or $a.Items.ContainsKey('partial')) { $open = $true }
    if (& $Found $a.Items) {
      $yes = $true
      $kv = [string]$a.Items['keys']; $sp = $kv.IndexOf(' ')
      if ($sp -ge 0) { foreach ($x in $kv.Substring($sp + 1).Split(',')) { if ($prov -cnotcontains $x) { $prov += $x } } }
      elseif ($kv -and $prov -cnotcontains '') { $prov += '' }
    }
  }
  if ($yes) { $r.State = 'yes'; $r.Providers = $prov }
  elseif (-not $open -and $any) { $r.State = 'no' }
  return $r
}

function Get-RefText($M) { return $RelText[$M.Rel] + ' ' + $M.Id + ' ' + $M.Name }

function Get-PcCount([int]$N) { if ($N -eq 1) { return '1 computer' }; return "$N computers" }


function New-Row([string]$Pc, [string]$User, [string]$Raw, [string]$Source, [string]$Os) {
  return [ordered]@{
    PC = $Pc; User = $User; Ids = @(); Status = ''; Why = ''; CheckedAt = ''; Details = ''; Kinds = @(); Output = $Raw
    Known = $false; Win = $false; More = $false; Accts = @(); OtherProfiles = 0; Refs = @()
    AgentKey = 'unknown'; AgentKeyProviders = @(); Sessions = 'unknown'; McpTokens = 'unknown'
    Source = $Source; OS = $Os; LastSeen = ''; LastReport = ''; Unnamed = $false
  }
}

function Set-Result($Row, [string]$Det, [bool]$HasDet, [DateTime]$Now) {
  $row = $Row
  $raw = [string]$row.Output
  if ($raw.Trim().Length -eq 0) {
    if ($HasDet -and ($Det -eq 'scriptError' -or $Det -eq 'fail')) { $row.Status = 'failed'; $row.Why = 'the check stopped with an error and sent no result' }
    elseif ($HasDet -and $Det -ceq $NoResultRow) { $row.Status = 'no_result'; $row.Why = 'no result yet: Intune has no result row for this PC' }
    elseif ($HasDet) { $row.Status = 'no_result'; $row.Why = 'no result from this PC yet' }
    else { $row.Status = 'no_result'; $row.Why = 'the export has no result for this computer' }
    return $row
  }
  if ($raw -cmatch '^blindspot (failed|act|not_checked|review|clear) accounts=') {
    $row.Status = 'not_checked'; $row.Why = 'this is the summary line, which names no findings: export the inventory value instead'; return $row
  }
  $p = Read-Inventory $raw
  if (-not $p.Ok) {
    $row.Status = 'not_checked'
    if ($p.Newer -ceq 'version') { $row.Why = 'its result is in a newer format than this report tool reads: the computers run a newer Blindspot, so update this tool' }
    elseif ($p.Newer -ceq 'item') { $row.Why = 'its result names a finding this report tool does not know: the computers run a newer Blindspot, so update this tool' }
    else { $row.Why = 'its result does not fit the expected format' }
    return $row
  }
  switch ($p.Special) {
    'none' { $row.Status = 'no_result'; $row.Why = 'the check has not finished a run on this computer'; return $row }
    'unreadable' { $row.Status = 'not_checked'; $row.Why = 'the saved result could not be read'; return $row }
    'stale' { $row.Status = 'stale'; $row.Why = 'the last finished run is old'; $row.CheckedAt = $p.Time; return $row }
    'failed' { $row.Status = 'failed'; $row.Why = 'a run did not finish or could not save its result'; $row.CheckedAt = $p.Time; return $row }
    'cut' {
      $row.Status = 'not_checked'
      if ($HasDet) { $row.Why = 'its result fills all the room Intune keeps and does not end in +more, so Intune may have cut it short' }
      else { $row.Why = 'its result is 2,048 characters or more and does not end in +more, so it may have been cut short' }
      return $row
    }
  }
  $row.CheckedAt = $p.Time
  if (-not $row.OS) { if ($p.Win) { $row.OS = 'Windows' } else { $row.OS = 'macOS' } }
  $at = Get-UtcTime $p.Time
  $age = ($Now - $at).TotalSeconds
  if ($age -lt -3600) { $row.Status = 'not_checked'; $row.Why = 'its result is dated in the future'; return $row }
  if ($age -gt $StaleDays * 86400) {
    $row.Status = 'stale'; $row.Why = "its result is older than $StaleDays days (it read " + $StatusText[$p.Outcome].ToLower() + ')'; return $row
  }
  if ($HasDet -and $p.Outcome -eq 'clear' -and $Det -cne 'success') {
    $row.Status = 'not_checked'; $row.Why = 'it reads clear, but Intune says the check did not succeed'; return $row
  }
  $row.Status = $p.Outcome
  $row.Kinds = $p.Kinds
  $row.Known = $true; $row.Win = $p.Win; $row.More = $p.More; $row.Accts = $p.Accounts; $row.OtherProfiles = $p.OtherProfiles
  $row.Refs = @(Get-MitreRefs $row)
  $ak = Get-PathState $row { param($i) $i.ContainsKey('run-without-asking') -and $i.ContainsKey('keys') }
  $row.AgentKey = $ak.State; $row.AgentKeyProviders = $ak.Providers
  $row.Sessions = (Get-PathState $row { param($i) $i.ContainsKey('sessions') }).State
  $row.McpTokens = (Get-PathState $row { param($i) $i.ContainsKey('mcp-tokens') }).State
  $parts = @()
  foreach ($a in $p.Accounts) {
    $d = $a.Name + ': ' + $a.Outcome.Replace('_', ' ')
    if ($a.Detail) { $d += ' (' + $a.Detail + ')' }
    $parts += $d
  }
  $row.Details = $parts -join ' | '
  $why = @()
  if ($p.Outcome -ceq 'failed') { $w = 'the check could not run'; if ($p.Reason) { $w += ' (' + $p.Reason.Replace('_', ' ') + ')' }; $why += $w }
  $part = @($p.Accounts | Where-Object { $_.Items.ContainsKey('partial') -or ($_.Machine -and $_.Outcome -ceq 'not_checked') }).Count
  $none = @($p.Accounts | Where-Object { $_.Detail -ceq 'no accounts' }).Count
  $skip = @($p.Accounts | Where-Object { -not $_.Machine -and $_.Outcome -ceq 'not_checked' -and -not $_.Items.ContainsKey('partial') -and $_.Detail -cne 'no accounts' -and -not ($p.Reason -and $_.Detail -ceq $p.Reason) }).Count
  if ($part -gt 0) { $why += 'partly checked' }
  if ($skip -gt 0) { $why += "$skip account" + $(if ($skip -eq 1) { '' } else { 's' }) + ' not checked' }
  if ($none -gt 0) { $why += 'no accounts to check' }
  if ($p.More) { $why += 'more on the computer than its result keeps' }
  if ($p.OtherProfiles -gt 0) { $why += "$($p.OtherProfiles) other account" + $(if ($p.OtherProfiles -eq 1) { '' } else { 's' }) + ' on this PC not checked' }
  $row.Why = $why -join '; '
  return $row
}

function ConvertTo-HtmlText([string]$S) {
  if ($null -eq $S) { return '' }
  return [System.Net.WebUtility]::HtmlEncode($S)
}

# --- Reading the export files ----------------------------------------------------------------

$MaxCell = 1024 * 1024
$NameHeaders = @('Computer Name', 'Computer', 'Device name', 'Device', 'Name', 'Hostname', 'Host name', 'deviceName', 'Display Name')
$OsHeaders = @('OS', 'Operating System', 'Platform')
$IdHeaders = [ordered]@{
  mdm = @('Device id', 'DeviceId', 'Managed Device ID', 'Intune Device ID', 'UDID')
  serial = @('Serial Number', 'SerialNumber', 'Serial')
  entra = @('Microsoft Entra Device ID', 'Entra Device ID', 'Azure AD Device ID', 'AzureADDeviceId', 'AAD Device ID')
}
$ResultShape = '^(v[0-9]{1,3} [a-z_]{1,20} [0-9]{4}-|stale: last run |failed: the run started |none$|unreadable$|blindspot (failed|act|not_checked|review|clear) accounts=)'

function Stop-Plain([string]$Message) { throw ('Stopped: ' + $Message) }

function Get-Inner($E) { $x = $E; while ($x.InnerException) { $x = $x.InnerException }; return $x }
# .NET on macOS and Linux reports a refused open as an IOException with errno 13, not UnauthorizedAccessException.
function Test-NoAccess($X) { return ($X -is [UnauthorizedAccessException] -or $X.HResult -eq 13 -or $X.HResult -eq -2147024891) }
# Windows says ERROR_SHARING_VIOLATION or ERROR_LOCK_VIOLATION. .NET on macOS and Linux gives the errno of the
# refused lock, EWOULDBLOCK: 35 on macOS and 11 on Linux, and each number is another error on the other system.
function Get-InUseCodes([string]$Platform, [string]$Os) {
  if ($Platform -ceq 'Win32NT') { return @(-2147024864, -2147024863) }
  if ($Os.StartsWith('Darwin', [StringComparison]::Ordinal)) { return @(35) }
  if ($Os.StartsWith('Linux', [StringComparison]::Ordinal)) { return @(11) }
  return @()
}
$InUseCodes = @(Get-InUseCodes ([string][Environment]::OSVersion.Platform) ([string]$PSVersionTable['OS']))
function Test-InUse($X) { return ($X -is [IO.IOException] -and $InUseCodes -contains $X.HResult) }

function Get-InputFiles {
  $seen = @{}
  foreach ($f in $Files) {
    $rp = @(Resolve-Path -LiteralPath $f -ErrorAction SilentlyContinue)
    if ($rp.Count -ne 1 -or $rp[0].Provider.Name -cne 'FileSystem') { Stop-Plain "There is no file at $f. Check the name and the folder, and run it again." }
    $full = $rp[0].ProviderPath
    if ([IO.Directory]::Exists($full)) { Stop-Plain "$f is a folder. Give the export file in it, such as $(Join-Path $f 'export.csv')." }
    if (-not [IO.File]::Exists($full)) { Stop-Plain "There is no file at $f. Check the name and the folder, and run it again." }
    if ($seen.ContainsKey($full)) { Stop-Plain "$f is given twice." }
    $seen[$full] = $true
    @{ Path = $full; Label = [IO.Path]::GetFileName($full); Given = $f }
  }
}

function Open-Export([string]$Path, [string]$Label) {
  try { $fs = New-Object IO.FileStream -ArgumentList $Path, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::ReadWrite) }
  catch {
    $e = Get-Inner $_.Exception
    if (Test-NoAccess $e) { Stop-Plain "No permission to read $Label. Copy it somewhere you can read it, or ask for access, and run it again." }
    if (Test-InUse $e) { Stop-Plain "$Label is open in another program, such as Excel, which keeps others from reading it. Close it there and run it again." }
    if ($e -is [IO.IOException]) { Stop-Plain "Could not read $($Label): $(Get-Plain $e.Message)" }
    throw
  }
  $head = New-Object byte[] 4096
  $n = $fs.Read($head, 0, $head.Length)
  [void]$fs.Seek(0, [IO.SeekOrigin]::Begin)
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bom = ($n -ge 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) -or ($n -ge 2 -and (($head[0] -eq 0xFF -and $head[1] -eq 0xFE) -or ($head[0] -eq 0xFE -and $head[1] -eq 0xFF)))
  if (-not $bom) {
    if ($n -ge 4 -and $head[0] -eq 0x50 -and $head[1] -eq 0x4B -and $head[2] -eq 3 -and $head[3] -eq 4) {
      $fs.Dispose(); Stop-Plain "$Label is an Excel workbook, not a CSV file. In Excel, save it as CSV (File, Save As, CSV UTF-8) and run it again on that file."
    }
    $even = 0; $odd = 0
    for ($i = 0; $i -lt $n; $i++) { if ($head[$i] -eq 0) { if ($i % 2) { $odd++ } else { $even++ } } }
    if ($odd -gt $n / 8 -and $even -eq 0) { $enc = New-Object System.Text.UnicodeEncoding($false, $false) }
    elseif ($even -gt $n / 8 -and $odd -eq 0) { $enc = New-Object System.Text.UnicodeEncoding($true, $false) }
    elseif ($odd + $even -gt 0) { $fs.Dispose(); Stop-Plain "$Label is not a text file. Export the computers from your MDM as a CSV file and run it on that." }
  }
  return New-Object IO.StreamReader -ArgumentList $fs, $enc, $true
}

function Get-Delimiter([string]$Line) {
  $best = ','; $most = 0
  foreach ($d in @(',', ';', "`t")) {
    $c = 0; $q = $false
    foreach ($ch in $Line.ToCharArray()) { if ($ch -eq '"') { $q = -not $q } elseif (-not $q -and [string]$ch -eq $d) { $c++ } }
    if ($c -gt $most) { $most = $c; $best = $d }
  }
  return [char]$best
}

function Read-CsvRecord([IO.TextReader]$R, [char]$D) {
  $line = $R.ReadLine()
  if ($null -eq $line) { return $null }
  $cells = New-Object System.Collections.Generic.List[string]
  $sb = New-Object System.Text.StringBuilder
  $i = 0; $q = $false; $start = $true
  while ($true) {
    if ($sb.Length -gt $MaxCell) { Stop-Plain 'A cell in the file is longer than 1 MB, so it is not a Blindspot export.' }
    if ($q) {
      $j = $line.IndexOf('"', $i)
      if ($j -lt 0) {
        [void]$sb.Append($line, $i, $line.Length - $i).Append("`n")
        $line = $R.ReadLine()
        if ($null -eq $line) { Stop-Plain 'A quoted cell in the file is never closed, so the file is not a whole CSV export. Export it again.' }
        $i = 0; continue
      }
      [void]$sb.Append($line, $i, $j - $i)
      if ($j + 1 -lt $line.Length -and $line[$j + 1] -eq [char]'"') { [void]$sb.Append('"'); $i = $j + 2; continue }
      $q = $false; $i = $j + 1; continue
    }
    if ($i -ge $line.Length) { $cells.Add($sb.ToString()); break }
    if ($line[$i] -eq $D) { $cells.Add($sb.ToString()); [void]$sb.Clear(); $i++; $start = $true; continue }
    if ($start -and $line[$i] -eq [char]'"') { $q = $true; $start = $false; $i++; continue }
    $k = $line.IndexOf($D, $i); if ($k -lt 0) { $k = $line.Length }
    [void]$sb.Append($line, $i, $k - $i); $i = $k; $start = $false
  }
  return ,$cells.ToArray()
}

function Get-Cleaned([string]$V) {
  $t = $V.Trim()
  if ($t.StartsWith('<result>', [StringComparison]::Ordinal) -and $t.EndsWith('</result>', [StringComparison]::Ordinal) -and $t.Length -ge 17) { return $t.Substring(8, $t.Length - 17) }
  return $V
}

function Get-Unguarded([string]$V) {
  if ($V.StartsWith("'") -and $V.Length -gt 1) {
    $rest = $V.Substring(1).TrimStart(' ')
    if ($rest.Length -gt 0 -and ('=+-@' + [char]0xFF1D + [char]0xFF0B + [char]0xFF0D + [char]0xFF20 + "`t").IndexOf($rest[0]) -ge 0) { return $V.Substring(1) }
  }
  return $V
}

function Get-Next([object[]]$Given, [string]$Option, [string]$Value) {
  $f = @($Given | ForEach-Object { '"' + $_ + '"' }) -join ' '
  return "  $Me $f -$Option `"$Value`""
}

function Get-ColumnList([string[]]$Head, $Sample) {
  $out = @()
  for ($c = 0; $c -lt $Head.Count; $c++) {
    $v = ''
    foreach ($rec in $Sample) { if ($c -lt $rec.Count -and $rec[$c].Trim()) { $v = $rec[$c].Trim(); break } }
    $v = Get-Plain $v
    if ($v.Length -gt 50) { $v = $v.Substring(0, 50) + '...' }
    $out += '  ' + (Get-Plain $Head[$c]) + ': ' + $(if ($v) { $v } else { '(empty)' })
  }
  return ($out -join "`n")
}

function Find-Column([string[]]$Head, [string]$Want, [string]$Label, [string]$Option, $Sample, $Given) {
  $hit = @(for ($i = 0; $i -lt $Head.Count; $i++) { if ($Head[$i].Trim() -eq $Want) { $i } })
  if ($hit.Count -eq 1) { return $hit[0] }
  $why = "$Label has no column named `"$Want`"."
  if ($hit.Count -gt 1) { $why = "$Label has $($hit.Count) columns named `"$Want`"." }
  Stop-Plain ($why + " Its columns, with a value from each:`n" + (Get-ColumnList $Head $Sample) + "`nRun it again with the name of the one to read after -$Option, as written above.")
}

function Read-ExportFile($F, [DateTime]$Now) {
  $Label = $F.Label
  $rd = Open-Export $F.Path $Label
  try {
    $first = $rd.ReadLine()
    if ($null -eq $first -or -not $first.Trim()) { Stop-Plain "$Label is empty. Export the computers from your MDM again, with the Blindspot result column, and run it on that file." }
  } finally { $rd.Dispose() }
  $delim = Get-Delimiter $first
  $rd = Open-Export $F.Path $Label
  try {
    $head = @(Read-CsvRecord $rd $delim | ForEach-Object { $_.Trim([char]0xFEFF, ' ') })
    $sample = New-Object System.Collections.Generic.List[object]
    while ($sample.Count -lt 1000) { $rec = Read-CsvRecord $rd $delim; if ($null -eq $rec) { break }; if (@($rec | Where-Object { $_.Trim() }).Count -gt 0) { $sample.Add($rec) } }
  } finally { $rd.Dispose() }
  if ($sample.Count -eq 0) { Stop-Plain "$Label lists no computers: it has a header row and nothing under it. Export the computers from your MDM again and run it on that file." }
  $idx = @{ Name = -1; Result = -1; Seen = -1; Os = -1; User = -1; Det = -1; Note = -1 }
  $ours = @($ExportColumns | Where-Object { $head -ccontains $_ }).Count -eq $ExportColumns.Count
  if ($ours) {
    $idx.Name = [Array]::IndexOf($head, 'Device name'); $idx.Result = [Array]::IndexOf($head, 'Result'); $idx.Seen = [Array]::IndexOf($head, 'Last reported')
    $idx.Os = [Array]::IndexOf($head, 'OS'); $idx.User = [Array]::IndexOf($head, 'User')
    $idx.Det = [Array]::IndexOf($head, 'Detection state'); $idx.Note = [Array]::IndexOf($head, 'Note')
  }
  if ($Opt.ResultColumn) { $idx.Result = Find-Column $head $Opt.ResultColumn $Label 'ResultColumn' $sample $F.Given }
  elseif (-not $ours) {
    $cand = @(); $strong = @()
    for ($c = 0; $c -lt $head.Count; $c++) {
      $vals = @($sample | ForEach-Object { if ($c -lt $_.Count) { (Get-Cleaned $_[$c]).Trim() } } | Where-Object { $_ -cmatch $ResultShape })
      if ($vals.Count -eq 0) { continue }
      $cand += $c
      if (@($vals | Where-Object { $_ -cnotmatch '^(none|unreadable)$' }).Count -gt 0) { $strong += $c }
    }
    if ($cand.Count -eq 0) {
      Stop-Plain ("$Label holds no Blindspot result. It looked in every column for a value that starts with v1, or reads none, stale, failed or unreadable. Its columns, with a value from each:`n" +
        (Get-ColumnList $head $sample) + "`nExport the column that holds the Blindspot result too (in Jamf Pro the extension attribute, in Intune the custom attribute's Result), and run it again.")
    }
    if ($cand.Count -gt 1) {
      $pick = $cand[0]; if ($strong.Count -gt 0) { $pick = $strong[0] }
      Stop-Plain ("$Label has $($cand.Count) columns that look like the Blindspot result, so it does not pick one. Its columns, with a value from each:`n" +
        (Get-ColumnList $head $sample) + "`nThe ones that look like the result: " + (@($cand | ForEach-Object { '"' + (Get-Plain $head[$_]) + '"' }) -join ', ') + ".`nRun it again naming the one to read:`n" + (Get-Next $F.Given 'ResultColumn' $head[$pick]))
    }
    $idx.Result = $cand[0]
  }
  if ($Opt.NameColumn) { $idx.Name = Find-Column $head $Opt.NameColumn $Label 'NameColumn' $sample $F.Given }
  elseif (-not $ours) {
    $cand = @(for ($c = 0; $c -lt $head.Count; $c++) { if ($c -ne $idx.Result -and $NameHeaders -contains $head[$c]) { $c } })
    if ($cand.Count -ne 1) {
      $guess = @(for ($c = 0; $c -lt $head.Count; $c++) { if ($c -ne $idx.Result) { $head[$c] } }) | Select-Object -First 1
      Stop-Plain ("Could not tell which column of $Label holds the computer's name. Its columns, with a value from each:`n" + (Get-ColumnList $head $sample) +
        "`nRun it again naming the one to read, for example:`n" + (Get-Next $F.Given 'NameColumn' $guess))
    }
    $idx.Name = $cand[0]
  }
  if ($Opt.SeenColumn) { $idx.Seen = Find-Column $head $Opt.SeenColumn $Label 'SeenColumn' $sample $F.Given }
  if ($Opt.OsColumn) { $idx.Os = Find-Column $head $Opt.OsColumn $Label 'OsColumn' $sample $F.Given }
  elseif (-not $ours) { $o = @(for ($c = 0; $c -lt $head.Count; $c++) { if ($OsHeaders -contains $head[$c]) { $c } }); if ($o.Count -eq 1) { $idx.Os = $o[0] } }
  $idCols = [ordered]@{}
  foreach ($kind in $IdHeaders.Keys) {
    $o = @(for ($c = 0; $c -lt $head.Count; $c++) { if ($c -ne $idx.Result -and $c -ne $idx.Name -and $IdHeaders[$kind] -contains $head[$c]) { $c } })
    if ($o.Count -eq 1) { $idCols[$kind] = $o[0] }
  }

  $out = New-Object System.Collections.ArrayList
  $notes = New-Object System.Collections.ArrayList
  $rd = Open-Export $F.Path $Label
  try {
    [void](Read-CsvRecord $rd $delim)
    $n = 1
    while ($true) {
      $rec = Read-CsvRecord $rd $delim
      if ($null -eq $rec) { break }
      $n++
      if (@($rec | Where-Object { $_.Trim() }).Count -eq 0) { continue }
      $cell = { param($ix) if ($ix -ge 0 -and $ix -lt $rec.Count) { [string]$rec[$ix] } else { '' } }
      $note = & $cell $idx.Note
      if ($note.Trim()) { [void]$notes.Add((Get-Plain $note)); continue }
      $pc = Get-Unguarded (& $cell $idx.Name)
      $unnamed = -not $pc.Trim()
      if ($unnamed) { $pc = "(name not given) row $n" }
      $ot = & $cell $idx.Os
      $os = ''
      if ($ot -match 'mac|darwin') { $os = 'macOS' } elseif ($ot -match 'win') { $os = 'Windows' } elseif ($ot -match 'linux') { $os = 'Linux' }
      $row = New-Row $pc (Get-Unguarded (& $cell $idx.User)) (Get-Cleaned (& $cell $idx.Result)) $Label $os
      $row.LastSeen = & $cell $idx.Seen
      if ($ours) { $row.LastReport = $row.LastSeen }
      $ids = @()
      foreach ($kind in $idCols.Keys) { $v = (& $cell $idCols[$kind]).Trim(); if ($v) { $ids += $kind + ':' + $v.ToLowerInvariant() } }
      $row.Ids = $ids
      $row.Unnamed = $unnamed
      [void]$out.Add((New-Object PSObject -Property (Set-Result $row (& $cell $idx.Det) $ours $Now)))
    }
  } finally { $rd.Dispose() }
  return @{ Rows = $out.ToArray(); Notes = $notes.ToArray() }
}

# Rows are never joined into one computer: different computers can share a name or an id (a
# placeholder serial such as "To be filled by O.E.M.", small ids from two MDMs), and a join would
# drop one computer's findings. The page only says how many names and ids repeat.
function Get-RepeatCount($Rows) {
  $seen = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
  foreach ($r in $Rows) {
    $keys = @($r.Ids)
    if (-not $r.Unnamed) { $keys += 'name:' + $r.PC.Trim().ToLowerInvariant() }
    foreach ($k in $keys) { $seen[$k] = 1 + [int]$seen[$k] }
  }
  return @($seen.Values | Where-Object { $_ -gt 1 }).Count
}

# --- Working out what the report says ----------------------------------------------------------

$NcKeys = @('not_checked', 'failed', 'stale', 'no_result')
$NcGroups = [ordered]@{
  not_checked = @{ Label = 'Not checked or partly checked'; Note = 'not checked or partly checked'; Step = 'To see the full result, the person runs Blindspot on their own account.' }
  failed = @{ Label = 'Run failed'; Note = 'with a run that failed'; Step = 'Run the check again. If it fails again, the person runs Blindspot on their own account to see why.' }
  stale = @{ Label = 'Stale result'; Note = 'with a stale result'; Step = 'Check the computer is on and reporting to the MDM.' }
  no_result = @{ Label = 'No result'; Note = 'with no result'; Step = 'Check the Blindspot check is assigned to these computers and has run.' }
}
# The first step for each kind of finding to act on, in the words gird-check.sh's own advice uses.
$ActSteps = [ordered]@{
  wiper = 'Do not revoke any GitHub token yet. First stop and remove gh-token-monitor: it runs a destructive command when the token it uses stops working.'
  incidents = 'From another computer, rotate every key this computer could reach.'
  lockfile = 'If that project was installed, rotate every key this computer could reach, from another computer.'
  planted = 'To see which files, the person runs Blindspot on their own account, and deletes any they did not put there.'
  keys = 'Move the keys out of the files they are in, then rotate them.'
  history = 'Treat the keys in shell history as exposed and rotate them.'
  sessions = 'Treat the keys in agent sessions as exposed and rotate them.'
  'mcp-tokens' = 'Replace tokens in MCP configs with environment variable references, then rotate them.'
  'allow-lists' = 'Delete the saved Claude Code commands that contain keys, and rotate those keys.'
  'ssh-links' = 'Delete the links to authorized_keys.'
}
$PrioShown = 8

function Get-Priority($Row) {
  $k = @($Row.Kinds)
  if ($k -ccontains 'wiper') { return 0 }
  if ($k -ccontains 'incidents' -or $k -ccontains 'planted') { return 1 }
  if ($Row.Sessions -ceq 'yes') { return 2 }
  if ($Row.AgentKey -ceq 'yes') { return 3 }
  return 4
}

function Get-ShortLabel([string]$K) { if ($ShortLabel.ContainsKey($K)) { return $ShortLabel[$K] }; return $Kinds[$K] }

function Get-FoundText($Row) {
  $parts = @()
  foreach ($k in $ItemOrder) {
    if (@($Row.Kinds) -cnotcontains $k) { continue }
    $vals = @()
    foreach ($a in @($Row.Accts)) {
      if (-not $a.Items.ContainsKey($k)) { continue }
      $v = [string]$a.Items[$k]
      if ($k -ceq 'keys') { $sp = $v.IndexOf(' '); if ($sp -ge 0) { $v = $v.Substring($sp + 1) } else { $v = '' } }
      elseif ($ListArg -cnotcontains $k) { $v = '' }
      foreach ($x in $v.Split(',')) { if ($x -and $vals -cnotcontains $x) { $vals += $x } }
    }
    $t = Get-ShortLabel $k
    if ($vals.Count -gt 0) { $t += ': ' + ($vals -join ', ') }
    $parts += $t
  }
  return $parts -join '; '
}

function Get-Account($Row) {
  if ([string]$Row.User -and $Row.User.Trim()) { return [string]$Row.User }
  return (@($Row.Accts | Where-Object { -not $_.Machine -and $_.Detail -cne 'no accounts' } | ForEach-Object { $_.Name }) -join ', ')
}


function Get-Window($Rows) {
  $t = @($Rows | Where-Object { $_.CheckedAt } | ForEach-Object { $_.CheckedAt } | Sort-Object)
  if ($t.Count -eq 0) { return '' }
  $a = Get-UtcTime $t[0]; $b = Get-UtcTime $t[$t.Count - 1]
  $ci = [Globalization.CultureInfo]::InvariantCulture
  if ($a.Date -eq $b.Date) { return $a.ToString('d MMMM yyyy', $ci) }
  if ($a.Year -eq $b.Year -and $a.Month -eq $b.Month) { return [string]$a.Day + ' to ' + $b.ToString('d MMMM yyyy', $ci) }
  return $a.ToString('d MMMM yyyy', $ci) + ' to ' + $b.ToString('d MMMM yyyy', $ci)
}

function Get-OsSplit($Rows) {
  $parts = @()
  foreach ($o in @('Windows', 'macOS', 'Linux')) { $n = @($Rows | Where-Object { $_.OS -ceq $o }).Count; if ($n -gt 0) { $parts += "$n $o" } }
  $n = @($Rows | Where-Object { -not $_.OS }).Count
  if ($n -gt 0) { $parts += "$n with the system not known" }
  return $parts -join ', '
}

function Get-ReportData($Rows, $Notes, $Sources, [DateTime]$Now, [int]$Repeats, [string]$Org) {
  $count = @{}
  foreach ($k in $StatusText.Keys) { $count[$k] = @($Rows | Where-Object { $_.Status -eq $k }).Count }
  $known = @($Rows | Where-Object { $_.Known })
  $ci = [Globalization.CultureInfo]::InvariantCulture
  $d = @{
    Org = $Org; Day = $Now.ToString('d MMMM yyyy', $ci); Now = $Now.ToString('yyyy-MM-dd HH:mm', $ci) + ' UTC'; StaleDays = $StaleDays
    Window = (Get-Window $Rows)
    Sources = (@($Sources.PSBase.Keys | ForEach-Object { $_ + ' (' + $Sources[$_] + ')' }) -join ', ')
    Notes = @($Notes); Counts = $count; Total = $Rows.Count; OsSplit = (Get-OsSplit $Rows)
    NotChecked = $count.not_checked + $count.failed + $count.stale + $count.no_result
    Meaning = $MitreMeaning; Credit = $MitreSource
    Kinds = @(); Paths = @(); Techniques = @(); Tactics = [ordered]@{}; Limits = @(); Prio = @(); Wiper = @(); Malware = 0
    NcGroups = @(); NcOsSplit = ''; All = (New-Object System.Collections.ArrayList)
  }
  # PSBase: a dictionary with a 'keys' entry answers .Keys with that entry.
  foreach ($k in $Kinds.PSBase.Keys) {
    $with = @($known | Where-Object { @($_.Kinds) -ccontains $k })
    $n = @($Rows | Where-Object { @($_.Kinds) -ccontains $k }).Count
    if ($n -eq 0) { continue }
    $level = @($Items | Where-Object { $_.Word -ceq $k })[0].Level
    $cells = @{}; $why = [ordered]@{}; $rels = @()
    foreach ($fw in @('attack', 'atlas')) {
      $cell = @{ Refs = @(); Text = '' }
      $mine = @($MitreRows | Where-Object { $_.Word -ceq $k -and $_.Fw -ceq $fw })
      $none = @($mine | Where-Object { $_.Rel -ceq 'none' })
      if ($none.Count -gt 0) { $why[$fw] = $none[0].Note; $cell.Text = $none[0].Note; $cells[$fw] = $cell; continue }
      foreach ($m in $mine) {
        $on = @($with | Where-Object { @($_.Refs) -contains $m })
        if ($on.Count -eq 0) { continue }
        $only = @()
        if ($m.Os -ceq 'win') { $only += 'Windows PCs' } elseif ($m.Os -ceq 'mac') { $only += 'Macs' }
        if (@($m.Scope).Count -gt 0) {
          $hit = @()
          foreach ($x in $on) { foreach ($i in @((Get-WordIds $x)[$k])) { if (@($m.Scope) -ccontains $i -and $hit -cnotcontains $i) { $hit += $i } } }
          $only += 'the incidents ' + ((@($hit | ForEach-Object { $nm = $MitreIncidentNames[$_]; if ($nm) { $nm } else { $_ } }) | Select-Object -Unique) -join ', ')
        }
        $q = ''; if ($only.Count -gt 0) { $q = 'Only for ' + ($only -join ', on ') + ': ' + (Get-PcCount $on.Count) }
        $cell.Refs += @{ Id = $m.Id; Url = $m.Url; Name = $m.Name; Only = $q }
        $rt = $m.Rel.Substring(0, 1).ToUpper() + $m.Rel.Substring(1)
        if ($rels -cnotcontains $rt) { $rels += $rt }
      }
      if ($cell.Refs.Count -eq 0 -and $mine.Count -gt 0) { $cell.Text = 'None applies to what these computers sent.' }
      $cells[$fw] = $cell
    }
    $joint = ''
    if ($why.Count -eq 2 -and $why['attack'] -ceq $why['atlas']) { $joint = 'No MITRE reference: ' + $why['attack'] }
    $d.Kinds += @{ Word = $k; Level = $level; Label = $Kinds[$k]; Count = $n; Rels = $rels; Cells = $cells; Joint = $joint }
  }
  foreach ($pa in @(
      @{ Prop = 'AgentKey'; Text = 'An AI agent set to run commands without asking, with a key in plain text in the same account' },
      @{ Prop = 'Sessions'; Text = 'A key in an AI agent''s saved session files' },
      @{ Prop = 'McpTokens'; Text = 'A token written in an MCP server''s config' })) {
    $yes = @($Rows | Where-Object { $_.($pa.Prop) -ceq 'yes' })
    $prov = @()
    if ($pa.Prop -ceq 'AgentKey') {
      $pc = [ordered]@{}
      foreach ($y in $yes) { foreach ($x in @($y.AgentKeyProviders)) { $nm = $x; if (-not $nm) { $nm = 'not named in the result' }; if ($pc.Contains($nm)) { $pc[$nm]++ } else { $pc[$nm] = 1 } } }
      $prov = @($pc.PSBase.Keys | ForEach-Object { $_ + ' (' + (Get-PcCount $pc[$_]) + ')' })
    }
    $no = @($Rows | Where-Object { $_.($pa.Prop) -ceq 'no' })
    $d.Paths += @{ Text = $pa.Text; Yes = $yes.Count; No = $no.Count; Unknown = @($Rows | Where-Object { $_.($pa.Prop) -ceq 'unknown' }).Count
      Providers = $prov; NoOthers = @($no | Where-Object { $_.OtherProfiles -gt 0 }).Count }
  }
  $techs = [ordered]@{}
  foreach ($m in $MitreRows) { if ($m.Rel -cne 'none' -and -not $techs.Contains($m.Fw + ' ' + $m.Id)) { $techs[$m.Fw + ' ' + $m.Id] = $m } }
  $tl = @()
  foreach ($key in $techs.PSBase.Keys) {
    $m = $techs[$key]
    $on = @($known | Where-Object { @($_.Refs | Where-Object { $_.Fw -ceq $m.Fw -and $_.Id -ceq $m.Id }).Count -gt 0 })
    if ($on.Count -eq 0) { continue }
    $t = @{ Name = $m.Name; Id = $m.Id; Url = $m.Url; Fw = $FwName[$m.Fw]; FwKey = $m.Fw; N = $on.Count; Tactics = @($m.Tactics) }
    foreach ($rel in $RelText.Keys) { $t[$rel] = @($on | Where-Object { @($_.Refs | Where-Object { $_.Fw -ceq $m.Fw -and $_.Id -ceq $m.Id -and $_.Rel -ceq $rel }).Count -gt 0 }).Count }
    $tl += New-Object PSObject -Property $t
  }
  $d.Techniques = @($tl | Sort-Object @{ Expression = { $_.FwKey } }, @{ Expression = { $_.N }; Descending = $true })
  foreach ($fw in @('attack', 'atlas')) {
    $byTactic = [ordered]@{}
    foreach ($m in @($d.Techniques | Where-Object { $_.FwKey -ceq $fw })) {
      foreach ($tc in @($m.Tactics)) {
        if (-not $byTactic.Contains($tc)) { $byTactic[$tc] = @() }
        $nm = $m.Name + ' (' + $m.Id + ')'
        if ($byTactic[$tc] -cnotcontains $nm) { $byTactic[$tc] += $nm }
      }
    }
    if ($byTactic.Count -gt 0) { $d.Tactics[$FwName[$fw]] = @($byTactic.PSBase.Keys | ForEach-Object { $_ + ': ' + ($byTactic[$_] -join '; ') }) }
  }

  $acts = @($Rows | Where-Object { $_.Status -eq 'act' } | Sort-Object @{ Expression = { Get-Priority $_ } }, @{ Expression = { $_.PC } })
  foreach ($r in @($acts | Select-Object -First $PrioShown)) {
    $why = @(); $steps = @()
    foreach ($k in $ItemOrder) {
      if (@($r.Kinds) -cnotcontains $k -or $ActItems -cnotcontains $k) { continue }
      $why += Get-ShortLabel $k
      if ($ActSteps.Contains($k) -and $steps.Count -lt 2) { $steps += $ActSteps[$k] }
    }
    if ($steps.Count -eq 0) { $steps += 'To see what was found, the person runs Blindspot on their own account.' }
    $d.Prio += @{ PC = $r.PC; Account = (Get-Account $r); OS = $r.OS; Why = ($why -join '; '); Step = ($steps -join ' ') }
  }
  $d.ActCount = $acts.Count
  $d.Wiper = @($Rows | Where-Object { @($_.Kinds) -ccontains 'wiper' } | ForEach-Object { $_.PC })
  $d.Malware = @($Rows | Where-Object { @($_.Kinds) -ccontains 'incidents' }).Count

  $nc = @($Rows | Where-Object { $NcKeys -contains $_.Status })
  foreach ($g in $NcGroups.PSBase.Keys) {
    $in = @($nc | Where-Object { $_.Status -eq $g })
    if ($in.Count -eq 0) { continue }
    $by = [ordered]@{}
    foreach ($r in $in) {
      $w = [string]$r.Why; if (-not $w) { $w = $StatusText[$g] }
      $w = $w.Substring(0, 1).ToUpper() + $w.Substring(1)
      if (-not $by.Contains($w)) { $by[$w] = New-Object System.Collections.ArrayList }
      [void]$by[$w].Add($r.PC)
    }
    $reasons = @()
    foreach ($w in $by.PSBase.Keys) {
      $step = $NcGroups[$g].Step
      if ($w.Contains('update this tool')) { $step = 'Get the newest gird-report.ps1 and run it again.' }
      elseif ($w.Contains('summary line')) { $step = 'Export the column that holds the inventory value, and run it again.' }
      $reasons += @{ Why = $w; Hosts = @($by[$w] | Sort-Object); Step = $step }
    }
    $d.NcGroups += @{ Key = $g; Label = $NcGroups[$g].Label; Note = $NcGroups[$g].Note; N = $in.Count; Reasons = $reasons }
  }
  $d.NcOsSplit = Get-OsSplit $nc

  $order = @($Rows | Sort-Object @{ Expression = { $StatusOrder[$_.Status] } }, @{ Expression = { if ($_.Status -eq 'act') { Get-Priority $_ } else { 0 } } }, @{ Expression = { $_.PC } })
  foreach ($r in $order) {
    $raw = ''
    if ($r.Status -eq 'not_checked' -and -not $r.Known) { $raw = [string]$r.Output; if ($raw.Length -gt 200) { $raw = $raw.Substring(0, 200) + '...' } }
    $at = ''; if ($r.CheckedAt) { $at = (Get-UtcTime $r.CheckedAt).ToString('d MMM HH:mm', $ci) }
    [void]$d.All.Add(@{ PC = $r.PC; Account = (Get-Account $r); OS = $r.OS; Status = $r.Status; StatusText = $StatusText[$r.Status]; Found = (Get-FoundText $r); Why = $r.Why; Raw = $raw; At = $at })
  }

  if (@($Rows | Where-Object { $_.OS -ceq 'Windows' }).Count -gt 0) {
    $others = @($known | Where-Object { $_.Win -and $_.OtherProfiles -gt 0 }).Count
    $lim = 'Each Windows result covers one account: the person signed in when it ran.'
    if ($others -gt 0) { $lim += ' ' + (Get-PcCount $others) + ' had other accounts that were not checked.' }
    $d.Limits += $lim
  }
  if (@($Rows | Where-Object { $_.OS -ceq 'macOS' }).Count -gt 0) {
    $d.Limits += 'Each Mac result covers every local account with a user ID of 500 or above. One it could not check is listed as not checked, and a result cut to fit may leave accounts out.'
  }
  $failedBare = @($Rows | Where-Object { $_.Status -eq 'failed' -and -not $_.Known }).Count
  $d.Limits += "$($count.no_result) with no result, $($count.stale) with a stale result, $failedBare failed with no result, and " +
    "$(@($Rows | Where-Object { $_.Status -eq 'not_checked' -and -not $_.Known }).Count) with a result this tool could not read. Nothing they may hold is in the counts in this report."
  $partly = @($Rows | Where-Object { $_.Known -and ($_.Status -eq 'failed' -or $_.Status -eq 'not_checked' -or @($_.Accts | Where-Object { $_.Items.ContainsKey('partial') -or $_.Outcome -ceq 'not_checked' }).Count -gt 0) }).Count
  if ($partly -gt 0) { $d.Limits += (Get-PcCount $partly) + ' failed or were partly checked but sent a result: what it names is in the counts in this report, and what the run did not reach is not known.' }
  $cut = @($known | Where-Object { $_.More }).Count
  if ($cut -gt 0) { $d.Limits += (Get-PcCount $cut) + ' sent a result cut to fit what the MDM keeps. Findings past the cut are not in the counts in this report.' }
  if ($Repeats -gt 0) {
    $d.Limits += "$Repeats computer name" + $(if ($Repeats -eq 1) { ' (or device identifier) appears' } else { 's (or device identifiers) appear' }) +
      ' more than once across the rows. Each row was counted as its own computer, so some computers may be counted more than once.'
  }
  return $d
}

# --- The page: markup only, from the data Get-ReportData worked out ------------------------------

function Get-Link([string]$Url, [string]$Text) {
  if ($Url.StartsWith('https://attack.mitre.org/techniques/', [StringComparison]::Ordinal) -or $Url.StartsWith('https://atlas.mitre.org/techniques/', [StringComparison]::Ordinal)) {
    return '<a href="' + (ConvertTo-HtmlText $Url) + '" rel="noopener noreferrer">' + (ConvertTo-HtmlText $Text) + '</a>'
  }
  return (ConvertTo-HtmlText $Text)
}

# Text for a quoted CSS string: every character but a letter, a digit or a space as a six-digit escape,
# so nothing from the input can end the string or the style element.
function ConvertTo-CssText([string]$S) {
  return [regex]::Replace([string]$S, '[^A-Za-z0-9 ]', { param($m) '\' + ([int][char]$m.Value).ToString('X6') })
}

function Get-Num([double]$N) { return ([Math]::Round($N, 1)).ToString([Globalization.CultureInfo]::InvariantCulture) }

$PageCss = @'
:root{
  --navy:#0B1E3F;
  --bg:#F8FAFC; --card:#FFFFFF; --ink:#0F172A; --body:#334155; --muted:#5B6B80;
  --line:#E2E8F0; --line-2:#C7D2E0; --grp:#EEF2F6;
  --link:#1E3A5F;
  --act:#991B1B; --review:#B8860B; --nc:#5B6B80; --clear:#4F7F5C;
  --bar:#1E3A5F; --bar-soft:#9DB0C6;
  --sans:"IBM Plex Sans", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --mono:"IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  color-scheme:light;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#0A0F16; --card:#111823; --ink:#EAF0F6; --body:#C0CBD8; --muted:#8FA0B3;
    --line:#1E2835; --line-2:#2B3746; --grp:#18212D;
    --link:#C9D6E5;
    --act:#E5484D; --review:#E39B2D; --nc:#8FA0B3; --clear:#8FC2A0;
    --bar:#A9BED6; --bar-soft:#4A5B70;
    color-scheme:dark;
  }
}
:root[data-theme="dark"]{
  --bg:#0A0F16; --card:#111823; --ink:#EAF0F6; --body:#C0CBD8; --muted:#8FA0B3;
  --line:#1E2835; --line-2:#2B3746; --grp:#18212D;
  --link:#C9D6E5;
  --act:#E5484D; --review:#E39B2D; --nc:#8FA0B3; --clear:#8FC2A0;
  --bar:#A9BED6; --bar-soft:#4A5B70;
  color-scheme:dark;
}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0; background:var(--bg); color:var(--body); font-family:var(--sans);
  font-size:15px; line-height:1.55; -webkit-font-smoothing:antialiased;
  padding-inline:max(16px, env(safe-area-inset-left, 0px));
  padding-block:24px 48px; font-variant-numeric:tabular-nums}
.doc{max-width:1040px; margin:0 auto; background:var(--card); border:1px solid var(--line); border-radius:6px; overflow:hidden}
a{color:var(--link); text-decoration:underline; text-underline-offset:2px}
h1,h2,h3{color:var(--ink); margin:0; font-weight:600}
h1{font-size:26px; line-height:1.25; letter-spacing:-.01em}
h2{font-size:19px; line-height:1.3}
h3{font-size:14px; line-height:1.4}
p{margin:0 0 12px; max-width:68ch}
.mono{font-family:var(--mono)}
.eyebrow{font-family:var(--mono); font-size:11px; font-weight:500; letter-spacing:.16em;
  text-transform:uppercase; color:var(--muted); margin:0 0 6px}
.small{font-size:12.5px}
.muted{color:var(--muted)}
.wrap{overflow-wrap:anywhere}
.mast{background:var(--navy); color:#FFFFFF; display:flex; align-items:center; justify-content:space-between;
  gap:16px; flex-wrap:wrap; padding:16px 40px}
.brand{display:flex; align-items:center; gap:12px}
.brand svg{display:block; flex:none}
.wordmark{font-size:19px; font-weight:700; letter-spacing:.10em; line-height:1; color:#FFFFFF}
.mast .prod{font-family:var(--mono); font-size:11px; letter-spacing:.16em; text-transform:uppercase; color:#C7D2E0}
.mast .prod b{color:#FFFFFF; font-weight:600}
.pad{padding:28px 40px}
section{border-top:1px solid var(--line)}
.sec-head{display:flex; align-items:baseline; gap:12px; margin-bottom:14px}
.sec-head .num{font-family:var(--mono); font-size:11px; color:var(--muted); letter-spacing:.08em; flex:none}
.title{padding:28px 40px 8px}
.subject{font-size:19px; font-weight:500; color:var(--ink); margin:6px 0 0; max-width:none}
.what{margin:12px 0 0; color:var(--body)}
.org{display:flex; flex-wrap:wrap; gap:6px 24px; margin:10px 0 0; font-size:12.5px; color:var(--muted)}
.org dt{display:inline; font-family:var(--mono); font-size:11px; letter-spacing:.16em; text-transform:uppercase}
.org dd{display:inline; margin:0 0 0 6px; color:var(--ink); font-weight:500}
.answer{padding:20px 40px 28px; border-top:0}
.lede{font-size:19px; line-height:1.45; color:var(--ink); font-weight:500; max-width:52ch; margin:0 0 18px}
.lede b{font-weight:700}
.tiles{display:grid; grid-template-columns:repeat(4, minmax(0,1fr)); gap:1px; background:var(--line);
  border:1px solid var(--line); border-radius:6px; overflow:hidden; margin:0 0 10px; padding:0; list-style:none}
.tiles li{background:var(--card); padding:12px 14px}
.tiles .k{display:flex; align-items:center; gap:7px; font-size:12.5px; color:var(--body)}
.tiles .v{font-size:24px; font-weight:600; color:var(--ink); line-height:1.2; margin-top:4px}
.stack{display:block; width:100%; height:14px; margin:12px 0 4px}
.stack-cap{display:flex; justify-content:space-between; font-family:var(--mono); font-size:11px; color:var(--muted)}
.s-act{fill:var(--act)} .s-review{fill:var(--review)} .s-clear{fill:var(--clear)}
.first{margin-top:20px; border:1px solid var(--line-2); border-left:3px solid var(--act); border-radius:4px;
  padding:14px 16px; background:var(--card)}
.first h2{font-size:14px; margin-bottom:6px}
.first ol{margin:0; padding-left:20px}
.first li{margin:4px 0; max-width:72ch}
.mk{width:12px; height:12px; flex:none; vertical-align:-1px}
.c-act{color:var(--act)} .c-review{color:var(--review)} .c-nc{color:var(--nc)} .c-clear{color:var(--clear)}
.oc{display:inline-flex; align-items:center; gap:6px; white-space:nowrap}
.paths{display:grid; grid-template-columns:repeat(3, minmax(0,1fr)); gap:16px; margin:0; padding:0; list-style:none}
.path{border:1px solid var(--line); border-radius:6px; padding:16px; display:flex; flex-direction:column; gap:8px}
.path .n{font-size:24px; font-weight:600; color:var(--ink); line-height:1.1}
.path .n span{font-size:12.5px; font-weight:400; color:var(--muted); margin-left:4px}
.path p{margin:0; font-size:15px}
.path .tally{font-size:12.5px; color:var(--muted); margin-top:auto; border-top:1px solid var(--line); padding-top:8px}
.path .prov{font-size:12.5px; color:var(--muted)}
.note{font-size:12.5px; color:var(--muted); margin-top:12px; max-width:80ch}
.scroll{overflow-x:auto; -webkit-overflow-scrolling:touch; border:1px solid var(--line); border-radius:6px}
table{border-collapse:collapse; width:100%; font-size:12.5px; line-height:1.45}
caption{caption-side:top}
.tcap{font-size:12.5px; color:var(--muted); margin:0 0 8px; max-width:none}
th,td{padding:8px 12px; text-align:left; vertical-align:top; border-bottom:1px solid var(--line)}
thead th{font-family:var(--mono); font-size:11px; font-weight:500; letter-spacing:.06em; text-transform:uppercase;
  color:var(--muted); background:var(--bg); white-space:nowrap}
tbody tr:last-child th, tbody tr:last-child td{border-bottom:0}
tbody th{font-weight:500; color:var(--ink)}
td.num, th.num{text-align:right; white-space:nowrap}
.host{font-family:var(--mono); font-size:12.5px; color:var(--ink); overflow-wrap:anywhere; min-width:22ch}
.hn{display:inline-block; max-width:100%; overflow-wrap:anywhere}
.sys{white-space:nowrap}
.acct{font-family:var(--mono); font-size:12.5px; overflow-wrap:anywhere; min-width:21ch}
.raw{font-family:var(--mono); font-size:11px; overflow-wrap:anywhere}
.t-prio{min-width:760px}
.t-kinds{min-width:880px}
.t-all{min-width:820px}
.t-nc{min-width:720px}
.grp th{background:var(--grp); color:var(--ink); font-family:var(--mono); font-size:11px; font-weight:500;
  letter-spacing:.06em; text-transform:uppercase}
.ref{display:block; color:var(--body)}
.ref b{font-family:var(--mono); font-weight:500; color:var(--ink); font-size:11px; letter-spacing:.02em}
.ref + .ref{margin-top:4px}
.rel{display:inline-block; font-family:var(--mono); font-size:11px; padding:1px 6px; border:1px solid var(--line-2);
  border-radius:3px; color:var(--ink); white-space:nowrap}
.rel.ind{border-style:dashed}
.rel + .rel{margin-top:4px}
.more td{color:var(--muted); font-style:italic; text-align:center; background:var(--bg)}
.foot-row th, .foot-row td{border-top:1px solid var(--line-2); font-weight:600; color:var(--ink); background:var(--bg)}
.disclaim{border-left:3px solid var(--line-2); padding:8px 14px; margin:0 0 16px; font-size:12.5px; max-width:none}
.charts{display:grid; grid-template-columns:repeat(2, minmax(0,1fr)); gap:24px}
.chart h3{margin-bottom:4px}
.chart .sub{font-size:12.5px; color:var(--muted); margin:0 0 10px}
.bars{list-style:none; margin:0; padding:0}
.bars li{display:grid; grid-template-columns:minmax(0,1fr) 5ch; column-gap:8px; row-gap:3px; margin:0 0 9px; align-items:center}
.bars .lbl{grid-column:1 / -1; font-size:12.5px; color:var(--body); display:flex; gap:6px; align-items:baseline; min-width:0}
.bars .lbl b{font-family:var(--mono); font-size:11px; font-weight:500; color:var(--ink); flex:none}
.bars .lbl span{overflow-wrap:anywhere}
.bars svg{display:block; width:100%; height:8px}
.bars .val{font-size:12.5px; color:var(--ink); text-align:right}
.bars .grp-lbl{display:block; font-family:var(--mono); font-size:11px; letter-spacing:.06em; text-transform:uppercase; color:var(--muted);
  margin:12px 0 6px}
.bars .grp-lbl:first-child{margin-top:0}
.b-exp{fill:var(--bar)}
.b-ind{fill:url(#hatch)}
.track{fill:var(--line)}
.legend{display:flex; flex-wrap:wrap; gap:6px 18px; font-size:12.5px; color:var(--body); margin:4px 0 16px; padding:0; list-style:none}
.legend li{display:flex; align-items:center; gap:6px}
.legend svg{width:22px; height:8px}
.cov{display:grid; grid-template-columns:repeat(2, minmax(0,1fr)); gap:24px; margin-top:16px}
.scope h3, .blk h3{margin-bottom:8px}
.scope ul, .blk ul{margin:0; padding-left:18px; max-width:80ch}
.scope li, .blk li{margin:0 0 6px}
.scope li b{color:var(--ink); font-weight:600}
.blk{margin-top:24px}
.tactics ul{margin-bottom:14px}
.kv{display:grid; grid-template-columns:max-content minmax(0,1fr); gap:8px 20px; margin:0}
.kv dt{color:var(--ink); font-weight:600; font-size:14px}
.kv dd{margin:0; max-width:80ch}
.scope-line{margin:-6px 0 18px; color:var(--body); max-width:80ch}
.foot{border-top:1px solid var(--line); padding:16px 40px; display:flex; align-items:center; gap:10px;
  font-size:12.5px; color:var(--muted); flex-wrap:wrap}
.foot svg{flex:none}
.vh{position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0 0 0 0); white-space:nowrap}
@media (max-width:860px){
  .charts{grid-template-columns:1fr; gap:28px}
  .paths{grid-template-columns:1fr}
}
@media (max-width:640px){
  body{padding-block:0}
  .doc{border-radius:0; border-inline:0}
  .pad, .title, .answer, .foot{padding-inline:18px}
  .mast{padding:14px 18px}
  .tiles{grid-template-columns:repeat(2, minmax(0,1fr))}
  .cov{grid-template-columns:1fr}
  .lede{font-size:15px}
  .kv{grid-template-columns:1fr; gap:2px}
  .kv dd{margin-bottom:10px}
}
@page{
  margin:14mm 13mm 18mm;
  @bottom-left{content:url("data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 1024 1024%22 width=%2211%22 height=%2211%22%3E%3Crect width=%221024%22 height=%221024%22 rx=%22228.00%22 fill=%22%230B1E3F%22/%3E%3Cpath d=%22M868.00 512.00 A356.00 356.00 0 0 1 690.00 820.31 L615.41 564.69 A116.06 116.06 0 0 0 609.33 448.79 Z%22 fill=%22%2314E4D0%22 stroke=%22%230B1E3F%22 stroke-width=%2216.02%22 stroke-linejoin=%22round%22/%3E%3Cpath d=%22M690.00 820.31 A356.00 356.00 0 0 1 334.00 820.31 L518.07 627.90 A116.06 116.06 0 0 0 615.41 564.69 Z%22 fill=%22%2314E4D0%22 stroke=%22%230B1E3F%22 stroke-width=%2216.02%22 stroke-linejoin=%22round%22/%3E%3Cpath d=%22M334.00 820.31 A356.00 356.00 0 0 1 156.00 512.00 L414.67 575.21 A116.06 116.06 0 0 0 518.07 627.90 Z%22 fill=%22%2314E4D0%22 stroke=%22%230B1E3F%22 stroke-width=%2216.02%22 stroke-linejoin=%22round%22/%3E%3Cpath d=%22M156.00 512.00 A356.00 356.00 0 0 1 334.00 203.69 L408.59 459.31 A116.06 116.06 0 0 0 414.67 575.21 Z%22 fill=%22%2314E4D0%22 stroke=%22%230B1E3F%22 stroke-width=%2216.02%22 stroke-linejoin=%22round%22/%3E%3Cpath d=%22M334.00 203.69 A356.00 356.00 0 0 1 690.00 203.69 L505.93 396.10 A116.06 116.06 0 0 0 408.59 459.31 Z%22 fill=%22%2314E4D0%22 stroke=%22%230B1E3F%22 stroke-width=%2216.02%22 stroke-linejoin=%22round%22/%3E%3Cpath d=%22M690.00 203.69 A356.00 356.00 0 0 1 868.00 512.00 L609.33 448.79 A116.06 116.06 0 0 0 505.93 396.10 Z%22 fill=%22%2314E4D0%22 stroke=%22%230B1E3F%22 stroke-width=%2216.02%22 stroke-linejoin=%22round%22/%3E%3Ccircle cx=%22512.00%22 cy=%22512.00%22 r=%2229.90%22 fill=%22%23D4A84A%22/%3E%3C/svg%3E") "{{FOOT}}";
    font-family:"IBM Plex Mono", ui-monospace, Menlo, monospace; font-size:8pt; color:#5B6B80; vertical-align:middle}
  @bottom-right{content:"Page " counter(page) " of " counter(pages);
    font-family:"IBM Plex Mono", ui-monospace, Menlo, monospace; font-size:8pt; color:#5B6B80; vertical-align:middle}
}
@media print{
  :root, :root:not([data-theme="light"]), :root[data-theme="dark"]{
    --bg:#F8FAFC; --card:#FFFFFF; --ink:#0F172A; --body:#334155; --muted:#5B6B80;
    --line:#D5DCE5; --line-2:#B5C1CF; --grp:#EEF2F6; --link:#1E3A5F;
    --act:#991B1B; --review:#B8860B; --nc:#5B6B80; --clear:#4F7F5C;
    --bar:#1E3A5F; --bar-soft:#9DB0C6; color-scheme:light;
  }
  body{padding:0; background:#FFFFFF; font-size:10.5pt}
  .doc{max-width:none; border:0; border-radius:0}
  .mast, .stack, .grp th, .first, .bars svg, .mk{-webkit-print-color-adjust:exact; print-color-adjust:exact}
  .mast{padding:10px 14px}
  .pad, .title, .answer{padding-inline:0}
  .title{padding-top:16px}
  .foot{display:none}
  .scroll{overflow:visible; border:0}
  .t-prio, .t-kinds, .t-all, .t-nc{min-width:0}
  table{font-size:8.5pt}
  th, td{padding:5px 6px}
  thead{display:table-header-group}
  tr, .path, .chart, .first, .tiles, .disclaim, .cov > div, .blk, .scope > p{break-inside:avoid}
  #scope{break-before:page}
  h2, h3, .sec-head{break-after:avoid}
  .paths{grid-template-columns:repeat(3, minmax(0,1fr))}
  .charts{grid-template-columns:repeat(2, minmax(0,1fr)); gap:16px}
  .cov{grid-template-columns:repeat(2, minmax(0,1fr))}
  .host{min-width:16ch} .acct{min-width:13ch}
  a{color:inherit; text-decoration:none}
}
'@

$PageSymbols = @'
<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">
  <defs>
    <symbol id="gird-mark" viewBox="0 0 1024 1024">
      <rect width="1024" height="1024" rx="228.00" fill="#0B1E3F"/>
      <path d="M868.00 512.00 A356.00 356.00 0 0 1 690.00 820.31 L615.41 564.69 A116.06 116.06 0 0 0 609.33 448.79 Z" fill="#14E4D0" stroke="#0B1E3F" stroke-width="16.02" stroke-linejoin="round"/>
      <path d="M690.00 820.31 A356.00 356.00 0 0 1 334.00 820.31 L518.07 627.90 A116.06 116.06 0 0 0 615.41 564.69 Z" fill="#14E4D0" stroke="#0B1E3F" stroke-width="16.02" stroke-linejoin="round"/>
      <path d="M334.00 820.31 A356.00 356.00 0 0 1 156.00 512.00 L414.67 575.21 A116.06 116.06 0 0 0 518.07 627.90 Z" fill="#14E4D0" stroke="#0B1E3F" stroke-width="16.02" stroke-linejoin="round"/>
      <path d="M156.00 512.00 A356.00 356.00 0 0 1 334.00 203.69 L408.59 459.31 A116.06 116.06 0 0 0 414.67 575.21 Z" fill="#14E4D0" stroke="#0B1E3F" stroke-width="16.02" stroke-linejoin="round"/>
      <path d="M334.00 203.69 A356.00 356.00 0 0 1 690.00 203.69 L505.93 396.10 A116.06 116.06 0 0 0 408.59 459.31 Z" fill="#14E4D0" stroke="#0B1E3F" stroke-width="16.02" stroke-linejoin="round"/>
      <path d="M690.00 203.69 A356.00 356.00 0 0 1 868.00 512.00 L609.33 448.79 A116.06 116.06 0 0 0 505.93 396.10 Z" fill="#14E4D0" stroke="#0B1E3F" stroke-width="16.02" stroke-linejoin="round"/>
      <circle cx="512.00" cy="512.00" r="29.90" fill="#D4A84A"/>
    </symbol>
    <symbol id="o-act" viewBox="0 0 12 12"><path d="M6 .8 11.2 6 6 11.2.8 6Z" fill="currentColor"/></symbol>
    <symbol id="o-nc" viewBox="0 0 12 12"><circle cx="6" cy="6" r="4.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="2.2 1.6"/></symbol>
    <symbol id="o-review" viewBox="0 0 12 12"><circle cx="6" cy="6" r="4.4" fill="none" stroke="currentColor" stroke-width="2.4"/></symbol>
    <symbol id="o-clear" viewBox="0 0 12 12"><path d="M2.2 6.3 4.8 8.8 9.8 3.4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></symbol>
    <pattern id="hatch" width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="4" height="4" style="fill:var(--bar-soft)"/>
      <rect width="1.6" height="4" style="fill:var(--bar)"/>
    </pattern>
    <pattern id="hatch-nc" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="5" height="5" style="fill:var(--card)"/>
      <rect width="2" height="5" style="fill:var(--nc)"/>
    </pattern>
  </defs>
</svg>
'@

# The page's four outcomes: each status of a row is one of them.
$Outcome = [ordered]@{ act = @{ Mark = 'act'; Text = 'Act now' }; nc = @{ Mark = 'nc'; Text = 'Not fully checked' }; review = @{ Mark = 'review'; Text = 'Review' }; clear = @{ Mark = 'clear'; Text = 'Clear' } }
function Get-OutcomeKey([string]$Status) { if ($Status -eq 'act' -or $Status -eq 'review' -or $Status -eq 'clear') { return $Status }; return 'nc' }
function Get-Mark([string]$Key) { return '<svg class="mk c-' + $Key + '" aria-hidden="true"><use href="#o-' + $Key + '"/></svg>' }
# The reference columns of section 4, one per framework in data/mitre.tsv.
$RefColumns = [ordered]@{ attack = 'MITRE ATT&CK'; atlas = 'MITRE ATLAS' }

function Get-ReportPage($D) {
  $e = { param($s) ConvertTo-HtmlText ([string]$s) }
  $pc = { param($n) if ($n -eq 1) { '1 computer' } else { [string]$n + ' computers' } }
  $h = New-Object System.Text.StringBuilder
  $title = 'AI Exposure Report'
  $foot = '  GIRD  \00B7  AI Exposure Report'
  if ($D.Org) { $title += ': ' + $D.Org; $foot += '  \00B7  ' + (ConvertTo-CssText $D.Org) }
  $title += ', ' + $D.Day
  [void]$h.Append('<!doctype html>' + "`n" + '<html lang="en-GB">' + "`n" + '<head>' + "`n" + '<meta charset="utf-8">' + "`n" +
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">' + "`n" + '<meta name="color-scheme" content="light dark">' + "`n" +
    '<title>' + (& $e $title) + '</title>' + "`n" + '<style>' + "`n" + $PageCss.Replace('{{FOOT}}', $foot) + '</style>' + "`n" + '</head>' + "`n" + '<body>' + "`n")
  [void]$h.Append($PageSymbols + "`n" + '<div class="doc">' + "`n")
  [void]$h.Append('<header class="mast"><div class="brand"><svg width="30" height="30" role="img" aria-label="GIRD"><use href="#gird-mark"/></svg>' +
    '<span class="wordmark" aria-hidden="true">GIRD</span></div><div class="prod"><b>Blindspot</b> fleet report</div></header>' + "`n" + '<main>' + "`n")

  [void]$h.Append('<div class="title"><p class="eyebrow">Blindspot, from GIRD</p><h1>AI Exposure Report</h1>')
  if ($D.Org) { [void]$h.Append('<p class="subject wrap">' + (& $e $D.Org) + '</p>') }
  [void]$h.Append('<dl class="org"><div><dt>Report date</dt><dd>' + (& $e $D.Day) + '</dd></div>')
  if ($D.Window) { [void]$h.Append('<div><dt>Results from</dt><dd>' + (& $e $D.Window) + '</dd></div>') }
  [void]$h.Append('</dl><p class="what">What AI coding agents can reach on ' + (& $pc $D.Total) + ', and what was found.</p></div>' + "`n")

  # 01 Summary
  $c = $D.Counts
  $tiles = [ordered]@{ act = $c.act; nc = $D.NotChecked; review = $c.review; clear = $c.clear }
  [void]$h.Append('<section class="answer" aria-labelledby="s-answer"><div class="sec-head"><span class="num">01</span><h2 id="s-answer">Summary</h2></div>')
  [void]$h.Append('<p class="lede"><b>' + $c.act + ' of ' + (& $pc $D.Total) + '</b> ' + $(if ($c.act -eq 1) { 'needs' } else { 'need' }) + ' attention now.')
  if ($D.NotChecked -gt 0) { [void]$h.Append(' ' + $D.NotChecked + ' could not be fully checked.') }
  [void]$h.Append('</p><p class="scope-line">This report covers what Blindspot reads in files on each computer: AI agents, keys and known malware. It does not see the network, sign-ins or the cloud. The full scope is in section 8.</p>')
  [void]$h.Append('<ul class="tiles">')
  foreach ($k in $tiles.PSBase.Keys) { [void]$h.Append('<li><div class="k">' + (Get-Mark $k) + $Outcome[$k].Text + '</div><div class="v">' + $tiles[$k] + '</div></li>') }
  [void]$h.Append('</ul>')
  if ($D.Total -gt 0) {
    $segs = @($tiles.PSBase.Keys | Where-Object { $tiles[$_] -gt 0 })
    [void]$h.Append('<svg class="stack" viewBox="0 0 1000 14" preserveAspectRatio="none" role="img" aria-label="' + (& $e ((& $pc $D.Total) + ': ' + (@($segs | ForEach-Object { [string]$tiles[$_] + ' ' + $Outcome[$_].Text.ToLower() }) -join ', ') + '.')) + '">')
    $x = 0.0
    for ($i = 0; $i -lt $segs.Count; $i++) {
      $k = $segs[$i]; $w = $tiles[$k] / $D.Total * 1000
      if ($i -lt $segs.Count - 1) { $w -= 2 }
      if ($w -lt 0.5) { $w = 0.5 }
      $fill = ' class="s-' + $k + '"'; if ($k -ceq 'nc') { $fill = ' fill="url(#hatch-nc)"' }
      [void]$h.Append('<rect x="' + (Get-Num $x) + '" y="0" width="' + (Get-Num $w) + '" height="14"' + $fill + '><title>' + $Outcome[$k].Text + ': ' + (& $pc $tiles[$k]) + '</title></rect>')
      $x += $w + 2
    }
    [void]$h.Append('</svg><div class="stack-cap"><span>' + (& $pc $D.Total))
    if ($D.OsSplit) { [void]$h.Append(': ' + (& $e $D.OsSplit)) }
    [void]$h.Append('</span></div>')
  }
  if ($D.NotChecked -gt 0) {
    [void]$h.Append('<p class="note">Not fully checked: ' + (@($D.NcGroups | ForEach-Object { [string]$_.N + ' ' + $_.Note }) -join ', ') + '. None of them counts as clear. Section 6 lists them.</p>')
  }
  if ($c.act -gt 0) {
    $steps = @()
    $wiper = @($D.Wiper)
    if ($wiper.Count -gt 0) {
      $on = (& $pc $wiper.Count)
      if ($wiper.Count -le 3) { $on = (@($wiper | ForEach-Object { '<span class="host">' + (& $e $_) + '</span>' }) -join ', ') }
      $steps += 'On ' + $on + ', do not revoke or rotate any GitHub token yet. First stop and remove <span class="mono">gh-token-monitor</span>: it runs a destructive command when the token it uses stops working.'
    }
    if ($D.Malware -gt 0) { $steps += 'From another computer, rotate every key the ' + (& $pc $D.Malware) + ' with a malware incident found could reach. They lead section 3.' }
    $steps += 'Then deal with the ' + (& $pc $c.act) + ' at Act now, in the order section 3 gives.'
    [void]$h.Append('<div class="first"><h2>First thing to do</h2><ol>')
    foreach ($s in $steps) { [void]$h.Append('<li>' + $s + '</li>') }
    [void]$h.Append('</ol></div>')
  }
  [void]$h.Append('</section>' + "`n")

  # 02 What could get out
  [void]$h.Append('<section class="pad" aria-labelledby="s-out"><div class="sec-head"><span class="num">02</span><h2 id="s-out">What could get out</h2></div>')
  [void]$h.Append('<p>These count what was found in files on each computer. They do not show that a key was used, copied or sent anywhere. Each statement counts every one of the ' + (& $pc $D.Total) + ' in this report once: found, none found or not known.</p>')
  [void]$h.Append('<ul class="paths">')
  foreach ($p in $D.Paths) {
    [void]$h.Append('<li class="path"><div class="n">' + $p.Yes + ' <span>' + $(if ($p.Yes -eq 1) { 'computer' } else { 'computers' }) + '</span></div><p>' + (& $e $p.Text) + '.</p>')
    [void]$h.Append('<div class="tally">Found on ' + (& $pc $p.Yes) + ', none found on ' + (& $pc $p.No) + ', not known for ' + (& $pc $p.Unknown) + '.</div>')
    if ($p.Providers.Count -gt 0) { [void]$h.Append('<div class="prov">Providers of those keys: ' + (& $e ($p.Providers -join ', ')) + '.</div>') }
    if ($p.NoOthers -gt 0) {
      if ($p.No -eq 1) { $t = 'The computer with none found also has other accounts that were not read.' }
      else { $t = "$($p.NoOthers) of the $($p.No) computers with none found also " + $(if ($p.NoOthers -eq 1) { 'has' } else { 'have' }) + ' other accounts that were not read.' }
      [void]$h.Append('<div class="prov">' + $t + '</div>')
    }
    [void]$h.Append('</li>')
  }
  [void]$h.Append('</ul><p class="note">Found: an account on the computer showed it. None found: no account showed it, and every account its result lists was read in full, in a result that is fresh, whole and from a run that finished. ' +
    'It speaks for those accounts only: a Windows result reads the person signed in when it ran, and other accounts on that PC are counted on their own. ' +
    'Not known: the computer sent no result, a stale or failed one, one cut to fit or one this tool could not read, or an account in it was partly checked or not checked.</p></section>' + "`n")

  # 03 Computers to deal with first
  [void]$h.Append('<section class="pad" aria-labelledby="s-first"><div class="sec-head"><span class="num">03</span><h2 id="s-first">Computers to deal with first</h2></div>')
  if ($D.ActCount -eq 0) { [void]$h.Append('<p class="muted">No computer is at Act now.</p>') }
  else {
    $cap = 'The ' + $D.Prio.Count + ' most urgent of the ' + (& $pc $D.ActCount) + ' at Act now'
    if ($D.Prio.Count -eq $D.ActCount) { $cap = 'The ' + (& $pc $D.ActCount) + ' at Act now' }
    $cap += ', in order: malware first, then keys an agent has read, then keys an agent could read without asking, then the rest.'
    [void]$h.Append('<p class="tcap" aria-hidden="true">' + $cap + '</p><div class="scroll"><table class="t-prio"><caption class="vh">' + $cap + '</caption>')
    [void]$h.Append('<thead><tr><th scope="col" class="num">#</th><th scope="col">Computer</th><th scope="col">Account</th><th scope="col">System</th><th scope="col">Why</th><th scope="col">First step</th></tr></thead><tbody>')
    $i = 0
    foreach ($r in $D.Prio) {
      $i++
      $os = $r.OS; if (-not $os) { $os = 'Not known' }
      [void]$h.Append('<tr><td class="num">' + $i + '</td><th scope="row" class="host">' + (& $e $r.PC) + '</th><td class="acct">' + (& $e $r.Account).Replace('@', '@<wbr>') + '</td><td class="sys">' + (& $e $os) + '</td><td>' + (& $e $r.Why) + '</td><td>' + (& $e $r.Step) + '</td></tr>')
    }
    if ($D.ActCount -gt $D.Prio.Count) {
      $more = $D.ActCount - $D.Prio.Count
      [void]$h.Append('<tr class="more"><td colspan="6">' + $(if ($more -eq 1) { '1 more computer at Act now is' } else { "$more more computers at Act now are" }) + ' in section 7, in the same order.</td></tr>')
    }
    [void]$h.Append('</tbody></table></div>')
  }
  [void]$h.Append('</section>' + "`n")

  # 04 Findings by kind
  [void]$h.Append('<section class="pad" id="findings" aria-labelledby="s-kinds"><div class="sec-head"><span class="num">04</span><h2 id="s-kinds">Findings by kind</h2></div>')
  if ($D.Kinds.Count -eq 0) { [void]$h.Append('<p class="muted">No finding in the results that were read.</p>') }
  else {
    $cols = @($RefColumns.PSBase.Keys)
    [void]$h.Append('<p class="disclaim">' + (& $e $D.Meaning) + '</p>')
    $cap = 'Computers with each kind of finding, of the ' + (& $pc $D.Total) + ' in this report.'
    [void]$h.Append('<p class="tcap" aria-hidden="true">' + $cap + '</p><div class="scroll"><table class="t-kinds"><caption class="vh">' + $cap + '</caption>')
    [void]$h.Append('<thead><tr><th scope="col">Finding</th><th scope="col" class="num">Computers</th><th scope="col">Relation</th>')
    foreach ($fw in $cols) { [void]$h.Append('<th scope="col">' + (& $e $RefColumns[$fw]) + '</th>') }
    [void]$h.Append('</tr></thead><tbody>')
    $span = 3 + $cols.Count
    foreach ($lv in @(@{ Level = 'act'; Key = 'act'; Text = 'Act now' }, @{ Level = 'review'; Key = 'review'; Text = 'Review' }, @{ Level = 'partial'; Key = 'nc'; Text = 'Not fully checked' })) {
      $rows = @($D.Kinds | Where-Object { $_.Level -ceq $lv.Level })
      if ($rows.Count -eq 0) { continue }
      [void]$h.Append('<tr class="grp"><th scope="rowgroup" colspan="' + $span + '"><span class="oc">' + (Get-Mark $lv.Key) + $lv.Text + '</span></th></tr>')
      foreach ($k in $rows) {
        $rel = '<span class="muted">Not mapped</span>'
        if ($k.Rels.Count -gt 0) { $rel = (@($k.Rels | ForEach-Object { '<span class="rel' + $(if ($_ -ceq 'Indicator') { ' ind' } else { '' }) + '">' + $_ + '</span>' }) -join '<br>') }
        [void]$h.Append('<tr><th scope="row">' + (& $e $k.Label) + '</th><td class="num">' + $k.Count + '</td><td>' + $rel + '</td>')
        if ($k.Joint) { [void]$h.Append('<td colspan="' + $cols.Count + '"><span class="ref muted">' + (& $e $k.Joint) + '</span></td>') }
        else {
          foreach ($fw in $cols) {
            $cell = $k.Cells[$fw]; $t = ''
            foreach ($r in $cell.Refs) {
              $t += '<span class="ref"><b>' + (Get-Link $r.Url $r.Id) + '</b> ' + (& $e $r.Name) + '</span>'
              if ($r.Only) { $t += '<span class="ref muted">' + (& $e $r.Only) + '</span>' }
            }
            if ($cell.Text) { $t += '<span class="ref muted">' + (& $e $cell.Text) + '</span>' }
            [void]$h.Append('<td>' + $t + '</td>')
          }
        }
        [void]$h.Append('</tr>')
      }
    }
    [void]$h.Append('</tbody></table></div>')
  }
  [void]$h.Append('</section>' + "`n")

  # 05 Summary by technique
  [void]$h.Append('<section class="pad" aria-labelledby="s-sum"><div class="sec-head"><span class="num">05</span><h2 id="s-sum">Summary by technique</h2></div>')
  if ($D.Techniques.Count -eq 0) { [void]$h.Append('<p class="muted">No finding relates to a MITRE technique.</p>') }
  else {
    $max = 1
    foreach ($t in $D.Techniques) { foreach ($rel in $RelText.Keys) { if ($t.$rel -gt $max) { $max = $t.$rel } } }
    $relCls = @{ exposure = 'exp'; indicator = 'ind' }
    [void]$h.Append('<div class="sumfig"><ul class="legend" aria-label="Relations">')
    foreach ($rel in $RelText.Keys) { [void]$h.Append('<li><svg viewBox="0 0 22 8" aria-hidden="true"><rect width="22" height="8" rx="2" class="b-' + $relCls[$rel] + '"/></svg>' + $rel.Substring(0, 1).ToUpper() + $rel.Substring(1) + '</li>') }
    [void]$h.Append('</ul><div class="charts">')
    foreach ($fw in @(@{ Key = 'attack'; Title = 'MITRE ATT&CK technique'; Sub = 'Computers, Enterprise ' + $MitreAttackVersion }, @{ Key = 'atlas'; Title = 'MITRE ATLAS technique'; Sub = 'Computers, release ' + $MitreAtlasVersion })) {
      $mine = @($D.Techniques | Where-Object { $_.FwKey -ceq $fw.Key })
      [void]$h.Append('<div class="chart"><h3>' + (& $e $fw.Title) + '</h3><p class="sub">' + (& $e $fw.Sub) + '</p>')
      if ($mine.Count -eq 0) { [void]$h.Append('<p class="sub">No finding relates to one.</p></div>'); continue }
      [void]$h.Append('<ul class="bars">')
      foreach ($rel in $RelText.Keys) {
        $on = @($mine | Where-Object { $_.$rel -gt 0 } | Sort-Object @{ Expression = { $_.$rel }; Descending = $true })
        if ($on.Count -eq 0) { continue }
        [void]$h.Append('<li class="grp-lbl">' + $rel.Substring(0, 1).ToUpper() + $rel.Substring(1) + '</li>')
        foreach ($t in $on) {
          $w = $t.$rel / $max * 100; if ($w -lt 1.5) { $w = 1.5 }
          [void]$h.Append('<li class="bar ' + $relCls[$rel] + '"><div class="lbl"><b>' + (& $e $t.Id) + '</b><span>' + (& $e $t.Name) + '</span></div>' +
            '<svg viewBox="0 0 100 8" preserveAspectRatio="none" aria-hidden="true"><rect width="100" height="8" class="track"/><rect width="' + (Get-Num $w) + '" height="8" class="b-' + $relCls[$rel] + '"/></svg><span class="val">' + $t.$rel + '</span></li>')
        }
      }
      [void]$h.Append('</ul></div>')
    }
    [void]$h.Append('</div><p class="note">A computer counts once for each technique, in each relation that applies to it. The counts per finding are in section 4.</p></div>')
  }
  [void]$h.Append('<div class="blk tactics">')
  if ($D.Tactics.Count -eq 0) { [void]$h.Append('<p>No finding in this report relates to a MITRE tactic.</p>') }
  else {
    foreach ($fw in $D.Tactics.PSBase.Keys) {
      [void]$h.Append('<h3>' + (& $e $fw) + ' tactics the findings in this report relate to</h3><ul>')
      foreach ($x in $D.Tactics[$fw]) { [void]$h.Append('<li>' + (& $e $x) + '</li>') }
      [void]$h.Append('</ul>')
    }
    [void]$h.Append('<p class="note">A tactic is listed because a technique a finding in this report relates to belongs to it. Blindspot checks for none of these techniques in use.</p>')
  }
  [void]$h.Append('</div></section>' + "`n")

  # 06 Computers not fully checked
  [void]$h.Append('<section class="pad" aria-labelledby="s-nc"><div class="sec-head"><span class="num">06</span><h2 id="s-nc">Computers not fully checked</h2></div>')
  if ($D.NotChecked -eq 0) { [void]$h.Append('<p class="muted">Every computer sent a fresh result this tool could read.</p>') }
  else {
    $cap = (& $pc $D.NotChecked) + ', by reason. None of them counts as clear.'
    [void]$h.Append('<p class="tcap" aria-hidden="true">' + $cap + '</p><div class="scroll"><table class="t-nc"><caption class="vh">' + $cap + '</caption>')
    [void]$h.Append('<thead><tr><th scope="col">Reason</th><th scope="col" class="num">Computers</th><th scope="col">Which</th><th scope="col">What to do</th></tr></thead><tbody>')
    foreach ($g in $D.NcGroups) {
      [void]$h.Append('<tr class="grp"><th scope="rowgroup" colspan="4"><span class="oc">' + (Get-Mark 'nc') + (& $e $g.Label) + ', ' + $g.N + '</span></th></tr>')
      foreach ($r in $g.Reasons) {
        $hl = @($r.Hosts); $hosts = ''
        for ($j = 0; $j -lt $hl.Count; $j++) { $hosts += '<span class="hn">' + (& $e $hl[$j]) + $(if ($j -lt $hl.Count - 1) { ',</span> ' } else { '</span>' }) }
        [void]$h.Append('<tr><th scope="row">' + (& $e $r.Why) + '</th><td class="num">' + @($r.Hosts).Count + '</td><td class="host">' + $hosts + '</td><td>' + (& $e $r.Step) + '</td></tr>')
      }
    }
    [void]$h.Append('<tr class="foot-row"><th scope="row">Total</th><td class="num">' + $D.NotChecked + '</td><td colspan="2">' + (& $e $D.NcOsSplit) + '</td></tr></tbody></table></div>')
  }
  if ($D.Notes.Count -gt 0) {
    [void]$h.Append('<div class="blk"><h3>Could not list every PC</h3><ul>')
    foreach ($n in $D.Notes) { [void]$h.Append('<li>' + (& $e $n) + '</li>') }
    [void]$h.Append('</ul></div>')
  }
  [void]$h.Append('<div class="blk"><h3>Limits of these results</h3><ul>')
  foreach ($x in $D.Limits) { [void]$h.Append('<li>' + (& $e $x) + '</li>') }
  [void]$h.Append('</ul></div></section>' + "`n")

  # 07 Every computer
  [void]$h.Append('<section class="pad" id="every" aria-labelledby="s-all"><div class="sec-head"><span class="num">07</span><h2 id="s-all">Every computer</h2></div>')
  $cap = 'All ' + (& $pc $D.Total) + ', Act now first in the order of section 3, then not fully checked, Review and Clear.'
  if ($D.Total -eq 1) { $cap = 'The 1 computer in this report.' }
  if ($D.Total -gt 0) {
    [void]$h.Append('<p class="tcap" aria-hidden="true">' + $cap + '</p><div class="scroll"><table class="t-all"><caption class="vh">' + $cap + '</caption>')
    [void]$h.Append('<thead><tr><th scope="col">Computer</th><th scope="col">Account</th><th scope="col">System</th><th scope="col">Outcome</th><th scope="col">Found</th><th scope="col">Result from</th></tr></thead><tbody>')
    foreach ($r in $D.All) {
      $k = Get-OutcomeKey $r.Status
      $os = $r.OS; if (-not $os) { $os = 'Not known' }
      $found = (& $e $r.Found)
      if ($r.Why) { $found += $(if ($found) { '<br>' } else { '' }) + '<span class="muted">' + (& $e ($r.Why.Substring(0, 1).ToUpper() + $r.Why.Substring(1))) + '</span>' }
      if ($r.Raw) { $found += '<br><span class="raw">' + (& $e $r.Raw) + '</span>' }
      [void]$h.Append('<tr><th scope="row" class="host">' + (& $e $r.PC) + '</th><td class="acct">' + (& $e $r.Account).Replace('@', '@<wbr>') + '</td><td class="sys">' + (& $e $os) + '</td><td><span class="oc">' + (Get-Mark $k) + (& $e $r.StatusText) + '</span></td><td>' + $found + '</td><td class="sys">' + (& $e $r.At) + '</td></tr>')
    }
    [void]$h.Append('</tbody></table></div>')
  }
  [void]$h.Append('<div class="blk src"><h3>Where these results came from</h3><dl class="kv">')
  [void]$h.Append('<dt>Sources</dt><dd>' + (& $e $D.Sources) + '</dd>')
  if ($D.Window) { [void]$h.Append('<dt>Results from</dt><dd>' + (& $e $D.Window) + '</dd>') }
  [void]$h.Append('<dt>Stale</dt><dd>A result older than ' + $D.StaleDays + ' days counts as stale.</dd><dt>Built</dt><dd>' + (& $e $D.Now) + '</dd></dl></div></section>' + "`n")

  # 08 Scope and method: the same in every report.
  [void]$h.Append('<section class="pad scope" id="scope" aria-labelledby="s-scope"><div class="sec-head"><span class="num">08</span><h2 id="s-scope">Scope and method</h2></div>')
  [void]$h.Append('<p>Blindspot reads files on each computer. It finds things an attack could use, such as keys stored where they can be read and AI agents allowed to run commands without asking, and traces of the malware incidents on its list. It does not watch for attacks and does not detect any technique in use.</p>')
  [void]$h.Append('<div class="cov"><div><h3>Looks at</h3><ul>' +
    '<li><b>AI coding agents</b>, and which are set to run commands without asking.</li>' +
    '<li><b>Keys</b> stored in files, in shell history, in AI agent session files, in MCP server configs and in Claude Code allow lists.</li>' +
    '<li><b>SSH keys</b> without a passphrase, and links to authorized_keys.</li>' +
    '<li><b>Known malware</b>: package versions, editor extensions and files from the incidents on its list.</li>' +
    '<li><b>Tools</b> with a published security fix, hosted platforms that leaked stored secrets, and project settings that act when a folder opens.</li>' +
    '</ul></div><div><h3>Does not look at</h3><ul>')
  foreach ($x in $NotLooked) { $i = $x.IndexOf(':'); if ($i -gt 0) { [void]$h.Append('<li><b>' + (& $e $x.Substring(0, $i)) + '</b>' + (& $e $x.Substring($i)) + '</li>') } else { [void]$h.Append('<li>' + (& $e $x) + '</li>') } }
  [void]$h.Append('</ul></div></div>')
  [void]$h.Append('<div class="blk"><h3>How results are counted</h3><dl class="kv">' +
    '<dt>Act now</dt><dd>Something to deal with now: traces of malware, a key stored where it can be read, or a link to authorized_keys.</dd>' +
    '<dt>Review</dt><dd>Something to change or confirm, not urgent.</dd>' +
    '<dt>Not fully checked</dt><dd>A computer that sent ' + $NotCheckedWhy + '. It never counts as clear.</dd>' +
    '<dt>Clear</dt><dd>Every account the result lists was read in full and nothing was found. It does not show that no key has left the computer.</dd>' +
    '<dt>Windows</dt><dd>A result covers the person signed in when it ran. Other accounts on that PC are not read.</dd>' +
    '<dt>Mac</dt><dd>A result covers every local account with a user ID of 500 or above.</dd>' +
    '<dt>Counting</dt><dd>Each row of the export files counts as one computer. A computer counts once in each statement, table row or chart bar, however many keys or agents it has, and can appear in several.</dd></dl></div>')
  [void]$h.Append('<div class="blk"><h3>Attack tactics Blindspot findings can relate to</h3><dl class="kv">')
  foreach ($fw in @('attack', 'atlas')) {
    $tl = @()
    foreach ($m in $MitreRows) { if ($m.Fw -ceq $fw -and $m.Rel -cne 'none') { foreach ($t in @($m.Tactics)) { if ($tl -cnotcontains $t) { $tl += $t } } } }
    [void]$h.Append('<dt>' + (& $e $FwName[$fw]) + '</dt><dd>' + (& $e ($tl -join ', ')) + '</dd>')
  }
  [void]$h.Append('</dl></div>')
  [void]$h.Append('<div class="blk"><h3>How results are handled</h3><dl class="kv">' +
    '<dt>Source</dt><dd>Each computer''s own saved result, read from the MDM''s export. A result holds counts and names from fixed lists and the names of accounts, never a file path, a file''s contents or a key. The full result stays on the computer: to see which files, the person runs Blindspot on their own account.</dd>' +
    '<dt>Building the report</dt><dd>The report is built on one computer from the export files and makes no network request.</dd>' +
    '<dt>Frameworks</dt><dd>MITRE ATT&amp;CK Enterprise ' + (& $e $MitreAttackVersion) + '. MITRE ATLAS release ' + (& $e $MitreAtlasVersion) + '.</dd></dl></div>')
  [void]$h.Append('<div class="blk"><h3>Attribution</h3><ul><li>' + (& $e $D.Credit) + '</li><li>OWASP Top 10 for LLM Applications is referenced by name only.</li></ul></div></section>' + "`n")

  [void]$h.Append('</main>' + "`n" + '<footer class="foot"><svg width="16" height="16" aria-hidden="true"><use href="#gird-mark"/></svg><span>Blindspot is open source, made by GIRD. <a href="https://gird.ai">gird.ai</a></span></footer>' + "`n")
  [void]$h.Append('</div>' + "`n" + '</body>' + "`n" + '</html>' + "`n")
  return $h.ToString()
}

function Get-ReportCsv($Rows) {
  $csv = New-Object System.Text.StringBuilder
  [void]$csv.AppendLine((@('pc', 'user', 'status', 'why', 'checked_at', 'details', 'intune_last_report', 'output', 'mitre', 'mitre_note', 'mitre_source',
    'run_without_asking_and_key', 'run_without_asking_key_providers', 'key_in_agent_sessions', 'token_in_mcp_config', 'os', 'source', 'last_seen') | ForEach-Object { ConvertTo-CsvCell $_ }) -join ',')
  foreach ($r in $Rows) {
    $refs = @()
    foreach ($m in @($r.Refs)) { $t = $FwName[$m.Fw] + ' ' + (Get-RefText $m); if ($refs -cnotcontains $t) { $refs += $t } }
    $note = ''; $src = ''
    if ($refs.Count -gt 0) { $note = $MitreMeaning; $src = $MitreSource }
    $prov = @($r.AgentKeyProviders | ForEach-Object { if ($_) { $_ } else { 'not named' } }) -join ','
    $cells = @($r.PC, $r.User, $r.Status, $r.Why, $r.CheckedAt, $r.Details, $r.LastReport, $r.Output, ($refs -join '; '), $note, $src,
      $r.AgentKey, $prov, $r.Sessions, $r.McpTokens, $r.OS, $r.Source, $r.LastSeen)
    [void]$csv.AppendLine((@($cells | ForEach-Object { ConvertTo-CsvCell ([string]$_) })) -join ',')
  }
  return $csv.ToString()
}

# --- Saving ------------------------------------------------------------------------------------

function Get-OutDir {
  $d = $Opt.OutDir
  if (-not $d) { $d = '.' }
  $rp = @(Resolve-Path -LiteralPath $d -ErrorAction SilentlyContinue)
  if ($rp.Count -ne 1 -or $rp[0].Provider.Name -cne 'FileSystem' -or -not [IO.Directory]::Exists($rp[0].ProviderPath)) {
    Stop-Plain "$d is not a folder on disk. Give a folder with -OutDir, or leave it out to save in this folder."
  }
  return $rp[0].ProviderPath
}

function Save-Report([string]$Dir, [string]$Stamp, [string]$Csv, [string]$Html) {
  try {
    for ($n = 1; $n -le 100; $n++) {
      $base = [IO.Path]::Combine($Dir, 'blindspot-report-' + $Stamp + $(if ($n -gt 1) { '-' + $n } else { '' }))
      if ((Test-Taken ($base + '.csv')) -or (Test-Taken ($base + '.html'))) { continue }
      try { New-ReportFile ($base + '.csv') $Csv $true }
      catch { if (Test-Taken ($base + '.csv')) { continue }; throw }
      try { New-ReportFile ($base + '.html') $Html $false }
      catch {
        [IO.File]::Delete($base + '.csv')
        if (Test-Taken ($base + '.html')) { continue }
        throw
      }
      return $base
    }
  } catch {
    $x = Get-Inner $_.Exception
    if (Test-NoAccess $x) { Stop-Plain "No permission to save the report in $Dir. Run it from a folder you can write to, or add -OutDir with one." }
    if ($x -is [IO.IOException]) { Stop-Plain "Could not save the report in $($Dir): $(Get-Plain $x.Message) Free some space or add -OutDir with another folder." }
    throw
  }
  Stop-Plain "100 reports from this minute are already in $Dir, so this one was not saved."
}

function Invoke-Report {
  $dir = Get-OutDir
  $files = @(Get-InputFiles)
  $now = [DateTime]::UtcNow
  $rows = New-Object System.Collections.ArrayList
  $notes = New-Object System.Collections.ArrayList
  $sources = [ordered]@{}
  foreach ($f in $files) {
    $got = Read-ExportFile $f $now
    $sources[$f.Label] = $got.Rows.Count
    foreach ($r in $got.Rows) { [void]$rows.Add($r) }
    foreach ($n in $got.Notes) { if (-not $notes.Contains($n)) { [void]$notes.Add($n) } }
  }
  $sorted = @($rows | Sort-Object @{ Expression = { $StatusOrder[$_.Status] } }, @{ Expression = { $_.PC } })
  $data = Get-ReportData $sorted $notes.ToArray() $sources $now (Get-RepeatCount $rows) (Get-Plain $Opt.Organisation).Trim()
  $base = Save-Report $dir ($now.ToString('yyyyMMdd-HHmm', [Globalization.CultureInfo]::InvariantCulture)) (Get-ReportCsv $sorted) (Get-ReportPage $data)
  foreach ($n in $notes) { Write-Host ('Note: ' + $n) }
  $c = $data.Counts
  Write-Host ("Read $($sorted.Count) computer" + $(if ($sorted.Count -eq 1) { '' } else { 's' }) + ' from ' + (@($sources.PSBase.Keys) -join ', ') + '.')
  Write-Host ("Need attention now: $($c.act). To review: $($c.review). Clear: $($c.clear).")
  Write-Host ("Not checked: $($data.NotChecked) ($NotCheckedWhy). None of these counts as clear.")
  Write-Host ('Report: ' + $base + '.html (and the same rows in ' + [IO.Path]::GetFileName($base) + '.csv beside it)')
  if ($Opt.Open) { Invoke-Item -LiteralPath ($base + '.html') }
}

try { Invoke-Report }
catch {
  $msg = [string]$_.Exception.Message
  if ($msg.StartsWith('Stopped: ', [StringComparison]::Ordinal)) { $msg = $msg.Substring(9) }
  else { $msg = 'Could not finish the report: ' + $msg }
  Stop-Tool $msg
}
exit 0
