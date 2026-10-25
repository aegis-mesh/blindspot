<#
Blindspot, the GIRD AI key check, for Windows PowerShell, version 1.2.0 (25 October 2026)
https://gird.ai/blindspot

Shows the AI coding agents and MCP servers on this computer, AI and cloud keys
stored in plain text, keys saved in Claude Code allow lists, and signs of this
week's LiteLLM, OpenCode, Railway and Zeabur incidents.

It never uses admin rights, starts an agent, an MCP server or Python, or prints a
key. It reads files and prints paths and counts. It asks gird.ai for public totals
when it starts. When it finishes it shares counts and a hashed device ID, never
paths or keys, and gets back how you compare. -Offline stops all of that.
Key types and session locations come from data/keys.tsv and data/sessions.tsv; gird-check.sh is
the source of truth for every other check.

  powershell -ExecutionPolicy Bypass -File gird-check.ps1            a short summary
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -Full      every detail
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -All       also scans Desktop, Documents and Downloads
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -Offline   shares nothing (DO_NOT_TRACK=1 works too)
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -Save      saves the full report as a text file
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -AllSessions  waits until every agent session is checked
  -NoColor (or NO_COLOR=1)                                            plain text, no colors

Runs on Windows PowerShell 5.1 and PowerShell 7. This file is plain ASCII on purpose:
Windows PowerShell 5.1 reads a script without a byte order mark as the ANSI code page,
so every non-ASCII character below is built from its code point.
#>
param(
  [switch]$All, [switch]$Full, [switch]$Offline, [switch]$Save, [switch]$NoColor, [switch]$Help, [switch]$AllSessions,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$OptAllSess = [bool]$AllSessions; $OptAll = [bool]$All; $OptFull = [bool]$Full; $OptOffline = [bool]$Offline; $OptSave = [bool]$Save; $OptNoColor = [bool]$NoColor
foreach ($arg in $Rest) {
  switch ($arg) {
    '--all' { $OptAll = $true } '--full' { $OptFull = $true } '--save' { $OptSave = $true }
    '--offline' { $OptOffline = $true } '--no-color' { $OptNoColor = $true } '--no-game' { } '--all-sessions' { $OptAllSess = $true }
    { $_ -eq '--help' -or $_ -eq '-h' } { $Help = $true }
    default { [Console]::Out.WriteLine("Unknown option: $arg (try -Help)"); exit 2 }
  }
}
if ($Help) {
  $lines = (Get-Content -LiteralPath $PSCommandPath -TotalCount 22) | Select-Object -Skip 1
  foreach ($l in $lines) { if ($l -notmatch '^#>') { [Console]::Out.WriteLine($l) } }
  exit 0
}
if ($env:DO_NOT_TRACK -eq '1') { $OptOffline = $true }

$ScriptVersion = '1'
$Web = 'https://gird.ai'; if ($env:GIRD_CHECK_WEB) { $Web = $env:GIRD_CHECK_WEB }   # the overrides here are for testing
$Api = "$Web/api/check"; if ($env:GIRD_CHECK_API) { $Api = $env:GIRD_CHECK_API }

$OnWindows = $env:OS -eq 'Windows_NT'
$IsCore = $PSVersionTable.PSEdition -eq 'Core'
$Sep = [IO.Path]::DirectorySeparatorChar
$PathCmp = [StringComparison]::Ordinal; if ($OnWindows) { $PathCmp = [StringComparison]::OrdinalIgnoreCase }

$HomeDir = $env:USERPROFILE; if (-not $HomeDir) { $HomeDir = $env:HOME }
if (-not $HomeDir -or -not [IO.Directory]::Exists($HomeDir)) { [Console]::Out.WriteLine('USERPROFILE is not set.'); exit 1 }
if ($HomeDir.Length -gt 3) { $HomeDir = $HomeDir.TrimEnd('\', '/') }
function J([string]$base, [string]$rel) { $base + $Sep + ($rel -replace '[\\/]', $Sep) }
$AppData = $env:APPDATA; if (-not $AppData) { $AppData = J $HomeDir 'AppData/Roaming' }
$LocalAppData = $env:LOCALAPPDATA; if (-not $LocalAppData) { $LocalAppData = J $HomeDir 'AppData/Local' }
# Goose keeps its data and state in %APPDATA%\Block\goose\data, or under GOOSE_PATH_ROOT when that
# is an absolute path (crates/goose/src/config/paths.rs).
$GooseData = J $AppData 'Block/goose/data'; $GooseState = $GooseData
$GoosePathRoot = [Environment]::GetEnvironmentVariable('GOOSE_PATH_ROOT')
if ($GoosePathRoot -and ($GoosePathRoot -match '^[A-Za-z]:[\\/]' -or (-not $OnWindows -and $GoosePathRoot.StartsWith('/')))) {
  $GooseData = J $GoosePathRoot.TrimEnd('\', '/') 'data'; $GooseState = J $GoosePathRoot.TrimEnd('\', '/') 'state'
}
$TempDirs = New-Object System.Collections.Generic.List[string]
foreach ($t in @($env:TEMP, $env:TMP)) { if ($t) { $t = $t.TrimEnd('\', '/'); if (-not $TempDirs.Contains($t)) { $TempDirs.Add($t) } } }
if ($TempDirs.Count -eq 0) { $TempDirs.Add([IO.Path]::GetTempPath().TrimEnd('\', '/')) }

# ---------------------------------------------------------------------------
# Look and feel. Colors only on a console that understands them, never with
# NO_COLOR or when redirected.
# ---------------------------------------------------------------------------
$IsConsole = $false; $InConsole = $false
try { $IsConsole = -not [Console]::IsOutputRedirected; $InConsole = -not [Console]::IsInputRedirected } catch { }
$Compact = $IsConsole
if ($env:GIRD_CHECK_COMPACT -eq '1') { $Compact = $true }
if ($OptFull) { $Compact = $false }
$Vt = $true
if ($OnWindows) { $Vt = $false; try { $Vt = [bool]$Host.UI.SupportsVirtualTerminal } catch { } }
$Esc = [string][char]27
if ($IsConsole -and $Vt -and -not $env:NO_COLOR -and -not $OptNoColor -and $env:TERM -ne 'dumb') {
  $cRst = "$Esc[0m"; $cBold = "$Esc[1m"; $cDim = "$Esc[2m"; $cRed = "$Esc[31m"; $cGrn = "$Esc[32m"; $cYel = "$Esc[33m"
  $cTeal = "$Esc[38;5;44m"; $cGold = "$Esc[38;5;179m"
} else {
  $cRst = ''; $cBold = ''; $cDim = ''; $cRed = ''; $cGrn = ''; $cYel = ''; $cTeal = ''; $cGold = ''
}
# The legacy console's fonts lack these symbols, so it gets ASCII ones.
$Fancy = -not ($OnWindows -and $IsConsole -and -not $env:WT_SESSION -and -not $env:TERM_PROGRAM)
if ($Fancy) {
  $gOk = [string][char]0x2713; $gX = [string][char]0x2717; $gDot = [string][char]0x25CF; $gRing = [string][char]0x25CB
  $gBul = [string][char]0x2022; $gMid = [string][char]0x00B7; $gBar = [string][char]0x258C; $gStar = [string][char]0x2605
  $gRuleCh = [char]0x2500
} else {
  $gOk = '+'; $gX = 'x'; $gDot = '*'; $gRing = 'o'; $gBul = '-'; $gMid = '.'; $gBar = '|'; $gStar = '*'; $gRuleCh = [char]'-'
}
$OldOutEnc = $null
if ($OnWindows) { try { $OldOutEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { $OldOutEnc = $null } }
$Width = 80
if ($IsConsole) {
  try { $Width = [Console]::WindowWidth } catch { $Width = 80 }
  if ($Width -le 0) { $Width = 80 }
  if ($Width -gt 96) { $Width = 96 }
  if ($Width -lt 60) { $Width = 60 }
}
$Rule = New-Object string($gRuleCh, ($Width - 4))
$NL = [Environment]::NewLine

function Out-Text([string]$s) { [Console]::Out.Write($s.Replace("`n", $NL)) }

# Everything shown is also kept in the report, so it can be saved at the end. While
# capturing, lines go to Cap instead, so the report can be built in parts and shown
# as a summary or in full.
$Report = New-Object System.Text.StringBuilder
$Capture = $false
$Cap = New-Object System.Text.StringBuilder
function Emit([string]$s) {
  if ($script:Capture) { [void]$script:Cap.Append($s).Append("`n"); return }
  Out-Text ($s + "`n"); [void]$script:Report.Append($s).Append("`n")
}
function Blank { Emit '' }
function Take-Cap { $s = $script:Cap.ToString(); [void]$script:Cap.Clear(); $s }
# Paths are shown with control characters replaced, so a hostile file name can't
# send escape sequences to the console.
function Short([string]$p) {
  $s = [regex]::Replace($p, '[\x00-\x1f\x7f-\x9f]', '?')
  if ($s.StartsWith($HomeDir + $Sep, $PathCmp)) { return '~' + $Sep + $s.Substring($HomeDir.Length + 1) }
  $s
}
function Plural($n, [string]$one, [string]$many) { if ("$n" -eq '1') { "$n $one" } else { "$n $many" } }
function Commas($n) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:N0}', [long]$n) }
function First-Names($names, [int]$n) {
  $a = @($names); $o = ($a | Select-Object -First $n) -join ', '
  if ($a.Count -gt $n) { $o += " +$($a.Count - $n)" }
  $o
}
# A whole number from a small JSON reply, or nothing. Only digits ever come out,
# so a reply can't put anything else on the screen.
function JNum([string]$name, [string]$text) {
  $m = [regex]::Match($text, '"' + $name + '":([0-9]{1,12})([,}]|$)')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}
# Breaks text the way fold -s does in gird-check.sh, so both print the same lines.
function Fold([string]$text, [int]$w) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $text.Split("`n")) {
    $buf = New-Object System.Text.StringBuilder
    foreach ($ch in $line.ToCharArray()) {
      while ($buf.Length + 1 -gt $w) {
        $s = $buf.ToString(); $i = $s.LastIndexOfAny([char[]]@(' ', "`t"))
        if ($i -ge 0) { $out.Add($s.Substring(0, $i + 1)); [void]$buf.Remove(0, $i + 1) }
        elseif ($buf.Length -eq 0) { break }
        else { $out.Add($s); [void]$buf.Clear() }
      }
      [void]$buf.Append($ch)
    }
    $out.Add($buf.ToString())
  }
  foreach ($l in $out) { $l.TrimEnd() }
}
function Wrap([string]$text, [int]$ind, [string]$first, [string]$rest, [string]$color = '') {
  $w = $Width - $ind - 3; if ($w -lt 20) { $w = 20 }
  $n = 0; $end = ''; if ($color) { $end = $cRst }
  foreach ($l in (Fold $text $w)) {
    if ($n -eq 0) { Emit "$first$color$l$end" } else { Emit "$rest$color$l$end" }
    $n = 1
  }
}
function Section([string]$num, [string]$title, [string]$right) {
  Blank
  $pad = $Width - 8 - $title.Length - $right.Length; if ($pad -lt 2) { $pad = 2 }
  Emit "  $cTeal$cBold$num$cRst  $cBold$title$cRst$(' ' * $pad)$cDim$right$cRst"
  Emit "  $cDim$Rule$cRst"
}
function Heading([string]$title, [string]$right) {
  Blank
  $pad = $Width - 4 - $title.Length - $right.Length; if ($pad -lt 2) { $pad = 2 }
  Emit "  $cBold$title$cRst$(' ' * $pad)$cDim$right$cRst"
  Emit "  $cDim$Rule$cRst"
}
# One aligned row; a long name pushes the detail down.
function Pair([string]$glyph, [string]$name, [int]$nw, [string]$detail) {
  if ($name.Length -gt $nw) { Emit "     $glyph  $name"; Emit "$(' ' * ($nw + 10))$detail" }
  else { Emit "     $glyph  $($name.PadRight($nw))  $detail" }
}
# The latest finding, on one line that the next one overwrites. Console only.
function Progress([string]$text) {
  if (-not $IsConsole) { return }
  $mx = $Width - 8; if ($text.Length -gt $mx) { $text = $text.Substring(0, $mx - 3) + '...' }
  if ($Vt) { Out-Text "`r$Esc[K  $cTeal$gMid$cRst  $cDim$text$cRst" } else { Out-Text ("`r  $gMid  " + $text.PadRight($mx)) }
}
function Progress-Clear {
  if (-not $IsConsole) { return }
  if ($Vt) { Out-Text "`r$Esc[K" } else { Out-Text ("`r" + (' ' * ($Width - 1)) + "`r") }
}

# ---------------------------------------------------------------------------
# Talking to gird.ai: a GET for the public totals and a POST for the report. Short
# timeouts, no redirects, https only when the API is https, replies capped in size.
# A failure just means nothing comes back.
# ---------------------------------------------------------------------------
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
function Http([string]$method, [string]$url, [int]$seconds, [string]$body, [int]$max) {
  if (-not ($url.StartsWith('https://') -or ($url.StartsWith('http://') -and -not $Api.StartsWith('https://')))) { return '' }
  try {
    $req = [Net.HttpWebRequest][Net.WebRequest]::Create($url)
    $req.Method = $method; $req.Timeout = $seconds * 1000; $req.ReadWriteTimeout = $seconds * 1000
    $req.AllowAutoRedirect = $false; $req.UserAgent = 'gird-check.ps1'
    if ($body) {
      $bytes = [Text.Encoding]::UTF8.GetBytes($body)
      $req.ContentType = 'application/json'; $req.ContentLength = $bytes.Length
      $rs = $req.GetRequestStream(); $rs.Write($bytes, 0, $bytes.Length); $rs.Close()
    }
    $resp = $req.GetResponse()
    try {
      $code = [int]$resp.StatusCode
      if ($code -lt 200 -or $code -ge 300) { return '' }
      $st = $resp.GetResponseStream(); $buf = New-Object byte[] ($max + 1); $got = 0
      while ($got -le $max) { $r = $st.Read($buf, $got, $buf.Length - $got); if ($r -le 0) { break }; $got += $r }
      if ($got -gt $max) { return '' }
      return [Text.Encoding]::UTF8.GetString($buf, 0, $got)
    } finally { $resp.Close() }
  } catch { return '' }
}

# ---------------------------------------------------------------------------
# Key formats, the same as gird-check.sh. A key is matched and then thrown away:
# it is never printed, kept or sent anywhere.
# ---------------------------------------------------------------------------
# >>> keys: generated from data/keys.tsv by tools/gen.sh. Edit that file, then run it.
$ALL_KEYS = 'sk-ant-[A-Za-z0-9_-]{90,}|sk-or-v1-[a-f0-9]{64}|sk-proj-[A-Za-z0-9_-]{120,}|sk-proj-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}([^A-Za-z0-9_-]|$)|sk-svcacct-[A-Za-z0-9_-]{60,}|sk-admin-[A-Za-z0-9_-]{120,}|(^|[^A-Za-z0-9-])sk-[A-Za-z0-9]{48}([^A-Za-z0-9]|$)|AIza[0-9A-Za-z_-]{35}|(^|[^A-Za-z0-9])AQ\.[A-Za-z0-9_-]{40,}|gsk_[A-Za-z0-9]{52}|xai-[A-Za-z0-9]{64,}|(^|[^A-Za-z0-9_])hf_[A-Za-z0-9]{34,40}([^A-Za-z0-9_]|$)|pplx-[A-Za-z0-9]{40,52}|r8_[A-Za-z0-9]{37}|(^|[^A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}([^A-Z0-9]|$)|ABSKQmVkcm9ja0FQSUtleS[A-Za-z0-9+/]{60,}|bedrock-api-key-YmVkcm9jay5hbWF6b25hd3MuY29t|gh[pour]_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9_.-]{36,}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}|npm_[A-Za-z0-9]{36}'
$PROVIDER_IDS = 'anthropic openrouter openai google groq xai huggingface perplexity replicate aws github npm'
$KEY_STARTS = 'sk-ant-|sk-or-v1-|sk-|AIza|AQ[.]|gsk_|xai-|hf_|pplx-|r8_|AKIA|ASIA|ABSK|bedrock-api-key|gh[pousr]_|github_pat_|npm_'
$KeyProviderFn = @'
function Key-Provider([string]$s) {
  $s = $s -replace '^[^A-Za-z]*\\[ntr"]', '' -replace '^[^A-Za-z]+', ''
  if ($s -cmatch '^(sk-ant-)') { return 'Anthropic' }
  if ($s -cmatch '^(sk-or-v1-)') { return 'OpenRouter' }
  if ($s -cmatch '^(sk-)') { return 'OpenAI' }
  if ($s -cmatch '^(AIza|AQ[.])') { return 'Google' }
  if ($s -cmatch '^(gsk_)') { return 'Groq' }
  if ($s -cmatch '^(xai-)') { return 'xAI' }
  if ($s -cmatch '^(hf_)') { return 'Hugging Face' }
  if ($s -cmatch '^(pplx-)') { return 'Perplexity' }
  if ($s -cmatch '^(r8_)') { return 'Replicate' }
  if ($s -cmatch '^(AKIA|ASIA|ABSK|bedrock-api-key)') { return 'AWS' }
  if ($s -cmatch '^(gh[pousr]_|github_pat_)') { return 'GitHub' }
  if ($s -cmatch '^(npm_)') { return 'npm' }
  $null
}
function Provider-Id([string]$n) { switch -CaseSensitive ($n) { 'Anthropic' { 'anthropic' } 'OpenRouter' { 'openrouter' } 'OpenAI' { 'openai' } 'Google' { 'google' } 'Groq' { 'groq' } 'xAI' { 'xai' } 'Hugging Face' { 'huggingface' } 'Perplexity' { 'perplexity' } 'Replicate' { 'replicate' } 'AWS' { 'aws' } 'GitHub' { 'github' } 'npm' { 'npm' } default { $null } } }
'@
# <<< keys
# Agent sessions are JSON, where a key often follows an escape such as \n, so a backslash escape
# also counts as the boundary in front of a key.
$TR_KEYS = $ALL_KEYS -replace '\(\^\|\[\^([^\]]*)\]\)', '(^|[^$1]|\\[ntr"])'
# A secret written as a value: KEY=value in a command, or "token": "value" in a config.
# These match what gird-check.sh's patterns match, rewritten so .NET's backtracking
# stays linear: a name is tried once from its first character, (?>...) never gives
# characters back, and the lookahead finds KEY, TOKEN, SECRET or PASSWORD in one
# pass. gird-check.sh's P_ASSIGN wants a capital letter somewhere before the word.
# grep reads a line at a time, so [^\S\n] and [^"\n] keep a match on one line.
$P_NAME = '(?<![A-Z0-9_])(?=[A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD))(?>[A-Z0-9_]*)'
$P_ASSIGN = '(?<![A-Z0-9_])(?=(?>[0-9_]*)[A-Z][A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD))(?>[A-Z0-9_]+)=[^\s"$\\]{12,}'
$P_JSONSECRET = '"(?:(?=[A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD))(?>[A-Z0-9_]*)|apiKey|api_key|accessToken|access_token|authToken|token|secret)"[^\S\n]*:[^\S\n]*"[^"$<{\n][^"\n]{11,}"'
$P_TOMLSECRET = $P_NAME + '[^\S\n]*=[^\S\n]*"[^"$<{\n][^"\n]{11,}"'
$P_PLACEHOLDER = 'your|xxxx|here|example|placeholder|changeme|dummy|<|[$][{]'
# grep reads line by line, so ^ and $ are line ends here too.
# Every pattern has a time limit. A file that hits it is listed as skipped, never
# taken as clean. GIRD_CHECK_REGEX_TIMEOUT_MS is for tests.
$RxOpt = [Text.RegularExpressions.RegexOptions]::Multiline
$RxTimeout = [TimeSpan]::FromSeconds(2)
if ($env:GIRD_CHECK_REGEX_TIMEOUT_MS -match '^[0-9]{1,6}$' -and [int]$env:GIRD_CHECK_REGEX_TIMEOUT_MS -gt 0) { $RxTimeout = [TimeSpan]::FromMilliseconds([int]$env:GIRD_CHECK_REGEX_TIMEOUT_MS) }
$RxKeys = New-Object regex($ALL_KEYS, $RxOpt, $RxTimeout)
$RxInline = New-Object regex("$ALL_KEYS|$P_JSONSECRET|$P_TOMLSECRET", $RxOpt, $RxTimeout)
$RxCommand = New-Object regex("$ALL_KEYS|$P_ASSIGN", $RxOpt, $RxTimeout)
$RxPlaceholder = New-Object regex($P_PLACEHOLDER, [Text.RegularExpressions.RegexOptions]::IgnoreCase, $RxTimeout)
$SlowFiles = New-Object System.Collections.Generic.List[string]
function Mark-Slow([string]$f) {
  if (-not $SlowFiles.Contains($f)) { $SlowFiles.Add($f); Progress "Skipped, took too long to check: $(Short $f)" }
}

$TextCache = @{}
function Read-Text([string]$f) {
  if ($TextCache.ContainsKey($f)) { return $TextCache[$f] }
  $t = $null
  try { if ([IO.File]::Exists($f)) { $t = [IO.File]::ReadAllText($f) } } catch { $t = $null }
  $TextCache[$f] = $t
  $t
}
function Has-Match([string]$f, [regex]$rx) {
  if ($SlowFiles.Contains($f)) { return $false }
  $t = Read-Text $f; if ($null -eq $t) { return $false }
  try { $rx.IsMatch($t) } catch { Mark-Slow $f; $false }
}
# A match that is not a placeholder like your-key-here.
function Has-RealMatch([string]$f, [regex]$rx) {
  if ($SlowFiles.Contains($f)) { return $false }
  $t = Read-Text $f; if ($null -eq $t) { return $false }
  try { foreach ($m in $rx.Matches($t)) { if (-not $RxPlaceholder.IsMatch($m.Value)) { return $true } } } catch { Mark-Slow $f }
  $false
}
# The provider of a matched key (generated above) and whether a key looks made up. Text, so the
# background session check can load the same functions.
$KeyFns = $KeyProviderFn + @'
function Made-Up([string]$k) {
  # No key is longer than 300 characters (GitHub's 93-character tokens are the longest fixed
  # format, OpenAI project keys run to about 170): a longer run of key characters is data.
  if ($k.Length -gt 300) { return $true }
  $k = $k -replace '^[^A-Za-z]*\\[ntr"]', '' -replace '^[^A-Za-z]+', '' -replace '[^A-Za-z0-9_.-]+$', ''
  if ($k -cmatch 'EXAMPLE|xxxx|XXXX|0123456789|1234567890|abcdef|ABCDEF' -or $k -cmatch '(.)\1{7}') { return $true }
  $set = New-Object 'System.Collections.Generic.HashSet[char]'
  foreach ($c in $k.ToCharArray()) { [void]$set.Add($c) }
  $min = 12; if ($k.Length -lt 30) { $min = 8 }
  $set.Count -lt $min
}
function Is-CliOwnKey([string]$f, [string]$k) {
  # Amazon Q CLI keeps temporary AWS credentials for its own telemetry in its database
  # (data.sqlite3, state entry telemetry-cognito-credentials, an ASIA key id), and so does Kiro
  # CLI, the same CLI renamed: such a key id there is the CLI's own, not a key an agent read.
  # Long-term AKIA keys and every other provider in those files still count.
  $k = $k -replace '^[^A-Za-z]*\\[ntr"]', '' -replace '^[^A-Za-z]+', ''
  ($k -cmatch '^ASIA') -and ($f -match '[\\/](amazon-q|kiro-cli)[\\/]data\.sqlite3(-journal|-wal)?$')
}
'@
. ([scriptblock]::Create($KeyFns))
function Providers-In([string]$f) {
  if ($SlowFiles.Contains($f)) { return @() }
  $t = Read-Text $f; if ($null -eq $t) { return @() }
  $seen = New-Object System.Collections.Generic.List[string]
  try { $all = @($RxKeys.Matches($t)) } catch { Mark-Slow $f; return @() }
  foreach ($m in $all) {
    $p = Key-Provider $m.Value
    if ($p -and -not $seen.Contains($p)) { $seen.Add($p) }
  }
  $seen.ToArray()
}

# ---------------------------------------------------------------------------
# Fixed lists for the case-study counts in the report, the same as gird-check.sh.
# Only ids from these lists, counts and yes/no leave the computer: never a path, a
# file name or a name you gave an MCP server. gird.ai keeps the same lists and
# drops anything else, so change all three together.
# ---------------------------------------------------------------------------
$MCP_CLIENT_IDS = 'claude-code claude-desktop cursor windsurf codex gemini-cli vscode cline continue goose opencode other'
$MCP_KNOWN_IDS = 'github gitlab filesystem git postgres mysql sqlite mongodb redis supabase firebase
  playwright puppeteer browserbase chrome-devtools slack linear notion jira atlassian confluence
  sentry stripe figma context7 memory fetch brave-search exa tavily perplexity sequential-thinking
  time gdrive google-maps aws cloudflare vercel docker kubernetes terraform datadog grafana
  shopify hubspot salesforce zapier n8n everything desktop-commander serena firecrawl taskmaster
  shadcn deepwiki neon prisma netlify heroku azure huggingface'
$MCP_ALIASES = 'gh=github fs=filesystem file-system=filesystem pg=postgres postgresql=postgres
  sqlite3=sqlite mongo=mongodb browserbasehq=browserbase brave=brave-search notionhq=notion
  figma-dev-mode=figma figma-developer=figma perplexity-ask=perplexity
  sequentialthinking=sequential-thinking google-drive=gdrive k8s=kubernetes
  desktopcommander=desktop-commander taskmaster-ai=taskmaster task-master-ai=taskmaster
  task-master=taskmaster shadcn-ui=shadcn hf=huggingface hugging-face=huggingface'
$KEY_PLACE_IDS = 'shell_rc shell_history env_file mcp_config agent_config project_file other'
function Ids([string]$list) { , ($list -split '\s+' | Where-Object { $_ }) }

# The well-known ids among MCP server labels, in list order, and how many labels
# matched none. Only ids from the list and a number come out, never a label.
function Strip-Label([string]$s) {
  $s = $s -replace '[ ._]+', '-'
  do {
    $t = $s
    $s = $s -replace '^-+', '' -replace '-+$', '' -replace '^mcp-', '' -replace '^server-', '' -replace '-mcp$', '' -replace '-server$', ''
  } while ($s -ne $t)
  if ($s -eq 'mcp' -or $s -eq 'server') { $s = '' }
  $s
}
function Label-Part([string]$s) { Strip-Label (($s -replace '^@+', '') -replace '@.*$', '') }
function Mcp-Match($labels) {
  $known = Ids $MCP_KNOWN_IDS; $ok = @{}; foreach ($k in $known) { $ok[$k] = 1 }
  $al = @{}
  foreach ($a in (Ids $MCP_ALIASES)) { $p = $a.Split('='); if ($p.Count -eq 2 -and $ok.ContainsKey($p[1])) { $al[$p[0]] = $p[1] } }
  $hit = @{}; $other = 0
  foreach ($label in $labels) {
    $seg = $label.ToLowerInvariant().Split('/')
    $s = Label-Part $seg[$seg.Count - 1]
    if ($s -eq '' -and $seg.Count -gt 1) { $s = Label-Part $seg[$seg.Count - 2] }
    if ($ok.ContainsKey($s)) { $hit[$s] = 1 } elseif ($al.ContainsKey($s)) { $hit[$al[$s]] = 1 } else { $other++ }
  }
  $ids = @($known | Where-Object { $hit.ContainsKey($_) })
  @{ Known = $ids; Other = $other }
}

# The MCP server names in a JSON config, without running anything: mcpServers,
# servers, mcp (or mcp.servers) and every project's mcpServers. $null when the
# file can't be read. PowerShell's own ConvertFrom-Json is not used because it
# refuses keys that differ only in case, which Claude Code's config can hold.
# A property of a parsed JSON object, or $null. The last one wins, as in jq.
function Json-Get([object]$obj, [string]$key) {
  $found = $null
  if ($IsCore) {
    if ($null -eq $obj -or $obj.ValueKind -ne [Text.Json.JsonValueKind]::Object) { return $null }
    foreach ($p in $obj.EnumerateObject()) { if ($p.Name -ceq $key) { $found = @{ V = $p.Value } } }
  } elseif ($obj -is [Collections.IDictionary] -and $obj.ContainsKey($key)) { $found = @{ V = $obj[$key] } }
  $found
}
function Is-JsonObject([object]$v) {
  if ($IsCore) { return ($null -ne $v -and $v -is [Text.Json.JsonElement] -and $v.ValueKind -eq [Text.Json.JsonValueKind]::Object) }
  $v -is [Collections.IDictionary]
}
function Json-Names([object]$obj, [string]$key) {
  $g = Json-Get $obj $key
  if ($null -ne $g -and (Is-JsonObject $g.V)) { return , $g.V }
  $null
}
function Obj-Keys([object]$obj) {
  if ($null -eq $obj) { return @() }
  if ($IsCore) { return @($obj.EnumerateObject() | ForEach-Object { $_.Name }) }
  @($obj.Keys)
}
function Json-Servers([string]$f) {
  $t = Read-Text $f; if ($null -eq $t) { return $null }
  try {
    if ($IsCore) {
      $o = New-Object System.Text.Json.JsonDocumentOptions
      $o.CommentHandling = [Text.Json.JsonCommentHandling]::Skip; $o.AllowTrailingCommas = $true
      $root = [Text.Json.JsonDocument]::Parse($t, $o).RootElement
    } else {
      Add-Type -AssemblyName System.Web.Extensions
      $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
      $js.MaxJsonLength = [int]::MaxValue; $js.RecursionLimit = 1000
      $root = $js.DeserializeObject($t)
    }
  } catch { return $null }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  $names = New-Object System.Collections.Generic.List[string]
  $add = { param($o) foreach ($k in (Obj-Keys $o)) { if ($seen.Add($k)) { $names.Add($k) } } }
  & $add (Json-Names $root 'mcpServers')
  & $add (Json-Names $root 'servers')
  $mcp = Json-Names $root 'mcp'
  if ($null -ne $mcp) { if ($null -ne (Json-Get $mcp 'servers')) { & $add (Json-Names $mcp 'servers') } else { & $add $mcp } }
  $projects = Json-Names $root 'projects'
  foreach ($p in (Obj-Keys $projects)) {
    & $add (Json-Names (Json-Get $projects $p).V 'mcpServers')
  }
  , @($names | ForEach-Object { [regex]::Replace($_, '[\x00-\x1f\x7f]', '?') })
}

# An npm publish from this folder would ship .claude\ unless something excludes it.
function Npm-WouldShip([string]$dir) {
  $pkg = J $dir 'package.json'; $t = Read-Text $pkg
  if ($null -eq $t) { return $false }
  if ($t -cmatch '"private"\s*:\s*true') { return $false }
  if ($t -cmatch '"files"\s*:') { return $false }
  $ni = Read-Text (J $dir '.npmignore')
  if ($null -ne $ni) { return -not ($ni -cmatch '(?m)(^|/)\.claude') }
  $gi = Read-Text (J $dir '.gitignore')
  if ($null -ne $gi -and $gi -cmatch '\.claude') { return $false }
  $true
}

function Is-File([string]$p) { try { [IO.File]::Exists($p) } catch { $false } }
function Is-Dir([string]$p) { try { [IO.Directory]::Exists($p) } catch { $false } }
function Exists([string]$p) { (Is-File $p) -or (Is-Dir $p) }
function Env-Or([string]$name, [string]$fallback) { $v = [Environment]::GetEnvironmentVariable($name); if ($v) { $v } else { $fallback } }
function Has-Command([string]$name) { $null -ne (Get-Command -Name $name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1) }
function Entries([string]$dir) {
  try { $e = ([IO.DirectoryInfo]$dir).GetFileSystemInfos() } catch { return @() }
  , @($e | Sort-Object -Property Name -CaseSensitive)
}
function Is-Link($info) { ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }
function Is-DirInfo($info) { ($info.Attributes -band [IO.FileAttributes]::Directory) -ne 0 }
# Whether this person owns a file, read off Windows (PowerShell 7 adds User to a file's info). A link
# is judged by what it points at, as bash's -O does, where .NET can resolve it (PowerShell 7.2 and up).
function Owns-File([string]$p) {
  try {
    $it = Get-Item -LiteralPath $p -Force -ErrorAction Stop
    $t = $null; try { $t = [IO.File]::ResolveLinkTarget($p, $true) } catch { }
    if ($t) { $it = Get-Item -LiteralPath $t.FullName -Force -ErrorAction Stop }
    $owner = [string]$it.User
    return [bool]($owner -and $owner -ceq [Environment]::UserName)
  } catch { return $false }
}
# A file with more than one name, or a link: PowerShell gives LinkType HardLink to a file with more
# than one name, and SymbolicLink to a link. In a shared folder either could put another person's file
# under a marker's name.
function Multi-Name([string]$p) { try { return [bool]((Get-Item -LiteralPath $p -Force -ErrorAction Stop).LinkType) } catch { return $true } }
# Children of these patterns, by name, under the folders named.
function Glob-Dirs([string]$parent, [string]$pattern) {
  if (-not (Is-Dir $parent)) { return @() }
  try { , @([IO.Directory]::GetDirectories($parent, $pattern) | Sort-Object) } catch { , @() }
}

# One pass over the home folder, depth-limited, skipping heavy and system folders:
# dependency caches, build output, model and VM images, cloud sync folders.
$PruneNames = @('node_modules', '.git', '.Trash', '.cache', '.npm', '.pnpm-store', '.yarn', '.cargo', '.rustup', '.gradle',
  '.m2', '.pyenv', '.rbenv', '.nvm', '.bun', '.deno', '__pycache__', '.tox', '.next', 'dist', 'build', 'target', 'vendor',
  'Pods', 'DerivedData', '.terraform', '.gem', '.cocoapods', '.android', '.pub-cache', '.dartServer', '.swiftpm', '.ollama',
  '.lmstudio', '.colima', '.lima', '.orbstack', '.minikube', '.vagrant.d', '.docker', '.oh-my-zsh', '.zsh_sessions',
  '.codeium', '.vscode-server', '.nuget', '.dotnet')
$PrunePaths = New-Object System.Collections.Generic.List[string]
foreach ($p in @('AppData', 'Library', 'Applications', 'Pictures', 'Videos', 'Movies', 'Music', 'Public', 'go', '.vscode', '.cursor',
    '.windsurf', '.devin', '.local/share', 'Dropbox', 'Google Drive', 'Saved Games', 'Favorites', 'Contacts', 'Links', 'Searches',
    '3D Objects', 'scoop')) { $PrunePaths.Add((J $HomeDir $p)) }
if (-not $OptAll) { foreach ($p in @('Desktop', 'Documents', 'Downloads')) { $PrunePaths.Add((J $HomeDir $p)) } }
$Found = New-Object System.Collections.Generic.List[string]
# Kept apart from $Found, so files_found counts what it always has: the files of the npm and
# project checks, and linked settings files, which are checked like the files but are not files.
$LinkSettings = New-Object System.Collections.Generic.List[string]
$LockFiles = New-Object System.Collections.Generic.List[string]
$TaskFiles = New-Object System.Collections.Generic.List[string]
$WormFiles = New-Object System.Collections.Generic.List[string]
$AiderFiles = New-Object System.Collections.Generic.List[string]
# The project files of data/auto-approve.tsv, every project's .vscode/settings.json (section 2), and
# links to this user's ~/.ssh/authorized_keys outside ~/.ssh.
$AaFiles = New-Object System.Collections.Generic.List[string]
$VscSettings = New-Object System.Collections.Generic.List[string]
$AkLinks = New-Object System.Collections.Generic.List[string]
$Sites = New-Object System.Collections.Generic.List[string]
# Folders the scan could not read: the files in them were not checked (sections 2 to 5 say so).
$UnreadDirs = New-Object System.Collections.Generic.List[string]
$script:ScanN = 0
function Is-Pruned([string]$path, [string]$name, [int]$depth) {
  foreach ($n in $PruneNames) { if ($name -ceq $n) { return $true } }
  foreach ($p in $PrunePaths) { if ($path.Equals($p, $PathCmp)) { return $true } }
  ($depth -eq 1) -and $name.StartsWith('OneDrive', $PathCmp)
}
# Files worms plant in a project, from data/planted.tsv.
# >>> planted: generated from data/planted.tsv by tools/gen.sh. Edit that file, then run it.
$WormNameAlone = '\.(claude|vscode)[/\\]+(router_runtime\.js|math_init\.js)'
$WormNameWeak = '\.(claude|vscode)[/\\]+(setup\.mjs)'
function Planted-Note([string]$p) { switch -CaseSensitive ($p) { '.claude/router_runtime.js' { 'a file the TanStack worm plants' } '.vscode/router_runtime.js' { 'a file the TanStack worm plants' } '.claude/setup.mjs' { 'a file the TanStack and keyv worms plant' } '.claude/math_init.js' { 'a file the keyv worm plants' } '.vscode/setup.mjs' { 'a file the TanStack and keyv worms plant' } default { $null } } }
function Planted-Sha([string]$p) { switch -CaseSensitive ($p) { '.claude/setup.mjs' { 'fd3ca4007b225fdf8de7af4345a19179d5efa8c4bb9205f88cda806e5684b1eb 54dc7ea54a1317cca0e890a2770630cf7fa6c97813e0cb9d2caa93012b350668 2258284d65f63829bd67eaba01ef6f1ada2f593f9bbe41678b2df360bd90d3df' } '.vscode/setup.mjs' { 'fd3ca4007b225fdf8de7af4345a19179d5efa8c4bb9205f88cda806e5684b1eb 54dc7ea54a1317cca0e890a2770630cf7fa6c97813e0cb9d2caa93012b350668 2258284d65f63829bd67eaba01ef6f1ada2f593f9bbe41678b2df360bd90d3df' } default { '' } } }
$PlantedAlone = @('.claude/router_runtime.js', '.vscode/router_runtime.js', '.claude/math_init.js')
$WormRefNote = 'runs a file a worm plants'
# <<< planted
# Agents set to run commands without asking (data/auto-approve.tsv), read in section 1.
# >>> auto-approve: generated from data/auto-approve.tsv by tools/gen.sh. Edit that file, then run it.
$AaTable = @(
  ,@('Claude Code', 'all', (J (Env-Or 'CLAUDE_CONFIG_DIR' (J $HomeDir '.claude')) 'settings.json'), 'bypassPermissions', @('"defaultMode": "bypassPermissions"'))
  ,@('Codex', 'all', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'config.toml'), 'never asks, full access', @('approval_policy = "never"', 'sandbox_mode = "danger-full-access"'))
  ,@('VS Code Copilot', 'all', (J $AppData 'Code/User/settings.json'), 'chat.tools.global.autoApprove', @('"chat.tools.global.autoApprove": true'))
  ,@('VS Code Copilot', 'all', (J $AppData 'Code/User/settings.json'), 'chat.permissions.default: autoApprove', @('"chat.permissions.default": "autoApprove"'))
  ,@('VS Code Copilot', 'all', (J $AppData 'Code/User/settings.json'), 'chat.permissions.default: autopilot', @('"chat.permissions.default": "autopilot"'))
)
$AaProject = @()
# <<< auto-approve
function Is-WormFile([string]$parent, [string]$name) { $null -ne (Planted-Note "$parent/$name") }
# Whether a link ends at a regular file. Off Windows a repo can link a settings file to /dev/zero or
# /dev/tty, which .NET would read for ever; UnixMode (PowerShell 7.1 and up) starts with - for a
# regular file and l for a link, which is followed. Windows has no such files in a profile.
function Is-RegularFile([string]$p) {
  if (-not (Is-File $p)) { return $false }
  if ($OnWindows) { return $true }
  $t = $p
  for ($i = 0; $i -lt 40; $i++) {
    try { $it = Get-Item -LiteralPath $t -Force -ErrorAction Stop } catch { return $false }
    $m = [string]$it.UnixMode
    if (-not $m.StartsWith('l')) { return $m.StartsWith('-') }
    $lt = [string](@($it.Target)[0]); if (-not $lt) { return $false }
    if (-not [IO.Path]::IsPathRooted($lt)) { $lt = J ([IO.Path]::GetDirectoryName($t)) $lt }
    $t = $lt
  }
  $false
}
function Is-AaProject([string]$path) {
  $ps = $path -replace '\\', '/'
  foreach ($r in $AaProject) { if ($ps.EndsWith('/' + $r, [StringComparison]::Ordinal)) { return $true } }
  $false
}
# A link's target, read without following it: LinkTarget on PowerShell 7, Get-Item's Target on 5.1.
function Link-Target($info) {
  $t = $null
  try { $t = $info.LinkTarget } catch { }
  if (-not $t) { try { $t = @((Get-Item -LiteralPath $info.FullName -Force -ErrorAction Stop).Target)[0] } catch { } }
  [string]$t
}
# A folder's physical path, with the links on the way resolved, as cd and pwd -P give it: .NET reads
# the current directory back from the system, which resolves them (Windows keeps the path as given).
# $null when the folder can't be entered.
function Real-Dir([string]$d) {
  $old = $null
  try { $old = [IO.Directory]::GetCurrentDirectory(); [IO.Directory]::SetCurrentDirectory($d); [IO.Directory]::GetCurrentDirectory() } catch { $null }
  finally { if ($old) { try { [IO.Directory]::SetCurrentDirectory($old) } catch { } } }
}
# Does a link in $dir with this target resolve to this user's own ~/.ssh/authorized_keys? As bash's
# find -ilname '*authorized_keys' and -ef: a target named so, in any case, whose folder resolves to
# ~/.ssh, so .ssh/./authorized_keys, .ssh//authorized_keys and a link through a linked folder count,
# and another case of the name counts where the volume ignores case (APFS, NTFS). A link into a repo's
# own .ssh/authorized_keys fixture does not count, and a link to the file's place counts before the
# file exists: an agent writing through it creates it.
$AkDir = $null; $AkCaseless = $false
if (Is-Dir (J $HomeDir '.ssh')) { $AkDir = Real-Dir (J $HomeDir '.ssh') }
if ($AkDir) { $AkCaseless = (Is-File (J $AkDir 'authorized_keys')) -and (Is-File (J $AkDir 'AUTHORIZED_KEYS')) }
function Is-AkLink([string]$dir, [string]$target) {
  if (-not $target -or -not $AkDir) { return $false }
  try {
    $t = $target -replace '\\', '/'; $cut = $t.LastIndexOf('/'); $base = $t.Substring($cut + 1)
    if (-not $base.EndsWith('authorized_keys', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ($cut -lt 0) { $parent = $dir } elseif ($cut -eq 0) { $parent = '/' } else { $parent = $t.Substring(0, $cut) }
    if (-not [IO.Path]::IsPathRooted($parent)) { $parent = J $dir $parent }
    $real = Real-Dir $parent
    if (-not $real -or -not $real.Equals($AkDir, $PathCmp)) { return $false }
    if ($base -ceq 'authorized_keys') { return $true }
    return ($AkCaseless -and $base.Equals('authorized_keys', [StringComparison]::OrdinalIgnoreCase))
  } catch { return $false }
}
function Scan-Home([string]$dir, [int]$depth) {
  try { $es = ([IO.DirectoryInfo]$dir).GetFileSystemInfos() } catch { $UnreadDirs.Add($dir); return }
  foreach ($e in @($es | Sort-Object -Property Name -CaseSensitive)) {
    $name = $e.Name; $path = $e.FullName; $d = $depth + 1; $link = Is-Link $e
    if (Is-DirInfo $e) {
      if ($link -or (Is-Pruned $path $name $d)) { continue }
      if ($name -ceq 'site-packages') { $Sites.Add($path); continue }
      if ($d -lt 6) { Scan-Home $path $d }
      continue
    }
    $parent = [IO.Path]::GetFileName($dir)
    $isSettings = $parent -ceq '.claude' -and ($name -ceq 'settings.json' -or $name -ceq 'settings.local.json')
    # A linked settings, tasks or worm file is followed when it ends at a regular file; any other
    # link is not.
    if ($link) {
      if ($isSettings) { if (Is-RegularFile $path) { $LinkSettings.Add($path) } }
      elseif ($parent -ceq '.vscode' -and $name -ceq 'tasks.json') { if (Is-RegularFile $path) { $TaskFiles.Add($path) } }
      elseif (Is-WormFile $parent $name) { if (Is-RegularFile $path) { $WormFiles.Add($path) } }
      if ((Is-AkLink $dir (Link-Target $e)) -and -not $path.StartsWith((J $HomeDir '.ssh') + $Sep, $PathCmp)) { $AkLinks.Add($path) }
      continue
    }
    if ($name -ceq '.env' -or $name.StartsWith('.env.') -or $name -ceq '.envrc' -or $name -ceq '.mcp.json' -or $name -ceq 'pyvenv.cfg' -or $isSettings -or
      ($name -ceq 'mcp.json' -and ($parent -ceq '.cursor' -or $parent -ceq '.vscode'))) {
      $Found.Add($path)
      $script:ScanN++
      if ($script:ScanN % 4 -eq 1) { Progress "Checking $(Short $path)" }
    } elseif ($name -ceq 'package-lock.json' -or $name -ceq 'npm-shrinkwrap.json' -or $name -ceq 'pnpm-lock.yaml' -or $name -ceq 'yarn.lock' -or $name -ceq 'bun.lock') { $LockFiles.Add($path) }
    elseif ($name -ceq '.aider.chat.history.md' -or $name -ceq '.aider.input.history') { $AiderFiles.Add($path) }
    elseif ($parent -ceq '.vscode' -and $name -ceq 'tasks.json') { $TaskFiles.Add($path) }
    elseif (Is-WormFile $parent $name) { $WormFiles.Add($path) }
    else {
      if ($parent -ceq '.vscode' -and $name -ceq 'settings.json') { $VscSettings.Add($path) }
      if (Is-AaProject $path) { $AaFiles.Add($path) }
    }
  }
}
# Whether a folder holds any file within three levels, and any changed in 30 days.
function Activity([string]$dir, [int]$depth, $since, $state) {
  foreach ($e in (Entries $dir)) {
    if ($state.Recent) { return }
    if (Is-Link $e) { continue }
    if (Is-DirInfo $e) { if ($depth + 1 -lt 3) { Activity $e.FullName ($depth + 1) $since $state }; continue }
    $state.Any = $true
    if ($e.LastWriteTimeUtc -gt $since) { $state.Recent = $true }
  }
}
# Python environments under a folder, a few levels deep, skipping node_modules.
function Find-Sites([string]$dir, [int]$depth, [int]$max, $out) {
  foreach ($e in (Entries $dir)) {
    if ((Is-Link $e) -or -not (Is-DirInfo $e)) { continue }
    if ($e.Name -ceq 'node_modules') { continue }
    if ($e.Name -ceq 'site-packages' -or $e.Name -ceq 'dist-packages') { $out.Add($e.FullName); continue }
    if ($depth + 1 -lt $max) { Find-Sites $e.FullName ($depth + 1) $max $out }
  }
}

# The GIRD mark and wordmark, as in gird-check.sh. Kept as \u escapes so the file stays ASCII
# for Windows PowerShell 5.1; the legacy console (no Windows Terminal) gets the one-line header.
function Show-Banner {
  $u = { param($s) [regex]::Unescape($s) }
  $wm = @(' \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2557\u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2557', '\u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d \u2588\u2588\u2551\u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2557', '\u2588\u2588\u2551  \u2588\u2588\u2588\u2557\u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u2588\u2588\u2551  \u2588\u2588\u2551', '\u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2551\u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2551  \u2588\u2588\u2551', '\u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u2588\u2588\u2551\u2588\u2588\u2551  \u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d', ' \u255a\u2550\u2550\u2550\u2550\u2550\u255d \u255a\u2550\u255d\u255a\u2550\u255d  \u255a\u2550\u255d\u255a\u2550\u2550\u2550\u2550\u2550\u255d')
  $mk = @('    \u28a0\u28e4\u28f4\u28f6\u28e4\u2804    ', ' \u2880\u28f4\u28c7\u2818\u28ff\u28ff\u281f\u2881\u28f4\u28ff\u28e6\u2840 ', ' \u28fe\u28ff\u28ff\u2840\u2809\u2801 \u2819\u283b\u283f\u28ff\u28f7 ', '', ' \u28bf\u28ff\u28f6\u28e6\u28c4 \u2880\u28c0\u2808\u28ff\u28ff\u287f ', ' \u2808\u283b\u28ff\u281f\u2881\u28f4\u28ff\u28ff\u2844\u28b9\u281f\u2801 ')
  $boxRx = & $u '[\u2557\u2551\u2554\u2550\u255d\u255a]+'
  for ($i = 0; $i -lt 6; $i++) {
    $row = & $u $wm[$i]
    if ($cTeal) { $row = [regex]::Replace($row, $boxRx, { param($m) $cTeal + $m.Value + $cRst + $cBold }) }
    if ($i -eq 3) { $mark = (& $u ' \u2819\u281b\u283b\u2801 ') + $cGold + (& $u '\u2830\u2806') + $cTeal + (& $u ' \u2880\u28e6\u28e4\u28c4\u2840') } else { $mark = & $u $mk[$i] }
    Emit ("  $cTeal$mark$cRst   $cBold$row$cRst")
  }
  Emit ("  $cTeal" + (& $u '    \u2810\u281b\u283f\u283f\u281b\u2803    ') + "$cRst   ${cBold}BLINDSPOT$cRst  ${cDim}v1.2.0 $gMid 25 Oct 2026 $gMid gird.ai/blindspot$cRst")
}

# ===========================================================================
$ScanT0 = [DateTime]::UtcNow
$Early = $false
try {
Blank
if ($Fancy) { Show-Banner } else {
Emit ("  $cTeal${cBold}GIRD$cRst  ${cBold}BLINDSPOT$cRst  ${cDim}v1.2.0 $gMid 25 Oct 2026 $gMid gird.ai/blindspot$cRst")
}
Blank
Emit "  ${cDim}Read-only. Prints paths and counts, never a key.$cRst"
if (-not $OptOffline) { Emit "  ${cDim}Shares counts and a hashed device ID with gird.ai. -Offline skips it.$cRst" }
if (-not $OptAll) { Emit "  ${cDim}Skips Desktop, Documents and Downloads. Add -All to include them.$cRst" }

# One line of real, public totals under the banner, picked at random from the ones
# big enough to mean something. Below 1,000 AI builders it shows nothing: the
# header says you're one of the first 1,000 instead.
if (-not $OptOffline) {
  $pj = (Http 'GET' "$Api/stats" 2 '' 65536) -replace '\s', ''
  $dv = JNum 'devices' $pj; $d7 = JNum 'devices_7d' $pj; $kf = JNum 'key_files' $pj
  $cl = ''; $m = [regex]::Match($pj, '"clean":(0(\.[0-9]{1,6})?|1(\.0{1,6})?)([,}]|$)'); if ($m.Success) { $cl = $m.Groups[1].Value }
  if ($dv) {
    if ([long]$dv -lt 1000) { $Early = $true }
    else {
      $pm = New-Object System.Collections.Generic.List[string]
      $pm.Add("$(Commas $dv) AI builders have run Blindspot.")
      if ($d7 -and [long]$d7 -ge 50) { $pm.Add("$(Commas $d7) AI builders ran it this week.") }
      if ($kf -and [long]$kf -ge 100) { $pm.Add("Blindspot has found $(Commas $kf) files with AI keys in plain text so far.") }
      if ($cl) {
        $cp = [int][Math]::Floor([double]::Parse($cl, [Globalization.CultureInfo]::InvariantCulture) * 100 + 0.5)
        if ($cp -ge 1 -and $cp -le 99) { $pm.Add("$cp% of AI builders had no keys in plain text. Let's see about you.") }
      }
      Out-Text "`n  $cGold$gStar$cRst $cBold$($pm[(Get-Random -Maximum $pm.Count)])$cRst`n"
    }
  }
}
Blank

Progress 'Looking through your home folder'
# --- Keys in agent sessions, checked in the background --------------------------
# docs/designs/transcripts.md, and the same list as gird-check.sh's SESS_SOURCES.
# >>> sessions: generated from data/sessions.tsv by tools/gen.sh. Edit that file, then run it.
$SessTable = @(
  @('read', 'Claude Code', (J (Env-Or 'CLAUDE_CONFIG_DIR' (J $HomeDir '.claude')) 'projects')),
  @('read', 'Claude Code', (J (Env-Or 'CLAUDE_CONFIG_DIR' (J $HomeDir '.claude')) 'history.jsonl')),
  @('read', 'Claude Code', (J (Env-Or 'CLAUDE_CONFIG_DIR' (J $HomeDir '.claude')) 'paste-cache')),
  @('read', 'Claude Desktop', (J $AppData 'Claude/local-agent-mode-sessions')),
  @('read', 'Claude Desktop', (J $LocalAppData 'Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/local-agent-mode-sessions')),
  @('read', 'Claude Desktop', (J $AppData 'Claude-3p/local-agent-mode-sessions')),
  @('read', 'Claude Desktop', (J $LocalAppData 'Claude-3p/local-agent-mode-sessions')),
  @('read', 'Codex', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'sessions')),
  @('read', 'Codex', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'archived_sessions')),
  @('read', 'Codex', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'history.jsonl')),
  @('read', 'Codex', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'thread_history_1.sqlite')),
  @('read', 'Codex', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'thread_history_1.sqlite-wal')),
  @('read', 'Codex', (J (Env-Or 'CODEX_SQLITE_HOME' (J $HomeDir '.codex')) 'thread_history_1.sqlite')),
  @('read', 'Codex', (J (Env-Or 'CODEX_SQLITE_HOME' (J $HomeDir '.codex')) 'thread_history_1.sqlite-wal')),
  @('read', 'Gemini CLI', (J (Env-Or 'GEMINI_CLI_HOME' $HomeDir) '.gemini/tmp')),
  @('read', 'Qwen Code', (J (Env-Or 'QWEN_HOME' (J $HomeDir '.qwen')) 'projects')),
  @('read', 'Qwen Code', (J (Env-Or 'QWEN_HOME' (J $HomeDir '.qwen')) 'tmp')),
  @('read', 'OpenCode', (J (Env-Or 'XDG_DATA_HOME' (J $HomeDir '.local/share')) 'opencode/opencode.db')),
  @('read', 'OpenCode', (J (Env-Or 'XDG_DATA_HOME' (J $HomeDir '.local/share')) 'opencode/opencode.db-wal')),
  @('read', 'OpenCode', (J (Env-Or 'XDG_DATA_HOME' (J $HomeDir '.local/share')) 'opencode/storage')),
  @('read', 'GitHub Copilot CLI', (J (Env-Or 'COPILOT_HOME' (J $HomeDir '.copilot')) 'session-state')),
  @('read', 'GitHub Copilot CLI', (J (Env-Or 'COPILOT_HOME' (J $HomeDir '.copilot')) 'history-session-state')),
  @('read', 'GitHub Copilot CLI', (J (Env-Or 'COPILOT_HOME' (J $HomeDir '.copilot')) 'command-history-state')),
  @('read', 'GitHub Copilot CLI', (J (Env-Or 'COPILOT_HOME' (J $HomeDir '.copilot')) 'session-store.db')),
  @('read', 'GitHub Copilot CLI', (J (Env-Or 'COPILOT_HOME' (J $HomeDir '.copilot')) 'session-store.db-wal')),
  @('read', 'GitHub Copilot CLI', (J (Env-Or 'COPILOT_HOME' (J $HomeDir '.copilot')) 'command-history-state.json')),
  @('read', 'Roo Code', (J $AppData 'Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks')),
  @('read', 'Roo Code', (J $AppData 'Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks')),
  @('read', 'Cline', (J $AppData 'Code/User/globalStorage/saoudrizwan.claude-dev/tasks')),
  @('read', 'Cline', (J $AppData 'Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks')),
  @('read', 'Cline', (J (Env-Or 'CLINE_DATA_DIR' (J $HomeDir '.cline/data')) 'sessions')),
  @('read', 'Cline', (J (Env-Or 'CLINE_DATA_DIR' (J $HomeDir '.cline/data')) 'tasks')),
  @('read', 'Cline', (J (Env-Or 'CLINE_DIR' (J $HomeDir '.cline')) 'data/sessions')),
  @('read', 'Cline', (J (Env-Or 'CLINE_DIR' (J $HomeDir '.cline')) 'data/tasks')),
  @('read', 'Cline', (Env-Or 'CLINE_SESSION_DATA_DIR' (J $HomeDir '.cline/data/sessions'))),
  @('read', 'Continue', (J (Env-Or 'CONTINUE_GLOBAL_DIR' (J $HomeDir '.continue')) 'sessions')),
  @('read', 'Continue', (J (Env-Or 'CONTINUE_GLOBAL_DIR' (J $HomeDir '.continue')) 'dev_data/0.2.0/chatInteraction.jsonl')),
  @('read', 'Goose', (J $GooseData 'sessions')),
  @('read', 'Goose', (J $GooseState 'logs')),
  @('read', 'Goose', (J $GooseState 'history.txt')),
  @('read', 'Kiro CLI', (J (Env-Or 'KIRO_HOME' (J $HomeDir '.kiro')) 'sessions')),
  @('read', 'Kiro CLI', (J $LocalAppData 'kiro-cli')),
  @('read', 'Amazon Q', (J $LocalAppData 'amazon-q')),
  @('read', 'Amazon Q', (J $HomeDir '.aws/amazonq/.cli_bash_history')),
  @('read', 'Factory Droid', (J $HomeDir '.factory/sessions')),
  @('read', 'Factory Droid', (J $HomeDir '.factory/projects')),
  @('read', 'Factory Droid', (J $HomeDir '.factory/state/history.json')),
  @('read', 'Cursor', (J $AppData 'Cursor/User/globalStorage/state.vscdb')),
  @('read', 'Cursor', (J $HomeDir '.cursor/projects')),
  @('read', 'Cursor', (J $HomeDir '.cursor/chats')),
  @('read', 'Windsurf', (J $HomeDir '.windsurf/transcripts')),
  @('read', 'Antigravity', (J $HomeDir '.gemini/antigravity/brain')),
  @('read', 'Antigravity', (J $HomeDir '.gemini/antigravity-cli/brain')),
  @('read', 'Antigravity', (J $HomeDir '.gemini/antigravity-ide/brain')),
  @('db', 'Antigravity', (J $HomeDir '.gemini/antigravity/conversations')),
  @('db', 'Antigravity', (J $HomeDir '.gemini/antigravity-cli/conversations')),
  @('db', 'Antigravity', (J $HomeDir '.gemini/antigravity-ide/conversations')),
  @('sealed', 'Windsurf', (J $HomeDir '.codeium/windsurf/cascade')),
  @('sealed', 'Antigravity', (J $HomeDir '.gemini/antigravity/conversations')),
  @('sealed', 'Antigravity', (J $HomeDir '.gemini/antigravity-cli/conversations')),
  @('sealed', 'Antigravity', (J $HomeDir '.gemini/antigravity-ide/conversations')))
# <<< sessions
$SessSources = @($SessTable | Where-Object { $_[0] -eq 'read' -or $_[0] -eq 'db' } | ForEach-Object { , @($_[1], $_[2]) })
# Folders whose .pb conversation files are stored encrypted: those files are counted and named as
# not checked.
$SessSealed = @($SessTable | Where-Object { $_[0] -eq 'sealed' } | ForEach-Object { , @($_[1], $_[2]) })
# Lists the files under the session roots one folder at a time, so a folder that can't be read is
# counted in $st.Skipped and the rest are still listed (EnumerateFiles over all folders at once
# stops at the first one it can't open, and drops the rest of that root). Folders that are links
# are not followed, as ripgrep and gird-check.sh's perl do not. A pipe, a socket or a device is
# never listed: opening a pipe waits for a writer, and a device may never end. Text, so the
# background session check can load it too; it returns the list as one object.
$SessListFn = @'
# A regular file, following a link: what bash's [ -f ] and perl's -f say. PowerShell 7.2 and up
# say which a file is off Windows (the first letter of UnixMode, from Get-Item); Windows keeps no
# pipes or devices among files, and an older PowerShell is taken at its word.
function Is-PlainFile([string]$p) {
  if ($env:OS -eq 'Windows_NT') { return $true }
  try {
    $t = $null; try { $t = [IO.File]::ResolveLinkTarget($p, $true) } catch { }
    if ($t) { if (-not $t.Exists) { return $false }; $p = $t.FullName }
    $m = [string](Get-Item -LiteralPath $p -Force -ErrorAction Stop).UnixMode
    return (-not $m) -or $m.StartsWith('-')
  } catch { return $true }
}
function Sess-List($roots, $st) {
  $files = New-Object System.Collections.Generic.List[object]
  $dirs = New-Object System.Collections.Generic.Stack[object]
  foreach ($r in $roots) {
    try {
      if ([IO.File]::Exists($r)) { $files.Add((New-Object IO.FileInfo $r)) } else { $dirs.Push((New-Object IO.DirectoryInfo $r)) }
    } catch { $st.Skipped++ }
  }
  while ($dirs.Count -gt 0) {
    if ($st.Stop) { break }
    $d = $dirs.Pop()
    try {
      foreach ($f in $d.EnumerateFiles()) {
        # Only an entry that may not be a regular file is asked about: a link, or an empty one, as
        # pipes, sockets and devices are.
        if ((($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $f.Length -eq 0) -and -not (Is-PlainFile $f.FullName)) { continue }
        $files.Add($f)
      }
      foreach ($sd in $d.EnumerateDirectories()) { if (($sd.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $dirs.Push($sd) } }
    } catch { $st.Skipped++ }
  }
  ,$files
}
'@
. ([scriptblock]::Create($SessListFn))
# A location given as a file is read as it is, following a link as ripgrep follows one, but only to
# a regular file. A db folder gives its SQLite files, *.db and their *.db-wal, and nothing else in it;
# one that can't be listed is given as it is, so the check names it as a folder not read.
$SessRoots = @(@(foreach ($sessRow in $SessTable) {
    if ($sessRow[0] -eq 'read') { if ((Is-Dir $sessRow[2]) -or ((Is-File $sessRow[2]) -and (Is-PlainFile $sessRow[2]))) { $sessRow[2] } }
    elseif ($sessRow[0] -eq 'db' -and (Is-Dir $sessRow[2])) {
      try {
        foreach ($f in ([IO.DirectoryInfo]$sessRow[2]).EnumerateFiles()) {
          if ($f.Name -cmatch '\.db(-wal)?$' -and ((($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and $f.Length -gt 0) -or (Is-PlainFile $f.FullName))) { $f.FullName }
        }
      } catch { $sessRow[2] }
    }
  }) | Select-Object -Unique)
# Runs in its own runspace: lists the files newest first and checks them until told to stop, or
# lets rg.exe do it. Only "file<tab>provider" leaves it; keys stay inside.
$SessWorker = {
  param($roots, $keys, $pre, $rg, $fns, $st, $timeoutMs, $cut, $hold)
  . ([scriptblock]::Create($fns))
  $to = [TimeSpan]::FromMilliseconds($timeoutMs)
  $rx = New-Object regex($keys, [Text.RegularExpressions.RegexOptions]::Multiline, $to)
  $rxPre = New-Object regex($pre, [Text.RegularExpressions.RegexOptions]::None, $to)
  $rxSep = New-Object regex('[^A-Za-z0-9_.\\\-]', [Text.RegularExpressions.RegexOptions]::RightToLeft, $to)
  $hit = { param($f, $k)
    $p = Key-Provider $k
    if ($p -and -not (Made-Up $k) -and -not (Is-CliOwnKey $f $k) -and -not $st.Seen.ContainsKey("$f`t$p")) { $st.Seen["$f`t$p"] = 1; [void]$st.Hits.Add("$f`t$p") } }
  # Tests only: the .NET engine waits while the file named exists; rg.exe gets it as one more root,
  # so a pipe nobody writes to holds it, as gird-check.sh's ripgrep is held.
  if ($hold -and -not $rg) { while ((Test-Path -LiteralPath $hold) -and -not $st.Stop) { Start-Sleep -Milliseconds 50 } }
  if ($rg) {
    $q = { param($a) '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    $pf = $null
    try {
      $pf = [IO.Path]::GetTempFileName(); [IO.File]::WriteAllText($pf, $keys)
      $psi = New-Object Diagnostics.ProcessStartInfo $rg
      $rgRoots = @($roots); if ($hold) { $rgRoots += $hold }
      $psi.Arguments = '-a --hidden --no-ignore --no-config --no-messages -o --no-line-number --with-filename --null -f ' + (& $q $pf) + ' -- ' + (($rgRoots | ForEach-Object { & $q $_ }) -join ' ')
      $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
      $st.Proc = [Diagnostics.Process]::Start($psi)
      # --null ends the file name with a NUL, the one character a path can't hold. A line without
      # one is a piece of a file name that holds a newline.
      $frag = ''
      while ($null -ne ($l = $st.Proc.StandardOutput.ReadLine())) {
        $i = $l.IndexOf([char]0)
        if ($i -lt 0) { $frag += $l + '?'; continue }
        & $hit ($frag + $l.Substring(0, $i)) $l.Substring($i + 1); $frag = ''
      }
      $st.Proc.WaitForExit(); if (-not $st.Stop) { $st.RgExit = $st.Proc.ExitCode }
    } catch { if ($null -eq $st.Proc) { $st.Failed = $true } } finally { if ($pf) { Remove-Item -LiteralPath $pf -ErrorAction SilentlyContinue } }
    return
  }
  # Stopped while still listing: Listed stays false and the report says the sessions were not all checked.
  $files = Sess-List $roots $st
  if ($st.Stop) { return }
  $sorted = @($files | Sort-Object -Property @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, FullName)
  $st.Total = $sorted.Count; $st.Listed = $true
  $n = 0; $latin = [Text.Encoding]::GetEncoding(28591); $buf = New-Object char[] 1048576
  foreach ($f in $sorted) {
    if ($st.Stop) { break }
    if ($null -ne $cut -and $n -ge $cut) { break }
    $n++
    if ($f.Name.EndsWith('.zst')) { $st.Zst++; continue }
    # An empty file holds nothing and is not opened, so a pipe an older PowerShell could not tell
    # from a file never holds the check up. Never a link: Windows gives a link's own size, 0.
    if ($f.Length -eq 0 -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $st.Done++; continue }
    # Read 1 MB at a time and cut just after the last character that can't be in a key or start an
    # escape such as \n (a backslash never ends a piece), so a huge database file never loads at
    # once, a piece never ends inside a token unless one runs past 8 MB, and a stop is seen within
    # one piece.
    $sr = $null; $whole = $true
    try {
      $sr = New-Object IO.StreamReader((New-Object IO.FileStream($f.FullName, 'Open', 'Read', 'ReadWrite')), $latin)
      $carry = ''
      while (($got = $sr.Read($buf, 0, $buf.Length)) -gt 0) {
        if ($st.Stop) { $whole = $false; break }
        $t = $carry + (New-Object string($buf, 0, $got))
        $sep = $rxSep.Match($t)
        if (-not $sep.Success -and $t.Length -lt 8388608) { $carry = $t; continue }
        if ($sep.Success) {
          $at = $sep.Index + 1
          $carry = $t.Substring($at); $t = $t.Substring(0, $at)
        } else { $carry = '' }
        if ($rxPre.IsMatch($t)) { foreach ($m in $rx.Matches($t)) { & $hit $f.FullName $m.Value } }
      }
      if ($whole -and $carry.Length -gt 0 -and $rxPre.IsMatch($carry)) { foreach ($m in $rx.Matches($carry)) { & $hit $f.FullName $m.Value } }
      if ($whole) { $st.Done++ }
    } catch {
      # A pattern that ran out of time leaves the file not checked, as a stop does. Anything else
      # (no permission, a range another program has locked, a file that is gone) is a file that
      # could not be read, counted apart so the report says so.
      $timedOut = $false; $xe = $_.Exception
      while ($xe) { if ($xe -is [Text.RegularExpressions.RegexMatchTimeoutException]) { $timedOut = $true }; $xe = $xe.InnerException }
      if (-not $timedOut) { $st.Unread++ }
    } finally { if ($sr) { $sr.Dispose() } }
  }
}
$SessSt = [hashtable]::Synchronized(@{ Stop = $false; Listed = $false; Total = 0; Done = 0; Zst = 0; Unread = 0; Skipped = 0; Failed = $false; RgExit = $null; Proc = $null; Hits = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)); Seen = @{} })
$SessEngine = 'none'
$rgCmd = Get-Command -Name rg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($env:GIRD_CHECK_SESSIONS_ENGINE) { $SessEngine = $env:GIRD_CHECK_SESSIONS_ENGINE } elseif ($rgCmd) { $SessEngine = 'rg' } else { $SessEngine = 'net' }
if ($SessEngine -eq 'perl') { $SessEngine = 'net' }
if ($SessEngine -eq 'rg' -and -not $rgCmd) { $SessEngine = 'none' }
$SessPs = $null; $SessHandle = $null
if ($SessRoots.Count -gt 0 -and $SessEngine -ne 'none') {
  $rgPath = $null; if ($SessEngine -eq 'rg') { $rgPath = $rgCmd.Source }
  $cut = $null; if ($env:GIRD_CHECK_SESSIONS_STOP_AFTER -match '^[0-9]+$') { $cut = [int]$env:GIRD_CHECK_SESSIONS_STOP_AFTER }
  $SessPs = [powershell]::Create()
  [void]$SessPs.AddScript($SessWorker).AddArgument($SessRoots).AddArgument($TR_KEYS).AddArgument($KEY_STARTS).AddArgument($rgPath).AddArgument($KeyFns + $SessListFn).AddArgument($SessSt).AddArgument([int]$RxTimeout.TotalMilliseconds).AddArgument($cut).AddArgument($env:GIRD_CHECK_SESSIONS_HOLD)
  $SessHandle = $SessPs.BeginInvoke()
}
# Stops the check, or waits for it with -AllSessions.
function Sess-Stop([bool]$wait) {
  if ($null -eq $script:SessPs) { return }
  if (-not $wait) {
    $SessSt.Stop = $true
    if (-not $script:SessHandle.IsCompleted) { $SessSt.Stopped = $true; if ($SessSt.Proc) { try { $SessSt.Proc.Kill() } catch { } } }
  }
  [void]$script:SessHandle.AsyncWaitHandle.WaitOne()
  try { $script:SessPs.EndInvoke($script:SessHandle) | Out-Null } catch { }
  $script:SessPs.Dispose(); $script:SessPs = $null
}

Scan-Home $HomeDir 0
$HOME_PARTIAL = 0; if ($UnreadDirs.Count -gt 0) { $HOME_PARTIAL = 1 }
# Files worms plant in a project, from data/planted.tsv. A name only a worm uses counts on its own. A
# name projects use too (setup.mjs) counts in a project that also holds one of those, or when the file
# is the very one the sources publish the SHA-256 of; anywhere else section 2 lists it as a file to
# read ($WormLook). $WormProj holds the projects that count, each the folder holding .claude or
# .vscode: there a hook that runs such a file counts too.
function Worm-Project([string]$f) { [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($f)) }
function Planted-Rel([string]$f) { [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($f)) + '/' + [IO.Path]::GetFileName($f) }
function File-Sha256([string]$f) {
  try {
    $fs = [IO.File]::OpenRead($f)
    try { $hb = [Security.Cryptography.SHA256]::Create().ComputeHash($fs) } finally { $fs.Dispose() }
    -join ($hb | ForEach-Object { $_.ToString('x2') })
  } catch { '' }
}
$WormProj = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($f in $WormFiles) { if ($PlantedAlone -ccontains (Planted-Rel $f)) { [void]$WormProj.Add((Worm-Project $f)) } }
foreach ($f in $WormFiles) {
  $wpr = Worm-Project $f
  if (($PlantedAlone -ccontains (Planted-Rel $f)) -or $WormProj.Contains($wpr)) { continue }
  $wok = $false
  foreach ($wal in $PlantedAlone) { if (Exists (J $wpr $wal)) { $wok = $true; break } }
  if (-not $wok) { $wsh = File-Sha256 $f; if ($wsh -and (@((Planted-Sha (Planted-Rel $f)) -split ' ') -ccontains $wsh)) { $wok = $true } }
  if ($wok) { [void]$WormProj.Add($wpr) }
}
$WormHit = New-Object System.Collections.Generic.List[string]; $WormLook = New-Object System.Collections.Generic.List[string]
foreach ($f in $WormFiles) { if (($PlantedAlone -ccontains (Planted-Rel $f)) -or $WormProj.Contains((Worm-Project $f))) { $WormHit.Add($f) } else { $WormLook.Add($f) } }
$N_LOOK = $WormLook.Count
$EnvFiles = @($Found | Where-Object { [IO.Path]::GetFileName($_) -cmatch '^\.env(rc|\..*)?$' })
$AllowFiles = @(@($Found) + @($LinkSettings) | Where-Object { [IO.Path]::GetFileName($_) -cmatch '^settings(\.local)?\.json$' -and [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($_)) -ceq '.claude' })
$ProjectMcp = @($Found | Where-Object { $n = [IO.Path]::GetFileName($_); $n -ceq '.mcp.json' -or $n -ceq 'mcp.json' })
$Venvs = @($Found | Where-Object { [IO.Path]::GetFileName($_) -ceq 'pyvenv.cfg' } | ForEach-Object { [IO.Path]::GetDirectoryName($_) })

# --- 1. Coding agents --------------------------------------------------------
# name | commands | install paths | folders that change when it is used | id
$Agents = @(
  @('Claude Code', 'claude', @((J $HomeDir '.claude')), @((J $HomeDir '.claude/projects')), 'claude-code'),
  @('Claude Desktop', '', @((J $LocalAppData 'AnthropicClaude'), (J $AppData 'Claude')), @((J $AppData 'Claude')), 'claude-desktop'),
  @('Codex', 'codex', @((J $HomeDir '.codex')), @((J $HomeDir '.codex/sessions')), 'codex'),
  @('Gemini CLI', 'gemini', @((J $HomeDir '.gemini')), @((J $HomeDir '.gemini/tmp')), 'gemini-cli'),
  @('Cursor', 'cursor', @((J $LocalAppData 'Programs/cursor'), (J $HomeDir '.cursor')), @((J $AppData 'Cursor/User/workspaceStorage')), 'cursor'),
  @('Windsurf', 'windsurf', @((J $LocalAppData 'Programs/Windsurf'), (J $HomeDir '.codeium/windsurf')), @((J $AppData 'Windsurf/User/workspaceStorage')), 'windsurf'),
  @('Antigravity', 'antigravity', @((J $LocalAppData 'Programs/Antigravity')), @((J $AppData 'Antigravity/User/workspaceStorage')), 'antigravity'),
  @('GitHub Copilot CLI', 'copilot', @((J $HomeDir '.copilot')), @((J $HomeDir '.copilot')), 'copilot-cli'),
  @('OpenCode', 'opencode', @((J $HomeDir '.config/opencode'), (J $HomeDir '.local/share/opencode')), @((J $HomeDir '.local/share/opencode')), 'opencode'),
  @('Goose', 'goose', @((J $AppData 'Block/goose')), @($GooseData), 'goose'),
  @('Aider', 'aider', @(), @(), 'aider'),
  @('Cline', '', @((J $AppData 'Code/User/globalStorage/saoudrizwan.claude-dev'), (J $AppData 'Cursor/User/globalStorage/saoudrizwan.claude-dev')),
    @((J $AppData 'Code/User/globalStorage/saoudrizwan.claude-dev/tasks'), (J $AppData 'Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks')), 'cline'),
  @('Continue', '', @((J $HomeDir '.continue')), @((J $HomeDir '.continue/sessions')), 'continue')
)
$AgRows = New-Object System.Collections.Generic.List[object]
$AgentIds = New-Object System.Collections.Generic.List[string]; $AgNames = New-Object System.Collections.Generic.List[string]
$IdleNames = New-Object System.Collections.Generic.List[string]; $IdleIds = New-Object System.Collections.Generic.List[string]
$Since = [DateTime]::UtcNow.AddDays(-30)
foreach ($a in $Agents) {
  $inst = $false
  if ($a[1] -and (Has-Command $a[1])) { $inst = $true }
  foreach ($p in $a[2]) { if (Exists $p) { $inst = $true } }
  if (-not $inst) { continue }
  $AgentIds.Add($a[4]); $AgNames.Add($a[0])
  if (@($a[3]).Count -eq 0) { $st = 'installed' }
  else {
    $state = @{ Any = $false; Recent = $false }
    foreach ($p in $a[3]) { if (Is-Dir $p) { Activity $p 0 $Since $state } }
    if ($state.Recent) { $st = 'active' }
    else {
      $IdleNames.Add($a[0]); $IdleIds.Add($a[4])
      if ($state.Any) { $st = 'idle' } else { $st = 'unused' }
    }
  }
  $AgRows.Add(@($a[0], $st))
}
$N_AG = $AgentIds.Count; $N_IDLE = $IdleIds.Count
if ($N_AG -gt 0) { Progress "Found $(Plural $N_AG 'coding agent' 'coding agents'): $(First-Names $AgNames 3)" } else { Progress 'No coding agents found' }

# --- 2. MCP servers ----------------------------------------------------------
# app | client id, from the fixed list | config file
$McpFiles = @(
  @('Claude Code', 'claude-code', (J $HomeDir '.claude.json')),
  @('Claude Desktop', 'claude-desktop', (J $AppData 'Claude/claude_desktop_config.json')),
  @('Cursor', 'cursor', (J $HomeDir '.cursor/mcp.json')),
  @('Windsurf', 'windsurf', (J $HomeDir '.codeium/windsurf/mcp_config.json')),
  @('Codex', 'codex', (J $HomeDir '.codex/config.toml')),
  @('Gemini CLI', 'gemini-cli', (J $HomeDir '.gemini/settings.json')),
  @('VS Code', 'vscode', (J $AppData 'Code/User/mcp.json')),
  @('Cline', 'cline', (J $AppData 'Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json')),
  @('Cline in Cursor', 'cline', (J $AppData 'Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json')),
  @('Continue', 'continue', (J $HomeDir '.continue/config.json')),
  @('Continue', 'continue', (J $HomeDir '.continue/config.yaml')),
  @('Goose', 'goose', (J $AppData 'Block/goose/config/config.yaml')),
  @('OpenCode', 'opencode', (J $HomeDir '.config/opencode/opencode.json'))
)
$McpRows = New-Object System.Collections.Generic.List[object]
$N_MCP = 0; $N_MCP_TOKEN = 0; $McpTokFirst = ''; $N_MCP_CACHE = 0; $N_MCP_CACHEF = 0
$McpTally = @{}; $McpNames = New-Object System.Collections.Generic.List[string]; $McpTokIds = New-Object System.Collections.Generic.List[string]
$McpList = New-Object System.Collections.Generic.List[string]
foreach ($m in $McpFiles) { $McpList.Add($m[2]) }; foreach ($f in $ProjectMcp) { $McpList.Add($f) }
# Configs inside plugin catalogs and caches are counted apart: they are copies of
# other people's configs, not servers this person set up.
function Is-PluginPath([string]$f) { ($f -replace '\\', '/') -match '/\.codex/\.tmp/|/\.claude/plugins/|/\.cache/|/Library/Caches/|/node_modules/' }
function Mcp-Row([string]$who, [string]$f, [string]$cid) {
  $c = $null; $nm = @()
  if ($f.EndsWith('.toml')) {
    $t = Read-Text $f
    if ($null -ne $t) {
      $nm = @(foreach ($line in $t.Split("`n")) {
        $mm = [regex]::Match($line, '^\[mcp_servers\.(?:"([^"]+)"|([^\].]+))\]\s*$')
        if ($mm.Success) { $mm.Groups[1].Value + $mm.Groups[2].Value }
      })
      $c = $nm.Count
    }
  } elseif ($f.EndsWith('.json')) {
    $names = Json-Servers $f
    if ($null -ne $names) { $nm = @($names); $c = $nm.Count }
  } elseif ($f.EndsWith('.yaml') -or $f.EndsWith('.yml')) {
    $t = Read-Text $f
    if (-not ($null -ne $t -and $t -cmatch '(?m)^\s*(mcpServers|extensions):')) { $c = 0 }
  }
  $tok = $false
  if ((Has-Match $f $RxInline) -and (Has-RealMatch $f $RxInline)) { $tok = $true }
  if ($c -eq 0 -and $null -ne $c -and -not $tok) { return }
  if (-not ((Ids $MCP_CLIENT_IDS) -contains $cid)) { $cid = 'other' }
  $pl = Is-PluginPath $f
  if ($null -ne $c -and $pl) { $script:N_MCP_CACHE += $c; $script:N_MCP_CACHEF++ }
  elseif ($null -ne $c) {
    $script:N_MCP += $c
    if ($McpTally.ContainsKey($cid)) { $McpTally[$cid] += $c } else { $McpTally[$cid] = $c }
    foreach ($x in $nm) { $McpNames.Add($x) }
  }
  if ($tok) {
    $script:N_MCP_TOKEN++; if (-not $script:McpTokFirst) { $script:McpTokFirst = $f }
    if (-not $McpTokIds.Contains($cid)) { $McpTokIds.Add($cid) }
    Progress "Token written in an MCP config: $(Short $f)"
  }
  $McpRows.Add(@{ Who = $who; File = $f; Count = $c; Tok = $tok; Pl = $pl })
}
foreach ($m in $McpFiles) { if (Is-File $m[2]) { Mcp-Row $m[0] $m[2] $m[1] } }
foreach ($f in $ProjectMcp) {
  if (-not (Is-File $f)) { continue }
  $fs = $f -replace '\\', '/'
  if ($fs.EndsWith('/.cursor/mcp.json')) { $cid = 'cursor' } elseif ($fs.EndsWith('/.vscode/mcp.json')) { $cid = 'vscode' }
  elseif ($fs.EndsWith('/.mcp.json')) { $cid = 'claude-code' } else { $cid = 'other' }
  Mcp-Row 'Project' $f $cid
}
$McpCacheNote = ''; if ($N_MCP_CACHE -gt 0) { $McpCacheNote = ", $N_MCP_CACHE more in plugin folders" }
$McpSum = "$(Plural $N_MCP 'server' 'servers')$McpCacheNote"
if ($N_MCP -eq 0 -and $N_MCP_CACHE -gt 0) { $McpSum = "none set up, $N_MCP_CACHE in plugin folders" }

# Project settings that make an agent or editor run something, or trust the project's MCP
# servers, as soon as the folder is opened. A cloned repo brings them along (Check Point,
# CVE-2025-59536 and CVE-2026-21852; Oasis Security on Cursor's folderOpen tasks). Both
# settings.json and settings.local.json are read, since repos commit either. Each file is read as
# one line, so pretty-printed JSON matches too, with comments removed first: // to the end of the
# line and /* */, outside strings only (a \" does not end a string; a line break does, unless a \
# escapes it, as VS Code's JSONC parser reads it). tasks.json and VS Code's settings.json are
# JSONC, and a commented-out setting in any other file is not active either. One regex pass keeps
# each string and drops each comment, so the time is linear whatever the input.
$AutoRows = New-Object System.Collections.Generic.List[object]; $WormRefs = New-Object System.Collections.Generic.List[string]
$AutoSeen = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
# Worms plant a file in the folder (data/planted.tsv) and run it from a hook or a task. A command runs
# one when the file is the script an interpreter runs: the first word after node, bun, deno or tsx
# and their options, or after bun run or deno run, never the code of -e, -p, --eval or --print (an
# option word starting with e or p ends the match); when the file is the command itself; or when a
# task's command is the interpreter and its first argument the file. Each may come after ;, &, &&, |
# or ||. A rule or a guard that only names the file, or passes it to another script, does not count.
# The file may be quoted, after $CLAUDE_PROJECT_DIR, ${workspaceFolder} or ./, and must end there.
# The same expression as gird-check.sh's worm_cmd.
function Worm-Cmd([string]$name) {
  if (-not $name) { return $null }
  $cf = '(\\"|'')?((\\")?\$\{?(CLAUDE_PROJECT_DIR|workspaceFolder)\}?(\\")?[/\\]+|\.[/\\]+)?' + $name + '(\\"|["''\s;&|)])'
  $cp = '(([^\s"\\]|\\\\)*(/|\\\\))?'
  $co = '(--|--[A-DF-OQ-Za-df-oq-z0-9][^\s"\\]*|-[A-DF-OQ-Za-df-oq-z0-9]+)\s+'
  $cs = '"command"\s*:\s*"\s*(([^"\\]|\\.)*(;|&&?|\|\|?)\s*)?'
  $ci = '"command"\s*:\s*"' + $cp + '(node|bun|deno|tsx)(\.exe)?"'
  $ca = '"args"\s*:\s*\[\s*"(\$\{?(workspaceFolder|CLAUDE_PROJECT_DIR)\}?[/\\]+|\.[/\\]+)?' + $name + '"'
  $cb = '([^{}]|\{[^{}]*\})*'
  New-Object regex(($cs + $cp + '((node|tsx)(\.exe)?\s+(' + $co + ')*|(bun|deno)(\.exe)?\s+(' + $co + ')*(run\s+(' + $co + ')*)?)' + $cf + '|' + $cs + $cf + '|' + $ci + $cb + $ca + '|' + $ca + $cb + $ci), $RxOpt, $RxTimeout)
}
$RxWormAlone = Worm-Cmd $WormNameAlone; $RxWormWeak = Worm-Cmd $WormNameWeak
# Keys that make Claude Code run a command: hooks and its helper commands.
$RxHooks = New-Object regex('"hooks"\s*:\s*\{\s*"|"(apiKeyHelper|statusLine|awsAuthRefresh|awsCredentialExport|gcpAuthRefresh|otelHeadersHelper)"\s*:', $RxOpt, $RxTimeout)
$RxMcpAuto = New-Object regex('"enableAllProjectMcpServers"\s*:\s*true|"enabledMcpjsonServers"\s*:\s*\[\s*"', $RxOpt, $RxTimeout)
# An empty ANTHROPIC_BASE_URL sets nothing.
$RxBaseUrl = New-Object regex('"ANTHROPIC_BASE_URL"\s*:\s*"(?=[^"]*[^"\s])(?![A-Za-z]+://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?[/"])[^"]*"', $RxOpt, $RxTimeout)
# Claude Code before 2.1.257 took bypassPermissions from any settings file, a project's too; later
# versions take it only from the person's own or managed settings (Claude Code's settings docs).
$RxBypass = New-Object regex('"defaultMode"\s*:\s*"bypassPermissions"', $RxOpt, $RxTimeout)
$RxFolderOpen = New-Object regex('"runOn"\s*:\s*"folderOpen"', $RxOpt, $RxTimeout)
# A string (kept, group 1), a // comment, or a /* */ comment (dropped; one left open runs to the end).
$RxJsonc = New-Object regex('("(?:[^"\\\r\n]|\\[\s\S])*(?:"|(?=[\r\n])|$))|//[^\r\n]*|/\*(?:[\s\S]*?\*/|[\s\S]*)', $RxOpt, $RxTimeout)
function Flat-Text([string]$f) {
  $t = Read-Text $f; if ($null -eq $t) { return $null }
  try { $RxJsonc.Replace($t, '$1') -replace '[\r\n\t]', ' ' } catch { Mark-Slow $f; $null }
}
function Flat-Match([string]$f, [string]$t, [regex]$rx) { try { $rx.IsMatch($t) } catch { Mark-Slow $f; $false } }
# A setting of data/auto-approve.tsv in a file: every pattern must match, spaces ignored. A .json
# file is read as one line through Flat-Text (comments are its job), and a match starts at the text,
# a { or a , and ends at the text's end, a , } # or /, so a longer key or another value never counts.
# A .toml file is read line by line: a # line is skipped, a match is a whole line up to a # comment
# (so a setting inside an inline table, a profile written as one, does not count), a value in double
# quotes also matches the same value in single quotes (a TOML literal string), and only the lines
# before the first [table] count: a setting under [profiles.x] applies only when that profile is
# used, and Codex 0.134.0 and later read no such table from config.toml.
function Aa-Hit([string]$f, $pats) {
  $toml = $f.EndsWith('.toml')
  if ($toml) { $t = Read-Text $f } else { $t = Flat-Text $f }
  if ($null -eq $t) { return $false }
  $pp = @($pats | ForEach-Object { $_ -replace '\s', '' })
  $got = New-Object bool[] $pp.Count
  $lines = @($t); if ($toml) { $lines = $t.Split("`n") }
  foreach ($line in $lines) {
    $l = $line -replace '\s', ''
    if ($toml -and $l.StartsWith('#')) { continue }
    if ($toml -and $l.StartsWith('[')) { break }
    for ($i = 0; $i -lt $pp.Count; $i++) {
      if ($got[$i]) { continue }
      if ($toml) {
        foreach ($q in @($pp[$i], $pp[$i].Replace('"', "'"))) {
          if ($l.StartsWith($q, [StringComparison]::Ordinal) -and ($l.Length -eq $q.Length -or [string]$l[$q.Length] -eq '#')) { $got[$i] = $true }
        }
        continue
      }
      $k = $l.IndexOf($pp[$i], [StringComparison]::Ordinal)
      while ($k -ge 0) {
        $b = ''; if ($k -gt 0) { $b = [string]$l[$k - 1] }
        $e = $k + $pp[$i].Length; $a = ''; if ($e -lt $l.Length) { $a = [string]$l[$e] }
        $hit = (($b -eq '' -or $b -eq '{' -or $b -eq ',') -and ($a -eq '' -or ',}#/'.Contains($a)))
        if ($hit) { $got[$i] = $true; break }
        $k = $l.IndexOf($pp[$i], $k + 1, [StringComparison]::Ordinal)
      }
    }
  }
  -not ($got -contains $false)
}
function Auto-Row([string]$f, [string]$what, [string]$t) {
  # A worm file counts only when a command runs it (Worm-Cmd), and a file projects use too only in a
  # project that counts ($WormProj).
  if (($RxWormAlone -and (Flat-Match $f $t $RxWormAlone)) -or ($RxWormWeak -and $WormProj.Contains((Worm-Project $f)) -and (Flat-Match $f $t $RxWormWeak))) { $WormRefs.Add($f) }
  # A repo's worktrees carry the same settings: one row, with how many more folders have it. The
  # row names the repo's own file, whichever one the scan listed first.
  $key = $t + [char]0 + ($f -replace '[/\\]\.claude[/\\]worktrees[/\\][^/\\]+[/\\]', '/')
  if ($AutoSeen.ContainsKey($key)) {
    # The repo's own folder is the one listed, whichever the scan finds first.
    $row = $AutoSeen[$key]; $row.More = $row.More + 1
    if ($row.File -match '[/\\]\.claude[/\\]worktrees[/\\]' -and $f -notmatch '[/\\]\.claude[/\\]worktrees[/\\]') { $row.File = $f }
    return
  }
  $row = @{ File = $f; What = $what; More = 0 }
  $AutoSeen[$key] = $row; $AutoRows.Add($row); Progress "Project settings that $($what): $(Short $f)"
}
$homeClaude = J $HomeDir '.claude'
foreach ($f in $AllowFiles) {
  if ([IO.Path]::GetDirectoryName($f).Equals($homeClaude, $PathCmp) -or ($f -replace '\\', '/') -match '/\.claude/plugins/' -or -not (Is-File $f)) { continue }
  $t = Flat-Text $f; if ($null -eq $t) { continue }
  $w = New-Object System.Collections.Generic.List[string]
  if (Flat-Match $f $t $RxHooks) { $w.Add('run commands while the agent works') }
  if (Flat-Match $f $t $RxMcpAuto) { $w.Add('turn on MCP servers without asking') }
  if (Flat-Match $f $t $RxBaseUrl) { $w.Add('send the agent''s API traffic, key included, to another server') }
  if (Flat-Match $f $t $RxBypass) { $w.Add('skip permission prompts with bypassPermissions. Claude Code applies it from a project only before version 2.1.257') }
  if ($w.Count -gt 0) { Auto-Row $f ($w -join ', ') $t }
}
foreach ($f in $TaskFiles) {
  if (($f -replace '\\', '/') -match '/\.claude/plugins/') { continue }
  $t = Flat-Text $f
  if ($null -ne $t -and (Flat-Match $f $t $RxFolderOpen)) { Auto-Row $f 'run a task when the folder opens in VS Code or Cursor' $t }
}
# A project's .vscode/settings.json with "chat.tools.autoApprove": true, the setting the
# CVE-2025-53773 prompt injection made Copilot write so it could run commands without asking. VS Code
# 1.104 renamed it without migration, so current VS Code ignores it: a sign of that attack, or of an
# old VS Code, not a setting in force. A thing to look at, not an agent set to run without asking.
foreach ($f in $VscSettings) {
  if (-not (Is-File $f)) { continue }
  if (Aa-Hit $f @('"chat.tools.autoApprove": true')) {
    Auto-Row $f 'auto-approve Copilot''s tools with chat.tools.autoApprove, the setting the CVE-2025-53773 attack wrote into projects. VS Code 1.104 and later ignore it' ([string](Flat-Text $f))
  }
}
$N_AUTO = $AutoRows.Count
# Row 02 counts projects: the folders holding these settings.
$AutoProj = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($r in $AutoRows) { [void]$AutoProj.Add([IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($r.File))) }
$N_AUTO_PROJ = $AutoProj.Count

# --- 3. Keys in plain text ---------------------------------------------------
$DocsRoots = New-Object System.Collections.Generic.List[string]
$DocsRoots.Add((J $HomeDir 'Documents'))
if ($OnWindows) { try { $md = [Environment]::GetFolderPath('MyDocuments'); if ($md -and -not $DocsRoots.Contains($md)) { $DocsRoots.Add($md) } } catch { } }
$ShellRc = New-Object System.Collections.Generic.List[string]
foreach ($f in @('.zshrc', '.zprofile', '.zshenv', '.zlogin', '.bashrc', '.bash_profile', '.profile', '.config/fish/config.fish')) { $ShellRc.Add((J $HomeDir $f)) }
foreach ($d in $DocsRoots) {
  foreach ($ed in @('PowerShell', 'WindowsPowerShell')) {
    foreach ($pf in @('Microsoft.PowerShell_profile.ps1', 'profile.ps1', 'Microsoft.VSCode_profile.ps1')) { $ShellRc.Add((J $d "$ed/$pf")) }
  }
}
$ShellHist = New-Object System.Collections.Generic.List[string]
foreach ($f in @('.zsh_history', '.bash_history', '.local/share/fish/fish_history', '.python_history', '.node_repl_history')) { $ShellHist.Add((J $HomeDir $f)) }
# PSReadLine keeps one history file per host: ConsoleHost_history.txt, and one each for VS Code and others.
$PsrlDir = J $AppData 'Microsoft/Windows/PowerShell/PSReadLine'
if (Is-Dir $PsrlDir) { try { foreach ($f in ([IO.Directory]::GetFiles($PsrlDir, '*_history.txt') | Sort-Object)) { $ShellHist.Add($f) } } catch { } }
$ProjectFiles = @($EnvFiles) + @($ProjectMcp)
$Candidates = New-Object System.Collections.Generic.List[string]
$cset = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$cands = @($ShellRc) + @((J $HomeDir '.env'), (J $HomeDir '.envrc')) + @($ShellHist) + @(
  '.claude.json', '.claude/settings.json', '.claude/settings.local.json', '.codex/config.toml', '.gemini/settings.json', '.gemini/.env',
  '.cursor/mcp.json', '.codeium/windsurf/mcp_config.json', '.continue/config.json', '.continue/config.yaml', '.config/goose/config.yaml',
  '.config/opencode/opencode.json', '.aider.conf.yml' | ForEach-Object { J $HomeDir $_ }) +
  @((J $AppData 'Block/goose/config/config.yaml'), (J $AppData 'Claude/claude_desktop_config.json')) + $ProjectFiles
foreach ($f in $cands) { if ($f -and $cset.Add($f)) { $Candidates.Add($f) } }

function In-List([string]$f, $list) { foreach ($x in $list) { if ($f.Equals($x, $PathCmp)) { return $true } }; $false }
function Under([string]$f, [string]$dir) { $f.StartsWith($dir + $Sep, $PathCmp) }
$AgentDirs = @('.claude', '.codex', '.gemini', '.cursor', '.codeium', '.continue', '.copilot', '.config/goose', '.config/opencode', '.local/share/opencode' | ForEach-Object { J $HomeDir $_ }) +
  @((J $AppData 'Block/goose'), (J $AppData 'Claude'))
function Key-Place([string]$f) {
  if (In-List $f $ShellRc) { return 'shell_rc' }
  if (In-List $f $ShellHist) { return 'shell_history' }
  if ([IO.Path]::GetFileName($f) -cmatch '^\.env(rc|\..*)?$') { return 'env_file' }
  if (In-List $f $McpList) { return 'mcp_config' }
  foreach ($d in $AgentDirs) { if (Under $f $d) { return 'agent_config' } }
  if ($f.StartsWith((J $HomeDir '.aider'), $PathCmp)) { return 'agent_config' }
  if (In-List $f $ProjectFiles) { return 'project_file' }
  'other'
}
$KeyRows = New-Object System.Collections.Generic.List[object]
$KEY_FILES = 0; $HIST_KEYS = 0; $ProvIds = New-Object System.Collections.Generic.List[string]; $KeyFirst = $null
$KeyPlaces = New-Object System.Collections.Generic.List[string]; $ProvTally = New-Object System.Collections.Generic.List[string]
# A file that is there but can't be read (a root-owned .env a container wrote, a file made 000, one
# another program holds open) was not checked: section 3 names it and the check is partial, never
# "no keys". A link to nothing is not one, as in gird-check.sh.
$KeyUnread = New-Object System.Collections.Generic.List[string]
foreach ($f in $Candidates) {
  if (-not (Has-Match $f $RxKeys)) {
    if ((Is-File $f) -and $null -eq (Read-Text $f) -and (Is-RegularFile $f)) { $KeyUnread.Add($f) }
    continue
  }
  $p = @(Providers-In $f)
  if ($p.Count -eq 0) { continue }
  $ptxt = $p -join ', '
  $KEY_FILES++; if ($null -eq $KeyFirst) { $KeyFirst = @($f, $ptxt) }
  Progress "Key in plain text: $(Short $f) ($ptxt)"
  $kp = Key-Place $f; $KeyPlaces.Add($kp)
  if ($kp -eq 'shell_history') { $HIST_KEYS++ }
  foreach ($nm in $p) {
    $id = Provider-Id $nm
    if (-not $ProvIds.Contains($id)) { $ProvIds.Add($id) }
    $ProvTally.Add($id)
  }
  $KeyRows.Add(@($f, $ptxt))
}
if ($KEY_FILES -eq 0 -and $KeyUnread.Count -gt 0) { Progress "No keys in the files read, but $(Plural $KeyUnread.Count 'file' 'files') could not be read" }
elseif ($KEY_FILES -eq 0) { Progress 'No keys in shell profiles, history, agent configs or .env files' }

# Login files any agent you run can read.
$Logins = New-Object System.Collections.Generic.List[string]; $LoginIds = New-Object System.Collections.Generic.List[string]
function Login($paths, [string]$label, [string]$id, [string]$marker = '') {
  foreach ($f in @($paths)) {
    if (-not (Is-File $f)) { continue }
    if ($marker) { $t = Read-Text $f; if ($null -eq $t -or -not ($t -cmatch $marker)) { continue } }
    $Logins.Add($label); $LoginIds.Add($id); return
  }
}
Login (J $HomeDir '.aws/credentials') 'AWS keys' 'aws'
Login @((J $AppData 'gcloud/application_default_credentials.json'), (J $HomeDir '.config/gcloud/application_default_credentials.json')) 'Google Cloud login' 'gcloud'
Login (J $HomeDir '.azure/msal_token_cache.json') 'Azure login' 'azure'
Login (J $HomeDir '.kube/config') 'Kubernetes logins' 'kube'
Login (J $HomeDir '.docker/config.json') 'Docker registry logins' 'docker' '"auth"\s*:\s*"[A-Za-z0-9+/=]{8,}'
Login (J $HomeDir '.npmrc') 'npm token' 'npm' '_authToken'
Login (J $HomeDir '.netrc') 'saved passwords in .netrc' 'netrc'
if (-not $LoginIds.Contains('netrc')) { Login (J $HomeDir '_netrc') 'saved passwords in _netrc' 'netrc' }
Login (J $HomeDir '.git-credentials') 'saved Git passwords' 'git-credentials'
Login @((J $AppData 'GitHub CLI/hosts.yml'), (J $HomeDir '.config/gh/hosts.yml')) 'GitHub CLI token' 'gh' 'oauth_token'
Login (J $HomeDir '.pypirc') 'PyPI token' 'pypi' 'password'
Login (J $HomeDir '.codex/auth.json') 'Codex login' 'codex'
Login (J $HomeDir '.claude/.credentials.json') 'Claude Code login' 'claude-code'
Login (J $HomeDir '.gemini/oauth_creds.json') 'Gemini CLI login' 'gemini'
Login (J $HomeDir '.local/share/opencode/auth.json') 'OpenCode provider keys' 'opencode'
Login (J $HomeDir '.railway/config.json') 'Railway login' 'railway'
$N_SSH = 0; $N_SSH_OPEN = 0
$SshDir = J $HomeDir '.ssh'
if (Is-Dir $SshDir) {
  foreach ($e in (Entries $SshDir)) {
    if ((Is-DirInfo $e)) { continue }
    $n = $e.Name
    if ($n.EndsWith('.pub') -or $n.Contains('known_hosts') -or $n.EndsWith('config') -or $n.Contains('authorized_keys')) { continue }
    $t = Read-Text $e.FullName
    if ($null -eq $t -or -not $t.Contains('PRIVATE KEY-----')) { continue }
    $N_SSH++
    if ($t.Contains('ENCRYPTED')) { }
    elseif ($t.Contains('b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ') -or $t -cmatch 'BEGIN (RSA|EC|DSA) PRIVATE KEY|BEGIN PRIVATE KEY') { $N_SSH_OPEN++ }
  }
}
if ($N_SSH -gt 0) {
  $s = Plural $N_SSH 'SSH private key' 'SSH private keys'
  if ($N_SSH_OPEN -gt 0) { $s = "$s, $N_SSH_OPEN with no passphrase" }
  $Logins.Add($s); $LoginIds.Add('ssh')
}
$N_LOGIN = $LoginIds.Count
$LoginsText = $Logins -join ', '
if ($LoginsText) { Progress "Login files any agent you run can read: $LoginsText" }

# --- 4. Keys saved in Claude Code allow lists -------------------------------
$AllowRows = New-Object System.Collections.Generic.List[object]; $N_ALLOW = 0; $N_ALLOW_NPM = 0; $AllowFirst = ''
$allowAll = @(@($AllowFiles) + @((J $HomeDir '.claude/settings.json'), (J $HomeDir '.claude/settings.local.json')) | Where-Object { $_ } | Sort-Object -Unique -CaseSensitive)
foreach ($f in $allowAll) {
  if (-not (Is-File $f)) { continue }
  if (-not (Has-RealMatch $f $RxCommand)) { continue }
  $N_ALLOW++; if (-not $AllowFirst) { $AllowFirst = $f }
  Progress "Saved Claude Code command with a key: $(Short $f)"
  $marker = $Sep + '.claude' + $Sep
  $npm = Npm-WouldShip $f.Substring(0, $f.LastIndexOf($marker))
  if ($npm) { $N_ALLOW_NPM++ }
  $AllowRows.Add(@($f, $npm))
}

# --- 5. Recent key leaks -----------------------------------------------------
# Folders that hold Python environments. Fixed install locations are read by name;
# the rest are searched a few levels deep, skipping node_modules.
$SitesAll = New-Object System.Collections.Generic.List[string]
foreach ($s in $Sites) { $SitesAll.Add($s) }
foreach ($v in $Venvs) { Find-Sites $v 0 4 $SitesAll }
$pyParents = New-Object System.Collections.Generic.List[object]
$pyParents.Add(@((J $LocalAppData 'Programs/Python'), 'Python3*', 'Lib/site-packages'))
$pyParents.Add(@((J $AppData 'Python'), 'Python3*', 'site-packages'))
foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:SystemDrive)) {
  if ($pf) { $pyParents.Add(@(($pf.TrimEnd('\', '/')), 'Python3*', 'Lib/site-packages')) }
}
foreach ($pp in $pyParents) {
  foreach ($d in (Glob-Dirs $pp[0] $pp[1])) { $sp = J $d $pp[2]; if (Is-Dir $sp) { $SitesAll.Add($sp) } }
}
foreach ($d in (Glob-Dirs (J $LocalAppData 'Packages') 'PythonSoftwareFoundation.Python.3*')) {
  foreach ($d2 in (Glob-Dirs (J $d 'LocalCache/local-packages') 'Python3*')) { $sp = J $d2 'site-packages'; if (Is-Dir $sp) { $SitesAll.Add($sp) } }
}
$PyRoots = @('.pyenv/pyenv-win/versions', 'miniconda3', 'miniforge3', 'anaconda3', '.conda', '.virtualenvs', 'Envs', '.local/pipx', 'pipx' | ForEach-Object { J $HomeDir $_ }) +
  @((J $LocalAppData 'pipx'), (J $AppData 'uv'), (J $LocalAppData 'miniconda3'), (J $LocalAppData 'anaconda3'))
if ($env:ProgramData) { $PyRoots += @((J $env:ProgramData 'miniconda3'), (J $env:ProgramData 'anaconda3')) }
foreach ($r in $PyRoots) { if (Is-Dir $r) { Find-Sites $r 0 6 $SitesAll } }
$SitesAll = @($SitesAll | Sort-Object -Unique -CaseSensitive)
# >>> incidents: generated from data/incidents.tsv by tools/gen.sh. Edit that file, then run it.
function Npm-Label([string]$t) { switch ($t) { 'axios' { 'Axios takeover, March 2026' } 'tanstack' { 'TanStack worm, May 2026' } 'mistral' { 'Mistral AI npm packages, May 2026' } 'uipath' { 'UiPath npm packages, May 2026' } 'mistralpy' { 'mistralai 2.4.6, May 2026' } 'guardrails' { 'guardrails-ai 0.10.1, May 2026' } 'opensearch' { 'OpenSearch client, May 2026' } 'bitwarden' { 'Bitwarden CLI, April 2026' } 'mastra' { 'Mastra npm packages, June 2026' } 'keyv' { 'keyv worm, August 2026' } 'keyvscope' { 'keyv account takeover, August 2026' } 'sandworm' { 'SANDWORM_MODE worm, February 2026' } 'sandsleep' { 'SANDWORM_MODE sleeper packages, February 2026' } 'tensorlake' { 'tensorlake package, October 2026' } 'litellm' { 'LiteLLM 1.107.0, October 2026' } 'opencode' { 'OpenCode Console, October 2026' } 'railway' { 'Railway, October 2026' } 'zeabur' { 'Zeabur, October 2026' } 'glassworm' { 'GlassWorm extensions, January 2026' } 'glasswormmar' { 'GlassWorm extensions, March 2026' } 'glasswormvsix' { 'GlassWorm sleeper extensions, March 2026' } 'glasswormapr' { 'GlassWorm sleeper extensions, April 2026' } 'glasswormoct' { 'GlassWorm-linked themes, October 2026' } 'injective' { 'Injective SDK, July 2026' } default { $t } } }
function Incident-Line([string]$t) { switch ($t) { 'axios' { 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it. cisa.gov' } 'tanstack' { 'TanStack worm, May 2026: stole cloud, GitHub, npm and SSH credentials on install, then republished itself. github.com' } 'mistral' { 'Mistral AI npm packages, May 2026: published with malware Mistral says could not run, as its setup script names a missing file. docs.mistral.ai' } 'uipath' { 'UiPath npm packages, May 2026: published with malware that a bug in its payload kept from working, Wiz says. wiz.io' } 'mistralpy' { 'mistralai 2.4.6, May 2026: started a credential stealer in the background when imported on Linux. docs.mistral.ai' } 'guardrails' { 'guardrails-ai 0.10.1, May 2026: downloaded and ran a credential stealer, on Linux only. wiz.io' } 'opensearch' { 'OpenSearch client, May 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' } 'bitwarden' { 'Bitwarden CLI, April 2026: stole SSH keys, npm, GitHub and cloud credentials, and AI tool configs. stepsecurity.io' } 'mastra' { 'Mastra npm packages, June 2026: pulled in malware that started at login and sent browser history to the attackers. socket.dev' } 'keyv' { 'keyv worm, August 2026: stole cloud, GitHub and npm credentials, and planted hooks that run when repos open. socket.dev' } 'keyvscope' { 'keyv account takeover, August 2026: published from the compromised keyv account, and the GitHub advisory says to treat a machine that installed one as compromised. github.com' } 'sandworm' { 'SANDWORM_MODE worm, February 2026: stole credentials and AI provider keys, and added an MCP server to AI assistants. socket.dev' } 'sandsleep' { 'SANDWORM_MODE sleeper packages, February 2026: published by the SANDWORM_MODE attackers with no malware in them yet, Socket says. socket.dev' } 'tensorlake' { 'tensorlake package, October 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' } 'litellm' { 'LiteLLM 1.107.0, October 2026: stole credentials and loaded remote-code execution tools on machines that installed it. docs.litellm.ai' } 'opencode' { 'OpenCode Console, October 2026: exposed AI provider keys saved in Console workspaces; users reported charges on them. techcrunch.com' } 'railway' { 'Railway, October 2026: an attacker may have accessed encrypted environment variables and obtained the decrypted contents of some. blog.railway.com' } 'zeabur' { 'Zeabur, October 2026: an attacker read environment variables and secrets stored on the platform. zeabur.com' } 'glassworm' { 'GlassWorm extensions, January 2026: stole SSH keys, cloud and npm credentials, keychains and crypto wallets from Macs. socket.dev' } 'glasswormmar' { 'GlassWorm extensions, March 2026: ran attacker code in memory that could reach local credentials, tokens and secrets. socket.dev' } 'glasswormvsix' { 'GlassWorm sleeper extensions, March 2026: installed a malicious extension from GitHub into every editor it found. socket.dev' } 'glasswormapr' { 'GlassWorm sleeper extensions, April 2026: updated cloned extensions to install malware from GitHub into VS Code, Cursor and Windsurf. socket.dev' } 'glasswormoct' { 'GlassWorm-linked themes, October 2026: VS Code themes that ran hidden loaders, one of them tied to GlassWorm. socket.dev' } 'injective' { 'Injective SDK, July 2026: sent the seed phrase or private key of any wallet an app created or imported with it. github.com' } default { $t } } }
function Incident-Level([string]$t) { switch ($t) { 'mistral' { 'update' } 'uipath' { 'update' } 'sandsleep' { 'update' } 'opencode' { 'leak' } 'railway' { 'leak' } 'zeabur' { 'leak' } 'injective' { 'update' } default { 'act' } } }
function Incident-Name([string]$t) { switch ($t) { 'axios' { 'Axios takeover' } 'tanstack' { 'TanStack worm' } 'mistral' { 'Mistral AI npm packages' } 'uipath' { 'UiPath npm packages' } 'mistralpy' { 'mistralai 2.4.6' } 'guardrails' { 'guardrails-ai 0.10.1' } 'opensearch' { 'OpenSearch client' } 'bitwarden' { 'Bitwarden CLI' } 'mastra' { 'Mastra npm packages' } 'keyv' { 'keyv worm' } 'keyvscope' { 'keyv account takeover' } 'sandworm' { 'SANDWORM_MODE worm' } 'sandsleep' { 'SANDWORM_MODE sleeper packages' } 'tensorlake' { 'tensorlake package' } 'litellm' { 'LiteLLM 1.107.0' } 'opencode' { 'OpenCode Console' } 'railway' { 'Railway' } 'zeabur' { 'Zeabur' } 'glassworm' { 'GlassWorm extensions' } 'glasswormmar' { 'GlassWorm extensions' } 'glasswormvsix' { 'GlassWorm sleeper extensions' } 'glasswormapr' { 'GlassWorm sleeper extensions' } 'glasswormoct' { 'GlassWorm-linked themes' } 'injective' { 'Injective SDK' } default { $t } } }
function Incident-Source([string]$t) { switch ($t) { 'axios' { 'www.cisa.gov/news-events/alerts/2026/04/20/supply-chain-compromise-impacts-axios-node-package-manager' } 'tanstack' { 'github.com/advisories/GHSA-g7cv-rxg3-hmpx' } 'mistral' { 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' } 'uipath' { 'www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised' } 'mistralpy' { 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' } 'guardrails' { 'www.wiz.io/blog/mini-shai-hulud-strikes-again-tanstack-more-npm-packages-compromised' } 'opensearch' { 'github.com/advisories/GHSA-298w-vvm4-ww55' } 'bitwarden' { 'www.stepsecurity.io/blog/bitwarden-cli-hijacked-on-npm-bun-staged-credential-stealer-targets-developers-github-actions-and-ai-tools' } 'mastra' { 'socket.dev/blog/mastra-npm-packages-compromised' } 'keyv' { 'socket.dev/blog/popular-npm-packages-in-the-keyv-and-cacheable-namespaces-compromised-in-active-supply-chain' } 'keyvscope' { 'github.com/advisories/GHSA-q99r-cjmf-3xrf' } 'sandworm' { 'socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning' } 'sandsleep' { 'socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning' } 'tensorlake' { 'github.com/advisories/GHSA-rqxj-g25x-4v9v' } 'litellm' { 'docs.litellm.ai/blog/security-incident-oct-21-2026' } 'opencode' { 'techcrunch.com/2026/10/19/hackers-hit-ai-coding-tool-opencode-running-up-charges-on-users-ai-accounts/' } 'railway' { 'blog.railway.com/p/security-disclosure-wednesday-october-21st' } 'zeabur' { 'zeabur.com/blogs/october-2026-security-incident' } 'glassworm' { 'socket.dev/blog/glassworm-loader-hits-open-vsx-via-suspected-developer-account-compromise' } 'glasswormmar' { 'socket.dev/blog/open-vsx-transitive-glassworm-campaign' } 'glasswormvsix' { 'socket.dev/blog/glassworm-sleeper-extensions-activated-on-open-vsx' } 'glasswormapr' { 'socket.dev/blog/73-open-vsx-sleeper-extensions-glassworm' } 'glasswormoct' { 'socket.dev/blog/glassworm-vscode-themes' } 'injective' { 'github.com/advisories/GHSA-5fc4-fm2x-6f4r' } default { $t } } }
function Incident-Advice([string]$t) { switch ($t) { 'keyvscope' { 'Rotate the secrets this machine held from another computer, as the GitHub advisory says, then pin each @keyv package listed in section 5 to its version before 6.0.0.' } 'sandsleep' { 'Uninstall the SANDWORM_MODE sleeper packages listed in section 5: the attackers published every version of them.' } 'glassworm' { 'On a Mac, also check ~/Library/LaunchAgents for unfamiliar plists such as com.user.nodestart.plist, and look for /tmp/ijewf and /tmp/out.zip, where the malware collects what it steals.' } 'glasswormvsix' { 'Also check every editor you use, VS Code included, for extensions you did not install yourself: this malware installs one from GitHub into each editor it finds.' } 'glasswormapr' { 'Also check every editor you use, VS Code included, for extensions you did not install yourself: this malware installs one from GitHub into each editor it finds.' } 'injective' { 'Move the funds out of any wallet created or imported with Injective SDK 1.20.21, into a new wallet.' } default { '' } } }
function Incident-Summary([string]$t) { switch ($t) { 'injective' { 'Injective SDK: move the funds out of its wallets' } default { '' } } }
# <<< incidents
# >>> bad-pypi: generated from data/bad-pypi.tsv by tools/gen.sh. Edit that file, then run it.
$BadPypi = @'
litellm 1.107.0 litellm all
mistralai 2.4.6 mistralpy linux
guardrails_ai 0.10.1 guardrails linux
'@
$PyIncidents = @('litellm', 'mistralpy', 'guardrails')
# <<< bad-pypi
# >>> indicators: generated from data/indicators.tsv by tools/gen.sh. Edit that file, then run it.
$IndTable = @(
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir 'Library/LaunchAgents/com.user.gh-token-monitor.plist'), '-')
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir '.config/systemd/user/gh-token-monitor.service'), '-')
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir '.local/bin/gh-token-monitor.sh'), '-')
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir '.config/gh-token-monitor'), '-')
  ,@('tanstack', 'all', 'wiper', 'yes', '/tmp/gh-token-monitor.out.log', '-')
  ,@('tanstack', 'all', 'wiper', 'yes', '/tmp/gh-token-monitor.err.log', '-')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir 'Library/LaunchAgents/com.nvm.protocal.plist'), 'starts the Mastra malware at login')
  ,@('glassworm', 'all', 'startup', 'no', (J $HomeDir 'Library/LaunchAgents/com.user.nodestart.plist'), 'starts the GlassWorm malware at login')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir 'Library/NodePackages/protocal.cjs'), 'starts the Mastra malware at login')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir '.config/systemd/user/nvmconf.service'), 'starts the Mastra malware at login')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir '.config/systemd/nvmconf/protocal.cjs'), 'starts the Mastra malware at login')
  ,@('mastra', 'win', 'startup', 'no', $(if ($env:ProgramData) { J $env:ProgramData 'NodePackages/protocal.cjs' } else { '' }), 'starts the Mastra malware at login')
  ,@('litellm', 'all', 'site', 'no', 'cook.pth', '-')
  ,@('litellm', 'all', 'site', 'no', 'cook.py', '-')
  ,@('litellm', 'all', 'temp', 'yes', 'remote_code_loader.lock', 'These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don''t run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.')
  ,@('litellm', 'all', 'temp', 'yes', '.pc_once_*', 'These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don''t run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.')
  ,@('litellm', 'all', 'temp', 'yes', '.pc_sq_*', 'These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don''t run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.')
  ,@('litellm', 'all', 'temp', 'yes', '.pc_e_*', 'These files mean the malware ran and sent data out, LiteLLM says: rotate what that environment could reach, and kill the detached python process that holds remote_code_loader.lock. Don''t run Python or pip in the environment that had litellm 1.107.0 until cook.pth, cook.py, sitecustomize.py and their compiled copies in __pycache__ are deleted from it.')
  ,@('mistralpy', 'linux', 'temp', 'yes', 'transformers.pyz', 'Kill any python process started from transformers.pyz, then delete the file.')
)
# <<< indicators
if ($OnWindows) { $IndOs = 'win' } elseif (Is-Dir '/System/Library/CoreServices') { $IndOs = 'mac' } else { $IndOs = 'linux' }
$IndOn = @($IndTable | Where-Object { $_[1] -eq 'all' -or $_[1] -eq $IndOs })
# Rows are name, version, incident and os: where the version's malware could run.
$BadPypiRows = @($BadPypi -split "`r?`n" | ForEach-Object { , @($_ -split ' ') } | Where-Object { $_.Count -ge 4 })
# Python incidents (data/bad-pypi.tsv and the site and temp lines of data/indicators.tsv). $LiteBad
# and $Marks hold @(incident, what was found); $PyUpd holds @(incident, os, what was found) for a bad
# version installed where its malware could not run (bad-pypi's os column): a version to update, not
# a compromised machine. The hit incidents' first words make "the LiteLLM malware".
function Py-Short($ids) { # the first word of each incident's name, as "A, B and C"
  $w = @($ids | ForEach-Object { (Incident-Name $_).Split(' ')[0] })
  if ($w.Count -le 1) { $w -join '' } else { ($w[0..($w.Count - 2)] -join ', ') + ' and ' + $w[$w.Count - 1] }
}
# The advice shown under an incident's row when its temp files are found: the note of its temp lines.
function Temp-Advice([string]$pi) { foreach ($r in $IndTable) { if ($r[0] -ceq $pi -and $r[2] -eq 'temp') { return $r[5] } }; '' }
Progress "Checking $(Plural $SitesAll.Count 'Python environment' 'Python environments') for the $(Py-Short $PyIncidents) malware"
$N_PY = 0; $N_LITE = 0; $LiteVers = New-Object System.Collections.Generic.List[string]
$LiteBad = New-Object System.Collections.Generic.List[object]; $LitePyc = New-Object System.Collections.Generic.List[string]
$PyUpd = New-Object System.Collections.Generic.List[object]
foreach ($sp in $SitesAll) {
  if (-not (Is-Dir $sp)) { continue }
  $N_PY++
  # The installed LiteLLM versions, shown on a clean row and counted in litellm_installed.
  foreach ($d in (Glob-Dirs $sp 'litellm-*.dist-info')) {
    $v = [regex]::Replace(([IO.Path]::GetFileName($d) -replace '^litellm-', '' -replace '\.dist-info$', ''), '[\x00-\x1f\x7f-\x9f]', '?')
    $N_LITE++; if (-not $LiteVers.Contains($v)) { $LiteVers.Add($v) }
  }
  foreach ($pi in $PyIncidents) {
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($r in $BadPypiRows) {
      if ($r[2] -cne $pi -or -not (Is-Dir (J $sp "$($r[0])-$($r[1]).dist-info"))) { continue }
      # Where its malware could not run (the os column), the version is one to update, not a hit.
      if ($r[3] -eq 'all' -or $r[3] -eq $IndOs) { $bad.Add("$($r[0]) $($r[1])") } else { $PyUpd.Add(@($pi, $r[3], "$(Short $sp): $($r[0]) $($r[1])")) }
    }
    foreach ($r in $IndOn) { if ($r[2] -eq 'site' -and $r[0] -ceq $pi -and (Is-File (J $sp $r[4]))) { $bad.Add($r[4]) } }
    if ($bad.Count -gt 0) { $LiteBad.Add(@($pi, "$(Short $sp): $($bad -join ', ')")) }
  }
  # cook.pyc stays code: a compiled leftover is only a possible sign, with its own row and fix.
  $pyc = @(); try { if (Is-Dir (J $sp '__pycache__')) { $pyc = @([IO.Directory]::GetFiles((J $sp '__pycache__'), 'cook.*.pyc')) } } catch { }
  if ($pyc.Count -gt 0) { $LitePyc.Add("$(Short $sp): cook.pyc") }
}
$Marks = New-Object System.Collections.Generic.List[object]
foreach ($t in $TempDirs) {
  if (-not (Is-Dir $t)) { continue }
  foreach ($r in $IndOn) {
    if ($r[2] -ne 'temp') { continue }
    # Not $found: variable names ignore case, and $Found is the home scan's list of files.
    $tempHits = @()
    if ($r[4].EndsWith('*')) { try { $tempHits = @([IO.Directory]::GetFileSystemEntries($t, $r[4]) | Sort-Object) } catch { } }
    elseif (Exists (J $t $r[4])) { $tempHits = @((J $t $r[4])) }
    foreach ($m in $tempHits) {
      # Another user's file in the shared /tmp is not this person's sign (owner yes in
      # data/indicators.tsv), and nor is one linked, symbolically or hard, under a marker's name;
      # %TEMP% on Windows is the person's own folder.
      if ($r[3] -eq 'yes' -and -not $OnWindows -and (-not (Owns-File $m) -or (Multi-Name $m))) { continue }
      $Marks.Add(@($r[0], $m))
    }
  }
}
# An environment variable and a running process are not files, so these stay code (the issue
# LiteLLM's advisory links, BerriAI/litellm#47826, names both). The hourly loader that holds
# remote_code_loader.lock only runs on macOS and Linux.
if ($env:PRIVCOLLECT_ACTIVE) { $Marks.Add(@('litellm', 'PRIVCOLLECT_ACTIVE is set in this shell')) }
$LOADER = 0
# A bad version in uv's cache: the row of each one found, in the list's order. The cache is walked
# once, for every version at once; the exact version only, so 2.4.6 is not 2.4.60 or 2.4.6.post1.
$uvWant = @(); foreach ($r in $BadPypiRows) { $uvWant += ('^' + [regex]::Escape("$($r[0])-$($r[1])") + '(-.*|\.dist-info|\.tar\.gz|\.zip)?$') }
$uvFound = @{}
foreach ($uv in @((J $LocalAppData 'uv/cache'), (J $HomeDir '.cache/uv'))) {
  if ($uvFound.Count -ge $uvWant.Count -or -not (Is-Dir $uv)) { continue }
  try {
    $q = New-Object System.Collections.Generic.Queue[object]; $q.Enqueue(@($uv, 0))
    while ($q.Count -gt 0 -and $uvFound.Count -lt $uvWant.Count) {
      $it = $q.Dequeue()
      foreach ($e in (Entries $it[0])) {
        for ($i = 0; $i -lt $uvWant.Count; $i++) { if (-not $uvFound.ContainsKey($i) -and $e.Name -cmatch $uvWant[$i]) { $uvFound[$i] = $true } }
        if ((Is-DirInfo $e) -and -not (Is-Link $e) -and $it[1] + 1 -lt 6) { $q.Enqueue(@($e.FullName, ($it[1] + 1))) }
      }
    }
  } catch { }
}
$UvBad = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $BadPypiRows.Count; $i++) { if ($uvFound.ContainsKey($i)) { $UvBad.Add($BadPypiRows[$i]) } }
$PyHits = New-Object System.Collections.Generic.List[string]
foreach ($pi in $PyIncidents) {
  $hit = $pi -eq 'litellm' -and $LOADER -eq 1
  foreach ($l in $LiteBad) { if ($l[0] -ceq $pi) { $hit = $true } }
  foreach ($l in $Marks) { if ($l[0] -ceq $pi) { $hit = $true } }
  if ($hit) { $PyHits.Add($pi) }
}
$PY_HIT = 0; if ($PyHits.Count -gt 0) { $PY_HIT = 1 }
# A bad version installed where its malware could not run: a version to update (yellow), with no
# part in PY_HIT, the score or the card's py.
$PY_UPD_HIT = 0; if ($PyUpd.Count -gt 0) { $PY_UPD_HIT = 1 }
# litellm_found and the card's ll stay LiteLLM's own; the card's py is any other Python incident.
$LITELLM_HIT = 0; if ($PyHits -contains 'litellm') { $LITELLM_HIT = 1 }
$PY_OTHER = 0; if (@($PyHits | Where-Object { $_ -cne 'litellm' }).Count -gt 0) { $PY_OTHER = 1 }
$PyShort = Py-Short $PyHits
if ($PY_HIT -eq 1) { Progress "Signs of the $PyShort malware found" }
elseif ($LitePyc.Count -gt 0) { Progress 'A leftover cook.pyc may come from the LiteLLM malware' }
elseif ($PY_UPD_HIT -eq 1) { Progress 'A Python package to update: its malware could not run on this OS' }
# >>> bad-npm: generated from data/bad-npm.tsv by tools/gen.sh. Edit that file, then run it.
$BadNpm = @'
axios 1.14.1 axios
axios 0.30.4 axios
plain-crypto-js * axios
@tanstack/arktype-adapter 1.166.12 tanstack
@tanstack/arktype-adapter 1.166.15 tanstack
@tanstack/eslint-plugin-router 1.161.9 tanstack
@tanstack/eslint-plugin-router 1.161.12 tanstack
@tanstack/eslint-plugin-start 0.0.4 tanstack
@tanstack/eslint-plugin-start 0.0.7 tanstack
@tanstack/history 1.161.9 tanstack
@tanstack/history 1.161.12 tanstack
@tanstack/nitro-v2-vite-plugin 1.154.12 tanstack
@tanstack/nitro-v2-vite-plugin 1.154.15 tanstack
@tanstack/react-router 1.169.5 tanstack
@tanstack/react-router 1.169.8 tanstack
@tanstack/react-router-devtools 1.166.16 tanstack
@tanstack/react-router-devtools 1.166.19 tanstack
@tanstack/react-router-ssr-query 1.166.15 tanstack
@tanstack/react-router-ssr-query 1.166.18 tanstack
@tanstack/react-start 1.167.68 tanstack
@tanstack/react-start 1.167.71 tanstack
@tanstack/react-start-client 1.166.51 tanstack
@tanstack/react-start-client 1.166.54 tanstack
@tanstack/react-start-rsc 0.0.47 tanstack
@tanstack/react-start-rsc 0.0.50 tanstack
@tanstack/react-start-server 1.166.55 tanstack
@tanstack/react-start-server 1.166.58 tanstack
@tanstack/router-cli 1.166.46 tanstack
@tanstack/router-cli 1.166.49 tanstack
@tanstack/router-core 1.169.5 tanstack
@tanstack/router-core 1.169.8 tanstack
@tanstack/router-devtools 1.166.16 tanstack
@tanstack/router-devtools 1.166.19 tanstack
@tanstack/router-devtools-core 1.167.6 tanstack
@tanstack/router-devtools-core 1.167.9 tanstack
@tanstack/router-generator 1.166.45 tanstack
@tanstack/router-generator 1.166.48 tanstack
@tanstack/router-plugin 1.167.38 tanstack
@tanstack/router-plugin 1.167.41 tanstack
@tanstack/router-ssr-query-core 1.168.3 tanstack
@tanstack/router-ssr-query-core 1.168.6 tanstack
@tanstack/router-utils 1.161.11 tanstack
@tanstack/router-utils 1.161.14 tanstack
@tanstack/router-vite-plugin 1.166.53 tanstack
@tanstack/router-vite-plugin 1.166.56 tanstack
@tanstack/solid-router 1.169.5 tanstack
@tanstack/solid-router 1.169.8 tanstack
@tanstack/solid-router-devtools 1.166.16 tanstack
@tanstack/solid-router-devtools 1.166.19 tanstack
@tanstack/solid-router-ssr-query 1.166.15 tanstack
@tanstack/solid-router-ssr-query 1.166.18 tanstack
@tanstack/solid-start 1.167.65 tanstack
@tanstack/solid-start 1.167.68 tanstack
@tanstack/solid-start-client 1.166.50 tanstack
@tanstack/solid-start-client 1.166.53 tanstack
@tanstack/solid-start-server 1.166.54 tanstack
@tanstack/solid-start-server 1.166.57 tanstack
@tanstack/start-client-core 1.168.5 tanstack
@tanstack/start-client-core 1.168.8 tanstack
@tanstack/start-fn-stubs 1.161.9 tanstack
@tanstack/start-fn-stubs 1.161.12 tanstack
@tanstack/start-plugin-core 1.169.23 tanstack
@tanstack/start-plugin-core 1.169.26 tanstack
@tanstack/start-server-core 1.167.33 tanstack
@tanstack/start-server-core 1.167.36 tanstack
@tanstack/start-static-server-functions 1.166.44 tanstack
@tanstack/start-static-server-functions 1.166.47 tanstack
@tanstack/start-storage-context 1.166.38 tanstack
@tanstack/start-storage-context 1.166.41 tanstack
@tanstack/valibot-adapter 1.166.12 tanstack
@tanstack/valibot-adapter 1.166.15 tanstack
@tanstack/virtual-file-routes 1.161.10 tanstack
@tanstack/virtual-file-routes 1.161.13 tanstack
@tanstack/vue-router 1.169.5 tanstack
@tanstack/vue-router 1.169.8 tanstack
@tanstack/vue-router-devtools 1.166.16 tanstack
@tanstack/vue-router-devtools 1.166.19 tanstack
@tanstack/vue-router-ssr-query 1.166.15 tanstack
@tanstack/vue-router-ssr-query 1.166.18 tanstack
@tanstack/vue-start 1.167.61 tanstack
@tanstack/vue-start 1.167.64 tanstack
@tanstack/vue-start-client 1.166.46 tanstack
@tanstack/vue-start-client 1.166.49 tanstack
@tanstack/vue-start-server 1.166.50 tanstack
@tanstack/vue-start-server 1.166.53 tanstack
@tanstack/zod-adapter 1.166.12 tanstack
@tanstack/zod-adapter 1.166.15 tanstack
@beproduct/nestjs-auth 0.1.2 tanstack
@beproduct/nestjs-auth 0.1.3 tanstack
@beproduct/nestjs-auth 0.1.4 tanstack
@beproduct/nestjs-auth 0.1.5 tanstack
@beproduct/nestjs-auth 0.1.6 tanstack
@beproduct/nestjs-auth 0.1.7 tanstack
@beproduct/nestjs-auth 0.1.8 tanstack
@beproduct/nestjs-auth 0.1.9 tanstack
@beproduct/nestjs-auth 0.1.10 tanstack
@beproduct/nestjs-auth 0.1.11 tanstack
@beproduct/nestjs-auth 0.1.12 tanstack
@beproduct/nestjs-auth 0.1.13 tanstack
@beproduct/nestjs-auth 0.1.14 tanstack
@beproduct/nestjs-auth 0.1.15 tanstack
@beproduct/nestjs-auth 0.1.16 tanstack
@beproduct/nestjs-auth 0.1.17 tanstack
@beproduct/nestjs-auth 0.1.18 tanstack
@beproduct/nestjs-auth 0.1.19 tanstack
@dirigible-ai/sdk 0.6.2 tanstack
@dirigible-ai/sdk 0.6.3 tanstack
@draftauth/client 0.2.1 tanstack
@draftauth/client 0.2.2 tanstack
@draftauth/core 0.13.1 tanstack
@draftauth/core 0.13.2 tanstack
@draftlab/auth 0.24.1 tanstack
@draftlab/auth 0.24.2 tanstack
@draftlab/auth-router 0.5.1 tanstack
@draftlab/auth-router 0.5.2 tanstack
@draftlab/db 0.16.1 tanstack
@draftlab/db 0.16.2 tanstack
@mesadev/rest 0.28.3 tanstack
@mesadev/saguaro 0.4.22 tanstack
@mesadev/sdk 0.28.3 tanstack
@ml-toolkit-ts/preprocessing 1.0.2 tanstack
@ml-toolkit-ts/preprocessing 1.0.3 tanstack
@ml-toolkit-ts/xgboost 1.0.3 tanstack
@ml-toolkit-ts/xgboost 1.0.4 tanstack
@squawk/airport-data 0.7.4 tanstack
@squawk/airport-data 0.7.5 tanstack
@squawk/airport-data 0.7.6 tanstack
@squawk/airport-data 0.7.7 tanstack
@squawk/airport-data 0.7.8 tanstack
@squawk/airports 0.6.2 tanstack
@squawk/airports 0.6.3 tanstack
@squawk/airports 0.6.4 tanstack
@squawk/airports 0.6.5 tanstack
@squawk/airports 0.6.6 tanstack
@squawk/airspace 0.8.1 tanstack
@squawk/airspace 0.8.2 tanstack
@squawk/airspace 0.8.3 tanstack
@squawk/airspace 0.8.4 tanstack
@squawk/airspace 0.8.5 tanstack
@squawk/airspace-data 0.5.3 tanstack
@squawk/airspace-data 0.5.4 tanstack
@squawk/airspace-data 0.5.5 tanstack
@squawk/airspace-data 0.5.6 tanstack
@squawk/airspace-data 0.5.7 tanstack
@squawk/airway-data 0.5.4 tanstack
@squawk/airway-data 0.5.5 tanstack
@squawk/airway-data 0.5.6 tanstack
@squawk/airway-data 0.5.7 tanstack
@squawk/airway-data 0.5.8 tanstack
@squawk/airways 0.4.2 tanstack
@squawk/airways 0.4.3 tanstack
@squawk/airways 0.4.4 tanstack
@squawk/airways 0.4.5 tanstack
@squawk/airways 0.4.6 tanstack
@squawk/fix-data 0.6.4 tanstack
@squawk/fix-data 0.6.5 tanstack
@squawk/fix-data 0.6.6 tanstack
@squawk/fix-data 0.6.7 tanstack
@squawk/fix-data 0.6.8 tanstack
@squawk/fixes 0.3.2 tanstack
@squawk/fixes 0.3.3 tanstack
@squawk/fixes 0.3.4 tanstack
@squawk/fixes 0.3.5 tanstack
@squawk/fixes 0.3.6 tanstack
@squawk/flight-math 0.5.4 tanstack
@squawk/flight-math 0.5.5 tanstack
@squawk/flight-math 0.5.6 tanstack
@squawk/flight-math 0.5.7 tanstack
@squawk/flight-math 0.5.8 tanstack
@squawk/flightplan 0.5.2 tanstack
@squawk/flightplan 0.5.3 tanstack
@squawk/flightplan 0.5.4 tanstack
@squawk/flightplan 0.5.5 tanstack
@squawk/flightplan 0.5.6 tanstack
@squawk/geo 0.4.4 tanstack
@squawk/geo 0.4.5 tanstack
@squawk/geo 0.4.6 tanstack
@squawk/geo 0.4.7 tanstack
@squawk/geo 0.4.8 tanstack
@squawk/icao-registry 0.5.2 tanstack
@squawk/icao-registry 0.5.3 tanstack
@squawk/icao-registry 0.5.4 tanstack
@squawk/icao-registry 0.5.5 tanstack
@squawk/icao-registry 0.5.6 tanstack
@squawk/icao-registry-data 0.8.4 tanstack
@squawk/icao-registry-data 0.8.5 tanstack
@squawk/icao-registry-data 0.8.6 tanstack
@squawk/icao-registry-data 0.8.7 tanstack
@squawk/icao-registry-data 0.8.8 tanstack
@squawk/mcp 0.9.1 tanstack
@squawk/mcp 0.9.2 tanstack
@squawk/mcp 0.9.3 tanstack
@squawk/mcp 0.9.4 tanstack
@squawk/mcp 0.9.5 tanstack
@squawk/navaid-data 0.6.4 tanstack
@squawk/navaid-data 0.6.5 tanstack
@squawk/navaid-data 0.6.6 tanstack
@squawk/navaid-data 0.6.7 tanstack
@squawk/navaid-data 0.6.8 tanstack
@squawk/navaids 0.4.2 tanstack
@squawk/navaids 0.4.3 tanstack
@squawk/navaids 0.4.4 tanstack
@squawk/navaids 0.4.5 tanstack
@squawk/navaids 0.4.6 tanstack
@squawk/notams 0.3.6 tanstack
@squawk/notams 0.3.7 tanstack
@squawk/notams 0.3.8 tanstack
@squawk/notams 0.3.9 tanstack
@squawk/notams 0.3.10 tanstack
@squawk/procedure-data 0.7.3 tanstack
@squawk/procedure-data 0.7.4 tanstack
@squawk/procedure-data 0.7.5 tanstack
@squawk/procedure-data 0.7.6 tanstack
@squawk/procedure-data 0.7.7 tanstack
@squawk/procedures 0.5.2 tanstack
@squawk/procedures 0.5.3 tanstack
@squawk/procedures 0.5.4 tanstack
@squawk/procedures 0.5.5 tanstack
@squawk/procedures 0.5.6 tanstack
@squawk/types 0.8.1 tanstack
@squawk/types 0.8.2 tanstack
@squawk/types 0.8.3 tanstack
@squawk/types 0.8.4 tanstack
@squawk/types 0.8.5 tanstack
@squawk/units 0.4.3 tanstack
@squawk/units 0.4.4 tanstack
@squawk/units 0.4.5 tanstack
@squawk/units 0.4.6 tanstack
@squawk/units 0.4.7 tanstack
@squawk/weather 0.5.6 tanstack
@squawk/weather 0.5.7 tanstack
@squawk/weather 0.5.8 tanstack
@squawk/weather 0.5.9 tanstack
@squawk/weather 0.5.10 tanstack
@supersurkhet/cli 0.0.2 tanstack
@supersurkhet/cli 0.0.3 tanstack
@supersurkhet/cli 0.0.4 tanstack
@supersurkhet/cli 0.0.5 tanstack
@supersurkhet/cli 0.0.6 tanstack
@supersurkhet/cli 0.0.7 tanstack
@supersurkhet/sdk 0.0.2 tanstack
@supersurkhet/sdk 0.0.3 tanstack
@supersurkhet/sdk 0.0.4 tanstack
@supersurkhet/sdk 0.0.5 tanstack
@supersurkhet/sdk 0.0.6 tanstack
@supersurkhet/sdk 0.0.7 tanstack
@tallyui/components 1.0.1 tanstack
@tallyui/components 1.0.2 tanstack
@tallyui/components 1.0.3 tanstack
@tallyui/connector-medusa 1.0.1 tanstack
@tallyui/connector-medusa 1.0.2 tanstack
@tallyui/connector-medusa 1.0.3 tanstack
@tallyui/connector-shopify 1.0.1 tanstack
@tallyui/connector-shopify 1.0.2 tanstack
@tallyui/connector-shopify 1.0.3 tanstack
@tallyui/connector-vendure 1.0.1 tanstack
@tallyui/connector-vendure 1.0.2 tanstack
@tallyui/connector-vendure 1.0.3 tanstack
@tallyui/connector-woocommerce 1.0.1 tanstack
@tallyui/connector-woocommerce 1.0.2 tanstack
@tallyui/connector-woocommerce 1.0.3 tanstack
@tallyui/core 0.2.1 tanstack
@tallyui/core 0.2.2 tanstack
@tallyui/core 0.2.3 tanstack
@tallyui/database 1.0.1 tanstack
@tallyui/database 1.0.2 tanstack
@tallyui/database 1.0.3 tanstack
@tallyui/pos 0.1.1 tanstack
@tallyui/pos 0.1.2 tanstack
@tallyui/pos 0.1.3 tanstack
@tallyui/storage-sqlite 0.2.1 tanstack
@tallyui/storage-sqlite 0.2.2 tanstack
@tallyui/storage-sqlite 0.2.3 tanstack
@tallyui/theme 0.2.1 tanstack
@tallyui/theme 0.2.2 tanstack
@tallyui/theme 0.2.3 tanstack
@taskflow-corp/cli 0.1.24 tanstack
@taskflow-corp/cli 0.1.25 tanstack
@taskflow-corp/cli 0.1.26 tanstack
@taskflow-corp/cli 0.1.27 tanstack
@taskflow-corp/cli 0.1.28 tanstack
@taskflow-corp/cli 0.1.29 tanstack
@tolka/cli 1.0.2 tanstack
@tolka/cli 1.0.3 tanstack
@tolka/cli 1.0.4 tanstack
@tolka/cli 1.0.5 tanstack
@tolka/cli 1.0.6 tanstack
agentwork-cli 0.1.4 tanstack
agentwork-cli 0.1.5 tanstack
cmux-agent-mcp 0.1.3 tanstack
cmux-agent-mcp 0.1.4 tanstack
cmux-agent-mcp 0.1.5 tanstack
cmux-agent-mcp 0.1.6 tanstack
cmux-agent-mcp 0.1.7 tanstack
cmux-agent-mcp 0.1.8 tanstack
cross-stitch 1.1.3 tanstack
cross-stitch 1.1.4 tanstack
cross-stitch 1.1.5 tanstack
cross-stitch 1.1.6 tanstack
cross-stitch 1.1.7 tanstack
git-branch-selector 1.3.3 tanstack
git-branch-selector 1.3.4 tanstack
git-branch-selector 1.3.5 tanstack
git-branch-selector 1.3.6 tanstack
git-branch-selector 1.3.7 tanstack
git-git-git 1.0.8 tanstack
git-git-git 1.0.9 tanstack
git-git-git 1.0.10 tanstack
git-git-git 1.0.11 tanstack
git-git-git 1.0.12 tanstack
ml-toolkit-ts 1.0.4 tanstack
ml-toolkit-ts 1.0.5 tanstack
nextmove-mcp 0.1.3 tanstack
nextmove-mcp 0.1.4 tanstack
nextmove-mcp 0.1.5 tanstack
nextmove-mcp 0.1.6 tanstack
nextmove-mcp 0.1.7 tanstack
safe-action 0.8.3 tanstack
safe-action 0.8.4 tanstack
ts-dna 3.0.1 tanstack
ts-dna 3.0.2 tanstack
ts-dna 3.0.3 tanstack
ts-dna 3.0.4 tanstack
ts-dna 3.0.5 tanstack
wot-api 0.8.1 tanstack
wot-api 0.8.2 tanstack
wot-api 0.8.3 tanstack
wot-api 0.8.4 tanstack
@mistralai/mistralai 2.2.2 mistral
@mistralai/mistralai 2.2.3 mistral
@mistralai/mistralai 2.2.4 mistral
@mistralai/mistralai-azure 1.7.1 mistral
@mistralai/mistralai-azure 1.7.2 mistral
@mistralai/mistralai-azure 1.7.3 mistral
@mistralai/mistralai-gcp 1.7.1 mistral
@mistralai/mistralai-gcp 1.7.2 mistral
@mistralai/mistralai-gcp 1.7.3 mistral
@uipath/access-policy-sdk 0.3.1 uipath
@uipath/access-policy-tool 0.3.1 uipath
@uipath/admin-tool 0.1.1 uipath
@uipath/agent-sdk 1.0.2 uipath
@uipath/agent-tool 1.0.1 uipath
@uipath/agent.sdk 0.0.18 uipath
@uipath/aops-policy-tool 0.3.1 uipath
@uipath/ap-chat 1.5.7 uipath
@uipath/api-workflow-tool 1.0.1 uipath
@uipath/apollo-core 5.9.2 uipath
@uipath/apollo-react 4.24.5 uipath
@uipath/apollo-wind 2.16.2 uipath
@uipath/auth 1.0.1 uipath
@uipath/case-tool 1.0.1 uipath
@uipath/cli 1.0.1 uipath
@uipath/codedagent-tool 1.0.1 uipath
@uipath/codedagents-tool 0.1.12 uipath
@uipath/codedapp-tool 1.0.1 uipath
@uipath/common 1.0.1 uipath
@uipath/context-grounding-tool 0.1.1 uipath
@uipath/data-fabric-tool 1.0.2 uipath
@uipath/docsai-tool 1.0.1 uipath
@uipath/filesystem 1.0.1 uipath
@uipath/flow-tool 1.0.2 uipath
@uipath/functions-tool 1.0.1 uipath
@uipath/gov-tool 0.3.1 uipath
@uipath/identity-tool 0.1.1 uipath
@uipath/insights-sdk 1.0.1 uipath
@uipath/insights-tool 1.0.1 uipath
@uipath/integrationservice-sdk 1.0.2 uipath
@uipath/integrationservice-tool 1.0.2 uipath
@uipath/llmgw-tool 1.0.1 uipath
@uipath/maestro-sdk 1.0.1 uipath
@uipath/maestro-tool 1.0.1 uipath
@uipath/orchestrator-tool 1.0.1 uipath
@uipath/packager-tool-apiworkflow 0.0.19 uipath
@uipath/packager-tool-bpmn 0.0.9 uipath
@uipath/packager-tool-case 0.0.9 uipath
@uipath/packager-tool-connector 0.0.19 uipath
@uipath/packager-tool-flow 0.0.19 uipath
@uipath/packager-tool-functions 0.1.1 uipath
@uipath/packager-tool-webapp 1.0.6 uipath
@uipath/packager-tool-workflowcompiler 0.0.16 uipath
@uipath/packager-tool-workflowcompiler-browser 0.0.34 uipath
@uipath/platform-tool 1.0.1 uipath
@uipath/project-packager 1.1.16 uipath
@uipath/resource-tool 1.0.1 uipath
@uipath/resourcecatalog-tool 0.1.1 uipath
@uipath/resources-tool 0.1.11 uipath
@uipath/robot 1.3.4 uipath
@uipath/rpa-legacy-tool 1.0.1 uipath
@uipath/rpa-tool 0.9.5 uipath
@uipath/solution-packager 0.0.35 uipath
@uipath/solution-tool 1.0.1 uipath
@uipath/solutionpackager-sdk 1.0.11 uipath
@uipath/solutionpackager-tool-core 0.0.34 uipath
@uipath/tasks-tool 1.0.1 uipath
@uipath/telemetry 0.0.7 uipath
@uipath/test-manager-tool 1.0.2 uipath
@uipath/tool-workflowcompiler 0.0.12 uipath
@uipath/traces-tool 1.0.1 uipath
@uipath/ui-widgets-multi-file-upload 1.0.1 uipath
@uipath/uipath-python-bridge 1.0.1 uipath
@uipath/vertical-solutions-tool 1.0.1 uipath
@uipath/vss 0.1.6 uipath
@uipath/widget.sdk 1.2.3 uipath
@bitwarden/cli 2026.4.0 bitwarden
@mastra/core 1.42.1 mastra
mastra 1.13.1 mastra
create-mastra 1.13.1 mastra
easy-day-js 1.11.22 mastra
@mastra/agent-browser 0.3.2 mastra
@mastra/agent-builder 1.0.42 mastra
@mastra/ai-sdk 1.4.6 mastra
@mastra/arize 1.2.3 mastra
@mastra/auth 1.0.3 mastra
@mastra/auth-auth0 1.0.2 mastra
@mastra/auth-better-auth 1.0.4 mastra
@mastra/auth-clerk 1.0.3 mastra
@mastra/auth-supabase 1.0.2 mastra
@mastra/auth-workos 1.5.3 mastra
@mastra/blaxel 0.4.2 mastra
@mastra/braintrust 1.1.4 mastra
@mastra/chroma 1.0.2 mastra
@mastra/claude 1.0.3 mastra
@mastra/clickhouse 1.10.1 mastra
@mastra/client-js 1.24.1 mastra
@mastra/cloudflare 1.4.2 mastra
@mastra/cloudflare-d1 1.0.7 mastra
@mastra/convex 1.2.2 mastra
@mastra/couchbase 1.0.4 mastra
@mastra/cursor 0.2.1 mastra
@mastra/datadog 1.2.5 mastra
@mastra/daytona 0.4.2 mastra
@mastra/deployer 1.42.1 mastra
@mastra/deployer-cloudflare 1.1.44 mastra
@mastra/deployer-netlify 1.1.20 mastra
@mastra/deployer-vercel 1.1.38 mastra
@mastra/docker 0.3.1 mastra
@mastra/dsql 1.0.3 mastra
@mastra/duckdb 1.4.3 mastra
@mastra/dynamodb 1.0.9 mastra
@mastra/e2b 0.3.4 mastra
@mastra/editor 0.11.3 mastra
@mastra/evals 1.3.1 mastra
@mastra/express 1.3.31 mastra
@mastra/fastembed 1.1.3 mastra
@mastra/fastify 1.3.31 mastra
@mastra/gcs 0.2.3 mastra
@mastra/github-signals 0.1.2 mastra
@mastra/google-cloud-pubsub 1.0.6 mastra
@mastra/hono 1.4.26 mastra
@mastra/inngest 1.5.2 mastra
@mastra/koa 1.5.14 mastra
@mastra/langfuse 1.3.6 mastra
@mastra/langsmith 1.2.4 mastra
@mastra/libsql 1.13.1 mastra
@mastra/loggers 1.1.3 mastra
@mastra/longmemeval 1.0.50 mastra
@mastra/mcp 1.10.1 mastra
@mastra/mcp-docs-server 1.1.47 mastra
@mastra/mcp-registry-registry 1.0.2 mastra
@mastra/mem0 0.1.14 mastra
@mastra/memory 1.20.4 mastra
@mastra/mongodb 1.9.3 mastra
@mastra/mssql 1.3.2 mastra
@mastra/nestjs 0.1.15 mastra
@mastra/node-audio 0.1.8 mastra
@mastra/node-speaker 0.1.1 mastra
@mastra/observability 1.14.2 mastra
@mastra/otel-bridge 1.2.3 mastra
@mastra/otel-exporter 1.2.3 mastra
@mastra/pg 1.13.1 mastra
@mastra/pinecone 1.0.2 mastra
@mastra/playground-ui 33.0.1 mastra
@mastra/posthog 1.0.29 mastra
@mastra/qdrant 1.0.3 mastra
@mastra/rag 2.2.2 mastra
@mastra/react 1.0.1 mastra
@mastra/redis 1.1.3 mastra
@mastra/s3 0.5.3 mastra
@mastra/s3vectors 1.0.7 mastra
@mastra/schema-compat 1.2.12 mastra
@mastra/sentry 1.1.4 mastra
@mastra/server 2.1.1 mastra
@mastra/stagehand 0.2.5 mastra
@mastra/tavily 1.0.3 mastra
@mastra/temporal 0.1.14 mastra
@mastra/turbopuffer 1.0.3 mastra
@mastra/upstash 1.1.3 mastra
@mastra/vectorize 1.0.3 mastra
@mastra/voice-aws-nova-sonic 0.1.4 mastra
@mastra/voice-deepgram 0.12.2 mastra
@mastra/voice-elevenlabs 0.12.2 mastra
@mastra/voice-google 0.12.3 mastra
@mastra/voice-google-gemini-live 0.12.2 mastra
@mastra/voice-openai 0.12.3 mastra
@mastra/voice-openai-realtime 0.12.6 mastra
@mastra/voice-playai 0.12.2 mastra
keyv 6.0.0 keyv
cacheable 2.5.1 keyv
cache-manager 7.2.10 keyv
cacheable-request 13.0.20 keyv
flat-cache 6.1.24 keyv
file-entry-cache 11.1.6 keyv
@cacheable/net 2.1.1 keyv
@cacheable/node-cache 3.1.2 keyv
@cacheable/memory 2.2.1 keyv
@cacheable/utils 2.5.1 keyv
ecto 5.0.1 keyv
claud-code * sandworm
cloude-code * sandworm
rimarf * sandworm
naniod * sandworm
suport-color * sandworm
@keyv/bigmap 6.0.0 keyvscope
@keyv/cloudflare-kv 6.0.0 keyvscope
@keyv/compress-brotli 6.0.0 keyvscope
@keyv/compress-gzip 6.0.0 keyvscope
@keyv/compress-lz4 6.0.0 keyvscope
@keyv/dynamo 6.0.0 keyvscope
@keyv/encrypt-node 6.0.0 keyvscope
@keyv/encrypt-web 6.0.0 keyvscope
@keyv/etcd 6.0.0 keyvscope
@keyv/memcache 6.0.0 keyvscope
@keyv/mongo 6.0.0 keyvscope
@keyv/mysql 6.0.0 keyvscope
@keyv/postgres 6.0.0 keyvscope
@keyv/redis 6.0.0 keyvscope
@keyv/serialize-msgpackr 6.0.0 keyvscope
@keyv/serialize-superjson 6.0.0 keyvscope
@keyv/sqlite 6.0.0 keyvscope
@keyv/test-suite 6.0.0 keyvscope
@keyv/valkey 6.0.0 keyvscope
@opensearch-project/opensearch 3.5.3 opensearch
@opensearch-project/opensearch 3.6.2 opensearch
@opensearch-project/opensearch 3.7.0 opensearch
@opensearch-project/opensearch 3.8.0 opensearch
tensorlake 0.5.144 tensorlake
cloude * sandworm
opencraw * sandworm
crypto-reader-info * sandworm
format-defaults * sandworm
hardhta * sandworm
iru-caches * sandsleep
iruchache * sandsleep
node-native-bridge * sandworm
secp256 * sandworm
crypto-locale * sandworm
detect-cache * sandworm
locale-loader-pro * sandworm
parse-compat * sandworm
scan-store * sandworm
veim * sandworm
yarsg * sandworm
ethres * sandsleep
uudi * sandsleep
@injectivelabs/sdk-ts 1.20.21 injective
'@
# <<< bad-npm
# >>> bad-extensions: generated from data/bad-extensions.tsv by tools/gen.sh. Edit that file, then run it.
$BadExt = @'
oorzc.ssh-tools 0.5.1 glassworm openvsx
oorzc.i18n-tools-plus 1.6.8 glassworm openvsx
oorzc.mind-map 1.0.61 glassworm openvsx
oorzc.scss-to-css-compile 1.3.4 glassworm openvsx
Angular-studio.ng-angular-extension * glassworm openvsx
awesome-codebase.codebase-dart-pro * glassworm openvsx
cudra-production.vsce-prettier-pro * glassworm openvsx
dev-studio-sense.php-comp-tools-vscode * glassworm openvsx
ko-zu-gun-studio.synchronization-settings-vscode * glassworm openvsx
littensy-studio.magical-icons * glassworm openvsx
pretty-studio-advisor.prettyxml-formatter * glassworm openvsx
sol-studio.solidity-extension * glassworm openvsx
studio-jjalaire-team.professional-quarto-extension * glassworm openvsx
studio-velte-distributor.pro-svelte-extension * glassworm openvsx
sun-shine-studio.shiny-extension-for-vscode * glassworm openvsx
tucyzirille-studio.angular-pro-tools-extension * glassworm openvsx
vce-brendan-studio-eich.js-debuger-vscode * glassworm openvsx
aadarkcode.one-dark-material * glasswormmar openvsx
aligntool.extension-align-professional-tool * glasswormmar openvsx
awesomeco.wonder-for-vscode-icons * glasswormmar openvsx
bhbpbarn.vsce-python-indent-extension * glasswormmar openvsx
blockstoks.easily-gitignore-manage * glasswormmar openvsx
brategmaqendaalar-studio.pro-prettyxml-formatter * glasswormmar openvsx
codbroks.compile-runnner-extension * glasswormmar openvsx
codevunmis.csv-sql-tsv-rainbow * glasswormmar openvsx
codwayexten.code-way-extension * glasswormmar openvsx
cosmic-themes.sql-formatter * glasswormmar openvsx
craz2team.vscode-todo-extension * glasswormmar openvsx
crotoapp.vscode-xml-extension * glasswormmar openvsx
daeumer-web.es-linter-for-vs-code * glasswormmar openvsx
dark-code-studio.flutter-extension * glasswormmar openvsx
densy-little-studio.wonder-for-vscode-icons * glasswormmar openvsx
dep-labs-studio.dep-proffesinal-extension * glasswormmar openvsx
devmidu-studio.svg-better-extension * glasswormmar openvsx
dopbop-studio.vscode-tailwindcss-extension-toolkit * glasswormmar openvsx
errlenscre.error-lens-finder-ex * glasswormmar openvsx
exss-studio.yaml-professional-extension * glasswormmar openvsx
federicanc.dotenv-syntax-highlighting * glasswormmar openvsx
flutxvs.vscode-kuberntes-extension * glasswormmar openvsx
gvotcha.claude-code-extension * glasswormmar openvsx
gvotcha.claude-code-extensions * glasswormmar openvsx
intellipro.extension-json-intelligence * glasswormmar openvsx
kharizma.vscode-extension-wakatime * glasswormmar openvsx
kwitch-studio.auto-run-command-extension * glasswormmar openvsx
lavender-studio.theme-lavender-dreams * glasswormmar openvsx
lyu-wen-studio-web-han.better-formatter-vscode * glasswormmar openvsx
markvalid.vscode-mdvalidator-extension * glasswormmar openvsx
mecreation-studio.pyrefly-pro-extension * glasswormmar openvsx
mswincx.antigravity-cockpit * glasswormmar openvsx
mswincx.antigravity-cockpit-extension * glasswormmar openvsx
namopins.prettier-pro-vscode-extension * glasswormmar openvsx
oigotm.my-command-palette-extension * glasswormmar openvsx
otoboss.autoimport-extension * glasswormmar openvsx
ovixcode.vscode-better-comments * glasswormmar openvsx
pessa07tm.my-js-ts-auto-commands * glasswormmar openvsx
potstok.dotnet-runtime-extension * glasswormmar openvsx
prismapp.prisma-vs-code-extension * glasswormmar openvsx
projmanager.your-project-manager-extension * glasswormmar openvsx
pubruncode.ccoderunner * glasswormmar openvsx
pyflowpyr.py-flowpyright-extension * glasswormmar openvsx
pyscopexte.pyscope-extension * glasswormmar openvsx
redcapcollective.vscode-quarkus-elite-suite * glasswormmar openvsx
rubyideext.ruby-ide-extension * glasswormmar openvsx
runnerpost.runner-your-code * glasswormmar openvsx
shinypy.shiny-extension-for-vscode * glasswormmar openvsx
ssgwysc.volar-vscode * glasswormmar openvsx
sxatvo.jinja-extension * glasswormmar openvsx
tamokill12.foundry-pdf-extension * glasswormmar openvsx
thing-mn.your-flow-extension-for-icons * glasswormmar openvsx
tima-web-wang.shell-check-utils * glasswormmar openvsx
tokcodes.import-cost-extension * glasswormmar openvsx
toowespace.worksets-extension * glasswormmar openvsx
treedotree.tree-do-todoextension * glasswormmar openvsx
turbobase.sql-turbo-tool * glasswormmar openvsx
twilkbilk.color-highlight-css * glasswormmar openvsx
yamaprolas.revature-labs-extension * glasswormmar openvsx
lauracode.wrap-selected-code 0.0.2 glasswormvsix openvsx
96-studio.json-formatter 0.0.2 glasswormvsix openvsx
96-studio.json-formatter 0.0.4 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.1 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.3 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.4 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.5 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.6 glasswormvsix openvsx
spacetoow.vsc-python-indent 1.21.7 glasswormvsix openvsx
namop-dex.claude-code-assistant 2.1.47 glasswormvsix openvsx
msw-tm.component-vetur-toolkit 0.37.4 glasswormvsix openvsx
cod-vok.arko-dev-devsecops 1.0.4 glasswormvsix openvsx
oxigener-tmp.sql-turbo-manager 0.28.10 glasswormvsix openvsx
otobo-vs.csv-query-tsv-rainbow 3.3.4 glasswormvsix openvsx
awesome-codespace.jinja-language-support 0.3.2 glasswormvsix openvsx
yamal-dext.wonder-workspace-icons 0.10.4 glasswormvsix openvsx
daeumer-web.align-format-tool 1.4.6 glasswormvsix openvsx
baksmink.vscode-quokka-extension 1.0.756 glasswormvsix openvsx
bansheejust22.retro-vhs-theme 1.0.1 glasswormvsix openvsx
quickrunn.auto-run-command-quick 1.6.2 glasswormvsix openvsx
outsidestormcommand.monochromator-theme * glasswormapr openvsx
keyacrosslaud.auto-loop-for-antigravity * glasswormapr openvsx
krundoven.ironplc-fast-hub * glasswormapr openvsx
boulderzitunnel.vscode-buddies * glasswormapr openvsx
cubedivervolt.html-code-validate * glasswormapr openvsx
winnerdomain17.version-lens-tool * glasswormapr openvsx
microsoftvs.microsoftvs * glasswormoct any
cosmic-themes.theme-cosmic-nebula * glasswormoct any
'@
# <<< bad-extensions
$NpmBad = @{}; $NpmAny = @{}; $NpmNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal); $N_BAD_NPM = 0
foreach ($l in ($BadNpm -split "`r?`n")) {
  $p = $l -split ' '; if ($p.Count -lt 3) { continue }
  $N_BAD_NPM++
  if ($p[1] -ceq '*') { $NpmAny[$p[0]] = $p[2] } else { $NpmBad["$($p[0])@$($p[1])"] = $p[2] }
  [void]$NpmNames.Add($p[0])
}
$NpmRows = New-Object System.Collections.Generic.List[object]; $NpmCacheRows = New-Object System.Collections.Generic.List[object]; $NpmSeen = @{}
$NpmCacheTag = " (npm's download cache)"
# Versions are shown only if they look like versions, so a package can't put terminal control codes in the report.
function Npm-Hit([string]$where, [string]$nm, [string]$v) {
  if ($v -cnotmatch '^[0-9A-Za-z.+_-]+\z') { $v = '?' }
  if ($v -cmatch '^0\.0\.1-security(\.[0-9]+)?\z') { return }  # npm's empty placeholder for a removed package: 0.0.1-security, or 0.0.1-security.0 for a few names
  $k = "$nm@$v"; $t = $null
  if ($NpmBad.ContainsKey($k)) { $t = $NpmBad[$k] } elseif ($NpmAny.ContainsKey($nm)) { $t = $NpmAny[$nm] }
  if ($null -eq $t -or $NpmSeen.ContainsKey("$where|$k")) { return }
  $NpmSeen["$where|$k"] = $true
  if ($where.EndsWith($NpmCacheTag, [StringComparison]::Ordinal)) { $NpmCacheRows.Add(@($where, "$nm $v", $t)) } else { $NpmRows.Add(@($where, "$nm $v", $t)) }
}
# Tarball URLs (/name/-/name-1.2.3.tgz: npm, yarn 1 and npm's cache), name@version tokens (pnpm,
# bun, yarn berry's name@npm:version), npm's "node_modules/name" entries with a "version" line,
# nested and bundled ones (node_modules/tool/node_modules/name) included, since those have no URL,
# and pnpm 5 and 7's /name/1.2.3 keys. A pin in an overrides section moves away from a version, so
# overrides are skipped.
$RxTgz = New-Object regex('/((?:@(?>[A-Za-z0-9._~-]+)/)?(?>[A-Za-z0-9._~-]+))/-/([A-Za-z0-9._~-]+)\.tgz', $RxOpt, $RxTimeout)
$RxTok = New-Object regex('(?<![A-Za-z0-9._~@-])((?:@(?>[A-Za-z0-9._~-]+)/)?(?>[A-Za-z0-9._~-]+))@(?:npm:)?([0-9](?>[0-9A-Za-z.+-]*))', $RxOpt, $RxTimeout)
$RxLockEntry = New-Object regex('^[^\n]*?"((?:node_modules/(?:[A-Za-z0-9._~@-]+/)*)?(?:@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+)"[^\S\n]*:[^\S\n]*\{|^[^\n]*?"version"[^\S\n]*:[^\S\n]*"([^"\n]+)"', $RxOpt, $RxTimeout)
$RxPnpmKey = New-Object regex('^[^\S\n]+/((?:@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+)/([0-9][^:(_/\n]*)', $RxOpt, $RxTimeout)
$RxPnpmOver = New-Object regex('^overrides:', $RxOpt, $RxTimeout)
$RxBunOver = New-Object regex('"overrides"[^\S\n]*:[^\S\n]*\{', $RxOpt, $RxTimeout)
function Strip-Overrides([string]$kind, [string]$text) {
  $pnpm = $kind -ceq 'pnpm-lock.yaml'
  if ($pnpm) { if (-not $RxPnpmOver.IsMatch($text)) { return $text } } elseif (-not $RxBunOver.IsMatch($text)) { return $text }
  $sb = New-Object System.Text.StringBuilder; $over = $false; $depth = 0
  foreach ($l in $text.Split("`n")) {
    if ($pnpm) {
      if ($l.Length -gt 0 -and $l[0] -ne ' ' -and $l[0] -ne '#') { $over = $l.StartsWith('overrides:', [StringComparison]::Ordinal) }
      if ($over) { continue }
    } else {
      $o = $l.Split('{').Count - $l.Split('}').Count
      if ($over) { $depth += $o; if ($depth -le 0) { $over = $false }; continue }
      if ($RxBunOver.IsMatch($l)) { $depth = $o; $over = $depth -gt 0; continue }
    }
    [void]$sb.Append($l).Append("`n")
  }
  $sb.ToString()
}
function Npm-Scan([string]$where, [string]$text, [string]$kind) {
  try {
    if ($kind -ceq 'pnpm-lock.yaml' -or $kind -ceq 'bun.lock') { $text = Strip-Overrides $kind $text }
    if ($kind -ceq 'package-lock.json' -or $kind -ceq 'npm-shrinkwrap.json') {
      $pend = ''
      foreach ($m in $RxLockEntry.Matches($text)) {
        if ($m.Groups[1].Success) { $pend = $m.Groups[1].Value -replace '^.*node_modules/', '' }
        elseif ($pend) { Npm-Hit $where $pend $m.Groups[2].Value; $pend = '' }
      }
    }
    if ($kind -ceq 'pnpm-lock.yaml') { foreach ($m in $RxPnpmKey.Matches($text)) { Npm-Hit $where $m.Groups[1].Value $m.Groups[2].Value } }
    foreach ($m in $RxTgz.Matches($text)) {
      $nm = $m.Groups[1].Value; $b = $nm -replace '^@[^/]*/', ''; $base = $m.Groups[2].Value
      if ($base.StartsWith("$b-", [StringComparison]::Ordinal)) { Npm-Hit $where $nm $base.Substring($b.Length + 1) }
    }
    foreach ($m in $RxTok.Matches($text)) { Npm-Hit $where $m.Groups[1].Value $m.Groups[2].Value }
  } catch { if (-not $SlowFiles.Contains($where)) { $script:NpmSlow++ }; Mark-Slow $where }
}
# Read directly rather than through Read-Text, so big lockfiles are not kept in memory.
# A lockfile the scan found but can't read leaves npm not fully checked, as the cache does.
$N_LOCK = 0; $NpmSlow = 0; $NpmUnread = 0; $LockUnread = New-Object System.Collections.Generic.List[string]
foreach ($f in $LockFiles) { try { $t = [IO.File]::ReadAllText($f) } catch { $LockUnread.Add($f); continue }; $N_LOCK++; Npm-Scan $f $t ([IO.Path]::GetFileName($f)) }
# Global installs: npm's own folders, the version managers (nvm, volta, fnm, asdf, mise, nodenv,
# nvm-windows), pnpm's and bun's global folders, and npx's cache, read from each package's package.json.
$NpmRoots = New-Object System.Collections.Generic.List[string]
function Add-NpmRoot([string]$r) { if ($r -and (Is-Dir $r) -and -not $NpmRoots.Contains($r)) { $NpmRoots.Add($r) } }
foreach ($r in @((J $AppData 'npm/node_modules'), (J $HomeDir '.npm-global/lib/node_modules'), (J $HomeDir '.bun/install/global/node_modules'),
    '/opt/homebrew/lib/node_modules', '/usr/local/lib/node_modules', '/usr/lib/node_modules')) { Add-NpmRoot $r }
