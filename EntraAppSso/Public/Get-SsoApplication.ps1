function Get-SsoApplication {
    <#
    .SYNOPSIS
        Gets service principals with their SSO configuration type.

    .DESCRIPTION
        Queries Entra ID for service principals and identifies their SSO configuration
        type (SAML, OIDC, Password, or None). Uses the preferredSingleSignOnMode property
        with fallback detection for older applications that don't have this property set.

    .PARAMETER SsoType
        Filter results by SSO type. Valid values: All, SAML, OIDC, Password, None.
        Default is All.

    .PARAMETER ServicePrincipalId
        Optional. Specify one or more service principal Object IDs to query.
        If not specified, all service principals are queried.

    .PARAMETER ExcludeMicrosoft
        Exclude Microsoft first-party and Microsoft-managed service principals.
        This includes apps owned by Microsoft's tenant as well as Microsoft-managed
        apps registered in your tenant (e.g., P2P Server device RDP certificates).

    .PARAMETER IncludeNone
        Include service principals with no SSO configured.

    .EXAMPLE
        Get-SsoApplication

        Gets all service principals that have SSO configured (SAML, OIDC, or Password).

    .EXAMPLE
        Get-SsoApplication -SsoType SAML

        Gets only SAML-configured service principals.

    .EXAMPLE
        Get-SsoApplication -SsoType OIDC -ExcludeMicrosoft

        Gets OIDC-configured apps excluding Microsoft first-party applications.

    .EXAMPLE
        Get-SsoApplication -IncludeNone

        Gets all service principals including those without SSO configured.

    .OUTPUTS
        PSCustomObject with properties:
        - DisplayName, ApplicationId, ObjectId
        - SsoType, SsoTypeSource, PreferredSingleSignOnMode
        - HasSamlSigningCert, SamlSigningCertCount, EarliestSamlCertExpiration
        - LoginUrl, ReplyUrlCount, ServicePrincipalType

    .NOTES
        Requires Microsoft.Graph.Applications module and Application.Read.All permission.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('All', 'SAML', 'OIDC', 'Password', 'None')]
        [String]$SsoType = 'All',

        [Parameter()]
        [String[]]$ServicePrincipalId,

        [Parameter()]
        [Switch]$ExcludeMicrosoft,

        [Parameter()]
        [Switch]$IncludeNone,

        [Parameter(DontShow)]
        [Int32]$ProgressParentId = -1
    )

    begin {
        Write-Verbose -Message "Starting Get-SsoApplication with SsoType filter: $SsoType"

        # Initialize result collection using List for O(n) performance
        $results = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

        # Microsoft tenant ID for filtering first-party apps
        $microsoftTenantId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

        # Load Microsoft-managed app definitions once for performance
        $microsoftAppDefinitions = $null
        if ($ExcludeMicrosoft) {
            $microsoftAppDefinitions = Get-MicrosoftAppDefinition
        }
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
            $skippedMicrosoftManaged = 0
            $skippedNoSso = 0
            $progressId = if ($ProgressParentId -ge 0) { $ProgressParentId + 1 } else { 1 }

            foreach ($sp in $servicePrincipals) {
                $processedCount++

                # Show progress
                $percentComplete = [Math]::Round(($processedCount / $spCount) * 100)
                $progressParams = @{
                    Id              = $progressId
                    Activity        = 'Processing SSO Applications'
                    Status          = "Service Principal $processedCount of $spCount"
                    CurrentOperation = $sp.DisplayName
                    PercentComplete = $percentComplete
                }
                if ($ProgressParentId -ge 0) {
                    $progressParams['ParentId'] = $ProgressParentId
                }
                Write-Progress @progressParams

                # Skip Microsoft first-party apps if requested (by tenant ownership)
                if ($ExcludeMicrosoft -and $sp.AppOwnerOrganizationId -eq $microsoftTenantId) {
                    $skippedMicrosoft++
                    Write-Verbose -Message "Skipping Microsoft first-party app: $($sp.DisplayName)"
                    continue
                }

                # Skip Microsoft-managed apps registered in customer tenant (e.g., P2P Server)
                if ($ExcludeMicrosoft) {
                    $msCheck = Test-EntraAppMicrosoftManaged -ServicePrincipal $sp -Definitions $microsoftAppDefinitions
                    if ($msCheck.IsMicrosoftManaged) {
                        $skippedMicrosoftManaged++
                        Write-Verbose -Message "Skipping Microsoft-managed app ($($msCheck.MatchedDefinition)): $($sp.DisplayName)"
                        continue
                    }
                }

                # Resolve SSO type
                $ssoInfo = Resolve-SsoType -ServicePrincipal $sp

                # Filter by SSO type
                if ($SsoType -ne 'All' -and $ssoInfo.SsoType -ne $SsoType) {
                    continue
                }

                # Skip None unless explicitly included
                if ($ssoInfo.SsoType -eq 'None' -and -not $IncludeNone) {
                    $skippedNoSso++
                    continue
                }

                # Calculate earliest SAML cert expiration
                $earliestSamlCertExp = $null
                if ($ssoInfo.SamlCertExpirations.Count -gt 0) {
                    $earliestSamlCertExp = ($ssoInfo.SamlCertExpirations | Sort-Object | Select-Object -First 1)
                }

                # Join notification emails for CSV-friendly output
                $notificationEmails = if ($ssoInfo.NotificationEmailAddresses.Count -gt 0) {
                    $ssoInfo.NotificationEmailAddresses -join '; '
                } else {
                    ''
                }

                $appResult = [PSCustomObject]@{
                    DisplayName                 = $sp.DisplayName
                    ApplicationId               = $sp.AppId
                    ObjectId                    = $sp.Id
                    ServicePrincipalType        = $sp.ServicePrincipalType
                    SsoType                     = $ssoInfo.SsoType
                    SsoTypeSource               = $ssoInfo.SsoTypeSource
                    PreferredSingleSignOnMode   = $ssoInfo.PreferredSingleSignOnMode
                    HasSamlSigningCert          = $ssoInfo.HasSamlSigningCert
                    SamlSigningCertCount        = $ssoInfo.SamlSigningCertCount
                    EarliestSamlCertExpiration  = $earliestSamlCertExp
                    HasSamlSettings             = $ssoInfo.HasSamlSettings
                    HasNotificationEmails       = $ssoInfo.HasNotificationEmails
                    NotificationEmailAddresses  = $notificationEmails
                    LoginUrl                    = $ssoInfo.LoginUrl
                    LogoutUrl                   = $ssoInfo.LogoutUrl
                    ReplyUrlCount               = $ssoInfo.ReplyUrlCount
                    AppOwnerOrganizationId      = $sp.AppOwnerOrganizationId
                }

                $results.Add($appResult)

            }

            # Complete progress
            Write-Progress -Id $progressId -Activity 'Processing SSO Applications' -Completed

            if ($ExcludeMicrosoft) {
                Write-Verbose -Message "Skipped $skippedMicrosoft Microsoft first-party service principal(s)"
                Write-Verbose -Message "Skipped $skippedMicrosoftManaged Microsoft-managed service principal(s)"
            }
            if (-not $IncludeNone) {
                Write-Verbose -Message "Skipped $skippedNoSso service principal(s) with no SSO configured"
            }
        }
        catch {
            Write-Progress -Id $progressId -Activity 'Processing SSO Applications' -Completed
            Write-Error -Message "Failed to query service principals: $PSItem"
            throw
        }
    }

    end {
        Write-Verbose -Message "Found $($results.Count) service principal(s) matching criteria"
        $results
    }
}
