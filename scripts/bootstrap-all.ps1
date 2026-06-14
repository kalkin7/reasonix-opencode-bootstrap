<#
.SYNOPSIS
  All-in-one Reasonix + OpenCode Go + Skill Store bootstrap for a new machine.
  One script to install everything and verify it works.
  Fully LLM-friendly: accepts -OpenCodeApiKey to skip all interactive prompts.

.DESCRIPTION
  Run this on a FRESH Windows machine to turn it into a Reasonix + OpenCode Go
  DeepSeek V4 development environment with full skill store.

  It does (in order):
    1. Checks prerequisites: PowerShell 7+, Node.js 18+, git
    2. Installs/updates Reasonix Go (npm install -g reasonix@next)
    3. Prompts for OpenCode Go API key, saves to %APPDATA%\reasonix\credentials
    4. Adds opencode-go-deepseek provider to %APPDATA%\reasonix\config.toml
    5. Clones the agent-skills store (GitHub) if not already present
    6. Runs setup_skills.ps1 Bootstrap
    7. Runs setup_skills.ps1 Verify
    8. Quick smoke test: reasonix run "hello"

.PARAMETER OpenCodeApiKey
  API key for OpenCode Go. When provided, skips the interactive key prompt.
  Essential for LLM-driven / non-interactive setup.

.PARAMETER SkipReasonixInstall
  Skip npm install step (useful if already installed).

.PARAMETER SkipKeyPrompt
  Skip API key prompt (use when key is already in credentials).
  Ignored when -OpenCodeApiKey is also provided.

.PARAMETER SkillStorePath
  Where to clone/find the skill store. Default: "$env:USERPROFILE\agent-skills".

.PARAMETER NoVerify
  Skip final smoke test.

.PARAMETER GitCloneUrl
  Skill store Git URL. Default: https://github.com/kalkin7/agent-skills.git

.EXAMPLE
  # Normal one-click setup (interactive)
  .\bootstrap-all.ps1

.EXAMPLE
  # LLM-driven setup (non-interactive, all prompts skipped)
  .\bootstrap-all.ps1 -OpenCodeApiKey "sk-xxxx"

.EXAMPLE
  # Re-run safely (already installed, just update config + skills)
  .\bootstrap-all.ps1 -SkipReasonixInstall

.EXAMPLE
  # Remote one-liner (run from any machine):
  irm https://raw.githubusercontent.com/kalkin7/reasonix-opencode-bootstrap/main/scripts/bootstrap-all.ps1 | iex
#>

param(
  [string] $OpenCodeApiKey = "",
  [switch] $SkipReasonixInstall,
  [switch] $SkipKeyPrompt,
  [string] $SkillStorePath = "",
  [switch] $NoVerify,
  [string] $GitCloneUrl = "https://github.com/kalkin7/agent-skills.git"
)

$ErrorActionPreference = "Stop"

# === Bypass execution policy for this process (safe, only affects this run) ===
$prevPolicy = Get-ExecutionPolicy -Scope Process
if ($prevPolicy -eq "Restricted" -or $prevPolicy -eq "AllSigned" -or $prevPolicy -eq "RemoteSigned") {
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
  Write-Host "  Execution policy bypassed for this process (was: $prevPolicy)" -ForegroundColor Gray
}

# === PATH refresh helper (needed after npm install -g) ===
function Update-EnvironmentPath {
  # Reload PATH from registry so newly installed npm globals are found
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($machinePath) { $env:Path = $machinePath + ';' + $env:Path }
  if ($userPath) { $env:Path = $userPath + ';' + $env:Path }
}

