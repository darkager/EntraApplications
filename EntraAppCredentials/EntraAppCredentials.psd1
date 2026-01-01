@{
    # Script module or binary module file associated with this manifest
    RootModule        = 'EntraAppCredentials.psm1'

    # Version number of this module
    ModuleVersion     = '0.1.1'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID              = '13166fde-cb50-4182-bd51-7823553a137b'

    # Author of this module
    Author            = 'Your Name'

    # Company or vendor of this module
    CompanyName       = 'Your Company'

    # Copyright statement for this module
    Copyright         = '(c) 2025. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'PowerShell module to query and report on expiring credentials (secrets and certificates) for Entra ID applications and service principals.'

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
        'Get-ExpiringAppCredential'
        'Get-ExpiringSpCredential'
        'Export-CredentialReport'
        'Clear-CredentialOwnerCache'
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
            Tags         = @('EntraID', 'AzureAD', 'Credentials', 'Certificates', 'Secrets', 'Expiration', 'MicrosoftGraph')

            # A URL to the license for this module
            # LicenseUri = ''

            # A URL to the main website for this project
            # ProjectUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'v0.1.1 - Reorganized module directory structure and updated documentation.'

            # Prerelease string of this module
            # Prerelease = ''
        }
    }
}
