function Export-EntraCredentialReport {
    <#
    .SYNOPSIS
        Exports a combined credential expiration report to CSV.

    .DESCRIPTION
        Queries both applications and service principals for expiring credentials
        and exports the combined results to a CSV file. Optionally returns the
        data as objects for further processing.

    .PARAMETER OutputPath
        Base path for the CSV output. The function appends '_<timestamp>.csv' if a
        directory is specified, or uses the exact path if a .csv file is specified.
        If not specified, outputs to EntraCredentialReport_<timestamp>.csv in the current directory.

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
        Exclude Microsoft first-party and Microsoft-managed service principals.
        This includes apps owned by Microsoft's tenant as well as Microsoft-managed
        apps registered in your tenant (e.g., P2P Server device RDP certificates).

    .PARAMETER ExcludeManagedIdentity
        Exclude Managed Identity service principals. Managed Identity credentials
        are auto-rotated by Azure and typically don't require manual monitoring.

    .PARAMETER ExcludeOwners
        Exclude owner information from the report. Use for faster execution.

    .PARAMETER PassThru
        Return the credential objects in addition to exporting to CSV.

    .EXAMPLE
        Export-EntraCredentialReport

        Exports all expiring credentials to a timestamped CSV file in the current directory.

    .EXAMPLE
        Export-EntraCredentialReport -OutputPath 'C:\Reports'

        Exports to C:\Reports\EntraCredentialReport_<timestamp>.csv

    .EXAMPLE
        Export-EntraCredentialReport -OutputPath 'C:\Reports\credentials.csv' -DaysUntilExpiration 90

        Exports credentials expiring within 90 days to the specific file.

    .EXAMPLE
        Export-EntraCredentialReport -ExcludeMicrosoft -ExcludeManagedIdentity -PassThru

        Exports credentials excluding Microsoft and Managed Identity apps, returns the objects.

    .EXAMPLE
        $report = Export-EntraCredentialReport -PassThru
        $report | Where-Object -FilterScript { $PSItem.Status -eq 'Expired' }

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
        [Switch]$ExcludeMicrosoft,

        [Parameter()]
        [Switch]$ExcludeManagedIdentity,

        [Parameter()]
        [Switch]$ExcludeOwners,

        [Parameter()]
        [Switch]$PassThru
    )

    begin {
        Write-Verbose -Message 'Starting Export-EntraCredentialReport'

        # Generate output path
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        if (-not $OutputPath) {
            $OutputPath = Join-Path -Path (Get-Location) -ChildPath "EntraCredentialReport_$timestamp.csv"
        }
        elseif (Test-Path -Path $OutputPath -PathType Container) {
            # OutputPath is a directory - append filename
            $OutputPath = Join-Path -Path $OutputPath -ChildPath "EntraCredentialReport_$timestamp.csv"
        }
        elseif (-not $OutputPath.EndsWith('.csv', [StringComparison]::OrdinalIgnoreCase)) {
            # OutputPath is a base name - append timestamp and extension
            $OutputPath = "${OutputPath}_$timestamp.csv"
        }
        # else: OutputPath is already a full .csv path, use as-is

        # Ensure directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # Initialize combined results using List for O(n) performance
        $allCredentials = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

        # Determine IncludeOwners value (inverse of ExcludeOwners)
        $includeOwners = -not $ExcludeOwners

        # Progress tracking
        $parentProgressId = 0
        $totalSteps = ([Int32]$IncludeApplications) + ([Int32]$IncludeServicePrincipals)
        $currentStep = 0
    }

    process {
        try {
            # Get application credentials
            if ($IncludeApplications) {
                $currentStep++
                $parentPercent = [Math]::Round(($currentStep - 1) / $totalSteps * 100)
                Write-Progress -Id $parentProgressId -Activity 'Exporting Credential Report' `
                    -Status "[$currentStep/$totalSteps] Querying application credentials" `
                    -PercentComplete $parentPercent

                Write-Verbose -Message 'Querying application credentials...'
                $appCredentials = Get-ExpiringAppCredential `
                    -DaysUntilExpiration $DaysUntilExpiration `
                    -IncludeExpired $IncludeExpired `
                    -IncludeOwners $includeOwners `
                    -ProgressParentId $parentProgressId

                foreach ($cred in $appCredentials) {
                    # Normalize to common schema
                    $normalized = [PSCustomObject]@{
                        DisplayName          = $cred.DisplayName
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
                $currentStep++
                $parentPercent = [Math]::Round(($currentStep - 1) / $totalSteps * 100)
                Write-Progress -Id $parentProgressId -Activity 'Exporting Credential Report' `
                    -Status "[$currentStep/$totalSteps] Querying service principal credentials" `
                    -PercentComplete $parentPercent

                Write-Verbose -Message 'Querying service principal credentials...'
                $spCredentials = Get-ExpiringSpCredential `
                    -DaysUntilExpiration $DaysUntilExpiration `
                    -IncludeExpired $IncludeExpired `
                    -IncludeOwners $includeOwners `
                    -ExcludeMicrosoft:$ExcludeMicrosoft `
                    -ExcludeManagedIdentity:$ExcludeManagedIdentity `
                    -ProgressParentId $parentProgressId

                foreach ($cred in $spCredentials) {
                    # Normalize to common schema
                    $normalized = [PSCustomObject]@{
                        DisplayName          = $cred.DisplayName
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

            # Complete parent progress
            Write-Progress -Id $parentProgressId -Activity 'Exporting Credential Report' -Completed

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
            Write-Progress -Id $parentProgressId -Activity 'Exporting Credential Report' -Completed
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
