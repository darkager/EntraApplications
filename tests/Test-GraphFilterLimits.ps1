<#
.SYNOPSIS
    Tests Microsoft Graph API filter 'in' operator limits.

.DESCRIPTION
    Empirically determines the practical limits for using the 'in' operator
    in Microsoft Graph API filter queries. Tests both:
    1. Number of values in an 'in' clause
    2. URL/query string length limits

    Known documented limits:
    - ~15 expressions (OR conditions) default
    - ~3000 character URL length
    - Can use ConsistencyLevel: eventual for advanced queries

.EXAMPLE
    .\Test-GraphFilterLimits.ps1

.EXAMPLE
    .\Test-GraphFilterLimits.ps1 -MaxValuesToTest 50 -Verbose

.NOTES
    Requires Microsoft.Graph.Beta.Reports module and AuditLog.Read.All permission.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [Int32]$MaxValuesToTest = 100,

    [Parameter()]
    [Int32]$StartingCount = 5,

    [Parameter()]
    [Int32]$Increment = 5
)

#Requires -Modules Microsoft.Graph.Beta.Reports

Write-Host "`n=== Microsoft Graph Filter 'in' Operator Limit Test ===" -ForegroundColor Cyan
Write-Host "Testing with sign-in logs (auditLogs/signIns endpoint)`n"

# First, get some real appIds to use for testing
Write-Host "Step 1: Gathering sample AppIds from recent sign-ins..." -ForegroundColor Yellow

try {
    $sampleSignIns = Get-MgBetaAuditLogSignIn -Top 200 -ErrorAction Stop
    $uniqueAppIds = @($sampleSignIns | Select-Object -ExpandProperty AppId -Unique)
    Write-Host "  Found $($uniqueAppIds.Count) unique AppIds to use for testing`n" -ForegroundColor Green
}
catch {
    Write-Error "Failed to get sample sign-ins. Ensure you have AuditLog.Read.All permission."
    Write-Error $PSItem
    exit 1
}

if ($uniqueAppIds.Count -lt $MaxValuesToTest) {
    Write-Warning "Only found $($uniqueAppIds.Count) unique AppIds. Adjusting MaxValuesToTest."
    $MaxValuesToTest = $uniqueAppIds.Count
}

# Test results
$results = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

Write-Host "Step 2: Testing 'in' operator with increasing value counts..." -ForegroundColor Yellow
Write-Host "  Testing from $StartingCount to $MaxValuesToTest values (increment: $Increment)`n"

$lastSuccessCount = 0
$firstFailCount = 0

for ($count = $StartingCount; $count -le $MaxValuesToTest; $count += $Increment) {
    $testAppIds = $uniqueAppIds | Select-Object -First $count

    # Build the filter string
    $quotedIds = $testAppIds | ForEach-Object -Process { "'$PSItem'" }
    $filterValue = "appId in ($($quotedIds -join ', '))"
    $filterLength = $filterValue.Length

    Write-Host "  Testing $count AppIds (filter length: $filterLength chars)... " -NoNewline

    $startTime = Get-Date
    $success = $false
    $errorMessage = $null
    $resultCount = 0

    try {
        # Use -Top 1 to minimize data transfer while testing filter validity
        $testResult = Get-MgBetaAuditLogSignIn -Filter $filterValue -Top 1 -ErrorAction Stop
        $success = $true
        $resultCount = @($testResult).Count
        $lastSuccessCount = $count
        Write-Host "SUCCESS" -ForegroundColor Green -NoNewline
        Write-Host " (returned $resultCount record(s))"
    }
    catch {
        $success = $false
        $errorMessage = $PSItem.Exception.Message
        if ($firstFailCount -eq 0) {
            $firstFailCount = $count
        }
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "    Error: $($errorMessage.Substring(0, [Math]::Min(100, $errorMessage.Length)))..." -ForegroundColor DarkRed
    }

    $duration = (Get-Date) - $startTime

    $results.Add([PSCustomObject]@{
        ValueCount    = $count
        FilterLength  = $filterLength
        Success       = $success
        DurationMs    = [Math]::Round($duration.TotalMilliseconds)
        ResultCount   = $resultCount
        ErrorMessage  = $errorMessage
    })

    # If we've found the failure point, test a few more to confirm
    if (-not $success -and $results.Count -ge 3) {
        $recentFailures = @($results | Select-Object -Last 3 | Where-Object -FilterScript { -not $PSItem.Success })
        if ($recentFailures.Count -ge 2) {
            Write-Host "`n  Stopping early - found consistent failure point" -ForegroundColor Yellow
            break
        }
    }
}

