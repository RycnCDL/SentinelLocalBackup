# Sentinel Local Backup Tool

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)](https://github.com/RycnCDL/SentinelLocalBackup)

> **PowerShell module for exporting Microsoft Sentinel / Log Analytics tables to local CSV files with resume capability and integrity validation.**

## Purpose

Many organizations — especially in Germany — require local log backups for:

- **Compliance** — Data residency and BSI/DSGVO audit requirements
- **Trust** — Local control over sensitive security logs
- **Business Continuity** — Offline access to historical data
- **Cost Optimization** — Long-term archival outside Azure retention pricing

This module addresses these needs with reliable, paginated export of Log Analytics tables to CSV, with SHA256 integrity hashing and resume support for large datasets.

---

## Features

- **Interactive wizard** (`Start-SentinelBackup`) — guides through auth, workspace, table selection and export config in one session
- **CSV with UTF-8 BOM** — opens correctly in German Excel and all standard tooling
- **Time-window pagination** — handles tables of any size with configurable batch sizes
- **Automatic resume** — `checkpoint.json` written after every batch; interrupted exports pick up exactly where they stopped
- **Integrity validation** — SHA256 hash stored in `metadata.json` and verifiable at any time
- **Dual authentication** — Azure CLI (`az login`) or Az PowerShell Module (`Connect-AzAccount`)
- **Interactive table selection** — numbered list with single / range / multi / pattern / `all` selection
- **Flexible time ranges** — 7 / 30 / 90 / 365 days or custom start/end dates

---

## Requirements

| Requirement | Version |
|-------------|---------|
| PowerShell | 5.1+ (Windows) or 7+ (cross-platform) |
| Az.Accounts | 2.12.0+ |
| Az.OperationalInsights | 3.2.0+ |
| RBAC | Log Analytics Reader (or higher) on the workspace |

---

## Installation

```powershell
# Install Azure module dependencies
Install-Module -Name Az.Accounts            -Scope CurrentUser -Force
Install-Module -Name Az.OperationalInsights -Scope CurrentUser -Force

# Clone the repository
git clone https://github.com/RycnCDL/SentinelLocalBackup.git
cd SentinelLocalBackup

# Import the module
Import-Module ./SentinelLocalBackup.psd1
```

---

## Quick Start

### Option A — Interactive wizard (recommended)

```powershell
Import-Module ./SentinelLocalBackup.psd1

Start-SentinelBackup
```

The wizard walks you through six steps:

```
Step 1  Authentication      Az CLI or Az Module, reuses existing session
Step 2  Subscription        Lists enabled subscriptions, auto-selects if only one
Step 3  Workspace           Lists Log Analytics workspaces via REST API
Step 4  Table selection     Numbered list with single/range/multi/all selection
Step 5  Export settings     Output path, time range, batch size
Step 6  Confirm & run       Shows plan, exports each table, displays summary
```

### Option B — Direct export (scripting / automation)

```powershell
Import-Module ./SentinelLocalBackup.psd1

# Authenticate first
Connect-ToAzure

# Select subscription and workspace (populates session)
Select-Subscription
Select-Workspace

# Export a single table (last 30 days, 7-day batches)
Export-TableToCSV -TableName "SecurityEvent" -OutputPath "D:\Backups"

# Export with a custom time range
Export-TableToCSV `
    -TableName  "Syslog" `
    -OutputPath "D:\Backups" `
    -StartTime  (Get-Date).AddDays(-90) `
    -BatchDays  1          # Use 1-day batches for high-volume tables
```

### Option C — Resume an interrupted export

```powershell
# Scan C:\SentinelBackups for incomplete exports and resume interactively
Resume-SentinelBackup

# Resume from a specific checkpoint
Resume-SentinelBackup -CheckpointPath "C:\SentinelBackups\SecurityEvent\20250226_143000\checkpoint.json"

# Scan a different output directory
Resume-SentinelBackup -OutputPath "D:\Backups"
```

---

## Command Reference

### Start-SentinelBackup

Interactive guided export wizard.

```powershell
Start-SentinelBackup
    [-OutputPath <string>]   # Pre-set output directory (wizard prompts if omitted)
    [-SkipBanner]            # Skip ASCII art (useful in automated contexts)
```

### Resume-SentinelBackup

Find and resume interrupted exports.

```powershell
Resume-SentinelBackup
    [-OutputPath <string>]          # Directory to scan (default: C:\SentinelBackups)
    [-CheckpointPath <string>]      # Path to a specific checkpoint.json
```

### Export-TableToCSV

Export a single table directly (no wizard).

```powershell
Export-TableToCSV
    -TableName <string>                    # Required: table name (e.g. "SecurityEvent")
    [-OutputPath <string>]                 # Default: C:\SentinelBackups
    [-StartTime <datetime>]                # Default: 30 days ago (UTC)
    [-EndTime <datetime>]                  # Default: now (UTC)
    [-BatchDays <int>]                     # Days per API call, default: 7
    [-MaxRows <int>]                       # Row safety limit, default: 500000 (0 = no limit)
    [-SkipConfirm]                         # Skip row-count confirmation prompt
    [-ResumeCheckpointPath <string>]       # Path to checkpoint.json to resume from
```

**Recommended `BatchDays` by table volume:**

| Table | Recommended BatchDays |
|-------|-----------------------|
| Low-volume custom tables | 14–30 |
| Standard tables (Syslog, CommonSecurityLog) | 7 |
| High-volume (SecurityEvent, AzureActivity) | 1–2 |

### Get-BackupStatus

Display metadata from a completed export run.

```powershell
Get-BackupStatus -MetadataPath "C:\SentinelBackups\SecurityEvent\20250226_143000\metadata.json"
```

### Test-BackupIntegrity

Re-hash the CSV and compare to stored SHA256.

```powershell
Test-BackupIntegrity -MetadataPath "C:\SentinelBackups\SecurityEvent\20250226_143000\metadata.json"
```

### Table Discovery

```powershell
# List all tables in the connected workspace
Get-WorkspaceTables

# Custom tables only
Get-WorkspaceTables -IncludeCustomOnly

# Filter by name pattern
Get-WorkspaceTables -TableNameFilter "Security*"

# Wildcard / regex search
Find-Tables "Security*"
Find-Tables "^Security" -UseRegex

# Interactive numbered selection UI
$tables = Select-Tables
$tables = Select-Tables -Tables (Get-WorkspaceTables -TableNameFilter "Security*")
```

---

## Output Structure

Each export run creates a timestamped subdirectory:

```
C:\SentinelBackups\
  SecurityEvent\
    20250226_143000\
      SecurityEvent_20250226_143000.csv   # UTF-8 BOM, all rows
      metadata.json                        # Run metadata + SHA256
      checkpoint.json                      # Present only during active/interrupted runs
```

### metadata.json

```json
{
  "exportVersion":  "1.0",
  "tableName":      "SecurityEvent",
  "workspaceName":  "my-sentinel-workspace",
  "workspaceId":    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "exportedAt":     "2025-02-26T14:30:00Z",
  "timeRangeStart": "2025-01-27T00:00:00Z",
  "timeRangeEnd":   "2025-02-26T14:00:00Z",
  "totalRows":      142857,
  "batchDays":      7,
  "wasResumed":     false,
  "csvFile":        "SecurityEvent_20250226_143000.csv",
  "csvSizeMB":      38.4,
  "csvEncoding":    "UTF-8 BOM",
  "csvSHA256":      "A3F1C2...",
  "schema":         [ ... ],
  "exportedBy":     "jdoe",
  "hostname":       "WORKSTATION01"
}
```

### checkpoint.json (resume state)

Written after every successful batch. Automatically deleted on completion.

```json
{
  "version":               "1.0",
  "tableName":             "SecurityEvent",
  "runId":                 "20250226_143000",
  "csvPath":               "C:\\SentinelBackups\\SecurityEvent\\20250226_143000\\SecurityEvent_20250226_143000.csv",
  "lastCompletedBatchEnd": "2025-02-10T00:00:00Z",
  "totalRowsWritten":      48210,
  "batchDays":             7,
  "savedAt":               "2025-02-26T15:12:33Z"
}
```

---

## Automation (Scheduled Task)

```powershell
# Run-SentinelBackup.ps1 — daily incremental backup via Az CLI
#Requires -Modules SentinelLocalBackup

Import-Module SentinelLocalBackup

# Uses existing az login session (configure az login with a Service Principal beforehand)
Connect-ToAzure
Select-Subscription
Select-Workspace

# Export last 24 hours for key tables
$tables = @("SecurityEvent", "Syslog", "CommonSecurityLog")
foreach ($t in $tables) {
    Export-TableToCSV `
        -TableName  $t `
        -OutputPath "D:\Backups\Sentinel" `
        -StartTime  (Get-Date).ToUniversalTime().AddDays(-1) `
        -BatchDays  1 `
        -SkipConfirm
}
```

**Register as a Windows Scheduled Task:**

```powershell
$action  = New-ScheduledTaskAction -Execute "pwsh.exe" `
               -Argument "-NonInteractive -File C:\Scripts\Run-SentinelBackup.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

Register-ScheduledTask -TaskName "SentinelDailyBackup" `
    -Action $action -Trigger $trigger -RunLevel Highest
