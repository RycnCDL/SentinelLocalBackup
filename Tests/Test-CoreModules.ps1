<#
.SYNOPSIS
    Test script for core modules validation
.DESCRIPTION
    Validates that Authentication, Configuration, and UIHelpers modules
    load correctly and basic functions work as expected.
.NOTES
    This is a manual test script, not automated Pester tests (those come later)
#>

#Requires -Version 5.1

$ErrorActionPreference = "Continue"

# Get script directory
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleRoot = Split-Path -Parent $TestRoot

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Sentinel Local Backup - Core Tests   " -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$testsPassed = 0
$testsFailed = 0

function Test-Section {
    param([string]$Name)
    Write-Host "`n--- $Name ---" -ForegroundColor Yellow
}

function Test-Assert {
    param(
        [string]$Description,
        [bool]$Condition,
        [string]$FailureMessage = ""
    )

    if ($Condition) {
        Write-Host "  ✓ $Description" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "  ✗ $Description" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "    Error: $FailureMessage" -ForegroundColor Red
        }
        $script:testsFailed++
    }
}

# Test 1: Module files exist
Test-Section "File Structure"

Test-Assert "Module manifest exists" `
    (Test-Path "$ModuleRoot/SentinelLocalBackup.psd1")

Test-Assert "Module loader exists" `
    (Test-Path "$ModuleRoot/SentinelLocalBackup.psm1")

Test-Assert "Authentication.ps1 exists" `
    (Test-Path "$ModuleRoot/Core/Authentication.ps1")

Test-Assert "Configuration.ps1 exists" `
    (Test-Path "$ModuleRoot/Core/Configuration.ps1")

Test-Assert "UIHelpers.ps1 exists" `
    (Test-Path "$ModuleRoot/Helpers/UIHelpers.ps1")

# Test 2: Module manifest is valid
Test-Section "Module Manifest Validation"

try {
    $manifest = Test-ModuleManifest -Path "$ModuleRoot/SentinelLocalBackup.psd1" -ErrorAction Stop
    Test-Assert "Module manifest is valid" $true
    Test-Assert "Module version is 1.0.0" ($manifest.Version -eq "1.0.0")
    Test-Assert "Module GUID is set" ($null -ne $manifest.Guid)
    Test-Assert "Module has description" ($manifest.Description.Length -gt 0)
} catch {
    Test-Assert "Module manifest is valid" $false $_.Exception.Message
}

# Test 3: Load individual module files (without Import-Module)
Test-Section "Direct Module Loading (Dot-Sourcing)"

try {
    # Load in correct order (dependencies)
    . "$ModuleRoot/Helpers/UIHelpers.ps1"
    Test-Assert "UIHelpers.ps1 loads without errors" $true
} catch {
    Test-Assert "UIHelpers.ps1 loads without errors" $false $_.Exception.Message
}

try {
    . "$ModuleRoot/Core/Configuration.ps1"
    Test-Assert "Configuration.ps1 loads without errors" $true
} catch {
    Test-Assert "Configuration.ps1 loads without errors" $false $_.Exception.Message
}

try {
    . "$ModuleRoot/Core/Authentication.ps1"
    Test-Assert "Authentication.ps1 loads without errors" $true
} catch {
    Test-Assert "Authentication.ps1 loads without errors" $false $_.Exception.Message
}

# Test 4: Configuration functions
Test-Section "Configuration Functions"

try {
    $config = Get-SentinelConfig
    Test-Assert "Get-SentinelConfig returns hashtable" ($config -is [hashtable])
    Test-Assert "Config has ApiVersion" ($null -ne $config.ApiVersion)
    Test-Assert "Config has ManagementApiUrl" ($null -ne $config.ManagementApiUrl)
    Test-Assert "Config.DebugMode is false by default" ($config.DebugMode -eq $false)

    $session = Get-SentinelSession
    Test-Assert "Get-SentinelSession returns hashtable" ($session -is [hashtable])
    Test-Assert "Session.SubscriptionId is null initially" ($null -eq $session.SubscriptionId)

    Set-DebugMode $true
    $config = Get-SentinelConfig
    Test-Assert "Set-DebugMode enables debug" ($config.DebugMode -eq $true)

    Set-DebugMode $false  # Reset
} catch {
    Test-Assert "Configuration functions work" $false $_.Exception.Message
}

# Test 5: UIHelpers functions
Test-Section "UIHelpers Functions"

try {
    # These functions should not throw errors
    Write-ColorOutput "Test message" "Green"
    Test-Assert "Write-ColorOutput executes" $true

    Write-Header "Test Header"
    Test-Assert "Write-Header executes" $true

    # Note: Get-YesNoChoice requires user input, skip interactive test
    Test-Assert "Get-YesNoChoice function exists" `
        ($null -ne (Get-Command Get-YesNoChoice -ErrorAction SilentlyContinue))

} catch {
    Test-Assert "UIHelpers functions work" $false $_.Exception.Message
}

