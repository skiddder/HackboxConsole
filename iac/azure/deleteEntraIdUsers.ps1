param (
    [ValidateRange(1, 999)]
    [int]$startUserIndex = 1,
    [int]$stopUserIndex = [int]::MaxValue,
    [string]$userNamePrefix = "hackuser"
)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)

if($startUserIndex -gt $stopUserIndex) {
    throw "Invalid user index range. Start index ($startUserIndex) cannot be greater than stop index ($stopUserIndex)."
}

# Install required PowerShell modules
foreach ($module in @(
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.SignIns'
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
    $mgctx.Scopes -notcontains "Group.ReadWrite.All" -or
    $mgctx.Scopes -notcontains "UserAuthenticationMethod.ReadWrite.All"
) {
    Write-Host "Connecting to Microsoft Graph with required permissions..."
    Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","UserAuthenticationMethod.ReadWrite.All" -UseDeviceCode
    $mgctx = Get-MgContext
    if($null -eq $mgctx -or 
        $mgctx.Scopes -notcontains "User.ReadWrite.All" -or
        $mgctx.Scopes -notcontains "Group.ReadWrite.All" -or
        $mgctx.Scopes -notcontains "UserAuthenticationMethod.ReadWrite.All"
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