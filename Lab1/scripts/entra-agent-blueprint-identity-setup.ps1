# Microsoft Entra Agent ID - PowerShell script
# Creates an Agent Identity Blueprint and Agent Identity in Microsoft Entra.
#
# Usage (BlueprintName and AgentName optional; default Lab1 Blueprint/Agent + random suffix):
#   .\entra-agent-blueprint-identity-setup.ps1 -TenantId '293882e2-ff46-4747-b46a-a84ca8e98fa0'
#   .\entra-agent-blueprint-identity-setup.ps1   # tenant from current Microsoft Graph session
# Use quotes around the GUID. Do not pass values like -TenantId--TenantId<guid>.
#
# Prerequisites: Microsoft Graph PowerShell module; step 1 calls Connect-MgGraph when needed.

[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$BlueprintName,
    [string]$AgentName
)

$Lab1BlueprintNamePrefix = 'Lab1 Blueprint'
$Lab1AgentNamePrefix     = 'Lab1 Agent'

#region Helper Functions

function Test-EntraTenantGuid {
    param([string]$Value)
    return $Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

function Get-DecodedJwtToken {
    <#
    .SYNOPSIS
    Decodes a JWT token and returns the payload as formatted JSON.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )
    
    try {
        $tokenParts = $Token.Split('.')
        if ($tokenParts.Count -lt 2) {
            throw "Invalid JWT token format"
        }
        
        $payload = $tokenParts[1]
        while ($payload.Length % 4 -ne 0) {
            $payload += '='
        }
        
        $decodedBytes = [System.Convert]::FromBase64String($payload.Replace('-', '+').Replace('_', '/'))
        $decodedJson = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
        
        return ($decodedJson | ConvertFrom-Json | ConvertTo-Json -Depth 10)
    }
    catch {
        Write-Error "Failed to decode JWT token: $_"
        return $null
    }
}

#endregion

#region Step 1: Setup

