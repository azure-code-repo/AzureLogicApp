[CmdletBinding()]
Param
(
    [Parameter(Mandatory, Position=0, HelpMessage = 'Specify the parameter file')]
    [String]$parameterFile,
    [Parameter(Mandatory=$false)] [switch]$forMe,
    [Parameter(Mandatory=$false)] [switch]$forCitrix,
    [Parameter(Mandatory=$false)] [string]$ruleName="landscape",
    [Parameter(Mandatory=$false)] [switch]$deleteRule
)

if (-not ($forMe -or $forCitrix)){
    Write-Error "You must pass one or more switches: forMe or forCitrix"
    return
}
$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"

$parameters = & "$utilitiesFolder\Get-Parameters" -parameterFile $parameterFile

$server = Get-AzAnalysisServicesServer -ResourceGroupName $parameters.parameters.analysisServicesResourceGroupName.value -Name $parameters.parameters.analysisServicesName.value
if (-not $server) {
    Write-Error "Whitelisting failed because AAS $($parameters.parameters.analysisServicesName.value) was not found.  Please create AAS and try again."
    return
}
if ($server.state -eq "Paused"){
    Write-Error "Whitelisting failed because AAS $($parameters.parameters.analysisServicesName.value) was in the paused state."
    return
}
if ($server -and -not $server.FirewallConfig -and -not $deleteRule) {
    # trying to set white list when the firewall is disabled. Enable it
    Write-Warning "The firewall is currently disabled.  Whitelisting is not possible."
    return
} elseif ($server -and -not $server.FirewallConfig -and $deleteRule) {
    #can't delete a rule if the firewall is off.  There are no rules
    Write-Warning "The firewall is disabled so there are no rules to delete."
    return
}

function Get-ExistingRule {
    param([string] $ruleName)
    return $server.FirewallConfig.FirewallRules | Where-Object {$_.FirewallRuleName -EQ $ruleName}
}
function Remove-ExistingRule {
    param([string] $ruleName)
    $existing = Get-ExistingRule -ruleName $ruleName

    if ($existing) {
        $server.FirewallConfig.FirewallRules.Remove($existing) | Out-Null
    }
}

if ($forMe) {
     Remove-ExistingRule -ruleName $ruleName
     if (-not $deleteRule) {
        $ipStart = (Invoke-WebRequest -uri "https://api.ipify.org/" -UseBasicParsing).Content
        $rule = New-AzAnalysisServicesFirewallRule -FirewallRuleName $ruleName -RangeStart $ipStart -rangeEnd $ipStart
        $rule.RangeEnd = $rule.RangeStart
        $server.FirewallConfig.FirewallRules.Add($rule)
     }

 }
 if ($forCitrix) {
    # Add rules for Citrix VDA1&2
    Remove-ExistingRule -ruleName "Citrix1"
    Remove-ExistingRule -ruleName "Citrix2"
    if (-not $deleteRule) {
        $rule1 = New-AzAnalysisServicesFirewallRule -FirewallRuleName "Citrix1" -RangeStart "40.67.200.41" -rangeEnd "40.67.200.41"
        $rule2 = New-AzAnalysisServicesFirewallRule -FirewallRuleName "Citrix2" -RangeStart "40.67.210.147" -rangeEnd "40.67.210.147"
        $server.FirewallConfig.FirewallRules.Add($rule1)
        $server.FirewallConfig.FirewallRules.Add($rule2)
    }

}

Set-AzAnalysisServicesServer -Name $parameters.parameters.analysisServicesName.value -ResourceGroupName $parameters.parameters.analysisServicesResourceGroupName.value `
    -FirewallConfig $server.FirewallConfig
