<#
.SYNOPSIS
    Export Functions for Sentinel Local Backup
.DESCRIPTION
    Exports Log Analytics table data to local CSV files with UTF-8 BOM encoding.
    Supports pagination for large tables, integrity validation, and metadata
    generation for compliance and auditing purposes.
.VERSION
    1.0
#>

#region Private Helpers

function Invoke-LogAnalyticsQuery {
    <#
    .SYNOPSIS
        Executes a KQL query against the Log Analytics workspace
    .PARAMETER Query
        KQL query string
    .PARAMETER Timespan
        ISO 8601 timespan (e.g. P7D for 7 days, P30D for 30 days)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Query,

        [Parameter(Mandatory=$false)]
        [string]$Timespan = "P30D"
    )

    $Session = Get-SentinelSession
    $Config  = Get-SentinelConfig

    $uri = "https://api.loganalytics.io/v1/workspaces/$($Session.WorkspaceId)/query"

    $headers = @{
        "Authorization" = "Bearer $($Session.AuthToken)"
        "Content-Type"  = "application/json"
    }

    $body = @{
        query    = $Query
        timespan = $Timespan
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method POST -Body $body -ErrorAction Stop
    return $response
}

function ConvertTo-FlatRows {
    <#
    .SYNOPSIS
        Converts Log Analytics API response into flat PSCustomObject rows
    #>
    param(
        [Parameter(Mandatory=$true)]
        $ApiResponse
    )

    $table   = $ApiResponse.tables[0]
    $columns = $table.columns
    $rows    = $table.rows

    $result = foreach ($row in $rows) {
        $obj = [ordered]@{}
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $obj[$columns[$i].name] = $row[$i]
        }
        [PSCustomObject]$obj
    }

    return $result
}

