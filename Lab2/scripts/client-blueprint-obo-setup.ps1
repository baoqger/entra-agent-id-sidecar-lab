# =============================================================================
# Setup Blueprint for OBO Flow (PowerShell) — Lab2
# =============================================================================
# Following: https://blog.christianposta.com/entra-agent-id-agw/PART-2.html
#
# Steps:
#   1. Look up Blueprint application
#   2. Application ID URI (api://<blueprint-app-id>)
#   3. Delegated scope access_as_user on Blueprint
#   4. Client SPA requiredResourceAccess → Blueprint scope
#   5. Admin consent Client SPA → Blueprint (oauth2PermissionGrant)
#
# Usage:
#   .\client-blueprint-obo-setup.ps1
#   .\client-blueprint-obo-setup.ps1 -TenantId '...' -BlueprintAppId '...' ...
#   # Or omit parameters; reads from ..\sidecar\.env:
#   #   TENANT_ID, BLUEPRINT_APP_ID, AGENT_CLIENT_ID, CLIENT_SPA_APP_ID
# =============================================================================

param(
    [string]$TenantId,
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\sidecar\.env"),
    [string]$BlueprintAppId,
    [string]$AgentAppId,
    [string]$ClientSpaAppId
)

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

if (-not $BlueprintAppId) {
    $BlueprintAppId = Read-DotEnvKey -Path $EnvFile -Key "BLUEPRINT_APP_ID"
    if (-not $BlueprintAppId) {
        Write-Error "BLUEPRINT_APP_ID not found in $EnvFile and -BlueprintAppId was not provided"
        exit 1
    }
}

if (-not $AgentAppId) {
    $AgentAppId = Read-DotEnvKey -Path $EnvFile -Key "AGENT_CLIENT_ID"
    if (-not $AgentAppId) {
        Write-Error "AGENT_CLIENT_ID not found in $EnvFile and -AgentAppId was not provided"
        exit 1
    }
}

if (-not $ClientSpaAppId) {
    $ClientSpaAppId = Read-DotEnvKey -Path $EnvFile -Key "CLIENT_SPA_APP_ID"
    if (-not $ClientSpaAppId) {
        Write-Error "CLIENT_SPA_APP_ID not found in $EnvFile and -ClientSpaAppId was not provided"
        exit 1
    }
}

Write-Host ""
Write-Host "Setup Blueprint for OBO flow"
Write-Host "  .env:       $EnvFile"
Write-Host "  Tenant:     $TenantId"
Write-Host "  Blueprint:  $BlueprintAppId"
Write-Host "  Agent:      $AgentAppId"
Write-Host "  Client SPA: $ClientSpaAppId"
Write-Host ""

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Error "Install Microsoft Graph PowerShell: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    exit 1
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes @(
    "AgentIdentityBlueprint.ReadWrite.All",
    "Application.ReadWrite.All",
    "DelegatedPermissionGrant.ReadWrite.All"
) -TenantId $TenantId -NoWelcome
Write-Host "  Connected"
Write-Host ""

# Step 1: Get Blueprint
Write-Host "Step 1: Looking up Blueprint..."
$result = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/beta/applications?`$filter=appId eq '$BlueprintAppId'&`$select=id,displayName,identifierUris,api"

if (-not $result.value -or $result.value.Count -eq 0) {
    Write-Error "Blueprint application not found for appId $BlueprintAppId"
    exit 1
}

$blueprintApp = $result.value[0]
$blueprintObjectId = $blueprintApp.id

Write-Host "  Found: $($blueprintApp.displayName)"
Write-Host "  Object ID: $blueprintObjectId"
Write-Host "  Current URIs: $($blueprintApp.identifierUris -join ', ')"
$existingScopes = @($blueprintApp.api.oauth2PermissionScopes)
Write-Host "  Current scopes: $(($existingScopes | ForEach-Object { $_.value }) -join ', ')"
Write-Host ""

# Step 2: Application ID URI
$appIdUri = "api://$BlueprintAppId"
Write-Host "Step 2: Application ID URI -> $appIdUri"

if ($blueprintApp.identifierUris -contains $appIdUri) {
    Write-Host "  Already set"
} else {
    $body = @{ identifierUris = @($appIdUri) } | ConvertTo-Json
    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/beta/applications/$blueprintObjectId" `
        -Body $body -ContentType "application/json"
    Write-Host "  Set App ID URI"
}
Write-Host ""

