#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
    EntraAppCredentials module loader.

.DESCRIPTION
    Loads all public and private functions from the module directory.
    Public functions are exported; private functions remain internal.
#>

# Get public and private function definition files
$Public = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)

# Dot-source the files
foreach ($import in @($Public + $Private)) {
    try {
        . $import.FullName
        Write-Verbose -Message "Imported function: $($import.BaseName)"
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $PSItem"
    }
}

# Module-scoped variables for caching
$script:OwnerCache = New-Object -TypeName 'System.Collections.Generic.Dictionary[[String],[PSCustomObject]]'

<#
.SYNOPSIS
    Clears the module's internal owner cache.

.DESCRIPTION
    Use this function to clear cached owner lookups if you need fresh data
    without reimporting the module.
#>
function Clear-CredentialOwnerCache {
    [CmdletBinding()]
    param()

    $script:OwnerCache.Clear()
    Write-Verbose -Message 'Owner cache cleared.'
}

# Export the cache-clearing function
Export-ModuleMember -Function @(
    'Get-ExpiringAppCredential'
    'Get-ExpiringSpCredential'
    'Export-CredentialReport'
    'Clear-CredentialOwnerCache'
)
