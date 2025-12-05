# Azure Environment Preparation Helpers

In this directory, you will find useful scripts to help prepare your Azure environment for hackathons.


## Scripts

 - [createEntraIdUsers.ps1](createEntraIdUsers.ps1): Creates Entra ID users in your Entra ID.
 - [deleteEntraIdUsers.ps1](deleteEntraIdUsers.ps1): Deletes Entra ID users from your Entra ID.
 - [removeOrphanedRoleAssignments.ps1](removeOrphanedRoleAssignments.ps1): Removes Azure role assignments that reference non-existent principals across subscriptions and resource groups.
 - [renameAndOrganizeSubscriptions.ps1](renameAndOrganizeSubscriptions.ps1): Renames Azure subscriptions to a management/traininglab scheme and organizes traininglab subscriptions into a management group called "labsubscriptions".
 