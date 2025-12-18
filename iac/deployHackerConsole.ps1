param (
    [string]$SourceChallengesDir = "",
    [string]$SourceSolutionsDir = "",
    [string]$ResourceGroupName = "HackConsole",

    [string]$location = $null,
    [string]$webAppName = $null,
    [string]$sku = $null,
    [string]$workerSize = $null,

    [string]$hackerUsername = "",
    [securestring]$hackerPassword = $null,
    [string]$coachUsername = "",
    [securestring]$coachPassword = $null,

    [switch]$doNotCopyChallengesOrSolutions,
    [switch]$doNotCleanUp
)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent $scriptPath

if(-not (Get-Module -ListAvailable -Name Az)) {
    Install-Module -Name Az -AllowClobber -Force
}
Import-Module Az.Accounts
Import-Module Az.Websites
Import-Module Az.Resources



if(-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    Connect-AzAccount -UseDeviceAuthentication
}

# Install required PowerShell modules
if((-not (Get-Command bicep.exe -ErrorAction SilentlyContinue)) -and (-not (Get-Command bicep -ErrorAction SilentlyContinue))) {
    Write-Error "Bicep CLI not found. Go to: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#azure-powershell"
    throw "Bicep CLI not found. Please install Bicep CLI and make sure it is in your PATH."
}

# does the file exist?
if(-not (Test-Path (Join-Path $consoleRoot "users.json") -PathType Leaf)) {
    if($hackerUsername -eq "" -or $coachUsername -eq "" -or $hackerPassword -eq $null -or $coachPassword -eq $null) {
         throw "Either provide the users.json file or provide all four parameters: hackerUsername, hackerPassword, coachUsername, coachPassword"
    }
}
else {
    if($hackerUsername -ne "" -or $coachUsername -ne "" -or $hackerPassword -ne $null -or $coachPassword -ne $null) {
        Write-Warning "Both users.json file and user parameters provided. The users.json file will be used."
    }
    # use defaults for template / they will be ignored by the application if users.json is present
    $hackerUsername = "hacker"
    $hackerPassword = ConvertTo-SecureString -String "hackerPassword" -AsPlainText -Force
    $coachUsername = "coach"
    $coachPassword = ConvertTo-SecureString -String "coachPassword" -AsPlainText -Force
}

if(-not $doNotCopyChallengesOrSolutions) {
    if($SourceChallengesDir -eq "") {
        throw "SourceChallengesDir must be provided"
    }
    if($SourceSolutionsDir -eq "") {
        throw "SourceSolutionsDir must be provided"
    }
    if(-not (Test-Path $SourceChallengesDir -PathType Container)) {
        throw "SourceChallengesDir must be a directory"
    }
    if(-not (Test-Path $SourceSolutionsDir -PathType Container)) {
        throw "SourceSolutionsDir must be a directory"
    }
    Write-Host "Copying challenges and solutions to the console"
    # remove the challenges directory
    Remove-Item -Path (Join-Path $consoleRoot "hack_console" "challenges") -Recurse -Force
    # remove the solutions directory
    Remove-Item -Path (Join-Path $consoleRoot "hack_console" "solutions") -Recurse -Force
    # copy the challenges to the console
    Copy-Item -Path $SourceChallengesDir -Destination (Join-Path $consoleRoot "hack_console" ) -Recurse
    # copy the solutions to the console
    Copy-Item -Path $SourceSolutionsDir -Destination (Join-Path $consoleRoot "hack_console" ) -Recurse
}
if(-not (Test-Path (Join-Path $consoleRoot "hack_console" "challenges") -PathType Container)) {
    throw "Challenges directory not found"
}
if(-not (Test-Path (Join-Path $consoleRoot "hack_console" "solutions") -PathType Container)) {
    throw "Solutions directory not found"
}
# no md files pattern challenge-*.md in the challenges directory (recursively)
$challengeMdFileCount = (Get-ChildItem -Path (Join-Path $consoleRoot "hack_console" "challenges") -Recurse -Filter "*challenge*.md").Count
Write-Host "  - Found $challengeMdFileCount challenges md files"
if($challengeMdFileCount -eq 0) {
    throw "No challenges md files found in the challenges directory"
}
$solutionMdFileCount = (Get-ChildItem -Path (Join-Path $consoleRoot "hack_console" "solutions") -Recurse -Filter "*solution*.md").Count
Write-Host "  - Found $solutionMdFileCount solutions md files"
if($solutionMdFileCount  -eq 0) {
    throw "No solutions md files found in the solutions directory"
}
if($challengeMdFileCount -ne $solutionMdFileCount) {
    Write-Warning "The number of challenges md files does not match the number of solutions md files"
}

