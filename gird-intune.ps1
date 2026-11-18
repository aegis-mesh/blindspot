<#
Blindspot for Microsoft Intune, optional: sets up the daily fleet check as an Intune Remediation and
exports every PC's latest result for gird-report.ps1. https://gird.ai/blindspot

Run it on your own PC, signed in as an Intune admin. It signs in to Microsoft Graph with
Microsoft's own PowerShell module and sends nothing anywhere else. Without it, export the results
from the Intune admin center by hand and give that file to gird-report.ps1.

  gird-intune.ps1 -Deploy -Group <name>   adds the check as an Intune Remediation for that group
                                          only: runs once a day as the signed-in person, 64-bit, no
                                          fix script. Run again with a newer release to update it.
  gird-intune.ps1 -Export <file.csv>      writes each PC's latest result to a new CSV file, with a
                                          row for each Windows PC in the assigned group that has no
                                          result yet. Then run: gird-report.ps1 <file.csv>
  gird-intune.ps1 -Remove                 deletes the Remediation this tool made, after showing it

  -FleetScript <path>   blindspot-fleet.ps1 to deploy (default: next to this file)
  -WhatIf               with -Deploy or -Remove, shows what would change and changes nothing
  -Force                with -Remove, deletes without asking again

Needs the Microsoft.Graph.Authentication module. Runs on Windows PowerShell 5.1 and
PowerShell 7. This file is plain ASCII on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Deploy, [switch]$Remove, [switch]$Help, [switch]$Force,
  [string]$Export, [string]$Group, [string]$FleetScript
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# >>> shared: copied from gird-report.ps1 by tools/gen.sh. Edit it there, then run it.
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

$GraphRoot = 'https://graph.microsoft.com/'
$Beta = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
$Name = 'Blindspot fleet check'
$Publisher = 'Blindspot'
$MaxScriptBytes = 200 * 1024
$MarkerRx = '\(blindspot-intune-id: ([0-9a-f]{32})\)$'

function Show-Usage {
  Write-Host 'Usage:'
  Write-Host '  gird-intune.ps1 -Deploy -Group <name> [-FleetScript <path>] [-WhatIf]'
  Write-Host '  gird-intune.ps1 -Export <file.csv>'
  Write-Host '  gird-intune.ps1 -Remove [-WhatIf] [-Force]'
}

$modes = @($Deploy.IsPresent, [bool]$Export, $Remove.IsPresent | Where-Object { $_ }).Count
if ($Help) { Show-Usage; exit 0 }
if ($modes -ne 1) { Show-Usage; Stop-Tool 'Give one of -Deploy, -Export or -Remove.' 2 }
if ($Group -and -not $Deploy) { Stop-Tool '-Group works with -Deploy only.' 2 }
if ($FleetScript -and -not $Deploy) { Stop-Tool '-FleetScript works with -Deploy only.' 2 }
if ($Force -and -not $Remove) { Stop-Tool '-Force works with -Remove only.' 2 }
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
      [void]$notes.Add("Could not list the PCs with no result for an assignment to '$type': Microsoft Graph does not say which PCs it reaches. PCs with no result there are not in the export, which does not mean they are clear.")
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
        [void]$notes.Add("Could not list the PCs with no result for group $gid, because its members could not be read: " + $_.Exception.Message + ' PCs with no result there are not in the export, which does not mean they are clear.')
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
      [void]$notes.Add("Could not list the PCs with no result for the people in group $gid ($people): Microsoft Graph does not say which of a person's PCs Intune runs the check on. PCs with no result there are not in the export, which does not mean they are clear.")
    }
    if ($hidden -gt 0 -and $excluding) {
      [void]$notes.Add("Could not read $hidden PC" + $(if ($hidden -eq 1) { '' } else { 's' }) + " in exclusion group $gid. Allow Device.Read.All for gird-intune.ps1 and run gird-intune.ps1 -Export again. Until then a PC listed as no result yet may in fact be excluded from the check.")
    }
    elseif ($hidden -gt 0) {
      [void]$notes.Add("Could not read $hidden PC" + $(if ($hidden -eq 1) { '' } else { 's' }) + " in group $gid. Allow Device.Read.All for gird-intune.ps1 and run gird-intune.ps1 -Export again. PCs with no result there are not in the export, which does not mean they are clear.")
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
    $rows += ,@($pc, $mid, [string](Get-Prop $d 'userPrincipalName'), 'Windows', '', $NoResultRow, '', '')
  }
  return @{ Rows = $rows; Notes = $notes.ToArray(); Unassigned = $false }
}