function New-OutputDirectory {
    <#
    .SYNOPSIS
        Creates the output directory structure for a backup run
    .PARAMETER BasePath
        Root backup folder
    .PARAMETER TableName
        Table being exported
    .PARAMETER RunId
        Unique run identifier (timestamp-based)
    #>
    param(
        [string]$BasePath,
        [string]$TableName,
        [string]$RunId
    )

    $dir = Join-Path $BasePath "$TableName\$RunId"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

#endregion

#region Public Export Functions

function Export-TableToCSV {
    <#
    .SYNOPSIS
        Exports a single Log Analytics table to a CSV file with UTF-8 BOM
    .DESCRIPTION
        Queries a Log Analytics workspace table and writes the results to a
        CSV file encoded with UTF-8 BOM (required for Excel compatibility and
        German compliance tooling). Large tables are exported in batches using
        time-window pagination.

        A companion metadata.json file is generated alongside every CSV with:
          - Table name, row count, column schema
          - Export timestamp, time range covered
          - SHA256 hash of the CSV for integrity verification

    .PARAMETER TableName
        Name of the Log Analytics table to export (e.g. "SecurityEvent")
    .PARAMETER OutputPath
        Local folder where the CSV will be saved.
        Default: C:\SentinelBackups
    .PARAMETER StartTime
        Start of the time range to export. Default: 30 days ago.
    .PARAMETER EndTime
        End of the time range to export. Default: now (UTC).
    .PARAMETER BatchDays
        Days per batch for paginated export. Default: 7.
        Reduce to 1-2 for high-volume tables (e.g. SecurityEvent).
    .PARAMETER MaxRows
        Safety limit on total rows exported. 0 = no limit. Default: 500000.
    .PARAMETER SkipConfirm
        Skip the row-count confirmation prompt before exporting.
    .EXAMPLE
        Export-TableToCSV -TableName "SecurityEvent" -OutputPath "D:\Backups"
    .EXAMPLE
        Export-TableToCSV -TableName "MyCustomTable_CL" -StartTime (Get-Date).AddDays(-90) -BatchDays 14
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TableName,

        [Parameter(Mandatory=$false)]
        [string]$OutputPath = "C:\SentinelBackups",

        [Parameter(Mandatory=$false)]
        [datetime]$StartTime = (Get-Date).ToUniversalTime().AddDays(-30),

        [Parameter(Mandatory=$false)]
        [datetime]$EndTime = (Get-Date).ToUniversalTime(),

        [Parameter(Mandatory=$false)]
        [int]$BatchDays = 7,

        [Parameter(Mandatory=$false)]
        [int]$MaxRows = 500000,

        [Parameter(Mandatory=$false)]
        [switch]$SkipConfirm
    )

    $Session = Get-SentinelSession
    $runId   = Get-Date -Format "yyyyMMdd_HHmmss"
    $outDir  = New-OutputDirectory -BasePath $OutputPath -TableName $TableName -RunId $runId
    $csvPath = Join-Path $outDir "$TableName`_$runId.csv"
    $metaPath= Join-Path $outDir "metadata.json"

    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  [Export] $TableName" -ForegroundColor White
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-ColorOutput "  Workspace : $($Session.WorkspaceName)" "Gray"
    Write-ColorOutput "  Time range: $($StartTime.ToString('yyyy-MM-dd HH:mm')) UTC -> $($EndTime.ToString('yyyy-MM-dd HH:mm')) UTC" "Gray"
    Write-ColorOutput "  Output    : $csvPath" "Gray"
    Write-Host ""

    # --- Step 1: Row count estimate ---
    Write-ColorOutput "  [1/4] Estimating row count..." "Yellow"

    $isoStart = $StartTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $isoEnd   = $EndTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

    $countKql = "$TableName | where TimeGenerated between (datetime('$isoStart') .. datetime('$isoEnd')) | count"

    try {
        $countResponse = Invoke-LogAnalyticsQuery -Query $countKql -Timespan "P$(([int]($EndTime - $StartTime).TotalDays + 1))D"
        $estimatedRows = [int]($countResponse.tables[0].rows[0][0])
        Write-ColorOutput "  Estimated rows: $($estimatedRows.ToString('N0'))" "Cyan"
    }
    catch {
        Write-ColorOutput "  Could not estimate row count: $_" "Yellow"
        $estimatedRows = -1
    }

    if ($MaxRows -gt 0 -and $estimatedRows -gt $MaxRows) {
        Write-ColorOutput "  WARNING: Table has $($estimatedRows.ToString('N0')) rows, limit is $($MaxRows.ToString('N0'))." "Red"
        Write-ColorOutput "           Use -MaxRows 0 to remove limit or -StartTime to narrow range." "Red"
        Write-Host ""
        if (-not $SkipConfirm) {
            $continue = Get-YesNoChoice "Export first $($MaxRows.ToString('N0')) rows anyway?" "N"
            if (-not $continue) {
                Write-ColorOutput "  Export cancelled." "Yellow"
                return $null
            }
        }
    }
    elseif ($estimatedRows -gt 0 -and -not $SkipConfirm) {
        $proceed = Get-YesNoChoice "Export $($estimatedRows.ToString('N0')) rows from '$TableName'?" "Y"
        if (-not $proceed) {
            Write-ColorOutput "  Export cancelled." "Yellow"
            return $null
        }
    }

    # --- Step 2: Schema discovery ---
    Write-ColorOutput "  [2/4] Discovering schema..." "Yellow"

    $schemaKql = "$TableName | getschema"
    try {
        $schemaResponse = Invoke-LogAnalyticsQuery -Query $schemaKql -Timespan "P1D"
        $schemaRows     = ConvertTo-FlatRows -ApiResponse $schemaResponse
        $columns        = $schemaRows | Select-Object ColumnName, DataType, ColumnType
        Write-ColorOutput "  Columns: $($columns.Count)" "Cyan"
    }
    catch {
        Write-ColorOutput "  Could not retrieve schema, will infer from data." "Yellow"
        $columns = @()
    }

    # --- Step 3: Paginated export ---
    Write-ColorOutput "  [3/4] Exporting data in $BatchDays-day batches..." "Yellow"

    $utf8Bom      = New-Object System.Text.UTF8Encoding $true
    $streamWriter = New-Object System.IO.StreamWriter($csvPath, $false, $utf8Bom)

    $totalRows    = 0
    $batchNum     = 0
    $headerWritten= $false
    $batchStart   = $StartTime

    try {
        while ($batchStart -lt $EndTime) {
            $batchEnd = $batchStart.AddDays($BatchDays)
            if ($batchEnd -gt $EndTime) { $batchEnd = $EndTime }

            $batchNum++
            $bsStr = $batchStart.ToString("yyyy-MM-dd")
            $beStr = $batchEnd.ToString("yyyy-MM-dd")
            Write-ColorOutput "    Batch $($batchNum): $bsStr -> $beStr" "Gray"

            $isoBS = $batchStart.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $isoBE = $batchEnd.ToString("yyyy-MM-ddTHH:mm:ssZ")

            $batchKql = "$TableName | where TimeGenerated between (datetime('$isoBS') .. datetime('$isoBE'))"
            if ($MaxRows -gt 0) {
                $remaining = $MaxRows - $totalRows
                if ($remaining -le 0) { break }
                $batchKql += " | take $remaining"
            }

            try {
                $batchResponse = Invoke-LogAnalyticsQuery -Query $batchKql -Timespan "P$($BatchDays + 1)D"
                $batchRows     = ConvertTo-FlatRows -ApiResponse $batchResponse

                if ($batchRows.Count -eq 0) {
                    $batchStart = $batchEnd
                    continue
                }

                # Write CSV header once
                if (-not $headerWritten) {
                    $header = ($batchRows[0].PSObject.Properties.Name | ForEach-Object {
                        if ($_ -match '[,"\r\n]') { "`"$_`"" } else { $_ }
                    }) -join ","
                    $streamWriter.WriteLine($header)
                    $headerWritten = $true
                }

                # Write data rows
                foreach ($row in $batchRows) {
                    $csvLine = ($row.PSObject.Properties.Value | ForEach-Object {
                        $val = if ($null -eq $_) { "" } else { $_.ToString() }
                        if ($val -match '[,"\r\n]') { "`"$($val -replace '"','""')`"" } else { $val }
                    }) -join ","
                    $streamWriter.WriteLine($csvLine)
                    $totalRows++
                }

                Write-ColorOutput "    -> $($batchRows.Count) rows (total: $($totalRows.ToString('N0')))" "Green"
            }
            catch {
                Write-ColorOutput "    [WARN] Batch $batchNum failed: $_" "Yellow"
                Write-ColorOutput "           Skipping this batch and continuing..." "Gray"
            }

            $batchStart = $batchEnd
        }
    }
    finally {
        $streamWriter.Flush()
        $streamWriter.Close()
        $streamWriter.Dispose()
    }

    Write-ColorOutput "  Total rows exported: $($totalRows.ToString('N0'))" "Cyan"

    # --- Step 4: Metadata + integrity ---
    Write-ColorOutput "  [4/4] Generating metadata and integrity hash..." "Yellow"

    $sha256   = [System.Security.Cryptography.SHA256]::Create()
    $fileBytes= [System.IO.File]::ReadAllBytes($csvPath)
    $hashBytes= $sha256.ComputeHash($fileBytes)
    $sha256.Dispose()
    $csvHash  = [BitConverter]::ToString($hashBytes) -replace "-",""

    $fileSizeMB = [math]::Round((Get-Item $csvPath).Length / 1MB, 3)

    $metadata = [ordered]@{
        exportVersion   = "1.0"
        tableName       = $TableName
        workspaceName   = $Session.WorkspaceName
        workspaceId     = $Session.WorkspaceId
        subscriptionId  = $Session.SubscriptionId
        exportedAt      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        timeRangeStart  = $StartTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        timeRangeEnd    = $EndTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        totalRows       = $totalRows
        batchDays       = $BatchDays
        csvFile         = [System.IO.Path]::GetFileName($csvPath)
        csvSizeMB       = $fileSizeMB
        csvEncoding     = "UTF-8 BOM"
        csvSHA256       = $csvHash
        schema          = $columns
        exportedBy      = $env:USERNAME
        hostname        = $env:COMPUTERNAME
    }

    $metadata | ConvertTo-Json -Depth 5 | Out-File -FilePath $metaPath -Encoding UTF8

    # --- Summary ---
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
    Write-Host "Export Complete" -ForegroundColor Green -NoNewline
    Write-Host "                                               │" -ForegroundColor DarkGray
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

    $lines = @(
        @{ Label = "Table";    Value = $TableName },
        @{ Label = "Rows";     Value = $totalRows.ToString('N0') },
        @{ Label = "Size";     Value = "$fileSizeMB MB" },
        @{ Label = "CSV";      Value = $csvPath },
        @{ Label = "Metadata"; Value = $metaPath },
        @{ Label = "SHA256";   Value = $csvHash.Substring(0,16) + "..." }
    )
    foreach ($line in $lines) {
        $label = $line.Label.PadRight(9)
        $val   = $line.Value
        if ($val.Length -gt 45) { $val = "..." + $val.Substring($val.Length - 42) }
        Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$label" -ForegroundColor Yellow -NoNewline
        Write-Host ": $val" -ForegroundColor White -NoNewline
        $pad = 55 - ($label.Length + $val.Length + 2)
        if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
        Write-Host "│" -ForegroundColor DarkGray
    }

    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    return [PSCustomObject]@{
        TableName  = $TableName
        OutputDir  = $outDir
        CsvPath    = $csvPath
        MetaPath   = $metaPath
        TotalRows  = $totalRows
        SizeMB     = $fileSizeMB
        SHA256     = $csvHash
        Success    = $true
    }
}

function Get-BackupStatus {
    <#
    .SYNOPSIS
        Reads and displays the metadata for a previous backup run
    .PARAMETER MetadataPath
        Path to a metadata.json file from a previous export
    .EXAMPLE
        Get-BackupStatus -MetadataPath "C:\SentinelBackups\SecurityEvent\20250101_120000\metadata.json"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$MetadataPath
    )

    if (-not (Test-Path $MetadataPath)) {
        throw "Metadata file not found: $MetadataPath"
    }

    $meta = Get-Content $MetadataPath -Raw | ConvertFrom-Json

    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │  Backup Status                                              │" -ForegroundColor DarkGray
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray

    $fields = @(
        @{ L = "Table";      V = $meta.tableName },
        @{ L = "Workspace";  V = $meta.workspaceName },
        @{ L = "Exported";   V = $meta.exportedAt },
        @{ L = "Range";      V = "$($meta.timeRangeStart) -> $($meta.timeRangeEnd)" },
        @{ L = "Rows";       V = $meta.totalRows.ToString('N0') },
        @{ L = "Size";       V = "$($meta.csvSizeMB) MB" },
        @{ L = "Encoding";   V = $meta.csvEncoding },
        @{ L = "SHA256";     V = $meta.csvSHA256.Substring(0,16) + "..." },
        @{ L = "By";         V = "$($meta.exportedBy) @ $($meta.hostname)" }
    )

    foreach ($f in $fields) {
        $label = $f.L.PadRight(10)
        $val   = if ($f.V) { $f.V.ToString() } else { "N/A" }
        if ($val.Length -gt 43) { $val = $val.Substring(0, 40) + "..." }
        Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$label" -ForegroundColor Yellow -NoNewline
        Write-Host ": $val" -ForegroundColor White -NoNewline
        $pad = 53 - ($label.Length + $val.Length + 2)
        if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
        Write-Host "│" -ForegroundColor DarkGray
    }

    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""

    return $meta
}

