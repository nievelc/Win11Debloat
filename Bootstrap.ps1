# ============================================================================
#  Bootstrap.ps1  --  One-line remote launcher for nievelc/Win11Debloat.
#
#  Usage from a fresh machine (PowerShell, elevated recommended):
#
#      & ([scriptblock]::Create((irm "https://raw.githubusercontent.com/nievelc/Win11Debloat/main/Bootstrap.ps1")))
#
#  Downloads this fork's main branch as a zip, extracts it, unblocks the
#  files, then invokes Win11Debloat.ps1 in the same session so any extra
#  args passed to this script flow through.
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThroughArgs
)

$ErrorActionPreference = 'Stop'
$Repo   = 'nievelc/Win11Debloat'
$Branch = 'main'
$Zip    = "$env:TEMP\Win11Debloat-$Branch.zip"
$Root   = "$env:TEMP\Win11Debloat-$Branch"

Write-Host "Downloading $Repo@$Branch..." -ForegroundColor Cyan
if (Test-Path $Root) { Remove-Item -Recurse -Force $Root }
Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $Zip -UseBasicParsing

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $Zip -DestinationPath $Root -Force

# Unblock files (Windows marks internet-downloaded scripts as untrusted)
Get-ChildItem -Path $Root -Recurse -File | Unblock-File

$scriptDir  = Join-Path $Root "Win11Debloat-$Branch"
$scriptPath = Join-Path $scriptDir 'Win11Debloat.ps1'
if (-not (Test-Path $scriptPath)) {
    throw "Win11Debloat.ps1 not found under $scriptDir"
}

# If not elevated, relaunch elevated via a new PowerShell process
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Not elevated - relaunching Win11Debloat.ps1 as Administrator..." -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$scriptPath`"") + $PassThroughArgs
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    return
}

Write-Host "Launching Win11Debloat.ps1..." -ForegroundColor Cyan
& $scriptPath @PassThroughArgs
