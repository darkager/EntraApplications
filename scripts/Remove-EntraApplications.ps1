#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
    Bulk-remove Entra ID application registrations from a CSV of object IDs.

.DESCRIPTION
    Reads a CSV file containing an ObjectId column and deletes each corresponding
    application registration from Entra ID. All operations are logged via
    PowerShell transcript.

.PARAMETER InputCsv
    Path to the CSV file. Must contain an 'ObjectId' column with application object IDs.

.PARAMETER TranscriptPath
    Path for the transcript log file. Defaults to
    Remove-EntraApplications_<timestamp>.log in the current directory.

.PARAMETER Force
    Skip the confirmation prompt before deletion begins.

.EXAMPLE
    .\Remove-EntraApplications.ps1 -InputCsv 'C:\Data\apps-to-delete.csv'

    Prompts for confirmation, then deletes each application listed in the CSV.

.EXAMPLE
    .\Remove-EntraApplications.ps1 -InputCsv 'C:\Data\apps-to-delete.csv' -Force -Verbose

    Deletes without prompting; verbose output shows per-item progress.

.EXAMPLE
    .\Remove-EntraApplications.ps1 -InputCsv 'C:\Data\apps-to-delete.csv' -WhatIf

    Shows what would be deleted without making any changes.

.NOTES
    Requires an active Microsoft Graph session with Application.ReadWrite.All permission.
    Connect first: Connect-MgGraph -Scopes 'Application.ReadWrite.All'

    CSV format:
        ObjectId
        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path -Path $PSItem -PathType Leaf)) {
            throw "File not found: $PSItem"
        }
        $true
    })]
    [String]$InputCsv,

    [Parameter()]
    [String]$TranscriptPath,

    [Parameter()]
    [Switch]$Force
)

# Build transcript path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not $TranscriptPath) {
    $TranscriptPath = Join-Path -Path (Get-Location) -ChildPath "Remove-EntraApplications_$timestamp.log"
}

# Start transcript (bypass WhatIf — logging is observational, not destructive)
$savedWhatIf = $WhatIfPreference
$WhatIfPreference = $false
Start-Transcript -Path $TranscriptPath -Append
$WhatIfPreference = $savedWhatIf
Write-Verbose -Message "Transcript logging to: $TranscriptPath"

try {
    # Import and validate CSV
    Write-Verbose -Message "Importing CSV: $InputCsv"
    $entries = Import-Csv -Path $InputCsv -Encoding UTF8

    if (-not $entries) {
        Write-Warning -Message 'CSV file is empty. Nothing to process.'
        return
    }

    $columnNames = ($entries | Select-Object -First 1).PSObject.Properties.Name
    if ('ObjectId' -notin $columnNames) {
        throw "CSV must contain an 'ObjectId' column. Found columns: $($columnNames -join ', ')"
    }

    # Filter out blank rows
    $entries = @($entries | Where-Object -FilterScript { -not [String]::IsNullOrWhiteSpace($PSItem.ObjectId) })
    $totalCount = $entries.Count
    Write-Host "Found $totalCount application(s) to delete in CSV." -ForegroundColor Cyan

    if ($totalCount -eq 0) {
        Write-Warning -Message 'No valid ObjectId values found in CSV.'
        return
    }

    # Confirmation gate (skip when -WhatIf so per-item WhatIf output is shown)
    if (-not $WhatIfPreference -and -not $Force -and -not $PSCmdlet.ShouldProcess(
        "$totalCount application registration(s)",
        'Delete'
    )) {
        Write-Host 'Operation cancelled by user.' -ForegroundColor Yellow
        return
    }

    # Process deletions
    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    $processedCount = 0

    foreach ($entry in $entries) {
        $processedCount++
        $objectId = $entry.ObjectId.Trim()
        $percentComplete = [Math]::Round(($processedCount / $totalCount) * 100)

        Write-Progress -Activity 'Removing Application Registrations' `
            -Status "[$processedCount/$totalCount] $objectId" `
            -PercentComplete $percentComplete

        # Validate GUID format
        $guidResult = [Guid]::Empty
        if (-not [Guid]::TryParse($objectId, [ref]$guidResult)) {
            Write-Warning -Message "Skipping invalid ObjectId (not a GUID): $objectId"
            $skippedCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess($objectId, 'Remove-MgApplication')) {
            try {
                Remove-MgApplication -ApplicationId $objectId -ErrorAction Stop
                Write-Verbose -Message "Deleted application: $objectId"
                $successCount++
            }
            catch {
                Write-Warning -Message "Failed to delete application $objectId : $PSItem"
                $failCount++
            }
        }
    }

    Write-Progress -Activity 'Removing Application Registrations' -Completed

    # Summary
    Write-Host ''
    Write-Host '--- Summary ---' -ForegroundColor Cyan
    Write-Host "  Total in CSV:  $totalCount" -ForegroundColor White
    Write-Host "  Deleted:       $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "  Failed:        $failCount" -ForegroundColor Red
    }
    if ($skippedCount -gt 0) {
        Write-Host "  Skipped:       $skippedCount" -ForegroundColor Yellow
    }
    Write-Host "  Transcript:    $TranscriptPath" -ForegroundColor White
}
catch {
    Write-Error -Message "Script failed: $PSItem"
    throw
}
finally {
    $savedWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    Stop-Transcript
    $WhatIfPreference = $savedWhatIf
}
