function Get-MicrosoftAppDefinition {
    <#
    .SYNOPSIS
        Returns definitions for identifying Microsoft-managed applications.

    .DESCRIPTION
        Provides a strongly-typed collection of Microsoft-managed application
        definitions that can be used to identify apps that should be excluded
        when using -ExcludeMicrosoft. Each definition includes primary identifiers
        and optional secondary validation logic.

        This approach allows for extensible identification of Microsoft apps
        that may not be caught by the standard AppOwnerOrganizationId check
        (e.g., P2P Server which is registered under the customer's tenant).

    .OUTPUTS
        System.Collections.Generic.List[PSCustomObject] containing app definitions.

    .EXAMPLE
        $definitions = Get-MicrosoftAppDefinition
        foreach ($def in $definitions) {
            Write-Host "App: $($def.AppName)"
        }

    .NOTES
        Internal function - not exported from module.

        Each definition contains:
        - AppName: Display name for logging/identification
        - AppDescription: Brief description of the app's purpose
        - PrimaryIdentifiers: List of values to check in servicePrincipalNames
        - SecondaryValidation: Optional additional validation when name differs

        Secondary validation types:
        - Regex: Pattern match against a property value
        - Equals: Exact match against a property value
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param()

    # Use strongly-typed List for O(n) performance
    $definitions = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

    # P2P Server - Microsoft-managed RDP certificates for device-to-device connections
    # Reference: https://learn.microsoft.com/en-us/entra/identity/devices/faq
    $p2pServer = [PSCustomObject]@{
        AppName              = 'P2P Server'
        AppDescription       = 'Microsoft-managed RDP certificates for Entra ID joined device connections'
        PrimaryIdentifiers   = [System.Collections.Generic.List[String]]@(
            'urn:p2p_cert'
        )
        SecondaryValidation  = [PSCustomObject]@{
            PropertyName     = 'KeyCredentials.DisplayName'
            ValidationType   = 'Regex'
            ValidationValue  = '^CN=MS-Organization-P2P-Access \[\d{4}\]$'
            Description      = 'Certificate naming pattern for P2P Access certificates'
        }
    }
    $definitions.Add($p2pServer)

    # Return the definitions
    $definitions
}
