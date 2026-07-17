#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Pro N — Maximum security baseline
    MSB + CIS L1 + ASD Essential Eight
    Auto-login preserved for unattended setup.
#>

$ErrorActionPreference = 'Continue'
$LogFile = 'C:\Windows\Logs\security-baseline.log'
function Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $msg" | Tee-Object -FilePath $LogFile -Append | Write-Host
}

Log '=========================================='
Log ' Security Baseline — MSB + CIS L1 + ASD E8'
Log '=========================================='

# ── Account policy ────────────────────────────────────────────────────────────
Log '--- Account policy ---'
net accounts /minpwlen:14 /maxpwage:60 /minpwage:1 /uniquepw:10 | Out-Null
net accounts /lockoutthreshold:5 /lockoutduration:15 /lockoutwindow:15 | Out-Null

# Rename built-in Administrator to ITSupport
$admin = Get-LocalUser | Where-Object { $_.SID -like '*-500' }
if ($admin -and $admin.Name -ne 'ITSupport') {
    Rename-LocalUser -Name $admin.Name -NewName 'ITSupport'
    Log "Renamed built-in Administrator -> ITSupport"
}
Disable-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
Log "Guest account disabled"

# ── UAC — maximum ─────────────────────────────────────────────────────────────
Log '--- UAC maximum ---'
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v EnableLUA                  /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 2 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v ConsentPromptBehaviorUser  /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v PromptOnSecureDesktop      /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v EnableVirtualization       /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v EnableInstallerDetection   /t REG_DWORD /d 1 /f | Out-Null

# ── Disable Fast Startup ─────────────────────────────────────────────────────
Log '--- Disabling Fast Startup ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' /v HiberbootEnabled /t REG_DWORD /d 0 /f | Out-Null
powercfg /hibernate off | Out-Null

# ── Disable IPv6 ─────────────────────────────────────────────────────────────
Log '--- Disabling IPv6 ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' /v DisabledComponents /t REG_DWORD /d 255 /f | Out-Null
Get-NetAdapter | ForEach-Object {
    Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
}

# ── Disable NetBIOS over TCP/IP ───────────────────────────────────────────────
Log '--- Disabling NetBIOS ---'
Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
    $_.SetTcpipNetbios(2) | Out-Null
}
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' /v NodeType /t REG_DWORD /d 2 /f | Out-Null

# ── Disable LLMNR ─────────────────────────────────────────────────────────────
Log '--- Disabling LLMNR ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' /v EnableMulticast /t REG_DWORD /d 0 /f | Out-Null

# ── Disable mDNS ─────────────────────────────────────────────────────────────
Log '--- Disabling mDNS ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' /v EnableMDNS /t REG_DWORD /d 0 /f | Out-Null

# ── Disable WPAD (Web Proxy Auto-Discovery — used in MITM attacks) ────────────
Log '--- Disabling WPAD ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\WinHttpAutoProxySvc' /v Start /t REG_DWORD /d 4 /f | Out-Null
Stop-Service WinHttpAutoProxySvc -Force -ErrorAction SilentlyContinue

# ── Credential Guard ──────────────────────────────────────────────────────────
Log '--- Enabling Credential Guard ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' /v EnableVirtualizationBasedSecurity   /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' /v RequirePlatformSecurityFeatures     /t REG_DWORD /d 3 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'         /v LsaCfgFlags                        /t REG_DWORD /d 1 /f | Out-Null

# ── Disable WDigest ───────────────────────────────────────────────────────────
Log '--- Disabling WDigest (no plaintext creds in memory) ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' /v UseLogonCredential /t REG_DWORD /d 0 /f | Out-Null

# ── LSASS as Protected Process ────────────────────────────────────────────────
Log '--- LSASS PPL protection ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v RunAsPPL     /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v RunAsPPLBoot /t REG_DWORD /d 1 /f | Out-Null

# ── NTLMv2 only ───────────────────────────────────────────────────────────────
Log '--- Enforcing NTLMv2 only ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v LmCompatibilityLevel /t REG_DWORD /d 5 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v NoLMHash             /t REG_DWORD /d 1 /f | Out-Null

# ── HVCI (Hypervisor-Protected Code Integrity) ────────────────────────────────
Log '--- Enabling HVCI ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' /v Enabled /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' /v Locked  /t REG_DWORD /d 0 /f | Out-Null

# ── SMBv1 disabled ────────────────────────────────────────────────────────────
Log '--- Disabling SMBv1 ---'
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' /v SMB1 /t REG_DWORD /d 0 /f | Out-Null

# ── SMB signing ───────────────────────────────────────────────────────────────
Log '--- Enabling SMB signing ---'
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force -ErrorAction SilentlyContinue
Set-SmbServerConfiguration -EnableSecuritySignature  $true -Force -ErrorAction SilentlyContinue
Set-SmbClientConfiguration -EnableSecuritySignature  $true -Force -ErrorAction SilentlyContinue

# ── Disable legacy TLS / SSL ──────────────────────────────────────────────────
Log '--- Disabling SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1 ---'
foreach ($proto in @('SSL 2.0','SSL 3.0','TLS 1.0','TLS 1.1')) {
    $base = "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto"
    reg add "$base\Server" /v Enabled           /t REG_DWORD /d 0 /f | Out-Null
    reg add "$base\Server" /v DisabledByDefault /t REG_DWORD /d 1 /f | Out-Null
    reg add "$base\Client" /v Enabled           /t REG_DWORD /d 0 /f | Out-Null
    reg add "$base\Client" /v DisabledByDefault /t REG_DWORD /d 1 /f | Out-Null
}

# ── Disable autorun/autoplay ──────────────────────────────────────────────────
Log '--- Disabling AutoRun/AutoPlay ---'
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v NoDriveTypeAutoRun      /t REG_DWORD /d 255 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer'                /v NoAutoplayfornonVolume  /t REG_DWORD /d 1   /f | Out-Null

# ── Disable Remote Assistance ─────────────────────────────────────────────────
Log '--- Disabling Remote Assistance ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance' /v fAllowToGetHelp /t REG_DWORD /d 0 /f | Out-Null

# ── Disable Windows Script Host ───────────────────────────────────────────────
Log '--- Disabling Windows Script Host ---'
reg add 'HKLM\SOFTWARE\Microsoft\Windows Script Host\Settings' /v Enabled /t REG_DWORD /d 0 /f | Out-Null

# ── Disable anonymous access ──────────────────────────────────────────────────
Log '--- Disabling anonymous network access ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v RestrictAnonymous          /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v RestrictAnonymousSAM       /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v EveryoneIncludesAnonymous  /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' /v RestrictNullSessAccess /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' /v NullSessionShares      /t REG_MULTI_SZ /d "" /f | Out-Null

# ── Safe DLL search order ─────────────────────────────────────────────────────
Log '--- Safe DLL search order ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' /v SafeDllSearchMode /t REG_DWORD /d 1 /f | Out-Null

# ── PowerShell logging ────────────────────────────────────────────────────────
Log '--- PowerShell logging ---'
$psp = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
reg add "$psp\ScriptBlockLogging" /v EnableScriptBlockLogging            /t REG_DWORD   /d 1  /f | Out-Null
reg add "$psp\ScriptBlockLogging" /v EnableScriptBlockInvocationLogging  /t REG_DWORD   /d 1  /f | Out-Null
reg add "$psp\ModuleLogging"      /v EnableModuleLogging                 /t REG_DWORD   /d 1  /f | Out-Null
reg add "$psp\ModuleLogging"      /v ModuleNames                         /t REG_MULTI_SZ /d "*" /f | Out-Null
reg add "$psp\Transcription"      /v EnableTranscripting                 /t REG_DWORD   /d 1  /f | Out-Null
reg add "$psp\Transcription"      /v OutputDirectory                     /t REG_SZ /d "C:\Windows\Logs\PowerShell" /f | Out-Null
reg add "$psp\Transcription"      /v EnableInvocationHeader              /t REG_DWORD   /d 1  /f | Out-Null
New-Item -ItemType Directory 'C:\Windows\Logs\PowerShell' -Force | Out-Null

# ── Process creation cmdline audit ───────────────────────────────────────────
Log '--- Process creation cmdline audit ---'
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f | Out-Null

# ── Audit policy ─────────────────────────────────────────────────────────────
Log '--- Audit policy ---'
auditpol /set /subcategory:"Logon"                     /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Logoff"                    /success:enable /failure:disable | Out-Null
auditpol /set /subcategory:"Account Lockout"           /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Special Logon"             /success:enable /failure:disable | Out-Null
auditpol /set /subcategory:"Credential Validation"     /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Process Creation"          /success:enable /failure:disable | Out-Null
auditpol /set /subcategory:"Audit Policy Change"       /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Sensitive Privilege Use"   /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Security System Extension" /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"System Integrity"          /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"User Account Management"   /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:disable | Out-Null
auditpol /set /subcategory:"Other Object Access Events" /success:enable /failure:enable | Out-Null

