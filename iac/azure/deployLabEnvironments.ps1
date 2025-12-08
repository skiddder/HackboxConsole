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
    [string]$preferredLocation = ""
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

# add the object id to the user settings
$users = @()
foreach($userSetting in $entraIdUserSettings) {
    $user = Get-MgUser -Filter "userPrincipalName eq '$($userSetting.value)'"
    if($null -eq $user) {
        throw "Failed to find Entra ID user with userPrincipalName: $($userSetting.value)"
    }
    $users += $user
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
        # run script only if labDirectory is specified
        if($labDirectory -ne "") {
            if((Test-Path (Join-Path $labDirectory "deploy-lab.ps1") -PathType Leaf)) {
                # deploy lab resources for this user
                Write-Host "Deploying lab resources for user $($user.UserPrincipalName) in subscription $($sub.Name) ($($sub.Id))..."
                & (Join-Path $labDirectory "deploy-lab.ps1") `
                    -DeploymentType $deploymentType `
                    -SubscriptionId $sub.Id `
                    -PreferredLocation $preferredLocation `
                    -AllowedEntraUserIds @($user.Id) | Out-Null
            }
            else {
                Write-Warning "deploy-lab.ps1 script not found in lab directory $labDirectory. Skipping deployment for user $($user.UserPrincipalName)."
            }
        }

        Start-Sleep -Seconds 1
        $currentUserIndex++
    }
}
elseif($deploymentType -eq "resourcegroup") {
    Write-Host "Deploying lab resources scoped to resource groups."
    $currentUserIndex = 0
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

            # run script only if labDirectory is specified
            if($labDirectory -ne "") {
                if((Test-Path (Join-Path $labDirectory "deploy-lab.ps1") -PathType Leaf)) {
                    # deploy lab resources for this user
                    Write-Host "Deploying lab resources for user $($user.UserPrincipalName) in subscription $($sub.Name) ($($sub.Id))..."
                    & (Join-Path $labDirectory "deploy-lab.ps1") `
                        -DeploymentType $deploymentType `
                        -SubscriptionId $sub.Id `
                        -ResourceGroupName $resourceGroupName `
                        -PreferredLocation $preferredLocation `
                        -AllowedEntraUserIds @($user.Id) | Out-Null
                }
                else {
                    Write-Warning "deploy-lab.ps1 script not found in lab directory $labDirectory. Skipping deployment for user $($user.UserPrincipalName)."
                }
            }

            Start-Sleep -Seconds 1

            $currentUserIndex++
        }
    }
}
#>

