function Get-ExpiringSpCredential {
    <#
    .SYNOPSIS
        Gets service principals with expiring or expired credentials.

    .DESCRIPTION
        Queries Entra ID for service principals (Enterprise Applications) that have
        credentials (secrets or certificates) expiring within the specified threshold
        or that have already expired. This includes SAML signing certificates.

    .PARAMETER DaysUntilExpiration
        The number of days to look ahead for expiring credentials.
        Credentials expiring within this many days will be included.
        Default is 30 days.

    .PARAMETER IncludeExpired
        Include credentials that have already expired.
        Default is $true.

    .PARAMETER IncludeOwners
        Include owner information for each service principal.
        Default is $true. Set to $false for faster execution if owner info is not needed.

    .PARAMETER ServicePrincipalId
        Optional. Specify one or more service principal Object IDs to query.
        If not specified, all service principals are queried.

    .PARAMETER ExcludeMicrosoft
        Exclude Microsoft first-party service principals.
        Default is $false.

    .EXAMPLE
        Get-ExpiringSpCredential

        Gets all service principals with credentials expiring in the next 30 days or already expired.

    .EXAMPLE
        Get-ExpiringSpCredential -DaysUntilExpiration 90 -IncludeExpired $false

        Gets service principals with credentials expiring in the next 90 days, excluding already expired.

    .EXAMPLE
        Get-ExpiringSpCredential -ExcludeMicrosoft $true

        Gets expiring credentials excluding Microsoft first-party applications.

    .OUTPUTS
        PSCustomObject with properties:
        - ServicePrincipalName, ApplicationId, ObjectId, ObjectType
        - CredentialType, CredentialName, KeyId
        - StartDate, EndDate, DaysRemaining, Status
        - CertificateType, CertificateUsage (for certificates)
        - Owner, OwnerIds

    .NOTES
        Requires Microsoft.Graph.Applications module and Application.Read.All permission.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(0, 3650)]
        [Int32]$DaysUntilExpiration = 30,

        [Parameter()]
        [Bool]$IncludeExpired = $true,

        [Parameter()]
        [Bool]$IncludeOwners = $true,

        [Parameter()]
        [String[]]$ServicePrincipalId,

        [Parameter()]
        [Bool]$ExcludeMicrosoft = $false
    )

    begin {
        Write-Verbose -Message "Starting Get-ExpiringSpCredential with threshold of $DaysUntilExpiration days"

        # Initialize result collection using List for O(n) performance
        $results = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'
        $now = Get-Date

        # Microsoft tenant ID for filtering first-party apps
        $microsoftTenantId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
    }

    process {
        try {
            # Get service principals
            if ($ServicePrincipalId) {
                Write-Verbose -Message "Querying $($ServicePrincipalId.Count) specific service principal(s)"
                $servicePrincipals = foreach ($spId in $ServicePrincipalId) {
                    Get-MgServicePrincipal -ServicePrincipalId $spId -ErrorAction Stop
                }
            }
            else {
                Write-Verbose -Message 'Querying all service principals'
                $servicePrincipals = Get-MgServicePrincipal -All -ErrorAction Stop
            }

            $spCount = @($servicePrincipals).Count
            Write-Verbose -Message "Found $spCount service principal(s) to process"

            $processedCount = 0
            $skippedMicrosoft = 0

            foreach ($sp in $servicePrincipals) {
                $processedCount++

                # Skip Microsoft first-party apps if requested
                if ($ExcludeMicrosoft -and $sp.AppOwnerOrganizationId -eq $microsoftTenantId) {
                    $skippedMicrosoft++
                    Write-Verbose -Message "Skipping Microsoft app: $($sp.DisplayName)"
                    continue
                }

                Write-Verbose -Message "Processing service principal $processedCount of $spCount : $($sp.DisplayName)"

                # Get owner information once per service principal (not per credential)
                $ownerInfo = $null
                if ($IncludeOwners) {
                    try {
                        $owners = Get-MgServicePrincipalOwner -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue
                        $ownerInfo = Resolve-OwnerInfo -Owners $owners -ObjectId $sp.Id
                    }
                    catch {
                        Write-Warning -Message "Failed to get owners for service principal $($sp.DisplayName): $PSItem"
                        $ownerInfo = [PSCustomObject]@{
                            OwnerDisplayNames = '<<Error>>'
                            OwnerUpns         = ''
                            OwnerIds          = ''
                            OwnerCount        = 0
                        }
                    }
                }

                # Process password credentials (secrets)
                foreach ($secret in $sp.PasswordCredentials) {
                    $credStatus = Get-CredentialStatus -EndDateTime $secret.EndDateTime -ReferenceDate $now

                    # Filter based on parameters
                    $includeThis = $false
                    if ($credStatus.Status -eq 'Expired' -and $IncludeExpired) {
                        $includeThis = $true
                    }
                    elseif ($credStatus.Status -ne 'Expired' -and $credStatus.DaysRemaining -le $DaysUntilExpiration) {
                        $includeThis = $true
                    }

                    if ($includeThis) {
                        $credentialResult = [PSCustomObject]@{
                            ServicePrincipalName = $sp.DisplayName
                            ApplicationId        = $sp.AppId
                            ObjectId             = $sp.Id
                            ObjectType           = 'ServicePrincipal'
                            ServicePrincipalType = $sp.ServicePrincipalType
                            CredentialType       = 'Secret'
                            CredentialName       = $secret.DisplayName
                            KeyId                = $secret.KeyId
                            Hint                 = $secret.Hint
                            StartDate            = $secret.StartDateTime
                            EndDate              = $secret.EndDateTime
                            DaysRemaining        = $credStatus.DaysRemaining
                            DaysPastExpiration   = $credStatus.DaysPastExpiration
                            Status               = $credStatus.Status
                            CertificateType      = $null
                            CertificateUsage     = $null
                            Owner                = if ($ownerInfo) { $ownerInfo.OwnerDisplayNames } else { '' }
                            OwnerUpns            = if ($ownerInfo) { $ownerInfo.OwnerUpns } else { '' }
                            OwnerIds             = if ($ownerInfo) { $ownerInfo.OwnerIds } else { '' }
                        }
                        $results.Add($credentialResult)
                    }
                }

                # Process key credentials (certificates)
                foreach ($cert in $sp.KeyCredentials) {
                    $credStatus = Get-CredentialStatus -EndDateTime $cert.EndDateTime -ReferenceDate $now

                    # Filter based on parameters
                    $includeThis = $false
                    if ($credStatus.Status -eq 'Expired' -and $IncludeExpired) {
                        $includeThis = $true
                    }
                    elseif ($credStatus.Status -ne 'Expired' -and $credStatus.DaysRemaining -le $DaysUntilExpiration) {
                        $includeThis = $true
                    }

                    if ($includeThis) {
                        # Determine if this is a SAML signing cert
                        $certType = $cert.Type
                        $certUsage = $cert.Usage
                        $isSamlSigningCert = ($certType -eq 'AsymmetricX509Cert' -and $certUsage -eq 'Sign')

                        $credentialResult = [PSCustomObject]@{
                            ServicePrincipalName = $sp.DisplayName
                            ApplicationId        = $sp.AppId
                            ObjectId             = $sp.Id
                            ObjectType           = 'ServicePrincipal'
                            ServicePrincipalType = $sp.ServicePrincipalType
                            CredentialType       = if ($isSamlSigningCert) { 'SAMLSigningCertificate' } else { 'Certificate' }
                            CredentialName       = $cert.DisplayName
                            KeyId                = $cert.KeyId
                            Hint                 = $null
                            StartDate            = $cert.StartDateTime
                            EndDate              = $cert.EndDateTime
                            DaysRemaining        = $credStatus.DaysRemaining
                            DaysPastExpiration   = $credStatus.DaysPastExpiration
                            Status               = $credStatus.Status
                            CertificateType      = $certType
                            CertificateUsage     = $certUsage
                            Owner                = if ($ownerInfo) { $ownerInfo.OwnerDisplayNames } else { '' }
                            OwnerUpns            = if ($ownerInfo) { $ownerInfo.OwnerUpns } else { '' }
                            OwnerIds             = if ($ownerInfo) { $ownerInfo.OwnerIds } else { '' }
                        }
                        $results.Add($credentialResult)
                    }
                }
            }

            if ($ExcludeMicrosoft) {
                Write-Verbose -Message "Skipped $skippedMicrosoft Microsoft first-party service principal(s)"
            }
        }
        catch {
            Write-Error -Message "Failed to query service principals: $PSItem"
            throw
        }
    }

    end {
        Write-Verbose -Message "Found $($results.Count) credential(s) matching criteria"
        $results
    }
}
