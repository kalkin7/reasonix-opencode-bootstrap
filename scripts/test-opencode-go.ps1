<#
.SYNOPSIS
  Reasonix + OpenCode Go compatibility tester.
  Verifies basic connectivity and reasoning_protocol/effort field compatibility.

.DESCRIPTION
  Tests whether OpenCode Go accepts DeepSeek's reasoning_protocol and effort
  fields. Runs real API calls through reasonix run in three phases:

  Phase 1 (always):    SMOKE-01 — basic OpenCode Go connectivity
  Phase 2 (unless -SkipDeepseek):  EXP-01 — reasoning_protocol = "deepseek" only
  Phase 3 (unless -SkipDeepseek):  EXP-02 — deepseek + effort = "high"
  Config is backed up before each modification and restored afterwards.

.PARAMETER SkipDeepseek
  Skip EXP-01 (deepseek protocol only) and EXP-02 (deepseek + effort).

.PARAMETER ReportPath
  Path to save the Markdown report. Default: ./reports/opencode-go-test-<timestamp>.md

.PARAMETER TimeoutSeconds
  Per-test timeout in seconds. Default: 120

.EXAMPLE
  .\scripts\test-opencode-go.ps1
  .\scripts\test-opencode-go.ps1 -SkipDeepseek
#>

