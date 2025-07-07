param(
	[Parameter(Mandatory = $true)][string]$xmlaCubeFilesDirectory,
	[Parameter(Mandatory = $true)][string]$parameterFile,
	[Parameter(Mandatory = $false)][switch]$whitelist

)

function global:Get-KeyVaultSecretValueText	{
    param (
        [Parameter(Mandatory = $true)][Microsoft.Azure.Commands.KeyVault.Models.PSKeyVaultSecretIdentityItem]$keyVaultSecret
    )

    $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyVaultSecret.SecretValue))

    return $secretValueText
}

# Deploy the SAAS Cubes *.xmla in a specified folder using a SSAS admin username/Password
$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"


$a = Get-Module -ListAvailable -Name SqlServer
if (-not $a) {
	Write-Host "installing SqlServer modules: start"
	Install-Module -Name SqlServer -Force -AllowClobber
	Write-Host "installing modules: end"

	Write-Host "getting modules list: start"
	Get-Module SqlServer -ListAvailable
	Write-Host "getting modules list: end"
}

# Write-Host "listing commands: start"
Import-Module -Name SqlServer

$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile
$ssasServer = $parameters.parameters.analysisServicesName.value
$keyVaultName = $parameters.parameters.keyVaultName.value
$tenantId = $parameters.parameters.tenantId.value
$databaseServer = $parameters.parameters.sqlServerName.value
$databaseName = $parameters.parameters.sqlDataWarehouseName.value
$appId = $parameters.parameters.applicationId.value
$location = $parameters.parameters.location.value
$region = $location.ToLower().Replace(" ", "")
$appSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $parameters.parameters.adApplicationName.value -ErrorAction SilentlyContinue

$aasUserId = $parameters.parameters.analysisServicesSqlUserLogin.value
$aasUserPwd = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $aasUserId -ErrorAction SilentlyContinue

$Credential = New-Object System.Management.Automation.PSCredential($appId, $appSecret.SecretValue)

$AASServerName = "asazure://$region.asazure.windows.net/$ssasServer"
$rolloutEnvironment = $AASServerName.Replace("asazure://", "").Split("/")[0]

if ($whitelist) {
	# whitelist the AAS server
	& "$utilitiesFolder\Set-SSASWhitelist" -parameterFile $parameterFile -forMe -ruleName "AASDeploy"
}

#Function to read JSON from XMLA file
function Get-JsonFromXmla {
	param([string] $xmlaQuery)

	$BracketCount = 0;
	$JsonItems = New-Object 'System.Collections.Generic.List[string]'
	$Json = [System.Text.StringBuilder]::new()

	foreach ($c in $xmlaQuery.ToCharArray()) {
		if ($c -eq '{') {
			++$BracketCount;
		}
		elseif ($c -eq '}') {
			--$BracketCount;
		}
		[void]$Json.Append($c);

		if ($BracketCount -eq 0 -and $c -ne ' ') {
			$JsonItems.Add($Json.ToString());
			$Json = [System.Text.StringBuilder]::new()
		}
	}
	return $JsonItems;
}

# helper to turn PSCustomObject into a list of key/value pairs
function Get-ObjectMembers {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
		[PSCustomObject]$obj
	)
	$obj | Get-Member -MemberType NoteProperty | ForEach-Object {
		$key = $_.Name
		[PSCustomObject]@{Key = $key; Value = $obj."$key" }
	}
}

foreach ($xmlaCubeFile in (Get-ChildItem -Path $xmlaCubeFilesDirectory -Filter "*.xmla")) {
	$filePath = $xmlaCubeFile.FullName
	Write-Verbose "Deploy AAS cube file $xmlaCubeFile"

	# Replace magic strings for database server, database, user and password
	$xmlaQuery = [string](get-content $filePath -Raw)

	$jsonQuery = Get-JsonFromXmla($xmlaQuery)

	$jsonData = $jsonQuery[0] | ConvertFrom-Json

	$jsondata | Get-ObjectMembers | ForEach-Object {
		$_.Value | Get-ObjectMembers | Where-Object Key -eq "database" | ForEach-Object {
			$_.Value.model | Get-ObjectMembers | Where-Object Key -eq "dataSources" | ForEach-Object {
				$_.value | ForEach-Object {
					if ($_.connectionDetails.protocol -eq "tds") {
						$_.connectionDetails.address.server = "$databaseServer.database.windows.net"
						$_.connectionDetails.address.database = $databaseName
						if ($_.credential.AuthenticationKind -ne "UsernamePassword") {
							$_.credential.AuthenticationKind = "UsernamePassword"
						}
						if ($_.credential.Username) {
							$_.credential.Username = $aasUserId
						}
						else {
							Add-Member -InputObject $_.credential -MemberType NoteProperty -Name "Username" -Value $aasUserId
						}
						$sqlPassword = (Get-KeyVaultSecretValueText -keyVaultSecret $aasUserPwd)
						if ($_.credential.Password) {
							$_.credential.Password = $sqlPassword
						}
						else {
							Add-Member -InputObject $_.credential -MemberType NoteProperty -Name "Password" -Value $sqlPassword
						}
					}
					elseif ($_.connectionDetails.protocol -eq "azure-blobs") {
						# For a project to use this script we must elevate their deployment SPN to 'Contributor' instead of 'InA Tech Deployment Contributor'
						$adlsGen2ResourceGroupName = $parameters.parameters.adlStoreResourceGroupName.value
						$adlsGen2StoreName = $parameters.parameters.adlStoreName.value
						$adlsGen2StorageKey = Get-AzStorageAccountKey -ResourceGroupName $adlsGen2ResourceGroupName -Name $adlsGen2StoreName
						$_.connectionDetails.address.account = $adlsGen2StoreName
						$_.connectionDetails.address.domain = "blob.core.windows.net"
						#$_.credential.path = "https://$adlsGen2StoreName.blob.core.windows.net/"
						if ($_.credential.AuthenticationKind -ne "Key") {
							$_.credential.AuthenticationKind = "Key"
						}
						if ($_.credential.Key) {
							$_.credential.Key = $adlsGen2StorageKey[0].value
						}
						else {
							Add-Member -InputObject $_.credential -MemberType NoteProperty -Name "Key" -Value $adlsGen2StorageKey[0].value
						}
					}
					else {
						throw "Unsupported data source type. Supported data sources are Azure SQL(DW) and Azure Blob(ADLS Gen 2)"
					}
				}
			}
		}
	}

		$newQuery = ($jsonData | ConvertTo-Json -Depth 10)
	    # Write-Verbose $newQuery
		Invoke-ASCmd -Server $AASServerName -Query $newQuery -Credential $Credential -ServicePrincipal -TenantId $tenantId

	}
	if ($whitelist) {
		# whitelist the AAS server
		& "$utilitiesFolder\Set-SSASWhitelist" -parameterFile $parameterFile -forMe -ruleName "AASDeploy" -deleteRule
	}

	Write-Host "Deploy-SSASCube.ps1 script execution completed."
