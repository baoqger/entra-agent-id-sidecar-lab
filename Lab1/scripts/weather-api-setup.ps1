# =============================================================================
# Weather API resource (custom audience) for Agent Identity
# =============================================================================
# Steps:
#   1. Weather API app registration (create or reuse)
#   2. Application ID URI (api://<appId>)
#   3. App role Weather.Read
#   4. Service principal for Weather API
#   5. Assign app role to Agent Identity service principal
#
# Prerequisites:
#   - Agent Identity created (AGENT_CLIENT_ID in sidecar .env)
#   - Microsoft.Graph.Authentication (Connect-MgGraph)
#   - Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All
#
# Usage:
#   .\weather-api-setup.ps1 -TenantId '<tenant-guid>' -AgentAppId '<agent-app-id>'
#   .\weather-api-setup.ps1   # TENANT_ID and AGENT_CLIENT_ID from ..\sidecar\.env
#   -AppDisplayName optional; default is "Weather API" + random 6-digit suffix (new app only)
# =============================================================================

param(
    [string]$TenantId,
    [string]$AgentAppId,
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\sidecar\.env"),
    [string]$WeatherApiAppId,
    [string]$AppDisplayName,
    [string]$AppRoleValue = "Weather.Read"
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

function ConvertTo-GraphAppRoleDefinition {
    param(
        [Parameter(Mandatory = $true)]$Role
    )
    $allowed = @($Role.allowedMemberTypes | ForEach-Object { [string]$_ })
    if ($allowed.Count -eq 0) {
        $allowed = @("Application")
    }
    return [ordered]@{
        allowedMemberTypes = $allowed
        description        = [string]$Role.description
        displayName        = [string]$Role.displayName
        id                 = [string]$Role.id
        isEnabled          = [bool]$Role.isEnabled
        value              = [string]$Role.value
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
Write-Host "Weather API resource setup"
if ($runSuffix) {
    Write-Host "  Run suffix: $runSuffix"
}
Write-Host "  App name:   $AppDisplayName"
Write-Host "  Tenant: $TenantId"
Write-Host "  Agent:  $AgentAppId"
Write-Host "  .env:   $EnvFile"
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
    "AppRoleAssignment.ReadWrite.All"
) -TenantId $TenantId -NoWelcome
Write-Host "  Connected"
Write-Host ""

# Step 1: Weather API app registration
Write-Host "Step 1: Weather API app registration..."

$weatherAppObjectId = $null
$weatherApiAppIdResolved = $WeatherApiAppId

if ($weatherApiAppIdResolved) {
    $appResult = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$weatherApiAppIdResolved'&`$select=id,appId,displayName,identifierUris,appRoles"
    if (-not $appResult.value -or $appResult.value.Count -eq 0) {
        Write-Error "No application found for -WeatherApiAppId $weatherApiAppIdResolved"
        exit 1
    }
    $weatherApp = $appResult.value[0]
    Write-Host "  Using existing app: $($weatherApp.displayName) ($weatherApiAppIdResolved)"
} else {
    $filterName = $AppDisplayName.Replace("'", "''")
    $existing = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$filterName'&`$select=id,appId,displayName,identifierUris,appRoles"

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
            appRoles       = @()
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

# Step 3: App role Weather.Read
Write-Host "Step 3: App role '$AppRoleValue'..."

$appRolesUri = Format-GraphResourceUri -Path "applications/$weatherAppObjectId" -Query '$select=appRoles'
$appRefresh = Invoke-MgGraphRequest -Method GET -Uri $appRolesUri
$existingRoles = @($appRefresh.appRoles)
$role = $existingRoles | Where-Object { $_.value -eq $AppRoleValue }

if ($role) {
    $appRoleId = $role.id
    Write-Host "  Role already exists (ID: $appRoleId)"
} else {
    $appRoleId = (New-Guid).ToString()
    $newRole = [ordered]@{
        allowedMemberTypes = @("Application")
        description        = "Allows agents to read weather data from the sample API"
        displayName        = "Read weather"
        id                 = $appRoleId
        isEnabled          = $true
        value              = $AppRoleValue
    }
    $mergedRoles = @(
        foreach ($r in $existingRoles) {
            if ($null -ne $r -and $r.value) {
                ConvertTo-GraphAppRoleDefinition -Role $r
            }
        }
    ) + @((ConvertTo-GraphAppRoleDefinition -Role $newRole))

    $body = @{ appRoles = $mergedRoles } | ConvertTo-Json -Depth 6
    $patchUri = Format-GraphResourceUri -Path "applications/$weatherAppObjectId"
    try {
        Invoke-MgGraphRequest -Method PATCH `
            -Uri $patchUri `
            -Body $body -ContentType "application/json"
    } catch {
        Write-Error "Failed to add app role $AppRoleValue : $($_.Exception.Message)"
        exit 1
    }
    Write-Host "  Added app role $AppRoleValue (ID: $appRoleId)"
    Start-Sleep -Seconds 3
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

$weatherSpRolesUri = Format-GraphResourceUri -Path "servicePrincipals/$weatherSpId" -Query '$select=appRoles'
$weatherSpFull = Invoke-MgGraphRequest -Method GET -Uri $weatherSpRolesUri
$spRole = $weatherSpFull.appRoles | Where-Object { $_.value -eq $AppRoleValue }
if ($spRole) {
    $appRoleId = $spRole.id
}
Write-Host ""

# Step 5: Assign app role to Agent Identity SP
Write-Host "Step 5: Grant $AppRoleValue to Agent Identity..."

$agentSpResult = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AgentAppId'&`$select=id,displayName"

if (-not $agentSpResult.value -or $agentSpResult.value.Count -eq 0) {
    Write-Error "Agent service principal not found for appId $AgentAppId. Create an agent identity first."
    exit 1
}

$agentSpId = $agentSpResult.value[0].id
Write-Host "  Agent SP: $($agentSpResult.value[0].displayName) ($agentSpId)"

$assignments = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$agentSpId/appRoleAssignments"

$alreadyAssigned = $assignments.value | Where-Object {
    $_.resourceId -eq $weatherSpId -and $_.appRoleId -eq $appRoleId
}

if ($alreadyAssigned) {
    Write-Host "  App role assignment already exists"
} else {
    $assignBody = @{
        principalId = $agentSpId
        resourceId  = $weatherSpId
        appRoleId   = $appRoleId
    } | ConvertTo-Json
    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$agentSpId/appRoleAssignments" `
            -Body $assignBody -ContentType "application/json" | Out-Null
        Write-Host "  Assigned $AppRoleValue to agent"
    } catch {
        Write-Error "Assignment failed: $($_.Exception.Message)"
        exit 1
    }
}
Write-Host ""

Write-Host "Done."
Write-Host "  Weather API App ID:   $weatherApiAppIdResolved"
Write-Host "  Application ID URI:   $appIdUri"
Write-Host "  App role:             $AppRoleValue"
Write-Host "  Sidecar scope hint:   ${appIdUri}/.default"
Write-Host ""