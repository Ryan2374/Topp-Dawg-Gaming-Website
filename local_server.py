#!/usr/bin/env python3
"""Topp Dawg Gaming local-only retail price lab. Python standard library only.
Run: py -3 local_server.py   Open: http://127.0.0.1:8765/lab.html
Never binds beyond localhost. Public product pages only; no bot/CAPTCHA bypass.
"""
import json
import re
import os
import socket
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from html.parser import HTMLParser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

BASE = Path(__file__).resolve().parent
SITE = BASE / 'site'
FILE = BASE / 'retail-lab-offers.json'
CATALOG = json.loads((BASE / 'parts-catalog.json').read_text(encoding='utf-8'))
LOCK = threading.RLock()
PORT = int(os.environ.get('TDG_PORT', '8765'))
MAX_HTML = 7_000_000
MAX_POST = 20_000
VENDORS = {
    'newegg.com': 'Newegg',
    'bhphotovideo.com': 'B&H Photo',
    'microcenter.com': 'Micro Center',
    'bestbuy.com': 'Best Buy',
}

def list_keys():
    result={}
    for mode in ('desktop','laptop'):
        for cat, items in CATALOG[mode].items():
            for item in items:
                key=f'{mode}.{cat}.{item["id"]}'
                result[key]={'name':item['name'],'mode':mode,'category':cat}
    for item in CATALOG['os']:
        result[f'os.{item["id"]}']={'name':item['name'],'mode':'both','category':'os'}
    return result
PARTS=list_keys()

def utcnow():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')

def source_for_url(url):
    p=urlparse(url)
    host=(p.hostname or '').lower().rstrip('.')
    if p.scheme!='https' or p.username or p.password or p.port not in (None,443):
        raise ValueError('Use a normal HTTPS retailer product-page URL (no credentials or custom ports).')
    for suffix, name in VENDORS.items():
        if host==suffix or host.endswith('.'+suffix):
            return name
    raise ValueError('Supported product-page domains: Newegg, B&H, Micro Center, Best Buy.')

class CheckedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        source_for_url(newurl)
        return super().redirect_request(req,fp,code,msg,headers,newurl)

class PageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ld=[]; self.meta={}; self.title=''; self._script=False; self._title=False; self._buffer=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='script' and 'ld+json' in a.get('type','').lower():
            self._script=True; self._buffer=[]
        if tag=='title': self._title=True
        if tag=='meta':
            key=(a.get('property') or a.get('name') or a.get('itemprop') or '').strip().lower()
            if key and a.get('content') and key not in self.meta:
                self.meta[key]=a['content'].strip()
    def handle_endtag(self,tag):
        if tag=='script' and self._script:
            try:self.ld.append(json.loads(''.join(self._buffer)))
            except (json.JSONDecodeError,ValueError): pass
            self._script=False; self._buffer=[]
        if tag=='title':self._title=False
    def handle_data(self,data):
        if self._script:self._buffer.append(data)
        if self._title:self.title+=data

def walk_json(node):
    if isinstance(node,dict):
        yield node
        for val in node.values(): yield from walk_json(val)
    elif isinstance(node,list):
        for val in node: yield from walk_json(val)

def clean_amount(value):
    if value is None or isinstance(value,bool):return None
    if isinstance(value,str):
        value=re.sub(r'[$,\s]', '',value)
        if not re.fullmatch(r'\d{1,6}(?:\.\d{1,2})?',value):return None
    try: v=Decimal(str(value))
    except Exception:return None
    if v<=0 or v>Decimal('100000'):return None
    return float(v.quantize(Decimal('0.01'),rounding=ROUND_HALF_UP))

def normalized_stock(value):
    if value is None:return 'unknown'
    v=str(value).lower()
    if 'outofstock' in v or 'soldout' in v or 'discontinued' in v or 'instoreonly' in v:return 'out_of_stock'
    if 'instock' in v or 'limitedavailability' in v:return 'in_stock'
    return 'unknown'

def extract_product(html):
    parser=PageParser(); parser.feed(html); parser.close()
    metadata=parser.meta
    for payload in parser.ld:
        for row in walk_json(payload):
            kinds=row.get('@type',[])
            if isinstance(kinds,str):kinds=[kinds]
            if not any(str(k).lower().endswith(('product','productgroup')) for k in kinds):continue
            for offer in (row.get('offers') if isinstance(row.get('offers'),list) else [row.get('offers')]):
                if not isinstance(offer,dict):continue
                currency=offer.get('priceCurrency') or row.get('priceCurrency') or 'USD'
                if str(currency).upper() != 'USD':continue
                amount=clean_amount(offer.get('price'))
                if amount is None and isinstance(offer.get('priceSpecification'),dict):
                    amount=clean_amount(offer['priceSpecification'].get('price'))
                if amount is None:continue
                name=str(row.get('name') or metadata.get('og:title') or parser.title).strip()[:220]
                return {'price':amount, 'availability':normalized_stock(offer.get('availability')), 'title':name, 'extraction':'Product JSON-LD offer'}
    for key in ('product:price:amount','og:price:amount','price','price:amount','product:price'):
        amount=clean_amount(metadata.get(key))
        if amount is not None:
            currency=metadata.get('product:price:currency') or metadata.get('pricecurrency') or 'USD'
            if currency.upper()!='USD':continue
            return {'price':amount,'availability':normalized_stock(metadata.get('availability') or metadata.get('product:availability')),
                    'title':str(metadata.get('og:title') or parser.title).strip()[:220], 'extraction':f'HTML metadata ({key})'}
    return None

