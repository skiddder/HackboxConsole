# WhatTheHack Documentation

Run a [WhatTheHack](https://github.com/microsoft/WhatTheHack) hackathon with the Hackathon Console.

1. Choose a hack
   ```pwsh
   .\documentation\WhatTheHack\chooseWhatTheHack.ps1
   ```
1. Prepare the environment for the chosen hack
   ```pwsh
   .\documentation\WhatTheHack\chooseWhatTheHack.ps1 -HackName "001-IntroToKubernetes"
   # some hacks offer variants, e.g. "A" or "B" (for example "001-IntroToKubernetes")
   # .\documentation\WhatTheHack\chooseWhatTheHack.ps1 -HackName "001-IntroToKubernetes" -HackVariant "B"
   ```
1. Start the Hackathon Console (in this example, we prepare logins for 4 teams with a single coach for each team)
   ```pwsh
   .\iac\createUsers.ps1 -numberOfTenants 4
   ```
1. Deploy to Azure
   ```pwsh
   .\iac\deployHackerConsole.ps1 -doNotCopyChallengesOrSolutions
   ```
1. Check the users.json file for the logins of the teams and coaches
1. (optional) In case you want to run it within environments:

   1. Follow the instructions in the chosen hack's README.md file.
   1. Publish credentials to foreach team
      ```pwsh
      # for csv with required columns: name, value   (optional columns: group, tenant)
      Get-Content .\creds.csv | ConvertFrom-Csv | .\iac\addMultipleCredentails.ps1 -storageAccountName remsa001 -storageAccountName "storage...."
      # for json array of objects with required attributes: name, value   (optional attributes: group, tenant)
      Get-Content .\creds.json | ConvertFrom-Json | .\iac\addMultipleCredentails.ps1 -storageAccountName remsa001 -storageAccountName "storage...." 
      ```
