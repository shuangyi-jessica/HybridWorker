Connect-AzAccount -Identity -ErrorAction Stop
# Credential for VM creation
$UserName = 'win-vm'
$Password = ConvertTo-SecureString 'win-vm_Jessica' -AsPlainText -Force

$myVM = 'myHybridWorker'
$vmResourceGroup = 'hybridworkervm_rg'
$networkResourceGroup = 'hwnetworkresources_rg'
$vmLocation = 'westeurope'
$subscriptionId = 'a6f140c7-d601-4fd5-bfb7-a2d3871a91c8'
$automationAccountName = "hwautomation"
$hybridWorkerGroupName = "hwg"

# =============================================
# Check whether NIC has been created
# =============================================
$nicName = 'hw_nic'
# Specify VM OsDisk name
$vmDiskName = ('' + $myVM.ToLower() + '_OsDisk')
$vmDiskSize = '127'
$vmDiskaccountType = 'Standard_LRS'
# Specify VM creation configuration
$vmURL = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($vmResourceGroup)/providers/Microsoft.Compute/virtualMachines/$($myVM)?api-version=2018-10-01"
$vmPayload = @"
{
  "location": "$vmLocation",
  "name": "$myVM",
  "identity":{
    "type":"SystemAssigned"
  },
  "properties": {
    "hardwareProfile": {
      "vmSize": "Standard_B2ms"
    },
    "storageProfile": {
      "imageReference":{
        "sku":"2022-Datacenter",
        "publisher":"MicrosoftWindowsServer",
        "version":"latest",
        "offer":"WindowsServer"
      },
      "osDisk": {
        "name": "$vmDiskName",
        "diskSizeGB": "$vmDiskSize",
        "managedDisk": {
          "storageAccountType": "$vmDiskaccountType"
        },
        "osType": "Windows",
        "createOption": "FromImage",
        "caching": "ReadWrite"
      }
    },
    "osProfile": {
      "adminUsername": "$UserName",
      "computerName": "$myVM",
      "adminPassword": "$Password"
    },
    "networkProfile": {
      "networkInterfaces": [
        {
          "id": "/subscriptions/$subscriptionId/resourceGroups/$networkResourceGroup/providers/Microsoft.Network/networkInterfaces/$nicName",
          "properties": {
            "primary": true
          }
        }
      ]
    }
  }
}
"@
$NICUri = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($networkResourceGroup)/providers/Microsoft.Network/networkInterfaces/$($nicName)?api-version=2022-11-01"
try{
    $NIC = invoke-azrestmethod -uri $NICUri -method 'GET' -ErrorAction Stop
    Write-Output "Checking if NIC was already created"
    $NIC
    if ($NIC.StatusCode -in 200..204){
        Write-Output "NIC exists."
        # Create the virtual machine
        try{
          $vmCreation = Invoke-AzRestMethod -Uri $vmURL -Method PUT -Payload $vmPayload -ErrorAction Stop
          if ($vmCreation.StatusCode -in 200..204){
            Write-Output "Virtual machine $myVM is created successfully."
            # Get Virtual machine resource id
            try{
              $vmRes = invoke-azrestmethod -uri $vmURL -method 'GET' -ErrorAction Stop
              if ($vmRes.StatusCode -in 200..204){
                $vmObject = $vmRes.Content | convertfrom-json | Select-Object -Property 'id'
                $vmResourceId = $vmObject.id
              }else{
                Write-Output "Encountered error when getting VM resource id."
                $vmRes
              }
            }catch{
              $_
            }

          }else{
            Write-Output "Virtual machine creation encountered error."
            $vmCreation
            Exit 3
          }
        }catch{
          $_
        }
}else{
  Write-Output "NIC doesn't exist."
  Exit 4
  }
}catch{
  $_
}

# =======================================
# Deploy extension-based hybrid worker
# =======================================
# Generate HRW id
$hrwId = (New-Guid).Guid
# Create HRW URL
$hwuri = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($networkResourceGroup)/providers/Microsoft.Automation/automationAccounts/$($automationAccountName)/hybridRunbookWorkerGroups/$($hybridWorkerGroupName)/hybridRunbookWorkers/$($hrwId)?api-version=2021-06-22"
$hwPayload = @"
{
  "properties": {
    "vmResourceId": "$vmResourceId"
  }
}
"@