```

---

## Required Azure Permissions

Minimum RBAC role on the Log Analytics workspace:

- **Log Analytics Reader** — read-only query access (recommended)

Or a custom role with:
```
Microsoft.OperationalInsights/workspaces/query/*/read
Microsoft.OperationalInsights/workspaces/read
```

---

## Data Protection

Exported CSV files contain the same sensitive data as your Sentinel workspace. Apply appropriate controls:

- Encrypt the backup drive (BitLocker on Windows, LUKS on Linux)
- Store on an access-controlled file server or NAS
- Apply retention and deletion policies (e.g. delete after 365 days)
- Consider field-level masking for PII before sharing externally

---

## Performance Reference

| Rows | Approximate Time | Approximate File Size |
|------|------------------|-----------------------|
| 100k | 1–2 min | 20–50 MB |
| 1M | 10–15 min | 200–500 MB |
| 10M | 90–120 min | 2–5 GB |

*Assumes 7-day batches, ~2s API round-trip latency per batch, typical Log Analytics response size.*

Reduce `BatchDays` for high-velocity tables to stay within the 64 MB API response limit.

---

## Troubleshooting

**Authentication token expired mid-export**
The export will fail on the next batch call. A `checkpoint.json` is already on disk.
Run `Resume-SentinelBackup` after re-authenticating.

**"Too many requests" (HTTP 429)**
Reduce `-BatchDays` to spread requests over more, smaller calls.

**CSV opens with garbled characters in Excel**
Make sure you open the file with `Data > From Text/CSV` and select UTF-8 encoding,
or double-click if your Windows locale is already set to UTF-8.

**No tables returned by Get-WorkspaceTables**
Verify your account has at least Log Analytics Reader on the workspace.
Try the KQL fallback: `search * | summarize count() by Type` in Log Analytics directly.

**Integrity check fails**
The CSV file was modified after export. Do not open CSV files in applications that
auto-save on open (some older Excel versions). Keep originals read-only.

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit with a clear message
4. Open a Pull Request

Issues and feature requests welcome at [GitHub Issues](https://github.com/RycnCDL/SentinelLocalBackup/issues).

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

## Author

[@RycnCDL](https://github.com/RycnCDL) — Microsoft Security community contributor

**If this tool helps your organization, please star the repository!**