function Connect-EntraAgentIDEnvironment {
    <#
    .SYNOPSIS
    Connects to Azure and Microsoft Graph with required permissions using user identity.
    
    .PARAMETER TenantId
    The Entra tenant ID. If not provided, will attempt to get from current context.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    if ($TenantId -and -not (Test-EntraTenantGuid -Value $TenantId)) {
        Write-Warning "Invalid -TenantId '$TenantId'; resolving tenant from Microsoft Graph or Azure CLI instead."
        $TenantId = $null
    }
    
    Write-Host "[LOCK] Step 1: Connecting to Azure and Microsoft Graph..." -ForegroundColor Cyan
    Write-Host ""
    
    # Check current Graph connection first
    $currentContext = Get-MgContext -ErrorAction SilentlyContinue
    
    if ($currentContext) {
        Write-Host "[INFO] Current Microsoft Graph Connection:" -ForegroundColor Cyan
        Write-Host "  Account:     $($currentContext.Account)" -ForegroundColor White
        Write-Host "  Tenant ID:   $($currentContext.TenantId)" -ForegroundColor White
        Write-Host "  Scopes:      $($currentContext.Scopes -join ', ')" -ForegroundColor Gray
        Write-Host ""
        
        # Use tenant from current context if not provided
        if (-not $TenantId) {
            $TenantId = $currentContext.TenantId
        }
    } else {
        Write-Host "[WARN]  Not currently logged in to Microsoft Graph" -ForegroundColor Yellow
        Write-Host ""
    }
    
    # Get tenant ID from Azure context if still not available
    if (-not $TenantId) {
        try {
            $context = Get-AzContext -ErrorAction SilentlyContinue
            if ($context) {
                $TenantId = $context.Tenant.Id
                Write-Host "  Found tenant from Azure context: $TenantId" -ForegroundColor Gray
            }
        }
        catch {
            # Ignore error
        }
        
        if (-not $TenantId) {
            try {
                $TenantId = az account show --query tenantId -o tsv 2>$null
                if ($TenantId) {
                    Write-Host "  Found tenant from Azure CLI: $TenantId" -ForegroundColor Gray
                }
            }
            catch {
                # Ignore error
            }
        }
    }
    
    if (-not $TenantId) {
        throw "No tenant ID available. Pass -TenantId '<guid>', or sign in with Connect-AzAccount / az login first."
    }

    if (-not (Test-EntraTenantGuid -Value $TenantId)) {
        throw "Tenant ID '$TenantId' is not a valid GUID."
    }

    # NOTE: Do NOT include Directory.ReadWrite.All - it BLOCKS Agent deletion (Microsoft Known Issue)
    $requiredScopes = @(
        "AgentIdentityBlueprint.AddRemoveCreds.All",
        "AgentIdentityBlueprint.Create",
        "AgentIdentityBlueprint.DeleteRestore.All",
        "AgentIdentity.DeleteRestore.All",
        "DelegatedPermissionGrant.ReadWrite.All",
        "Application.Read.All",
        "AgentIdentityBlueprintPrincipal.Create",
        "AppRoleAssignment.ReadWrite.All",
        "Directory.Read.All",
        "User.Read"
    )

    $scopesQuoted = ($requiredScopes | ForEach-Object { "'$_'" }) -join ','

    if (-not $currentContext) {
        Write-Host "  Not connected to Microsoft Graph. Starting interactive sign-in..." -ForegroundColor Yellow
        Write-Host "  Tenant: $TenantId" -ForegroundColor Gray
        Write-Host ""

        try {
            Connect-MgGraph -Scopes $requiredScopes -TenantId $TenantId -NoWelcome -ErrorAction Stop
        }
        catch {
            Write-Host "  Connect-MgGraph failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Connect manually:" -ForegroundColor Yellow
            Write-Host "  Connect-MgGraph -Scopes $scopesQuoted -TenantId '$TenantId'" -ForegroundColor White
            Write-Host ""
            throw "Not connected to Microsoft Graph. Please connect as shown above."
        }

        $currentContext = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $currentContext) {
            throw "Connect-MgGraph finished but no Microsoft Graph session is available."
        }

        Write-Host "  Signed in as: $($currentContext.Account)" -ForegroundColor Green
        Write-Host ""
    }
    
    $needsReconnect = $false
    if ($currentContext) {
        # Check if all required scopes are present
        $missingScopes = $requiredScopes | Where-Object { $_ -notin $currentContext.Scopes }
        if ($missingScopes.Count -gt 0) {
            Write-Host "  WARNING: Missing required scopes: $($missingScopes -join ', ')" -ForegroundColor Yellow
            Write-Host "  The script may fail without these scopes." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Please reconnect manually with all required scopes:" -ForegroundColor Yellow
            Write-Host "  Disconnect-MgGraph" -ForegroundColor White
            Write-Host "  Connect-MgGraph -Scopes $scopesQuoted -TenantId '$TenantId'" -ForegroundColor White
            Write-Host ""
            throw "Missing required Microsoft Graph scopes. Please reconnect with all scopes as shown above."
        } else {
            Write-Host "  All required scopes present" -ForegroundColor Green
            Write-Host ""
        }
    }
    
    Write-Host ""
    Write-Host "Connected to tenant: $TenantId" -ForegroundColor Green
    Write-Host ""
    
    return @{
        TenantId = $TenantId
        Account  = $currentContext.Account
    }
} 
#endregion

#region Step 2: Blueprint Creation 

