<#
.SYNOPSIS
Deletes Entra ID users that share a common prefix and optional index range, with optional permanent purge.

.DESCRIPTION
Locates users whose UPN starts with the specified prefix, deletes them within the given numeric range, and optionally purges them from the deleted users container.

.PARAMETER startUserIndex
Optional first numeric suffix of the user accounts to target.

.PARAMETER stopUserIndex
Optional last numeric suffix of the user accounts to target.

.PARAMETER userNamePrefix
Optional UPN prefix (before the dash and numeric suffix) used to identify hackathon users.

.PARAMETER purgeUsers
Switch to permanently remove matching deleted users after soft delete.

.EXAMPLE
PS> .\deleteENtraIdUsers.ps1 -startUserIndex 1 -stopUserIndex 50 -purgeUsers
Deletes hackuser-1 through hackuser-50 and permanently purges them.

.EXAMPLE
PS> .\deleteENtraIdUsers.ps1 -userNamePrefix "demo" -startUserIndex 10 -stopUserIndex 25
Deletes demo-10 through demo-25 but leaves them in the recycle bin for possible restore.

.EXAMPLE
PS> .\deleteENtraIdUsers.ps1 -userNamePrefix "hackuser" -purgeUsers -startUserIndex 200
Deletes and purges every hackuser-### account from 200 upward until no higher index exists.

.NOTES
Requires Microsoft Graph permissions User.ReadWrite.All and User.DeleteRestore.All.
#>
param (
    [ValidateRange(1, 999)]
    [int]$startUserIndex = 1,
    [int]$stopUserIndex = [int]::MaxValue,
    [string]$userNamePrefix = "hackuser",
    [switch]$purgeUsers
)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)

if($startUserIndex -gt $stopUserIndex) {
    throw "Invalid user index range. Start index ($startUserIndex) cannot be greater than stop index ($stopUserIndex)."
}

# Install required PowerShell modules
foreach ($module in @(
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Identity.DirectoryManagement'
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
if($null -eq $mgctx -or 
    $mgctx.Scopes -notcontains "User.ReadWrite.All" -or
    $mgctx.Scopes -notcontains "User.DeleteRestore.All"
) {
    Write-Host "Connecting to Microsoft Graph with required permissions..."
    Connect-MgGraph -Scopes "User.ReadWrite.All","User.DeleteRestore.All" -UseDeviceCode
    $mgctx = Get-MgContext
    if($null -eq $mgctx -or 
        $mgctx.Scopes -notcontains "User.ReadWrite.All" -or
        $mgctx.Scopes -notcontains "User.DeleteRestore.All"
    ) {
        throw "Failed to connect to Microsoft Graph with required permissions."
    }
} 
else {
    Write-Host "Already connected to Microsoft Graph with required permissions."
}


# looking for user accounts to delete
Get-MgUser -Filter "startsWith(userPrincipalName,'$userNamePrefix')" | ForEach-Object {
    $userName = ($_.UserPrincipalName -split "@")[0]
    if($userName.StartsWith($userNamePrefix + "-")) {
        $userNumber = [int]$userName.Substring($userNamePrefix.Length + 1)
        if($userNumber -ge $startUserIndex -and $userNumber -le $stopUserIndex) {
            Write-Host "Deleting user: $($_.UserPrincipalName) (Id: $($_.Id))"
            Remove-MgUser -UserId $_.Id -Confirm:$false
        }
    }
}


if($purgeUsers) {
    Write-Host "Purging deleted users..."
    do {
        $deletedUsers = Get-MgDirectoryDeletedItemAsUser -Filter "startsWith(userPrincipalName,'$userNamePrefix')" -All
        foreach ($deletedUser in $deletedUsers) {
            $userName = ($deletedUser.UserPrincipalName -split "@")[0]
            if($userName.StartsWith($userNamePrefix + "-")) {
                $userNumber = [int]$userName.Substring($userNamePrefix.Length + 1)
                if($userNumber -ge $startUserIndex -and $userNumber -le $stopUserIndex) {
                    Write-Host "Permanently deleting user: $($deletedUser.UserPrincipalName) (Id: $($deletedUser.Id))"
                    Remove-MgDirectoryDeletedItem -DirectoryObjectId $deletedUser.Id -Confirm:$false
                }
            }
        }
    } while ($deletedUsers.Count -gt 0)
}
