# # Ensures you do not inherit an AzContext in your runbook
# Disable-AzContextAutosave -Scope Process

Connect-AzAccount -Identity -ErrorAction Stop

$vmName = 'myHybridWorker'
$vmResourceGroup = 'hybridworkervm_rg'
$vmNetworkRG = 'hwnetworkresources_rg'
$mySubscription = 'a6f140c7-d601-4fd5-bfb7-a2d3871a91c8'
$myAutomationAccount = 'hwautomation'
$hrwgName = 'hwg'

# Delete hybrid worker
$hwguri = "https://management.azure.com/subscriptions/$($mySubscription)/resourceGroups/$($vmNetworkRG)/providers/Microsoft.Automation/automationAccounts/$($myAutomationAccount)/hybridRunbookWorkerGroups/$($hrwgName)/hybridRunbookWorkers?api-version=2021-06-22"
try{
    $hwgres = Invoke-AzRestMethod -Uri $hwguri -Method GET -ErrorAction Stop
    if ($hwgres.StatusCode -in 200..204){
        $hwContentValue = ($hwgres.Content | ConvertFrom-Json).value # There could be none, one, or more hybrid workers
        if (!$hwContentValue){
            Write-Output "There is no hybrid worker."
            Exit 1
        }elseif (([array]$hwContentValue.properties.workerName).length-gt 1){
            $hwNumber = ([array]$hwContentValue.properties.workerName).length
            Write-Output "There are $hwNumber hybrid worker."
            Exit 2
        }else{
            $hwid = $hwContentValue.id
            $hwURL = "https://management.azure.com$($hwid)?api-version=2021-06-22"
            $hwDeletion = Invoke-azrestmethod -uri $hwURL -method Delete -ErrorAction Stop
            if ($hwDeletion.StatusCode -in 200..204){
                Write-Output "Hybrid worker is removed successfully."
            }else{
                Write-Output "Hybrid worker removal encountered error."
                $hwDeletion
            }
        }
    }else{
        Write-Output "Encountered error when getting hybrid worker information."
        $hwgres
    }
}catch{
    $_
}

# Delete virtual machine
$vmURL = "https://management.azure.com/subscriptions/$($mySubscription)/resourceGroups/$($vmResourceGroup)/providers/Microsoft.Compute/virtualMachines/$($vmName)?api-version=2018-10-01"
try{
    $vmDeletion = Invoke-AzRestMethod -uri $vmURL -method Delete -ErrorAction Stop
    if ($vmDeletion.StatusCode -in 200..204){
        Write-Output "Virtual machine is deleted successfully."
    }else{
        Write-Output "Virtual machine deletion encountered error."
        $vmDeletion
    }
}catch{
    $_
}

# check if virtual machine has been deleted, if yes, delete the OS disk
$vmDiskName = (''+$vmName.ToLower()+'_OsDisk')
$diskUri = "https://management.azure.com/subscriptions/$($mySubscription)/resourceGroups/$($vmResourceGroup)/providers/Microsoft.Compute/disks/$($vmDiskName)?api-version=2021-12-01"
$vmExists = Get-AzResource -Name $vmName -ResourceGroupName $vmResourceGroup
try{
    if (-not $vmExists) {
        Write-Output "VM $vmName does not exist, deleting OS Disk"
        $OSDiskDeletion = Invoke-AzRestMethod -uri $diskUri -Method DELETE -ErrorAction Stop
        if ($OSDiskDeletion.StatusCode -in 200..204){
            Write-Output "OS Disk is deleted successfully."
        }else{
            Write-Output "OS Disk deletion encountered error."
            $OSDiskDeletion
        }
    }
    else{
        Write-Output "Waiting for VM to be deleted"
        Do{
            Start-Sleep -s 10
            $vmExists = Get-AzResource -Name $vmName -ResourceGroupName $vmResourceGroup
        }until(-not $vmExists)
        Write-Output "VM is deleted, start deleting OS Disk"
        $OSDiskDeletion = Invoke-AzRestMethod -uri $diskUri -Method DELETE -ErrorAction Stop
        if ($OSDiskDeletion.StatusCode -in 200..204){
            Write-Output "OS Disk is deleted successfully. This job is completed."
        }else{
            Write-Output "OS Disk deletion encountered error."
            $OSDiskDeletion
        }
    }
}catch{
    $_
}