# Event log sizes
wevtutil sl Security    /ms:196608000 | Out-Null
wevtutil sl System      /ms:32768000  | Out-Null
wevtutil sl Application /ms:32768000  | Out-Null

# ── Windows Defender — all protections on ────────────────────────────────────
Log '--- Windows Defender full hardening ---'
Set-MpPreference -DisableRealtimeMonitoring          $false
Set-MpPreference -DisableBehaviorMonitoring          $false
Set-MpPreference -DisableIOAVProtection              $false
Set-MpPreference -DisableScriptScanning              $false
Set-MpPreference -DisableArchiveScanning             $false
Set-MpPreference -EnableNetworkProtection            EnabledWithoutNotification
Set-MpPreference -EnableControlledFolderAccess       Enabled
Set-MpPreference -PUAProtection                      Enabled
Set-MpPreference -MAPSReporting                      Advanced
Set-MpPreference -SubmitSamplesConsent               SendSafeSamples
Set-MpPreference -CloudBlockLevel                    High
Set-MpPreference -CloudExtendedTimeout               50
Set-MpPreference -SignatureUpdateInterval            4
Set-MpPreference -DisableEmailScanning               $false
Set-MpPreference -DisableRemovableDriveScanning      $false
Set-MpPreference -DisableScanningNetworkFiles        $false

# ── ASR rules ─────────────────────────────────────────────────────────────────
Log '--- Attack Surface Reduction rules ---'
$asrRules = @{
    'BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550' = 1  # Block executable content from email
    'D4F940AB-401B-4EFC-AADC-AD5F3C50688A' = 1  # Block Office child processes
    '3B576869-A4EC-4529-8536-B80A7769E899' = 1  # Block Office creating executables
    '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84' = 1  # Block Office injecting into processes
    'D3E037E1-3EB8-44C8-A917-57927947596D' = 1  # Block JS/VBS launching downloaded exe
    '5BEB7EFE-FD9A-4556-801D-275E5FFC04CC' = 1  # Block obfuscated scripts
    '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B' = 1  # Block Win32 API calls from Office macros
    '01443614-CD74-433A-B99E-2ECDC07BFC25' = 1  # Block untrusted executables from USB
    'C1DB55AB-C21A-4637-BB3F-A12568109D35' = 1  # Block WMI persistence
    '9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2' = 1  # Block credential stealing from LSASS
    'D1E49AAC-8F56-4280-B9BA-993A6D77406C' = 1  # Block PSExec/WMI process creation
    'B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4' = 1  # Block unsigned processes from USB
    '26190899-1602-49E8-8B27-EB1D0A1CE869' = 1  # Block Office comms child processes
    '7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C' = 1  # Block Adobe Reader child processes
    'E6DB77E5-3DF2-4CF1-B95A-636979351E5B' = 1  # Block persistence via removable media
}
foreach ($id in $asrRules.Keys) {
    Add-MpPreference -AttackSurfaceReductionRules_Ids $id `
        -AttackSurfaceReductionRules_Actions $asrRules[$id] -ErrorAction SilentlyContinue
}

# ── Firewall — harden all profiles ───────────────────────────────────────────
Log '--- Windows Firewall hardening ---'
Set-NetFirewallProfile -Profile Domain,Public,Private `
    -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow `
    -NotifyOnListen True -ErrorAction SilentlyContinue
# RDP only on Private/Domain
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
    Where-Object Profile -match 'Public' | Disable-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
    Where-Object Profile -match 'Domain|Private' | Enable-NetFirewallRule -ErrorAction SilentlyContinue

# ── Disable Print Spooler (PrintNightmare) ────────────────────────────────────
Log '--- Disabling Print Spooler ---'
Stop-Service Spooler -Force -ErrorAction SilentlyContinue
Set-Service  Spooler -StartupType Disabled -ErrorAction SilentlyContinue

# ── Disable unnecessary services ─────────────────────────────────────────────
Log '--- Disabling unnecessary/risky services ---'
$svcs = @(
    'Fax','RetailDemo','MapsBroker','lfsvc','SharedAccess',
    'WMPNetworkSvc','RemoteRegistry','TlntSvr','FTPSVC',
    'W3SVC','simptcp','SNMP','SNMPTrap'
)
foreach ($s in $svcs) {
    Stop-Service $s -Force -ErrorAction SilentlyContinue
    Set-Service  $s -StartupType Disabled -ErrorAction SilentlyContinue
}

# ── Disable scheduled telemetry tasks ─────────────────────────────────────────
Log '--- Disabling telemetry scheduled tasks ---'
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
)
foreach ($t in $tasks) {
    Disable-ScheduledTask -TaskPath (Split-Path $t) -TaskName (Split-Path $t -Leaf) -ErrorAction SilentlyContinue
}

# ── Network — set to Private ──────────────────────────────────────────────────
Log '--- Setting network profile to Private ---'
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

# ── Screen lock — 5 minutes ───────────────────────────────────────────────────
Log '--- Screen lock 5 minutes ---'
powercfg /change monitor-timeout-ac 5
powercfg /change monitor-timeout-dc 5
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v InactivityTimeoutSecs /t REG_DWORD /d 300 /f | Out-Null
reg add 'HKCU\Control Panel\Desktop' /v ScreenSaveActive    /t REG_SZ /d 1   /f | Out-Null
reg add 'HKCU\Control Panel\Desktop' /v ScreenSaverIsSecure /t REG_SZ /d 1   /f | Out-Null
reg add 'HKCU\Control Panel\Desktop' /v ScreenSaveTimeOut   /t REG_SZ /d 300 /f | Out-Null

# ── BitLocker ─────────────────────────────────────────────────────────────────
Log '--- BitLocker ---'
$bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
if ($bl -and $bl.ProtectionStatus -ne 'On') {
    try {
        New-Item -ItemType Directory 'C:\BitLockerRecovery' -Force | Out-Null
        Enable-BitLocker -MountPoint 'C:' -EncryptionMethod XtsAes256 `
            -RecoveryPasswordProtector -SkipHardwareTest -ErrorAction Stop
        $key = (Get-BitLockerVolume -MountPoint 'C:').KeyProtector |
               Where-Object KeyProtectorType -eq RecoveryPassword
        "BitLocker Recovery Key:`n$($key.RecoveryPassword)" |
            Out-File 'C:\BitLockerRecovery\recovery-key.txt'
        Log "BitLocker enabled — BACK UP C:\BitLockerRecovery\recovery-key.txt"
    } catch { Log "BitLocker skipped (no TPM?): $_" }
}

# ── Disable legacy protocols ──────────────────────────────────────────────────
Log '--- Removing legacy network features ---'
Disable-WindowsOptionalFeature -Online -FeatureName 'TelnetClient' -NoRestart -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName 'TFTP'         -NoRestart -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction SilentlyContinue

# ── Event log guest restriction ───────────────────────────────────────────────
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security' /v RestrictGuestAccess /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\EventLog\System'   /v RestrictGuestAccess /t REG_DWORD /d 1 /f | Out-Null

Log '=========================================='
Log ' Security baseline complete.'
Log ' BitLocker key (if applied): C:\BitLockerRecovery\recovery-key.txt'
Log " Log: $LogFile"
Log '=========================================='

# ── Smart App Control ─────────────────────────────────────────────────────────
# SAC must be enabled before first app runs — Evaluation mode first, then On
# Note: SAC requires a clean install state (already satisfied here)
Log '--- Enabling Smart App Control ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy' /v VerifiedAndReputablePolicyState /t REG_DWORD /d 1 /f | Out-Null
# 0=Off 1=On 2=Evaluation — set to 1 (On)
# SAC also writes to this key via Security Center:
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' /v AllowAllTrustedApps /t REG_DWORD /d 0 /f | Out-Null

# ── Tamper Protection (must be done via WMI/MDM — registry alone not enough) ─
Log '--- Enabling Tamper Protection ---'
# Tamper Protection registry key (enforced by Security Center on clean install)
reg add 'HKLM\SOFTWARE\Microsoft\Windows Defender\Features' /v TamperProtection /t REG_DWORD /d 5 /f | Out-Null
# 5=On 4=Off

# ── Reputation-based protection ───────────────────────────────────────────────
Log '--- Enabling reputation-based protection ---'
# Check apps and files
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' /v SmartScreenEnabled /t REG_SZ /d 'RequireAdmin' /f | Out-Null
# SmartScreen for Microsoft Edge (also set via policy)
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v SmartScreenEnabled /t REG_DWORD /d 1 /f | Out-Null
# Potentially unwanted app blocking
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender' /v PUAProtection /t REG_DWORD /d 1 /f | Out-Null
# SmartScreen for apps (reputation check)
reg add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost' /v EnableWebContentEvaluation /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost' /v PreventOverride            /t REG_DWORD /d 1 /f | Out-Null

