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

If the 'connections' table is targeted, the object should have
'hackboxuser', 'user', 'pass', and 'host' properties,
with an optional 'port' and an optional 'hackboxconnection' property.

.EXAMPLE
Get-Content .\creds.json | ConvertFrom-Json | .\addMultipleCredentials.ps1 -storageAccountName 'contosovault' -ResourceGroupName 'HackConsole'
Loads credential objects from creds.json and writes them to the credentials table.

.EXAMPLE
[pscustomobject]@{ name = 'ApiKey'; value = 'secret'; group = 'Prod'; tenant = 'team1' } | .\addMultipleCredentials.ps1
Creates an inline credential object and submits it directly through the pipeline.

.EXAMPLE
[pscustomobject]@{ hackboxuser = 'hacker01'; user = 'admin'; pass = 'topsecret'; host = '10.1.2.3' ; port = 3389 } | .\addMultipleCredentials.ps1 -TableName 'connections'
Assigns the user an rdp connection in the connections table.

#>
[CmdletBinding()]
param(
    [string]$storageAccountName = "",
    [string]$ResourceGroupName = "HackConsole",
    [ValidateSet("credentials", "connections")]
    [string]$TableName = "credentials",
    [string]$ip = "",
    [switch]$skipFirewallRule,
    [Parameter(ValueFromPipeline = $true)]
    [psobject]$InputObject
)

