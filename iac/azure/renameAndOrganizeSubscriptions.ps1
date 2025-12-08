<#
.SYNOPSIS
Automates renaming Azure subscriptions into a management/traininglab scheme and moves the traininglab subscriptions into a dedicated management group.
.PARAMETER managementGroupId
Scopes renaming to a specific management group; when left empty (default) the script iterates over every subscription in the tenant.
.DESCRIPTION
Ensures one subscription is named 'management' and renames the remaining ones
to the pattern 'traininglab-{n}' using the Az PowerShell module.
.EXAMPLE
.\renameSubscriptions.ps1
Runs the script against the currently signed-in Azure tenant.
#>

param(
    [string]$managementGroupId = ""
)

if(-not (Get-Module -ListAvailable -Name Az)) {
    Install-Module -Name Az -AllowClobber -Force
}
Import-Module Az


if(-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Connect-AzAccount -UseDeviceAuthentication
}

$subscriptionIdFilter = $null
if($managementGroupId -ne "") {
    $subscriptionIdFilter = @{}
    Get-AzManagementGroup -GroupName $managementGroupId -Recurse -Expand -ErrorAction Stop | Select-Object -ExpandProperty Children | ForEach-Object {
        if($_.Type -eq "/subscriptions") {
            $subscriptionIdFilter[$_.Name.ToLower()] = $true
        }
    }
}



$armUrl = (Get-AzContext).Environment.ResourceManagerUrl
function Rename-Subscription {
    param (
        [string]$SubscriptionId,
        [string]$NewName
    )
    Write-Host "Renaming subscription '$SubscriptionId' to '$NewName'"
    $response = Invoke-AzRest -Uri "$armUrl/subscriptions/$SubscriptionId/providers/Microsoft.Subscription/rename?api-version=2021-10-01" -Method POST -Payload (@{ subscriptionName = $NewName } | ConvertTo-Json) -ErrorAction Stop
    if($response.StatusCode -ne 200) {
        throw "Failed to rename subscription '$SubscriptionId' to '$NewName'. StatusCode: $($response.StatusCode), Content: $($response.Content)"
    }
}


$hasManagement = $false
$maxAssignedNumber = 0
foreach ($sub in Get-AzSubscription) {
    # apply filter if specified
    if($null -ne $subscriptionIdFilter) {
        if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
            continue
        }
    }
    if ($sub.Name -eq "management") {
        $hasManagement = $true
        continue
    }
    if( $sub.Name.ToLower().StartsWith('traininglab-')) {
        # get the number part as int and max it in case it is abve 0
        try {
            $numberPart = [int]$sub.Name.Substring(12)
            $maxAssignedNumber = [math]::Max($maxAssignedNumber, $numberPart)
        }
        catch { }
    }
}

Write-Host "Max traininglab- number found: $maxAssignedNumber"

if(-not $hasManagement) {
    Write-Warning "No subscription named 'management' found. Taking the first subscription, that qualifies."
    $renamed = $false
    foreach($sub in (Get-AzSubscription | Where-Object { (-not $_.Name.ToLower().StartsWith('traininglab-')) -and ($_.Name -ne "management") })) {
        # apply filter if specified
        if($null -ne $subscriptionIdFilter) {
            if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
                continue
            }
        }
        Rename-Subscription -SubscriptionId $sub.Id -NewName "management" 
        $renamed = $true
        break
    }
    if(-not $renamed) {
        throw "No subscription found to rename to 'management'."
    }
    Write-Host "Waiting 60 seconds for the rename operation to propagate..."
    Start-Sleep -Seconds 60
}

# ensure exactly one 'management' subscription exists, before proceeding with the renaming
$subs = Get-AzSubscription
$managementCount = 0
foreach($sub in (Get-AzSubscription | Where-Object { $_.Name -eq "management" })) {
    # apply filter if specified
    if($null -ne $subscriptionIdFilter) {
        if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
            continue
        }
    }
    $managementCount++
}
if($managementCount -ne 1) {
    throw "There should be exactly one subscription named 'management'. Found: $managementCount"
}
# Renaming subscriptions to traininglab-{n}
foreach($sub in ($subs | Where-Object { (-not $_.Name.ToLower().StartsWith('traininglab-')) -and ($_.Name -ne "management") })) {
    # apply filter if specified
    if($null -ne $subscriptionIdFilter) {
        if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
            continue
        }
    }
    $maxAssignedNumber++
    Rename-Subscription -SubscriptionId $sub.Id -NewName "traininglab-$maxAssignedNumber"
}
$subs = $null

#create management group and add subscriptions
if(-not (Get-AzManagementGroup -GroupName "labsubscriptions" -ErrorAction SilentlyContinue)) {
    Write-Host "Creating management group 'labsubscriptions'"
    if($managementGroupId -ne "") {
        New-AzManagementGroup -GroupName "labsubscriptions" -DisplayName "Lab Subscriptions" -ParentId (Get-AzManagementGroup -GroupName $managementGroupId -ErrorAction Stop).Id
    }
    else {
        New-AzManagementGroup -GroupName "labsubscriptions" -DisplayName "Lab Subscriptions"
    }
}


# getting assigned subscriptionIds
$existingSubscriptionIds = @{ }
Get-AzManagementGroup -GroupName "labsubscriptions" -Recurse -Expand | Select-Object -ExpandProperty Children | ForEach-Object {
    if($_.Type -eq "/subscriptions") {
        $existingSubscriptionIds[$_.Name.ToLower()] = $true
    }
}

foreach($sub in (Get-AzSubscription  | Where-Object { $_.Name.ToLower().StartsWith('traininglab-')})) {
    # apply filter if specified
    if($null -ne $subscriptionIdFilter) {
        if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
            continue
        }
    }
    if($existingSubscriptionIds.ContainsKey($sub.Id.ToLower())) {
        return
    }
    Write-Host "Adding subscription '$($sub.Name)' to management group 'labsubscriptions'"
    New-AzManagementGroupSubscription -GroupName "labsubscriptions" -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
}
