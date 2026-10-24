<#
Blindspot, the GIRD AI key check, for Windows PowerShell, version 1.1.0 (23 October 2026)
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
$ALL_KEYS = 'sk-ant-[A-Za-z0-9_-]{90,}|sk-or-v1-[a-f0-9]{64}|sk-proj-[A-Za-z0-9_-]{120,}|sk-svcacct-[A-Za-z0-9_-]{60,}|(^|[^A-Za-z0-9-])sk-[A-Za-z0-9]{48}([^A-Za-z0-9]|$)|AIza[0-9A-Za-z_-]{35}|(^|[^A-Za-z0-9])AQ\.[A-Za-z0-9_-]{40,}|gsk_[A-Za-z0-9]{52}|xai-[A-Za-z0-9]{64,}|(^|[^A-Za-z0-9_])hf_[A-Za-z0-9]{34,40}([^A-Za-z0-9_]|$)|pplx-[A-Za-z0-9]{40,52}|r8_[A-Za-z0-9]{37}|(^|[^A-Z0-9])AKIA[0-9A-Z]{16}([^A-Z0-9]|$)|bedrock-api-key-YmVkcm9jay5hbWF6b25hd3MuY29t|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}|npm_[A-Za-z0-9]{36}'
$PROVIDER_IDS = 'anthropic openrouter openai google groq xai huggingface perplexity replicate aws github npm'
$KEY_STARTS = 'sk-ant-|sk-or-v1-|sk-|AIza|AQ[.]|gsk_|xai-|hf_|pplx-|r8_|AKIA|bedrock-api-key|gh[pousr]_|github_pat_|npm_'
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
  if ($s -cmatch '^(AKIA|bedrock-api-key)') { return 'AWS' }
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
  $k = $k -replace '^[^A-Za-z]*\\[ntr"]', '' -replace '^[^A-Za-z]+', '' -replace '[^A-Za-z0-9_.-]+$', ''
  if ($k -cmatch 'EXAMPLE|xxxx|XXXX|0123456789|abcdef|ABCDEF' -or $k -cmatch '(.)\1{7}') { return $true }
  $set = New-Object 'System.Collections.Generic.HashSet[char]'
  foreach ($c in $k.ToCharArray()) { [void]$set.Add($c) }
  $min = 12; if ($k.Length -lt 30) { $min = 8 }
  $set.Count -lt $min
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
    '.windsurf', '.local/share', 'Dropbox', 'Google Drive', 'Saved Games', 'Favorites', 'Contacts', 'Links', 'Searches',
    '3D Objects', 'scoop')) { $PrunePaths.Add((J $HomeDir $p)) }
