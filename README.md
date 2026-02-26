# Sentinel Local Backup Tool

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)](https://github.com/RycnCDL/SentinelLocalBackup)

> **PowerShell module for exporting Microsoft Sentinel / Log Analytics tables to local CSV files with resume capability and integrity validation.**

## 🎯 Purpose

Many organizations, especially in Germany, require local log backups for:
- **Compliance**: Data residency and audit requirements
- **Trust**: Local control over sensitive security logs
- **Business Continuity**: Offline access to historical data
- **Cost Optimization**: Long-term archival outside of Azure

This tool addresses these needs by providing reliable, automated export of Log Analytics tables to CSV format.

## ✨ Features

- 📊 **Export all or selected tables** from Log Analytics workspace
- 📄 **CSV format** with UTF-8 BOM encoding (Excel-friendly)
- 🔄 **Pagination** for large tables (handles millions of rows)
- 📦 **ZIP compression** with metadata JSON
- ⏸️ **Resume capability** for interrupted exports
- 🤖 **Automated execution** via scheduled tasks or cron
- ✅ **Data integrity validation** (row counts, checksums)
- 🔐 **Dual authentication** (Interactive or Service Principal)

## 🚀 Quick Start

### Installation

```powershell
# Install from PowerShell Gallery (coming soon)
Install-Module -Name SentinelLocalBackup -Scope CurrentUser

# Or clone from GitHub
git clone https://github.com/RycnCDL/SentinelLocalBackup.git
cd SentinelLocalBackup
Import-Module ./SentinelLocalBackup.psd1
```

### Prerequisites

```powershell
# Required Azure PowerShell modules
Install-Module -Name Az.Accounts -Force
Install-Module -Name Az.OperationalInsights -Force
```

### Basic Usage

```powershell
# Interactive: Export all tables from last 30 days
Connect-AzAccount
Start-SentinelBackup -WorkspaceId "abc-123-def" -AllTables -TimeRange "30d"

# Specific tables only
Start-SentinelBackup -WorkspaceId "abc-123-def" -Tables "SecurityEvent", "Syslog"

# With compression and cleanup
Start-SentinelBackup -WorkspaceId "abc-123-def" -AllTables -Compress -DeleteUncompressed
```

## 📖 Documentation

### Main Commands

| Command | Description |
|---------|-------------|
| `Start-SentinelBackup` | Start a new backup session |
| `Resume-SentinelBackup` | Resume interrupted backup |
| `Get-BackupStatus` | Check backup session status |
| `Test-BackupIntegrity` | Validate exported data |

### Parameters

```powershell
Start-SentinelBackup
    -WorkspaceId <string>              # Required: Log Analytics workspace ID
    [-SubscriptionId <string>]          # Auto-detect if omitted
    [-ResourceGroup <string>]           # Auto-detect if omitted
    [-Tables <string[]>]                # Specific tables or patterns
    [-AllTables]                        # Export all tables
    [-OutputPath <string>]              # Default: C:\SentinelBackups
    [-TimeRange <string>]               # "30d", "7d", "90d"
    [-StartTime <datetime>]             # Explicit start time
    [-EndTime <datetime>]               # Explicit end time
    [-Compress]                         # Create ZIP archives
    [-DeleteUncompressed]               # Clean up CSV after ZIP
    [-BatchSize <int>]                  # Default: 5000 rows
    [-Parallel <int>]                   # Concurrent tables (PS7+)
    [-NoValidation]                     # Skip integrity checks
    [-Force]                            # Overwrite existing backups
    [-Credential <PSCredential>]        # Service Principal auth
    [-WhatIf]                           # Dry-run mode
    [-Verbose]                          # Detailed logging
```

### Output Structure

```
C:\SentinelBackups\
└── 2026-02-26_10-00-00_WorkspaceID\    # Timestamped session
    ├── session.json                     # Resume state
    ├── manifest.json                    # Backup metadata
    ├── SecurityEvent\
    │   ├── SecurityEvent.csv            # Raw data
    │   ├── SecurityEvent.metadata.json  # Schema + checksum
    │   └── SecurityEvent.zip            # Compressed
    ├── Syslog\
    │   ├── Syslog.csv
    │   ├── Syslog.metadata.json
    │   └── Syslog.zip
    └── backup-summary.html              # Human-readable report
```

## 🔧 Advanced Usage

### Automated Backups (Windows)

```powershell
# Create scheduled task for daily backups
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -File C:\Scripts\Run-SentinelBackup.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

Register-ScheduledTask -TaskName "SentinelDailyBackup" `
    -Action $action -Trigger $trigger
```

**Run-SentinelBackup.ps1**:
```powershell
#Requires -Modules SentinelLocalBackup, Az.Accounts

# Service Principal auth
$tenantId = $env:AZURE_TENANT_ID
$appId = $env:AZURE_CLIENT_ID
$secret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object PSCredential($appId, $secret)

Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $tenantId

# Run backup
Start-SentinelBackup `
    -WorkspaceId "abc-123-def" `
    -AllTables `
    -TimeRange "1d" `
    -Compress `
    -OutputPath "D:\Backups\Sentinel" `
    -Verbose
```

### Resume After Interruption

```powershell
# If backup was interrupted, find the session ID
$sessionId = (Get-Content "C:\SentinelBackups\*\session.json" | ConvertFrom-Json).SessionId

# Resume from checkpoint
Resume-SentinelBackup -SessionId $sessionId
```

### Pattern Matching

```powershell
# Export all Security* and *Alert tables
Start-SentinelBackup -WorkspaceId "abc-123" -Tables "Security*", "*Alert"
```

### Parallel Export (PowerShell 7+)

```powershell
# Export 3 tables concurrently
Start-SentinelBackup -WorkspaceId "abc-123" -AllTables -Parallel 3
```

## 🔐 Security

### Authentication Methods

**Interactive (Default)**:
```powershell
Connect-AzAccount
Start-SentinelBackup -WorkspaceId "abc-123" -AllTables
```

**Service Principal (Automated)**:
```powershell
$cred = Get-Credential  # AppId + Secret
Start-SentinelBackup -WorkspaceId "abc-123" -AllTables -Credential $cred -TenantId "tenant-id"
```

### Required Permissions

Minimum RBAC role on Log Analytics workspace:
- **Log Analytics Reader** (recommended)
- Or custom role with: `Microsoft.OperationalInsights/workspaces/query/*/read`

### Data Protection

⚠️ **Important**: Exported CSV files may contain sensitive data (PII, credentials)

Recommendations:
- ✅ Use BitLocker or LUKS for disk encryption
- ✅ Store backups on secure file server
- ✅ Implement file-level encryption (`Protect-CmsMessage`)
- ✅ Apply retention policies (delete after 90/180/365 days)

## 📊 Performance

### Benchmark Estimates

| Table Size | Estimated Time | Network Load |
|------------|----------------|--------------|
| 100k rows | 2-3 minutes | 50 MB |
| 1M rows | 8-12 minutes | 500 MB |
| 10M rows | 80-90 minutes | 5 GB |

*Assumes: 50 MB/s network, 2s API latency per 5000-row batch*

### Optimization Tips

- Use `-Parallel` flag (PowerShell 7+) to export multiple tables concurrently
- Run during off-peak hours to avoid API throttling
- Use `-TimeRange` to export incremental data (e.g., last 24 hours)
- Enable compression (`-Compress`) to save disk space (~90% reduction)

## 🐛 Troubleshooting

### Common Issues

**"InvalidAuthenticationToken" Error**
```powershell
# Solution: Re-authenticate
Connect-AzAccount
```

**"Too Many Requests (429)" Error**
- The tool automatically retries with exponential backoff
- If persistent, reduce `-BatchSize` or `-Parallel` value

**Disk Space Exhausted**
- The tool checks available space before starting
- Use `-Compress -DeleteUncompressed` to save space

**Resume State Corrupted**
- Delete `session.json` and restart backup

### Debug Mode

```powershell
Start-SentinelBackup -WorkspaceId "abc-123" -AllTables -Verbose -Debug
```

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by German compliance requirements for local log storage
- Built on top of Azure PowerShell SDK
- Community feedback from Microsoft Sentinel users

## 📧 Support

- **Issues**: [GitHub Issues](https://github.com/RycnCDL/SentinelLocalBackup/issues)
- **Discussions**: [GitHub Discussions](https://github.com/RycnCDL/SentinelLocalBackup/discussions)
- **Author**: [@RycnCDL](https://github.com/RycnCDL)

---

**⭐ If this tool helps you, please consider starring the repository!**
