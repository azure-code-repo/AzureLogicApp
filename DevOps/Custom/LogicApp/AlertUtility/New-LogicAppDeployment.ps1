Param
(
  [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
  [String]$parameterFile,
  [Parameter(Mandatory = $False, HelpMessage = 'Specify the path from the repo root to where the ARM templates are checked in.')]
  [String]$armFolderName,
  [Parameter(Mandatory = $False, HelpMessage = 'The file name of the ARM template.')]
  [String]$armTemplateFileName = "ArmTemplate.json",
  [Parameter(Mandatory = $False, HelpMessage = 'The file name of the published ARM template parameter file.')]
  [String]$armParameterFileName,
  [Parameter(Mandatory = $False, HelpMessage = 'Set RBAC permissions on connectors. ONly need to do this once')]
  [switch]$Permissions
)
# Deploy logic app using the ARM template published to git.
$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"
$managerFolder = "{0}\{1}" -f $devOpsProjectFolder, "LandscapeManager"
$rootFolder = (Get-Item -Path $PSScriptRoot).FullName
$armFolder = Join-Path -Path $rootFolder -ChildPath $armFolderName
$runbooksFolder = "{0}\{1}" -f $devOpsProjectFolder, "LandscapeManager\RunBooks"
& "$runbooksFolder\Import-PlatformCore.ps1"

if (-not $armTemplateFileName) {
  $armTemplateFileName = "ArmTemplate.json"
}
if (-not $armParameterFileName) {
  $armParameterFileName = "ARMTemplateParameters.json"
}

$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile

$rootPath = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.Parent.FullName
$devOpsProjectFolder = "{0}\{1}" -f $rootPath, "DevOps"
$armFolderPath = "{0}\Custom\LogicApp\AlertUtility" -f $devOpsProjectFolder
$logicAppParameterFile = "{0}\{1}" -f $armFolderPath, $armParameterFileName
$logicAppParameters = Get-Content -Path $logicAppParameterFile | ConvertFrom-JSON
$monitorlogicAppName = $logicAppParameters.parameters.logicAppName.value
$resourceGroupName = $parameters.parameters.analysisServicesResourceGroupName.value
try {
  $sqlUserPasword = Get-AzKeyVaultSecret -VaultName $parameters.parameters.keyvaultname.value -Name $logicAppParameters.parameters.sqldw_username.value
}
catch {
}
if (-not $sqlUserPasword -or $Permissions) {
  & "$utilitiesFolder\New-SqlUserWithRole.ps1" -parameterFile $parameterFile -SqlUserName $logicAppParameters.parameters.sqldw_username.value -DbRole db_datawriter

  $sqlUserPasword = Get-AzKeyVaultSecret -VaultName $parameters.parameters.keyvaultname.value -Name $logicAppParameters.parameters.sqldw_username.value
}

$templateParameterFilePath = Join-Path -Path $armFolder -ChildPath $armParameterFileName
$templateFilePath = Join-Path -Path $armFolder -ChildPath $armTemplateFileName

$deployName = "$($monitorlogicAppName)_deploy"
New-AzResourceGroupDeployment `
  -Name $deployName `
  -ResourceGroupName $resourceGroupName `
  -TemplateParameterFile  $templateParameterFilePath `
  -TemplateFile $templateFilePath `
  -sqldw_password $sqlUserPasword.SecretValue | Out-Null

function GrantPermissionToSqlUser {
  param
  (
    # Parameter help description
    [String]$SqlUserName,
    [string]$Permissions

  )

  $databaseName = $parameters.parameters.sqlDataWarehouseName.value
  $serverName = $parameters.parameters.sqlServerName.value

  $sqlUserGrantPermissionStr = "GRANT {0} TO {1};"

  $sqlUserCmdStr = $sqlUserGrantPermissionStr -f $Permissions, $SqlUserName

  try {
    $clientid = $parameters.parameters.deploymentApplicationId.value
    $tenantid = $parameters.parameters.tenantId.value
    $secret = Get-AzKeyVaultSecret -VaultName $parameters.parameters.landscapeKeyVaultName.value -Name $parameters.parameters.deploymentAdApplicationName.value -AsPlainText -ErrorAction Stop

    $request = Invoke-RestMethod -Method POST `
      -Uri "https://login.microsoftonline.com/$tenantid/oauth2/token"`
      -Body @{ resource = "https://database.windows.net/"; grant_type = "client_credentials"; client_id = $clientid; client_secret = $secret }`
      -ContentType "application/x-www-test-urlencoded"

    Invoke-Sqlcmd -ServerInstance "$serverName.database.windows.net" -Database $databaseName -AccessToken $request.access_token -query $sqlUserCmdStr -ErrorAction Stop
    Write-Host "Granted VIEW DATABASE STATE permission to $SqlUserName on database $databaseName"
  }
  catch {
    throw
  }
}

