# Topp Dawg Gaming - structured shopping-price provider, Windows PowerShell 5.1.
# This script overrides Invoke-ShoppingBrowser from shopping_browser.ps1.
# SerpApi is NOT a supplier; its Google Shopping results are UNVERIFIED price
# observations. No checkout total or inventory availability is asserted.
$script:TDGShoppingCache = @{}
function Get-TDGShoppingKeyPath {
    return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ToppDawgGaming\shopping-api-key.dpapi')
}
function Get-TDGShoppingKey {
    $path = Get-TDGShoppingKeyPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $saved = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8).Trim()
    if ([string]::IsNullOrWhiteSpace($saved)) { return '' }
    $secure = ConvertTo-SecureString -String $saved -ErrorAction Stop
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($null -ne $secure) { $secure.Dispose() }
    }
}
function TDG-VendorFromSource([string]$source) {
    $s = $source.ToLowerInvariant() -replace '[^a-z0-9]',''
    if ($s -match 'newegg') { return 'Newegg' }
    if ($s -match '^bh$|bhphotovideo|bandhphoto|bhphoto|bhvideo') { return 'B&H Photo' }
    if ($s -match 'microcenter') { return 'Micro Center' }
    if ($s -match 'bestbuy') { return 'Best Buy' }
    return ''
}
function TDG-ShoppingPrice($item) {
    $value = $item.extracted_price
    if ($null -ne $value -and [string]$value -match '^\d+(?:\.\d+)?$') {
        $number = [decimal]$value
        if ($number -ge 10 -and $number -le 15000) { return $number }
    }
    $price = [string]$item.price
    $match = [regex]::Match($price,'^\s*\$\s*([\d,]+(?:\.\d{1,2})?)\s*$')
    if ($match.Success) {
        $number = [decimal]::Parse(($match.Groups[1].Value -replace ',',''),[Globalization.CultureInfo]::InvariantCulture)
        if ($number -ge 10 -and $number -le 15000) { return $number }
    }
    return $null
}
function Invoke-ShoppingBrowser([string]$query) {
    $diagnostics = New-Object 'System.Collections.Generic.List[string]'
    $offers = New-Object 'System.Collections.Generic.List[object]'
    $key = ''
    try { $key = Get-TDGShoppingKey }
    catch {
        $diagnostics.Add('Stored shopping API key could not be decrypted by this Windows account. Run SETUP_SHOPPING_API.bat again.')
        return @{ offers=@();diagnostics=@($diagnostics.ToArray());browser='SerpApi';mode='structured_api' }
    }
    if ([string]::IsNullOrWhiteSpace($key)) {
        $diagnostics.Add('SETUP REQUIRED: Run SETUP_SHOPPING_API.bat and enter your free SerpApi key. No reseller account needed. Shopping search did not run.')
        return @{ offers=@();diagnostics=@($diagnostics.ToArray());browser='SerpApi';mode='structured_api' }
    }
    $query = ([string]$query).Trim()
    if ($query.Length -lt 3 -or $query.Length -gt 220) { throw 'Product query must be 3-220 characters.' }
    $cacheId = $query.ToLowerInvariant()
    if ($script:TDGShoppingCache.ContainsKey($cacheId)) {
        $previous = $script:TDGShoppingCache[$cacheId]
        if (([DateTimeOffset]::UtcNow - $previous.at).TotalMinutes -lt 10) {
            return @{offers=$previous.offers;diagnostics=@('SerpApi: using shopping prices cached less than 10 minutes ago');browser='SerpApi';mode='structured_api'}
        }
    }
    try {
        # API credentials remain in this PowerShell process; never send them to
        # the browser, store them in public website files, or echo URLs to logs.
        $endpoint = 'https://serpapi.com/search.json?engine=google_shopping&hl=en&gl=us&q=' +
            [Uri]::EscapeDataString($query) + '&api_key=' + [Uri]::EscapeDataString($key)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $req = [Net.HttpWebRequest][Net.WebRequest]::Create($endpoint)
        $req.Method = 'GET'
        $req.Timeout = 25000
        $req.ReadWriteTimeout = 25000
        $req.Accept = 'application/json'
        $req.UserAgent = 'ToppDawgGaming-LocalPriceTester/1.0'
        $req.AllowAutoRedirect = $false
        $response = $null
        try {
            $response = [Net.HttpWebResponse]$req.GetResponse()
            if ([int]$response.StatusCode -ne 200) { throw ('Provider returned HTTP ' + [int]$response.StatusCode) }
            $reader = [IO.StreamReader]::new($response.GetResponseStream(),[Text.Encoding]::UTF8)
            try {
                $jsonString = $reader.ReadToEnd()
                if ($jsonString.Length -gt 3000000) { throw 'Provider response exceeded 3 MB.' }
            } finally { $reader.Dispose() }
        } finally { if ($null -ne $response) { $response.Close() } }
        $payload = ConvertFrom-Json -InputObject $jsonString -ErrorAction Stop
        if ($payload.error) {
            # Provider errors can include sensitive fields; do not log raw payload.
            throw 'The shopping-data provider rejected the request. Check the API key, quota and account status.'
        }
        $sourceUrl = 'https://www.google.com/search?tbm=shop&hl=en&gl=us&q=' + [Uri]::EscapeDataString($query)
        $seen = @{}
        foreach ($item in @($payload.shopping_results)) {
            if ($null -eq $item) { continue }
            $vendor = TDG-VendorFromSource ([string]$item.source)
            if ([string]::IsNullOrWhiteSpace($vendor)) { continue }
            $price = TDG-ShoppingPrice $item
            if ($null -eq $price) { continue }
            $title = ([string]$item.title).Trim()
            if ($title.Length -lt 5) { continue }
            if ($title.Length -gt 200) { $title = $title.Substring(0,200) }
            $notes = ([string]$item.snippet + ' ' + [string]$item.delivery)
            if ($title -match '(?i)out of stock|sold out' -or $notes -match '(?i)out of stock|sold out') { continue }
            $identity = $vendor + '|' + $title.ToLowerInvariant() + '|' + [string]$price
            if ($seen.ContainsKey($identity)) { continue }
            $seen[$identity] = $true
            # Google shopping links are not direct retailer links. The server
            # only accepts a productUrl when it is genuinely on a store domain.
            $offers.Add(@{ vendor=$vendor;title=$title;price=$price;
                availability='unknown';productUrl=$null;searchUrl=$sourceUrl;
                engine='Google Shopping via SerpApi';evidence='shopping_search_unverified' })
            if ($offers.Count -ge 80) { break }
        }
        $diagnostics.Add(('SerpApi Google Shopping: {0} price listing(s) from the selected retailers' -f $offers.Count))
        $diagnostics.Add('All prices are search-result estimates. Stock, seller, exact variant, delivery and final checkout cost are NOT confirmed.')
        $result = @($offers.ToArray())
        $script:TDGShoppingCache[$cacheId] = @{at=[DateTimeOffset]::UtcNow;offers=$result}
        return @{ offers=$result; diagnostics=@($diagnostics.ToArray());browser='SerpApi';mode='structured_api' }
    } catch [Net.WebException] {
        $code = ''
        if ($null -ne $_.Exception.Response) {
            try { $code = 'HTTP ' + [int]$_.Exception.Response.StatusCode } catch { }
            try { $_.Exception.Response.Close() } catch { }
        }
        if ($code) { $diagnostics.Add('SerpApi request failed: ' + $code + '. Check your key, free quota and network access.') }
        else { $diagnostics.Add('SerpApi request failed: network connection issue. Verify HTTPS to serpapi.com.') }
    } catch {
        $diagnostics.Add('Structured shopping search failed: ' + $_.Exception.GetType().Name + '. Check SETUP_SHOPPING_API.bat and provider quota.')
    }
    return @{offers=@();diagnostics=@($diagnostics.ToArray());browser='SerpApi';mode='structured_api'}
}
