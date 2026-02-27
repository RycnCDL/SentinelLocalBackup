<#
.SYNOPSIS
    Authentication Module for Sentinel Manager
.DESCRIPTION
    Handles Azure authentication using Azure CLI or Az PowerShell Module.
    Provides token management and session validation.
.VERSION
    3.0
#>

# Import required modules
. "$PSScriptRoot/../Helpers/UIHelpers.ps1"
. "$PSScriptRoot/Configuration.ps1"

#region Authentication Functions

function Connect-ToAzure {
    <#
    .SYNOPSIS
        Authenticates to Azure using available methods
    .DESCRIPTION
        Auto-detects available authentication methods (Az CLI, Az Module)
        and prompts user to select and authenticate
    .RETURN
        $true if successful, $false otherwise
    #>

    Write-Header "Authentifizierung"

    # Auto-detect available authentication methods
    $azCliAvailable = $false
    $azModuleAvailable = $false

    try {
        $null = Get-Command az -ErrorAction Stop
        $azCliAvailable = $true
    } catch {}

    if (Get-Module -ListAvailable -Name Az.Accounts) {
        $azModuleAvailable = $true
    }

    $Session = Get-SentinelSession

    # Check for existing authentication
    $azCliLoggedIn = $false
    $azModuleLoggedIn = $false
    $currentUser = $null

    if ($azCliAvailable) {
        try {
            $account = az account show 2>$null | ConvertFrom-Json
            if ($account) {
                # Validate the session is actually alive by requesting a token
                # (az account show only reads local cache and can be stale)
                $testToken = az account get-access-token --output json 2>$null
                if ($LASTEXITCODE -eq 0 -and $testToken) {
                    $azCliLoggedIn = $true
                    $currentUser = $account.user.name
                } else {
                    Write-ColorOutput "Azure CLI: Cached account found but token expired." "Yellow"
                    Write-ColorOutput "  A fresh login is required." "Yellow"
                }
            }
        } catch {}
    }

    if ($azModuleAvailable) {
        try {
            Import-Module Az.Accounts -ErrorAction SilentlyContinue
            $context = Get-AzContext -ErrorAction SilentlyContinue
            if ($context) {
                $azModuleLoggedIn = $true
                $currentUser = $context.Account.Id
            }
        } catch {}
    }

    # Show current authentication status
    if ($azCliLoggedIn -or $azModuleLoggedIn) {
        Write-Host ""
        Write-ColorOutput "Aktuelle Authentifizierung erkannt:" "Green"
        Write-Host "  Benutzer: $currentUser"
        if ($azCliLoggedIn) {
            Write-Host "  Methode: Azure CLI"
        } elseif ($azModuleLoggedIn) {
            Write-Host "  Methode: PowerShell Az Module"
        }
        Write-Host ""

        $useExisting = Get-YesNoChoice "Möchtest du die bestehende Authentifizierung verwenden?" "Y"

        if ($useExisting) {
            if ($azCliLoggedIn) {
                $Session.UseAzModule = $false
                Write-ColorOutput "Verwende bestehende Azure CLI Session" "Green"
            } else {
                $Session.UseAzModule = $true
                Write-ColorOutput "Verwende bestehende Az Module Session" "Green"
            }
            return $true
        }

        Write-ColorOutput "`nNeu authentifizieren..." "Yellow"
        Write-Host ""
    }

    Write-ColorOutput "Verfügbare Authentifizierungsmethoden:" "Cyan"
    $options = @()
    $optionMap = @{}
    $index = 1

    if ($azCliAvailable) {
        Write-Host "$index. Azure CLI (az login) - Interaktive Anmeldung"
        $optionMap[$index.ToString()] = "AzCLI"
        $options += $index
        $index++
    }

    if ($azModuleAvailable) {
        Write-Host "$index. PowerShell Az Module - Device Code (empfohlen)"
        $optionMap[$index.ToString()] = "AzModuleDevice"
        $options += $index
        $index++

        Write-Host "$index. PowerShell Az Module - Browser-basiert (erfordert Browser)"
        $optionMap[$index.ToString()] = "AzModule"
        $options += $index
        $index++
    }

    if (-not $azModuleAvailable) {
        Write-Host "$index. PowerShell Az Module installieren und verwenden"
        $optionMap[$index.ToString()] = "InstallAzModule"
        $options += $index
    }

    Write-Host ""

    if ($options.Count -eq 0) {
        Write-ColorOutput "Keine Authentifizierungsmethode gefunden!" "Red"
        Write-ColorOutput "Installiere Az PowerShell Module..." "Yellow"
        Install-Module -Name Az.Accounts -Scope CurrentUser -Force -AllowClobber
        Import-Module Az.Accounts
        $Session.UseAzModule = $true
        Write-ColorOutput "Verwende Device Code Authentifizierung..." "Yellow"
        Write-ColorOutput "Hinweis: Folge den Anweisungen auf dem Bildschirm" "Cyan"
        Connect-AzAccount -UseDeviceAuthentication
        return $?
    }

    $choice = Read-Host "Wähle eine Authentifizierungsmethode ($(($options -join ',')))"

    try {
        $method = $optionMap[$choice]

        switch ($method) {
            "AzCLI" {
                Write-ColorOutput "Verwende Azure CLI..." "Yellow"
                $Session.UseAzModule = $false
                Write-ColorOutput "Starte Azure CLI Login..." "Yellow"
                az login
                return $?
            }
            "AzModule" {
                Write-ColorOutput "Verwende PowerShell Az Module (Browser)..." "Yellow"
                Write-ColorOutput "Hinweis: Öffnet Browser für Authentifizierung" "Cyan"
                $Session.UseAzModule = $true
                Import-Module Az.Accounts -ErrorAction SilentlyContinue
                Connect-AzAccount
                return $?
            }
            "AzModuleDevice" {
                Write-ColorOutput "Verwende PowerShell Az Module (Device Code)..." "Yellow"
                Write-ColorOutput "Hinweis: Folge den Anweisungen auf dem Bildschirm" "Cyan"
                $Session.UseAzModule = $true
                Import-Module Az.Accounts -ErrorAction SilentlyContinue
                Connect-AzAccount -UseDeviceAuthentication
                return $?
            }
            "InstallAzModule" {
                Write-ColorOutput "Installiere Az PowerShell Module..." "Yellow"
                Install-Module -Name Az.Accounts -Scope CurrentUser -Force -AllowClobber
                Import-Module Az.Accounts
                $Session.UseAzModule = $true
                Write-ColorOutput "Verwende Device Code Authentifizierung..." "Yellow"
                Write-ColorOutput "Hinweis: Folge den Anweisungen auf dem Bildschirm" "Cyan"
                Connect-AzAccount -UseDeviceAuthentication
                return $?
            }
            default {
                Write-ColorOutput "Ungültige Auswahl!" "Red"
                return $false
            }
        }
    }
    catch {
        Write-ColorOutput "Authentifizierungsfehler: $_" "Red"
        return $false
    }
}