function New-AgentIdentityBlueprint {
    <#
    .SYNOPSIS
    Creates an Agent Identity Blueprint with a service principal and client secret.
    
    .PARAMETER BlueprintName
    The display name for the blueprint. REQUIRED - you must provide a meaningful name.
    
    .PARAMETER TenantId
    The Entra tenant ID.
    
    .EXAMPLE
    New-AgentIdentityBlueprint -BlueprintName "Production Blueprint" -TenantId "xxx-xxx"
    #>
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Please provide a name for the blueprint (e.g., 'Production Blueprint', 'Weather Agent Blueprint')")]
        [ValidateNotNullOrEmpty()]
        [string]$BlueprintName,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    Write-Host "[INFO] Step 2: Creating Agent Identity Blueprint..." -ForegroundColor Cyan
    
    # Verify Microsoft Graph connection before proceeding
    $currentContext = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $currentContext) {
        Write-Host ""
        Write-Host "  ERROR: Microsoft Graph connection lost" -ForegroundColor Red
        Write-Host "  Please reconnect and try again:" -ForegroundColor Yellow
        Write-Host "  Connect-MgGraph -Scopes 'AgentIdentityBlueprint.AddRemoveCreds.All','AgentIdentityBlueprint.Create','DelegatedPermissionGrant.ReadWrite.All','Application.Read.All','AgentIdentityBlueprintPrincipal.Create','AppRoleAssignment.ReadWrite.All','Directory.Read.All','User.Read' -TenantId $TenantId" -ForegroundColor White
        Write-Host ""
        throw "Not connected to Microsoft Graph"
    }
    
    Write-Host "  Current connection: $($currentContext.Account)" -ForegroundColor Gray
    Write-Host "  Tenant: $($currentContext.TenantId)" -ForegroundColor Gray
    Write-Host "  Blueprint Name: $BlueprintName" -ForegroundColor Gray
    Write-Host ""
    
    # Get current user ID
    try {
        Write-Host "  Getting user information..." -ForegroundColor Gray
        $me = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction Stop
        $myUserId = $me.id
        Write-Host "  User ID: $myUserId" -ForegroundColor Gray
    }
    catch {
        Write-Host ""
        Write-Host "  ERROR: Failed to get user information from Microsoft Graph" -ForegroundColor Red
        Write-Host "  Error details: $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host ""
        
        if ($_.Exception.Message -like "*DeviceCodeCredential*") {
            Write-Host "  DeviceCodeCredential error detected" -ForegroundColor Yellow
            Write-Host "  This usually means the connection needs to be refreshed." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Please disconnect and reconnect:" -ForegroundColor Cyan
            Write-Host "  Disconnect-MgGraph" -ForegroundColor White
            Write-Host "  Connect-MgGraph -Scopes 'AgentIdentityBlueprint.AddRemoveCreds.All','AgentIdentityBlueprint.Create','DelegatedPermissionGrant.ReadWrite.All','Application.Read.All','AgentIdentityBlueprintPrincipal.Create','AppRoleAssignment.ReadWrite.All','Directory.Read.All','User.Read' -TenantId $TenantId" -ForegroundColor White
            Write-Host ""
        } else {
            Write-Host "  This may indicate:" -ForegroundColor Yellow
            Write-Host "  - Microsoft.Graph module version mismatch" -ForegroundColor White
            Write-Host "  - Expired or invalid authentication token" -ForegroundColor White
            Write-Host "  - Network connectivity issues" -ForegroundColor White
            Write-Host ""
            Write-Host "  Try reconnecting:" -ForegroundColor Cyan
            Write-Host "  Disconnect-MgGraph" -ForegroundColor White
            Write-Host "  Connect-MgGraph -Scopes 'AgentIdentityBlueprint.AddRemoveCreds.All','AgentIdentityBlueprint.Create','DelegatedPermissionGrant.ReadWrite.All','Application.Read.All','AgentIdentityBlueprintPrincipal.Create','AppRoleAssignment.ReadWrite.All','Directory.Read.All','User.Read' -TenantId $TenantId" -ForegroundColor White
            Write-Host ""
        }
        throw $_
    }
    
    # Create blueprint
    $body = @{
        "@odata.type"         = "Microsoft.Graph.AgentIdentityBlueprint"
        displayName           = $BlueprintName
        "sponsors@odata.bind" = @("https://graph.microsoft.com/v1.0/users/$myUserId")
        "owners@odata.bind"   = @("https://graph.microsoft.com/v1.0/users/$myUserId")
    }
    
    $blueprint = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/beta/applications/" `
        -Headers @{ "OData-Version" = "4.0" } `
        -Body ($body | ConvertTo-Json)
    
    Write-Host "  [OK] Blueprint created: $($blueprint.appId)" -ForegroundColor Green
    
    # Create blueprint principal
    $principalBody = @{ appId = $blueprint.appId }
    $principal = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" `
        -Headers @{ "OData-Version" = "4.0" } `
        -Body ($principalBody | ConvertTo-Json)
    
    Write-Host "  [OK] Blueprint Principal created: $($principal.id)" -ForegroundColor Green
    
    # Wait for principal to propagate
    Write-Host "  [WAIT] Waiting for principal to propagate..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Add client secret
    $blueprintApp = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/applications?`$filter=appId eq '$($blueprint.appId)'").value[0]
    
    $secretBody = @{
        passwordCredential = @{
            displayName = "Agent ID Secret " + $BlueprintName
        }
    }
    
    $secret = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/beta/applications/$($blueprintApp.id)/addPassword" `
        -Body ($secretBody | ConvertTo-Json)
    
    # Debug: Check what properties the secret object has
    if (-not $secret.secretText) {
        Write-Host "  [WARN]  DEBUG: Secret object properties:" -ForegroundColor Yellow
        $secret | ConvertTo-Json -Depth 5 | Write-Host
        Write-Error "Secret object doesn't have 'secretText' property!"
        throw "Failed to get client secret from addPassword response"
    }
    
    Write-Host "  [OK] Client secret created (length: $($secret.secretText.Length) chars)" -ForegroundColor Green
    Write-Host "`n  [KEY] CLIENT SECRET (copy this now):" -ForegroundColor Yellow
    Write-Host "  $($secret.secretText)" -ForegroundColor White
    Write-Host ""
    
    # Verify the secret works before proceeding
    Write-Host "  [WAIT] Verifying client secret is valid..." -ForegroundColor Yellow
    $maxRetries = 10
    $retryCount = 0
    $secretValid = $false
    
    while (-not $secretValid -and $retryCount -lt $maxRetries) {
        try {
            $testTokenBody = @{
                client_id     = $blueprint.appId
                scope         = "https://graph.microsoft.com/.default"
                grant_type    = "client_credentials"
                client_secret = $secret.secretText
            }
            
            $testResponse = Invoke-RestMethod -Method POST `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -ContentType "application/x-www-form-urlencoded" `
                -Body $testTokenBody `
                -ErrorAction Stop
            
            if ($testResponse.access_token) {
                $secretValid = $true
                Write-Host "  [OK] Client secret verified and working!" -ForegroundColor Green
            }
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "  [WAIT] Secret not ready yet, waiting... (attempt $retryCount/$maxRetries)" -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
            else {
                Write-Warning "  [WARN]  Secret verification failed after $maxRetries attempts. Proceeding anyway..."
            }
        }
    }
    
    Write-Host "  [WARN]  SAVE THIS SECRET - you won't see it again!" -ForegroundColor Yellow
    
    return @{
        BlueprintName     = $BlueprintName
        BlueprintAppId    = $blueprint.appId
        BlueprintObjectId = $blueprint.id
        PrincipalId       = $principal.id
        ClientSecret      = $secret.secretText
        UserId            = $myUserId
    }
}

#endregion

#region Step 3: Agent Identity Creation

function New-AgentIdentity {
    <#
    .SYNOPSIS
    Creates an Agent Identity from a blueprint.
    
    .PARAMETER AgentName
    The display name for the agent identity. If not provided, auto-generates with timestamp.
    
    .PARAMETER BlueprintAppId
    The App ID of the blueprint to use.
    
    .PARAMETER ClientSecret
    The client secret of the blueprint.
    
    .PARAMETER TenantId
    The Entra tenant ID.
    
    .PARAMETER UserId
    The user ID to set as sponsor.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$AgentName,
        
        [Parameter(Mandatory = $true)]
        [string]$BlueprintAppId,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )
    
    Write-Host "[AGENT] Step 3: Creating Agent Identity..." -ForegroundColor Cyan
    
    # Generate agent name with timestamp if not provided
    if (-not $AgentName) {
        $AgentName = "RZ PoC Agent (" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ")"
    }
    
    # Get blueprint token for agent creation
    Write-Host "  [KEY] Using Blueprint App ID: $BlueprintAppId" -ForegroundColor Gray
    Write-Host "  [KEY] Secret length: $($ClientSecret.Length) characters" -ForegroundColor Gray
    
    $tokenBody = @{
        client_id     = $BlueprintAppId
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
        client_secret = $ClientSecret
    }
    
    # Retry logic for token acquisition (secret may need time to propagate)
    $maxRetries = 5
    $retryCount = 0
    $blueprintToken = $null
    
    while (-not $blueprintToken -and $retryCount -lt $maxRetries) {
        try {
            $tokenResponse = Invoke-RestMethod -Method POST `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -ContentType "application/x-www-form-urlencoded" `
                -Body $tokenBody `
                -ErrorAction Stop
            
            $blueprintToken = $tokenResponse.access_token
            Write-Host "  [OK] Got blueprint token for agent creation" -ForegroundColor Green
        }
        catch {
            $retryCount++
            $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($errorResponse.error -eq "invalid_client" -and $retryCount -lt $maxRetries) {
                Write-Host "  [WAIT] Secret not ready yet, waiting... (attempt $retryCount/$maxRetries)" -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
            else {
                Write-Error "  [ERROR] Failed to get blueprint token. This usually means:"
                Write-Error "     - The client secret is invalid or expired"
                Write-Error "     - The blueprint application was deleted"
                Write-Error "     - Blueprint App ID: $BlueprintAppId"
                Write-Error "  Error: $($_.ErrorDetails.Message)"
                throw
            }
        }
    }
    
    if (-not $blueprintToken) {
        throw "Failed to acquire blueprint token after $maxRetries retries"
    }
    
    # Verify the token has the right claims
    try {
        $tokenPayload = Get-DecodedJwtToken -Token $blueprintToken | ConvertFrom-Json
        if ($tokenPayload.roles -notcontains "AgentIdentity.CreateAsManager") {
            Write-Warning "  [WARN]  Token doesn't have AgentIdentity.CreateAsManager role. Waiting for permissions to propagate..."
            Start-Sleep -Seconds 10
        }
    }
    catch {
        Write-Warning "  [WARN]  Could not decode token, proceeding anyway..."
    }
    
    # Create agent identity
    $agentIdentityBody = @{
        displayName              = $AgentName
        agentIdentityBlueprintId = $BlueprintAppId
        "sponsors@odata.bind"    = @("https://graph.microsoft.com/v1.0/users/$UserId")
    }
    
    $agentIdentity = Invoke-RestMethod -Method POST `
        -Uri "https://graph.microsoft.com/beta/serviceprincipals/Microsoft.Graph.AgentIdentity" `
        -Headers @{
        "Authorization" = "Bearer $blueprintToken"
        "OData-Version" = "4.0"
        "Content-Type"  = "application/json"
    } `
        -Body ($agentIdentityBody | ConvertTo-Json)
    
    Write-Host "  [OK] Agent Identity created!" -ForegroundColor Green
    Write-Host "  App ID: $($agentIdentity.appId)" -ForegroundColor Gray
    Write-Host "  Service Principal ID: $($agentIdentity.id)" -ForegroundColor Gray
    
    return @{
        AgentName          = $AgentName
        AgentIdentityAppId = $agentIdentity.appId
        AgentIdentitySP    = $agentIdentity.id
    }
}

#endregion

#region Main Orchestration Function

function Start-EntraAgentIDWorkflow {
    <#
    .SYNOPSIS
    Creates an Agent Identity Blueprint and Agent Identity in Microsoft Entra.

    .DESCRIPTION
    Orchestrates:
    1. Validate Microsoft Graph connection
    2. Create Agent Identity Blueprint
    3. Create Agent Identity

    .PARAMETER TenantId
    The Entra tenant ID. If not provided, uses current context.

    .PARAMETER BlueprintName
    Blueprint display name.

    .PARAMETER AgentName
    Agent identity display name.

    .EXAMPLE
    Start-EntraAgentIDWorkflow -BlueprintName "Production Blueprint" -AgentName "Weather Agent"
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $true, HelpMessage = "Please provide a name for the blueprint (e.g., 'Production Blueprint', 'Dev Blueprint')")]
        [ValidateNotNullOrEmpty()]
        [string]$BlueprintName,

        [Parameter(Mandatory = $true, HelpMessage = "Please provide a name for the agent identity (e.g., 'Weather Agent', 'Sales Agent')")]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName
    )

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "   Microsoft Entra Agent ID - Blueprint and Agent Setup" -ForegroundColor Cyan
    Write-Host "============================================================`n" -ForegroundColor Cyan

    Write-Host "[INFO]  Note: This workflow creates NEW blueprint and agent identities each time." -ForegroundColor Yellow
    Write-Host "   Old blueprints will remain in your tenant until manually deleted." -ForegroundColor Yellow
    Write-Host ""

    try {
        $connection = Connect-EntraAgentIDEnvironment -TenantId $TenantId
        Start-Sleep -Seconds 1

        Write-Host "[NOTE] Creating a NEW blueprint for this workflow..." -ForegroundColor Cyan
        $blueprint = New-AgentIdentityBlueprint -BlueprintName $BlueprintName -TenantId $connection.TenantId
        Write-Host "  [WAIT] Waiting for blueprint to fully propagate..." -ForegroundColor Gray
        Start-Sleep -Seconds 10

        $agent = New-AgentIdentity `
            -AgentName $AgentName `
            -BlueprintAppId $blueprint.BlueprintAppId `
            -ClientSecret $blueprint.ClientSecret `
            -TenantId $connection.TenantId `
            -UserId $blueprint.UserId
        Start-Sleep -Seconds 3

        Write-Host "`n============================================================" -ForegroundColor Green
        Write-Host "   [OK] Workflow Completed Successfully!" -ForegroundColor Green
        Write-Host "============================================================`n" -ForegroundColor Green

        Write-Host "[INFO] Summary:" -ForegroundColor Cyan
        Write-Host "  Tenant ID:                $($connection.TenantId)" -ForegroundColor Gray
        Write-Host "  Blueprint Name:           $($blueprint.BlueprintName)" -ForegroundColor Gray
        Write-Host "  Blueprint App ID:         $($blueprint.BlueprintAppId)" -ForegroundColor Gray
        Write-Host "  Blueprint Client Secret:  (shown above during blueprint creation — save it)" -ForegroundColor Gray
        Write-Host "  Agent Name:               $($agent.AgentName)" -ForegroundColor Gray
        Write-Host "  Agent App ID:             $($agent.AgentIdentityAppId)" -ForegroundColor Gray
        Write-Host "  Agent Service Principal:  $($agent.AgentIdentitySP)" -ForegroundColor Gray
        Write-Host ""

        return @{
            Connection = $connection
            Blueprint  = $blueprint
            Agent      = $agent
        }
    }
    catch {
        Write-Host "`n============================================================" -ForegroundColor Red
        Write-Host "   [ERROR] Workflow Failed" -ForegroundColor Red
        Write-Host "============================================================`n" -ForegroundColor Red
        Write-Error "Error: $_"
        throw
    }
}