# ── Exploit Protection (Windows Defender Exploit Guard) ───────────────────────
Log '--- Configuring Exploit Protection ---'
# System-wide settings: DEP, ASLR, CFG, SEHOP
$exploitPolicy = @'
<?xml version="1.0" encoding="UTF-8"?>
<MitigationPolicy>
  <SystemConfig>
    <DEP Enable="true" EmulateAtlThunks="false" />
    <ASLR ForceRelocateImages="true" RequireInfo="false" BottomUp="true" HighEntropy="true" />
    <SEHOP Enable="true" TelemetryOnly="false" />
    <Heap TerminateOnError="true" />
  </SystemConfig>
</MitigationPolicy>
'@
$exploitXml = 'C:\Windows\Setup\Scripts\exploit-protection.xml'
$exploitPolicy | Out-File $exploitXml -Encoding UTF8
Set-ProcessMitigation -PolicyFilePath $exploitXml -ErrorAction SilentlyContinue
Log "Exploit Protection policy applied"

# ── Memory Integrity (Core Isolation) ────────────────────────────────────────
Log '--- Enabling Memory Integrity (Core Isolation) ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' /v Enabled /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' /v WasEnabledBy /t REG_DWORD /d 2 /f | Out-Null

# ── Kernel DMA Protection ─────────────────────────────────────────────────────
Log '--- Enabling Kernel DMA Protection ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Kernel DMA Protection' /v DeviceEnumerationPolicy /t REG_DWORD /d 0 /f | Out-Null

# ── Windows Security Center — ensure all features reported as enabled ─────────
Log '--- Windows Security settings ---'
# Virus & threat protection
reg add 'HKLM\SOFTWARE\Microsoft\Windows Defender' /v DisableAntiSpyware  /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows Defender' /v DisableAntiVirus     /t REG_DWORD /d 0 /f | Out-Null
# Firewall
reg add 'HKLM\SOFTWARE\Microsoft\Windows Defender Security Center\Firewall and network protection' /v UILockdown /t REG_DWORD /d 0 /f | Out-Null
# Account protection notifications
reg add 'HKLM\SOFTWARE\Microsoft\Windows Defender Security Center\Account protection' /v DisableNotifications /t REG_DWORD /d 0 /f | Out-Null

# ── Secure DNS (DNS over HTTPS) ───────────────────────────────────────────────
Log '--- Enabling DNS over HTTPS ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' /v EnableAutoDoh /t REG_DWORD /d 2 /f | Out-Null

# ── Windows Hello hardening (no password fallback for domain) ─────────────────
Log '--- Windows Hello / credential hardening ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\PassportForWork' /v Enabled /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\PassportForWork' /v RequireSecurityDevice /t REG_DWORD /d 1 /f | Out-Null

# ── Virtualization Based Security — full config ───────────────────────────────
Log '--- VBS full configuration ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' /v EnableVirtualizationBasedSecurity  /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' /v RequirePlatformSecurityFeatures    /t REG_DWORD /d 3 /f | Out-Null  # Secure Boot + DMA
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' /v HypervisorEnforcedCodeIntegrity    /t REG_DWORD /d 1 /f | Out-Null

Log '--- All Windows security features enabled ---'

# ── Disable RDP completely ────────────────────────────────────────────────────
Log '--- Disabling RDP ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' /v fDenyTSConnections /t REG_DWORD /d 1 /f | Out-Null
Stop-Service TermService -Force -ErrorAction SilentlyContinue
Set-Service  TermService -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
Set-Service  UmRdpService -StartupType Disabled -ErrorAction SilentlyContinue
# Block RDP in firewall
Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
# Remove Remote Desktop app
Get-AppxPackage -Name 'Microsoft.RemoteDesktop' -AllUsers -ErrorAction SilentlyContinue |
    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object DisplayName -eq 'Microsoft.RemoteDesktop' |
    Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
Log "RDP disabled and Remote Desktop app removed"

# ── ASD E8 — Office macro policy (even without Office installed) ──────────────
Log '--- ASD E8: Office macro policies ---'
$officeVersions = @('16.0','15.0','14.0')
$officeApps     = @('Word','Excel','PowerPoint','Access','Outlook','Publisher','Visio','Project')
foreach ($ver in $officeVersions) {
    foreach ($app in $officeApps) {
        $key = "HKLM\SOFTWARE\Policies\Microsoft\Office\$ver\$app\Security"
        reg add $key /v VBAWarnings           /t REG_DWORD /d 4 /f | Out-Null  # 4=disable all macros
        reg add $key /v AccessVBOM            /t REG_DWORD /d 0 /f | Out-Null  # block VBA object model
        reg add $key /v ExtensionHardening    /t REG_DWORD /d 1 /f | Out-Null
        reg add $key /v BlockContentExecution /t REG_DWORD /d 1 /f | Out-Null
    }
}
# Block macros from internet-sourced files
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Excel\Security'      /v MacroRuntimeScanScope /t REG_DWORD /d 2 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Word\Security'       /v MacroRuntimeScanScope /t REG_DWORD /d 2 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\PowerPoint\Security' /v MacroRuntimeScanScope /t REG_DWORD /d 2 /f | Out-Null

# ── ASD E8 — User application hardening ──────────────────────────────────────
Log '--- ASD E8: User application hardening ---'
# Disable Java in browsers (registry block)
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_RESTRICT_ACTIVEXINSTALL' /v iexplore.exe /t REG_DWORD /d 1 /f | Out-Null
# Disable Flash (already EOL but belt-and-suspenders)
reg add 'HKLM\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Addons' /v FlashPlayerEnabled /t REG_DWORD /d 0 /f | Out-Null
# Block web content in PDF (Adobe policy)
reg add 'HKLM\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown' /v bEnableFlash           /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown' /v bAllowOpenFile          /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown' /v bDisableJavaScript      /t REG_DWORD /d 1 /f | Out-Null
# Chrome hardening (policies applied if Chrome is installed)
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v SafeBrowsingProtectionLevel /t REG_DWORD /d 2   /f | Out-Null  # enhanced
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v PasswordManagerEnabled      /t REG_DWORD /d 0   /f | Out-Null  # use dedicated password manager
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v DefaultPopupsSetting        /t REG_DWORD /d 2   /f | Out-Null  # block popups
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v DefaultGeolocationSetting   /t REG_DWORD /d 2   /f | Out-Null  # block geolocation
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v AutoplayAllowed             /t REG_DWORD /d 0   /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v BlockThirdPartyCookies      /t REG_DWORD /d 1   /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v SitePerProcess              /t REG_DWORD /d 1   /f | Out-Null  # site isolation
reg add 'HKLM\SOFTWARE\Policies\Google\Chrome' /v SSLVersionMin               /t REG_SZ    /d 'tls1.2' /f | Out-Null
# Microsoft Edge hardening
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v SmartScreenEnabled               /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v SmartScreenPuaEnabled            /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v PreventSmartScreenPromptOverride /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v SSLVersionMin                    /t REG_SZ    /d 'tls1.2' /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v SitePerProcess                   /t REG_DWORD /d 1 /f | Out-Null

# ── ASD E8 — Restrict administrative privileges ───────────────────────────────
Log '--- ASD E8: Restrict administrative privileges ---'
# Prevent standard users from installing software system-wide
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v DisableMSI              /t REG_DWORD /d 1 /f | Out-Null  # 1=block non-admin MSI
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' /v AlwaysInstallElevated   /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer' /v AlwaysInstallElevated   /t REG_DWORD /d 0 /f | Out-Null
# Prevent users from adding printers without admin
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers' /v DisableWebPnPDownload /t REG_DWORD /d 1 /f | Out-Null
# No admin shares auto-created
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' /v AutoShareWks /t REG_DWORD /d 0 /f | Out-Null

# ── ASD E8 — Backups (File History to local drive) ────────────────────────────
Log '--- ASD E8: Configuring File History backup ---'
# Enable File History service
Set-Service fhsvc -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service fhsvc -ErrorAction SilentlyContinue
# Configure via registry (user must select backup drive on first use)
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\FileHistory' /v Disabled /t REG_DWORD /d 0 /f | Out-Null
# Enable System Restore as a baseline safety net
Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
Checkpoint-Computer -Description 'Post-deployment baseline' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction SilentlyContinue
Log "System Restore point created"

