param(
    [Parameter(Mandatory = $true)]
    [string]$storageAccountName,
    [Parameter(Mandatory = $true)]
    [string]$name,
    [Parameter(Mandatory = $true)]
    [string]$value,
    [string]$group='Default',
    [string]$tenant='Default',
    [string]$ResourceGroupName = "HackConsole",
    [string]$ip = ""
)

# group validation
$group = (($group.ToCharArray() | Where-Object { $_ -match '[a-zA-Z0-9_-]' }) -join '').Trim()

# add the client ip to the storage account firewall
if($ip -eq "") {
    $ip = (Invoke-RestMethod http://ipinfo.io/json).ip
}
Write-Host "Adding firewall rule for the client ip ($ip)"
Add-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroupName -Name $storageAccountName -IPAddressOrRange "$ip" -ErrorAction Stop | Out-Null

Write-Host "Waiting for 10 seconds for the firewall rule to take effect"
Start-Sleep -Seconds 10

Write-Host "Adding credential to the storage account table"
#add an entry to the storage account table
$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $storageAccountName).Value[0]
$context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
$table = Get-AzStorageTable -Name 'credentials' -Context $context

$entity = New-Object -TypeName Microsoft.Azure.Cosmos.Table.DynamicTableEntity -ArgumentList $tenant, "$group|$name"
$entity.Properties.Add('group', $group)
$entity.Properties.Add('name', $name)
$entity.Properties.Add('Credential', $value)
$tableOperation = [Microsoft.Azure.Cosmos.Table.TableOperation]::InsertOrReplace($entity)
$table.CloudTable.Execute($tableOperation)


# remove the firewall rule
Write-Host "Removing firewall rule for the client ip ($ip)"
Remove-AzStorageAccountNetworkRule -ResourceGroupName $ResourceGroupName -Name $storageAccountName -IPAddressOrRange "$ip" -ErrorAction Stop | Out-Null

