<#
.SYNOPSIS
  One-time Reasonix + OpenCode Go setup.
  Stores the API key and adds the provider to Reasonix's global config.

.DESCRIPTION
  Run this script ONCE. It will:
    - Prompt for the OpenCode Go API key (masked input)
    - Save it to %APPDATA%\reasonix\credentials
    - Add the opencode-go-deepseek provider to %APPDATA%\reasonix\config.toml
    - Set opencode-go-deepseek as the default model
    - Backup any existing config before writing

  Afterwards, just run: reasonix code

.PARAMETER NoDefault
  Add the provider but do NOT change the existing default_model.

.PARAMETER SkipKeyPrompt
  Skip the API key prompt. Use when the key is already in credentials
  and you only want to add/update the provider config.

.EXAMPLE
  .\scripts\setup-opencode-go.ps1

.EXAMPLE
  .\scripts\setup-opencode-go.ps1 -NoDefault

.EXAMPLE
  .\scripts\setup-opencode-go.ps1 -SkipKeyPrompt
#>
param(
  [switch] $NoDefault,
  [switch] $SkipKeyPrompt,
  [switch] $UseDeepseekReasoning
)

$ErrorActionPreference = "Stop"

# === Check Reasonix is installed ===
$rxVersion = reasonix --version 2>$null
if (-not $rxVersion) {
  Write-Host ""
  Write-Host "Reasonix가 설치되지 않았습니다." -ForegroundColor Yellow
  Write-Host "설치하려면: npm install -g reasonix@next" -ForegroundColor Cyan
  Write-Host "또는 bootstrap-all.ps1 을 실행하세요." -ForegroundColor Cyan
  Write-Host ""
  $confirm = Read-Host "계속 진행하시겠습니까? (Reasonix 미설치 시 provider 설정만 저장됩니다) [Y/n]"
  if ($confirm -ne "" -and $confirm -notmatch '^(y|Y)') {
    Write-Host "중단합니다."
    exit 1
  }
}

$ProviderName = "opencode-go-deepseek"
$KeyEnvName   = "OPENCODE_GO_API_KEY"

$reasoning = if ($UseDeepseekReasoning) { "deepseek" } else { "none" }

$NewProviderBlock = @"
[[providers]]
name = "opencode-go-deepseek"
kind = "openai"
base_url = "https://opencode.ai/zen/go/v1"
models = ["deepseek-v4-flash", "deepseek-v4-pro"]
default = "deepseek-v4-flash"
api_key_env = "OPENCODE_GO_API_KEY"
context_window = 1000000
  reasoning_protocol = "$reasoning"
  price = { cache_hit = 0.0028, input = 0.14, output = 0.28, currency = "$" }
"@

$NewDefaultModel = "default_model = ""$ProviderName"""

# === Paths ===

$CredentialsDir  = Join-Path $env:APPDATA "reasonix"
$CredentialsPath = Join-Path $CredentialsDir "credentials"
$ConfigPath      = Join-Path $CredentialsDir "config.toml"

# ==============================================================================
# 1. PROMPT FOR API KEY AND SAVE TO CREDENTIALS
# ==============================================================================

if (-not $SkipKeyPrompt) {
  Write-Host "Reasonix OpenCode Go Setup"
  Write-Host "============================"
  Write-Host ""

  $secureKey = Read-Host "Enter OpenCode Go API key" -AsSecureString

  if ($null -eq $secureKey -or $secureKey.Length -eq 0) {
    Write-Error "OpenCode Go API key is required."
    exit 1
  }

  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)

  try {
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    if ([string]::IsNullOrWhiteSpace($plainKey)) {
      Write-Error "OpenCode Go API key is required."
      exit 1
    }

    New-Item -ItemType Directory -Force -Path $CredentialsDir | Out-Null
    $keyLine = "$KeyEnvName=$plainKey"

    if (Test-Path -LiteralPath $CredentialsPath) {
      $existing = Get-Content -LiteralPath $CredentialsPath
      $updated = $false

      $next = foreach ($line in $existing) {
        if ($line -match "^\s*$([regex]::Escape($KeyEnvName))\s*=") {
          $updated = $true
          $keyLine
        } else {
          $line
        }
      }

      if (-not $updated) {
        $next += $keyLine
      }

      Set-Content -LiteralPath $CredentialsPath -Value $next -Encoding UTF8
    } else {
      Set-Content -LiteralPath $CredentialsPath -Value @($keyLine) -Encoding UTF8
    }

    Write-Host ""
    Write-Host "API key saved to $CredentialsPath"
  }
  finally {
    if ($bstr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $plainKey = $null
  }
} else {
  Write-Host "Skipping API key prompt (-SkipKeyPrompt)."
}

# ==============================================================================
# 2. BACKUP EXISTING CONFIG
# ==============================================================================

New-Item -ItemType Directory -Force -Path $CredentialsDir | Out-Null

if (Test-Path -LiteralPath $ConfigPath) {
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupPath = "$ConfigPath.bak-$ts"
  Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
  Write-Host "Config backup: $backupPath"
}

# ==============================================================================
# 3. READ EXISTING CONFIG LINES
# ==============================================================================

$lines = if (Test-Path -LiteralPath $ConfigPath) {
  @(Get-Content -LiteralPath $ConfigPath)
} else {
  @()
}

# ==============================================================================
# 4. MARK TARGET PROVIDER BLOCK INDICES (two-pass: find then filter)
# ==============================================================================

