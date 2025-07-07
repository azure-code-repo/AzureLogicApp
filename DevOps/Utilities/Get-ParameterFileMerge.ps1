[cmdletbinding(
    DefaultParameterSetName = 'overwrite'
    )]
Param
(
    [Parameter(Mandatory, Position=0, HelpMessage="The target parameter file.  Override values will be merged into this. Pass the file name to read off disk or the PSCustomObject")]
    [Object]$parameterFile,
    [Parameter(Mandatory, Position=1, HelpMessage="The source parameter file.  Values  from this file will overwrite or be added to the target file.  Pass the file name to read off disk or the PSCustomObject")]
    [Object]$overrideFile,
    [Parameter(Mandatory = $False, ParameterSetName="overwrite", HelpMessage = 'Specify this to persist the overridden file. The existing parameter file will be changed on disk.')]
    [switch]$writeToDisk,
    [Parameter(Mandatory = $False, ParameterSetName="newfile", HelpMessage = 'Specify this to persist the overridden file to a new file. A new parameter file will be created on disk.')]
    [String]$writeToDiskFileName=$null,
    [switch]$force,
    [Parameter(Mandatory = $False, HelpMessage = 'Specify this to ensure only existing values in the target are updated.')]
    [switch]$overwriteExisting
)
#Write-Verbose "1 $parameterFile"
#Write-Verbose "2 $overrideFile"
# merge the values in one parameter file with another
$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$parametersFolder = "{0}\{1}" -f $devOpsProjectFolder, "Projects"
$writeToDiskPath = $null

if ($parameterFile.GetType().Name -eq "String" -and $overrideFile.GetType().Name -eq "String" -and $parameterFile -eq $overrideFile) {
    throw "You cannot merge a file into itself!"
}

if ($overrideFile.GetType().Name -eq "String") {
    if ((Split-Path -Path $overrideFile -NoQualifier) -eq $overrideFile) {
        # No path was passed so we assume the file is in the Projects folder
        $overrideFilePath = Join-Path -Path $parametersFolder -ChildPath $overrideFile

    } else {
        $overrideFilePath = $overrideFile
    }
    Write-Verbose "Merging from $overrideFilePath"
} else {
    Write-Verbose "Merging from a PSObject"
}
if ($parameterFile.GetType().Name -eq "String" -and $parameterFile -eq $writeToDiskFileName) {
    throw "The value specified for 'writeToDiskFilename' cannot be the same as parameterFile.  If you want to overwrite the exisiting main file pass -writeToDisk."
} elseif ($parameterFile.GetType().Name -eq "String") {
    # workout if an absolute path was passed or just a file name that we will assume lives in the projects folder
    if ((Split-Path -Path $parameterFile -NoQualifier) -eq $parameterFile) {
        $parameterFilePath = Join-Path -Path $parametersFolder -ChildPath $parameterFile
    } else {
        $parameterFilePath = $parameterFile
    }
    Write-Verbose "Merging into $parameterFilePath"
} else {
    Write-Verbose "Merging into a PSObject"
}

if ($writeToDisk -and -not $writeToDiskFileName -and -not $parameterFilePath) {
    Write-Warning "The merged values cannot be written to disk because no file name was passed."
} elseif ($writeToDisk) {
    $writeToDiskPath = Join-Path -Path $devOpsProjectFolder -ChildPath "Projects\$parameterFile"
} elseif ($writeToDiskFileName) {
    $writeToDiskPath = Join-Path -Path $devOpsProjectFolder -ChildPath "Projects\$writeToDiskFileName"
}

if ($parameterFilePath -and $parameterFilePath -eq $writeToDiskPath) {
    throw "The value specified for 'writeToDiskFilename' cannot be the same as parameterFile.  If you want to overwrite the exisiting main file pass -writeToDisk."
}

function Copy-Property {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)]$InputObject,
        $SourceObject,
        [string[]]$Property,
        [switch]$Passthru)

    $passthruHash = @{Passthru = $passthru.IsPresent }

    $propHash = @{ }
    $property | Foreach-Object {
        $propHash += @{$_ = $SourceObject.$_ }
    }
    $inputObject | Add-Member -NotePropertyMembers $propHash @passthruHash
}

try {
    if ($parameterFilePath -and -not (Test-Path $parameterFilePath.trim())) {
        Write-Error "Parameter file not found in path $parameterFilePath"
        throw [System.IO.FileNotFoundException]
    } elseif ($parameterFilePath) {
        $parameters = Get-Content -Path $parameterFilePath -Raw | ConvertFrom-JSON
    } else {

        $parameters = $parameterFile
    }
    if ($overrideFilePath -and -not (Test-Path $overrideFilePath.trim())) {
        Write-Error "Override file not found in path $overrideFilePath"
        throw [System.IO.FileNotFoundException]
    } elseif ($overrideFilePath) {
        $overrideParameters = Get-Content -Path $overrideFilePath -Raw | ConvertFrom-JSON
    } else {
        $overrideParameters = $overrideFile
    }
    if (-not $parameters.parameters) {
        Write-Error "No Target"
    }
    $properties = $overrideParameters.parameters | Get-Member -MemberType Properties | Select-Object
    ForEach($property in $properties) {
        if ($overwriteExisting -and ($parameters.parameters).($property.Name)) {
            $parameters.parameters.psobject.properties.remove($property.Name)
            Copy-Property -InputObject $parameters.parameters -Property $property.Name -SourceObject $overrideParameters.parameters
        } elseif ($overwriteExisting -and -not ($parameters.parameters).($property.Name)) {
            Write-Verbose "Parameter $($property.Name) skipped.  Not in target file."
        }
        else {
            # only overwrite values that alrady exist in the target
            $parameters.parameters.psobject.properties.remove($property.Name)
            Copy-Property -InputObject $parameters.parameters -Property $property.Name -SourceObject $overrideParameters.parameters
        }
    }

    if ($writeToDiskPath) {
        $args = @{
            filePath=$writeToDiskPath
           }
        if (!$force){
            $args["NoClobber"]=$true
        }
        $parameters | ConvertTo-JSON -Depth 10 | Out-File @args
        Write-Verbose "Merged parameter file created at: $writeToDiskPath"

    }
    return $parameters
}
catch [System.IO.FileNotFoundException] {
    throw

}