def fetch_page(url):
    vendor=source_for_url(url)
    opener=urllib.request.build_opener(CheckedRedirect())
    req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36','Accept':'text/html,application/xhtml+xml','Accept-Language':'en-US,en;q=0.9','Accept-Encoding':'identity'})
    try:
        with opener.open(req,timeout=15) as response:
            source_for_url(response.geturl())
            ct=response.headers.get('content-type','').lower()
            if ct and 'html' not in ct:raise ValueError(f'Retailer returned {ct}, not an HTML product page.')
            data=response.read(MAX_HTML+1)
            if len(data)>MAX_HTML:raise ValueError('Retailer page is larger than the test safety limit.')
            charset=response.headers.get_content_charset() or 'utf-8'
            html=data.decode(charset,errors='replace')
    except urllib.error.HTTPError as e:
        if e.code in (403,429,503):raise ValueError(f'HTTP {e.code}: the retailer blocked or limited automated requests. Open the page in your browser; do not assume a price.')
        raise ValueError(f'Retailer returned HTTP {e.code}.')
    except (urllib.error.URLError,TimeoutError,socket.timeout) as e:
        raise ValueError(f'Connection failed: {e.reason if isinstance(e,urllib.error.URLError) else str(e)}')
    record=extract_product(html)
    if not record:raise ValueError('Page loaded, but no trustworthy product price was found in its public structured data. No price was assumed.')
    record.update({'vendor':vendor,'url':url,'checked_at':utcnow()})
    return record

def markup_pct(cost):
    c=Decimal(str(cost))
    if c<=50:return Decimal('0.20')
    if c>=1000:return Decimal('0.05')
    return Decimal('0.20') - (c-Decimal('50'))*Decimal('0.15')/Decimal('950')

def selling_price(cost):
    c=Decimal(str(cost))
    return float((c*(1+markup_pct(cost))).quantize(Decimal('0.01'),rounding=ROUND_HALF_UP))

def load_offers():
    if not FILE.exists():return []
    try:
        rows=json.loads(FILE.read_text(encoding='utf-8'))
        return rows if isinstance(rows,list) else []
    except (ValueError,OSError):return []

def write_offers(rows):
    with tempfile.NamedTemporaryFile('w',encoding='utf-8',dir=BASE,prefix='.tmp-prices-',delete=False) as f:
        json.dump(rows,f,indent=2);f.write('\n');name=f.name
    os.replace(name,FILE)

def save_offer(key,record):
    if key not in PARTS:raise ValueError('Choose a valid component before checking its price.')
    if not isinstance(record,dict):raise ValueError('Invalid retailer response.')
    vendor=source_for_url(record.get('url',''))
    cost=clean_amount(record.get('price'))
    if cost is None:raise ValueError('Price was not a valid positive USD amount.')
    entry={'key':key,'vendor':vendor,'url':record['url'],'price':cost,
           'availability':record.get('availability') if record.get('availability') in ('in_stock','out_of_stock','unknown') else 'unknown',
           'title':str(record.get('title') or '')[:220],'extraction':str(record.get('extraction') or 'Browser capture')[:90],
           'checked_at':utcnow()}
    with LOCK:
        rows=[r for r in load_offers() if not(r.get('key')==key and r.get('vendor')==vendor and r.get('url')==record['url'])]
        rows.append(entry);write_offers(rows)
    return entry

def age_seconds(ts):
    try:return max(0,(datetime.now(timezone.utc)-datetime.fromisoformat(ts.replace('Z','+00:00'))).total_seconds())
    except Exception:return 1e20

def eligible(rows):
    # This is a price experiment, NOT verified inventory. A recently observed retail listing
    # can be shown even if the retailer did not provide structured availability metadata.
    valid=[r for r in rows if r.get('availability')!='out_of_stock' and age_seconds(r.get('checked_at',''))<=7200]
    if not valid:return None
    in_stock=[r for r in valid if r.get('availability')=='in_stock']
    return min(in_stock or valid,key=lambda r:r['price'])

