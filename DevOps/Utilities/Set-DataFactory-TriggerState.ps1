Param
(
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,

	[Parameter(Mandatory = $False, HelpMessage = 'Specify the published ARM template')]
    [String]$armTemplate,

    [Parameter(Mandatory = $False, HelpMessage = 'Specify the parameter file')]
    [String]$overrideFile,

	[Parameter(Mandatory = $False, HelpMessage = 'Specify to disable the triggers')]
	[switch]$disableTriggers
)

function triggerSortUtil {
    param([Microsoft.Azure.Commands.DataFactoryV2.Models.PSTrigger]$trigger,
    [Hashtable] $triggerNameResourceDict,
    [Hashtable] $visited,
    [System.Collections.Stack] $sortedList)
    if ($visited[$trigger.Name] -eq $true) {
        return;
    }
    $visited[$trigger.Name] = $true;
    if ($trigger.Properties.DependsOn) {
        $trigger.Properties.DependsOn | Where-Object {$_ -and $_.ReferenceTrigger} | ForEach-Object{
            triggerSortUtil -trigger $triggerNameResourceDict[$_.ReferenceTrigger.ReferenceName] -triggerNameResourceDict $triggerNameResourceDict -visited $visited -sortedList $sortedList
        }
    }
    $sortedList.Push($trigger)
}

function Get-SortedTriggers {
    param(
        [string] $DataFactoryName,
        [string] $ResourceGroupName
    )
    $triggers = Get-AzDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName
    $triggerDict = @{}
    $visited = @{}
    $stack = new-object System.Collections.Stack
    $triggers | ForEach-Object{ $triggerDict[$_.Name] = $_ }
    $triggers | ForEach-Object{ triggerSortUtil -trigger $_ -triggerNameResourceDict $triggerDict -visited $visited -sortedList $stack }
    $sortedList = new-object Collections.Generic.List[Microsoft.Azure.Commands.DataFactoryV2.Models.PSTrigger]

    while ($stack.Count -gt 0) {
        $sortedList.Add($stack.Pop())
    }
    $sortedList
}

$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"
$triggersFolder = "{0}\{1}\{2}" -f $devOpsProjectFolder, "Projects", "triggers"


if ($overrideFile) {
	$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile -overrideFile $overrideFile
} else {
	$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile
}

$dataFactoryResourceGroupName = $parameters.parameters.dataFactoryResourceGroupName.value
$dataFactoryName = $parameters.parameters.dataFactoryName.value
$triggerFileName = "{0}.triggers.csv" -f $dataFactoryName
$TriggerPath = Join-Path -path $triggersFolder -childPath $triggerFileName

$df = Get-azDataFactoryV2 -ResourceGroupName $dataFactoryResourceGroupName -Name $dataFactoryName -ErrorAction SilentlyContinue
if (-not $df) {
    Write-Warning "Data Factory does not exist"
    return
}
try{
	if ($disableTriggers) {
		Write-Verbose "stopping all triggers"
		$templateJson = Get-Content $armTemplate | ConvertFrom-Json
		$resources = $templateJson.resources

		#Triggers
		Write-Host "Getting published triggers"
		$triggersInTemplate = $resources | Where-Object { $_.type -eq "Microsoft.DataFactory/factories/triggers" }
		$triggerNamesInTemplate = $triggersInTemplate | ForEach-Object {$_.name.Substring(37, $_.name.Length-40)}

		$triggersDeployed = Get-SortedTriggers -DataFactoryName $dataFactoryName -ResourceGroupName $dataFactoryResourceGroupName

		$triggersToStop = $triggersDeployed | Where-Object { $triggerNamesInTemplate -contains $_.Name } | ForEach-Object {
			New-Object PSObject -Property @{
				Name = $_.Name
				TriggerType = $_.Properties.GetType().Name
			}
		}

		#Stop all triggers
		Write-Host "Stopping deployed triggers`n"
		$triggersToStop | ForEach-Object {
			if ($_.TriggerType -eq "BlobEventsTrigger" -or $_.TriggerType -eq "CustomEventsTrigger") {
				Write-Host "Skipping trigger" $_.Name
				# $storageAccount = $parameters.parameters.storageAccountName.value
				# Write-Host "Removing lock of storage account" $storageAccount
				# $lockScope = "subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Storage/storageAccounts/{2}" -f $parameters.parameters.subscriptionId.value, $parameters.parameters.storageAccountResourceGroupName.value, $storageAccount
				# $locks = Get-AzResourceLock -scope $lockScope
				# if ($locks) {
				# 	$locks | Remove-AzResourceLock -Force | Out-Null
				# }
				# Write-Host "Unsubscribing" $_.Name "from events"
				# $status = Remove-AzDataFactoryV2TriggerSubscription -ResourceGroupName $dataFactoryResourceGroupName -DataFactoryName $dataFactoryName -Name $_.Name
				# while ($status.Status -ne "Disabled"){
				# 	Start-Sleep -s 15
				# 	$status = Get-AzDataFactoryV2TriggerSubscriptionStatus -ResourceGroupName $dataFactoryResourceGroupName -DataFactoryName $dataFactoryName -Name $_.Name
				# }
				# Write-Host "Stopping trigger" $_.Name
				# Stop-AzDataFactoryV2Trigger -ResourceGroupName $dataFactoryResourceGroupName -DataFactoryName $dataFactoryName -Name $_.Name -Force

				# Write-Host "Adding lock for storage account" $storageAccount
				# foreach ($lock in $locks) {
				# 	New-AzResourceLock -LockName $lock.Name -ResourceGroupName $parameters.parameters.dataFactoryResourceGroupName.value -LockLevel $lock.Properties.Level -Force
				# }
			} else {
				Write-Host "Stopping trigger" $_.Name
				Stop-AzDataFactoryV2Trigger -ResourceGroupName $dataFactoryResourceGroupName -DataFactoryName $dataFactoryName -Name $_.Name -Force
			}
		}
	} else {
		Write-Verbose "starting trigger at path $TriggerPath"
		if([IO.File]::Exists($TriggerPath) -ne $true){
			Write-Host "no trigger file found at $TriggerPath"
			return
		}
		$triggerdetails=Get-Content -Path $TriggerPath
		foreach($trigger in $triggerdetails)
		{
			if($trigger -eq ""){
				continue
			}

			$depl = Start-AzDataFactoryV2Trigger -ResourceGroupName $dataFactoryResourceGroupName -DataFactoryName $dataFactoryName -Name $trigger -force

			Write-Host "$depl"
		}
	}
}
catch{
	Write-Error $_
	throw
}
