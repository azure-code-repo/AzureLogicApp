Param
(
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,
    [Parameter(Mandatory = $True, HelpMessage = 'The folder path where your dev ADF publishes the ARM template.  The published parameter file will be there too.')]
    [String]$publishFolderPath,
    [Parameter(Mandatory = $False, HelpMessage = 'The root parameter file for your adf.  This is generated by landscape and you shouldn''t need to change it. Must be in DevOps\Projects folder')]
    [String]$rootParameterFile,
    [Parameter(Mandatory = $False, HelpMessage = 'The environment specifc parameter file for your adf.  Developers must maintain this if required. It should contain environment specific values that are not in the root file. Must be in DevOps\Projects folder and is named using the datsfactory name.')]
    [String]$adfParameterFile,
    [Parameter(Mandatory = $False, HelpMessage = 'The file name of the ADF ARM template.')]
    [String]$publishedArmTemplateFileName,
    [Parameter(Mandatory = $False, HelpMessage = 'The file name of the published ADF ARM template parameter file.')]
    [String]$publishedArmParameterFileName,
    [Parameter(Mandatory = $False, HelpMessage = 'Pass if this is a linked ARM template deployment')]
    [switch]$linkedTemplate,
    [Parameter(Mandatory = $False, HelpMessage = 'The file name that lists the triggers names to stop before deployment.')]
    [String]$triggerStopBlobName="",
    [Parameter(Mandatory = $False, HelpMessage = 'The file name that lists the triggers names to start after deployment.')]
    [String]$triggerStartBlobName="",
    [Parameter(Mandatory = $False, HelpMessage = 'Pass this if you are using trigger file names.')]
    [String]$triggerSASToken="",
    [Parameter(Mandatory = $False, HelpMessage = 'Pass this if you are using trigger file names. The account for triggerSASToken')]
    [String]$triggerStorageAccountName

)
# Deploy a data factory using the ARM template published to git.
# Run this from a branch after you have merged your adf_publish branch
$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"
$projectsFolder = "{0}\{1}" -f $devOpsProjectFolder, "Projects"

if ($triggerSASToken) {
    Write-Warning "The use of the triggerSAStoken parameter is deprecated and will be removed in a future release."
}
$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile
$resourceGroupName = $parameters.parameters.dataFactoryResourceGroupName.value

if (!$rootParameterFile){
    $rootParameterFile = $parameters.parameters.dataFactoryRootParameterFileName.value
}
if (!$adfParameterFile) {
    $adfParameterFile = "{0}.json" -f $parameters.parameters.dataFactoryName.value
}

# support default file names generated by ADF GUI
if (-not $publishedArmTemplateFileName) {
    if ($linkedTemplate) {
        $publishedArmTemplateFileName = "ArmTemplate_master.json"
    } else {
        $publishedArmTemplateFileName = "ARMTemplateForFactory.json"
    }
}
if (-not $publishedArmParameterFileName) {
    if ($linkedTemplate) {
        $publishedArmParameterFileName = "ArmTemplateParameters_master.json"
    } else {
        $publishedArmParameterFileName = "ARMTemplateParametersForFactory.json"
    }
}

