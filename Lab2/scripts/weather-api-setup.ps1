# =============================================================================
# Weather API resource (custom audience) for Agent Identity — OBO (Lab2)
# =============================================================================
# Steps:
#   1. Weather API app registration (create or reuse)
#   2. Application ID URI (api://<appId>)
#   3. Delegated OAuth2 scope for OBO (e.g. weather.read)
#   4. Service principal for Weather API
#   5. Admin consent — Agent Identity SP → Weather API (oauth2PermissionGrant)
#
# Prerequisites:
#   - Agent Identity created (AGENT_CLIENT_ID in sidecar .env)
#   - Microsoft.Graph.Authentication (Connect-MgGraph)
#   - Application.ReadWrite.All, DelegatedPermissionGrant.ReadWrite.All
#
# Usage:
#   .\weather-api-setup.ps1 -TenantId '<tenant-guid>' -AgentAppId '<agent-app-id>'
#   .\weather-api-setup.ps1   # TENANT_ID and AGENT_CLIENT_ID from ..\sidecar\.env
# =============================================================================

param(
    [string]$TenantId,
    [string]$AgentAppId,
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\sidecar\.env"),
    [string]$WeatherApiAppId,
    [string]$AppDisplayName,
    [string]$DelegatedScopeValue = "weather.read"
)

$WeatherApiAppDisplayNamePrefix = 'Weather API'

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

function Format-GraphResourceUri {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Query
    )
    $uri = "https://graph.microsoft.com/v1.0/$Path"
    if ($Query) {
        $uri += "?$Query"
    }
    return $uri
}

function ConvertTo-GraphOAuth2Scope {
    param([Parameter(Mandatory = $true)]$Scope)
    return [ordered]@{
        adminConsentDescription = [string]$Scope.adminConsentDescription
        adminConsentDisplayName = [string]$Scope.adminConsentDisplayName
        id                      = [string]$Scope.id
        isEnabled               = [bool]$Scope.isEnabled
        type                    = [string]$Scope.type
        userConsentDescription  = [string]$Scope.userConsentDescription
        userConsentDisplayName  = [string]$Scope.userConsentDisplayName
        value                   = [string]$Scope.value
    }
}