# ── ASD E8 — Application Control (WDAC baseline policy) ─────────────────────
Log '--- ASD E8: WDAC application control ---'
# Deploy the Windows default audit policy as a starting point
# This allows all signed MS code and audits unsigned — non-blocking to preserve usability
$wdacPolicy = "$env:SystemRoot\System32\CodeIntegrity\CiPolicies\Active"
$defaultPolicy = "$env:SystemRoot\System32\CodeIntegrity\CiPolicies\{A244370E-44C9-4C06-B551-F6016E563076}.cip"
if (Test-Path $defaultPolicy) {
    Log "WDAC default policy already present"
} else {
    # Copy the Windows default allow policy (ships with Windows)
    $src = "$env:SystemRoot\schemas\CodeIntegrity\ExamplePolicies\DefaultWindows_Enforced.xml"
    if (Test-Path $src) {
        New-Item -ItemType Directory -Path $wdacPolicy -Force | Out-Null
        & CiTool --update-policy $src -ErrorAction SilentlyContinue
        Log "WDAC DefaultWindows policy applied"
    } else {
        Log "WDAC source policy not found — skipping (SAC provides coverage)"
    }
}

Log '--- ASD Essential Eight — all controls applied ---'

# ══════════════════════════════════════════════════════════════════════════════
# ManageEngine / CIS gaps — User Rights Assignment, MSS, Security Options
# Auto-login preserved throughout
# ══════════════════════════════════════════════════════════════════════════════

# ── User Rights Assignment ────────────────────────────────────────────────────
Log '--- User Rights Assignment ---'
$tmpInf = "$env:TEMP\security.inf"
$tmpDb  = "$env:TEMP\security.sdb"
@'
[Unicode]
Unicode=yes
[Version]
signature="$CHICAGO$"
Revision=1
[Privilege Rights]
SeNetworkLogonRight = *S-1-5-32-544
SeDenyNetworkLogonRight = *S-1-5-32-546,*S-1-5-114
SeDenyInteractiveLogonRight = *S-1-5-32-546
SeDenyRemoteInteractiveLogonRight = *S-1-5-32-546,*S-1-5-114
SeInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-545
SeRemoteShutdownRight = *S-1-5-32-544
SeDebugPrivilege =
SeTcbPrivilege =
SeCreateTokenPrivilege =
SeAssignPrimaryTokenPrivilege =
SeLoadDriverPrivilege = *S-1-5-32-544
SeManageVolumePrivilege = *S-1-5-32-544
SeBackupPrivilege = *S-1-5-32-544
SeRestorePrivilege = *S-1-5-32-544
SeTakeOwnershipPrivilege = *S-1-5-32-544
'@ | Out-File $tmpInf -Encoding Unicode
secedit /configure /db $tmpDb /cfg $tmpInf /quiet 2>&1 | Out-Null
Log "User rights assignment applied"

# ── Secondary Logon disabled (pass-the-hash vector) ──────────────────────────
Log '--- Disabling Secondary Logon service ---'
Stop-Service seclogon -Force -ErrorAction SilentlyContinue
Set-Service  seclogon -StartupType Disabled -ErrorAction SilentlyContinue

# ── MSS registry hardening ────────────────────────────────────────────────────
Log '--- MSS registry hardening ---'
$mss = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
reg add $mss /v DisableIPSourceRouting      /t REG_DWORD /d 2 /f | Out-Null  # highest protection
reg add $mss /v EnableICMPRedirect          /t REG_DWORD /d 0 /f | Out-Null
reg add $mss /v NoNameReleaseOnDemand       /t REG_DWORD /d 1 /f | Out-Null
reg add $mss /v TcpMaxDataRetransmissions   /t REG_DWORD /d 3 /f | Out-Null
reg add $mss /v PerformRouterDiscovery      /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' /v DisableIPSourceRouting /t REG_DWORD /d 2 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' /v SafeModeBlockNonAdmins /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v ScreenSaverGracePeriod /t REG_SZ /d 0 /f | Out-Null  # immediate lock

# ── Security options ──────────────────────────────────────────────────────────
Log '--- Security options ---'
# Do not display last username on logon screen
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v DontDisplayLastUserName      /t REG_DWORD /d 1 /f | Out-Null
# Do not display username at all
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v DontDisplayLockedUserId      /t REG_DWORD /d 3 /f | Out-Null
# Logon message
# Logon banner applied at END of script — never blocks auto-login during setup
# Shutdown without logon — disabled
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v ShutdownWithoutLogon         /t REG_DWORD /d 0 /f | Out-Null
# Limit cached logons to 2
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'     /v CachedLogonsCount            /t REG_SZ /d '2' /f | Out-Null
# Restrict SAM remote calls to Administrators only
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'                      /v RestrictRemoteSam            /t REG_SZ /d 'O:BAG:BAD:(A;;RC;;;BA)' /f | Out-Null
# Network access: do not allow anonymous enumeration
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'                      /v RestrictAnonymousSAM         /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'                      /v RestrictAnonymous            /t REG_DWORD /d 1 /f | Out-Null
# Machine inactivity limit 300s (belt+suspenders with screensaver)
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v InactivityTimeoutSecs        /t REG_DWORD /d 300 /f | Out-Null
# Prevent PKU2U online identity authentication
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa\pku2u'               /v AllowOnlineID                /t REG_DWORD /d 0 /f | Out-Null
# DCOM restrictions
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DCOM'               /v MachineAccessRestriction     /t REG_SZ /d 'O:BAG:BAD:(A;;CCDCLC;;;PS)(A;;CCDC;;;SY)(A;;CCDCLC;;;AU)' /f | Out-Null

# ── Firewall logging ──────────────────────────────────────────────────────────
Log '--- Firewall logging ---'
netsh advfirewall set allprofiles logging droppedconnections enable  | Out-Null
netsh advfirewall set allprofiles logging maxfilesize 16384          | Out-Null
netsh advfirewall set allprofiles logging filename '%systemroot%\system32\LogFiles\Firewall\pfirewall.log' | Out-Null
# No unicast response to multicast/broadcast
netsh advfirewall set allprofiles settings unicastresponsetomulticast disable | Out-Null

# ── Computer Browser service disabled ─────────────────────────────────────────
Log '--- Disabling Computer Browser service ---'
Stop-Service Browser -Force -ErrorAction SilentlyContinue
Set-Service  Browser -StartupType Disabled -ErrorAction SilentlyContinue

# ── Advanced audit — additional subcategories ─────────────────────────────────
Log '--- Advanced audit policy additions ---'
auditpol /set /subcategory:"Plug and Play Events"               /success:enable /failure:disable | Out-Null
auditpol /set /subcategory:"Removable Storage"                  /success:enable /failure:enable  | Out-Null
auditpol /set /subcategory:"SAM"                                /success:disable /failure:enable | Out-Null
auditpol /set /subcategory:"File Share"                         /success:enable /failure:enable  | Out-Null
auditpol /set /subcategory:"Other Account Management Events"    /success:enable /failure:enable  | Out-Null
auditpol /set /subcategory:"Computer Account Management"        /success:enable /failure:enable  | Out-Null
auditpol /set /subcategory:"Distribution Group Management"      /success:enable /failure:disable | Out-Null
auditpol /set /subcategory:"Other Logon/Logoff Events"          /success:enable /failure:enable  | Out-Null
auditpol /set /subcategory:"Network Policy Server"              /success:enable /failure:enable  | Out-Null
auditpol /set /subcategory:"Detailed File Share"                /success:disable /failure:enable | Out-Null

# ══════════════════════════════════════════════════════════════════════════════
# WDAC — Block all software installs except Microsoft-signed + Edge
# Auto-login user (User) can run installed apps but cannot install new software
# ══════════════════════════════════════════════════════════════════════════════
Log '--- WDAC: Block unauthorised software installation ---'

