<#
.SYNOPSIS
    UI Helper Functions for Sentinel Local Backup
.DESCRIPTION
    Provides reusable UI functions for consistent output formatting,
    headers, and user interactions across Sentinel Local Backup.
.VERSION
    3.0
#>

#region Output Functions

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Writes colored output to the console
    .PARAMETER Message
        The message to display
    .PARAMETER Color
        The color to use (Green, Yellow, Red, Cyan, White, Gray)
    .EXAMPLE
        Write-ColorOutput "Success!" "Green"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Green", "Yellow", "Red", "Cyan", "White", "Gray")]
        [string]$Color = "White"
    )

    Write-Host $Message -ForegroundColor $Color
}

function Write-Banner {
    <#
    .SYNOPSIS
        Displays ASCII art banner for Sentinel Local Backup
    #>
    Clear-Host
    Write-Host ""
    Write-Host "  ███████╗███████╗███╗   ██╗████████╗██╗███╗   ██╗███████╗██╗     " -ForegroundColor Cyan
    Write-Host "  ██╔════╝██╔════╝████╗  ██║╚══██╔══╝██║████╗  ██║██╔════╝██║     " -ForegroundColor Cyan
    Write-Host "  ███████╗█████╗  ██╔██╗ ██║   ██║   ██║██╔██╗ ██║█████╗  ██║     " -ForegroundColor Blue
    Write-Host "  ╚════██║██╔══╝  ██║╚██╗██║   ██║   ██║██║╚██╗██║██╔══╝  ██║     " -ForegroundColor Blue
    Write-Host "  ███████║███████╗██║ ╚████║   ██║   ██║██║ ╚████║███████╗███████╗" -ForegroundColor DarkCyan
    Write-Host "  ╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "                    L O C A L   B A C K U P" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "   v1.0" -ForegroundColor White -NoNewline
    Write-Host "                                 Author: " -ForegroundColor DarkGray -NoNewline
    Write-Host "Phillipe (RycnCDL)" -ForegroundColor Cyan
    Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-SystemInfo {
    <#
    .SYNOPSIS
        Displays system information
    #>
    $psVersion = $PSVersionTable.PSVersion.ToString()
    $currentDate = Get-Date -Format "dd.MM.yyyy HH:mm"
    $osInfo = if ($IsLinux) { "Linux" } elseif ($IsMacOS) { "macOS" } else { "Windows" }

    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
    Write-Host "System Info" -ForegroundColor Yellow -NoNewline
    Write-Host "                                                  │" -ForegroundColor DarkGray
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray
    Write-Host "  │ PowerShell: " -ForegroundColor DarkGray -NoNewline
    Write-Host "$psVersion" -ForegroundColor Cyan -NoNewline
    Write-Host (" " * (47 - $psVersion.Length)) -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
    Write-Host "  │ Platform:   " -ForegroundColor DarkGray -NoNewline
    Write-Host "$osInfo" -ForegroundColor Cyan -NoNewline
    Write-Host (" " * (47 - $osInfo.Length)) -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
    Write-Host "  │ Date:       " -ForegroundColor DarkGray -NoNewline
    Write-Host "$currentDate" -ForegroundColor Cyan -NoNewline
    Write-Host (" " * (47 - $currentDate.Length)) -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-FeatureBox {
    <#
    .SYNOPSIS
        Displays feature categories in colored boxes
    #>
    Write-Host "  ┌────────────────────────┬────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Geladene Module" -ForegroundColor Green -NoNewline
    Write-Host "        │ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Status" -ForegroundColor Yellow -NoNewline
    Write-Host "                             │" -ForegroundColor DarkGray
    Write-Host "  ├────────────────────────┼────────────────────────────────────┤" -ForegroundColor DarkGray

    $modules = @(
        @{Name="[*] Tables"; Status="Available: CRUD, Plan, Retention"},
        @{Name="[*] DCR/DCE"; Status="Available: Management & Templates"},
        @{Name="[*] Analytics"; Status="Available: Rules, Creation, Templates"},
        @{Name="[*] Workbooks"; Status="Available: Export, Import, Delete"},
        @{Name="[*] Incidents"; Status="Available: Full Management & Bulk"},
        @{Name="[*] Backup"; Status="Available: Export All Configs"}
    )

    foreach ($module in $modules) {
        $nameLen = $module.Name.Length + 2
        $statusLen = $module.Status.Length
        Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
        Write-Host $module.Name -ForegroundColor White -NoNewline
        Write-Host (" " * (22 - $nameLen)) -NoNewline
        Write-Host "│ " -ForegroundColor DarkGray -NoNewline
        Write-Host $module.Status -ForegroundColor Green -NoNewline
        Write-Host (" " * (36 - $statusLen)) -NoNewline
        Write-Host "│" -ForegroundColor DarkGray
    }

    Write-Host "  └────────────────────────┴────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-MenuHeader {
    <#
    .SYNOPSIS
        Displays enhanced menu header with icon and context
    .PARAMETER Title
        Menu title
    .PARAMETER Icon
        Icon/Emoji for menu
    .PARAMETER ShowContext
        Show session context (subscription, workspace)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter(Mandatory=$false)]
        [string]$Icon = "[*]",

        [Parameter(Mandatory=$false)]
        [bool]$ShowContext = $true
    )

    Clear-Host
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  " -ForegroundColor Cyan -NoNewline
    Write-Host "$Icon $Title" -ForegroundColor White -NoNewline
    $padding = 56 - ($Title.Length + $Icon.Length + 1)
    Write-Host (" " * $padding) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    if ($ShowContext) {
        try {
            $Session = Get-SentinelSession
            if ($Session.SubscriptionName -and $Session.WorkspaceName) {
                Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
                Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
                Write-Host "Context" -ForegroundColor Yellow -NoNewline
                Write-Host "                                                      │" -ForegroundColor DarkGray
                Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

                # Subscription
                Write-Host "  │ Subscription: " -ForegroundColor DarkGray -NoNewline
                $subDisplay = $Session.SubscriptionName
                if ($subDisplay.Length -gt 42) { $subDisplay = $subDisplay.Substring(0, 39) + "..." }
                Write-Host "$subDisplay" -ForegroundColor Cyan -NoNewline
                Write-Host (" " * (44 - $subDisplay.Length)) -NoNewline
                Write-Host "│" -ForegroundColor DarkGray

                # Workspace
                Write-Host "  │ Workspace:    " -ForegroundColor DarkGray -NoNewline
                $wsDisplay = $Session.WorkspaceName
                if ($wsDisplay.Length -gt 42) { $wsDisplay = $wsDisplay.Substring(0, 39) + "..." }
                Write-Host "$wsDisplay" -ForegroundColor Cyan -NoNewline
                Write-Host (" " * (44 - $wsDisplay.Length)) -NoNewline
                Write-Host "│" -ForegroundColor DarkGray

                # Resource Group
                Write-Host "  │ Res. Group:   " -ForegroundColor DarkGray -NoNewline
                $rgDisplay = $Session.ResourceGroup
                if ($rgDisplay.Length -gt 42) { $rgDisplay = $rgDisplay.Substring(0, 39) + "..." }
                Write-Host "$rgDisplay" -ForegroundColor Cyan -NoNewline
                Write-Host (" " * (44 - $rgDisplay.Length)) -NoNewline
                Write-Host "│" -ForegroundColor DarkGray

                Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
                Write-Host ""
            }
        } catch {
            # Silently skip if session not available
        }
    }
}

