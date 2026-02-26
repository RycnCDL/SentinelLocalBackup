# Exporting Microsoft Sentinel Tables to Local CSV — A PowerShell Module for Compliance-Driven Environments

*Posted to Microsoft Tech Community — Security, Compliance & Identity*

---

## The Conversation I Keep Having

Every few months I sit across from a customer security team and the conversation goes something like this:

> "We love Microsoft Sentinel. The analytics rules are great, the UEBA is impressive... but what happens to our logs when we cancel the subscription? And honestly — can we store a copy locally? Our auditors want something they can hand to regulators without depending on a cloud portal."

In Germany this is not an edge case. It is nearly every mid-size enterprise I work with. The BSI Grundschutz, sector-specific regulations like KRITIS, and the general cultural preference for "we have a copy here, in *our* building" means that cloud-only log retention is still a hard sell for a significant portion of the market.

For a long time my answer was "yes, you can run a KQL query and export to CSV from the portal." Which is technically true and practically useless the moment someone asks to export 90 days of SecurityEvent for 200,000 devices.

So I built something better.

---

## Introducing SentinelLocalBackup

**SentinelLocalBackup** is an open-source PowerShell module that exports Log Analytics / Microsoft Sentinel tables to local CSV files. It is designed for exactly this use case: compliance-driven environments where a local, verifiable, human-readable copy of security logs is a hard requirement.