# Folders holding one folder per version or package, and where node_modules sits in each.
$NpmGlobs = New-Object System.Collections.Generic.List[object]
foreach ($g in @(@('.nvm/versions/node', 'lib/node_modules'), @('.volta/tools/image/node', 'lib/node_modules'), @('.volta/tools/image/packages', 'lib/node_modules'),
    @('.local/share/fnm/node-versions', 'installation/lib/node_modules'), @('Library/Application Support/fnm/node-versions', 'installation/lib/node_modules'),
    @('.asdf/installs/nodejs', 'lib/node_modules'), @('.local/share/mise/installs/node', 'lib/node_modules'), @('.nodenv/versions', 'lib/node_modules'),
    @('Library/pnpm/global', 'node_modules'), @('.local/share/pnpm/global', 'node_modules'), @('.npm/_npx', 'node_modules'))) { $NpmGlobs.Add(@((J $HomeDir $g[0]), $g[1])) }
$nvmWin = $env:NVM_HOME; if (-not $nvmWin) { $nvmWin = J $AppData 'nvm' }
$fnmWin = $env:FNM_DIR; if (-not $fnmWin) { $fnmWin = J $AppData 'fnm' }
foreach ($g in @(@($nvmWin, 'node_modules'), @((J $fnmWin 'node-versions'), 'installation/node_modules'),
    @((J $LocalAppData 'Volta/tools/image/node'), 'node_modules'), @((J $LocalAppData 'Volta/tools/image/packages'), 'node_modules'),
    @((J $LocalAppData 'Volta/tools/image/packages'), 'lib/node_modules'), @((J $LocalAppData 'mise/installs/node'), 'node_modules'),
    @((J $LocalAppData 'pnpm/global'), 'node_modules'), @((J $LocalAppData 'npm-cache/_npx'), 'node_modules'))) { $NpmGlobs.Add($g) }