Write-Output "Connecting the VM to the existing hybrid worker group..."
# Write-Output $hwuri
# Write-Output $hwPayload
$aauri = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$networkResourceGroup/providers/Microsoft.Automation/automationAccounts/$($automationAccountName)?api-version=2021-06-22"
$automation = Invoke-AzRestMethod -uri $aauri -method 'GET'
$automationContent = $automation.Content | Convertfrom-json
$automationAccountUri = $automationContent.properties.automationHybridServiceUrl
$hwExtensionURI = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($vmResourceGroup)/providers/Microsoft.Compute/virtualMachines/$($myVM)/extensions/HybridWorkerExtension?api-version=2021-11-01"
$hwExtensionPayload = @"
{
  "location": "westeurope",
  "properties": {
    "publisher": "Microsoft.Azure.Automation.HybridWorker",
    "type": "HybridWorkerForWindows",
    "typeHandlerVersion": 1.1,
    "autoUpgradeMinorVersion" : "$false",
    "enableAutomaticUpgrade" : "$false",
    "settings": {
      "AutomationAccountURL": "$automationAccountUri"
    }
  }
}
"@

try {
  $hwCreation = Invoke-AzRestMethod -Uri $hwuri -Method PUT -Payload $hwPayload -ErrorAction Stop
  if ($hwCreation.StatusCode -in 200..204) {
    Write-Output "Hybrid worker is added successfully."
    # Add hybrid worker extension
    Write-Output "Installing the hybrid worker extension on the VM..."
    # Write-Output $hwExtensionPayload
    $hwExtension = Invoke-AzRestMethod -Uri $hwExtensionURI -Method PUT -Payload $hwExtensionPayload -ErrorAction Stop
    if ($hwExtension.StatusCode -in 200..204) {
      Write-Output "Hybrid worker extension is added successfully."
    }
    else {
      Write-Output "Encountered error when adding hybrid worker extension."
      $hwExtension
      Exit 2
    }
  }
  else {
    Write-Output "Encountered error when adding hybrid worker."
    $hwCreation
    Exit 1
  }
}
catch {
  $_
}

# To Confirm HRW Creation, make a get
# $output = Invoke-AzRestMethod -Uri $hwuri -Method GET -Payload $hwPayload -ErrorAction Stop
# Write-Output "Hybrid worker information is as following."
# Write-Output $output.Content

##=====================================================================
# Check the hybrid worker status and start RunbookTask
##=====================================================================
# Define the variables of RunbookTask
$runbookTask = "RunbookTask"
$runbookDelection = "RemoveHW"
$hybridWorkerName = "hwg"
$randomValue = Get-Random -Minimum 1 -Maximum 999
$jobName1 = ('' + $runbookTask.ToLower() + $randomValue )
$randomValue = Get-Random -Minimum 1 -Maximum 999
$jobName2 = ('' + $runbookDelection.ToLower() + $randomValue )
$runbookUri = "https://management.azure.com/subscriptions/a6f140c7-d601-4fd5-bfb7-a2d3871a91c8/resourceGroups/hwnetworkresources_rg/providers/Microsoft.Automation/automationAccounts/hwautomation/jobs/$($jobName1)?api-version=2022-08-08"
$runbookPayload = @"
{
  "properties": {
    "runbook": {
      "name": "$runbookTask"
    },
    "runOn": "$hybridWorkerName"
  }
}
"@
$runbookDeletionUri = "https://management.azure.com/subscriptions/a6f140c7-d601-4fd5-bfb7-a2d3871a91c8/resourceGroups/hwnetworkresources_rg/providers/Microsoft.Automation/automationAccounts/hwautomation/jobs/$($jobName2)?api-version=2022-08-08"
$runbookDeletionPayload = @"
{
  "properties": {
    "runbook": {
      "name": "$runbookDelection"
    },
    "runOn": ""
  }
}
"@

