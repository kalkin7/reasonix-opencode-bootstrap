<#
.DEPRECATED Use setup-opencode-go.ps1 instead.
This script only saves the API key. For a complete setup (key + provider
config + default model), run:

  .\scripts\setup-opencode-go.ps1
#>
$ErrorActionPreference = "Stop"

Write-Host "=== DEPRECATED: use setup-opencode-go.ps1 instead ==="
Write-Host "This script only saves the key. setup-opencode-go.ps1 also adds the provider config."
Write-Host ""

Write-Host "Reasonix OpenCode Go Key Setup"
Write-Host "==============================="
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

  $credentialsDir = Join-Path $env:APPDATA "reasonix"
  $credentialsPath = Join-Path $credentialsDir "credentials"

  New-Item -ItemType Directory -Force -Path $credentialsDir | Out-Null

  $line = "OPENCODE_GO_API_KEY=$plainKey"

  if (Test-Path -LiteralPath $credentialsPath) {
    $existing = Get-Content -LiteralPath $credentialsPath
    $updated = $false

    $next = foreach ($l in $existing) {
      if ($l -match '^\s*OPENCODE_GO_API_KEY\s*=') {
        $updated = $true
        $line
      } else {
        $l
      }
    }

    if (-not $updated) {
      $next += $line
    }

    Set-Content -LiteralPath $credentialsPath -Value $next -Encoding UTF8
  } else {
    Set-Content -LiteralPath $credentialsPath -Value @($line) -Encoding UTF8
  }

  Write-Host ""
  Write-Host "OpenCode Go API key saved to: $credentialsPath"
  Write-Host ""
  Write-Host "You can now run Reasonix normally:"
  Write-Host "  reasonix code"
  Write-Host "  reasonix run ""hello"""
}
finally {
  if ($bstr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
  $plainKey = $null
}
