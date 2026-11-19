# Chrome-only, no-WebSocket diagnostic. Windows PowerShell 5.1.
$ErrorActionPreference='Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'shopping_browser.ps1')
Write-Host ''
Write-Host 'TOPP DAWG GAMING - CHROME SHOPPING DIAGNOSTIC (NO WEBSOCKET)' -ForegroundColor Cyan
try {
    $chrome = Get-ShoppingBrowser
    Write-Host ('Google Chrome: ' + $chrome) -ForegroundColor Green
    foreach ($hostName in @('www.bing.com','www.google.com')) {
        try {
            $r=Invoke-WebRequest -Uri ('https://'+$hostName+'/') -UseBasicParsing -Method Head -TimeoutSec 9
            Write-Host ('HTTPS '+$hostName+': '+[int]$r.StatusCode) -ForegroundColor Green
        } catch { Write-Host ('HTTPS '+$hostName+': '+$_.Exception.Message) -ForegroundColor Yellow }
    }
    Write-Host 'Starting Chrome headless DOM capture (no remote debugging port)...' -ForegroundColor Cyan
    $data=Invoke-ShoppingBrowser 'AMD Ryzen 5 9600X'
    foreach ($msg in @($data.diagnostics)) { Write-Host ('  '+$msg) }
    Write-Host ('Total extracted search listing candidates: '+@($data.offers).Count) -ForegroundColor Green
    Write-Host 'Done. Zero results may mean search access restrictions or changed shopping markup.'
} catch {
    Write-Host ('DIAGNOSTIC FAILED: '+$_.Exception.GetBaseException().Message) -ForegroundColor Red
    exit 1
}