def price_api(mode):
    groups=[(key,v) for key,v in PARTS.items() if v['mode'] in (mode,'both')]
    with LOCK: rows=load_offers()
    results=[]
    for key,_ in groups:
        if key=='os.none':
            results.append({'key':key,'retailPrice':0,'availability':'in_stock','source':'local_fixed_price'});continue
        winner=eligible([r for r in rows if r.get('key')==key])
        results.append({'key':key,'retailPrice':selling_price(winner['price']) if winner else None,
                        'availability': winner['availability'] if winner else 'unverified',
                        'source':'live_page_observation' if winner else 'not_checked',
                        'vendor':winner['vendor'] if winner else None,
                        'checkedAt':winner['checked_at'] if winner else None})
    return {'mode':mode,'prices':results,'status':'local_test','checkedAt':utcnow()}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(SITE),**kwargs)
    def log_message(self,format,*args): print('[LOCAL]',format%args)
    def jsonout(self,data,status=200):
        blob=json.dumps(data,ensure_ascii=False).encode('utf-8')
        self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Length',str(len(blob)));self.end_headers();self.wfile.write(blob)
    def do_GET(self):
        p=urllib.parse.urlparse(self.path)
        if p.path=='/':self.send_response(302);self.send_header('Location','/builder.html');self.end_headers();return
        if p.path=='/api/prices':
            mode=urllib.parse.parse_qs(p.query).get('mode',['desktop'])[0]
            if mode not in ('desktop','laptop'):return self.jsonout({'error':'Invalid mode'},400)
            return self.jsonout(price_api(mode))
        if p.path=='/api/lab':
            with LOCK:rows=load_offers()
            for row in rows:
                row['markupPercent']=round(float(markup_pct(row['price']))*100,3)
                row['sellingPrice']=selling_price(row['price'])
                row['stale']=age_seconds(row.get('checked_at',''))>7200
                row['partName']=PARTS.get(row['key'],{}).get('name','Unknown')
            return self.jsonout({'parts':PARTS,'offers':rows,'asOf':utcnow(),'localTest':True})
        if p.path.startswith('/api/'):
            return self.jsonout({'error':'Unknown API route'},404)
        return super().do_GET()
    def do_POST(self):
        # Do not accept cross-site write requests from unrelated webpages.
        origin=self.headers.get('Origin')
        if origin and origin!=f'http://127.0.0.1:{PORT}':
            return self.jsonout({'error':'Cross-site writes are not allowed in this local test.'},403)
        p=urllib.parse.urlparse(self.path)
        size=int(self.headers.get('Content-Length','0') or 0)
        if size<=0 or size>MAX_POST:return self.jsonout({'error':'Invalid request size'},413)
        try:data=json.loads(self.rfile.read(size))
        except (ValueError,UnicodeError):return self.jsonout({'error':'Invalid JSON body'},400)
        try:
            if p.path=='/api/fetch':
                key=data.get('key')
                if key not in PARTS:raise ValueError('Select a valid component.')
                record=fetch_page(str(data.get('url','')))
                entry=save_offer(key,record)
                return self.jsonout({'ok':True,'offer':entry,'markupPercent':round(float(markup_pct(entry['price']))*100,3),'sellingPrice':selling_price(entry['price'])})
            if p.path=='/api/capture':
                # Browser-assisted extraction: still observed public data, not guaranteed stock.
                record={'url':str(data.get('url','')),'price':data.get('price'),'title':str(data.get('title','')),
                        'availability':str(data.get('availability','unknown')),'extraction':'Browser-observed page data'}
                entry=save_offer(data.get('key'),record)
                return self.jsonout({'ok':True,'offer':entry,'markupPercent':round(float(markup_pct(entry['price']))*100,3),'sellingPrice':selling_price(entry['price'])})
            if p.path=='/api/delete':
                key=str(data.get('key',''));url=str(data.get('url',''))
                with LOCK:
                    old=load_offers();new=[r for r in old if not(r.get('key')==key and r.get('url')==url)]
                    write_offers(new)
                return self.jsonout({'ok':True,'removed':len(old)-len(new)})
            if p.path=='/api/refresh':
                with LOCK:rows=load_offers()
                if not rows:return self.jsonout({'ok':True,'refreshed':0,'results':[]})
                def one(row):
                    try:
                        offer=fetch_page(row['url']);save_offer(row['key'],offer)
                        return {'vendor':row['vendor'],'key':row['key'],'ok':True}
                    except Exception as err:
                        return {'vendor':row['vendor'],'key':row['key'],'ok':False,'error':str(err)[:280]}
                with ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(one,rows[:50]))
                return self.jsonout({'ok':True,'refreshed':sum(r['ok'] for r in results),'results':results})
            return self.jsonout({'error':'Unknown route'},404)
        except ValueError as error:return self.jsonout({'error':str(error)},400)
        except Exception as error:return self.jsonout({'error':'Lookup failed: '+str(error)[:240]},502)

def main():
    try: server=ThreadingHTTPServer(('127.0.0.1',PORT),Handler)
    except OSError as err:
        print(f'Unable to start local test server: {err}');return 1
    url=f'http://127.0.0.1:{PORT}/lab.html'
    print('\nTOPP DAWG GAMING LOCAL RETAIL TEST')
    print('Open:',url)
    print('PC Builder: http://127.0.0.1:%d/builder.html'%PORT)
    print('No online hosting or supplier accounts required. Press CTRL+C to stop.\n')
    if '--no-browser' not in sys.argv:
        try:webbrowser.open(url)
        except Exception:pass
    try:server.serve_forever()
    except KeyboardInterrupt:print('\nLocal test server stopped.')
    finally:server.server_close()
    return 0

if __name__=='__main__':sys.exit(main())
