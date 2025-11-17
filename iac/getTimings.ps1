[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$storageAccountName,
    [string]$ResourceGroupName = "HackConsole",
    [string]$ip = "",
    [switch]$skipFirewallRule
)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$consoleRoot = Split-Path -Parent $scriptPath


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

try {
    $allRows = @()
    Write-Host "Preparing storage context"
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $storageAccountName).Value[0]
    $script:context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    $script:table = Get-AzStorageTable -Name 'settings' -Context $script:context

    # Retrieve all entries from the 'settings' table
    $query = New-Object Microsoft.Azure.Cosmos.Table.TableQuery
    $query.FilterString = "RowKey ge 'Statistics|ChallengeCompletionSeconds' and RowKey le 'Statistics|ChallengeCompletionSecondz'"
    $allEntries = $script:table.CloudTable.ExecuteQuery($query)
    foreach ($entry in $allEntries) {
        if($entry.RowKey -ne "Statistics|ChallengeCompletionSeconds") {
            continue
        }
        $r = @{
            Tenant = $entry.PartitionKey
        }
        foreach ($property in $entry.Properties.GetEnumerator()) {
            if($property.Key -in @("Tenant", "group", "key")) {
                continue
            }
            $r[$property.Key] = $property.Value
            Write-Host "$($entry.PartitionKey) - $($property.Key): $($property.Value)"
        }
        if($r.Count -le 1) {
            continue
        }
        $r["Tenant"] = $entry.PartitionKey
        $allRows += ([pscustomobject]$r)
    }
    # ensure that all rows have the same properties (add empty string for missing ones)
    $rowKeys = @()
    foreach($r in $allRows) {
        foreach($key in $r.PSObject.Properties.Name) {
            if(-not ($rowKeys -contains $key)) {
                $rowKeys += $key
            }
        }
    }
    $rowKeys = $rowKeys | Sort-Object
    $allFinalRows = @()
    foreach($r in $allRows) {
        # convert to pscustomobject to hashtable
        $nr = [ordered]@{}
        $nr["Tenant"] = $r.Tenant
        foreach($key in $rowKeys) {
            if($r.PSObject.Properties.Match($key)) {
                $nr[$key] = $r.$key
            }
            else {
                $nr[$key] = ""
            }
        }
        $allFinalRows += ([pscustomobject]$nr)
    }
    $allRows = $null
    # naturally sort by Tenant
    $allFinalRows | Sort-Object Tenant | ConvertTo-Csv -NoTypeInformation | Out-File (Join-Path -Path $consoleRoot -ChildPath "timings.csv")
    Write-Host "Timings exported to $(Join-Path -Path $consoleRoot -ChildPath "timings.csv")"
}
catch {
    Write-Error "An error occurred: $_"
}
finally {
    if ($script:firewallAdded) {
        Write-Host "Removing firewall rule for the client ip ($($script:ipToUse))"
        Remove-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroupName -Name $storageAccountName -IPAddressOrRange "$($script:ipToUse)" -ErrorAction Stop | Out-Null
    }
}
