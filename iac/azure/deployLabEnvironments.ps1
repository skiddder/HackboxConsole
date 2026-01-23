<#
.SYNOPSIS
sadasd
.DESCRIPTION
dasds
.PARAMETER managementGroupId
Limits the cleanup to subscriptions inside the specified management group; when omitted, all tenant subscriptions are considered.
.PARAMETER subscriptionPrefix
Prefix used to select target subscriptions (defaults to 'traininglab-').
.PARAMETER deploymentType
Defines the deployment scope; allowed values are subscription or resourcegroup (defaults to 'resourcegroup').
.PARAMETER teamsPerSubscription
Number of teams expected per subscription (defaults to 5). Just for resourcegroup deployments.
.PARAMETER preferredLocation
Specifies the preferred Azure region for resource deployment. "" indicates no preference.
#>
param(
    [string]$labDirectory = "",
    [string]$managementGroupId = "",
    [string]$subscriptionPrefix = "traininglab-",
    [ValidateSet('subscription','resourcegroup')]
    [string]$deploymentType = "resourcegroup",
    [int]$teamsPerSubscription = 5,
    [string]$preferredLocation = "",
    [ValidateRange(1, 100)]
    [int]$labDeploymentParallelization = 10,
    [switch]$skipResourceGroupCreation
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)

if(-not(Test-Path (Join-Path $consoleRoot "createdEntraIdUserSettings.json"))) {
    throw "the file createdEntraIdUserSettings.json was not found in $consoleRoot. Please run the createEntraIdUsers.ps1 script first."
}
$entraIdUserSettings = Get-Content (Join-Path $consoleRoot "createdEntraIdUserSettings.json") | ConvertFrom-Json | Where-Object { $_.group -eq "Azure" -and $_.name -eq "EntraID Username" }
if($null -eq $entraIdUserSettings -or $entraIdUserSettings.Count -eq 0) {
    throw "the file createdEntraIdUserSettings.json does not contain an entry for Entra ID users in the Azure group. Please run the createEntraIdUsers.ps1 script first."
}

if($labDirectory -ne "") {
    $labDirectory = (Resolve-Path -Path $labDirectory -ErrorAction Stop).Path
    if(-not(Test-Path $labDirectory)) {
        throw "The specified lab directory '$labDirectory' does not exist."
    }
}

# az module
if(-not (Get-Module -ListAvailable -Name Az)) {
    Install-Module -Name Az -AllowClobber -Force
}
Import-Module Az
if(-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Connect-AzAccount -UseDeviceAuthentication
}

# Install required PowerShell modules
foreach ($module in @(
    'Microsoft.Graph.Users'
)) {
    if( -not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module: $module"
        Install-PSResource -Name $module -Repository PSGallery -TrustRepository
    }
    Write-Host "Importing module: $module"
    Import-Module $module
}

# Connect to Microsoft Graph with required permissions
$mgctx = Get-MgContext
if($null -eq $mgctx -or $mgctx.Scopes -notcontains "User.ReadWrite.All") {
    Write-Host "Connecting to Microsoft Graph with required permissions..."
    Connect-MgGraph -Scopes "User.ReadWrite.All" -UseDeviceCode
    $mgctx = Get-MgContext
    if($null -eq $mgctx -or $mgctx.Scopes -notcontains "User.ReadWrite.All") {
        throw "Failed to connect to Microsoft Graph with required permissions."
    }
} 
else {
    Write-Host "Already connected to Microsoft Graph with required permissions."
}

class HackBoxCredentialsConsumer {
    hidden [PSCustomObject[]] $credentials = @()

    HackBoxCredentialsConsumer() {
    }

