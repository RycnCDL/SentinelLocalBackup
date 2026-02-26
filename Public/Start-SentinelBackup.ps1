<#
.SYNOPSIS
    Start-SentinelBackup - Main entry point for Sentinel Local Backup
.DESCRIPTION
    Interactive wizard that guides the user through:
      1. Azure authentication
      2. Subscription selection
      3. Log Analytics workspace selection
      4. Table discovery and selection
      5. Export configuration (output path, time range, batch size)
      6. Execution and summary

    Designed for compliance-focused environments (e.g. German customers)
    who need local copies of Sentinel/Log Analytics data in CSV format.
.VERSION
    1.0
#>

function Start-SentinelBackup {
    <#
    .SYNOPSIS
        Interactive guided export wizard for Sentinel Local Backup
    .DESCRIPTION
        Orchestrates authentication, workspace selection, table selection,
        and export configuration into a single interactive session.
    .PARAMETER OutputPath
        Pre-set output directory. If omitted, the wizard will prompt for it.
    .PARAMETER SkipBanner
        Skip the ASCII art banner (useful for automation/scripts).
    .EXAMPLE
        Start-SentinelBackup
    .EXAMPLE
        Start-SentinelBackup -OutputPath "D:\ComplianceBackups"
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$OutputPath = "",

        [Parameter(Mandatory=$false)]
        [switch]$SkipBanner
    )

    # ── Step 0: Banner ──────────────────────────────────────────────────────
    if (-not $SkipBanner) {
        Write-Banner
        Write-Host "  Sentinel Local Backup v1.0" -ForegroundColor Cyan
        Write-Host "  Export Log Analytics tables to local CSV files" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Press any key to start..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }

    # ── Step 1: Authentication ───────────────────────────────────────────────
    Write-MenuHeader -Title "Step 1: Authentication" -Icon "[Auth]" -ShowContext $false

    $authOk = Connect-ToAzure
    if (-not $authOk) {
        Write-ColorOutput "Authentication failed. Exiting." "Red"
        return
    }

    # ── Step 2: Subscription ─────────────────────────────────────────────────
    Write-MenuHeader -Title "Step 2: Select Subscription" -Icon "[Sub]" -ShowContext $false

    $subOk = Select-Subscription
    if (-not $subOk) {
        Write-ColorOutput "No subscription selected. Exiting." "Red"
        return
    }

    # ── Step 3: Workspace ────────────────────────────────────────────────────
    Write-MenuHeader -Title "Step 3: Select Workspace" -Icon "[WS]" -ShowContext $false

    $wsOk = Select-Workspace
    if (-not $wsOk) {
        Write-ColorOutput "No workspace selected. Exiting." "Red"
        return
    }

    # ── Step 4: Table Selection ───────────────────────────────────────────────
    Write-MenuHeader -Title "Step 4: Select Tables" -Icon "[Tables]" -ShowContext $true

    Write-ColorOutput "  Fetching available tables from workspace..." "Cyan"
    $selectedTables = Select-Tables

    if (-not $selectedTables -or $selectedTables.Count -eq 0) {
        Write-ColorOutput "No tables selected. Exiting." "Yellow"
        return
    }

    # ── Step 5: Export Configuration ──────────────────────────────────────────
    Write-MenuHeader -Title "Step 5: Export Settings" -Icon "[Config]" -ShowContext $true

    # Output path
    if (-not $OutputPath) {
        Write-Host "  Output directory for CSV files:" -ForegroundColor Yellow
        Write-Host "  (Press Enter for default: C:\SentinelBackups)" -ForegroundColor Gray
        $inputPath = Read-Host "  > "
        $OutputPath = if ($inputPath.Trim()) { $inputPath.Trim() } else { "C:\SentinelBackups" }
    }

    # Verify/create output path
    if (-not (Test-Path $OutputPath)) {
        $create = Get-YesNoChoice "Output directory '$OutputPath' does not exist. Create it?" "Y"
        if ($create) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            Write-ColorOutput "  Created: $OutputPath" "Green"
        } else {
            Write-ColorOutput "Output directory not created. Exiting." "Yellow"
            return
        }
    }

    # Time range
    Write-Host ""
    Write-Host "  Time range options:" -ForegroundColor Yellow
    Write-Host "    1. Last 7 days   (default for small tables)"
    Write-Host "    2. Last 30 days  (recommended)"
    Write-Host "    3. Last 90 days"
    Write-Host "    4. Last 365 days (may be slow for large tables)"
    Write-Host "    5. Custom range"
    Write-Host ""
    $rangeChoice = Read-Host "  Select time range (1-5, default=2)"

    $startTime = $null
    $endTime   = (Get-Date).ToUniversalTime()

    switch ($rangeChoice.Trim()) {
        "1" { $startTime = $endTime.AddDays(-7) }
        "3" { $startTime = $endTime.AddDays(-90) }
        "4" { $startTime = $endTime.AddDays(-365) }
        "5" {
            do {
                $startStr = Read-Host "  Start date (yyyy-MM-dd)"
                $ok = [datetime]::TryParse($startStr, [ref]$startTime)
                if (-not $ok) { Write-ColorOutput "  Invalid date format." "Red" }
            } while (-not $ok)
            $startTime = $startTime.ToUniversalTime()
        }
        default { $startTime = $endTime.AddDays(-30) }
    }

    # Batch size
    Write-Host ""
    Write-Host "  Batch size (days per API call):" -ForegroundColor Yellow
    Write-Host "    1. 7 days   (recommended for most tables)"
    Write-Host "    2. 1 day    (for high-volume tables like SecurityEvent)"
    Write-Host "    3. 14 days  (for low-volume tables)"
    Write-Host "    4. 30 days  (for very sparse tables)"
    Write-Host ""
    $batchChoice = Read-Host "  Select batch size (1-4, default=1)"

    $batchDays = switch ($batchChoice.Trim()) {
        "2" { 1 }
        "3" { 14 }
        "4" { 30 }
        default { 7 }
    }

    # ── Step 6: Confirm & Run ──────────────────────────────────────────────────
    Write-MenuHeader -Title "Step 6: Confirm & Export" -Icon "[Run]" -ShowContext $true

    $Session = Get-SentinelSession
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  Export Plan                                                │" -ForegroundColor DarkGray
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

    $planLines = @(
        @{ L = "Workspace"; V = $Session.WorkspaceName },
        @{ L = "Tables";    V = "$($selectedTables.Count) selected" },
        @{ L = "From";      V = $startTime.ToString("yyyy-MM-dd HH:mm") + " UTC" },
        @{ L = "To";        V = $endTime.ToString("yyyy-MM-dd HH:mm") + " UTC" },
        @{ L = "Batch";     V = "$batchDays day(s) per API call" },
        @{ L = "Output";    V = $OutputPath }
    )
    foreach ($pl in $planLines) {
        $label = $pl.L.PadRight(10)
        $val   = $pl.V
        if ($val.Length -gt 43) { $val = "..." + $val.Substring($val.Length - 40) }
        Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$label" -ForegroundColor Yellow -NoNewline
        Write-Host ": $val" -ForegroundColor White -NoNewline
        $pad = 53 - ($label.Length + $val.Length + 2)
        if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
        Write-Host "│" -ForegroundColor DarkGray
    }
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray
    Write-Host "  │  Tables:                                                    │" -ForegroundColor DarkGray
    foreach ($t in $selectedTables) {
        $name = "    - $($t.Name)"
        if ($name.Length -gt 60) { $name = $name.Substring(0, 57) + "..." }
        $namePad = $name.PadRight(60)
        Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$namePad" -ForegroundColor Cyan -NoNewline
        Write-Host "│" -ForegroundColor DarkGray
    }
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    $confirm = Get-YesNoChoice "Start export?" "Y"
    if (-not $confirm) {
        Write-ColorOutput "Export cancelled." "Yellow"
        return
    }

    # ── Run exports ────────────────────────────────────────────────────────────
    $results   = @()
    $succeeded = 0
    $failed    = 0

    foreach ($table in $selectedTables) {
        Write-Host ""
        Write-ColorOutput "━━━ Exporting: $($table.Name) ━━━" "Cyan"

        try {
            $result = Export-TableToCSV `
                -TableName  $table.Name `
                -OutputPath $OutputPath `
                -StartTime  $startTime `
                -EndTime    $endTime `
                -BatchDays  $batchDays `
                -SkipConfirm

            $results += $result
            $succeeded++
        }
        catch {
            Write-ColorOutput "  [FAIL] $($table.Name): $_" "Red"
            $results += [PSCustomObject]@{
                TableName = $table.Name
                Success   = $false
                Error     = $_.Exception.Message
            }
            $failed++
        }
    }

    # ── Final Summary ──────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  Backup Complete                                          ║" -ForegroundColor Cyan
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  Results                                                    │" -ForegroundColor DarkGray
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

    foreach ($r in $results) {
        if ($r.Success) {
            $summary = "$($r.TotalRows.ToString('N0')) rows | $($r.SizeMB) MB"
            $name    = $r.TableName.PadRight(28)
            Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
            Write-Host "[OK] " -ForegroundColor Green -NoNewline
            Write-Host "$name" -ForegroundColor White -NoNewline
            Write-Host "$summary" -ForegroundColor Cyan -NoNewline
            $pad = 24 - $summary.Length
            if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
            Write-Host "│" -ForegroundColor DarkGray
        } else {
            $name = $r.TableName.PadRight(28)
            Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
            Write-Host "[FAIL] " -ForegroundColor Red -NoNewline
            Write-Host "$name" -ForegroundColor White -NoNewline
            Write-Host "                       │" -ForegroundColor DarkGray
        }
    }

    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

    $statusColor = if ($failed -eq 0) { "Green" } else { "Yellow" }
    $statusLine  = "  Succeeded: $succeeded  |  Failed: $failed"
    Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
    Write-Host $statusLine -ForegroundColor $statusColor -NoNewline
    $pad = 57 - $statusLine.Length
    if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
    Write-Host "│" -ForegroundColor DarkGray

    Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
    Write-Host "Output: $OutputPath" -ForegroundColor Gray -NoNewline
    $outLen = "Output: $OutputPath".Length
    $pad    = 57 - $outLen
    if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
    Write-Host "│" -ForegroundColor DarkGray

    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    return $results
}
