function Export-EntraSsoReport {
    <#
    .SYNOPSIS
        Exports an SSO configuration report to CSV.

    .DESCRIPTION
        Queries service principals for SSO configuration and exports the results
        to a CSV file. Provides summary statistics by SSO type.

    .PARAMETER OutputPath
        Base path for the CSV output. The function appends '_<timestamp>.csv' if a
        directory is specified, or uses the exact path if a .csv file is specified.
        If not specified, outputs to EntraSsoReport_<timestamp>.csv in the current directory.

    .PARAMETER SsoType
        Filter results by SSO type. Valid values: All, SAML, OIDC, Password.
        Default is All (excludes None).

    .PARAMETER ExcludeMicrosoft
        Exclude Microsoft first-party service principals.

    .PARAMETER IncludeNone
        Include service principals with no SSO configured.

    .PARAMETER PassThru
        Return the SSO application objects in addition to exporting to CSV.

    .EXAMPLE
        Export-EntraSsoReport

        Exports all SSO-configured applications to a timestamped CSV file in the current directory.

    .EXAMPLE
        Export-EntraSsoReport -OutputPath 'C:\Reports'

        Exports to C:\Reports\EntraSsoReport_<timestamp>.csv

    .EXAMPLE
        Export-EntraSsoReport -OutputPath 'C:\Reports\SsoReport.csv' -SsoType SAML

        Exports only SAML applications to the specific file.

    .EXAMPLE
        Export-EntraSsoReport -ExcludeMicrosoft -PassThru

        Exports non-Microsoft apps and returns the objects for further processing.

    .EXAMPLE
        $report = Export-EntraSsoReport -PassThru
        $report | Where-Object -FilterScript { $PSItem.SsoType -eq 'SAML' -and $PSItem.HasSamlSigningCert }

        Gets the report and filters for SAML apps with signing certificates.

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
        [ValidateSet('All', 'SAML', 'OIDC', 'Password')]
        [String]$SsoType = 'All',

        [Parameter()]
        [Switch]$ExcludeMicrosoft,

        [Parameter()]
        [Switch]$IncludeNone,

        [Parameter()]
        [Switch]$PassThru
    )

    begin {
        Write-Verbose -Message 'Starting Export-EntraSsoReport'

        # Generate output path
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        if (-not $OutputPath) {
            $OutputPath = Join-Path -Path (Get-Location) -ChildPath "EntraSsoReport_$timestamp.csv"
        }
        elseif (Test-Path -Path $OutputPath -PathType Container) {
            # OutputPath is a directory - append filename
            $OutputPath = Join-Path -Path $OutputPath -ChildPath "EntraSsoReport_$timestamp.csv"
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

        # Progress tracking
        $parentProgressId = 0
    }

    process {
        try {
            # Get SSO applications
            Write-Progress -Id $parentProgressId -Activity 'Exporting SSO Report' `
                -Status '[1/1] Querying SSO-configured service principals' `
                -PercentComplete 0

            Write-Verbose -Message 'Querying SSO applications...'
            $ssoApps = Get-SsoApplication `
                -SsoType $SsoType `
                -ExcludeMicrosoft:$ExcludeMicrosoft `
                -IncludeNone:$IncludeNone `
                -ProgressParentId $parentProgressId

            # Complete parent progress
            Write-Progress -Id $parentProgressId -Activity 'Exporting SSO Report' -Completed

            $appCount = @($ssoApps).Count

            if ($appCount -eq 0) {
                Write-Warning -Message 'No SSO applications found matching criteria.'
                return
            }

            # Sort by SSO type, then by display name
            $sortedApps = $ssoApps | Sort-Object -Property SsoType, DisplayName

            # Export to CSV
            Write-Verbose -Message "Exporting $appCount application(s) to $OutputPath"
            $sortedApps | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

            Write-Host "Report exported to: $OutputPath" -ForegroundColor Green
            Write-Host "Total SSO applications found: $appCount" -ForegroundColor Cyan

            # Summary by SSO type
            $ssoSummary = $sortedApps | Group-Object -Property SsoType
            foreach ($group in $ssoSummary) {
                $color = switch ($group.Name) {
                    'SAML' { 'Yellow' }
                    'OIDC' { 'Cyan' }
                    'Password' { 'Magenta' }
                    'None' { 'Gray' }
                    'NotSupported' { 'DarkGray' }
                    default { 'White' }
                }
                Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor $color
            }

            # Summary by detection source
            $sourceSummary = $sortedApps | Group-Object -Property SsoTypeSource
            Write-Host "`nDetection source breakdown:" -ForegroundColor Cyan
            foreach ($group in $sourceSummary) {
                Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor White
            }

            # SAML certificate warning
            $samlWithCerts = @($sortedApps | Where-Object -FilterScript {
                $PSItem.SsoType -eq 'SAML' -and $PSItem.HasSamlSigningCert
            })
            if ($samlWithCerts.Count -gt 0) {
                $now = Get-Date
                $expiringSoon = @($samlWithCerts | Where-Object -FilterScript {
                    $null -ne $PSItem.EarliestSamlCertExpiration -and
                    ($PSItem.EarliestSamlCertExpiration - $now).Days -le 30
                })
                if ($expiringSoon.Count -gt 0) {
                    Write-Host "`nWarning: $($expiringSoon.Count) SAML app(s) have certificates expiring within 30 days!" -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Progress -Id $parentProgressId -Activity 'Exporting SSO Report' -Completed
            Write-Error -Message "Failed to generate SSO report: $PSItem"
            throw
        }
    }

    end {
        if ($PassThru) {
            $sortedApps
        }
    }
}
