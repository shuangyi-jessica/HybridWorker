# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Install the correct modules
# [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.208 -Force
Import-PackageProvider -Name NuGet -RequiredVersion 2.8.5.201
Install-Module -Name Az.Accounts -MaximumVersion 2.12.1 -Scope AllUsers -Repository PSGallery -Force
Install-Module -Name Az -MaximumVersion 9.6.0 -Scope AllUsers -Repository PSGallery -Force
Uninstall-Module -Name Az.Accounts -RequiredVersion 2.12.3 -Force

# Connect to Azure with system-assigned managed identity
Import-Module -Name Az.Accounts -MaximumVersion 2.12.1 -Force
#Import-Module -Name Az.Accounts -Force
Connect-AzAccount -Identity -ErrorAction Stop
$RGName = 'hwnetworkresources_rg'
Get-AzResource -ResourceGroupName $RGName | Format-Table