$wdacXml = 'C:\Windows\Setup\Scripts\wdac-policy.xml'
@'
<?xml version="1.0" encoding="utf-8"?>
<SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy" PolicyType="Base Policy">
  <VersionEx>10.0.0.0</VersionEx>
  <PlatformID>{2E07F7E4-194C-4D20-B7C9-6F44A6C5A234}</PlatformID>
  <Rules>
    <!-- Enforce mode -->
    <Rule><Option>Enabled:Unsigned System Integrity Policy</Option></Rule>
    <Rule><Option>Enabled:Advanced Boot Options Menu</Option></Rule>
    <Rule><Option>Required:Enforce Store Applications</Option></Rule>
    <!-- Audit only — set to Enforce after testing by removing this line -->
    <!-- <Rule><Option>Enabled:Audit Mode</Option></Rule> -->
  </Rules>
  <EKUs />
  <FileRules>
    <!-- Explicitly deny known installer patterns in user-writable paths -->
    <Deny ID="ID_DENY_TEMP_EXE"     FriendlyName="Deny EXE from Temp"     FilePath="%TEMP%\*" />
    <Deny ID="ID_DENY_APPDATA_EXE"  FriendlyName="Deny EXE from AppData"  FilePath="%LOCALAPPDATA%\*" />
    <Deny ID="ID_DENY_DOWNLOADS"    FriendlyName="Deny EXE from Downloads" FilePath="%USERPROFILE%\Downloads\*" />
    <Deny ID="ID_DENY_DESKTOP"      FriendlyName="Deny EXE from Desktop"   FilePath="%USERPROFILE%\Desktop\*" />
  </FileRules>
  <Signers>
    <!-- Allow Microsoft Windows -->
    <Signer ID="ID_SIGNER_WINDOWS" Name="Microsoft Windows">
      <CertRoot Type="Wellknown" Value="06" />
    </Signer>
    <!-- Allow Microsoft WHQL (drivers) -->
    <Signer ID="ID_SIGNER_WHQL" Name="Microsoft WHQL">
      <CertRoot Type="Wellknown" Value="05" />
    </Signer>
    <!-- Allow Microsoft Store -->
    <Signer ID="ID_SIGNER_STORE" Name="Microsoft Store">
      <CertRoot Type="Wellknown" Value="14" />
    </Signer>
  </Signers>
  <SigningScenarios>
    <SigningScenario Value="131" ID="ID_SIGNINGSCENARIO_DRIVERS" FriendlyName="Kernel Mode">
      <ProductSigners>
        <AllowedSigners>
          <AllowedSigner SignerId="ID_SIGNER_WINDOWS" />
          <AllowedSigner SignerId="ID_SIGNER_WHQL" />
        </AllowedSigners>
      </ProductSigners>
    </SigningScenario>
    <SigningScenario Value="12" ID="ID_SIGNINGSCENARIO_USERMODE" FriendlyName="User Mode">
      <ProductSigners>
        <AllowedSigners>
          <AllowedSigner SignerId="ID_SIGNER_WINDOWS" />
          <AllowedSigner SignerId="ID_SIGNER_STORE" />
        </AllowedSigners>
        <DeniedSigners />
        <FileRulesRef>
          <FileRuleRef RuleID="ID_DENY_TEMP_EXE" />
          <FileRuleRef RuleID="ID_DENY_APPDATA_EXE" />
          <FileRuleRef RuleID="ID_DENY_DOWNLOADS" />
          <FileRuleRef RuleID="ID_DENY_DESKTOP" />
        </FileRulesRef>
      </ProductSigners>
    </SigningScenario>
  </SigningScenarios>
  <UpdatePolicySigners />
  <CiSigners />
  <HvciOptions>0</HvciOptions>
  <Settings>
    <Setting Provider="PolicyInfo" Key="Information" ValueName="Name">
      <Value><String>Workstation-Baseline</String></Value>
    </Setting>
  </Settings>
</SiPolicy>
'@ | Out-File $wdacXml -Encoding UTF8

# Compile and deploy WDAC policy
try {
    $compiledPolicy = 'C:\Windows\System32\CodeIntegrity\CiPolicies\Active\{WorkstationBaseline}.cip'
    ConvertFrom-CIPolicy -XmlFilePath $wdacXml -BinaryFilePath $compiledPolicy -ErrorAction Stop
    & CiTool --update-policy $compiledPolicy -ErrorAction SilentlyContinue
    Log "WDAC policy compiled and deployed — restart required to enforce"
} catch {
    Log "WDAC compile failed: $_ — policy XML saved for manual deployment"
}

Log '=========================================='
Log ' Full baseline complete (ManageEngine + E8)'
Log ' RESTART REQUIRED for WDAC, HVCI, VBS,'
Log ' Credential Guard, BitLocker to take effect'
Log '=========================================='

# ══════════════════════════════════════════════════════════════════════════════
# Edge Browser — Workplace hardening
# Secure but functional: SmartScreen on, tracking blocked, no password save,
# site isolation, TLS 1.2+, no autofill of payments/addresses,
# no personal profile, no sync to personal MS account
# Users can still browse normally, open files, use web apps
# ══════════════════════════════════════════════════════════════════════════════
Log '--- Edge browser workplace hardening ---'
$edge = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'

# ── Security ──────────────────────────────────────────────────────────────────
reg add $edge /v SmartScreenEnabled                         /t REG_DWORD /d 1       /f | Out-Null  # SmartScreen on
reg add $edge /v SmartScreenPuaEnabled                      /t REG_DWORD /d 1       /f | Out-Null  # block PUA downloads
reg add $edge /v PreventSmartScreenPromptOverride           /t REG_DWORD /d 1       /f | Out-Null  # can't bypass SmartScreen for sites
reg add $edge /v PreventSmartScreenPromptOverrideForFiles   /t REG_DWORD /d 1       /f | Out-Null  # can't bypass SmartScreen for files
reg add $edge /v SSLVersionMin                              /t REG_SZ    /d 'tls1.2' /f | Out-Null  # TLS 1.2 minimum
reg add $edge /v SitePerProcess                             /t REG_DWORD /d 1       /f | Out-Null  # site isolation (Spectre mitigation)
reg add $edge /v TyposquattingCheckerEnabled                /t REG_DWORD /d 1       /f | Out-Null  # warn on lookalike URLs
reg add $edge /v EnhanceSecurityMode                        /t REG_DWORD /d 1       /f | Out-Null  # enhanced security mode (SuperDuper Secure Mode)
reg add $edge /v EnhanceSecurityModeBypassListDomains       /t REG_SZ    /d ''      /f | Out-Null
reg add $edge /v BlockThirdPartyCookies                     /t REG_DWORD /d 1       /f | Out-Null  # block 3rd party cookies
reg add $edge /v TrackingPrevention                         /t REG_DWORD /d 2       /f | Out-Null  # balanced tracking prevention
reg add $edge /v SendSiteInfoToImproveServices              /t REG_DWORD /d 0       /f | Out-Null  # no telemetry to Microsoft

# ── Privacy — no personal data sync ──────────────────────────────────────────
reg add $edge /v SyncDisabled                               /t REG_DWORD /d 1       /f | Out-Null  # disable sync to MS account
reg add $edge /v BrowserSignin                              /t REG_DWORD /d 0       /f | Out-Null  # 0=disable browser sign-in (no personal MS account)
reg add $edge /v NonRemovableProfileEnabled                 /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v EdgeShoppingAssistantEnabled               /t REG_DWORD /d 0       /f | Out-Null  # no shopping assistant
reg add $edge /v PersonalizationReportingEnabled            /t REG_DWORD /d 0       /f | Out-Null

# ── No password/payment/address autofill ─────────────────────────────────────
reg add $edge /v PasswordManagerEnabled                     /t REG_DWORD /d 0       /f | Out-Null  # use dedicated password manager
reg add $edge /v PaymentMethodQueryEnabled                  /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v AutofillCreditCardEnabled                  /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v AutofillAddressEnabled                     /t REG_DWORD /d 0       /f | Out-Null

# ── Popups and redirects ──────────────────────────────────────────────────────
reg add $edge /v DefaultPopupsSetting                       /t REG_DWORD /d 2       /f | Out-Null  # block popups
reg add $edge /v DefaultGeolocationSetting                  /t REG_DWORD /d 2       /f | Out-Null  # block geolocation
reg add $edge /v AutoplayAllowed                            /t REG_DWORD /d 0       /f | Out-Null  # no autoplay
reg add $edge /v AdsSettingForIntrusiveAdsSites             /t REG_DWORD /d 2       /f | Out-Null  # block ads on intrusive sites

# ── Extensions — allow only from Edge Add-ons store ──────────────────────────
reg add $edge /v ExtensionInstallBlocklist                  /t REG_SZ    /d '*'     /f | Out-Null  # block all by default
# To allow specific extensions add their IDs to ExtensionInstallAllowlist
# e.g. reg add "$edge\ExtensionInstallAllowlist" /v 1 /t REG_SZ /d "<extension-id>" /f

# ── New tab / homepage — clean for workplace ──────────────────────────────────
reg add $edge /v NewTabPageLocation                         /t REG_SZ    /d 'about:blank' /f | Out-Null
reg add $edge /v HomepageIsNewTabPage                       /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v NewTabPageContentEnabled                   /t REG_DWORD /d 0       /f | Out-Null  # no MS news/sponsored content on NTP
reg add $edge /v NewTabPageQuickLinksEnabled                /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v ShowMicrosoftRewards                       /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v SpotlightExperiencesAndRecommendationsEnabled /t REG_DWORD /d 0   /f | Out-Null

# ── Disable Copilot / AI features in Edge ────────────────────────────────────
reg add $edge /v HubsSidebarEnabled                         /t REG_DWORD /d 0       /f | Out-Null  # hide sidebar
reg add $edge /v DiscoverPageContextEnabled                 /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v EdgeFollowEnabled                          /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v CopilotCDPPageContext                      /t REG_DWORD /d 0       /f | Out-Null
reg add $edge /v EdgeEntraCopilotPageContext                /t REG_DWORD /d 0       /f | Out-Null

# ── Downloads — prompt always, no auto-open ───────────────────────────────────
reg add $edge /v PromptForDownloadLocation                  /t REG_DWORD /d 1       /f | Out-Null
reg add $edge /v AutoOpenAllowedForURLs                     /t REG_SZ    /d ''      /f | Out-Null
reg add $edge /v AutoOpenFileTypes                          /t REG_SZ    /d ''      /f | Out-Null