if (-not $TenantId) {
    $TenantId = Read-DotEnvKey -Path $EnvFile -Key "TENANT_ID"
    if (-not $TenantId) {
        Write-Error "TENANT_ID not found in $EnvFile and -TenantId was not provided"
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

$runSuffix = $null
if ([string]::IsNullOrWhiteSpace($AppDisplayName)) {
    $runSuffix = Get-Random -Minimum 100000 -Maximum 999999
    $AppDisplayName = "$WeatherApiAppDisplayNamePrefix $runSuffix"
}

Write-Host ""
Write-Host "Weather API resource setup (OBO)"
if ($runSuffix) {
    Write-Host "  Run suffix: $runSuffix"
}
Write-Host "  App name:   $AppDisplayName"
Write-Host "  Tenant:     $TenantId"
Write-Host "  Agent:      $AgentAppId"
Write-Host "  .env:       $EnvFile"
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
Connect-MgGraph -Scopes @(
    "Application.ReadWrite.All",
    "DelegatedPermissionGrant.ReadWrite.All"
) -TenantId $TenantId -NoWelcome
Write-Host "  Connected"
Write-Host ""

# Step 1: Weather API app registration
Write-Host "Step 1: Weather API app registration..."

$weatherAppObjectId = $null
$weatherApiAppIdResolved = $WeatherApiAppId

if ($weatherApiAppIdResolved) {
    $appResult = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$weatherApiAppIdResolved'&`$select=id,appId,displayName,identifierUris"
    if (-not $appResult.value -or $appResult.value.Count -eq 0) {
        Write-Error "No application found for -WeatherApiAppId $weatherApiAppIdResolved"
        exit 1
    }
    $weatherApp = $appResult.value[0]
    Write-Host "  Using existing app: $($weatherApp.displayName) ($weatherApiAppIdResolved)"
} else {
    $filterName = $AppDisplayName.Replace("'", "''")
    $existing = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$filterName'&`$select=id,appId,displayName,identifierUris"

    if ($existing.value -and $existing.value.Count -gt 0) {
        $weatherApp = $existing.value[0]
        $weatherApiAppIdResolved = $weatherApp.appId
        Write-Host "  Found by display name: $weatherApiAppIdResolved"
    } else {
        Write-Host "  Creating: $AppDisplayName"
        $createBody = @{
            displayName    = $AppDisplayName
            signInAudience = "AzureADMyOrg"
        } | ConvertTo-Json
        $created = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/applications" `
            -Body $createBody -ContentType "application/json"
        $weatherAppObjectId = $created.id
        $weatherApiAppIdResolved = $created.appId
        $weatherApp = @{
            id             = $weatherAppObjectId
            appId          = $weatherApiAppIdResolved
            identifierUris = @()
        }
        Write-Host "  Created app ID: $weatherApiAppIdResolved"
        Start-Sleep -Seconds 5
    }
}

if (-not $weatherAppObjectId) {
    $weatherAppObjectId = $weatherApp.id
}
if (-not $weatherApiAppIdResolved) {
    $weatherApiAppIdResolved = $weatherApp.appId
}

$appIdUri = "api://$weatherApiAppIdResolved"

# Step 2: Application ID URI
Write-Host "Step 2: Application ID URI -> $appIdUri"
$currentUris = @($weatherApp.identifierUris)
if ($currentUris -notcontains $appIdUri) {
    $newUris = @($currentUris + $appIdUri | Select-Object -Unique)
    $body = @{ identifierUris = $newUris } | ConvertTo-Json
    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/applications/$weatherAppObjectId" `
        -Body $body -ContentType "application/json"
    Write-Host "  Set identifier URI"
} else {
    Write-Host "  Already set"
}
Write-Host ""

# Step 3: Delegated scope (OBO)
Write-Host "Step 3: Delegated scope '$DelegatedScopeValue' (OBO)..."

$apiGetUri = Format-GraphResourceUri -Path "applications/$weatherAppObjectId" -Query '$select=api'
$patchAppUri = Format-GraphResourceUri -Path "applications/$weatherAppObjectId"
$apiSnap = Invoke-MgGraphRequest -Method GET -Uri $apiGetUri
$existingScopes = @()
if ($apiSnap.api -and $apiSnap.api.oauth2PermissionScopes) {
    foreach ($s in @($apiSnap.api.oauth2PermissionScopes)) {
        if ($null -ne $s -and $s.value) { $existingScopes += $s }
    }
}

$scopeAlreadyExists = @($existingScopes | Where-Object { $_.value -eq $DelegatedScopeValue }).Count -gt 0

if ($scopeAlreadyExists) {
    Write-Host "  Delegated scope already exists"
} else {
    $newScope = [ordered]@{
        id                      = (New-Guid).ToString()
        adminConsentDescription = "Allow the agent to read weather on behalf of the signed-in user"
        adminConsentDisplayName = "Read weather as user"
        isEnabled               = $true
        type                    = "User"
        userConsentDescription  = "Allow the agent to read weather on your behalf"
        userConsentDisplayName  = "Read weather as user"
        value                   = $DelegatedScopeValue
    }
    $scopeByValue = [ordered]@{}
    foreach ($s in $existingScopes) {
        $scopeByValue[[string]$s.value] = ConvertTo-GraphOAuth2Scope -Scope $s
    }
    $scopeByValue[$DelegatedScopeValue] = ConvertTo-GraphOAuth2Scope -Scope $newScope
    $allScopes = @($scopeByValue.Values)

    $tokenVersion = 2
    if ($apiSnap.api -and $apiSnap.api.requestedAccessTokenVersion) {
        $tokenVersion = [int]$apiSnap.api.requestedAccessTokenVersion
    }
    $scopeBody = @{
        api = @{
            requestedAccessTokenVersion = $tokenVersion
            oauth2PermissionScopes      = $allScopes
        }
    } | ConvertTo-Json -Depth 12

    try {
        Invoke-MgGraphRequest -Method PATCH -Uri $patchAppUri -Body $scopeBody -ContentType "application/json"
        Write-Host "  Added scope $appIdUri/$DelegatedScopeValue"
        Start-Sleep -Seconds 5
    } catch {
        $detail = [string]$_.ErrorDetails.Message
        if ($detail -match 'DuplicateValue') {
            Write-Host "  Delegated scope already present in tenant (DuplicateValue)"
        } else {
            if ($detail) { Write-Host "  Graph: $detail" }
            Write-Error "Failed to add delegated scope: $($_.Exception.Message)"
            exit 1
        }
    }
}
Write-Host ""

# Step 4: Service principal for Weather API
Write-Host "Step 4: Weather API service principal..."
$spResult = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$weatherApiAppIdResolved'&`$select=id,appId"

if ($spResult.value -and $spResult.value.Count -gt 0) {
    $weatherSpId = $spResult.value[0].id
    Write-Host "  Already exists ($weatherSpId)"
} else {
    $spBody = @{ appId = $weatherApiAppIdResolved } | ConvertTo-Json
    $spCreated = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" `
        -Body $spBody -ContentType "application/json"
    $weatherSpId = $spCreated.id
    Write-Host "  Created ($weatherSpId)"
    Start-Sleep -Seconds 5
}
Write-Host ""

# Step 5: Admin consent — Agent → Weather API (OBO)
Write-Host "Step 5: Admin consent Agent -> Weather API (OBO)..."

$agentSpResult = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AgentAppId'&`$select=id,displayName"

if (-not $agentSpResult.value -or $agentSpResult.value.Count -eq 0) {
    Write-Error "Agent service principal not found for appId $AgentAppId. Create an agent identity first."
    exit 1
}

$agentSpId = $agentSpResult.value[0].id
Write-Host "  Agent SP: $($agentSpResult.value[0].displayName) ($agentSpId)"

try {
    $grantFilter = "clientId eq '$agentSpId' and resourceId eq '$weatherSpId'"
    $existingGrant = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=$grantFilter"
    $grant = $null
    if ($existingGrant.value -and $existingGrant.value.Count -gt 0) {
        $grant = $existingGrant.value[0]
    }
    if ($grant -and ($grant.scope -split '\s+') -contains $DelegatedScopeValue) {
        Write-Host "  Already consented (scope: $($grant.scope))"
    } elseif ($grant) {
        $mergedScope = ($grant.scope.Trim() + " $DelegatedScopeValue").Trim() -replace '\s+', ' '
        Invoke-MgGraphRequest -Method PATCH `
            -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($grant.id)" `
            -Body (@{ scope = $mergedScope } | ConvertTo-Json) `
            -ContentType "application/json"
        Write-Host "  Updated grant: $mergedScope"
    } else {
        $grantBody = @{
            clientId    = $agentSpId
            consentType = "AllPrincipals"
            resourceId  = $weatherSpId
            scope       = $DelegatedScopeValue
        } | ConvertTo-Json
        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" `
            -Body $grantBody -ContentType "application/json" | Out-Null
        Write-Host "  Granted Agent -> Weather API ($DelegatedScopeValue)"
    }
} catch {
    Write-Error "OBO consent failed: $($_.Exception.Message)"
    exit 1
}
Write-Host ""

Write-Host "Done."
Write-Host "  Weather API App ID:     $weatherApiAppIdResolved"
Write-Host "  Application ID URI:     $appIdUri"
Write-Host "  Delegated scope (OBO):  $DelegatedScopeValue"
Write-Host "  OBO scope for sidecar:  api://$weatherApiAppIdResolved/$DelegatedScopeValue"
Write-Host ""