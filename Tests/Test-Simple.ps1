# Simple test script for core modules
$ErrorActionPreference = "Continue"

Write-Host "`n=== Sentinel Local Backup - Core Tests ===" -ForegroundColor Cyan
Write-Host ""

$ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# Test 1: Files exist
Write-Host "Test 1: File Structure" -ForegroundColor Yellow
$files = @(
    "SentinelLocalBackup.psd1"
    "SentinelLocalBackup.psm1"
    "Core/Authentication.ps1"
    "Core/Configuration.ps1"
    "Helpers/UIHelpers.ps1"
    "Operations/TableDiscovery.ps1"
)

foreach ($file in $files) {
    $path = Join-Path $ModuleRoot $file
    if (Test-Path $path) {
        Write-Host "  [OK] $file" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $file not found" -ForegroundColor Red
    }
}

# Test 2: Load modules
Write-Host "`nTest 2: Loading Modules" -ForegroundColor Yellow

try {
    . "$ModuleRoot/Helpers/UIHelpers.ps1"
    Write-Host "  [OK] UIHelpers.ps1 loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] UIHelpers.ps1: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    . "$ModuleRoot/Core/Configuration.ps1"
    Write-Host "  [OK] Configuration.ps1 loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Configuration.ps1: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    . "$ModuleRoot/Core/Authentication.ps1"
    Write-Host "  [OK] Authentication.ps1 loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Authentication.ps1: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    . "$ModuleRoot/Operations/TableDiscovery.ps1"
    Write-Host "  [OK] TableDiscovery.ps1 loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] TableDiscovery.ps1: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Functions work
Write-Host "`nTest 3: Core Functions" -ForegroundColor Yellow

try {
    $config = Get-SentinelConfig
    if ($config -and $config.ApiVersion) {
        Write-Host "  [OK] Get-SentinelConfig works" -ForegroundColor Green
    }
} catch {
    Write-Host "  [FAIL] Get-SentinelConfig: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $session = Get-SentinelSession
    if ($session) {
        Write-Host "  [OK] Get-SentinelSession works" -ForegroundColor Green
    }
} catch {
    Write-Host "  [FAIL] Get-SentinelSession: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $templates = Get-SchemaTemplates
    if ($templates.ContainsKey("Syslog")) {
        Write-Host "  [OK] Get-SchemaTemplates works ($($templates.Count) templates)" -ForegroundColor Green
    }
} catch {
    Write-Host "  [FAIL] Get-SchemaTemplates: $($_.Exception.Message)" -ForegroundColor Red
}

# Verify TableDiscovery functions exist
try {
    $funcs = @("Get-WorkspaceTables", "Find-Tables", "Select-Tables")
    foreach ($fn in $funcs) {
        if (Get-Command $fn -ErrorAction SilentlyContinue) {
            Write-Host "  [OK] $fn is defined" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $fn not found" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  [FAIL] TableDiscovery functions: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Check dependencies
Write-Host "`nTest 4: Module Dependencies" -ForegroundColor Yellow

$azAccounts = Get-Module -ListAvailable -Name Az.Accounts
if ($azAccounts) {
    Write-Host "  [OK] Az.Accounts installed (v$($azAccounts[0].Version))" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Az.Accounts not installed" -ForegroundColor Yellow
    Write-Host "         Install: Install-Module -Name Az.Accounts" -ForegroundColor Gray
}

$azOI = Get-Module -ListAvailable -Name Az.OperationalInsights
if ($azOI) {
    Write-Host "  [OK] Az.OperationalInsights installed (v$($azOI[0].Version))" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Az.OperationalInsights not installed" -ForegroundColor Yellow
    Write-Host "         Install: Install-Module -Name Az.OperationalInsights" -ForegroundColor Gray
}

Write-Host "`n=== Tests Complete ===" -ForegroundColor Cyan
Write-Host ""