    [void] ConsumeJobOutput([object]$jobOutput, [string]$hackboxTenant) {
        $this.ConsumeJobOutput($jobOutput, $hackboxTenant, "Lab-Deployment")
    }
    [void] ConsumeJobOutput([object]$jobOutput, [string]$hackboxTenant, [string]$hackboxGroup) {
        # check if foreach works on $jobOutput
        if(-not ($jobOutput -is [System.Collections.IEnumerable])) {
            return
        }
        foreach($r in $jobOutput) {
            if($r -is [System.Collections.IDictionary] -or $r -is [System.Collections.Hashtable]) {
                if($r.ContainsKey("HackboxCredential")) {
                    if($r["HackboxCredential"] -is [System.Collections.IDictionary] -or $r["HackboxCredential"] -is [System.Collections.Hashtable]) {
                        if(
                            $r["HackboxCredential"].ContainsKey("name") -and $r["HackboxCredential"].ContainsKey("value") -and
                             $r["HackboxCredential"]["name"] -ne "" -and $r["HackboxCredential"]["value"] -ne ""
                        ) {
                            $consoleCredential = [PSCustomObject]@{
                                tenant = $hackboxTenant
                                group = $hackboxGroup
                                name = $r["HackboxCredential"]["name"]
                                value = $r["HackboxCredential"]["value"]
                                note = ""
                            }
                            if($r["HackboxCredential"].ContainsKey("note") -and $r["HackboxCredential"]["note"] -ne "") {
                                $consoleCredential.note = $r["HackboxCredential"]["note"]
                            }
                            $this.credentials += $consoleCredential
                        }
                    }
                }
            }
        }
    }

    [void]resetCredentials() {
        $this.credentials = @()
    }

    [PSCustomObject[]]getCredentials() {
        return $this.credentials
    }
    [string]jsonifyCredentials() {
        return ($this.credentials | ConvertTo-Json -Depth 5 -AsArray)
    }
}

$credentialConsumer = [HackBoxCredentialsConsumer]::new()


# get the user information
$users = @()
foreach($userSetting in $entraIdUserSettings) {
    $user = Get-MgUser -Filter "userPrincipalName eq '$($userSetting.value)'"
    if($null -eq $user) {
        throw "Failed to find Entra ID user with userPrincipalName: $($userSetting.value)"
    }
    $users += [PSCustomObject]@{
        UserPrincipalName = $user.UserPrincipalName
        Id = $user.Id
        DisplayName = $user.DisplayName
        Mail = $user.Mail
        HackboxTenantId = $userSetting.tenant
    }
}
$entraIdUserSettings = @()
# sort entraIdUserSettings by value (to ensure consistent order and idempotency)
$users = $users | Sort-Object -Property UserPrincipalName


# qualified subscriptions
$subscriptionIdFilter = $null
if($managementGroupId -ne "") {
    $subscriptionIdFilter = @{}
    Get-AzManagementGroup -GroupName $managementGroupId -Recurse -Expand -ErrorAction Stop | Select-Object -ExpandProperty Children | ForEach-Object {
        if($_.Type -eq "/subscriptions") {
            $subscriptionIdFilter[$_.Name.ToLower()] = $true
        }
    }
}
$qualifiedSubscriptions = @()
foreach($sub in (Get-AzSubscription  | Where-Object { $_.Name.ToLower().StartsWith($subscriptionPrefix.ToLower()) -and $_.State -eq "Enabled"})) {
    if($null -ne $subscriptionIdFilter) {
        if(-not $subscriptionIdFilter.ContainsKey($sub.Id.ToLower())) {
            continue
        }
    }
    $qualifiedSubscriptions += $sub
}
# sort subscriptions by name, id (to ensure consistent order and idempotency)
$qualifiedSubscriptions = $qualifiedSubscriptions | Sort-Object -Property Name, Id


# enough subscriptions found to accommodate the users?
Write-Host "Found $($users.Count) Entra ID users."
Write-Host "Found $($qualifiedSubscriptions.Count) qualified subscriptions."
if($deploymentType -eq "subscription") {
    $requiredSubscriptions = $users.Count
}
elseif($deploymentType -eq "resourcegroup") {
    $requiredSubscriptions = [math]::Ceiling($users.Count / $teamsPerSubscription)
}
Write-Host "Required subscriptions to accommodate all users: $requiredSubscriptions (vs $($qualifiedSubscriptions.Count) available)."
if($qualifiedSubscriptions.Count -lt $requiredSubscriptions) {
    throw "Not enough qualified subscriptions found to accommodate all users. Required: $requiredSubscriptions, Found: $($qualifiedSubscriptions.Count)."
}