# Test 6: Authentication detection (non-interactive)
Test-Section "Authentication Detection"

try {
    # Check if Az CLI is available
    $azCliAvailable = $null -ne (Get-Command az -ErrorAction SilentlyContinue)
    Test-Assert "Az CLI detection works" $true
    if ($azCliAvailable) {
        Write-Host "    Note: Az CLI found on system" -ForegroundColor Gray
    } else {
        Write-Host "    Note: Az CLI not found on system" -ForegroundColor Gray
    }

    # Check if Az PowerShell module is available
    $azModuleAvailable = $null -ne (Get-Module -ListAvailable -Name Az.Accounts)
    Test-Assert "Az Module detection works" $true
    if ($azModuleAvailable) {
        Write-Host "    Note: Az.Accounts module found" -ForegroundColor Gray
    } else {
        Write-Host "    Note: Az.Accounts module not installed" -ForegroundColor Gray
        Write-Host "    Install with: Install-Module -Name Az.Accounts" -ForegroundColor Yellow
    }

} catch {
    Test-Assert "Authentication detection works" $false $_.Exception.Message
}

# Test 7: Schema templates
Test-Section "Schema Templates"

try {
    $templates = Get-SchemaTemplates
    Test-Assert "Get-SchemaTemplates returns hashtable" ($templates -is [hashtable])
    Test-Assert "Schema templates contain Syslog" ($templates.ContainsKey("Syslog"))
    Test-Assert "Schema templates contain CommonSecurityLog" ($templates.ContainsKey("CommonSecurityLog"))
    Test-Assert "Syslog template has Description" ($null -ne $templates.Syslog.Description)
    Test-Assert "Syslog template has Columns" ($templates.Syslog.Columns.Count -gt 0)

    Write-Host "    Available templates: $($templates.Keys -join ', ')" -ForegroundColor Gray

} catch {
    Test-Assert "Schema templates work" $false $_.Exception.Message
}

# Test 8: Module manifest dependencies
Test-Section "Module Dependencies Check"

$requiredModules = @(
    @{Name='Az.Accounts'; MinVersion='2.12.0'}
    @{Name='Az.OperationalInsights'; MinVersion='3.2.0'}
)

foreach ($module in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $module.Name |
                 Where-Object { $_.Version -ge [version]$module.MinVersion } |
                 Select-Object -First 1

    if ($installed) {
        Test-Assert "$($module.Name) (minimum $($module.MinVersion)) is installed" $true
        Write-Host "    Installed: $($installed.Version)" -ForegroundColor Gray
    } else {
        Test-Assert "$($module.Name) (minimum $($module.MinVersion)) is installed" $false
        Write-Host "    Install: Install-Module -Name $($module.Name) -MinimumVersion $($module.MinVersion)" -ForegroundColor Yellow
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Test Summary                          " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nTests Passed: " -NoNewline
Write-Host $testsPassed -ForegroundColor Green

Write-Host "Tests Failed: " -NoNewline
Write-Host $testsFailed -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })

Write-Host "Total Tests:  " -NoNewline
Write-Host ($testsPassed + $testsFailed)

if ($testsFailed -eq 0) {
    Write-Host "`n✓ All tests passed! Core modules are working correctly." -ForegroundColor Green
} else {
    Write-Host "`n✗ Some tests failed. Review errors above." -ForegroundColor Red
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Install missing Az modules (if any)" -ForegroundColor White
Write-Host "  2. Run: Import-Module ./SentinelLocalBackup.psd1" -ForegroundColor White
Write-Host "  3. Test authentication: Connect-ToAzure" -ForegroundColor White
Write-Host ""

# Return exit code based on results
exit $testsFailed
