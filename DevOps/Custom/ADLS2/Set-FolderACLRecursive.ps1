$rootPath = (Get-Item -Path $PSScriptRoot).FullName
# Parameters
# For token authN & authZ
# svc-b-da-p-80010-ecosystem-adls-permissions
$clientId="1df7846b-461f-42f4-9fba-4b193824756e"
$clientSecret = "??"
# set true if you want to get bearer token using the client secret
$useClientSecret = $true
#$clientId="35757ac0-0aa9-4e62-9ef5-b39734c989ff" #svc-b-da-b-80066-ina-dataowner
$tenant="f66fae02-5d36-495b-bfe0-78a6ff9f8e6e"
# Identify location to apply ACL update from
$accountName = "dbstorageda06b80066adls"
$container = "unilever"

#$rootDir = "UniversalDataLake/ExternalSources/SecondarySales"
#$rootDir = "UniversalDataLake/ExternalSources/FeatureVision"
$rootDir = "UniversalDataLake/InternalSources/UltraDT/BlobFileShare/ACCH_TRANSACTION"

# Specify how the ACL should be updated. 2 modes:
#  1. Absolute ACL - gets applied across the entire structure - assign $absoluteAcl - including default permissions, masks, etc.
#       Eg: user::rwx,default:user::rwx,group::r-x,default:group::r-x,other::---,default:other::---,mask::rwx,default:mask::rwx,user:mary@contoso.com:rwx,default:user:mary@contoso.com:rwx,group:5117a2b0-f09b-44e9-b92a-fa91a95d5c28:rwx,default:group:5117a2b0-f09b-44e9-b92a-fa91a95d5c28:rwx
#  2. Merge an ACE with existing ACL - assign $mergePricipal, $mergeType & $mergePerms
# $absoluteAcl & $mergePrincipal are mutually exclusive - 1 of them must be $null
#$absoluteAcl = "[scope:][type]:[id]:[permissions],[scope:][type]:[id]:[permissions]"
$mergeType = "group"
$mergePerms = "r-x"

$mergePrincipal = "c0505d9b-eef2-45e2-9acc-23df836b7928"
# Use this variable in conjunction with $mergePrincipal & $mergeType to remove an ACE
$removeEntry = $false

# Number of parallel runspaces to execute this operation
$numRunspaces = 100
# This should always be $true. Set to $false to make the whole operation run single-threaded
$useRunspaces = $true
# Max # of items per parallel batch;  Think REST API ignores this.  Returns 500 items regardless
$maxItemsPerBatch = 1000

