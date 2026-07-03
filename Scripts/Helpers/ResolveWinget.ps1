<#
    .SYNOPSIS
        Locates the winget executable, even when its PATH alias isn't ready yet.

    .DESCRIPTION
        On a freshly installed Windows (especially at first logon, e.g. an
        unattended setup), the App Installer package is present on disk but its
        App Execution Alias in %LOCALAPPDATA%\Microsoft\WindowsApps has not been
        registered for the new user profile yet, so `Get-Command winget` fails
        even though winget.exe exists under Program Files\WindowsApps.

        This helper tries the normal command first, then falls back to resolving
        winget.exe directly from the DesktopAppInstaller package folder (we run
        elevated, so the ACL-locked WindowsApps folder is enumerable). Returns
        the full path to a runnable winget.exe, or $null if none is found.
#>
function Resolve-WingetPath {
    # 1. Normal case: winget is on PATH / the App Execution Alias is registered
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) { return $cmd.Source }

    # 2. Ask the package manager where App Installer lives. This works even when
    #    the PATH alias isn't provisioned yet. Try the current user first, then
    #    -AllUsers (needs admin, which the debloater has) in case the package is
    #    installed system-wide but not yet registered for this profile.
    $pkgQueries = @(
        { Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue },
        { Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue }
    )
    foreach ($query in $pkgQueries) {
        try {
            $pkg = & $query |
                Sort-Object -Property @{ Expression = { try { [version]$_.Version } catch { [version]'0.0.0' } } } -Descending |
                Select-Object -First 1
            if ($pkg -and $pkg.InstallLocation) {
                $exe = Join-Path $pkg.InstallLocation 'winget.exe'
                if (Test-Path $exe) { return $exe }
            }
        }
        catch { }
    }

    # 3. Last resort: the per-user App Execution Alias stub, if it exists on disk
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $alias) { return $alias }

    return $null
}
