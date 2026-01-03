function Test-EntraAppMicrosoftManaged {
    <#
    .SYNOPSIS
        Tests whether a service principal is a Microsoft-managed application.

    .DESCRIPTION
        Evaluates a service principal against known Microsoft-managed application
        definitions to determine if it should be excluded when using -ExcludeMicrosoft.

        This function handles edge cases where Microsoft-managed apps are registered
        under the customer's tenant (e.g., P2P Server) rather than Microsoft's tenant.

        Validation logic:
        1. Check if servicePrincipalNames contains any primary identifier
        2. If primary identifier found AND secondary validation passes -> match

        Both primary identifier AND secondary validation are required to prevent
        false positives from coincidentally named applications.

    .PARAMETER ServicePrincipal
        The service principal object from Get-MgServicePrincipal.

    .PARAMETER Definitions
        Optional. Collection of Microsoft app definitions from Get-MicrosoftAppDefinition.
        If not provided, definitions are loaded automatically.

    .OUTPUTS
        PSCustomObject with:
        - IsMicrosoftManaged: Boolean indicating if this is a Microsoft-managed app
        - MatchedDefinition: The definition that matched (if any)
        - MatchReason: Description of why this was identified as Microsoft-managed

    .EXAMPLE
        $sp = Get-MgServicePrincipal -ServicePrincipalId $id
        $result = Test-EntraAppMicrosoftManaged -ServicePrincipal $sp
        if ($result.IsMicrosoftManaged) { Write-Host "Skipping: $($result.MatchReason)" }

    .NOTES
        Internal function - not exported from module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [Object]$ServicePrincipal,

        [Parameter()]
        [System.Collections.Generic.List[PSCustomObject]]$Definitions
    )

    $sp = $ServicePrincipal

    # Load definitions if not provided
    if ($null -eq $Definitions -or $Definitions.Count -eq 0) {
        $Definitions = Get-MicrosoftAppDefinition
    }

    # Check each definition
    foreach ($def in $Definitions) {
        # Check primary identifiers in servicePrincipalNames
        $hasPrimaryMatch = $false
        $matchedIdentifier = $null

        if ($null -ne $sp.ServicePrincipalNames) {
            foreach ($identifier in $def.PrimaryIdentifiers) {
                if ($sp.ServicePrincipalNames -contains $identifier) {
                    $hasPrimaryMatch = $true
                    $matchedIdentifier = $identifier
                    break
                }
            }
        }

        if (-not $hasPrimaryMatch) {
            continue
        }

        # Primary identifier found - now require secondary validation to confirm
        if ($null -eq $def.SecondaryValidation) {
            # No secondary validation defined - skip this definition
            # (Definitions should always have secondary validation for safety)
            continue
        }

        $secondaryMatch = $false
        $validation = $def.SecondaryValidation

        switch ($validation.ValidationType) {
            'Regex' {
                # Handle nested property paths like 'KeyCredentials.DisplayName'
                $propertyPath = $validation.PropertyName -split '\.'

                if ($propertyPath[0] -eq 'KeyCredentials' -and $propertyPath.Count -eq 2) {
                    $subProperty = $propertyPath[1]
                    if ($null -ne $sp.KeyCredentials -and $sp.KeyCredentials.Count -gt 0) {
                        $matchingItems = @($sp.KeyCredentials | Where-Object -FilterScript {
                            $PSItem.$subProperty -match $validation.ValidationValue
                        })
                        $secondaryMatch = $matchingItems.Count -gt 0
                    }
                }
                elseif ($propertyPath.Count -eq 1) {
                    $propValue = $sp.$($propertyPath[0])
                    if ($null -ne $propValue) {
                        $secondaryMatch = $propValue -match $validation.ValidationValue
                    }
                }
            }
            'Equals' {
                $propValue = $sp.$($validation.PropertyName)
                $secondaryMatch = $propValue -eq $validation.ValidationValue
            }
        }

        if ($secondaryMatch) {
            return [PSCustomObject]@{
                IsMicrosoftManaged = $true
                MatchedDefinition  = $def.AppName
                MatchReason        = "Primary identifier '$matchedIdentifier' with secondary validation: $($validation.Description)"
            }
        }
    }

    # No match found
    [PSCustomObject]@{
        IsMicrosoftManaged = $false
        MatchedDefinition  = $null
        MatchReason        = $null
    }
}
