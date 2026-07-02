# ============================================================================
#  CustomSetup.ps1  --  Tim's post-debloat setup prompts
#
#  Fork addition to Raphire/Win11Debloat. Runs after the base debloat completes
#  and interactively prompts the user for four extra setup steps:
#
#    1. Static IPv4 configuration (IP, subnet mask, gateway, DNS) with option
#       to preserve the existing config (skip).
#    2. Enable / disable Remote Desktop (RDP).
#    3. Suppress toast / pop-up notifications in Outlook (new + classic),
#       Microsoft Edge, Brave and Google Chrome.
#    4. Set the desktop background to solid black.
#
#  Each step is independent and wrapped in try/catch so one failure does not
#  abort the whole flow. Call `Invoke-CustomSetup` from Win11Debloat.ps1.
# ============================================================================

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [ValidateSet('Y','N')][string]$Default = 'N'
    )
    $suffix = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        switch -Regex ($answer.Trim().ToLower()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host "  Please answer Y or N." -ForegroundColor Yellow }
        }
    }
}

function Read-WithDefault {
    param(
        [string]$Prompt,
        [string]$Default,
        [scriptblock]$Validator = { param($v) $true }
    )
    while ($true) {
        $shown = if ($Default) { " [$Default]" } else { "" }
        $answer = Read-Host "$Prompt$shown"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        if (& $Validator $answer) { return $answer }
        Write-Host "  Invalid value, try again." -ForegroundColor Yellow
    }
}

