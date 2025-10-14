param(
    [string]$HackName = "",
    [switch]$Download
)

$script:scriptPath = (Get-Item "$PSScriptRoot").FullName
$script:WhatTheHackRepo = (Join-Path $script:scriptPath "Repo")
$script:ConsoleRoot =  (Get-Item "$PSScriptRoot/../..").FullName


if(($Download) -and (Test-Path "$script:WhatTheHackRepo" -PathType Container)){
    Write-Host "WhatTheHack Repo already exists locally. Using cached version. Use -Download to re-download the repo."
}
else {
    Write-Host "Downloading WhatTheHack Repo from GitHub"
    <#
    if(Test-Path "$script:WhatTheHackRepo" -PathType Container) {
        Remove-Item "$script:WhatTheHackRepo" -Recurse -Force | Out-Null
    }
    New-Item -Path "$script:WhatTheHackRepo" -ItemType Directory | Out-Null
    if(Test-Path "$script:WhatTheHackRepo.zip" -PathType Leaf) {
        Remove-Item "$script:WhatTheHackRepo.zip" -Force
    }
    Invoke-WebRequest -Uri "https://github.com/microsoft/WhatTheHack/archive/refs/heads/master.zip" -OutFile "$script:WhatTheHackRepo.zip"
    Expand-Archive "$script:WhatTheHackRepo.zip" -DestinationPath "$script:WhatTheHackRepo"
    #>
}


function getRelativeHackPaths {
    $hacks = @()
    foreach($rd in (Get-ChildItem -Path "$script:WhatTheHackRepo" -Directory)) {
        foreach($hack in (Get-ChildItem -Path "$($rd.FullName)" -Directory)) {
            if($hack.Name -notmatch "^[0-9]+-" -and $hack.Name.StartsWith("000-")) {
                continue
            }
            if(
                -not (Test-Path "$($hack.FullName)/Coach" -PathType Container) -or 
                -not (Test-Path "$($hack.FullName)/Student" -PathType Container)
            ) {
                continue
            }
            $hacks += [PSCustomObject]@{
                Name = $hack.Name
                Path = $hack.FullName
                RelativePath = $hack.FullName.Substring($script:WhatTheHackRepo.Length+1)
            }
        }
        if(
            (Test-Path "$($rd.FullName)/Coach" -PathType Container) -or 
            (Test-Path "$($rd.FullName)/Student" -PathType Container)
        ) {
            $hacks += [PSCustomObject]@{
                Name = $rd.Name
                Path = $rd.FullName
                RelativePath = $rd.FullName.Substring($script:WhatTheHackRepo.Length+1)
            }
        }
    }
    return $hacks
}

function validateHackName {
    param (
        [string]$HackName
    )

    $chosenHackRelativePathCount = 0
    $chosenHackRelativePath = $null
    $chosenHackNameCount = 0
    $chosenHackName = $null
    foreach($h in getRelativeHackPaths) {
        if($h.Name -ieq $HackName) {
            $chosenHackNameCount++
            $chosenHackName = $h
        }
        if($h.RelativePath -ieq $HackName) {
            $chosenHackRelativePathCount++
            $chosenHackRelativePath = $h
        }
    }
    if($chosenHackRelativePathCount -gt 0) {
        return $chosenHackRelativePath
    }
    elseif($chosenHackNameCount -gt 0) {
        if($chosenHackNameCount -gt 1) {
            Write-Warning "Multiple hacks found with the name '$HackName'. Please specify the relative path instead."
        }
        return $chosenHackName
    }
    else {
        throw "No hack found with the name or relative path '$HackName'."
    }    
}

function rewriteMdFile {
    param (
        [string]$FilePath
    )

    $content = (Get-Content -Path $FilePath -Raw).Trim() -split "`n"

    # cleaning up the title
    $content[0] = $content[0] -replace "^#\s+Challenge\s+\d+(\s*[:-])?", "#"

    # navigation bars
    for($i=0; $i -lt 5  -and $i -lt $content.Count; $i++) {
        if($content[$i].Contains("[Home](") -and ( $content[$i].Contains("Challenge") -or $content[$i].Contains("Solution") ) ) {
            $content[$i] = ""
            break
        }
    }

    $content = $content -join "`n"

    # rewriting relative links
    $content = $content -replace "\]\(\.\.\/\.\.\/000-HowToHack\/", "](../000-HowToHack/"

    Set-Content -Path $FilePath -Value $content
}

