param(
    [Parameter(Mandatory=$true)] [string]$parameterFile,
    [Parameter(Mandatory=$false, ParameterSetName="ForMe")] [switch]$forMe,
    [Parameter(Mandatory=$false, ParameterSetName="ForCitrix")] [switch]$forCitrixCloud,
    [Parameter(Mandatory=$false)] [string]$customRuleName,
    [Parameter(Mandatory=$false)] [switch]$deleteRule
)

$devOpsProjectFolder = (Get-Item -Path $PSScriptRoot).Parent.FullName
$utilitiesFolder = "{0}\{1}" -f $devOpsProjectFolder, "Utilities"

$parameters = & "$utilitiesFolder\Get-Parameters.ps1" -parameterFile $parameterFile

$serverName = $parameters.parameters.sqlServerName.value
$rgName = $parameters.parameters.sqlServerResourceGroupName.value
$location = $parameters.parameters.location.value

function Set-Rule {
    param(
        [string] $rName, [string] $rIpStart, [string] $rIpEnd
    )
    # Matching a rule by its name is case sensitive so make it case insensitive
    foreach($rule in Get-AzSqlServerFirewallRule -ServerName $serverName -ResourceGroupName $rgName) {
        if ($rule.FirewallRuleName -eq $rName) {
            $fRule = $rule
            $rName = $rule.FirewallRuleName
        }
    }

    if (-not $fRule) {
        if ($deleteRule) {
            Write-Warning "Firewall rule '$rName' cannot be deleted because it doesn't exist in $serverName"
        } else  {
            Write-Host "Add a new firewall rule '$rName'"
            New-AzSqlServerFirewallRule -FirewallRuleName $rName -StartIpAddress $rIpStart -EndIpAddress $rIpEnd -ServerName $serverName -ResourceGroupName $rgName
        }
    } else {
        if ($deleteRule) {
            Write-Host "Deleting existing firewall rule '$rName'"
            $lockScope = "subscriptions/{0}/resourceGroups/{1}" -f $parameters.parameters.subscriptionId.value, $parameters.parameters.dataFactoryResourceGroupName.value
            $locks = Get-AzResourceLock -scope $lockScope
            if ($locks) {
                $locks | Remove-AzResourceLock -Force | Out-Null
            }
            Remove-AzSqlServerFirewallRule -FirewallRuleName $rName -ServerName $serverName -ResourceGroupName $rgName
            foreach ($lock in $locks) {
                New-AzResourceLock -LockName $lock.Name -ResourceGroupName $parameters.parameters.dataFactoryResourceGroupName.value -LockLevel $lock.Properties.Level -Force
            }
        } else {
            Write-Host "Updating existing firewall rule '$rName'"
            Set-AzSqlServerFirewallRule -FirewallRuleName $rName -StartIpAddress $rIpStart -EndIpAddress $rIpEnd -ServerName $serverName -ResourceGroupName $rgName
        }
    }
}


if ($forMe) {
    $ruleName="landscape"
    $ipAddressStart = (Invoke-WebRequest -uri "https://api.ipify.org/" -UseBasicParsing).Content
    $ipAddressEnd = $ipAddressStart
}
if ($forMe) {
    if (-not [String]::IsNullOrEmpty($customRuleName)) {
        $ruleName = $customRuleName
    }
    Set-Rule -rName $ruleName -rIpStart $ipAddressStart -rIpEnd $ipAddressEnd
} elseif ($forCitrixCloud) {

    if ($location -eq "West Europe") {
        # Only need to call this is allow azure services is off
        $ruleName="CitrixVDA1"
        $ipAddressStart = "10.234.2.45"
        $ipAddressEnd = "10.234.2.45"
        Set-Rule -rName $ruleName -rIpStart $ipAddressStart -rIpEnd $ipAddressEnd
        $ruleName="CitrixVDA2"
        $ipAddressStart = "10.234.2.27"
        $ipAddressEnd = "10.234.2.27"
        Set-Rule -rName $ruleName -rIpStart $ipAddressStart -rIpEnd $ipAddressEnd
    }
    elseif ($location -eq "North Europe") {
        #only 1 VDA in Dublin currently
        $ruleName="CitrixVDA1"
        $ipAddressStart = "13.74.11.33"
        $ipAddressEnd = "13.74.11.33"
        Set-Rule -rName $ruleName -rIpStart $ipAddressStart -rIpEnd $ipAddressEnd
    }
}
