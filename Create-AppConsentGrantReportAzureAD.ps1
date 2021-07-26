<# 
.SYNOPSIS
    Lists and categorizes risk for delegated permissions (OAuth2PermissionGrants) and application permissions (AppRoleAssignments).

.PARAMETER AdminUPN
    The user principal name of an administrator in your tenant with at least Global Reader permissions.

.PARAMETER Path
    The path to output results to in Excel format.

.EXAMPLE
    PS C:\> .\Create-AppConsentGrantReport.ps1 -AdminUPN globalreader@contoso.onmicrosoft.com -Path .\output.xlsx
    Generates an Excel report and pivot chart that shows all consents and emphasizes risky consents.
#>

[CmdletBinding()]
param
(
    # Interactive sign in using, use this option normally
    [Parameter(
        Mandatory=$true,
        ParameterSetName="Interactive"
    )]
    [string]
    $AdminUPN,

    # For use when doing non-interactive sign in or script testing
    [Parameter(
        Mandatory=$true,
        ParameterSetName="NonInteractive"
    )]
    [string]
    $PasswordFilePath,

    [Parameter(
        Mandatory=$true,
        ParameterSetName="NonInteractive"
    )]
    [string]
    $Username,

    # Output file location
    [Parameter(Mandatory=$true)]
    [string]
    $Path
)

function Start-MSCloudIdSession
{
    if ($AdminUPN) {
        Connect-AzureAD -AccountId $AdminUPN
    }
    elseif ($PasswordFilePath) {
        $password = Get-Content $PasswordFilePath | ConvertTo-SecureString
        $credential = New-Object System.Management.Automation.PsCredential($Username, $password)
        Connect-AzureAD -Credential $Credential
    }
}

function Load-Module ($m) {

    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $m}) {
        write-host "Module $m is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
            Import-Module $m
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                Install-Module -Name $m -Force -Scope CurrentUser
                Import-Module $m
            }
            else {

                # If module is not imported, not available and not in online gallery then abort
                write-host "Module $m not imported, not available and not in online gallery, exiting."
                EXIT 1
            }
        }
    }
}

