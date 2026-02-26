$files = @(
    'C:\Users\Phillipe\SentinelProjects\SentinelLocalBackup\Core\Authentication.ps1'
    'C:\Users\Phillipe\SentinelProjects\SentinelLocalBackup\Core\Configuration.ps1'
    'C:\Users\Phillipe\SentinelProjects\SentinelLocalBackup\SentinelLocalBackup.psm1'
)

$utf8Bom = New-Object System.Text.UTF8Encoding $true

foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($file, $content, $utf8Bom)
    Write-Host "[OK] Fixed: $([System.IO.Path]::GetFileName($file))" -ForegroundColor Green
}
