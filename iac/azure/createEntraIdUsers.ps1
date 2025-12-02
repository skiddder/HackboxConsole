param (
    [ValidateRange(1, 999)]
    [int]$startUserIndex = 1,
    [string]$userNamePrefix = "hackuser",
    [Nullable[datetime]]$hackathonStartDate = $null,
    [Nullable[datetime]]$hackathonEndDate = $null,
    [string[]]$additionalGroupnames = @(),
    [string]$csvPath = ""
)

# Configure TAP so, that 5 days work! https://learn.microsoft.com/en-us/entra/identity/authentication/howto-authentication-temporary-access-pass 

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)


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

if($null -eq $hackathonStartDate) {
    Write-Warning "Hackathon start date not provided.`n`tUsing current date and time as start date.`n`tYou are highly encouraged to provide explicit start date set to the actual start date of the hackathon."
    $hackathonStartDate = (Get-Date)
}
if($null -eq $hackathonEndDate) {
    $hackathonEndDate = $hackathonStartDate.AddDays(5).AddMinutes(-1)
}

# maximum hackathon duration is 5 days
if(
    $hackathonEndDate -le $hackathonStartDate -or
    $hackathonEndDate.AddDays(-5) -gt $hackathonStartDate
) {
    throw "Hackathon invalid start date and/or end date parameters. Start Date: $($hackathonStartDate.ToString("yyyy-MM-dd HH:mm:ss")), End Date: $($hackathonEndDate.ToString("yyyy-MM-dd HH:mm:ss"))"
}
$lifetimeInMinutes = ($hackathonEndDate - $hackathonStartDate).TotalMinutes


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

# checking additional groups
$addtionalGroupIds = @()
foreach($g in $additionalGroupnames) {
    if($null -eq $g) {
        continue
    }
    $GroupName = $g.Trim()
    if($GroupName -eq "") {
        continue
    }
    # must contain characters 0-9 a-z A-Z _ - .
    if($GroupName -notmatch '^[0-9a-zA-Z_\-\.]+$') {
        throw "Invalid group name: $GroupName. Group names must only contain characters 0-9 a-z A-Z _ - ."
    }
    $num = 0
    Get-MgGroup -Filter "DisplayName eq '$GroupName'" | ForEach-Object {
        $addtionalGroupIds += $_.Id
        $num++
    }
    if($num -eq 0) {
        throw "Group with name $GroupName not found in Entra ID."
    }
    if($num -gt 1) {
        throw "Multiple groups with name $GroupName found in Entra ID. Group names must be unique."
    }
}

# checking tenants
$tenantNames = @{}
foreach($u in Get-Content (Join-Path -Path $consoleRoot -ChildPath "users.json") -Encoding utf8 | ConvertFrom-Json) {
    if($u.role -eq "hacker" -or $u.role -eq "coach" ) {
        $tenantNames[$u.tenant] = $true
    }
}
$tenantNames = $tenantNames.Keys
Write-Host "We have $($tenantNames.Count) tenants"
if($tenantNames.Count -eq 0) {
    throw "No tenants found in users.json"
}