function Get-AccessToken {
    <#
    .SYNOPSIS
        Gets an Azure access token for a specified resource
    .PARAMETER Resource
        The Azure resource URL to get a token for.
        Default: https://management.azure.com (Management API)
        Use https://api.loganalytics.io for Log Analytics queries.
    .PARAMETER ForceRefresh
        Forces token refresh (not implemented yet)
    .RETURN
        Access token string or $null if error
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$Resource = "",

        [switch]$ForceRefresh = $false
    )

    $Config = Get-SentinelConfig
    $Session = Get-SentinelSession

    # Default to Management API if no resource specified
    if (-not $Resource) { $Resource = $Config.ManagementApiUrl }

    try {
        # Check if session data is present
        if (-not $Session.SubscriptionId) {
            Write-ColorOutput "Fehler: Keine Subscription ausgewählt!" "Red"
            return $null
        }

        if ($Config.DebugMode) {
            Write-Host "[DEBUG] Auth-Methode: $(if($Session.UseAzModule){'Az Module'}else{'Azure CLI'})" -ForegroundColor Gray
            Write-Host "[DEBUG] Subscription: $($Session.SubscriptionId)" -ForegroundColor Gray
        }

        $token = $null

        if ($Session.UseAzModule) {
            # Use Az PowerShell Module
            Import-Module Az.Accounts -ErrorAction SilentlyContinue

            # Check if still authenticated
            $context = Get-AzContext -ErrorAction SilentlyContinue
            if (-not $context) {
                Write-ColorOutput "Az Module Session abgelaufen! Bitte erneut authentifizieren." "Red"
                return $null
            }

            # Resource URL WITHOUT trailing slash for Az Module
            $tokenObj = Get-AzAccessToken -ResourceUrl $Resource -ErrorAction Stop

            # Convert token (can be SecureString or String)
            if ($tokenObj.Token -is [System.Security.SecureString]) {
                # Convert SecureString to Plain Text (Cross-Platform)
                # Use ConvertFrom-SecureString for PowerShell 7+ (works on Linux/macOS/Windows)
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    $token = ConvertFrom-SecureString -SecureString $tokenObj.Token -AsPlainText
                } else {
                    # Fallback for Windows PowerShell 5.1
                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenObj.Token)
                    try {
                        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                    } finally {
                        # Important: Free memory for security
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
                    }
                }
            } else {
                $token = $tokenObj.Token
            }

            if ($Config.DebugMode) {
                Write-Host "[DEBUG] Token Type: $($tokenObj.Token.GetType().Name)" -ForegroundColor Gray
                Write-Host "[DEBUG] Token ExpiresOn: $($tokenObj.ExpiresOn)" -ForegroundColor Gray
            }
        } else {
            # Use Azure CLI
            # Try --scope first (Azure CLI 2.55+), then --resource (older CLI)
            $tokenObj  = $null
            $lastError = ""

            # Attempt 1: --scope (newer Azure CLI 2.55+)
            $rawOutput = $null
            $errFile   = [System.IO.Path]::GetTempFileName()
            try {
                $rawOutput = az account get-access-token --scope "$Resource/.default" --output json 2>$errFile
                if ($LASTEXITCODE -eq 0 -and $rawOutput) {
                    $tokenObj = $rawOutput | ConvertFrom-Json -ErrorAction Stop
                }
            } catch {
                $tokenObj = $null
            }

            # Attempt 2: --resource (older Azure CLI)
            if (-not $tokenObj) {
                try {
                    $rawOutput = az account get-access-token --resource "$Resource" --output json 2>$errFile
                    if ($LASTEXITCODE -eq 0 -and $rawOutput) {
                        $tokenObj = $rawOutput | ConvertFrom-Json -ErrorAction Stop
                    }
                } catch {
                    $tokenObj = $null
                }
            }

            # Read captured stderr for diagnostics
            if (Test-Path $errFile) {
                $lastError = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue)
                Remove-Item $errFile -Force -ErrorAction SilentlyContinue
            }

            if (-not $tokenObj -or -not $tokenObj.accessToken) {
                Write-ColorOutput "Azure CLI Token-Abruf fehlgeschlagen!" "Red"
                if ($lastError) {
                    Write-ColorOutput "  Azure CLI Fehler: $($lastError.Trim())" "Yellow"
                }
                Write-Host ""
                Write-Host "  Mögliche Lösungen:" -ForegroundColor Cyan
                Write-Host "    1. az login                         (erneut anmelden)"
                Write-Host "    2. az account set -s <SubscriptionId>  (Subscription setzen)"
                Write-Host "    3. az upgrade                       (Azure CLI aktualisieren)"
                Write-Host "    4. az account get-access-token      (manueller Token-Test)"
                return $null
            }

            $token = $tokenObj.accessToken

            if ($Config.DebugMode) {
                Write-Host "[DEBUG] Token ExpiresOn: $($tokenObj.expiresOn)" -ForegroundColor Gray
            }
        }

        if (-not $token) {
            Write-ColorOutput "Fehler: Leerer Token zurückgegeben!" "Red"
            return $null
        }

        if ($Config.DebugMode) {
            Write-Host "[DEBUG] Token Länge: $($token.Length) Zeichen" -ForegroundColor Gray
            if ($token.Length -gt 0) {
                $prefixLength = [Math]::Min(20, $token.Length)
                Write-Host "[DEBUG] Token Prefix: $($token.Substring(0, $prefixLength))..." -ForegroundColor Gray
            }
        }

        return $token
    }
    catch {
        Write-ColorOutput "Fehler beim Abrufen des Access Tokens: $_" "Red"
        Write-ColorOutput "Mögliche Ursachen:" "Yellow"
        Write-Host "  - Session abgelaufen - bitte neu authentifizieren"
        Write-Host "  - Netzwerkprobleme"
        Write-Host "  - Fehlende Berechtigungen"
        return $null
    }
}

