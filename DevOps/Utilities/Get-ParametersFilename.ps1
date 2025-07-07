Param
(
    [Parameter(Mandatory = $True, HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,
    [Parameter(Mandatory = $False, HelpMessage = 'Specify the parameter override file.  Use this to set specific values to something else. Useful if you need to create multiple instances of components.')]
    [String]$overrideFile=""
)

$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName

$suffix = "";
if ($overrideFile -ne "")
{
    # construct the name for the overriden file.  We want to chop out everything except the word that describes the override
    $suffix = $overrideFile -replace "json", ""
    $suffix = $suffix -replace "parameters", ""
    $suffix = $suffix -replace "overrides", ""
    $suffix = $suffix -replace "override", ""
    $suffix = $suffix -replace "\..\.", "."
    $suffix = $suffix -replace "\.[0-9]+\.", "."
    $suffix = $suffix -replace "\.", ""

    if ($suffix -eq "")
    {
        # replace the main parameter file rather that create a new one
        $newFile = $parameterFile
    } else {
        $newFile = $parameterFile -replace "parameters\.", "parameters.$suffix."
    }
    #Write-Output "New override parameter filename is $newFile"

    # return the overridden file
    $parameterFile = $newFile
}
return $parameterFile
