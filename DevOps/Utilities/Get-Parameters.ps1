[CmdletBinding(DefaultParameterSetName="fromCache")]
Param
(
    [Parameter(Position = 0, Mandatory = $True, ParameterSetName='fromCache', HelpMessage = 'Specify the parameter file')]
    [Parameter(Position = 0, Mandatory = $True, ParameterSetName='bootStrap', HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,
    [Parameter(Mandatory = $False, ParameterSetName='fromCache', HelpMessage = 'Specify the parameter override file.  Use this to set specific values to something else. Useful if you need to create multiple instances of components.')]
    [Parameter(Mandatory = $False, ParameterSetName='bootStrap', HelpMessage = 'Specify the parameter override file.  Use this to set specific values to something else. Useful if you need to create multiple instances of components.')]
    [String]$overrideFile="",
    [Parameter(Mandatory = $False, ParameterSetName='bootStrap', HelpMessage = 'Specify if you want to a specific landscape storage account in the event the parameter file is not available on the local disk.')]
    [Hashtable]$bootStrap,
    [Parameter(Mandatory = $False, ParameterSetName='fromCache', HelpMessage = 'Specify if you want to use landscape''s global storage account in CDE-01 the event the parameter file is not available on the local disk.')]
    [switch]$fromGlobalCache
)

$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"

function Copy-Property{
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true)]$InputObject,
          $SourceObject,
          [string[]]$Property,
          [switch]$Passthru)

          $passthruHash=@{Passthru=$passthru.IsPresent}

          $propHash=@{}
          $property | Foreach-Object {
                        $propHash+=@{$_=$SourceObject.$_}
                      }
          $inputObject | Add-Member -NotePropertyMembers $propHash @passthruHash
        }
$tokens = $parameterFile.Split(".")
if ($tokens.Count -eq 2) {
    # Assume a contracted parameter file name was passed.
    $parameterFile = "{0}.$parameterFile.json" -f "parameters"
}

if ($overrideFile -ne "")
{
    $newFile = & "$utilitiesFolder\Get-ParametersFileName.ps1" -parameterFile $parameterFile -overrideFile $overrideFile

    # if the override file doesn't exist, create it
    try {
        $params = @{
            parameterFile=$newFile
            erroraction='silentlycontinue'
        }
        if ($bootStrap) {
            $params.bootStrap = $bootStrap
        }
        $paramFile = & "$utilitiesFolder\Get-ParametersFile.ps1" @params

        # handle the case when the override file doesn't have a valur in $suffix.  In this case we want to apply the overrides to
        # the main parameter file rather than create a new one with the suffix added to the name
        throw [System.IO.FileNotFoundException] "Override parameters will be applied to the main parameter file $parameterFile."
    }
    catch {
        Write-Host "New param override file doesn't exist.  Creating it"
        $params = @{
            parameterFile=$overrideFile
        }
        if ($bootStrap) {
            $params.bootStrap = $bootStrap
        }
        elseif ($fromGlobalCache) {
            $params.fromGlobalCache = $true
        }
        $overrideParameters = & "$utilitiesFolder\Get-Parameters.ps1" @params
        $params.parameterFile = $parameterFile
        $parameters = & "$utilitiesFolder\Get-Parameters.ps1" @params

        $properties = $overrideParameters.parameters | Get-Member -MemberType Properties | Select-Object
        $properties.GetType
        ForEach($property in $properties) {
            $parameters.parameters.psobject.properties.remove($property.Name)
            Copy-Property -InputObject $parameters.parameters -Property $property.Name -SourceObject $overrideParameters.parameters

        }
        $parameterProjectFile = "{0}\Projects\$newFile" -f $devOpsProjectFolder
        $parameters | ConvertTo-JSON -Depth 10 | Out-File -filepath $parameterProjectFile -Force
        Write-Host "Overridden parameter file created at: $parameterProjectFile"

    }
    # return the overridden file
    $parameterFile = $newFile
}
$params = @{
    parameterFile=$parameterFile
}
if ($bootStrap) {
    $params.bootStrap = $bootStrap
}
elseif ($fromGlobalCache) {
    $params.fromGlobalCache = $true
}
$paramFile = & "$utilitiesFolder\Get-ParametersFile.ps1" @params
$parameters = Get-Content -Path $paramFile -Raw | ConvertFrom-JSON
return $parameters
