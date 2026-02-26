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
                $azCliLoggedIn = $true
                $currentUser = $account.user.name
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
        Gets an Azure access token for management API
    .PARAMETER ForceRefresh
        Forces token refresh (not implemented yet)
    .RETURN
        Access token string or $null if error
    #>
    param(
        [switch]$ForceRefresh = $false
    )

    $Config = Get-SentinelConfig
    $Session = Get-SentinelSession

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
            $tokenObj = Get-AzAccessToken -ResourceUrl $Config.ManagementApiUrl -ErrorAction Stop

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
            # Resource URL WITH trailing slash for Azure CLI
            $tokenJson = az account get-access-token --resource "$($Config.ManagementApiUrl)/" 2>$null

            if ($LASTEXITCODE -ne 0) {
                Write-ColorOutput "Azure CLI Session abgelaufen! Bitte erneut authentifizieren." "Red"
                return $null
            }

            $tokenObj = $tokenJson | ConvertFrom-Json
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

#region Export Module Members

