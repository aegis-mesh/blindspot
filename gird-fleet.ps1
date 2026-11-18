<#
Blindspot for IT teams, on Windows: checks the signed-in person's account, run by an MDM.
https://gird.ai/blindspot, docs/designs/fleet-mode.md (Windows)

It starts gird-check.ps1 -AccountRun as a separate Windows PowerShell process, as the person who
is signed in, with that person's rights only, checks every line it sends back and builds the
result itself. It also looks for agents installed under %ProgramFiles% and for malware markers in
%ProgramData%. The result is saved in %LOCALAPPDATA%\Blindspot\last.json. Nothing is sent anywhere.
An MDM runs blindspot-fleet.ps1, which is this file with gird-check.ps1 packed inside.

  powershell -ExecutionPolicy Bypass -File blindspot-fleet.ps1                the inventory value
  powershell -ExecutionPolicy Bypass -File blindspot-fleet.ps1 -Json          the result as JSON
  powershell -ExecutionPolicy Bypass -File blindspot-fleet.ps1 -Summary       the one summary line
  -Deadline <seconds>  the time the whole run has, 1500 when not given
  -MacExitCodes        exit 0 clear, 10 act, 11 review, 12 not_checked, 13 failed, as on a Mac;
                       otherwise 0 for clear and 1 for anything else, as Intune reads it
  -ExitZero            exit 0 whenever the run finished; failed still exits 1 (13 with -MacExitCodes)

Runs on Windows PowerShell 5.1 and PowerShell 7, in 64-bit PowerShell, as the signed-in person.
This file is plain ASCII, as gird-check.ps1 is.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [switch]$Json, [switch]$Summary, [switch]$ExitZero, [switch]$MacExitCodes, [switch]$All, [switch]$Help,
  [string]$Deadline = '',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)
# Everything down to the language mode check is written in statements the reduced language
# (Constrained Language Mode) allows: it refuses the .NET calls further down.
$FlUsage = $null; $FlTest = $false
foreach ($arg in $Rest) {
  switch -CaseSensitive ($arg) {
    '--json' { $Json = $true } '--summary-to-stdout' { $Summary = $true } '--exit-zero' { $ExitZero = $true }
    '--mac-exit-codes' { $MacExitCodes = $true } '--all' { $All = $true }
    { $_ -eq '--help' -or $_ -eq '-h' } { $Help = $true }
    { $_.StartsWith('--deadline=') } { $Deadline = $_.Substring(11) }
    default { if ($null -eq $FlUsage) { $FlUsage = "Unknown option: $arg (try -Help)" } }
  }
}
# Other people with a profile on this PC, whose accounts this run does not check. A profile counts
# when its account is a person's: a local account other than the built-in ones (an account number of
# 1000 or more), or a domain or Microsoft Entra ID account, whose folder exists and is not one of the
# defaultuser profiles Windows setup leaves. A local account an IT team made for itself can't be told
# from a person's, so it counts.
function Is-PersonProfile([string]$sid, [string]$folder) {
  if ($sid -cnotmatch '^S-1-(5-21|12-1)(-[0-9]+)+$') { return $false }
  if ($sid.StartsWith('S-1-5-21-') -and [long](($sid -split '-')[-1]) -lt 1000) { return $false }
  if (-not $folder -or (($folder -split '[\\/]')[-1]) -match '^defaultuser[0-9]*$') { return $false }
  $true
}
# An account name as the result shows it: one with other characters, or named machine like the PC's own
# row in the inventory value, shows as invalid-name.
function Shown-Name([string]$n) {
  if ($n -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or $n -eq 'machine') { return 'invalid-name' }
  $n
}
function Count-Others([string]$sid, [string]$myFolder) {
  if ($env:OS -ne 'Windows_NT') {
    if ($FlTest -and $env:GIRD_CHECK_FLEET_PROFILES -match '^[0-9]{1,4}$') { return [int]$env:GIRD_CHECK_FLEET_PROFILES }
    return 0
  }
  $n = 0
  try {
    foreach ($k in @(Get-ChildItem -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop)) {
      $s = [string]$k.PSChildName
      $f = ''; try { $f = [string](Get-ItemProperty -LiteralPath $k.PSPath -Name ProfileImagePath -ErrorAction Stop).ProfileImagePath } catch { $f = '' }
      if (($sid -and $s -eq $sid) -or ($myFolder -and $f -eq $myFolder)) { continue }
      if ((Is-PersonProfile $s $f) -and (Test-Path -LiteralPath $f -PathType Container)) { $n++ }
    }
  } catch { }
  $n
}
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
  $u = (Get-Date).ToUniversalTime()
  $at = Get-Date -Date $u -UFormat '%Y-%m-%dT%H:%M:%SZ'
  $ep = (Get-Date -Date $u -UFormat '%s') -replace '[.,].*$', ''
  $nm = $env:USERNAME; if (-not $nm) { $nm = $env:USER }
  $nm = Shown-Name $nm
  $oth = Count-Others '' $env:USERPROFILE
  $sl = "blindspot failed accounts=1 act=0 review=0 not_checked=1 other_profiles=$oth v=unknown at=$at reason=language_mode"
  $iv = "v1 failed $($at.Substring(0, 16))Z other_profiles=$oth reason=language_mode | $($nm): not_checked language_mode"
  if ($Json) {
    Write-Output "{`n  ""blindspot"": ""1"",`n  ""script"": ""unknown"",`n  ""checked_at"": ""$at"",`n  ""checked_epoch"": $ep,`n  ""os"": ""other"",`n  ""outcome"": ""failed"",`n  ""reason"": ""language_mode"",`n  ""deadline_reached"": false,`n  ""other_profiles"": $oth,`n  ""accounts"": [{""account"":""$nm"",""complete"":false,""outcome"":""not_checked"",""not_checked"":""language_mode""}],`n  ""machine"": {""complete"":false,""outcome"":""not_checked"",""agents"":[],""possible_signs"":[],""incidents"":[]},`n  ""summary"": ""$sl"",`n  ""inventory"": ""$iv"",`n  ""learn_more"": ""https://gird.ai/argus""`n}"
  } elseif ($Summary) { Write-Output $sl } else { Write-Output $iv }
  if ($MacExitCodes) { exit 13 }
  exit 1
}