if ($env:PNPM_HOME) { $NpmGlobs.Add(@((J $env:PNPM_HOME 'global'), 'node_modules')) }
foreach ($g in $NpmGlobs) { foreach ($d in (Glob-Dirs $g[0] '*')) { Add-NpmRoot (J $d $g[1]) } }
# One pass over each root: a folder named for a bad package (node_modules/<name> or
# node_modules/@<scope>/<name>) has its package.json read, as the package itself or as a dependency
# of a globally installed tool. Nothing is looked up per bad name.
function Npm-Package([string]$d, [string]$nm, [bool]$deep) {
  if ($NpmNames.Contains($nm)) {
    $pj = J $d 'package.json'
    if (Is-File $pj) {
      $m = [regex]::Match([string](Read-Text $pj), '"version"\s*:\s*"([^"]+)"')
      $v = ''; if ($m.Success) { $v = $m.Groups[1].Value }
      Npm-Hit $d $nm $v
    }
  }
  if ($deep) { $nm2 = J $d 'node_modules'; if (Is-Dir $nm2) { Npm-Modules $nm2 $false } }
}
function Npm-Modules([string]$md, [bool]$deep) {
  foreach ($d in (Glob-Dirs $md '*')) {
    $dn = [IO.Path]::GetFileName($d); if ($dn.StartsWith('.')) { continue }
    if ($dn.StartsWith('@')) {
      foreach ($d2 in (Glob-Dirs $d '*')) { $n2 = [IO.Path]::GetFileName($d2); if (-not $n2.StartsWith('.')) { Npm-Package $d2 "$dn/$n2" $deep } }
    } else { Npm-Package $d $dn $deep }
  }
}
foreach ($r in $NpmRoots) { Npm-Modules $r $true }
# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it.
$OutTable = @(
  ,@('cursor', 'Cursor', 'mac', 'plist', '/Applications/Cursor.app/Contents/Info.plist', '-', '3.0', 'a malicious agent could escape the sandbox', 'github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw')
  ,@('cursor', 'Cursor', 'mac', 'plist', (J $HomeDir 'Applications/Cursor.app/Contents/Info.plist'), '-', '3.0', 'a malicious agent could escape the sandbox', 'github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw')
  ,@('amazonq', 'Amazon Q language server', 'mac', 'folder', (J $HomeDir 'Library/Caches/aws/toolkits/language-servers/AmazonQ'), '-', '1.69.0', 'a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands', 'aws.amazon.com/security/security-bulletins/2026-047-aws/')
  ,@('amazonq', 'Amazon Q language server', 'linux', 'folder', (J $HomeDir '.cache/aws/toolkits/language-servers/AmazonQ'), '-', '1.69.0', 'a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands', 'aws.amazon.com/security/security-bulletins/2026-047-aws/')
  ,@('amazonq', 'Amazon Q language server', 'win', 'folder', (J $LocalAppData 'aws/toolkits/language-servers/AmazonQ'), '-', '1.69.0', 'a link in a workspace can reach files outside it, and before 1.65.0 a workspace you trust can run its commands', 'aws.amazon.com/security/security-bulletins/2026-047-aws/')
  ,@('claudecode', 'Claude Code', 'all', 'npm', '@anthropic-ai/claude-code', '0.2.116', '1.0.24', 'a web page could reach the editor connection', 'github.com/advisories/GHSA-9f65-56v6-gxw7')
  ,@('mcpremote', 'mcp-remote', 'all', 'npm', 'mcp-remote', '0.0.5', '0.1.16', 'a hostile MCP server could run commands', 'github.com/advisories/GHSA-6xpm-ggf7-wc3p')
  ,@('mcpremote', 'mcp-remote', 'all', 'mcparg', 'mcp-remote', '0.0.5', '0.1.16', 'a hostile MCP server could run commands', 'github.com/advisories/GHSA-6xpm-ggf7-wc3p')
)
# <<< outdated
# --- 1. Coding agents: settings and versions -------------------------------------
# Agents set to run commands without asking (data/auto-approve.tsv), matched as gird-check.sh does:
# a line with its spaces removed, starting at the line, a { or a , and ending at the line's end, a
# , } # or /. Lines starting with // or # are skipped; in a .toml file only the lines before the
# first [table] count.
# Agents set to run commands without asking (data/auto-approve.tsv), matched by Aa-Hit (section 2).
$AaList = New-Object System.Collections.Generic.List[object]; $aaSeen = @{}
foreach ($r in $AaTable) {
  if ($r[1] -ne 'all' -and $r[1] -ne $IndOs) { continue }
  if ($r[2].StartsWith('{PROJECT}/')) { $rel = '/' + $r[2].Substring(10); $files = @($AaFiles | Where-Object { ($_ -replace '\\', '/').EndsWith($rel, [StringComparison]::Ordinal) }) } else { $files = @($r[2]) }
  foreach ($f in $files) {
    if (-not (Is-File $f) -or -not (Aa-Hit $f $r[4])) { continue }
    if ($aaSeen.ContainsKey($f)) { $aaSeen[$f].Setting += ", $($r[3])" }
    else { $row = @{ File = $f; Agent = $r[0]; Setting = $r[3] }; $aaSeen[$f] = $row; $AaList.Add($row) }
  }
}
$N_YOLO = $AaList.Count
if ($N_YOLO -gt 0) { Progress "Agents set to run commands without asking: $($AaList[0].Agent)" }
# Agent versions with a published fix (data/outdated.tsv). Only a version of numbers and dots is
# compared, part by part as numbers; anything else is not reported.
function Ver-Ok([string]$v) { $v -cmatch '^[0-9]+(\.[0-9]+)*$' }
function Ver-Cmp([string]$a, [string]$b) {
  $x = $a.Split('.'); $y = $b.Split('.'); $n = [Math]::Max($x.Count, $y.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $p = '0'; if ($i -lt $x.Count) { $p = $x[$i].TrimStart('0') }; $q = '0'; if ($i -lt $y.Count) { $q = $y[$i].TrimStart('0') }
    if ($p -eq '') { $p = '0' }; if ($q -eq '') { $q = '0' }
    if ($p.Length -ne $q.Length) { if ($p.Length -lt $q.Length) { return -1 } else { return 1 } }
    $c = [string]::CompareOrdinal($p, $q); if ($c -lt 0) { return -1 } elseif ($c -gt 0) { return 1 }
  }
  0
}
# name@version in a text, where nothing that can be part of a package name comes right before it.
$RxArgVer = New-Object regex('\G[0-9A-Za-z.+-]+')
function Pkg-Args([string]$nm, [string]$t) {
  if (-not $t) { return }
  $p = "$nm@"; $k = $t.IndexOf($p, [StringComparison]::Ordinal)
  while ($k -ge 0) {
    if (-not ($k -gt 0 -and ([string]$t[$k - 1]) -cmatch '[A-Za-z0-9._/@-]')) { $m = $RxArgVer.Match($t, $k + $p.Length); if ($m.Success) { $m.Value } }
    $k = $t.IndexOf($p, $k + 1, [StringComparison]::Ordinal)
  }
}
$OldList = New-Object System.Collections.Generic.List[object]; $oldSeen = @{}
foreach ($r in $OutTable) {
  if ($r[2] -ne 'all' -and $r[2] -ne $IndOs) { continue }
  $vs = @()
  switch ($r[3]) {
    'plist' { $t = Read-Text $r[4]; if ($null -ne $t) { $m = [regex]::Match($t, '<key>CFBundleShortVersionString</key>\s*<string>([^<]*)</string>'); if ($m.Success) { $vs = @($m.Groups[1].Value) } } }
    'folder' {
      $best = ''
      foreach ($d in (Glob-Dirs $r[4] '*')) { $n = [IO.Path]::GetFileName($d); if ((Ver-Ok $n) -and ($best -eq '' -or (Ver-Cmp $n $best) -gt 0)) { $best = $n } }
      if ($best) { $vs = @($best) }
    }
    'npm' { $vs = @(foreach ($nr in $NpmRoots) { $pj = J (J $nr $r[4]) 'package.json'; if (Is-File $pj) { $m = [regex]::Match([string](Read-Text $pj), '"version"\s*:\s*"([^"]+)"'); if ($m.Success) { $m.Groups[1].Value } } }) }
    'mcparg' { $vs = @(foreach ($f in $McpList) { if (Is-File $f) { Pkg-Args $r[4] (Read-Text $f) } }) }
  }
  foreach ($v in $vs) {
    if (-not (Ver-Ok $v)) { continue }
    # name@0.1 in an MCP config is a range npx resolves when it runs, not a version: not reported.
    if ($r[3] -eq 'mcparg' -and $v.Split('.').Count -lt 3) { continue }
    if ($r[5] -ne '-' -and (Ver-Cmp $v $r[5]) -lt 0) { continue }
    if ((Ver-Cmp $v $r[6]) -ge 0) { continue }
    if ($oldSeen.ContainsKey($r[0])) { $o = $oldSeen[$r[0]]; if (-not $o.Vers.Contains($v)) { $o.Vers.Add($v) } }
    else { $o = @{ Name = $r[1]; Vers = (New-Object System.Collections.Generic.List[string]); Fixed = $r[6]; Hole = $r[7]; Src = $r[8] }; $o.Vers.Add($v); $oldSeen[$r[0]] = $o; $OldList.Add($o) }
  }
}
$N_OLD = $OldList.Count
if ($N_OLD -gt 0) { Progress "A tool with a security fix to install: $($OldList[0].Name)" }
# npm's download cache keeps a package after it is uninstalled. A hit there means it was downloaded
# on this machine, usually by an install; the report says which of the three places it came from.
# A folder or file that can't be read leaves the cache not fully checked, never clean: a cache
# folder on the way that exists but can't be listed counts too.
function Npm-Cache-Index([string]$c) { # the index folder; '' when the cache has none, $null when a folder on the way can't be read
  $p = $c
  foreach ($part in @('_cacache', 'index-v5')) {
    if (-not (Is-Dir $p)) { return '' }
    try { $kids = @(([IO.DirectoryInfo]$p).GetDirectories() | ForEach-Object { $_.Name }) } catch { return $null }
    if (@($kids | Where-Object { $_.Equals($part, $PathCmp) }).Count -eq 0) { return '' }
    $p = J $p $part
  }
  $p
}
foreach ($c in @((J $LocalAppData 'npm-cache'), (J $HomeDir '.npm'))) {
  $ix = Npm-Cache-Index $c
  if ($null -eq $ix) { $NpmUnread++; continue }
  if (-not $ix) { continue }
  $q = New-Object System.Collections.Generic.Queue[string]; $q.Enqueue($ix)
  while ($q.Count -gt 0) {
    $dd = $q.Dequeue()
    try { $ents = ([IO.DirectoryInfo]$dd).GetFileSystemInfos() } catch { $NpmUnread++; continue }
    foreach ($e in $ents) {
      if (Is-Link $e) { continue }
      if (Is-DirInfo $e) { $q.Enqueue($e.FullName); continue }
      try { $t = [IO.File]::ReadAllText($e.FullName) } catch { $NpmUnread++; continue }
      Npm-Scan "$c$NpmCacheTag" $t ''
    }
  }
}
$byWhere = [Comparison[object]] { param($x, $y) $o = [string]::CompareOrdinal($x[0], $y[0]); if ($o -eq 0) { $o = [string]::CompareOrdinal($x[1], $y[1]) }; $o }
$NpmRows.Sort($byWhere); $NpmCacheRows.Sort($byWhere); $NpmRows.AddRange($NpmCacheRows)
# Editor extensions that shipped malware (data/bad-extensions.tsv): <id>-<version> folders, perhaps
# with a platform suffix such as -darwin-arm64, the id compared without case. VS Code installs from
# the Marketplace; Cursor, Windsurf, VSCodium and Kiro install from Open VSX. Windsurf became Devin
# Desktop on 2 June 2026, which keeps the extensions in ~/.devin/extensions and only reads the old
# folder (its FAQ: only the name changed), so both are read. A line whose bad build
# was only ever on Open VSX (registry openvsx) is not looked for in VS Code's own folder, where the
# same version is the Marketplace's clean build. A folder that can't be read leaves the check not
# done in full ($ExtUnread), never clean.
$ExtRows = New-Object System.Collections.Generic.List[object]; $ExtUnread = 0
$BadExtRows = @($BadExt -split "`r?`n" | ForEach-Object { , @($_ -split ' ') } | Where-Object { $_.Count -ge 4 })
foreach ($er in @('.vscode/extensions', '.cursor/extensions', '.windsurf/extensions', '.devin/extensions', '.vscode-oss/extensions', '.kiro/extensions')) {
  $reg = 'openvsx'; if ($er -eq '.vscode/extensions') { $reg = 'marketplace' }
  $xdir = J $HomeDir $er
  if (-not (Is-Dir $xdir)) { continue }
  try { $xents = @(([IO.DirectoryInfo]$xdir).GetFileSystemInfos() | Sort-Object -Property Name -CaseSensitive) } catch { $ExtUnread++; continue }
  foreach ($e in $xents) {
    if (-not (Is-DirInfo $e)) { continue }
    foreach ($x in $BadExtRows) {
      if ($x[3] -ne 'any' -and $x[3] -ne $reg) { continue }
      $pre = $x[0] + '-'
      if (-not $e.Name.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { continue }
      $m = [regex]::Match($e.Name.Substring($pre.Length), '^([0-9]+(?:\.[0-9]+)*)(-.*)?$')
      if (-not $m.Success) { continue }
      if ($x[1] -ceq '*' -or $x[1] -ceq $m.Groups[1].Value) { $ExtRows.Add(@($e.FullName, "$($x[0]) $($m.Groups[1].Value)", $x[2])); break }
    }
  }
}
# Incidents that leave the machine itself uncompromised only need the version updated; the rest mean a compromised machine.
$NPM_HIT = 0; $NPM_UPD = 0
$NpmTags = @($NpmRows | ForEach-Object { $_[2] } | Sort-Object -Unique -CaseSensitive)
foreach ($t in $NpmTags) { if ((Incident-Level $t) -eq 'act') { $NPM_HIT = 1 } else { $NPM_UPD = 1 } }
# A lockfile records what some machine resolved, not what ran here. An act-level hit was installed
# when npm's cache or a global install has it, or node_modules next to the lockfile holds that
# version. A hit in a lockfile alone ($LockProj holds their folders) leaves the headline and the fix
# depending on whether that project was installed; the score and the link stay as they are.
$NpmInst = 0; $LockProj = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($r in $NpmRows) {
  if ((Incident-Level $r[2]) -ne 'act') { continue }
  if ($r[0] -cmatch '[/\\](package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lock)$') {
    $isp = $r[1].LastIndexOf(' '); $ipn = $r[1].Substring(0, $isp); $ipv = $r[1].Substring($isp + 1)
    $ipj = J (J (J ([IO.Path]::GetDirectoryName($r[0])) 'node_modules') $ipn) 'package.json'
    $iiv = ''; if (Is-File $ipj) { $im = [regex]::Match([string](Read-Text $ipj), '"version"\s*:\s*"([^"]+)"'); if ($im.Success) { $iiv = $im.Groups[1].Value } }
    if ($iiv -and $iiv -ceq $ipv) { $NpmInst = 1 } else { [void]$LockProj.Add([IO.Path]::GetDirectoryName($r[0])) }
  } else { $NpmInst = 1 }
}
$N_LOCKPROJ = $LockProj.Count
# What these worms leave behind (data/indicators.tsv). gh-token-monitor runs a destructive command
# when the stolen GitHub token stops working (in the TanStack wave it tries to run rm -rf ~/, Wiz; in
# the keyv wave it evaluates a handler string the attacker supplied, Socket), so it must be stopped
# before any token is revoked. A file in the shared /tmp counts only if this person owns it; Windows has no /tmp.
$Wiper = New-Object System.Collections.Generic.List[string]
$Persist = New-Object System.Collections.Generic.List[object]
# A startup file of an incident whose packages are editor extensions only (GlassWorm's LaunchAgent)
# is that incident's sign, shown with the extensions ($ExtPersist), never called npm malware, and only
# next to an extension that shipped malware: GlassWorm's is named com.user.nodestart.plist, the kind
# of name people give their own LaunchAgents, and Socket gives the name as an example. Alone, it is a
# file to check ($ExtCheck), not a compromised machine.
$ExtPersist = New-Object System.Collections.Generic.List[object]; $ExtPersistTags = New-Object System.Collections.Generic.List[string]
$ExtIncs = @($BadExtRows | ForEach-Object { $_[2] })
$NpmIncs = @($BadNpm -split "`r?`n" | ForEach-Object { @($_ -split ' ')[2] })
foreach ($r in $IndOn) {
  if ($r[2] -ne 'wiper' -and $r[2] -ne 'startup') { continue }
  $m = $r[4]; if (-not $m -or -not (Exists $m)) { continue }
  if ($r[3] -eq 'yes') {
    if ($OnWindows) { continue }
    # Only under its one name, outside the home folder: a link, symbolic or hard, could put another
    # person's file under it.
    if (-not (Owns-File $m) -or (-not $m.StartsWith("$HomeDir/") -and (Multi-Name $m))) { continue }
  }
  if ($r[2] -eq 'wiper') { $Wiper.Add($m) }
  elseif ($ExtIncs -contains $r[0] -and -not ($NpmIncs -contains $r[0])) { $ExtPersist.Add(@($m, $r[5])); if (-not $ExtPersistTags.Contains($r[0])) { $ExtPersistTags.Add($r[0]) } }
  else { $Persist.Add(@($m, $r[5])) }
}
# A registry value is not a file, so the Mastra malware's Run key stays code.
if ($OnWindows) {
  try {
    $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
    if ($rk) { if ($null -ne $rk.GetValue('NvmProtocal')) { $Persist.Add(@('NvmProtocal in your startup programs', 'starts the Mastra malware at login')) }; $rk.Close() }
  } catch { }
}
foreach ($f in $WormHit) { $Persist.Add(@($f, (Planted-Note (Planted-Rel $f)))) }
foreach ($f in $WormRefs) { $Persist.Add(@($f, $WormRefNote)) }
$ExtCheck = New-Object System.Collections.Generic.List[object]; $ExtCheckTags = New-Object System.Collections.Generic.List[string]
if ($ExtRows.Count -eq 0 -and $ExtPersist.Count -gt 0) {
  $ExtCheck.AddRange($ExtPersist); $ExtCheckTags.AddRange($ExtPersistTags); $ExtPersist.Clear(); $ExtPersistTags.Clear()
}
$WIPER_HIT = 0; if ($Wiper.Count -gt 0) { $WIPER_HIT = 1 }
$MAL_HIT = 0; if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0 -or $WIPER_HIT -eq 1) { $MAL_HIT = 1 }
$MAL_LOCKONLY = 0; if ($MAL_HIT -eq 1 -and $NpmInst -eq 0 -and $Persist.Count -eq 0 -and $WIPER_HIT -eq 0) { $MAL_LOCKONLY = 1 }
# Editor extension malware is its own finding, never called npm malware: EXT_HIT, the link's ex. An
# extension incident's startup file next to it is its sign too.
$EXT_HIT = 0; if ($ExtRows.Count -gt 0 -or $ExtPersist.Count -gt 0) { $EXT_HIT = 1 }
$ExtTags = @((@(foreach ($r in $ExtRows) { $r[2] }) + @($ExtPersistTags)) | Sort-Object -Unique -CaseSensitive)
$ANY_MAL = 0; if ($MAL_HIT -eq 1 -or $EXT_HIT -eq 1) { $ANY_MAL = 1 }
if ($MAL_HIT -eq 1 -and $EXT_HIT -eq 1) { $MalWhat = 'npm and editor extension malware'; $MalShort = 'npm and editor extension' }
elseif ($EXT_HIT -eq 1) { $MalWhat = 'malware in an editor extension'; $MalShort = 'editor extension' }
else { $MalWhat = 'npm malware'; $MalShort = 'npm' }
if ($WIPER_HIT -eq 1) { Progress 'A wiper waits for a GitHub token to be revoked: gh-token-monitor' }
elseif ($ANY_MAL -eq 1) { Progress "Signs of $MalWhat found" }
elseif ($ExtCheck.Count -gt 0) { Progress "A startup file to check: $(Short $ExtCheck[0][0])" }
# Hosted platforms that leaked stored secrets (data/platforms.tsv): found by a command on PATH, a
# file or a folder.
# >>> platforms: generated from data/platforms.tsv by tools/gen.sh. Edit that file, then run it.
$Platforms = @(
  @{ Id = 'opencode'; Name = 'OpenCode'; Cmds = @('opencode'); Dirs = @((J $HomeDir '.config/opencode'), (J $HomeDir '.local/share/opencode')); Files = @(); Found = 'installed'; Advice = 'If you used OpenCode Console, rotate every provider key you saved there. Keys kept only in the CLI were not affected.'; Summary = 'OpenCode found: used its Console? Rotate keys' },
  @{ Id = 'railway'; Name = 'Railway'; Cmds = @('railway'); Dirs = @(); Files = @((J $HomeDir '.railway/config.json')); Found = 'CLI found'; Advice = 'Railway asked all users to rotate every environment variable stored there, including API keys and private registry credentials, and to review their logs for unusual activity.'; Summary = 'Railway CLI found: rotate secrets stored there' },
  @{ Id = 'zeabur'; Name = 'Zeabur'; Cmds = @('zeabur'); Dirs = @((J $HomeDir '.config/zeabur')); Files = @(); Found = 'CLI found'; Advice = 'Zeabur said on 19 October that an attacker read service environment variables stored on the platform, and asked every customer to replace all of them. Revoke each key at its provider first.'; Summary = 'Zeabur CLI found: rotate secrets stored there' })