function Get-ExportPath {
  $dir = [IO.Path]::GetDirectoryName($Export)
  if (-not $dir) { $dir = '.' }
  $leaf = [IO.Path]::GetFileName($Export)
  $rp = @(Resolve-Path -LiteralPath $dir -ErrorAction SilentlyContinue)
  if (-not $leaf -or $rp.Count -ne 1 -or $rp[0].Provider.Name -cne 'FileSystem' -or -not [IO.Directory]::Exists($rp[0].ProviderPath)) {
    Stop-Tool "$Export is not a file name in a folder on disk. Give one with -Export, such as -Export intune.csv."
  }
  $full = [IO.Path]::Combine($rp[0].ProviderPath, $leaf)
  if (Test-Taken $full) { Stop-Tool "$Export is already there. This tool only makes a new file: give another name." }
  return $full
}

function Invoke-Export {
  $path = Get-ExportPath
  Connect-Graph @('DeviceManagementScripts.Read.All', 'DeviceManagementManagedDevices.Read.All', 'GroupMember.ReadBasic.All', 'Device.Read.All')
  $found = Get-Ours
  if ($found.Mine.Count -eq 0) { Stop-Tool 'No Remediation made by this tool was found. Run -Deploy first.' }
  if ($found.Mine.Count -gt 1) { Stop-Several $found.Mine }
  $id = [string](Get-Prop $found.Mine[0] 'id')
  $states = @(Get-GraphAll ($Beta + '/' + [Uri]::EscapeDataString($id) + '/deviceRunStates?$expand=managedDevice'))
  $lines = New-Object System.Collections.ArrayList
  foreach ($st in $states) {
    $dev = Get-Prop $st 'managedDevice'
    $pc = [string](Get-Prop $dev 'deviceName')
    if (-not $pc) { $pc = '(name not given) ' + [string](Get-Prop $st 'id') }
    $raw = Get-Prop $st 'preRemediationDetectionScriptOutput'
    if ($null -eq $raw) { $raw = '' }
    [void]$lines.Add(@($pc, [string](Get-Prop $dev 'id'), [string](Get-Prop $dev 'userPrincipalName'), 'Windows', [string]$raw,
      [string](Get-Prop $st 'detectionState'), [string](Get-Prop $st 'lastStateUpdateDateTime'), ''))
  }
  $silent = Get-SilentPcs $id $states
  foreach ($r in $silent.Rows) { [void]$lines.Add($r) }
  $notes = @($silent.Notes | ForEach-Object { Get-Plain $_ } | Select-Object -Unique)
  if ($silent.Unassigned) { $notes += 'The Remediation is assigned to no group, so no PC runs the check. Assign it to a group with -Deploy -Group <name>.' }
  foreach ($n in $notes) { [void]$lines.Add(@('', '', '', '', '', '', '', $n)) }
  $csv = New-Object System.Text.StringBuilder
  [void]$csv.AppendLine((@($ExportColumns | ForEach-Object { ConvertTo-CsvCell $_ })) -join ',')
  foreach ($l in $lines) { [void]$csv.AppendLine((@($l | ForEach-Object { ConvertTo-CsvCell ([string]$_) })) -join ',') }
  New-ReportFile $path $csv.ToString() $true
  foreach ($n in $notes) { Write-Host ('Note: ' + $n) }
  $pcs = $states.Count + @($silent.Rows).Count
  Write-Host ("Exported $pcs PC" + $(if ($pcs -eq 1) { '' } else { 's' }) + ", $(@($silent.Rows).Count) of them with no result row yet, to $path.")
  Write-Host ('Next: gird-report.ps1 "' + $path + '"')
}

try {
  if ($Deploy) { Invoke-Deploy }
  elseif ($Export) { Invoke-Export }
  else { Invoke-Remove }
} catch {
  $msg = $_.Exception.Message
  if (-not $msg.StartsWith('Stopped:')) { $msg = 'Stopped: ' + $msg }
  Stop-Tool $msg
}
exit 0
