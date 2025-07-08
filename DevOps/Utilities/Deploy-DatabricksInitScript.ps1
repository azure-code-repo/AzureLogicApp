param(
	[Parameter(Mandatory = $true)][string]$applicationId,
	[Parameter(Mandatory = $true)][string]$spnSecret,
	[Parameter(Mandatory = $true)][string]$resourceGroup,
	[Parameter(Mandatory = $true)][string]$databricksWorkspace,
	[Parameter(Mandatory = $true)][string]$databricksHost,
	[Parameter(Mandatory = $true)][string]$subscriptionId,
	[Parameter(Mandatory = $true)][string]$tenantId,
	[Parameter(Mandatory = $true)][string]$artifactPath,
	[Parameter(Mandatory = $true)][string]$destinationPath
)
$URI = "https://login.microsoftonline.com/$tenantId/oauth2/token/"

$Secret = [System.Web.HttpUtility]::UrlEncode($spnSecret)
$BodyText="grant_type=client_credentials&client_id=$applicationId&resource=https://management.core.windows.net/&client_secret=$Secret"
$Response = Invoke-RestMethod -Method POST -Body $BodyText -Uri $URI -ContentType application/x-www-test-urlencoded
$ManagementAccessToken = $Response.access_token

Write-Verbose "Getting new AAD Databricks Token"
$BodyText="grant_type=client_credentials&client_id=$applicationId&resource=2ff814a6-TEST-4ab8-test-cd0e6f879c1d&client_secret=$Secret"
$Response = Invoke-RestMethod -Method POST -Body $BodyText -Uri $URI -ContentType application/x-www-test-urlencoded
$DatabricksAccessToken = $Response.access_token

$Header = @{
    "Authorization" = "Bearer $DatabricksAccessToken"
	"X-Databricks-Azure-SP-Management-Token"   = $ManagementAccessToken;
	"X-Databricks-Azure-Workspace-Resource-Id" = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Databricks/workspaces/$databricksWorkspace"
}
$Header | Out-String | Write-Host
$Body = (@{
    path="$destinationPath";
    format="AUTO";
    language="PYTHON";
    content=[convert]::ToBase64String((Get-Content -path "$artifactPath" -Encoding byte));
    overwrite="true";
  } | ConvertTo-Json -Compress)
$Body | Out-String | Write-Host
Invoke-WebRequest -URI "$databricksHost/api/2.0/workspace/import" -Method Post -Headers $Header -Body $Body

Write-Host "Deploy-DatabricksInitScript.ps1 script execution completed."
