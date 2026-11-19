# Topp Dawg Gaming - Chrome-only shopping search capture WITHOUT DevTools.
# Windows PowerShell 5.1, no Python, no Chrome debugger WebSocket, no accounts.
# Capture public shopping search results with Chrome --headless --dump-dom, then
# parse the SAVED DOM inside a separate offline Chrome page. No retailer pages.
# Every price here is an UNVERIFIED search-listing observation, not live stock.
function Get-ShoppingBrowser {
    $override = [Environment]::GetEnvironmentVariable('TDG_CHROME_PATH')
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        $override = $override.Trim().Trim('"')
        if ((Test-Path -LiteralPath $override -PathType Leaf) -and
            [IO.Path]::GetFileName($override).Equals('chrome.exe',[StringComparison]::OrdinalIgnoreCase)) {
            return $override
        }
        throw 'TDG_CHROME_PATH is set but is not a valid chrome.exe. Correct or clear it.'
    }
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($base in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$base)) {
            $paths.Add((Join-Path $base 'Google\Chrome\Application\chrome.exe'))
        }
    }
    foreach ($regPath in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
                           'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe')) {
        try {
            $value = (Get-Item -LiteralPath $regPath -ErrorAction Stop).GetValue('')
            if ($value) { $paths.Add(([string]$value).Trim('"')) }
        } catch { }
    }
    try {
        $cmd = Get-Command 'chrome.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source) { $paths.Add([string]$cmd.Source) }
    } catch { }
    foreach ($path in $paths) {
        if ([IO.Path]::GetFileName($path).Equals('chrome.exe',[StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
    }
    throw 'Google Chrome not found. Install Chrome or set TDG_CHROME_PATH; Edge is not used.'
}
function Invoke-ChromeDomDump([string]$chrome,[string]$target,[string]$work,[string]$label,[int]$waitMs) {
    $profile = Join-Path $work ('profile-' + $label)
    [void][IO.Directory]::CreateDirectory($profile)
    $stdout = Join-Path $work ($label + '-out.html')
    $stderr = Join-Path $work ($label + '-err.txt')
    $chromeArgs = '--headless=new --disable-gpu --no-first-run --no-default-browser-check --disable-extensions ' +
            '--user-data-dir="' + $profile + '" --dump-dom --timeout=' + $waitMs + ' "' + $target + '"'
    $process = $null
    try {
        $process = Start-Process -FilePath $chrome -ArgumentList $chromeArgs -WindowStyle Hidden `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -ErrorAction Stop
        # A hung Google/Bing page must never stall the entire local website forever.
        $grace = [Math]::Max(15000, $waitMs + 10000)
        if (-not $process.WaitForExit($grace)) {
            throw ('Chrome timed out capturing ' + $label + ' (no prices recorded).')
        }
        if (-not (Test-Path -LiteralPath $stdout -PathType Leaf)) {
            throw ('Chrome produced no captured DOM for ' + $label + '.')
        }
        $file = Get-Item -LiteralPath $stdout
        if ($file.Length -lt 80) { throw ('Chrome returned an empty or very small page for ' + $label + '.') }
        if ($file.Length -gt 12000000) { throw ('Chrome returned an excessively large page for ' + $label + '.') }
        return [IO.File]::ReadAllText($stdout,[Text.Encoding]::UTF8)
    } finally {
        if ($null -ne $process) {
            try { if (-not $process.HasExited) { $process.Kill() } } catch { }
            try { $process.Dispose() } catch { }
        }
    }
}
function Invoke-OfflineShoppingParse([string]$chrome,[string]$work,[string]$pageHtml,[string]$searchUrl,[string]$extractor,[string]$label) {
    # Parse saved HTML as inert HTML in an OFFLINE document; no scripts or
    # network from the captured page are executed. The only script is ours.
    $utf8 = [Text.Encoding]::UTF8
    $page64 = [Convert]::ToBase64String($utf8.GetBytes($pageHtml))
    $extract64 = [Convert]::ToBase64String($utf8.GetBytes($extractor))
    $url64 = [Convert]::ToBase64String($utf8.GetBytes($searchUrl))
    $template = @'
<!doctype html><html lang="en"><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'"><title>TDG Offline Shopping Extraction</title>
<body><pre id="tdg-result">NOT_READY</pre><script>
try {
  const decode = b64 => new TextDecoder('utf-8').decode(Uint8Array.from(atob(b64), c => c.charCodeAt(0)));
  const page = new DOMParser().parseFromString(decode('__PAGE__'), 'text/html');
  const searchUrl = new URL(decode('__URL__'));
  // The remote HTML is never written into the live page. Its scripts are inert.
  const run = new Function('document','location', 'return '+decode('__EXTRACT__')+';');
  const data = run(page, searchUrl);
  document.getElementById('tdg-result').textContent = JSON.stringify(data);
} catch(error) {
  document.getElementById('tdg-result').textContent = JSON.stringify({error:String(error)});
}
</script></body></html>
'@
    $html = $template.Replace('__PAGE__',$page64).Replace('__EXTRACT__',$extract64).Replace('__URL__',$url64)
    $file = Join-Path $work ('offline-' + $label + '.html')
    [IO.File]::WriteAllText($file,$html,(New-Object System.Text.UTF8Encoding($false)))
    $uri = ([Uri]$file).AbsoluteUri
    $rendered = Invoke-ChromeDomDump $chrome $uri $work ('extract-' + $label) 1500
    $match = [regex]::Match($rendered,'(?s)<pre\s+id="tdg-result"[^>]*>(.*?)</pre>')
    if (-not $match.Success) { throw 'Chrome offline extraction did not return a result marker.' }
    $value = [Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
    if ($value -eq 'NOT_READY') { throw 'Chrome did not execute the offline extraction script.' }
    $result = ConvertFrom-Json -InputObject $value -ErrorAction Stop
    if ($result.error) { throw ('Offline extraction error: ' + [string]$result.error) }
    return $result
}
function Invoke-ShoppingBrowser([string]$query) {
    $binary = Get-ShoppingBrowser
    $work = Join-Path $env:TEMP ('TDG-Search-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($work)
    $messages = New-Object 'System.Collections.Generic.List[string]'
    $allOffers = New-Object 'System.Collections.Generic.List[object]'
    try {
        $extractor = [IO.File]::ReadAllText((Join-Path $root 'site\assets\shopping-extract.js'),[Text.Encoding]::UTF8)
        $sources = @(
            @{name='Bing Shopping';url=('https://www.bing.com/shop?q='+[Uri]::EscapeDataString($query))},
            @{name='Google Shopping';url=('https://www.google.com/search?tbm=shop&hl=en&gl=us&q='+[Uri]::EscapeDataString($query))}
        )
        $index = 0
        foreach ($src in $sources) {
            $index++
            $label = 's' + $index
            try {
                $page = Invoke-ChromeDomDump $binary ([string]$src.url) $work $label 9000
                # Never pass Chrome error pages or tiny interstitials as product results.
                if ($page -match '(?i)ERR_(CONNECTION|NAME|TUNNEL|PROXY|INTERNET)|This site.can.t be reached') {
                    throw 'Chrome displayed a network error page.'
                }
                $data = Invoke-OfflineShoppingParse $binary $work $page ([string]$src.url) $extractor $label
                if ($data.blocked -or $data.consent) {
                    $messages.Add($src.name + ': verification, consent, or automated-access restriction')
                    continue
                }
                $count = 0
                foreach ($offer in @($data.offers)) {
                    if ($null -eq $offer -or $count -ge 32) { continue }
                    $allOffers.Add($offer)
                    $count++
                }
                $messages.Add($src.name + ': ' + $count + ' readable candidate listing(s)')
            } catch {
                $messages.Add($src.name + ': ' + $_.Exception.GetBaseException().Message)
            }
        }
        return @{offers=@($allOffers.ToArray()); diagnostics=@($messages.ToArray()); browser='chrome.exe / headless DOM capture'; mode='no_websocket'}
    } finally {
        # Only the temporary, isolated capture files are removed.
        try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { }
    }
}
