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

    $locksRemoved = 0
    Write-Host "Removing all locks from Subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor Yellow
    foreach($lock in (Get-AzResourceLock -ErrorAction SilentlyContinue | Sort-Object ResourceId)) {
        Write-Host "  Removing from Resource: $($lock.ResourceId)" -ForegroundColor Cyan
        $lock | Remove-AzResourceLock -ErrorAction Continue -Force -Confirm:$false | Out-Null
        $locksRemoved++
        Start-Sleep -Seconds 1
    }
    Write-Host "  Total Locks Removed: $locksRemoved"
    if($locksRemoved -gt 0) {
        Write-Host "  Waiting 10 seconds for locks to be fully removed..."
        Start-Sleep -Seconds 10
    }

    $resourceGroupsDeleted = 0
    Write-Host "Removing all Resource Groups from Subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor Yellow
    foreach($rg in (Get-AzResourceGroup)) {

        Write-Host "  Deleting Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Cyan
        Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force -Confirm:$false -ErrorAction Continue | Out-Null
        $resourceGroupsDeleted++
        Start-Sleep -Seconds 2
    }
    Write-Host "  Total Resource Groups Deleted: $resourceGroupsDeleted"
}
