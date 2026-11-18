<#
Prints the SHA-256 of a PowerShell script with its comments removed, and with a second path writes
that copy there. tools/gen.sh packs gird-check.ps1 into blindspot-fleet.ps1 this way, so anyone can
check the $PackedSha a release's blindspot-fleet.ps1 carries against the published gird-check.ps1:

  pwsh -NoProfile -File tools/strip-comments.ps1 gird-check.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\strip-comments.ps1 gird-check.ps1

PowerShell's own tokenizer finds the comments, so a # in a string, a here-string or a regex is never
touched. Kept: the comments before the first line of code (the header, which -Help prints and whose
version line gird-fleet.ps1 reads) and #requires lines. Comment-based help anywhere else, or a
signature block, stops it with exit code 1. A comment at the end of a line goes with the spaces
before it (one stays after a backtick), one before code on the same line becomes a space, and a line
left empty is dropped, unless the line before it ends with a backtick that continues it. The copy is
then parsed again: it must have no errors and the same tokens apart from comments and blank lines,
the same syntax tree, the same #requires and the same help for the script, or nothing is written and
the exit code is 1.
#>
param([Parameter(Mandatory = $true)][string]$In, [string]$Out = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
function Fail([string]$m) { [Console]::Error.WriteLine("strip-comments: $m"); exit 1 }

function Parse-Text([string]$text, [string]$what) {
  $tk = $null; $er = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tk, [ref]$er)
  if ($er -and $er.Count) { Fail "$what does not parse: $($er[0].Message) (line $($er[0].Extent.StartLineNumber))" }
  return , @($ast, $tk)
}
function Is-Kept([Management.Automation.Language.Token]$t, [bool]$head) {
  return ($head -or $t.Text -match '^#requires\b')
}
# The tokens a run sees: comments left out, and each run of line ends counted once.
function Code-Tokens($tokens) {
  $l = New-Object System.Collections.Generic.List[string]
  $nl = $false
  foreach ($t in $tokens) {
    if ($t.Kind -eq 'Comment') { continue }
    if ($t.Kind -eq 'NewLine') { if ($nl) { continue }; $nl = $true } else { $nl = $false }
    $l.Add("$($t.Kind)|$($t.TokenFlags)|$($t.Text)")
  }
  return , $l
}
function Ast-Shape($ast) {
  return (($ast.FindAll({ $true }, $true) | ForEach-Object { $_.GetType().Name }) -join ',')
}
function Help-Of($ast) {
  $c = $ast.GetHelpContent()
  if ($c) { return $c.GetCommentBlock() }
  return ''
}
function Requires-Of($ast) {
  $r = $ast.ScriptRequirements
  if (-not $r) { return '' }
  return (($r.PSObject.Properties | ForEach-Object { "$($_.Name)=$(@($_.Value) -join ';')" }) -join '|')
}

$src = (Resolve-Path -LiteralPath $In).ProviderPath
$bytes = [IO.File]::ReadAllBytes($src)
$text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
if ($text -match '[^\x00-\x7F]') { Fail "$In is not plain ASCII" }
$p = Parse-Text $text $In
$ast = $p[0]; $tokens = $p[1]

$sb = New-Object Text.StringBuilder
$line = New-Object Text.StringBuilder
$code = $false; $cont = $false; $head = $true; $pos = 0
$kept = New-Object System.Collections.Generic.List[string]
foreach ($t in $tokens) {
  $s = [Math]::Min($t.Extent.StartOffset, $text.Length); $e = [Math]::Min($t.Extent.EndOffset, $text.Length)
  $gap = $text.Substring($pos, $s - $pos)
  if ($gap -notmatch '^[ \t]*$') { Fail "text outside any token at offset $pos" }
  [void]$line.Append($gap); $pos = $e
  $raw = $text.Substring($s, $e - $s)
  switch ($t.Kind) {
    'Comment' {
      if ($raw -match '^# SIG # Begin signature block') { Fail "$In is signed: removing its comments would break the signature" }
      if (-not (Is-Kept $t $head) -and $raw -match '(?m)^\s*(<#|#)?\s*\.(SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|INPUTS|OUTPUTS|NOTES|LINK|COMPONENT|ROLE|FUNCTIONALITY|FORWARDHELPTARGETNAME|FORWARDHELPCATEGORY|REMOTEHELPRUNSPACE|EXTERNALHELP)\b') {
        Fail "line $($t.Extent.StartLineNumber) is comment-based help, which this would remove"
      }
      if (Is-Kept $t $head) { [void]$line.Append($raw); $kept.Add($raw); $code = $true; break }
      $before = ' '; if ($line.Length) { $before = [string]$line[$line.Length - 1] }
      $after = ' '; if ($e -lt $text.Length) { $after = [string]$text[$e] }
      if ($after -eq "`r" -or $after -eq "`n" -or $e -ge $text.Length) {
        $n = $line.Length; while ($n -gt 0 -and ($line[$n - 1] -eq ' ' -or $line[$n - 1] -eq "`t")) { $n-- }
        if ($n -lt $line.Length -and $n -gt 0 -and $line[$n - 1] -eq '`') { $n++ }
        [void]$line.Remove($n, $line.Length - $n)
      } elseif ($before -notmatch '\s' -and $after -notmatch '\s') { [void]$line.Append(' ') }
    }
    'NewLine' {
      if ($code) { [void]$sb.Append($line.ToString()).Append($raw) } elseif ($cont) { [void]$sb.Append($raw) }
      [void]$line.Clear(); $code = $false; $cont = $false
    }
    'LineContinuation' {
      $head = $false
      [void]$sb.Append($line.ToString()).Append($raw)
      [void]$line.Clear(); $code = $false; $cont = $true
    }
    'EndOfInput' { if ($code) { [void]$sb.Append($line.ToString()) } }
    default { $head = $false; [void]$line.Append($raw); $code = $true; $cont = $false }
  }
}
$outText = $sb.ToString()

$q = Parse-Text $outText 'the copy without comments'
$a2 = $q[0]; $t2 = $q[1]
$c1 = Code-Tokens $tokens; $c2 = Code-Tokens $t2
if ($c1.Count -ne $c2.Count) { Fail "the copy has $($c2.Count) tokens, the script $($c1.Count)" }
for ($i = 0; $i -lt $c1.Count; $i++) { if ($c1[$i] -cne $c2[$i]) { Fail "token $i differs: '$($c1[$i])' became '$($c2[$i])'" } }
$k2 = @($t2 | Where-Object { $_.Kind -eq 'Comment' } | ForEach-Object { $_.Text })
if (($k2 -join "`n") -cne ($kept -join "`n")) { Fail 'the comments kept differ from the copy''s' }
if ((Ast-Shape $ast) -cne (Ast-Shape $a2)) { Fail 'the syntax tree differs' }
if ((Help-Of $ast) -cne (Help-Of $a2)) { Fail 'the comment-based help differs' }
if ((Requires-Of $ast) -cne (Requires-Of $a2)) { Fail 'the #requires differ' }

$ob = [Text.Encoding]::ASCII.GetBytes($outText)
if ($Out) { [IO.File]::WriteAllBytes($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out), $ob) }
$sha = [Security.Cryptography.SHA256]::Create()
try { [Console]::Out.WriteLine((-join ($sha.ComputeHash($ob) | ForEach-Object { $_.ToString('x2') }))) } finally { $sha.Dispose() }