# <<< platforms
$PlatFound = @($Platforms | Where-Object {
  $p = $_; (@($p.Cmds | Where-Object { Has-Command $_ }).Count -gt 0) -or (@($p.Dirs | Where-Object { Is-Dir $_ }).Count -gt 0) -or (@($p.Files | Where-Object { Is-File $_ }).Count -gt 0)
} | ForEach-Object { $_.Id })
function Join-Or($names) { $n = @($names); if ($n.Count -le 1) { $n -join '' } else { ($n[0..($n.Count - 2)] -join ', ') + ' or ' + $n[$n.Count - 1] } }
$PlatFix = Join-Or @($Platforms | Where-Object { $PlatFound -contains $_.Id } | ForEach-Object { Incident-Name $_.Id })
# The report's fixed fields opencode and railway.
$OC = 0; if ($PlatFound -contains 'opencode') { $OC = 1 }
$RW = 0; if ($PlatFound -contains 'railway') { $RW = 1 }

# --- Keys in agent sessions: the results --------------------------------------
# Stopped here, when the rest of the check is done, unless -AllSessions asked to wait.
Sess-Stop $OptAllSess
# SESS_DONE counts the files read to the end; SESS_UNREAD the folders that could not be read (-1:
# some, rg.exe gives no count) and SESS_UNREAD_FILES the files; SESS_NOTRUN the files no engine
# looked at, because there is none or the check could not start.
$SESS_TOTAL = [int]$SessSt.Total; $SESS_DONE = [int]$SessSt.Done; $SESS_ZST = [int]$SessSt.Zst; $SESS_UNREAD = [int]$SessSt.Skipped; $SESS_UNREAD_FILES = [int]$SessSt.Unread; $SESS_NOTRUN = 0
if ($SessEngine -ne 'net' -or -not $SessSt.Listed) {
  $cnt = @{ Skipped = 0; Stop = $false }
  $sessAll = Sess-List $SessRoots $cnt
  $SESS_TOTAL = $sessAll.Count; $SESS_ZST = @($sessAll | Where-Object { $_.Name.EndsWith('.zst') }).Count; $SESS_UNREAD = [int]$cnt.Skipped
  # rg.exe reports no progress per file: it finished (0 or 1), finished but could not read some
  # file or folder (2), or was stopped before the end.
  if ($SessEngine -eq 'none' -or $SessSt.Failed) { $SESS_NOTRUN = $SESS_TOTAL; $SESS_DONE = 0 }
  elseif ($SessEngine -eq 'rg' -and -not $SessSt.Stopped -and ($SessSt.RgExit -eq 0 -or $SessSt.RgExit -eq 1)) { $SESS_DONE = $SESS_TOTAL - $SESS_ZST }
  elseif ($SessEngine -eq 'rg' -and -not $SessSt.Stopped -and $SessSt.RgExit -eq 2) { $SESS_DONE = $SESS_TOTAL - $SESS_ZST; $SESS_UNREAD = -1 }
  elseif ($SessEngine -eq 'rg') { $SESS_DONE = -1 }
  else { $SESS_DONE = 0 }
}
$sessHits = New-Object System.Collections.Generic.List[string]
foreach ($h in $SessSt.Hits) { $sessHits.Add([string]$h) }
# Aider keeps its chat and the prompts typed into it (.aider.chat.history.md, .aider.input.history)
# in each project, found by the home scan, and they are checked here.
$rxTr = New-Object regex($TR_KEYS, $RxOpt, $RxTimeout)
foreach ($f in $AiderFiles) {
  $SESS_TOTAL++
  $t = Read-Text $f; if ($null -eq $t) { $SESS_UNREAD_FILES++; continue }
  if ($SESS_DONE -ge 0) { $SESS_DONE++ }
  $seenA = @{}
  try { foreach ($m in $rxTr.Matches($t)) { $p = Key-Provider $m.Value; if ($p -and -not (Made-Up $m.Value) -and -not $seenA.ContainsKey($p)) { $seenA[$p] = 1; $sessHits.Add("$f`t$p") } } } catch { Mark-Slow $f }
}
# Which agent a file belongs to and where it was found: the session folder it is under, or the
# file itself when the location is one file (Codex's history.jsonl, an Aider history). The report
# names places, not session files: a session file's path can spell out a project folder (Claude
# Code keeps sessions under one named after the project's full path), which would put a username
# and a project into a report pasted into an issue.
function Sess-Where([string]$f) {
  if ($f.EndsWith('.aider.chat.history.md') -or $f.EndsWith('.aider.input.history')) { return @('Aider', $f) }
  foreach ($src in $SessSources) { if ($f.Equals($src[1], $PathCmp) -or $f.StartsWith($src[1] + [IO.Path]::DirectorySeparatorChar, $PathCmp) -or $f.StartsWith($src[1] + '/', $PathCmp)) { return @($src[0], $src[1]) } }
  @('Other', [IO.Path]::GetDirectoryName($f))
}
$SessFiles = New-Object System.Collections.Generic.List[string]; $SessPlaces = New-Object System.Collections.Generic.List[string]; $sessPlaceN = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal); $sessAg = [ordered]@{}
foreach ($h in $sessHits) {
  # The provider comes last and holds no tab, so a tab in a file name can't shift the split.
  $at = $h.LastIndexOf("`t"); $f = $h.Substring(0, $at); $p = $h.Substring($at + 1); $a, $where = Sess-Where $f
  if (-not $SessFiles.Contains($f)) {
    $SessFiles.Add($f); if ($sessPlaceN.ContainsKey($where)) { $sessPlaceN[$where]++ } else { $SessPlaces.Add($where); $sessPlaceN[$where] = 1 }
    if (-not $sessAg.Contains($a)) { $sessAg[$a] = @{ N = 0; P = (New-Object System.Collections.Generic.List[string]) } }; $sessAg[$a].N++
  }
  if (-not $sessAg[$a].P.Contains($p)) { $sessAg[$a].P.Add($p) }
}
$SessFiles.Sort([StringComparer]::Ordinal)
# Most files first, then by name.
$SessPlaces.Sort([Comparison[string]]{ param($x, $y) if ($sessPlaceN[$x] -ne $sessPlaceN[$y]) { return $sessPlaceN[$y] - $sessPlaceN[$x] }; return [string]::CompareOrdinal($x, $y) })
$N_SESS = $SessFiles.Count; $N_PLACES = $SessPlaces.Count
$SessRows = @($sessAg.Keys | ForEach-Object { , @($_, $sessAg[$_].N, ($sessAg[$_].P -join ', ')) } | Sort-Object -Property @{ Expression = { $_[1] }; Descending = $true }, @{ Expression = { $_[0] } })
# Partly checked: any file not read to the end (compressed, unreadable, or not reached when the
# check was stopped), or a folder that could not be read.
$SESS_PARTIAL = ($SESS_UNREAD -ne 0) -or ($SESS_TOTAL -gt 0 -and ($SESS_NOTRUN -gt 0 -or $SESS_DONE -lt $SESS_TOTAL))
# The encrypted .pb files in those folders, by agent. A folder that holds none (Antigravity's newer
# conversations are SQLite, read above) is never named.
$SessSealedAg = New-Object System.Collections.Generic.List[string]; $SessSealedN = 0
foreach ($sealRow in $SessSealed) {
  if (-not (Is-Dir $sealRow[1])) { continue }
  $sealN = @((Sess-List @($sealRow[1]) @{ Skipped = 0; Stop = $false }) | Where-Object { $_.Name -cmatch '\.pb$' }).Count
  if ($sealN -gt 0) { $SessSealedN += $sealN; if (-not $SessSealedAg.Contains($sealRow[0])) { $SessSealedAg.Add($sealRow[0]) } }
}
if ($N_SESS -gt 0) { Progress "Keys in $(Plural $N_SESS 'agent session file' 'agent session files')" }