function Write-MainMenuHeader {
    <#
    .SYNOPSIS
        Displays dashboard-style header for main menu with stats
    #>
    Clear-Host
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  " -ForegroundColor Cyan -NoNewline
    Write-Host "[Home] Main Menu" -ForegroundColor White -NoNewline
    Write-Host " " -NoNewline
    Write-Host "- Dashboard" -ForegroundColor DarkCyan -NoNewline
    Write-Host "                                  ║" -ForegroundColor Cyan
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    try {
        $Session = Get-SentinelSession
        $Config = Get-SentinelConfig

        # User Info
        $currentUser = "Unknown"
        try {
            if ($Session.UseAzModule) {
                $context = Get-AzContext -ErrorAction SilentlyContinue
                if ($context) { $currentUser = $context.Account.Id }
            } else {
                $account = az account show 2>$null | ConvertFrom-Json
                if ($account) { $currentUser = $account.user.name }
            }
        } catch {}

        Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Session Status" -ForegroundColor Green -NoNewline
        Write-Host "                                               │" -ForegroundColor DarkGray
        Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

        # User
        Write-Host "  │ User:         " -ForegroundColor DarkGray -NoNewline
        $userDisplay = $currentUser
        if ($userDisplay.Length -gt 42) { $userDisplay = $userDisplay.Substring(0, 39) + "..." }
        Write-Host "$userDisplay" -ForegroundColor Green -NoNewline
        Write-Host (" " * (44 - $userDisplay.Length)) -NoNewline
        Write-Host "│" -ForegroundColor DarkGray

        # Subscription
        Write-Host "  │ Subscription: " -ForegroundColor DarkGray -NoNewline
        $subDisplay = $Session.SubscriptionName
        if ($subDisplay.Length -gt 42) { $subDisplay = $subDisplay.Substring(0, 39) + "..." }
        Write-Host "$subDisplay" -ForegroundColor Cyan -NoNewline
        Write-Host (" " * (44 - $subDisplay.Length)) -NoNewline
        Write-Host "│" -ForegroundColor DarkGray

        # Workspace
        Write-Host "  │ Workspace:    " -ForegroundColor DarkGray -NoNewline
        $wsDisplay = $Session.WorkspaceName
        if ($wsDisplay.Length -gt 42) { $wsDisplay = $wsDisplay.Substring(0, 39) + "..." }
        Write-Host "$wsDisplay" -ForegroundColor Cyan -NoNewline
        Write-Host (" " * (44 - $wsDisplay.Length)) -NoNewline
        Write-Host "│" -ForegroundColor DarkGray

        # Resource Group
        Write-Host "  │ Res. Group:   " -ForegroundColor DarkGray -NoNewline
        $rgDisplay = $Session.ResourceGroup
        if ($rgDisplay.Length -gt 42) { $rgDisplay = $rgDisplay.Substring(0, 39) + "..." }
        Write-Host "$rgDisplay" -ForegroundColor Cyan -NoNewline
        Write-Host (" " * (44 - $rgDisplay.Length)) -NoNewline
        Write-Host "│" -ForegroundColor DarkGray

        # Debug Mode
        if ($Config.DebugMode) {
            Write-Host "  │ Debug Mode:   " -ForegroundColor DarkGray -NoNewline
            Write-Host "ENABLED" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * 38) -NoNewline
            Write-Host "│" -ForegroundColor DarkGray
        }

        Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
        Write-Host ""
    } catch {
        # Minimal header if session fails
        Write-Host "  Session not initialized" -ForegroundColor Yellow
        Write-Host ""
    }
}

function Write-Header {
    <#
    .SYNOPSIS
        Legacy header function - redirects to Write-MenuHeader
    .PARAMETER Title
        The title to display in the header
    .EXAMPLE
        Write-Header "Main Menu"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    # Redirect to new function
    Write-MenuHeader -Title $Title -Icon "[*]" -ShowContext $true
}

#endregion

#region Interaction Functions

function Get-YesNoChoice {
    <#
    .SYNOPSIS
        Prompts the user for a Yes/No choice
    .PARAMETER Message
        The message to display
    .PARAMETER DefaultChoice
        The default choice (Y or N)
    .RETURN
        $true for Yes, $false for No
    .EXAMPLE
        $result = Get-YesNoChoice "Continue?" "Y"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Y", "N")]
        [string]$DefaultChoice = "Y"
    )

    $choices = @("&Yes", "&No")
    $default = if ($DefaultChoice -eq "Y") { 0 } else { 1 }
    $decision = $Host.UI.PromptForChoice("", $Message, $choices, $default)

    return $decision -eq 0
}

#endregion

#region Export Module Members

