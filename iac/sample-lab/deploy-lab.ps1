<#
.SYNOPSIS
Deploys the lab resources scoped to a subscription or resource group.
.DESCRIPTION
Provides a controlled deployment flow for lab environments, optionally limited to a resource group and specific Entra user IDs.
.PARAMETER DeploymentType
Defines the deployment scope; allowed values are subscription or resourcegroup.
.PARAMETER SubscriptionId
Specifies the Azure subscription that contains the lab resources.
.PARAMETER ResourceGroupName
In case of resourcegroup deployment, specifies the target resource group name.
.PARAMETER AllowedEntraUserIds
Optional list of Entra user object IDs permitted to access the lab resources.
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('subscription','resourcegroup')]
    [string]$DeploymentType,
    
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [string]$ResourceGroupName = "",

    [string[]]$AllowedEntraUserIds = @()
)

# Validate parameters
if($DeploymentType -eq 'resourcegroup' -and [string]::IsNullOrEmpty($ResourceGroupName)) {
    throw "ResourceGroupName must be provided when DeploymentType is 'resourcegroup'."
}

