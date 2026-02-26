# Re-save UIHelpers.ps1 with UTF-8 BOM so PowerShell reads it correctly
$filePath = 'C:\Users\Phillipe\SentinelProjects\SentinelLocalBackup\Helpers\UIHelpers.ps1'

# Read as UTF-8 (correct)
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

# Write back with UTF-8 BOM
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($filePath, $content, $utf8Bom)

Write-Host "Saved with UTF-8 BOM" -ForegroundColor Green

# Verify BOM
$bytes = [System.IO.File]::ReadAllBytes($filePath)
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "Verified: UTF-8 BOM present (EF BB BF)" -ForegroundColor Green
} else {
    Write-Host "Warning: BOM not found" -ForegroundColor Red
}
