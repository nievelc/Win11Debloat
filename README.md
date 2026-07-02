# Win11Debloat + Setup

A fork of [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) that turns a fresh Windows 11 install into a working machine in one pass. You get everything the original does — pre-installed junk removed, telemetry cut down, the UI stripped of the noisy bits — plus a handful of extra setup tweaks, all in the **same interface** as the rest of the app.

**What this fork adds on top** — a **Custom Setup** category in the tweaks list, alongside the original's Privacy, Taskbar, File Explorer, etc.:

- **Enable Remote Desktop (RDP)** — a checkbox that turns RDP on with Network Level Authentication and opens the firewall rules (unchecking reverses it).
- **Silence notifications** — kills the toast/pop-up spam from Outlook (new *and* classic), Edge, Brave, and Chrome, so you don't spend your first day dismissing bubbles.
- **Tame Edge** — skips the first-run setup wizard, turns off diagnostic data and tracking out of the box, sets google.com as the homepage and new tab page, and kills the MSN feed, Rewards, shopping assistant, and sidebar.
- **Install Brave** — a checkbox that pulls down the Brave browser via winget.
- **Solid black desktop** — clears the wallpaper and sets a solid black background, applied instantly.
- **Configure static IP** — a button in the Custom Setup card opens a themed dialog to set the IP / subnet mask / gateway / DNS on an adapter, pre-filled from its current config.

These behave exactly like the built-in tweaks: tick what you want, review the pending changes, and hit Apply. Registry-backed ones (RDP, notifications, Edge) even show their current state and can be undone. Everything works from the command line too — `-EnableRDP`, `-DisableAppNotifications`, `-SetEdgePolicies`, `-InstallBrave`, `-SetBlackDesktop`.

### One-line install

