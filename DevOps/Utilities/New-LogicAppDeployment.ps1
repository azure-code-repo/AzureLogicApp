Param
(
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the path from the repo root to where the ARM templates are checked in.')]
    [String]$armFolderName,
    [Parameter(Mandatory = $True, HelpMessage = 'The file name of the ARM template.')]
    [String]$armTemplateFileName
)

function global:Get-KeyVaultSecretValueText	{
    param (
        [Parameter(Mandatory = $true)][Microsoft.Azure.Commands.KeyVault.Models.PSKeyVaultSecretIdentityItem]$keyVaultSecret
    )

    $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyVaultSecret.SecretValue))

    return $secretValueText
}

# Deploy logic app using the ARM template published to git.
$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"

$parameters = & "$utilitiesFolder\Get-Parameters.ps1" -parameterFile $parameterFile

$templateFilePath = Join-Path -Path $armFolderName -ChildPath $armTemplateFileName
$logicAppParametersFilePath = "{0}.parameters.json" -f $templateFilePath.Replace(".json","")

$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"
$projectsFolder = "{0}\{1}" -f $devOpsProjectFolder, "Projects"

$parameterFile = $parameterFile.ToLower()
$parameterFilePath = "{0}\Projects\{1}" -f $devOpsProjectFolder, $parameterFile

# $logicAppParameters = Get-Content -Path $templateFilePath -Raw | ConvertFrom-JSON

$logicAppResourceGroupName = $parameters.parameters.logicAppResourceGroupName.value
$logicAppName = $parameters.parameters.logicAppName.value

$mergedParameterFileName = "{0}.deploy.json" -f $logicAppName
$mergedParameterFilePath = "{0}\Projects\{1}" -f $devOpsProjectFolder, $mergedParameterFileName
Write-Host $mergedParameterFilePath
$merged = & "$utilitiesFolder\Get-ParameterFileMerge.ps1" -parameterFile $logicAppParametersFilePath -overrideFile $parameterFile -writeToDiskFilename $mergedParameterFileName -force -overwriteExisting | Out-Null
# $location = $parameters.parameters.location.value
# $logicAppStorageConnectionName = $parameters.parameters.logicAppStorageConnectionName.value
# $logicAppO365apiConnection = $parameters.parameters.logicAppO365apiConnection.value
# $logicAppADFConnectionName = $parameters.parameters.logicAppADFConnectionName.value
# $logicAppSharePointConnectionName = $parameters.parameters.logicAppSharePointConnectionName.value
# $PHlogicAppSharePointConnectionName = $parameters.parameters.PHlogicAppSharePointConnectionName.value
# $keyVaultName = $parameters.parameters.keyVaultName.value
# $adApplicationName = $parameters.parameters.adApplicationName.value
# $adApplicationId = $parameters.parameters.applicationId.value
# $subscriptionId = $parameters.parameters.subscriptionId.value

# if($logicAppParameters.parameters.logicapp_sqldw_username){
#     $logicAppSqlDWapiConnectionUser = "sqllogicappuser"
#     $logicAppSqlDWapiConnectionUserValue = ConvertTo-SecureString $logicAppSqlDWapiConnectionUser -AsPlainText -Force
#     $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $logicAppSqlDWapiConnectionUser
#     $logicAppSqlDWapiConnectionPasswordValue = Get-KeyVaultSecretValueText -keyVaultSecret  $secret
#     $logicAppSqlDWapiConnectionPasswordValue = ConvertTo-SecureString $logicAppSqlDWapiConnectionPasswordValue -AsPlainText -Force
# }

# if($logicAppParameters.parameters.logicapp_sql_username){
#    $logicAppSqlapiConnectionUser = $parameters.parameters.logicAppSqlUserLogin.value
#     $sqldb_sqlConnectionString = "Server=tcp:{0}.database.windows.net,1433;Initial Catalog={1};Persist Security Info=False;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" -f $parameters.parameters.sqlServerName.value, $parameters.parameters.sqlDatabaseName.value

#     $sqldb_sqlConnectionString = ConvertTo-SecureString $sqldb_sqlConnectionString -AsPlainText -Force

#     $logicAppSqlapiConnectionUserValue = ConvertTo-SecureString $logicAppSqlapiConnectionUser -AsPlainText -Force
#     $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $logicAppSqlapiConnectionUser
#     $logicAppSqlapiConnectionPasswordValue = ConvertTo-SecureString (Get-KeyVaultSecretValueText -keyVaultSecret $secret) -AsPlainText -Force
# }

# $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $adApplicationName
# $applicationId_token_clientSecret = Get-KeyVaultSecretValueText -keyVaultSecret  $secret
# $applicationId_token_clientSecret = ConvertTo-SecureString $applicationId_token_clientSecret -AsPlainText -Force

$params = @{
    "Name" = $logicAppName
    "ResourceGroupName" = $logicAppResourceGroupName
    "TemplateFile" = $templateFilePath
    "TemplateParameterFile" = $mergedParameterFilePath
    # "logicAppName" = $logicAppName
    # "location" = $location
    # "logicAppStorageConnectionName" = $logicAppStorageConnectionName
    # "logicAppO365apiConnection" = $logicAppO365apiConnection
    # "logicAppADFConnectionName" = $logicAppADFConnectionName
    # "logicAppSharePointConnectionName" = $logicAppSharePointConnectionName
    # "PHlogicAppSharePointConnectionName" = $PHlogicAppSharePointConnectionName
}

#$logicAppParameters.resources[0].properties.definition.actions.Run_query_and_list_results.inputs.queries.subscriptions

# if($logicAppParameters.parameters.logicapp_sqldw_username){
#     $params.Add("logicapp_sqldw_username",$logicAppSqlDWapiConnectionUserValue)
#     $params.Add("logicapp_sqldw_password",$logicAppSqlDWapiConnectionPasswordValue)
# }

# if($logicAppParameters.parameters.logicapp_sql_username){
#     $params.Add("logicapp_sql_username",$logicAppSqlapiConnectionUserValue)
#     $params.Add("logicapp_sql_password",$logicAppSqlapiConnectionPasswordValue)
#     $params.Add("logicapp_sql_sqlConnectionString",$sqldb_sqlConnectionString)
# }

# if($logicAppParameters.parameters.datalake_token_clientSecret){
#     $params.Add("datalake_token_clientSecret", $applicationId_token_clientSecret)
#     $params.Add("datalake_token_clientId", $adApplicationId)
# }

# if($logicAppParameters.parameters.monitorlogs_token_clientSecret){
#     $params.Add("monitorlogs_token_clientSecret",  $applicationId_token_clientSecret)
#     $params.Add("monitorlogs_token_clientId",  $adApplicationId)
# }

Write-Host "Deploying LogicApp $($logicAppName) - $($logicAppResourceGroupName): Template $($templateFilePath) - Parameters $($parameterFilePath)..."
New-AzResourceGroupDeployment @params -Force -Verbose `
-ErrorVariable ErrorMessages
