@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'SentinelLocalBackup.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # ID used to uniquely identify this module
    GUID = 'a7f3e5c9-2b4d-4a8e-9f6c-1d3e5b7a9c2f'

    # Author of this module
    Author = 'Phillipe (RycnCDL)'

    # Company or vendor of this module
    CompanyName = 'RycnCDL'

    # Copyright statement for this module
    Copyright = '(c) 2026 Phillipe (RycnCDL). All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'PowerShell module for exporting Microsoft Sentinel / Log Analytics tables to local CSV files with resume capability and integrity validation.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName='Az.Accounts'; ModuleVersion='2.12.0'}
        @{ModuleName='Az.OperationalInsights'; ModuleVersion='3.2.0'}
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Start-SentinelBackup'
        'Resume-SentinelBackup'
        'Get-BackupStatus'
        'Test-BackupIntegrity'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Microsoft-Sentinel', 'Log-Analytics', 'Azure', 'Backup', 'Export', 'CSV', 'Compliance')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/RycnCDL/SentinelLocalBackup/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/RycnCDL/SentinelLocalBackup'

            # ReleaseNotes of this module
            ReleaseNotes = @'
## 1.0.0 (2026-02-26)
- Initial release
- Export Log Analytics tables to CSV
- Pagination for large tables
- Resume capability for interrupted exports
- ZIP compression support
- Data integrity validation
- Automated/scheduled execution support
'@
        }
    }
}
