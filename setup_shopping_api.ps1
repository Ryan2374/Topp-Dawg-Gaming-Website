# Topp Dawg Gaming local shopping price search, one-time setup.
# Stores the SerpApi key encrypted using this Windows account's DPAPI.
$ErrorActionPreference = 'Stop'
Write-Host ''
Write-Host 'TOPP DAWG GAMING - SHOPPING SEARCH SETUP' -ForegroundColor Cyan
Write-Host ''
Write-Host 'This is a SEARCH-DATA provider key, not a reseller/supplier account.'
Write-Host 'Free SerpApi tier: https://serpapi.com/'
Write-Host 'The key stays encrypted locally for your Windows user and is never sent to the website browser.'
Write-Host ''
try {
    $key = Read-Host 'Paste your SerpApi API key (input hidden)' -AsSecureString
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($key)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if ([string]::IsNullOrWhiteSpace($plain) -or $plain -notmatch '^[A-Za-z0-9_-]{16,128}$') {
            throw 'The key must be 16-128 characters, using letters, numbers, underscore or hyphen.'
        }
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    $dir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ToppDawgGaming'
    [void][IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir 'shopping-api-key.dpapi'
    $protected = ConvertFrom-SecureString -SecureString $key
    [IO.File]::WriteAllText($path,($protected+"`n"),(New-Object Text.UTF8Encoding($false)))
    $key.Dispose()
    Write-Host ''
    Write-Host 'SUCCESS: Your shopping-data key was saved encrypted for this Windows account.' -ForegroundColor Green
    Write-Host 'Close and restart start_local_test.bat, then click Search Shopping Prices Automatically.'
    Write-Host 'Your website remains local. No reseller accounts or Python are required.'
} catch {
    Write-Host ('SETUP FAILED: '+$_.Exception.Message) -ForegroundColor Red
    exit 1
}
