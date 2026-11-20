# =============================================================================
# MSAL.js Client SPA app (Lab2 OBO)
# =============================================================================
# Steps:
#   1. Client SPA app registration (or reuse by display name)
#   2. SPA redirect URI
#   3. Service principal for the client SPA
#
# The user signs into this app in the browser, then the agent uses OBO with Tc.
#
# Prerequisites: Connect-MgGraph with Application.ReadWrite.All
#
# Usage:
#   .\client-spa-setup.ps1 -TenantId '<tenant-guid>'
#   .\client-spa-setup.ps1   # TENANT_ID from ..\sidecar\.env
#   -AppDisplayName optional; default is "Agent Demo Client SPA" + random 6-digit suffix
# =============================================================================

param(
    [string]$TenantId,
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\sidecar\.env"),
    [string]$AppDisplayName,
    [string]$RedirectUri = "http://localhost:3003"
)

$ClientSpaAppDisplayNamePrefix = 'Agent Client SPA'

function Read-DotEnvKey {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

if (-not $TenantId) {
    $TenantId = Read-DotEnvKey -Path $EnvFile -Key "TENANT_ID"
    if (-not $TenantId) {
        Write-Error "TENANT_ID not found in $EnvFile and -TenantId was not provided"
        exit 1
    }
}

$runSuffix = $null
if ([string]::IsNullOrWhiteSpace($AppDisplayName)) {
    $runSuffix = Get-Random -Minimum 100000 -Maximum 999999
    $AppDisplayName = "$ClientSpaAppDisplayNamePrefix $runSuffix"
}

Write-Host ""
Write-Host "Client SPA app setup (OBO)"
if ($runSuffix) {
    Write-Host "  Run suffix:  $runSuffix"
}
Write-Host "  Tenant:      $TenantId"
Write-Host "  DisplayName: $AppDisplayName"
Write-Host "  RedirectUri: $RedirectUri"
Write-Host ""

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Error @"
Microsoft Graph PowerShell SDK is not installed.

  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery
"@
    exit 1
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes @("Application.ReadWrite.All") -TenantId $TenantId -NoWelcome
Write-Host "  Connected"
Write-Host ""

# Step 1: App registration
Write-Host "Step 1: Client SPA app registration..."

$filterName = $AppDisplayName.Replace("'", "''")
$existing = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$filterName'&`$select=id,appId,displayName"

$clientSpaAppId = $null
if ($existing.value -and $existing.value.Count -gt 0) {
    $clientSpaAppId = $existing.value[0].appId
    Write-Host "  Already exists: $clientSpaAppId"
} else {
    $body = @{
        displayName    = $AppDisplayName
        signInAudience = "AzureADMyOrg"
        spa            = @{
            redirectUris = @($RedirectUri)
        }
    } | ConvertTo-Json -Depth 5

    $created = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/applications" `
        -Body $body -ContentType "application/json"

    $clientSpaAppId = $created.appId
    Write-Host "  Created: $clientSpaAppId"
    Start-Sleep -Seconds 5
}
Write-Host ""

# Step 2: SPA redirect URI
Write-Host "Step 2: SPA redirect URI -> $RedirectUri"

$spaBody = @{
    spa = @{
        redirectUris = @($RedirectUri)
    }
} | ConvertTo-Json -Depth 5

Invoke-MgGraphRequest -Method PATCH `
    -Uri "https://graph.microsoft.com/v1.0/applications(appId='$clientSpaAppId')" `
    -Body $spaBody -ContentType "application/json"
Write-Host "  Set redirect URI"
Write-Host ""

# Step 3: Service principal
Write-Host "Step 3: Client SPA service principal..."
$spResult = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$clientSpaAppId'&`$select=id"

if ($spResult.value -and $spResult.value.Count -gt 0) {
    Write-Host "  Already exists ($($spResult.value[0].id))"
} else {
    $spBody = @{ appId = $clientSpaAppId } | ConvertTo-Json
    $spCreated = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" `
        -Body $spBody -ContentType "application/json"
    Write-Host "  Created ($($spCreated.id))"
}
Write-Host ""

Write-Host "Done."
Write-Host "  Client SPA App ID: $clientSpaAppId"
Write-Host "  Redirect URI:      $RedirectUri"
Write-Host ""
Write-Host ""