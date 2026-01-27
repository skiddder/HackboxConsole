param(
    [string]$managementGroupId = "",
    [string]$subscriptionPrefix = "traininglab-"
)

# az module
foreach($module in @(
    'Az.Accounts',
    'Az.Resources'
)) {
    if( -not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module"
        Install-Module -Name $module -AllowClobber -Force
    }
    Write-Host "Importing module: $module"
    Import-Module $module
}
if(-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Connect-AzAccount -UseDeviceAuthentication
}


$subscriptionIdFilter = $null
if($managementGroupId -ne "") {
    $subscriptionIdFilter = @{}
    foreach($mg in (Get-AzManagementGroup -GroupName $managementGroupId -Recurse -Expand -ErrorAction Stop | Select-Object -ExpandProperty Children )) {
        if($mg.Type -eq "/subscriptions") {
            $subscriptionIdFilter[$mg.Name.ToLower()] = $true
        }
    }
}

# Collect qualified subscriptions
$qualifiedSubscriptions = @()
foreach($sub in (Get-AzSubscription  | Where-Object { $_.Name.ToLower().StartsWith($subscriptionPrefix.ToLower()) -and $_.State -eq "Enabled"})) {
    if($null -ne $subscriptionIdFilter) {
        if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
            continue
        }
    }
    $qualifiedSubscriptions += $sub
}

Write-Host "Found $($qualifiedSubscriptions.Count) qualified subscriptions to clean up."

# Collect all deletion jobs
$deletionJobs = @()

foreach($sub in $qualifiedSubscriptions) {
    Write-Host "Processing subscription: $($sub.Name)" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    # Get all resource groups in the subscription
    $resourceGroups = Get-AzResourceGroup
    
    foreach($rg in $resourceGroups) {
        Write-Host "  Initiating forced deletion of resource group: $($rg.ResourceGroupName)" -ForegroundColor Yellow
        
        try {
            # Remove resource group with -Force and -AsJob for non-blocking execution
            $job = Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force -AsJob
            $deletionJobs += @{
                Job = $job
                SubscriptionName = $sub.Name
                ResourceGroupName = $rg.ResourceGroupName
            }
            Write-Host "    Started deletion job for: $($rg.ResourceGroupName)" -ForegroundColor White

            Start-Sleep -Milliseconds 500 # Slight delay to avoid overwhelming the system
        }
        catch {
            Write-Host "    Failed to start deletion for: $($rg.ResourceGroupName). Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nStarted $($deletionJobs.Count) deletion jobs. Waiting for completion..." -ForegroundColor Cyan

# Wait for all jobs to complete and report results
foreach($jobInfo in $deletionJobs) {
    $job = $jobInfo.Job
    $result = $job | Wait-Job | Receive-Job
    
    if($job.State -eq 'Completed') {
        Write-Host "  Successfully deleted: $($jobInfo.ResourceGroupName) in $($jobInfo.SubscriptionName)" -ForegroundColor Green
    }
    else {
        Write-Host "  Failed to delete: $($jobInfo.ResourceGroupName) in $($jobInfo.SubscriptionName). State: $($job.State)" -ForegroundColor Red
    }
    
    # Clean up the job
    $job | Remove-Job -Force -ErrorAction SilentlyContinue
}

Write-Host "`nCompleted all resource group deletions." -ForegroundColor Cyan
