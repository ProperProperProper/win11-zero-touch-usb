#Requires -RunAsAdministrator
<#
.SYNOPSIS
    OEM driver and firmware installer — Dell, HP, Lenovo, ASUS, Microsoft Surface
    Compatible with Windows 11 25H2 (build 26100+)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$LogFile = "C:\Windows\Logs\driver-install.log"
function Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Tee-Object -FilePath $LogFile -Append | Write-Host
}

# Wait for network
Log "Waiting for network..."
$elapsed = 0
while (-not (Test-Connection 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
    Start-Sleep 5; $elapsed += 5
    if ($elapsed -ge 120) { Log "No network after 120s — continuing anyway"; break }
}
Log "Network ready."

# Wait for winget
Log "Waiting for winget..."
$elapsed = 0
while (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Start-Sleep 5; $elapsed += 5
    if ($elapsed -ge 120) { Log "winget not available"; break }
}

function Winget-Install($id) {
    Log "Installing $id..."
    winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | ForEach-Object { Log $_ }
}

function Install-WUModule {
    if (-not (Get-Module PSWindowsUpdate -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -SkipPublisherCheck
        Import-Module PSWindowsUpdate
    }
}

# Detect OEM
$cs           = Get-CimInstance Win32_ComputerSystem
$Manufacturer = $cs.Manufacturer.ToUpper()
$Model        = $cs.Model
Log "Detected: '$($cs.Manufacturer)' | Model: '$Model'"

# DELL
if ($Manufacturer -match 'DELL') {
    Log "=== Dell: Dell Command Update ==="
    Winget-Install 'Dell.CommandUpdate.Universal'
    $dcu = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe",
             "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") |
           Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($dcu) {
        Log "Running DCU..."
        & $dcu /applyUpdates -reboot=disable -outputLog="C:\Windows\Logs\dcu.log"
        Log "DCU exit: $LASTEXITCODE"
    } else { Log "ERROR: dcu-cli.exe not found" }
}

# HP
elseif ($Manufacturer -match 'HP|HEWLETT') {
    Log "=== HP: HP Image Assistant ==="
    $hpiaPath = "$env:TEMP\HPImageAssistant.exe"
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri 'https://ftp.hp.com/pub/caps-softpaq/cmit/HPImageAssistant.exe' -OutFile $hpiaPath -UseBasicParsing
        Log "Running HPIA..."
        & $hpiaPath /Operation:Analyze /Action:Install /Category:All /Selection:All /Silent /ReportFolder:"C:\Windows\Logs\HPIA"
        Log "HPIA exit: $LASTEXITCODE"
    } catch {
        Log "HPIA failed: $_ — falling back to HP Support Assistant"
        Winget-Install 'HP.HPSupportAssistant'
    }
}

# LENOVO
elseif ($Manufacturer -match 'LENOVO') {
    Log "=== Lenovo: Thin Installer ==="
    $thinPath = "$env:TEMP\ThinInstaller.exe"
    $thinRepo = "$env:TEMP\LenovoDrivers"
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri 'https://download.lenovo.com/pccbbs/thinkvantage_en/thin_installer.exe' -OutFile $thinPath -UseBasicParsing
        New-Item -ItemType Directory -Path $thinRepo -Force | Out-Null
        Log "Downloading Lenovo packages..."
        & $thinPath /NOREBOOT /NOCANCEL /EXPORTTOREPO /REPOPATH $thinRepo 2>&1 | ForEach-Object { Log $_ }
        Log "Installing Lenovo packages..."
        & $thinPath /NOREBOOT /NOCANCEL /INSTALLALL /REPOPATH $thinRepo 2>&1 | ForEach-Object { Log $_ }
        Log "Thin Installer exit: $LASTEXITCODE"
    } catch {
        Log "Thin Installer failed: $_ — falling back to Lenovo System Update"
        Winget-Install 'Lenovo.SystemUpdate'
        $lsu = "${env:ProgramFiles(x86)}\Lenovo\System Update\tvsuCommandLine.exe"
        if (Test-Path $lsu) { & $lsu /CM /SLOGGING /NOREBOOT /NOCANCEL }
    }
}

# ASUS
elseif ($Manufacturer -match 'ASUS|ASUSTEK') {
    Log "=== ASUS: Windows Update drivers + MyASUS ==="
    try {
        Install-WUModule
        Log "Installing ASUS drivers via Windows Update..."
        Install-WindowsUpdate -Category 'Drivers' -AcceptAll -IgnoreReboot -Confirm:$false | ForEach-Object { Log $_ }
    } catch { Log "WU drivers failed: $_" }
    Winget-Install 'ASUS.MyASUS'
}

# SURFACE
elseif ($Manufacturer -match 'MICROSOFT' -and $Model -match 'SURFACE') {
    Log "=== Microsoft Surface: Windows Update + Surface App ==="
    try {
        Install-WUModule
        Log "Installing Surface drivers and firmware..."
        Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false | ForEach-Object { Log $_ }
    } catch {
        Log "WU failed: $_ — using usoclient"
        usoclient StartScan; Start-Sleep 10; usoclient StartInstall
    }
    Winget-Install 'Microsoft.SurfaceApp'
}

# UNKNOWN
else {
    Log "=== Unknown OEM — Windows Update drivers ==="
    try {
        Install-WUModule
        Install-WindowsUpdate -Category 'Drivers' -AcceptAll -IgnoreReboot -Confirm:$false | ForEach-Object { Log $_ }
    } catch {
        Log "WU failed: $_"
        usoclient StartScan; Start-Sleep 10; usoclient StartInstall
    }
}

# Always run full Windows Update
Log "=== Windows Update — all patches ==="
try {
    Install-WUModule
    Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false | ForEach-Object { Log $_ }
} catch {
    Log "WU patches failed: $_ — usoclient fallback"
    usoclient StartScan; Start-Sleep 30; usoclient StartInstall
}

Log "=== Done. Log: $LogFile — reboot may be required ==="
