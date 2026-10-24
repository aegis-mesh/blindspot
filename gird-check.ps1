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
Key formats come from Argus. gird-check.sh is the source of truth for every check.

  powershell -ExecutionPolicy Bypass -File gird-check.ps1            a short summary
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -Full      every detail
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -All       also scans Desktop, Documents and Downloads
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -Offline   shares nothing (DO_NOT_TRACK=1 works too)
  powershell -ExecutionPolicy Bypass -File gird-check.ps1 -Save      saves the full report as a text file
  -NoColor (or NO_COLOR=1)                                            plain text, no colors

Runs on Windows PowerShell 5.1 and PowerShell 7. This file is plain ASCII on purpose:
Windows PowerShell 5.1 reads a script without a byte order mark as the ANSI code page,
so every non-ASCII character below is built from its code point.
#>
param(
  [switch]$All, [switch]$Full, [switch]$Offline, [switch]$Save, [switch]$NoColor, [switch]$Help,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$OptAll = [bool]$All; $OptFull = [bool]$Full; $OptOffline = [bool]$Offline; $OptSave = [bool]$Save; $OptNoColor = [bool]$NoColor
foreach ($arg in $Rest) {
  switch ($arg) {
    '--all' { $OptAll = $true } '--full' { $OptFull = $true } '--save' { $OptSave = $true }
    '--offline' { $OptOffline = $true } '--no-color' { $OptNoColor = $true } '--no-game' { }
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
$P_ANTHROPIC = 'sk-ant-[A-Za-z0-9_-]{90,}'
$P_OPENAI = 'sk-proj-[A-Za-z0-9_-]{120,}|sk-svcacct-[A-Za-z0-9_-]{60,}|(^|[^A-Za-z0-9-])sk-[A-Za-z0-9]{48}([^A-Za-z0-9]|$)'
$P_GOOGLE = 'AIza[0-9A-Za-z_-]{35}|(^|[^A-Za-z0-9])AQ\.[A-Za-z0-9_-]{40,}'
$P_OPENROUTER = 'sk-or-v1-[a-f0-9]{64}'
$P_GROQ = 'gsk_[A-Za-z0-9]{52}'
$P_XAI = 'xai-[A-Za-z0-9]{64,}'
$P_HF = '(^|[^A-Za-z0-9_])hf_[A-Za-z0-9]{34,40}([^A-Za-z0-9_]|$)'
$P_PPLX = 'pplx-[A-Za-z0-9]{40,52}'
$P_REPLICATE = 'r8_[A-Za-z0-9]{37}'
$P_AWS = '(^|[^A-Z0-9])AKIA[0-9A-Z]{16}([^A-Z0-9]|$)|bedrock-api-key-YmVkcm9jay5hbWF6b25hd3MuY29t'
$P_GITHUB = 'gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}'
$P_NPM = 'npm_[A-Za-z0-9]{36}'
$ALL_KEYS = "$P_ANTHROPIC|$P_OPENAI|$P_GOOGLE|$P_OPENROUTER|$P_GROQ|$P_XAI|$P_HF|$P_PPLX|$P_REPLICATE|$P_AWS|$P_GITHUB|$P_NPM"
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
function Providers-In([string]$f) {
  if ($SlowFiles.Contains($f)) { return @() }
  $t = Read-Text $f; if ($null -eq $t) { return @() }
  $seen = New-Object System.Collections.Generic.List[string]
  try { $all = @($RxKeys.Matches($t)) } catch { Mark-Slow $f; return @() }
  foreach ($m in $all) {
    $s = $m.Value -replace '^[^A-Za-z]+', ''
    $p = $null
    if ($s -cmatch '^sk-ant-') { $p = 'Anthropic' }
    elseif ($s -cmatch '^sk-or-v1-') { $p = 'OpenRouter' }
    elseif ($s -cmatch '^sk-') { $p = 'OpenAI' }
    elseif ($s -cmatch '^(AIza|AQ[.])') { $p = 'Google' }
    elseif ($s -cmatch '^gsk_') { $p = 'Groq' }
    elseif ($s -cmatch '^xai-') { $p = 'xAI' }
    elseif ($s -cmatch '^hf_') { $p = 'Hugging Face' }
    elseif ($s -cmatch '^pplx-') { $p = 'Perplexity' }
    elseif ($s -cmatch '^r8_') { $p = 'Replicate' }
    elseif ($s -cmatch '^(AKIA|bedrock-api-key)') { $p = 'AWS' }
    elseif ($s -cmatch '^(gh[pousr]_|github_pat_)') { $p = 'GitHub' }
    elseif ($s -cmatch '^npm_') { $p = 'npm' }
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
$PROVIDER_IDS = 'anthropic openai google openrouter groq xai huggingface perplexity replicate aws github npm'
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
$Sites = New-Object System.Collections.Generic.List[string]
$script:ScanN = 0
function Is-Pruned([string]$path, [string]$name, [int]$depth) {
  foreach ($n in $PruneNames) { if ($name -ceq $n) { return $true } }
  foreach ($p in $PrunePaths) { if ($path.Equals($p, $PathCmp)) { return $true } }
  ($depth -eq 1) -and $name.StartsWith('OneDrive', $PathCmp)
}
# Files the TanStack and keyv worms plant in a project (Wiz; Snyk: .claude/setup.mjs, .claude/math_init.js
# and .vscode/setup.mjs).
function Is-WormFile([string]$parent, [string]$name) {
  (($parent -ceq '.claude' -or $parent -ceq '.vscode') -and ($name -ceq 'router_runtime.js' -or $name -ceq 'tanstack_runner.js')) -or
  (($parent -ceq '.claude' -or $parent -ceq '.vscode') -and $name -ceq 'setup.mjs') -or ($parent -ceq '.claude' -and $name -ceq 'math_init.js')
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
      continue
    }
    if ($name -ceq '.env' -or $name.StartsWith('.env.') -or $name -ceq '.envrc' -or $name -ceq '.mcp.json' -or $name -ceq 'pyvenv.cfg' -or $isSettings -or
      ($name -ceq 'mcp.json' -and ($parent -ceq '.cursor' -or $parent -ceq '.vscode'))) {
      $Found.Add($path)
      $script:ScanN++
      if ($script:ScanN % 4 -eq 1) { Progress "Checking $(Short $path)" }
    } elseif ($name -ceq 'package-lock.json' -or $name -ceq 'npm-shrinkwrap.json' -or $name -ceq 'pnpm-lock.yaml' -or $name -ceq 'yarn.lock' -or $name -ceq 'bun.lock') { $LockFiles.Add($path) }
    elseif ($parent -ceq '.vscode' -and $name -ceq 'tasks.json') { $TaskFiles.Add($path) }
    elseif (Is-WormFile $parent $name) { $WormFiles.Add($path) }
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
# The TanStack and keyv worms plant one of these in the folder and run it from a hook or a task.
# A worm file counts only when a command runs it (an interpreter given its path, the path as the
# command itself, or a task's argument), not when a rule or a guard merely names it.
$WormName = '\.(claude|vscode)[/\\]+(router_runtime\.js|tanstack_runner\.js|setup\.mjs|math_init\.js)'
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
    if ($nm -eq 'Hugging Face') { $id = 'huggingface' } else { $id = $nm.ToLowerInvariant() }
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
Login @((J $HomeDir '_netrc'), (J $HomeDir '.netrc')) 'saved passwords in .netrc' 'netrc'
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
Progress "Checking $(Plural $SitesAll.Count 'Python environment' 'Python environments') for the LiteLLM malware"
$N_PY = 0; $N_LITE = 0; $LiteVers = New-Object System.Collections.Generic.List[string]
$LiteBad = New-Object System.Collections.Generic.List[string]; $LitePyc = New-Object System.Collections.Generic.List[string]
foreach ($sp in $SitesAll) {
  if (-not (Is-Dir $sp)) { continue }
  $N_PY++
  foreach ($d in (Glob-Dirs $sp 'litellm-*.dist-info')) {
    $v = [regex]::Replace(([IO.Path]::GetFileName($d) -replace '^litellm-', '' -replace '\.dist-info$', ''), '[\x00-\x1f\x7f-\x9f]', '?')
    $N_LITE++; if (-not $LiteVers.Contains($v)) { $LiteVers.Add($v) }
  }
  $bad = New-Object System.Collections.Generic.List[string]
  if (Is-Dir (J $sp 'litellm-1.107.0.dist-info')) { $bad.Add('litellm 1.107.0') }
  if (Is-File (J $sp 'cook.pth')) { $bad.Add('cook.pth') }
  if (Is-File (J $sp 'cook.py')) { $bad.Add('cook.py') }
  $pyc = @(); try { if (Is-Dir (J $sp '__pycache__')) { $pyc = @([IO.Directory]::GetFiles((J $sp '__pycache__'), 'cook.*.pyc')) } } catch { }
  if ($pyc.Count -gt 0) { $LitePyc.Add("$(Short $sp): cook.pyc") }
  if ($bad.Count -gt 0) { $LiteBad.Add("$(Short $sp): $($bad -join ', ')") }
}
$Marks = New-Object System.Collections.Generic.List[string]
foreach ($t in $TempDirs) {
  if (-not (Is-Dir $t)) { continue }
  if (Exists (J $t 'remote_code_loader.lock')) { $Marks.Add((J $t 'remote_code_loader.lock')) }
  foreach ($pat in @('.pc_once_*', '.pc_sq_*', '.pc_e_*')) {
    try { foreach ($m in ([IO.Directory]::GetFileSystemEntries($t, $pat) | Sort-Object)) { $Marks.Add($m) } } catch { }
  }
}
if ($env:PRIVCOLLECT_ACTIVE) { $Marks.Add('PRIVCOLLECT_ACTIVE is set in this shell') }
# The hourly loader that holds remote_code_loader.lock only runs on macOS and Linux.
$LOADER = 0
$UvBad = $false
foreach ($uv in @((J $LocalAppData 'uv/cache'), (J $HomeDir '.cache/uv'))) {
  if ($UvBad -or -not (Is-Dir $uv)) { continue }
  try {
    $q = New-Object System.Collections.Generic.Queue[object]; $q.Enqueue(@($uv, 0))
    while ($q.Count -gt 0 -and -not $UvBad) {
      $it = $q.Dequeue()
      foreach ($e in (Entries $it[0])) {
        if ($e.Name.StartsWith('litellm-1.107.0')) { $UvBad = $true; break }
        if ((Is-DirInfo $e) -and -not (Is-Link $e) -and $it[1] + 1 -lt 6) { $q.Enqueue(@($e.FullName, ($it[1] + 1))) }
      }
    }
  } catch { }
}
$LITELLM_HIT = 0
if ($LiteBad.Count -gt 0 -or $Marks.Count -gt 0 -or $LOADER -eq 1) { $LITELLM_HIT = 1 }
if ($LITELLM_HIT -eq 1) { Progress 'Signs of the LiteLLM malware found' }
elseif ($LitePyc.Count -gt 0) { Progress 'A leftover cook.pyc may come from the LiteLLM malware' }
# npm packages with malware, each one named in a GitHub malware advisory: Axios GHSA-fw8c-xr5c-95f9,
# TanStack GHSA-g7cv-rxg3-hmpx, Mistral GHSA-3q49-cfcf-g5fm, GHSA-2rm2-c4pc-xxr9 and
# GHSA-rccm-wwph-vgxc, OpenSearch GHSA-298w-vvm4-ww55, and one advisory per package for the rest.
# A version of * means every version of that name is malware. tensorlake's advisory also lists every
# version, but names only 0.5.144 as malicious, so only that one is flagged. Not complete: the AntV, UiPath and
# Red Hat waves and most packages the keyv worm spread to are not listed. The same list as gird-check.sh.
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
'@
$NpmBad = @{}; $NpmAny = @{}; $NpmNames = New-Object System.Collections.Generic.List[string]; $N_BAD_NPM = 0
foreach ($l in ($BadNpm -split "`r?`n")) {
  $p = $l -split ' '; if ($p.Count -lt 3) { continue }
  $N_BAD_NPM++
  if ($p[1] -ceq '*') { $NpmAny[$p[0]] = $p[2] } else { $NpmBad["$($p[0])@$($p[1])"] = $p[2] }
  if (-not $NpmNames.Contains($p[0])) { $NpmNames.Add($p[0]) }
}
function Npm-Label([string]$t) {
  switch ($t) {
    'axios' { 'Axios takeover, March 2026' } 'tanstack' { 'TanStack worm, May 2026' } 'mistral' { 'Mistral AI packages, May 2026' }
    'bitwarden' { 'Bitwarden CLI, April 2026' } 'mastra' { 'Mastra worm, June 2026' } 'keyv' { 'keyv worm, August 2026' }
    'opensearch' { 'OpenSearch client, May 2026' } 'tensorlake' { 'tensorlake package, October 2026' }
    default { 'SANDWORM_MODE worm, February 2026' }
  }
}
$NpmRows = New-Object System.Collections.Generic.List[object]; $NpmCacheRows = New-Object System.Collections.Generic.List[object]; $NpmSeen = @{}
$NpmCacheTag = " (npm's download cache)"
# Versions are shown only if they look like versions, so a package can't put terminal control codes in the report.
function Npm-Hit([string]$where, [string]$nm, [string]$v) {
  if ($v -cnotmatch '^[0-9A-Za-z.+_-]+\z') { $v = '?' }
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
# npm's download cache keeps a package after it is uninstalled, and the malware ran when it installed.
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
$NPM_HIT = 0; if ($NpmRows.Count -gt 0) { $NPM_HIT = 1 }
# What these worms leave behind. gh-token-monitor runs a destructive command when the stolen GitHub
# token stops working (it erased the home folder in the TanStack wave, Wiz; in the keyv wave it runs
# an attacker-supplied command, SANS), so it must be stopped before any token is revoked.
$Wiper = New-Object System.Collections.Generic.List[string]
foreach ($m in @((J $HomeDir 'Library/LaunchAgents/com.user.gh-token-monitor.plist'), (J $HomeDir '.config/systemd/user/gh-token-monitor.service'),
    (J $HomeDir '.local/bin/gh-token-monitor.sh'), (J $HomeDir '.config/gh-token-monitor'))) {
  if (Exists $m) { $Wiper.Add($m) }
}
# Its logs in the shared /tmp count only if this person owns them. Windows has no /tmp.
if (-not $OnWindows) {
  foreach ($m in @('/tmp/gh-token-monitor.out.log', '/tmp/gh-token-monitor.err.log')) {
    if (-not (Exists $m)) { continue }
    $owner = ''; try { $owner = [string](Get-Item -LiteralPath $m -Force -ErrorAction Stop).User } catch { }
    if ($owner -and $owner -ceq [Environment]::UserName) { $Wiper.Add($m) }
  }
}
# The Mastra worm's startup files (Socket).
$Persist = New-Object System.Collections.Generic.List[object]
foreach ($m in @((J $HomeDir 'Library/LaunchAgents/com.nvm.protocal.plist'), (J $HomeDir 'Library/NodePackages/protocal.cjs'),
    (J $HomeDir '.config/systemd/user/nvmconf.service'), (J $HomeDir '.config/systemd/nvmconf/protocal.cjs'))) {
  if (Exists $m) { $Persist.Add(@($m, 'starts the Mastra worm at login')) }
}
if ($OnWindows) {
  if ($env:ProgramData -and (Exists (J $env:ProgramData 'NodePackages/protocal.cjs'))) { $Persist.Add(@((J $env:ProgramData 'NodePackages/protocal.cjs'), 'starts the Mastra worm at login')) }
  try {
    $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
    if ($rk) { if ($null -ne $rk.GetValue('NvmProtocal')) { $Persist.Add(@('NvmProtocal in your startup programs', 'starts the Mastra worm at login')) }; $rk.Close() }
  } catch { }
}
foreach ($f in $WormFiles) { $Persist.Add(@($f, 'a file the TanStack and keyv worms plant')) }
foreach ($f in $WormRefs) { $Persist.Add(@($f, 'runs a file the TanStack and keyv worms plant')) }
$WIPER_HIT = 0; if ($Wiper.Count -gt 0) { $WIPER_HIT = 1 }
$MAL_HIT = 0; if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0 -or $WIPER_HIT -eq 1) { $MAL_HIT = 1 }
if ($WIPER_HIT -eq 1) { Progress 'A wiper waits for a GitHub token to be revoked: gh-token-monitor' }
elseif ($MAL_HIT -eq 1) { Progress 'Signs of npm malware found' }
$OC = 0; if ((Has-Command 'opencode') -or (Is-Dir (J $HomeDir '.config/opencode')) -or (Is-Dir (J $HomeDir '.local/share/opencode'))) { $OC = 1 }
$RW = 0; if ((Has-Command 'railway') -or (Is-File (J $HomeDir '.railway/config.json'))) { $RW = 1 }
$ZB = 0; if ((Has-Command 'zeabur') -or (Is-Dir (J $HomeDir '.config/zeabur'))) { $ZB = 1 }

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
if ($LITELLM_HIT -eq 0 -and $LitePyc.Count -gt 0) { Add-Todo 5 'A leftover cook.pyc can come from the LiteLLM 1.107.0 malware. If litellm 1.107.0 was ever installed there, treat this machine as compromised, follow LiteLLM''s advisory and rotate every key it could reach.' }
if ($LITELLM_HIT -eq 1) { Add-Todo 5 'Treat this machine as compromised. Don''t run Python in the affected environments, follow LiteLLM''s advisory, and rotate every key the machine could reach.' }
$Store = 'a secrets manager'; if ($OnWindows) { $Store = 'Windows Credential Manager or a secrets manager' }
if ($KEY_FILES -gt 0) { Add-Todo 3 "Move keys out of shell profiles, history and .env files into $Store, then rotate them." }
if ($HIST_KEYS -gt 0) { Add-Todo 3 'Keys in shell history were typed into a command. Treat them as exposed and rotate them.' }
if ($N_MCP_TOKEN -gt 0) { Add-Todo 2 'Replace tokens written into MCP configs with environment variable references, then rotate them.' }
if ($N_ALLOW -gt 0) { Add-Todo 4 'Delete the saved Claude Code commands that contain keys, add .claude/ to .npmignore, and rotate those keys.' }
if ($N_SSH_OPEN -gt 0) { Add-Todo 3 'Add a passphrase to SSH keys that have none, with ssh-keygen -p -f followed by the key file.' }
if ($N_IDLE -gt 0) { Add-Todo 1 "Remove agents you no longer use: $($IdleNames -join ', '). A poisoned package can drive an installed agent, which is how the Nx attack stole keys." }
if ($N_AUTO -gt 0) { Add-Todo 2 'Read the settings marked in section 2 before an agent or editor opens those folders, and delete anything you didn''t put there yourself. A cloned project can bring these with it.' }
if ($OC -eq 1 -or $RW -eq 1 -or $ZB -eq 1) { Add-Todo 5 'If you used OpenCode Console or deploy on Railway or Zeabur, rotate the keys stored there, even if nothing above looks wrong.' }
$ISSUES = $Todo.Count

$SCORE = 100
if ($LITELLM_HIT -eq 1) { $SCORE -= 40 }
if ($MAL_HIT -eq 1) { $SCORE -= 40 }
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
if ($LITELLM_HIT -eq 1 -or $MAL_HIT -eq 1) { $Sev = $cRed }
elseif ($KEY_FILES -gt 0 -or $N_ALLOW -gt 0 -or $N_MCP_TOKEN -gt 0) { $Sev = $cRed }
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
elseif ($MAL_HIT -eq 1) { $Act = 'ACT NOW: SIGNS OF NPM MALWARE' }
elseif ($LITELLM_HIT -eq 1) { $Act = 'ACT NOW: SIGNS OF THE LITELLM 1.107.0 MALWARE' }
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
Section '05' 'RECENT KEY LEAKS' '5 checked'
if ($LITELLM_HIT -eq 1) {
  Pair "$cRed$gX$cRst" 'LiteLLM 1.107.0' 16 "${cRed}signs of the malware found$cRst"
  foreach ($l in (@($LiteBad) + @($Marks))) { Emit "        $(Short $l)" }
  Wrap "Don't run Python or pip in these environments. Advisory: docs.litellm.ai/blog/security-incident-oct-21-2026" 8 '        ' '        '
} elseif ($LitePyc.Count -gt 0) {
  Pair "$cYel!$cRst" 'LiteLLM 1.107.0' 16 "${cYel}possible leftover$cRst"
  foreach ($l in $LitePyc) { Emit "        $l" }
  Wrap 'A compiled cook file stays behind when cook.py is deleted, which is what the 1.107.0 malware ships. If litellm 1.107.0 was ever installed here, treat this as a hit. Advisory: docs.litellm.ai/blog/security-incident-oct-21-2026' 8 '        ' '        '
} else {
  Pair "$cGrn$gOk$cRst" 'LiteLLM 1.107.0' 16 "no signs in $(Plural $N_PY 'Python environment' 'Python environments')"
  if ($N_LITE -gt 0) { Emit "$ind26${cDim}installed: $($LiteVers -join ' ')$cRst" }
}
if ($UvBad) { Wrap 'Your uv cache holds the 1.107.0 package. Clear it with: uv cache clean litellm' 8 '        ' '        ' $cYel }
if ($WIPER_HIT -eq 1) {
  Pair "$cRed$gX$cRst" 'npm worms' 16 "${cRed}a wiper is waiting$cRst"
  foreach ($l in $Wiper) { Emit "        $(Short $l)" }
  if ($OnWindows) { $stop = 'Get-CimInstance Win32_Process | Where-Object CommandLine -like ''*gh-token-monitor*'' | Invoke-CimMethod -MethodName Terminate, then ' }
  elseif (Is-Dir '/System/Library/CoreServices') { $uidv = ''; try { $uidv = [string](& id -u 2>$null) } catch { }; $stop = "launchctl bootout gui/$uidv/com.user.gh-token-monitor, then pkill -f gh-token-monitor, then " }
  else { $stop = 'systemctl --user disable --now gh-token-monitor.service, then pkill -f gh-token-monitor, then ' }
  Wrap "Don't revoke any GitHub token until it is stopped and these files are gone: gh-token-monitor runs a destructive command when the stolen token stops working, and erased the home folder in the TanStack wave." 8 '        ' '        ' $cRed
  Wrap "Stop it with $($stop)delete the files above." 8 '        ' '        ' $cRed
}
if ($NPM_HIT -eq 1 -or $Persist.Count -gt 0) {
  if ($WIPER_HIT -eq 0) { Pair "$cRed$gX$cRst" 'npm worms' 16 "${cRed}signs of the malware found$cRst" }
  foreach ($r in $NpmRows) { Emit "        $(Short $r[0])"; Emit "          $($r[1]) ${cDim}($(Npm-Label $r[2]))$cRst" }
  foreach ($r in $Persist) { Emit "        $(Short $r[0])"; Emit "          $($r[1])" }
} elseif ($WIPER_HIT -eq 0 -and ($NpmSlow -gt 0 -or $NpmUnread -gt 0)) {
  $why = New-Object System.Collections.Generic.List[string]
  if ($NpmSlow -gt 0) { $why.Add("$(Plural $NpmSlow 'file' 'files') took too long") }
  if ($NpmUnread -gt 0) { $why.Add("part of npm's cache could not be read") }
  Pair "$cYel!$cRst" 'npm worms' 16 "${cYel}not fully checked: $($why -join ', ')$cRst"
} elseif ($WIPER_HIT -eq 0) {
  Pair "$cGrn$gOk$cRst" 'npm worms' 16 "none of $($NpmBad.Count) bad versions or $($NpmAny.Count) bad packages"
  Emit "$ind26${cDim}checked $(Plural $N_LOCK 'lockfile' 'lockfiles'), global installs and npm's cache$cRst"
}
if ($OC -eq 1) {
  Pair "$cYel!$cRst" 'OpenCode' 16 'installed'
  Wrap 'If you used OpenCode Console, the hosted gateway, rotate every provider key you saved there. Keys kept only in the CLI were not affected.' 26 $ind26 $ind26 $cDim
} else { Pair "$cDim$gMid$cRst" 'OpenCode' 16 "${cDim}not installed$cRst" }
if ($RW -eq 1) {
  Pair "$cYel!$cRst" 'Railway' 16 'CLI found'
  Wrap 'Railway asked every customer to rotate all secrets stored on the platform and to check their logs.' 26 $ind26 $ind26 $cDim
} else { Pair "$cDim$gMid$cRst" 'Railway' 16 "${cDim}CLI not found$cRst" }
if ($ZB -eq 1) {
  Pair "$cYel!$cRst" 'Zeabur' 16 'CLI found'
  Wrap 'Zeabur said on 15 October that attackers read service environment variables stored on the platform, and asked every customer to replace all of them. Revoke each key at its provider first.' 26 $ind26 $ind26 $cDim
} else { Pair "$cDim$gMid$cRst" 'Zeabur' 16 "${cDim}CLI not found$cRst" }
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
if ($N_AG -eq 0) { $G1 = "$cDim$gMid$cRst"; $D1 = 'none found' }
elseif ($N_IDLE -gt 0) { $G1 = "$cYel$gRing$cRst"; $D1 = "$N_AG found, $N_IDLE idle: $(First-Names $IdleNames 2)" }
else { $G1 = "$cGrn$gOk$cRst"; $D1 = "$N_AG found, all used in the last 30 days" }
if ($N_MCP_TOKEN -gt 1) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, tokens in $N_MCP_TOKEN files, like $(Short $McpTokFirst)" }
elseif ($N_MCP_TOKEN -eq 1) { $G2 = "$cRed$gX$cRst"; $D2 = "$McpSum, a token in $(Short $McpTokFirst)" }
elseif ($N_AUTO -gt 0) { $G2 = "$cYel!$cRst"; $D2 = "$McpSum, $(Plural $N_AUTO_PROJ 'project acts' 'projects act') on opening" }
elseif ($McpRows.Count -gt 0) { $G2 = "$cGrn$gOk$cRst"; $D2 = "$McpSum, no tokens in their configs" }
else { $G2 = "$cGrn$gOk$cRst"; $D2 = 'none configured' }
if ($KEY_FILES -gt 1) { $G3 = "$cRed$gX$cRst"; $D3 = "$KEY_FILES files, like $(Short $KeyFirst[0]) ($($KeyFirst[1]))" }
elseif ($KEY_FILES -eq 1) { $G3 = "$cRed$gX$cRst"; $D3 = "$(Short $KeyFirst[0]) holds $($KeyFirst[1]) keys" }
elseif ($N_SSH_OPEN -gt 0) { $G3 = "$cYel$gRing$cRst"; $D3 = "none in plain text, but $(Plural $N_SSH_OPEN 'SSH key has' 'SSH keys have') no passphrase" }
else { $G3 = "$cGrn$gOk$cRst"; $D3 = 'no AI or cloud keys in plain text' }
if ($N_ALLOW -eq 0) { $G4 = "$cGrn$gOk$cRst"; $D4 = 'no saved commands with keys' }
elseif ($N_ALLOW_NPM -gt 0 -and $N_ALLOW -eq 1) { $G4 = "$cRed$gX$cRst"; $D4 = '1 saved key, and an npm publish would ship it' }
elseif ($N_ALLOW_NPM -gt 0) { $G4 = "$cRed$gX$cRst"; $D4 = "$N_ALLOW saved keys, $N_ALLOW_NPM that an npm publish would ship" }
elseif ($N_ALLOW -eq 1) { $G4 = "$cRed$gX$cRst"; $D4 = "a saved key in $(Short $AllowFirst)" }
else { $G4 = "$cRed$gX$cRst"; $D4 = "saved keys in $N_ALLOW files" }
$leaks = @(); if ($OC -eq 1) { $leaks += 'OpenCode' }; if ($RW -eq 1) { $leaks += 'Railway' }; if ($ZB -eq 1) { $leaks += 'Zeabur' }
if ($WIPER_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = 'gh-token-monitor: stop it before revoking tokens' }
elseif ($MAL_HIT -eq 1 -and $LITELLM_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = 'npm and LiteLLM malware found. Act now' }
elseif ($MAL_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = 'signs of npm malware. Act now' }
elseif ($LITELLM_HIT -eq 1) { $G5 = "$cRed$gX$cRst"; $D5 = 'signs of the LiteLLM malware. Act now' }
elseif ($NpmSlow -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'npm packages not fully checked: took too long' }
elseif ($NpmUnread -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'npm packages not fully checked: cache unreadable' }
elseif ($LitePyc.Count -gt 0) { $G5 = "$cYel!$cRst"; $D5 = 'possible LiteLLM leftover: check cook.pyc' }
elseif ($leaks.Count -ge 2) {
  $G5 = "$cYel!$cRst"
  $l = ($leaks[0..($leaks.Count - 2)] -join ', ') + ' and ' + $leaks[$leaks.Count - 1]
  if ($leaks.Count -eq 3) { $D5 = "$l found: rotate keys" } else { $D5 = "$l found: rotate their keys" }
}
elseif ($OC -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'OpenCode found: used its Console? Rotate keys' }
elseif ($RW -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'Railway CLI found: rotate secrets stored there' }
elseif ($ZB -eq 1) { $G5 = "$cYel!$cRst"; $D5 = 'Zeabur CLI found: rotate secrets stored there' }
else { $G5 = "$cGrn$gOk$cRst"; $D5 = 'no LiteLLM, npm, OpenCode, Railway, Zeabur leaks' }
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
# hk the shell history files with keys, nm npm malware and wp gh-token-monitor, so the
# page never says to rotate a token while it is there.
# ---------------------------------------------------------------------------
function Card-Url {
  $d = (Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
  "$Web/blindspot/card/#v=2&s=$SCORE&g=$GRADE&a=$N_AG&i=$N_IDLE&m=$N_MCP&mt=$N_MCP_TOKEN&k=$KEY_FILES&p=$($ProvIds -join '.')&al=$N_ALLOW&an=$N_ALLOW_NPM&ll=$LITELLM_HIT&lf=$N_LOGIN&sp=$N_SSH_OPEN&d=$d&pc=$PCT&pn=$PCT_N&u=$LinkRunId&r=$RANK&sk=$N_SSH&hk=$HIST_KEYS&ag=$($AgentIds -join '.')&nm=$MAL_HIT&wp=$WIPER_HIT"
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
      $fs = New-Object IO.FileStream($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
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
  if ($null -ne $OldOutEnc) { try { [Console]::OutputEncoding = $OldOutEnc } catch { } }
}
exit 0