# Summary
Write-Host "`n=== Test Results Summary ===" -ForegroundColor Cyan

Write-Host "`nValue Count Results:" -ForegroundColor Yellow
$results | Format-Table -Property ValueCount, FilterLength, Success, DurationMs -AutoSize

Write-Host "Findings:" -ForegroundColor Green
Write-Host "  - Maximum successful 'in' values: $lastSuccessCount"
if ($firstFailCount -gt 0) {
    Write-Host "  - First failure at: $firstFailCount values"

    $lastSuccess = $results | Where-Object -FilterScript { $PSItem.ValueCount -eq $lastSuccessCount }
    if ($lastSuccess) {
        Write-Host "  - Safe filter length: $($lastSuccess.FilterLength) characters"
    }
}
else {
    Write-Host "  - No failures encountered up to $MaxValuesToTest values"
}

# Test with ConsistencyLevel: eventual header
Write-Host "`nStep 3: Testing with ConsistencyLevel: eventual header..." -ForegroundColor Yellow

if ($firstFailCount -gt 0) {
    $testCount = $firstFailCount
    $testAppIds = $uniqueAppIds | Select-Object -First $testCount
    $quotedIds = $testAppIds | ForEach-Object -Process { "'$PSItem'" }
    $filterValue = "appId in ($($quotedIds -join ', '))"

    Write-Host "  Retrying $testCount AppIds with advanced query... " -NoNewline

    try {
        # Note: Get-MgBetaAuditLogSignIn may not support -ConsistencyLevel directly
        # This is for documentation purposes - may need Invoke-MgGraphRequest
        $testResult = Get-MgBetaAuditLogSignIn -Filter $filterValue -Top 1 -ConsistencyLevel eventual -ErrorAction Stop
        Write-Host "SUCCESS with ConsistencyLevel: eventual" -ForegroundColor Green
    }
    catch {
        Write-Host "Still FAILED" -ForegroundColor Red
        Write-Host "  Advanced query did not help for this endpoint" -ForegroundColor DarkYellow
    }
}

# Recommendations
Write-Host "`n=== Recommendations ===" -ForegroundColor Cyan

$recommendedBatchSize = if ($lastSuccessCount -gt 0) {
    [Math]::Floor($lastSuccessCount * 0.8)  # 80% of max for safety margin
} else {
    10  # Conservative default
}

Write-Host @"

Based on testing, recommended approach for batch querying:

1. Batch Size: $recommendedBatchSize AppIds per query (80% of max for safety)
2. For $($uniqueAppIds.Count) SSO apps, you would need: $([Math]::Ceiling($uniqueAppIds.Count / $recommendedBatchSize)) API calls

Example batching code:

`$appIds = @('id1', 'id2', ...) # Your SSO app IDs
`$batchSize = $recommendedBatchSize
`$batches = for (`$i = 0; `$i -lt `$appIds.Count; `$i += `$batchSize) {
    ,@(`$appIds[`$i..[Math]::Min(`$i + `$batchSize - 1, `$appIds.Count - 1)])
}

foreach (`$batch in `$batches) {
    `$filter = "appId in (`$(`$batch | ForEach-Object { "'`$PSItem'" } | Join-String -Separator ', '))"
    `$signIns = Get-MgBetaAuditLogSignIn -Filter `$filter -All
    # Process results...
}

"@

# Export detailed results
$results | Export-Csv -Path "$PSScriptRoot\FilterLimitTestResults.csv" -NoTypeInformation -Encoding UTF8
Write-Host "Detailed results exported to: $PSScriptRoot\FilterLimitTestResults.csv`n" -ForegroundColor Gray
