#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
================================================================================
FULLY AUTOMATED HYPER-V NAT + DHCP + WDS PXE DEPLOYMENT SCRIPT
================================================================================

PURPOSE
-------
Creates a complete standalone PXE deployment environment for Hyper-V labs.

FEATURES
--------
✔ Creates Hyper-V Internal vSwitch
✔ Creates NAT network
✔ Configures host gateway adapter
✔ Configures static server IP
✔ Installs DHCP Server
✔ Creates DHCP scope
✔ Configures DHCP options
✔ Installs WDS
✔ Initialises standalone WDS
✔ Configures PXE
✔ Configures TFTP
✔ Opens firewall rules
✔ Self-healing retry logic
✔ Event Viewer logging
✔ Graceful error handling
✔ Safe re-run support
✔ Hyper-V NAT compatible
✔ Workgroup compatible
✔ No Active Directory required

NETWORK DESIGN
--------------
Hyper-V Host Gateway:
    192.168.9.1

WDS/DHCP Server:
    192.168.9.10

DHCP Scope:
    192.168.9.100 - 192.168.9.200

PXE works ONLY inside this virtual switch.

REQUIREMENTS
------------
- Windows Server with Hyper-V installed
- Run as Administrator
- Internet access optional
- PXE clients must exist on same vSwitch

================================================================================
#>

#region CONFIG

$Config = @{

    # Hyper-V
    VSwitchName                = "PXE-NAT-SWITCH"

    # Network
    NATName                    = "PXE-NAT"
    NetworkPrefix              = "192.168.9.0/24"
    GatewayIP                  = "192.168.9.1"
    GatewayPrefixLength        = 24

    # Server
    ServerIP                   = "192.168.9.10"
    ServerPrefixLength         = 24
    ServerGateway              = "192.168.9.1"
    DNSServers                 = @("1.1.1.1","8.8.8.8")

    # DHCP
    ScopeName                  = "PXE Scope"
    ScopeStart                 = "192.168.9.100"
    ScopeEnd                   = "192.168.9.200"
    ScopeSubnetMask            = "255.255.255.0"
    ScopeRouter                = "192.168.9.1"
    ScopeDNS                   = @("1.1.1.1","8.8.8.8")
    ScopeLeaseDurationDays     = 8

    # WDS
    RemoteInstallPath          = "D:\RemoteInstall"

    # Logging
    LogFolder                  = "C:\Logs"
    LogFile                    = "PXE-Environment-Setup.log"
    EventSource                = "PXE-Deployment"

    # Retry
    MaxRetries                 = 3
    RetryDelaySeconds          = 5

    # Firewall
    RequiredUDPPorts           = @(67,68,69,4011)
}

#endregion

#region GLOBALS

$Global:LogPath = $null
$Global:TranscriptStarted = $false

#endregion

#region LOGGING