# Check the hybrid worker deployment status
$hwgUri = "https://management.azure.com/subscriptions/$($subscriptionId)/resourceGroups/$($networkResourceGroup)/providers/Microsoft.Automation/automationAccounts/$($automationAccountName)/hybridRunbookWorkerGroups/$($hybridWorkerGroupName)/hybridRunbookWorkers?api-version=2021-06-22"
try {
  $hybridWorkerStatus = Invoke-AzRestMethod -uri $hwgUri -method 'GET' -ErrorAction Stop
  if ($hybridWorkerStatus.StatusCode -in 200..204) {
    $hwValue = ($hybridWorkerStatus.Content | convertfrom-json).value
    # Write-Output $jobStatus
    if (!$hwValue) {
      $ErrorMessage = "There is no hybrid worker."
      throw $ErrorMessage
    }
    elseif (([array]$hwValue.properties.workerName).length -gt 1) {
      $hwNumber = ([array]$hwValue.properties.workerName).length
      $ErrorMessage2 = "There are $hwNumber hybrid workers."
      throw $ErrorMessage2
    }
    else {
      $workerNames = $hwValue.properties.workerName
      Write-Output "The hybrid worker is " $workerNames
      if ($null -ne ($myVM | ? { $workerNames -match $_ })) {
        Write-Output "Hybrid worker is deployed successfully."

        # Start RunbookTask
        #Start-AzAutomationRunbook -AutomationAccountName "MyAutomationAccount" -Name "Test-Runbook" -RunOn "MyHybridGroup" -Wait
        $runbookStart = Invoke-AzRestMethod -Uri $runbookUri -Method PUT -Payload $runbookPayload -ErrorAction Stop
        if ($runbookStart.StatusCode -in 200..204) {
          Write-Output "Runbook $runbookTask started successfully."
          $jobs = Get-AzAutomationJob -ResourceGroupName $networkResourceGroup -AutomationAccountName $automationAccountName -RunbookName $runbookTask
          $jobStatus = $jobs[0].Status
          Write-Output "$runbookTask is $jobStatus, waiting to be completed"
          # Check job status, if done delete hybrid worker
          Do {
            Start-Sleep -Seconds 120
            $jobs = Get-AzAutomationJob -ResourceGroupName $networkResourceGroup -AutomationAccountName $automationAccountName -RunbookName $runbookTask
            $jobStatus = $jobs[0].Status
          }until ($jobStatus -contains "Completed")
          Write-Output "$runbookTask is $jobStatus, proceeding with hybrid worker deletion"
          $runbookDeletionStart = Invoke-AzRestMethod -Uri $runbookDeletionUri -Method PUT -Payload $runbookDeletionPayload -ErrorAction Stop
          if ($runbookDeletionStart.StatusCode -in 200..204) {
            Write-Output "Runbook $runbookDelection started successfully. Start deleting hybrid worker"
            $jobs2 = Get-AzAutomationJob -ResourceGroupName $networkResourceGroup -AutomationAccountName $automationAccountName -RunbookName $runbookDelection
            $jobStatus2 = $jobs2[0].Status
            Write-Output "$runbookDelection is $jobStatus2, waiting to be completed"
            Do {
              Start-Sleep -Seconds 60
              $jobs2 = Get-AzAutomationJob -ResourceGroupName $networkResourceGroup -AutomationAccountName $automationAccountName -RunbookName $runbookDelection
              $jobStatus2 = $jobs2[0].Status
            }until ($jobStatus2 -contains "Completed")
            Write-Output "$runbookDelection is $jobStatus2, hybrid worker is deleted."
          }
          else {
            Write-Output "Encountered error when starting Runbook $runbookDelection."
            $runbookDeletionStart
          }
        }
        else {
          Write-Output "Encountered error when starting Runbook $runbookTask."
          $runbookStart
        }
      }
      else {
        $ErrorMessage3 = "Hybrid worker is not deployed."
        throw $ErrorMessage3
      }
    }
  }
  else {
    Write-Output "Encountered error when getting hybrid worker information."
    $hybridWorkerStatus
  }
}
catch {
  $_
}