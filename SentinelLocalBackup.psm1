<#
.SYNOPSIS
    Sentinel Local Backup Tool - Main Module
.DESCRIPTION
    PowerShell module for exporting Microsoft Sentinel / Log Analytics tables
    to local CSV files with resume capability and integrity validation.
.VERSION
    1.0.0
.AUTHOR
    Phillipe (RycnCDL)
#>

#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.OperationalInsights

$ErrorActionPreference = "Stop"

# Get the module root path
$ModuleRoot = $PSScriptRoot

Write-Verbose "Loading Sentinel Local Backup module from: $ModuleRoot"

# Load helper modules first (no dependencies)
Write-Verbose "  Loading UIHelpers..."
. "$ModuleRoot/Helpers/UIHelpers.ps1"

# Load core modules (depends on UIHelpers)
Write-Verbose "  Loading Configuration..."
. "$ModuleRoot/Core/Configuration.ps1"

Write-Verbose "  Loading Authentication..."
. "$ModuleRoot/Core/Authentication.ps1"

# Load operation modules
Write-Verbose "  Loading TableDiscovery..."
if (Test-Path "$ModuleRoot/Operations/TableDiscovery.ps1") {
    . "$ModuleRoot/Operations/TableDiscovery.ps1"
}

Write-Verbose "  Loading DataExport..."
if (Test-Path "$ModuleRoot/Operations/DataExport.ps1") {
    . "$ModuleRoot/Operations/DataExport.ps1"
}

Write-Verbose "  Loading Compression..."
if (Test-Path "$ModuleRoot/Operations/Compression.ps1") {
    . "$ModuleRoot/Operations/Compression.ps1"
}

Write-Verbose "  Loading Validation..."
if (Test-Path "$ModuleRoot/Operations/Validation.ps1") {
    . "$ModuleRoot/Operations/Validation.ps1"
}

# Load helper modules
Write-Verbose "  Loading Resume..."
if (Test-Path "$ModuleRoot/Helpers/Resume.ps1") {
    . "$ModuleRoot/Helpers/Resume.ps1"
}

Write-Verbose "  Loading FileSystem..."
if (Test-Path "$ModuleRoot/Helpers/FileSystem.ps1") {
    . "$ModuleRoot/Helpers/FileSystem.ps1"
}

Write-Verbose "  Loading Metadata..."
if (Test-Path "$ModuleRoot/Helpers/Metadata.ps1") {
    . "$ModuleRoot/Helpers/Metadata.ps1"
}

Write-Verbose "  Loading Progress..."
if (Test-Path "$ModuleRoot/Helpers/Progress.ps1") {
    . "$ModuleRoot/Helpers/Progress.ps1"
}

# Load public functions
Write-Verbose "  Loading Public functions..."
if (Test-Path "$ModuleRoot/Public") {
    Get-ChildItem "$ModuleRoot/Public/*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Verbose "    Loading $($_.Name)..."
        . $_.FullName
    }
}

Write-Verbose "Sentinel Local Backup module loaded successfully!"

# Export public functions (will be defined in Public/*.ps1 files)
Export-ModuleMember -Function @(
    'Start-SentinelBackup'
    'Resume-SentinelBackup'
    'Get-BackupStatus'
    'Test-BackupIntegrity'
    'Connect-ToAzure'  # Export for testing/manual use
    'Get-WorkspaceTables'  # Export for advanced users
)
