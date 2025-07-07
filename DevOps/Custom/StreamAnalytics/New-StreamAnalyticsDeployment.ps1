Param
(
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,
    [Parameter(Mandatory = $False, HelpMessage = 'Specify the path where the SA ARM templates are checked in.  This should be off the repo root')]
    [String]$armFolderName = "StreamAnalytics",
    [Parameter(Mandatory = $True, HelpMessage = 'The file name of the ARM template.')]
    [String]$armTemplateFileName,
    [Parameter(Mandatory = $False, HelpMessage = 'The file name of the published ARM template parameter file.')]
    [String]$armParameterFileName,
    [Parameter(Mandatory = $False, HelpMessage = 'The file name of the published ARM template parameter file.')]
    [String]$secretName
)
# Deploy a stream analytic job to land data from one blob account to the current storage account
$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"
$projectsFolder = "{0}\{1}" -f $devOpsProjectFolder, "Projects"
$rootFolder = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName
$armFolder = "{0}\{1}" -f $rootFolder, $armFolderName
$runbooksFolder = "{0}\{1}" -f $devOpsProjectFolder, "LandscapeManager\RunBooks"
& "$runbooksFolder\Import-PlatformCore.ps1"
$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile

$templateParameterFilePath = Join-Path -Path $armFolder -ChildPath $armParameterFileName
$templateFilePath = Join-Path -Path $armFolder -ChildPath $armTemplateFileName

$itsg = $parameters.parameters.projectNumber.value
$storageAccountResourceGroupName = $parameters.parameters.storageAccountResourceGroupName.value
$storageAccountName = $parameters.parameters.storageAccountName.value
$accountKeys = Get-AzStorageAccountKey -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName

$sharedAccessPolicyKeySecret = & "$utilitiesFolder\Get-KeyVaultSecret" -parameterFile $parameterFile -secretName $secretName
$sharedAccessPolicyKeySecretValueText = Get-KeyVaultSecretValueText -keyVaultSecret $sharedAccessPolicyKeySecret

New-AzResourceGroupDeployment -Name "iot_$itsg" -ResourceGroupName $storageAccountResourceGroupName -TemplateParameterFile $templateParameterFilePath `
 -TemplateFile $templateFilePath -Output_iotoutput_Storage1_accountKey $accountKeys[0].Value -Input_iotsource_sharedAccessPolicyKey $sharedAccessPolicyKeySecretValueText