# if you want to disable/enable triggers for a release, upload text files to a container called adftriggers in your
# dev storage account and create a sas token
if ($triggerStopBlobName -or $triggerStartBlobName) {
    $containerName = "adftriggers"

    $storageContext = New-AzStorageContext -StorageAccountName $triggerStorageAccountName -UseConnectedAccount
    if(-not(Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue))
    {
        throw "Trigger start and stop files must be uploaded to container '$containerName'. The SAS token is invalid or no such container exists in $triggerStorageAccountName."
    } else {

        if ($triggerStartBlobName) {
            $startFilePath = New-TemporaryFile
            Get-AzStorageBlobContent -Container $containerName -Blob $triggerStartBlobName -Destination $startFilePath -Context $storageContext -Force -ErrorAction Stop
        }
        if ($triggerStopBlobName) {
            $stopFilePath = New-TemporaryFile
            Get-AzStorageBlobContent -Container $containerName -Blob $triggerStopBlobName -Destination $stopFilePath -Context $storageContext -Force -ErrorAction Stop
        }
    }
}
function Set-LinkedAdfArmBlobs {
    param($ctx, $container, $storagefolder, $localFolder)

    if(-not(Get-AzStorageContainer -Name $container -Context $ctx -ErrorAction SilentlyContinue))
    {
        Write-Host "Creating Container for linked ARM template upload"
        New-AzStorageContainer -Name $container -Context $ctx

    }
    # Clean the target directory
    Get-AzStorageBlob -Container $container -Context $ctx -Prefix $storagefolder | Remove-AzStorageBlob
    # | ForEach-Object -Process {$_.FullName}
    foreach ($Blob in Get-ChildItem -Path $localFolder)
    {
        $blobName = Join-Path -Path $storagefolder -ChildPath $blob.Name
        Set-AzStorageBlobContent -File $Blob.FullName -Container $container -Blob $blobName -Context $ctx
    }
}
# Generate a name for the merged parameter file.  This will be created in the projects folder and is the actual file that will
# be used to perform the deployment.
$mergedParameterFileName = "{0}.deploy.json" -f $parameters.parameters.dataFactoryName.value
$mergedParameterFilePath = Join-Path -Path $projectsFolder -ChildPath $mergedParameterFileName
$publishedParameterFilePath = Join-Path -Path $publishFolderPath -ChildPath $publishedArmParameterFileName
$publishedArmTemplateFilePath = Join-Path -Path $publishFolderPath -ChildPath $publishedArmTemplateFileName

if ($stopFilePath) {
    Write-Host "Stopping triggers prior to deployment..."
    # Get a list of existing triggers
    $existingTriggers = Get-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroupName -DataFactoryName $parameters.parameters.dataFactoryName.value | Select-Object -ExpandProperty Name
    if (-not $existingTriggers) {
        $existingTriggers = @()
    }
    $triggers=Get-Content -Path $stopFilePath
    foreach($trigger in $triggers)
    {
        if(-not $trigger){
            continue
        }
        Write-Verbose "stopping trigger $trigger in $($parameters.parameters.dataFactoryName.value)"
        if ($existingTriggers.Contains($trigger)) {
            Stop-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroupName -DataFactoryName $parameters.parameters.dataFactoryName.value -Name $trigger -force
        } else {
            Write-Warning "Unable to stop trigger $trigger in $($parameters.parameters.dataFactoryName.value). It doesn't exist!"
        }

    }
}