#endregion

#region Workspace & Subscription Selection

function Select-Subscription {
    <#
    .SYNOPSIS
        Lists available subscriptions and lets the user choose one
    .DESCRIPTION
        Queries available Azure subscriptions and stores the selection in the
        session. Skips the prompt if only one subscription is available.
    .RETURN
        $true if a subscription was selected, $false otherwise
    #>
    $Session = Get-SentinelSession

    Write-ColorOutput "  Loading subscriptions..." "Cyan"

    $subscriptions = @()

    try {
        if ($Session.UseAzModule) {
            Import-Module Az.Accounts -ErrorAction SilentlyContinue
            $subs = Get-AzSubscription -ErrorAction Stop
            foreach ($s in $subs) {
                $subscriptions += [PSCustomObject]@{
                    Id   = $s.Id
                    Name = $s.Name
                    State = $s.State
                }
            }
        } else {
            $json = az account list --output json 2>$null | ConvertFrom-Json
            foreach ($s in $json) {
                $subscriptions += [PSCustomObject]@{
                    Id    = $s.id
                    Name  = $s.name
                    State = $s.state
                }
            }
        }
    }
    catch {
        Write-ColorOutput "  Could not list subscriptions: $_" "Red"
        return $false
    }

    $subscriptions = $subscriptions | Where-Object { $_.State -eq "Enabled" } | Sort-Object Name

    if ($subscriptions.Count -eq 0) {
        Write-ColorOutput "  No enabled subscriptions found." "Red"
        return $false
    }

    # Auto-select if only one
    if ($subscriptions.Count -eq 1) {
        $Session.SubscriptionId   = $subscriptions[0].Id
        $Session.SubscriptionName = $subscriptions[0].Name
        Write-ColorOutput "  Auto-selected subscription: $($subscriptions[0].Name)" "Green"
        return $true
    }

    # Show selection list
    Write-Host ""
    Write-Host "  ┌────┬────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ ## │ Subscription                                           │" -ForegroundColor DarkGray
    Write-Host "  ├────┼────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $num  = ($i + 1).ToString().PadLeft(2)
        $name = $subscriptions[$i].Name
        if ($name.Length -gt 54) { $name = $name.Substring(0, 51) + "..." }
        $namePad = $name.PadRight(54)

        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$num" -ForegroundColor Yellow -NoNewline
        Write-Host " │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$namePad" -ForegroundColor White -NoNewline
        Write-Host "│" -ForegroundColor DarkGray
    }
    Write-Host "  └────┴────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $choice = Read-Host "  Select subscription (1-$($subscriptions.Count))"
        $idx    = 0
        $valid  = [int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $subscriptions.Count
        if (-not $valid) { Write-ColorOutput "  Invalid choice, try again." "Red" }
    } while (-not $valid)

    $selected = $subscriptions[$idx - 1]
    $Session.SubscriptionId   = $selected.Id
    $Session.SubscriptionName = $selected.Name

    # Set active subscription and verify it took effect
    try {
        if ($Session.UseAzModule) {
            Set-AzContext -SubscriptionId $selected.Id -ErrorAction Stop | Out-Null
        } else {
            az account set --subscription $selected.Id
            if ($LASTEXITCODE -ne 0) {
                Write-ColorOutput "  Failed to set subscription via Azure CLI." "Red"
                Write-ColorOutput "  Try: az account set --subscription $($selected.Id)" "Yellow"
                return $false
            }

            # Verify subscription is active
            $verify = az account show --output json 2>$null | ConvertFrom-Json
            if ($verify -and $verify.id -ne $selected.Id) {
                Write-ColorOutput "  Warning: Active subscription does not match selection." "Yellow"
                Write-ColorOutput "  Expected: $($selected.Id)" "Yellow"
                Write-ColorOutput "  Active:   $($verify.id)" "Yellow"
            }
        }
    } catch {
        Write-ColorOutput "  Error setting subscription: $_" "Red"
        return $false
    }

    Write-ColorOutput "  Selected: $($selected.Name)" "Green"
    return $true
}

