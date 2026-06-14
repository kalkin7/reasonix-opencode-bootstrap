<#
.SYNOPSIS
  Temporary test runner. Key is NOT saved to disk — it lives only in the
  current process environment and is discarded when the script exits.

.DESCRIPTION
  Use this script for one-off testing with a temp key. For daily use, run
  set-opencode-go-key.ps1 ONCE to store the key in Reasonix's global
  credentials file (%APPDATA%\reasonix\credentials), then just run
  `reasonix code` directly — no script needed.
#>
param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]] $ReasonixArgs
)

$secureKey = Read-Host "Enter OpenCode Go API key" -AsSecureString

if ($null -eq $secureKey -or $secureKey.Length -eq 0) {
  Write-Error "OpenCode Go API key is required."
  exit 1
}

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)

try {
  $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

  $env:OPENCODE_GO_API_KEY = $plainKey

  if ($ReasonixArgs.Count -eq 0) {
    & reasonix code
  } else {
    & reasonix @ReasonixArgs
  }

  exit $LASTEXITCODE
}
finally {
  if ($bstr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
  $env:OPENCODE_GO_API_KEY = $null
  $plainKey = $null
}
