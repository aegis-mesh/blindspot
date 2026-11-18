<#
Blindspot fleet report: one report from the Blindspot results your MDM collected.
https://gird.ai/blindspot

Export your computers from your MDM as a CSV file, with the column that holds the Blindspot
result, then run:

  gird-report.ps1 export.csv

It finds the computer name and result columns, the delimiter and the encoding by itself, and saves
an HTML and a CSV report in the folder you run it from. Several export files are fine. It reads
files only: no sign-in, no network request, no administrator rights.

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
  Write-Host 'Only if it guesses wrong: -NameColumn <name>, -ResultColumn <name>, -SeenColumn <name>,'
  Write-Host '-OsColumn <name>, -StaleDays <days>, -OutDir <folder>. -Open opens the report when it is done.'
}

$Opt = @{ NameColumn = ''; ResultColumn = ''; SeenColumn = ''; OsColumn = ''; StaleDays = '3'; OutDir = ''; Open = $false; Help = $false }
$Files = New-Object System.Collections.ArrayList
$Valued = @('NameColumn', 'ResultColumn', 'SeenColumn', 'OsColumn', 'StaleDays', 'OutDir', 'FromFile')
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
    if ($i + 1 -ge $argv.Count) { Stop-Tool ("-$n needs a value after it, such as -$n " + $(if ($n -eq 'StaleDays') { '5' } elseif ($n -eq 'OutDir') { 'reports' } else { '"Computer Name"' }) + '.') 2 }
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
$ItemOrder = @('wiper', 'incidents', 'lockfile', 'planted', 'run-without-asking', 'keys', 'history', 'sessions', 'mcp-tokens',
  'allow-lists', 'ssh-links', 'ssh-open', 'update-tools', 'platforms', 'on-open', 'to-read', 'remove', 'update', 'possible',
  'tmp-wiper', 'tmp-marks', 'partial')
$ActItems = @('wiper', 'incidents', 'lockfile', 'planted', 'keys', 'history', 'sessions', 'mcp-tokens', 'allow-lists', 'ssh-links')
$NoArg = @('wiper', 'tmp-wiper', 'partial')
$NumArg = @('planted', 'history', 'sessions', 'mcp-tokens', 'allow-lists', 'ssh-links', 'ssh-open', 'on-open', 'to-read')
$ListArg = @('incidents', 'lockfile', 'run-without-asking', 'update-tools', 'platforms', 'remove', 'update', 'possible', 'tmp-marks')
$FailReasons = @('host_32bit', 'system_account', 'language_mode', 'unpack', 'save', 'start', 'no_output')
$WinWords = @('deadline', 'time_limit', 'bad_output')
$MacWords = @('name', 'no_login_shell', 'home_missing', 'home_link', 'home_owner', 'home_shared', 'home_system', 'home_name',
  'home_no_answer', 'sudo', 'bad_output', 'time_limit', 'deadline', 'copy_changed')