begin {
    if([string]::IsNullOrWhiteSpace($storageAccountName)) {
        Write-Host "Storage account name not provided. Attempting to retrieve from resource group."
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName | Where-Object { $_.Kind -eq 'StorageV2' -and $_.StorageAccountName.StartsWith('storage') } | Select-Object -First 1
        if($null -eq $storageAccount) {
            throw "No suitable storage account found in resource group '$ResourceGroupName'. Please provide the storage account name explicitly."
        }
        $storageAccountName = $storageAccount.StorageAccountName
    }

    $script:firewallAdded = $false
    $script:publicAccessWasDisabled = $false
    if(-not $skipFirewallRule) {
        # Check if public network access is enabled
        $storageAccountInfo = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccountName -ErrorAction Stop
        if ($storageAccountInfo.PublicNetworkAccess -eq 'Disabled') {
            Write-Host "Public network access is disabled. Temporarily enabling it."
            Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccountName -PublicNetworkAccess Enabled -ErrorAction Stop | Out-Null
            $script:publicAccessWasDisabled = $true
            Write-Host "Waiting for 10 seconds for the public network access change to take effect"
            Start-Sleep -Seconds 10
        }

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

    # Helper function to get access token as plain string
    function Get-PlainAccessToken {
        param([string]$ResourceUrl, [string]$TenantId)
        
        $params = @{
            ResourceUrl = $ResourceUrl
            ErrorAction = 'Stop'
        }
        if ($TenantId) { $params.TenantId = $TenantId }
        
        $tokenResult = Get-AzAccessToken @params
        $token = $tokenResult.Token
        
        # Convert SecureString to plain text if needed
        if ($token -is [System.Security.SecureString]) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
            try {
                $token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        
        return @{
            Token = $token
            ExpiresOn = $tokenResult.ExpiresOn
        }
    }

    # Helper function to create SharedKey authorization header for storage account key auth
    function Get-SharedKeyAuthHeader {
        param(
            [string]$StorageAccountName,
            [string]$StorageAccountKey,
            [string]$Method,
            [string]$Resource,
            [string]$ContentType,
            [string]$Date
        )
        
        # SharedKeyLite for Table service: StringToSign = Date + "\n" + CanonicalizedResource
        $stringToSign = "$Date`n/$StorageAccountName/$Resource"
        
        # Create HMAC-SHA256 signature
        $keyBytes = [Convert]::FromBase64String($StorageAccountKey)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = $keyBytes
        $signatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign))
        $signature = [Convert]::ToBase64String($signatureBytes)
        
        return "SharedKeyLite $StorageAccountName`:$signature"
    }

    # Helper function to write entity using REST API (works with both auth methods)
    function Write-TableEntityRest {
        param(
            [string]$StorageAccountName,
            [string]$TableName,
            [string]$PartitionKey,
            [string]$RowKey,
            [hashtable]$Properties,
            [string]$StorageAccountKey = $null  # If provided, use SharedKey; otherwise use OAuth
        )
        
        $tableUrl = "https://$StorageAccountName.table.core.windows.net/$TableName"
        
        # Build entity body
        $entity = @{
            PartitionKey = $PartitionKey
            RowKey = $RowKey
        }
        foreach ($key in $Properties.Keys) {
            $entity[$key] = $Properties[$key]
        }
        $body = $entity | ConvertTo-Json -Compress
        
        $dateString = [DateTime]::UtcNow.ToString("R")
        $contentType = "application/json"
        
        # Build headers based on auth method
        if ($StorageAccountKey) {
            # Use SharedKey authentication
            $resource = "$TableName(PartitionKey='$([Uri]::EscapeDataString($PartitionKey))',RowKey='$([Uri]::EscapeDataString($RowKey))')"
            $authHeader = Get-SharedKeyAuthHeader -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -Method "PUT" -Resource $resource -ContentType $contentType -Date $dateString
            
            $headers = @{
                "Authorization" = $authHeader
                "Content-Type" = $contentType
                "Accept" = "application/json;odata=nometadata"
                "x-ms-version" = "2020-12-06"
                "x-ms-date" = $dateString
                "DataServiceVersion" = "3.0;NetFx"
                "Prefer" = "return-no-content"
            }
        }
        else {
            # Use OAuth authentication
            $azContext = Get-AzContext
            $tokenInfo = Get-PlainAccessToken -ResourceUrl "https://storage.azure.com" -TenantId $azContext.Tenant.Id
            $token = $tokenInfo.Token
            
            $headers = @{
                "Authorization" = "Bearer $token"
                "Content-Type" = $contentType
                "Accept" = "application/json;odata=nometadata"
                "x-ms-version" = "2020-12-06"
                "x-ms-date" = $dateString
                "DataServiceVersion" = "3.0;NetFx"
                "Prefer" = "return-no-content"
            }
        }
        
        # Use PUT for InsertOrReplace
        $entityUrl = "$tableUrl(PartitionKey='$([Uri]::EscapeDataString($PartitionKey))',RowKey='$([Uri]::EscapeDataString($RowKey))')"
        
        $response = Invoke-RestMethod -Uri $entityUrl -Method Put -Headers $headers -Body $body -StatusCodeVariable statusCode -ErrorAction Stop
        return $statusCode
    }

    # Helper function to test REST API table access (works with both auth methods)
    function Test-TableConnectionRest {
        param(
            [string]$StorageAccountName,
            [string]$TableName,
            [string]$StorageAccountKey = $null  # If provided, use SharedKey; otherwise use OAuth
        )
        try {
            $tableUrl = "https://$StorageAccountName.table.core.windows.net/$TableName()"
            $dateString = [DateTime]::UtcNow.ToString("R")
            
            if ($StorageAccountKey) {
                # Use SharedKey authentication
                $resource = "$TableName()"
                $authHeader = Get-SharedKeyAuthHeader -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -Method "GET" -Resource $resource -ContentType "" -Date $dateString
                
                $headers = @{
                    "Authorization" = $authHeader
                    "Accept" = "application/json;odata=nometadata"
                    "x-ms-version" = "2020-12-06"
                    "x-ms-date" = $dateString
                    "DataServiceVersion" = "3.0;NetFx"
                }
            }
            else {
                # Use OAuth authentication
                $azContext = Get-AzContext
                $tokenInfo = Get-PlainAccessToken -ResourceUrl "https://storage.azure.com" -TenantId $azContext.Tenant.Id
                $token = $tokenInfo.Token
                
                $headers = @{
                    "Authorization" = "Bearer $token"
                    "Accept" = "application/json;odata=nometadata"
                    "x-ms-version" = "2020-12-06"
                    "x-ms-date" = $dateString
                    "DataServiceVersion" = "3.0;NetFx"
                }
            }
            
            # Query for 1 entity to test
            $response = Invoke-RestMethod -Uri "$tableUrl`?`$top=1" -Method Get -Headers $headers -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }

    $script:storageAccountKey = $null
    
    # Try storage account keys first
    try {
        $keyResult = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $storageAccountName -ErrorAction Stop
        $script:storageAccountKey = $keyResult.Value[0]
        
        if (-not (Test-TableConnectionRest -StorageAccountName $storageAccountName -TableName $TableName -StorageAccountKey $script:storageAccountKey)) {
            $script:storageAccountKey = $null
        }
    }
    catch {
        # Storage account keys not available or disabled
    }

    # If storage account keys didn't work, try OAuth
    if (-not $script:storageAccountKey) {
        if (-not (Test-TableConnectionRest -StorageAccountName $storageAccountName -TableName $TableName)) {
            throw "Failed to connect to the storage table. Ensure your user has 'Storage Table Data Contributor' role on the storage account."
        }
    }

    # Log authentication method
    if ($script:storageAccountKey) {
        Write-Host "Using Account Keys Authentication Method"
    }
    else {
        $azContext = Get-AzContext
        Write-Host "Using EntraID Authentication Method with Account: $($azContext.Account.Id)"
    }
}

process {
    try {
        if ($null -eq $InputObject) {
            Write-Warning "Received null input object, skipping."
            return
        }

        if($TableName -eq "credentials") {
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

            # Build properties hashtable
            $properties = @{
                group = $group
                name = $name
                Credential = $value
                note = $note
            }
            # Use REST API (with storage key if available, OAuth otherwise)
            $statusCode = Write-TableEntityRest -StorageAccountName $storageAccountName -TableName $TableName -PartitionKey $tenant -RowKey "$group|$name" -Properties $properties -StorageAccountKey $script:storageAccountKey
            
            if($statusCode -ge 200 -and $statusCode -lt 300) {
                Write-Host "Successfully added credential '$name' in group '$group' for tenant '$tenant'."
            }
            else {
                Write-Warning "Failed to add credential '$name' in group '$group' for tenant '$tenant'. Status code: $statusCode"
            }
        }
        elseif ($TableName -eq "connections") {
            $hackboxuser = $InputObject.hackboxuser
            $hackboxconnection = if($InputObject.PSObject.Properties.Match('hackboxconnection')) { $InputObject.hackboxconnection } else { 'rdp' }
            if([string]::IsNullOrWhiteSpace($hackboxuser)) {
                Write-Warning "Input object must have non-empty 'hackboxuser' property. Skipping this entry."
                return
            }
            if([string]::IsNullOrWhiteSpace($hackboxconnection)) {
                $hackboxconnection = 'rdp'
            }
            if([string]::IsNullOrWhiteSpace($InputObject.user) -or [string]::IsNullOrWhiteSpace($InputObject.pass) -or [string]::IsNullOrWhiteSpace($InputObject.host)) {
                Write-Warning "Input object must have non-empty 'user', 'pass', and 'host' properties for connection entries. Skipping this entry."
                return
            }
            $properties = @{
                user = $InputObject.user
                pass = $InputObject.pass
                host = $InputObject.host
            }
            if($InputObject.PSObject.Properties.Match('port')) {
                # try to parse port as int, default to 3389 if parsing fails
                try {
                    $properties['port'] = [int]$InputObject.port
                    if($properties['port'] -le 0 -or $properties['port'] -gt 65535) {
                        Write-Warning "Port number '$($properties['port'])' is out of valid range (1-65535). Defaulting to 3389. Ignoring the invalid port value."
                        $properties.Remove('port')
                    }
                }
                catch {
                }
            }
            # Use REST API (with storage key if available, OAuth otherwise)
            $statusCode = Write-TableEntityRest -StorageAccountName $storageAccountName -TableName $TableName -PartitionKey $hackboxuser -RowKey $hackboxconnection -Properties $properties -StorageAccountKey $script:storageAccountKey
            
            if($statusCode -ge 200 -and $statusCode -lt 300) {
                Write-Host "Successfully added connection '$hackboxconnection' for user '$hackboxuser'."
            }
            else {
                Write-Warning "Failed to add connection '$hackboxconnection' for user '$hackboxuser'. Status code: $statusCode"
            }
        }
        else {
            Write-Warning "Unsupported table name '$TableName'. Skipping."
            return
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
    if ($script:publicAccessWasDisabled) {
        Write-Host "Restoring public network access to disabled state"
        Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccountName -PublicNetworkAccess Disabled -ErrorAction Stop | Out-Null
    }
}