function Test-IPv4 {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    [System.Net.IPAddress]::TryParse($Value, [ref]([System.Net.IPAddress]::Any)) -and
        ($Value -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
}

function Convert-MaskToPrefix {
    param([string]$Mask)
    try {
        $bytes = ([System.Net.IPAddress]::Parse($Mask)).GetAddressBytes()
        $bits = ($bytes | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
        return ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    catch { return $null }
}

# ---------------------------------------------------------------------------
# 1. Static IP configuration
# ---------------------------------------------------------------------------
function Set-CustomStaticIP {
    Write-Section "Static IP configuration"

    try {
        $adapters = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' |
            Sort-Object -Property ifIndex
    }
    catch {
        Write-Warning "Unable to enumerate network adapters: $_"
        return
    }

    if (-not $adapters) {
        Write-Host "No active network adapters found. Skipping." -ForegroundColor Yellow
        return
    }

    Write-Host "Active network adapters:"
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $a = $adapters[$i]
        $cur = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $curIp = if ($cur) { "$($cur.IPAddress)/$($cur.PrefixLength)" } else { 'no IPv4' }
        Write-Host ("  [{0}] {1}  ({2})  current: {3}" -f ($i + 1), $a.Name, $a.InterfaceDescription, $curIp)
    }

    $choice = Read-WithDefault -Prompt "Select adapter number (or 'S' to skip)" -Default '1'
    if ($choice -match '^(s|skip)$') {
        Write-Host "Skipping static IP configuration; existing network config preserved." -ForegroundColor Green
        return
    }
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $adapters.Count) {
        Write-Warning "Invalid selection. Skipping static IP configuration."
        return
    }
    $adapter = $adapters[$idx - 1]

    # Pull current settings as defaults
    $curIp = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $curGw = (Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Select-Object -First 1).NextHop
    $curDns = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ','

    $defaultMask = if ($curIp) {
        $bits = ('1' * $curIp.PrefixLength).PadRight(32, '0')
        (0..3 | ForEach-Object { [Convert]::ToInt32($bits.Substring($_ * 8, 8), 2) }) -join '.'
    } else { '255.255.255.0' }

    Write-Host ""
    Write-Host "Press Enter at any prompt to keep the shown [default]. Type 'skip' at the IP prompt to cancel." -ForegroundColor DarkGray

    $ip = Read-WithDefault -Prompt "IPv4 address" -Default $curIp.IPAddress -Validator {
        param($v) $v -match '^(s|skip)$' -or (Test-IPv4 $v)
    }
    if ($ip -match '^(s|skip)$') {
        Write-Host "Skipping static IP configuration; existing network config preserved." -ForegroundColor Green
        return
    }

    $mask = Read-WithDefault -Prompt "Subnet mask" -Default $defaultMask -Validator { param($v) Test-IPv4 $v }
    $prefix = Convert-MaskToPrefix $mask
    if (-not $prefix) {
        Write-Warning "Could not convert subnet mask to prefix length. Aborting IP config."
        return
    }

    $gw = Read-WithDefault -Prompt "Default gateway" -Default $curGw -Validator {
        param($v) [string]::IsNullOrWhiteSpace($v) -or (Test-IPv4 $v)
    }

    $dns = Read-WithDefault -Prompt "DNS servers (comma-separated)" -Default $curDns -Validator {
        param($v)
        if ([string]::IsNullOrWhiteSpace($v)) { return $true }
        ($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { Test-IPv4 $_ }) -notcontains $false
    }

    Write-Host ""
    Write-Host "About to apply:" -ForegroundColor Yellow
    Write-Host "  Adapter : $($adapter.Name)"
    Write-Host "  IP      : $ip/$prefix ($mask)"
    Write-Host "  Gateway : $gw"
    Write-Host "  DNS     : $dns"
    if (-not (Read-YesNo -Prompt "Apply these settings?" -Default 'Y')) {
        Write-Host "Aborted static IP configuration." -ForegroundColor Yellow
        return
    }

    try {
        # Clear existing IPv4 config so New-NetIPAddress won't collide
        Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        $params = @{
            InterfaceIndex = $adapter.ifIndex
            IPAddress      = $ip
            PrefixLength   = $prefix
            AddressFamily  = 'IPv4'
            ErrorAction    = 'Stop'
        }
        if ($gw) { $params.DefaultGateway = $gw }
        New-NetIPAddress @params | Out-Null

        if ($dns) {
            $dnsList = $dns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsList -ErrorAction Stop
        }

        Write-Host "Static IP applied successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to apply static IP: $_"
    }
}

# ---------------------------------------------------------------------------
# 2. Enable / disable RDP
# ---------------------------------------------------------------------------
function Set-CustomRDP {
    Write-Section "Remote Desktop (RDP)"

    $curDeny = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
    $curState = if ($curDeny -eq 0) { 'ENABLED' } else { 'DISABLED' }
    Write-Host "RDP is currently: $curState"

    $enable = Read-YesNo -Prompt "Enable Remote Desktop?" -Default $(if ($curDeny -eq 0) { 'Y' } else { 'N' })

    try {
        if ($enable) {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                -Name 'UserAuthentication' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
            Write-Host "RDP enabled and firewall rule opened." -ForegroundColor Green
        }
        else {
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                -Name 'fDenyTSConnections' -Value 1 -Type DWord -Force
            Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
            Write-Host "RDP disabled and firewall rule closed." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to change RDP state: $_"
    }
}

# ---------------------------------------------------------------------------
# 3. Suppress notifications in Outlook (new + classic), Edge, Brave, Chrome
# ---------------------------------------------------------------------------
function Disable-CustomNotifications {
    Write-Section "Suppress toast / pop-up notifications"

    if (-not (Read-YesNo -Prompt "Disable notifications for Outlook (new+classic), Edge, Brave, Chrome?" -Default 'Y')) {
        Write-Host "Skipped notification suppression." -ForegroundColor Yellow
        return
    }

    # --- Windows toast: per-app entries under Notifications\Settings\<AppID> ---
    $notifRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    $appIds = @(
        # Outlook (new)
        'Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows'
        # Outlook (classic) — the classic app registers under its executable name
        'Microsoft.Office.OUTLOOK.EXE.15'
        'Microsoft.Office.OUTLOOK.EXE.16'
        # Microsoft Edge (stable + beta + dev)
        'Microsoft.MicrosoftEdge.Stable'
        'Microsoft.MicrosoftEdge_8wekyb3d8bbwe!MicrosoftEdge'
    )
    try {
        if (-not (Test-Path $notifRoot)) { New-Item -Path $notifRoot -Force | Out-Null }
        foreach ($appId in $appIds) {
            $key = Join-Path $notifRoot $appId
            if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
            Set-ItemProperty -Path $key -Name 'Enabled' -Value 0 -Type DWord -Force
        }
        Write-Host "Toast notifications disabled for Outlook (new+classic) and Edge." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to write per-app toast keys: $_"
    }

    # --- Chromium browsers: block web notifications via policy ---
    # DefaultNotificationsSetting: 1 = allow, 2 = block, 3 = ask
    $browserPolicies = @(
        @{ Name = 'Microsoft Edge'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' }
        @{ Name = 'Google Chrome';  Path = 'HKLM:\SOFTWARE\Policies\Google\Chrome'  }
        @{ Name = 'Brave';          Path = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' }
    )
    foreach ($b in $browserPolicies) {
        try {
            if (-not (Test-Path $b.Path)) { New-Item -Path $b.Path -Force | Out-Null }
            Set-ItemProperty -Path $b.Path -Name 'DefaultNotificationsSetting' -Value 2 -Type DWord -Force
            Write-Host "Blocked web notifications in $($b.Name)." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to set notification policy for $($b.Name): $_"
        }
    }

    # --- Outlook classic: turn off Desktop Alert and new-mail sound ---
    foreach ($ver in @('16.0', '15.0')) {
        $outlookKey = "HKCU:\Software\Microsoft\Office\$ver\Outlook\Preferences"
        try {
            if (Test-Path "HKCU:\Software\Microsoft\Office\$ver\Outlook") {
                if (-not (Test-Path $outlookKey)) { New-Item -Path $outlookKey -Force | Out-Null }
                Set-ItemProperty -Path $outlookKey -Name 'NewmailDesktopAlerts' -Value 0 -Type DWord -Force
                Set-ItemProperty -Path $outlookKey -Name 'PlaySound'            -Value 0 -Type DWord -Force
                Write-Host "Disabled Outlook $ver desktop alerts + new-mail sound." -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Failed to update Outlook $ver preferences: $_"
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Solid black desktop background
# ---------------------------------------------------------------------------
function Set-CustomBlackDesktop {
    Write-Section "Black desktop background"

    if (-not (Read-YesNo -Prompt "Set desktop background to solid black?" -Default 'Y')) {
        Write-Host "Skipped desktop background change." -ForegroundColor Yellow
        return
    }

    try {
        # Solid colour = "0 0 0" (space-separated RGB), no wallpaper image
        Set-ItemProperty -Path 'HKCU:\Control Panel\Colors'  -Name 'Background'     -Value '0 0 0' -Force
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper'      -Value ''      -Force
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '0'     -Force
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper'  -Value '0'     -Force

        # Apply immediately without logoff via SystemParametersInfo
        if (-not ('Win32.SPI' -as [Type])) {
            Add-Type -Namespace Win32 -Name SPI -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Auto, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
        }
        # SPI_SETDESKWALLPAPER = 20; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 0x03
        [Win32.SPI]::SystemParametersInfo(20, 0, '', 3) | Out-Null

        # Force the solid-colour COLOR_BACKGROUND (index 1) to black
        if (-not ('Win32.SysColors' -as [Type])) {
            Add-Type -Namespace Win32 -Name SysColors -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetSysColors(int cElements, int[] lpaElements, int[] lpaRgbValues);
'@
        }
        [Win32.SysColors]::SetSysColors(1, @(1), @(0)) | Out-Null

        Write-Host "Desktop background set to solid black." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to set black desktop: $_"
    }
}

# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------
function Invoke-CustomSetup {
    Write-Host ""
    Write-Host ""
    Write-Host ("#" * 70) -ForegroundColor Magenta
    Write-Host "#  Custom post-debloat setup (Tim's fork additions)" -ForegroundColor Magenta
    Write-Host ("#" * 70) -ForegroundColor Magenta

    if (-not (Read-YesNo -Prompt "Run the extra setup prompts (static IP / RDP / notifications / desktop)?" -Default 'Y')) {
        Write-Host "Skipping custom setup." -ForegroundColor Yellow
        return
    }

    Set-CustomStaticIP
    Set-CustomRDP
    Disable-CustomNotifications
    Set-CustomBlackDesktop

    Write-Host ""
    Write-Host "Custom setup complete." -ForegroundColor Magenta
}