if ($linkedTemplate) {
    $armRootFolderPath = "Adf/{0}" -f $parameters.parameters.dataFactoryName.value
    $storageAccountName = $parameters.parameters.storageAccountName.value
    $containerName = "armartefacts"
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
    $token = New-AzStorageContainerSASToken -Name $containerName -Permission rl -ExpiryTime (Get-Date).AddMinutes(60.0) -Context $storageContext
    $token = "?{0}" -f $token

    # If the ADF is big then the generated ARM template will be published as a linked template.  In order for ARM to be
    # able to perform a deployment we must upload the linked templates to storage and tell RM to deploy using them

    Write-Host "Copying ARM templates to $storageAccountName/$containerName/$armRootFolderPath..."
    Set-LinkedAdfArmBlobs -ctx $storageContext -container $containerName -storagefolder $armRootFolderPath -localFolder $publishFolderPath
    # Copy the merged parameter file..This is the result of applying the landscape autogenerated adf parameter file with the user maintained
    # parameter file (both found in the DevOps\Projects folder) and then the result of this is merged with the published parameter file
    # i.e. the one ADF creates when you click the Publish button.
    # The result of all this merging should produce a parameter file that is good for use in the target environment.
    # There seems to be a defect with New-AzResourceGroupDeployment when used with linked templates.  parameter value overrides are
    # supposed to take precedence over those in the specified parameter file or defined in the template but for -TemplateParameterUri they do not
    # so we will set them manually here
    $armTemplateBlob = (Join-Path -Path $armRootFolderPath -ChildPath $publishedArmTemplateFileName).Replace("\", "/")
    $templateUrl = (Get-AzStorageBlob -Container $containerName -Blob $armTemplateBlob -Context $storageContext).ICloudBlob.uri.AbsoluteUri
    $containerUri = (Split-Path -Path $templateUrl -Parent).Replace("\", "/")

    Write-Host "Merging parameter files..."
    # First merge the the adf parameters controlled by the dev team into root parameters provided by landscape
    $merge = & "$utilitiesFolder\Get-ParameterFileMerge.ps1" -parameterFile $rootParameterFile -overrideFile $adfParameterFile
    # Fix the defect by adding the overrides
    $propHash = @{}
    if (-not $merge.parameters.containerUri){
        $propHash["containerUri"] = @{value=$containerUri}
    }
    if (-not $merge.parameters.containerSasToken){
        $propHash["containerSasToken"] = @{value=$token}
    }
    $passthruHash = @{Passthru = $passthru.IsPresent }
    $merge.parameters | Add-Member -NotePropertyMembers $propHash @passthruHash | Out-Null
    $merge.parameters.containerUri.value = $containerUri
    $merge.parameters.containerSasToken.value = $token
    # Now merge this into the ADF published parameter file and write the result to disk
    $merge = & "$utilitiesFolder\Get-ParameterFileMerge.ps1" -parameterFile $publishedParameterFilePath -overrideFile $merge -writeToDiskFilename $mergedParameterFileName -force -overwriteExisting | Out-Null

    Write-Host "Copy merged parameter file $mergedParameterFileName..."
    $blobName = Join-Path -Path $armRootFolderPath -ChildPath $mergedParameterFileName
    $parmeterFileBlob = Set-AzStorageBlobContent -File $mergedParameterFilePath -Container $containerName -Blob $blobName -Context $storageContext
    $parameterUrl = $parmeterFileBlob.ICloudBlob.uri.AbsoluteUri

    Write-Host "Deploying datafactory $($parameters.parameters.dataFactoryName.value) using linked ARM template..."
    New-AzResourceGroupDeployment -ResourceGroupName $parameters.parameters.dataFactoryResourceGroupName.value -Name $mergedParameterFileName `
      -TemplateUri $templateUrl -QueryString $token -TemplateParameterFile $mergedParameterFilePath
} else {
    Write-Host "Merging parameter files..."
    # First merge the root parameters provided by landscape into the adf parameters controlled by the dev team
    $merge = & "$utilitiesFolder\Get-ParameterFileMerge.ps1" -parameterFile $rootParameterFile -overrideFile $adfParameterFile
    # Now merge this into the ADF published parameter file and write the result to disk
    $merge = & "$utilitiesFolder\Get-ParameterFileMerge.ps1" -parameterFile $publishedParameterFilePath -overrideFile $merge -writeToDiskFilename $mergedParameterFileName -force -overwriteExisting | Out-Null

    Write-Host "Deploying datafactory $($parameters.parameters.dataFactoryName.value)..."
    New-AzResourceGroupDeployment -ResourceGroupName $parameters.parameters.dataFactoryResourceGroupName.value -Name $mergedParameterFileName `
    -TemplateParameterFile $mergedParameterFilePath -TemplateFile $publishedArmTemplateFilePath
}
if ($startFilePath) {
    Write-Host "Starting triggers after deployment..."
    # Get a list of existing triggers
    $existingTriggers = Get-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroupName -DataFactoryName $parameters.parameters.dataFactoryName.value | Select-Object -ExpandProperty Name
    if (-not $existingTriggers) {
        $existingTriggers = @()
    }
    $triggers=Get-Content -Path $startFilePath
    foreach($trigger in $triggers)
    {
        if(-not $trigger){
            continue
        }
        Write-Verbose "Starting $trigger in $($parameters.parameters.dataFactoryName.value)"
        if ($existingTriggers.Contains($trigger)) {
            Start-AzDataFactoryV2Trigger -ResourceGroupName $resourceGroupName -DataFactoryName $parameters.parameters.dataFactoryName.value -Name $trigger -force
        } else {
            Write-Warning "Unable to start trigger $trigger in $($parameters.parameters.dataFactoryName.value). It doesn't exist!"
        }
    }
}
