function Get-BatchedSignInActivity {
    <#
    .SYNOPSIS
        Retrieves sign-in activity for multiple applications using batched queries.

    .DESCRIPTION
        Queries the Microsoft Graph Beta API for sign-in activity across multiple
        applications. Uses batched 'in' operator queries to minimize API calls
        while respecting Graph API filter limits.

        Known Graph API limits:
        - ~15 expressions in filter clause (default)
        - ~3000 character URL/filter length
        - Using ConsistencyLevel: eventual may increase limits

    .PARAMETER AppIds
        Array of Application IDs to query sign-in activity for.

    .PARAMETER BatchSize
        Number of AppIds to include per API query. Default is 10.
        Recommended range: 10-15 (to stay within Graph API limits).

    .PARAMETER DaysBack
        Number of days back to query for sign-ins. Default is 30.
        Maximum is typically 30 days for sign-in logs.

    .PARAMETER IncludeDetails
        Include detailed sign-in information (authentication method, protocol, etc.).
        When false, only returns aggregated last sign-in date per app.

    .OUTPUTS
        PSCustomObject with sign-in activity summary per application.

    .EXAMPLE
        $appIds = @('app-id-1', 'app-id-2', 'app-id-3')
        Get-BatchedSignInActivity -AppIds $appIds

    .NOTES
        Internal function - not exported from module.

        Requires:
        - Microsoft.Graph.Beta.Reports module
        - AuditLog.Read.All or Directory.Read.All permission
        - Entra ID P1 or P2 license
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [String[]]$AppIds,

        [Parameter()]
        [ValidateRange(1, 20)]
        [Int32]$BatchSize = 10,

        [Parameter()]
        [ValidateRange(1, 30)]
        [Int32]$DaysBack = 30,

        [Parameter()]
        [Switch]$IncludeDetails
    )

    begin {
        Write-Verbose -Message "Starting Get-BatchedSignInActivity for $($AppIds.Count) application(s)"

        # Initialize results dictionary for aggregation
        $activityMap = New-Object -TypeName 'System.Collections.Generic.Dictionary[[String],[PSCustomObject]]'

        # Initialize each app with default values
        foreach ($appId in $AppIds) {
            $activityMap[$appId] = [PSCustomObject]@{
                AppId                    = $appId
                HasSignInData            = $false
                LastSignInDateTime       = $null
                SignInCount              = 0
                UniqueUserCount          = 0
                SuccessCount             = 0
                FailureCount             = 0
                AuthenticationProtocols  = @()
                LastAuthProtocol         = $null
            }
        }

        # Calculate date filter
        $startDate = (Get-Date).AddDays(-$DaysBack).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    process {
        # Create batches
        $batches = New-Object -TypeName 'System.Collections.Generic.List[String[]]'
        for ($i = 0; $i -lt $AppIds.Count; $i += $BatchSize) {
            $endIndex = [Math]::Min($i + $BatchSize - 1, $AppIds.Count - 1)
            $batch = @($AppIds[$i..$endIndex])
            $batches.Add($batch)
        }

        Write-Verbose -Message "Created $($batches.Count) batch(es) of up to $BatchSize AppIds each"

        $batchNum = 0
        foreach ($batch in $batches) {
            $batchNum++
            Write-Verbose -Message "Processing batch $batchNum of $($batches.Count) ($($batch.Count) AppIds)"

            # Build the 'in' filter
            $quotedIds = $batch | ForEach-Object -Process { "'$PSItem'" }
            $appIdFilter = "appId in ($($quotedIds -join ', '))"
            $fullFilter = "createdDateTime ge $startDate and $appIdFilter"

            Write-Verbose -Message "Filter length: $($fullFilter.Length) characters"

            try {
                # Query sign-ins for this batch
                $signIns = Get-MgBetaAuditLogSignIn -Filter $fullFilter -All -ErrorAction Stop

                Write-Verbose -Message "  Retrieved $(@($signIns).Count) sign-in record(s)"

                # Aggregate results by AppId
                foreach ($signIn in $signIns) {
                    $appId = $signIn.AppId

                    if ($activityMap.ContainsKey($appId)) {
                        $activity = $activityMap[$appId]
                        $activity.HasSignInData = $true
                        $activity.SignInCount++

                        # Track latest sign-in
                        if ($null -eq $activity.LastSignInDateTime -or $signIn.CreatedDateTime -gt $activity.LastSignInDateTime) {
                            $activity.LastSignInDateTime = $signIn.CreatedDateTime
                            $activity.LastAuthProtocol = $signIn.AuthenticationProtocol
                        }

                        # Track success/failure
                        if ($signIn.Status.ErrorCode -eq 0) {
                            $activity.SuccessCount++
                        }
                        else {
                            $activity.FailureCount++
                        }

                        # Track authentication protocols (if detailed)
                        if ($IncludeDetails -and $signIn.AuthenticationProtocol) {
                            if ($activity.AuthenticationProtocols -notcontains $signIn.AuthenticationProtocol) {
                                $activity.AuthenticationProtocols = @($activity.AuthenticationProtocols) + $signIn.AuthenticationProtocol
                            }
                        }
                    }
                }

                # Calculate unique users per app (requires grouping)
                $groupedByApp = $signIns | Group-Object -Property AppId
                foreach ($group in $groupedByApp) {
                    if ($activityMap.ContainsKey($group.Name)) {
                        $uniqueUsers = @($group.Group | Select-Object -ExpandProperty UserId -Unique)
                        $activityMap[$group.Name].UniqueUserCount = $uniqueUsers.Count
                    }
                }
            }
            catch {
                Write-Warning -Message "Failed to query batch $batchNum`: $PSItem"

                # If batch fails, it might be a filter limit issue
                # Could implement fallback to individual queries here
                if ($PSItem.Exception.Message -match 'BadRequest|InvalidFilter') {
                    Write-Warning -Message "Filter may have exceeded limits. Consider reducing BatchSize."
                }
            }
        }
    }

    end {
        # Return results
        $results = $activityMap.Values | Sort-Object -Property LastSignInDateTime -Descending
        Write-Verbose -Message "Returning activity data for $($results.Count) application(s)"
        $results
    }
}
