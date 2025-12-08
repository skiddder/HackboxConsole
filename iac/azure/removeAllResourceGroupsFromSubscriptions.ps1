<#
.SYNOPSIS
Removes every resource group from Azure subscriptions matching the provided prefix, optionally scoped to a management group.
.PARAMETER managementGroupId
Limits the cleanup to subscriptions inside the specified management group; when omitted, all tenant subscriptions are considered.
.PARAMETER subscriptionPrefix
Prefix used to select target subscriptions (defaults to 'traininglab-').
.DESCRIPTION
Iterates through subscriptions whose names start with the provided prefix, sets context to each one, and deletes every resource group found using the Az PowerShell module. Useful for quickly resetting training or lab environments.
.EXAMPLE
.\removeAllResourceGroupsFromSubscriptions.ps1 -managementGroupId "labsubscriptions"
Deletes all resource groups from enabled subscriptions under the specified management group whose names start with the default prefix.
#>
param(
    [string]$managementGroupId = "",
    [string]$subscriptionPrefix = "traininglab-"
)


$subscriptionIdFilter = $null
if($managementGroupId -ne "") {
    $subscriptionIdFilter = @{}
    Get-AzManagementGroup -GroupName $managementGroupId -Recurse -Expand -ErrorAction Stop | Select-Object -ExpandProperty Children | ForEach-Object {
        if($_.Type -eq "/subscriptions") {
            $subscriptionIdFilter[$_.Name.ToLower()] = $true
        }
    }
}

foreach($sub in (Get-AzSubscription  | Where-Object { $_.Name.ToLower().StartsWith($subscriptionPrefix.ToLower()) -and $_.State -eq "Enabled"})) {
    if($null -ne $subscriptionIdFilter) {
        if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
            continue
        }
    }

    Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
    Write-Host "Removing all Resource Groups from Subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor Yellow
    foreach($rg in (Get-AzResourceGroup)) {
        Write-Host "  Deleting Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Cyan
        Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
}