Open PowerShell **as Administrator** on the fresh machine and paste:

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/nievelc/Win11Debloat/main/Bootstrap.ps1")))
```

That fetches this fork, unblocks the scripts, and launches `Win11Debloat.ps1`. The extra tweaks show up in the **Custom Setup** category in the GUI. Pass `-Silent` / `-Sysprep` to run unattended.

The extra tweaks are defined in `Config/Features.json` (Custom Setup category) with their registry files in `Regfiles/`; the winget/desktop/static-IP logic lives in `Scripts/Features/InvokeChanges.ps1` and `Scripts/GUI/Show-StaticIPDialog.ps1`.

### Fully unattended install media (lab use)

Want a Windows 11 installer that creates **your** local admin account, skips every OOBE screen (Microsoft account included), and runs the debloater automatically at first logon? `New-LabMedia.ps1` generates the `autounattend.xml` for you — your username and password are typed locally and never leave your machine.

Clone or [download](../../archive/refs/heads/main.zip) this repo, open PowerShell in the repo folder, then pick one:

**USB stick (simplest — physical machines).** Make a normal bootable USB first (Rufus or the Media Creation Tool), then:

```powershell
.\New-LabMedia.ps1 -UsbDrive E:
```

Windows Setup automatically reads `autounattend.xml` from the root of the install media, so injecting it is literally a file copy — no ISO surgery needed.

**Rebuilt ISO (VMs).** Point it at a stock Windows 11 ISO ([download from Microsoft](https://www.microsoft.com/software-download/windows11)):

```powershell
.\New-LabMedia.ps1 -SourceIso C:\ISOs\Win11.iso
```

It prompts for username/password, extracts the ISO, injects the answer file plus the debloater (bundled to `C:\Win11Debloat` on the target), and rebuilds a bootable ISO next to the source. No Windows ADK, no admin rights. The rebuilt ISO is UEFI-boot only — use Gen2/EFI VMs.

**What to expect when you boot it:** the only question Setup asks is *which disk to install to* (deliberately kept manual so the media can never silently wipe a machine). After that it installs, auto-logs into your new admin account once, and launches the debloater + setup prompts.

**Lab-use notes:** the answer file bypasses the TPM/Secure Boot/RAM/CPU checks and uses Microsoft's public *generic* Pro key, which selects the edition but does **not** activate Windows — bring your own licence. The password is stored base64-encoded (not encrypted) in the generated `autounattend.xml`, so treat the media as containing the password, and don't commit the generated file anywhere public.

---

**Upstream credit:** all of the heavy lifting — the debloat itself, the CLI/GUI, the config system, the wiki — is [Raphire's](https://github.com/Raphire/Win11Debloat). If this saved you time, [buy him a coffee](https://ko-fi.com/M4M5C6UPC).

---

[![GitHub Release](https://img.shields.io/github/v/release/Raphire/Win11Debloat?style=for-the-badge&label=Latest%20release)](https://github.com/Raphire/Win11Debloat/releases/latest)
[![Join the Discussion](https://img.shields.io/badge/Join-the%20Discussion-2D9F2D?style=for-the-badge&logo=github&logoColor=white)](https://github.com/Raphire/Win11Debloat/discussions)
[![Static Badge](https://img.shields.io/badge/Documentation-_?style=for-the-badge&logo=bookstack&color=grey)](https://github.com/Raphire/Win11Debloat/wiki/)

 Win11Debloat is a lightweight, easy to use PowerShell script that allows you to quickly declutter and customize your Windows experience, no installation required! You can use it to remove pre-installed apps, disable telemetry, remove intrusive interface elements and much more. No need to painstakingly go through all the settings yourself or remove apps one by one. Win11Debloat makes the process quick and easy!

The script also includes many features that system administrators and power users will enjoy. Such as a powerful command-line interface, support for Windows Audit mode and the ability to make changes to other Windows users. You can also easily export & import your preferred settings, allowing you to quickly apply the same settings on all your systems. Please refer to our [wiki](https://github.com/Raphire/Win11Debloat/wiki) for more details.

![Win11Debloat Menu](/Assets/Images/menu.png)

#### Did this script help you? Please consider buying me a cup of coffee to support my work

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/M4M5C6UPC)

## Usage

> [!Warning]
> Great care went into making sure this script does not unintentionally break any OS functionality, but use at your own risk! If you run into any issues, please report them [here](https://github.com/Raphire/Win11Debloat/issues).

### Quick method

Download & run the script automatically via PowerShell.

1. Open PowerShell or Terminal.
2. Copy and paste the command below into PowerShell:

```PowerShell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/nievelc/Win11Debloat/main/Bootstrap.ps1")))
```

3. Wait for the script to automatically download and launch Win11Debloat.
4. Carefully read through and follow the on-screen instructions.

This method supports command-line parameters to customize the behaviour of the script. Please click [here](https://github.com/Raphire/Win11Debloat/wiki/Command%E2%80%90line-Interface#parameters) for more information.

### Traditional method

<details>
  <summary>Manually download & run the script.</summary><br/>

  1. [Download the latest version of the script](https://github.com/Raphire/Win11Debloat/releases/latest), and extract the .ZIP file to your desired location.
  2. Navigate to the Win11Debloat folder
  3. Double click the `Run.bat` file to start the script. NOTE: If the console window immediately closes and nothing happens, try the advanced method below.
  4. Accept the Windows UAC prompt to run the script as administrator, this is required for the script to function.
  5. Carefully read through and follow the on-screen instructions.
</details>

### Advanced method

<details>
  <summary>Manually download the script & run the script via PowerShell. Recommended for advanced users.</summary><br/>

  1. [Download the latest version of the script](https://github.com/Raphire/Win11Debloat/releases/latest), and extract the .ZIP file to your desired location.
  2. Open PowerShell or Terminal as an administrator.
  3. Temporarily enable PowerShell execution by entering the following command:

  ```PowerShell
  Set-ExecutionPolicy Unrestricted -Scope Process -Force
  ```

  4. In PowerShell, navigate to the directory where the files were extracted. Example: `cd c:\Win11Debloat`
  5. Now run the script by entering the following command:

  ```PowerShell
  .\Win11Debloat.ps1
  ```

  6. Carefully read through and follow the on-screen instructions.

  This method supports command-line parameters to customize the behaviour of the script. Please click [here](https://github.com/Raphire/Win11Debloat/wiki/Command%E2%80%90line-Interface#parameters) for more information.
</details>

## Features

Below is an overview of the key features and functionality offered by Win11Debloat. You can visit the [the wiki](https://github.com/Raphire/Win11Debloat/wiki) for more details.

> [!Tip]
> All of the changes made by Win11Debloat can easily be reverted and almost all of the apps can be reinstalled through the Microsoft Store. You can visit [the wiki](https://github.com/Raphire/Win11Debloat/wiki/Reverting-Changes) for more information on reverting changes.

#### App Removal

- Remove a wide variety of preinstalled apps. Click [here](https://github.com/Raphire/Win11Debloat/wiki/App-Removal) for more info.

#### Privacy & Suggested Content

- Disable telemetry, diagnostic data, activity history, app-launch tracking & targeted ads.
- Disable tips, tricks, suggestions & ads across Windows, the lock screen and Microsoft Edge.
- Disable Windows location services, app location access and Find My Device location tracking.
- Hide Microsoft 365 ads on the Settings 'Home' page, or hide the 'Home' page entirely.

#### AI Features

- Disable & remove Microsoft Copilot, Windows Recall and Click to Do.
- Prevent AI service (WSAIFabricSvc) from starting automatically.
- Disable AI Features in Edge, Paint and Notepad.

#### System

- Disable the Drag Tray for sharing & moving files.
- Restore the old Windows 10 style context menu.
- Turn off Enhance Pointer Precision, also known as mouse acceleration.
- Disable the Sticky Keys keyboard shortcut.
- Disable Storage Sense automatic disk cleanup.
- Disable fast start-up to ensure a full shutdown.
- Disable BitLocker automatic device encryption.
- Disable network connectivity during Modern Standby to reduce battery drain.

#### Windows Update

- Prevent Windows from getting updates as soon as they're available.
- Prevent automatic restarts after updates while signed in.
- Disable sharing of downloaded updates with other PCs, also known as Delivery Optimization.

#### Appearance

- Enable dark mode for system and apps.
- Disable transparency, animations and visual effects.

#### Start Menu & Search

- Customize the start menu by removing pinned apps, hiding recommendations, and customizing the 'All Apps' section.
- Disable the Phone Link mobile devices integration in the start menu.
- Disable Bing web search & Copilot integration and Microsoft Store app suggestions in Windows search.

#### Taskbar

- Change taskbar alignment.
- Customize or hide taskbar buttons like the search bar, taskview and more.
- Disable widgets on the taskbar & lock screen.
- Enable the 'End Task' option in the taskbar right click menu to quickly force-close apps.
- Enable the 'Last Active Click' behavior in the taskbar app area. This allows you to repeatedly click on an application's icon in the taskbar to switch focus between the open windows of that application.
- Customize how app buttons are shown on the taskbar.

#### File Explorer

- Change the default location that File Explorer opens to.
- Show file extensions for known file types.
- Show hidden files, folders and drives.
- Hide the Home, Gallery or OneDrive section from the File Explorer navigation pane.
- Hide duplicate removable drive entries from the File Explorer navigation pane, so only the entry under 'This PC' remains.
- Add all common folders (Desktop, Downloads, etc.) back to 'This PC' in File Explorer.
- Change drive letter position or visibility in File Explorer.

#### Multi-tasking

- Disable window snapping.
- Disable Snap Assist and Snap Layout suggestions when dragging or snapping windows.
- Change whether tabs are shown when snapping windows or pressing Alt+Tab.

#### Optional Windows Features

- Enable Windows Sandbox, a lightweight desktop environment for safely running applications in isolation.
- Enable Windows Subsystem for Linux which allows you to run a Linux environment directly on Windows.

#### Other

- Disable Xbox Game Bar integration & game/screen recording. This also disables `ms-gamingoverlay`/`ms-gamebar` popups if you uninstall the Xbox Game Bar.
- Disable bloat in Brave browser (AI, Crypto, News, etc.)

#### Advanced Features

- Ability to [apply changes to a different user](https://github.com/Raphire/Win11Debloat/wiki/Advanced-Features#running-as-another-user), instead of the currently logged in user.
- [Sysprep mode](https://github.com/Raphire/Win11Debloat/wiki/Advanced-Features#sysprep-mode) to apply changes to the Windows Default user profile. Which ensures, all new users will have the changes automatically applied to them.

## Contributing

We welcome contributions of all kinds! Please see our [Contributing Guidelines](https://github.com/Raphire/Win11Debloat/blob/main/.github/CONTRIBUTING.md) for detailed instructions on how to get started and best practices for contributing.

## License

Win11Debloat is licensed under the MIT license. See the LICENSE file for more information.