if ($Help) {
  foreach ($l in ((Get-Content -LiteralPath $PSCommandPath -TotalCount 20) | Select-Object -Skip 1)) { [Console]::Out.WriteLine($l) }
  exit 0
}
if ($null -ne $FlUsage) { [Console]::Out.WriteLine($FlUsage); exit 2 }
function Fl-Usage([string]$msg, [int]$code) { [Console]::Error.WriteLine("blindspot: $msg"); exit $code }
if ($Deadline -cnotmatch '^([1-9][0-9]{0,4})?$') { Fl-Usage '-Deadline takes a number of seconds, up to 99999' 2 }
if ($Json -and $Summary) { Fl-Usage 'choose -Json or -Summary, not both' 2 }
if ($All) { Fl-Usage '-All is refused here: Desktop and Documents can hold cloud files that download when read' 13 }

$OnWindows = $env:OS -eq 'Windows_NT'
# The GIRD_CHECK_FLEET_* settings let the tests, which run off Windows, stand in for Windows' own
# programs and folders. They are read only off Windows, where this script runs for tests alone.
if (-not $OnWindows) {
  if ($env:GIRD_CHECK_FLEET_TEST -ne '1') { Fl-Usage 'gird-fleet.ps1 is for Windows. On a Mac, run gird-fleet.sh (docs/fleet.md)' 13 }
  $FlTest = $true
}
$Sep = [IO.Path]::DirectorySeparatorChar
function J([string]$base, [string]$rel) { $base + $Sep + ($rel -replace '[\\/]', $Sep) }
function Env-Or([string]$name, [string]$fallback) { $v = [Environment]::GetEnvironmentVariable($name); if ($v) { $v } else { $fallback } }
$HomeDir = $env:USERPROFILE; if (-not $HomeDir) { $HomeDir = $env:HOME }
$AppData = $env:APPDATA; if (-not $AppData) { $AppData = J $HomeDir 'AppData/Roaming' }
$LocalAppData = $env:LOCALAPPDATA; if (-not $LocalAppData) { $LocalAppData = J $HomeDir 'AppData/Local' }
$GooseData = J $AppData 'Block/goose/data'
$PathCmp = [StringComparison]::Ordinal; if ($OnWindows) { $PathCmp = [StringComparison]::OrdinalIgnoreCase }
$Inv = [Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------------------
# The tables, written here by tools/gen.sh: never edit them here.
# ---------------------------------------------------------------------------
# >>> agents: copied from gird-check.ps1 by tools/gen.sh. Edit it there, then run it.
$Agents = @(
  @('Claude Code', 'claude', @((J $HomeDir '.claude')), @((J $HomeDir '.claude/projects')), 'claude-code'),
  @('Claude Desktop', '', @((J $LocalAppData 'AnthropicClaude'), (J $AppData 'Claude')), @((J $AppData 'Claude')), 'claude-desktop'),
  @('Codex', 'codex', @((J $HomeDir '.codex')), @((J $HomeDir '.codex/sessions')), 'codex'),
  @('Gemini CLI', 'gemini', @((J $HomeDir '.gemini')), @((J $HomeDir '.gemini/tmp')), 'gemini-cli'),
  @('Cursor', 'cursor', @((J $LocalAppData 'Programs/cursor'), (J $HomeDir '.cursor')), @((J $AppData 'Cursor/User/workspaceStorage')), 'cursor'),
  @('Windsurf', 'windsurf;devin-desktop', @((J $LocalAppData 'Programs/Windsurf'), (J $HomeDir '.codeium/windsurf')), @((J $AppData 'Windsurf/User/workspaceStorage'), (J $AppData 'Devin/User/workspaceStorage')), 'windsurf'),
  @('Antigravity', 'antigravity', @((J $LocalAppData 'Programs/Antigravity')), @((J $AppData 'Antigravity/User/workspaceStorage')), 'antigravity'),
  @('GitHub Copilot CLI', 'copilot', @((J $HomeDir '.copilot')), @((J $HomeDir '.copilot')), 'copilot-cli'),
  @('OpenCode', 'opencode', @((J $HomeDir '.config/opencode'), (J $HomeDir '.local/share/opencode')), @((J $HomeDir '.local/share/opencode')), 'opencode'),
  @('Goose', 'goose', @((J $AppData 'Block/goose')), @($GooseData), 'goose'),
  @('Aider', 'aider', @(), @(), 'aider'),
  @('Cline', '', @((J $AppData 'Code/User/globalStorage/saoudrizwan.claude-dev'), (J $AppData 'Cursor/User/globalStorage/saoudrizwan.claude-dev')),
    @((J $AppData 'Code/User/globalStorage/saoudrizwan.claude-dev/tasks'), (J $AppData 'Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks')), 'cline'),
  @('Continue', '', @((J $HomeDir '.continue')), @((J $HomeDir '.continue/sessions')), 'continue')
)
# <<< agents
# >>> fleet-tables: generated from data/ by tools/gen.sh. Edit those files, then run it.
$FlIncidents = @{ 'axios' = 'act'; 'tanstack' = 'act'; 'mistral' = 'update'; 'uipath' = 'update'; 'mistralpy' = 'act'; 'guardrails' = 'act'; 'opensearch' = 'act'; 'bitwarden' = 'act'; 'minishai' = 'act'; 'lightning' = 'act'; 'durabletask' = 'act'; 'telnyx' = 'act'; 'mastra' = 'act'; 'antv' = 'act'; 'nxconsole' = 'act'; 'redhat' = 'act'; 'keyv' = 'act'; 'keyvscope' = 'act'; 'keyvspread' = 'act'; 'sandworm' = 'act'; 'sandsleep' = 'act'; 'tensorlake' = 'act'; 'litellm' = 'act'; 'litellmmar' = 'act'; 'opencode' = 'leak'; 'railway' = 'leak'; 'zeabur' = 'leak'; 'glassworm' = 'act'; 'glasswormmar' = 'act'; 'glasswormvsix' = 'act'; 'glasswormapr' = 'act'; 'glasswormzig' = 'act'; 'glasswormdec' = 'act'; 'glasswormoct' = 'act'; 'glasswormuni' = 'act'; 'glasswasm' = 'act'; 'injective' = 'update' }
$FlProviders = 'anthropic openrouter openai google groq xai huggingface perplexity replicate aws github npm'
$FlYoloNames = @('Claude Code', 'Codex', 'VS Code Copilot')
$FlTools = @('amazonq', 'claudecode', 'mcpremote')
$FlPlatforms = @('opencode', 'railway', 'zeabur')
$FlProgramData = @(
  ,@('mastra', 'NodePackages/protocal.cjs')
)
# <<< fleet-tables
# >>> packed-check: written into blindspot-fleet.ps1 by tools/gen.sh; empty here, where gird-check.ps1 sits next to this file.
$PackedCheck = ''
$PackedSha = ''
# <<< packed-check

# ---------------------------------------------------------------------------
# The run.
# ---------------------------------------------------------------------------
$FlStart = [DateTime]::UtcNow
$FlAt = $FlStart.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $Inv)
$FlEpoch = [long][Math]::Floor(($FlStart - (New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc))).TotalSeconds)
$FlDeadline = 1500; if ($Deadline) { $FlDeadline = [int]$Deadline }
$FlReserve = [Math]::Min(40, [int][Math]::Floor($FlDeadline / 10))
$FlEnd = $FlStart.AddSeconds($FlDeadline - $FlReserve)
$FlReason = ''
$FlOutMax = 4096
$FlStopSecs = 10
$FlKeys = @('v', 'agents', 'yolo', 'tools', 'mcp_servers', 'mcp_token_files', 'key_files', 'key_providers', 'history_keys', 'session_files', 'sessions_partial', 'allow_list_keys', 'ssh_open', 'ak_links', 'planted', 'possible', 'incidents', 'platforms', 'on_open', 'to_read', 'updates', 'wiper', 'lock_only', 'remove', 'not_read', 'moved', 'tmp_marks', 'tmp_wiper', 'protected', 'engine', 'end')

