# Azure Environment Preparation Helpers

In this directory, you will find useful scripts to help prepare your Azure environment for hackathons.


## Scripts

 - [createEntraIdUsers.ps1](createEntraIdUsers.ps1): Creates Entra ID users in your Entra ID.
 - [deleteEntraIdUsers.ps1](deleteEntraIdUsers.ps1): Deletes Entra ID users from your Entra ID.
 - [removeOrphanedRoleAssignments.ps1](removeOrphanedRoleAssignments.ps1): Removes Azure role assignments that reference non-existent principals across subscriptions and resource groups.
 - [renameAndOrganizeSubscriptions.ps1](renameAndOrganizeSubscriptions.ps1): Renames Azure subscriptions to a management/traininglab scheme and organizes traininglab subscriptions into a management group called "labsubscriptions".
 


## Usage - When to run which script?


### Optional Task: Rename and organize subscriptions
As soon as you have received your Azure tenant and subscriptions for the hackathon, you can run the following script to rename and organize your subscriptions:

Organize your tenant's subscriptions using `renameAndOrganizeSubscriptions.ps1`

**You can also use f.e. `renameAndOrganizeSubscriptions.ps1 -managementGroupId d5d99ee9-928e-411c-b822-60836adfef65` to limit the scope to subscriptions within a specific management group (recursively).**


### Weeks before the hackathon: Capacity & Quota Planning
Fill out the [quota-requests-sample.csv](quota-requests-sample.csv) file with your expected resource usage for the hackathon for each subscription.
Use the `processQuotaRequests.ps1` script to analyze your Azure subscriptions' capacity and quota for the hackathon.

**You can also use f.e. `processQuotaRequests.ps1 -managementGroupId d5d99ee9-928e-411c-b822-60836adfef65` to limit the scope to subscriptions within a specific management group (recursively).**

Use `Get-Help .\processQuotaRequests.ps1 -Detailed` or `Get-Help .\processQuotaRequests.ps1 -Full` to see all information (parameters, examples) for the script.


### Days before the hackathon: Create Entra ID users
Use the `createEntraIdUsers.ps1` script to create Entra ID users for hackathon participants before the hackathon starts.

Use `Get-Help .\createEntraIdUsers.ps1 -Detailed` or `Get-Help .\createEntraIdUsers.ps1 -Full` to see all information (parameters, examples) for the script.


### After the hackathon: Delete Entra ID users
Use the `deleteEntraIdUsers.ps1` script to delete Entra ID users created for hackathon participants after the hackathon ends.

Use `Get-Help .\deleteEntraIdUsers.ps1 -Detailed` or `Get-Help .\deleteEntraIdUsers.ps1 -Full` to see all information (parameters, examples) for the script.