# --- What to do, and the score -----------------------------------------------
# Each fix also belongs to a section, so that section's details can end with it.
$Todo = New-Object System.Collections.Generic.List[string]
$Fixes = @{ 1 = (New-Object System.Collections.Generic.List[string]); 2 = (New-Object System.Collections.Generic.List[string]);
  3 = (New-Object System.Collections.Generic.List[string]); 4 = (New-Object System.Collections.Generic.List[string]); 5 = (New-Object System.Collections.Generic.List[string]) }
# With gh-token-monitor present, revoking a token sets it off: every rotate or revoke the report says
# waits for it, in the sections as in the fix list. The wiper's own fix is the one that says so.
function Wiper-Wait([string]$text) {
  if ($WIPER_HIT -eq 1 -and -not $text.StartsWith("Don't revoke") -and $text -cmatch '[Rr]otate|[Rr]evoke') { return "$text Only once gh-token-monitor is stopped and removed (section 5)." }
  $text
}
function Add-Todo([int]$sec, [string]$text) {
  $text = Wiper-Wait $text
  $Todo.Add($text); $Fixes[$sec].Add($text)
}
if ($WIPER_HIT -eq 1) { Add-Todo 5 'Don''t revoke any GitHub token yet. First stop and remove gh-token-monitor, as section 5 shows: it runs a destructive command when the stolen token stops working. Then rotate every key this machine could reach.' }
# A bad version found only in lockfiles: whether this machine is compromised depends on whether
# that project was installed here.
if ($MAL_LOCKONLY -eq 1) {
  if ($N_LOCKPROJ -eq 1) { $lp = 'the project'; $ll = 'its lockfile' } else { $lp = 'the projects'; $ll = 'their lockfiles' }
  Add-Todo 5 "If you ran an install in $lp section 5 lists, treat this machine as compromised: clear npm's cache with npm cache clean --force and rotate every key this machine could reach. If not, update $ll to a version without the malware."
} elseif ($MAL_HIT -eq 1) { Add-Todo 5 'Treat this machine as compromised. Delete the packages and files listed in section 5, clear npm''s cache with npm cache clean --force, and rotate every key this machine could reach.' }
if ($EXT_HIT -eq 1) {
  # Only what section 5 lists: the extensions, the incident's startup file, or both.
  if ($ExtPersist.Count -gt 0) { $edo = 'Uninstall the extensions listed in section 5, delete the startup file listed there, and' }
  else { $edo = 'Uninstall the extensions listed in section 5 and' }
  Add-Todo 5 "Treat this machine as compromised. $edo rotate every key this machine could reach."
}
# An incident's own fix (data/incidents.tsv), once for each incident found, right after the act-now
# fixes: an act-level one, then an update-level one, ahead of every other fix (the Injective SDK's:
# move the funds out of a wallet whose seed phrase may have been sent out). Two incidents can share a
# fix (two waves of one malware): it is said once.
function Add-Advice([string]$level) {
  $seen = @{}; $said = @{}
  foreach ($t in (@($NpmTags) + @($ExtTags) + @($PyHits))) {
    if ($seen.ContainsKey($t)) { continue }; $seen[$t] = 1
    if ((Incident-Level $t) -ne $level) { continue }
    $a = Incident-Advice $t; if (-not $a -or $said.ContainsKey($a)) { continue }; $said[$a] = 1
    Add-Todo 5 $a
  }
}
if ($ExtCheck.Count -gt 0) { Add-Todo 5 'Open the startup file listed in section 5 and check what it starts at login. If you did not set it up yourself, treat this machine as compromised: delete it and rotate every key this machine could reach.' }
if ($LITELLM_HIT -eq 0 -and $LitePyc.Count -gt 0) { Add-Todo 5 'A leftover cook.pyc can come from the LiteLLM 1.107.0 malware. If litellm 1.107.0 was ever installed there, treat this machine as compromised, follow LiteLLM''s advisory and rotate every key it could reach.' }
if ($PyHits.Count -gt 1) { $adv = 'each advisory in section 5' } else { $adv = "$PyShort's advisory" }
# "Don't run Python" only when a Python environment holds the bad package, not for a temp file alone.
$PyEnv = @($LiteBad | Where-Object { $PyHits -contains $_[0] }).Count -gt 0
if ($PY_HIT -eq 1 -and $PyEnv) { Add-Todo 5 "Treat this machine as compromised. Don't run Python in the affected environments, follow $adv, and rotate every key the machine could reach." }
elseif ($PY_HIT -eq 1) { Add-Todo 5 "Treat this machine as compromised. Stop any process started from the files listed in section 5, delete them, follow $adv, and rotate every key the machine could reach." }
Add-Advice 'act'
Add-Advice 'update'
$Store = 'a secrets manager'; if ($OnWindows) { $Store = 'Windows Credential Manager or a secrets manager' }
$N_AK = $AkLinks.Count
if ($N_AK -gt 0) { Add-Todo 2 'Delete the links to ~/.ssh/authorized_keys listed in section 2.' }
if ($KEY_FILES -gt 0) { Add-Todo 3 "Move keys out of shell profiles, history and .env files into $Store, then rotate them." }
if ($HIST_KEYS -gt 0) { Add-Todo 3 'Keys in shell history were typed into a command. Treat them as exposed and rotate them.' }
if ($N_SESS -gt 0) { Add-Todo 3 "Keys turned up in $(Plural $N_SESS 'agent session file' 'agent session files'). An agent read or was given them: treat them as exposed and rotate them." }
if ($N_MCP_TOKEN -gt 0) { Add-Todo 2 'Replace tokens written into MCP configs with environment variable references, then rotate them.' }
if ($N_ALLOW -gt 0) { Add-Todo 4 'Delete the saved Claude Code commands that contain keys, add .claude/ to .npmignore, and rotate those keys.' }
if ($N_SSH_OPEN -gt 0) { Add-Todo 3 'Add a passphrase to SSH keys that have none, with ssh-keygen -p -f followed by the key file.' }
if ($N_YOLO -gt 0) { Add-Todo 1 'Turn off run-without-asking in the agents listed in section 1, unless they run in a sandbox.' }
if ($N_OLD -gt 0) { Add-Todo 1 'Update the tools listed in section 1 that have a security fix.' }
if ($N_IDLE -gt 0) { Add-Todo 1 "Remove agents you no longer use: $($IdleNames -join ', '). A poisoned package can drive an installed agent, which is how the Nx attack stole keys." }
if ($N_AUTO -gt 0) { Add-Todo 2 'Read the settings marked in section 2 before an agent or editor opens those folders, and delete anything you didn''t put there yourself. A cloned project can bring these with it.' }
if ($N_LOOK -gt 0) { Add-Todo 2 'Read the files section 2 lists as named like files worms plant, and delete any you didn''t put there yourself.' }
if ($MAL_HIT -eq 0 -and $NPM_UPD -eq 1) { Add-Todo 5 'Update the npm packages listed in section 5 to a version without the malware, and clear npm''s cache with npm cache clean --force.' }
if ($PY_HIT -eq 0 -and $PY_UPD_HIT -eq 1) { Add-Todo 5 'Update the Python packages listed in section 5 to a version without the malware.' }
if ($PlatFound.Count -gt 0) { Add-Todo 5 "If you used $PlatFix, rotate the keys stored there, even if nothing above looks wrong." }
$ISSUES = $Todo.Count