function Sha256-Hex([byte[]]$b) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { -join ($sha.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
}
function File-Sha([string]$p) { try { Sha256-Hex ([IO.File]::ReadAllBytes($p)) } catch { '' } }
function Is-Reparse([string]$p) { try { (([IO.File]::GetAttributes($p)) -band [IO.FileAttributes]::ReparsePoint) -ne 0 } catch { $false } }

# The person this run checks, and the SID that tells their files from other accounts'.
$FlSid = ''
if ($OnWindows) { try { $FlSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $FlSid = '' } }
$FlUser = [Environment]::UserName
$FlShown = Shown-Name $FlUser

$FlOther = Count-Others $FlSid $env:USERPROFILE

$FlOs = 'other'
if ($OnWindows) {
  $ov = [Environment]::OSVersion.Version
  if ($ov.Major -eq 10) { if ($ov.Build -ge 22000) { $FlOs = 'Windows 11' } else { $FlOs = 'Windows 10' } } else { $FlOs = 'Windows' }
}

# A 32-bit PowerShell is shown another Program Files and another set of installed tools, so its
# check would miss things. SYSTEM, LocalService and NetworkService have no person's files to check: run
# as one of them, a check would find an empty profile and read clear.
if ($OnWindows -and [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $FlReason = 'host_32bit' }
elseif (@('S-1-5-18', 'S-1-5-19', 'S-1-5-20') -contains $FlSid) { $FlReason = 'system_account' }

# The saved result's folder, in the person's own profile: one that is a link or not a folder is moved
# aside and made again.
$FlState = J $LocalAppData 'Blindspot'
function State-Prep {
  $ok = $false
  try { $ok = [IO.Directory]::Exists($script:FlState) -and -not (Is-Reparse $script:FlState) } catch { $ok = $false }
  if ($ok) { return $true }
  try {
    if ([IO.File]::Exists($script:FlState) -or [IO.Directory]::Exists($script:FlState) -or (Is-Reparse $script:FlState)) {
      $aside = "$($script:FlState).replaced-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss', $Inv))-$PID"
      if ([IO.Directory]::Exists($script:FlState)) { [IO.Directory]::Move($script:FlState, $aside) } else { [IO.File]::Move($script:FlState, $aside) }
    }
    [void][IO.Directory]::CreateDirectory($script:FlState)
    return ([IO.Directory]::Exists($script:FlState) -and -not (Is-Reparse $script:FlState))
  } catch { return $false }
}

# gird-check.ps1, as this run carries it: packed inside blindspot-fleet.ps1, or next to this file.
$FlRel = 'unknown'; $FlCheck = ''; $FlCheckSha = ''; $FlCheckBytes = $null
if (-not $FlReason) {
  try {
    if ($PackedCheck) {
      $ms = New-Object IO.MemoryStream (, [Convert]::FromBase64String($PackedCheck))
      $gz = New-Object IO.Compression.GZipStream ($ms, [IO.Compression.CompressionMode]::Decompress)
      $out = New-Object IO.MemoryStream
      $gz.CopyTo($out); $gz.Dispose(); $ms.Dispose()
      $FlCheckBytes = $out.ToArray(); $out.Dispose()
      $FlCheckSha = $PackedSha
    } elseif (-not $PSScriptRoot) {
      [Console]::Error.WriteLine('blindspot: run it from a file: gird-fleet.ps1 reads gird-check.ps1 from its own folder')
      $FlReason = 'unpack'
    } else {
      $FlCheckBytes = [IO.File]::ReadAllBytes((J $PSScriptRoot 'gird-check.ps1'))
      $FlCheckSha = Sha256-Hex $FlCheckBytes
    }
    if (-not $FlReason -and (Sha256-Hex $FlCheckBytes) -ne $FlCheckSha) { $FlReason = 'unpack' }
  } catch { $FlReason = 'unpack' }
}
if (-not $FlReason) {
  $hd = [Text.Encoding]::ASCII.GetString($FlCheckBytes, 0, [Math]::Min(400, $FlCheckBytes.Length))
  $m = [regex]::Match($hd, '\nBlindspot, [^\n]*, version ([0-9]+(\.[0-9]+)*) ')
  if ($m.Success) { $FlRel = $m.Groups[1].Value } else { $FlReason = 'unpack' }
}
if (-not $FlReason -and -not (State-Prep)) { $FlReason = 'save' }
# Unpacked into the person's own profile, which only they, administrators and SYSTEM can write, and
# written again whenever its SHA-256 is not the one this run carries.
if (-not $FlReason) {
  $FlCheck = J (J $FlState $FlRel) 'gird-check.ps1'
  try {
    if ((File-Sha $FlCheck) -ne $FlCheckSha -or (Is-Reparse $FlCheck)) {
      $vd = J $FlState $FlRel
      if ((Is-Reparse $vd) -or [IO.File]::Exists($vd)) { if ([IO.File]::Exists($vd)) { [IO.File]::Delete($vd) } else { [IO.Directory]::Delete($vd) } }
      [void][IO.Directory]::CreateDirectory($vd)
      if ([IO.Directory]::Exists($FlCheck)) { [IO.Directory]::Delete($FlCheck, $true) }
      if ([IO.File]::Exists($FlCheck) -or (Is-Reparse $FlCheck)) {
        if (-not (Is-Reparse $FlCheck)) { [IO.File]::SetAttributes($FlCheck, [IO.FileAttributes]::Normal) }
        [IO.File]::Delete($FlCheck)
      }
      [IO.File]::WriteAllBytes($FlCheck, $FlCheckBytes)
    }
  } catch { }
}

# The system's process list, read once and only read: each process's id, its parent's id and its start
# time in UTC ticks (-1 when not given). $null when it can't be read within SECS seconds.
function Proc-Rows([int]$secs) {
  $l = New-Object System.Collections.Generic.List[object]
  try {
    if ($OnWindows) {
      foreach ($p in (Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, CreationDate -OperationTimeoutSec $secs -ErrorAction Stop)) {
        $s = [long]-1; if ($p.CreationDate) { $s = [long]$p.CreationDate.ToUniversalTime().Ticks }
        $l.Add(@([int]$p.ProcessId, [int]$p.ParentProcessId, $s))
      }
    } else {
      $psi = New-Object Diagnostics.ProcessStartInfo '/bin/ps'
      if ($FlTest -and $env:GIRD_CHECK_FLEET_PS) { $psi.FileName = $env:GIRD_CHECK_FLEET_PS }
      $psi.Arguments = '-A -o pid= -o ppid= -o lstart='
      $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true
      $lp = [Diagnostics.Process]::Start($psi)
      $t = $lp.StandardOutput.ReadToEndAsync()
      if (-not $t.Wait($secs * 1000) -or -not $lp.WaitForExit($secs * 1000) -or $lp.ExitCode -ne 0) { return $null }
      foreach ($x in ($t.Result -split "`n")) {
        if ($x -notmatch '^\s*([0-9]+)\s+([0-9]+)\s+(\S.*\S)\s*$') { continue }
        $s = [long]-1; try { $s = [long][DateTime]::ParseExact(($Matches[3] -replace '\s+', ' '), 'ddd MMM d HH:mm:ss yyyy', $Inv).ToUniversalTime().Ticks } catch { }
        $l.Add(@([int]$Matches[1], [int]$Matches[2], $s))
      }
    }
  } catch { return $null }
  , $l
}
# True when a process in ROWS still names ROOT as its parent and started between FROM and TO, or its
# start time can't be read. Windows gives an ended process's id to new processes, so this can be wrong
# either way; it only marks the account partly checked.
function Left-Running($rows, [int]$root, [long]$from, [long]$to) {
  foreach ($r in $rows) {
    if ($r[0] -ne $root -and $r[1] -eq $root -and ($r[2] -lt 0 -or $from -lt 0 -or ($r[2] -ge $from -and $r[2] -le $to))) { return $true }
  }
  $false
}
# Stops the account run, the one process this script started, through its own handle. What the run
# started, it stops itself before its time is up. True when the run did not end, or a process it
# started may still be running, or the process list could not be read; all within FlStopSecs.
function Stop-Run([Diagnostics.Process]$proc, [long]$rootStart) {
  $stopEnd = [DateTime]::UtcNow.AddSeconds($script:FlStopSecs)
  try { $proc.Kill() } catch { }
  $ended = $false
  try { $ended = $proc.WaitForExit([int][Math]::Max(0, ($stopEnd - [DateTime]::UtcNow).TotalMilliseconds)) } catch { }
  if (-not $ended) { return $true }
  $to = [DateTime]::UtcNow.Ticks; try { $to = [long]$proc.ExitTime.ToUniversalTime().Ticks } catch { }
  $secs = [int][Math]::Floor(($stopEnd - [DateTime]::UtcNow).TotalSeconds)
  if ($secs -lt 1) { return $true }
  $rows = Proc-Rows $secs
  if ($null -eq $rows) { return $true }
  # ps gives start times to the second.
  if (-not $OnWindows -and $rootStart -ge 0) { $rootStart -= $rootStart % [TimeSpan]::TicksPerSecond }
  Left-Running $rows $proc.Id $rootStart $to
}
function Quote-Arg([string]$a) {
  if ($a -and $a -notmatch '[\s"]') { return $a }
  '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# Starts the account run as a separate Windows PowerShell process, by full path, with -NoProfile, the
# person's own environment less the test-only GIRD_CHECK_* settings, no input and no window. Reads at
# most FlOutMax + 1 bytes of its output until it ends or LIMIT seconds pass. Its error stream is read
# and dropped.
function Run-Account([int]$limit) {
  $r = @{ Bytes = (New-Object byte[] 0); Timeout = $false; Left = $false; Started = $false; Exited = $false; Why = 'start' }
  $exe = ''
  if ($OnWindows) { $exe = J $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe' }
  elseif ($FlTest -and $env:GIRD_CHECK_FLEET_POWERSHELL) { $exe = $env:GIRD_CHECK_FLEET_POWERSHELL }
  $argv = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script:FlCheck, '-AccountRun', "--account-seconds=$limit")
  $psi = New-Object Diagnostics.ProcessStartInfo
  if ($FlTest -and $env:GIRD_CHECK_FLEET_LAUNCH) { $psi.FileName = $env:GIRD_CHECK_FLEET_LAUNCH; $argv = @($exe) + $argv } else { $psi.FileName = $exe }
  $psi.Arguments = (@($argv | ForEach-Object { Quote-Arg $_ }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
  $psi.WorkingDirectory = $script:FlState
  foreach ($k in @($psi.EnvironmentVariables.Keys)) { if (([string]$k).StartsWith('GIRD_CHECK_', [StringComparison]::OrdinalIgnoreCase)) { $psi.EnvironmentVariables.Remove($k) } }
  # The file it starts must still be the one this run carries.
  if ((File-Sha $script:FlCheck) -ne $script:FlCheckSha) { $r.Why = 'unpack'; return $r }
  try { $proc = [Diagnostics.Process]::Start($psi) } catch { return $r }
  if ($null -eq $proc) { return $r }
  $r.Started = $true
  $rootStart = [long]-1; try { $rootStart = [long]$proc.StartTime.ToUniversalTime().Ticks } catch { }
  try { $proc.StandardInput.Close() } catch { }
  $errTask = $null; try { $errTask = $proc.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null) } catch { }
  $buf = New-Object byte[] ($script:FlOutMax + 1); $got = 0
  $end = [DateTime]::UtcNow.AddSeconds($limit)
  $stream = $proc.StandardOutput.BaseStream
  while ($got -le $script:FlOutMax) {
    $t = $stream.ReadAsync($buf, $got, $buf.Length - $got)
    $ms = ($end - [DateTime]::UtcNow).TotalMilliseconds
    if ($ms -le 0 -or -not $t.Wait([int][Math]::Min(2147483647, $ms))) { $r.Timeout = $true; break }
    $n = $t.Result; if ($n -le 0) { break }
    $got += $n
  }
  if (-not $r.Timeout -and $got -le $script:FlOutMax) {
    $ms = ($end - [DateTime]::UtcNow).TotalMilliseconds
    if ($ms -le 0 -or -not $proc.WaitForExit([int][Math]::Min(2147483647, $ms))) { $r.Timeout = $true }
  }
  if ($r.Timeout -or $got -gt $script:FlOutMax -or -not $proc.HasExited) { $r.Left = Stop-Run $proc $rootStart } else { $r.Exited = $true }
  $r.Bytes = New-Object byte[] $got; [Array]::Copy($buf, $r.Bytes, $got)
  try { $proc.Dispose() } catch { }
  $r
}

# The ids an account run may send.
$IdAgents = @($Agents | ForEach-Object { $_[4] })
function Yolo-Id([string]$n) {
  foreach ($a in $Agents) { if ($a[0] -ceq $n) { return $a[4] } }
  ($n.ToLowerInvariant() -replace ' ', '-') -replace '[^a-z0-9-]', ''
}
$IdYolo = @($IdAgents) + @($FlYoloNames | ForEach-Object { Yolo-Id $_ })
$IdProviders = @($FlProviders -split ' ')
$IdIncidents = @($FlIncidents.Keys)
function Ids-Ok([string]$v, $allowed) { # every id allowed, none twice, at most 40, one space apart
  if ($v -eq '') { return $true }
  if ($v -cnotmatch '^[a-z0-9-]+( [a-z0-9-]+)*$') { return $false }
  $seen = @{}; $ids = $v -split ' '
  if ($ids.Count -gt 40) { return $false }
  foreach ($x in $ids) { if (-not ($allowed -ccontains $x) -or $seen.ContainsKey($x)) { return $false }; $seen[$x] = 1 }
  $true
}
# One account run's output. Every line must be the next key in FlKeys with a value of its kind; any
# other line, any other byte, or more than FlOutMax bytes refuses the whole output. On Windows
# protected is always ok, tmp_marks always empty and tmp_wiper always 0 (Windows has no shared /tmp),
# and engine rg, dotnet or none.
function Parse-Account([byte[]]$b) {
  if ($b.Length -lt 1 -or $b.Length -gt $script:FlOutMax) { return $null }
  foreach ($c in $b) { if (-not ($c -eq 10 -or $c -eq 32 -or $c -eq 61 -or $c -eq 95 -or $c -eq 45 -or ($c -ge 48 -and $c -le 57) -or ($c -ge 97 -and $c -le 122))) { return $null } }
  if ($b[$b.Length - 1] -ne 10) { return $null }
  $lines = [Text.Encoding]::ASCII.GetString($b, 0, $b.Length - 1).Split([char]10)
  if ($lines.Count -ne $script:FlKeys.Count) { return $null }
  $fa = @{}
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]; $k = $script:FlKeys[$i]
    if (-not $l.StartsWith("$k=", [StringComparison]::Ordinal)) { return $null }
    $v = $l.Substring($k.Length + 1)
    switch -CaseSensitive ($k) {
      { $_ -eq 'v' -or $_ -eq 'end' } { if ($v -cne '1') { return $null } }
      'agents' { if (-not (Ids-Ok $v $IdAgents)) { return $null } }
      'yolo' { if (-not (Ids-Ok $v $IdYolo)) { return $null } }
      'tools' { if (-not (Ids-Ok $v $FlTools)) { return $null } }
      'key_providers' { if (-not (Ids-Ok $v $IdProviders)) { return $null } }
      'platforms' { if (-not (Ids-Ok $v $FlPlatforms)) { return $null } }
      { @('incidents', 'possible', 'updates', 'lock_only', 'remove') -ccontains $_ } { if (-not (Ids-Ok $v $IdIncidents)) { return $null } }
      { @('sessions_partial', 'wiper', 'moved') -ccontains $_ } { if ($v -cnotmatch '^[01]$') { return $null } }
      'tmp_marks' { if ($v -cne '') { return $null } }
      'tmp_wiper' { if ($v -cne '0') { return $null } }
      'protected' { if ($v -cne 'ok') { return $null } }
      'engine' { if (@('rg', 'dotnet', 'none') -cnotcontains $v) { return $null } }
      { @('mcp_servers', 'mcp_token_files', 'key_files', 'history_keys', 'session_files', 'allow_list_keys', 'ssh_open', 'ak_links', 'planted', 'on_open', 'to_read', 'not_read') -ccontains $_ } { if ($v -cnotmatch '^(0|[1-9][0-9]{0,5})$') { return $null } }
    }
    $fa[$k] = $v
  }
  $fa
}
function Words([string]$v) { if ($v) { , @($v -split ' ') } else { , @() } }
function Json-List($ids) { '[' + ((@($ids) | Where-Object { $_ } | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']' }
function Json-Incidents($ids) { '[' + ((@($ids) | Where-Object { $_ } | ForEach-Object { '{"id":"' + $_ + '","level":"' + $FlIncidents[$_] + '"}' }) -join ',') + ']' }
function Json-Bool($b) { if ($b) { 'true' } else { 'false' } }
function Commas($ids) { (@($ids) -join ',') }

# --- The account --------------------------------------------------------------
$Row = ''; $AccOut = 'not_checked'; $AccInv = ''; $FlTimeHit = $false; $FlNotChecked = ''; $FlLeft = $false
if ($FlReason) { $FlNotChecked = $FlReason }
else {
  $lim = [int][Math]::Floor(($FlEnd - [DateTime]::UtcNow).TotalSeconds) - $FlStopSecs
  if ($lim -lt 1) { $FlNotChecked = 'deadline'; $FlTimeHit = $true }
  else {
    $run = Run-Account $lim
    $FlLeft = [bool]$run.Left
    $FA = Parse-Account $run.Bytes
    $stopped = $false
    if ($null -ne $FA) { if ($run.Timeout) { $stopped = $true } }
    elseif ($run.Timeout) { $FlNotChecked = 'time_limit' }
    elseif (-not $run.Started) { $FlReason = $run.Why; $FlNotChecked = $FlReason }
    elseif ([Text.Encoding]::ASCII.GetString($run.Bytes).Trim() -ceq 'language_mode=1') { $FlReason = 'language_mode'; $FlNotChecked = $FlReason }
    elseif ($run.Bytes.Length -eq 0 -and $run.Exited) { $FlReason = 'no_output'; $FlNotChecked = $FlReason }
    else { $FlNotChecked = 'bad_output' }
    if ($run.Timeout -and [DateTime]::UtcNow -ge $FlEnd) { $FlTimeHit = $true }
  }
}
$N_ACT = 0; $N_UPD = 0; $N_NC = 0
if ($FlNotChecked) {
  $AccOut = 'not_checked'; $N_NC = 1
  $pl = ''; if ($FlLeft) { $pl = ',"processes_left":true' }
  $Row = "{""account"":""$FlShown"",""complete"":false,""outcome"":""not_checked"",""not_checked"":""$FlNotChecked""$pl}"
  $AccInv = "$($FlShown): not_checked $FlNotChecked"
} else {
  $act = $false; $upd = $false; $inv = New-Object System.Collections.Generic.List[string]
  $ia = @(); $iu = @()
  foreach ($x in (Words $FA['incidents'])) { if ($FlIncidents[$x] -eq 'act') { $ia += $x } else { $iu += $x } }
  if ($FA['wiper'] -eq '1') { $act = $true; $inv.Add('wiper') }
  if ($ia.Count -gt 0) { $act = $true; $inv.Add("incidents $(Commas $ia)") }
  if ($FA['lock_only']) { $act = $true; $inv.Add("lockfile $(Commas (Words $FA['lock_only']))") }
  if ($iu.Count -gt 0) { $upd = $true }
  if ([int]$FA['planted'] -gt 0) { $act = $true; $inv.Add("planted $($FA['planted'])") }
  if ($FA['yolo']) { $upd = $true; $inv.Add("run-without-asking $(Commas (Words $FA['yolo']))") }
  if ([int]$FA['key_files'] -gt 0) { $act = $true; $kp = ''; if ($FA['key_providers']) { $kp = ' ' + (Commas (Words $FA['key_providers'])) }; $inv.Add("keys $($FA['key_files'])$kp") }
  if ([int]$FA['history_keys'] -gt 0) { $act = $true; $inv.Add("history $($FA['history_keys'])") }
  if ([int]$FA['session_files'] -gt 0) { $act = $true; $inv.Add("sessions $($FA['session_files'])") }
  if ([int]$FA['mcp_token_files'] -gt 0) { $act = $true; $inv.Add("mcp-tokens $($FA['mcp_token_files'])") }
  if ([int]$FA['allow_list_keys'] -gt 0) { $act = $true; $inv.Add("allow-lists $($FA['allow_list_keys'])") }
  if ([int]$FA['ak_links'] -gt 0) { $act = $true; $inv.Add("ssh-links $($FA['ak_links'])") }
  if ([int]$FA['ssh_open'] -gt 0) { $upd = $true; $inv.Add("ssh-open $($FA['ssh_open'])") }
  if ($FA['tools']) { $upd = $true; $inv.Add("update-tools $(Commas (Words $FA['tools']))") }
  if ($FA['platforms']) { $upd = $true; $inv.Add("platforms $(Commas (Words $FA['platforms']))") }
  if ([int]$FA['on_open'] -gt 0) { $upd = $true; $inv.Add("on-open $($FA['on_open'])") }
  if ([int]$FA['to_read'] -gt 0) { $upd = $true; $inv.Add("to-read $($FA['to_read'])") }
  if ($FA['updates']) { $upd = $true }
  if ($FA['remove']) { $upd = $true; $inv.Add("remove $(Commas (Words $FA['remove']))") }
  $ul = New-Object System.Collections.Generic.List[string]
  foreach ($x in (@($iu) + @(Words $FA['updates']))) { if ($x -and -not $ul.Contains($x)) { $ul.Add($x) } }
  if ($ul.Count -gt 0) { $inv.Add("update $(Commas $ul)") }
  if ($FA['possible']) { $upd = $true; $inv.Add("possible $(Commas (Words $FA['possible']))") }
  $complete = -not ($FA['sessions_partial'] -eq '1' -or [int]$FA['not_read'] -gt 0 -or $FA['moved'] -eq '1' -or $stopped)
  if ($act) { $AccOut = 'act' } elseif (-not $complete) { $AccOut = 'not_checked' } elseif ($upd) { $AccOut = 'review' } else { $AccOut = 'clear' }
  switch ($AccOut) { 'act' { $N_ACT = 1 } 'review' { $N_UPD = 1 } 'not_checked' { $N_NC = 1 } }
  if (-not $complete) { $inv.Add('partial') }
  $extra = ''; if ($stopped) { $extra += ',"stopped":"time_limit"' }; if ($FlLeft) { $extra += ',"processes_left":true' }
  $Row = "{""account"":""$FlShown"",""complete"":$(Json-Bool $complete),""outcome"":""$AccOut"",""agents"":$(Json-List (Words $FA['agents'])),""agents_run_without_asking"":$(Json-List (Words $FA['yolo'])),""tools_to_update"":$(Json-List (Words $FA['tools'])),""mcp_servers"":$($FA['mcp_servers']),""mcp_token_files"":$($FA['mcp_token_files']),""key_files"":$($FA['key_files']),""key_providers"":$(Json-List (Words $FA['key_providers'])),""history_keys"":$($FA['history_keys']),""session_files_with_keys"":$($FA['session_files']),""allow_list_keys"":$($FA['allow_list_keys']),""ssh_keys_no_passphrase"":$($FA['ssh_open']),""authorized_keys_links"":$($FA['ak_links']),""planted_files"":$($FA['planted']),""possible_signs"":$(Json-List (Words $FA['possible'])),""project_settings_on_open"":$($FA['on_open']),""files_to_read"":$($FA['to_read']),""versions_to_update"":$(Json-List (Words $FA['updates'])),""wiper"":$(Json-Bool ($FA['wiper'] -eq '1')),""lockfile_only_incidents"":$(Json-List (Words $FA['lock_only'])),""extensions_to_remove"":$(Json-List (Words $FA['remove'])),""platforms_found"":$(Json-List (Words $FA['platforms'])),""files_not_checked"":$($FA['not_read']),""agent_folders_moved"":$(Json-Bool ($FA['moved'] -eq '1')),""shared_tmp_markers"":[],""shared_tmp_wiper_logs"":false,""sessions_partly_checked"":$(Json-Bool ($FA['sessions_partial'] -eq '1')),""protected_folders"":""checked"",""session_engine"":""$($FA['engine'])""$extra,""incidents"":$(Json-Incidents (Words $FA['incidents']))}"
  $AccInv = "$($FlShown): $AccOut"; if ($inv.Count -gt 0) { $AccInv += ' ' + ($inv -join '; ') }
}

# --- The PC's shared places, by name only: nothing in them is read or run ------------
# Agents installed for every account under %ProgramFiles%, where the per-person install folders of
# the agents table (under %LOCALAPPDATA%\Programs) have their machine-wide twin.
$MAgents = New-Object System.Collections.Generic.List[string]; $MInc = New-Object System.Collections.Generic.List[string]; $MPoss = New-Object System.Collections.Generic.List[string]
$PF = @(); $PD = ''
if ($OnWindows) { $PF = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }; $PD = $env:ProgramData }
elseif ($FlTest -and ($env:GIRD_CHECK_FLEET_PROGRAMFILES -or $env:GIRD_CHECK_FLEET_PROGRAMDATA)) { $PF = @($env:GIRD_CHECK_FLEET_PROGRAMFILES) | Where-Object { $_ }; $PD = $env:GIRD_CHECK_FLEET_PROGRAMDATA }
$perUser = (J $LocalAppData 'Programs') + $Sep
foreach ($a in $Agents) {
  foreach ($p in $a[2]) {
    if (-not $p -or -not $p.StartsWith($perUser, $PathCmp)) { continue }
    foreach ($pf in $PF) {
      $mp = J $pf $p.Substring($perUser.Length)
      if (([IO.Directory]::Exists($mp) -or [IO.File]::Exists($mp)) -and -not $MAgents.Contains($a[4])) { $MAgents.Add($a[4]) }
    }
  }
}
# Malware markers in %ProgramData%, where any account can create a file but, on NTFS, a standard
# account cannot give one to another owner, so the owner decides: one that Administrators, SYSTEM or a
# service owns is a finding for the PC; one the person owns is a finding on their own row, which the
# account run reports; one another account owns, or whose owner can't be read, is a possible sign for
# the PC. A link is nothing, and a file with more than one name, whoever owns it, only a possible sign
# for the PC: any account can hard-link a file it can reach under a marker's name.
function Owner-Kind([string]$p) {
  if ($OnWindows) {
    try { $o = (Get-Acl -LiteralPath $p -ErrorAction Stop).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { return 'unknown' }
    if ($o -eq $FlSid) { return 'person' }
    if ($o -eq 'S-1-5-18' -or $o -eq 'S-1-5-19' -or $o -eq 'S-1-5-20' -or $o -eq 'S-1-5-32-544' -or $o.StartsWith('S-1-5-80-')) { return 'machine' }
    return 'other'
  }
  try { $u = [string](Get-Item -LiteralPath $p -Force -ErrorAction Stop).User } catch { return 'unknown' }
  if ($u -ceq $FlUser) { return 'person' }
  if ($u -ceq 'root') { return 'machine' }
  if ($u) { 'other' } else { 'unknown' }
}
function Mark-Kind([string]$kind, [string]$linkType) {
  if ($linkType) { return 'possible' }
  switch ($kind) { 'person' { 'account' } 'machine' { 'incident' } default { 'possible' } }
}
if ($PD) {
  foreach ($r in $FlProgramData) {
    $mp = J $PD $r[1]
    if (-not ([IO.File]::Exists($mp) -or [IO.Directory]::Exists($mp))) { continue }
    if (Is-Reparse $mp) { continue }
    $lt = $null; try { $lt = (Get-Item -LiteralPath $mp -Force -ErrorAction Stop).LinkType } catch { $lt = 'unknown' }
    switch (Mark-Kind (Owner-Kind $mp) ([string]$lt)) {
      'incident' { if (-not $MInc.Contains($r[0])) { $MInc.Add($r[0]) } }
      'possible' { if (-not $MPoss.Contains($r[0])) { $MPoss.Add($r[0]) } }
    }
  }
}
$MOut = 'clear'
foreach ($x in $MInc) { if ($FlIncidents[$x] -eq 'act') { $MOut = 'act' } elseif ($MOut -ne 'act') { $MOut = 'review' } }
if ($MPoss.Count -gt 0 -and $MOut -ne 'act') { $MOut = 'review' }
$Machine = "{""complete"":true,""outcome"":""$MOut"",""agents"":$(Json-List $MAgents),""possible_signs"":$(Json-List $MPoss),""incidents"":$(Json-Incidents $MInc)}"

# --- The result -----------------------------------------------------------------
$rank = @{ 'failed' = 5; 'act' = 4; 'not_checked' = 3; 'review' = 2; 'clear' = 1 }
$Outcome = 'clear'
foreach ($o in @($AccOut, $MOut)) { if ($rank[$o] -gt $rank[$Outcome]) { $Outcome = $o } }
if ($FlReason) { $Outcome = 'failed' }
# Intune keeps 2,048 characters of a script's output, and a value of 2,048 or more without +more could
# be one Intune cut, so a value is at most 2,047. Too long, the account keeps its outcome, and an act
# account its gh-token-monitor and incidents, and the value ends with +more; the saved file has the rest.
function Fit-Value([string]$head, [string]$acc, [string]$key, [string]$base, [string]$tail) {
  $v = "$head | $acc$tail"
  if ($v.Length -le 2047) { return $v }
  $v = "$head | $key$tail +more"
  if ($v.Length -le 2047) { return $v }
  "$head | $base$tail +more"
}
function Build-Text {
  $script:SummaryLine = "blindspot $script:Outcome accounts=1 act=$N_ACT review=$N_UPD not_checked=$N_NC other_profiles=$FlOther v=$FlRel at=$FlAt"
  if ($script:FlReason) { $script:SummaryLine += " reason=$($script:FlReason)" }
  # The inventory value: one line, no path, file name or key, and the head fixed: the outcome, the
  # time, other_profiles, then reason on a failed result.
  $head = "v1 $($script:Outcome) $($FlAt.Substring(0, 16))Z other_profiles=$FlOther"
  if ($script:FlReason) { $head += " reason=$($script:FlReason)" }
  $tail = ''
  if ($MOut -ne 'clear') {
    $tail = " | machine: $MOut"; if ($MInc.Count -gt 0) { $tail += " incidents $(Commas $MInc)" }; if ($MPoss.Count -gt 0) { $tail += "; possible $(Commas $MPoss)" }
  }
  $key = "$($FlShown): $AccOut"
  if ($AccOut -eq 'act') { $ks = @($inv | Where-Object { $_ -eq 'wiper' -or $_.StartsWith('incidents ') }); if ($ks.Count -gt 0) { $key += ' ' + ($ks -join '; ') } }
  $script:InventoryV = Fit-Value $head $script:AccInv $key "$($FlShown): $AccOut" $tail
  $dl = Json-Bool $FlTimeHit
  $rs = ''; if ($script:FlReason) { $rs = "`n  ""reason"": ""$($script:FlReason)""," }
  $script:JsonDoc = "{`n  ""blindspot"": ""1"",`n  ""script"": ""$FlRel"",`n  ""checked_at"": ""$FlAt"",`n  ""checked_epoch"": $FlEpoch,`n  ""os"": ""$FlOs"",`n  ""outcome"": ""$($script:Outcome)"",$rs`n  ""deadline_reached"": $dl,`n  ""other_profiles"": $FlOther,`n  ""accounts"": [$Row],`n  ""machine"": $Machine,`n  ""summary"": ""$($script:SummaryLine)"",`n  ""inventory"": ""$($script:InventoryV)"",`n  ""learn_more"": ""https://gird.ai/argus""`n}"
}
Build-Text
# Saved in the person's own profile: written to a new file, then renamed into place.
function Save-Result([string]$text) {
  if (-not (State-Prep)) { return $false }
  $dst = J $script:FlState 'last.json'; $tmp = J $script:FlState ".last.json.$PID.tmp"
  try {
    [IO.File]::WriteAllText($tmp, $text + "`n", (New-Object Text.UTF8Encoding($false)))
    if ([IO.Directory]::Exists($dst)) { return $false }
    if ([IO.File]::Exists($dst) -or (Is-Reparse $dst)) { [IO.File]::Delete($dst) }
    [IO.File]::Move($tmp, $dst)
    return $true
  } catch { try { [IO.File]::Delete($tmp) } catch { }; return $false }
}
if (-not (Save-Result $JsonDoc)) { if (-not $FlReason) { $FlReason = 'save' }; $Outcome = 'failed'; Build-Text }

if ($Json) { [Console]::Out.Write($JsonDoc + "`n") }
elseif ($Summary) { [Console]::Out.Write($SummaryLine + "`n") }
else { [Console]::Out.Write($InventoryV + "`n") }
if ($MacExitCodes) {
  if ($Outcome -eq 'failed') { exit 13 }
  if ($ExitZero) { exit 0 }
  switch ($Outcome) { 'clear' { exit 0 } 'act' { exit 10 } 'review' { exit 11 } default { exit 12 } }
}
if ($Outcome -eq 'failed') { exit 1 }
if ($ExitZero -or $Outcome -eq 'clear') { exit 0 }
exit 1
