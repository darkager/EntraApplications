function Get-CredentialStatus {
    <#
    .SYNOPSIS
        Calculates credential expiration status.

    .DESCRIPTION
        Internal helper function that determines days remaining until expiration
        and categorizes the credential status.

    .PARAMETER EndDateTime
        The expiration date/time of the credential.

    .PARAMETER ReferenceDate
        The date to calculate from. Defaults to current date/time.

    .OUTPUTS
        PSCustomObject with DaysRemaining and Status properties.

    .NOTES
        Internal function - not exported.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Nullable[DateTime]]$EndDateTime,

        [Parameter()]
        [DateTime]$ReferenceDate = (Get-Date)
    )

    # Handle null end date (no expiration set)
    if ($null -eq $EndDateTime) {
        return [PSCustomObject]@{
            DaysRemaining      = $null
            DaysPastExpiration = $null
            Status             = 'NoExpiration'
        }
    }

    $daysDiff = ($EndDateTime - $ReferenceDate).Days

    # Calculate DaysRemaining and DaysPastExpiration
    if ($daysDiff -lt 0) {
        $daysRemaining = 0
        $daysPastExpiration = [Math]::Abs($daysDiff)
    }
    else {
        $daysRemaining = $daysDiff
        $daysPastExpiration = $null
    }

    $status = switch ($true) {
        ($daysDiff -lt 0) { 'Expired'; break }
        ($daysDiff -eq 0) { 'ExpiringToday'; break }
        ($daysDiff -le 30) { 'ExpiringSoon'; break }
        ($daysDiff -le 90) { 'ExpiringMedium'; break }
        default { 'Valid' }
    }

    [PSCustomObject]@{
        DaysRemaining      = $daysRemaining
        DaysPastExpiration = $daysPastExpiration
        Status             = $status
    }
}
