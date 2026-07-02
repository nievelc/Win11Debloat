<#
    .SYNOPSIS
        Modal dialog for configuring a static IPv4 address on a network adapter.

    .DESCRIPTION
        Fork addition. Lists active network adapters, pre-fills the current
        IPv4 address / subnet mask / gateway / DNS of the selected adapter,
        validates input and applies the configuration via the NetTCPIP cmdlets.
        Nothing is changed unless the user clicks Apply. Styled to match the
        other Win11Debloat modals (About, Restore backup).
#>

function Test-IPv4String {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    return [System.Net.IPAddress]::TryParse($Value, [ref]([System.Net.IPAddress]::Any))
}

function Convert-SubnetMaskToPrefixLength {
    param([string]$Mask)
    try {
        $bytes = ([System.Net.IPAddress]::Parse($Mask)).GetAddressBytes()
        $bits = ($bytes | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
        # A valid mask is contiguous 1s followed by contiguous 0s
        if ($bits -notmatch '^1*0*$') { return $null }
        return ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    catch { return $null }
}

function Convert-PrefixLengthToSubnetMask {
    param([int]$PrefixLength)
    $bits = ('1' * $PrefixLength).PadRight(32, '0')
    return (0..3 | ForEach-Object { [Convert]::ToInt32($bits.Substring($_ * 8, 8), 2) }) -join '.'
}

function Show-StaticIPDialog {
    param (
        [Parameter(Mandatory=$false)]
        [System.Windows.Window]$Owner = $null
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase | Out-Null

    $usesDarkMode = GetSystemUsesDarkMode
    $ownerWindow = if ($Owner) { $Owner } else { $script:GuiWindow }

    # Show overlay if owner window exists
    $overlay = $null
    if ($ownerWindow) {
        try {
            $overlay = $ownerWindow.FindName('ModalOverlay')
            if ($overlay) {
                $ownerWindow.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Visible' })
            }
        }
        catch { }
    }

    # Load XAML from file
    $xaml = Get-Content -Path $script:StaticIPWindowSchema -Raw
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    try {
        $ipWindow = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }

    if ($ownerWindow) {
        try { $ipWindow.Owner = $ownerWindow } catch { }
    }

    SetWindowThemeResources -window $ipWindow -usesDarkMode $usesDarkMode

    # Get UI elements
    $titleBar     = $ipWindow.FindName('TitleBar')
    $adapterCombo = $ipWindow.FindName('AdapterCombo')
    $ipBox        = $ipWindow.FindName('IpTextBox')
    $maskBox      = $ipWindow.FindName('MaskTextBox')
    $gatewayBox   = $ipWindow.FindName('GatewayTextBox')
    $dnsBox       = $ipWindow.FindName('DnsTextBox')
    $statusText   = $ipWindow.FindName('StatusText')
    $applyButton  = $ipWindow.FindName('ApplyButton')
    $cancelButton = $ipWindow.FindName('CancelButton')

    $script:StaticIPDialogState = @{
        Adapters = @()
        Window   = $ipWindow
    }

    function Set-DialogStatus {
        param([string]$Message, [string]$Color)
        $statusText.Text = $Message
        $statusText.Foreground = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.ColorConverter]::ConvertFromString($Color))
        $statusText.Visibility = 'Visible'
    }

    # Enumerate active adapters. @() matters: a single adapter comes back as a
    # bare CimInstance whose .Count is $null
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object Status -eq 'Up' | Sort-Object -Property ifIndex)
    $script:StaticIPDialogState.Adapters = $adapters

    if ($adapters.Count -eq 0) {
        $adapterCombo.Items.Add('No active network adapters found') | Out-Null
        $adapterCombo.SelectedIndex = 0
        $adapterCombo.IsEnabled = $false
        $applyButton.IsEnabled = $false
    }
    else {
        foreach ($a in $adapters) {
            $adapterCombo.Items.Add(("{0}  ({1})" -f $a.Name, $a.InterfaceDescription)) | Out-Null
        }
    }

    # Pre-fill the input fields with the selected adapter's current IPv4 config
    $fillFromAdapter = {
        $idx = $adapterCombo.SelectedIndex
        $list = $script:StaticIPDialogState.Adapters
        if ($idx -lt 0 -or $idx -ge $list.Count) { return }
        $adapter = $list[$idx]

        $curIp = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $curGw = (Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Select-Object -First 1).NextHop
        $curDns = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '

        $ipBox.Text      = if ($curIp) { $curIp.IPAddress } else { '' }
        $maskBox.Text    = if ($curIp) { Convert-PrefixLengthToSubnetMask -PrefixLength $curIp.PrefixLength } else { '255.255.255.0' }
        $gatewayBox.Text = if ($curGw) { $curGw } else { '' }
        $dnsBox.Text     = $curDns
    }

    $adapterCombo.Add_SelectionChanged($fillFromAdapter)
    if ($adapters.Count -gt 0) {
        $adapterCombo.SelectedIndex = 0
        & $fillFromAdapter
    }

    # Title bar drag to move window
    $titleBar.Add_MouseLeftButtonDown({
        $ipWindow.DragMove()
    })

    $applyButton.Add_Click({
        $list = $script:StaticIPDialogState.Adapters
        $idx = $adapterCombo.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $list.Count) { return }
        $adapter = $list[$idx]

        $ip   = $ipBox.Text.Trim()
        $mask = $maskBox.Text.Trim()
        $gw   = $gatewayBox.Text.Trim()
        $dns  = $dnsBox.Text.Trim()

        # ---- Validate ----
        if (-not (Test-IPv4String $ip)) {
            Set-DialogStatus -Message "'$ip' is not a valid IPv4 address." -Color '#e81123'
            return
        }
        $prefix = Convert-SubnetMaskToPrefixLength -Mask $mask
        if ($null -eq $prefix -or -not (Test-IPv4String $mask)) {
            Set-DialogStatus -Message "'$mask' is not a valid subnet mask." -Color '#e81123'
            return
        }
        if ($gw -and -not (Test-IPv4String $gw)) {
            Set-DialogStatus -Message "'$gw' is not a valid gateway address." -Color '#e81123'
            return
        }
        $dnsList = @()
        if ($dns) {
            $dnsList = @($dns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            foreach ($server in $dnsList) {
                if (-not (Test-IPv4String $server)) {
                    Set-DialogStatus -Message "'$server' is not a valid DNS server address." -Color '#e81123'
                    return
                }
            }
        }

        # ---- Apply ----
        try {
            $applyButton.IsEnabled = $false
            Set-DialogStatus -Message 'Applying...' -Color '#8a8a8a'
            # Force the UI to repaint before the blocking network calls
            $ipWindow.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

            # Clear existing IPv4 config so New-NetIPAddress won't collide
            Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

            $newIpParams = @{
                InterfaceIndex = $adapter.ifIndex
                IPAddress      = $ip
                PrefixLength   = $prefix
                AddressFamily  = 'IPv4'
                ErrorAction    = 'Stop'
            }
            if ($gw) { $newIpParams.DefaultGateway = $gw }
            New-NetIPAddress @newIpParams | Out-Null

            if ($dnsList.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsList -ErrorAction Stop
            }

            Set-DialogStatus -Message "Static IP applied to '$($adapter.Name)'." -Color '#107c10'
            $cancelButton.Content = 'Close'
        }
        catch {
            Set-DialogStatus -Message "Failed to apply static IP: $($_.Exception.Message)" -Color '#e81123'
            $applyButton.IsEnabled = $true
        }
    })

    $cancelButton.Add_Click({
        $ipWindow.Close()
    })

    # Handle Escape key to close
    $ipWindow.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq 'Escape') {
            $ipWindow.Close()
        }
    })

    try {
        $ipWindow.ShowDialog() | Out-Null
    }
    finally {
        if ($overlay) {
            try {
                $ownerWindow.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Collapsed' })
            }
            catch { }
        }
    }
}