function Initialize-Logging {

    try {

        if (-not (Test-Path $Config.LogFolder)) {

            New-Item `
                -Path $Config.LogFolder `
                -ItemType Directory `
                -Force | Out-Null
        }

        $Global:LogPath = Join-Path `
            $Config.LogFolder `
            $Config.LogFile

        Start-Transcript `
            -Path $Global:LogPath `
            -Append `
            -Force | Out-Null

        $Global:TranscriptStarted = $true

        if (-not [System.Diagnostics.EventLog]::SourceExists($Config.EventSource)) {

            New-EventLog `
                -LogName Application `
                -Source $Config.EventSource `
                -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host "Logging initialisation failed"
    }
}

function Write-Log {

    param(
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[$Timestamp] [$Level] $Message"

    switch ($Level) {

        "ERROR"   { Write-Host $Line -ForegroundColor Red }
        "WARN"    { Write-Host $Line -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Line -ForegroundColor Green }
        "DEBUG"   { Write-Host $Line -ForegroundColor Cyan }
        default   { Write-Host $Line }
    }

    try {

        Add-Content `
            -Path $Global:LogPath `
            -Value $Line `
            -ErrorAction SilentlyContinue
    }
    catch {
    }

    try {

        $EventType = switch ($Level) {

            "ERROR" { "Error" }
            "WARN"  { "Warning" }
            default { "Information" }
        }

        Write-EventLog `
            -LogName Application `
            -Source $Config.EventSource `
            -EventId 1000 `
            -EntryType $EventType `
            -Message $Message `
            -ErrorAction SilentlyContinue
    }
    catch {
    }
}

#endregion

#region RETRY ENGINE

function Invoke-WithRetry {

    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [switch]$Fatal
    )

    $LastError = $null

    for ($Attempt = 1; $Attempt -le $Config.MaxRetries; $Attempt++) {

        try {

            Write-Log "$OperationName (Attempt $Attempt/$($Config.MaxRetries))"

            $Result = & $ScriptBlock

            Write-Log "$OperationName completed" "SUCCESS"

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

    Write-Log "$OperationName failed permanently" "ERROR"

    if ($Fatal) {
        throw $LastError
    }

    return $null
}

#endregion

#region VALIDATION

function Test-Administrator {

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal = New-Object `
        Security.Principal.WindowsPrincipal($Identity)

    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

#endregion

#region HYPER-V VSWITCH

function Initialize-VSwitch {

    Invoke-WithRetry `
        -OperationName "Creating Hyper-V Internal vSwitch" `
        -Fatal `
        -ScriptBlock {

        $Existing = Get-VMSwitch `
            -Name $Config.VSwitchName `
            -ErrorAction SilentlyContinue

        if ($Existing) {

            Write-Log "vSwitch already exists"
            return
        }

        New-VMSwitch `
            -SwitchName $Config.VSwitchName `
            -SwitchType Internal `
            -ErrorAction Stop | Out-Null

        Write-Log "Created vSwitch: $($Config.VSwitchName)"
    }
}

#endregion

#region HOST NAT

function Initialize-NAT {

    Invoke-WithRetry `
        -OperationName "Configuring NAT Network" `
        -Fatal `
        -ScriptBlock {

        $Adapter = Get-NetAdapter |
            Where-Object {
                $_.Name -like "*$($Config.VSwitchName)*"
            }

        if (-not $Adapter) {
            throw "Unable to locate Hyper-V virtual adapter"
        }

        $ExistingIP = Get-NetIPAddress `
            -InterfaceIndex $Adapter.ifIndex `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue

        if (-not $ExistingIP) {

            New-NetIPAddress `
                -InterfaceIndex $Adapter.ifIndex `
                -IPAddress $Config.GatewayIP `
                -PrefixLength $Config.GatewayPrefixLength `
                -ErrorAction Stop | Out-Null
        }

        $ExistingNat = Get-NetNat `
            -Name $Config.NATName `
            -ErrorAction SilentlyContinue

        if (-not $ExistingNat) {

            New-NetNat `
                -Name $Config.NATName `
                -InternalIPInterfaceAddressPrefix $Config.NetworkPrefix `
                -ErrorAction Stop | Out-Null
        }

        Write-Log "NAT configured"
    }
}

#endregion

#region SERVER NETWORK

function Configure-ServerNetwork {

    Invoke-WithRetry `
        -OperationName "Configuring Server Network" `
        -Fatal `
        -ScriptBlock {

        $Adapter = Get-NetAdapter |
            Where-Object {
                $_.Status -eq "Up"
            } |
            Select-Object -First 1

        if (-not $Adapter) {
            throw "No active network adapter found"
        }

        $ExistingIP = Get-NetIPAddress `
            -InterfaceIndex $Adapter.ifIndex `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -eq $Config.ServerIP
            }

        if (-not $ExistingIP) {

            Get-NetIPAddress `
                -InterfaceIndex $Adapter.ifIndex `
                -AddressFamily IPv4 `
                -ErrorAction SilentlyContinue |
                Remove-NetIPAddress `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue

            New-NetIPAddress `
                -InterfaceIndex $Adapter.ifIndex `
                -IPAddress $Config.ServerIP `
                -PrefixLength $Config.ServerPrefixLength `
                -DefaultGateway $Config.ServerGateway `
                -ErrorAction Stop | Out-Null
        }

        Set-DnsClientServerAddress `
            -InterfaceIndex $Adapter.ifIndex `
            -ServerAddresses $Config.DNSServers `
            -ErrorAction Stop

        Write-Log "Server network configured"
    }
}

#endregion

#region DHCP

function Install-DHCP {

    Invoke-WithRetry `
        -OperationName "Installing DHCP Server" `
        -Fatal `
        -ScriptBlock {

        $Feature = Get-WindowsFeature DHCP

        if ($Feature.InstallState -ne "Installed") {

            Install-WindowsFeature `
                -Name DHCP `
                -IncludeManagementTools `
                -ErrorAction Stop | Out-Null
        }

        Write-Log "DHCP installed"
    }
}

function Configure-DHCP {

    Invoke-WithRetry `
        -OperationName "Configuring DHCP Scope" `
        -Fatal `
        -ScriptBlock {

        $Scope = Get-DhcpServerv4Scope `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq $Config.ScopeName
            }

        if (-not $Scope) {

            Add-DhcpServerv4Scope `
                -Name $Config.ScopeName `
                -StartRange $Config.ScopeStart `
                -EndRange $Config.ScopeEnd `
                -SubnetMask $Config.ScopeSubnetMask `
                -LeaseDuration (
                    New-TimeSpan `
                        -Days $Config.ScopeLeaseDurationDays
                ) `
                -State Active `
                -ErrorAction Stop
        }

        Set-DhcpServerv4OptionValue `
            -Router $Config.ScopeRouter `
            -DnsServer $Config.ScopeDNS `
            -ErrorAction Stop

        # PXE Options
        Set-DhcpServerv4OptionValue `
            -OptionId 66 `
            -Value $Config.ServerIP `
            -ErrorAction SilentlyContinue

        Set-DhcpServerv4OptionValue `
            -OptionId 67 `
            -Value "boot\x64\wdsmgfw.efi" `
            -ErrorAction SilentlyContinue

        Restart-Service DHCPServer -ErrorAction SilentlyContinue

        Write-Log "DHCP configured"
    }
}

#endregion

#region WDS

function Install-WDS {

    Invoke-WithRetry `
        -OperationName "Installing WDS" `
        -Fatal `
        -ScriptBlock {

        $Feature = Get-WindowsFeature WDS

        if ($Feature.InstallState -ne "Installed") {

            Install-WindowsFeature `
                -Name WDS `
                -IncludeManagementTools `
                -ErrorAction Stop | Out-Null
        }

        Write-Log "WDS installed"
    }
}

function Initialize-WDS {

    Invoke-WithRetry `
        -OperationName "Initialising WDS" `
        -Fatal `
        -ScriptBlock {

        if (-not (Test-Path $Config.RemoteInstallPath)) {

            New-Item `
                -Path $Config.RemoteInstallPath `
                -ItemType Directory `
                -Force | Out-Null
        }

        $Check = cmd.exe /c "wdsutil /get-server /show:config" 2>&1

        if ($LASTEXITCODE -ne 0) {

            cmd.exe /c `
                "wdsutil /initialize-server /reminst:$($Config.RemoteInstallPath) /standalone /answer:yes"

            if ($LASTEXITCODE -ne 0) {
                throw "WDS initialisation failed"
            }
        }

        cmd.exe /c "wdsutil /set-server /AnswerClients:All"
        cmd.exe /c "wdsutil /set-server /UseDhcpPorts:No"
        cmd.exe /c "wdsutil /set-server /DhcpOption60:Yes"

        Write-Log "WDS configured"
    }
}

#endregion

#region SERVICES

function Repair-Services {

    Invoke-WithRetry `
        -OperationName "Repairing Services" `
        -ScriptBlock {

        $Services = @(
            "DHCPServer",
            "WDSServer",
            "WDSTFTP"
        )

        foreach ($Name in $Services) {

            $Service = Get-Service `
                -Name $Name `
                -ErrorAction Stop

            Set-Service `
                -Name $Name `
                -StartupType Automatic `
                -ErrorAction SilentlyContinue

            if ($Service.Status -ne "Running") {

                Start-Service `
                    -Name $Name `
                    -ErrorAction Stop
            }

            Write-Log "$Name running"
        }
    }
}

#endregion

#region FIREWALL

function Configure-Firewall {

    Invoke-WithRetry `
        -OperationName "Configuring Firewall" `
        -ScriptBlock {

        foreach ($Port in $Config.RequiredUDPPorts) {

            $RuleName = "PXE-UDP-$Port"

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
                    -Profile Any | Out-Null
            }

            Write-Log "Firewall opened UDP $Port"
        }
    }
}

#endregion

#region VALIDATION

function Validate-PXEEnvironment {

    Invoke-WithRetry `
        -OperationName "Validating PXE Environment" `
        -ScriptBlock {

        $Services = @(
            "DHCPServer",
            "WDSServer",
            "WDSTFTP"
        )

        foreach ($ServiceName in $Services) {

            $Service = Get-Service `
                -Name $ServiceName `
                -ErrorAction Stop

            if ($Service.Status -ne "Running") {

                throw "$ServiceName is not running"
            }
        }

        Write-Log "All PXE services healthy"

        $Images = cmd.exe /c `
            "wdsutil /get-allimages /show:images" 2>&1

        if ($Images -notmatch "boot") {

            Write-Log "No boot images detected" "WARN"
            Write-Log "Import boot.wim before deployment"
        }

        Write-Log "PXE validation complete"
    }
}

#endregion

#region MAIN

try {

    Initialize-Logging

    Write-Log "======================================================="
    Write-Log "STARTING FULL PXE DEPLOYMENT ENVIRONMENT CONFIGURATION"
    Write-Log "======================================================="

    if (-not (Test-Administrator)) {
        throw "Must run as Administrator"
    }

    Write-Log "Administrator privileges confirmed"

    Initialize-VSwitch

    Initialize-NAT

    Configure-ServerNetwork

    Install-DHCP

    Configure-DHCP

    Install-WDS

    Initialize-WDS

    Repair-Services

    Configure-Firewall

    Validate-PXEEnvironment

    Write-Log "======================================================="
    Write-Log "PXE ENVIRONMENT READY"
    Write-Log "=======================================================" "SUCCESS"

    Write-Log ""
    Write-Log "NEXT STEPS:"
    Write-Log "1. Import boot.wim into WDS"
    Write-Log "2. Connect PXE clients to vSwitch:"
    Write-Log "   $($Config.VSwitchName)"
    Write-Log "3. Enable Network Boot in VM firmware"
    Write-Log "4. Gen2 VMs may require Secure Boot disabled"
    Write-Log ""

    Write-Log "BOOT IMAGE IMPORT:"
    Write-Log 'wdsutil /add-image /imagefile:"D:\sources\boot.wim" /imagetype:Boot /imagegroup:"Boot Images"'
    Write-Log ""

    Write-Log "Server IP: $($Config.ServerIP)"
    Write-Log "Gateway: $($Config.GatewayIP)"
    Write-Log "DHCP Scope: $($Config.ScopeStart) - $($Config.ScopeEnd)"
    Write-Log ""

    Write-Log "Log File:"
    Write-Log $Global:LogPath
}
catch {

    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"

    exit 1
}
finally {

    try {

        if ($Global:TranscriptStarted) {
            Stop-Transcript | Out-Null
        }
    }
    catch {
    }
}

#endregion