# Topp Dawg Gaming - local retail price checking server.
# Windows PowerShell 5.1, built-in .NET only. No Python, Node, or admin required.
# Local only: listens on 127.0.0.1:8765, never on a public interface.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$site = Join-Path $root 'site'
$offerFile = Join-Path $root 'retail-lab-offers.json'
$shoppingFile = Join-Path $root 'shopping-price-observations.json'
$catalogFile = Join-Path $root 'parts-catalog.json'
$port = 8765
$baseUrl = "http://127.0.0.1:$port"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$catalog = Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json
$parts = @{}
foreach ($mode in @('desktop','laptop')) {
    foreach ($group in $catalog.$mode.PSObject.Properties) {
        foreach ($item in $group.Value) {
            $key = "$mode.$($group.Name).$($item.id)"
            $parts[$key] = @{ name=$item.name; mode=$mode; category=$group.Name }
        }
    }
}
foreach ($item in $catalog.os) {
    $parts["os.$($item.id)"] = @{ name=$item.name; mode='both'; category='os' }
}
. (Join-Path $root 'shopping_browser.ps1')
function Now-ISO { return [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
function Read-Offers {
    if (-not (Test-Path -LiteralPath $offerFile)) { return }
    try {
        $data = Get-Content -LiteralPath $offerFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $data) { return }
        foreach ($entry in @($data)) { Write-Output $entry }
    } catch { return }
}
function Write-Offers($rows) {
    $data = ConvertTo-Json -InputObject @($rows) -Depth 20
    $temporary = "$offerFile.tmp"
    [IO.File]::WriteAllText($temporary, ($data + "`n"), $utf8)
    Move-Item -LiteralPath $temporary -Destination $offerFile -Force
}
function Test-RetailURL([string]$url) {
    $uri = $null
    if (-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri)) { throw 'Enter a normal HTTPS product page URL.' }
    if ($uri.Scheme -ne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo) { throw 'Retailer URL must use HTTPS without credentials or nonstandard ports.' }
    $hostName = $uri.DnsSafeHost.ToLowerInvariant().TrimEnd('.')
    $vendors = @{'newegg.com'='Newegg';'bhphotovideo.com'='B&H Photo';'microcenter.com'='Micro Center';'bestbuy.com'='Best Buy'}
    foreach ($domain in $vendors.Keys) {
        if ($hostName -eq $domain -or $hostName.EndsWith('.' + $domain)) { return $vendors[$domain] }
    }
    throw 'Allowed retailer domains: Newegg, B&H, Micro Center, Best Buy.'
}
function Amount($inputValue) {
    if ($null -eq $inputValue -or $inputValue -is [bool]) { return $null }
    $text = ([string]$inputValue).Trim() -replace '[$,\s]',''
    if ($text -notmatch '^\d{1,6}(\.\d{1,2})?$') { return $null }
    $cost = [decimal]::Parse($text,[Globalization.CultureInfo]::InvariantCulture)
    if ($cost -le 0 -or $cost -gt 100000) { return $null }
    return $cost
}
function Markup([decimal]$cost) {
    if ($cost -le 50) { return [decimal]0.20 }
    if ($cost -ge 1000) { return [decimal]0.05 }
    return [decimal]0.20 - (($cost - 50) * [decimal]0.15 / 950)
}
function Sell([decimal]$cost) {
    return [math]::Round(($cost * (1 + (Markup $cost))),2,[MidpointRounding]::AwayFromZero)
}
function Stock($value) {
    $s = ([string]$value).ToLowerInvariant()
    if ($s -match 'outofstock|soldout|discontinued|instoreonly') { return 'out_of_stock' }
    if ($s -match 'instock|limitedavailability') { return 'in_stock' }
    return 'unknown'
}
function AgeSeconds($timestamp) {
    try { return [Math]::Max(0,([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$timestamp)).TotalSeconds) }
    catch { return [double]::PositiveInfinity }
}
function Save-Offer([string]$key,$record) {
    if (-not $parts.ContainsKey($key)) { throw 'Choose a valid component.' }
    $url = [string]$record.url
    $vendor = Test-RetailURL $url
    $cost = Amount $record.price
    if ($null -eq $cost) { throw 'Price must be a valid positive USD amount.' }
    $stock = [string]$record.availability
    if (@('in_stock','out_of_stock','unknown') -notcontains $stock) { $stock = 'unknown' }
    $title = [string]$record.title
    if ($title.Length -gt 220) { $title = $title.Substring(0,220) }
    $extraction = [string]$record.extraction
    if ($extraction.Length -gt 90) { $extraction = $extraction.Substring(0,90) }
    $entry = @{ key=$key;vendor=$vendor;url=$url;price=[decimal]$cost;availability=$stock;title=$title;extraction=$extraction;checked_at=(Now-ISO) }
    $rows = @(Read-Offers | Where-Object { -not ($_.key -eq $key -and $_.vendor -eq $vendor -and $_.url -eq $url) })
    Write-Offers (@($rows) + @($entry))
    return $entry
}
function Product-Offer($node,[string]$defaultTitle) {
    if ($null -eq $node) { return $null }
    if ($node -is [array]) {
        foreach ($child in $node) { $found = Product-Offer $child $defaultTitle; if ($null -ne $found) { return $found } }
        return $null
    }
    if ($node -isnot [pscustomobject]) { return $null }
    $types = @($node.'@type')
    $isProduct = $false
    foreach ($t in $types) { if ([string]$t -match '(?i)(product|productgroup)$') { $isProduct = $true } }
    if ($isProduct) {
        $offers = @($node.offers)
        foreach ($offer in $offers) {
            if ($null -eq $offer -or $offer -isnot [pscustomobject]) { continue }
            $currency = [string]$offer.priceCurrency
            if ($currency -and $currency.ToUpperInvariant() -ne 'USD') { continue }
            $cost = Amount $offer.price
            if ($null -eq $cost -and $offer.priceSpecification) { $cost = Amount $offer.priceSpecification.price }
            if ($null -ne $cost) {
                $title = if ($node.name) { [string]$node.name } else { $defaultTitle }
                return @{price=$cost;availability=(Stock $offer.availability);title=$title;extraction='Product JSON-LD offer'}
            }
        }
    }
    foreach ($property in $node.PSObject.Properties) {
        if ($property.Value -is [pscustomobject] -or $property.Value -is [array]) {
            $found = Product-Offer $property.Value $defaultTitle
            if ($null -ne $found) { return $found }
        }
    }
    return $null
}
function Extract-Product([string]$html) {
    $title = ''
    $tm = [regex]::Match($html,'(?is)<title\b[^>]*>(.*?)</title>')
    if ($tm.Success) { $title = [Net.WebUtility]::HtmlDecode(($tm.Groups[1].Value -replace '<[^>]+>','')).Trim() }
    if ($title.Length -gt 220) { $title = $title.Substring(0,220) }
    $metadata = @{}
    foreach ($tag in [regex]::Matches($html,'(?is)<meta\b[^>]*>')) {
        $keyMatch = [regex]::Match($tag.Value,'(?i)\b(?:property|name|itemprop)\s*=\s*["'']([^"'']+)["'']')
        $valueMatch = [regex]::Match($tag.Value,'(?i)\bcontent\s*=\s*["'']([^"'']+)["'']')
        if ($keyMatch.Success -and $valueMatch.Success) {
            $k = $keyMatch.Groups[1].Value.Trim().ToLowerInvariant()
            if (-not $metadata.ContainsKey($k)) { $metadata[$k] = [Net.WebUtility]::HtmlDecode($valueMatch.Groups[1].Value.Trim()) }
        }
    }
    foreach ($block in [regex]::Matches($html,'(?is)<script\b[^>]*\btype\s*=\s*["'']application/ld\+json["''][^>]*>(.*?)</script>')) {
        try {
            $data = $block.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
            $found = Product-Offer $data $title
            if ($null -ne $found) { return $found }
        } catch { }
    }
    foreach ($field in @('product:price:amount','og:price:amount','price','price:amount','product:price')) {
        if ($metadata.ContainsKey($field)) {
            $currency = if ($metadata.ContainsKey('product:price:currency')) { $metadata['product:price:currency'] } else { 'USD' }
            if ($currency.ToUpperInvariant() -ne 'USD') { continue }
            $cost = Amount $metadata[$field]
            if ($null -ne $cost) {
                if ($metadata.ContainsKey('og:title')) { $title = [string]$metadata['og:title'] }
                $stock = if ($metadata.ContainsKey('availability')) { $metadata['availability'] } else { '' }
                return @{price=$cost;availability=(Stock $stock);title=$title;extraction="HTML metadata ($field)"}
            }
        }
    }
    return $null
}
function Fetch-Offer([string]$url) {
    $vendor = Test-RetailURL $url
    $nextUrl = $url
    for ($n=0;$n -lt 5;$n++) {
        [void](Test-RetailURL $nextUrl)
        $request = [Net.HttpWebRequest][Net.WebRequest]::Create($nextUrl)
        $request.Method = 'GET'
        $request.Timeout = 15000
        $request.ReadWriteTimeout = 15000
        $request.AllowAutoRedirect = $false
        $request.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/123.0.0.0 Safari/537.36'
        $request.Accept = 'text/html,application/xhtml+xml'
        $request.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
        try { $response = [Net.HttpWebResponse]$request.GetResponse() }
        catch [Net.WebException] {
            $http = $_.Exception.Response
            if ($null -ne $http) {
                $code = [int]$http.StatusCode
                $http.Close()
                if (@(403,429,503) -contains $code) { throw "HTTP $code`: retailer blocked or limited the automatic lookup. Try the browser capture method." }
                throw "Retailer returned HTTP $code."
            }
            throw "Retailer request failed: $($_.Exception.Message)"
        }
        try {
            $code = [int]$response.StatusCode
            if (@(301,302,303,307,308) -contains $code) {
                $location = $response.Headers['Location']
                if (-not $location) { throw 'Redirect missing location.' }
                $nextUrl = ([Uri]::new([Uri]$nextUrl,[string]$location)).AbsoluteUri
                [void](Test-RetailURL $nextUrl)
                continue
            }
            if ($code -ne 200) { throw "Retailer returned HTTP $code." }
            if ($response.ContentType -and $response.ContentType -notmatch '(?i)html') { throw 'Retailer did not return an HTML product page.' }
            $source = $response.GetResponseStream()
            $memory = New-Object IO.MemoryStream
            $buffer = New-Object byte[] 16384
            while (($count = $source.Read($buffer,0,$buffer.Length)) -gt 0) {
                if ($memory.Length + $count -gt 7000000) { throw 'Retailer page exceeds the maximum permitted size.' }
                $memory.Write($buffer,0,$count)
            }
            $html = [Text.Encoding]::UTF8.GetString($memory.ToArray())
            $record = Extract-Product $html
            if ($null -eq $record) { throw 'No trustworthy product price found in public structured data; no price assumed.' }
            $record['url'] = $url
            $record['vendor'] = $vendor
            return $record
        } finally { $response.Close() }
    }
    throw 'Too many retailer redirects.'
}
function Lab-Data {
    $rows = @(Read-Offers)
    $enriched = @()
    foreach ($offer in $rows) {
        $cost = [decimal]$offer.price
        $enriched += @{ key=$offer.key;vendor=$offer.vendor;url=$offer.url;price=$cost;availability=$offer.availability;title=$offer.title;extraction=$offer.extraction;checked_at=$offer.checked_at;markupPercent=([math]::Round((Markup $cost)*100,3));sellingPrice=(Sell $cost);stale=((AgeSeconds $offer.checked_at) -gt 7200);partName=$(if ($parts.ContainsKey([string]$offer.key)) {$parts[[string]$offer.key].name} else {'Unknown'}) }
    }
    foreach ($item in @(Read-ShoppingObservations)) {
        if (-not $parts.ContainsKey([string]$item.key)) { continue }
        $cost = Amount $item.price
        if ($null -eq $cost) { continue }
        $enriched += @{key=$item.key;vendor=$item.vendor;url=$item.searchUrl;price=$cost;availability='unknown';title=$item.title;
          extraction='Shopping search listing - UNVERIFIED';checked_at=$item.checked_at;
          markupPercent=([math]::Round((Markup $cost)*100,3));sellingPrice=(Sell $cost);
          stale=((AgeSeconds $item.checked_at) -gt 7200);partName=$parts[[string]$item.key].name;kind='shopping'}
    }
    return @{ parts=$parts;offers=$enriched;asOf=(Now-ISO);localTest=$true }
}
function Prices-Data([string]$mode) {
    $rows = @(Read-Offers)
    $prices = @()
    foreach ($key in ($parts.Keys | Sort-Object)) {
        $part = $parts[$key]
        if ($part.mode -ne $mode -and $part.mode -ne 'both') { continue }
        if ($key -eq 'os.none') {
            $prices += @{key=$key;retailPrice=0;availability='in_stock';source='local_fixed_price'}
            continue
        }
        $eligible = @($rows | Where-Object { $_.key -eq $key -and $_.availability -ne 'out_of_stock' -and (AgeSeconds $_.checked_at) -le 7200 })
        $preferred = @($eligible | Where-Object { $_.availability -eq 'in_stock' })
        if ($preferred.Count -gt 0) { $eligible = $preferred }
        $winner = $eligible | Sort-Object -Property { [decimal]$_.price } | Select-Object -First 1
        if ($null -eq $winner) {
            $searchPrice = @(Read-ShoppingObservations | Where-Object { $_.key -eq $key -and (AgeSeconds $_.checked_at) -le 7200 -and (Amount $_.price) -ne $null } | Sort-Object -Property { [decimal]$_.price } | Select-Object -First 1)
            if ($searchPrice.Count -gt 0) {
                $observed = $searchPrice[0]
                $prices += @{key=$key;retailPrice=(Sell ([decimal]$observed.price));availability='unverified';source='shopping_search_estimate';vendor=$observed.vendor;checkedAt=$observed.checked_at}
            } else {
                $prices += @{key=$key;retailPrice=$null;availability='unverified';source='not_checked';vendor=$null;checkedAt=$null}
            }
        } else {
            $prices += @{key=$key;retailPrice=(Sell ([decimal]$winner.price));availability=$winner.availability;source='live_page_observation';vendor=$winner.vendor;checkedAt=$winner.checked_at}
        }
    }
    return @{mode=$mode;prices=$prices;status='local_test';checkedAt=(Now-ISO)}
}
# Automatic retail discovery: searches public retailer listings using a no-key
# Bing RSS index; falls back to the retailer's own public search HTML where possible.
# No CAPTCHA solving, account use, rotating proxy or fabricated prices.
$searchVendors = @{
  'Newegg' = @{domain='newegg.com';query='https://www.newegg.com/p/pl?d='}
  'B&H Photo' = @{domain='bhphotovideo.com';query='https://www.bhphotovideo.com/c/search?q='}
  'Micro Center' = @{domain='microcenter.com';query='https://www.microcenter.com/search/search_results.aspx?Ntt='}
  'Best Buy' = @{domain='bestbuy.com';query='https://www.bestbuy.com/site/searchpage.jsp?st='}
}
function Product-Query([string]$key) {
    $p = $parts[$key]
    if ($null -eq $p) { throw 'Unknown catalog part.' }
    $name = [string]$p.name
    # The existing catalog includes conceptual names and generic specifications.
    # Query them, but don't claim an exact MPN or finalized laptop platform.
    $name = $name -replace '(?i)\s*\((?:example|subject to model|Intel|AM5)\)', ''
    $name = $name -replace '(?i)\s+concept\s*$', ''
    $name = $name -replace '(?i)\s*\(GPU up to [^)]+\)', ''
    if ($key.StartsWith('desktop.gpu.')) { return ('graphics card ' + $name) }
    if ($key.StartsWith('desktop.ram.')) { return ('desktop RAM ' + $name) }
    if ($key.StartsWith('laptop.platform.')) { return ('gaming laptop ' + $name) }
    if ($key.StartsWith('laptop.ram.')) { return ('laptop SO-DIMM ' + $name) }
    if ($key.StartsWith('desktop.case.')) { return ('ATX PC case ' + $name) }
    if ($key.StartsWith('desktop.cooler.')) { return ('CPU ' + $name) }
    return $name
}
function Model-Matches([string]$key,[string]$title) {
    if ([string]::IsNullOrWhiteSpace($title)) { return $false }
    $t = $title.ToLowerInvariant()
    # Search results are not guaranteed to describe a single purchasable component.
    # Reject common multi-item offers and non-new items before matching a model.
    # Do not globally reject the word 'kit': a RAM kit can be a valid single SKU.
    if ($t -match '(?i)\b(bundle|combo|package deal|prebuilt|refurbished|renewed|used|open[ -]?box)\b') { return $false }
    if ($key.StartsWith('desktop.cpu.')) {
        # A CPU search must not accept a CPU + motherboard / other-PC-parts kit.
        if ($t -match '(?i)\b(motherboard|mainboard|mobo|memory kit|graphics card|ram|ssd|gaming desktop|desktop computer|complete system|build kit)\b') { return $false }
        if ($t -match '(?i)\b(b650|b850|b860|x670|x870|z790|z890|a620)\b') { return $false }
        if ($t -match '(?i)\s+[&+]\s+') { return $false }
        if ($t -match '(?i)\bkit\b') { return $false }
    }
    # Hard filters for model family, not exact manufacturer's part number.
    if ($key -match '^desktop\.cpu\.r5$') { return ($t -match '\bryzen\s*5\s*9600x\b') }
    if ($key -match '^desktop\.cpu\.r7$') { return ($t -match '\bryzen\s*7\s*9700x\b') }
    if ($key -match '^desktop\.cpu\.i5$') { return ($t -match '\b(?:core\s*)?ultra\s*5\s*245k\b') }
    if ($key -match '^desktop\.cpu\.i7$') { return ($t -match '\b(?:core\s*)?ultra\s*7\s*265k\b') }
    if ($key -match '^desktop\.gpu\.5060$') { return ($t -match '\brtx\s*5060\b' -and $t -notmatch '\brtx\s*5060\s*ti\b') }
    if ($key -match '^desktop\.gpu\.5070$') { return ($t -match '\brtx\s*5070\b' -and $t -notmatch '\brtx\s*5070\s*ti\b') }
    if ($key -match '^desktop\.gpu\.5080$') { return ($t -match '\brtx\s*5080\b') }
    if ($key -match '^desktop\.gpu\.9070xt$') { return ($t -match '\brx\s*9070\s*xt\b') }
    if ($key -match '^desktop\.motherboard\.(b650|x870|b860|z890)$') {
        $chipset = $Matches[1]; return ($t -match ('\b' + $chipset + '\b') -and $t -match 'wi.?fi|wireless')
    }
    if ($key -match '^(desktop|laptop)\.ssd\.(1|2|4)$') {
        $size=$Matches[2];return ($t -match ('\b'+$size+'\s*tb\b') -and $t -match 'nvme|m\.2')
    }
    if ($key -match '^(desktop|laptop)\.ram\.(16|32|64)$') {
        $size=$Matches[2];return ($t -match ('\b'+$size+'\s*gb\b') -and ($key.StartsWith('laptop.') -or $t -match 'ddr5'))
    }
    if ($key -match '^desktop\.psu\.(650|750|850|1000)$') {
        $w=$Matches[1]; return ($t -match ('\b'+$w+'\s*w\b') -and $t -match 'gold')
    }
    if ($key -eq 'os.none') { return $false }
    if ($key -eq 'os.win11') { return ($t -match 'windows\s*11\s*home' -and $t -match 'license|retail|oem') }
    if ($key.StartsWith('laptop.platform.')) { return $false } # Concept, not purchasable exact system
    if ($key.StartsWith('desktop.case.') -or $key.StartsWith('desktop.cooler.')) { return $false } # No MPN to verify dimensions
    return $false
}
function Product-Link([string]$vendor,[string]$url) {
    try { if ((Test-RetailURL $url) -ne $vendor) { return $false } } catch { return $false }
    $uri=[Uri]$url
    $path=$uri.AbsolutePath.ToLowerInvariant()
    switch ($vendor) {
      'Newegg' { return ($path -match '/p/(?!pl)(?:[a-z0-9-]+)' -or $path -match '\.html$') }
      'B&H Photo' { return ($path -match '/c/product/\d+' -or $path -match '/c/product/[^/]+') }
      'Micro Center' { return ($path -match '/product/\d+') }
      'Best Buy' { return ($path -match '/site/.+/(?:\d+\.p|\d+)$') }
    }
    return $false
}
function Search-Text([string]$url) {
    # URLs for discovery are created by this server. Redirects must remain at Bing
    # or an explicitly approved retail site; blocks become reported failures.
    $next=$url
    for ($i=0;$i -lt 4;$i++) {
        $uri=[Uri]$next
        if ($uri.Scheme -ne 'https' -or $uri.Port -ne 443) { throw 'Search redirected outside HTTPS.' }
        $hostName=$uri.DnsSafeHost.ToLowerInvariant()
        $isBing = ($hostName -eq 'bing.com' -or $hostName.EndsWith('.bing.com'))
        if (-not $isBing) { [void](Test-RetailURL $next) }
        $req=[Net.HttpWebRequest][Net.WebRequest]::Create($next)
        $req.Method='GET';$req.Timeout=8500;$req.ReadWriteTimeout=8500
        $req.AllowAutoRedirect=$false
        $req.UserAgent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0 Safari/537.36'
        $req.Accept='application/rss+xml,text/html,application/xml,application/xhtml+xml'
        $req.AutomaticDecompression=[Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
        try { $resp=[Net.HttpWebResponse]$req.GetResponse() }
        catch [Net.WebException] {
            if ($null -ne $_.Exception.Response) { $code=[int]$_.Exception.Response.StatusCode;$_.Exception.Response.Close();throw "Search HTTP $code" }
            throw ('Search connection error: '+$_.Exception.Message)
        }
        try {
            $code=[int]$resp.StatusCode
            if (@(301,302,303,307,308) -contains $code) {
                $location=$resp.Headers['Location'];if (-not $location) { throw 'Search redirect without destination.' }
                $next=([Uri]::new([Uri]$next,[string]$location)).AbsoluteUri
                continue
            }
            if ($code -ne 200) { throw "Search HTTP $code" }
            $reader=[IO.StreamReader]::new($resp.GetResponseStream(),[Text.Encoding]::UTF8)
            $buffer=New-Object char[] 8192
            $sb=New-Object Text.StringBuilder
            while (($count=$reader.Read($buffer,0,$buffer.Length)) -gt 0) {
                if (($sb.Length+$count) -gt 2500000) { throw 'Search page too large.' }
                [void]$sb.Append($buffer,0,$count)
            }
            return $sb.ToString()
        } finally { $resp.Close() }
    }
    throw 'Too many search redirects.'
}
function Find-CandidateLinks([string]$vendor,[string]$query) {
    $links=New-Object 'System.Collections.Generic.List[string]'
    $diagnostics=New-Object 'System.Collections.Generic.List[string]'
    $domain=[string]$searchVendors[$vendor].domain
    # Bing index, not a paid API. Results may be unavailable from some PCs or IPs.
    try {
        $searchUrl='https://www.bing.com/search?format=rss&mkt=en-US&q='+[Uri]::EscapeDataString('site:'+$domain+' '+$query)
        $xmlText=Search-Text $searchUrl
        [xml]$feed=$xmlText
        foreach ($item in @($feed.rss.channel.item)) {
            $link=([string]$item.link).Trim()
            if ((Product-Link $vendor $link) -and -not $links.Contains($link)) { $links.Add($link) }
        }
        $diagnostics.Add('Bing indexed results: '+$links.Count)
    } catch { $diagnostics.Add('Indexed search: '+$_.Exception.Message) }
    # Storefront search is tried only if the index returned no product links.
    if ($links.Count -eq 0) {
        try {
            $searchUrl=[string]$searchVendors[$vendor].query+[Uri]::EscapeDataString($query)
            $html=Search-Text $searchUrl
            $base=[Uri]$searchUrl
            foreach ($match in [regex]::Matches($html,'(?is)\bhref\s*=\s*["'']([^"'']{1,800})["'']')) {
                $href=[Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
                try {
                    $resolved=([Uri]::new($base,$href)).AbsoluteUri
                    if ((Product-Link $vendor $resolved) -and -not $links.Contains($resolved)) { $links.Add($resolved) }
                } catch {}
                if ($links.Count -ge 12) { break }
            }
            $diagnostics.Add('Retailer search links: '+$links.Count)
        } catch { $diagnostics.Add('Store search: '+$_.Exception.Message) }
    }
    return @{ links=@($links.ToArray()); diagnostics=@($diagnostics.ToArray()) }
}
function Search-OneStore([string]$key,[string]$vendor) {
    if (-not $parts.ContainsKey($key)) { throw 'Unknown catalog part.' }
    if (-not $searchVendors.ContainsKey($vendor)) { throw 'Unsupported retailer.' }
    $query=Product-Query $key
    if ($key.StartsWith('laptop.platform.') -or $key.StartsWith('desktop.case.') -or $key.StartsWith('desktop.cooler.')) {
        return @{vendor=$vendor;status='needs_model';query=$query;checked=0;message='This catalog entry describes a component type, not an exact model with verifiable specifications. Add a real brand/model before automatic pricing.'}
    }
    if ($key -eq 'os.none') { return @{vendor=$vendor;status='not_applicable';query=$query;checked=0;message='No operating system selected; cost is $0.'} }
    $discover=Find-CandidateLinks $vendor $query
    $offersFound=New-Object 'System.Collections.Generic.List[object]'
    $checked=0
    $errors=New-Object 'System.Collections.Generic.List[string]'
    foreach ($link in $discover.links) {
        if ($checked -ge 2) { break }
        $checked++
        try {
            $record=Fetch-Offer $link
            if (-not (Model-Matches $key ([string]$record.title))) { continue }
            $record['extraction']='Auto search / '+[string]$record.extraction
            $entry=Save-Offer $key $record
            $offersFound.Add($entry)
        } catch { $errors.Add($_.Exception.Message) }
    }
    if ($offersFound.Count -gt 0) {
        $sorted=@($offersFound | Sort-Object -Property { if ($_.availability -eq 'in_stock') {0} else {1} }, { [decimal]$_.price })
        $winner=$sorted[0];$sell=Sell ([decimal]$winner.price)
        $stockText=if ($winner.availability -eq 'in_stock') {'in-stock claim'} else {'stock unconfirmed'}
        return @{vendor=$vendor;status='priced';query=$query;checked=$checked;count=$offersFound.Count;
          offer=$winner;sellingPrice=$sell;markupPercent=([math]::Round((Markup ([decimal]$winner.price))*100,3));
          message="Observed $($offersFound.Count) matching priced product(s); $stockText. Exact manufacturer variant and delivery still require checking."}
    }
    $details=(@($discover.diagnostics)+@($errors | Select-Object -First 2)) -join '; '
    $status=if ($details -match 'HTTP (403|429|503)') {'blocked'} elseif ($discover.links.Count -eq 0) {'no_links'} else {'no_price'}
    return @{vendor=$vendor;status=$status;query=$query;checked=$checked;count=0;message=('No matching product price was captured. '+$details).Trim()}
}

# Shopping-search observations are stored separately from product-page checks;
# search snippets cannot verify a retailer's current inventory or final checkout price.
function Read-ShoppingObservations {
    if (-not (Test-Path -LiteralPath $shoppingFile -PathType Leaf)) { return }
    try {
        $rows = Get-Content -LiteralPath $shoppingFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($item in @($rows)) {
            if ($null -eq $item) { continue }
            $itemKey = [string]$item.key
            # Revalidate previously saved search observations as matching rules
            # improve. Never serve a saved CPU+motherboard bundle as a CPU price.
            if (-not $parts.ContainsKey($itemKey)) { continue }
            if (-not (Model-Matches $itemKey ([string]$item.title))) { continue }
            Write-Output $item
        }
    } catch { return }
}
function Write-ShoppingObservations($rows) {
    $json = ConvertTo-Json -InputObject @($rows) -Depth 10
    $tmp = "$shoppingFile.tmp"
    [IO.File]::WriteAllText($tmp,($json+"`n"),$utf8)
    Move-Item -LiteralPath $tmp -Destination $shoppingFile -Force
}
function Search-Shopping([string]$key) {
    if (-not $parts.ContainsKey($key)) { throw 'Unknown component.' }
    $query = Product-Query $key
    if ($key -eq 'os.none') { return @{status='not_applicable';query=$query;results=@();message='No operating system to price.';diagnostics=@()} }
    if ($key.StartsWith('laptop.platform.') -or $key.StartsWith('desktop.case.') -or $key.StartsWith('desktop.cooler.')) {
        return @{status='needs_model';query=$query;results=@();message='This catalog option is a general concept, not a particular purchasable model. Select an exact brand/model before pricing it.';diagnostics=@()}
    }
    $browserResult = Invoke-ShoppingBrowser $query
    $choices = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($candidate in @($browserResult.offers)) {
        if ($null -eq $candidate) { continue }
        $vendor=[string]$candidate.vendor
        if (@('Newegg','B&H Photo','Micro Center','Best Buy') -notcontains $vendor) { continue }
        $title=([string]$candidate.title).Trim()
        if ($title.Length -gt 200) { $title=$title.Substring(0,200) }
        if (-not (Model-Matches $key $title)) { continue }
        if ([string]$candidate.availability -eq 'out_of_stock') { continue }
        $cost = Amount $candidate.price
        if ($null -eq $cost) { continue }
        # Search sources must be the actual Google or Bing shopping page.
        $sourceUrl = [string]$candidate.searchUrl
        $sourceUri=$null
        if (-not [Uri]::TryCreate($sourceUrl,[UriKind]::Absolute,[ref]$sourceUri)) { continue }
        if ($sourceUri.Scheme -ne 'https' -or $sourceUri.Port -ne 443) { continue }
        $hostName = $sourceUri.DnsSafeHost.ToLowerInvariant()
        if ($hostName -notin @('www.bing.com','bing.com','www.google.com','google.com')) { continue }
        $productUrl=$null
        if ($candidate.productUrl) {
            try { if ((Test-RetailURL ([string]$candidate.productUrl)) -eq $vendor) { $productUrl=[string]$candidate.productUrl } } catch {}
        }
        $unique=($vendor+'|'+$title.ToLowerInvariant()+'|'+[string]$cost)
        if ($seen.ContainsKey($unique)) { continue }
        $seen[$unique]=$true
        $choices.Add(@{key=$key;vendor=$vendor;title=$title;price=[decimal]$cost;availability='unknown';
           checked_at=(Now-ISO);searchUrl=$sourceUrl;productUrl=$productUrl;engine=[string]$candidate.engine;
           classification='search_listing_unverified'})
    }
    $selected=New-Object 'System.Collections.Generic.List[object]'
    foreach ($vendor in @('Newegg','B&H Photo','Micro Center','Best Buy')) {
        $matches=@($choices | Where-Object { $_.vendor -eq $vendor } | Sort-Object -Property { [decimal]$_.price } | Select-Object -First 4)
        foreach ($entry in $matches) { $selected.Add($entry) }
    }
    if ($selected.Count -gt 0) {
        $old = @(Read-ShoppingObservations | Where-Object { $_.key -ne $key })
        Write-ShoppingObservations (@($old) + @($selected.ToArray()))
    }
    $output=New-Object 'System.Collections.Generic.List[object]'
    foreach ($vendor in @('Newegg','B&H Photo','Micro Center','Best Buy')) {
        $found=@($selected | Where-Object { $_.vendor -eq $vendor } | Sort-Object -Property { [decimal]$_.price })
        if ($found.Count -eq 0) {
            $output.Add(@{vendor=$vendor;status='not_found';message='No eligible standalone model-matching listing returned. Price and stock unknown.'})
        } else {
            $winner=$found[0];$cost=[decimal]$winner.price
            $output.Add(@{vendor=$vendor;status='estimate';count=$found.Count;offer=$winner;
                markupPercent=([math]::Round((Markup $cost)*100,3));sellingPrice=(Sell $cost);
                message='Shopping search result only. Stock, exact variant, shipping and checkout price are NOT confirmed.'})
        }
    }
    return @{status=$(if ($selected.Count -gt 0) {'estimates'} else {'no_results'});query=$query;results=@($output.ToArray());
        diagnostics=@($browserResult.diagnostics);browser=$browserResult.browser;checkedAt=(Now-ISO);
        message=$(if ($selected.Count -gt 0) {'Search-result prices are estimates, not confirmed retail offers.'} else {'Neither shopping search exposed usable matching prices; no prices were fabricated.'})}
}

function Api-Request([string]$method,[string]$path,[string]$query,$data) {
    if ($method -eq 'GET') {
        if ($path -eq '/api/lab') { return (Lab-Data) }
        if ($path -eq '/api/prices') {
            $mode = if ($query -match '(?:^|&)mode=laptop(?:&|$)') { 'laptop' } else { 'desktop' }
            return (Prices-Data $mode)
        }
        throw 'Unknown API route.'
    }
    if ($null -eq $data) { throw 'Invalid JSON request.' }
    if ($path -eq '/api/shopping') { return (Search-Shopping ([string]$data.key)) }
    if ($path -eq '/api/search') {
        return (Search-OneStore ([string]$data.key) ([string]$data.vendor))
    }
    if ($path -eq '/api/fetch') {
        $offer = Fetch-Offer ([string]$data.url)
        $entry = Save-Offer ([string]$data.key) $offer
        return @{ok=$true;offer=$entry;markupPercent=([math]::Round((Markup ([decimal]$entry.price))*100,3));sellingPrice=(Sell ([decimal]$entry.price))}
    }
    if ($path -eq '/api/capture') {
        $record = @{url=[string]$data.url;price=$data.price;title=[string]$data.title;availability=[string]$data.availability;extraction='Browser-observed page data'}
        $entry = Save-Offer ([string]$data.key) $record
        return @{ok=$true;offer=$entry;markupPercent=([math]::Round((Markup ([decimal]$entry.price))*100,3));sellingPrice=(Sell ([decimal]$entry.price))}
    }
    if ($path -eq '/api/delete') {
        if ([string]$data.kind -eq 'shopping') {
            $rows=@(Read-ShoppingObservations)
            $remaining=@($rows | Where-Object { -not ($_.key -eq [string]$data.key -and $_.searchUrl -eq [string]$data.url -and $_.vendor -eq [string]$data.vendor -and $_.title -eq [string]$data.title -and [decimal]$_.price -eq [decimal]$data.price) })
            Write-ShoppingObservations $remaining
            return @{ok=$true;removed=($rows.Count-$remaining.Count)}
        }
        $old = @(Read-Offers)
        $new = @($old | Where-Object { -not ($_.key -eq [string]$data.key -and $_.url -eq [string]$data.url) })
        Write-Offers $new
        return @{ok=$true;removed=($old.Count-$new.Count)}
    }
    if ($path -eq '/api/refresh') {
        $old = @(Read-Offers | Select-Object -First 50)
        $results = @()
        foreach ($item in $old) {
            try {
                $fresh = Fetch-Offer ([string]$item.url)
                [void](Save-Offer ([string]$item.key) $fresh)
                $results += @{vendor=$item.vendor;key=$item.key;ok=$true}
            } catch {
                $results += @{vendor=$item.vendor;key=$item.key;ok=$false;error=[string]$_.Exception.Message}
            }
        }
        return @{ok=$true;refreshed=@($results | Where-Object {$_.ok}).Count;results=$results}
    }
    throw 'Unknown API route.'
}
function Send-HTTP($stream,[int]$code,[string]$type,[byte[]]$data,[bool]$redirect=$false) {
    $reason = switch ($code) {200 {'OK'} 302 {'Found'} 400 {'Bad Request'} 403 {'Forbidden'} 404 {'Not Found'} 413 {'Payload Too Large'} 502 {'Bad Gateway'} default {'Error'}}
    $extra = if ($redirect) { "Location: /lab.html`r`n" } else { '' }
    $header = "HTTP/1.1 $code $reason`r`nContent-Type: $type`r`nContent-Length: $($data.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n${extra}`r`n"
    $bytes = [Text.Encoding]::ASCII.GetBytes($header)
    $stream.Write($bytes,0,$bytes.Length)
    if ($data.Length -gt 0) { $stream.Write($data,0,$data.Length) }
    $stream.Flush()
}
function Json-HTTP($stream,[int]$code,$data) {
    $json = ConvertTo-Json -InputObject $data -Depth 25 -Compress
    $bytes = $utf8.GetBytes($json)
    Send-HTTP $stream $code 'application/json; charset=utf-8' $bytes
}
function Serve-Client($client) {
    $stream = $client.GetStream()
    $client.ReceiveTimeout = 20000
    $client.SendTimeout = 20000
    $request = New-Object 'System.Collections.Generic.List[byte]'
    $complete = $false
    while ($request.Count -lt 32768) {
        $next = $stream.ReadByte()
        if ($next -lt 0) { return }
        $request.Add([byte]$next)
        $l = $request.Count
        if ($l -ge 4 -and $request[$l-4] -eq 13 -and $request[$l-3] -eq 10 -and $request[$l-2] -eq 13 -and $request[$l-1] -eq 10) { $complete = $true;break }
    }
    if (-not $complete) { return }
    $header = [Text.Encoding]::ASCII.GetString($request.ToArray())
    $lines = $header -split "`r`n"
    if ($lines[0] -notmatch '^(GET|POST) (\S+) HTTP/1\.[01]$') { Json-HTTP $stream 400 @{error='Unsupported HTTP request.'}; return }
    $method = $Matches[1]
    $rawPath = $Matches[2]
    $headers = @{}
    foreach ($line in $lines[1..($lines.Length-1)]) {
        if ($line -match '^([^:]+):\s*(.*)$') { $headers[$Matches[1].ToLowerInvariant()] = $Matches[2].Trim() }
    }
    if (-not $headers.ContainsKey('host') -or $headers.host -ne "127.0.0.1:$port") { Json-HTTP $stream 403 @{error='Only localhost requests are allowed.'}; return }
    if ($method -eq 'POST' -and $headers.ContainsKey('origin') -and $headers.origin -ne $baseUrl) { Json-HTTP $stream 403 @{error='Cross-site writes are not allowed.'};return }
    $uri = [Uri]::new("$baseUrl$rawPath")
    $path = $uri.AbsolutePath
    $query = $uri.Query.TrimStart('?')
    if ($path -eq '/') { Send-HTTP $stream 302 'text/plain' ([byte[]]@()) $true;return }
    if ($path.StartsWith('/api/')) {
        try {
            $data = $null
            if ($method -eq 'POST') {
                $length = 0
                if (-not $headers.ContainsKey('content-length') -or -not [int]::TryParse($headers['content-length'],[ref]$length) -or $length -lt 1 -or $length -gt 20000) { Json-HTTP $stream 413 @{error='Invalid request size.'};return }
                $body = New-Object byte[] $length
                $offset = 0
                while ($offset -lt $length) {
                    $got = $stream.Read($body,$offset,$length-$offset)
                    if ($got -le 0) { throw 'Incomplete request body.' }
                    $offset += $got
                }
                $data = [Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json
            }
            $result = Api-Request $method $path $query $data
            Json-HTTP $stream 200 $result
        } catch {
            Write-Host "API $path - $($_.Exception.Message)" -ForegroundColor Yellow
            Json-HTTP $stream 400 @{error=[string]$_.Exception.Message}
        }
        return
    }
    if ($method -ne 'GET') { Json-HTTP $stream 404 @{error='Not found.'};return }
    $decoded = [Uri]::UnescapeDataString($path)
    $candidate = [IO.Path]::GetFullPath((Join-Path -Path $site -ChildPath ($decoded.TrimStart('/').Replace('/',[IO.Path]::DirectorySeparatorChar))))
    $sitePrefix = [IO.Path]::GetFullPath($site).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($sitePrefix,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { Json-HTTP $stream 404 @{error='Page not found.'};return }
    $ext = [IO.Path]::GetExtension($candidate).ToLowerInvariant()
    $mime = switch ($ext) {'.html' {'text/html; charset=utf-8'} '.css' {'text/css; charset=utf-8'} '.js' {'application/javascript; charset=utf-8'} '.json' {'application/json; charset=utf-8'} '.svg' {'image/svg+xml'} '.png' {'image/png'} '.ico' {'image/x-icon'} '.xml' {'application/xml'} '.txt' {'text/plain; charset=utf-8'} default {$null}}
    if (-not $mime) { Json-HTTP $stream 404 @{error='Unsupported file.'};return }
    $blob = [IO.File]::ReadAllBytes($candidate)
    Send-HTTP $stream 200 $mime $blob
}
# Bind the first available LOCAL port instead of crashing when an older test server
# is already listening on 8765. Keep the listener open once selected (no race).
$listener = $null
try {
    $started = $false
    foreach ($candidatePort in (8765..8785)) {
        $candidateListener = $null
        try {
            $candidateListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, [int]$candidatePort)
            $candidateListener.Start()
            $listener = $candidateListener
            $port = [int]$candidatePort
            $baseUrl = "http://127.0.0.1:$port"
            $started = $true
            break
        } catch {
            if ($null -ne $candidateListener) {
                try { $candidateListener.Stop() } catch { }
            }
            $cause = $_.Exception
            while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
            if ($cause -is [System.Net.Sockets.SocketException] -and
                $cause.SocketErrorCode -eq [System.Net.Sockets.SocketError]::AddressAlreadyInUse) {
                continue
            }
            throw
        }
    }
    if (-not $started) { throw 'Local ports 8765 through 8785 are busy. Stop old Topp Dawg Gaming test windows and try again.' }
    if ($port -ne 8765) {
        Write-Host "Port 8765 is busy; this local test will use port $port instead." -ForegroundColor Yellow
        Write-Host 'You can stop the previous test window with Ctrl+C if you no longer need it.' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'TOPP DAWG GAMING - LOCAL RETAIL PRICING LAB' -ForegroundColor Green
    Write-Host 'No Python installation required. Nothing published online.'
    Write-Host "Retail Price Lab: $baseUrl/lab.html"
    Write-Host "PC Builder:       $baseUrl/builder.html"
    Write-Host 'Press Ctrl+C to stop.'
    Write-Host ''
    try { Start-Process "$baseUrl/lab.html" | Out-Null } catch { Write-Host "Open the Retail Price Lab URL shown above in your browser." }
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try { Serve-Client $client }
        catch { Write-Host "Local request error: $($_.Exception.Message)" -ForegroundColor Yellow }
        finally { $client.Close() }
    }
} catch {
    Write-Host "Could not start local site: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally { if ($null -ne $listener) { $listener.Stop() } }
