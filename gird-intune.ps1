<#
Blindspot for Microsoft Intune: sets up the daily fleet check and reads every PC's result.
https://gird.ai/blindspot

Run it on your own PC, signed in as an Intune admin. It signs in to Microsoft Graph with
Microsoft's own PowerShell module and sends nothing anywhere else.

  gird-intune.ps1 -Deploy -Group <name>   adds the check as an Intune Remediation for that group
                                          only: runs once a day as the signed-in person, 64-bit, no
                                          fix script. Run again with a newer release to update it.
  gird-intune.ps1 -Report                 reads each PC's latest result and saves a report (HTML
                                          and CSV) in this folder, or in -OutDir. A Windows PC in the
                                          assigned group with no result is listed as no result yet.
  gird-intune.ps1 -Remove                 deletes the Remediation this tool made, after showing it

  -FleetScript <path>   blindspot-fleet.ps1 to deploy (default: next to this file)
  -StaleDays <days>     with -Report, a result older than this is stale (default 3, at most 30)
  -WhatIf               with -Deploy or -Remove, shows what would change and changes nothing
  -Force                with -Remove, deletes without asking again

Needs the Microsoft.Graph.Authentication module. Runs on Windows PowerShell 5.1 and
PowerShell 7. This file is plain ASCII on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Deploy, [switch]$Report, [switch]$Remove, [switch]$Help, [switch]$Force,
  [string]$Group, [string]$FleetScript, [string]$OutDir, [int]$StaleDays = 3
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$GraphRoot = 'https://graph.microsoft.com/'
$Beta = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
$Name = 'Blindspot fleet check'
$Publisher = 'Blindspot'
$MaxScriptBytes = 200 * 1024
$MarkerRx = '\(blindspot-intune-id: ([0-9a-f]{32})\)$'

function Show-Usage {
  Write-Host 'Usage:'
  Write-Host '  gird-intune.ps1 -Deploy -Group <name> [-FleetScript <path>] [-WhatIf]'
  Write-Host '  gird-intune.ps1 -Report [-StaleDays <days>] [-OutDir <folder>]'
  Write-Host '  gird-intune.ps1 -Remove [-WhatIf] [-Force]'
}
function Get-Plain($S) {
  if ($null -eq $S) { return '' }
  return [regex]::Replace([string]$S, '[\p{Cc}\p{Cf}]', '')
}
function Stop-Tool([string]$Message, [int]$Code = 1) {
  [Console]::Error.WriteLine((Get-Plain $Message))
  exit $Code
}

$modes = @($Deploy.IsPresent, $Report.IsPresent, $Remove.IsPresent | Where-Object { $_ }).Count
if ($Help) { Show-Usage; exit 0 }
if ($modes -ne 1) { Show-Usage; Stop-Tool 'Give one of -Deploy, -Report or -Remove.' 2 }
if ($Group -and -not $Deploy) { Stop-Tool '-Group works with -Deploy only.' 2 }
if ($FleetScript -and -not $Deploy) { Stop-Tool '-FleetScript works with -Deploy only.' 2 }
if ($PSBoundParameters.ContainsKey('StaleDays') -and -not $Report) { Stop-Tool '-StaleDays works with -Report only.' 2 }
if ($OutDir -and -not $Report) { Stop-Tool '-OutDir works with -Report only.' 2 }
if ($Force -and -not $Remove) { Stop-Tool '-Force works with -Remove only.' 2 }
if ($StaleDays -lt 1 -or $StaleDays -gt 30) { Stop-Tool '-StaleDays takes a number of days, from 1 to 30.' 2 }
if ($Deploy -and -not $Group) { Stop-Tool '-Deploy needs -Group <name>: the Microsoft Entra group whose PCs run the check.' 2 }

function Get-Prop($Object, [string]$Key) {
  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Key)) { return $Object[$Key] }
    return $null
  }
  $p = $Object.PSObject.Properties[$Key]
  if ($p) { return $p.Value }
  return $null
}

function Connect-Graph([string[]]$Scopes) {
  if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    [Console]::Error.WriteLine("This needs Microsoft's Graph sign-in module. Install it with:")
    [Console]::Error.WriteLine('  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser')
    exit 3
  }
  Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
  $c = Get-Command Connect-MgGraph -ErrorAction SilentlyContinue
  if (-not $c -or -not $c.Parameters.ContainsKey('NoWelcome') -or -not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("The Microsoft Graph sign-in module on this PC is too old for this tool. Update it with:")
    [Console]::Error.WriteLine('  Update-Module Microsoft.Graph.Authentication')
    exit 3
  }
  Write-Host ('Signs in to Microsoft Graph and asks for these permissions: ' + ($Scopes -join ', ') + '.')
  try { Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop | Out-Null }
  catch { Stop-Tool ("Could not sign in to Microsoft Graph: " + $_.Exception.Message) }
}

function Invoke-Graph([string]$Method, [string]$Uri, $Body) {
  if (-not $Uri.StartsWith($GraphRoot, [StringComparison]::Ordinal)) {
    throw "Stopped: Microsoft Graph pointed to an address that is not Microsoft Graph."
  }
  $p = @{ Method = $Method; Uri = $Uri; ErrorAction = 'Stop' }
  if ($null -ne $Body) {
    $p.Body = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
    $p.ContentType = 'application/json'
  }
  Invoke-MgGraphRequest @p
}

