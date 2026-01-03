#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
    EntraAppSso module loader.

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

# Export public functions
Export-ModuleMember -Function @(
    'Get-SsoApplication'
    'Export-EntraSsoReport'
)
