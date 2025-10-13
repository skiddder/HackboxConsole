param(
    [ValidateRange(1,100)]
    [int]$numberOfTenants=2,
    [string]$baseHackerUsername="hacker",
    [string]$baseCoachUsername="coach",
    [ValidateSet("simple","complex")]
    [string]$hackerPasswordStrength="simple",
    [ValidateSet("simple","complex")]
    [string]$coachPasswordStrength="complex"
)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent $scriptPath


function generatePassword {
    param(
        [ValidateSet("simple","complex")]
        [string]$strength="simple"
    )
    if($strength -eq "simple") {
        # simple password
        $length = 8
        $fruits = @('apple','banana','cherry','grape','kiwi','lemon','mango','nectarine','orange','papaya','quince','raspberry','strawberry','tangerine','watermelon')
        $adjectives = @('big','small','tasty', 'sweet','sour','fresh','ripe','juicy','delicious','yummy','crisp','zesty','fruity','succulent', 'flavorful')

        # password is adjective + fruit + 2 digit number
        return ($adjectives | Get-Random) + "-" +($fruits | Get-Random) + "-" + (Get-Random -Minimum 10 -Maximum 99).ToString()

    } else {
        # complex password
        $length = 16
        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        return -join ((1..$length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    }
}


$users = @()
for ($i = 1; $i -le $numberOfTenants; $i++) {
    $users += [PSCustomObject]@{
        "username" = ( $baseHackerUsername + $i )
        "password" = ( generatePassword -strength $hackerPasswordStrength )
        "role" = "hacker"
        "tenant" = ( "team" + $i )
    }
    $users += [PSCustomObject]@{
        "username" = ( $baseCoachUsername + $i )
        "password" = ( generatePassword -strength $coachPasswordStrength )
        "role" = "coach"
        "tenant" = ( "team" + $i )
    }
}


$users | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path -Path $consoleRoot -ChildPath "users.json") -Encoding utf8