function Test-BackupIntegrity {
    <#
    .SYNOPSIS
        Verifies a backup CSV against its stored SHA256 hash
    .PARAMETER MetadataPath
        Path to the metadata.json file
    .EXAMPLE
        Test-BackupIntegrity -MetadataPath "C:\SentinelBackups\...\metadata.json"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$MetadataPath
    )

    $meta    = Get-Content $MetadataPath -Raw | ConvertFrom-Json
    $csvPath = Join-Path (Split-Path $MetadataPath) $meta.csvFile

    if (-not (Test-Path $csvPath)) {
        Write-ColorOutput "  [FAIL] CSV file not found: $csvPath" "Red"
        return $false
    }

    Write-ColorOutput "  Verifying integrity of '$($meta.csvFile)'..." "Cyan"

    $sha256   = [System.Security.Cryptography.SHA256]::Create()
    $fileBytes= [System.IO.File]::ReadAllBytes($csvPath)
    $hashBytes= $sha256.ComputeHash($fileBytes)
    $sha256.Dispose()
    $actualHash = [BitConverter]::ToString($hashBytes) -replace "-",""

    if ($actualHash -eq $meta.csvSHA256) {
        Write-ColorOutput "  [OK] Integrity verified - SHA256 matches" "Green"
        Write-ColorOutput "       Hash: $($actualHash.Substring(0,32))..." "Gray"
        return $true
    }
    else {
        Write-ColorOutput "  [FAIL] Integrity check FAILED - file may be corrupted or tampered" "Red"
        Write-ColorOutput "       Expected: $($meta.csvSHA256.Substring(0,32))..." "Gray"
        Write-ColorOutput "       Actual  : $($actualHash.Substring(0,32))..." "Gray"
        return $false
    }
}

#endregion
