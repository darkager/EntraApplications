# EntraApplications

PowerShell modules for managing and reporting on Entra ID (Azure AD) applications and service principals.

## EntraAppCredentials Module

Query and report on expiring credentials (secrets and certificates) for Entra ID applications and service principals.

### Overview

This module helps administrators identify and track credentials that are expiring or have already expired across:

- **Applications** (App Registrations) - Client secrets and certificates
- **Service Principals** (Enterprise Applications) - Client secrets, certificates, and SAML signing certificates

### Requirements

- PowerShell 5.1 or later (Desktop or Core)
- Microsoft.Graph.Applications module (v2.0.0 or later)
- Microsoft Graph permissions: `Application.Read.All`

### Installation

1. Install the Microsoft.Graph.Applications module:

```powershell
Install-Module -Name Microsoft.Graph.Applications -MinimumVersion 2.0.0
```

2. Copy the `EntraAppCredentials` folder to a location in your `$env:PSModulePath`

3. Import the module:

```powershell
Import-Module EntraAppCredentials
```

### Authentication

Connect to Microsoft Graph before using the module:

```powershell
Connect-MgGraph -Scopes 'Application.Read.All'
```

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
Get-ExpiringSpCredential -ExcludeMicrosoft $true

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
| ExcludeMicrosoft | Bool | $false | Exclude Microsoft first-party applications |

#### Export-CredentialReport

Exports a combined credential report from both applications and service principals to CSV.

```powershell
# Export all expiring credentials to a timestamped CSV
Export-CredentialReport

# Export to a specific file with 90-day threshold
Export-CredentialReport -OutputPath 'C:\Reports\credentials.csv' -DaysUntilExpiration 90

# Export and also return objects for further processing
$report = Export-CredentialReport -PassThru
$report | Where-Object -FilterScript { $PSItem.Status -eq 'Expired' }

# Export only applications (no service principals)
Export-CredentialReport -IncludeServicePrincipals $false
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| OutputPath | String | Auto-generated | CSV file path |
| DaysUntilExpiration | Int32 | 30 | Days to look ahead |
| IncludeExpired | Bool | $true | Include expired credentials |
| IncludeApplications | Bool | $true | Include app registrations |
| IncludeServicePrincipals | Bool | $true | Include enterprise apps |
| ExcludeMicrosoft | Bool | $false | Exclude Microsoft first-party apps |
| IncludeOwners | Bool | $true | Include owner information |
| PassThru | Switch | - | Return objects in addition to CSV export |

#### Clear-CredentialOwnerCache

Clears the module's internal owner cache.

```powershell
Clear-CredentialOwnerCache
```

### Output Properties

#### Application Credentials

| Property | Description |
|----------|-------------|
| ApplicationName | Display name of the application |
| ApplicationId | Application (client) ID |
| ObjectId | Object ID of the application |
| ObjectType | Always "Application" |
| CredentialType | "Secret" or "Certificate" |
| CredentialName | Display name of the credential |
| KeyId | Unique identifier for the credential |
| Hint | Secret hint (first few characters) |
| StartDate | When the credential became valid |
| EndDate | When the credential expires |
| DaysRemaining | Days until expiration (0 if expired) |
| DaysPastExpiration | Days past expiration (null if not expired) |
| Status | Expired, ExpiringToday, ExpiringSoon, ExpiringMedium, Valid |
| CertificateType | Certificate type (for certificates) |
| CertificateUsage | Certificate usage (for certificates) |
| Owner | Owner display names |
| OwnerUpns | Owner UPNs (semicolon-separated) |
| OwnerIds | Owner Object IDs (semicolon-separated) |

#### Service Principal Credentials

Same as application credentials, plus:

| Property | Description |
|----------|-------------|
| ServicePrincipalName | Display name of the service principal |
| ServicePrincipalType | Type (Application, ManagedIdentity, etc.) |
| CredentialType | "Secret", "Certificate", or "SAMLSigningCertificate" |

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
# Connect to Graph
Connect-MgGraph -Scopes 'Application.Read.All'

# Generate report for credentials expiring in the next 60 days
Export-CredentialReport -DaysUntilExpiration 60 -OutputPath 'C:\Reports\WeeklyCredentialReport.csv'

# Disconnect
Disconnect-MgGraph
```

#### Find All Expired Credentials

```powershell
$expired = Export-CredentialReport -PassThru |
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

### Performance Notes

- The module uses strongly-typed .NET collections (`List[T]`, `Dictionary[TKey,TValue]`) for O(n) performance
- Owner information is cached per object to minimize API calls
- Use `-IncludeOwners $false` for faster execution when owner data is not needed
- Use `-ExcludeMicrosoft $true` for service principals to skip first-party Microsoft apps

## Changelog

### v0.1.1 (2026-01-01)

- Reorganized module directory structure
- Updated documentation

### v0.1.0 (2025-12-31)

- Initial release
- `Get-ExpiringAppCredential` - Query application credentials
- `Get-ExpiringSpCredential` - Query service principal credentials with SAML signing certificate detection
- `Export-CredentialReport` - Combined CSV export with status summary
- `Clear-CredentialOwnerCache` - Cache management
- Owner resolution with caching for performance
- Microsoft first-party app filtering for service principals
- `DaysPastExpiration` property for expired credentials

## License

MIT License