# Accumulate processing stats (thread safe counters)
$itemsStats = @{
    itemsProcessed = New-Object System.Threading.SemaphoreSlim -ArgumentList @(0)
    itemsUpdated = New-Object System.Threading.SemaphoreSlim -ArgumentList @(0)
    itemsErrors = New-Object System.Threading.SemaphoreSlim -ArgumentList @(0)
}
$oldProgressPreference = $Global:ProgressPreference
$Global:ProgressPreference = "SilentlyContinue"
# Setup headers for subsequent calls to DFS REST API
$headers = @{
    "x-ms-version" = "2018-11-09"
}
$baseUri = "https://$accountName.dfs.core.windows.net/$container"
$baseListUri = $baseUri + "`?resource=filesystem&recursive=true&upn=true&maxResults=$maxItemsPerBatch"
if ($null -ne $rootDir) {
    $baseListUri = $baseListUri + "&directory=$rootDir"
}
$addRootDir = $null -eq $rootDir -or $rootDir -eq "/"
# If we have an absolute ACL, we actually need 2 versions; 1 for directories (containing default perms) & 1 for files without default perms
if ($null -ne $absoluteAcl) {
    $entries = $absoluteAcl.Split(',') | ForEach-Object {
        $entry = $_.split(':')
        if ($entry[0] -ne "default") {
            $_
        }
    }
    $fileAbsoluteAcl = $entries -join ','
}
$logTimeStamp = (Get-Date -UFormat %Y-%m-%dT%R%S).Replace(":","")
# Parameters shared across all workers
$itemParams = @{
    absoluteAcl = $absoluteAcl
    fileAbsoluteAcl = $fileAbsoluteAcl
    mergePrincipal = $mergePrincipal
    mergeType = $mergeType
    mergePerms = $mergePerms
    removeEntry = $removeEntry
    baseUri = $baseUri
    requestHeaders = $headers
    tokenElapseDelta = New-TimeSpan -Seconds 120
    clientId = $clientId

    tenant = $tenant
    batchNumber = 0
    logFile = "$rootPath\Set-FolderACLRecursive$logTimeStamp.log"
    errorLogFile = "$rootPath\Set-FolderACLRecursive$logTimeStamp.err"
}
if ($useClientSecret) {
    $itemParams.clientSecret = $clientSecret
}
# Token acquisition - needs to be callable from background Runspaces
Function New-AccessToken1($sharedParams) {
    # Acquire auth token
    $body = @{
        client_id = $sharedParams.clientId
        client_secret = $sharedParams.clientSecret
        scope = "https://storage.azure.com/.default"
        grant_type = "client_credentials"
    }
    $token = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($sharedParams.tenant)/oauth2/v2.0/token" -Body $body
    $sharedParams.requestHeaders.Authorization = "Bearer " + $token.access_token
    $sharedParams.tokenExpiry = (Get-Date).AddSeconds($token.expires_in)
}
Function New-AccessToken($sharedParams) {
    # Acquire auth token
    $ResourceId="https://storage.azure.com/"
    $token=Get-AdalToken -Resource $ResourceId -ClientId $sharedParams.clientId -Authority "https://login.microsoftonline.com/$($sharedParams.tenant)/"
    $sharedParams.requestHeaders.Authorization = "Bearer " + $token.AccessToken
    $sharedParams.tokenExpiry = $token.ExpiresOn.LocalDateTime
}
# Check if token needs to be renewed
Function Reset-TokenExpiry($sharedParams) {
    if ($sharedParams.tokenExpiry - (Get-Date) -le $sharedParams.tokenElapseDelta) {
        if ($sharedParams.clientSecret) {
            New-AccessToken1 $sharedParams
        } else {
            New-AccessToken $sharedParams
        }

    }
}
$startedAt = Get-Date
# Acquire initial token
Reset-TokenExpiry $itemParams

