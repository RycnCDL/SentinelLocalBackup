$bytes = [System.IO.File]::ReadAllBytes('C:\Users\Phillipe\SentinelProjects\SentinelLocalBackup\Helpers\UIHelpers.ps1')
$content = [System.Text.Encoding]::UTF8.GetString($bytes)
$lines = $content -split "`n"
$line = $lines[274]
Write-Host "Line 275 raw: [$line]"
Write-Host "Char codes:"
foreach ($c in [char[]]$line) {
    Write-Host "  U+$("{0:X4}" -f [int]$c) = '$c'"
}