#endregion

if ($MyInvocation.InvocationName -eq '.') {
    throw "Do not dot-source this script. Run: .\entra-agent-blueprint-identity-setup.ps1 [-TenantId '<guid>']"
}

if ($TenantId -and -not (Test-EntraTenantGuid -Value $TenantId)) {
    throw @"
Invalid -TenantId '$TenantId'.

Use a tenant GUID in single quotes, for example:
  .\entra-agent-blueprint-identity-setup.ps1 -TenantId '293882e2-ff46-4747-b46a-a84ca8e98fa0'

Or omit -TenantId when you are already signed in to Microsoft Graph (Connect-MgGraph).
Do not concatenate the parameter name with the GUID (not -TenantId--TenantId<guid>).
"@
}

if ($BlueprintName -and (Test-EntraTenantGuid -Value $BlueprintName)) {
    throw @"
-BlueprintName '$BlueprintName' looks like a tenant ID, not a blueprint display name.

Pass the tenant with -TenantId '...' and omit -BlueprintName to use the default Lab1 Blueprint <suffix> name.
"@
}

$runSuffix = Get-Random -Minimum 100000 -Maximum 999999
if ([string]::IsNullOrWhiteSpace($BlueprintName)) {
    $BlueprintName = "$Lab1BlueprintNamePrefix $runSuffix"
}
if ([string]::IsNullOrWhiteSpace($AgentName)) {
    $AgentName = "$Lab1AgentNamePrefix $runSuffix"
}

Write-Host "Run suffix: $runSuffix" -ForegroundColor Gray
Write-Host "Blueprint name: $BlueprintName" -ForegroundColor Gray
Write-Host "Agent name: $AgentName" -ForegroundColor Gray
Write-Host ""

Start-EntraAgentIDWorkflow -TenantId $TenantId -BlueprintName $BlueprintName -AgentName $AgentName
