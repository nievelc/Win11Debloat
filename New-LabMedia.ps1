# ============================================================================
#  New-LabMedia.ps1  --  Build unattended Windows 11 install media with your
#                        own username/password and this repo baked in.
#
#  Generates an autounattend.xml that:
#    - Skips language / product key / EULA / all OOBE screens (Microsoft
#      account included). Disk selection stays manual on purpose, so the
#      media can never silently wipe a machine.
#    - Creates a local administrator account with the name and password you
#      choose, and auto-logs it in once.
#    - Bypasses TPM / Secure Boot / RAM / CPU checks (lab use).
#    - Copies this repo to C:\Win11Debloat on the target and runs
#      Win11Debloat.ps1 (debloat + CustomSetup prompts) at first logon.
#
#  Two ways to use it:
#
#    USB (simplest, physical machines):
#      Make a normal bootable USB first (Rufus or Media Creation Tool), then:
#        .\New-LabMedia.ps1 -UsbDrive E:
#
#    ISO (VMs):
#      Point it at a stock Windows 11 ISO and it builds a new one:
#        .\New-LabMedia.ps1 -SourceIso C:\ISOs\Win11.iso -OutputIso C:\ISOs\Win11-lab.iso
#      No Windows ADK and no admin rights needed. The rebuilt ISO is
#      UEFI-boot only (which is all Windows 11 supports anyway).
#
#  Passwords never leave your machine: the XML is generated locally and the
#  password is stored in it base64-encoded (standard unattend obfuscation,
#  NOT encryption - treat the generated file/media as containing the password).
# ============================================================================