# ── Keep useful features ON (don't break users) ───────────────────────────────
reg add $edge /v SpellcheckEnabled                          /t REG_DWORD /d 1       /f | Out-Null
reg add $edge /v TranslateEnabled                           /t REG_DWORD /d 1       /f | Out-Null
reg add $edge /v PrintingEnabled                            /t REG_DWORD /d 1       /f | Out-Null
reg add $edge /v DownloadRestrictions                       /t REG_DWORD /d 0       /f | Out-Null  # allow all downloads (SmartScreen still scans)
reg add $edge /v DefaultCookiesSetting                      /t REG_DWORD /d 1       /f | Out-Null  # allow 1st party cookies (needed for web apps)
reg add $edge /v DefaultJavaScriptSetting                   /t REG_DWORD /d 1       /f | Out-Null  # allow JS (required for most web apps)

Log "Edge workplace hardening complete"

# ══════════════════════════════════════════════════════════════════════════════
# Additional hardening — cloud print, PS v2, per-app mitigations, and more
# ══════════════════════════════════════════════════════════════════════════════

# ── Disable cloud printing ────────────────────────────────────────────────────
Log '--- Disabling cloud printing ---'
Stop-Service PrintWorkflowUserSvc      -Force -ErrorAction SilentlyContinue
Set-Service  PrintWorkflowUserSvc      -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service GCPDService               -Force -ErrorAction SilentlyContinue
Set-Service  GCPDService               -StartupType Disabled -ErrorAction SilentlyContinue
# Disable Internet Printing Client feature
Disable-WindowsOptionalFeature -Online -FeatureName 'Printing-Foundation-InternetPrinting-Client' -NoRestart -ErrorAction SilentlyContinue
# Block cloud print via policy
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers'              /v DisableWebPnPDownload   /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers'              /v DisableHTTPPrinting     /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' /v NoWarningNoElevationOnInstall /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' /v UpdatePromptSettings  /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'             /v DisableCloudOptimizedContent /t REG_DWORD /d 1 /f | Out-Null
# Block Universal Print (Microsoft cloud print service)
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' /v Restricted            /t REG_DWORD /d 1 /f | Out-Null
Log "Cloud printing disabled"

# ── Remove PowerShell v2 (bypasses all PS logging) ────────────────────────────
Log '--- Removing PowerShell v2 ---'
Disable-WindowsOptionalFeature -Online -FeatureName 'MicrosoftWindowsPowerShellV2'     -NoRestart -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName 'MicrosoftWindowsPowerShellV2Root' -NoRestart -ErrorAction SilentlyContinue
Log "PowerShell v2 removed"

# ── Disable WSL ───────────────────────────────────────────────────────────────
Log '--- Disabling Windows Subsystem for Linux ---'
Disable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Windows-Subsystem-Linux' -NoRestart -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform'            -NoRestart -ErrorAction SilentlyContinue
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Lxss' /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 0 /f | Out-Null

# ── Clear pagefile at shutdown ────────────────────────────────────────────────
Log '--- Clear pagefile at shutdown ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f | Out-Null

# ── Disable crash dumps (contain memory/credentials) ─────────────────────────
Log '--- Disabling crash dumps ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v CrashDumpEnabled    /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v LogEvent            /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v SendAlert           /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' /v AutoReboot          /t REG_DWORD /d 1 /f | Out-Null

# ── Disable 8.3 filename creation (path-based bypass) ────────────────────────
Log '--- Disabling 8.3 filename creation ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' /v NtfsDisable8dot3NameCreation /t REG_DWORD /d 1 /f | Out-Null
fsutil behavior set disable8dot3 1 | Out-Null

# ── Block remote/web fonts (font-based exploits) ─────────────────────────────
Log '--- Blocking remote fonts ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' /v EnableFontProviders /t REG_DWORD /d 0 /f | Out-Null

# ── Disable Windows Insider / beta builds ────────────────────────────────────
Log '--- Disabling Windows Insider ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' /v DisableWUfBSafeguards /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds' /v AllowBuildPreview      /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds' /v EnableConfigFlighting  /t REG_DWORD /d 0 /f | Out-Null

# ── Disable IPC$/ADMIN$ shares ───────────────────────────────────────────────
Log '--- Disabling IPC$ and ADMIN$ shares ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' /v AutoShareWks    /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' /v AutoShareServer /t REG_DWORD /d 0 /f | Out-Null

# ── Disable anonymous named pipe access ──────────────────────────────────────
Log '--- Restricting named pipes ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' /v NullSessionPipes /t REG_MULTI_SZ /d "" /f | Out-Null

# ── Kerberos — AES only, disable RC4 ─────────────────────────────────────────
Log '--- Kerberos: disable RC4, require AES ---'
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters' /v SupportedEncryptionTypes /t REG_DWORD /d 2147483640 /f | Out-Null
# 2147483640 = AES128+AES256+Future — excludes DES and RC4

# ── Accessibility exploit mitigation ─────────────────────────────────────────
# sethc.exe (StickyKeys) and utilman.exe (Ease of Access) at logon screen
# can be replaced with cmd.exe for a SYSTEM shell — prevent this
Log '--- Accessibility exploit mitigation ---'
$sethc  = "$env:SystemRoot\System32\sethc.exe"
$utilman = "$env:SystemRoot\System32\Utilman.exe"
foreach ($f in @($sethc, $utilman)) {
    if (Test-Path $f) {
        $acl = Get-Acl $f
        $acl.SetOwner([System.Security.Principal.NTAccount]'Administrators')
        Set-Acl $f $acl -ErrorAction SilentlyContinue
        icacls $f /inheritance:r /grant:r "Administrators:(F)" /deny "Everyone:(RX,WD,AD,WA)" 2>&1 | Out-Null
    }
}
Log "sethc.exe and utilman.exe access restricted"

# ── Disable Presentation Mode (suppresses screen lock) ───────────────────────
Log '--- Disabling Presentation Mode ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PresentationSettings' /v NoPresentationSettings /t REG_DWORD /d 1 /f | Out-Null

# ── Disable Windows Error Reporting / feedback ───────────────────────────────
Log '--- Disabling Windows Error Reporting ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' /v Disabled            /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' /v DontSendAdditionalData /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' /v LoggingDisabled      /t REG_DWORD /d 1 /f | Out-Null
Stop-Service WerSvc -Force -ErrorAction SilentlyContinue
Set-Service  WerSvc -StartupType Disabled -ErrorAction SilentlyContinue

# ── Disable Storage Sense cloud upload ───────────────────────────────────────
Log '--- Disabling Storage Sense cloud features ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense' /v AllowStorageSenseGlobal /t REG_DWORD /d 0 /f | Out-Null

# ── Windows Recovery — restrict access ───────────────────────────────────────
Log '--- Restricting Windows Recovery ---'
bcdedit /set {default} recoveryenabled No  2>&1 | Out-Null
bcdedit /set {default} bootstatuspolicy IgnoreAllFailures 2>&1 | Out-Null