function Select-Workspace {
    <#
    .SYNOPSIS
        Lists Log Analytics workspaces in the selected subscription and lets
        the user choose one
    .DESCRIPTION
        Queries the Azure REST API for all Log Analytics workspaces in the
        current subscription. Stores the selection (WorkspaceId, WorkspaceName,
        ResourceGroup) in the session.
    .RETURN
        $true if a workspace was selected, $false otherwise
    #>
    $Session = Get-SentinelSession
    $Config  = Get-SentinelConfig

    if (-not $Session.SubscriptionId) {
        Write-ColorOutput "  No subscription selected. Run Select-Subscription first." "Red"
        return $false
    }

    Write-ColorOutput "  Loading Log Analytics workspaces..." "Cyan"

    $workspaces = @()

    try {
        $uri = "$($Config.ManagementApiUrl)/subscriptions/$($Session.SubscriptionId)" +
               "/providers/Microsoft.OperationalInsights/workspaces?api-version=2022-10-01"

        # Get token for the API call
        $token = Get-AccessToken
        if (-not $token) { return $false }

        $headers  = @{ "Authorization" = "Bearer $token" }
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop

        foreach ($ws in $response.value) {
            $rg = (($ws.id -split "/resourceGroups/")[1] -split "/")[0]
            $workspaces += [PSCustomObject]@{
                Name          = $ws.name
                ResourceGroup = $rg
                WorkspaceId   = $ws.properties.customerId
                Location      = $ws.location
                Sku           = $ws.properties.sku.name
            }
        }
    }
    catch {
        Write-ColorOutput "  Could not list workspaces via REST: $_" "Yellow"
        Write-ColorOutput "  Trying Az Module fallback..." "Gray"

        try {
            Import-Module Az.OperationalInsights -ErrorAction SilentlyContinue
            $azWs = Get-AzOperationalInsightsWorkspace -ErrorAction Stop
            foreach ($ws in $azWs) {
                $workspaces += [PSCustomObject]@{
                    Name          = $ws.Name
                    ResourceGroup = $ws.ResourceGroupName
                    WorkspaceId   = $ws.CustomerId
                    Location      = $ws.Location
                    Sku           = $ws.Sku
                }
            }
        }
        catch {
            Write-ColorOutput "  Could not list workspaces: $_" "Red"
            return $false
        }
    }

    $workspaces = $workspaces | Sort-Object Name

    if ($workspaces.Count -eq 0) {
        Write-ColorOutput "  No Log Analytics workspaces found in subscription '$($Session.SubscriptionName)'." "Red"
        return $false
    }

    # Auto-select if only one
    if ($workspaces.Count -eq 1) {
        $ws = $workspaces[0]
        $Session.WorkspaceName  = $ws.Name
        $Session.WorkspaceId    = $ws.WorkspaceId
        $Session.ResourceGroup  = $ws.ResourceGroup
        $Session.AuthToken      = Get-AccessToken
        Write-ColorOutput "  Auto-selected workspace: $($ws.Name)" "Green"
        return $true
    }

    # Show selection list
    Write-Host ""
    Write-Host "  ┌────┬──────────────────────────────┬──────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ ## │ Workspace                     │ Resource Group           │" -ForegroundColor DarkGray
    Write-Host "  ├────┼──────────────────────────────┼──────────────────────────┤" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $workspaces.Count; $i++) {
        $num  = ($i + 1).ToString().PadLeft(2)
        $name = $workspaces[$i].Name
        if ($name.Length -gt 28) { $name = $name.Substring(0, 25) + "..." }
        $namePad = $name.PadRight(28)

        $rg = $workspaces[$i].ResourceGroup
        if ($rg.Length -gt 24) { $rg = $rg.Substring(0, 21) + "..." }
        $rgPad = $rg.PadRight(24)

        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$num" -ForegroundColor Yellow -NoNewline
        Write-Host " │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$namePad" -ForegroundColor Cyan -NoNewline
        Write-Host "│ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$rgPad" -ForegroundColor White -NoNewline
        Write-Host "│" -ForegroundColor DarkGray
    }
    Write-Host "  └────┴──────────────────────────────┴──────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $choice = Read-Host "  Select workspace (1-$($workspaces.Count))"
        $idx    = 0
        $valid  = [int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $workspaces.Count
        if (-not $valid) { Write-ColorOutput "  Invalid choice, try again." "Red" }
    } while (-not $valid)

    $ws = $workspaces[$idx - 1]
    $Session.WorkspaceName = $ws.Name
    $Session.WorkspaceId   = $ws.WorkspaceId
    $Session.ResourceGroup = $ws.ResourceGroup
    $Session.AuthToken     = Get-AccessToken

    Write-ColorOutput "  Selected: $($ws.Name) (RG: $($ws.ResourceGroup))" "Green"
    return $true
}

#endregion

#region Export Module Members

