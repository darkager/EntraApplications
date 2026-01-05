@{
    # Script module or binary module file associated with this manifest
    RootModule        = 'EntraAppSso.psm1'

    # Version number of this module
    ModuleVersion     = '0.3.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID              = '055a8029-1315-4d5a-8398-fcc8b3d4406e'

    # Author of this module
    Author            = 'Your Name'

    # Company or vendor of this module
    CompanyName       = 'Your Company'

    # Copyright statement for this module
    Copyright         = '(c) 2026. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'PowerShell module to identify and report on SSO-configured applications (SAML, OIDC, Password) in Entra ID.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @(
        @{
            ModuleName    = 'Microsoft.Graph.Applications'
            ModuleVersion = '2.0.0'
        }
    )

    # Functions to export from this module, for best performance, do not use wildcards
    FunctionsToExport = @(
        'Get-SsoApplication'
        'Export-EntraSsoReport'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            # Tags applied to this module for discoverability
            Tags         = @('EntraID', 'AzureAD', 'SSO', 'SAML', 'OIDC', 'SingleSignOn', 'MicrosoftGraph')

            # A URL to the license for this module
            # LicenseUri = ''

            # A URL to the main website for this project
            # ProjectUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
v0.3.0 - Regenerated module GUID for proper module identity.
v0.2.1 - Fixed -ExcludeMicrosoft to properly filter Microsoft-managed apps like P2P Server that are registered in customer tenant.
v0.2.0 - Added progress bar display with parent-child support. Added -ProgressParentId parameter for nested progress scenarios. Changed to explicit function exports.
v0.1.0 - Initial release. Identify and report on SSO-configured applications (SAML, OIDC, Password).
'@

            # Prerelease string of this module
            # Prerelease = ''
        }
    }
}