$SCORE = 100
if ($PY_HIT -eq 1) { $SCORE -= 40 }
if ($ANY_MAL -eq 1) { $SCORE -= 40 }
$SCORE -= [Math]::Min($KEY_FILES * 8, 32)
$SCORE -= [Math]::Min($HIST_KEYS * 6, 12)
$SCORE -= [Math]::Min($N_ALLOW * 10, 20)
$SCORE -= [Math]::Min($N_MCP_TOKEN * 6, 12)
$SCORE -= [Math]::Min($N_IDLE * 3, 12)
if ($N_SSH_OPEN -gt 0) { $SCORE -= 4 }
if ($SCORE -lt 0) { $SCORE = 0 }
if ($SCORE -ge 90) { $GRADE = 'A' } elseif ($SCORE -ge 78) { $GRADE = 'B' } elseif ($SCORE -ge 64) { $GRADE = 'C' } elseif ($SCORE -ge 50) { $GRADE = 'D' } else { $GRADE = 'F' }
# GRADE only goes in the research counts. People see how they compare instead.
$SCAN_SECS = [int][Math]::Floor(([DateTime]::UtcNow - $ScanT0).TotalSeconds)
Progress-Clear

# ---------------------------------------------------------------------------
# Counts for GIRD's research, sent once when the scan is done unless -Offline or
# DO_NOT_TRACK=1, with the same fields as gird-check.sh. Never a path, a file name,
# a key, a name you gave an MCP server, a username, a hostname or the raw machine
# ID. The device ID is a one-way SHA-256 of the Windows MachineGuid salted for this
# script, the same one gird-check.sh computes in Git Bash on this computer.
# ---------------------------------------------------------------------------
function Json-List($ids) { '[' + ((@($ids) | Where-Object { $_ } | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']' }
function Json-Tally([string]$list, $tally) {
  $parts = foreach ($id in (Ids $list)) { if ($tally.ContainsKey($id)) { '"' + $id + '":' + $tally[$id] } }
  '{' + (@($parts) -join ',') + '}'
}
function Count-Of($items) { $t = @{}; foreach ($x in $items) { if ($t.ContainsKey($x)) { $t[$x]++ } else { $t[$x] = 1 } }; $t }
function Sha256Hex([string]$s) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
}
$Guid = ''
if ($env:GIRD_CHECK_TEST_MACHINEGUID) { $Guid = $env:GIRD_CHECK_TEST_MACHINEGUID }   # tests only
elseif ($OnWindows) {
  # The 64-bit view, so 32-bit PowerShell on 64-bit Windows reads the same value.
  try {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $k = $base.OpenSubKey('SOFTWARE\Microsoft\Cryptography')
    if ($k) { $Guid = [string]$k.GetValue('MachineGuid'); $k.Close() }
    $base.Close()
  } catch { $Guid = '' }
}
$DEVICE_ID = ''; if ($Guid) { $DEVICE_ID = Sha256Hex "gird-check-v1:$Guid" }
$Guid = ''
if ($DEVICE_ID -cnotmatch '^[0-9a-f]{64}$') { $DEVICE_ID = '' }
$rb = New-Object byte[] 8; $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($rb); $rng.Dispose()
$RUN_ID = -join ($rb | ForEach-Object { $_.ToString('x2') })
if ($OnWindows) {
  $ov = [Environment]::OSVersion.Version
  if ($ov.Major -eq 10) { if ($ov.Build -ge 22000) { $OSV = 'Windows 11' } else { $OSV = 'Windows 10' } } else { $OSV = 'Windows' }
} elseif (Is-Dir '/System/Library/CoreServices') { $OSV = 'macOS' } else { $OSV = 'Linux' }
# The processor itself, even when PowerShell runs emulated on an Arm PC.
$archRaw = ''
if ($OnWindows) {
  try {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $k = $base.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
    if ($k) { $archRaw = [string]$k.GetValue('PROCESSOR_ARCHITECTURE'); $k.Close() }
    $base.Close()
  } catch { }
  if (-not $archRaw) { $archRaw = $env:PROCESSOR_ARCHITEW6432 }
  if (-not $archRaw) { $archRaw = $env:PROCESSOR_ARCHITECTURE }
} else {
  try { $archRaw = [string][Runtime.InteropServices.RuntimeInformation]::OSArchitecture } catch { }
}
switch (([string]$archRaw).ToUpperInvariant()) { 'ARM64' { $ARCH_ID = 'arm64' } 'AMD64' { $ARCH_ID = 'x86_64' } 'X64' { $ARCH_ID = 'x86_64' } default { $ARCH_ID = 'other' } }
$MODEL = ''
if ($env:WT_SESSION) { $TERMAPP = 'windows-terminal' }
else {
  switch ($env:TERM_PROGRAM) {
    'vscode' { $TERMAPP = 'vscode' } 'WezTerm' { $TERMAPP = 'wezterm' } 'Hyper' { $TERMAPP = 'hyper' } 'tmux' { $TERMAPP = 'tmux' }
    'Apple_Terminal' { $TERMAPP = 'terminal' } 'iTerm.app' { $TERMAPP = 'iterm2' } 'WarpTerminal' { $TERMAPP = 'warp' } 'ghostty' { $TERMAPP = 'ghostty' }
    default { if ($env:TERM_PROGRAM) { $TERMAPP = 'other' } elseif ($OnWindows) { $TERMAPP = 'conhost' } else { $TERMAPP = 'unknown' } }
  }
}
$TMUXED = 0; if ($env:TMUX) { $TMUXED = 1 }
if ($IsCore) { $SHELLNAME = 'pwsh' } else { $SHELLNAME = 'powershell' }
$LANGCODE = 'other'
try { $cn = [Globalization.CultureInfo]::CurrentCulture.Name -replace '-', '_'; if ($cn -cmatch '^[a-z]{2}(_[A-Z]{2})?$') { $LANGCODE = $cn } } catch { }
$VIA = 'none'; if ($env:CLAUDECODE) { $VIA = 'claude-code' }
$N_FOUND = $Found.Count; $N_ENVF = @($EnvFiles).Count; $N_ALLOWF = @($AllowFiles).Count
$N_MCPF = @($McpRows | Where-Object { -not $_.Pl }).Count
$mm = Mcp-Match $McpNames
$J_MCPC = Json-Tally $MCP_CLIENT_IDS $McpTally
$J_PLACES = Json-Tally $KEY_PLACE_IDS (Count-Of $KeyPlaces)
$J_PROVF = Json-Tally $PROVIDER_IDS (Count-Of $ProvTally)
# Not $OPTALL: variable names ignore case, so it would be $OptAll itself, reset to 0 before the test.
$AllFolders = 0; if ($OptAll) { $AllFolders = 1 }
$PAYLOAD = "{""v"":""1"",""kind"":""report"",""run_id"":""$RUN_ID"",""device_id"":""$DEVICE_ID"",""script"":""$ScriptVersion"",""os"":""$OSV"",""arch"":""$ARCH_ID"",""model"":""$MODEL"",""terminal"":""$TERMAPP"",""tmux"":$TMUXED,""shell"":""$SHELLNAME"",""bash"":0,""lang"":""$LANGCODE"",""via"":""$VIA"",""grade"":""$GRADE"",""score"":$SCORE,""agents"":$(Json-List $AgentIds),""agents_idle"":$N_IDLE,""agents_idle_ids"":$(Json-List $IdleIds),""mcp_servers"":$N_MCP,""mcp_configs"":$N_MCPF,""mcp_token_files"":$N_MCP_TOKEN,""mcp_clients"":$J_MCPC,""mcp_token_clients"":$(Json-List $McpTokIds),""mcp_known"":$(Json-List $mm.Known),""mcp_other"":$($mm.Other),""key_files"":$KEY_FILES,""key_places"":$J_PLACES,""key_providers"":$(Json-List $ProvIds),""provider_files"":$J_PROVF,""history_keys"":$HIST_KEYS,""env_files"":$N_ENVF,""allow_list_files"":$N_ALLOWF,""allow_list_keys"":$N_ALLOW,""allow_list_npm"":$N_ALLOW_NPM,""login_files"":$(Json-List $LoginIds),""ssh_keys"":$N_SSH,""ssh_no_passphrase"":$N_SSH_OPEN,""python_envs"":$N_PY,""litellm_installed"":$N_LITE,""litellm_found"":$LITELLM_HIT,""opencode"":$OC,""railway"":$RW,""files_found"":$N_FOUND,""scan_seconds"":$SCAN_SECS,""all_folders"":$AllFolders,""game_played"":0,""game_best"":0,""results_wait_seconds"":0}"
# The reply holds p, the share of people whose latest run scored lower, n, how many
# people that is, and r, this device's place in line. Only digits are read from it.
$PCT = ''; $PCT_N = ''; $RANK = ''; $LinkRunId = ''
if (-not $OptOffline) {
  $LinkRunId = $RUN_ID   # the result link carries the run ID only when a report did
  if ($IsConsole) { Out-Text "  ${cDim}Comparing with other AI builders...$cRst" }
  $rp = Http 'POST' $Api 3 $PAYLOAD 65536
  if ($rp.Length -gt 4096) { $rp = $rp.Substring(0, 4096) }
  $rp = $rp -replace '\s', ''
  Progress-Clear
  $p = JNum 'p' $rp; $n = JNum 'n' $rp; $rk = JNum 'r' $rp
  if ($p -and $n -and $n.Length -le 9 -and [long]$p -ge 1 -and [long]$p -le 99 -and [long]$n -ge 1) { $PCT = $p; $PCT_N = $n }
  if ($rk -and $rk -cmatch '^[1-9][0-9]{0,8}$') { $RANK = $rk }
}

# ===========================================================================
# The report. Every part is built first, then shown: a summary on a console, or
# every detail with -Full or when the output is redirected. A saved report always
# has every detail.
# ===========================================================================
# A check that was not done in full never leaves the headline green: the sessions were partly
# checked, a key file, part of npm's cache or an extension folder could not be read, or a file took
# too long. The headline then says what it can: no findings in the paths checked.
$Partial = [bool]($HOME_PARTIAL -eq 1 -or $SESS_PARTIAL -or $KeyUnread.Count -gt 0 -or $NpmUnread -gt 0 -or $LockUnread.Count -gt 0 -or $NpmSlow -gt 0 -or $SlowFiles.Count -gt 0 -or $ExtUnread -gt 0)
if ($PY_HIT -eq 1 -or $ANY_MAL -eq 1) { $Sev = $cRed }
elseif ($KEY_FILES -gt 0 -or $N_ALLOW -gt 0 -or $N_MCP_TOKEN -gt 0 -or $N_AK -gt 0) { $Sev = $cRed }
elseif ($ISSUES -gt 0 -or $Partial) { $Sev = $cYel } else { $Sev = $cGrn }
if ($ISSUES -gt 0) { $FixN = "$(Plural $ISSUES 'thing' 'things') to fix" } elseif ($Partial) { $FixN = 'No findings in the paths checked' } else { $FixN = 'No findings in this scan' }
$PctTxt = ''; if ($PCT) { $PctTxt = "Better than $PCT% of AI builders who ran Blindspot" }
$SlowText = "$(Plural $SlowFiles.Count 'file' 'files') skipped: took too long to check"
$Stats = "$(Plural $N_AG 'coding agent' 'coding agents'), $N_IDLE not used in 30 days, $(Plural $N_MCP 'MCP server' 'MCP servers'), $(Plural $KEY_FILES 'file' 'files') with keys in plain text, $(Plural $N_ALLOW 'key' 'keys') in allow lists"
$Capture = $true; [void]$Cap.Clear()
# The first 1,000 are told so, above either header. The place in line itself is never shown.
if (($RANK -and [long]$RANK -le 1000) -or (-not $RANK -and $Early)) {
  Wrap "You're one of the first 1,000 AI builders to run Blindspot." 4 "  $cGold$gStar$cRst " '    ' $cBold; Blank
}
$Act = ''
if ($WIPER_HIT -eq 1) { $Act = 'ACT NOW: REMOVE GH-TOKEN-MONITOR BEFORE YOU REVOKE ANY TOKEN' }
elseif ($ANY_MAL -eq 1 -and ($MAL_LOCKONLY -eq 0 -or $EXT_HIT -eq 1)) { $Act = "ACT NOW: SIGNS OF $($MalWhat.ToUpperInvariant())" }
elseif ($PY_HIT -eq 1) { $Act = "ACT NOW: SIGNS OF THE $((@($PyHits | ForEach-Object { Incident-Name $_ }) -join ' AND ').ToUpperInvariant()) MALWARE" }
elseif ($MAL_LOCKONLY -eq 1) {
  if ($N_LOCKPROJ -eq 1) { $Act = 'ACT NOW IF YOU INSTALLED IT: A LOCKFILE LISTS NPM MALWARE' } else { $Act = 'ACT NOW IF YOU INSTALLED THEM: LOCKFILES LIST NPM MALWARE' }
}
if ($Act) {
  Emit "  $Sev$gBar$cRst $cBold$Act$cRst"
  if ($PctTxt) { Emit "  $Sev$gBar$cRst $cBold$PctTxt.$cRst $FixN." } else { Emit "  $Sev$gBar$cRst $FixN." }
} elseif ($PctTxt) {
  Emit "  $Sev$gBar$cRst $cBold$($PctTxt.ToUpperInvariant())$cRst"
  Emit "  $Sev$gBar$cRst $FixN."
} else {
  Emit "  $Sev$gBar$cRst $cBold$($FixN.ToUpperInvariant())$cRst"
}
$HeadShort = Take-Cap
Wrap $Stats 4 "  $Sev$gBar$cRst " "  $Sev$gBar$cRst " $cDim
# Folders the home scan could not read, so sections 2 to 5 did not read the files in them.
function Dir-List($dirs) { $da = @($dirs); $dl = (@($da | Select-Object -First 3 | ForEach-Object { Short $_ })) -join ', '; if ($da.Count -gt 3) { $dl += " and $($da.Count - 3) more" }; $dl }
if ($UnreadDirs.Count -gt 0) {
  if ($UnreadDirs.Count -eq 1) { $udText = '1 folder in your home could not be read, so sections 2 to 5 did not check the files in it' }
  else { $udText = "$($UnreadDirs.Count) folders in your home could not be read, so sections 2 to 5 did not check the files in them" }
  Wrap "$($udText): $(Dir-List $UnreadDirs)." 4 "  $cYel$gBar$cRst " "  $cYel$gBar$cRst " $cYel
}
$HeadFull = $HeadShort + (Take-Cap)

Section '01' 'CODING AGENTS' "$N_AG found, $N_IDLE idle"
if ($N_AG -eq 0) { Emit '     No coding agents found.' }
foreach ($r in $AgRows) {
  switch ($r[1]) {
    'active' { Pair "$cGrn$gDot$cRst" $r[0] 20 'used in the last 30 days' }
    'idle' { Pair "$cYel$gRing$cRst" $r[0] 20 "${cDim}installed, not used in 30 days$cRst" }
    'unused' { Pair "$cYel$gRing$cRst" $r[0] 20 "${cDim}installed, no use recorded$cRst" }
    default { Pair "$cDim$gBul$cRst" $r[0] 20 "${cDim}installed$cRst" }
  }
}
if ($N_YOLO -gt 0) {
  Blank
  Emit "     ${cBold}Agents set to run commands without asking$cRst"
  foreach ($r in $AaList) { Pair "$cYel!$cRst" ('{0,-16} {1}' -f $r.Agent, (Short $r.File)) 46 $r.Setting }
  Wrap 'A prompt injection in anything the agent reads can then run commands on this computer. Turn it off unless the agent runs in a sandbox.' 8 '        ' '        ' $cDim
}
if ($N_OLD -gt 0) {
  Blank
  Emit "     ${cBold}Tools with a security fix to install$cRst"
  foreach ($r in $OldList) {
    Pair "$cYel!$cRst" $r.Name 20 "$($r.Vers -join ', '), update to $($r.Fixed) or later"
    Wrap "$($r.Hole.Substring(0, 1).ToUpperInvariant())$($r.Hole.Substring(1)). $($r.Src)" 8 '        ' '        ' $cDim
  }
}
$Sec1 = Take-Cap
Section '02' 'MCP SERVERS' (Plural $N_MCP 'server' 'servers')
if ($N_MCP -eq 0 -and $N_MCP_TOKEN -eq 0) { Emit '     No MCP servers configured.' }
foreach ($r in $McpRows) {
  if ($r.Pl -and -not $r.Tok) { continue }
  if ($null -ne $r.Count) { $d = Plural $r.Count 'server' 'servers' } else { $d = 'servers configured' }
  $nm = '{0,-14} {1}' -f $r.Who, (Short $r.File)
  if ($r.Tok) { Pair "$cRed$gX$cRst" $nm 46 "$d, ${cRed}token in the file$cRst" } else { Pair "$cTeal$gBul$cRst" $nm 46 $d }
}
if ($N_MCP_CACHE -gt 0) {
  Pair "$cDim$gMid$cRst" 'Plugin folders' 46 "$cDim$(Plural $N_MCP_CACHE 'server' 'servers') in $(Plural $N_MCP_CACHEF 'file' 'files'), not counted above$cRst"
}
if ($N_AUTO -gt 0) {
  Blank
  Emit "     ${cBold}Project settings that act as soon as the folder is opened$cRst"
  foreach ($r in $AutoRows) {
    Emit "     $cYel!$cRst  $(Short $r.File)"
    $more = ''; if ($r.More -gt 0) { $more = " The same settings are in $(Plural $r.More 'more folder' 'more folders'), such as worktrees." }
    Wrap "Set to $($r.What).$more" 8 '        ' '        ' $cDim
  }
}
if ($N_LOOK -gt 0) {
  Blank
  Emit "     ${cBold}Files named like the ones worms plant$cRst"
  foreach ($f in $WormLook) {
    Emit "     $cYel!$cRst  $(Short $f)"
    Wrap "Named like $(Planted-Note (Planted-Rel $f)), with nothing else of theirs beside it. If you didn't put it there, read it before an agent or editor opens this folder." 8 '        ' '        ' $cDim
  }
}
if ($N_AK -gt 0) {
  Blank
  Emit "     ${cBold}Files that link to your SSH logins$cRst"
  foreach ($f in $AkLinks) { Emit "     $cRed$gX$cRst  $(Short $f)" }
  Wrap 'An agent that edits this file adds a login to this computer. Delete the link.' 8 '        ' '        ' $cRed
}
$Sec2 = Take-Cap
Section '03' 'KEYS IN PLAIN TEXT' (Plural $KEY_FILES 'file' 'files')
# With files that could not be read, this line comes below, with them.
if ($KEY_FILES -eq 0 -and $KeyUnread.Count -eq 0 -and $HOME_PARTIAL -eq 1) { Wrap 'No AI or cloud keys in shell profiles, history, agent configs or .env files, but some folders in your home were not read.' 8 "     $cYel!$cRst  " '        ' }
elseif ($KEY_FILES -eq 0 -and $KeyUnread.Count -eq 0) { Wrap 'No AI or cloud keys in shell profiles, history, agent configs or .env files.' 8 "     $cGrn$gOk$cRst  " '        ' }
$shown = 0
foreach ($r in $KeyRows) { $shown++; if ($shown -le 20) { Pair "$cRed$gX$cRst" (Short $r[0]) 44 $r[1] } }
if ($KEY_FILES -gt 20) { Emit "        ${cDim}and $($KEY_FILES - 20) more$cRst" }
# The files that could not be read, named, so none of them is taken for one without keys.
if ($KeyUnread.Count -gt 0) {
  $ku = Plural $KeyUnread.Count 'file' 'files'
  if ($KEY_FILES -gt 0) { $kt = "$ku could not be read, so this is not the full list:" }
  elseif ($HOME_PARTIAL -eq 1) { $kt = "No AI or cloud keys in the files read, but $ku and some folders in your home could not be read:" }
  else { $kt = "No AI or cloud keys in the files read, but $ku could not be read:" }
  Wrap $kt 8 "     $cYel!$cRst  " '        '
  foreach ($f in ($KeyUnread | Select-Object -First 20)) { Emit "        $(Short $f)" }
  if ($KeyUnread.Count -gt 20) { Emit "        ${cDim}and $($KeyUnread.Count - 20) more$cRst" }
}
if ($SlowFiles.Count -gt 0) {
  Blank
  Emit "     $cYel!$cRst  $cBold$SlowText$cRst"
  foreach ($f in ($SlowFiles | Select-Object -First 20)) { Emit "        $(Short $f)" }
}
if ($LoginsText) {
  Blank
  Emit "     ${cBold}Login files any agent you run can read$cRst"
  Wrap $LoginsText 8 '        ' '        '
}
if ($SESS_TOTAL -gt 0 -or $SESS_UNREAD -ne 0 -or $SessSealedN -gt 0) {
  Blank
  Emit "     ${cBold}Keys in agent sessions$cRst"
  foreach ($r in $SessRows) { Pair "$cRed$gX$cRst" $r[0] 20 "$(Plural $r[1] 'file' 'files'): $($r[2])" }
  if ($N_SESS -gt 0) {
    $placeShow = @($SessPlaces | Select-Object -First 20)
    $cw = 0; foreach ($g in $placeShow) { $cw = [Math]::Max($cw, (Plural $sessPlaceN[$g] 'file' 'files').Length) }
    $fw = 80 - 8 - 2 - $cw
    foreach ($g in $placeShow) {
      $d = Short $g
      if ($d.Length -gt $fw) { $hd = [int][Math]::Floor(($fw - 3) / 2); $d = $d.Substring(0, $hd) + '...' + $d.Substring($d.Length - ($fw - 3 - $hd)) }
      Emit ("        $cDim" + $d.PadRight($fw) + '  ' + (Plural $sessPlaceN[$g] 'file' 'files').PadLeft($cw) + $cRst)
    }
    if ($N_PLACES -gt 20) { Emit "        ${cDim}and $($N_PLACES - 20) more$cRst" }
    Wrap (Wiper-Wait 'Treat these keys as exposed and rotate them.') 8 '        ' '        '
  }
  $allTxt = 'Install ripgrep, or add -AllSessions, to check all of them.'
  if ($SESS_NOTRUN -gt 0) {
    $why = '.'; if ($SessSt.Failed) { $why = ': the check could not start.' }
    Wrap "$(Plural $SESS_NOTRUN 'agent session file was' 'agent session files were') not checked$why" 8 "     $cYel!$cRst  " '        '
  }
  elseif ($SESS_DONE -lt 0) { Wrap 'Agent sessions were partly checked. Add -AllSessions to check all of them.' 8 "     $cYel!$cRst  " '        ' }
  elseif (($SESS_DONE + $SESS_UNREAD_FILES) -lt ($SESS_TOTAL - $SESS_ZST)) { Wrap "Checked the newest $(Commas $SESS_DONE) of $(Commas $SESS_TOTAL) agent session files. $allTxt" 8 "     $cYel!$cRst  " '        ' }
  elseif ($N_SESS -eq 0 -and $SESS_DONE -gt 0 -and $SESS_UNREAD -eq 0 -and $SESS_UNREAD_FILES -eq 0) {
    # The files read, not the compressed ones, which are named below.
    Emit "     $cGrn$gOk$cRst  No keys in $(Plural (Commas $SESS_DONE) 'agent session file' 'agent session files')."
  }
  $urParts = @()
  if ($SESS_UNREAD -gt 0) { $urParts += (Plural $SESS_UNREAD 'folder' 'folders') }
  if ($SESS_UNREAD_FILES -gt 0) { $urParts += (Plural $SESS_UNREAD_FILES 'file' 'files') }
  if ($urParts.Count -gt 0) { Wrap "Agent sessions were partly checked: $($urParts -join ' and ') could not be read." 8 "     $cYel!$cRst  " '        ' }
  elseif ($SESS_UNREAD -lt 0) { Wrap 'Agent sessions were partly checked: some files or folders could not be read.' 8 "     $cYel!$cRst  " '        ' }
  if ($SESS_ZST -gt 0) { Wrap "$(Plural $SESS_ZST 'compressed session file was' 'compressed session files were') not checked." 8 "     $cYel!$cRst  " '        ' }
  if ($SessSealedN -gt 0) {
    $sealVerb = 'conversation files are encrypted, so they were'; if ($SessSealedN -eq 1) { $sealVerb = 'conversation file is encrypted, so it was' }
    Wrap "$SessSealedN $($SessSealedAg -join ' and ') $sealVerb not checked." 8 '        ' '        ' $cDim
  }
}
$Sec3 = Take-Cap
Section '04' 'KEYS IN CLAUDE CODE ALLOW LISTS' (Plural $N_ALLOW 'file' 'files')
if ($N_ALLOW -eq 0 -and $HOME_PARTIAL -eq 1) { Wrap 'No saved commands with keys, but some folders in your home were not read.' 8 "     $cYel!$cRst  " '        ' }
elseif ($N_ALLOW -eq 0) { Emit "     $cGrn$gOk$cRst  No saved commands with keys." }
foreach ($r in $AllowRows) {
  Emit "     $cRed$gX$cRst  $(Short $r[0])"
  Emit '        A saved command contains a key.'
  if ($r[1]) { Wrap 'An npm publish from this folder would include it.' 8 '        ' '        ' $cRed }
}
$Sec4 = Take-Cap
$ind26 = ' ' * 26
$N_LEAKS = @($PyIncidents).Count + 2 + @($Platforms).Count   # the Python incidents, npm, editor extensions and each platform
Section '05' 'RECENT KEY LEAKS' "$N_LEAKS checked"
# One row per Python incident. cook.pyc, the installed versions and the loader are LiteLLM's. The
# advice under a hit: for a bad package in an environment, don't run Python there; for its temp
# files, the incident's own (data/indicators.tsv); for a version whose malware could not run on this
# OS (data/bad-pypi.tsv), update it.
function Os-Name([string]$o) { switch ($o) { 'mac' { 'macOS' } 'linux' { 'Linux' } 'win' { 'Windows' } default { $o } } }
foreach ($pi in $PyIncidents) {
  $pl = Incident-Name $pi
  $upd = @($PyUpd | Where-Object { $_[0] -ceq $pi })
  $do = ''
  if ($PyHits -contains $pi) {
    Pair "$cRed$gX$cRst" $pl 16 "${cRed}signs of the malware found$cRst"
    foreach ($l in $LiteBad) { if ($l[0] -ceq $pi) { Emit "        $(Short $l[1])" } }
    foreach ($l in $Marks) { if ($l[0] -ceq $pi) { Emit "        $(Short $l[1])" } }
    if (@($LiteBad | Where-Object { $_[0] -ceq $pi }).Count -gt 0) { $do = "Don't run Python or pip in these environments." }
    if (@($Marks | Where-Object { $_[0] -ceq $pi }).Count -gt 0 -or -not $do) { $do = (@($do, (Temp-Advice $pi)) | Where-Object { $_ }) -join ' ' }
  } elseif ($upd.Count -gt 0) {
    Pair "$cYel!$cRst" $pl 16 "${cYel}a bad version to update$cRst"
  } elseif ($pi -eq 'litellm' -and $LitePyc.Count -gt 0) {
    Pair "$cYel!$cRst" $pl 16 "${cYel}possible leftover$cRst"
    foreach ($l in $LitePyc) { Emit "        $l" }
    Wrap "A compiled cook file stays behind when cook.py is deleted, which is what the 1.107.0 malware ships. If litellm 1.107.0 was ever installed here, treat this as a hit. Advisory: $(Incident-Source $pi)" 8 '        ' '        '
  } else {
    Pair "$cGrn$gOk$cRst" $pl 16 "no signs in $(Plural $N_PY 'Python environment' 'Python environments')"
    if ($pi -eq 'litellm' -and $N_LITE -gt 0) { Emit "$ind26${cDim}installed: $(Short ($LiteVers -join ' '))$cRst" }
  }
  if ($upd.Count -gt 0) {
    $oss = @()
    foreach ($u in $upd) { Emit "        $(Short $u[2])"; $osn = Os-Name $u[1]; if ($oss -notcontains $osn) { $oss += $osn } }
    $do = (@($do, "Its malware runs on $($oss -join ' and ') only, so it did not run here. Update to a version without it.") | Where-Object { $_ }) -join ' '
  }
  if ($do) { Wrap "$do Advisory: $(Incident-Source $pi)" 8 '        ' '        ' }
  foreach ($r in $UvBad) { if ($r[2] -ceq $pi) { Wrap "Your uv cache holds the $($r[1]) package. Clear it with: uv cache clean $($r[0])" 8 '        ' '        ' $cYel } }
}
if ($WIPER_HIT -eq 1) {
  Pair "$cRed$gX$cRst" 'npm malware' 16 "${cRed}a wiper is waiting$cRst"
  foreach ($l in $Wiper) { Emit "        $(Short $l)" }
  if ($OnWindows) { $stop = 'Get-CimInstance Win32_Process | Where-Object CommandLine -like ''*gh-token-monitor*'' | Invoke-CimMethod -MethodName Terminate, then ' }
  elseif (Is-Dir '/System/Library/CoreServices') { $uidv = ''; try { $uidv = [string](& id -u 2>$null) } catch { }; $stop = "launchctl bootout gui/$uidv/com.user.gh-token-monitor, then pkill -f gh-token-monitor, then " }
  else { $stop = 'systemctl --user disable --now gh-token-monitor.service, then pkill -f gh-token-monitor, then ' }
  Wrap "Don't revoke any GitHub token until it is stopped and these files are gone: gh-token-monitor runs a destructive command when the stolen token stops working, and in the TanStack wave it tries to erase the home folder." 8 '        ' '        ' $cRed
  Wrap "Stop it with $($stop)delete the files above." 8 '        ' '        ' $cRed
}
if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0 -or $NPM_UPD -eq 1) {
  if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0) {
    if ($WIPER_HIT -eq 0) { Pair "$cRed$gX$cRst" 'npm malware' 16 "${cRed}signs of the malware found$cRst" }
  } else { Pair "$cYel!$cRst" 'npm malware' 16 "${cYel}a bad version to update$cRst" }
  foreach ($r in $NpmRows) {
    if ($r[0].EndsWith($NpmCacheTag)) { $w = "downloaded into npm's cache" }
    elseif ($r[0] -match '[/\\](package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lock)$') { $w = 'listed in this lockfile' }
    else { $w = 'installed' }
    Emit "        $(Short $r[0])"; Emit "          $($r[1]) ${cDim}($(Npm-Label $r[2])), $w$cRst"
  }
  foreach ($r in $Persist) { Emit "        $(Short $r[0])"; Emit "          $($r[1])" }
  foreach ($t in $NpmTags) { Wrap (Incident-Line $t) 8 '        ' '        ' $cDim }
}
# What of npm's places could not be read: part of its cache, lockfiles, folders the scan could not
# enter. The row is never green over them, and findings above them are not the full list.
$npParts = New-Object System.Collections.Generic.List[string]
if ($NpmUnread -gt 0) { $npParts.Add("part of npm's cache") }
if ($LockUnread.Count -gt 0) { $npParts.Add((Plural $LockUnread.Count 'lockfile' 'lockfiles')) }
if ($HOME_PARTIAL -eq 1) { $npParts.Add('some folders in your home') }
$npText = ''
if ($npParts.Count -eq 1) { $npText = $npParts[0] } elseif ($npParts.Count -eq 2) { $npText = $npParts[0] + ' and ' + $npParts[1] } elseif ($npParts.Count -eq 3) { $npText = $npParts[0] + ', ' + $npParts[1] + ' and ' + $npParts[2] }
$npFound = ($NPM_HIT -eq 1 -or $Persist.Count -gt 0 -or $NPM_UPD -eq 1)
if (-not $npFound -and $WIPER_HIT -eq 0 -and ($NpmSlow -gt 0 -or $npText)) {
  $why = New-Object System.Collections.Generic.List[string]
  if ($NpmSlow -gt 0) { $why.Add("$(Plural $NpmSlow 'file' 'files') took too long") }
  if ($npText) { $why.Add("$npText could not be read") }
  Pair "$cYel!$cRst" 'npm malware' 16 "${cYel}not fully checked: $($why -join ', ')$cRst"
  foreach ($f in $LockUnread) { Emit "        $(Short $f)" }
} elseif (-not $npFound -and $WIPER_HIT -eq 0) {
  Pair "$cGrn$gOk$cRst" 'npm malware' 16 "none of $($NpmBad.Count) bad versions or $($NpmAny.Count) bad packages"
  Emit "$ind26${cDim}checked $(Plural $N_LOCK 'lockfile' 'lockfiles'), global installs and npm's cache$cRst"
}
# With findings above, a part of the check that did not finish still has to be said.
if (($NpmSlow -gt 0 -or $npText) -and ($WIPER_HIT -eq 1 -or $npFound)) {
  if ($NpmSlow -gt 0) { Wrap "$(Plural $NpmSlow 'file' 'files') took too long to check, so this is not the full list." 8 '        ' '        ' $cYel }
  if ($npText) {
    Wrap "$($npText.Substring(0, 1).ToUpperInvariant())$($npText.Substring(1)) could not be read, so this is not the full list." 8 '        ' '        ' $cYel
    foreach ($f in $LockUnread) { Emit "        $(Short $f)" }
  }
}
if ($EXT_HIT -eq 1) {
  Pair "$cRed$gX$cRst" 'Editor extensions' 16 "${cRed}signs of the malware found$cRst"
  foreach ($r in $ExtRows) { Emit "        $(Short $r[0])"; Emit "          $($r[1]) ${cDim}($(Npm-Label $r[2])), installed$cRst" }
  foreach ($r in $ExtPersist) { Emit "        $(Short $r[0])"; Emit "          $($r[1])" }
  foreach ($t in $ExtTags) { Wrap (Incident-Line $t) 8 '        ' '        ' $cDim }
} elseif ($ExtCheck.Count -gt 0) {
  Pair "$cYel!$cRst" 'Editor extensions' 16 "${cYel}a startup file to check$cRst"
  foreach ($r in $ExtCheck) { Emit "        $(Short $r[0])"; Emit "          has the name of a file that $($r[1])" }
  Wrap 'No editor extension that shipped malware was found. Open the file and check what it starts: if you did not set it up yourself, treat this machine as compromised.' 8 '        ' '        '
  foreach ($t in $ExtCheckTags) { Wrap (Incident-Line $t) 8 '        ' '        ' $cDim }
} elseif ($ExtUnread -gt 0) {
  Pair "$cYel!$cRst" 'Editor extensions' 16 "${cYel}not fully checked: $(Plural $ExtUnread 'extension folder' 'extension folders') could not be read$cRst"
} else {
  Pair "$cGrn$gOk$cRst" 'Editor extensions' 16 "none of $(@($BadExtRows | Where-Object { $_[1] -ne '*' }).Count) bad versions or $(@($BadExtRows | Where-Object { $_[1] -eq '*' }).Count) bad extensions"
  Wrap 'checked the extension folders of VS Code, Cursor, Windsurf, Devin Desktop, VSCodium and Kiro' 26 $ind26 $ind26 $cDim
}
# With findings above, a folder that could not be read still has to be said.
if ($ExtUnread -gt 0 -and ($EXT_HIT -eq 1 -or $ExtCheck.Count -gt 0)) {
  if ($ExtUnread -eq 1) { $xmsg = 'An extension folder' } else { $xmsg = 'Some extension folders' }
  Wrap "$xmsg could not be read, so this is not the full list." 8 '        ' '        ' $cYel
}
foreach ($p in $Platforms) {
  if ($PlatFound -contains $p.Id) {
    Pair "$cYel!$cRst" $p.Name 16 $p.Found
    Wrap (Wiper-Wait $p.Advice) 26 $ind26 $ind26 $cDim
  } else {
    if ($p.Found.EndsWith(' found')) { $w = $p.Found.Substring(0, $p.Found.Length - 6) + ' not found' } else { $w = 'not ' + $p.Found }
    Pair "$cDim$gMid$cRst" $p.Name 16 "$cDim$w$cRst"
  }
}
$Sec5 = Take-Cap
Heading 'WHAT TO DO' 'most urgent first'
$i = 0
foreach ($t in $Todo) { $i++; Wrap $t 10 "     $cTeal$($i.ToString().PadLeft(2)).$cRst  " '          ' }
if ($i -gt 0) { Blank }
Wrap 'Also: set a monthly spend limit on every AI provider key, at the provider.' 5 '     ' '     '
$SecTodo = Take-Cap
# Argus is a Mac app, so on Windows it is one line, as gird-check.sh says off a Mac.
$ArgusLine = 'Built by GIRD. Argus, our free Mac app, shows what AI coding agents actually do: gird.ai/argus'
Blank
Wrap $ArgusLine 2 '  ' '  ' $cDim
$SecArgus = Take-Cap
Blank
Wrap 'Finding nothing does not prove nothing leaked. This shows what could reach your keys, not what your agents did with them.' 2 '  ' '  ' $cDim
$SecFoot = Take-Cap