function Get-GraphAll([string]$Uri) {
  $items = New-Object System.Collections.ArrayList
  $seen = @{}
  $next = $Uri
  while ($next) {
    if ($seen.ContainsKey($next)) { throw 'Stopped: Microsoft Graph sent the same page twice.' }
    $seen[$next] = $true
    $r = Invoke-Graph 'GET' $next $null
    $has = $false; $v = $null
    if ($r -is [System.Collections.IDictionary]) { if ($r.Contains('value')) { $has = $true; $v = $r['value'] } }
    elseif ($null -ne $r -and $r.PSObject.Properties['value']) { $has = $true; $v = $r.PSObject.Properties['value'].Value }
    if (-not $has -or $null -eq $v) { throw 'Stopped: Microsoft Graph sent a page of results with no list in it, so nothing was read from it.' }
    foreach ($x in $v) { [void]$items.Add($x) }
    $next = [string](Get-Prop $r '@odata.nextLink')
  }
  return $items.ToArray()
}

function Test-Ours($S) {
  if ((Get-Prop $S 'isGlobalScript') -eq $true) { return $false }
  if ([string](Get-Prop $S 'publisher') -cne $Publisher) { return $false }
  return ([string](Get-Prop $S 'description')) -cmatch $MarkerRx
}

function Get-Ours {
  $all = @(Get-GraphAll ($Beta + '?$select=id,displayName,description,publisher,isGlobalScript'))
  $mine = @($all | Where-Object { Test-Ours $_ })
  $named = @($all | Where-Object { ([string](Get-Prop $_ 'displayName')) -eq $Name -and -not (Test-Ours $_) })
  return @{ Mine = $mine; NamedOnly = $named }
}

function Show-Script($S, [string]$Lead) {
  Write-Host ($Lead + ': ' + (Get-Plain (Get-Prop $S 'displayName')))
  Write-Host ('  id:            ' + (Get-Plain (Get-Prop $S 'id')))
  $c = Get-Prop $S 'createdDateTime'; if ($c) { Write-Host ('  created:       ' + (Get-Plain $c)) }
  $m = Get-Prop $S 'lastModifiedDateTime'; if ($m) { Write-Host ('  last changed:  ' + (Get-Plain $m)) }
}

function Get-Checked([string]$Id, [string]$Lead, [string]$Mode) {
  $s = Invoke-Graph 'GET' ($Beta + '/' + [Uri]::EscapeDataString($Id)) $null
  if (-not (Test-Ours $s) -or [string](Get-Prop $s 'id') -ne $Id) { Stop-Tool "The Remediation changed while this ran, so nothing was changed. Run $Mode again." }
  Show-Script $s $Lead
  $assigned = @(Get-GraphAll ($Beta + '/' + [Uri]::EscapeDataString($Id) + '/assignments'))
  if ($assigned.Count -eq 0) { Write-Host '  assigned to:   no group' }
  else { Write-Host ('  assigned to:   ' + $assigned.Count + ' group' + $(if ($assigned.Count -eq 1) { '' } else { 's' })) }
  return $s
}

function Stop-Several($Mine) {
  [Console]::Error.WriteLine('More than one Remediation carries this tool''s mark, so it changes none of them:')
  foreach ($s in $Mine) { [Console]::Error.WriteLine('  ' + (Get-Plain (Get-Prop $s 'id')) + '  ' + (Get-Plain (Get-Prop $s 'displayName'))) }
  Stop-Tool 'Delete the extra ones in the Intune admin center (Devices > Scripts and remediations), then run this again.'
}

