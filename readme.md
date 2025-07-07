# Overview
This is your Azure DevOps team project and GIT repository. If you need to use GIT features then you must have a Dev Ops 'basic' licence.  Contact Landscape to get yours. If you don't need GIT, you can still browse your team project but GIT features will be disabled without a valid basic licence.

# Contacting the Landscape Team
You can contact the landscape team by emailing this address: IATech.AzureLandscape <IATech.AzureLandscape@unilever.com>.  Note that requests for service should be raised through [Service Now](https://unilever.service-now.com/).
Full details for Azure Service Requests [here](https://unilever.sharepoint.com/:w:/r/sites/IATechDevelopersTesters/_layouts/15/Doc.aspx?sourcedoc=%7B4DF24482-C2C3-4E27-80A1-9493A1CAFE73%7D&file=Azure%20Service%20Request%20SOP%20v2.0.docx&action=default&mobileredirect=true).
Whenever you contact landscape be sure to quote the ITSG number assigned to the environment in question.  You dev ITSG is 903766 but your higher environments will each get their own number.

# Documentation
All supporting documentation for new foundation Azure is stored in SharePoint [here](https://unilever.sharepoint.com/sites/IATechDevelopersTesters/Shared%20Documents/Forms/AllItems.aspx?RootFolder=%2Fsites%2FIATechDevelopersTesters%2FShared%20Documents%2FGeneral&FolderCTID=0x012000BD59F07527E67E469D73EA1BB40B85D8).  If you cannot access this link contact landscape and ask for access to I&A Developers & Testers documentation for new foundation Azure.  Don't bug the landscape team with ad hoc requests until you have read the user guide.

# Security
Only authorised individuals can access your application environments.
## Security Groups
Access to your environments and components, and to this team project is controlled by the following user security groups:
1. SEC-ES-DA-d-903766-azure-developer
2. SEC-ES-DA-d-903766-azure-tester
3. SEC-ES-DA-d-903766-azure-devops

You must be in one of these groups in order to work on the project.  Note that your team can opt to take ownership of these groups so that you can self manage starters and leavers.  To do this, contact landscape.  You must nominate a few individuals as project admins then landscape will add these names to your project admin security group SEC-ES-DA-d-903766-ProjectAdmins.

## Data Security
Access to data via public end points is granted uniquely to each user security group per environment.  Data write permissions are not normal granted to users in a production environment.  You can request 'just in time' permissions elevation to access the ability to edit/delete production data for the purposes of support. This must be supported by TDA.  If you are approved for this, nominated individuals will be able to use the portal to activate a production data writer role for a two hour window. [User Guide](https://unilever.sharepoint.com/:w:/r/sites/IATechDevelopersTesters/Shared%20Documents/General/I%26ATech%20Privileged%20Identity%20Management%20-%20UserGuide.docx?d=w09617e0abd0a45aab90d131351b7fc32&csf=1&web=1&e=Sz9DDZ).

## Moving Data Between Environments
All environments are self contained and sandboxed from each other.  If you need to move data between environments e.g. to perform a performance test in Pre-Prod against a full set of production data, ask landscape to provision a dedicated DevOps resource group and ADF.  This will have linked services that point to your ADLS and storage accounts in all environments.

# Starting and Stoping Compute Resources (SqlDW, AAS & Web Apps)
In the developement environment, Developers and Dev Ops personnel can start and stop SqlDW, Azure Analysis Services & Web Apps using the portal.  In all other environments you must use the Webhooks V2 provided by the platform.

# WebhooksV2
Shared Webhooks are available for you to schedule when to start, stop and process your components and data:

* Pause/Resume SqlDw, AAS & Web Apps
* Scale/Resize SqlDb, SqlDW, AAS & Web Apps
* Process AAS cubes using TMSL

Be sure to use V2 and not legacy V1 versions.  See 'I&ATech WebhooksV2-UserGuide.docx'.

# Deploying into Higher Environments
Manual deployments are not allowed.  The permissions required to do this are not granted to individuals.  Instead you must create a build and release pipeline.

# Secrets
## Key Vault Secrets
Landscape are the only team that can edit your key vault.  If you need to connect to datasources then you must ask the landscape team to add the credentials to key vault so that they can be used by your ADF linked services.  All your linked services should be created so that they read secrets on the fly.  You can
create new ones yourselves once landscape confirm the secret name.

In the dev environment only, members of the developer and dev ops groups can read key vault through its public end point.  Your dev key vault is named
bieno-da-d-903766-kv-01.  You can read it from PowerShell using the script DevOps\Utilities\Get-KeyvaultSecret.ps1 or the commandlet Get-AzKeyVaultSecret.

## Monitoring Secrets
DevOps personnel are responsible to monitor the expiry dates of secrets.  When landscape add a secret to key vault they will set the key vault secret expiry date to match the actual expiry date of the secret, if it has one.  To see a list of your secrets with their expiry date open the [platform dashboard:](https://app.powerbi.com/groups/me/reports/eacd2579-db6a-48ce-aa19-825bab8bf2db/ReportSection830fa28d1e7b03b38838?ctid=f66fae02-5d36-495b-bfe0-78a6ff9f8e6e&openReportSource=ReportInvitation&bookmarkGuid=Bookmark8111ca604aa0cb402521)
If you wish to be alerted about expring secrets ask landscape.

# Databricks Workspace Access
Access to ADB workspaces is controlled by the platform.  Users are added to each workspace by a scheduled job that reads your security groups.  Any user that is added manually will be removed automatically by this job.  Under certain circumstances this synchronisation job can be configured to meet project specific requirements.  Ask Landscape.

# Developer Desktop
We have two options, Citrix cloud and Dev Test Labs.  Note that you only need to use these services for certain development/support activities and it is possible that your don't need them at all.  E.g. if you only work on ADF you will be able to author data sets and pipleines from any browser. If you are developing PowerShell for CICD you may need DTL in order to test scripts that connect to components with a firewall.
## Citrix Cloud
You can launch a variety of desk top applications using this service.  REquest from Landscape is you need to use it. Access here: [I&A's Citrix Cloud Desktop](https://unilever.cloud.com/Citrix/StoreWeb/#/apps/all). Note that you cannot use PowerShell with this service.  Use dev test labs instead.
## Dev Test Labs (DTL)
The only way to access DTL is via the RDP app published in citrix cloud.  You must launch this application and connect to your DTL Vm using its IP address. See the Amsterdam user guide for more details.

If your project is approved to use DTL you need to be added to this on prem AD group: SEC-ES-da-p-56728-InA-DTLUser, ask landscape to do this.  Once you are in this group you will be able to see I&A's lab.  All DTL vms are hosted in a dedicated subnet and component firewalls are preconfigured to allow inbound DTL traffic.

Depending on which region your resources have been provisioned in please use the approriate DTL resource.

  - Amsterdam [bnlwe-da04-dtl](https://portal.azure.com/#@Unilever.onmicrosoft.com/resource/subscriptions/105fbd8d-388f-4b19-9fda-d56f44121122/resourceGroups/bnlwe-da04-p-00000-dtl-rg/providers/Microsoft.DevTestLab/labs/bnlwe-da04-dtl/overview).

  - Dublin [bieno-da12-dtl](https://portal.azure.com/#@Unilever.onmicrosoft.com/resource/subscriptions/c9462478-f3d6-4345-acd0-feb25ebe28ca/resourceGroups/bieno-da12-p-00000-dtl-rg/providers/Microsoft.DevTestLab/labs/bieno-da12-dtl-01/overview).

You must start your VM each day.<br><br>