GitHub: [github.com/RycnCDL/SentinelLocalBackup](https://github.com/RycnCDL/SentinelLocalBackup)

### What it does

- **Exports any Log Analytics table** to CSV, using time-window pagination so it handles tables of any size
- **UTF-8 BOM encoding** so the output opens correctly in German-locale Excel without a single garbled character
- **SHA256 integrity hash** stored in a companion `metadata.json` — every export is verifiable
- **Resume capability** — a `checkpoint.json` is written after every batch, so if the network drops or the token expires at 2 AM, the export picks up exactly where it stopped
- **Interactive wizard** — `Start-SentinelBackup` walks through authentication, subscription, workspace, table selection and time range in a guided UI
- **Dual authentication** — works with both Azure CLI (`az login`) and Az PowerShell Module (`Connect-AzAccount`), reusing existing sessions automatically

---

## Why Local CSV?

Before showing the code I want to briefly justify the format choice, because I know some readers will ask "why not Parquet, or direct SQL, or Azure Data Lake?"

**CSV with UTF-8 BOM is universally readable.** A compliance auditor does not have a Spark cluster. They have Excel. They need to open a file, see rows of log data, and be able to confirm it matches what the SIEM showed. CSV satisfies this requirement without additional tooling.

**UTF-8 BOM specifically** matters in German-language Windows environments. Without the BOM, Excel on a German locale system opens the file with Windows-1252 encoding and every special character — umlauts in usernames, paths with special chars — becomes garbage. One BOM prevents a lot of support calls.

**SHA256 integrity** means you can prove the file has not been modified since export. Store the `metadata.json` alongside the CSV and `Test-BackupIntegrity` re-hashes and compares instantly.

---

## Getting Started in 5 Minutes

### Prerequisites

```powershell
Install-Module -Name Az.Accounts            -Scope CurrentUser -Force
Install-Module -Name Az.OperationalInsights -Scope CurrentUser -Force
```

### Install

```powershell
git clone https://github.com/RycnCDL/SentinelLocalBackup.git
cd SentinelLocalBackup
Import-Module ./SentinelLocalBackup.psd1
```

### Run the wizard

```powershell
Start-SentinelBackup
```

That's it. The wizard handles everything:

```
Step 1  Authentication      Detects existing az/Az session, or prompts for login
Step 2  Subscription        Lists your enabled subscriptions
Step 3  Workspace           Lists Log Analytics workspaces in the subscription
Step 4  Table selection     Browse and select tables with range/pattern support
Step 5  Export settings     Output path, time range (7/30/90/365/custom), batch size
Step 6  Confirm & run       Shows the plan, exports, displays per-table summary
```

---

## The Table Selection UI

One feature I put extra thought into was the table selection step. In a real Sentinel deployment you might have 80–120 tables. Nobody wants to type table names. The selector shows a numbered list and supports:

| Input | Result |
|-------|--------|
| `3` | Select table 3 |
| `1-5` | Select tables 1 through 5 |
| `1,3,7` | Select tables 1, 3 and 7 |
| `all` | Select everything |
| `f:Security*` | Filter list to tables matching `Security*` |
| `0` or `q` | Go back |

For customers who want to export specific categories this is significantly faster than typing 15 table names.

---

## Handling Large Tables: Pagination and Batching

The Log Analytics query API has a response size limit. For high-volume tables like `SecurityEvent` or `AzureActivity`, a 30-day query in one call will fail or return incomplete results.

SentinelLocalBackup uses **time-window pagination**: instead of querying 30 days at once, it queries one batch at a time (default 7 days) and appends results to the CSV. The batch size is configurable:

```powershell
# High-volume table: use 1-day batches to stay within API limits
Export-TableToCSV `
    -TableName  "SecurityEvent" `
    -OutputPath "D:\Backups" `
    -StartTime  (Get-Date).AddDays(-90) `
    -BatchDays  1
```

A rough guide:

| Table type | Recommended BatchDays |
|------------|-----------------------|
| Custom tables, sparse tables | 14–30 |
| Syslog, CommonSecurityLog | 7 |
| SecurityEvent, AzureActivity | 1–2 |

---

## Resume: Because Networks Are Unreliable

If you are exporting 90 days of SecurityEvent data at 1-day batches, that is 90 API calls over perhaps 30–45 minutes. In that window, tokens expire. VPNs drop. Laptops hibernate.

After every successful batch the module writes a `checkpoint.json` next to the CSV:

```json
{
  "tableName":             "SecurityEvent",
  "lastCompletedBatchEnd": "2025-02-10T00:00:00Z",
  "totalRowsWritten":      48210,
  "savedAt":               "2025-02-26T15:12:33Z"
}
```

On the next morning:

```powershell
Resume-SentinelBackup
```

The module scans the output directory, shows you which exports are incomplete, and continues from exactly the last good batch. The final CSV is indistinguishable from a clean run — no duplicate rows, no gaps (within the batch boundaries), one UTF-8 BOM at the top.

The `checkpoint.json` is deleted automatically when the export completes. Its presence always means an incomplete run.

---

## Output Structure

Each export run creates a timestamped directory:

```
C:\SentinelBackups\
  SecurityEvent\
    20250226_143000\
      SecurityEvent_20250226_143000.csv    ← UTF-8 BOM CSV
      metadata.json                         ← SHA256 + schema + run info
```

The `metadata.json` contains everything an auditor needs to understand the provenance of the file:

```json
{
  "tableName":      "SecurityEvent",
  "workspaceName":  "contoso-sentinel",
  "exportedAt":     "2025-02-26T14:30:00Z",
  "timeRangeStart": "2025-01-27T00:00:00Z",
  "timeRangeEnd":   "2025-02-26T14:00:00Z",
  "totalRows":      142857,
  "csvEncoding":    "UTF-8 BOM",
  "csvSHA256":      "A3F1C2D4...",
  "exportedBy":     "jdoe",
  "hostname":       "WORKSTATION01"
}
```

Integrity verification is a one-liner:

```powershell
Test-BackupIntegrity -MetadataPath "C:\SentinelBackups\SecurityEvent\20250226_143000\metadata.json"
```

```
[OK] Integrity verified - SHA256 matches
     Hash: A3F1C2D4E5F67890...
```

---

## Automation Example

For daily incremental backups, the export functions work well in a scheduled script:

```powershell
# Run-DailyBackup.ps1
Import-Module SentinelLocalBackup

Connect-ToAzure
Select-Subscription
Select-Workspace

$tables = @("SecurityEvent", "Syslog", "AzureActivity", "SigninLogs")

foreach ($table in $tables) {
    Export-TableToCSV `
        -TableName  $table `
        -OutputPath "D:\Backups\Sentinel" `
        -StartTime  (Get-Date).ToUniversalTime().AddDays(-1) `
        -BatchDays  1 `
        -SkipConfirm
}
```

Pair this with a Windows Scheduled Task or an Azure Automation runbook (using a managed identity) for a fully automated daily backup.

---

## What's Next

This is v1.0.0. The core export, resume, and integrity features are solid. On my list for the next release:

- **ZIP compression** — post-export archiving to save disk space (90%+ reduction for text logs)
- **Service Principal / Managed Identity** authentication for fully unattended automation
- **Multi-table parallel export** — using PowerShell 7's `ForEach-Object -Parallel` for speed
- **Pester test suite** — replacing the current manual validation script

If any of these are priorities for your use case, open an issue or a PR on GitHub. Community input shapes the roadmap.

---

## Conclusion

Microsoft Sentinel is an excellent SIEM. Local log backup is not a vote of no-confidence in the platform — it is a compliance requirement, and in some markets it is simply non-negotiable.

SentinelLocalBackup tries to make that requirement easy to meet: one command, guided setup, reliable pagination, verifiable output.

If it solves a problem for you, I would appreciate a star on GitHub and any feedback you have on the issues page.

**GitHub**: [github.com/RycnCDL/SentinelLocalBackup](https://github.com/RycnCDL/SentinelLocalBackup)

---

*Phillipe — Microsoft Security community contributor*
*Feedback and contributions welcome*