function Invoke-Deploy {
  $path = $FleetScript
  if (-not $path) { $path = Join-Path $PSScriptRoot 'blindspot-fleet.ps1' }
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Tool "No script at $path. Give the path with -FleetScript." }
  $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path).ProviderPath)
  if ($bytes.Length -eq 0) { Stop-Tool "$path is empty." }
  if ($bytes.Length -ge $MaxScriptBytes) {
    Stop-Tool ("$path is " + [Math]::Ceiling($bytes.Length / 1024) + ' KB. Intune takes a script under 200 KB: use the blindspot-fleet.ps1 from a release.')
  }
  Connect-Graph @('DeviceManagementScripts.ReadWrite.All', 'Group.ReadBasic.All')

  $q = "displayName eq '" + $Group.Replace("'", "''") + "'"
  $groups = @(Get-GraphAll ('https://graph.microsoft.com/v1.0/groups?$filter=' + [Uri]::EscapeDataString($q) + '&$select=id,displayName'))
  if ($groups.Count -eq 0) { Stop-Tool "No group is named '$Group'. Check the name in Microsoft Entra ID." }
  if ($groups.Count -gt 1) {
    [Console]::Error.WriteLine("$($groups.Count) groups are named '$Group', so this does not pick one:")
    foreach ($g in $groups) { [Console]::Error.WriteLine('  ' + (Get-Plain (Get-Prop $g 'id'))) }
    Stop-Tool 'Rename one of them, or make a group for the check, and run this again.'
  }
  $groupId = [string](Get-Prop $groups[0] 'id')
  if (-not $groupId) { Stop-Tool 'Microsoft Graph sent the group without its id, so nothing was changed.' }

  $found = Get-Ours
  if ($found.Mine.Count -gt 1) { Stop-Several $found.Mine }
  $existing = $null
  if ($found.Mine.Count -eq 1) { $existing = $found.Mine[0] }
  elseif ($found.NamedOnly.Count -gt 0) {
    Stop-Tool "A Remediation named '$Name' is already there, and this tool did not make it, so it leaves it alone. Rename or delete it in the Intune admin center, then run this again."
  }

  $mark = $null
  if ($existing) {
    $existing = Get-Checked ([string](Get-Prop $existing 'id')) 'Updates' '-Deploy'
    $m = [regex]::Match([string](Get-Prop $existing 'description'), $MarkerRx)
    $mark = $m.Groups[1].Value
  } else {
    $mark = [Guid]::NewGuid().ToString('N')
  }
  $body = [ordered]@{
    '@odata.type' = '#microsoft.graph.deviceHealthScript'
    displayName = $Name
    description = "Finds AI keys in plain text, coding agents, MCP configs and signs of malware on each PC, for the signed-in person. Made by gird-intune.ps1, which finds it again by this mark (blindspot-intune-id: $mark)"
    publisher = $Publisher
    detectionScriptContent = [Convert]::ToBase64String($bytes)
    runAsAccount = 'user'
    runAs32Bit = $false
    enforceSignatureCheck = $false
  }
  $assign = @{
    deviceHealthScriptAssignments = @(
      [ordered]@{
        '@odata.type' = '#microsoft.graph.deviceHealthScriptAssignment'
        target = [ordered]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId }
        runRemediationScript = $false
        runSchedule = [ordered]@{ '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'; interval = 1; useUtc = $false; time = '09:00:00' }
      }
    )
  }

  $assignText = "Assign it to the group '$Group' only, daily, as the signed-in person. This replaces the groups it is assigned to now"
  $id = $null
  if ($existing) {
    $id = [string](Get-Prop $existing 'id')
    $shown = Get-Plain "$Name ($id)"
    $doScript = $PSCmdlet.ShouldProcess($shown, 'Replace its script with ' + $path)
    $doAssign = $PSCmdlet.ShouldProcess($shown, $assignText)
    if (-not ($doScript -and $doAssign)) { return }
    Invoke-Graph 'PATCH' ($Beta + '/' + [Uri]::EscapeDataString($id)) $body | Out-Null
    Write-Host "Updated the script of '$Name'."
  } else {
    Write-Host "Creates: $Name"
    $doScript = $PSCmdlet.ShouldProcess($Name, 'Create a Remediation from ' + $path)
    $doAssign = $PSCmdlet.ShouldProcess($Name, $assignText)
    if (-not ($doScript -and $doAssign)) { return }
    $created = Invoke-Graph 'POST' $Beta $body
    $id = [string](Get-Prop $created 'id')
    if (-not $id) { Stop-Tool 'Intune did not say what id it gave the new Remediation. Run -Deploy again: it finds it by its mark.' }
    Write-Host (Get-Plain "Created '$Name' ($id).")
  }
  try { Invoke-Graph 'POST' ($Beta + '/' + [Uri]::EscapeDataString($id) + '/assign') $assign | Out-Null }
  catch { Stop-Tool ("The Remediation is there but is not assigned yet: " + $_.Exception.Message + ' Run -Deploy again.') }
  Write-Host "Assigned to '$Group' only: runs once a day, as the signed-in person, in 64-bit PowerShell, with no fix script."
}

function Invoke-Remove {
  Connect-Graph @('DeviceManagementScripts.ReadWrite.All')
  $found = Get-Ours
  if ($found.Mine.Count -eq 0) { Write-Host 'Nothing to remove: no Remediation carries this tool''s mark.'; return }
  if ($found.Mine.Count -gt 1) { Stop-Several $found.Mine }
  $id = [string](Get-Prop $found.Mine[0] 'id')
  [void](Get-Checked $id 'Deletes' '-Remove')
  $shown = Get-Plain "$Name ($id)"
  if (-not $PSCmdlet.ShouldProcess($shown, 'Delete')) { return }
  if (-not $Force -and -not $PSCmdlet.ShouldContinue("Delete $shown from Intune?", 'Delete')) { Write-Host 'Nothing was deleted.'; return }
  Invoke-Graph 'DELETE' ($Beta + '/' + [Uri]::EscapeDataString($id)) $null | Out-Null
  Write-Host "Deleted $shown. PCs stop running it at their next check-in with Intune."
}