# Worker script block
$scriptBlock = {
    Param ($items, $sharedParams)
    $callStart = Get-Date
    $Global:ProgressPreference = "SilentlyContinue"
    $items | ForEach-Object {
        #$host.UI.WriteDebugLine("Processing: " + $_.name)
        $itemsStats.itemsProcessed.Release() | Out-Null
        $item = $_
        try {
            if ($_.isDirectory) {
                $updatedAcl = $sharedParams.absoluteAcl
            }
            else {
                $updatedAcl = $sharedParams.fileAbsoluteAcl
            }
            # If we're merging an entry into the existing file's ACL, then we need to retrieve the full ACL first
            if ($null -ne $sharedParams.mergePrincipal) {
                try {
                    Reset-TokenExpiry $sharedParams

                    $aclResp = Invoke-WebRequest -Method Head -Headers $sharedParams.requestHeaders "$($sharedParams.baseUri)/$($_.name)`?action=getAccessControl&upn=true"
                    $currentAcl = $aclResp.Headers["x-ms-acl"]
                    # Check if we need to update the ACL
                    $entryFound = $false
                    $entryModified = $false
                    # Process the ACL. Format of each entry is; [scope:][type]:[id]:[permissions]
                    $updatedEntries = $currentAcl.Split(',') | ForEach-Object {
                        $entry = $_.split(':')
                        # handle 'default' scope
                        $doOutput = $true
                        $idxOffset = 0
                        if ($entry.Length -eq 4) {
                            $idxOffset = 1
                        }
                        if ($entry[$idxOffset + 0] -eq $sharedParams.mergeType -and $entry[$idxOffset + 1] -eq $sharedParams.mergePrincipal) {
                            $entryFound = $true
                            if ($sharedParams.removeEntry) {
                                # Remove the entry by not outputing if from this expression
                                $doOutput = $false
                                $entryModified = $true
                            }
                            elseif ($entry[$idxOffset + 2] -ne $sharedParams.mergePerms) {
                                $entry[$idxOffset + 2] = $sharedParams.mergePerms
                                $_ = $entry -join ':'
                                $entryModified = $true
                            }
                        }
                        if ($doOutput) {
                            $_
                        }
                    }
                    if ($entryFound -eq $true -and $entryModified -eq $true) {
                        $updatedAcl = $updatedEntries -join ','
                    } elseif ($entryFound -eq $true) {
                        $updatedAcl = $null
                    } elseif ($sharedParams.removeEntry -ne $true) {
                        $updatedAcl = "$currentAcl,$($sharedParams.mergeType)`:$($sharedParams.mergePrincipal)`:$($sharedParams.mergePerms)"
                        if ($_.isDirectory) {
                            $updatedAcl = $updatedAcl + ",default`:$($sharedParams.mergeType)`:$($sharedParams.mergePrincipal)`:$($sharedParams.mergePerms)"
                        }
                    }
                }
                catch [System.Net.WebException] {
                    $errorMessage  = "Batch $($sharedParams.batchNumber): Failed to retrieve existing ACL for $($item.name). This file will be skipped. Details: " + $_.Exception.Message
                    Add-Content -Path $sharedParams.errorLogFile -Value $errorMessage
                    $host.UI.WriteErrorLine($errorMessage)
                    $itemsStats.itemsErrors.Release()
                    $updatedAcl = $null
                }
            }
            if ($null -ne $updatedAcl) {
                #$host.UI.WriteDebugLine("Updating ACL for: $($_.name):$updatedAcl")
                try {
                    Reset-TokenExpiry $sharedParams
                    Invoke-WebRequest -Method Patch -Headers ($sharedParams.requestHeaders + @{"x-ms-acl" = $updatedAcl}) "$($sharedParams.baseUri)/$($_.name)`?action=setAccessControl" | Out-Null
                    $itemsStats.itemsUpdated.Release()
                }
                catch [System.Net.WebException] {
                    $errorMessage  = "Batch $($sharedParams.batchNumber): Failed to update ACL for $($item.name). Details: " + $_.Exception.Message
                    Add-Content -Path $sharedParams.errorLogFile -Value $errorMessage
                    $host.UI.WriteErrorLine("Failed to update ACL for $($item.name). Details: " + $_)
                    $itemsStats.itemsErrors.Release()
                }
            }
        }
        catch {
            $host.UI.WriteErrorLine("Unknown failure processing $($item.name). Details: " + $_)
            $itemsStats.itemsErrors.Release()
        }
    }
    $elapsedTime = $(get-date) - $callStart
    $totalTime = "{0:HH:mm:ss.fff}" -f ([datetime]$elapsedTime.Ticks)
    $log = "Batch no: $($sharedParams.batchNumber) completed at $(Get-Date). Elapsed time: $totalTime"
    $host.UI.WriteLine("$log")
    Add-Content -Path $sharedParams.logFile -Value $log
}
# Setup our Runspace Pool
if ($useRunspaces) {
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $sessionState.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    # Marshall variables & functions over to the RunspacePool
    $sessionState.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'itemsStats', $itemsStats, ""))
    $sessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'New-AccessToken', (Get-Content Function:\New-AccessToken -ErrorAction Stop)))
    $sessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList 'Reset-TokenExpiry', (Get-Content Function:\Reset-TokenExpiry -ErrorAction Stop)))
    $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $numRunspaces, $sessionState, $Host)
    $runspacePool.Open()
}
$runSpaces = [System.Collections.ArrayList]@()

# Loop through the entire listing until we've processed all files & directories
$continuationToken = $null
$StartedAt = Get-Date
$batchCount = 0

New-Item -Path $itemParams.logFile | Out-Null
New-Item -Path $itemParams.errorLogFile | Out-Null
$host.UI.WriteLine("Log file: $($itemParams.logFile)")
if ($useClientSecret) {
    Add-Content -Path $itemParams.logFile  -Value "Using client secret to obtain bearer token."
} else {
    Add-Content -Path $itemParams.logFile  -Value "Using ADAL to obtain bearer token."
}
Add-Content -Path $itemParams.logFile  -Value "Begin Processing at: $StartedAt"
Add-Content -Path $itemParams.logFile -Value "ClientId: $clientId"
Add-Content -Path $itemParams.logFile -Value "Tenant: $tenant"
Add-Content -Path $itemParams.logFile -Value "ADLS Gen2: $accountName"
if ($mergePrincipal) {
    Add-Content -Path $itemParams.logFile -Value "Merge Principal: $mergePrincipal"
    Add-Content -Path $itemParams.logFile -Value "Merge Principal Type: $mergeType"
    Add-Content -Path $itemParams.logFile -Value "Merge Principal Permissions: $mergePerms"
} else {
    Add-Content -Path $itemParams.logFile -Value "Absolute ACL: $absoluteAcl"
}
Add-Content -Path $itemParams.logFile -Value "Root directory: $rootDir"
Add-Content -Path $itemParams.logFile -Value "Use runspaces: $useRunspaces"
if ($removeEntry) {
    Add-Content -Path $itemParams.logFile -Value "Remove ACLs: $removeEntry"
}
if ($useRunspaces) {
    Add-Content -Path $itemParams.logFile -Value "Number of Runspaces: $numRunspaces"
}
Add-Content -Path $itemParams.logFile -Value "Batch size: $maxItemsPerBatch"