if (-not $OptAll) { foreach ($p in @('Desktop', 'Documents', 'Downloads')) { $PrunePaths.Add((J $HomeDir $p)) } }
$Found = New-Object System.Collections.Generic.List[string]
# Kept apart from $Found, so files_found counts what it always has.
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
$script:ScanN = 0
function Is-Pruned([string]$path, [string]$name, [int]$depth) {
  foreach ($n in $PruneNames) { if ($name -ceq $n) { return $true } }
  foreach ($p in $PrunePaths) { if ($path.Equals($p, $PathCmp)) { return $true } }
  ($depth -eq 1) -and $name.StartsWith('OneDrive', $PathCmp)
}
# Files worms plant in a project, from data/planted.tsv.
# >>> planted: generated from data/planted.tsv by tools/gen.sh. Edit that file, then run it.
$WormName = '\.(claude|vscode)[/\\]+(router_runtime\.js|tanstack_runner\.js|setup\.mjs|math_init\.js)'
function Planted-Note([string]$p) { switch -CaseSensitive ($p) { '.claude/router_runtime.js' { 'a file the TanStack and keyv worms plant' } '.claude/tanstack_runner.js' { 'a file the TanStack and keyv worms plant' } '.vscode/router_runtime.js' { 'a file the TanStack and keyv worms plant' } '.vscode/tanstack_runner.js' { 'a file the TanStack and keyv worms plant' } '.claude/setup.mjs' { 'a file the TanStack and keyv worms plant' } '.claude/math_init.js' { 'a file the TanStack and keyv worms plant' } '.vscode/setup.mjs' { 'a file the TanStack and keyv worms plant' } default { $null } } }
$WormRefNote = 'runs a file the TanStack and keyv worms plant'
# <<< planted
# Agents set to run commands without asking (data/auto-approve.tsv), read in section 1.
# >>> auto-approve: generated from data/auto-approve.tsv by tools/gen.sh. Edit that file, then run it.
$AaTable = @(
  ,@('Claude Code', 'all', (J (Env-Or 'CLAUDE_CONFIG_DIR' (J $HomeDir '.claude')) 'settings.json'), 'bypassPermissions', @('"defaultMode": "bypassPermissions"'))
  ,@('Codex', 'all', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'config.toml'), 'never asks, full access', @('approval_policy = "never"', 'sandbox_mode = "danger-full-access"'))
  ,@('VS Code Copilot', 'all', (J $AppData 'Code/User/settings.json'), 'chat.tools.global.autoApprove', @('"chat.tools.global.autoApprove": true'))
)
$AaProject = @()
# <<< auto-approve
function Is-WormFile([string]$parent, [string]$name) { $null -ne (Planted-Note "$parent/$name") }
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
# Does a link in $dir with this target resolve to this user's own ~/.ssh/authorized_keys? The paths
# are compared resolved, so a link into a repo's own .ssh/authorized_keys fixture does not count,
# and a link to the file's place counts before the file exists: an agent writing through it creates it.
$AkPath = $null; try { $AkPath = [IO.Path]::GetFullPath((J $HomeDir '.ssh/authorized_keys')) } catch { }
function Is-AkLink([string]$dir, [string]$target) {
  if (-not $target -or -not $AkPath) { return $false }
  try {
    $t = $target; if (-not [IO.Path]::IsPathRooted($t)) { $t = J $dir $t }
    return [IO.Path]::GetFullPath($t).Equals($AkPath, $PathCmp)
  } catch { return $false }
}
function Scan-Home([string]$dir, [int]$depth) {
  foreach ($e in (Entries $dir)) {
    $name = $e.Name; $path = $e.FullName; $d = $depth + 1; $link = Is-Link $e
    if (Is-DirInfo $e) {
      if ($link -or (Is-Pruned $path $name $d)) { continue }
      if ($name -ceq 'site-packages') { $Sites.Add($path); continue }
      if ($d -lt 6) { Scan-Home $path $d }
      continue
    }
    $parent = [IO.Path]::GetFileName($dir)
    $isSettings = $parent -ceq '.claude' -and ($name -ceq 'settings.json' -or $name -ceq 'settings.local.json')
    # A linked settings, tasks or worm file is followed; any other link is not.
    if ($link) {
      if ($isSettings) { $Found.Add($path) }
      elseif ($parent -ceq '.vscode' -and $name -ceq 'tasks.json') { $TaskFiles.Add($path) }
      elseif (Is-WormFile $parent $name) { $WormFiles.Add($path) }
      if ((Is-AkLink $dir (Link-Target $e)) -and -not $path.StartsWith((J $HomeDir '.ssh') + $Sep, $PathCmp)) { $AkLinks.Add($path) }
      continue
    }
    if ($name -ceq '.env' -or $name.StartsWith('.env.') -or $name -ceq '.envrc' -or $name -ceq '.mcp.json' -or $name -ceq 'pyvenv.cfg' -or $isSettings -or
      ($name -ceq 'mcp.json' -and ($parent -ceq '.cursor' -or $parent -ceq '.vscode'))) {
      $Found.Add($path)
      $script:ScanN++
      if ($script:ScanN % 4 -eq 1) { Progress "Checking $(Short $path)" }
    } elseif ($name -ceq 'package-lock.json' -or $name -ceq 'npm-shrinkwrap.json' -or $name -ceq 'pnpm-lock.yaml' -or $name -ceq 'yarn.lock' -or $name -ceq 'bun.lock') { $LockFiles.Add($path) }
    elseif ($name -ceq '.aider.chat.history.md') { $AiderFiles.Add($path) }
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
  Emit ("  $cTeal" + (& $u '    \u2810\u281b\u283f\u283f\u281b\u2803    ') + "$cRst   ${cBold}BLINDSPOT$cRst  ${cDim}v1.1.0 $gMid 23 Oct 2026 $gMid gird.ai/blindspot$cRst")
}

# ===========================================================================
$ScanT0 = [DateTime]::UtcNow
$Early = $false
try {
Blank
if ($Fancy) { Show-Banner } else {
Emit ("  $cTeal${cBold}GIRD$cRst  ${cBold}BLINDSPOT$cRst  ${cDim}v1.1.0 $gMid 23 Oct 2026 $gMid gird.ai/blindspot$cRst")
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
  @('read', 'Claude Desktop', (J $AppData 'Claude/local-agent-mode-sessions')),
  @('read', 'Codex', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'sessions')),
  @('read', 'Codex', (J (Env-Or 'CODEX_HOME' (J $HomeDir '.codex')) 'history.jsonl')),
  @('read', 'Gemini CLI', (J (Env-Or 'GEMINI_CLI_HOME' $HomeDir) '.gemini/tmp')),
  @('read', 'Qwen Code', (J (Env-Or 'QWEN_HOME' (J $HomeDir '.qwen')) 'projects')),
  @('read', 'OpenCode', (J (Env-Or 'XDG_DATA_HOME' (J $HomeDir '.local/share')) 'opencode/opencode.db')),
  @('read', 'OpenCode', (J (Env-Or 'XDG_DATA_HOME' (J $HomeDir '.local/share')) 'opencode/storage')),
  @('read', 'GitHub Copilot CLI', (J (Env-Or 'COPILOT_HOME' (J $HomeDir '.copilot')) 'session-state')),
  @('read', 'Roo Code', (J $AppData 'Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks')),
  @('read', 'Roo Code', (J $AppData 'Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks')),
  @('read', 'Cline', (J $AppData 'Code/User/globalStorage/saoudrizwan.claude-dev/tasks')),
  @('read', 'Cline', (J $AppData 'Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks')),
  @('read', 'Cline', (J $HomeDir '.cline/data/sessions')),
  @('read', 'Continue', (J (Env-Or 'CONTINUE_GLOBAL_DIR' (J $HomeDir '.continue')) 'sessions')),
  @('read', 'Goose', (J (J $AppData 'Block/goose/data') 'sessions')),
  @('read', 'Kiro CLI', (J $HomeDir '.kiro/sessions')),
  @('read', 'Kiro CLI', (J $LocalAppData 'kiro-cli')),
  @('read', 'Amazon Q', (J $LocalAppData 'amazon-q')),
  @('read', 'Factory Droid', (J $HomeDir '.factory/sessions')),
  @('read', 'Cursor', (J $AppData 'Cursor/User/globalStorage/state.vscdb')),
  @('read', 'Cursor', (J $HomeDir '.cursor/projects')),
  @('sealed', 'Windsurf', (J $HomeDir '.codeium/windsurf/cascade')),
  @('sealed', 'Antigravity', (J $HomeDir '.gemini/antigravity/conversations')))
# <<< sessions
$SessSources = @($SessTable | Where-Object { $_[0] -eq 'read' } | ForEach-Object { , @($_[1], $_[2]) })
$SessSealed = @($SessTable | Where-Object { $_[0] -eq 'sealed' } | ForEach-Object { , @($_[1], $_[2]) })
$SessRoots = @($SessSources | ForEach-Object { $_[1] } | Where-Object { Exists $_ } | Select-Object -Unique)
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
    if ($p -and -not (Made-Up $k) -and -not $st.Seen.ContainsKey("$f`t$p")) { $st.Seen["$f`t$p"] = 1; [void]$st.Hits.Add("$f`t$p") } }
  if ($hold) { while ((Test-Path -LiteralPath $hold) -and -not $st.Stop) { Start-Sleep -Milliseconds 50 } }  # tests only
  if ($rg) {
    $q = { param($a) '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    $pf = [IO.Path]::GetTempFileName(); [IO.File]::WriteAllText($pf, $keys)
    try {
      $psi = New-Object Diagnostics.ProcessStartInfo $rg
      $psi.Arguments = '-a --hidden --no-ignore --no-config --no-messages -o --no-line-number --with-filename --null -f ' + (& $q $pf) + ' -- ' + (($roots | ForEach-Object { & $q $_ }) -join ' ')
      $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
      $st.Proc = [Diagnostics.Process]::Start($psi)
      while ($null -ne ($l = $st.Proc.StandardOutput.ReadLine())) { $i = $l.IndexOf([char]0); if ($i -gt 0) { & $hit $l.Substring(0, $i) $l.Substring($i + 1) } }
      $st.Proc.WaitForExit(); if (-not $st.Stop) { $st.RgExit = $st.Proc.ExitCode }
    } catch { } finally { Remove-Item -LiteralPath $pf -ErrorAction SilentlyContinue }
    return
  }
  # Stopped while still listing: Listed stays false and the report says the sessions were not all checked.
  $files = New-Object System.Collections.Generic.List[object]
  foreach ($r in $roots) {
    try {
      if ([IO.File]::Exists($r)) { $files.Add((New-Object IO.FileInfo $r)) }
      else { foreach ($f in (New-Object IO.DirectoryInfo $r).EnumerateFiles('*', [IO.SearchOption]::AllDirectories)) { if ($st.Stop) { return }; $files.Add($f) } }
    } catch { }
  }
  $sorted = @($files | Sort-Object -Property @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, FullName)
  $st.Total = $sorted.Count; $st.Listed = $true
  $n = 0; $latin = [Text.Encoding]::GetEncoding(28591); $buf = New-Object char[] 1048576
  foreach ($f in $sorted) {
    if ($st.Stop) { break }
    if ($null -ne $cut -and $n -ge $cut) { break }
    $n++
    if ($f.Name.EndsWith('.zst')) { $st.Zst++; continue }
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
    } catch { } finally { if ($sr) { $sr.Dispose() } }
  }
}
$SessSt = [hashtable]::Synchronized(@{ Stop = $false; Listed = $false; Total = 0; Done = 0; Zst = 0; RgExit = $null; Proc = $null; Hits = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)); Seen = @{} })
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
  [void]$SessPs.AddScript($SessWorker).AddArgument($SessRoots).AddArgument($TR_KEYS).AddArgument($KEY_STARTS).AddArgument($rgPath).AddArgument($KeyFns).AddArgument($SessSt).AddArgument([int]$RxTimeout.TotalMilliseconds).AddArgument($cut).AddArgument($env:GIRD_CHECK_SESSIONS_HOLD)
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
$EnvFiles = @($Found | Where-Object { [IO.Path]::GetFileName($_) -cmatch '^\.env(rc|\..*)?$' })
$AllowFiles = @($Found | Where-Object { [IO.Path]::GetFileName($_) -cmatch '^settings(\.local)?\.json$' -and [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($_)) -ceq '.claude' })
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
  @('Goose', 'goose', @((J $AppData 'Block/goose')), @((J $AppData 'Block/goose/data')), 'goose'),
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
# one line, so pretty-printed JSON matches too; only tasks.json (JSONC) has comments removed first.
$AutoRows = New-Object System.Collections.Generic.List[object]; $WormRefs = New-Object System.Collections.Generic.List[string]
$AutoSeen = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
# Worms plant a file in the folder ($WormName, from data/planted.tsv) and run it from a hook or a task.
# A worm file counts only when a command runs it (an interpreter given its path, the path as the
# command itself, or a task's argument), not when a rule or a guard merely names it.
$RxWormRun = New-Object regex(('"command"\s*:\s*"(?:[^"\\]|\\.)*\b(node|bun|deno|tsx)(\.exe)?\s(?:[^"\\]|\\.)*' + $WormName +
  '|"command"\s*:\s*"\s*(\\?"?\$\{?CLAUDE_PROJECT_DIR\}?(\\?")?[/\\]|\.[/\\])?' + $WormName + '|"args"\s*:\s*\[[^\]]*' + $WormName), $RxOpt, $RxTimeout)