# The inventory value, as gird-fleet.sh writes it (docs/designs/fleet-mode.md, "The result"),
# with the Windows header fields other_profiles= and reason=. Anything else does not fit.
$Outcomes = @{ clear = 1; review = 2; not_checked = 3; act = 4; failed = 5 }
$NoArg = @('wiper', 'tmp-wiper', 'partial')
$NumArg = @('planted', 'history', 'sessions', 'mcp-tokens', 'allow-lists', 'ssh-links', 'ssh-open', 'on-open', 'to-read')
$ListArg = @('incidents', 'lockfile', 'run-without-asking', 'update-tools', 'platforms', 'remove', 'update', 'possible', 'tmp-marks')
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
$ReasonRx = '^[a-z0-9_]{1,40}$'
$IntuneKeeps = 2048
$IdList = '^[a-z0-9][a-z0-9._-]{0,63}(,[a-z0-9][a-z0-9._-]{0,63}){0,63}$'

function Test-Items([string]$Text, [System.Collections.ArrayList]$Into) {
  foreach ($it in $Text.Split([string[]]@('; '), [StringSplitOptions]::None)) {
    $sp = $it.IndexOf(' ')
    $k = $it; $a = $null
    if ($sp -ge 0) { $k = $it.Substring(0, $sp); $a = $it.Substring($sp + 1) }
    if ($NoArg -ccontains $k) { if ($null -ne $a) { return $false } }
    elseif ($NumArg -ccontains $k) { if ($null -eq $a -or $a -cnotmatch '^[1-9][0-9]{0,5}$') { return $false } }
    elseif ($ListArg -ccontains $k) { if ($null -eq $a -or $a -cnotmatch $IdList) { return $false } }
    elseif ($k -ceq 'keys') {
      if ($null -eq $a -or $a -cnotmatch '^[1-9][0-9]{0,5}( [a-z0-9][a-z0-9._-]{0,63}(,[a-z0-9][a-z0-9._-]{0,63}){0,63})?$') { return $false }
    }
    else { return $false }
    if (-not $Into.Contains($k)) { [void]$Into.Add($k) }
  }
  return $true
}

