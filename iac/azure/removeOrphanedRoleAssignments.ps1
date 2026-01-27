<# 
.SYNOPSIS
Removes Azure role assignments that reference non-existent principals across subscriptions (and optionally resource groups). 
.DESCRIPTION
Enumerates role assignments using Az modules, verifies principal existence via Microsoft Graph, and removes entries whose principals no longer exist. Supports subscription-wide scans and an optional switch to include all resource groups. 
.PARAMETER includeResourceGroups
Switch that, when set, scans every resource group in each subscription in addition to subscription scopes. 
.EXAMPLE
.\removeOrphanedRoleAssignments.ps1 -includeResourceGroups
#>
param(
    [switch]$excludeSubscriptionScope,
    [switch]$includeManagementGroupScope,
    [switch]$includeResourceGroupScope
)



class GraphLite {
    hidden [string] $graphToken
    GraphLite() {
        $this.graphToken = ConvertFrom-SecureString -SecureString (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -AsSecureString -WarningAction Ignore).Token -AsPlainText -WarningAction Ignore
    }

    [bool] objectExists([string] $objectId) {
        # check if the object exists (ATTENTION: in case of insufficient permissions, the object will be assumed to not exist)
        try{
            $this.getObject($objectId)
            return $true
        }
        catch {
            return $false
        }
    }

    [PSCustomObject] getObject([string] $objectId) {
        # try different methods to get the object
        try{ return $this.getDirectoryObject($objectId) } catch { }
        try{ return $this.getServicePrincipal($objectId) } catch { }
        try{ return $this.getUser($objectId) } catch { }
        throw "Could not find the object with the id $objectId"
    }

    [PSCustomObject] getDirectoryObject([string] $objectId) {
        # requires (least priviledge): Directory.Read.All
        return Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$objectId" -Headers @{ "Authorization" = ( "Bearer " + $this.graphToken ) }
    }
    [PSCustomObject] getServicePrincipal([string] $objectId) {
        # requires (least priviledge): Application.Read.All
        return Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$objectId" -Headers @{ "Authorization" = ( "Bearer " + $this.graphToken ) }
    }
    [PSCustomObject] getUser([string] $objectId) {
        # requires (least priviledge): User.Read.All
        return Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/users/$objectId" -Headers @{ "Authorization" = ( "Bearer " + $this.graphToken ) }
    }
}

class GraphLiteCache  {
    hidden [GraphLite] $graphLiteObject
    hidden [hashtable] $cache
    GraphLiteCache([GraphLite] $graphLiteObject) {
        $this.graphLiteObject = $graphLiteObject
        $this.cache = @{}
    }

    [bool] objectExists([string] $objectId) {
        try {
            $this.getObject($objectId)
            return $true
        }
        catch {
            return $false
        }
    }

    [PSCustomObject] getObject([string] $objectId) {
        if($this.cache.ContainsKey($objectId)) {
            if ($null -eq $this.cache[$objectId]) {
                throw "The object with the id $objectId does not exist"
            }
            return $this.cache[$objectId]
        }
        try {
            $this.cache[$objectId] = $this.graphLiteObject.getObject($objectId)
        }
        catch {
            $this.cache[$objectId] = $null
            throw $_
        }
        return $this.cache[$objectId]
    }

    [void] clearCache() {
        $this.cache = @{}
    }
}


$graphLiteObject = [GraphLiteCache]::new( [GraphLite]::new() )


function Remove-OrphanedRoleAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    $lowerScope = $Scope.ToLower()
    # get the assignments for the resource
    foreach($assignment in Get-AzRoleAssignment -Scope $Scope) {
        #are we in current scope?
        if(-not $assignment.Scope.ToLower().StartsWith($lowerScope)) {
            continue
        }
        
        # saveguard check if the object id is still valid (in case of insufficient permissions, the object will be assumed to not exist)
        if(-not $graphLiteObject.objectExists($assignment.ObjectId)) {
            Write-Host (" - Removing role assignment: " + $assignment.RoleDefinitionName + " for " + $assignment.ObjectId)
            $result = $assignment | Remove-AzRoleAssignment -ErrorAction Continue
            Write-Host (" - Result: " + $result)
        }
    }
}



if($includeManagementGroupScope) {
    foreach($mg in (Get-AzManagementGroup)) {
        Write-Host ("Processing Management Group: " + $mg.Name)
        Remove-OrphanedRoleAssignments -Scope ($mg.Id)
    }
}

if(-not $excludeSubscriptionScope) {
    foreach($subscription in (Get-AzSubscription)) {
        Write-Host ("Processing subscription: " + $subscription.SubscriptionId + " (" + $subscription.Name + ")")
        Remove-OrphanedRoleAssignments -Scope ("/subscriptions/" + $subscription.SubscriptionId)
    }
}

if($includeResourceGroupScope) {
    $context = Get-AzContext
    foreach($subscription in (Get-AzSubscription)) {
        Set-AzContext -SubscriptionId $subscription.SubscriptionId
        foreach($rg in (Get-AzResourceGroup)) {
            Write-Host ("Processing Resource Group: " + $rg.ResourceGroupName + " in subscription: " + $subscription.SubscriptionId)
            Remove-OrphanedRoleAssignments -Scope $rg.ResourceId
        }
    }
    Set-AzContext -Context $context
}