# Colors
function Title($msg)   { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Step($msg)    { Write-Host "  $msg" -ForegroundColor White }
function OK($msg)      { Write-Host "  $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "  $msg" -ForegroundColor Yellow }
function Err($msg)     { Write-Host "  $msg" -ForegroundColor Red }

# Script Root
$ScriptRoot = Split-Path -Parent $PSCommandPath

# ============================================================================
# 1. PREREQUISITES
# ============================================================================

Write-Host "=== Reasonix + OpenCode Go + Skills Setup ===" -ForegroundColor Magenta

Title "1/7 - Checking prerequisites"

$pwshMajor = $PSVersionTable.PSVersion.Major
if ($pwshMajor -lt 7) {
  Err "PowerShell 7+ required. Current: $($PSVersionTable.PSVersion)"
  Err "Install: winget install Microsoft.PowerShell"
  exit 1
}
OK "PowerShell $($PSVersionTable.PSVersion)"

$nodeVersion = node --version 2>$null
if (-not $nodeVersion) {
  Err "Node.js not found. Node.js 18+ required."
  Err "Install: winget install OpenJS.NodeJS.LTS or https://nodejs.org"
  exit 1
}
OK "Node.js $nodeVersion"

$gitVersion = git --version 2>$null
if (-not $gitVersion) {
  Err "git not found. Git is required for skill store."
  Err "Install: winget install Git.Git or https://git-scm.com"
  exit 1
}
OK $gitVersion

# ============================================================================
# 2. INSTALL REASONIX GO
# ============================================================================

Title "2/7 - Installing Reasonix Go"

if (-not $SkipReasonixInstall) {
  Step "npm install -g reasonix@next"
  npm install -g reasonix@next
  if ($LASTEXITCODE -ne 0) {
    Warn "npm install exit code: $LASTEXITCODE (may be ok)"
  }
  # Refresh PATH so newly installed reasonix is found
  Update-EnvironmentPath
}

$rxVersion = reasonix --version 2>$null
if (-not $rxVersion) {
  Err "reasonix command not found. Install failed."
  exit 1
}
OK "Reasonix: $rxVersion"

# ============================================================================
# 3. OPENCODE GO PROVIDER + API KEY
# ============================================================================

Title "3/7 - OpenCode Go Provider setup"

$setupScript = Join-Path $ScriptRoot "setup-opencode-go.ps1"
if (Test-Path $setupScript) {
  Step "Running setup-opencode-go.ps1 ..."
  $keyArgs = @()
  if ($SkipKeyPrompt) { $keyArgs += "-SkipKeyPrompt" }
  if ($OpenCodeApiKey) { $keyArgs += "-OpenCodeApiKey"; $keyArgs += $OpenCodeApiKey }
  & $setupScript @keyArgs
  if ($LASTEXITCODE -ne 0) {
    Err "setup-opencode-go.ps1 failed (exit: $LASTEXITCODE)"
    exit 1
  }
  OK "OpenCode Go Provider configured"
} else {
  # Fallback for irm|iex remote execution (no companion script on disk)
  Warn "setup-opencode-go.ps1 not found at: $setupScript"
  Step "Using inline fallback for OpenCode Go provider setup..."

  $CredentialsDir  = Join-Path $env:APPDATA "reasonix"
  $CredentialsPath = Join-Path $CredentialsDir "credentials"
  $ConfigPath      = Join-Path $CredentialsDir "config.toml"
  New-Item -ItemType Directory -Force -Path $CredentialsDir | Out-Null

  # Save API key
  if ($OpenCodeApiKey) {
    $keyLine = "OPENCODE_GO_API_KEY=$OpenCodeApiKey"
    Set-Content -LiteralPath $CredentialsPath -Value @($keyLine) -Encoding UTF8
    OK "API key saved to $CredentialsPath"
  } elseif (-not $SkipKeyPrompt) {
    Err "No API key provided. Use -OpenCodeApiKey or run interactively from a cloned repo."
    exit 1
  }

  # Write provider config
  $providerConfig = @"
default_model = "opencode-go-deepseek"

[[providers]]
name = "opencode-go-deepseek"
kind = "openai"
base_url = "https://opencode.ai/zen/go/v1"
models = ["deepseek-v4-flash", "deepseek-v4-pro"]
default = "deepseek-v4-flash"
api_key_env = "OPENCODE_GO_API_KEY"
context_window = 1000000
reasoning_protocol = "none"
price = { cache_hit = 0.0028, input = 0.14, output = 0.28, currency = "$" }
"@
  Set-Content -LiteralPath $ConfigPath -Value $providerConfig -Encoding UTF8
  OK "Provider config written to $ConfigPath"
}

# ============================================================================
# 4. SKILL STORE CLONE / UPDATE
# ============================================================================

Title "4/7 - Preparing Skill Store"

if (-not $SkillStorePath) {
  $SkillStorePath = Join-Path $env:USERPROFILE "agent-skills"
}

if (Test-Path (Join-Path $SkillStorePath ".git")) {
  Step "Skill store already exists: $SkillStorePath"
  Push-Location $SkillStorePath
  try {
    Step "git pull --rebase origin main"
    git pull --rebase origin main 2>&1 | Out-Null
    OK "Skill store updated"
  } catch {
    Warn "git pull failed: $_"
  } finally {
    Pop-Location
  }
} else {
  Step "Cloning skill store..."
  Step "Target: $SkillStorePath"
  git clone $GitCloneUrl $SkillStorePath 2>&1
  if ($LASTEXITCODE -ne 0) {
    Err "git clone failed"
    Err "Clone manually: git clone $GitCloneUrl `"$SkillStorePath`""
    exit 1
  }
  OK "Skill store cloned"
}

$setupSkillsScript = Join-Path $SkillStorePath "setup_skills.ps1"
if (-not (Test-Path $setupSkillsScript)) {
  Err "setup_skills.ps1 not found: $setupSkillsScript"
  exit 1
}

# ============================================================================
# 5. SETUP_SKILLS BOOTSTRAP
# ============================================================================

Title "5/7 - Skill Store Bootstrap"

Step "Running setup_skills.ps1 Bootstrap ..."
Push-Location $SkillStorePath
try {
  & $setupSkillsScript Bootstrap
  if ($LASTEXITCODE -ne 0) {
    Warn "Bootstrap exit code: $LASTEXITCODE"
  }
  OK "Bootstrap complete"
} catch {
  Warn "Bootstrap error: $_"
} finally {
  Pop-Location
}

# ============================================================================
# 6. SETUP_SKILLS VERIFY
# ============================================================================

Title "6/7 - Skill Store Verification"

Push-Location $SkillStorePath
try {
  & $setupSkillsScript Verify
  if ($LASTEXITCODE -ne 0) {
    Warn "Verify had warnings (may be ok)"
  }
  OK "Verify complete"
} catch {
  Warn "Verify error: $_"
} finally {
  Pop-Location
}

# ============================================================================
# 7. SMOKE TEST
# ============================================================================

if (-not $NoVerify) {
  Title "7/7 - Final Smoke Test"

  Step "reasonix --version"
  $ver = reasonix --version 2>&1
  OK $ver

  Step "reasonix run 'hello' (OpenCode Go API call)..."
  Write-Host "  (up to 30s)" -ForegroundColor Gray
  $result = reasonix run "Reply with exactly: OK" 2>&1
  if ($LASTEXITCODE -eq 0) {
    OK "Reasonix + OpenCode Go working correctly"
    Write-Host "    Response: $($result -join ' ')" -ForegroundColor Gray
  } else {
    Warn "reasonix run exit code: $LASTEXITCODE"
    Warn "Output: $($result -join ' ')"
    Warn "Check API key and network."
  }
} else {
  Title "7/7 - Smoke test skipped (-NoVerify)"
}

# ============================================================================
# DONE
# ============================================================================

Write-Host ""
Write-Host "=== ALL DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "  reasonix code" -ForegroundColor Cyan
Write-Host "  reasonix run 'hello'" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tips:" -ForegroundColor Yellow
Write-Host "  Switch model: /model opencode-go-deepseek/deepseek-v4-pro" -ForegroundColor Gray
Write-Host "  Re-bootstrap: $setupSkillsScript Bootstrap" -ForegroundColor Gray