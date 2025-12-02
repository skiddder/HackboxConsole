<#
.SYNOPSIS
Add multiple credentials into the storage table used by the console.

.DESCRIPTION
Accepts objects containing credential metadata (name, value, group, tenant)
and writes them to the credentials table of the specified storage account.
Optionally adds and removes a temporary firewall rule to permit access.

.PARAMETER storageAccountName
Name of the Azure Storage Account that hosts the credentials table.

.PARAMETER ResourceGroupName
Resource group containing the storage account. Defaults to 'HackConsole'.

.PARAMETER ip
Client IPv4 address to allow through the storage account firewall.
When omitted, the script resolves the public IP automatically.

.PARAMETER skipFirewallRule
Skip adding and removing the temporary firewall rule for the client IP.

.PARAMETER InputObject
Credential payload objects received from the pipeline or passed explicitly.
Each object should expose at least the 'name' and 'value' properties, and can
optionally include 'group' and 'tenant' to override their defaults.

.EXAMPLE
Get-Content .\creds.json | ConvertFrom-Json | .\addMultipleCredentails.ps1 -storageAccountName 'contosovault' -ResourceGroupName 'HackConsole'
Loads credential objects from creds.json and writes them to the credentials table.

.EXAMPLE
[pscustomobject]@{ name = 'ApiKey'; value = 'secret'; group = 'Prod'; tenant = 'team1' } |
  .\addMultipleCredentails.ps1 -storageAccountName 'storageName'
Creates an inline credential object and submits it directly through the pipeline.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$storageAccountName,
    [string]$ResourceGroupName = "HackConsole",
    [string]$ip = "",
    [switch]$skipFirewallRule,
    [Parameter(ValueFromPipeline = $true)]
    [psobject]$InputObject
)

begin {
    $script:firewallAdded = $false
    if(-not $skipFirewallRule) {
        # add the client ip to the storage account firewall
        $script:ipToUse = $ip
        if([string]::IsNullOrWhiteSpace($script:ipToUse)) {
            $script:ipToUse  = (Invoke-RestMethod https://ipinfo.io/json).ip
        }

        Write-Host "Adding firewall rule for the client ip ($script:ipToUse)"
        Add-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroupName -Name $storageAccountName -IPAddressOrRange "$script:ipToUse" -ErrorAction Stop | Out-Null
        $script:firewallAdded = $true

        Write-Host "Waiting for 10 seconds for the firewall rule to take effect"
        Start-Sleep -Seconds 10
    }

    Write-Host "Preparing storage context"
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $storageAccountName).Value[0]
    $script:context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    $script:table = Get-AzStorageTable -Name 'credentials' -Context $script:context
}

process {
    try {
        if ($null -eq $InputObject) {
            Write-Warning "Received null input object, skipping."
            return
        }

        # Extract properties from the input object
        $name = $InputObject.name
        $value = $InputObject.value

        $group = if ($InputObject.PSObject.Properties.Match('group')) { $InputObject.group } else { 'Default' }
        $group = (($group.ToCharArray() | Where-Object { $_ -match '[a-zA-Z0-9_-]' }) -join '').Trim()
        if ($group -eq '') { $group = 'Default' }
        $tenant = if ($InputObject.PSObject.Properties.Match('tenant')) { $InputObject.tenant } else { 'Default' }
        $note = if ($InputObject.PSObject.Properties.Match('note')) { $InputObject.note } else { '' }
        if($note.Length -gt 160) {
            Write-Warning "Note length exceeds 160 characters. Truncating."
            $note = $note.Substring(0, 160)
        }
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($value)) {
            Write-Warning "Input object must have non-empty 'name' and 'value' properties. Skipping this entry."
            return
        }

        # group validation
        $entity = New-Object -TypeName Microsoft.Azure.Cosmos.Table.DynamicTableEntity -ArgumentList $tenant, "$group|$name"
        $entity.Properties.Add('group', [Microsoft.Azure.Cosmos.Table.EntityProperty]::GeneratePropertyForString($group))
        $entity.Properties.Add('name', [Microsoft.Azure.Cosmos.Table.EntityProperty]::GeneratePropertyForString($name))
        $entity.Properties.Add('Credential', [Microsoft.Azure.Cosmos.Table.EntityProperty]::GeneratePropertyForString($value))
        $entity.Properties.Add('note', [Microsoft.Azure.Cosmos.Table.EntityProperty]::GeneratePropertyForString($note))
        $tableOperation = [Microsoft.Azure.Cosmos.Table.TableOperation]::InsertOrReplace($entity)
        $status = $script:table.CloudTable.Execute($tableOperation)
        if($status.HttpStatusCode -ge 200 -and $status.HttpStatusCode -lt 300) {
            Write-Host "Successfully added credential '$name' in group '$group' for tenant '$tenant'."
        }
        else {
            Write-Warning "Failed to add credential '$name' in group '$group' for tenant '$tenant'. Status code: $($status.HttpStatusCode)"
        }
    }
    catch {
        Write-Error "An error occurred: $_"
    }
}

end {
    if ($script:firewallAdded) {
        Write-Host "Removing firewall rule for the client ip ($($script:ipToUse))"
        Remove-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroupName -Name $storageAccountName -IPAddressOrRange "$($script:ipToUse)" -ErrorAction Stop | Out-Null
    }
}