$AnyWord = @($FailReasons + $WinWords + $MacWords)
$Kinds = [ordered]@{
  'wiper' = 'gh-token-monitor wiper installed'
  'incidents' = 'Malware incident found'
  'lockfile' = 'Malware versions in a lockfile'
  'planted' = 'Files a worm plants in a project'
  'keys' = 'Keys in plain text'
  'history' = 'Keys in shell history'
  'sessions' = 'Keys in agent sessions'
  'mcp-tokens' = 'Tokens in MCP configs'
  'allow-lists' = 'Keys in Claude Code allow lists'
  'ssh-links' = 'Links to authorized_keys'
  'run-without-asking' = 'Agent set to run commands without asking'
  'ssh-open' = 'SSH keys without a passphrase'
  'update-tools' = 'Tools with a security fix to install'
  'update' = 'Package versions to update'
  'remove' = 'Extensions to remove'
  'platforms' = 'Hosted platform that leaked secrets'
  'on-open' = 'Project settings that act when a folder opens'
  'to-read' = 'Files named like worm files, to read'
  'possible' = 'Possible signs of malware'
  'tmp-wiper' = 'Wiper logs in a shared folder'
  'tmp-marks' = 'Malware markers in a shared folder'
  'partial' = 'Partly checked'
}
# >>> mitre: generated from data/mitre.tsv by tools/gen.sh. Edit that file, then run it.
$MitreAttackVersion = 'v20.1'
$MitreAtlasVersion = '2026.10'
$MitreRows = @(
  @{ Word = 'wiper'; Os = 'mac'; Scope = @(); Fw = 'attack'; Id = 'T1543.001'; Name = 'Create or Modify System Process: Launch Agent'; Tactics = @('Persistence', 'Privilege Escalation'); Rel = 'indicator'; Url = 'https://attack.mitre.org/techniques/T1543/001/'; Note = '' }
  @{ Word = 'wiper'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1485'; Name = 'Data Destruction'; Tactics = @('Impact'); Rel = 'armed'; Url = 'https://attack.mitre.org/techniques/T1485/'; Note = '' }
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
  @{ Word = 'sessions'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0085.002'; Name = 'Data from AI Services: Conversation Context and Memory'; Tactics = @('Collection'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0085.002'; Note = '' }
  @{ Word = 'mcp-tokens'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.001'; Name = 'Unsecured Credentials: Credentials In Files'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/001/'; Note = '' }
  @{ Word = 'mcp-tokens'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0083'; Name = 'Credentials from AI Agent Configuration'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0083'; Note = '' }
  @{ Word = 'allow-lists'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1552.001'; Name = 'Unsecured Credentials: Credentials In Files'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1552/001/'; Note = '' }
  @{ Word = 'allow-lists'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0083'; Name = 'Credentials from AI Agent Configuration'; Tactics = @('Credential Access'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0083'; Note = '' }
  @{ Word = 'ssh-links'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1098.004'; Name = 'Account Manipulation: SSH Authorized Keys'; Tactics = @('Persistence', 'Privilege Escalation'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1098/004/'; Note = '' }
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
  @{ Word = 'on-open'; Os = 'all'; Scope = @(); Fw = 'attack'; Id = 'T1195.001'; Name = 'Supply Chain Compromise: Compromise Software Dependencies and Development Tools'; Tactics = @('Initial Access'); Rel = 'exposure'; Url = 'https://attack.mitre.org/techniques/T1195/001/'; Note = '' }
  @{ Word = 'on-open'; Os = 'all'; Scope = @(); Fw = 'atlas'; Id = 'AML.T0081'; Name = 'Modify AI Agent Configuration'; Tactics = @('Persistence', 'Defense Evasion'); Rel = 'exposure'; Url = 'https://atlas.mitre.org/techniques/AML.T0081'; Note = '' }
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

$StatusText = [ordered]@{
  act = 'Act now'
  not_checked = 'Not checked'
  failed = 'Failed'
  stale = 'Not checked: stale'
  no_result = 'Not checked: no result'
  review = 'Review'
  clear = 'Nothing found'
}


$MitreMeaning = 'MITRE ATT&CK and ATLAS references show which attack technique each finding relates to. Blindspot reads files on each computer. It does not watch for attacks and does not detect any technique in use. "Exposure" means Blindspot found something a technique could exploit. "Indicator" means it found a trace that a published incident links to the technique. "Armed" means it found something installed that carries out the technique when it is triggered. The mapping is Blindspot''s own, not MITRE''s.'
$MitreSource = 'References: MITRE ATT&CK Enterprise ' + $MitreAttackVersion + ' and MITRE ATLAS ' + $MitreAtlasVersion + '. ' +
  [char]0xA9 + ' 2026 The MITRE Corporation. This work is reproduced and distributed with the permission of The MITRE Corporation. ' +
  'The MITRE Corporation (MITRE) hereby grants you a non-exclusive, royalty-free license to use ATT&CK' + [char]0xAE +
  ' for research, development, and commercial purposes. Any copy you make for such purposes is authorized provided that you reproduce MITRE''s copyright designation and this license in any such copy. ' +
  'MITRE ATT&CK and ATT&CK are registered trademarks of The MITRE Corporation. MITRE ATLAS data: Copyright 2021-2026 MITRE, licensed under the Apache License, Version 2.0. ' +
  'The mapping of findings to techniques is Blindspot''s own, not MITRE''s.'
$FwName = @{ attack = 'ATT&CK'; atlas = 'ATLAS' }
$RelText = @{ exposure = 'Exposure for'; indicator = 'Indicator of'; armed = 'Armed for' }

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

function Get-PathState($Row, [scriptblock]$Found) {
  $r = @{ State = 'unknown'; Providers = @() }
  if (-not $Row.Known) { return $r }
  $yes = $false; $open = $Row.More; $any = $false; $prov = @()
  foreach ($a in @($Row.Accts)) {
    if ($a.Machine) { continue }
    $any = $true
    if (& $Found $a.Items) {
      $yes = $true
      $kv = [string]$a.Items['keys']; $sp = $kv.IndexOf(' ')
      if ($sp -ge 0) { foreach ($x in $kv.Substring($sp + 1).Split(',')) { if ($prov -cnotcontains $x) { $prov += $x } } }
      elseif ($kv -and $prov -cnotcontains '') { $prov += '' }
    }
    elseif ($a.Outcome -ceq 'not_checked') { $open = $true }
  }
  if ($yes) { $r.State = 'yes'; $r.Providers = $prov }
  elseif (-not $open -and $any) { $r.State = 'no' }
  return $r
}

function Get-RefText($M) {
  $t = $RelText[$M.Rel] + ' ' + $M.Id + ' ' + $M.Name
  if ($M.Rel -ceq 'armed') { $t += ': installed, runs when triggered' }
  return $t
}

function Get-PcCount([int]$N) { if ($N -eq 1) { return '1 computer' }; return "$N computers" }


function New-Row([string]$Pc, [string]$User, [string]$Raw, [string]$Source, [string]$Os) {
  return [ordered]@{
    PC = $Pc; User = $User; Id = ''; Status = ''; Why = ''; CheckedAt = ''; Details = ''; Kinds = @(); Output = $Raw
    Known = $false; Win = $false; More = $false; Accts = @(); OtherProfiles = 0; Refs = @()
    AgentKey = 'unknown'; AgentKeyProviders = @(); Sessions = 'unknown'; McpTokens = 'unknown'
    Source = $Source; OS = $Os; LastSeen = ''; LastReport = ''
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
  switch ($p.Outcome) {
    'failed' { $w = 'the check could not run'; if ($p.Reason) { $w += ' (' + $p.Reason.Replace('_', ' ') + ')' }; $why += $w }
    'not_checked' { $why += 'partly checked' }
  }
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
$ResultShape = '^(v[0-9]{1,3} [a-z_]{1,20} [0-9]{4}-|stale: last run |failed: the run started |none$|unreadable$|blindspot (failed|act|not_checked|review|clear) accounts=)'

function Stop-Plain([string]$Message) { throw ('Stopped: ' + $Message) }

function Get-Inner($E) { $x = $E; while ($x.InnerException) { $x = $x.InnerException }; return $x }
# .NET on macOS and Linux reports a refused open as an IOException with errno 13, not UnauthorizedAccessException.
function Test-NoAccess($X) { return ($X -is [UnauthorizedAccessException] -or $X.HResult -eq 13 -or $X.HResult -eq -2147024891) }

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
    if ($e -is [IO.IOException]) { Stop-Plain "$Label is open in another program, such as Excel, which keeps others from reading it. Close it there and run it again." }
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
  $idx = @{ Name = -1; Result = -1; Seen = -1; Os = -1; User = -1; Id = -1; Det = -1; Note = -1 }
  $ours = @($ExportColumns | Where-Object { $head -ccontains $_ }).Count -eq $ExportColumns.Count
  if ($ours) {
    $idx.Name = [Array]::IndexOf($head, 'Device name'); $idx.Result = [Array]::IndexOf($head, 'Result'); $idx.Seen = [Array]::IndexOf($head, 'Last reported')
    $idx.Os = [Array]::IndexOf($head, 'OS'); $idx.User = [Array]::IndexOf($head, 'User'); $idx.Id = [Array]::IndexOf($head, 'Device id')
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
    if ($cand.Count -gt 1) { $cand = $strong }
    if ($cand.Count -eq 0) {
      Stop-Plain ("$Label holds no Blindspot result. It looked in every column for a value that starts with v1, or reads none, stale, failed or unreadable. Its columns, with a value from each:`n" +
        (Get-ColumnList $head $sample) + "`nExport the column that holds the Blindspot result too (in Jamf Pro the extension attribute, in Intune the custom attribute's Result), and run it again.")
    }
    if ($cand.Count -gt 1) {
      Stop-Plain ("Could not tell which column of $Label holds the Blindspot result: " + (@($cand | ForEach-Object { '"' + $head[$_] + '"' }) -join ' and ') + " both look like one. Its columns, with a value from each:`n" +
        (Get-ColumnList $head $sample) + "`nRun it again naming the one to read:`n" + (Get-Next $F.Given 'ResultColumn' $head[$cand[0]]))
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
      if (-not $pc.Trim()) { $pc = "(name not given) row $n" }
      $ot = & $cell $idx.Os
      $os = ''
      if ($ot -match 'mac|darwin') { $os = 'macOS' } elseif ($ot -match 'win') { $os = 'Windows' } elseif ($ot -match 'linux') { $os = 'Linux' }
      $row = New-Row $pc (Get-Unguarded (& $cell $idx.User)) (Get-Cleaned (& $cell $idx.Result)) $Label $os
      $row.LastSeen = & $cell $idx.Seen
      if ($ours) { $row.LastReport = $row.LastSeen }
      $row.Id = & $cell $idx.Id
      [void]$out.Add((New-Object PSObject -Property (Set-Result $row (& $cell $idx.Det) $ours $Now)))
    }
  } finally { $rd.Dispose() }
  return @{ Rows = $out.ToArray(); Notes = $notes.ToArray() }
}

function Set-Duplicates($Rows) {
  $by = @{}
  foreach ($r in $Rows) { $k = $r.PC.ToLowerInvariant() + '|' + $r.Id; if (-not $by.ContainsKey($k)) { $by[$k] = New-Object System.Collections.ArrayList }; [void]$by[$k].Add($r) }
  foreach ($k in @($by.Keys)) {
    $g = @($by[$k])
    if ($g.Count -lt 2) { continue }
    $from = (@($g | ForEach-Object { $_.Source }) | Select-Object -Unique) -join ', '
    foreach ($r in $g) {
      $r.Status = 'not_checked'; $r.Known = $false; $r.Kinds = @(); $r.Refs = @(); $r.Details = ''
      $r.AgentKey = 'unknown'; $r.AgentKeyProviders = @(); $r.Sessions = 'unknown'; $r.McpTokens = 'unknown'
      $r.Why = "this name appears $($g.Count) times in the results read ($from), so it is not known which result is this computer's"
    }
  }
}

# --- Working out what the report says ----------------------------------------------------------

function Get-ReportData($Rows, $Notes, $Sources, [DateTime]$Now) {
  $count = @{}
  foreach ($k in $StatusText.Keys) { $count[$k] = @($Rows | Where-Object { $_.Status -eq $k }).Count }
  $known = @($Rows | Where-Object { $_.Known })
  $d = @{
    Now = $Now.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ' UTC'; StaleDays = $StaleDays
    Sources = (@($Sources.PSBase.Keys | ForEach-Object { $_ + ' (' + $Sources[$_] + ')' }) -join ', ')
    Notes = @($Notes); Counts = $count; Total = $Rows.Count; ShowTiles = ($Rows.Count -gt 0 -or $Notes.Count -eq 0)
    NotChecked = $count.not_checked + $count.stale + $count.no_result
    Meaning = $MitreMeaning; Credit = $MitreSource
    Kinds = @(); Paths = @(); Techniques = @(); Sections = @(); Tactics = [ordered]@{}; Limits = @()
  }
  # PSBase: a dictionary with a 'keys' entry answers .Keys with that entry.
  foreach ($k in $Kinds.PSBase.Keys) {
    $with = @($known | Where-Object { @($_.Kinds) -ccontains $k })
    $n = @($Rows | Where-Object { @($_.Kinds) -ccontains $k }).Count
    if ($n -eq 0) { continue }
    $refs = @(); $why = [ordered]@{}; $nothing = @()
    foreach ($fw in @('attack', 'atlas')) {
      $mine = @($MitreRows | Where-Object { $_.Word -ceq $k -and $_.Fw -ceq $fw })
      $none = @($mine | Where-Object { $_.Rel -ceq 'none' })
      if ($none.Count -gt 0) { $why[$fw] = $none[0].Note; continue }
      $shown = 0
      foreach ($m in $mine) {
        $on = @($with | Where-Object { @($_.Refs) -contains $m })
        if ($on.Count -eq 0) { continue }
        $shown++
        $only = @()
        if ($m.Os -ceq 'win') { $only += 'Windows PCs' } elseif ($m.Os -ceq 'mac') { $only += 'Macs' }
        if (@($m.Scope).Count -gt 0) {
          $hit = @()
          foreach ($x in $on) { foreach ($i in @((Get-WordIds $x)[$k])) { if (@($m.Scope) -ccontains $i -and $hit -cnotcontains $i) { $hit += $i } } }
          $only += 'the incidents ' + ((@($hit | ForEach-Object { $nm = $MitreIncidentNames[$_]; if ($nm) { $nm } else { $_ } }) | Select-Object -Unique) -join ', ')
        }
        $q = ''; if ($only.Count -gt 0) { $q = 'only for ' + ($only -join ', on ') + ': ' + (Get-PcCount $on.Count) }
        $refs += @{ Fw = $FwName[$fw]; Lead = $RelText[$m.Rel]; Id = $m.Id; Url = $m.Url; Name = $m.Name; Armed = ($m.Rel -ceq 'armed'); Only = $q }
      }
      if ($shown -eq 0 -and $mine.Count -gt 0) { $nothing += $FwName[$fw] + ': none applies to what these computers sent.' }
    }
    $noneText = @()
    if ($why.Count -eq 2 -and $why['attack'] -ceq $why['atlas']) { $noneText += 'No MITRE reference: ' + $why['attack'] }
    else { foreach ($fw in $why.PSBase.Keys) { $noneText += $FwName[$fw] + ': no reference. ' + $why[$fw] } }
    $d.Kinds += @{ Label = $Kinds[$k]; Count = $n; Refs = $refs; Plain = @($nothing + $noneText) }
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
    $d.Paths += @{ Text = $pa.Text; Yes = (Get-PcCount $yes.Count); Providers = $prov; Unknown = (Get-PcCount @($Rows | Where-Object { $_.($pa.Prop) -ceq 'unknown' }).Count) }
  }
  $techs = [ordered]@{}
  foreach ($m in $MitreRows) { if ($m.Rel -cne 'none' -and -not $techs.Contains($m.Fw + ' ' + $m.Id)) { $techs[$m.Fw + ' ' + $m.Id] = $m } }
  $tl = @()
  foreach ($key in $techs.PSBase.Keys) {
    $m = $techs[$key]
    $on = @($known | Where-Object { @($_.Refs | Where-Object { $_.Fw -ceq $m.Fw -and $_.Id -ceq $m.Id }).Count -gt 0 })
    if ($on.Count -eq 0) { continue }
    $t = @{ Name = $m.Name; Id = $m.Id; Url = $m.Url; Fw = $FwName[$m.Fw]; FwKey = $m.Fw; N = $on.Count }
    foreach ($rel in @('exposure', 'indicator', 'armed')) { $t[$rel] = @($on | Where-Object { @($_.Refs | Where-Object { $_.Fw -ceq $m.Fw -and $_.Id -ceq $m.Id -and $_.Rel -ceq $rel }).Count -gt 0 }).Count }
    $tl += New-Object PSObject -Property $t
  }
  $d.Techniques = @($tl | Sort-Object @{ Expression = { $_.FwKey } }, @{ Expression = { $_.N }; Descending = $true })
  foreach ($sec in @(
      @{ Title = 'Deal with these first'; Keys = @('act', 'not_checked', 'failed', 'stale') },
      @{ Title = 'No result'; Keys = @('no_result') },
      @{ Title = 'To review'; Keys = @('review') },
      @{ Title = 'Nothing found'; Keys = @('clear') })) {
    $list = @()
    foreach ($r in @($Rows | Where-Object { $sec.Keys -contains $_.Status })) {
      $raw = $false; $detail = $r.Details
      if ($r.Status -eq 'not_checked' -and -not $r.Details) { $raw = $true; $detail = $r.Output; if ($detail.Length -gt 200) { $detail = $detail.Substring(0, 200) + '...' } }
      $list += @{ PC = $r.PC; User = $r.User; OS = $r.OS; Source = $r.Source; Status = $r.Status; StatusText = $StatusText[$r.Status]; Why = $r.Why; CheckedAt = $r.CheckedAt; Detail = $detail; Raw = $raw }
    }
    $d.Sections += @{ Title = $sec.Title; Rows = $list }
  }
  foreach ($fw in @('attack', 'atlas')) {
    $byTactic = [ordered]@{}
    foreach ($m in $MitreRows) {
      if ($m.Fw -cne $fw -or $m.Rel -ceq 'none') { continue }
      foreach ($tc in @($m.Tactics)) {
        if (-not $byTactic.Contains($tc)) { $byTactic[$tc] = @() }
        $nm = $m.Name + ' (' + $m.Id + ')'
        if ($byTactic[$tc] -cnotcontains $nm) { $byTactic[$tc] += $nm }
      }
    }
    $d.Tactics[$FwName[$fw]] = @($byTactic.PSBase.Keys | ForEach-Object { $_ + ': ' + ($byTactic[$_] -join '; ') })
  }
  $d.NotLooked = @(
    'The network: no traffic, DNS or proxies. It cannot say whether a key left a computer.',
    'The identity provider: no sign-ins, sessions or account activity.',
    'The cloud control plane: no cloud permissions or audit logs, and not what a found key can reach.',
    'Data platforms, such as a lakehouse or a data warehouse.',
    'What AI agents do while they run: what they ran, read or sent. It reads their settings and files.',
    'Malware that is not on its list of incidents.')
  if (@($Rows | Where-Object { $_.OS -ceq 'Windows' }).Count -gt 0) {
    $others = @($known | Where-Object { $_.Win -and $_.OtherProfiles -gt 0 }).Count
    $lim = 'Each Windows result covers one account: the person signed in when it ran.'
    if ($others -gt 0) { $lim += ' ' + (Get-PcCount $others) + ' had other accounts that were not checked.' }
    $d.Limits += $lim
  }
  if (@($Rows | Where-Object { $_.OS -ceq 'macOS' }).Count -gt 0) {
    $d.Limits += 'Each Mac result covers every local account with a user ID of 500 or above. One it could not check is listed as not checked, and a result cut to fit may leave accounts out.'
  }
  $d.Limits += "$($count.no_result) with no result, $($count.stale) with a stale result, $($count.failed) failed, and " +
    "$(@($Rows | Where-Object { $_.Status -eq 'not_checked' -and -not $_.Known }).Count) with a result this tool could not read. Nothing they may hold is in the counts above."
  $cut = @($known | Where-Object { $_.More }).Count
  if ($cut -gt 0) { $d.Limits += (Get-PcCount $cut) + ' sent a result cut to fit what the MDM keeps. Findings past the cut are not in the counts above.' }
  return $d
}

# --- The page: markup only, from the data Get-ReportData worked out ------------------------------

function Get-Link([string]$Url, [string]$Text) {
  if ($Url.StartsWith('https://attack.mitre.org/techniques/', [StringComparison]::Ordinal) -or $Url.StartsWith('https://atlas.mitre.org/techniques/', [StringComparison]::Ordinal)) {
    return '<a href="' + (ConvertTo-HtmlText $Url) + '" rel="noopener noreferrer">' + (ConvertTo-HtmlText $Text) + '</a>'
  }
  return (ConvertTo-HtmlText $Text)
}

function Get-ReportPage($D) {
  $e = { param($s) ConvertTo-HtmlText ([string]$s) }
  $h = New-Object System.Text.StringBuilder
  [void]$h.Append(@'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Blindspot fleet report</title>
<style>
:root { --bg: #ffffff; --fg: #1d1d1f; --muted: #5f6368; --line: #dadce0; --act: #b3261e; --warn: #8a5300; --ok: #1e6b34; }
@media (prefers-color-scheme: dark) { :root { --bg: #161618; --fg: #ececee; --muted: #a0a3a8; --line: #3a3b3e; --act: #ff8a80; --warn: #ffc56b; --ok: #81c995; } }
body { background: var(--bg); color: var(--fg); font: 14px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; margin: 0; padding: 24px 16px; }
main { max-width: 1100px; margin: 0 auto; }
h1 { font-size: 22px; margin: 0 0 4px; } h2 { font-size: 16px; margin: 28px 0 8px; }
a { color: inherit; }
.muted { color: var(--muted); }
.tiles { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
.tile { border: 1px solid var(--line); border-radius: 8px; padding: 8px 12px; min-width: 110px; }
.tile b { display: block; font-size: 20px; }
.wrap { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; vertical-align: top; padding: 6px 8px; border-bottom: 1px solid var(--line); }
th { font-weight: 600; color: var(--muted); }
td.ref { color: var(--muted); font-size: 13px; }
td.raw { font-family: ui-monospace, Consolas, monospace; font-size: 12px; word-break: break-all; }
.s-act { color: var(--act); font-weight: 600; } .s-not_checked, .s-failed, .s-stale, .s-no_result, .s-review { color: var(--warn); font-weight: 600; } .s-clear { color: var(--ok); }
</style></head><body><main>
'@)
  [void]$h.Append('<h1>Blindspot fleet report</h1>')
  [void]$h.Append('<p class="muted">Results from ' + (& $e $D.Sources) + ', read ' + (& $e $D.Now) + '. A result older than ' + $D.StaleDays + ' days counts as stale. A Windows result covers the person signed in when it ran; a Mac result covers each account it lists.</p>')
  if ($D.ShowTiles) {
    [void]$h.Append('<div class="tiles"><div class="tile"><b>' + $D.Total + '</b>Computers</div>')
    foreach ($k in @('act', 'not_checked', 'failed', 'stale', 'no_result', 'review', 'clear')) { [void]$h.Append('<div class="tile"><b>' + $D.Counts[$k] + '</b>' + (& $e $StatusText[$k]) + '</div>') }
    [void]$h.Append('</div>')
  }
  if ($D.NotChecked -gt 0) {
    [void]$h.Append('<p>' + $D.NotChecked + ' computer' + $(if ($D.NotChecked -eq 1) { ' was' } else { 's were' }) + ' not checked: no result, a stale result, or a result that does not fit. None of them counts as clear.</p>')
  }
  if ($D.Notes.Count -gt 0) {
    [void]$h.Append('<h2>Could not list every PC</h2><ul>')
    foreach ($n in $D.Notes) { [void]$h.Append('<li>' + (& $e $n) + '</li>') }
    [void]$h.Append('</ul>')
  }
  $said = $false
  [void]$h.Append('<h2>What was found</h2>')
  if ($D.Kinds.Count -eq 0) { [void]$h.Append('<p class="muted">No finding in the results that were read.</p>') }
  else {
    [void]$h.Append('<p class="muted">' + (& $e $D.Meaning) + '</p>'); $said = $true
    [void]$h.Append('<div class="wrap"><table><tr><th>Finding</th><th>Computers</th><th>MITRE technique (exposure or indicator)</th></tr>')
    foreach ($k in $D.Kinds) {
      $lines = @()
      foreach ($r in $k.Refs) {
        $t = (& $e $r.Fw) + ': ' + (& $e $r.Lead) + ' ' + (Get-Link $r.Url $r.Id) + ' ' + (& $e $r.Name)
        if ($r.Armed) { $t += ': installed, runs when triggered' }
        if ($r.Only) { $t += ' (' + (& $e $r.Only) + ')' }
        $lines += $t
      }
      foreach ($p in $k.Plain) { $lines += (& $e $p) }
      [void]$h.Append('<tr><td>' + (& $e $k.Label) + '</td><td>' + $k.Count + '</td><td class="ref">' + ($lines -join '<br>') + '</td></tr>')
    }
    [void]$h.Append('</table></div>')
  }
  [void]$h.Append('<h2>What could get out</h2><p>These count what was found in files on each computer. They do not show that a key was used, copied or sent anywhere.</p><ul>')
  foreach ($p in $D.Paths) {
    $t = (& $e $p.Text) + ': ' + $p.Yes + '.'
    if ($p.Providers.Count -gt 0) { $t += ' Providers of those keys: ' + (& $e ($p.Providers -join ', ')) + '.' }
    [void]$h.Append('<li>' + $t + ' Not known for ' + $p.Unknown + '.</li>')
  }
  [void]$h.Append('</ul><p class="muted">Not known: the computer sent no result, a stale or failed one, one cut to fit, one this tool could not read, or one where an account was partly checked or not checked.</p>')
  [void]$h.Append('<h2>Techniques the findings relate to</h2>')
  if ($D.Techniques.Count -eq 0) { [void]$h.Append('<p class="muted">No finding relates to a MITRE technique.</p>') }
  else {
    if (-not $said) { [void]$h.Append('<p class="muted">' + (& $e $D.Meaning) + '</p>'); $said = $true }
    [void]$h.Append('<p class="muted">A computer is counted once for each technique, and once in each column that applies to it.</p>')
    [void]$h.Append('<div class="wrap"><table><tr><th>Technique</th><th>MITRE</th><th>Computers</th><th>Exposure</th><th>Indicator</th><th>Armed</th></tr>')
    foreach ($t in $D.Techniques) {
      [void]$h.Append('<tr><td>' + (& $e $t.Name) + ' <span class="muted">' + (Get-Link $t.Url $t.Id) + '</span></td><td>' + (& $e $t.Fw) + '</td><td>' + $t.N +
        '</td><td>' + $t.exposure + '</td><td>' + $t.indicator + '</td><td>' + $t.armed + '</td></tr>')
    }
    [void]$h.Append('</table></div>')
  }
  foreach ($sec in $D.Sections) {
    [void]$h.Append('<h2>' + (& $e $sec.Title) + ' (' + $sec.Rows.Count + ')</h2>')
    if ($sec.Rows.Count -eq 0) { [void]$h.Append('<p class="muted">None.</p>'); continue }
    [void]$h.Append('<div class="wrap"><table><tr><th>Computer</th><th>Person</th><th>OS</th><th>From</th><th>Status</th><th>Why</th><th>Checked</th><th>Details</th></tr>')
    foreach ($r in $sec.Rows) {
      $cls = ''; if ($r.Raw) { $cls = ' class="raw"' }
      [void]$h.Append('<tr><td>' + (& $e $r.PC) + '</td><td>' + (& $e $r.User) + '</td><td>' + (& $e $r.OS) + '</td><td>' + (& $e $r.Source) + '</td><td class="s-' + $r.Status + '">' +
        (& $e $r.StatusText) + '</td><td>' + (& $e $r.Why) + '</td><td>' + (& $e $r.CheckedAt) + '</td><td' + $cls + '>' + (& $e $r.Detail) + '</td></tr>')
    }
    [void]$h.Append('</table></div>')
  }
  [void]$h.Append('<h2>What this report covers and does not cover</h2>')
  if (-not $said) { [void]$h.Append('<p class="muted">' + (& $e $D.Meaning) + '</p>') }
  [void]$h.Append('<p>Blindspot reads files on each computer. It finds things an attack could use, such as keys in plain text and AI agents set to run commands without asking, and traces of the malware incidents on its list. It does not watch for attacks and does not detect any technique in use.</p>')
  foreach ($fw in $D.Tactics.PSBase.Keys) {
    [void]$h.Append('<p><b>' + (& $e $fw) + ' tactics the findings relate to:</b></p><ul>')
    foreach ($x in $D.Tactics[$fw]) { [void]$h.Append('<li>' + (& $e $x) + '</li>') }
    [void]$h.Append('</ul>')
  }
  [void]$h.Append('<p class="muted">A tactic is listed because a technique a finding relates to belongs to it. Blindspot checks for none of these techniques in use.</p><p><b>What Blindspot does not look at:</b></p><ul>')
  foreach ($x in $D.NotLooked) { [void]$h.Append('<li>' + (& $e $x) + '</li>') }
  [void]$h.Append('</ul><p><b>Limits of the results in this report:</b></p><ul>')
  foreach ($x in $D.Limits) { [void]$h.Append('<li>' + (& $e $x) + '</li>') }
  [void]$h.Append('</ul><p class="muted">The full result of each computer stays on that computer. To see which files, the person runs Blindspot on their own account.</p>')
  [void]$h.Append('<p class="muted">' + (& $e $D.Credit) + '</p></main></body></html>')
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
  Set-Duplicates $rows
  $order = @{ act = 0; not_checked = 1; failed = 2; stale = 3; no_result = 4; review = 5; clear = 6 }
  $sorted = @($rows | Sort-Object @{ Expression = { $order[$_.Status] } }, @{ Expression = { $_.PC } })
  $data = Get-ReportData $sorted $notes.ToArray() $sources $now
  $base = Save-Report $dir ($now.ToString('yyyyMMdd-HHmm', [Globalization.CultureInfo]::InvariantCulture)) (Get-ReportCsv $sorted) (Get-ReportPage $data)
  foreach ($n in $notes) { Write-Host ('Note: ' + $n) }
  $c = $data.Counts
  Write-Host ("Read $($sorted.Count) computer" + $(if ($sorted.Count -eq 1) { '' } else { 's' }) + ' from ' + (@($sources.PSBase.Keys) -join ', ') + '.')
  Write-Host ("Need attention now: $($c.act). To review: $($c.review). Nothing found: $($c.clear).")
  Write-Host ("Not checked: $($data.NotChecked + $c.failed) (no result, a stale or failed run, or a result that could not be read). None of these counts as clear.")
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