if($deploymentType -eq "subscription") {
    Write-Host "Deploying lab resources scoped to subscriptions."
    $currentUserIndex = 0
    $deploymentTasks = @()
    foreach($sub in $qualifiedSubscriptions) {
        # stop if all users have been assigned
        if($currentUserIndex -ge $users.Count) {
            break
        }
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        $user = $users[$currentUserIndex]
        # assign user to this subscription as owner
        if(-not (Get-AzRoleAssignment -ObjectId $user.Id -Scope "/subscriptions/$($sub.Id)" -RoleDefinitionName "Owner" -ErrorAction SilentlyContinue)) {
            Write-Host "Assigning user $($user.UserPrincipalName) as Owner to subscription $($sub.Name) ($($sub.Id))..."
            New-AzRoleAssignment -ObjectId $user.Id -RoleDefinitionName "Owner" -Scope "/subscriptions/$($sub.Id)" -ErrorAction Stop | Out-Null
        }
        else {
            Write-Host "User $($user.UserPrincipalName) is already assigned as Owner to subscription $($sub.Name) ($($sub.Id))."
        }
        # collect deployment task if labDirectory is specified
        if($labDirectory -ne "") {
            if((Test-Path (Join-Path $labDirectory "deploy-lab.ps1") -PathType Leaf)) {
                $deploymentTasks += @{
                    HackboxTenantId = $user.HackboxTenantId
                    UserPrincipalName = $user.UserPrincipalName
                    UserId = $user.Id
                    SubscriptionId = $sub.Id
                    SubscriptionName = $sub.Name
                }
            }
            else {
                Write-Warning "deploy-lab.ps1 script not found in lab directory $labDirectory. Skipping deployment for user $($user.UserPrincipalName)."
            }
        }

        Start-Sleep -Seconds 1
        $currentUserIndex++
    }

    # Run deployments in parallel using jobs (true process isolation)
    if($deploymentTasks.Count -gt 0) {
        Write-Host "Starting parallel deployment for $($deploymentTasks.Count) users (max $labDeploymentParallelization concurrent jobs)..."
        $labScriptPath = Join-Path $labDirectory "deploy-lab.ps1"
        
        $runningJobs = @()
        $taskIndex = 0
        $completedCount = 0
        
        while($taskIndex -lt $deploymentTasks.Count -or $runningJobs.Count -gt 0) {
            # Start new jobs up to the limit
            while($runningJobs.Count -lt $labDeploymentParallelization -and $taskIndex -lt $deploymentTasks.Count) {
                $task = $deploymentTasks[$taskIndex]
                Write-Host "[Job $($taskIndex + 1)/$($deploymentTasks.Count)] Starting deployment for user $($task.UserPrincipalName) in subscription $($task.SubscriptionName)..."
                
                $job = Start-Job -ScriptBlock {
                    param($labScriptPath, $deploymentType, $subscriptionId, $preferredLocation, $userId)
                    
                    # Import Az modules
                    foreach($mod in @("Az.Accounts","Az.Resources")) {
                        Import-Module $mod -ErrorAction Stop
                    }
                    # and set context
                    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop -Scope Process | Out-Null
                    
                    & $labScriptPath `
                        -DeploymentType $deploymentType `
                        -SubscriptionId $subscriptionId `
                        -PreferredLocation $preferredLocation `
                        -AllowedEntraUserIds @($userId)
                } -ArgumentList $labScriptPath, $deploymentType, $task.SubscriptionId, $preferredLocation, $task.UserId
                
                $runningJobs += @{ Job = $job; Task = $task; Index = $taskIndex }
                $taskIndex++
            }
            
            # Wait for at least one job to complete
            if($runningJobs.Count -gt 0) {
                $completed = $runningJobs | Where-Object { $_.Job.State -eq 'Completed' -or $_.Job.State -eq 'Failed' }
                
                foreach($item in $completed) {
                    $completedCount++
                    if($item.Job.State -eq 'Failed') {
                        Write-Warning "[Job $($item.Index + 1)] Deployment FAILED for user $($item.Task.UserPrincipalName): $($item.Job.ChildJobs[0].JobStateInfo.Reason)"
                        $credentialConsumer.ConsumeJobOutput((Receive-Job -Job $item.Job -ErrorAction SilentlyContinue), $item.Task.HackboxTenantId)
                    }
                    else {
                        Write-Host "[Job $($item.Index + 1)] Deployment completed for user $($item.Task.UserPrincipalName) ($completedCount/$($deploymentTasks.Count))"
                        $credentialConsumer.ConsumeJobOutput((Receive-Job -Job $item.Job), $item.Task.HackboxTenantId)
                    }
                    Remove-Job -Job $item.Job -Force
                }
                
                $runningJobs = @($runningJobs | Where-Object { $_.Job.State -eq 'Running' })
                
                if($runningJobs.Count -ge $labDeploymentParallelization -or ($taskIndex -ge $deploymentTasks.Count -and $runningJobs.Count -gt 0)) {
                    Start-Sleep -Milliseconds 500
                }
            }
        }
        
        Write-Host "Parallel deployment completed. Total: $completedCount jobs."
    }
}
elseif($deploymentType -eq "resourcegroup") {
    Write-Host "Deploying lab resources scoped to resource groups."
    $currentUserIndex = 0
    $deploymentTasks = @()
    foreach($sub in $qualifiedSubscriptions) {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

        for($i=0; $i -lt $teamsPerSubscription; $i++) {
            # stop if all users have been assigned
            if($currentUserIndex -ge $users.Count) {
                break
            }
            $user = $users[$currentUserIndex]
            # assign user to this subscription as reader
            if(-not (Get-AzRoleAssignment -ObjectId $user.Id -Scope "/subscriptions/$($sub.Id)" -RoleDefinitionName "Reader" -ErrorAction SilentlyContinue)) {
                Write-Host "Assigning user $($user.UserPrincipalName) as Reader to subscription $($sub.Name) ($($sub.Id))..."
                New-AzRoleAssignment -ObjectId $user.Id -RoleDefinitionName "Reader" -Scope "/subscriptions/$($sub.Id)" -ErrorAction Stop | Out-Null
            }
            else {
                Write-Host "User $($user.UserPrincipalName) is already assigned as Reader to subscription $($sub.Name) ($($sub.Id))."
            }


            if($skipResourceGroupCreation) {
                $resourceGroupName = "$($user.UserPrincipalName.Split("@")[0].ToLower())"
            }
            else {
                $resourceGroupName = "rg-$($user.UserPrincipalName.Split("@")[0].ToLower())"
                if(-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
                    Write-Host "Creating resource group $resourceGroupName in subscription $($sub.Name) ($($sub.Id))..."
                    if($preferredLocation -ne "") { 
                        $rglocation = $preferredLocation 
                    } 
                    else { 
                        $rglocation = "westeurope" 
                    }
                    New-AzResourceGroup -Name $resourceGroupName -Location $rglocation -ErrorAction Stop | Out-Null
                }
                else {
                    Write-Host "Resource group $resourceGroupName already exists in subscription $($sub.Name) ($($sub.Id))."
                }
                # assign user to this resource group as owner
                if(-not (Get-AzRoleAssignment -ObjectId $user.Id -Scope "/subscriptions/$($sub.Id)/resourceGroups/$resourceGroupName" -RoleDefinitionName "Owner" -ErrorAction SilentlyContinue)) {
                    Write-Host "Assigning user $($user.UserPrincipalName) as Owner to resource group $resourceGroupName in subscription $($sub.Name) ($($sub.Id))..."
                    New-AzRoleAssignment -ObjectId $user.Id -RoleDefinitionName "Owner" -Scope "/subscriptions/$($sub.Id)/resourceGroups/$resourceGroupName" -ErrorAction Stop | Out-Null
                }
                else {
                    Write-Host "User $($user.UserPrincipalName) is already assigned as Owner to resource group $resourceGroupName in subscription $($sub.Name) ($($sub.Id))."
                }
            }

            # collect deployment task if labDirectory is specified
            if($labDirectory -ne "") {
                if((Test-Path (Join-Path $labDirectory "deploy-lab.ps1") -PathType Leaf)) {
                    $deploymentTasks += @{
                        HackboxTenantId = $user.HackboxTenantId
                        UserPrincipalName = $user.UserPrincipalName
                        UserId = $user.Id
                        SubscriptionId = $sub.Id
                        SubscriptionName = $sub.Name
                        ResourceGroupName = $resourceGroupName
                    }
                }
                else {
                    Write-Warning "deploy-lab.ps1 script not found in lab directory $labDirectory. Skipping deployment for user $($user.UserPrincipalName)."
                }
            }

            Start-Sleep -Seconds 1

            $currentUserIndex++
        }
    }

    # Run deployments in parallel using jobs (true process isolation)
    if($deploymentTasks.Count -gt 0) {
        Write-Host "Starting parallel deployment for $($deploymentTasks.Count) users (max $labDeploymentParallelization concurrent jobs)..."
        $labScriptPath = Join-Path $labDirectory "deploy-lab.ps1"
        
        $runningJobs = @()
        $taskIndex = 0
        $completedCount = 0
        
        while($taskIndex -lt $deploymentTasks.Count -or $runningJobs.Count -gt 0) {
            # Start new jobs up to the limit
            while($runningJobs.Count -lt $labDeploymentParallelization -and $taskIndex -lt $deploymentTasks.Count) {
                $task = $deploymentTasks[$taskIndex]
                Write-Host "[Job $($taskIndex + 1)/$($deploymentTasks.Count)] Starting deployment for user $($task.UserPrincipalName) in subscription $($task.SubscriptionName)..."
                
                $job = Start-Job -ScriptBlock {
                    param($labScriptPath, $deploymentType, $subscriptionId, $resourceGroupName, $preferredLocation, $userId)
                    
                    # Import Az modules
                    foreach($mod in @("Az.Accounts","Az.Resources")) {
                        Import-Module $mod -ErrorAction Stop
                    }
                    # and set context
                    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop -Scope Process | Out-Null
                    
                    & $labScriptPath `
                        -DeploymentType $deploymentType `
                        -SubscriptionId $subscriptionId `
                        -ResourceGroupName $resourceGroupName `
                        -PreferredLocation $preferredLocation `
                        -AllowedEntraUserIds @($userId)
                } -ArgumentList $labScriptPath, $deploymentType, $task.SubscriptionId, $task.ResourceGroupName, $preferredLocation, $task.UserId
                
                $runningJobs += @{ Job = $job; Task = $task; Index = $taskIndex }
                $taskIndex++
            }
            
            # Wait for at least one job to complete
            if($runningJobs.Count -gt 0) {
                $completed = $runningJobs | Where-Object { $_.Job.State -eq 'Completed' -or $_.Job.State -eq 'Failed' }
                
                foreach($item in $completed) {
                    $completedCount++
                    if($item.Job.State -eq 'Failed') {
                        Write-Warning "[Job $($item.Index + 1)] Deployment FAILED for user $($item.Task.UserPrincipalName): $($item.Job.ChildJobs[0].JobStateInfo.Reason)"
                        $credentialConsumer.ConsumeJobOutput((Receive-Job -Job $item.Job -ErrorAction SilentlyContinue), $item.Task.HackboxTenantId)
                    }
                    else {
                        Write-Host "[Job $($item.Index + 1)] Deployment completed for user $($item.Task.UserPrincipalName) ($completedCount/$($deploymentTasks.Count))"
                        $credentialConsumer.ConsumeJobOutput((Receive-Job -Job $item.Job), $item.Task.HackboxTenantId)
                    }
                    Remove-Job -Job $item.Job -Force
                }
                
                $runningJobs = @($runningJobs | Where-Object { $_.Job.State -eq 'Running' })
                
                if($runningJobs.Count -ge $labDeploymentParallelization -or ($taskIndex -ge $deploymentTasks.Count -and $runningJobs.Count -gt 0)) {
                    Start-Sleep -Milliseconds 500
                }
            }
        }
        
        Write-Host "Parallel deployment completed. Total: $completedCount jobs."
    }
}

Write-Host ("Exporting created lab credentials to " + (Join-Path $consoleRoot "createdLabUserSettings.json"))
$credentialConsumer.jsonifyCredentials() | Out-File (Join-Path $consoleRoot "createdLabUserSettings.json") -Encoding UTF8