# Step 3: access_as_user delegated scope
Write-Host "Step 3: Adding 'access_as_user' delegated scope..."

$hasAccessAsUser = $existingScopes | Where-Object { $_.value -eq "access_as_user" }

if ($hasAccessAsUser) {
    Write-Host "  Scope already exists (ID: $($hasAccessAsUser.id))"
} else {
    $newScopeId = (New-Guid).ToString()

    $body = @{
        api = @{
            oauth2PermissionScopes = @(
                @{
                    id                      = $newScopeId
                    adminConsentDescription = "Allow the application to access the agent on behalf of the signed-in user"
                    adminConsentDisplayName = "Access agent as user"
                    isEnabled               = $true
                    type                    = "User"
                    userConsentDescription  = "Allow the application to access the agent on your behalf"
                    userConsentDisplayName  = "Access agent as user"
                    value                   = "access_as_user"
                }
            )
        }
    } | ConvertTo-Json -Depth 5

    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/beta/applications/$blueprintObjectId" `
        -Body $body -ContentType "application/json"
    Write-Host "  Added scope (ID: $newScopeId)"
    Write-Host "  Full scope: $appIdUri/access_as_user"
}
Write-Host ""

# Step 4: API permission on Client SPA
Write-Host "Step 4: Client SPA requiredResourceAccess -> Blueprint access_as_user..."

$bpUpdated = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/beta/applications?`$filter=appId eq '$BlueprintAppId'&`$select=id,api"
$scopeId = ($bpUpdated.value[0].api.oauth2PermissionScopes | Where-Object { $_.value -eq "access_as_user" }).id

$spaResult = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$ClientSpaAppId'&`$select=id"
if (-not $spaResult.value -or $spaResult.value.Count -eq 0) {
    Write-Error "Client SPA application not found for appId $ClientSpaAppId"
    exit 1
}
$clientSpaObjectId = $spaResult.value[0].id

if ($scopeId -and $clientSpaObjectId) {
    $body = @{
        requiredResourceAccess = @(
            @{
                resourceAppId  = $BlueprintAppId
                resourceAccess = @(
                    @{
                        id   = $scopeId
                        type = "Scope"
                    }
                )
            }
        )
    } | ConvertTo-Json -Depth 5

    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/applications/$clientSpaObjectId" `
        -Body $body -ContentType "application/json"
    Write-Host "  Added API permission on Client SPA"
} else {
    Write-Error "Missing scopeId=$scopeId or clientSpaObjectId=$clientSpaObjectId"
    exit 1
}
Write-Host ""

# Step 5: Admin consent Client SPA -> Blueprint
Write-Host "Step 5: Admin consent Client SPA -> Blueprint..."

$blueprintSp = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$BlueprintAppId'&`$select=id"
$blueprintSpId = $blueprintSp.value[0].id

$clientSpaSp = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$ClientSpaAppId'&`$select=id"
$clientSpaSpId = $clientSpaSp.value[0].id

if ($clientSpaSpId -and $blueprintSpId) {
    try {
        $existingConsent = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$clientSpaSpId' and resourceId eq '$blueprintSpId'"

        if ($existingConsent.value.Count -gt 0) {
            Write-Host "  Admin consent already exists"
        } else {
            $body = @{
                clientId    = $clientSpaSpId
                consentType = "AllPrincipals"
                resourceId  = $blueprintSpId
                scope       = "access_as_user"
            } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" `
                -Body $body -ContentType "application/json"
            Write-Host "  Admin consent granted"
        }
    } catch {
        Write-Error "Admin consent failed: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Error "Could not find service principals (Client SPA: $clientSpaSpId, Blueprint: $blueprintSpId)"
    exit 1
}
Write-Host ""

Write-Host "OBO blueprint setup complete."
Write-Host "  Blueprint API: $appIdUri"
Write-Host "  OBO scope:     $appIdUri/access_as_user"
Write-Host ""
Write-Host "  MSAL.js scopes: ['$appIdUri/access_as_user']"
Write-Host "  User token (Tc) aud: $appIdUri"
Write-Host "  Agent app id (reference): $AgentAppId"
Write-Host ""