# Keys that make Claude Code run a command: hooks and its helper commands.
$RxHooks = New-Object regex('"hooks"\s*:\s*\{\s*"|"(apiKeyHelper|statusLine|awsAuthRefresh|awsCredentialExport|gcpAuthRefresh|otelHeadersHelper)"\s*:', $RxOpt, $RxTimeout)
$RxMcpAuto = New-Object regex('"enableAllProjectMcpServers"\s*:\s*true|"enabledMcpjsonServers"\s*:\s*\[\s*"', $RxOpt, $RxTimeout)
$RxBaseUrl = New-Object regex('"ANTHROPIC_BASE_URL"\s*:\s*"(?![A-Za-z]+://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?[/"])[^"]*"', $RxOpt, $RxTimeout)
$RxFolderOpen = New-Object regex('"runOn"\s*:\s*"folderOpen"', $RxOpt, $RxTimeout)
$RxLineComment = New-Object regex('(^|[\s,{\[])//[^\n]*', $RxOpt, $RxTimeout)
$RxBlockComment = New-Object regex('/\*(?:[^*]|\*+[^*/])*\*+/', $RxOpt, $RxTimeout)
function Flat-Text([string]$f) {
  $t = Read-Text $f; if ($null -eq $t) { return $null }
  if (-not $f.EndsWith('tasks.json')) { return ($t -replace '[\r\n\t]', ' ') }
  try { $RxBlockComment.Replace(($RxLineComment.Replace($t, '$1') -replace '[\r\n\t]', ' '), '') } catch { Mark-Slow $f; $null }
}
function Flat-Match([string]$f, [string]$t, [regex]$rx) { try { $rx.IsMatch($t) } catch { Mark-Slow $f; $false } }
# A setting of data/auto-approve.tsv in a file: every pattern must match, spaces ignored. A .json
# file is read as one line through Flat-Text (comments are its job), and a match starts at the text,
# a { or a , and ends at the text's end, a , } # or /, so a longer key or another value never counts.
# A .toml file is read line by line: a # line is skipped, a match is a whole line up to a # comment
# (so a setting inside an inline table, a profile written as one, does not count), and only the
# lines before the first [table] count: a setting under [profiles.x] applies only when that profile
# is used.
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
      $k = $l.IndexOf($pp[$i], [StringComparison]::Ordinal)
      while ($k -ge 0) {
        $b = ''; if ($k -gt 0) { $b = [string]$l[$k - 1] }
        $e = $k + $pp[$i].Length; $a = ''; if ($e -lt $l.Length) { $a = [string]$l[$e] }
        if ($toml) { $hit = ($b -eq '' -and ($a -eq '' -or $a -eq '#')) }
        else { $hit = (($b -eq '' -or $b -eq '{' -or $b -eq ',') -and ($a -eq '' -or ',}#/'.Contains($a))) }
        if ($hit) { $got[$i] = $true; break }
        $k = $l.IndexOf($pp[$i], $k + 1, [StringComparison]::Ordinal)
      }
    }
  }
  -not ($got -contains $false)
}
function Auto-Row([string]$f, [string]$what, [string]$t) {
  if (Flat-Match $f $t $RxWormRun) { $WormRefs.Add($f) }
  # A repo's worktrees carry the same settings: one row, with how many more folders have it.
  $key = $t + [char]0 + ($f -replace '[/\\]\.claude[/\\]worktrees[/\\][^/\\]+[/\\]', '/')
  if ($AutoSeen.ContainsKey($key)) { $AutoSeen[$key].More = $AutoSeen[$key].More + 1; return }
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
foreach ($f in $Candidates) {
  if (-not (Has-Match $f $RxKeys)) { continue }
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
if ($KEY_FILES -eq 0) { Progress 'No keys in shell profiles, history, agent configs or .env files' }

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
function Npm-Label([string]$t) { switch ($t) { 'axios' { 'Axios takeover, March 2026' } 'tanstack' { 'TanStack worm, May 2026' } 'mistral' { 'Mistral AI packages, May 2026' } 'mistralpy' { 'mistralai 2.4.6, May 2026' } 'opensearch' { 'OpenSearch client, May 2026' } 'bitwarden' { 'Bitwarden CLI, April 2026' } 'mastra' { 'Mastra worm, June 2026' } 'keyv' { 'keyv worm, August 2026' } 'sandworm' { 'SANDWORM_MODE worm, February 2026' } 'tensorlake' { 'tensorlake package, October 2026' } 'litellm' { 'LiteLLM 1.107.0, October 2026' } 'opencode' { 'OpenCode Console, October 2026' } 'railway' { 'Railway, October 2026' } 'zeabur' { 'Zeabur, October 2026' } 'glassworm' { 'GlassWorm extensions, January 2026' } 'injective' { 'Injective SDK, July 2026' } default { $t } } }
function Incident-Line([string]$t) { switch ($t) { 'axios' { 'Axios takeover, March 2026: downloaded payloads, including a remote access trojan, onto machines that installed it. cisa.gov' } 'tanstack' { 'TanStack worm, May 2026: stole cloud, GitHub, npm and SSH credentials on install, then republished itself. github.com' } 'mistral' { 'Mistral AI packages, May 2026: published with malware that Mistral says could not run. docs.mistral.ai' } 'mistralpy' { 'mistralai 2.4.6, May 2026: started a credential stealer in the background when imported on Linux. docs.mistral.ai' } 'opensearch' { 'OpenSearch client, May 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' } 'bitwarden' { 'Bitwarden CLI, April 2026: stole SSH keys, npm, GitHub and cloud credentials, and AI tool configs. stepsecurity.io' } 'mastra' { 'Mastra worm, June 2026: started itself at login and sent browser history to the attackers. socket.dev' } 'keyv' { 'keyv worm, August 2026: stole cloud, GitHub and npm credentials, and planted hooks that run when repos open. socket.dev' } 'sandworm' { 'SANDWORM_MODE worm, February 2026: stole credentials and AI provider keys, and added an MCP server to AI assistants. socket.dev' } 'tensorlake' { 'tensorlake package, October 2026: GitHub says any computer that installed it should be treated as fully compromised. github.com' } 'litellm' { 'LiteLLM 1.107.0, October 2026: stole credentials and loaded remote-code execution tools on machines that installed it. docs.litellm.ai' } 'opencode' { 'OpenCode Console, October 2026: exposed AI provider keys saved in Console workspaces; users reported charges on them. techcrunch.com' } 'railway' { 'Railway, October 2026: an attacker accessed stored environment variables and decrypted some of them. blog.railway.com' } 'zeabur' { 'Zeabur, October 2026: an attacker read environment variables and secrets stored on the platform. zeabur.com' } 'glassworm' { 'GlassWorm extensions, January 2026: stole SSH keys, cloud and npm credentials, keychains and crypto wallets from Macs. socket.dev' } 'injective' { 'Injective SDK, July 2026: sent the seed phrase or private key of any wallet an app created or imported with it. github.com' } default { $t } } }
function Incident-Level([string]$t) { switch ($t) { 'mistral' { 'update' } 'injective' { 'update' } default { 'act' } } }
function Incident-Name([string]$t) { switch ($t) { 'axios' { 'Axios takeover' } 'tanstack' { 'TanStack worm' } 'mistral' { 'Mistral AI packages' } 'mistralpy' { 'mistralai 2.4.6' } 'opensearch' { 'OpenSearch client' } 'bitwarden' { 'Bitwarden CLI' } 'mastra' { 'Mastra worm' } 'keyv' { 'keyv worm' } 'sandworm' { 'SANDWORM_MODE worm' } 'tensorlake' { 'tensorlake package' } 'litellm' { 'LiteLLM 1.107.0' } 'opencode' { 'OpenCode Console' } 'railway' { 'Railway' } 'zeabur' { 'Zeabur' } 'glassworm' { 'GlassWorm extensions' } 'injective' { 'Injective SDK' } default { $t } } }
function Incident-Source([string]$t) { switch ($t) { 'axios' { 'www.cisa.gov/news-events/alerts/2026/04/20/supply-chain-compromise-impacts-axios-node-package-manager' } 'tanstack' { 'github.com/advisories/GHSA-g7cv-rxg3-hmpx' } 'mistral' { 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' } 'mistralpy' { 'docs.mistral.ai/resources/security-advisories/MAI-2026-002' } 'opensearch' { 'github.com/advisories/GHSA-298w-vvm4-ww55' } 'bitwarden' { 'www.stepsecurity.io/blog/bitwarden-cli-hijacked-on-npm-bun-staged-credential-stealer-targets-developers-github-actions-and-ai-tools' } 'mastra' { 'socket.dev/blog/mastra-npm-packages-compromised' } 'keyv' { 'socket.dev/blog/popular-npm-packages-in-the-keyv-and-cacheable-namespaces-compromised-in-active-supply-chain' } 'sandworm' { 'socket.dev/blog/sandworm-mode-npm-worm-ai-toolchain-poisoning' } 'tensorlake' { 'github.com/advisories/GHSA-rqxj-g25x-4v9v' } 'litellm' { 'docs.litellm.ai/blog/security-incident-oct-21-2026' } 'opencode' { 'techcrunch.com/2026/10/19/hackers-hit-ai-coding-tool-opencode-running-up-charges-on-users-ai-accounts/' } 'railway' { 'blog.railway.com/p/security-disclosure-wednesday-october-21st' } 'zeabur' { 'zeabur.com/blogs/october-2026-security-incident' } 'glassworm' { 'socket.dev/blog/glassworm-loader-hits-open-vsx-via-suspected-developer-account-compromise' } 'injective' { 'github.com/advisories/GHSA-5fc4-fm2x-6f4r' } default { $t } } }
function Incident-Advice([string]$t) { switch ($t) { 'glassworm' { 'On a Mac, also delete /tmp/ijewf, /tmp/out.zip and any plist in ~/Library/LaunchAgents you do not recognize, such as com.user.nodestart.plist.' } 'injective' { 'Move the funds out of any wallet created or imported with Injective SDK 1.20.21, into a new wallet.' } default { '' } } }
# <<< incidents
# >>> bad-pypi: generated from data/bad-pypi.tsv by tools/gen.sh. Edit that file, then run it.
$BadPypi = @'
litellm 1.107.0 litellm
mistralai 2.4.6 mistralpy
'@
$PyIncidents = @('litellm', 'mistralpy')
# <<< bad-pypi
# >>> indicators: generated from data/indicators.tsv by tools/gen.sh. Edit that file, then run it.
$IndTable = @(
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir 'Library/LaunchAgents/com.user.gh-token-monitor.plist'), '-')
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir '.config/systemd/user/gh-token-monitor.service'), '-')
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir '.local/bin/gh-token-monitor.sh'), '-')
  ,@('tanstack', 'all', 'wiper', 'no', (J $HomeDir '.config/gh-token-monitor'), '-')
  ,@('tanstack', 'all', 'wiper', 'yes', '/tmp/gh-token-monitor.out.log', '-')
  ,@('tanstack', 'all', 'wiper', 'yes', '/tmp/gh-token-monitor.err.log', '-')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir 'Library/LaunchAgents/com.nvm.protocal.plist'), 'starts the Mastra worm at login')
  ,@('glassworm', 'all', 'startup', 'no', (J $HomeDir 'Library/LaunchAgents/com.user.nodestart.plist'), 'starts the GlassWorm malware at login')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir 'Library/NodePackages/protocal.cjs'), 'starts the Mastra worm at login')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir '.config/systemd/user/nvmconf.service'), 'starts the Mastra worm at login')
  ,@('mastra', 'all', 'startup', 'no', (J $HomeDir '.config/systemd/nvmconf/protocal.cjs'), 'starts the Mastra worm at login')
  ,@('mastra', 'win', 'startup', 'no', $(if ($env:ProgramData) { J $env:ProgramData 'NodePackages/protocal.cjs' } else { '' }), 'starts the Mastra worm at login')
  ,@('litellm', 'all', 'site', 'no', 'cook.pth', '-')
  ,@('litellm', 'all', 'site', 'no', 'cook.py', '-')
  ,@('litellm', 'all', 'temp', 'no', 'remote_code_loader.lock', '-')
  ,@('litellm', 'all', 'temp', 'no', '.pc_once_*', '-')
  ,@('litellm', 'all', 'temp', 'no', '.pc_sq_*', '-')
  ,@('litellm', 'all', 'temp', 'no', '.pc_e_*', '-')
  ,@('mistralpy', 'linux', 'temp', 'no', 'transformers.pyz', '-')
)
# <<< indicators
if ($OnWindows) { $IndOs = 'win' } elseif (Is-Dir '/System/Library/CoreServices') { $IndOs = 'mac' } else { $IndOs = 'linux' }
$IndOn = @($IndTable | Where-Object { $_[1] -eq 'all' -or $_[1] -eq $IndOs })
$BadPypiRows = @($BadPypi -split "`r?`n" | ForEach-Object { , @($_ -split ' ') } | Where-Object { $_.Count -ge 3 })
# Python incidents (data/bad-pypi.tsv and the site and temp lines of data/indicators.tsv). $LiteBad
# and $Marks hold @(incident, what was found). The hit incidents' first words make "the LiteLLM malware".
function Py-Short($ids) { (@($ids | ForEach-Object { (Incident-Name $_).Split(' ')[0] }) -join ' and ') }
Progress "Checking $(Plural $SitesAll.Count 'Python environment' 'Python environments') for the $(Py-Short $PyIncidents) malware"
$N_PY = 0; $N_LITE = 0; $LiteVers = New-Object System.Collections.Generic.List[string]
$LiteBad = New-Object System.Collections.Generic.List[object]; $LitePyc = New-Object System.Collections.Generic.List[string]
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
    foreach ($r in $BadPypiRows) { if ($r[2] -ceq $pi -and (Is-Dir (J $sp "$($r[0])-$($r[1]).dist-info"))) { $bad.Add("$($r[0]) $($r[1])") } }
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
    if ($r[4].EndsWith('*')) {
      try { foreach ($m in ([IO.Directory]::GetFileSystemEntries($t, $r[4]) | Sort-Object)) { $Marks.Add(@($r[0], $m)) } } catch { }
    } elseif (Exists (J $t $r[4])) { $Marks.Add(@($r[0], (J $t $r[4]))) }
  }
}
# An environment variable and a running process are not files, so these stay code. The hourly
# loader that holds remote_code_loader.lock only runs on macOS and Linux.
if ($env:PRIVCOLLECT_ACTIVE) { $Marks.Add(@('litellm', 'PRIVCOLLECT_ACTIVE is set in this shell')) }
$LOADER = 0
# A bad version in uv's cache: @(incident, name, version) for each one found.
$UvBad = New-Object System.Collections.Generic.List[object]
foreach ($r in $BadPypiRows) {
  # The exact version: 2.4.6 is not 2.4.60 or 2.4.6.post1.
  $want = '^' + [regex]::Escape("$($r[0])-$($r[1])") + '(-.*|\.dist-info|\.tar\.gz|\.zip)?$'; $found = $false
  foreach ($uv in @((J $LocalAppData 'uv/cache'), (J $HomeDir '.cache/uv'))) {
    if ($found -or -not (Is-Dir $uv)) { continue }
    try {
      $q = New-Object System.Collections.Generic.Queue[object]; $q.Enqueue(@($uv, 0))
      while ($q.Count -gt 0 -and -not $found) {
        $it = $q.Dequeue()
        foreach ($e in (Entries $it[0])) {
          if ($e.Name -cmatch $want) { $found = $true; break }
          if ((Is-DirInfo $e) -and -not (Is-Link $e) -and $it[1] + 1 -lt 6) { $q.Enqueue(@($e.FullName, ($it[1] + 1))) }
        }
      }
    } catch { }
  }
  if ($found) { $UvBad.Add($r) }
}
$PyHits = New-Object System.Collections.Generic.List[string]
foreach ($pi in $PyIncidents) {
  $hit = $pi -eq 'litellm' -and $LOADER -eq 1
  foreach ($l in $LiteBad) { if ($l[0] -ceq $pi) { $hit = $true } }
  foreach ($l in $Marks) { if ($l[0] -ceq $pi) { $hit = $true } }
  if ($hit) { $PyHits.Add($pi) }
}
$PY_HIT = 0; if ($PyHits.Count -gt 0) { $PY_HIT = 1 }
# litellm_found and the card's ll stay LiteLLM's own; the card's py is any other Python incident.
$LITELLM_HIT = 0; if ($PyHits -contains 'litellm') { $LITELLM_HIT = 1 }
$PY_OTHER = 0; if (@($PyHits | Where-Object { $_ -cne 'litellm' }).Count -gt 0) { $PY_OTHER = 1 }
$PyShort = Py-Short $PyHits
if ($PY_HIT -eq 1) { Progress "Signs of the $PyShort malware found" }
elseif ($LitePyc.Count -gt 0) { Progress 'A leftover cook.pyc may come from the LiteLLM malware' }
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
@mistralai/mistralai 2.2.2 mistral
@mistralai/mistralai 2.2.3 mistral
@mistralai/mistralai 2.2.4 mistral
@mistralai/mistralai-azure 1.7.1 mistral
@mistralai/mistralai-azure 1.7.2 mistral
@mistralai/mistralai-azure 1.7.3 mistral
@mistralai/mistralai-gcp 1.7.1 mistral
@mistralai/mistralai-gcp 1.7.2 mistral
@mistralai/mistralai-gcp 1.7.3 mistral
@bitwarden/cli 2026.4.0 bitwarden
@mastra/core 1.42.1 mastra
mastra 1.13.1 mastra
create-mastra 1.13.1 mastra
easy-day-js 1.11.22 mastra
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
@keyv/bigmap 6.0.0 keyv
@keyv/cloudflare-kv 6.0.0 keyv
@keyv/compress-brotli 6.0.0 keyv
@keyv/compress-gzip 6.0.0 keyv
@keyv/compress-lz4 6.0.0 keyv
@keyv/dynamo 6.0.0 keyv
@keyv/encrypt-node 6.0.0 keyv
@keyv/encrypt-web 6.0.0 keyv
@keyv/etcd 6.0.0 keyv
@keyv/memcache 6.0.0 keyv
@keyv/mongo 6.0.0 keyv
@keyv/mysql 6.0.0 keyv
@keyv/postgres 6.0.0 keyv
@keyv/redis 6.0.0 keyv
@keyv/serialize-msgpackr 6.0.0 keyv
@keyv/serialize-superjson 6.0.0 keyv
@keyv/sqlite 6.0.0 keyv
@keyv/test-suite 6.0.0 keyv
@keyv/valkey 6.0.0 keyv
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
iru-caches * sandworm
iruchache * sandworm
node-native-bridge * sandworm
secp256 * sandworm
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
'@
# <<< bad-extensions
$NpmBad = @{}; $NpmAny = @{}; $NpmNames = New-Object System.Collections.Generic.List[string]; $N_BAD_NPM = 0
foreach ($l in ($BadNpm -split "`r?`n")) {
  $p = $l -split ' '; if ($p.Count -lt 3) { continue }
  $N_BAD_NPM++
  if ($p[1] -ceq '*') { $NpmAny[$p[0]] = $p[2] } else { $NpmBad["$($p[0])@$($p[1])"] = $p[2] }
  if (-not $NpmNames.Contains($p[0])) { $NpmNames.Add($p[0]) }
}
$NpmRows = New-Object System.Collections.Generic.List[object]; $NpmCacheRows = New-Object System.Collections.Generic.List[object]; $NpmSeen = @{}
$NpmCacheTag = " (npm's download cache)"
# Versions are shown only if they look like versions, so a package can't put terminal control codes in the report.
function Npm-Hit([string]$where, [string]$nm, [string]$v) {
  if ($v -cnotmatch '^[0-9A-Za-z.+_-]+\z') { $v = '?' }
  if ($v.EndsWith('-security')) { return }  # npm's empty placeholder for a removed package
  $k = "$nm@$v"; $t = $null
  if ($NpmBad.ContainsKey($k)) { $t = $NpmBad[$k] } elseif ($NpmAny.ContainsKey($nm)) { $t = $NpmAny[$nm] }
  if ($null -eq $t -or $NpmSeen.ContainsKey("$where|$k")) { return }
  $NpmSeen["$where|$k"] = $true
  if ($where.EndsWith($NpmCacheTag, [StringComparison]::Ordinal)) { $NpmCacheRows.Add(@($where, "$nm $v", $t)) } else { $NpmRows.Add(@($where, "$nm $v", $t)) }
}
# Tarball URLs (/name/-/name-1.2.3.tgz: npm, yarn 1 and npm's cache), name@version tokens (pnpm,
# bun, yarn berry's name@npm:version), npm's "node_modules/name" entries with a "version" line
# (locks written without URLs) and pnpm 5 and 7's /name/1.2.3 keys. A pin in an overrides section
# moves away from a version, so overrides are skipped.
$RxTgz = New-Object regex('/((?:@(?>[A-Za-z0-9._~-]+)/)?(?>[A-Za-z0-9._~-]+))/-/([A-Za-z0-9._~-]+)\.tgz', $RxOpt, $RxTimeout)
$RxTok = New-Object regex('(?<![A-Za-z0-9._~@-])((?:@(?>[A-Za-z0-9._~-]+)/)?(?>[A-Za-z0-9._~-]+))@(?:npm:)?([0-9](?>[0-9A-Za-z.+-]*))', $RxOpt, $RxTimeout)
$RxLockEntry = New-Object regex('^[^\n]*?"((?:node_modules/)*(?:@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+)"[^\S\n]*:[^\S\n]*\{|^[^\n]*?"version"[^\S\n]*:[^\S\n]*"([^"\n]+)"', $RxOpt, $RxTimeout)
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
$N_LOCK = 0; $NpmSlow = 0; $NpmUnread = 0
foreach ($f in $LockFiles) { try { $t = [IO.File]::ReadAllText($f) } catch { continue }; $N_LOCK++; Npm-Scan $f $t ([IO.Path]::GetFileName($f)) }
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
foreach ($r in $NpmRoots) {
  # The package itself, or a dependency of a globally installed tool.
  $mods = New-Object System.Collections.Generic.List[string]; $mods.Add($r)
  foreach ($d in (Glob-Dirs $r '*')) {
    $dn = [IO.Path]::GetFileName($d); if ($dn.StartsWith('.')) { continue }
    if (Is-Dir (J $d 'node_modules')) { $mods.Add((J $d 'node_modules')) }
    if (-not $dn.StartsWith('@')) { continue }
    foreach ($d2 in (Glob-Dirs $d '*')) { if (-not [IO.Path]::GetFileName($d2).StartsWith('.') -and (Is-Dir (J $d2 'node_modules'))) { $mods.Add((J $d2 'node_modules')) } }
  }
  foreach ($nm in $NpmNames) {
    foreach ($md in $mods) {
      $pd = J $md $nm; $pj = J $pd 'package.json'; if (-not (Is-File $pj)) { continue }
      $m = [regex]::Match([string](Read-Text $pj), '"version"\s*:\s*"([^"]+)"')
      $v = ''; if ($m.Success) { $v = $m.Groups[1].Value }
      Npm-Hit $pd $nm $v
    }
  }
}
# >>> outdated: generated from data/outdated.tsv by tools/gen.sh. Edit that file, then run it.
$OutTable = @(
  ,@('cursor', 'Cursor', 'mac', 'plist', '/Applications/Cursor.app/Contents/Info.plist', '-', '3.0', 'a prompt injection could escape the sandbox', 'github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw')
  ,@('cursor', 'Cursor', 'mac', 'plist', (J $HomeDir 'Applications/Cursor.app/Contents/Info.plist'), '-', '3.0', 'a prompt injection could escape the sandbox', 'github.com/cursor/cursor/security/advisories/GHSA-3p48-7v9f-v5cw')
  ,@('amazonq', 'Amazon Q language server', 'mac', 'folder', (J $HomeDir 'Library/Caches/aws/toolkits/language-servers/AmazonQ'), '-', '1.69.0', 'opening a hostile workspace can run its commands', 'aws.amazon.com/security/security-bulletins/2026-047-aws/')
  ,@('amazonq', 'Amazon Q language server', 'linux', 'folder', (J $HomeDir '.cache/aws/toolkits/language-servers/AmazonQ'), '-', '1.69.0', 'opening a hostile workspace can run its commands', 'aws.amazon.com/security/security-bulletins/2026-047-aws/')
  ,@('amazonq', 'Amazon Q language server', 'win', 'folder', (J $LocalAppData 'aws/toolkits/language-servers/AmazonQ'), '-', '1.69.0', 'opening a hostile workspace can run its commands', 'aws.amazon.com/security/security-bulletins/2026-047-aws/')
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
# A folder or file that can't be read leaves the cache not fully checked, never clean.
foreach ($c in @((J $LocalAppData 'npm-cache'), (J $HomeDir '.npm'))) {
  $ix = J $c '_cacache/index-v5'; if (-not (Is-Dir $ix)) { continue }
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
# the Marketplace; Cursor, Windsurf, VSCodium and Kiro install from Open VSX. A line whose bad build
# was only ever on Open VSX (registry openvsx) is not looked for in VS Code's own folder, where the
# same version is the Marketplace's clean build.
$ExtRows = New-Object System.Collections.Generic.List[object]
$BadExtRows = @($BadExt -split "`r?`n" | ForEach-Object { , @($_ -split ' ') } | Where-Object { $_.Count -ge 4 })
foreach ($er in @('.vscode/extensions', '.cursor/extensions', '.windsurf/extensions', '.vscode-oss/extensions', '.kiro/extensions')) {
  $reg = 'openvsx'; if ($er -eq '.vscode/extensions') { $reg = 'marketplace' }
  foreach ($e in (Entries (J $HomeDir $er))) {
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
# What these worms leave behind (data/indicators.tsv). gh-token-monitor runs a destructive command
# when the stolen GitHub token stops working (it erased the home folder in the TanStack wave, Wiz; in
# the keyv wave it runs an attacker-supplied command, SANS), so it must be stopped before any token
# is revoked. A file in the shared /tmp counts only if this person owns it; Windows has no /tmp.
$Wiper = New-Object System.Collections.Generic.List[string]
$Persist = New-Object System.Collections.Generic.List[object]
# A startup file of an incident whose packages are editor extensions only (GlassWorm's LaunchAgent)
# is that incident's sign, shown with the extensions ($ExtPersist), never called npm malware.
$ExtPersist = New-Object System.Collections.Generic.List[object]; $ExtPersistTags = New-Object System.Collections.Generic.List[string]
$ExtIncs = @($BadExtRows | ForEach-Object { $_[2] })
$NpmIncs = @($BadNpm -split "`r?`n" | ForEach-Object { @($_ -split ' ')[2] })
foreach ($r in $IndOn) {
  if ($r[2] -ne 'wiper' -and $r[2] -ne 'startup') { continue }
  $m = $r[4]; if (-not $m -or -not (Exists $m)) { continue }
  if ($r[3] -eq 'yes') {
    if ($OnWindows) { continue }
    $owner = ''; try { $owner = [string](Get-Item -LiteralPath $m -Force -ErrorAction Stop).User } catch { }
    if (-not ($owner -and $owner -ceq [Environment]::UserName)) { continue }
  }
  if ($r[2] -eq 'wiper') { $Wiper.Add($m) }
  elseif ($ExtIncs -contains $r[0] -and -not ($NpmIncs -contains $r[0])) { $ExtPersist.Add(@($m, $r[5])); if (-not $ExtPersistTags.Contains($r[0])) { $ExtPersistTags.Add($r[0]) } }
  else { $Persist.Add(@($m, $r[5])) }
}
# A registry value is not a file, so the Mastra worm's Run key stays code.
if ($OnWindows) {
  try {
    $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
    if ($rk) { if ($null -ne $rk.GetValue('NvmProtocal')) { $Persist.Add(@('NvmProtocal in your startup programs', 'starts the Mastra worm at login')) }; $rk.Close() }
  } catch { }
}
foreach ($f in $WormFiles) { $Persist.Add(@($f, (Planted-Note ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($f)) + '/' + [IO.Path]::GetFileName($f))))) }
foreach ($f in $WormRefs) { $Persist.Add(@($f, $WormRefNote)) }
$WIPER_HIT = 0; if ($Wiper.Count -gt 0) { $WIPER_HIT = 1 }
$MAL_HIT = 0; if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0 -or $WIPER_HIT -eq 1) { $MAL_HIT = 1 }
# Editor extension malware is its own finding, never called npm malware: EXT_HIT, the link's ex. An
# extension incident's startup file is its sign too.
$EXT_HIT = 0; if ($ExtRows.Count -gt 0 -or $ExtPersist.Count -gt 0) { $EXT_HIT = 1 }
$ExtTags = @((@(foreach ($r in $ExtRows) { $r[2] }) + @($ExtPersistTags)) | Sort-Object -Unique -CaseSensitive)
$ANY_MAL = 0; if ($MAL_HIT -eq 1 -or $EXT_HIT -eq 1) { $ANY_MAL = 1 }
if ($MAL_HIT -eq 1 -and $EXT_HIT -eq 1) { $MalWhat = 'npm and editor extension malware'; $MalShort = 'npm and editor extension' }
elseif ($EXT_HIT -eq 1) { $MalWhat = 'malware in an editor extension'; $MalShort = 'editor extension' }
else { $MalWhat = 'npm malware'; $MalShort = 'npm' }
if ($WIPER_HIT -eq 1) { Progress 'A wiper waits for a GitHub token to be revoked: gh-token-monitor' }
elseif ($ANY_MAL -eq 1) { Progress "Signs of $MalWhat found" }
# Hosted platforms that leaked stored secrets (data/platforms.tsv): found by a command on PATH, a
# file or a folder.
# >>> platforms: generated from data/platforms.tsv by tools/gen.sh. Edit that file, then run it.
$Platforms = @(
  @{ Id = 'opencode'; Name = 'OpenCode'; Cmds = @('opencode'); Dirs = @((J $HomeDir '.config/opencode'), (J $HomeDir '.local/share/opencode')); Files = @(); Found = 'installed'; Advice = 'If you used OpenCode Console, the hosted gateway, rotate every provider key you saved there. Keys kept only in the CLI were not affected.'; Summary = 'OpenCode found: used its Console? Rotate keys' },
  @{ Id = 'railway'; Name = 'Railway'; Cmds = @('railway'); Dirs = @(); Files = @((J $HomeDir '.railway/config.json')); Found = 'CLI found'; Advice = 'Railway asked every customer to rotate all secrets stored on the platform and to check their logs.'; Summary = 'Railway CLI found: rotate secrets stored there' },
  @{ Id = 'zeabur'; Name = 'Zeabur'; Cmds = @('zeabur'); Dirs = @((J $HomeDir '.config/zeabur')); Files = @(); Found = 'CLI found'; Advice = 'Zeabur said on 15 October that attackers read service environment variables stored on the platform, and asked every customer to replace all of them. Revoke each key at its provider first.'; Summary = 'Zeabur CLI found: rotate secrets stored there' })
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
$SESS_TOTAL = [int]$SessSt.Total; $SESS_DONE = [int]$SessSt.Done; $SESS_ZST = [int]$SessSt.Zst
if ($SessEngine -ne 'net' -or -not $SessSt.Listed) {
  $sessAll = New-Object System.Collections.Generic.List[string]
  foreach ($r in $SessRoots) {
    try { if ([IO.File]::Exists($r)) { $sessAll.Add($r) } else { foreach ($f in [IO.Directory]::EnumerateFiles($r, '*', [IO.SearchOption]::AllDirectories)) { $sessAll.Add($f) } } } catch { }
  }
  $SESS_TOTAL = $sessAll.Count; $SESS_ZST = @($sessAll | Where-Object { $_.EndsWith('.zst') }).Count
  # rg.exe reports no progress per file: it either finished (0 or 1) or did not.
  if ($SessEngine -eq 'rg' -and -not $SessSt.Stopped -and ($SessSt.RgExit -eq 0 -or $SessSt.RgExit -eq 1)) { $SESS_DONE = $SESS_TOTAL - $SESS_ZST } elseif ($SessEngine -eq 'rg') { $SESS_DONE = -1 } else { $SESS_DONE = 0 }
  if ($SessEngine -eq 'net' -and -not $SessSt.Listed) { $SESS_DONE = 0 }
}
$sessHits = New-Object System.Collections.Generic.List[string]
foreach ($h in $SessSt.Hits) { $sessHits.Add([string]$h) }
# Aider keeps its history in each project, found by the home scan, and is checked here.
$rxTr = New-Object regex($TR_KEYS, $RxOpt, $RxTimeout)
foreach ($f in $AiderFiles) {
  $t = Read-Text $f; if ($null -eq $t) { continue }
  $SESS_TOTAL++; if ($SESS_DONE -ge 0) { $SESS_DONE++ }
  $seenA = @{}
  try { foreach ($m in $rxTr.Matches($t)) { $p = Key-Provider $m.Value; if ($p -and -not (Made-Up $m.Value) -and -not $seenA.ContainsKey($p)) { $seenA[$p] = 1; $sessHits.Add("$f`t$p") } } } catch { Mark-Slow $f }
}
function Sess-Agent([string]$f) {
  if ($f.EndsWith('.aider.chat.history.md')) { return 'Aider' }
  foreach ($src in $SessSources) { if ($f.Equals($src[1], $PathCmp) -or $f.StartsWith($src[1] + [IO.Path]::DirectorySeparatorChar, $PathCmp) -or $f.StartsWith($src[1] + '/', $PathCmp)) { return $src[0] } }
  'Other'
}
$SessFiles = New-Object System.Collections.Generic.List[string]; $sessAg = [ordered]@{}
foreach ($h in $sessHits) {
  $f, $p = $h -split "`t", 2; $a = Sess-Agent $f
  if (-not $SessFiles.Contains($f)) { $SessFiles.Add($f); if (-not $sessAg.Contains($a)) { $sessAg[$a] = @{ N = 0; P = (New-Object System.Collections.Generic.List[string]) } }; $sessAg[$a].N++ }
  if (-not $sessAg[$a].P.Contains($p)) { $sessAg[$a].P.Add($p) }
}
$SessFiles.Sort([StringComparer]::Ordinal)
$N_SESS = $SessFiles.Count
$SessRows = @($sessAg.Keys | ForEach-Object { , @($_, $sessAg[$_].N, ($sessAg[$_].P -join ', ')) } | Sort-Object -Property @{ Expression = { $_[1] }; Descending = $true }, @{ Expression = { $_[0] } })
$SESS_PARTIAL = $SESS_TOTAL -gt 0 -and ($SessEngine -eq 'none' -or $SESS_DONE -lt 0 -or $SESS_DONE -lt ($SESS_TOTAL - $SESS_ZST))
$SessSealedFound = @($SessSealed | Where-Object { Is-Dir $_[1] } | ForEach-Object { $_[0] })
if ($N_SESS -gt 0) { Progress "Keys in $(Plural $N_SESS 'agent session file' 'agent session files')" }

# --- What to do, and the score -----------------------------------------------
# Each fix also belongs to a section, so that section's details can end with it.
$Todo = New-Object System.Collections.Generic.List[string]
$Fixes = @{ 1 = (New-Object System.Collections.Generic.List[string]); 2 = (New-Object System.Collections.Generic.List[string]);
  3 = (New-Object System.Collections.Generic.List[string]); 4 = (New-Object System.Collections.Generic.List[string]); 5 = (New-Object System.Collections.Generic.List[string]) }
function Add-Todo([int]$sec, [string]$text) {
  # With gh-token-monitor present, revoking a token sets it off: every other rotate waits for it.
  if ($WIPER_HIT -eq 1 -and -not $text.StartsWith("Don't revoke") -and $text -match 'rotate') { $text += ' Only once gh-token-monitor is stopped and removed (section 5).' }
  $Todo.Add($text); $Fixes[$sec].Add($text)
}
if ($WIPER_HIT -eq 1) { Add-Todo 5 'Don''t revoke any GitHub token yet. First stop and remove gh-token-monitor, as section 5 shows: it runs a destructive command when the stolen token stops working. Then rotate every key this machine could reach.' }
if ($MAL_HIT -eq 1) { Add-Todo 5 'Treat this machine as compromised. Delete the packages and files listed in section 5, clear npm''s cache with npm cache clean --force, and rotate every key this machine could reach.' }
if ($EXT_HIT -eq 1) {
  # Only what section 5 lists: the extensions, the incident's startup file, or both.
  if ($ExtRows.Count -gt 0 -and $ExtPersist.Count -gt 0) { $edo = 'Uninstall the extensions listed in section 5, delete the startup file listed there, and' }
  elseif ($ExtRows.Count -gt 0) { $edo = 'Uninstall the extensions listed in section 5 and' }
  else { $edo = 'Delete the startup file listed in section 5 and' }
  Add-Todo 5 "Treat this machine as compromised. $edo rotate every key this machine could reach."
}
# An incident's own fix (data/incidents.tsv), once for each incident found: an act-level one next to
# the act-now fixes, an update-level one before the update it has to come before.
function Add-Advice([string]$level) {
  $seen = @{}
  foreach ($t in (@($NpmTags) + @($ExtTags) + @($PyHits))) {
    if ($seen.ContainsKey($t)) { continue }; $seen[$t] = 1
    if ((Incident-Level $t) -ne $level) { continue }
    $a = Incident-Advice $t; if ($a) { Add-Todo 5 $a }
  }
}
if ($LITELLM_HIT -eq 0 -and $LitePyc.Count -gt 0) { Add-Todo 5 'A leftover cook.pyc can come from the LiteLLM 1.107.0 malware. If litellm 1.107.0 was ever installed there, treat this machine as compromised, follow LiteLLM''s advisory and rotate every key it could reach.' }
if ($PyHits.Count -gt 1) { $adv = 'each advisory in section 5' } else { $adv = "$PyShort's advisory" }
# "Don't run Python" only when a Python environment holds the bad package, not for a temp file alone.
$PyEnv = @($LiteBad | Where-Object { $PyHits -contains $_[0] }).Count -gt 0
if ($PY_HIT -eq 1 -and $PyEnv) { Add-Todo 5 "Treat this machine as compromised. Don't run Python in the affected environments, follow $adv, and rotate every key the machine could reach." }
elseif ($PY_HIT -eq 1) { Add-Todo 5 "Treat this machine as compromised. Stop any process started from the files listed in section 5, delete them, follow $adv, and rotate every key the machine could reach." }
Add-Advice 'act'
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
Add-Advice 'update'
if ($MAL_HIT -eq 0 -and $NPM_UPD -eq 1) { Add-Todo 5 'Update the npm packages listed in section 5 to a version without the malware, and clear npm''s cache with npm cache clean --force.' }
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
$OPTALL = 0; if ($OptAll) { $OPTALL = 1 }
$PAYLOAD = "{""v"":""1"",""kind"":""report"",""run_id"":""$RUN_ID"",""device_id"":""$DEVICE_ID"",""script"":""$ScriptVersion"",""os"":""$OSV"",""arch"":""$ARCH_ID"",""model"":""$MODEL"",""terminal"":""$TERMAPP"",""tmux"":$TMUXED,""shell"":""$SHELLNAME"",""bash"":0,""lang"":""$LANGCODE"",""via"":""$VIA"",""grade"":""$GRADE"",""score"":$SCORE,""agents"":$(Json-List $AgentIds),""agents_idle"":$N_IDLE,""agents_idle_ids"":$(Json-List $IdleIds),""mcp_servers"":$N_MCP,""mcp_configs"":$N_MCPF,""mcp_token_files"":$N_MCP_TOKEN,""mcp_clients"":$J_MCPC,""mcp_token_clients"":$(Json-List $McpTokIds),""mcp_known"":$(Json-List $mm.Known),""mcp_other"":$($mm.Other),""key_files"":$KEY_FILES,""key_places"":$J_PLACES,""key_providers"":$(Json-List $ProvIds),""provider_files"":$J_PROVF,""history_keys"":$HIST_KEYS,""env_files"":$N_ENVF,""allow_list_files"":$N_ALLOWF,""allow_list_keys"":$N_ALLOW,""allow_list_npm"":$N_ALLOW_NPM,""login_files"":$(Json-List $LoginIds),""ssh_keys"":$N_SSH,""ssh_no_passphrase"":$N_SSH_OPEN,""python_envs"":$N_PY,""litellm_installed"":$N_LITE,""litellm_found"":$LITELLM_HIT,""opencode"":$OC,""railway"":$RW,""files_found"":$N_FOUND,""scan_seconds"":$SCAN_SECS,""all_folders"":$OPTALL,""game_played"":0,""game_best"":0,""results_wait_seconds"":0}"
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
if ($PY_HIT -eq 1 -or $ANY_MAL -eq 1) { $Sev = $cRed }
elseif ($KEY_FILES -gt 0 -or $N_ALLOW -gt 0 -or $N_MCP_TOKEN -gt 0 -or $N_AK -gt 0) { $Sev = $cRed }
elseif ($ISSUES -gt 0) { $Sev = $cYel } else { $Sev = $cGrn }
if ($ISSUES -gt 0) { $FixN = "$(Plural $ISSUES 'thing' 'things') to fix" } else { $FixN = 'No findings in this scan' }
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
elseif ($ANY_MAL -eq 1) { $Act = "ACT NOW: SIGNS OF $($MalWhat.ToUpperInvariant())" }
elseif ($PY_HIT -eq 1) { $Act = "ACT NOW: SIGNS OF THE $((@($PyHits | ForEach-Object { Incident-Name $_ }) -join ' AND ').ToUpperInvariant()) MALWARE" }
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
if ($N_AK -gt 0) {
  Blank
  Emit "     ${cBold}Files that link to your SSH logins$cRst"
  foreach ($f in $AkLinks) { Emit "     $cRed$gX$cRst  $(Short $f)" }
  Wrap 'An agent that edits this file adds a login to this computer. Delete the link.' 8 '        ' '        ' $cRed
}
$Sec2 = Take-Cap
Section '03' 'KEYS IN PLAIN TEXT' (Plural $KEY_FILES 'file' 'files')
if ($KEY_FILES -eq 0) { Wrap 'No AI or cloud keys in shell profiles, history, agent configs or .env files.' 8 "     $cGrn$gOk$cRst  " '        ' }
$shown = 0
foreach ($r in $KeyRows) { $shown++; if ($shown -le 20) { Pair "$cRed$gX$cRst" (Short $r[0]) 44 $r[1] } }
if ($KEY_FILES -gt 20) { Emit "        ${cDim}and $($KEY_FILES - 20) more$cRst" }
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
if ($SESS_TOTAL -gt 0 -or $SessSealedFound.Count -gt 0) {
  Blank
  Emit "     ${cBold}Keys in agent sessions$cRst"
  foreach ($r in $SessRows) { Pair "$cRed$gX$cRst" $r[0] 20 "$(Plural $r[1] 'file' 'files'): $($r[2])" }
  if ($N_SESS -gt 0) {
    foreach ($f in ($SessFiles | Select-Object -First 20)) { Emit "        $cDim$(Short $f)$cRst" }
    if ($N_SESS -gt 20) { Emit "        ${cDim}and $($N_SESS - 20) more$cRst" }
    Wrap 'Treat these keys as exposed and rotate them.' 8 '        ' '        '
  }
  $allTxt = 'Install ripgrep, or add -AllSessions, to check all of them.'
  if ($SESS_TOTAL -gt 0 -and $SessEngine -eq 'none') { Wrap "$(Plural $SESS_TOTAL 'agent session file was' 'agent session files were') not checked." 8 "     $cYel!$cRst  " '        ' }
  elseif ($SESS_DONE -lt 0) { Wrap 'Agent sessions were partly checked. Add -AllSessions to check all of them.' 8 "     $cYel!$cRst  " '        ' }
  elseif ($SESS_DONE -lt ($SESS_TOTAL - $SESS_ZST)) { Wrap "Checked the newest $(Commas $SESS_DONE) of $(Commas $SESS_TOTAL) agent session files. $allTxt" 8 "     $cYel!$cRst  " '        ' }
  elseif ($N_SESS -eq 0 -and $SESS_TOTAL -gt 0) { Emit "     $cGrn$gOk$cRst  No keys in $(Plural (Commas $SESS_TOTAL) 'agent session file' 'agent session files')." }
  if ($SESS_ZST -gt 0) { Wrap "$(Plural $SESS_ZST 'compressed session file was' 'compressed session files were') not checked." 8 '        ' '        ' $cDim }
  if ($SessSealedFound.Count -gt 0) { Wrap "$($SessSealedFound -join ' and ') sessions are stored encrypted, so they were not checked." 8 '        ' '        ' $cDim }
}
$Sec3 = Take-Cap
Section '04' 'KEYS IN CLAUDE CODE ALLOW LISTS' (Plural $N_ALLOW 'file' 'files')
if ($N_ALLOW -eq 0) { Emit "     $cGrn$gOk$cRst  No saved commands with keys." }
foreach ($r in $AllowRows) {
  Emit "     $cRed$gX$cRst  $(Short $r[0])"
  Emit '        A saved command contains a key.'
  if ($r[1]) { Wrap 'An npm publish from this folder would include it.' 8 '        ' '        ' $cRed }
}
$Sec4 = Take-Cap
$ind26 = ' ' * 26
$N_LEAKS = @($PyIncidents).Count + 1 + @($Platforms).Count
Section '05' 'RECENT KEY LEAKS' "$N_LEAKS checked"
# One row per Python incident. cook.pyc, the installed versions and the loader are LiteLLM's.
foreach ($pi in $PyIncidents) {
  $pl = Incident-Name $pi
  if ($PyHits -contains $pi) {
    Pair "$cRed$gX$cRst" $pl 16 "${cRed}signs of the malware found$cRst"
    foreach ($l in $LiteBad) { if ($l[0] -ceq $pi) { Emit "        $(Short $l[1])" } }
    foreach ($l in $Marks) { if ($l[0] -ceq $pi) { Emit "        $(Short $l[1])" } }
    if (@($LiteBad | Where-Object { $_[0] -ceq $pi }).Count -gt 0) { $do = "Don't run Python or pip in these environments." } else { $do = 'Stop any process started from these files, then delete them.' }
    Wrap "$do Advisory: $(Incident-Source $pi)" 8 '        ' '        '
  } elseif ($pi -eq 'litellm' -and $LitePyc.Count -gt 0) {
    Pair "$cYel!$cRst" $pl 16 "${cYel}possible leftover$cRst"
    foreach ($l in $LitePyc) { Emit "        $l" }
    Wrap "A compiled cook file stays behind when cook.py is deleted, which is what the 1.107.0 malware ships. If litellm 1.107.0 was ever installed here, treat this as a hit. Advisory: $(Incident-Source $pi)" 8 '        ' '        '
  } else {
    Pair "$cGrn$gOk$cRst" $pl 16 "no signs in $(Plural $N_PY 'Python environment' 'Python environments')"
    if ($pi -eq 'litellm' -and $N_LITE -gt 0) { Emit "$ind26${cDim}installed: $(Short ($LiteVers -join ' '))$cRst" }
  }
  foreach ($r in $UvBad) { if ($r[2] -ceq $pi) { Wrap "Your uv cache holds the $($r[1]) package. Clear it with: uv cache clean $($r[0])" 8 '        ' '        ' $cYel } }
}
if ($WIPER_HIT -eq 1) {
  Pair "$cRed$gX$cRst" 'npm worms' 16 "${cRed}a wiper is waiting$cRst"
  foreach ($l in $Wiper) { Emit "        $(Short $l)" }
  if ($OnWindows) { $stop = 'Get-CimInstance Win32_Process | Where-Object CommandLine -like ''*gh-token-monitor*'' | Invoke-CimMethod -MethodName Terminate, then ' }
  elseif (Is-Dir '/System/Library/CoreServices') { $uidv = ''; try { $uidv = [string](& id -u 2>$null) } catch { }; $stop = "launchctl bootout gui/$uidv/com.user.gh-token-monitor, then pkill -f gh-token-monitor, then " }
  else { $stop = 'systemctl --user disable --now gh-token-monitor.service, then pkill -f gh-token-monitor, then ' }
  Wrap "Don't revoke any GitHub token until it is stopped and these files are gone: gh-token-monitor runs a destructive command when the stolen token stops working, and erased the home folder in the TanStack wave." 8 '        ' '        ' $cRed
  Wrap "Stop it with $($stop)delete the files above." 8 '        ' '        ' $cRed
}
if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0 -or $NPM_UPD -eq 1) {
  if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0) {
    if ($WIPER_HIT -eq 0) { Pair "$cRed$gX$cRst" 'npm worms' 16 "${cRed}signs of the malware found$cRst" }
  } else { Pair "$cYel!$cRst" 'npm worms' 16 "${cYel}a bad version to update$cRst" }
  foreach ($r in $NpmRows) {
    if ($r[0].EndsWith($NpmCacheTag)) { $w = "downloaded into npm's cache" }
    elseif ($r[0] -match '[/\\](package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lock)$') { $w = 'listed in this lockfile' }
    else { $w = 'installed' }
    Emit "        $(Short $r[0])"; Emit "          $($r[1]) ${cDim}($(Npm-Label $r[2])), $w$cRst"
  }
  foreach ($r in $Persist) { Emit "        $(Short $r[0])"; Emit "          $($r[1])" }
  foreach ($t in $NpmTags) { Wrap (Incident-Line $t) 8 '        ' '        ' $cDim }
} elseif ($WIPER_HIT -eq 0 -and ($NpmSlow -gt 0 -or $NpmUnread -gt 0)) {
  $why = New-Object System.Collections.Generic.List[string]
  if ($NpmSlow -gt 0) { $why.Add("$(Plural $NpmSlow 'file' 'files') took too long") }
  if ($NpmUnread -gt 0) { $why.Add("part of npm's cache could not be read") }
  Pair "$cYel!$cRst" 'npm worms' 16 "${cYel}not fully checked: $($why -join ', ')$cRst"
} elseif ($WIPER_HIT -eq 0) {
  Pair "$cGrn$gOk$cRst" 'npm worms' 16 "none of $($NpmBad.Count) bad versions or $($NpmAny.Count) bad packages"
  Emit "$ind26${cDim}checked $(Plural $N_LOCK 'lockfile' 'lockfiles'), global installs and npm's cache$cRst"
}
if ($EXT_HIT -eq 1) {
  Pair "$cRed$gX$cRst" 'Editor extensions' 16 "${cRed}signs of the malware found$cRst"
  foreach ($r in $ExtRows) { Emit "        $(Short $r[0])"; Emit "          $($r[1]) ${cDim}($(Npm-Label $r[2])), installed$cRst" }
  foreach ($r in $ExtPersist) { Emit "        $(Short $r[0])"; Emit "          $($r[1])" }
  foreach ($t in $ExtTags) { Wrap (Incident-Line $t) 8 '        ' '        ' $cDim }
}
foreach ($p in $Platforms) {
  if ($PlatFound -contains $p.Id) {
    Pair "$cYel!$cRst" $p.Name 16 $p.Found
    Wrap $p.Advice 26 $ind26 $ind26 $cDim
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
if ($N_OLD -gt 0) { $G1 = "$cYel!$cRst"; $D1 = "$N_AG found, $(Plural $N_OLD 'security fix' 'security fixes') to install" }
elseif ($N_YOLO -gt 0) { $G1 = "$cYel!$cRst"; $D1 = "$N_AG found, $N_YOLO set to run commands without asking" }
elseif ($N_AG -eq 0) { $G1 = "$cDim$gMid$cRst"; $D1 = 'none found' }
elseif ($N_IDLE -gt 0) { $G1 = "$cYel$gRing$cRst"; $D1 = "$N_AG found, $N_IDLE idle: $(First-Names $IdleNames 2)" }
else { $G1 = "$cGrn$gOk$cRst"; $D1 = "$N_AG found, all used in the last 30 days" }
if ($N_AK -gt 0) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, $(Plural $N_AK 'file links' 'files link') to your SSH logins" }
elseif ($N_MCP_TOKEN -gt 1) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, tokens in $N_MCP_TOKEN files, like $(Short $McpTokFirst)" }
elseif ($N_MCP_TOKEN -eq 1) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, a token in $(Short $McpTokFirst)" }
elseif ($N_AUTO -gt 0) { $G2 = "$cYel!$cRst"; $D2 = "$McpSum, $(Plural $N_AUTO_PROJ 'project acts' 'projects act') on opening" }
elseif ($McpRows.Count -gt 0) { $G2 = "$cGrn$gOk$cRst"; $D2 = "$McpSum, no tokens in their configs" }
else { $G2 = "$cGrn$gOk$cRst"; $D2 = 'none configured' }
if ($KEY_FILES -gt 1) { $G3 = "$cRed$gX$cRst"; $D3 = "$KEY_FILES files, like $(Short $KeyFirst[0]) ($($KeyFirst[1]))" }
elseif ($KEY_FILES -eq 1) { $G3 = "$cRed$gX$cRst"; $D3 = "$(Short $KeyFirst[0]) holds $($KeyFirst[1]) keys" }
elseif ($N_SESS -gt 0) { $G3 = "$cRed$gX$cRst"; $D3 = "keys in $(Plural $N_SESS 'agent session' 'agent sessions'): $($SessRows[0][0])" }
elseif ($SESS_PARTIAL) { $G3 = "$cYel!$cRst"; $D3 = 'none in files; agent sessions partly checked' }
elseif ($N_SSH_OPEN -gt 0) { $G3 = "$cYel$gRing$cRst"; $D3 = "none in plain text, but $(Plural $N_SSH_OPEN 'SSH key has' 'SSH keys have') no passphrase" }
else { $G3 = "$cGrn$gOk$cRst"; $D3 = 'no AI or cloud keys in plain text' }
if ($N_ALLOW -eq 0) { $G4 = "$cGrn$gOk$cRst"; $D4 = 'no saved commands with keys' }
elseif ($N_ALLOW_NPM -gt 0 -and $N_ALLOW -eq 1) { $G4 = "$cRed$gX$cRst"; $D4 = '1 saved key, and an npm publish would ship it' }
elseif ($N_ALLOW_NPM -gt 0) { $G4 = "$cRed$gX$cRst"; $D4 = "$N_ALLOW saved keys, $N_ALLOW_NPM that an npm publish would ship" }
elseif ($N_ALLOW -eq 1) { $G4 = "$cRed$gX$cRst"; $D4 = "a saved key in $(Short $AllowFirst)" }
else { $G4 = "$cRed$gX$cRst"; $D4 = "saved keys in $N_ALLOW files" }
$leaks = @($Platforms | Where-Object { $PlatFound -contains $_.Id })
if ($WIPER_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = 'gh-token-monitor: stop it before revoking tokens' }
elseif ($ANY_MAL -eq 1 -and $PY_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = "$MalShort and $PyShort malware found. Act now" }
elseif ($ANY_MAL -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = "signs of $MalWhat. Act now" }
elseif ($PY_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = "signs of the $PyShort malware. Act now" }
elseif ($NpmSlow -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'npm packages not fully checked: took too long' }
elseif ($NpmUnread -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'npm packages not fully checked: cache unreadable' }
elseif ($LitePyc.Count -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'possible LiteLLM leftover: check cook.pyc' }
elseif ($NPM_UPD -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'an npm package to update, see section 5' }
elseif ($leaks.Count -ge 2) {
  $G5 = "$cYel!$cRst"
  $names = @($leaks | ForEach-Object { $_.Name })
  $l = ($names[0..($names.Count - 2)] -join ', ') + ' and ' + $names[$names.Count - 1]
  if ($leaks.Count -ge 3) { $D5 = "$l found: rotate keys" } else { $D5 = "$l found: rotate their keys" }
}
elseif ($leaks.Count -eq 1) { $G5 = "$cYel!$cRst"; $D5 = $leaks[0].Summary }
else { $G5 = "$cGrn$gOk$cRst"; $D5 = "none of the $N_LEAKS recent leaks it checks" }
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
