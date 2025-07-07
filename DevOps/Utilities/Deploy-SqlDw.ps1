param(
    [Parameter(Mandatory = $true)][string]$parameterFile,
    [Parameter(Mandatory = $true)][string]$filePath,
    [Parameter(Mandatory = $false)][switch]$whitelist
)

$ErrorActionPreference = 'Stop'
<#
    Order of Execution

1. CreateSchema
2. External_sources_need key
3. CreateTable_withWMT&TGT
4. External table creation script
5. CreateStoreporcedure_withWMT&TGT
6. CreateViews_new2
7. Login_creation_execute on master
8. user access
#>

function global:Get-KeyVaultSecretValueText	{
    param (
        [Parameter(Mandatory = $true)][Microsoft.Azure.Commands.KeyVault.Models.PSKeyVaultSecretIdentityItem]$keyVaultSecret
    )

    $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyVaultSecret.SecretValue))

    return $secretValueText
}

$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"
$parameters = & "$utilitiesFolder\Get-Parameters.ps1" -parameterFile $parameterFile
$sqlDatabaseName = $parameters.parameters.sqlDataWarehouseName.value
$sqlLogin = "sqldeployuser"
$ServerInstance = $parameters.parameters.sqlServerName.value
$ServerInstance += ".database.windows.net"

$keyVaultName = $parameters.parameters.keyVaultName.value
$secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $sqlLogin
$sqlPassword = Get-KeyVaultSecretValueText -keyVaultSecret $secret

Get-Module -Name SqlPS | Remove-Module
$a = Get-Module -ListAvailable -Name SqlServer
if (-not $a)
{
	Write-Host "installing SqlServer modules: start"
	Install-Module -Name SqlServer -Force -AllowClobber
	Write-Host "installing modules: end"
}

Write-Host "*** Starting Deployment of SQLDW Schema Objects ***"
Write-Host "Database Name : $sqlDatabaseName"
Write-Host "Server Instance : $ServerInstance"
Write-Host "Username : $sqlLogin"

if ($whitelist) {
    & "$utilitiesFolder\Set-SqlWhitelist.ps1" -parameterFile $parameterFile -forMe -customRuleName "BuildAgent"
}

$schemaPath = "$filePath\Schemas"
$tablePath = "$filePath\Tables"
$proceduresPath = "$filePath\Procedures"
$externalFileFormats = "$filePath\FileFormats"
$viewsPath = "$filePath\Views"
$permissionsPath = "$filePath\Permissions"

if (Test-Path $schemaPath -PathType Container) {

    $files = (Get-ChildItem $schemaPath | Where-Object { $_.Name -like "*.sql" }).FullName
    foreach($file in $files) {
        $sql += (Get-Content $file -Raw) + [Environment]::NewLine
    }
    if ($sql.Length -gt 0) {
        Write-Host "Creating schemas..."
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $sqlDatabaseName -Username $sqlLogin -Password $sqlPassword -Query $sql
    } else {
        Write-Host "No schemas to deploy..."
    }
}
$sql = ""

if (Test-Path $externalFileFormats -PathType Container) {

    $files = (Get-ChildItem $externalFileFormats | Where-Object { $_.Name -like "*.sql" }).FullName
    foreach($file in $files) {
        $sql += (Get-Content $file -Raw) + [Environment]::NewLine
    }
    if ($sql.Length -gt 0) {
        Write-Host "Creating external file formats..."
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $sqlDatabaseName -Username $sqlLogin -Password $sqlPassword -Query $sql
    } else {
        Write-Host "No external file formats to deploy..."
    }
}
$sql = ""

if (Test-Path $tablePath -PathType Container) {

    $files = (Get-ChildItem $tablePath | Where-Object { $_.Name -like "*.sql" }).FullName
    foreach($file in $files) {
        $sql += (Get-Content $file -Raw) + [Environment]::NewLine
    }
    if ($sql.Length -gt 0) {
        Write-Host "Creating tables..."
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $sqlDatabaseName -Username $sqlLogin -Password $sqlPassword -Query $sql
    } else {
        Write-Host "No tables to deploy..."
    }
}
$sql = ""

if (Test-Path $proceduresPath -PathType Container) {

    $files = (Get-ChildItem $proceduresPath | Where-Object { $_.Name -like "*.sql" }).FullName
    foreach($file in $files) {
        $sql += (Get-Content $file -Raw) + [Environment]::NewLine
    }
    if ($sql.Length -gt 0) {
        Write-Host "Creating procedures..."
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $sqlDatabaseName -Username $sqlLogin -Password $sqlPassword -Query $sql
    } else {
        Write-Host "No procedures to deploy..."
    }
}
$sql = ""
if (Test-Path $viewsPath -PathType Container) {

    $files = (Get-ChildItem $viewsPath | Where-Object { $_.Name -like "*.sql" }).FullName
    foreach($file in $files) {
        $sql += (Get-Content $file -Raw) + [Environment]::NewLine
    }
    if ($sql.Length -gt 0) {
        Write-Host "Creating views..."
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $sqlDatabaseName -Username $sqlLogin -Password $sqlPassword -Query $sql
    } else {
        Write-Host "No views to deploy..."
    }
}
$sql = ""

if (Test-Path $permissionsPath -PathType Container) {

    $files = (Get-ChildItem $permissionsPath | Where-Object { $_.Name -like "*.sql" }).FullName
    foreach($file in $files) {
        $sql += (Get-Content $file -Raw) + [Environment]::NewLine
    }
    if ($sql.Length -gt 0) {
        Write-Host "Granting permissions..."
        Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $sqlDatabaseName -Username $sqlLogin -Password $sqlPassword -Query $sql
    } else {
        Write-Host "No permissions to deploy..."
    }
}
$sql = ""

if ($whitelist) {
    & "$utilitiesFolder\Set-SqlWhitelist.ps1" -parameterFile $parameterFile -forMe -customRuleName "BuildAgent" -deleteRule
}
Write-Output "Execution completed successfully"