[CmdletBinding(DefaultParameterSetName = 'Iso')]
param(
    # Local admin account to create on the installed system
    [string]$UserName,

    # Password for that account (prompted securely if omitted)
    [string]$Password,

    # --- ISO mode ---
    [Parameter(ParameterSetName = 'Iso')]
    [string]$SourceIso,

    [Parameter(ParameterSetName = 'Iso')]
    [string]$OutputIso,

    # --- USB mode: drive letter of an already-bootable Windows 11 USB ---
    [Parameter(ParameterSetName = 'Usb')]
    [string]$UsbDrive,

    # Edition-selection key. Default = Microsoft's public generic Windows 11
    # Pro key. Picks the edition only; it does NOT activate Windows.
    [string]$ProductKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T',

    # Locale / keyboard. Defaults are detected from the machine running this.
    [string]$Locale,
    [string]$KeyboardLayout,

    # Don't bundle the debloater / first-logon task, just the account + OOBE skip
    [switch]$NoDebloat
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

# ---------------------------------------------------------------------------
# Gather + validate inputs
# ---------------------------------------------------------------------------
while ([string]::IsNullOrWhiteSpace($UserName)) {
    $UserName = Read-Host "Username for the local admin account"
}
if ($UserName -notmatch '^[^"/\\\[\]:;|=,+*?<>@\s]{1,20}$') {
    throw "Invalid username '$UserName'. Max 20 chars, no spaces or "" / \ [ ] : ; | = , + * ? < > @"
}
if ($UserName -match '^(administrator|guest|defaultaccount|system|wdagutilityaccount)$') {
    throw "'$UserName' is a reserved Windows account name."
}

while ([string]::IsNullOrWhiteSpace($Password)) {
    $secure = Read-Host "Password for $UserName" -AsSecureString
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

if (-not $Locale)         { $Locale = (Get-Culture).Name }
if (-not $KeyboardLayout) {
    $KeyboardLayout = try { (Get-WinUserLanguageList)[0].InputMethodTips[0] } catch { '0409:00000409' }
}

if ($PSCmdlet.ParameterSetName -eq 'Usb') {
    $UsbDrive = $UsbDrive.TrimEnd('\').TrimEnd(':') + ':'
    if (-not (Test-Path "$UsbDrive\sources\boot.wim")) {
        throw "$UsbDrive does not look like bootable Windows install media (no \sources\boot.wim). Create the USB with Rufus or the Media Creation Tool first."
    }
}
else {
    if (-not $SourceIso) { $SourceIso = Read-Host "Path to the stock Windows 11 ISO" }
    $SourceIso = (Resolve-Path $SourceIso).Path
    if (-not $OutputIso) {
        $OutputIso = Join-Path (Split-Path $SourceIso) `
            ([IO.Path]::GetFileNameWithoutExtension($SourceIso) + "-$UserName-lab.iso")
    }
}

# ---------------------------------------------------------------------------
# Generate autounattend.xml
# ---------------------------------------------------------------------------
$userXml = [Security.SecurityElement]::Escape($UserName)
$pwB64   = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Password + 'Password'))

$firstLogonXml = if ($NoDebloat) { '' } else { @"

            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Description>Win11Debloat post-install setup</Description>
                    <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Win11Debloat\Win11Debloat.ps1</CommandLine>
                </SynchronousCommand>
            </FirstLogonCommands>
"@ }

$unattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by New-LabMedia.ps1 (nievelc/Win11Debloat). Contains a
     base64-ENCODED (not encrypted) account password - treat accordingly. -->
<unattend xmlns="urn:schemas-microsoft-com:unattend">

    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>$Locale</UILanguage>
            </SetupUILanguage>
            <InputLocale>$KeyboardLayout</InputLocale>
            <SystemLocale>$Locale</SystemLocale>
            <UILanguage>$Locale</UILanguage>
            <UserLocale>$Locale</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <UserData>
                <AcceptEula>true</AcceptEula>
                <ProductKey>
                    <Key>$ProductKey</Key>
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
            </UserData>
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>4</Order>
                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>5</Order>
                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>

    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>$KeyboardLayout</InputLocale>
            <SystemLocale>$Locale</SystemLocale>
            <UILanguage>$Locale</UILanguage>
            <UserLocale>$Locale</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>$userXml</Name>
                        <DisplayName>$userXml</DisplayName>
                        <Group>Administrators</Group>
                        <Password>
                            <Value>$pwB64</Value>
                            <PlainText>false</PlainText>
                        </Password>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <AutoLogon>
                <Enabled>true</Enabled>
                <LogonCount>1</LogonCount>
                <Username>$userXml</Username>
                <Password>
                    <Value>$pwB64</Value>
                    <PlainText>false</PlainText>
                </Password>
            </AutoLogon>$firstLogonXml
        </component>
    </settings>

</unattend>
"@

# Sanity-check the XML before writing it anywhere
$null = [xml]$unattendXml

function Copy-DebloatPayload {
    param([string]$MediaRoot)
    if ($NoDebloat) { return }
    $dest = Join-Path $MediaRoot 'sources\$OEM$\$1\Win11Debloat'
    Write-Host "Bundling debloater into $dest ..."
    $null = robocopy $repoRoot $dest /E /XD .git /XF *.iso /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
}

# ---------------------------------------------------------------------------
# USB mode: drop files onto existing bootable media and we're done
# ---------------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Usb') {
    [IO.File]::WriteAllText("$UsbDrive\autounattend.xml", $unattendXml, (New-Object Text.UTF8Encoding $false))
    Copy-DebloatPayload -MediaRoot "$UsbDrive\"
    Write-Host ""
    Write-Host "Done. $UsbDrive is ready - boot the target machine from it." -ForegroundColor Green
    Write-Host "Account: $UserName (admin, auto-logs in once). Disk selection stays manual." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# ISO mode: extract -> inject -> rebuild (UEFI bootable, no ADK, no admin)
# ---------------------------------------------------------------------------
$work = Join-Path $env:TEMP 'w11lab_build'   # short path: ISO trees exceed MAX_PATH under deep folders
if (Test-Path $work) { Remove-Item $work -Recurse -Force }

Write-Host "Mounting $SourceIso ..."
$mount = Mount-DiskImage -ImagePath $SourceIso -PassThru
try {
    $drive = ($mount | Get-Volume).DriveLetter
    Write-Host "Extracting ISO contents (this copies several GB)..."
    $null = robocopy "${drive}:\" $work /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
}
finally {
    Dismount-DiskImage -ImagePath $SourceIso | Out-Null
}

attrib -R "$work\*" /S /D | Out-Null
[IO.File]::WriteAllText("$work\autounattend.xml", $unattendXml, (New-Object Text.UTF8Encoding $false))
Copy-DebloatPayload -MediaRoot $work

if (-not (Test-Path "$work\efi\microsoft\boot\efisys.bin")) {
    throw "efisys.bin not found - source does not look like a Windows install ISO."
}

Write-Host "Rebuilding bootable ISO (UEFI)..."
Add-Type -CompilerParameters (New-Object CodeDom.Compiler.CompilerParameters -Property @{ CompilerOptions = '/unsafe' }) -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices.ComTypes;
public class ISOWriter {
    public unsafe static void Create(string path, object stream, int blockSize, int totalBlocks) {
        int bytesRead = 0;
        byte[] buf = new byte[blockSize * 2048];
        IntPtr ptr = (IntPtr)(&bytesRead);
        IStream istream = stream as IStream;
        using (FileStream fs = File.OpenWrite(path)) {
            long remaining = (long)totalBlocks * blockSize;
            while (remaining > 0) {
                int toRead = (int)Math.Min((long)buf.Length, remaining);
                istream.Read(buf, toRead, ptr);
                if (bytesRead <= 0) { break; }
                fs.Write(buf, 0, bytesRead);
                remaining -= bytesRead;
            }
            fs.Flush();
        }
    }
}
'@

$bootStream = New-Object -ComObject ADODB.Stream
$bootStream.Open()
$bootStream.Type = 1
$bootStream.LoadFromFile("$work\efi\microsoft\boot\efisys.bin")
$boot = New-Object -ComObject IMAPI2FS.BootOptions
$boot.AssignBootImage($bootStream)
$boot.PlatformId = 0xEF   # EFI
$boot.Emulation  = 0

$fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fsi.FileSystemsToCreate = 4          # UDF (supports the >4GB install.esd/wim)
$fsi.VolumeName = 'WIN11_LAB'
$fsi.FreeMediaBlocks = 5242880        # ~10.7 GB headroom
$fsi.BootImageOptions = $boot
$fsi.Root.AddTree($work, $false)

if (Test-Path $OutputIso) { Remove-Item $OutputIso -Force }
$img = $fsi.CreateResultImage()
[ISOWriter]::Create($OutputIso, $img.ImageStream, $img.BlockSize, $img.TotalBlocks)

Remove-Item $work -Recurse -Force

Write-Host ""
Write-Host ("Done: {0} ({1:N2} GB)" -f $OutputIso, ((Get-Item $OutputIso).Length / 1GB)) -ForegroundColor Green
Write-Host "Account: $UserName (admin, auto-logs in once). Disk selection stays manual." -ForegroundColor Green
Write-Host "Note: the ISO boots UEFI only - use Gen2/EFI VMs or modern hardware." -ForegroundColor DarkGray
exit 0
