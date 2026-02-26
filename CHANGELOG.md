# Changelog

All notable changes to **Sentinel Local Backup** will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2025-02-26

### Added

#### Core Module
- `SentinelLocalBackup.psd1` — module manifest (PowerShell 5.1+)
- `SentinelLocalBackup.psm1` — module loader with conditional dot-sourcing

#### Authentication (`Core/Authentication.ps1`)
- `Connect-ToAzure` — dual-mode authentication: Azure CLI (`az login`) and Az PowerShell Module (`Connect-AzAccount`)
- Auto-detects existing sessions; prompts only when no active session found
- Device code authentication support for headless environments
- `Select-Subscription` — lists enabled subscriptions, auto-selects when only one found
- `Select-Workspace` — lists Log Analytics workspaces via REST API with Az Module fallback
- `Get-AccessToken` — retrieves management API token from either auth backend; handles `SecureString` conversion for PS 5.1 and 7+

#### Configuration (`Core/Configuration.ps1`)
- `Get-SentinelConfig` — global config hashtable (API version, endpoint URLs, debug mode)
- `Get-SentinelSession` — session state (subscription, workspace, resource group, auth token)
- `Get-SchemaTemplates` — 7 pre-defined KQL schema templates (Syslog, CEF, WindowsEvent, etc.)

#### Table Discovery (`Operations/TableDiscovery.ps1`)
- `Get-WorkspaceTables` — queries workspace tables via REST API with KQL fallback; supports `IncludeCustomOnly` and `TableNameFilter` parameters
- `Find-Tables` — wildcard and regex pattern matching across workspace tables
- `Select-Tables` — interactive numbered selection UI with single / range (`1-5`) / multi (`1,3,7`) / `all` / pattern filter (`f:Security*`) modes

#### Export Engine (`Operations/Export.ps1`)
- `Export-TableToCSV` — paginated time-window export with:
  - Row count estimate before starting
  - Schema discovery via `getschema` KQL
  - UTF-8 BOM CSV output (Excel + German locale compatible)
  - `checkpoint.json` written after every successful batch for resume support
  - `metadata.json` with table name, workspace, time range, row count, file size, encoding, full schema, SHA256 hash, exporter identity
  - `-ResumeCheckpointPath` parameter for appending to interrupted exports
  - `-MaxRows` safety limit (default 500,000)
  - `-SkipConfirm` for scripted/automated use
- `Get-BackupStatus` — pretty-print metadata from any completed export run
- `Test-BackupIntegrity` — SHA256 re-hash and comparison against stored value
- `Save-Checkpoint` — internal helper for writing resume state

#### Wizard (`Public/Start-SentinelBackup.ps1`)
- `Start-SentinelBackup` — 6-step interactive wizard:
  1. Authentication
  2. Subscription selection
  3. Workspace selection
  4. Table discovery and selection
  5. Export configuration (output path, time range preset or custom, batch size)
  6. Confirmation, execution, and per-table result summary
- `-OutputPath` pre-set parameter, `-SkipBanner` for automation

#### Resume (`Public/Resume-SentinelBackup.ps1`)
- `Resume-SentinelBackup` — scans output directory recursively for `checkpoint.json` files; displays incomplete exports with rows written and interruption time; supports single / multi / `all` selection; calls `Export-TableToCSV` in resume mode for each
- `-CheckpointPath` for direct resume without scanning

#### UI Helpers (`Helpers/UIHelpers.ps1`)
- `Write-Banner` — ASCII art banner
- `Write-MenuHeader` — boxed section headers with optional session context
- `Write-ColorOutput` — wrapper for colored console output
- `Write-SystemInfo` — PS version, OS, date display
- `Write-FeatureBox` — loaded module status table
- `Get-YesNoChoice` — `PromptForChoice`-based Yes/No prompt with default

#### Tests (`Tests/Test-Simple.ps1`)
- Validates file structure (9 files)
- Dot-sources all modules in dependency order
- Asserts 14 public functions are defined and callable
- Checks Az module availability (warn-only)

### Technical Notes

- All `.ps1` files saved with **UTF-8 BOM** to ensure correct parsing on Windows systems with non-UTF-8 default locale (e.g. German Windows with Windows-1252 default)
- Box-drawing characters retained in UI strings; emoji replaced with ASCII `[*]` / `[Home]` markers for locale compatibility
- Checkpoint file is deleted on successful completion — its presence always indicates an incomplete run
- `wasResumed` field in `metadata.json` provides audit trail for resumed exports

---

## [Unreleased]

### Planned
- PowerShell Gallery publication (`Publish-Module`)
- ZIP compression option (`Compress-Archive` post-export)
- Service Principal / managed identity authentication path
- Multi-table parallel export (PowerShell 7+ `ForEach-Object -Parallel`)
- HTML summary report per session
- `--WhatIf` dry-run mode (shows row counts without writing files)
- Pester test suite replacing the manual `Test-Simple.ps1`