$createdUsers = @()
$createdEntraIdUserSettings = @()
$userDomain = $mgctx.Account.Split('@')[1]
$i = $startUserIndex
foreach($tenantName in $tenantNames) {
    Write-Host "Creating user for hackbox-tenant `"$tenantName`" in entra id..."
    $currentUser = [PSCustomObject]@{
        tenant = $tenantName
        userPrincipalName = "{0}-{1:d3}@{2}" -f @($userNamePrefix, [int]$i, $userDomain)
        userName = "{0}-{1:d3}" -f @($userNamePrefix, [int]$i)
        password = (New-Guid).Guid
        temporaryAccessPass = ""
        startFrom = $null
        validTo = $null
    }

    # Create Entra ID user
    write-Host "  - Creating user $($currentUser.userPrincipalName)..."
    $pwProfile = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphPasswordProfile
    $pwProfile.ForceChangePasswordNextSignIn = $true
    $pwProfile.Password = $currentUser.password
    for($i = 0; $i -lt 3; $i++) {
        try {
            $createdUser = New-MgUser -AccountEnabled `
                -DisplayName $currentUser.userName `
                -MailNickname $currentUser.userName `
                -UserPrincipalName $currentUser.userPrincipalName `
                -PasswordProfile $pwProfile -ErrorAction Stop
            break
        }
        catch {
            Write-Warning "Failed to create user $($currentUser.userPrincipalName). Retrying...`n`t$($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
    if($null -eq $createdUser) {
        throw "Failed to create user $($currentUser.userPrincipalName) after multiple attempts."
    }

    # adding user to the groups
    $createdGroupsNum = 0
    foreach($groupId in $addtionalGroupIds) {
        Write-Host "  - Adding user $($currentUser.userPrincipalName) to group with id $groupId"
        for($i = 0; $i -lt 3; $i++) {
            try {
                New-MgGroupMember -GroupId $groupId -DirectoryObjectId $createdUser.Id -ErrorAction Stop | Out-Null
                $createdGroupsNum++
                break
            }
            catch {
                Write-Warning "Failed to add user $($currentUser.userPrincipalName) to group with id $groupId. Skipping...`n`t$($_.Exception.Message)"
                Start-Sleep -Seconds 2
            }
        }
    }
    if($createdGroupsNum -ne $addtionalGroupIds.Count) {
        throw "Failed to add user $($currentUser.userPrincipalName) to all specified groups."
    }

    # Create Temporary Access Pass for the user
    Write-Host "  - Creating Temporary Access Pass for user $($currentUser.userPrincipalName)..."
    $tap = $null
    for($i = 0; $i -lt 3; $i++) {
        try {
            $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $createdUser.Id `
                -IsUsable `
                -IsUsableOnce:$false `
                -StartDateTime $hackathonStartDate `
                -LifetimeInMinutes $lifetimeInMinutes `
                -ErrorAction Stop
            break
        }
        catch {
            Write-Warning "Failed to create Temporary Access Pass for user $($currentUser.userPrincipalName). Retrying...`n`t$($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
    if($null -eq $tap) {
        Write-Warning "Failed to create Temporary Access Pass for user $($currentUser.userPrincipalName) after multiple attempts. Using password only."
    }
    else {
        $currentUser.temporaryAccessPass = $tap.TemporaryAccessPass
        $currentUser.startFrom = $tap.StartDateTime
        $currentUser.validTo = $tap.StartDateTime.AddMinutes($tap.LifetimeInMinutes)
        # fallback for startFrom
        if($null -eq $currentUser.startFrom) {
            $currentUser.startFrom = $hackathonStartDate
        }
        # fallback for vaildTo
        if($null -eq $currentUser.validTo) {
            $currentUser.validTo = $hackathonEndDate
        }
    }

    $createdUsers += $currentUser

    $createdEntraIdUserSettings += ([PSCustomObject]@{
        tenant = $tenantName
        group = "Azure"
        name = "EntraID Username"
        value = $currentUser.userPrincipalName
    })
    if($null -eq $tap -or $currentUser.temporaryAccessPass -eq "") {
        $createdEntraIdUserSettings += ([PSCustomObject]@{
            tenant = $tenantName
            group = "Azure"
            name = "EntraID Password"
            value = $currentUser.password
        })
    }
    else {
        $createdEntraIdUserSettings += ([PSCustomObject]@{
            tenant = $tenantName
            group = "Azure"
            name = "EntraID Temporary Access Pass"
            value = $currentUser.temporaryAccessPass
            note = "Valid from $($currentUser.startFrom.ToString("yyyy-MM-dd HH:mm:ss")) to $($currentUser.validTo.ToString("yyyy-MM-dd HH:mm:ss"))"
        })
    }
    $i++
}


$createdEntraIdUserSettings | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $consoleRoot "createdEntraIdUserSettings.json") -Encoding utf8
Write-Host "Saved Settings of created Entra ID users to: $jsonPath"

if($csvPath.Trim() -ne "") {
    $createdUsers | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
    Write-Host "Saved created Entra ID users to: $csvPath"
}

