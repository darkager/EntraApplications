function Resolve-OwnerInfo {
    <#
    .SYNOPSIS
        Resolves owner information from directory objects.

    .DESCRIPTION
        Internal helper function that extracts owner details from the
        directoryObject collection returned by Get-MgApplicationOwner
        or Get-MgServicePrincipalOwner. Uses module-level caching to
        avoid redundant processing.

    .PARAMETER Owners
        Collection of directoryObject owners from Graph API.

    .PARAMETER ObjectId
        The object ID of the application or service principal (for cache key).

    .OUTPUTS
        PSCustomObject with OwnerDisplayNames, OwnerUpns, and OwnerIds properties.

    .NOTES
        Internal function - not exported.
        Uses $script:OwnerCache for caching resolved owners.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [AllowNull()]
        [Object[]]$Owners,

        [Parameter(Mandatory)]
        [String]$ObjectId
    )

    # Check cache first
    if ($script:OwnerCache.ContainsKey($ObjectId)) {
        Write-Verbose -Message "Owner cache hit for $ObjectId"
        return $script:OwnerCache[$ObjectId]
    }

    # Process owners
    $ownerDisplayNames = New-Object -TypeName 'System.Collections.Generic.List[String]'
    $ownerUpns = New-Object -TypeName 'System.Collections.Generic.List[String]'
    $ownerIds = New-Object -TypeName 'System.Collections.Generic.List[String]'

    if ($null -eq $Owners -or $Owners.Count -eq 0) {
        $result = [PSCustomObject]@{
            OwnerDisplayNames = '<<No Owner>>'
            OwnerUpns         = ''
            OwnerIds          = ''
            OwnerCount        = 0
        }
        $script:OwnerCache.Add($ObjectId, $result)
        return $result
    }

    foreach ($owner in $Owners) {
        # Object ID is directly available
        if ($owner.Id) {
            $ownerIds.Add($owner.Id)
        }

        # Check AdditionalProperties for user/SP details
        $additionalProps = $owner.AdditionalProperties

        if ($additionalProps) {
            # For users - get UPN
            $upn = $additionalProps['userPrincipalName']
            if ($upn) {
                $ownerUpns.Add($upn)
                $ownerDisplayNames.Add($upn)
            }
            else {
                # For service principals or users without UPN
                $displayName = $additionalProps['displayName']
                if ($displayName) {
                    # Check if this is a service principal (no UPN means it's likely an SP)
                    $odataType = $additionalProps['@odata.type']
                    if ($odataType -eq '#microsoft.graph.servicePrincipal') {
                        $ownerDisplayNames.Add("$displayName (ServicePrincipal)")
                    }
                    else {
                        $ownerDisplayNames.Add($displayName)
                    }
                }
            }
        }
    }

    # Build result
    $result = [PSCustomObject]@{
        OwnerDisplayNames = if ($ownerDisplayNames.Count -gt 0) { $ownerDisplayNames -join '; ' } else { '<<No Owner>>' }
        OwnerUpns         = $ownerUpns -join '; '
        OwnerIds          = $ownerIds -join '; '
        OwnerCount        = $Owners.Count
    }

    # Cache the result
    $script:OwnerCache.Add($ObjectId, $result)
    Write-Verbose -Message "Cached owner info for $ObjectId"

    $result
}