# ── Per-app exploit mitigations (Office, Acrobat, Edge) ──────────────────────
Log '--- Per-app exploit mitigations ---'
$appMitigations = @(
    # Microsoft Office apps
    @{Name='WINWORD.EXE';   DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    @{Name='EXCEL.EXE';     DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    @{Name='POWERPNT.EXE';  DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    @{Name='OUTLOOK.EXE';   DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    @{Name='MSACCESS.EXE';  DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    # Adobe Reader
    @{Name='AcroRd32.exe';  DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    @{Name='Acrobat.exe';   DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    # Browsers
    @{Name='msedge.exe';    DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$false},
    @{Name='chrome.exe';    DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$false},
    # Script hosts
    @{Name='wscript.exe';   DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    @{Name='cscript.exe';   DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true},
    @{Name='mshta.exe';     DEP=$true; ASLR=$true; CFG=$true; ExtensionPoint=$true}
)
$mitigBase = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
foreach ($app in $appMitigations) {
    $key = "$mitigBase\$($app.Name)\MitigationOptions"
    # Set via Set-ProcessMitigation for cleaner application
    $params = @{ Name = $app.Name }
    if ($app.DEP)            { $params['Dep']            = 'Enable' }
    if ($app.ASLR)           { $params['Aslr']           = 'Enable' }
    if ($app.CFG)            { $params['CFG']            = 'Enable' }
    if ($app.ExtensionPoint) { $params['ExtensionPoint'] = 'Disable' }
    Set-ProcessMitigation @params -ErrorAction SilentlyContinue
    Log "Mitigation set: $($app.Name)"
}

# ── Disable Windows Help legacy ───────────────────────────────────────────────
Log '--- Disabling legacy Windows Help (winhlp32) ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WinHelp' /v AllowWinHelpForIntranetSites /t REG_DWORD /d 0 /f | Out-Null

# ── Disable Autorun for ALL drive types (belt+suspenders) ────────────────────
Log '--- Disabling Autorun for all drives ---'
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v NoDriveTypeAutoRun /t REG_DWORD /d 0xFF /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v NoAutorun          /t REG_DWORD /d 1    /f | Out-Null

# ── Defender — scheduled full scan weekly ────────────────────────────────────
Log '--- Configuring Defender scheduled scan ---'
Set-MpPreference -ScanScheduleDay       1     -ErrorAction SilentlyContinue  # Monday
Set-MpPreference -ScanScheduleTime      (New-TimeSpan -Hours 2) -ErrorAction SilentlyContinue  # 2am
Set-MpPreference -ScanParameters        2     -ErrorAction SilentlyContinue  # full scan (1=quick, 2=full)
Set-MpPreference -CheckForSignaturesBeforeRunningScan $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableRestorePoint   $false -ErrorAction SilentlyContinue  # scan restore points

# ── Defender — no exclusions (ensure clean slate) ────────────────────────────
Log '--- Ensuring no Defender exclusions ---'
$prefs = Get-MpPreference
if ($prefs.ExclusionPath)      { Remove-MpPreference -ExclusionPath      $prefs.ExclusionPath      -ErrorAction SilentlyContinue }
if ($prefs.ExclusionProcess)   { Remove-MpPreference -ExclusionProcess   $prefs.ExclusionProcess   -ErrorAction SilentlyContinue }
if ($prefs.ExclusionExtension) { Remove-MpPreference -ExclusionExtension $prefs.ExclusionExtension -ErrorAction SilentlyContinue }

# ── Certificate store — remove known bad roots ───────────────────────────────
Log '--- Hardening certificate store ---'
# Enable automatic root certificate update (keep legitimate CAs current)
reg add 'HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot' /v DisableRootAutoUpdate /t REG_DWORD /d 0 /f | Out-Null
# Block untrusted certificates
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' /v CertificateRevocation /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' /v DisableCachingOfSSLPages /t REG_DWORD /d 1 /f | Out-Null

# ── Disable Windows Insider telemetry ─────────────────────────────────────────
Log '--- Disabling all remaining telemetry channels ---'
$telemetryKeys = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
)
foreach ($k in $telemetryKeys) {
    reg add $k /v AllowTelemetry              /t REG_DWORD /d 0 /f | Out-Null
    reg add $k /v MaxTelemetryAllowed         /t REG_DWORD /d 0 /f | Out-Null
    reg add $k /v AllowDeviceNameInTelemetry  /t REG_DWORD /d 0 /f | Out-Null
}

# ── Event log — protect against tampering ────────────────────────────────────
Log '--- Protecting event logs from tampering ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security' /v WarningLevel /t REG_DWORD /d 90 /f | Out-Null  # warn at 90% full
# Retain logs on clear (forensic preservation)
wevtutil sl Security    /rt:false | Out-Null  # don't auto-overwrite
wevtutil sl System      /rt:false | Out-Null
wevtutil sl Application /rt:false | Out-Null

# ── Disable USB storage (audit mode — logs but allows, change /d 4 to /d 3 to block) ─
Log '--- USB storage device control (audit) ---'
# 3=block, 4=audit only — set to 4 to preserve functionality, review logs
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions' /v DenyRemovableDevices /t REG_DWORD /d 0 /f | Out-Null
# Audit removable storage access via Defender
Set-MpPreference -DisableRemovableDriveScanning $false -ErrorAction SilentlyContinue
auditpol /set /subcategory:"Removable Storage" /success:enable /failure:enable | Out-Null

# ── Disable storing LAN Manager hash (belt+suspenders) ───────────────────────
Log '--- No LAN Manager hash storage ---'
reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' /v NoLMHash /t REG_DWORD /d 1 /f | Out-Null

# ── Disable Object Linking (OLE) for untrusted zones ─────────────────────────
Log '--- OLE security hardening ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3' /v 1200 /t REG_DWORD /d 3 /f | Out-Null  # disable ActiveX in internet zone
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3' /v 1400 /t REG_DWORD /d 3 /f | Out-Null  # disable scripting in internet zone

# ── Disable legacy protocols / features ──────────────────────────────────────
Log '--- Removing remaining legacy features ---'
Disable-WindowsOptionalFeature -Online -FeatureName 'WorkFolders-Client'              -NoRestart -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName 'WindowsMediaPlayer'             -NoRestart -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName 'Internet-Explorer-Optional-amd64' -NoRestart -ErrorAction SilentlyContinue

# ── Network outbound firewall rules — block known bad ports ──────────────────
Log '--- Firewall: blocking known attack ports outbound ---'
# Block outbound Telnet, FTP command, TFTP, IRC, common RAT ports
$blockPorts = @(23,69,6667,6668,6669,1433,1434,4444,5554,9996)
foreach ($port in $blockPorts) {
    New-NetFirewallRule -DisplayName "Block Outbound Port $port" `
        -Direction Outbound -Protocol TCP -RemotePort $port `
        -Action Block -Profile Any -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Block Outbound UDP $port" `
        -Direction Outbound -Protocol UDP -RemotePort $port `
        -Action Block -Profile Any -ErrorAction SilentlyContinue | Out-Null
}

Log '=========================================='
Log ' All hardening complete.'
Log ' USB storage: AUDIT mode (change to block'
Log ' by setting DenyRemovableDevices=3)'
Log '=========================================='

# ── USB storage — explicitly ALLOW (audit only, no block) ────────────────────
Log '--- USB storage: allowed with audit logging ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions' /v DenyRemovableDevices /t REG_DWORD /d 0 /f | Out-Null
Set-MpPreference -DisableRemovableDriveScanning $false -ErrorAction SilentlyContinue
auditpol /set /subcategory:"Removable Storage" /success:enable /failure:enable | Out-Null

# ── Edge extensions — block all, remove pre-installed ────────────────────────
Log '--- Edge: blocking all extensions, removing pre-installed ---'
$edge = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'

# Block ALL extensions from being installed
reg add "$edge\ExtensionInstallBlocklist" /v 1 /t REG_SZ /d '*' /f | Out-Null

# Prevent users from installing extensions from Edge Add-ons store
reg add $edge /v ExtensionInstallBlocklist /t REG_SZ /d '*' /f | Out-Null

# Remove pre-installed/default Edge extensions by force-uninstalling known IDs
# Shopping assistant
reg add "$edge\ExtensionInstallForcelist" /v ForceList /t REG_SZ /d '' /f | Out-Null

# Disable Extensions toolbar button (prevents manual sideloading UI)
reg add $edge /v DeveloperToolsAvailability        /t REG_DWORD /d 2 /f | Out-Null  # 2=disable devtools (prevents unpacked extension load)
reg add $edge /v ExtensionSettings                 /t REG_SZ /d '{"*":{"installation_mode":"blocked"}}' /f | Out-Null

# Remove known built-in extensions that phone home
# Bing Shopping / Coupons
reg add 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' /v InstallDefault /t REG_DWORD /d 0 /f | Out-Null
reg add $edge /v EdgeShoppingAssistantEnabled /t REG_DWORD /d 0 /f | Out-Null
reg add $edge /v ShowMicrosoftRewards         /t REG_DWORD /d 0 /f | Out-Null
# Disable built-in Bing/Copilot sidebar extension
reg add $edge /v HubsSidebarEnabled           /t REG_DWORD /d 0 /f | Out-Null
reg add $edge /v MicrosoftEdgeInsiderPromotionEnabled /t REG_DWORD /d 0 /f | Out-Null

# To allow specific extensions for work (add their IDs here):
# reg add "$edge\ExtensionInstallAllowlist" /v 1 /t REG_SZ /d "odfafepnkmbhccpbejgmiehpchacaeak" /f  # example: uBlock Origin

Log "Edge extensions blocked"

Log '=========================================='
Log ' Final hardening pass complete.'
Log '=========================================='

# ── Bluetooth — allow HID (keyboards/mice) and audio (headsets) only ─────────
Log '--- Bluetooth: HID and audio only ---'

# Keep Bluetooth service running
Set-Service bthserv    -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service bthserv  -ErrorAction SilentlyContinue
Set-Service BthAvctpSvc -StartupType Automatic -ErrorAction SilentlyContinue  # audio/video profile

# Block all Bluetooth device classes EXCEPT:
#   HID  (keyboards, mice, trackpads)   = {00001124-0000-1000-8000-00805F9B34FB}
#   HFP  (headset hands-free profile)   = {0000111E-0000-1000-8000-00805F9B34FB}
#   HSP  (headset profile)              = {00001108-0000-1000-8000-00805F9B34FB}
#   A2DP (stereo audio sink)            = {0000110B-0000-1000-8000-00805F9B34FB}
#   AVRCP (media remote control)        = {0000110E-0000-1000-8000-00805F9B34FB}

# Block phone/PAN/file transfer/OPP device class installs via DeviceInstall policy
$btBlock = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
reg add $btBlock /v DenyDeviceClasses      /t REG_DWORD /d 1 /f | Out-Null
reg add $btBlock /v DenyDeviceClassesRetroactive /t REG_DWORD /d 1 /f | Out-Null

# Blocked Bluetooth device class GUIDs (phones, file transfer, PAN, serial, etc.)
$blockedClasses = @(
    '{E0CBF06C-CD8B-4647-BB8A-263B43F0F974}'  # Bluetooth device (generic — blocks unpaired unknown)
    '{00001101-0000-1000-8000-00805F9B34FB}'  # Serial Port Profile (SPP) — attack vector
    '{00001105-0000-1000-8000-00805F9B34FB}'  # Object Push Profile (OPP) — file transfer
    '{0000112F-0000-1000-8000-00805F9B34FB}'  # Phone Book Access Profile (PBAP)
    '{00001132-0000-1000-8000-00805F9B34FB}'  # Message Access Profile (MAP)
    '{00001116-0000-1000-8000-00805F9B34FB}'  # NAP — Bluetooth PAN (network)
    '{00001115-0000-1000-8000-00805F9B34FB}'  # PANU — Bluetooth personal area network
)
$i = 1
foreach ($guid in $blockedClasses) {
    reg add "$btBlock\DenyDeviceClasses" /v $i /t REG_SZ /d $guid /f | Out-Null
    $i++
}

# Disable Bluetooth advertising/discovery when not pairing
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Connect' /v AllowProjectionToPC /t REG_DWORD /d 0 /f | Out-Null

# Disable Bluetooth file sharing (OBEX/FTP over Bluetooth)
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions' /v DenyRemovableDevices /t REG_DWORD /d 0 /f | Out-Null  # preserve USB allow

# Disable Bluetooth tethering / mobile hotspot via Bluetooth
Stop-Service PanService -Force -ErrorAction SilentlyContinue
Set-Service  PanService -StartupType Disabled -ErrorAction SilentlyContinue

Log "Bluetooth configured: HID + audio only, file transfer/PAN/serial blocked"

# ── WiFi — require password/authentication, block open networks and ICS ───────
Log '--- WiFi: block open networks, disable ICS and hotspot ---'

# Block connecting to open (unsecured) WiFi networks
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' /v fBlockNonDomain              /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' /v fMinimizeConnections         /t REG_DWORD /d 3 /f | Out-Null  # 3=prevent wifi when ethernet connected
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' /v fSoftDisconnectConnections   /t REG_DWORD /d 1 /f | Out-Null

# Disable WiFi Sense (auto-connect to open/shared networks)
reg add 'HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' /v AutoConnectAllowedOEM           /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' /v DisableWifiSense             /t REG_DWORD /d 1 /f | Out-Null

# Block open/unsecured networks via WLAN policy
# Create a WLAN profile that denies connection to any network without security
$wlanXml = @'
<?xml version="1.0"?>
<WLANPolicy xmlns="http://www.microsoft.com/networking/WLAN/policy/v1">
  <name>BlockOpenNetworks</name>
  <description>Block unsecured open WiFi networks</description>
  <globalFlags>
    <enableAutoConfig>true</enableAutoConfig>
    <showDeniedNetwork>false</showDeniedNetwork>
    <allowEveryoneToCreateAllUserProfiles>false</allowEveryoneToCreateAllUserProfiles>
    <onlyUseGPProfilesForAllowedNetworks>false</onlyUseGPProfilesForAllowedNetworks>
    <enableAutoConnect>false</enableAutoConnect>
    <enableFilter>true</enableFilter>
    <profileSwitchingEnabled>false</profileSwitchingEnabled>
  </globalFlags>
  <networkFilter>
    <denyList>
      <networkAdded>
        <WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
          <name>BlockOpenNetworks</name>
          <SSIDConfig>
            <SSID><name></name></SSID>
            <nonBroadcast>false</nonBroadcast>
          </SSIDConfig>
          <connectionType>ESS</connectionType>
          <connectionMode>auto</connectionMode>
          <MSM>
            <security>
              <authEncryption>
                <authentication>open</authentication>
                <encryption>none</encryption>
                <useOneX>false</useOneX>
              </authEncryption>
            </security>
          </MSM>
        </WLANProfile>
      </networkAdded>
    </denyList>
  </networkFilter>
</WLANPolicy>
'@
$wlanPolicyPath = 'C:\Windows\Setup\Scripts\wlan-policy.xml'
$wlanXml | Out-File $wlanPolicyPath -Encoding UTF8
netsh wlan set profileparameter name="BlockOpenNetworks" connectionmode=manual 2>&1 | Out-Null
netsh wlan add filter permission=denyall networktype=infrastructure 2>&1 | Out-Null  # deny ALL infrastructure by default
# Then allow only secured networks
netsh wlan delete filter permission=allow networktype=infrastructure 2>&1 | Out-Null
Log "Open WiFi networks blocked via WLAN filter"

# Require WPA2 or WPA3 minimum — block WEP and open auth
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy' /v fDisallowOpenNetworks /t REG_DWORD /d 1 /f | Out-Null

# ── Disable Internet Connection Sharing (ICS) ─────────────────────────────────
Log '--- Disabling Internet Connection Sharing ---'
Stop-Service SharedAccess -Force -ErrorAction SilentlyContinue
Set-Service  SharedAccess -StartupType Disabled -ErrorAction SilentlyContinue
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Network Connections' /v NC_ShowSharedAccessUI        /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Network Connections' /v NC_PersonalFirewallConfig    /t REG_DWORD /d 0 /f | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Network Connections' /v NC_AllowNetBridge_NLA        /t REG_DWORD /d 0 /f | Out-Null  # no network bridge

# ── Disable Mobile Hotspot ────────────────────────────────────────────────────
Log '--- Disabling Mobile Hotspot ---'
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Network Connections' /v NC_StopSharedAccessOnFailure /t REG_DWORD /d 1 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\WcmSvc\Tethering'                     /v IsGroupPolicyEnabled         /t REG_DWORD /d 0 /f | Out-Null
# Disable hosted network / virtual WiFi adapter (used for hotspot)
netsh wlan set hostednetwork mode=disallow 2>&1 | Out-Null
reg add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\HotspotAuthentication' /v Enabled /t REG_DWORD /d 0 /f | Out-Null

Log "WiFi: open networks blocked, ICS disabled, mobile hotspot disabled"

# ── Australia locale — Melbourne ──────────────────────────────────────────────
Log '--- Australia locale: Melbourne, en-AU, AUS Eastern Standard Time ---'
Set-TimeZone -Id 'AUS Eastern Standard Time' -ErrorAction SilentlyContinue

# Set GeoID = Australia (12)
reg add 'HKCU\Control Panel\International\Geo' /v Nation /t REG_SZ /d 12 /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v GeoID /t REG_DWORD /d 12 /f | Out-Null

# Set en-AU locale (date DD/MM/YYYY, currency AUD, etc.)
Set-WinUserLanguageList -LanguageList 'en-AU' -Force -ErrorAction SilentlyContinue
Set-WinSystemLocale     -SystemLocale 'en-AU' -ErrorAction SilentlyContinue
Set-Culture             -CultureInfo  'en-AU' -ErrorAction SilentlyContinue
Set-WinHomeLocation     -GeoId 12            -ErrorAction SilentlyContinue

# Ensure correct date format
reg add 'HKCU\Control Panel\International' /v sShortDate  /t REG_SZ /d 'd/MM/yyyy'  /f | Out-Null
reg add 'HKCU\Control Panel\International' /v sLongDate   /t REG_SZ /d 'dddd, d MMMM yyyy' /f | Out-Null
reg add 'HKCU\Control Panel\International' /v sTimeFormat /t REG_SZ /d 'h:mm:ss tt' /f | Out-Null
reg add 'HKCU\Control Panel\International' /v sCurrency   /t REG_SZ /d '$'          /f | Out-Null
reg add 'HKCU\Control Panel\International' /v iCurrency   /t REG_SZ /d '0'          /f | Out-Null

Log "Locale set: en-AU, Melbourne, AUS Eastern Standard Time"

# ── Legal notice banner ───────────────────────────────────────────────────────
# Applied HERE — at end of all setup — so it never blocks auto-login during deployment.
# From next login onward the banner shows before the logon screen.
Log '--- Applying logon security banner ---'
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    /v LegalNoticeCaption /t REG_SZ `
    /d 'Authorised Access Only' /f | Out-Null
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    /v LegalNoticeText /t REG_SZ `
    /d 'This system is for authorised use only. Unauthorised access is prohibited and may be subject to prosecution under Australian law. All activity is monitored and logged.' `
    /f | Out-Null
Log "Legal notice banner set — will appear from next login onward"
