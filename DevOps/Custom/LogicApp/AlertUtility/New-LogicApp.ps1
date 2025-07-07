Param
(
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
	[String]$parameterFile,
	[Parameter(Mandatory = $False, HelpMessage = 'Specify the base logic app parameter file')]
	[String]$logicAppParameterFile="ARMTemplateParameters.json",
	[Parameter(Mandatory = $False, HelpMessage = 'Set RBAC permissions on connectors. Only need to do this once')]
    [switch]$Permissions
)

$rootPath = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.Parent.FullName
$devOpsProjectFolder = "{0}\{1}" -f $rootPath, "DevOps"
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"
$armFolderPath = "{0}\Custom\LogicApp\AlertUtility" -f $devOpsProjectFolder
$armParameterFilePath = Join-Path -Path $armFolderPath -Child $logicAppParameterFile

$tokens = $parameterFile.Split(".")
$environment= $Global:CtxBootStrap.ProjectEnvironment
if ($tokens.count -eq 2) {
	$environment=$tokens[0]
	$parameterFile = "parameters.{0}.json" -f $parameterFile
}
$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile
$overrides = Get-Content -Path $armParameterFilePath | ConvertFrom-JSON


$aasStatusURL = "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.AnalysisServices/servers/{2}?api-version=2017-08-01" -f $parameters.parameters.subscriptionId.value, $parameters.parameters.analysisServicesResourceGroupName.value, $parameters.parameters.analysisServicesName.value

$aasQPUMetricsURL ="https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.AnalysisServices/servers/{2}/providers/microsoft.insights/metrics?api-version=2018-01-01&metricnames=qpu_metric&interval={3}&aggregation=maximum" -f $parameters.parameters.subscriptionId.value, $parameters.parameters.analysisServicesResourceGroupName.value, $parameters.parameters.analysisServicesName.value, "PT@{variables('AASIdleTime')}M"

$dwStatusURL= "https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Sql/servers/{2}/databases/{3}?api-version=2017-10-01-preview" -f $parameters.parameters.subscriptionId.value, $parameters.parameters.sqlServerResourceGroupName.value, $parameters.parameters.sqlServerName.value, $parameters.parameters.sqlDataWarehouseName.value

$sqlDWPauseURL="https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DataFactory/factories/{2}/pipelines/PL_PAUSE_SQLDW/createRun?api-version=2017-09-01-preview" -f $parameters.parameters.subscriptionId.value, $parameters.parameters.dataFactoryResourceGroupName.value, $parameters.parameters.dataFactoryName.value

$aasPauseURL="https://management.azure.com/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.DataFactory/factories/{2}/pipelines/PL_PAUSE_AAS/createRun?api-version=2017-09-01-preview" -f $parameters.parameters.subscriptionId.value, $parameters.parameters.dataFactoryResourceGroupName.value, $parameters.parameters.dataFactoryName.value

$namingRoot = "{0}-da{1}-{2}-{3}-monitorlogicapp-" -f $Global:CtxBootStrap.NamePrefix, $Global:CtxBootStrap.SubscriptionNumber, $environment, $parameters.Parameters.ProjectNumber.value

$naming= $namingRoot + "01"

	# create a logic app specific parameter file
	$overrideFileName = "parameters.{0}{1}.{2}.{3}.json" -f "da", $Global:CtxBootStrap.SubscriptionNumber, $environment, $parameters.Parameters.ProjectNumber.value

	$overridesProjectFile = "{0}\{1}" -f $armFolderPath, $overrideFileName
	$overrides.parameters.logicAppName.value = $naming
	$overrides.parameters.ResourceGroup.value = $parameters.parameters.analysisServicesResourceGroupName.value
	$overrides.parameters.ITSG.value = $parameters.parameters.projectNumber.value
	$overrides.parameters.o365_name.value = "{0}o365-01" -f $namingRoot
	$overrides.parameters.sqldw_name.value = "{0}sqldw-01" -f $namingRoot
	$overrides.parameters.sqldw_displayName.value = "{0}sqldw-01" -f $namingRoot
	$overrides.parameters.sqldw_server.value = 	$parameters.parameters.sqlServerName.value + ".database.windows.net"
	$overrides.parameters.sqldw_database.value = $parameters.parameters.sqlDataWarehouseName.value
	$overrides.parameters.AASServerName.value = $parameters.parameters.analysisServicesName.value
    $overrides.parameters.AASStatusURL.value = $aasStatusURL
	$overrides.parameters.AASQPUMetricsURL.value = $aasQPUMetricsURL
	$overrides.parameters.DWStatusURL.value = $dwStatusURL
	$overrides.parameters.Subscription.value = $Global:CtxDeploy.Subscription.Name
	$overrides.parameters.ProjectName.value = $parameters.parameters.ProjectName.value
	$overrides.parameters.AASPauseURL.value = $aasPauseURL
	$overrides.parameters.DWPauseURL.value = $sqlDWPauseURL
	$overrides.parameters.DWServerName.value = $parameters.parameters.sqlDataWarehouseName.value
	$overrides | ConvertTo-JSON -Depth 10 | Out-File -filepath $overridesProjectFile -Force

	$args = @{
		parameterFile=$parameterFile
		armParameterFileName=$overrideFileName
	}

    $args.Permissions=$Permissions

	& "$armFolderPath\New-LogicAppDeployment.ps1" @args