$removeIndices = @{}  # line indices to remove (target provider block)

# Determine for each line whether it belongs to a target provider block.
# A provider block starts at [[providers]] and ends at the next top-level
# section header ([[...]] or [...]) or EOF.
# A block is the target if any line within it matches:
#     name = "opencode-go-deepseek"

$inProviderBlock = $false
$thisBlockIsTarget = $false
$thisBlockIndices = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
  $trimmed = $lines[$i].TrimStart()

  if ($trimmed -match '^\[\[providers\]\]') {
    # Flush previous block
    if ($inProviderBlock -and $thisBlockIsTarget) {
      foreach ($idx in $thisBlockIndices) {
        $removeIndices[$idx] = $true
      }
    }
    $thisBlockIndices = @($i)
    $inProviderBlock = $true
    $thisBlockIsTarget = $false
    continue
  }

  if ($inProviderBlock) {
    # Section headers end the block
    if ($trimmed -match '^\[' -and $trimmed -notmatch '^\[\[providers\]\]') {
      if ($thisBlockIsTarget) {
        foreach ($idx in $thisBlockIndices) {
          $removeIndices[$idx] = $true
        }
      }
      $inProviderBlock = $false
      $thisBlockIsTarget = $false
      $thisBlockIndices = @()
      continue
    }

    # Still inside the block
    $thisBlockIndices += $i

    # Check if this block declares our provider name
    if ($trimmed -match "^name\s*=\s*""$([regex]::Escape($ProviderName))""") {
      $thisBlockIsTarget = $true
    }
  }
}

# Flush last block
if ($inProviderBlock -and $thisBlockIsTarget) {
  foreach ($idx in $thisBlockIndices) {
    $removeIndices[$idx] = $true
  }
}

# ==============================================================================
# 5. BUILD OUTPUT: exclude target provider block
# ==============================================================================

$outLines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
  if (-not $removeIndices.ContainsKey($i)) {
    [void]$outLines.Add($lines[$i])
  }
}

# ==============================================================================
# 6. HANDLE default_model
# ==============================================================================

$hasDefaultModel = $false
$firstDefaultIdx = -1

for ($idx = 0; $idx -lt $outLines.Count; $idx++) {
  if ($outLines[$idx] -match '^\s*default_model\s*=') {
    if (-not $hasDefaultModel) {
      $firstDefaultIdx = $idx
    } else {
      # Mark duplicate for removal
      $outLines[$idx] = $null
    }
    $hasDefaultModel = $true
  }
}

# Clean null entries
$filtered = New-Object System.Collections.Generic.List[string]
for ($idx = 0; $idx -lt $outLines.Count; $idx++) {
  if ($null -ne $outLines[$idx]) {
    [void]$filtered.Add($outLines[$idx])
  }
}
$outLines = $filtered

# Re-scan firstDefaultIdx after filtering
$firstDefaultIdx = -1
for ($idx = 0; $idx -lt $outLines.Count; $idx++) {
  if ($outLines[$idx] -match '^\s*default_model\s*=') {
    $firstDefaultIdx = $idx
    break
  }
}

if (-not $NoDefault) {
  if ($firstDefaultIdx -ge 0) {
    $outLines[$firstDefaultIdx] = $NewDefaultModel
  } else {
    # Insert at top, after comments / version line
    $insertIdx = 0
    while ($insertIdx -lt $outLines.Count) {
      $t = $outLines[$insertIdx].TrimStart()
      if ($t -ne "" -and $t -notmatch '^(#|config_version\s*=)') {
        break
      }
      $insertIdx++
    }
    $head = New-Object System.Collections.Generic.List[string]
    for ($idx = 0; $idx -lt $insertIdx; $idx++) {
      [void]$head.Add($outLines[$idx])
    }
    [void]$head.Add($NewDefaultModel)
    [void]$head.Add("")
    for ($idx = $insertIdx; $idx -lt $outLines.Count; $idx++) {
      [void]$head.Add($outLines[$idx])
    }
    $outLines = $head
  }
}

# ==============================================================================
# 7. APPEND PROVIDER BLOCK
# ==============================================================================

# Ensure trailing newline before provider block
if ($outLines.Count -gt 0) {
  $last = $outLines[$outLines.Count - 1]
  if ([string]::IsNullOrWhiteSpace($last) -eq $false) {
    [void]$outLines.Add("")
  }
}

$providerLines = $NewProviderBlock -split "`r?`n"
foreach ($pl in $providerLines) {
  if ($pl.Length -gt 0 -or $outLines.Count -eq 0 -or $outLines[$outLines.Count - 1] -ne "") {
    [void]$outLines.Add($pl)
  }
}

# ==============================================================================
# 8. WRITE CONFIG
# ==============================================================================

Set-Content -LiteralPath $ConfigPath -Value $outLines.ToArray() -Encoding UTF8

# ==============================================================================
# 9. DONE
# ==============================================================================

Write-Host "Config updated: $ConfigPath"
Write-Host ""
Write-Host "Reasonix + OpenCode Go setup complete."
if (-not $NoDefault) {
  Write-Host "Default model: $ProviderName"
} else {
  Write-Host "Provider added, default_model not changed."
  Write-Host "Switch inside Reasonix: /model $ProviderName/deepseek-v4-flash"
}
Write-Host ""
Write-Host "You can now run:"
Write-Host "  reasonix code"
Write-Host "  reasonix run ""hello"""
