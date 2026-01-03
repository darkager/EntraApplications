function Get-ExpiringAppCredential {
    <#
    .SYNOPSIS
        Gets applications with expiring or expired credentials.

    .DESCRIPTION
        Queries Entra ID for application registrations (App Registrations) that have
        credentials (secrets or certificates) expiring within the specified threshold
        or that have already expired.

    .PARAMETER DaysUntilExpiration
        The number of days to look ahead for expiring credentials.
        Credentials expiring within this many days will be included.
        Default is 30 days.

    .PARAMETER IncludeExpired
        Include credentials that have already expired.
        Default is $true.

    .PARAMETER IncludeOwners
        Include owner information for each application.
        Default is $true. Set to $false for faster execution if owner info is not needed.

    .PARAMETER ApplicationId
        Optional. Specify one or more application Object IDs to query.
        If not specified, all applications are queried.

    .EXAMPLE
        Get-ExpiringAppCredential

        Gets all applications with credentials expiring in the next 30 days or already expired.

    .EXAMPLE
        Get-ExpiringAppCredential -DaysUntilExpiration 90 -IncludeExpired $false

        Gets applications with credentials expiring in the next 90 days, excluding already expired.

    .EXAMPLE
        Get-ExpiringAppCredential -ApplicationId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

        Gets credential information for a specific application.

    .OUTPUTS
        PSCustomObject with properties:
        - DisplayName, ApplicationId, ObjectId, ObjectType
        - CredentialType, CredentialName, KeyId
        - StartDate, EndDate, DaysRemaining, Status
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
        [String[]]$ApplicationId,

        [Parameter(DontShow)]
        [Int32]$ProgressParentId = -1
    )

    begin {
        Write-Verbose -Message "Starting Get-ExpiringAppCredential with threshold of $DaysUntilExpiration days"

        # Initialize result collection using List for O(n) performance
        $results = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'
        $now = Get-Date
    }

    process {
        try {
            # Get applications
            if ($ApplicationId) {
                Write-Verbose -Message "Querying $($ApplicationId.Count) specific application(s)"
                $applications = foreach ($appId in $ApplicationId) {
                    Get-MgApplication -ApplicationId $appId -ErrorAction Stop
                }
            }
            else {
                Write-Verbose -Message 'Querying all applications'
                $applications = Get-MgApplication -All -ErrorAction Stop
            }

            $appCount = @($applications).Count
            Write-Verbose -Message "Found $appCount application(s) to process"

            $processedCount = 0
            $progressId = if ($ProgressParentId -ge 0) { $ProgressParentId + 1 } else { 1 }
            foreach ($app in $applications) {
                $processedCount++

                # Show progress
                $percentComplete = [Math]::Round(($processedCount / $appCount) * 100)
                $progressParams = @{
                    Id              = $progressId
                    Activity        = 'Processing Applications'
                    Status          = "Application $processedCount of $appCount"
                    CurrentOperation = $app.DisplayName
                    PercentComplete = $percentComplete
                }
                if ($ProgressParentId -ge 0) {
                    $progressParams['ParentId'] = $ProgressParentId
                }
                Write-Progress @progressParams

                Write-Verbose -Message "Processing application $processedCount of $appCount : $($app.DisplayName)"

                # Get owner information once per application (not per credential)
                $ownerInfo = $null
                if ($IncludeOwners) {
                    try {
                        $owners = Get-MgApplicationOwner -ApplicationId $app.Id -ErrorAction SilentlyContinue
                        $ownerInfo = Resolve-OwnerInfo -Owners $owners -ObjectId $app.Id
                    }
                    catch {
                        Write-Warning -Message "Failed to get owners for application $($app.DisplayName): $PSItem"
                        $ownerInfo = [PSCustomObject]@{
                            OwnerDisplayNames = '<<Error>>'
                            OwnerUpns         = ''
                            OwnerIds          = ''
                            OwnerCount        = 0
                        }
                    }
                }

                # Process password credentials (secrets)
                foreach ($secret in $app.PasswordCredentials) {
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
                            DisplayName        = $app.DisplayName
                            ApplicationId      = $app.AppId
                            ObjectId           = $app.Id
                            ObjectType         = 'Application'
                            CredentialType     = 'Secret'
                            CredentialName     = $secret.DisplayName
                            KeyId              = $secret.KeyId
                            Hint               = $secret.Hint
                            StartDate          = $secret.StartDateTime
                            EndDate            = $secret.EndDateTime
                            DaysRemaining      = $credStatus.DaysRemaining
                            DaysPastExpiration = $credStatus.DaysPastExpiration
                            Status             = $credStatus.Status
                            Owner              = if ($ownerInfo) { $ownerInfo.OwnerDisplayNames } else { '' }
                            OwnerUpns          = if ($ownerInfo) { $ownerInfo.OwnerUpns } else { '' }
                            OwnerIds           = if ($ownerInfo) { $ownerInfo.OwnerIds } else { '' }
                        }
                        $results.Add($credentialResult)
                    }
                }

                # Process key credentials (certificates)
                foreach ($cert in $app.KeyCredentials) {
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
                        $credentialResult = [PSCustomObject]@{
                            DisplayName        = $app.DisplayName
                            ApplicationId      = $app.AppId
                            ObjectId           = $app.Id
                            ObjectType         = 'Application'
                            CredentialType     = 'Certificate'
                            CredentialName     = $cert.DisplayName
                            KeyId              = $cert.KeyId
                            Hint               = $null  # Certificates don't have hints
                            StartDate          = $cert.StartDateTime
                            EndDate            = $cert.EndDateTime
                            DaysRemaining      = $credStatus.DaysRemaining
                            DaysPastExpiration = $credStatus.DaysPastExpiration
                            Status             = $credStatus.Status
                            CertificateType    = $cert.Type
                            CertificateUsage   = $cert.Usage
                            Owner              = if ($ownerInfo) { $ownerInfo.OwnerDisplayNames } else { '' }
                            OwnerUpns          = if ($ownerInfo) { $ownerInfo.OwnerUpns } else { '' }
                            OwnerIds           = if ($ownerInfo) { $ownerInfo.OwnerIds } else { '' }
                        }
                        $results.Add($credentialResult)
                    }
                }
            }

            # Complete progress
            Write-Progress -Id $progressId -Activity 'Processing Applications' -Completed
        }
        catch {
            Write-Progress -Id $progressId -Activity 'Processing Applications' -Completed
            Write-Error -Message "Failed to query applications: $PSItem"
            throw
        }
    }

    end {
        Write-Verbose -Message "Found $($results.Count) credential(s) matching criteria"
        $results
    }
}