if($HackName -eq "") {
    getRelativeHackPaths
}
else {
    $chosenHack = validateHackName -HackName $HackName
    if($chosenHack) {
        Write-Host "Using hack: $($chosenHack.RelativePath)"
    }
    else {
        throw "No valid hack found for: $HackName"
    }

    # Clean up existing challenges and solutions
    foreach($subdir in @("challenges", "solutions")) {
        if(Test-Path (Join-Path $script:ConsoleRoot "hack_console" $subdir)  -PathType Container) {
            Write-Host "Removing existing $subdir from hack_console"
            Remove-Item (Join-Path $script:ConsoleRoot "hack_console" $subdir) -Recurse -Force | Out-Null
        }
        New-Item -Path (Join-Path $script:ConsoleRoot "hack_console" $subdir) -ItemType Directory | Out-Null
    }

    # Always copy HowToHack
    foreach($rd in (Get-ChildItem -Path "$script:WhatTheHackRepo" -Directory)) {
        if($rd.Name -eq "000-HowToHack") {
            Write-Host "Copying HowToHack to hack_console"
            Write-Host "Copying files from $($rd.FullName) to $(Join-Path $script:ConsoleRoot "hack_console" "challenges")"
            foreach($subdir in @("challenges", "solutions")) {
                Copy-Item -Path $rd.FullName -Destination (Join-Path $script:ConsoleRoot "hack_console" $subdir) -Recurse -Force | Out-Null
            }
            break
        }
        foreach($hack in (Get-ChildItem -Path "$($rd.FullName)" -Directory)) {
            if($hack.Name -eq "000-HowToHack") {
                Write-Host "Copying HowToHack to hack_console"
                foreach($subdir in @("challenges", "solutions")) {
                    Copy-Item -Path $hack.FullName -Destination (Join-Path $script:ConsoleRoot "hack_console" $subdir) -Recurse -Force | Out-Null
                }
                break
            }
        }
    }
    #remove any *challenge*.md files from HowToHack in solutions
    foreach($subdir in @("challenges", "solutions")) {
        Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" "$subdir" "000-HowToHack") -Recurse -Filter *challenge*.md | Remove-Item -Force | Out-Null
    }

    Write-Host "Copying challenges to hack_console"
    Get-ChildItem -Path $chosenHack.Path | Where-Object { $_.Name -ne "Coach" -and $_.Name.StartsWith(".") -eq $false }  | Copy-Item -Destination (Join-Path $script:ConsoleRoot "hack_console" "challenges") -Recurse -Force | Out-Null
    Write-Host "Copying solutions to hack_console"
    Get-ChildItem -Path $chosenHack.Path | Where-Object { $_.Name -ne "Student" -and $_.Name.StartsWith(".") -eq $false }  | Copy-Item -Destination (Join-Path $script:ConsoleRoot "hack_console" "solutions") -Recurse -Force | Out-Null

    Write-Host "Renaming .md files (if applicable)"
    foreach($mdFile in (Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" "challenges" "Student") -Filter *.md)) {
        Write-Host "Processing $($mdFile.Name)"
        if((-not $mdFile.Name.ToLower().Contains("challenge")) -and $mdFile.Name -match "^[0-9]+-") {
            $newName = $mdFile.Name -replace "^(?<num>[0-9]+)-", 'Challenge-${num}-'
            Write-Host "`tRenaming $($mdFile.Name) to $newName"
            Rename-Item -Path $mdFile.FullName -NewName $newName
    
        }
    }
    foreach($mdFile in (Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" "solutions" "Coach") -Filter *.md)) {
        if((-not $mdfile.Name.ToLower().Contains("solution")) -and $mdFile.Name -match "^[0-9]+-") {
            $newName = $mdFile.Name -replace "^(?<num>[0-9]+)-", 'Solution-${num}-'
            Write-Host "`tRenaming $($mdFile.Name) to $newName"
            Rename-Item -Path $mdFile.FullName -NewName $newName
    
        }
    }

    Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" "challenges" "Student") -Recurse | Where-Object { $_.Name -ne "download-Student.zip" -and $_.Name -notlike "*.md" } | Compress-Archive -DestinationPath (Join-Path $script:ConsoleRoot "hack_console" "challenges" "download-Student.zip") -Force | Out-Null
    Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" "solutions" "Coach") -Recurse | Where-Object { $_.Name -ne "download-Coach.zip" -and $_.Name -notlike "*.md" } | Compress-Archive -DestinationPath (Join-Path $script:ConsoleRoot "hack_console" "solutions" "download-Coach.zip") -Force | Out-Null

    Write-Host "Rewriting .md files"
    foreach($subdir in @("challenges", "solutions")) {
        foreach($mdFile in (Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" $subdir) -Recurse -Filter *.md)) {
            rewriteMdFile -FilePath $mdFile.FullName
        }
        foreach($role in @("Student", "Coach")) {
            if(Test-Path (Join-Path $script:ConsoleRoot "hack_console" $subdir $role) -PathType Container) {
                $prereqFile = $null
                foreach($mdFile in (Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" $subdir $role) -Filter 00*.md)) {
                    $prereqFile = $mdFile
                    break
                }
                if($null -eq $prereqFile) {
                    foreach($mdFile in (Get-ChildItem -Path (Join-Path $script:ConsoleRoot "hack_console" $subdir $role) -Filter *00*.md)) {
                        $prereqFile = $mdFile
                        break
                    }

                    if($null -eq $prereqFile) {
                        Write-Warning "No prerequisites file found in $subdir. It's recommended to have a prerequisites file named '00*.md' or similar."
                    }
                }
                if($prereqFile) {
                    Write-Host "Adding download link to $($prereqFile.Name)"
                    $content = (Get-Content $prereqFile.FullName -Raw).Trim() -split "`n"
                    $content = (
                        $content[0] + "`n`n" +
                        "> [!IMPORTANT]`n" +
                        "> **Please download this file before proceeding: [download-$($role).zip](../download-$($role).zip)**`n" +
                        "> `n" +
                        "> This is required content, that you will need to complete the hack.`n" +
                        ($content[1..($content.Count-1)] -join "`n")
                    )
                    Set-Content -Path $prereqFile.FullName -Value $content
                }
            }
        }

    }
}


