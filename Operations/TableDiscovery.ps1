<#
.SYNOPSIS
    Table Discovery Functions for Sentinel Local Backup
.DESCRIPTION
    Functions to discover, list, and select Log Analytics workspace tables
    for backup operations. Supports interactive selection and pattern matching.
.VERSION
    1.0
#>

function Get-WorkspaceTables {
    <#
    .SYNOPSIS
        Retrieves all tables from the Log Analytics workspace
    .DESCRIPTION
        Queries the Log Analytics workspace to list all available tables.
        Returns both custom and standard tables with metadata.
    .PARAMETER IncludeStandard
        Include standard/built-in tables (e.g., AzureActivity, SecurityEvent).
        Default: $true
    .PARAMETER IncludeCustomOnly
        Only return custom tables (tables created by the user/connectors).
    .PARAMETER TableNameFilter
        Optional wildcard filter, e.g. "Security*" or "*Event"
    .EXAMPLE
        $tables = Get-WorkspaceTables
    .EXAMPLE
        $tables = Get-WorkspaceTables -TableNameFilter "Security*"
    #>
    param(
        [Parameter(Mandatory=$false)]
        [bool]$IncludeStandard = $true,

        [Parameter(Mandatory=$false)]
        [switch]$IncludeCustomOnly,

        [Parameter(Mandatory=$false)]
        [string]$TableNameFilter = ""
    )

    $Session = Get-SentinelSession
    $Config  = Get-SentinelConfig

    if (-not $Session.WorkspaceId) {
        throw "No workspace configured. Run Connect-ToAzure and set a workspace first."
    }

    Write-ColorOutput "Discovering tables in workspace '$($Session.WorkspaceName)'..." "Cyan"

    $tables = @()

    try {
        # --- Method 1: REST API (preferred, returns table metadata) ---
        $uri = "$($Config.ManagementApiUrl)/subscriptions/$($Session.SubscriptionId)" +
               "/resourceGroups/$($Session.ResourceGroup)" +
               "/providers/Microsoft.OperationalInsights/workspaces/$($Session.WorkspaceName)" +
               "/tables?api-version=2022-10-01"

        $token  = $Session.AuthToken
        $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type"  = "application/json"
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop

        foreach ($table in $response.value) {
            $tableObj = [PSCustomObject]@{
                Name            = $table.name
                Kind            = if ($table.properties.schema.tableSubType) { $table.properties.schema.tableSubType } else { "Standard" }
                RetentionDays   = $table.properties.retentionInDays
                TotalRetention  = $table.properties.totalRetentionInDays
                Plan            = $table.properties.plan
                RowCount        = $null   # populated later if needed
                SizeGB          = $null
                LastIngestion   = $null
            }
            $tables += $tableObj
        }

        Write-ColorOutput "  Found $($tables.Count) tables via REST API" "Gray"
    }
    catch {
        Write-ColorOutput "  REST API unavailable, falling back to KQL..." "Yellow"

        # --- Method 2: KQL fallback ---
        try {
            $kql = "search * | summarize count() by Type | project TableName=Type | sort by TableName asc"

            $queryUri = "$($Config.ManagementApiUrl)/subscriptions/$($Session.SubscriptionId)" +
                        "/resourceGroups/$($Session.ResourceGroup)" +
                        "/providers/Microsoft.OperationalInsights/workspaces/$($Session.WorkspaceName)" +
                        "/query?api-version=2020-08-01"

            $body = @{ query = $kql } | ConvertTo-Json

            $queryResponse = Invoke-RestMethod -Uri $queryUri -Headers $headers `
                                               -Method POST -Body $body -ErrorAction Stop

            $rows = $queryResponse.tables[0].rows
            foreach ($row in $rows) {
                $tableObj = [PSCustomObject]@{
                    Name           = $row[0]
                    Kind           = "Unknown"
                    RetentionDays  = $null
                    TotalRetention = $null
                    Plan           = $null
                    RowCount       = $null
                    SizeGB         = $null
                    LastIngestion  = $null
                }
                $tables += $tableObj
            }

            Write-ColorOutput "  Found $($tables.Count) tables via KQL" "Gray"
        }
        catch {
            throw "Could not retrieve tables: $_"
        }
    }

    # Apply filters
    if ($IncludeCustomOnly) {
        $tables = $tables | Where-Object { $_.Kind -eq "CustomLog" -or $_.Name -match "_CL$" }
        Write-ColorOutput "  After custom-only filter: $($tables.Count) tables" "Gray"
    }

    if ($TableNameFilter) {
        $tables = $tables | Where-Object { $_.Name -like $TableNameFilter }
        Write-ColorOutput "  After name filter '$TableNameFilter': $($tables.Count) tables" "Gray"
    }

    return $tables | Sort-Object Name
}

function Find-Tables {
    <#
    .SYNOPSIS
        Finds tables matching a pattern in the workspace
    .DESCRIPTION
        Searches table names using wildcard or regex matching.
        Useful for quickly locating specific table groups.
    .PARAMETER Pattern
        Wildcard pattern to match (e.g. "Security*", "*Event", "*Custom*")
    .PARAMETER UseRegex
        Use regex instead of wildcard matching
    .EXAMPLE
        Find-Tables "Security*"
    .EXAMPLE
        Find-Tables "^Security" -UseRegex
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pattern,

        [Parameter(Mandatory=$false)]
        [switch]$UseRegex
    )

    $allTables = Get-WorkspaceTables

    if ($UseRegex) {
        return $allTables | Where-Object { $_.Name -match $Pattern }
    } else {
        return $allTables | Where-Object { $_.Name -like $Pattern }
    }
}

function Select-Tables {
    <#
    .SYNOPSIS
        Interactive table selection UI
    .DESCRIPTION
        Displays a numbered list of available workspace tables and lets the user
        select one or more for backup. Supports:
          - Single selection by number
          - Range selection (e.g. "1-5")
          - Multiple selections (e.g. "1,3,7")
          - "all" to select everything
          - Pattern filter to narrow the list
    .PARAMETER Tables
        Pre-fetched table list from Get-WorkspaceTables. If omitted, fetches live.
    .PARAMETER AllowMultiple
        Allow selecting multiple tables (default: $true)
    .EXAMPLE
        $selected = Select-Tables
    .EXAMPLE
        $tables  = Get-WorkspaceTables -TableNameFilter "Security*"
        $selected = Select-Tables -Tables $tables
    #>
    param(
        [Parameter(Mandatory=$false)]
        [array]$Tables = $null,

        [Parameter(Mandatory=$false)]
        [bool]$AllowMultiple = $true
    )

    # Fetch tables if not provided
    if (-not $Tables) {
        $Tables = Get-WorkspaceTables
    }

    if ($Tables.Count -eq 0) {
        Write-ColorOutput "No tables found in workspace." "Yellow"
        return @()
    }

    while ($true) {
        # Display table list
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
        Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
        Write-Host "Available Tables" -ForegroundColor Yellow -NoNewline
        Write-Host "                                               │" -ForegroundColor DarkGray
        Write-Host "  ├────┬────────────────────────────────┬─────────────────────────┤" -ForegroundColor DarkGray
        Write-Host "  │ ## │ Table Name                     │ Plan / Retention         │" -ForegroundColor DarkGray
        Write-Host "  ├────┼────────────────────────────────┼─────────────────────────┤" -ForegroundColor DarkGray

        for ($i = 0; $i -lt $Tables.Count; $i++) {
            $t       = $Tables[$i]
            $num     = ($i + 1).ToString().PadLeft(2)
            $name    = $t.Name
            if ($name.Length -gt 30) { $name = $name.Substring(0, 27) + "..." }
            $namePad = $name.PadRight(30)

            $meta = ""
            if ($t.Plan) { $meta += $t.Plan }
            if ($t.RetentionDays) { $meta += " / $($t.RetentionDays)d" }
            if (-not $meta) { $meta = "-" }
            $metaPad = $meta.PadRight(23)

            $color = if ($t.Kind -eq "CustomLog" -or $t.Name -match "_CL$") { "Cyan" } else { "White" }

            Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
            Write-Host "$num" -ForegroundColor Yellow -NoNewline
            Write-Host " │ " -ForegroundColor DarkGray -NoNewline
            Write-Host "$namePad" -ForegroundColor $color -NoNewline
            Write-Host "│ " -ForegroundColor DarkGray -NoNewline
            Write-Host "$metaPad" -ForegroundColor Gray -NoNewline
            Write-Host "│" -ForegroundColor DarkGray
        }

        Write-Host "  └────┴────────────────────────────────┴─────────────────────────┘" -ForegroundColor DarkGray
        Write-Host "  " -NoNewline
        Write-Host "Cyan" -ForegroundColor Cyan -NoNewline
        Write-Host " = custom log table (_CL suffix)" -ForegroundColor Gray
        Write-Host ""

        if ($AllowMultiple) {
            Write-Host "  Select tables to back up:" -ForegroundColor Yellow
            Write-Host "    - Single:   " -NoNewline; Write-Host "3" -ForegroundColor Cyan
            Write-Host "    - Multiple: " -NoNewline; Write-Host "1,3,5" -ForegroundColor Cyan
            Write-Host "    - Range:    " -NoNewline; Write-Host "1-5" -ForegroundColor Cyan
            Write-Host "    - All:      " -NoNewline; Write-Host "all" -ForegroundColor Cyan
            Write-Host "    - Filter:   " -NoNewline; Write-Host "f:Security*" -ForegroundColor Cyan
            Write-Host "    - Back:     " -NoNewline; Write-Host "0 or q" -ForegroundColor Gray
        } else {
            Write-Host "  Enter table number (0 to go back):" -ForegroundColor Yellow
        }

        Write-Host ""
        $input = Read-Host "  > "
        $input = $input.Trim()

        # Back/cancel
        if ($input -eq "0" -or $input -eq "q" -or $input -eq "") {
            return @()
        }

        # Filter mode: f:Pattern
        if ($input -match "^f:(.+)$") {
            $filterPattern = $Matches[1]
            $Tables = $Tables | Where-Object { $_.Name -like $filterPattern }
            Write-ColorOutput "  Filtered to $($Tables.Count) tables matching '$filterPattern'" "Gray"
            continue
        }

        # Select all
        if ($input -eq "all") {
            return $Tables
        }

        # Parse selection
        $selected = @()
        $parts    = $input -split ","

        $parseError = $false
        foreach ($part in $parts) {
            $part = $part.Trim()

            # Range: e.g. "1-5"
            if ($part -match "^(\d+)-(\d+)$") {
                $start = [int]$Matches[1]
                $end   = [int]$Matches[2]
                if ($start -lt 1 -or $end -gt $Tables.Count -or $start -gt $end) {
                    Write-ColorOutput "  Invalid range: $part (valid: 1-$($Tables.Count))" "Red"
                    $parseError = $true
                    break
                }
                for ($r = $start; $r -le $end; $r++) {
                    $selected += $Tables[$r - 1]
                }
            }
            # Single number
            elseif ($part -match "^\d+$") {
                $idx = [int]$part
                if ($idx -lt 1 -or $idx -gt $Tables.Count) {
                    Write-ColorOutput "  Invalid number: $idx (valid: 1-$($Tables.Count))" "Red"
                    $parseError = $true
                    break
                }
                $selected += $Tables[$idx - 1]
            }
            else {
                Write-ColorOutput "  Unrecognized input: '$part'" "Red"
                $parseError = $true
                break
            }

            if (-not $AllowMultiple) { break }
        }

        if ($parseError) { continue }

        # Remove duplicates
        $selected = $selected | Sort-Object Name -Unique

        if ($selected.Count -eq 0) {
            Write-ColorOutput "  No tables selected." "Yellow"
            continue
        }

        # Confirm selection
        Write-Host ""
        Write-Host "  Selected $($selected.Count) table(s):" -ForegroundColor Green
        foreach ($t in $selected) {
            Write-Host "    - $($t.Name)" -ForegroundColor Cyan
        }
        Write-Host ""

        $confirm = Get-YesNoChoice "Proceed with these tables?" "Y"
        if ($confirm) {
            return $selected
        }
        # else loop back and let user reselect
    }
}
