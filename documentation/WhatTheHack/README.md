# WhatTheHack Documentation

Run a [WhatTheHack](https://github.com/microsoft/WhatTheHack) hackathon with the Hackathon Console.

> [!NOTE]
> Most of the WhatTheHack hacks are supported. There are some, that do not have markdown files (just word or powerpoint files) and those are not supported.

## Prerequisites
 - Powershell 7+
 - Azure Az Module
 - Git
 - Azure Subscription
 - This repository cloned (``git clone https://github.com/qxsch/HackboxConsole.git``)


## Execution Steps

1. Choose a hack
   ```pwsh
   .\documentation\WhatTheHack\chooseWhatTheHack.ps1 | Format-Table Name, RelativePath, HackVariants
   ```
1. Prepare the environment for the chosen hack
   ```pwsh
   .\documentation\WhatTheHack\chooseWhatTheHack.ps1 -HackName "001-IntroToKubernetes"
   # some hacks offer variants, e.g. "A" or "B" or "C" or "D" for "001-IntroToKubernetes"
   # .\documentation\WhatTheHack\chooseWhatTheHack.ps1 -HackName "001-IntroToKubernetes" -HackVariant "B"
   ```
1. Create the Hackathon Console Users (in this example, we prepare logins for 4 teams with a single coach for each team)
   ```pwsh
   .\iac\createUsers.ps1 -numberOfTenants 4
   ```
1. Deploy to Azure
   ```pwsh
   .\iac\deployHackerConsole.ps1 -doNotCopyChallengesOrSolutions
   ```
1. Check the users.json file for the logins of the teams and coaches
1. (optional) In case you want to run it within pre-built environments:

   1. Follow the instructions in the chosen hack's prerequisites markdown file to create the environments for each team
   1. Put the credentials for each environments into a csv or json file
      - csv with required columns: name, value, tenant   (optional columns: group)
      - json array of objects with required attributes: name, value, tenant   (optional attributes: group)
      - tenant must match the tenant name in users.json (follows the pattern "team1", "team2", ...)
   1. Publish credentials
      ```pwsh
      # for csv with required columns: name, value   (optional columns: group, tenant)
      Get-Content .\creds.csv | ConvertFrom-Csv | .\iac\addMultipleCredentails.ps1 -storageAccountName remsa001 -storageAccountName "storage...."
      # for json array of objects with required attributes: name, value   (optional attributes: group, tenant)
      Get-Content .\creds.json | ConvertFrom-Json | .\iac\addMultipleCredentails.ps1 -storageAccountName remsa001 -storageAccountName "storage...." 
      ```