do {
    $listUri = $baseListUri
    # Include the continuation token if we've got one
    if ($null -ne $continuationToken) {
        $listUri = $listUri + "&continuation=" + [System.Web.HttpUtility]::UrlEncode($continuationToken)
    }
    try {
        Reset-TokenExpiry $itemParams
        $listResp = Invoke-WebRequest -Method Get -Headers $itemParams.requestHeaders $listUri
        $batchCount++
        $hash = $itemParams.Clone()
        $hash.batchNumber = $batchCount
        $items = ($listResp.Content | ConvertFrom-Json).paths
        if ($addRootDir) {
            $rootDirEntry = [pscustomobject]@{
                name = '/'
                isDirectory = $true
            }
            $items = @($rootDirEntry) + $items
            $addRootDir = $false
        }
        if ($useRunspaces) {
            # Dispatch this list to a new runspace
            $ps = [powershell]::Create().
                AddScript($scriptBlock).
                AddArgument($items).
                AddArgument($hash)
            $ps.RunspacePool = $runspacePool
            $runSpace = New-Object -TypeName psobject -Property @{
                PowerShell = $ps
                Handle = $($ps.BeginInvoke())
            }
            $runSpaces.Add($runSpace) | Out-Null
        }
        else {
            Invoke-Command -ScriptBlock $scriptBlock -ArgumentList @($hash, $itemParams)
        }

        $continuationToken = $listResp.Headers["x-ms-continuation"]
    }
    catch [System.Net.WebException] {
        $host.UI.WriteErrorLine("Failed to list directories and files. Details: " + $_)
    }
} while ($listResp.StatusCode -eq 200 -and $null -ne $continuationToken)
Add-Content -Path $itemParams.logFile -Value "Total number of batches submitted: $batchCount"
$host.UI.WriteLine("---------------------------------------------")
$host.UI.WriteLine("Total number of batches submitted: $batchCount")
# Cleanup
$host.UI.WriteLine("Waiting for completion & cleaning up")
Add-Content -Path $itemParams.logFile -Value "Waiting for completion & cleaning up"
$host.UI.WriteLine("---------------------------------------------")
$cleanUpErrors=0
while ($runSpaces.Count -gt 0) {
    $idx = [System.Threading.WaitHandle]::WaitAny($($runSpaces | Select-Object -First 64 | ForEach-Object { $_.Handle.AsyncWaitHandle }))
    $runSpace = $runSpaces.Item($idx)
    $runSpace.PowerShell.EndInvoke($runSpace.Handle) | Out-Null
    $runSpace.PowerShell.Dispose()
    $runSpaces.RemoveAt($idx)
}
$Global:ProgressPreference = $oldProgressPreference
$host.UI.WriteLine("---------------------------------------------")
$message = "Completed. Items processed: $($itemsStats.itemsProcessed.CurrentCount), items updated: $($itemsStats.itemsUpdated.CurrentCount), errors: $($itemsStats.itemsErrors.CurrentCount)"
$host.UI.WriteLine($message)
Add-Content -Path $itemParams.logFile -Value $message
$elapsedTime = $(get-date) - $StartedAt
$totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
$message = "Total Job Elapsed time $totalTime"
$host.UI.WriteLine($message)
Add-Content -Path $itemParams.logFile -Value $message
$host.UI.WriteLine("---------------------------------------------")
if ($itemsStats.itemsErrors.CurrentCount -eq 0) {
    Remove-Item -Path $itemParams.errorLogFile | Out-Null
}