Write-Host "Removing all __pycache__ directories"
Get-ChildItem -Path (Join-Path $consoleRoot "hack_console") -Recurse -Directory -Filter "__pycache__" | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force }

# run the bicep deployment
Write-Host ( "Deploying the hacker console to Resource Group $ResourceGroupName (Subscription: " + ((Get-AzContext).Subscription.Id) + ")" )
$params = @{
    TemplateFile = (Join-Path $scriptPath "deployment.bicep")
    ResourceGroupName = $ResourceGroupName
    hackerUsername = $hackerUsername
    hackerPassword = $hackerPassword
    coachUsername = $coachUsername
    coachPassword = $coachPassword
}
if(-not($null -eq $location -or $location -eq "")) {
    $params["location"] = $location
}
if(-not($null -eq $webAppName -or $webAppName -eq "")) {
    $params["webAppName"] = $webAppName
}
if(-not($null -eq $sku -or $sku -eq "")) {
    Write-Host "Setting sku to $sku"
    $params["sku"] = $sku
}
if(-not($null -eq $workerSize -or $workerSize -eq "")) {
    $params["workerSize"] = $workerSize
}
$deployment = New-AzResourceGroupDeployment @params -Name "hackboxconsole"  -ErrorAction Continue -ErrorVariable +evx
if($null -eq $deployment) {
    foreach($ev in $evx) {
        if($ev.Exception.Message.Contains('soft-deleted')) {
            Write-Host -ForegroundColor Yellow "Soft deleted resource found:`n$($ev.Exception.Message)"
        }
        elseif($ev.Exception.Message.Contains('quota')) {
            Write-Host -ForegroundColor Yellow "Quota exceeded:`n$($ev.Exception.Message)"
        }
    }
    throw "Deployment failed"
}


Write-Host "Deployment completed"
Write-Host ( "  - Web App Name:         " + $deployment.Outputs.webAppName.Value )
Write-Host ( "  - Web App URL:          https://" + $deployment.Outputs.webAppUrl.Value )
Write-Host ( "  - Storage Account Name: " + $deployment.Outputs.storageAccountName.Value )



# deploying the zip package
Write-Host "Creating the zip package"
$zipPackagePath = Join-Path $scriptPath "hack_console.zip"
if(Test-Path $zipPackagePath) {
    Remove-Item $zipPackagePath -Force
}
Get-ChildItem $consoleRoot | Where-Object { $_.Name -notin @( "iac", "createdEntraIdUserSettings.json" ) -and (-not $_.Name.EndsWith('.csv')) } | Compress-Archive -DestinationPath $zipPackagePath
Write-Host "Publishing the zip package to the web app"
Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $deployment.Outputs.webAppName.Value -ArchivePath $zipPackagePath -Force -ErrorAction Stop | Out-Null



if(-not $doNotCleanUp) {
    Write-Host "Cleaning up"
    # clean up the zip package
    Remove-Item -Path $zipPackagePath -Force | Out-Null

    # just clean up the challenges and solutions directories, in case they got copied before
    if(-not $doNotCopyChallengesOrSolutions) {
        # clean up the challenges directory
        Remove-Item -Path (Join-Path $consoleRoot "hack_console" "challenges") -Recurse -Force | Out-Null
        New-Item -Path (Join-Path $consoleRoot "hack_console" "challenges") -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $consoleRoot "hack_console" "challenges" ".gitkeep") -ItemType File | Out-Null

        # clean up the solutions directory
        Remove-Item -Path (Join-Path $consoleRoot "hack_console" "solutions") -Recurse -Force | Out-Null
        New-Item -Path (Join-Path $consoleRoot "hack_console" "solutions") -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $consoleRoot "hack_console" "solutions" ".gitkeep") -ItemType File | Out-Null
    }
}


Write-Host -ForegroundColor Green ( "URL:  https://" + $deployment.Outputs.webAppUrl.Value )
