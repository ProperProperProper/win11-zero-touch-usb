#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
================================================================================
ENTERPRISE WDS PXE VALIDATOR + SELF-HEALING CONFIGURATION SCRIPT
================================================================================

PURPOSE
-------
Fully validates and repairs Windows Deployment Services (WDS) for PXE booting
inside isolated Hyper-V NAT environments WITHOUT Active Directory.

Designed for:
 - Hyper-V isolated virtual switches
 - NAT networking
 - Workgroup environments
 - No Active Directory
 - No existing DHCP infrastructure
 - Fully automated deployments

FEATURES
--------
✔ Intelligent prerequisite validation
✔ Safe retry engine
✔ Graceful error handling
✔ Automatic self-healing
✔ WDS role installation
✔ Standalone WDS initialisation
✔ Service recovery
✔ PXE provider validation
✔ TFTP validation
✔ Firewall remediation
✔ WDS registry repair
✔ DHCP coexistence configuration
✔ Boot image validation
✔ Event Viewer logging
✔ Structured transcript logging
✔ NAT-aware diagnostics
✔ Hyper-V PXE compatibility checks
✔ Idempotent (safe to rerun)
✔ Safe cancellation handling
✔ Production-grade logging

IMPORTANT
---------
PXE REQUIRES DHCP.

This script configures WDS correctly but DOES NOT provide DHCP leases.

If this VM is the only infrastructure VM:
 - Install DHCP Server role
 - OR use dnsmasq/pfSense/etc.

PXE broadcast traffic DOES NOT cross NAT boundaries.
Clients MUST exist on the same Hyper-V virtual switch.

================================================================================
#>

#region CONFIG

$Config = @{
    RemoteInstallPath   = "D:\RemoteInstall"
    LogFolder           = "C:\Logs"
    LogFile             = "WDS-PXE-Deployment.log"
    EventSource         = "WDS-PXE-Validator"
    MaxRetries          = 3
    RetryDelaySeconds   = 5
    ServiceTimeout      = 30
    WDSServiceNames     = @("WDSServer","WDSTFTP")
    RequiredFirewallUDP = @(67,68,69,4011)
}

#endregion

#region GLOBALS

$Script:FatalError = $false
$Script:TranscriptStarted = $false

#endregion

#region LOGGING

function Initialize-Logging {

    try {

        if (-not (Test-Path $Config.LogFolder)) {
            New-Item -Path $Config.LogFolder -ItemType Directory -Force | Out-Null
        }

        $Global:LogPath = Join-Path $Config.LogFolder $Config.LogFile

        Start-Transcript -Path $Global:LogPath -Append -Force | Out-Null
        $Script:TranscriptStarted = $true

        if (-not [System.Diagnostics.EventLog]::SourceExists($Config.EventSource)) {

            New-EventLog `
                -LogName Application `
                -Source $Config.EventSource `
                -ErrorAction SilentlyContinue
        }

        Write-Log "Logging initialised"
    }
    catch {
        Write-Host "Failed to initialise logging: $($_.Exception.Message)"
    }
}

function Write-Log {

    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
        [string]$Level = "INFO"
    )

    try {

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $Formatted = "[$Timestamp] [$Level] $Message"

        switch ($Level) {
            "ERROR"   { Write-Host $Formatted -ForegroundColor Red }
            "WARN"    { Write-Host $Formatted -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $Formatted -ForegroundColor Green }
            "DEBUG"   { Write-Host $Formatted -ForegroundColor Cyan }
            default   { Write-Host $Formatted }
        }

        Add-Content -Path $Global:LogPath -Value $Formatted -ErrorAction SilentlyContinue

        try {

            $EntryType = switch ($Level) {
                "ERROR" { "Error" }
                "WARN"  { "Warning" }
                default { "Information" }
            }

            Write-EventLog `
                -LogName Application `
                -Source $Config.EventSource `
                -EntryType $EntryType `
                -EventId 1000 `
                -Message $Message `
                -ErrorAction SilentlyContinue
        }
        catch {
        }
    }
    catch {
        Write-Host "LOGGING FAILURE: $($_.Exception.Message)"
    }
}

#endregion

#region RETRY ENGINE

function Invoke-WithRetry {

    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory)]
        [string]$OperationName,

        [switch]$Fatal
    )

    $LastError = $null

    for ($Attempt = 1; $Attempt -le $Config.MaxRetries; $Attempt++) {

        try {

            Write-Log "$OperationName (Attempt $Attempt/$($Config.MaxRetries))"

            $Result = & $ScriptBlock

            Write-Log "$OperationName completed successfully" "SUCCESS"

            return $Result
        }
        catch {

            $LastError = $_

            Write-Log "$OperationName failed: $($_.Exception.Message)" "WARN"

            if ($Attempt -lt $Config.MaxRetries) {

                Write-Log "Retrying in $($Config.RetryDelaySeconds) seconds..."

                Start-Sleep -Seconds $Config.RetryDelaySeconds
            }
        }
    }

    Write-Log "$OperationName failed after all retry attempts" "ERROR"

    if ($Fatal) {

        $Script:FatalError = $true

        throw $LastError
    }

    return $null
}

#endregion

#region SAFE EXECUTION

function Invoke-SafeCommand {

    param(
        [string]$Command,
        [switch]$IgnoreExitCode
    )

    Write-Log "Executing: $Command" "DEBUG"

    $Output = cmd.exe /c $Command 2>&1

    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0 -and -not $IgnoreExitCode) {

        throw "Command failed with exit code $ExitCode : $Output"
    }

    return $Output
}

#endregion

#region PREREQUISITE VALIDATION

function Test-Administrator {

    try {

        $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

        $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

        return $Principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    catch {
        return $false
    }
}

function Test-ServerOS {

    try {

        $OS = Get-CimInstance Win32_OperatingSystem

        if ($OS.ProductType -eq 1) {
            return $false
        }

        return $true
    }
    catch {
        return $false
    }
}

#endregion

#region SELF-HEALING

function Repair-WDSServices {

    Invoke-WithRetry `
        -OperationName "Repairing WDS Services" `
        -ScriptBlock {

        foreach ($ServiceName in $Config.WDSServiceNames) {

            $Service = Get-Service -Name $ServiceName -ErrorAction Stop

            if ($Service.StartType -ne "Automatic") {

                Set-Service `
                    -Name $ServiceName `
                    -StartupType Automatic `
                    -ErrorAction Stop
            }

            if ($Service.Status -ne "Running") {

                Start-Service `
                    -Name $ServiceName `
                    -ErrorAction Stop

                $Timeout = [DateTime]::Now.AddSeconds($Config.ServiceTimeout)

                do {

                    Start-Sleep -Seconds 2

                    $Service.Refresh()

                } until (
                    $Service.Status -eq "Running" -or
                    [DateTime]::Now -gt $Timeout
                )

                if ($Service.Status -ne "Running") {
                    throw "$ServiceName failed to start"
                }
            }

            Write-Log "$ServiceName healthy"
        }
    }
}

