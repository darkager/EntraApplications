function Export-CredentialReport {
    <#
    .SYNOPSIS
        Exports a combined credential expiration report to CSV.

    .DESCRIPTION
        Queries both applications and service principals for expiring credentials
        and exports the combined results to a CSV file. Optionally returns the
        data as objects for further processing.

    .PARAMETER OutputPath
        The file path for the CSV export.
        If not specified, generates a file in the current directory with timestamp.

    .PARAMETER DaysUntilExpiration
        The number of days to look ahead for expiring credentials.
        Default is 30 days.

    .PARAMETER IncludeExpired
        Include credentials that have already expired.
        Default is $true.

    .PARAMETER IncludeApplications
        Include application (App Registration) credentials.
        Default is $true.

    .PARAMETER IncludeServicePrincipals
        Include service principal (Enterprise Application) credentials.
        Default is $true.

    .PARAMETER ExcludeMicrosoft
        Exclude Microsoft first-party service principals.
        Default is $false.

    .PARAMETER IncludeOwners
        Include owner information in the report.
        Default is $true.

    .PARAMETER PassThru
        Return the credential objects in addition to exporting to CSV.

    .EXAMPLE
        Export-CredentialReport

        Exports all expiring credentials to a timestamped CSV file.

    .EXAMPLE
        Export-CredentialReport -OutputPath 'C:\Reports\credentials.csv' -DaysUntilExpiration 90

        Exports credentials expiring within 90 days to a specific file.

    .EXAMPLE
        Export-CredentialReport -IncludeServicePrincipals $false -PassThru

        Exports only application credentials and returns the objects.

    .EXAMPLE
        $report = Export-CredentialReport -PassThru
        $report | Where-Object { $_.Status -eq 'Expired' }

        Gets the report and filters for expired credentials.

    .OUTPUTS
        If -PassThru is specified, returns PSCustomObject collection.
        Always creates a CSV file at the specified or generated path.

    .NOTES
        Requires Microsoft.Graph.Applications module and Application.Read.All permission.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [String]$OutputPath,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [Int32]$DaysUntilExpiration = 30,

        [Parameter()]
        [Bool]$IncludeExpired = $true,

        [Parameter()]
        [Bool]$IncludeApplications = $true,

        [Parameter()]
        [Bool]$IncludeServicePrincipals = $true,

        [Parameter()]
        [Bool]$ExcludeMicrosoft = $false,

        [Parameter()]
        [Bool]$IncludeOwners = $true,

        [Parameter()]
        [Switch]$PassThru
    )

    begin {
        Write-Verbose -Message 'Starting Export-CredentialReport'

        # Generate output path if not specified
        if (-not $OutputPath) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $OutputPath = Join-Path -Path (Get-Location) -ChildPath "CredentialReport_$timestamp.csv"
        }

        # Ensure directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # Initialize combined results using List for O(n) performance
        $allCredentials = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'
    }

    process {
        try {
            # Get application credentials
            if ($IncludeApplications) {
                Write-Verbose -Message 'Querying application credentials...'
                $appCredentials = Get-ExpiringAppCredential `
                    -DaysUntilExpiration $DaysUntilExpiration `
                    -IncludeExpired $IncludeExpired `
                    -IncludeOwners $IncludeOwners

                foreach ($cred in $appCredentials) {
                    # Normalize to common schema
                    $normalized = [PSCustomObject]@{
                        DisplayName          = $cred.ApplicationName
                        ApplicationId        = $cred.ApplicationId
                        ObjectId             = $cred.ObjectId
                        ObjectType           = $cred.ObjectType
                        ServicePrincipalType = $null
                        CredentialType       = $cred.CredentialType
                        CredentialName       = $cred.CredentialName
                        KeyId                = $cred.KeyId
                        Hint                 = $cred.Hint
                        StartDate            = $cred.StartDate
                        EndDate              = $cred.EndDate
                        DaysRemaining        = $cred.DaysRemaining
                        DaysPastExpiration   = $cred.DaysPastExpiration
                        Status               = $cred.Status
                        CertificateType      = $cred.CertificateType
                        CertificateUsage     = $cred.CertificateUsage
                        Owner                = $cred.Owner
                        OwnerUpns            = $cred.OwnerUpns
                        OwnerIds             = $cred.OwnerIds
                    }
                    $allCredentials.Add($normalized)
                }
                Write-Verbose -Message "Added $(@($appCredentials).Count) application credential(s)"
            }

            # Get service principal credentials
            if ($IncludeServicePrincipals) {
                Write-Verbose -Message 'Querying service principal credentials...'
                $spCredentials = Get-ExpiringSpCredential `
                    -DaysUntilExpiration $DaysUntilExpiration `
                    -IncludeExpired $IncludeExpired `
                    -IncludeOwners $IncludeOwners `
                    -ExcludeMicrosoft $ExcludeMicrosoft

                foreach ($cred in $spCredentials) {
                    # Normalize to common schema
                    $normalized = [PSCustomObject]@{
                        DisplayName          = $cred.ServicePrincipalName
                        ApplicationId        = $cred.ApplicationId
                        ObjectId             = $cred.ObjectId
                        ObjectType           = $cred.ObjectType
                        ServicePrincipalType = $cred.ServicePrincipalType
                        CredentialType       = $cred.CredentialType
                        CredentialName       = $cred.CredentialName
                        KeyId                = $cred.KeyId
                        Hint                 = $cred.Hint
                        StartDate            = $cred.StartDate
                        EndDate              = $cred.EndDate
                        DaysRemaining        = $cred.DaysRemaining
                        DaysPastExpiration   = $cred.DaysPastExpiration
                        Status               = $cred.Status
                        CertificateType      = $cred.CertificateType
                        CertificateUsage     = $cred.CertificateUsage
                        Owner                = $cred.Owner
                        OwnerUpns            = $cred.OwnerUpns
                        OwnerIds             = $cred.OwnerIds
                    }
                    $allCredentials.Add($normalized)
                }
                Write-Verbose -Message "Added $(@($spCredentials).Count) service principal credential(s)"
            }

            # Sort by days remaining (expired first, then soonest to expire)
            $sortedCredentials = $allCredentials | Sort-Object -Property @{
                Expression = {
                    if ($null -eq $PSItem.DaysRemaining) { [Int32]::MaxValue }
                    else { $PSItem.DaysRemaining }
                }
            }

            # Export to CSV
            Write-Verbose -Message "Exporting $($allCredentials.Count) credential(s) to $OutputPath"
            $sortedCredentials | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

            Write-Host "Report exported to: $OutputPath" -ForegroundColor Green
            Write-Host "Total credentials found: $($allCredentials.Count)" -ForegroundColor Cyan

            # Summary by status
            $statusSummary = $sortedCredentials | Group-Object -Property Status
            foreach ($group in $statusSummary) {
                $color = switch ($group.Name) {
                    'Expired' { 'Red' }
                    'ExpiringToday' { 'Red' }
                    'ExpiringSoon' { 'Yellow' }
                    'ExpiringMedium' { 'Yellow' }
                    'Valid' { 'Green' }
                    default { 'White' }
                }
                Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor $color
            }
        }
        catch {
            Write-Error -Message "Failed to generate credential report: $PSItem"
            throw
        }
    }

    end {
        if ($PassThru) {
            $sortedCredentials
        }
    }
}
