# Topp Dawg Gaming - structured price-search diagnostic.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'shopping_browser.ps1')
Write-Host ''
Write-Host 'TOPP DAWG GAMING - STRUCTURED SHOPPING SEARCH DIAGNOSTIC' -ForegroundColor Cyan
Write-Host 'Search-data method: SerpApi Google Shopping. Chrome scraping is disabled.'
Write-Host 'No supplier or reseller accounts are required.'
try {
    $path=Get-TDGShoppingKeyPath
    if (Test-Path -LiteralPath $path -PathType Leaf) { Write-Host 'Shopping search key: configured (encrypted locally)' -ForegroundColor Green }
    else { Write-Host 'Shopping search key: NOT CONFIGURED. Run SETUP_SHOPPING_API.bat.' -ForegroundColor Yellow; exit 2 }
    try {
        $r=Invoke-WebRequest -Uri 'https://serpapi.com/' -Method Head -UseBasicParsing -TimeoutSec 12
        Write-Host ('SerpApi HTTPS: HTTP '+[int]$r.StatusCode) -ForegroundColor Green
    } catch { Write-Host ('SerpApi HTTPS connectivity: '+$_.Exception.Message) -ForegroundColor Yellow }
    Write-Host 'Searching Google Shopping for AMD Ryzen 5 9600X...' -ForegroundColor Cyan
    $out=Invoke-ShoppingBrowser 'AMD Ryzen 5 9600X'
    foreach ($note in @($out.diagnostics)) { Write-Host ('  '+$note) }
    Write-Host ('Candidate listings from selected retailers: '+@($out.offers).Count)
    Write-Host 'Note: listing prices do not verify in-stock availability.'
} catch { Write-Host ('TEST FAILED: '+$_.Exception.Message) -ForegroundColor Red; exit 1 }
