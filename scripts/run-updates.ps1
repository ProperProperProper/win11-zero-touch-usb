# 1. Install the module (if not already installed)
Install-Module -Name PSWindowsUpdate -Force -Confirm:$false

# 2. Set execution policy to allow scripts
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# 3. Import the module
Import-Module PSWindowsUpdate

# 4. Check, download, and install all available updates
# -AcceptAll: Automatically accepts all updates and licence agreements
# -AutoReboot: Restarts the computer if required by the updates
# -Install: Triggers the installation process
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -AutoReboot
