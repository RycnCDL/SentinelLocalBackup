# Exporting Microsoft Sentinel Tables to Local CSV -- A PowerShell Module for Compliance-Driven Environments

*Posted to Microsoft Tech Community -- Security, Compliance and Identity*

---

## The Compliance Conversation

If you work with enterprise security teams in Germany, you have heard some version of this conversation:

> "Microsoft Sentinel is excellent. The detection rules work, the UEBA is mature, the integration with Defender XDR is seamless. But our auditors want a local copy of the logs. Something they can hand to regulators without depending on a cloud portal login. Something that lives on infrastructure we control."

This is not an edge case. Across German mid-size enterprises operating under BSI Grundschutz, KRITIS sector regulations, and the DSGVO (GDPR), the requirement for locally stored, verifiable copies of security telemetry is widespread. Cloud-only retention is still a difficult conversation in many compliance reviews.

For a long time the practical answer was: run a KQL query in the Azure portal, click Export, and save the CSV. This works for a few hundred rows. It falls apart when someone asks for 90 days of SecurityEvent data across a fleet of several thousand endpoints.

So I built a tool to solve this properly.

---

## Introducing SentinelLocalBackup

**SentinelLocalBackup** is an open-source PowerShell module that exports Microsoft Sentinel and Log Analytics workspace tables to local CSV files. It is purpose-built for compliance-driven environments where a local, integrity-verified, human-readable copy of security logs is a hard requirement -- not a nice-to-have.

