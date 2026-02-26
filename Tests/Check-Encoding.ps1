$bytes = [System.IO.File]::ReadAllBytes('C:\Users\Phillipe\SentinelProjects\SentinelLocalBackup\Helpers\UIHelpers.ps1')
# Check for BOM
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "Encoding: UTF-8 with BOM" -ForegroundColor Green
} else {
    Write-Host "Encoding: NO BOM (UTF-8 or ANSI)" -ForegroundColor Yellow
    Write-Host "First 3 bytes: $($bytes[0]) $($bytes[1]) $($bytes[2])"
}
Write-Host "Default PowerShell encoding: $([System.Text.Encoding]::Default.EncodingName)"
