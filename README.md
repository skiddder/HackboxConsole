# HackBox Console

> [!NOTE]  
> Comes with support for:
> - Microsoft [WhatTheHack - Integration Guide](documentation/WhatTheHack/README.md)
> - Microsoft [MicroHack - Integration Guide](documentation/MicroHack/README.md)
> - Or your own markdown based challenges and solutions: [Generic Deployment Instructions](documentation/Generic/README.md)



![HackBox Console Main](./hackbox.jpg)

![HackBox Console Challenge View](./hackbox2.jpg)

A portal for **Hackathon participants** to access challenges and credentials.

A portal for **Hackathon coaches** to access challenges, solutions, credentials and unlock challenges for participants.

The HackBox Console also supports multitenancy (multiple teams with a single coach each) and can be integrated with other tools, that take care of the sandbox environment provisioning.

Solutions and challenges are stored in markdown files.
  * challanges should follow the format: ``challenge-*.md``, f.e. ``challenge-1.md``, ``challenge-2.md``, ...
  * solutions should follow the format:  ``solution-*.md``, f.e. ``solution-1.md``, ``solution-2.md``, ...

Thanks to [zero-md](https://github.com/zerodevx/zero-md) the markdown files are rendered as HTML with a broad support for markdown syntax:
- [x] Math rendering via [`KaTeX`](https://github.com/KaTeX/KaTeX)
- [x] [`Mermaid`](https://github.com/mermaid-js/mermaid) diagrams
- [x] Syntax highlighting via [`highlight.js`](https://github.com/highlightjs/highlight.js)
- [x] Language detection for un-hinted code blocks
- [x] Hash-link scroll handling
- [x] FOUC prevention
- [x] Auto re-render on input changes
- [x] Light and dark themes
- [x] Spec-compliant extensibility
- [x] Renders single secrets ``<secret group="groupname" name="secretname" show="true|false|alwayshidden" />``
- [x] Renders secrets group table ``<secretgroup group="azure" show="true|false|alwayshidden" />``

## Prerequisites
 - Powershell 7+
 - Azure Az Module
 - Git
 - Azure Subscription
 - Bicep installed ( https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#install-manually )
 - This repository cloned (``git clone https://github.com/qxsch/HackboxConsole.git``)

## How to build & Deploy

Have a directory containing the challenges. It will walk through the directory (including subdirectories) and look for files named ``*challenge*.md``.
Have a directory containing the solutions. It will walk through the directory (including subdirectories) and look for files named ``*solution*.md``.

Easy and quick way to test the console use:
```pwsh
# for single tenant run:
.\iac\deployHackerConsole.ps1 `
    -SourceChallengesDir ..\path\to\challenges\ `
    -SourceSolutionsDir ..\path\to\solutions\ `
    -hackerUsername "hacker" `
    -hackerPassword ("hacker" | ConvertTo-SecureString -AsPlainText -Force) `
    -coachUsername "coach" `
    -coachPassword ("coach" | ConvertTo-SecureString -AsPlainText -Force)
```

For real deployment use **one** of the following options:
  * [Generic Deployment Instructions](documentation/Generic/README.md)
  * [WhatTheHack - Integration Guide](documentation/WhatTheHack/README.md)
  * [MicroHack - Integration Guide](documentation/MicroHack/README.md)


## users.json - Multi Tenant User Definition
The easiest way to create the ``users.json`` file is to use the [createUsers.ps1](iac/createUsers.ps1) script.

Alternatively, you can copy the [sample-users.json](sample-users.json) file to ``users.json`` and then modify it to fit your needs.

The file has the following structure:
```json
[
    {
        "username": "admin",
        "password": "admin",
        "role": "coach",
        "tenant": "Default"
    }
]
```

| Attribute | Required? | Description |
|-----------|-----------|-------------|
| username  | **required** | The username of the user  |
| password  | **required** | The password of the user  |
| role      | **required** | The role of the user:<ul><li>**coach**: Can see unlocked challenges, solutions and credentials within his tenant. Can unlock challenges for hackers.</li><li>**hacker**: Can see only unlocked challenges and credentials within his tenant.</li><li>**techlead**: Can start/stop/reset timers and unlock challenges across all tenants. (Just create a techlead, if you have a more than 3 tenants.)</li></ul> |
| tenant    | **optional** | The tenant the user belongs to (each tenant must have at least one coach and one hacker) |

