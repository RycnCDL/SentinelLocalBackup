<#
.SYNOPSIS
    Resume-SentinelBackup - Resume interrupted Sentinel Local Backup exports
.DESCRIPTION
    Scans the backup output directory for checkpoint.json files left behind by
    interrupted Export-TableToCSV runs. Lists them and lets the user pick which
    ones to resume. Passes each checkpoint to Export-TableToCSV which appends
    to the existing CSV from where it stopped.
.VERSION
    1.0
#>

function Resume-SentinelBackup {
    <#
    .SYNOPSIS
        Resume one or more interrupted Sentinel backup exports
    .DESCRIPTION
        Scans the given output directory recursively for checkpoint.json files.
        Each file represents a partially-completed export. The user selects
        which to resume and Export-TableToCSV continues from the last
        successfully written batch.
    .PARAMETER OutputPath
        Root backup directory to scan for incomplete exports.
        Default: C:\SentinelBackups
    .PARAMETER CheckpointPath
        Path to a specific checkpoint.json to resume directly (skips the scan).
    .EXAMPLE
        Resume-SentinelBackup
    .EXAMPLE
        Resume-SentinelBackup -OutputPath "D:\ComplianceBackups"
    .EXAMPLE
        Resume-SentinelBackup -CheckpointPath "C:\SentinelBackups\SecurityEvent\20250226_143000\checkpoint.json"
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$OutputPath = "C:\SentinelBackups",

        [Parameter(Mandatory=$false)]
        [string]$CheckpointPath = ""
    )

    Write-MenuHeader -Title "Resume Backup" -Icon "[Resume]" -ShowContext $true

    # ── Direct checkpoint path provided ────────────────────────────────────
    if ($CheckpointPath -ne "" -and (Test-Path $CheckpointPath)) {
        $cp = Get-Content $CheckpointPath -Raw | ConvertFrom-Json
        Write-ColorOutput "  Resuming: $($cp.tableName) from $($cp.lastCompletedBatchEnd)" "Cyan"
        Write-ColorOutput "  Rows already written: $($cp.totalRowsWritten.ToString('N0'))" "Gray"
        Write-Host ""

        $ok = Get-YesNoChoice "Resume this export?" "Y"
        if (-not $ok) { Write-ColorOutput "Cancelled." "Yellow"; return }

        return Export-TableToCSV -ResumeCheckpointPath $CheckpointPath
    }

    # ── Scan for incomplete exports ─────────────────────────────────────────
    Write-ColorOutput "  Scanning for incomplete exports in: $OutputPath" "Cyan"

    if (-not (Test-Path $OutputPath)) {
        Write-ColorOutput "  Directory not found: $OutputPath" "Red"
        return
    }

    $checkpoints = Get-ChildItem -Path $OutputPath -Recurse -Filter "checkpoint.json" -ErrorAction SilentlyContinue

    if (-not $checkpoints -or $checkpoints.Count -eq 0) {
        Write-Host ""
        Write-ColorOutput "  No incomplete exports found in '$OutputPath'." "Green"
        Write-ColorOutput "  All previous exports completed successfully." "Gray"
        Write-Host ""
        return
    }

    # Parse each checkpoint
    $incomplete = @()
    foreach ($f in $checkpoints) {
        try {
            $cp = Get-Content $f.FullName -Raw | ConvertFrom-Json
            $incomplete += [PSCustomObject]@{
                CheckpointFile    = $f.FullName
                TableName         = $cp.tableName
                RunId             = $cp.runId
                LastBatchEnd      = $cp.lastCompletedBatchEnd
                TotalRowsWritten  = $cp.totalRowsWritten
                StartTime         = $cp.startTime
                EndTime           = $cp.endTime
                BatchDays         = $cp.batchDays
                SavedAt           = $cp.savedAt
                WorkspaceName     = $cp.workspaceName
                CsvPath           = $cp.csvPath
            }
        }
        catch {
            Write-ColorOutput "  [WARN] Could not parse: $($f.FullName)" "Yellow"
        }
    }

    if ($incomplete.Count -eq 0) {
        Write-ColorOutput "  No valid checkpoints found." "Yellow"
        return
    }

    # ── Display incomplete exports ──────────────────────────────────────────
    Write-Host ""
    Write-Host "  ┌────┬──────────────────────────┬──────────────┬────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ ## │ Table                     │ Rows Written │ Interrupted At  │" -ForegroundColor DarkGray
    Write-Host "  ├────┼──────────────────────────┼──────────────┼────────────────┤" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $incomplete.Count; $i++) {
        $r    = $incomplete[$i]
        $num  = ($i + 1).ToString().PadLeft(2)

        $name = $r.TableName
        if ($name.Length -gt 24) { $name = $name.Substring(0, 21) + "..." }
        $namePad = $name.PadRight(24)

        $rows = $r.TotalRowsWritten.ToString('N0').PadRight(12)

        $savedAt = if ($r.SavedAt) {
            try { ([datetime]::Parse($r.SavedAt)).ToString("MM-dd HH:mm") } catch { "Unknown" }
        } else { "Unknown" }
        $savedPad = $savedAt.PadRight(14)

        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$num" -ForegroundColor Yellow -NoNewline
        Write-Host " │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$namePad" -ForegroundColor Cyan -NoNewline
        Write-Host "│ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$rows" -ForegroundColor White -NoNewline
        Write-Host "│ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$savedPad" -ForegroundColor Gray -NoNewline
        Write-Host "│" -ForegroundColor DarkGray
    }

    Write-Host "  └────┴──────────────────────────┴──────────────┴────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "    - Single:  " -NoNewline; Write-Host "2" -ForegroundColor Cyan
    Write-Host "    - Multiple:" -NoNewline; Write-Host " 1,3" -ForegroundColor Cyan
    Write-Host "    - All:     " -NoNewline; Write-Host "all" -ForegroundColor Cyan
    Write-Host "    - Cancel:  " -NoNewline; Write-Host "0 or q" -ForegroundColor Gray
    Write-Host ""

    $input = (Read-Host "  Select exports to resume").Trim()

    if ($input -eq "0" -or $input -eq "q" -or $input -eq "") {
        Write-ColorOutput "Cancelled." "Yellow"
        return
    }

    # Parse selection
    $toResume = @()

    if ($input -eq "all") {
        $toResume = $incomplete
    } else {
        foreach ($part in ($input -split ",")) {
            $part = $part.Trim()
            $idx  = 0
            if ([int]::TryParse($part, [ref]$idx) -and $idx -ge 1 -and $idx -le $incomplete.Count) {
                $toResume += $incomplete[$idx - 1]
            } else {
                Write-ColorOutput "  Skipping invalid selection: '$part'" "Yellow"
            }
        }
    }

    if ($toResume.Count -eq 0) {
        Write-ColorOutput "No valid exports selected." "Yellow"
        return
    }

    # ── Confirm ────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  Resuming $($toResume.Count) export(s):" -ForegroundColor Green
    foreach ($r in $toResume) {
        $pct = if ($r.TotalRowsWritten -gt 0) { "~$($r.TotalRowsWritten.ToString('N0')) rows done" } else { "0 rows done" }
        Write-Host "    - $($r.TableName)  ($pct)" -ForegroundColor Cyan
    }
    Write-Host ""

    $ok = Get-YesNoChoice "Proceed?" "Y"
    if (-not $ok) { Write-ColorOutput "Cancelled." "Yellow"; return }

    # ── Run resumes ────────────────────────────────────────────────────────
    $results = @()
    foreach ($r in $toResume) {
        Write-Host ""
        Write-ColorOutput "━━━ Resuming: $($r.TableName) ━━━" "Cyan"

        try {
            $result = Export-TableToCSV -ResumeCheckpointPath $r.CheckpointFile
            $results += $result
        }
        catch {
            Write-ColorOutput "  [FAIL] $($r.TableName): $_" "Red"
            $results += [PSCustomObject]@{
                TableName = $r.TableName
                Success   = $false
                Error     = $_.Exception.Message
            }
        }
    }

    # ── Summary ────────────────────────────────────────────────────────────
    Write-Host ""
    $succeeded = ($results | Where-Object { $_.Success }).Count
    $failed    = ($results | Where-Object { -not $_.Success }).Count

    if ($failed -eq 0) {
        Write-ColorOutput "  All $succeeded export(s) completed successfully." "Green"
    } else {
        Write-ColorOutput "  Completed: $succeeded | Failed: $failed" "Yellow"
    }
    Write-Host ""

    return $results
}