function Read-Inventory([string]$Raw) {
  $r = @{ Ok = $false; Outcome = ''; Time = $null; Accounts = @(); Kinds = @(); More = $false; OtherProfiles = 0; Reason = ''; Special = '' }
  if ($null -eq $Raw) { return $r }
  $t = $Raw.TrimEnd(" `t`r`n".ToCharArray())
  if ($Raw.Length -ge $IntuneKeeps -and -not $t.EndsWith(' +more', [StringComparison]::Ordinal)) { $r.Ok = $true; $r.Special = 'cut'; return $r }
  if ($t.Length -eq 0 -or $t.Length -gt $IntuneKeeps) { return $r }
  if ($t -cnotmatch '^[A-Za-z0-9 ._:;,|+=-]+$') { return $r }
  if ($t -ceq 'none') { $r.Ok = $true; $r.Special = 'none'; return $r }
  if ($t -ceq 'unreadable') { $r.Ok = $true; $r.Special = 'unreadable'; return $r }
  $m = [regex]::Match($t, '^stale: last run ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z)$')
  if ($m.Success) { $r.Ok = $true; $r.Special = 'stale'; $r.Time = $m.Groups[1].Value; return $r }
  $m = [regex]::Match($t, '^failed: the run started ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z) did not finish or could not save its result$')
  if ($m.Success) { $r.Ok = $true; $r.Special = 'failed'; $r.Time = $m.Groups[1].Value; return $r }

  if ($t.EndsWith(' +more', [StringComparison]::Ordinal)) { $r.More = $true; $t = $t.Substring(0, $t.Length - 6) }
  $m = [regex]::Match($t, '^v1 (failed|act|not_checked|review|clear) ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z)( other_profiles=([0-9]{1,4}))?( reason=([a-z0-9_]{1,40}))?((?: \| [^|]+)*)$')
  if (-not $m.Success) { return $r }
  $out = $m.Groups[1].Value
  $r.Outcome = $out
  $r.Time = $m.Groups[2].Value
  if ($m.Groups[4].Success) { $r.OtherProfiles = [int]$m.Groups[4].Value }
  if ($m.Groups[6].Success) {
    if ($out -cne 'failed') { return $r }
    $r.Reason = $m.Groups[6].Value
  }
  $segText = $m.Groups[7].Value
  $segs = @()
  if ($segText.Length -gt 0) { $segs = $segText.Substring(3).Split([string[]]@(' | '), [StringSplitOptions]::None) }
  if ($segs.Count -eq 0 -and $out -cne 'failed') { return $r }
  $kinds = New-Object System.Collections.ArrayList
  $accounts = New-Object System.Collections.ArrayList
  $worst = 0
  $names = @{}
  foreach ($s in $segs) {
    if ($s -ceq 'no accounts') {
      if ($worst -lt 3) { $worst = 3 }
      [void]$accounts.Add(@{ Name = '(no accounts)'; Outcome = 'not_checked'; Detail = 'no accounts' })
      continue
    }
    $sm = [regex]::Match($s, '^([A-Za-z0-9][A-Za-z0-9._-]{0,63}): (act|not_checked|review|clear)(;? (.+))?$')
    if (-not $sm.Success) { return $r }
    $who = $sm.Groups[1].Value; $so = $sm.Groups[2].Value; $rest = $sm.Groups[4].Value
    if ($names.ContainsKey($who) -and $who -cne 'invalid-name') { return $r }
    $names[$who] = $true
    $semi = $sm.Groups[3].Success -and $sm.Groups[3].Value.StartsWith(';')
    if ($semi -and $who -cne 'machine') { return $r }
    if ($sm.Groups[3].Success) {
      if ($so -ceq 'clear') { return $r }
      $isReason = $so -ceq 'not_checked' -and $rest -cmatch $ReasonRx -and -not ($NoArg -ccontains $rest)
      if (-not $isReason -and -not (Test-Items $rest $kinds)) { return $r }
    }
    $rank = $Outcomes[$so]
    if ($rank -gt $worst) { $worst = $rank }
    [void]$accounts.Add(@{ Name = $who; Outcome = $so; Detail = $rest })
  }
  $head = $Outcomes[$out]
  if ($worst -gt $head) { return $r }
  if ($out -cne 'failed' -and -not $r.More -and $worst -ne $head) { return $r }
  $r.Accounts = $accounts.ToArray()
  $r.Kinds = $kinds.ToArray()
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

function Get-PcRow($State, [DateTime]$Now) {
  $dev = Get-Prop $State 'managedDevice'
  $pc = [string](Get-Prop $dev 'deviceName')
  if (-not $pc) { $pc = '(name not given) ' + [string](Get-Prop $State 'id') }
  $raw = Get-Prop $State 'preRemediationDetectionScriptOutput'
  if ($null -eq $raw) { $raw = '' }
  $raw = [string]$raw
  $det = [string](Get-Prop $State 'detectionState')
  $row = [ordered]@{
    PC = $pc; User = [string](Get-Prop $dev 'userPrincipalName'); Status = ''; Why = ''; CheckedAt = ''
    Details = ''; Kinds = @(); LastReport = [string](Get-Prop $State 'lastStateUpdateDateTime'); Output = $raw
  }
  if ($raw.Trim().Length -eq 0) {
    if ($det -eq 'scriptError' -or $det -eq 'fail') { $row.Status = 'failed'; $row.Why = 'the check stopped with an error and sent no result' }
    else { $row.Status = 'no_result'; $row.Why = 'no result from this PC yet' }
    return $row
  }
  $p = Read-Inventory $raw
  if (-not $p.Ok) { $row.Status = 'not_checked'; $row.Why = 'its result does not fit the expected format'; return $row }
  switch ($p.Special) {
    'none' { $row.Status = 'no_result'; $row.Why = 'the check has not finished a run on this PC'; return $row }
    'unreadable' { $row.Status = 'not_checked'; $row.Why = 'the saved result could not be read'; return $row }
    'stale' { $row.Status = 'stale'; $row.Why = 'the last finished run is old'; $row.CheckedAt = $p.Time; return $row }
    'failed' { $row.Status = 'failed'; $row.Why = 'a run did not finish or could not save its result'; $row.CheckedAt = $p.Time; return $row }
    'cut' { $row.Status = 'not_checked'; $row.Why = 'its result fills all the room Intune keeps and does not end in +more, so Intune may have cut it short'; return $row }
  }
  $row.CheckedAt = $p.Time
  $at = Get-UtcTime $p.Time
  $age = ($Now - $at).TotalSeconds
  if ($age -lt -3600) { $row.Status = 'not_checked'; $row.Why = 'its result is dated in the future'; return $row }
  if ($age -gt $StaleDays * 86400) {
    $row.Status = 'stale'; $row.Why = "its result is older than $StaleDays days (it read " + $StatusText[$p.Outcome].ToLower() + ')'; return $row
  }
  if ($p.Outcome -eq 'clear' -and $det -cne 'success') {
    $row.Status = 'not_checked'; $row.Why = 'it reads clear, but Intune says the check did not succeed'; return $row
  }
  $row.Status = $p.Outcome
  $row.Kinds = $p.Kinds
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
  if ($p.More) { $why += 'more on the PC than Intune keeps' }
  if ($p.OtherProfiles -gt 0) { $why += "$($p.OtherProfiles) other account" + $(if ($p.OtherProfiles -eq 1) { '' } else { 's' }) + ' on this PC not checked' }
  $row.Why = $why -join '; '
  return $row
}

function ConvertTo-HtmlText([string]$S) {
  if ($null -eq $S) { return '' }
  return [System.Net.WebUtility]::HtmlEncode($S)
}
function ConvertTo-CsvCell([string]$S) {
  if ($null -eq $S) { $S = '' }
  $risky = '=+-@' + "`t`r`n" + [char]0xFF1D + [char]0xFF0B + [char]0xFF0D + [char]0xFF20
  $first = $S.TrimStart(' ')
  if ($first.Length -gt 0 -and $risky.IndexOf($first[0]) -ge 0) { $S = "'" + $S }
  return '"' + $S.Replace('"', '""') + '"'
}

function Get-SilentPcs([string]$ScriptId, $States) {
  $notes = New-Object System.Collections.ArrayList
  $rows = @()
  $include = @{}
  $exclude = @{}
  $everyPc = $false
  $assigned = @(Get-GraphAll ($Beta + '/' + [Uri]::EscapeDataString($ScriptId) + '/assignments'))
  if ($assigned.Count -eq 0) { return @{ Rows = @(); Notes = @(); Unassigned = $true } }
  foreach ($a in $assigned) {
    $t = Get-Prop $a 'target'
    $type = ([string](Get-Prop $t '@odata.type')).TrimStart('#')
    $gid = [string](Get-Prop $t 'groupId')
    $ft = [string](Get-Prop $t 'deviceAndAppManagementAssignmentFilterType')
    if ($ft -and $ft -ne 'none') {
      [void]$notes.Add('An assignment filter is set. This tool cannot apply it, so some PCs listed as no result yet may not be meant to run the check.')
    }
    if ($type -ceq 'microsoft.graph.allDevicesAssignmentTarget') { $everyPc = $true; continue }
    if ($type -cne 'microsoft.graph.groupAssignmentTarget' -and $type -cne 'microsoft.graph.exclusionGroupAssignmentTarget') {
      [void]$notes.Add("Could not list the PCs with no result for an assignment to '$type': Microsoft Graph does not say which PCs it reaches. PCs with no result there are not in this report, which does not mean they are clear.")
      continue
    }
    if (-not $gid) { [void]$notes.Add('Could not list the PCs with no result for one assignment: Microsoft Graph sent it without a group.'); continue }
    $excluding = $type -ceq 'microsoft.graph.exclusionGroupAssignmentTarget'
    try { $members = @(Get-GraphAll ('https://graph.microsoft.com/v1.0/groups/' + [Uri]::EscapeDataString($gid) + '/transitiveMembers')) }
    catch {
      if ($_.Exception.Message.StartsWith('Stopped:')) { throw }
      if ($excluding) {
        [void]$notes.Add("Could not read the members of exclusion group $($gid): " + $_.Exception.Message + ' So a PC listed as no result yet may in fact be excluded from the check.')
      } else {
        [void]$notes.Add("Could not list the PCs with no result for group $gid, because its members could not be read: " + $_.Exception.Message + ' PCs with no result there are not in this report, which does not mean they are clear.')
      }
      continue
    }
    $people = 0; $hidden = 0
    foreach ($m in $members) {
      $mt = ([string](Get-Prop $m '@odata.type')).TrimStart('#')
      if ($mt -ceq 'microsoft.graph.device') {
        $did = [string](Get-Prop $m 'deviceId')
        if (-not $did) { $hidden++ }
        elseif ($excluding) { $exclude[$did] = $true }
        else { $include[$did] = $true }
      }
      elseif ($mt -ceq 'microsoft.graph.user') { $people++ }
    }
    if ($people -gt 0 -and $excluding) {
      [void]$notes.Add("Group $gid is an exclusion group and holds people, so some PCs listed as no result yet may be excluded from the check.")
    }
    elseif ($people -gt 0) {
      [void]$notes.Add("Could not list the PCs with no result for the people in group $gid ($people): Microsoft Graph does not say which of a person's PCs Intune runs the check on. PCs with no result there are not in this report, which does not mean they are clear.")
    }
    if ($hidden -gt 0 -and $excluding) {
      [void]$notes.Add("Could not read $hidden PC" + $(if ($hidden -eq 1) { '' } else { 's' }) + " in exclusion group $gid. Allow Device.Read.All for this tool and run -Report again. Until then a PC listed as no result yet may in fact be excluded from the check.")
    }
    elseif ($hidden -gt 0) {
      [void]$notes.Add("Could not read $hidden PC" + $(if ($hidden -eq 1) { '' } else { 's' }) + " in group $gid. Allow Device.Read.All for this tool and run -Report again. PCs with no result there are not in this report, which does not mean they are clear.")
    }
  }
  if ($include.Count -eq 0 -and -not $everyPc) { return @{ Rows = @(); Notes = $notes.ToArray(); Unassigned = $false } }

  $seen = @{}
  foreach ($st in $States) {
    $dev = Get-Prop $st 'managedDevice'
    foreach ($k in @('id', 'azureADDeviceId')) {
      $v = [string](Get-Prop $dev $k)
      if ($v) { $seen[$v] = $true }
    }
  }
  $managed = @(Get-GraphAll ('https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$select=id,deviceName,userPrincipalName,azureADDeviceId,operatingSystem'))
  foreach ($d in $managed) {
    if ([string](Get-Prop $d 'operatingSystem') -ne 'Windows') { continue }
    $aad = [string](Get-Prop $d 'azureADDeviceId')
    $mid = [string](Get-Prop $d 'id')
    if ($mid -and $seen.ContainsKey($mid)) { continue }
    if ($aad -and $seen.ContainsKey($aad)) { continue }
    if ($aad -and $exclude.ContainsKey($aad)) { continue }
    if (-not $everyPc -and -not ($aad -and $include.ContainsKey($aad))) { continue }
    $pc = [string](Get-Prop $d 'deviceName')
    if (-not $pc) { $pc = '(name not given) ' + $mid }
    $rows += New-Object PSObject -Property ([ordered]@{
      PC = $pc; User = [string](Get-Prop $d 'userPrincipalName'); Status = 'no_result'
      Why = 'no result yet: Intune has no result row for this PC'; CheckedAt = ''; Details = ''; Kinds = @(); LastReport = ''; Output = ''
    })
  }
  return @{ Rows = $rows; Notes = $notes.ToArray(); Unassigned = $false }
}

function Get-OutDir {
  $d = $OutDir
  if (-not $d) { $d = '.' }
  try { $rp = @(Resolve-Path -LiteralPath $d -ErrorAction Stop) } catch { Stop-Tool "No folder at $d." }
  if ($rp.Count -ne 1 -or $rp[0].Provider.Name -cne 'FileSystem') { Stop-Tool "$d is not a folder on disk. Give a folder with -OutDir." }
  $full = $rp[0].ProviderPath
  if (-not [IO.Directory]::Exists($full)) { Stop-Tool "No folder at $d." }
  return $full
}

function Test-Taken([string]$Path) {
  if ([IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path)) { return $true }
  return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function New-ReportFile([string]$Path, [string]$Text, [bool]$Bom) {
  $enc = New-Object System.Text.UTF8Encoding($Bom)
  $bytes = [byte[]]($enc.GetPreamble() + $enc.GetBytes($Text))
  $fs = New-Object IO.FileStream -ArgumentList $Path, ([IO.FileMode]::CreateNew), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
  try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
}

function Save-Report([string]$Dir, [string]$Stamp, [string]$Csv, [string]$Html) {
  for ($n = 1; $n -le 100; $n++) {
    $base = [IO.Path]::Combine($Dir, 'blindspot-intune-' + $Stamp + $(if ($n -gt 1) { '-' + $n } else { '' }))
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
  throw "Stopped: 100 reports from this minute are already in $Dir, so this one was not saved."
}

function Invoke-Report {
  $dir = Get-OutDir
  Connect-Graph @('DeviceManagementScripts.Read.All', 'DeviceManagementManagedDevices.Read.All', 'GroupMember.ReadBasic.All', 'Device.Read.All')
  $found = Get-Ours
  if ($found.Mine.Count -eq 0) { Stop-Tool 'No Remediation made by this tool was found. Run -Deploy first.' }
  if ($found.Mine.Count -gt 1) { Stop-Several $found.Mine }
  $id = [string](Get-Prop $found.Mine[0] 'id')
  $states = @(Get-GraphAll ($Beta + '/' + [Uri]::EscapeDataString($id) + '/deviceRunStates?$expand=managedDevice'))
  $now = [DateTime]::UtcNow
  $rows = @()
  foreach ($st in $states) { $rows += New-Object PSObject -Property (Get-PcRow $st $now) }
  $silent = Get-SilentPcs $id $states
  $rows += $silent.Rows
  $notes = @($silent.Notes | ForEach-Object { Get-Plain $_ } | Select-Object -Unique)
  $unassigned = [bool]$silent.Unassigned
  $noAssignment = 'The Remediation is assigned to no group, so no PC runs the check. Assign it to a group with -Deploy -Group <name>.'
  $order = @{ act = 0; not_checked = 1; failed = 2; stale = 3; no_result = 4; review = 5; clear = 6 }
  $rows = @($rows | Sort-Object @{ Expression = { $order[$_.Status] } }, @{ Expression = { $_.PC } })

  $stamp = $now.ToString('yyyyMMdd-HHmm', [Globalization.CultureInfo]::InvariantCulture)

  $count = @{}
  foreach ($k in $StatusText.Keys) { $count[$k] = @($rows | Where-Object { $_.Status -eq $k }).Count }
  $kindCount = [ordered]@{}
  # PSBase: a dictionary with a 'keys' entry answers .Keys with that entry.
  foreach ($k in $Kinds.PSBase.Keys) {
    $c = @($rows | Where-Object { @($_.Kinds) -ccontains $k }).Count
    if ($c -gt 0) { $kindCount[$k] = $c }
  }
  $notChecked = $count.not_checked + $count.stale + $count.no_result

  $csv = New-Object System.Text.StringBuilder
  [void]$csv.AppendLine((@('pc', 'user', 'status', 'why', 'checked_at', 'details', 'intune_last_report', 'output') | ForEach-Object { ConvertTo-CsvCell $_ }) -join ',')
  foreach ($r in $rows) {
    $cells = @($r.PC, $r.User, $r.Status, $r.Why, $r.CheckedAt, $r.Details, $r.LastReport, $r.Output)
    [void]$csv.AppendLine((@($cells | ForEach-Object { ConvertTo-CsvCell ([string]$_) })) -join ',')
  }

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
.muted { color: var(--muted); }
.tiles { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
.tile { border: 1px solid var(--line); border-radius: 8px; padding: 8px 12px; min-width: 110px; }
.tile b { display: block; font-size: 20px; }
.wrap { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; vertical-align: top; padding: 6px 8px; border-bottom: 1px solid var(--line); }
th { font-weight: 600; color: var(--muted); }
td.raw { font-family: ui-monospace, Consolas, monospace; font-size: 12px; word-break: break-all; }
.s-act { color: var(--act); font-weight: 600; } .s-not_checked, .s-failed, .s-stale, .s-no_result, .s-review { color: var(--warn); font-weight: 600; } .s-clear { color: var(--ok); }
</style></head><body><main>
'@)
  [void]$h.Append('<h1>Blindspot fleet report</h1>')
  [void]$h.Append('<p class="muted">From Microsoft Intune, read ' + (ConvertTo-HtmlText ($now.ToString('yyyy-MM-dd HH:mm') + ' UTC')) + '. A result older than ' + $StaleDays + ' days counts as stale. Each result covers the person signed in when it ran.</p>')
  if ($unassigned) { [void]$h.Append('<p><b>' + (ConvertTo-HtmlText $noAssignment) + '</b></p>') }
  if ($rows.Count -gt 0 -or -not $unassigned) {
    [void]$h.Append('<div class="tiles">')
    [void]$h.Append('<div class="tile"><b>' + $rows.Count + '</b>PCs</div>')
    foreach ($k in @('act', 'not_checked', 'failed', 'stale', 'no_result', 'review', 'clear')) {
      [void]$h.Append('<div class="tile"><b>' + $count[$k] + '</b>' + (ConvertTo-HtmlText $StatusText[$k]) + '</div>')
    }
    [void]$h.Append('</div>')
  }
  if ($notChecked -gt 0) {
    [void]$h.Append('<p>' + $notChecked + ' PC' + $(if ($notChecked -eq 1) { ' was' } else { 's were' }) + ' not checked: no result, a stale result, or a result that does not fit. None of them counts as clear.</p>')
  }
  if ($notes.Count -gt 0) {
    [void]$h.Append('<h2>Could not list every PC</h2><ul>')
    foreach ($n in $notes) { [void]$h.Append('<li>' + (ConvertTo-HtmlText $n) + '</li>') }
    [void]$h.Append('</ul>')
  }
  [void]$h.Append('<h2>What was found</h2>')
  if ($kindCount.Count -eq 0) { [void]$h.Append('<p class="muted">No finding in the results that were read.</p>') }
  else {
    [void]$h.Append('<div class="wrap"><table><tr><th>Finding</th><th>PCs</th></tr>')
    foreach ($k in $kindCount.PSBase.Keys) { [void]$h.Append('<tr><td>' + (ConvertTo-HtmlText $Kinds[$k]) + '</td><td>' + $kindCount[$k] + '</td></tr>') }
    [void]$h.Append('</table></div>')
  }
  $sections = @(
    @{ Title = 'Deal with these first'; Keys = @('act', 'not_checked', 'failed', 'stale') },
    @{ Title = 'No result'; Keys = @('no_result') },
    @{ Title = 'To review'; Keys = @('review') },
    @{ Title = 'Nothing found'; Keys = @('clear') }
  )
  foreach ($sec in $sections) {
    $list = @($rows | Where-Object { $sec.Keys -contains $_.Status })
    [void]$h.Append('<h2>' + (ConvertTo-HtmlText $sec.Title) + ' (' + $list.Count + ')</h2>')
    if ($list.Count -eq 0) { [void]$h.Append('<p class="muted">None.</p>'); continue }
    [void]$h.Append('<div class="wrap"><table><tr><th>PC</th><th>Person</th><th>Status</th><th>Why</th><th>Checked</th><th>Details</th></tr>')
    foreach ($r in $list) {
      $detail = '<td>' + (ConvertTo-HtmlText $r.Details) + '</td>'
      if ($r.Status -eq 'not_checked' -and -not $r.Details) {
        $o = $r.Output; if ($o.Length -gt 200) { $o = $o.Substring(0, 200) + '...' }
        $detail = '<td class="raw">' + (ConvertTo-HtmlText $o) + '</td>'
      }
      [void]$h.Append('<tr><td>' + (ConvertTo-HtmlText $r.PC) + '</td><td>' + (ConvertTo-HtmlText $r.User) + '</td><td class="s-' + $r.Status + '">' +
        (ConvertTo-HtmlText $StatusText[$r.Status]) + '</td><td>' + (ConvertTo-HtmlText $r.Why) + '</td><td>' + (ConvertTo-HtmlText $r.CheckedAt) + '</td>' + $detail + '</tr>')
    }
    [void]$h.Append('</table></div>')
  }
  [void]$h.Append('<p class="muted">The full result of each PC stays on that PC. To see which files, the person runs Blindspot on their own account.</p>')
  [void]$h.Append('</main></body></html>')
  $base = Save-Report $dir $stamp $csv.ToString() $h.ToString()

  if ($unassigned) { Write-Host $noAssignment }
  if ($rows.Count -gt 0 -or -not $unassigned) {
    Write-Host ("$($rows.Count) PCs: $($count.act) to act on, $notChecked not checked, $($count.failed) failed, $($count.review) to review, $($count.clear) with nothing found.")
  }
  foreach ($n in $notes) { Write-Host ('Note: ' + $n) }
  Write-Host ('Saved: ' + $base + '.html')
  Write-Host ('Saved: ' + $base + '.csv')
}

try {
  if ($Deploy) { Invoke-Deploy }
  elseif ($Report) { Invoke-Report }
  else { Invoke-Remove }
} catch {
  $msg = $_.Exception.Message
  if (-not $msg.StartsWith('Stopped:')) { $msg = 'Stopped: ' + $msg }
  Stop-Tool $msg
}
exit 0