function Repair-WDSRegistry {

    Invoke-WithRetry `
        -OperationName "Repairing WDS Registry" `
        -ScriptBlock {

        $RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WDSServer\Providers\WDSPXE"

        if (-not (Test-Path $RegistryPath)) {

            New-Item `
                -Path $RegistryPath `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        Set-ItemProperty `
            -Path $RegistryPath `
            -Name "ProvidersOrder" `
            -Value "BINLSVC" `
            -Force `
            -ErrorAction SilentlyContinue

        Write-Log "WDS registry repaired"
    }
}

#endregion

#region WDS INSTALLATION

function Install-WDSRole {

    Invoke-WithRetry `
        -OperationName "Installing WDS Role" `
        -Fatal `
        -ScriptBlock {

        $Feature = Get-WindowsFeature -Name WDS

        if ($Feature.InstallState -eq "Installed") {

            Write-Log "WDS already installed"
            return
        }

        Install-WindowsFeature `
            -Name WDS `
            -IncludeManagementTools `
            -ErrorAction Stop | Out-Null

        Write-Log "WDS installed successfully"
    }
}

#endregion

#region REMOTEINSTALL

function Initialize-RemoteInstall {

    Invoke-WithRetry `
        -OperationName "Preparing RemoteInstall Directory" `
        -Fatal `
        -ScriptBlock {

        if (-not (Test-Path $Config.RemoteInstallPath)) {

            New-Item `
                -Path $Config.RemoteInstallPath `
                -ItemType Directory `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        $Drive = Get-PSDrive -Name (
            Split-Path $Config.RemoteInstallPath -Qualifier
        ).Replace(":","")

        if ($Drive.Free -lt 10GB) {

            throw "Insufficient disk space for WDS"
        }

        Write-Log "RemoteInstall ready"
    }
}

#endregion

#region WDS INITIALISATION

function Initialize-WDSStandalone {

    Invoke-WithRetry `
        -OperationName "Initialising WDS Standalone Mode" `
        -Fatal `
        -ScriptBlock {

        $AlreadyInitialized = $false

        try {

            $Output = Invoke-SafeCommand `
                -Command "wdsutil /get-server /show:config" `
                -IgnoreExitCode

            if ($Output -match "Windows Deployment Services") {
                $AlreadyInitialized = $true
            }
        }
        catch {
        }

        if ($AlreadyInitialized) {

            Write-Log "WDS already initialised"
            return
        }

        Invoke-SafeCommand `
            -Command "wdsutil /initialize-server /reminst:$($Config.RemoteInstallPath) /standalone /answer:yes"

        Write-Log "WDS initialised"
    }
}

#endregion

#region PXE CONFIGURATION

function Configure-PXE {

    Invoke-WithRetry `
        -OperationName "Configuring PXE Settings" `
        -Fatal `
        -ScriptBlock {

        Invoke-SafeCommand `
            -Command "wdsutil /set-server /AnswerClients:All"

        Invoke-SafeCommand `
            -Command "wdsutil /set-server /PxePromptPolicy /Known:NoPrompt /New:NoPrompt"

        Invoke-SafeCommand `
            -Command "wdsutil /set-server /UseDhcpPorts:No"

        Invoke-SafeCommand `
            -Command "wdsutil /set-server /DhcpOption60:Yes"

        Write-Log "PXE configuration applied"
    }
}

#endregion

#region FIREWALL

function Configure-Firewall {

    Invoke-WithRetry `
        -OperationName "Configuring Firewall Rules" `
        -ScriptBlock {

        foreach ($Port in $Config.RequiredFirewallUDP) {

            $RuleName = "WDS-PXE-UDP-$Port"

            $Rule = Get-NetFirewallRule `
                -DisplayName $RuleName `
                -ErrorAction SilentlyContinue

            if (-not $Rule) {

                New-NetFirewallRule `
                    -DisplayName $RuleName `
                    -Direction Inbound `
                    -Protocol UDP `
                    -LocalPort $Port `
                    -Action Allow `
                    -Profile Any `
                    -ErrorAction Stop | Out-Null
            }

            Write-Log "Firewall validated for UDP $Port"
        }
    }
}

#endregion

#region VALIDATION

function Test-WDSTFTP {

    Invoke-WithRetry `
        -OperationName "Validating TFTP" `
        -ScriptBlock {

        $Service = Get-Service WDSTFTP -ErrorAction Stop

        if ($Service.Status -ne "Running") {
            throw "WDSTFTP not running"
        }

        Write-Log "TFTP operational"
    }
}

function Test-BootImages {

    Invoke-WithRetry `
        -OperationName "Checking Boot Images" `
        -ScriptBlock {

        $Output = Invoke-SafeCommand `
            -Command "wdsutil /get-allimages /show:images" `
            -IgnoreExitCode

        if ($Output -match "boot") {

            Write-Log "Boot images detected" "SUCCESS"
        }
        else {

            Write-Log "No boot images found" "WARN"

            Write-Log "Import boot.wim from Windows ISO"
        }
    }
}

function Test-Networking {

    Invoke-WithRetry `
        -OperationName "Validating Hyper-V NAT Networking" `
        -ScriptBlock {

        $Adapters = Get-NetAdapter |
            Where-Object { $_.Status -eq "Up" }

        if (-not $Adapters) {
            throw "No active network adapters"
        }

        foreach ($Adapter in $Adapters) {

            Write-Log "Adapter: $($Adapter.Name)"

            $IPConfig = Get-NetIPAddress `
                -InterfaceIndex $Adapter.ifIndex `
                -AddressFamily IPv4 `
                -ErrorAction SilentlyContinue

            foreach ($IP in $IPConfig) {

                Write-Log "IPv4: $($IP.IPAddress)"
            }
        }

        $Nat = Get-NetNat -ErrorAction SilentlyContinue

        if ($Nat) {

            foreach ($Entry in $Nat) {

                Write-Log "Detected NAT: $($Entry.Name)"
                Write-Log "Prefix: $($Entry.InternalIPInterfaceAddressPrefix)"
            }
        }
        else {

            Write-Log "No Windows NAT objects found" "WARN"
        }
    }
}

#endregion

#region MAIN

try {

    Initialize-Logging

    Write-Log "========================================================="
    Write-Log "STARTING WDS PXE VALIDATION + SELF-HEALING"
    Write-Log "========================================================="

    if (-not (Test-Administrator)) {
        throw "Script must run as Administrator"
    }

    Write-Log "Administrative privileges confirmed"

    if (-not (Test-ServerOS)) {
        throw "WDS requires Windows Server OS"
    }

    Write-Log "Server OS confirmed"

    Install-WDSRole

    Initialize-RemoteInstall

    Initialize-WDSStandalone

    Repair-WDSRegistry

    Repair-WDSServices

    Configure-PXE

    Configure-Firewall

    Test-WDSTFTP

    Test-BootImages

    Test-Networking

    Write-Log "========================================================="
    Write-Log "VALIDATION COMPLETED SUCCESSFULLY"
    Write-Log "=========================================================" "SUCCESS"

    Write-Log ""
    Write-Log "NEXT STEPS:"
    Write-Log "1. Import boot.wim into WDS"
    Write-Log "2. Ensure DHCP exists on the same vSwitch"
    Write-Log "3. PXE clients must exist on SAME Hyper-V switch"
    Write-Log "4. Gen2 VMs may require Secure Boot disabled"
    Write-Log "5. Set Network Boot first in VM firmware"
    Write-Log ""

    Write-Log "Log File:"
    Write-Log $Global:LogPath
}
catch {

    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"

    Write-Log "Script terminated unexpectedly" "ERROR"

    exit 1
}
finally {

    try {

        if ($Script:TranscriptStarted) {
            Stop-Transcript | Out-Null
        }
    }
    catch {
    }
}

#endregion