#Set permissions
if ($Permissions) {
  GrantPermissionToSqlUser -SqlUserName $logicAppParameters.parameters.sqldw_username.value -Permissions "VIEW DATABASE STATE"

  if ($parameters.parameters.projectEnvironment.value -eq "d" ) {
    $granteeObjectId = $parameters.parameters.appContributorGroupId.value
  }
  else {
    $granteeObjectId = $parameters.parameters.appReaderGroupId.value
  }
  $monitorlogicResource = Get-AzResource -ResourceGroupName $resourceGroupName -Name $monitorlogicAppName
  $monitorlogicResource
  if ($monitorlogicResource) {
    $roleName = "Reader"

    New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $parameters.parameters.sqlServerName.value   -RoleDefinitionName $roleName -ResourceType "Microsoft.Sql/servers" -ObjectId $monitorlogicResource.Identity.PrincipalId

    $analysisServers = Get-AzResource -ResourceGroupName $resourceGroupName  -ResourceType "Microsoft.AnalysisServices/servers"
    foreach ($analysisServer in $analysisServers) {
      New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $analysisServer.Name  -RoleDefinitionName $roleName -ResourceType "Microsoft.AnalysisServices/servers" -ObjectId $monitorlogicResource.Identity.PrincipalId
    }

    New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $parameters.parameters.dataFactoryName.value  -RoleDefinitionName "InA Tech Reader" -ResourceType "Microsoft.DataFactory/factories" -ObjectId $monitorlogicResource.Identity.PrincipalId

    if ($parameters.parameters.projectEnvironment.value -eq "d" ) {
      New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $monitorlogicResource.Name -RoleDefinitionName "Logic App Contributor" -ResourceType $monitorlogicResource.ResourceType -ObjectId $granteeObjectId
    }
    else {
      New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $monitorlogicResource.Name -RoleDefinitionName "Logic App Operator" -ResourceType $monitorlogicResource.ResourceType -ObjectId $granteeObjectId
    }
  }

  foreach ($logicAppConnector in Get-AzResource -ResourceType "Microsoft.Web/connections" -ResourceGroupName $resourceGroupName) {
    if ($logicAppConnector.Name.Contains("sqldw")) {
      New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $logicAppConnector.Name -RoleDefinitionName "Logic App Contributor" -ResourceType $logicAppConnector.ResourceType -ObjectId $granteeObjectId
    }
    if ($logicAppConnector.Name.Contains("-test-")) {
      if ($parameters.parameters.projectEnvironment.value -eq "d" -or $parameters.parameters.projectEnvironment.value -eq "q" ) {
        New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $logicAppConnector.Name  -RoleDefinitionName "Logic App Contributor" -ResourceType $logicAppConnector.ResourceType -ObjectId $granteeObjectId
      }
      else {
        $granteeObjectId = $parameters.parameters.supportADGroupId.value
        New-AzRoleAssignment -ResourceGroupName $resourceGroupName -ResourceName $logicAppConnector.Name  -RoleDefinitionName "Logic App Contributor" -ResourceType $logicAppConnector.ResourceType -ObjectId $granteeObjectId e
      }
    }
  }
}