param(
  [switch] $SkipDeepseek,
  [string] $ReportPath,
  [int]    $TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

$ProviderName     = "opencode-go-deepseek"
$CredentialsDir   = Join-Path $env:APPDATA "reasonix"
$CredentialsPath  = Join-Path $CredentialsDir "credentials"
$ConfigPath       = Join-Path $CredentialsDir "config.toml"

# Default report path
if (-not $ReportPath) {
  $ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
  $ReportDir   = Join-Path $ProjectRoot "reports"
  $null = New-Item -ItemType Directory -Force -Path $ReportDir
  $ts   = Get-Date -Format "yyyyMMdd-HHmmss"
  $ReportPath = Join-Path $ReportDir "opencode-go-test-$ts.md"
}

$tests = [System.Collections.Generic.List[object]]::new()

# =============================================================================
# HELPERS
# =============================================================================

function Remove-Ansi {
  param([string]$Text)
  $esc = [char]27
  return $Text -replace "$esc\[[0-9;]*[a-zA-Z]", '' -replace "$esc\][0-9;]*[a-zA-Z]", ''
}

function Log-Result {
  param([string]$Id, [string]$Category, [string]$Description, [string]$Status, [string]$Detail)
  $tests.Add(@{ Id = $Id; Category = $Category; Description = $Description; Status = $Status; Detail = $Detail })
  $icon = switch ($Status) {
    'PASS' { '✓' }; 'FAIL' { '✗' }; 'SKIP' { '–' }; 'WARN' { '⚠' }; default { '?' }
  }
  $color = switch ($Status) {
    'PASS' { 'Green' }; 'FAIL' { 'Red' }; 'SKIP' { 'DarkGray' }; 'WARN' { 'Yellow' }; default { 'White' }
  }
  Write-Host "  $icon $Id $Description" -ForegroundColor $color
  if ($Detail) { Write-Host "       $Detail" -ForegroundColor $color }
}

function Invoke-ReasonixRun {
  param([string]$Prompt, [int]$TimeoutSec = $TimeoutSeconds)

  $reasonix = (Get-Command reasonix -ErrorAction Stop).Source

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

  $ext = [System.IO.Path]::GetExtension($reasonix).ToLowerInvariant()
  if ($ext -eq '.ps1') {
    $psi.FileName = 'pwsh'
    [void]$psi.ArgumentList.Add('-NoProfile')
    [void]$psi.ArgumentList.Add('-ExecutionPolicy')
    [void]$psi.ArgumentList.Add('Bypass')
    [void]$psi.ArgumentList.Add('-File')
    [void]$psi.ArgumentList.Add($reasonix)
  } elseif ($ext -eq '.cmd' -or $ext -eq '.bat') {
    $psi.FileName = 'cmd.exe'
    [void]$psi.ArgumentList.Add('/d')
    [void]$psi.ArgumentList.Add('/c')
    [void]$psi.ArgumentList.Add($reasonix)
  } else {
    $psi.FileName = $reasonix
  }
  [void]$psi.ArgumentList.Add('run')
  [void]$psi.ArgumentList.Add($Prompt)

  $p = [System.Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()

  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    $p.Kill()
    throw "TIMEOUT after ${TimeoutSec}s"
  }

  $out = $outTask.GetAwaiter().GetResult()
  $err = $errTask.GetAwaiter().GetResult()

  return @{
    ExitCode = $p.ExitCode
    Stdout   = $out
    Stderr   = $err
    Combined = "$out`n$err"
  }
}

# =============================================================================
# BANNER
# =============================================================================
Write-Host @"

╔══════════════════════════════════════════════╗
║  Reasonix + OpenCode Go  Compatibility Test ║
╚══════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# =============================================================================
# PRE-CHECKS
# =============================================================================
Write-Host "── Pre-checks ──────────────────────────────────" -ForegroundColor Magenta

try {
  $reasonixPath = (Get-Command reasonix -ErrorAction Stop).Source
  Log-Result 'PRE-01' 'Pre' 'reasonix executable' 'PASS' "at $reasonixPath"
} catch {
  Log-Result 'PRE-01' 'Pre' 'reasonix executable' 'FAIL' 'not found in PATH'
  Write-Host "`nFATAL: Install: npm install -g reasonix@next" -ForegroundColor Red; exit 1
}

$verRaw = & reasonix --version 2>&1 | Out-String
$verStr = (Remove-Ansi $verRaw).Trim()
if ($verStr -match 'npm-v1|1\.\d') {
  Log-Result 'PRE-02' 'Pre' 'Go version' 'PASS' $verStr
} else {
  Log-Result 'PRE-02' 'Pre' 'Go version' 'FAIL' "Legacy: $verStr"
  Write-Host "`nFATAL: install reasonix@next" -ForegroundColor Red; exit 1
}

if (Test-Path $CredentialsPath) {
  Log-Result 'PRE-03' 'Pre' 'credentials file' 'PASS' ''
} else {
  Log-Result 'PRE-03' 'Pre' 'credentials file' 'FAIL' 'not found'
}

if (Test-Path $CredentialsPath) {
  $hasKey = (Get-Content $CredentialsPath | Where-Object { $_ -match 'OPENCODE_GO_API_KEY=' }).Count -gt 0
  if ($hasKey) { Log-Result 'PRE-04' 'Pre' 'API key' 'PASS' 'OPENCODE_GO_API_KEY set' }
  else         { Log-Result 'PRE-04' 'Pre' 'API key' 'FAIL' 'not in credentials' }
} else {
  Log-Result 'PRE-04' 'Pre' 'API key' 'SKIP' 'credentials missing'
}

if (Test-Path $ConfigPath) {
  Log-Result 'PRE-05' 'Pre' 'config.toml' 'PASS' ''
} else {
  Log-Result 'PRE-05' 'Pre' 'config.toml' 'FAIL' 'not found'
}

$cfgLines = if (Test-Path $ConfigPath) { Get-Content $ConfigPath } else { @() }
$hasProvider = ($cfgLines | Where-Object { $_ -match 'name\s*=\s*"opencode-go-deepseek"' }).Count -gt 0
if ($hasProvider) { Log-Result 'PRE-06' 'Pre' 'provider block' 'PASS' '' }
else              { Log-Result 'PRE-06' 'Pre' 'provider block' 'FAIL' 'not found' }

$baseUrlLine = $cfgLines | Where-Object { $_ -match 'base_url\s*=' } | Select-Object -First 1
$expectedUrl = 'https://opencode.ai/zen/go/v1'
if ($baseUrlLine -and ($baseUrlLine -match [regex]::Escape($expectedUrl))) {
  Log-Result 'PRE-07' 'Pre' 'base_url' 'PASS' $expectedUrl
} elseif ($baseUrlLine) { Log-Result 'PRE-07' 'Pre' 'base_url' 'WARN' "unexpected: $baseUrlLine" }
else                    { Log-Result 'PRE-07' 'Pre' 'base_url' 'FAIL' 'not found' }

$protoLine = $cfgLines | Where-Object { $_ -match 'reasoning_protocol\s*=' } | Select-Object -First 1
if ($protoLine -and $protoLine -match '"(none|deepseek)"') {
  $currentProtocol = $matches[1]
  if ($currentProtocol -eq 'none') { Log-Result 'PRE-08' 'Pre' 'reasoning_protocol' 'PASS' 'none (recommended)' }
  else                             { Log-Result 'PRE-08' 'Pre' 'reasoning_protocol' 'WARN' 'deepseek (experimental)' }
} else {
  $currentProtocol = 'none'
  Log-Result 'PRE-08' 'Pre' 'reasoning_protocol' 'WARN' 'not explicitly set (defaults to none)'
}

# Fatal pre-checks
$fatal = $tests | Where-Object { $_.Id -in 'PRE-01','PRE-02' -and $_.Status -eq 'FAIL' }
if ($fatal) { Write-Host "`nFATAL: fix pre-requisites and retry." -ForegroundColor Red; exit 1 }

# Check whether we can reach the API at all
$configOk = @($tests | Where-Object { $_.Id -in 'PRE-03','PRE-04','PRE-05','PRE-06','PRE-07' -and $_.Status -eq 'PASS' }).Count
if ($configOk -lt 4) {
  Log-Result 'PRE-WARN' 'Pre' 'config completeness' 'WARN' 'some config checks failed — API tests may also fail'
}

# =============================================================================
# SMOKE-01: basic OpenCode Go connectivity
# =============================================================================
Write-Host "`n── Smoke Test ───────────────────────────────────" -ForegroundColor Magenta

try {
  $r = Invoke-ReasonixRun -Prompt '안녕?'
  $combined = Remove-Ansi $r.Combined

  $smokeFail = if ($combined -match '401|403')                         { 'Auth error (check API key)' }
               elseif ($combined -match '402|Out of balance|platform\.deepseek') { 'DeepSeek billing error' }
               elseif ($combined -match '400|Bad Request')              { 'Bad request' }
               elseif ($r.ExitCode -ne 0)                               { "Exit $($r.ExitCode)" }
               elseif ([string]::IsNullOrWhiteSpace($combined))         { 'Empty response' }
               else { $null }

  if ($smokeFail) {
    Log-Result 'SMOKE-01' 'Smoke' 'basic OpenCode Go call' 'FAIL' $smokeFail
    $basicOk = $false
  } else {
    Log-Result 'SMOKE-01' 'Smoke' 'basic OpenCode Go call' 'PASS' 'connected, response received'
    $basicOk = $true
  }
} catch {
  Log-Result 'SMOKE-01' 'Smoke' 'basic OpenCode Go call' 'FAIL' $_.Exception.Message
  $basicOk = $false
}

# =============================================================================
# DEEPSEEK PROTOCOL TESTS (optional)
# =============================================================================
if ($SkipDeepseek) {
  Write-Host "`n── Deepseek Protocol Tests ─────────────────────" -ForegroundColor Magenta
  Log-Result 'EXP-01' 'Exp' 'deepseek protocol only' 'SKIP' 'use -SkipDeepseek to skip'
  Log-Result 'EXP-02' 'Exp' 'deepseek + effort high'  'SKIP' 'use -SkipDeepseek to skip'
  $exp01Pass = $null
  $exp02Pass = $null
} else {
  Write-Host "`n── Deepseek Protocol Tests ─────────────────────" -ForegroundColor Magenta

  if (-not $basicOk) {
    Log-Result 'EXP-01' 'Exp' 'deepseek protocol only' 'SKIP' 'SMOKE-01 failed, cannot proceed'
    Log-Result 'EXP-02' 'Exp' 'deepseek + effort high'  'SKIP' 'SMOKE-01 failed, cannot proceed'
    $exp01Pass = $null
    $exp02Pass = $null
  } else {
    $prompt = '간단히 답해줘. 2+2는?'

    # -------------------------------------------------------------------------
    # EXP-01: reasoning_protocol = "deepseek"  (no effort)
    # -------------------------------------------------------------------------
    $backup01 = "$ConfigPath.test-exp01-bak"
    try {
      if (-not (Test-Path $ConfigPath)) { throw 'config.toml not found' }
      Copy-Item $ConfigPath $backup01 -Force

      $lines = Get-Content $ConfigPath
      $newLines = [System.Collections.Generic.List[string]]::new()
      $found = $false
      foreach ($line in $lines) {
        if ($line -match '^\s*reasoning_protocol\s*=') {
          $newLines.Add('reasoning_protocol = "deepseek"')
          $found = $true
        } elseif ($line -match '^\s*effort\s*=') {
          # Remove effort line to test pure protocol without effort
          continue
        } else {
          $newLines.Add($line)
        }
      }
      if (-not $found) { $newLines.Add('reasoning_protocol = "deepseek"') }
      Set-Content $ConfigPath -Value $newLines.ToArray() -Encoding UTF8
      Write-Host "   Config: reasoning_protocol => ""deepseek"", effort removed" -ForegroundColor DarkGray

      $r = Invoke-ReasonixRun -Prompt $prompt
      $combined = Remove-Ansi $r.Combined

      $has400 = $combined -match '400|Bad Request'
      if ($has400) {
        Log-Result 'EXP-01' 'Exp' 'deepseek protocol only' 'FAIL' '400 Bad Request — OpenCode Go rejects deepseek protocol'
        $exp01Pass = $false
      } elseif ($r.ExitCode -ne 0) {
        Log-Result 'EXP-01' 'Exp' 'deepseek protocol only' 'FAIL' "Exit $($r.ExitCode)"
        $exp01Pass = $false
      } else {
        Log-Result 'EXP-01' 'Exp' 'deepseek protocol only' 'PASS' 'deepseek protocol accepted'
        $exp01Pass = $true
      }
    } catch {
      Log-Result 'EXP-01' 'Exp' 'deepseek protocol only' 'FAIL' $_.Exception.Message
      $exp01Pass = $false
    } finally {
      if (Test-Path $backup01) {
        Copy-Item $backup01 $ConfigPath -Force; Remove-Item $backup01 -Force
        Write-Host "   Config restored (POST-EXP01)" -ForegroundColor DarkGray
      }
    }

    # -------------------------------------------------------------------------
    # EXP-02: reasoning_protocol = "deepseek"  +  effort = "high"
    # -------------------------------------------------------------------------
    if ($exp01Pass -eq $false) {
      Log-Result 'EXP-02' 'Exp' 'deepseek + effort high' 'SKIP' 'EXP-01 failed, cannot test effort compatibility'
      $exp02Pass = $null
    } else {
      $backup02 = "$ConfigPath.test-exp02-bak"
      try {
        if (-not (Test-Path $ConfigPath)) { throw 'config.toml not found' }
        Copy-Item $ConfigPath $backup02 -Force

        $lines = Get-Content $ConfigPath
        $newLines = [System.Collections.Generic.List[string]]::new()
        $found = $false
        $effortAdded = $false
        foreach ($line in $lines) {
          if ($line -match '^\s*reasoning_protocol\s*=') {
            $newLines.Add('reasoning_protocol = "deepseek"')
            $newLines.Add('effort = "high"')
            $found = $true
            $effortAdded = $true
          } elseif ($line -match '^\s*effort\s*=') {
            # Replace existing effort line instead of keeping it
            if (-not $effortAdded) {
              $newLines.Add('effort = "high"')
              $effortAdded = $true
            }
            # If effort already added above, skip this line
          } else {
            $newLines.Add($line)
          }
        }
        if (-not $found) {
          $newLines.Add('reasoning_protocol = "deepseek"')
          $newLines.Add('effort = "high"')
        } elseif (-not $effortAdded) {
          $newLines.Add('effort = "high"')
        }
        Set-Content $ConfigPath -Value $newLines.ToArray() -Encoding UTF8
        Write-Host "   Config: reasoning_protocol => ""deepseek"", effort => ""high""" -ForegroundColor DarkGray

        $r = Invoke-ReasonixRun -Prompt $prompt
        $combined = Remove-Ansi $r.Combined

        $has400 = $combined -match '400|Bad Request'
        if ($has400) {
          Log-Result 'EXP-02' 'Exp' 'deepseek + effort high' 'FAIL' '400 Bad Request — effort field not accepted'
          $exp02Pass = $false
        } elseif ($r.ExitCode -ne 0) {
          Log-Result 'EXP-02' 'Exp' 'deepseek + effort high' 'FAIL' "Exit $($r.ExitCode)"
          $exp02Pass = $false
        } else {
          Log-Result 'EXP-02' 'Exp' 'deepseek + effort high' 'PASS' 'deepseek + effort accepted'
          $exp02Pass = $true
        }
      } catch {
        Log-Result 'EXP-02' 'Exp' 'deepseek + effort high' 'FAIL' $_.Exception.Message
        $exp02Pass = $false
      } finally {
        if (Test-Path $backup02) {
          Copy-Item $backup02 $ConfigPath -Force; Remove-Item $backup02 -Force
          Write-Host "   Config restored (POST-EXP02)" -ForegroundColor DarkGray
        }
      }
    }
  }
}

# =============================================================================
# SUMMARY & RECOMMENDATION
# =============================================================================
Write-Host "`n── Summary ──────────────────────────────────────" -ForegroundColor Magenta

$passed   = @($tests | Where-Object { $_.Status -eq 'PASS' }).Count
$failed   = @($tests | Where-Object { $_.Status -eq 'FAIL' }).Count
$skipped  = @($tests | Where-Object { $_.Status -eq 'SKIP' }).Count
$warnings = @($tests | Where-Object { $_.Status -eq 'WARN' }).Count

Write-Host "  ✓ Passed : $passed" -ForegroundColor Green
Write-Host "  ✗ Failed : $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  ⚠ Warn   : $warnings" -ForegroundColor $(if ($warnings -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  – Skipped: $skipped" -ForegroundColor DarkGray

# Recommendation
if ($basicOk -eq $false) {
  $rec = 'SMOKE-01 failed. Check config, API key, and provider settings.'
} elseif ($SkipDeepseek) {
  $rec = 'reasoning_protocol = "none" is working. Deepseek tests were skipped (-SkipDeepseek).'
} elseif ($exp01Pass -eq $false) {
  $rec = 'reasoning_protocol = "none" required — OpenCode Go rejects deepseek schema (400 Bad Request).'
} elseif ($exp02Pass -eq $false) {
  $rec = 'reasoning_protocol = "deepseek" works, but effort = "high" is not accepted. Use deepseek without effort, or keep "none".'
} elseif ($exp02Pass -eq $true) {
  $rec = 'reasoning_protocol = "deepseek" recommended as default. effort = "high" is accepted, but should remain optional — not built into the default config.'
}

Write-Host "`n  Recommendation: $rec" -ForegroundColor Cyan

# =============================================================================
# REPORT
# =============================================================================
$rpt = [System.Collections.Generic.List[string]]::new()
$rpt.Add("# Reasonix & OpenCode Go Compatibility Report")
$rpt.Add("")
$rpt.Add("- **Date**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$rpt.Add("- **Reasonix**: $verStr")
$rpt.Add("- **Protocol**: $currentProtocol")
$rpt.Add("")
$rpt.Add("## Results")
$rpt.Add("")
$rpt.Add("| ID | Category | Test | Status | Detail |")
$rpt.Add("|---|---|---|---|---|")
foreach ($t in $tests) {
  $d = ($t.Detail -replace '\|', '/') -replace "`n", ' '
  $rpt.Add("| $($t.Id) | $($t.Category) | $($t.Description) | $($t.Status) | $d |")
}
$rpt.Add("")
$rpt.Add("## Summary")
$rpt.Add("")
$rpt.Add("- **Passed**: $passed")
$rpt.Add("- **Failed**: $failed")
$rpt.Add("- **Warnings**: $warnings")
$rpt.Add("- **Skipped**: $skipped")
$rpt.Add("")
$rpt.Add("## Recommendation")
$rpt.Add("")
$rpt.Add($rec)

Set-Content $ReportPath -Value $rpt.ToArray() -Encoding UTF8
Write-Host "`n  Report saved: $ReportPath" -ForegroundColor Green
Write-Host ""
