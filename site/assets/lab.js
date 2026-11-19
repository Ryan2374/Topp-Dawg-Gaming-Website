(()=>{'use strict';
const $=id=>document.getElementById(id);
const money=n=>new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(Number(n));
let catalog={}, activePart='', bookmark='';
function status(message,bad=false){$('status').textContent=message;$('status').classList.toggle('bad',bad);}
function setPartOptions(data){catalog=data.parts;const sel=$('part');const prior=sel.value;sel.replaceChildren();
 const groups=[['desktop','Desktop components'],['laptop','Laptop components'],['both','Operating system']];
 for(const [mode,label] of groups){let opt=document.createElement('optgroup');opt.label=label;
  for(const [key,p] of Object.entries(catalog)){if(p.mode!==mode)continue;let o=new Option(p.category.toUpperCase()+' — '+p.name,key);opt.append(o)}
  sel.append(opt);}
 const wanted=new URLSearchParams(location.search).get('part');sel.value=prior&&catalog[prior]?prior:(wanted&&catalog[wanted]?wanted:sel.options[0]?.value||'');onPartChanged();}
async function api(path,data){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const j=await r.json();if(!r.ok)throw Error(j.error||'Request failed');return j;}
function showOffer(j){const e=j.offer;$('result').classList.add('show');$('result-title').textContent=e.title||e.vendor+' observation';$('cost').textContent=money(e.price);$('markup').textContent=j.markupPercent.toFixed(2)+'%';$('selling').textContent=money(j.sellingPrice);
 $('product-source').textContent=e.vendor+' | '+e.extraction+' | stock: '+e.availability+' | '+new Date(e.checked_at).toLocaleString();}
async function load(){try{const r=await fetch('/api/lab',{cache:'no-store'});if(!r.ok)throw Error('server unreachable');const data=await r.json();if(!Object.keys(catalog).length)setPartOptions(data);
 const body=$('offer-rows');body.replaceChildren();if(!data.offers.length){const row=body.insertRow();row.innerHTML='<td colspan="7">No automatically retrieved retail prices yet. Choose a part and click Search Retailers Automatically.</td>';return;}
 data.offers.sort((a,b)=>b.checked_at.localeCompare(a.checked_at));
 for(const o of data.offers){const tr=body.insertRow();const c1=tr.insertCell();c1.textContent=o.partName;const c2=tr.insertCell();const a=document.createElement('a');a.textContent=o.vendor;a.href=o.url;a.target='_blank';a.rel='noopener noreferrer';c2.append(a);const small=document.createElement('small');small.textContent=new Date(o.checked_at).toLocaleString()+(o.stale?' (expired)':'');c2.append(small);
 tr.insertCell().textContent=money(o.price);tr.insertCell().textContent=o.markupPercent.toFixed(2)+'%';tr.insertCell().textContent=money(o.sellingPrice);
 const c6=tr.insertCell();const tag=document.createElement('span');tag.className='lab-badge'+(o.availability==='unknown'?' unknown':o.availability==='out_of_stock'?' sold':'');tag.textContent=o.kind==='shopping'?'Search listing — unverified':(({in_stock:'In stock (page claim)',out_of_stock:'Sold out',unknown:'Stock unconfirmed'})[o.availability]||'Unknown');c6.append(tag);
 const del=document.createElement('button');del.textContent='Remove';del.type='button';del.onclick=async()=>{if(!confirm('Remove this observation?'))return;await api('/api/delete',{key:o.key,url:o.url,kind:o.kind||'retail',vendor:o.vendor,price:o.price,title:o.title});await load()};tr.insertCell().append(del);
 }}catch(e){status('Could not connect to the local testing server: '+e.message,true)}}
function markup(cost){return cost<=50?.2:cost>=1000?.05:.2-(cost-50)*.15/950}
function calculate(){const c=Number($('calc-cost').value);$('calc-result').textContent=c>0?money(c*(1+markup(c)))+'  |  '+(markup(c)*100).toFixed(2)+'%':'Enter a positive cost';}
function bookmarkletFor(key){/* This runs inside the product page, reading only user-visible public page metadata. */
 const script=`(()=>{try{let p=null,a='unknown',t=document.title;for(const e of document.querySelectorAll('script[type="application/ld+json"]')){try{const v=JSON.parse(e.textContent);const walk=(n)=>{if(Array.isArray(n)){for(const x of n)walk(x)}else if(n&&typeof n==='object'){let types=n['@type']||[];if(typeof types==='string')types=[types];if(types.some(x=>String(x).toLowerCase().endsWith('product'))){t=n.name||t;let offers=Array.isArray(n.offers)?n.offers:[n.offers];for(const o of offers){if(o&&o.price&&p===null){p=o.price;a=String(o.availability||'').toLowerCase().includes('outofstock')?'out_of_stock':String(o.availability||'').toLowerCase().includes('instock')?'in_stock':'unknown';break}}}for(const x of Object.values(n))walk(x)}};walk(v)}catch(e){}}if(p===null){for(const k of ['product:price:amount','og:price:amount','price']){let e=document.querySelector('meta[property="'+k+'"],meta[name="'+k+'"],meta[itemprop="'+k+'"]');if(e&&e.content){p=e.content;break}}}if(p===null){for(const q of ['.price-current','.priceView-hero-price span','[data-selenium="pricingPrice"]','[itemprop="price"]','[data-testid="price"]']){let e=document.querySelector(q);if(!e)continue;let match=(e.getAttribute('content')||e.textContent||'').match(/\$\s*([\d,]+(?:\.\d{2})?)/);if(match){p=match[1];break}}}if(p===null){alert('No public product price metadata or recognized price element was detected on this page.');return;}const data={key:${JSON.stringify(key)},url:location.href,price:String(p).replace(/[$,]/g,''),availability:a,title:t};window.open('http://127.0.0.1:8765/lab.html#capture='+encodeURIComponent(JSON.stringify(data)),'_blank')}catch(e){alert('Could not capture price: '+e.message)}})()`;
 return 'javascript:'+script;}
function onPartChanged(){activePart=$('part').value;bookmark=bookmarkletFor(activePart);$('bookmarklet').href=bookmark;}
async function checkCapture(){if(!location.hash.startsWith('#capture='))return;const raw=decodeURIComponent(location.hash.slice('#capture='.length));history.replaceState(null,'',location.pathname);
 let candidate;try{candidate=JSON.parse(raw)}catch(e){status('Browser capture data was invalid.',true);return;}
 if(!catalog[candidate.key]){status('Captured component is not in the catalog.',true);return;}
 $('part').value=candidate.key;onPartChanged();$('retail-url').value=candidate.url;
 const cost=Number(candidate.price);if(!(cost>0&&cost<100000)){status('The browser capture did not contain a valid price.',true);return;}
 const ok=confirm('Browser captured a retail page price: '+money(cost)+' for '+catalog[candidate.key].name+'.\n\nActual page: '+candidate.title+'\nStock: '+candidate.availability+'\n\nSave this page-observed price for LOCAL TESTING? Verify the exact model yourself.');
 if(!ok){status('Capture was cancelled.');return;}
 try{const j=await api('/api/capture',candidate);showOffer(j);status('Browser-captured price saved. '+money(j.offer.price)+' → '+money(j.sellingPrice)+' after markup. Refresh the PC Builder to see it.');await load()}
 catch(e){status('Capture rejected: '+e.message,true);}}
async function runRetailSearch(){
 const key=$('part').value,part=catalog[key];if(!part)return;
 $('auto-search').disabled=true;
 $('result').classList.remove('show');const out=$('auto-results');out.replaceChildren();
 status('Opening isolated Google Chrome shopping searches for '+part.name+'… this may take 15–35 seconds. No copied URLs or accounts needed.');
 try{
  const j=await api('/api/shopping',{key});
  let found=0;
  for(const item of (j.results||[])){
    const line=document.createElement('div');
    if(item.status==='estimate'){
      found++;
      const e=item.offer;
      line.textContent=item.vendor+': '+money(e.price)+' shown by '+(e.engine||'shopping search')+' + '+Number(item.markupPercent).toFixed(2)+'% markup = '+money(item.sellingPrice)+' — '+e.title+' (stock NOT confirmed)';
    }else line.textContent=item.vendor+': '+(item.message||'no usable matching price found');
    out.append(line);
  }
  for(const note of (j.diagnostics||[])){const line=document.createElement('div');line.textContent='Search status: '+note;out.append(line);}
  if(j.status==='needs_model'){status(j.message,true);}
  else if(found){
    const best=j.results.filter(x=>x.status==='estimate').sort((a,b)=>a.sellingPrice-b.sellingPrice)[0];
    const o=best.offer;
    showOffer({offer:{...o,extraction:'Shopping search result (unverified)',checked_at:o.checked_at,availability:'unknown'},markupPercent:best.markupPercent,sellingPrice:best.sellingPrice});
    status('Found '+found+' retailer(s) with matching price observations. The PC Builder now shows an ESTIMATE; stock, model variant, shipping and checkout price are unverified.');
  }else status(j.message||'No reliable shopping prices found. No prices have been invented.',true);
  await load();
 }catch(e){status('Shopping search failed: '+e.message+' — no sample prices were substituted.',true)}
 finally{$('auto-search').disabled=false;}
}
$('auto-search').onclick=runRetailSearch;
$('check-form').onsubmit=async e=>{e.preventDefault();const url=$('retail-url').value.trim();$('check').disabled=true;status('Requesting the actual product page...');$('result').classList.remove('show');
 try{const j=await api('/api/fetch',{key:$('part').value,url});showOffer(j);status('Retail page price read and saved. '+money(j.offer.price)+' → '+money(j.sellingPrice)+' after '+j.markupPercent.toFixed(2)+'% markup.');await load()}
 catch(err){status('Price not captured: '+err.message+'\nYou can open the retailer page and try the optional browser capture method below.',true)}finally{$('check').disabled=false;}};
$('open-url').onclick=()=>{try{const u=new URL($('retail-url').value);if(u.protocol!=='https:')throw Error('HTTPS required');window.open(u.href,'_blank','noopener,noreferrer')}catch(e){status('Enter a valid HTTPS product URL first.',true)}};
$('part').addEventListener('change',onPartChanged);
$('calc-cost').addEventListener('input',calculate);
$('copy-bookmarklet').onclick=async()=>{try{await navigator.clipboard.writeText(bookmark);status('Bookmarklet copied. Create a browser bookmark and paste the code as its URL. Choose the component BEFORE copying.')}catch(e){status('Copy not available. Try dragging the Capture Retail Price link to your bookmarks bar.',true)}};
$('refresh').onclick=async()=>{$('refresh-status').textContent='Rechecking the selected part via shopping search…';await runRetailSearch();$('refresh-status').textContent='Selected part search finished. Other saved observations retain their own timestamps.'};
calculate();load().then(checkCapture);
})();
