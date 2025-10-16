# MicroHack Documentation

Run a [MicroHack](https://github.com/microsoft/MicroHack) ([Offical Website](https://www.microsoft.com/de-de/techwiese/events/microhacks/default.aspx)) hackathon with the Hackathon Console.

## Prerequisites
 - Powershell 7+
 - Azure Az Module
 - Git
 - Azure Subscription
 - This repository cloned (``git clone https://github.com/qxsch/HackboxConsole.git``)

## Execution Steps

1. Choose a hack
   ```pwsh
   .\documentation\MicroHack\chooseMicroHack.ps1 | Format-Table Name, RelativePath, HackVariants
   ```
