#Requires -PSEdition Desktop
<#
.SYNOPSIS
    Returns all the apps and service principles that currently use Azure AD Graph

.EXAMPLE
    PS C:\> .\Get-AzureADGraphApps.ps1
    Returns a collection of all the apps that have Azure AD Graph permissions assigned to them
#>

[cmdletbinding()]
param()

function Load-Module ($m) {
    Write-Progress -Activity "Loading dependencies..."
    # If module is imported say that and do nothing
    if (Get-Module | Where-Object { $_.Name -eq $m }) {
        Write-Verbose "Module $m is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $m }) {
            Import-Module $m
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object { $_.Name -eq $m }) {
                Install-Module -Name $m -Force -Scope CurrentUser
                Import-Module $m
            }
            else {

                # If module is not imported, not available and not in online gallery then abort
                Write-Host "Module $m not imported, not available and not in online gallery, exiting."
                EXIT 1
            }
        }
    }
}

function Get-MSCloudIdConsentGrantList {
    # An in-memory cache of objects by {object ID} andy by {object class, object ID} 
    $script:ObjectByObjectId = @{}
    $script:ObjectByObjectClassId = @{}

    # Function to add an object to the cache
    function CacheObject($Object) {
        if ($Object) {
            if (-not $script:ObjectByObjectClassId.ContainsKey($Object.ObjectType)) {
                $script:ObjectByObjectClassId[$Object.ObjectType] = @{}
            }
            $script:ObjectByObjectClassId[$Object.ObjectType][$Object.ObjectId] = $Object
            $script:ObjectByObjectId[$Object.ObjectId] = $Object
        }
    }

    # Function to retrieve an object from the cache (if it's there), or from Azure AD (if not).
    function GetObjectByObjectId($ObjectId) {
        if (-not $script:ObjectByObjectId.ContainsKey($ObjectId)) {
            Write-Verbose ("Querying Azure AD for object '{0}'" -f $ObjectId)
            try {
                $object = Get-AzureADObjectByObjectId -ObjectId $ObjectId
                CacheObject -Object $object
            }
            catch { 
                Write-Verbose "Object not found."
            }
        }
        return $script:ObjectByObjectId[$ObjectId]
    }
   
    # Get all ServicePrincipal objects and add to the cache
    Write-Progress -Activity "Retrieving Service Principal objects. Please wait..."
    $servicePrincipals = Get-AzureADServicePrincipal -All $true 
    $tenantId = (Get-AzureADTenantDetail).ObjectId

    $Oauth2PermGrants = @()

    $count = 0
    foreach ($sp in $servicePrincipals) {
        CacheObject -Object $sp
        $spPermGrants = Get-AzureADServicePrincipalOAuth2PermissionGrant -ObjectId $sp.ObjectId -All $true
        $Oauth2PermGrants += $spPermGrants
        $count++
        Write-Progress -Activity "Getting Service Principal Delegate Permissions..." -Status "$count of $($servicePrincipals.Count) - $($sp.DisplayName)" -percentComplete (($count / $servicePrincipals.Count) * 100)

        if ($sp.AppId -eq "00000002-0000-0000-c000-000000000000") {
            #Azure Active Directory Graph API app
            $aadGraphSp = $sp
        }
    }  

    # Get all existing OAuth2 permission grants, get the client, resource and scope details
    Write-Progress -Activity "Checking Delegated Permission Grants..."
    foreach ($grant in $Oauth2PermGrants) {
        if ($grant.ResourceId -eq $aadGraphSp.ObjectId -and $grant.Scope) {
            $grant.Scope.Split(" ") | Where-Object { $_ } | ForEach-Object {
                $scope = $_
                $client = GetObjectByObjectId -ObjectId $grant.ClientId

                $isAppProxyApp = $false
                if ($client.Tags -contains "WindowsAzureActiveDirectoryOnPremApp") {
                    $isAppProxyApp = $true
                }
                if(-not $isAppProxyApp)
                {
                    $ownerUPN = (Get-AzureADServicePrincipalOwner -ObjectId $client.ObjectId -Top 1).UserPrincipalName
                    Write-Progress -Activity "Checking Delegate Permissions - $($client.DisplayName)"
    
                    # Determine if the object comes from the Microsoft Services tenant, and flag it if true
                    $MicrosoftRegisteredClientApp = @()
                    if ($client.AppOwnerTenantId -eq "f8cdef31-a31e-4b4a-93e4-5f571e91255a" -or $client.AppOwnerTenantId -eq "72f988bf-86f1-41af-91ab-2d7cd011db47") {
                        $MicrosoftRegisteredClientApp = $true
                    }
                    else {
                        $MicrosoftRegisteredClientApp = $false
                    }
            
                    $isTenantOwnedApp = $false
                    if ($client.AppOwnerTenantId -eq $tenantId) {
                        $isTenantOwnedApp = $true
                    }

                    $resource = GetObjectByObjectId -ObjectId $grant.ResourceId

                    if ($grant.ConsentType -eq "AllPrincipals") {
                        $simplifiedgranttype = "Delegated-AllPrincipals"
                    }
                    elseif ($grant.ConsentType -eq "Principal") {
                        $simplifiedgranttype = "Delegated-Principal"
                    }
                    New-Object PSObject -Property ([ordered]@{
                        "ObjectId"       = $grant.ClientId
                        "DisplayName"    = $client.DisplayName
                        "ApplicationId"  = $client.AppId
                        "PermissionType" = $simplifiedgranttype
                        "Resource"       = $resource.DisplayName
                        "Permission"     = $scope
                        "MicrosoftApp"   = $MicrosoftRegisteredClientApp
                        "Owner"          = $ownerUPN
                        "TenantOwned"    = $isTenantOwnedApp
                    })
                }
            }
        }
    }
    
    # Iterate over all ServicePrincipal objects and get app permissions
    Write-Progress -Activity "Getting Application Permission Grants..."
    $script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator() | ForEach-Object {
        $sp = $_.Value
        Write-Progress -Activity "Checking Application Permissions - $($sp.DisplayName)"

        Get-AzureADServiceAppRoleAssignedTo -ObjectId $sp.ObjectId  -All $true `
        | Where-Object { $_.PrincipalType -eq "ServicePrincipal" -and $_.ResourceId -eq $aadGraphSp.ObjectId } | ForEach-Object {
            $assignment = $_
            
            $client = GetObjectByObjectId -ObjectId $assignment.PrincipalId
            
            $isAppProxyApp = $false
            if ($client.Tags -contains "WindowsAzureActiveDirectoryOnPremApp") {
                $isAppProxyApp = $true
            }
            if(-not $isAppProxyApp)
            {
                $ownerUPN = (Get-AzureADServicePrincipalOwner -ObjectId $client.ObjectId -Top 1).UserPrincipalName
                # Determine if the object comes from the Microsoft Services tenant, and flag it if true
                $MicrosoftRegisteredClientApp = @()
                if ($client.AppOwnerTenantId -eq "f8cdef31-a31e-4b4a-93e4-5f571e91255a" -or $client.AppOwnerTenantId -eq "72f988bf-86f1-41af-91ab-2d7cd011db47") {
                    $MicrosoftRegisteredClientApp = $true
                }
                else {
                    $MicrosoftRegisteredClientApp = $false
                }

                $isTenantOwnedApp = $false
                if ($client.AppOwnerTenantId -eq $tenantId) {
                    $isTenantOwnedApp = $true
                }
                $resource = GetObjectByObjectId -ObjectId $assignment.ResourceId            
                $appRole = $resource.AppRoles | Where-Object { $_.Id -eq $assignment.Id }

                New-Object PSObject -Property ([ordered]@{
                        "ObjectId"       = $assignment.PrincipalId
                        "DisplayName"    = $client.DisplayName
                        "ApplicationId"  = $client.AppId
                        "PermissionType" = "Application"
                        "Resource"       = $resource.DisplayName
                        "Permission"     = $appRole.Value
                        "MicrosoftApp"   = $MicrosoftRegisteredClientApp
                        "Owner"          = $ownerUPN
                        "TenantOwned"    = $isTenantOwnedApp
                    })
            }
        }
    }
}

Load-Module "AzureAD"

Connect-AzureAD | Out-Null

Get-MSCloudIdConsentGrantList