# Details for one section: the section, then its fixes.
function Fix-Lines($list) {
  if ($list.Count -eq 0) { return }
  Blank
  Emit "     ${cBold}What to do$cRst"
  foreach ($t in $list) { Wrap $t 8 "     $cTeal$gBul$cRst  " '        ' }
}
Fix-Lines $Fixes[1]; $Det1 = $Sec1 + (Take-Cap)
Fix-Lines $Fixes[2]; $Det2 = $Sec2 + (Take-Cap)
Fix-Lines $Fixes[3]; $Det3 = $Sec3 + (Take-Cap)
Fix-Lines $Fixes[4]; $Det4 = $Sec4 + (Take-Cap)
Fix-Lines $Fixes[5]; $Det5 = $Sec5 + (Take-Cap)

# The summary: one line per section with the most important finding in it.
function CLine([string]$num, [string]$mark, [string]$label, [string]$detail) {
  $room = $Width - 31; if ($room -lt 16) { $room = 16 }
  if ($detail.Length -gt $room) { $detail = $detail.Substring(0, $room - 3) + '...' }
  Emit "   $cTeal$cBold$num$cRst  $mark  $cBold$($label.PadRight(20))$cRst$detail"
}
# An update-level incident with a fix of its own has a summary for row 05 (data/incidents.tsv).
$UpdSum = ''
foreach ($t in $NpmTags) { if ((Incident-Level $t) -ne 'update') { continue }; $us = Incident-Summary $t; if ($us) { $UpdSum = $us; break } }
if ($N_OLD -gt 0) { $G1 = "$cYel!$cRst"; $D1 = "$N_AG found, $(Plural $N_OLD 'security fix' 'security fixes') to install" }
elseif ($N_YOLO -gt 0) { $G1 = "$cYel!$cRst"; $D1 = "$N_AG found, $N_YOLO set to run commands without asking" }
elseif ($N_AG -eq 0) { $G1 = "$cDim$gMid$cRst"; $D1 = 'none found' }
elseif ($N_IDLE -gt 0) { $G1 = "$cYel$gRing$cRst"; $D1 = "$N_AG found, $N_IDLE idle: $(First-Names $IdleNames 2)" }
else { $G1 = "$cGrn$gOk$cRst"; $D1 = "$N_AG found, all used in the last 30 days" }
if ($N_AK -gt 0) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, $(Plural $N_AK 'file links' 'files link') to your SSH logins" }
elseif ($N_MCP_TOKEN -gt 1) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, tokens in $N_MCP_TOKEN files, like $(Short $McpTokFirst)" }
elseif ($N_MCP_TOKEN -eq 1) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, a token in $(Short $McpTokFirst)" }
elseif ($N_AUTO -gt 0) { $G2 = "$cYel!$cRst"; $D2 = "$McpSum, $(Plural $N_AUTO_PROJ 'project acts' 'projects act') on opening" }
elseif ($N_LOOK -gt 0) { $G2 = "$cYel!$cRst"; $D2 = "$McpSum, $(Plural $N_LOOK 'project file' 'project files') to read" }
elseif ($HOME_PARTIAL -eq 1) { $G2 = "$cYel!$cRst"; $D2 = "$McpSum, but some folders were not read" }
elseif ($McpRows.Count -gt 0) { $G2 = "$cGrn$gOk$cRst"; $D2 = "$McpSum, no tokens in their configs" }
else { $G2 = "$cGrn$gOk$cRst"; $D2 = 'none configured' }
if ($KEY_FILES -gt 1) { $G3 = "$cRed$gX$cRst"; $D3 = "$KEY_FILES files, like $(Short $KeyFirst[0]) ($($KeyFirst[1]))" }
elseif ($KEY_FILES -eq 1) { $G3 = "$cRed$gX$cRst"; $D3 = "$(Short $KeyFirst[0]) holds $($KeyFirst[1]) keys" }
elseif ($N_SESS -gt 0) { $G3 = "$cRed$gX$cRst"; $D3 = "keys in $(Plural $N_SESS 'agent session file' 'agent session files'): $($SessRows[0][0])" }
elseif ($KeyUnread.Count -gt 0) { $G3 = "$cYel!$cRst"; $D3 = "none found, but $(Plural $KeyUnread.Count 'file' 'files') could not be read" }
elseif ($SESS_PARTIAL) { $G3 = "$cYel!$cRst"; $D3 = 'none in files; agent sessions partly checked' }
elseif ($N_SSH_OPEN -gt 0) { $G3 = "$cYel$gRing$cRst"; $D3 = "none in plain text, but $(Plural $N_SSH_OPEN 'SSH key has' 'SSH keys have') no passphrase" }
elseif ($HOME_PARTIAL -eq 1) { $G3 = "$cYel!$cRst"; $D3 = 'none found, but some folders were not read' }
else { $G3 = "$cGrn$gOk$cRst"; $D3 = 'no AI or cloud keys in plain text' }
if ($N_ALLOW -eq 0 -and $HOME_PARTIAL -eq 1) { $G4 = "$cYel!$cRst"; $D4 = 'none found, but some folders were not read' }
elseif ($N_ALLOW -eq 0) { $G4 = "$cGrn$gOk$cRst"; $D4 = 'no saved commands with keys' }
elseif ($N_ALLOW_NPM -gt 0 -and $N_ALLOW -eq 1) { $G4 = "$cRed$gX$cRst"; $D4 = '1 saved key, and an npm publish would ship it' }
elseif ($N_ALLOW_NPM -gt 0) { $G4 = "$cRed$gX$cRst"; $D4 = "$N_ALLOW saved keys, $N_ALLOW_NPM that an npm publish would ship" }
elseif ($N_ALLOW -eq 1) { $G4 = "$cRed$gX$cRst"; $D4 = "a saved key in $(Short $AllowFirst)" }
else { $G4 = "$cRed$gX$cRst"; $D4 = "saved keys in $N_ALLOW files" }
$leaks = @($Platforms | Where-Object { $PlatFound -contains $_.Id })
if ($WIPER_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = 'gh-token-monitor: stop it before revoking tokens' }
elseif ($ANY_MAL -eq 1 -and $PY_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = "$MalShort and $PyShort malware found. Act now" }
elseif ($MAL_LOCKONLY -eq 1 -and $EXT_HIT -eq 0) { $G5 = "$cRed$gX$cRst"; $D5 = 'npm malware in a lockfile: act if installed' }
elseif ($ANY_MAL -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = "signs of $MalWhat. Act now" }
elseif ($PY_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = "signs of the $PyShort malware. Act now" }
elseif ($UpdSum) { $G5 = "$cYel!$cRst"; $D5 = $UpdSum }
elseif ($LitePyc.Count -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'possible LiteLLM leftover: check cook.pyc' }
elseif ($ExtCheck.Count -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'a startup file to check, see section 5' }
elseif ($NPM_UPD -eq 1 -and $PY_UPD_HIT -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'npm and Python packages to update, see section 5' }
elseif ($NPM_UPD -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'an npm package to update, see section 5' }
elseif ($PY_UPD_HIT -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'a Python package to update, see section 5' }
elseif ($leaks.Count -ge 2) {
  $G5 = "$cYel!$cRst"
  $names = @($leaks | ForEach-Object { $_.Name })
  $l = ($names[0..($names.Count - 2)] -join ', ') + ' and ' + $names[$names.Count - 1]
  if ($leaks.Count -ge 3) { $D5 = "$l found: rotate keys" } else { $D5 = "$l found: rotate their keys" }
}
elseif ($leaks.Count -eq 1) { $G5 = "$cYel!$cRst"; $D5 = $leaks[0].Summary }
# A partial check comes after every finding someone has to act on, and before the green line.
elseif ($NpmSlow -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'npm packages not fully checked: took too long' }
elseif ($LockUnread.Count -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'npm packages not fully checked: files unreadable' }
elseif ($NpmUnread -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'npm packages not fully checked: cache unreadable' }
elseif ($ExtUnread -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'extensions not fully checked: folder unreadable' }
elseif ($HOME_PARTIAL -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'none found, but some folders were not read' }
else { $G5 = "$cGrn$gOk$cRst"; $D5 = "none of the $N_LEAKS recent leaks or malware it checks" }
Blank
CLine '01' $G1 'Coding agents' $D1
CLine '02' $G2 'MCP servers' $D2
CLine '03' $G3 'Keys in plain text' $D3
CLine '04' $G4 'Allow lists' $D4
CLine '05' $G5 'Recent leaks' $D5
if ($SlowFiles.Count -gt 0) { Blank; Wrap "$SlowText, like $(Short $SlowFiles[0])" 5 "   $cYel!$cRst " '     ' }
if ($ISSUES -gt 0) { Blank; Wrap $Todo[0] 14 "   ${cBold}First fix:$cRst " (' ' * 14) }
Blank
Wrap $ArgusLine 2 '  ' '  ' $cDim
if ($ISSUES -eq 0) {
  Blank
  Wrap 'Finding nothing does not prove nothing leaked. This shows what could reach your keys, not what your agents did with them.' 2 '  ' '  ' $cDim
}
$Summary = Take-Cap; $Capture = $false

