# ============================================
# Windows Defender Configuration Script
# Run as Administrator in PowerShell
# ============================================

# --- Real-Time Protection ---
Set-MpPreference -DisableRealtimeMonitoring $false
Set-MpPreference -DisableBehaviorMonitoring $false
Set-MpPreference -DisableIOAVProtection $false
Set-MpPreference -DisableScriptScanning $false

# --- Cloud Protection (improves detection) ---
Set-MpPreference -MAPSReporting Advanced
Set-MpPreference -SubmitSamplesConsent SendAllSamples

# --- PUA (Potentially Unwanted App) Blocking ---
Set-MpPreference -PUAProtection Enabled

# --- Network Protection (blocks malicious sites/IPs) ---
Set-MpPreference -EnableNetworkProtection Enabled

# --- Controlled Folder Access (ransomware protection) ---
Set-MpPreference -EnableControlledFolderAccess Enabled

# --- Scan Settings ---
Set-MpPreference -ScanScheduleQuickScanTime 02:00:00
Set-MpPreference -RemediationScheduleDay Everyday
Set-MpPreference -SignatureUpdateInterval 4

# --- Attack Surface Reduction Rules ---
$asrRules = @(
    "BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550",  # Block executable content from email
    "D4F940AB-401B-4EFC-AADC-AD5F3C50688A",  # Block Office apps creating child processes
    "3B576869-A4EC-4529-8536-B80A7769E899",  # Block Office apps creating executables
    "75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84",  # Block Office apps injecting into processes
    "D3E037E1-3EB8-44C8-A917-57927947596D",  # Block JS/VBS launching executables
    "5BEB7EFE-FD9A-4556-801D-275E5FFC04CC",  # Block obfuscated scripts
    "92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B",  # Block Win32 API calls from macros
    "01443614-CD74-433A-B99E-2ECDC07BFC25",  # Block executables from USB
    "56a863a9-875e-4185-98a7-b882c64b5ce5",  # Block abuse of exploited vulnerable drivers
    "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c"   # Block Adobe Reader child processes
)
foreach ($rule in $asrRules) {
    Add-MpPreference -AttackSurfaceReductionRules_Ids $rule -AttackSurfaceReductionRules_Actions Enabled
}

# --- SmartScreen (via Registry) ---
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "RequireAdmin" -Force

# --- Force signature update now ---
Update-MpSignature

# --- Verify config ---
Write-Host "`n=== Current Defender Status ===" -ForegroundColor Green
Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled, OnAccessProtectionEnabled
Write-Host "`n=== Preferences ===" -ForegroundColor Green
Get-MpPreference | Select-Object PUAProtection, EnableNetworkProtection, EnableControlledFolderAccess, MAPSReporting, SubmitSamplesConsent

Write-Host "`nDone. Defender is hardened." -ForegroundColor Cyan