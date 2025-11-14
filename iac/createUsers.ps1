param(
    [ValidateRange(1,200)]
    [int]$numberOfTenants=4,
    [string]$baseHackerUsername="hacker",
    [string]$baseCoachUsername="coach",
    [ValidateSet("simple","complex")]
    [string]$hackerPasswordStrength="simple",
    [ValidateSet("simple","complex")]
    [string]$coachPasswordStrength="complex",
    [string[]]$simplePasswordAdjectives = @(),
    [string[]]$simplePasswordNouns = @(),
    [ValidateRange(12,64)]
    [int]$complexPasswordLength = 16,
    [switch]$complexPasswordAllowSpecialChars,
    [switch]$disableTechleadUser,
    [switch]$createCsvFiles

)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent $scriptPath


function generatePassword {
    param(
        [ValidateSet("simple","complex")]
        [string]$strength="simple",
        [string[]]$simpleAdjectives = @(),
        [string[]]$simpleNouns = @(),
        [ValidateRange(12,64)]
        [int]$complexLength = 16,
        [switch]$complexAllowSpecialChars
    )
    if($strength -eq "simple") {
        # simple password
        if($null -ne $simpleAdjectives -and $simpleAdjectives.Count -gt 0) {
            $adjectives = $simpleAdjectives
        } else {
            $adjectives = @('big','small','tasty','sweet','sour','fresh','ripe','juicy','delicious','yummy','crisp','zesty','fruity','succulent', 'flavorful')
        }
        if($null -ne $simpleNouns -and $simpleNouns.Count -gt 0) {
            $fruits = $simpleNouns
        } else {
            $fruits = @('apple','banana','cherry','grape','kiwi','lemon','mango','nectarine','orange','papaya','quince','raspberry','strawberry','tangerine','watermelon')
        }
        # password is adjective + fruit + 2 digit number
        return ($adjectives | Get-Random) + "-" + ($fruits | Get-Random) + "-" + (Get-Random -Minimum 10 -Maximum 99).ToString()

    }
    else {
        # complex password
        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        $specialChars = '!@#&$/*-_=+;:,.?'

        $pwd = -join ((1..$complexLength) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
        if($complexAllowSpecialChars) {
            # replace some characters with special characters
            $numSpecialChars = [Math]::Max(1, [Math]::Floor($complexLength / 8))
            for($i=0; $i -lt $numSpecialChars; $i++) {
                $pos = Get-Random -Minimum 2 -Maximum $complexLength
                $specialChar = $specialChars[(Get-Random -Maximum $specialChars.Length)]
                $pwd = $pwd.Substring(0, $pos - 1) + $specialChar + $pwd.Substring($pos)
            }
        }
        return $pwd        
    }
}


$users = @()
if($disableTechleadUser -or $numberOfTenants -le 1) {
    Write-Host "Techlead user creation is disabled."
 }
else {
    # add a techlead user (always with highest complex password + 4 extra length)
    $users += [PSCustomObject]@{
        "username" = "techlead1"
        "password" = ( generatePassword -strength "complex" -complexLength ($complexPasswordLength + 4) -complexAllowSpecialChars )
        "role" = "techlead"
    }
}

# digits of numberOfTenants
$tenantDigits = $numberOfTenants.ToString().Length

# add hacker and coach users for each tenant
for ($i = 1; $i -le $numberOfTenants; $i++) {
    $paddedIndex = $i.ToString().PadLeft($tenantDigits, '0')
    $users += [PSCustomObject]@{
        "username" = ( $baseHackerUsername + $paddedIndex )
        "password" = ( generatePassword -strength $hackerPasswordStrength -simpleAdjectives $simplePasswordAdjectives -simpleNouns $simplePasswordNouns -complexLength $complexPasswordLength -complexAllowSpecialChars:$complexPasswordAllowSpecialChars )
        "role" = "hacker"
        "tenant" = ( "team" + $paddedIndex )
    }
    $users += [PSCustomObject]@{
        "username" = ( $baseCoachUsername + $paddedIndex )
        "password" = ( generatePassword -strength $coachPasswordStrength -simpleAdjectives $simplePasswordAdjectives -simpleNouns $simplePasswordNouns -complexLength $complexPasswordLength -complexAllowSpecialChars:$complexPasswordAllowSpecialChars )
        "role" = "coach"
        "tenant" = ( "team" + $paddedIndex )
    }
}


$users | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path -Path $consoleRoot -ChildPath "users.json") -Encoding utf8

if($createCsvFiles) {
    $users  | Where-Object { $_.role -eq "hacker" } | Select-Object tenant,username,password | ConvertTo-Csv | Out-File -FilePath (Join-Path -Path $consoleRoot -ChildPath "users-hackers.csv") -Encoding utf8
    $users  | Where-Object { $_.role -eq "coach" } | Select-Object tenant,username,password | ConvertTo-Csv | Out-File -FilePath (Join-Path -Path $consoleRoot -ChildPath "users-coaches.csv") -Encoding utf8
}