**GitHub**: [github.com/RycnCDL/SentinelLocalBackup](https://github.com/RycnCDL/SentinelLocalBackup)
**License**: MIT
**Compatibility**: PowerShell 5.1+ (Windows) or PowerShell 7+ (cross-platform)

---

## Key Features

- **Interactive 6-step wizard** -- `Start-SentinelBackup` guides through authentication, subscription selection, workspace selection, table discovery, export configuration, and execution in a single session.
- **Dual authentication** -- works with both Azure CLI (`az login`) and the Az PowerShell Module (`Connect-AzAccount`), including device code login for headless environments. Existing sessions are detected and reused automatically.
- **Time-window pagination** -- large tables are exported in configurable batches (1, 7, 14, or 30 days per API call) to stay within API response limits.
- **Checkpoint and resume** -- a `checkpoint.json` file is written after every successful batch. If the export is interrupted (network drop, token expiry, machine sleep), `Resume-SentinelBackup` picks up from the last completed batch with no duplicate rows and no gaps.
- **SHA256 integrity hashing** -- every completed export produces a `metadata.json` containing a SHA256 hash of the CSV file. `Test-BackupIntegrity` re-computes the hash and compares it against the stored value.
- **UTF-8 BOM encoding** -- the CSV output uses UTF-8 with BOM and includes a `sep=,` hint line, ensuring correct rendering in Excel on German-locale Windows systems without any import wizard steps.
- **Schema discovery** -- each export begins with a `getschema` KQL call to capture column names and types, which are stored in the metadata alongside the data.
- **Full audit trail** -- `metadata.json` records who ran the export, from which machine, against which workspace and subscription, the time range, total rows, file size, and the integrity hash.

---

## Why CSV?

A reasonable question: why not Parquet, direct-to-SQL, or Azure Data Lake Storage?

**Auditors use Excel.** A compliance officer or external auditor conducting a BSI Grundschutz review does not have a Spark cluster. They have Excel. They need to open a file, see rows of structured log data, and verify it corresponds to what the SIEM reported. CSV satisfies this without additional tooling.

**UTF-8 BOM prevents encoding disasters.** On a German-locale Windows system, Excel defaults to Windows-1252 encoding when opening a CSV file. Without the byte order mark, umlauts in usernames, file paths with special characters, and any non-ASCII content renders as garbled text. The BOM tells Excel to interpret the file as UTF-8. The `sep=,` hint line additionally tells Excel to use comma as the delimiter regardless of the locale's list separator (which is a semicolon in German regional settings).

**SHA256 proves immutability.** The hash stored in `metadata.json` provides a cryptographic proof that the CSV has not been altered since export. Combined with the timestamp and exporter identity, this gives auditors a verifiable chain of custody.

---

## Getting Started

### Prerequisites

```powershell
# Install required Azure PowerShell modules
Install-Module -Name Az.Accounts            -MinimumVersion 2.12.0 -Scope CurrentUser -Force
Install-Module -Name Az.OperationalInsights -MinimumVersion 3.2.0  -Scope CurrentUser -Force
```

Your Azure account needs at minimum the **Log Analytics Reader** role on the target workspace.

### Install the Module

```powershell
git clone https://github.com/RycnCDL/SentinelLocalBackup.git
cd SentinelLocalBackup
Import-Module ./SentinelLocalBackup.psd1
```

### Run the Wizard

```powershell
Start-SentinelBackup
```

The wizard walks through six steps:

```
Step 1  [Auth]     Authentication       Detects existing Az CLI / Az Module session, or prompts
Step 2  [Sub]      Subscription         Lists enabled subscriptions, auto-selects if only one
Step 3  [WS]       Workspace            Lists Log Analytics workspaces in the subscription
Step 4  [Tables]   Table selection       Numbered list with flexible selection (see below)
Step 5  [Config]   Export settings       Output path, time range (7/30/90/365/custom), batch size
Step 6  [Run]      Confirm and export    Shows the export plan, runs, displays per-table summary
```

---

## Table Selection UI

In a production Sentinel deployment, a workspace may contain anywhere from 50 to 800+ tables. The selection step displays a numbered, color-coded list and accepts the following input formats:

| Input | Effect |
|-------|--------|
| `3` | Select table number 3 |
| `1-5` | Select tables 1 through 5 (range) |
| `1,3,7` | Select tables 1, 3, and 7 (multiple) |
| `all` | Select all tables |
| `f:Security*` | Filter the list to tables matching the pattern `Security*` |
| `0` or `q` | Go back / cancel |

Tables are color-coded to help with identification:
- **Cyan** -- custom log tables (tables ending in `_CL`)
- **Magenta** -- Auxiliary/DataLake tier tables (these will be skipped during export; see the Auxiliary tables section below)
- **White** -- standard Analytics tier tables

The tool also shows a plan tier breakdown during discovery, for example:

```
Plan 'Analytics': 766 table(s)
Plan 'Auxiliary': 2 table(s)
```

---

## Handling Large Tables

The Log Analytics query API has a response size limit. For high-volume tables like SecurityEvent or AzureActivity, querying 30 or 90 days in a single call will fail or return truncated results.

SentinelLocalBackup addresses this with **time-window pagination**: instead of querying the entire range at once, it divides the time range into batches and queries each one separately, appending results to the CSV file. The batch size is configurable during the wizard or via the `-BatchDays` parameter:

```powershell
# High-volume table: use 1-day batches
Export-TableToCSV `
    -TableName  "SecurityEvent" `
    -OutputPath "D:\ComplianceBackups" `
    -StartTime  (Get-Date).AddDays(-90) `
    -BatchDays  1

# Sparse custom table: use 30-day batches
Export-TableToCSV `
    -TableName  "MyCustomTable_CL" `
    -OutputPath "D:\ComplianceBackups" `
    -BatchDays  30
```

A rough guide for choosing batch sizes:

| Table profile | Recommended BatchDays |
|------|--------|
| Low-volume custom tables, sparse data | 14 -- 30 |
| Standard tables (Syslog, CommonSecurityLog) | 7 |
| High-volume tables (SecurityEvent, AzureActivity) | 1 -- 2 |

---

## Checkpoint and Resume

If you are exporting 90 days of SecurityEvent data at 1-day batches, that is 90 sequential API calls. In a window of 30 to 60 minutes, any number of things can go wrong: authentication tokens expire, VPN connections drop, laptops enter sleep mode, or a transient API error occurs.

After every successful batch, the module writes a `checkpoint.json` file alongside the CSV:

```json
{
  "version":               "1.0",
  "tableName":             "SecurityEvent",
  "runId":                 "20260301_093000",
  "lastCompletedBatchEnd": "2026-02-15T00:00:00Z",
  "totalRowsWritten":      48210,
  "batchDays":             1,
  "savedAt":               "2026-03-01T10:15:33Z",
  "workspaceName":         "contoso-sentinel",
  "subscriptionId":        "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

To resume, re-authenticate and run:

```powershell
Resume-SentinelBackup
```

The module scans the output directory for `checkpoint.json` files, displays which exports are incomplete (with the table name, rows already written, and the time of interruption), and lets you select which to resume. The resumed export appends to the existing CSV starting from exactly where it stopped. The final output is indistinguishable from a clean, uninterrupted run.

When the export completes successfully, the `checkpoint.json` is automatically deleted. Its presence on disk always indicates an incomplete export.

---

## Output Structure

Each export creates a timestamped directory under the table name:

```
C:\SentinelBackups\
  SecurityEvent\
    20260301_093000\
      SecurityEvent_20260301_093000.csv      <-- UTF-8 BOM CSV with sep=, hint
      metadata.json                           <-- Full audit trail + SHA256 hash
```

The `metadata.json` contains everything needed for an audit:

```json
{
  "exportVersion":  "1.0",
  "tableName":      "SecurityEvent",
  "workspaceName":  "contoso-sentinel",
  "workspaceId":    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "exportedAt":     "2026-03-01T09:45:00Z",
  "timeRangeStart": "2026-01-30T00:00:00Z",
  "timeRangeEnd":   "2026-03-01T09:30:00Z",
  "totalRows":      142857,
  "batchDays":      1,
  "wasResumed":     false,
  "csvFile":        "SecurityEvent_20260301_093000.csv",
  "csvSizeMB":      38.4,
  "csvEncoding":    "UTF-8 BOM",
  "csvSHA256":      "A3F1C2D4E5F678901234567890ABCDEF...",
  "schema":         [ { "ColumnName": "TimeGenerated", "DataType": "datetime" }, "..." ],
  "exportedBy":     "phillipe",
  "hostname":       "WORKSTATION01"
}
```

Integrity verification is a one-liner:

```powershell
Test-BackupIntegrity -MetadataPath "C:\SentinelBackups\SecurityEvent\20260301_093000\metadata.json"
# Output: [OK] Integrity verified - SHA256 matches
```

---

## Important: Auxiliary and DataLake Tier Tables

This is a critical point to understand, and one that can cause confusion if overlooked.

**SentinelLocalBackup cannot export tables on the Auxiliary (formerly DataLake) tier.** This is not a bug in the tool -- it is a platform limitation. Auxiliary tier tables use a different storage backend, and standard KQL queries and REST API calls against these tables return zero rows.

### What the tool does

The module **detects** Auxiliary and DataLake tier tables during the discovery step. It labels them in **magenta** in the table selection UI and prints a warning:

```
[WARN] 2 Auxiliary/DataLake table(s) will be SKIPPED during export.
       Auxiliary tables cannot be queried via standard KQL or REST API.
       Use Azure Portal > Log Analytics > Search Jobs to export these manually.
```

If you include Auxiliary tables in your selection, they are automatically filtered out before the export begins. The final summary shows them as skipped with a clear explanation.

### Why this matters now

Azure recently introduced a **table tier switching** feature that allows users to change a table's plan from Analytics to Auxiliary (or vice versa). This is useful for cost optimization, but it has a side effect: tables that were originally on the Analytics tier and have been switched to Auxiliary will also no longer be queryable through standard KQL or the REST API. They behave identically to natively Auxiliary tables. SentinelLocalBackup will detect and skip these switched tables in the same way.

### How to export Auxiliary tables manually

For tables on the Auxiliary tier, use the **Search Jobs** feature in the Azure Portal:

1. Navigate to your Log Analytics workspace in the Azure Portal
2. Go to **Logs**
3. Create a Search Job targeting the Auxiliary table and your desired time range
4. When the job completes, the results are placed into a temporary searchable table
5. Export the results from there, or use SentinelLocalBackup to export the Search Job results table (which is on the Analytics tier)

This is the currently supported path for getting Auxiliary tier data out of Log Analytics.

---

## Automation Example

For daily incremental backups in a non-interactive context, use the export functions directly in a scheduled script:

```powershell
# Run-DailyBackup.ps1 -- Daily Sentinel log backup
#Requires -Modules SentinelLocalBackup

Import-Module SentinelLocalBackup

# Authenticate (uses existing session or prompts)
Connect-ToAzure
Select-Subscription
Select-Workspace

# Define which tables to back up daily
$tables = @("SecurityEvent", "Syslog", "CommonSecurityLog", "SigninLogs")

foreach ($table in $tables) {
    Export-TableToCSV `
        -TableName  $table `
        -OutputPath "D:\ComplianceBackups\Sentinel" `
        -StartTime  (Get-Date).ToUniversalTime().AddDays(-1) `
        -BatchDays  1 `
        -SkipConfirm
}

# Resume any previously interrupted exports
Resume-SentinelBackup -OutputPath "D:\ComplianceBackups\Sentinel"
```

Pair this with a Windows Scheduled Task or an Azure Automation runbook for a fully automated daily backup.

---

## What is Next

This is version 1.0.0. The core export, resume, and integrity features are stable and tested. Planned for future releases:

- **ZIP compression** -- post-export archiving to reduce disk usage (text-based CSV compresses very well)
- **Service principal and managed identity authentication** -- a dedicated authentication path for unattended automation without relying on interactive login
- **Parallel multi-table export** -- leveraging PowerShell 7's `ForEach-Object -Parallel` to export multiple tables concurrently
- **Pester test suite** -- replacing the current manual validation script with automated tests

If any of these are priorities for your environment, open an issue on GitHub or contribute a pull request. Community feedback directly shapes the roadmap.

---

## Conclusion

Microsoft Sentinel is an excellent SIEM platform. Wanting a local copy of your logs is not a lack of trust in the cloud -- it is a compliance requirement, and in many European markets it is simply non-negotiable.

SentinelLocalBackup aims to make that requirement straightforward to meet: one command to launch a guided wizard, reliable pagination for tables of any size, automatic resume for interrupted exports, and cryptographic verification of every output file.

If you run into edge cases with specific table schemas or want to suggest improvements, open an issue on GitHub -- I actively review and respond to every one.

**GitHub**: [github.com/RycnCDL/SentinelLocalBackup](https://github.com/RycnCDL/SentinelLocalBackup)

---

*Phillipe (RycnCDL) -- Microsoft Security community contributor, based in Germany*
*Feedback and contributions welcome*