Function Get-MSCloudIdConsentGrantList
{
    [CmdletBinding()]
    param(
        [int] $PrecacheSize = 999
    )
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
            } catch { 
                Write-Verbose "Object not found."
            }
        }
        return $script:ObjectByObjectId[$ObjectId]
    }
   
    # Get all ServicePrincipal objects and add to the cache
    Write-Verbose "Retrieving ServicePrincipal objects..."
    $servicePrincipals = Get-AzureADServicePrincipal -All $true 

    #there is a limitation on how Azure AD Graph retrieves the list of OAuth2PermissionGrants
    #we have to traverse all service principals and gather them separately.
    # Originally, we could have done this 
    # $Oauth2PermGrants = Get-AzureADOAuth2PermissionGrant -All $true 
    
    $Oauth2PermGrants = @()

    $count = 0
    foreach ($sp in $servicePrincipals)
    {
        CacheObject -Object $sp
        $spPermGrants = Get-AzureADServicePrincipalOAuth2PermissionGrant -ObjectId $sp.ObjectId -All $true
        $Oauth2PermGrants += $spPermGrants
        $count++
        Write-Progress -activity "Caching Objects from Azure AD . . ." -status "Cached: $count of $($servicePrincipals.Count)" -percentComplete (($count / $servicePrincipals.Count)  * 100)
    }  

    # Get one page of User objects and add to the cache
    Write-Verbose "Retrieving User objects..."
    Get-AzureADUser -Top $PrecacheSize | ForEach-Object { CacheObject -Object $_ }

    # Get all existing OAuth2 permission grants, get the client, resource and scope details
    Write-Progress -Activity "Processing Delegated Permission Grants..."
    foreach ($grant in $Oauth2PermGrants)
    {
        if ($grant.Scope) 
        {
            $grant.Scope.Split(" ") | Where-Object { $_ } | ForEach-Object {               
                $scope = $_
                $client = GetObjectByObjectId -ObjectId $grant.ClientId

                # Determine if the object comes from the Microsoft Services tenant, and flag it if true
                $MicrosoftRegisteredClientApp = @()
                if ($client.AppOwnerTenantId -eq "f8cdef31-a31e-4b4a-93e4-5f571e91255a" -or $client.AppOwnerTenantId -eq "72f988bf-86f1-41af-91ab-2d7cd011db47") {
                    $MicrosoftRegisteredClientApp = $true
                } else {
                    $MicrosoftRegisteredClientApp = $false
                }

                $resource = GetObjectByObjectId -ObjectId $grant.ResourceId
                $principalDisplayName = ""
                if ($grant.PrincipalId) {
                    $principal = GetObjectByObjectId -ObjectId $grant.PrincipalId
                    $principalDisplayName = $principal.DisplayName
                }

                if ($grant.ConsentType -eq "AllPrincipals") {
                    $simplifiedgranttype = "Delegated-AllPrincipals"
                } elseif ($grant.ConsentType -eq "Principal") {
                    $simplifiedgranttype = "Delegated-Principal"
                }
                
                if ($grant.ResourceId -eq "5ebbaf97-17d8-44b1-950e-04561f9b2509") {

                    New-Object PSObject -Property ([ordered]@{
                        "PermissionType" = $simplifiedgranttype
                        "ConsentTypeFilter" = $simplifiedgranttype
                        "ClientObjectId" = $grant.ClientId
                        "ClientDisplayName" = $client.DisplayName
                        "ResourceObjectId" = $grant.ResourceId
                        "ResourceObjectIdFilter" = $grant.ResourceId
                        "ResourceDisplayName" = $resource.DisplayName
                        "ResourceDisplayNameFilter" = $resource.DisplayName
                        "Permission" = $scope
                        "PermissionFilter" = $scope
                        "PrincipalObjectId" = $grant.PrincipalId
                        "PrincipalDisplayName" = $principalDisplayName
                        "MicrosoftRegisteredClientApp" = $MicrosoftRegisteredClientApp
                    })
                }
            }
        }
    }
    
    # Iterate over all ServicePrincipal objects and get app permissions
    Write-Progress -Activity "Processing Application Permission Grants..."
    $script:ObjectByObjectClassId['ServicePrincipal'].GetEnumerator() | ForEach-Object {
        $sp = $_.Value

        Get-AzureADServiceAppRoleAssignedTo -ObjectId $sp.ObjectId  -All $true `
        | Where-Object { $_.PrincipalType -eq "ServicePrincipal" } | ForEach-Object {
            $assignment = $_
            
            $client = GetObjectByObjectId -ObjectId $assignment.PrincipalId

            # Determine if the object comes from the Microsoft Services tenant, and flag it if true
            $MicrosoftRegisteredClientApp = @()
            if ($client.AppOwnerTenantId -eq "f8cdef31-a31e-4b4a-93e4-5f571e91255a" -or $client.AppOwnerTenantId -eq "72f988bf-86f1-41af-91ab-2d7cd011db47") {
                $MicrosoftRegisteredClientApp = $true
            } else {
                $MicrosoftRegisteredClientApp = $false
            }

            $resource = GetObjectByObjectId -ObjectId $assignment.ResourceId            
            $appRole = $resource.AppRoles | Where-Object { $_.Id -eq $assignment.Id }

            if ($assignment.ResourceId -eq "5ebbaf97-17d8-44b1-950e-04561f9b2509") {

                New-Object PSObject -Property ([ordered]@{
                    "PermissionType" = "Application"
                    "ClientObjectId" = $assignment.PrincipalId
                    "ClientDisplayName" = $client.DisplayName
                    "ResourceObjectId" = $assignment.ResourceId
                    "ResourceObjectIdFilter" = $grant.ResourceId
                    "ResourceDisplayName" = $resource.DisplayName
                    "ResourceDisplayNameFilter" = $resource.DisplayName
                    "Permission" = $appRole.Value
                    "PermissionFilter" = $appRole.Value
                    "ConsentTypeFilter" = "Application"
                    "MicrosoftRegisteredClientApp" = $MicrosoftRegisteredClientApp

                })
            }
        }
    }
}

# Create hash table of permissions and permissions risk
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/mepples21/azureadconfigassessment/master/permissiontable.csv' -OutFile .\permissiontable.csv
$permstable = Import-Csv .\permissiontable.csv -Delimiter ','

Load-Module "AzureAD"
Load-Module "ImportExcel"

Start-MSCloudIdSession -AdminUPN $AdminUPN

$data = Get-MSCloudIdConsentGrantList 

# Process Risk for gathered data
$count = 0
$data | ForEach-Object {

    $count++
    Write-Progress -activity "Processing risk for each permission . . ." -status "Processed: $count of $($data.Count)" -percentComplete (($count / $data.Count)  * 100)

    $scope = $_.Permission
    if ($_.PermissionType -eq "Delegated-AllPrincipals" -or "Delegated-Principal") {
        $type = "Delegated"
    } elseif ($_.PermissionType -eq "Application") {
        $type = "Application"
    }

    # Check permission table for an exact match
    $risk = $null
    $scoperoot = @()
    $scoperoot = $scope.Split(".")[0]
    
    $test = ($permstable | where {$_.Permission -eq "$scoperoot" -and $_.Type -eq $type}).Risk # checking if there is a matching root in the CSV
    $risk = ($permstable | where {$_.Permission -eq "$scope" -and $_.Type -eq $type}).Risk # Checking for an exact match

    # Search for matching root level permission if there was no exact match
    if (!$risk -and $test) {
        # No exact match, but there is a root match
        $risk = ($permstable | where {$_.Permission -eq "$scoperoot" -and $_.Type -eq $type}).Risk
    } elseif (!$risk -and !$test -and $type -eq "Application" -and $scope -like "*Write*") {
        # Application permissions without exact or root matches with write scope
        $risk = "High"
    } elseif (!$risk -and !$test -and $type -eq "Application" -and $scope -notlike "*Write*") {
        # Application permissions without exact or root matches without write scope
        $risk = "Medium"
    } elseif ($risk) {
        
    } else {
        # Any permissions without a match, should be primarily Delegated permissions
        $risk = "Unranked"
    }

    # Add the risk to the current object
    Add-Member -InputObject $_ -MemberType NoteProperty -Name Risk -Value $risk
    Add-Member -InputObject $_ -MemberType NoteProperty -Name RiskFilter -Value $risk
    Add-Member -InputObject $_ -MemberType NoteProperty -Name Reason -Value $reason
}

# Delete the existing output file if it already exists
$OutputFileExists = Test-Path $Path
if ($OutputFileExists -eq $true) {
    Get-ChildItem $Path | Remove-Item -Force
}

$count = 0
$highriskobjects = $data | Where-Object {$_.Risk -eq "High"}
$highriskobjects | ForEach-Object {
    $userAssignmentRequired = @()
    $userAssignments = @()
    $userAssignmentsCount = @()
    $userAssignmentRequired = Get-AzureADServicePrincipal -ObjectId $_.ClientObjectId

    if ($userAssignmentRequired.AppRoleAssignmentRequired -eq $true) {
        $userAssignments = Get-AzureADServiceAppRoleAssignment -ObjectId $_.ClientObjectId -All $true
        $userAssignmentsCount = $userAssignments.count
        Add-Member -InputObject $_ -MemberType NoteProperty -Name UsersAssignedCount -Value $userAssignmentsCount    
    } elseif ($userAssignmentRequired.AppRoleAssignmentRequired -eq $false) {
        $userAssignmentsCount = "AllUsers"
        Add-Member -InputObject $_ -MemberType NoteProperty -Name UsersAssignedCount -Value $userAssignmentsCount
    }

    $count++
    #Write-Progress -activity "Counting users assigned to high risk apps . . ." -status "Apps Counted: $count of $($highriskobjects.Count)" -percentComplete (($count / $highriskobjects.Count)  * 100)
}
$highriskusers = $highriskobjects | Where-Object {$_.PrincipalObjectId -ne $null} | Select-Object PrincipalDisplayName,Risk | Sort-Object PrincipalDisplayName -Unique
$highriskapps = $highriskobjects | Select-Object ClientDisplayName,Risk,UsersAssignedCount,MicrosoftRegisteredClientApp | Sort-Object ClientDisplayName -Unique | Sort-Object UsersAssignedCount -Descending

# Pivot table by user
$pt = New-PivotTableDefinition -SourceWorkSheet ConsentGrantData `
        -PivotTableName "PermissionsByUser" `
        -PivotFilter RiskFilter,PermissionFilter,ResourceDisplayNameFilter,ConsentTypeFilter,ClientDisplayName,MicrosoftRegisteredClientApp `
        -PivotRows PrincipalDisplayName `
        -PivotColumns Risk,PermissionType `
        -PivotData @{Permission='Count'} `
        -IncludePivotChart `
        -ChartType ColumnStacked `
        -ChartHeight 800 `
        -ChartWidth 1200 `
        -ChartRow 4 `
        -ChartColumn 14

# Pivot table by resource
$pt += New-PivotTableDefinition -SourceWorkSheet ConsentGrantData `
        -PivotTableName "PermissionsByResource" `
        -PivotFilter RiskFilter,ResourceDisplayNameFilter,ConsentTypeFilter,PrincipalDisplayName,MicrosoftRegisteredClientApp `
        -PivotRows ResourceDisplayName,PermissionFilter `
        -PivotColumns Risk,PermissionType `
        -PivotData @{Permission='Count'} `
        -IncludePivotChart `
        -ChartType ColumnStacked `
        -ChartHeight 800 `
        -ChartWidth 1200 `
        -ChartRow 4 `
        -ChartColumn 14

# Pivot table by risk rating
$pt += New-PivotTableDefinition -SourceWorkSheet ConsentGrantData `
        -PivotTableName "PermissionsByRiskRating" `
        -PivotFilter RiskFilter,PermissionFilter,ResourceDisplayNameFilter,ConsentTypeFilter,PrincipalDisplayName,MicrosoftRegisteredClientApp `
        -PivotRows Risk,ResourceDisplayName `
        -PivotColumns PermissionType `
        -PivotData @{Permission='Count'} `
        -IncludePivotChart `
        -ChartType ColumnStacked `
        -ChartHeight 800 `
        -ChartWidth 1200 `
        -ChartRow 4 `
        -ChartColumn 5

$excel = $data | Export-Excel -Path $Path -WorksheetName ConsentGrantData `
        -PivotTableDefinition $pt `
        -AutoSize `
        -Activate `
        -HideSheet "None" `
        -UnHideSheet "PermissionsByRiskRating" `
        -PassThru

# Create temporary Excel file and add High Risk Users sheet
$xlTempFile = "$env:TEMP\ImportExcelTempFile.xlsx"
Remove-Item $xlTempFile -ErrorAction Ignore
$exceltemp = $highriskusers | Export-Excel $xlTempFile -PassThru
Add-Worksheet -ExcelPackage $excel -WorksheetName HighRiskUsers -CopySource $exceltemp.Workbook.Worksheets["Sheet1"]

# Create temporary Excel file and add High Risk Apps sheet
$xlTempFile = "$env:TEMP\ImportExcelTempFile.xlsx"
Remove-Item $xlTempFile -ErrorAction Ignore
$exceltemp = $highriskapps | Export-Excel $xlTempFile -PassThru
Add-Worksheet -ExcelPackage $excel -WorksheetName HighRiskApps -CopySource $exceltemp.Workbook.Worksheets["Sheet1"] -Activate

$sheet = $excel.Workbook.Worksheets["ConsentGrantData"]
Add-ConditionalFormatting -Worksheet $sheet -Range "A1:N1048576" -RuleType Equal -ConditionValue "High" -ForeGroundColor White -BackgroundColor Red -Bold -Underline
Add-ConditionalFormatting -Worksheet $sheet -Range "A1:N1048576" -RuleType Equal -ConditionValue "Medium" -ForeGroundColor Black -BackgroundColor Orange -Bold -Underline
Add-ConditionalFormatting -Worksheet $sheet -Range "A1:N1048576" -RuleType Equal -ConditionValue "Low" -ForeGroundColor Black -BackgroundColor Yellow -Bold -Underline

$sheet = $excel.Workbook.Worksheets["HighRiskUsers"]
Add-ConditionalFormatting -Worksheet $sheet -Range "B1:B1048576" -RuleType Equal -ConditionValue "High" -ForeGroundColor White -BackgroundColor Red -Bold -Underline
Set-ExcelRange -Worksheet $sheet -Range A1:C1048576 -AutoSize

$sheet = $excel.Workbook.Worksheets["HighRiskApps"]
Add-ConditionalFormatting -Worksheet $sheet -Range "B1:B1048576" -RuleType Equal -ConditionValue "High" -ForeGroundColor White -BackgroundColor Red -Bold -Underline
Set-ExcelRange -Worksheet $sheet -Range A1:C1048576 -AutoSize

Export-Excel -ExcelPackage $excel -Show