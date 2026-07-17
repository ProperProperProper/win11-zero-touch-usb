#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Pro N — Workstation setup: debloat, harden, optimise
#>

$ErrorActionPreference = 'Continue'
$LogFile = 'C:\Windows\Logs\workstation-setup.log'
function Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Tee-Object -FilePath $LogFile -Append | Write-Host
}

Log '=========================================='
Log ' Windows 11 Pro N — Workstation Setup'
Log '=========================================='

# ── Remove bloat apps ─────────────────────────────────────────────────────────
Log '--- Removing bloat apps ---'
$bloat = @(
    'Microsoft.3DBuilder'
    'Microsoft.549981C3F5F10'          # Cortana app
    'Microsoft.BingFinance'
    'Microsoft.BingNews'
    'Microsoft.BingSports'
    'Microsoft.BingWeather'
    'Microsoft.Copilot'
    'Microsoft.GamingApp'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.Messaging'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MixedReality.Portal'
    'Microsoft.NetworkSpeedTest'
    'Microsoft.News'
    'Microsoft.Office.OneNote'
    'Microsoft.OneConnect'
    'Microsoft.OutlookForWindows'
    'Microsoft.Paint3D'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.RemoteDesktop'
    'Microsoft.ScreenSketch'
    'Microsoft.ScreenSketch'
    'Microsoft.SkypeApp'
    'Microsoft.Teams'
    'Microsoft.Todos'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsCommunicationsApps'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'MicrosoftTeams'
    'Clipchamp.Clipchamp'
    'MicrosoftCorporationII.MicrosoftFamily'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.OneDriveSync'
)

foreach ($app in $bloat) {
    Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue |
        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object DisplayName -eq $app |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    Log "Removed: $app"
}

# Keep: Calculator, Notepad, Paint, Snipping Tool, Terminal, Settings

# ── Disable Copilot ───────────────────────────────────────────────────────────
Log '--- Disabling Copilot ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v ShowCopilotButton /t REG_DWORD /d 0 /f | Out-Null

# ── Disable Cortana ───────────────────────────────────────────────────────────
Log '--- Disabling Cortana ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' /v AllowCortana /t REG_DWORD /d 0 /f | Out-Null

# ── Disable telemetry ─────────────────────────────────────────────────────────
Log '--- Disabling telemetry & data collection ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v AllowTelemetry /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' /v AllowTelemetry /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v LimitDiagnosticLogCollection /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v DisableOneSettingsDownloads /t REG_DWORD /d 1 /f | Out-Null

# Disable telemetry services
$telemetrySvcs = @('DiagTrack','dmwappushservice','WerSvc','PcaSvc')
foreach ($svc in $telemetrySvcs) {
    Stop-Service $svc -Force -ErrorAction SilentlyContinue
    Set-Service  $svc -StartupType Disabled -ErrorAction SilentlyContinue
    Log "Disabled service: $svc"
}

# ── Disable advertising ID ────────────────────────────────────────────────────
Log '--- Disabling advertising ID ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' /v DisabledByGroupPolicy /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' /v Enabled /t REG_DWORD /d 0 /f | Out-Null

# ── Disable Start menu ads / suggestions ─────────────────────────────────────
Log '--- Disabling Start menu ads and suggestions ---'
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v ContentDeliveryAllowed           /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v OemPreInstalledAppsEnabled       /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v PreInstalledAppsEnabled          /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v SilentInstalledAppsEnabled       /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v SubscribedContent-338388Enabled  /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v SubscribedContent-338389Enabled  /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v SubscribedContent-353698Enabled  /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v SystemPaneSuggestionsEnabled     /t REG_DWORD /d 0 /f | Out-Null

# ── Disable Xbox services ─────────────────────────────────────────────────────
Log '--- Disabling Xbox services ---'
$xboxSvcs = @('XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc','XboxSystemAppMonitor')
foreach ($svc in $xboxSvcs) {
    Stop-Service $svc -Force -ErrorAction SilentlyContinue
    Set-Service  $svc -StartupType Disabled -ErrorAction SilentlyContinue
}

# ── Disable OneDrive ──────────────────────────────────────────────────────────
Log '--- Disabling OneDrive ---'
Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
if (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") {
    & "$env:SystemRoot\System32\OneDriveSetup.exe" /uninstall 2>&1 | Out-Null
}
if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
    & "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" /uninstall 2>&1 | Out-Null
}
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive' /v DisableFileSyncNGSC /t REG_DWORD /d 1 /f | Out-Null