$FullText = $HeadFull + $Sec1 + $Sec2 + $Sec3 + $Sec4 + $Sec5 + $SecTodo + $SecArgus + $SecFoot
[void]$Report.Append($FullText)
if ($Compact) { Out-Text ($HeadShort + $Summary) } else { Out-Text $FullText }

# ---------------------------------------------------------------------------
# What next: the result link first, then details and save. One key each, nothing
# happens unasked. u is the run ID, r the early rank, sk the SSH private keys,
# hk the shell history files with keys, nm npm malware, ex malware in an editor extension
# and wp gh-token-monitor, so the page never says to rotate a token while it is there.
# ---------------------------------------------------------------------------
function Card-Url {
  $d = (Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
  "$Web/blindspot/card/#v=2&s=$SCORE&g=$GRADE&a=$N_AG&i=$N_IDLE&m=$N_MCP&mt=$N_MCP_TOKEN&k=$KEY_FILES&p=$($ProvIds -join '.')&al=$N_ALLOW&an=$N_ALLOW_NPM&ll=$LITELLM_HIT&lf=$N_LOGIN&sp=$N_SSH_OPEN&d=$d&pc=$PCT&pn=$PCT_N&u=$LinkRunId&r=$RANK&sk=$N_SSH&hk=$HIST_KEYS&ag=$($AgentIds -join '.')&nm=$MAL_HIT&py=$PY_OTHER&ex=$EXT_HIT&wp=$WIPER_HIT"
}
$ActSaved = 0; $ActCard = 0
function Do-Save {
  $dir = (Get-Location).ProviderPath
  $name = 'gird-ai-key-check-' + (Get-Date).ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture) + '.txt'
  $out = $null
  foreach ($cand in @($dir, $HomeDir)) {
    if (-not $cand) { continue }
    try {
      $path = J $cand $name
      # Readable only by you, as gird-check.sh's umask 077. On Windows the folder's permissions apply.
      # Before PowerShell 7.3 there is no UnixCreateMode: the empty file is made owner-only first
      # (GIRD_CHECK_TEST_NO_UNIXMODE takes that path in the tests).
      $unix = [Environment]::OSVersion.Platform -eq [PlatformID]::Unix
      if ($unix -and ('IO.UnixFileMode' -as [type]) -and -not $env:GIRD_CHECK_TEST_NO_UNIXMODE) {
        $fo = New-Object IO.FileStreamOptions; $fo.Mode = [IO.FileMode]::CreateNew; $fo.Access = [IO.FileAccess]::Write
        $fo.UnixCreateMode = [IO.UnixFileMode]'UserRead, UserWrite'
        $fs = New-Object IO.FileStream($path, $fo)
      } else {
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        if ($unix) {
          & /bin/chmod 600 $path 2>$null
          if ($LASTEXITCODE -ne 0) { $fs.Close(); Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue; throw 'chmod' }
        }
      }
      $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(([regex]::Replace($Report.ToString(), "$Esc\[[0-9;]*m", '')).Replace("`n", $NL))
      $fs.Write($bytes, 0, $bytes.Length); $fs.Close(); $out = $path; break
    } catch { $out = $null }
  }
  if ($out) {
    $script:ActSaved = 1
    Out-Text "  $cGrn$gOk Saved$cRst $out`n  ${cDim}It lists file paths, not keys. Delete it when you are done.$cRst`n"
  } else { Out-Text "  Could not save to $(J $dir $name)`n" }
}
function Do-Card {
  $u = Card-Url; $script:ActCard = 1
  $opened = $false
  if (-not $env:GIRD_CHECK_NO_OPEN) { try { Start-Process $u; $opened = $true } catch { } }
  if ($opened) { Out-Text "  $cGrn$gOk Opened your result in the browser.$cRst`n" } else { Out-Text "  Open your result:`n" }
  Out-Text "  $cDim$u$cRst`n"
  if ($LinkRunId) {
    Out-Text "  ${cDim}The link carries only counts and a random run ID, after the #, which browsers never send.$cRst`n"
    Out-Text "  ${cDim}If you press share there, the page sends back that ID, the button and the kind of result.$cRst`n"
  } else { Out-Text "  ${cDim}The link carries only your counts, after the #, which browsers never send to a server.$cRst`n" }
}

$MenuShown = $false; $MenuT0 = [DateTime]::UtcNow
if ($OptSave) { Do-Save }
if ($IsConsole -and $InConsole) {
  $MenuShown = $true
  # Drop anything typed during the scan, so it can't answer a question by accident.
  try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { }
  if ($PCT) { $Hero = 'Press ENTER to see how you rank and help spread awareness' } else { $Hero = 'Press ENTER to get your AI Exposure Check and help spread awareness' }
  $Hint = '1-5 details   s save   q quit'
  $tri = [string][char]0x25B6; if (-not $Fancy) { $tri = '>' }
  $hinted = $false
  Out-Text "`n  $cGold$cBold$tri $Hero$cRst`n    $cDim$Hint$cRst  "
  while ($true) {
    try { $k = [Console]::ReadKey($true) } catch { break }
    $ch = [string]$k.KeyChar
    if ($k.Key -eq [ConsoleKey]::Enter -or $ch -eq 'c' -or $ch -eq 'C') { Out-Text "`n"; Do-Card }
    elseif ($ch -ge '1' -and $ch -le '5' -and $ch.Length -eq 1) {
      Out-Text "$ch`n"
      switch ($ch) { '1' { Out-Text $Det1 } '2' { Out-Text $Det2 } '3' { Out-Text $Det3 } '4' { Out-Text $Det4 } '5' { Out-Text $Det5 } }
    }
    elseif ($ch -eq 's' -or $ch -eq 'S') { Out-Text "s`n"; Do-Save }
    elseif ($ch -eq 'q' -or $ch -eq 'Q' -or $k.Key -eq [ConsoleKey]::Escape) { Out-Text "q`n"; break }
    else {
      if (-not $hinted) { Out-Text "$cDim(ENTER, 1-5, s or q)$cRst " }
      $hinted = $true; continue
    }
    $hinted = $false
    Out-Text "`n  $cGold$cBold$tri $Hero$cRst`n    $cDim$Hint$cRst  "
  }
} else {
  Out-Text "`n  Your AI Exposure Check: $(Card-Url)`n"
}
# What people did at the end, for the same research: one more small event.
if (-not $OptOffline -and $MenuShown) {
  $ms = [int][Math]::Floor(([DateTime]::UtcNow - $MenuT0).TotalSeconds)
  [void](Http 'POST' $Api 5 "{""v"":""1"",""kind"":""actions"",""run_id"":""$RUN_ID"",""device_id"":""$DEVICE_ID"",""saved"":$ActSaved,""card"":$ActCard,""argus"":0,""menu_seconds"":$ms}" 65536)
}
Out-Text "`n"
} finally {
  Sess-Stop $false
  if ($null -ne $OldOutEnc) { try { [Console]::OutputEncoding = $OldOutEnc } catch { } }
}
exit 0
