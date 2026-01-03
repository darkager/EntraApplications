function Resolve-SsoType {
    <#
    .SYNOPSIS
        Determines the SSO type for a service principal.

    .DESCRIPTION
        Internal helper function that determines the SSO configuration type
        for a service principal using the preferredSingleSignOnMode property
        with fallback detection for older applications.

        Detection priority:
        1. preferredSingleSignOnMode property (definitive when set)
        2. SAML signing certificate detection (fallback for older SAML apps)
        3. Inference based on other properties

    .PARAMETER ServicePrincipal
        The service principal object from Get-MgServicePrincipal.

    .OUTPUTS
        PSCustomObject with SsoType, SsoTypeSource, and detection details.

    .NOTES
        Internal function - not exported.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [Object]$ServicePrincipal
    )

    $sp = $ServicePrincipal

    # Initialize detection result
    $result = [PSCustomObject]@{
        SsoType                    = 'None'
        SsoTypeSource              = 'Default'
        PreferredSingleSignOnMode  = $sp.PreferredSingleSignOnMode
        HasSamlSigningCert         = $false
        SamlSigningCertCount       = 0
        SamlCertExpirations        = @()
        HasSamlSettings            = $false
        HasNotificationEmails      = $false
        NotificationEmailAddresses = @()
        LoginUrl                   = $sp.LoginUrl
        LogoutUrl                  = $sp.LogoutUrl
        ReplyUrlCount              = @($sp.ReplyUrls).Count
    }

    # Check for SAML signing certificates (type=AsymmetricX509Cert, usage=Sign)
    $samlSigningCerts = @($sp.KeyCredentials | Where-Object -FilterScript {
        $PSItem.Type -eq 'AsymmetricX509Cert' -and $PSItem.Usage -eq 'Sign'
    })

    if ($samlSigningCerts.Count -gt 0) {
        $result.HasSamlSigningCert = $true
        $result.SamlSigningCertCount = $samlSigningCerts.Count
        $result.SamlCertExpirations = @($samlSigningCerts | ForEach-Object -Process { $PSItem.EndDateTime })
    }

    # Check for SAML settings
    if ($null -ne $sp.SamlSingleSignOnSettings -and $null -ne $sp.SamlSingleSignOnSettings.RelayState) {
        $result.HasSamlSettings = $true
    }

    # Check for notification emails (SAML cert expiry notifications)
    if ($null -ne $sp.NotificationEmailAddresses -and @($sp.NotificationEmailAddresses).Count -gt 0) {
        $result.HasNotificationEmails = $true
        $result.NotificationEmailAddresses = @($sp.NotificationEmailAddresses)
    }

    # Priority 1: Use preferredSingleSignOnMode if set
    if (-not [String]::IsNullOrEmpty($sp.PreferredSingleSignOnMode)) {
        switch ($sp.PreferredSingleSignOnMode.ToLower()) {
            'saml' {
                $result.SsoType = 'SAML'
                $result.SsoTypeSource = 'PreferredMode'
            }
            'oidc' {
                $result.SsoType = 'OIDC'
                $result.SsoTypeSource = 'PreferredMode'
            }
            'password' {
                $result.SsoType = 'Password'
                $result.SsoTypeSource = 'PreferredMode'
            }
            'notsupported' {
                $result.SsoType = 'NotSupported'
                $result.SsoTypeSource = 'PreferredMode'
            }
            default {
                $result.SsoType = 'Unknown'
                $result.SsoTypeSource = 'PreferredMode'
            }
        }
        return $result
    }

    # Priority 2: Fallback detection for SAML (older apps without preferredSingleSignOnMode)
    if ($result.HasSamlSigningCert) {
        $result.SsoType = 'SAML'
        $result.SsoTypeSource = 'SigningCertificate'
        return $result
    }

    # Additional SAML indicators
    if ($result.HasSamlSettings -or $result.HasNotificationEmails) {
        $result.SsoType = 'SAML'
        $result.SsoTypeSource = 'SamlIndicators'
        return $result
    }

    # Priority 3: No SSO configured
    $result.SsoType = 'None'
    $result.SsoTypeSource = 'NoIndicators'

    $result
}