# ── Power plan — High Performance ────────────────────────────────────────────
Log '--- Setting High Performance power plan ---'
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
powercfg /hibernate off
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0

# ── Visual performance — best for programs ────────────────────────────────────
Log '--- Optimising visual effects for performance ---'
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' /v VisualFXSetting /t REG_DWORD /d 3 /f | Out-Null
reg add 'HKCU\Control Panel\Desktop' /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f | Out-Null

# ── Taskbar — clean workstation layout ───────────────────────────────────────
Log '--- Configuring taskbar ---'
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v TaskbarAl          /t REG_DWORD /d 0 /f | Out-Null  # left-align
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v ShowTaskViewButton  /t REG_DWORD /d 0 /f | Out-Null  # hide task view
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v TaskbarMn           /t REG_DWORD /d 0 /f | Out-Null  # hide Meet Now
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v TaskbarDa           /t REG_DWORD /d 0 /f | Out-Null  # hide widgets
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'            /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f | Out-Null  # hide search box

# ── File Explorer — workstation defaults ──────────────────────────────────────
Log '--- Configuring File Explorer ---'
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v Hidden           /t REG_DWORD /d 1 /f | Out-Null  # show hidden files
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v HideFileExt      /t REG_DWORD /d 0 /f | Out-Null  # show extensions
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v LaunchTo         /t REG_DWORD /d 1 /f | Out-Null  # open to This PC
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v ShowSuperHidden   /t REG_DWORD /d 1 /f | Out-Null  # show protected OS files
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v SeparateProcess   /t REG_DWORD /d 1 /f | Out-Null  # each window in own process

# ── Dark mode ─────────────────────────────────────────────────────────────────
Log '--- Enabling dark mode ---'
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v AppsUseLightTheme   /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' /v SystemUsesLightTheme /t REG_DWORD /d 0 /f | Out-Null

# ── Disable lock screen ───────────────────────────────────────────────────────
Log '--- Disabling lock screen ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization' /v NoLockScreen /t REG_DWORD /d 1 /f | Out-Null

# ── Disable Windows Consumer Experience / tips ───────────────────────────────
Log '--- Disabling tips, suggestions, and consumer experience ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'   /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v Start_IrisRecommendations /t REG_DWORD /d 0 /f | Out-Null

# ── Enable Remote Desktop ─────────────────────────────────────────────────────
Log '--- Enabling Remote Desktop ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' /v fDenyTSConnections /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' /v UserAuthentication /t REG_DWORD /d 1 /f | Out-Null
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue

# ── Disable unnecessary scheduled tasks ──────────────────────────────────────
Log '--- Disabling junk scheduled tasks ---'
$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask'
)
foreach ($task in $tasks) {
    Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
    Log "Disabled task: $task"
}

# ── Disable unnecessary services ─────────────────────────────────────────────
Log '--- Disabling unnecessary services ---'
$services = @(
    'Fax'              # Fax
    'RetailDemo'       # Retail demo
    'MapsBroker'       # Downloaded maps manager
    'lfsvc'            # Geolocation
    'SharedAccess'     # Internet connection sharing
    'WMPNetworkSvc'    # Windows Media Player network
    'WSearch'          # Windows Search (re-enable if needed)
)
foreach ($svc in $services) {
    Stop-Service $svc -Force -ErrorAction SilentlyContinue
    Set-Service  $svc -StartupType Disabled -ErrorAction SilentlyContinue
    Log "Disabled service: $svc"
}

# ── Workstation-grade Windows Update policy ───────────────────────────────────
Log '--- Configuring Windows Update for workstation ---'
# Receive security updates quickly, defer feature updates 1 year
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' /v NoAutoUpdate          /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' /v AUOptions             /t REG_DWORD /d 4 /f | Out-Null  # auto download + schedule install
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' /v ScheduledInstallDay   /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' /v ScheduledInstallTime  /t REG_DWORD /d 3 /f | Out-Null  # 3am
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'    /v DeferFeatureUpdates   /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'    /v DeferFeatureUpdatesPeriodInDays /t REG_DWORD /d 365 /f | Out-Null

# ── Network profile — set to Private (required for RDP/file sharing) ──────────
Log '--- Setting network profile to Private ---'
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

# ── Enable Windows Firewall on all profiles ───────────────────────────────────
Log '--- Ensuring firewall is enabled ---'
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue

# ── Processor scheduling — background services (workstation) ──────────────────
Log '--- Optimising processor scheduling ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' /v Win32PrioritySeparation /t REG_DWORD /d 38 /f | Out-Null

# ── Disable Fast Startup (causes issues with dual-boot and some hardware) ─────
Log '--- Disabling Fast Startup ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null

# ── Install essential workstation tools via winget ────────────────────────────
Log '--- Installing workstation tools ---'
$tools = @(
    '7zip.7zip'
    'Google.Chrome'
    'Notepad++.Notepad++'
    'Microsoft.PowerShell'
    'Microsoft.WindowsTerminal'
    'Microsoft.VisualStudioCode'
    'Git.Git'
    'Adobe.Acrobat.Reader.64-bit'
)
foreach ($tool in $tools) {
    Log "Installing $tool..."
    winget install --id $tool -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | ForEach-Object { Log $_ }
}

# ── Restart Explorer to apply registry changes ────────────────────────────────
Log '--- Restarting Explorer ---'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Start-Process explorer

Log '=========================================='
Log ' Workstation setup complete!'
Log " Log: $LogFile"
Log '=========================================='

# ── Microsoft 365 — classic Outlook + core apps via ODT ──────────────────────
Log '--- Installing Microsoft 365 (classic Outlook, Word, Excel, PowerPoint) ---'
$odtDir    = "$env:TEMP\ODT"
$odtExe    = "$odtDir\setup.exe"
$odtConfig = "$odtDir\office-config.xml"

New-Item -ItemType Directory -Path $odtDir -Force | Out-Null

# Download Office Deployment Tool
$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri 'https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17928-20114.exe' `
        -OutFile "$odtDir\odt.exe" -UseBasicParsing
    # Extract ODT
    & "$odtDir\odt.exe" /quiet /extract:"$odtDir" 2>&1 | Out-Null
} catch {
    Log "ODT download failed: $_ — trying winget fallback"
    winget install --id Microsoft.Office -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | ForEach-Object { Log $_ }
}

# Office config — classic Outlook + Word + Excel + PowerPoint only
# No Teams, OneDrive, OneNote, Access, Publisher, Groove, Lync
@'
<Configuration ID="classic-outlook-workstation">
  <Add OfficeClientEdition="64" Channel="Current" ForceUpgrade="TRUE">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="OneNote" />
      <ExcludeApp ID="Publisher" />
      <ExcludeApp ID="Teams" />
    </Product>
  </Add>
  <Updates Enabled="TRUE" Channel="Current" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Logging Level="Standard" Path="C:\Windows\Logs" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="AUTOACTIVATE" Value="1" />
  <Property Name="SharedComputerLicensing" Value="0" />
  <!-- Force classic Outlook, block new Outlook -->
  <Property Name="NEWOUTLOOK" Value="0" />
</Configuration>
'@ | Out-File $odtConfig -Encoding UTF8

if (Test-Path $odtExe) {
    Log "Running ODT — installing classic Outlook + Word + Excel + PowerPoint..."
    & $odtExe /configure $odtConfig 2>&1 | ForEach-Object { Log $_ }
    Log "ODT exit code: $LASTEXITCODE"
} else {
    Log "ODT setup.exe not found after extraction — Office install skipped"
}

# Block new Outlook from replacing classic Outlook
reg add 'HKLM\SOFTWARE\Microsoft\Office\16.0\Outlook' /v DisableNewOutlook     /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Preferences' /v HideNewOutlookToggle /t REG_DWORD /d 1 /f | Out-Null
# Remove new Outlook (Outlook for Windows app)
Get-AppxPackage -Name 'Microsoft.OutlookForWindows' -AllUsers -ErrorAction SilentlyContinue |
    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Log "Classic Outlook install complete — new Outlook blocked"

# ── Australia — Melbourne locale (belt+suspenders with autounattend) ──────────
Set-TimeZone -Id 'AUS Eastern Standard Time' -ErrorAction SilentlyContinue
Set-WinUserLanguageList -LanguageList 'en-AU' -Force -ErrorAction SilentlyContinue
Set-WinSystemLocale     -SystemLocale 'en-AU' -ErrorAction SilentlyContinue
Set-Culture             -CultureInfo  'en-AU' -ErrorAction SilentlyContinue
Set-WinHomeLocation     -GeoId 12            -ErrorAction SilentlyContinue
