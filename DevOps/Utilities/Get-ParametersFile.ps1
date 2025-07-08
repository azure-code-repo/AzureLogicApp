Param
(
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,
    [Parameter(Mandatory = $False, HelpMessage = 'Specify if you want to a specific landscape storage account in the event the parameter file is not available on the local disk.')]
    [Hashtable]$bootStrap,
    [Parameter(Mandatory = $False, HelpMessage = 'Specify if you want to use landscape''s global storage account in CDE-01 the event the parameter file is not available on the local disk.')]
    [switch]$fromGlobalCache
)

$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"

$parameterFile = $parameterFile.ToLower()
$parameterFilePath = "{0}\Projects\{1}" -f $devOpsProjectFolder, $parameterFile
$args1 = @{
    ResourceGroupName = $Global:CtxBootStrap.LandscapeResourceGroupName
    Name = $Global:CtxBootStrap.LandscapeStorageAccountName
    DefaultProfile = $Global:CtxBootStrap.DefaultProfile
}
$args2 = @{
    StorageAccountName = $Global:CtxBootStrap.LandscapeStorageAccountName
}
if ($bootStrap) {
    # Connect to the landscape storage account in the specified subscription instead of the current one
    $args1.DefaultProfile = $bootStrap.DefaultProfile
    $args1.ResourceGroupName = $bootStrap.LandscapeResourceGroupName
    $args1.Name = $bootStrap.LandscapeStorageAccountName
    $args2.StorageAccountName = $bootStrap.LandscapeStorageAccountName
} elseif($fromGlobalCache) {
    # landscape keep two copies of project parameter files.  One in EcoMaster for the target subscription and the other
    # in eco master in cde-01
    # This only works if ITSG is globally unique.
    $args1.DefaultProfile = $Global:CtxProd
    $args1.ResourceGroupName = "prod-test-p-56728-rg"
    $args1.Name = "prodstggoogleda56728"
    $args2.StorageAccountName = "prodstggoogleda56728"
}
if (-not $(Try { Test-Path $parameterFilePath.trim() } Catch { $false }) ) {
    # All parameter files are backed up to landscape's prod storage account
    Write-Host "The requested parameter file '$parameterFile' was not found on your disk.  Trying to access from landscape backup.."
    Write-Warning "If you see this warning in your VSTS log then your specified parameter file is missing.  Check it exists in your DevOps\Projects folder."
    $accountKeys = Get-AzStorageAccountKey @args1
    $args2.StorageAccountKey = $accountKeys[0].Value
    $storageContext = New-AzStorageContext @args2

    $containerName = "parameterfiles"

    if(-not(Get-AzStorageContainer -Name $containerName -Context $storageContext.Context -DefaultProfile $arg1.DefaultProfile))
    {
        throw "'$parameterFile': The landscape parameter file backup container '$containerName' was not found in storage account $($args1.ResourceGroupName).$($args1.Name)."
    }
    $n=Get-AzStorageBlobContent -Destination $parameterFilePath -Container $containerName -Blob $parameterFile -Context $storageContext.Context
}

if ( $(Try { Test-Path $parameterFilePath.trim() } Catch { $false }) ) {
    Write-Verbose "Parameter file : $parameterFilePath"
}else {
    Write-Error "Parameter file not found in path $parameterFilePath"
    throw [System.IO.FileNotFoundException]
}
return $parameterFilePath
