# EntraApplications

PowerShell modules for managing and reporting on Entra ID (Azure AD) applications and service principals.

## Modules

| Module | Purpose |
|--------|---------|
| [EntraAppCredentials](#entraappcredentials-module) | Query and report on expiring credentials (secrets and certificates) |
| [EntraAppSso](#entraappsso-module) | Identify and report on SSO-configured applications (SAML, OIDC, Password) |

## Common Requirements

All modules in this repository share these requirements:

- PowerShell 5.1 or later (Desktop or Core)
- Microsoft.Graph.Applications module (v2.0.0 or later)
- Microsoft Graph permissions: `Application.Read.All`

### Installation

1. Install the Microsoft.Graph.Applications module:

```powershell
Install-Module -Name Microsoft.Graph.Applications -MinimumVersion 2.0.0
```

2. Copy the desired module folder(s) to a location in your `$env:PSModulePath`

3. Import the module:

```powershell
Import-Module EntraAppCredentials
Import-Module EntraAppSso
```

### Authentication

Connect to Microsoft Graph before using any module:

```powershell
Connect-MgGraph -Scopes 'Application.Read.All'
```

---

## EntraAppCredentials Module

Query and report on expiring credentials (secrets and certificates) for Entra ID applications and service principals.

### Overview

This module helps administrators identify and track credentials that are expiring or have already expired across:

- **Applications** (App Registrations) - Client secrets and certificates
- **Service Principals** (Enterprise Applications) - Client secrets, certificates, and SAML signing certificates

### Functions

#### Get-ExpiringAppCredential

Queries Entra ID for application registrations with expiring or expired credentials.

```powershell
# Get all credentials expiring in the next 30 days (default)
Get-ExpiringAppCredential

# Get credentials expiring in the next 90 days, excluding already expired
Get-ExpiringAppCredential -DaysUntilExpiration 90 -IncludeExpired $false

# Query a specific application
Get-ExpiringAppCredential -ApplicationId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# Skip owner lookup for faster execution
Get-ExpiringAppCredential -IncludeOwners $false
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| DaysUntilExpiration | Int32 | 30 | Days to look ahead for expiring credentials |
| IncludeExpired | Bool | $true | Include already expired credentials |
| IncludeOwners | Bool | $true | Include owner information |
| ApplicationId | String[] | - | Specific application Object IDs to query |

#### Get-ExpiringSpCredential

Queries Entra ID for service principals with expiring or expired credentials, including SAML signing certificates.

```powershell
# Get all service principal credentials expiring in the next 30 days
Get-ExpiringSpCredential

# Exclude Microsoft first-party applications
Get-ExpiringSpCredential -ExcludeMicrosoft

# Query specific service principals
Get-ExpiringSpCredential -ServicePrincipalId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| DaysUntilExpiration | Int32 | 30 | Days to look ahead for expiring credentials |
| IncludeExpired | Bool | $true | Include already expired credentials |
| IncludeOwners | Bool | $true | Include owner information |
| ServicePrincipalId | String[] | - | Specific service principal Object IDs to query |
| ExcludeMicrosoft | Switch | - | Exclude Microsoft first-party and Microsoft-managed apps (including P2P Server) |
| ExcludeManagedIdentity | Switch | - | Exclude Managed Identity service principals (auto-rotated) |

#### Export-EntraCredentialReport

Exports a combined credential report from both applications and service principals to CSV.

```powershell
# Export all expiring credentials to a timestamped CSV in current directory
Export-EntraCredentialReport

# Export to a directory (auto-generates filename)
Export-EntraCredentialReport -OutputPath 'C:\Reports'

# Export to a specific file with 90-day threshold
Export-EntraCredentialReport -OutputPath 'C:\Reports\credentials.csv' -DaysUntilExpiration 90

# Exclude Microsoft apps and Managed Identities
Export-EntraCredentialReport -ExcludeMicrosoft -ExcludeManagedIdentity -PassThru

# Export only applications (no service principals)
Export-EntraCredentialReport -IncludeServicePrincipals $false
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| OutputPath | String | Auto-generated | Directory or CSV file path. Auto-generates timestamped filename if directory. |
| DaysUntilExpiration | Int32 | 30 | Days to look ahead |
| IncludeExpired | Bool | $true | Include expired credentials |
| IncludeApplications | Bool | $true | Include app registrations |
| IncludeServicePrincipals | Bool | $true | Include enterprise apps |
| ExcludeMicrosoft | Switch | - | Exclude Microsoft first-party and Microsoft-managed apps (including P2P Server) |
| ExcludeManagedIdentity | Switch | - | Exclude Managed Identity service principals (auto-rotated) |
| ExcludeOwners | Switch | - | Exclude owner information (faster execution) |
| PassThru | Switch | - | Return objects in addition to CSV export |

#### Clear-CredentialOwnerCache

Clears the module's internal owner cache.

```powershell
Clear-CredentialOwnerCache
```

### Output Properties

#### Common Credential Properties

| Property | Description |
|----------|-------------|
| DisplayName | Display name of the application or service principal |
| ApplicationId | Application (client) ID |
| ObjectId | Object ID of the application or service principal |
| ObjectType | "Application" or "ServicePrincipal" |
| ServicePrincipalType | Type (Application, ManagedIdentity, etc.) - service principals only |
| CredentialType | "Secret", "Certificate", or "SAMLSigningCertificate" |
| CredentialName | Display name of the credential |
| KeyId | Unique identifier for the credential |
| Hint | Secret hint (first few characters) - secrets only |
| StartDate | When the credential became valid |
| EndDate | When the credential expires |
| DaysRemaining | Days until expiration (0 if expired) |
| DaysPastExpiration | Days past expiration (null if not expired) |
| Status | Expired, ExpiringToday, ExpiringSoon, ExpiringMedium, Valid |
| CertificateType | Certificate type - certificates only |
| CertificateUsage | Certificate usage - certificates only |
| Owner | Owner display names (semicolon-separated) |
| OwnerUpns | Owner UPNs (semicolon-separated) |
| OwnerIds | Owner Object IDs (semicolon-separated) |

### Status Values

| Status | Description |
|--------|-------------|
| Expired | Credential has already expired |
| ExpiringToday | Credential expires today |
| ExpiringSoon | Expires within 30 days |
| ExpiringMedium | Expires within 31-90 days |
| Valid | Expires in more than 90 days |
| NoExpiration | No expiration date set |

### Examples

#### Weekly Expiration Report

```powershell
Connect-MgGraph -Scopes 'Application.Read.All'

Export-EntraCredentialReport -DaysUntilExpiration 60 -OutputPath 'C:\Reports'

Disconnect-MgGraph
```

#### Find All Expired Credentials

```powershell
$expired = Export-EntraCredentialReport -PassThru |
    Where-Object -FilterScript { $PSItem.Status -eq 'Expired' }

$expired | Format-Table -Property DisplayName, CredentialType, EndDate, Owner
```

#### Monitor Specific Applications

```powershell
$appIds = @(
    'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
    'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
)

Get-ExpiringAppCredential -ApplicationId $appIds -DaysUntilExpiration 90
```

### Microsoft-Managed Application Detection

The `-ExcludeMicrosoft` switch excludes both:
1. **Microsoft first-party apps** - Apps owned by Microsoft's tenant (`f8cdef31-a31e-4b4a-93e4-5f571e91255a`)
2. **Microsoft-managed apps** - Apps registered in your tenant but managed by Microsoft (e.g., P2P Server)

Microsoft-managed app detection uses an extensible definition framework (`Get-MicrosoftAppDefinition`) with validation logic:

| Definition | Primary Identifier | Secondary Validation |
|------------|-------------------|---------------------|
| P2P Server | `urn:p2p_cert` in servicePrincipalNames | Certificate pattern: `CN=MS-Organization-P2P-Access [YYYY]` |

**P2P Server**: Automatically created when devices are Entra ID joined. Manages RDP certificates for device-to-device connections.

The validation logic requires BOTH conditions to match:
- Primary identifier found in `servicePrincipalNames`
- Secondary validation passes (e.g., certificate naming pattern matches)

This prevents false positives from coincidentally named applications.

Reference: [Microsoft Entra device management FAQ](https://learn.microsoft.com/en-us/entra/identity/devices/faq)

### Performance Notes

- The module uses strongly-typed .NET collections (`List[T]`, `Dictionary[TKey,TValue]`) for O(n) performance
- Owner information is cached per object to minimize API calls
- Microsoft-managed app definitions are loaded once per query for efficiency
- Use `-ExcludeOwners` for faster execution when owner data is not needed
- Use `-ExcludeMicrosoft` to skip Microsoft first-party and Microsoft-managed apps
- Use `-ExcludeManagedIdentity` to skip auto-rotated Managed Identity credentials

### Changelog

#### v0.4.0 (2026-01-05)

- Regenerated module GUID for proper module identity

#### v0.3.0 (2026-01-05)

- Standardized output property to `DisplayName` (was ApplicationName/ServicePrincipalName)
- Added progress bar display with parent-child support
- Added `-ProgressParentId` parameter for nested progress scenarios

#### v0.2.0 (2026-01-01)

- Renamed `Export-CredentialReport` to `Export-EntraCredentialReport`
- Changed `ExcludeMicrosoft` to Switch parameter
- Improved `OutputPath` handling

#### v0.1.1 (2026-01-01)

- Reorganized module directory structure
- Updated documentation

#### v0.1.0 (2025-12-31)

- Initial release
- `Get-ExpiringAppCredential` - Query application credentials
- `Get-ExpiringSpCredential` - Query service principal credentials with SAML signing certificate detection
- `Export-EntraCredentialReport` - Combined CSV export with status summary
- `Clear-CredentialOwnerCache` - Cache management
- Owner resolution with caching for performance
- Microsoft first-party app filtering for service principals
- `DaysPastExpiration` property for expired credentials

---

## EntraAppSso Module

Identify and report on SSO-configured applications (SAML, OIDC, Password) in Entra ID.

### Overview

This module helps administrators discover which service principals have SSO configured and identify the SSO type:

| SSO Type | Protocol | Description |
|----------|----------|-------------|
| **SAML** | SAML 2.0 | Token-based federation using SAML assertions |
| **OIDC** | OpenID Connect | Token-based federation using OAuth 2.0 / JWT |
| **Password** | Form-fill | Credential vaulting - Entra ID stores and replays user credentials |

### SSO Type Detection

The `preferredSingleSignOnMode` property on service principals explicitly identifies the SSO type. However, this property can be `null` for:
- Older SAML applications (pre-dating this property)
- OIDC applications where it wasn't explicitly set

The module uses a priority-based detection approach to handle these cases:

| Priority | Source | Method |
|----------|--------|--------|
| 1 | `PreferredMode` | Uses `preferredSingleSignOnMode` property when set (definitive) |
| 2 | `SigningCertificate` | Detects SAML by presence of signing certificates (`type=AsymmetricX509Cert`, `usage=Sign`) |
| 3 | `SamlIndicators` | Detects SAML settings or notification email addresses |

The `SsoTypeSource` output property indicates which detection method was used.

### Functions

#### Get-SsoApplication

Queries service principals and identifies their SSO configuration type.

```powershell
# Get all SSO-configured applications (SAML, OIDC, or Password)
Get-SsoApplication

# Get only SAML applications
Get-SsoApplication -SsoType SAML

# Get only OIDC applications
Get-SsoApplication -SsoType OIDC

# Get only Password SSO applications
Get-SsoApplication -SsoType Password

# Exclude Microsoft first-party applications
Get-SsoApplication -ExcludeMicrosoft

# Include apps with no SSO configured
Get-SsoApplication -IncludeNone

# Query specific service principals
Get-SsoApplication -ServicePrincipalId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| SsoType | String | All | Filter by SSO type: All, SAML, OIDC, Password, None |
| ServicePrincipalId | String[] | - | Specific service principal Object IDs to query |
| ExcludeMicrosoft | Switch | - | Exclude Microsoft first-party and Microsoft-managed apps (including P2P Server) |
| IncludeNone | Switch | - | Include apps with no SSO configured |

#### Export-EntraSsoReport

Exports an SSO configuration report to CSV with summary statistics.

```powershell
# Export all SSO applications to a timestamped CSV
Export-EntraSsoReport

# Export to a directory (auto-generates filename)
Export-EntraSsoReport -OutputPath 'C:\Reports'

# Export only SAML applications to a specific file
Export-EntraSsoReport -OutputPath 'C:\Reports\SamlApps.csv' -SsoType SAML

# Export only OIDC applications
Export-EntraSsoReport -SsoType OIDC

# Export only Password SSO applications
Export-EntraSsoReport -SsoType Password

# Exclude Microsoft first-party apps
Export-EntraSsoReport -ExcludeMicrosoft

# Export and return objects for further processing
$report = Export-EntraSsoReport -PassThru
$report | Where-Object -FilterScript { $PSItem.SsoType -eq 'SAML' }

# Include apps with no SSO for a complete inventory
Export-EntraSsoReport -IncludeNone
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| OutputPath | String | Auto-generated | Directory or CSV file path. Auto-generates timestamped filename if directory. |
| SsoType | String | All | Filter by SSO type: All, SAML, OIDC, Password |
| ExcludeMicrosoft | Switch | - | Exclude Microsoft first-party and Microsoft-managed apps (including P2P Server) |
| IncludeNone | Switch | - | Include apps with no SSO configured |
| PassThru | Switch | - | Return objects in addition to CSV export |

### Output Properties

| Property | Description |
|----------|-------------|
| DisplayName | Service principal display name |
| ApplicationId | Application (client) ID |
| ObjectId | Service principal Object ID |
| ServicePrincipalType | Type (Application, ManagedIdentity, etc.) |
| SsoType | SAML, OIDC, Password, None, or NotSupported |
| SsoTypeSource | Detection method: PreferredMode, SigningCertificate, SamlIndicators, NoIndicators |
| PreferredSingleSignOnMode | Raw value from Graph API (may be null) |
| HasSamlSigningCert | Whether SAML signing certificate exists |
| SamlSigningCertCount | Number of SAML signing certificates |
| EarliestSamlCertExpiration | Earliest SAML certificate expiration date |
| HasSamlSettings | Whether SAML settings (relay state) are configured |
| HasNotificationEmails | Whether certificate expiry notification emails are configured |
| NotificationEmailAddresses | Email addresses receiving SAML certificate expiry notifications (semicolon-separated) |
| LoginUrl | SP-initiated login URL |
| LogoutUrl | Logout URL |
| ReplyUrlCount | Number of reply/redirect URLs configured |
| AppOwnerOrganizationId | Owning tenant ID (used to identify Microsoft first-party apps) |

### SSO Type Values

| SsoType | Description |
|---------|-------------|
| SAML | SAML 2.0 single sign-on configured |
| OIDC | OpenID Connect single sign-on configured |
| Password | Password vaulting/form-fill SSO configured |
| None | No SSO configured |
| NotSupported | SSO explicitly marked as not supported |
| Unknown | `preferredSingleSignOnMode` set to unrecognized value |

### Examples

#### Inventory All SSO Applications

```powershell
Connect-MgGraph -Scopes 'Application.Read.All'

Export-EntraSsoReport -OutputPath 'C:\Reports\SsoInventory.csv'

Disconnect-MgGraph
```

#### Find SAML Apps with Expiring Certificates

```powershell
$samlApps = Get-SsoApplication -SsoType SAML

$expiringCerts = $samlApps | Where-Object -FilterScript {
    $PSItem.HasSamlSigningCert -and
    $PSItem.EarliestSamlCertExpiration -lt (Get-Date).AddDays(30)
}

$expiringCerts | Format-Table -Property DisplayName, EarliestSamlCertExpiration
```

#### Compare SSO Types Across Your Tenant

```powershell
$allSso = Get-SsoApplication

# Summary by SSO type
$allSso | Group-Object -Property SsoType |
    Select-Object -Property Name, Count |
    Sort-Object -Property Count -Descending

# Summary by detection source
$allSso | Group-Object -Property SsoTypeSource |
    Select-Object -Property Name, Count
```

#### Find Legacy SAML Apps (detected via certificate, not preferredSingleSignOnMode)

```powershell
Get-SsoApplication -SsoType SAML |
    Where-Object -FilterScript { $PSItem.SsoTypeSource -ne 'PreferredMode' } |
    Format-Table -Property DisplayName, SsoTypeSource, PreferredSingleSignOnMode
```

#### Audit Password SSO Applications

```powershell
# Password SSO apps store credentials - may want to review these
Get-SsoApplication -SsoType Password |
    Format-Table -Property DisplayName, ApplicationId, LoginUrl
```

### Microsoft-Managed Application Detection

The `-ExcludeMicrosoft` switch excludes both:
1. **Microsoft first-party apps** - Apps owned by Microsoft's tenant (`f8cdef31-a31e-4b4a-93e4-5f571e91255a`)
2. **Microsoft-managed apps** - Apps registered in your tenant but managed by Microsoft (e.g., P2P Server)

This uses the same extensible detection framework as the EntraAppCredentials module. See [Microsoft-Managed Application Detection](#microsoft-managed-application-detection) in the EntraAppCredentials section for details.

### Changelog

#### v0.3.0 (2026-01-05)

- Regenerated module GUID for proper module identity

#### v0.2.1 (2026-01-05)

- Fixed `-ExcludeMicrosoft` to properly filter Microsoft-managed apps like P2P Server that are registered in customer tenant

#### v0.2.0 (2026-01-05)

- Added progress bar display with parent-child support
- Added `-ProgressParentId` parameter for nested progress scenarios
- Changed to explicit function exports in module loader

#### v0.1.0 (2026-01-01)

- Initial release
- `Get-SsoApplication` - Query and identify SSO configuration types
- `Export-EntraSsoReport` - CSV export with SSO type summary
- SSO type detection with fallback for older SAML applications
- Support for SAML, OIDC, and Password SSO types

---

## License

MIT License
