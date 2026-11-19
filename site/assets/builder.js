(function () {
  'use strict';
  const root = document.getElementById('pc-builder');
  const catalogElement = document.getElementById('builder-data');
  if (!root || !catalogElement) return;
  const catalog = JSON.parse(catalogElement.textContent);
  const fieldsRoot = document.getElementById('builder-fields');
  const lineRoot = document.getElementById('builder-summary-lines');
  const feedback = document.getElementById('builder-feedback');
  const totalElement = document.getElementById('builder-total');
  const quoteButton = document.getElementById('builder-quote');
  const copyButton = document.getElementById('builder-copy');
  const resetButton = document.getElementById('builder-reset');
  const actionStatus = document.getElementById('builder-action-status');
  const pricingStatus = document.getElementById('pricing-status');
  const money = value => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
  const names = {
    cpu: 'Processor / CPU', motherboard: 'Motherboard', gpu: 'Graphics card / GPU',
    ram: 'Memory / RAM', ssd: 'Storage / SSD', cooler: 'CPU cooling',
    case: 'Case', psu: 'Power supply', os: 'Operating system',
    platform: 'Laptop platform'
  };
  const desktopKeys = ['cpu','motherboard','gpu','ram','ssd','cooler','case','psu','os'];
  const laptopKeys = ['platform','ram','ssd','os'];
  const introText = {
    desktop: ['DESKTOP BUILD COMPONENTS','Choose your parts.','All parts are enabled for local testing. Use the automatic retail price checker to find product prices without entering URLs. Only successfully retrieved prices are displayed.'],
    laptop: ['LAPTOP CONFIGURATION OPTIONS','Configure a laptop.','All laptop options are enabled in this local test; final upgrade compatibility is not validated. Test automatic retail product search in the Price Lab.']
  };
  const defaults = {
    desktop: { cpu:'r5',motherboard:'b650',gpu:'5070',ram:'32',ssd:'2',cooler:'air',case:'airflow',psu:'750',os:'win11' },
    laptop: { platform:'portable15',ram:'32',ssd:'2',os:'win11' }
  };
  const initialMode = (new URLSearchParams(location.search).get('type') === 'laptop' || window.__tdgPreviewMode === 'laptop') ? 'laptop' : 'desktop';
  let mode = initialMode;
  const pricing = {};
  let pricingState = 'loading';
  let lastChecked = null;
  const cache = {};
  const moneyOrRequest = entry => entry && typeof entry.retailPrice === 'number' ? money(entry.retailPrice) : 'Request price';
  const priceKey = (key,id) => key === 'os' ? 'os.'+id : mode+'.'+key+'.'+id;
  const priceFor = (key,item) => pricing[priceKey(key,item.id)];
  const selections = { desktop: {...defaults.desktop}, laptop: {...defaults.laptop} };
  function items(key) { return key==='os' ? catalog.os : catalog[mode][key]; }
  // LOCAL TEST: show every catalog entry, even when a retailer price is not yet checked.
  // Availability and exact SKU matching are deliberately not claimed as verified.
  function availableItems(key) { return items(key); }
  function selected(key) {
    return availableItems(key).find(item=>item.id===selections[mode][key]) || null;
  }
  function fieldKeys() { return mode==='desktop' ? desktopKeys : laptopKeys; }
  function makeElement(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }
  function makeFields() {
    fieldsRoot.replaceChildren();
    fieldKeys().forEach((key,index)=>{
      const box=makeElement('div','builder-field');
      const top=makeElement('div','builder-field-top');
      const label=makeElement('label','builder-field-label',names[key]);
      const selectId='part-'+key;
      label.htmlFor=selectId;
      top.append(label,makeElement('span','builder-field-number',String(index+1).padStart(2,'0')));
      const control=makeElement('select','builder-part-select');
      control.id=selectId;
      control.dataset.part=key;
      control.setAttribute('aria-label',names[key]);
      const visible=availableItems(key);
      if(!visible.length){
        const option=document.createElement('option');
        option.value='';
        option.textContent=pricingState==='checking' || pricingState==='loading'
          ? 'Checking verified inventory...':'No catalog options';
        control.append(option);
        control.disabled=true;
        selections[mode][key]='';
      } else {
        // The saved selection may have sold out since the previous request.
        if(!visible.some(item=>item.id===selections[mode][key])) selections[mode][key]=visible[0].id;
        visible.forEach(item=>{
          const option=document.createElement('option');
          option.value=item.id;
          option.textContent=item.name+'  |  '+moneyOrRequest(priceFor(key,item));
          control.append(option);
        });
        control.value=selections[mode][key];
      }
      box.append(top,control);
      if(key==='motherboard')box.append(makeElement('p','builder-field-hint','Only boards matching the CPU socket are compatible.'));
      if(key==='psu')box.append(makeElement('p','builder-field-hint','Final power capacity and cables are verified before an order.'));
      if(key==='platform')box.append(makeElement('p','builder-field-hint','Only actual approved laptop models can be offered.'));
      fieldsRoot.append(box);
    });
  }
  function validate() {
    const problems=[];
    const missing=fieldKeys().filter(key=>!selected(key));
    if(missing.length){
      problems.push('These categories have no selected options: '+missing.map(key=>names[key]).join(', ')+'. Please request a custom sourcing quote.');
      return problems;
    }
    if(mode!=='desktop')return problems;
    const cpu=selected('cpu'),board=selected('motherboard'),gpu=selected('gpu'),pcase=selected('case'),psu=selected('psu');
    if(cpu.socket!==board.socket)problems.push('CPU and motherboard sockets do not match.');
    if(gpu.length>pcase.maxGpu)problems.push('GPU length exceeds the case clearance.');
    if(psu.watts<gpu.psuMin)problems.push('Power supply wattage is below the GPU guideline.');
    if(!pcase.form.includes(board.form))problems.push('Motherboard size does not fit this case.');
    return problems;
  }
  function estimatedTotal() {
    const retail = fieldKeys().map(key => selected(key) ? priceFor(key,selected(key))?.retailPrice : null);
    if(retail.some(value => typeof value !== 'number' || !Number.isFinite(value))) return null;
    return Math.round((retail.reduce((a,b)=>a+b,0)+(mode==='desktop' ? catalog.assembly : 0))*100)/100;
  }
  function summaryText() {
    const lines = [
      'Topp Dawg Gaming / Build Configurator',
      'System: ' + (mode==='desktop'?'Custom gaming desktop':'Custom-configured gaming laptop'),
      ''
    ];
    fieldKeys().forEach(key => lines.push(names[key] + ': ' + (selected(key)?.name || 'No selection')));
    if(mode==='laptop' && selected('platform')) lines.push('Laptop concept notes: ' + selected('platform').details);
    fieldKeys().forEach(key => lines.push('Estimated selling price ('+names[key]+'): ' + (selected(key)?moneyOrRequest(priceFor(key,selected(key))):'Not currently available')));
    if(mode==='desktop') lines.push('Assembly and testing: ' + money(catalog.assembly));
    lines.push('Estimated subtotal: '+(estimatedTotal()===null?'Not available - request a written quote':money(estimatedTotal())));
    lines.push('Pricing status: '+pricingState+(lastChecked?' (checked '+lastChecked+')':''));
    lines.push('LOCAL TEST ONLY. Observed retail page prices are not guaranteed, stock may be unknown, and parts have not been verified for orders.');
    return lines.join('\n');
  }
  function paintSummary() {
    const problems=validate();
    lineRoot.replaceChildren();
    fieldKeys().forEach(key => {
      const row=makeElement('div','summary-line');
      const item=selected(key);
      row.append(makeElement('span','summary-key',names[key]),makeElement('strong','summary-value',item?.name||'No selection'));
      row.append(makeElement('span','summary-key','Selling price'),makeElement('span','summary-price',item?moneyOrRequest(priceFor(key,item)):'Not checked'));
      if(item){const link=makeElement('a','summary-price','Automatically search prices ↗');link.href='lab.html?part='+encodeURIComponent(priceKey(key,item.id));link.style.fontSize='.76rem';row.append(link)}
      lineRoot.append(row);
    });
    if(mode==='desktop') {
      const row=makeElement('div','summary-line');
      row.append(makeElement('span','summary-key','Assembly / testing'),makeElement('strong','summary-value',money(catalog.assembly)));
      lineRoot.append(row);
    }
    totalElement.textContent=estimatedTotal()===null?'Quote required':money(estimatedTotal());
    document.getElementById('summary-type').textContent=mode==='desktop'?'Custom desktop':'Laptop configuration';
    feedback.replaceChildren();
    if(problems.length){
      const title=makeElement('strong','','Check your selections');
      const ul=document.createElement('ul');
      problems.forEach(issue => ul.append(makeElement('li','',issue)));
      feedback.append(title,ul);
      feedback.className='builder-feedback is-error';
      quoteButton.disabled=true;
      quoteButton.title='Resolve basic compatibility issues first';
    }else{
      feedback.className='builder-feedback is-valid';
      const title=makeElement('strong','',mode==='desktop'?'Basic desktop checks passed':'Local laptop test');
      const checked=fieldKeys().filter(key=>selected(key) && typeof priceFor(key,selected(key))?.retailPrice==='number').length;
      const p=makeElement('p','',checked+' of '+fieldKeys().length+' selected components have observed retail prices. All catalog choices remain visible for local testing. Prices, availability and final compatibility are NOT verified for ordering.');
      feedback.append(title,p);
      quoteButton.disabled=false;
      quoteButton.title='Continue to the quote request form';
    }
  }
  function refresh() { makeFields(); paintSummary(); }
  async function loadPrices(selectedMode,force=false) {
    const generation=selectedMode;
    if(!force && cache[selectedMode] && Date.now()-cache[selectedMode].time<180000){
      Object.assign(pricing,cache[selectedMode].prices);
      pricingState=cache[selectedMode].status;
      lastChecked=cache[selectedMode].checkedAt;
      pricingStatus.textContent=cache[selectedMode].message;
      refresh();return;
    }
    pricingState='checking';
    pricingStatus.textContent='Checking reviewed retail prices and availability…';
    refresh();
    try {
      // Preview and local file:// pages cannot connect to Cloudflare Pages Functions.
      if(location.protocol==='file:' || typeof window.tdgPreviewNavigate==='function') throw new Error('Run start_local_test.bat for automatic retail search.');
      const response=await fetch('/api/prices?mode='+encodeURIComponent(selectedMode), {headers:{'Accept':'application/json'}, cache:'no-store'});
      if(!response.ok) throw new Error('supplier HTTP '+response.status);
      const data=await response.json();
      if(!data || !data.prices || !Array.isArray(data.prices)) throw new Error('invalid supplier data');
      const next={};
      for(const part of data.prices) {
        if(typeof part.key==='string' && (part.retailPrice===null || (typeof part.retailPrice==='number' && Number.isFinite(part.retailPrice) && part.retailPrice>=0))) {
          next[part.key]={retailPrice:part.retailPrice,availability:part.availability || 'unknown',source:part.source||'unavailable'};
        }
      }
      const priced=data.prices.filter(p=>['live_page_observation','shopping_search_estimate'].includes(p.source) && typeof p.retailPrice==='number').length;
      const message=priced ? 'LOCAL TEST: '+priced+' components have recorded retail-page prices or shopping-search estimates. ALL choices enabled. Shopping prices do not verify stock or checkout cost.' : 'LOCAL TEST: All parts are selectable, but no recent price observations are loaded. Open the Retail Price Lab for automatic shopping-result search.';
      cache[selectedMode]={time:Date.now(),prices:next,status:data.status||'unavailable',checkedAt:data.checkedAt,message};
      Object.assign(pricing,next);
      if(mode===generation){pricingState=data.status||'unavailable';lastChecked=data.checkedAt;pricingStatus.textContent=message;refresh();}
    } catch(error) {
      if(mode===generation){pricingState='not_connected';lastChecked=null;pricingStatus.textContent='Local server required for automatic price checks. All component selections remain enabled; no prices are invented. Open the Retail Price Lab.';refresh();}
    }
  }
  const autoPriceButton=document.createElement('button');
  autoPriceButton.type='button';autoPriceButton.className='btn btn-secondary';
  autoPriceButton.textContent='Automatically Price This Build';
  autoPriceButton.style.margin='14px 0';
  pricingStatus.insertAdjacentElement('afterend',autoPriceButton);
  autoPriceButton.addEventListener('click',async()=>{
    autoPriceButton.disabled=true;
    const currentMode=mode;
    const chosen=fieldKeys().filter(k=>k!=='os' || selections[mode][k]!=='none').map(k=>priceKey(k,selections[mode][k]));
    let matched=0,attempted=0,errors=0;
    try{
      for(const key of chosen){
        if(mode!==currentMode)break;
        actionStatus.textContent='Searching shopping listings for '+key+'… ('+(attempted+1)+' of '+chosen.length+'). Each part may take 15–35 seconds.';
        try{
          const r=await fetch('/api/shopping',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({key})});
          const j=await r.json();
          if(!r.ok)throw Error(j.error||'search failed');
          if(j.status==='estimates')matched+=j.results.filter(x=>x.status==='estimate').length;
          else if(j.status!=='not_applicable'&&j.status!=='needs_model')errors++;
        }catch(_err){errors++}
        attempted++;
        await loadPrices(currentMode,true);
      }
      actionStatus.textContent='Shopping searches finished: '+matched+' observed retailer listing(s) for '+attempted+' components; '+errors+' searches unavailable. Prices are search estimates only: stock and checkout cost are UNCONFIRMED. See Price Lab for diagnostics.';
    }finally{autoPriceButton.disabled=false;}
  });
  root.addEventListener('change', event => {
    const target=event.target.closest('select[data-part]');
    if(!target)return;
    const key=target.dataset.part;
    selections[mode][key]=target.value;
    actionStatus.textContent='';
    paintSummary();
  });
  root.querySelectorAll('[data-mode]').forEach(button => {
    button.addEventListener('click', () => {
      mode=button.dataset.mode;
      root.querySelectorAll('[data-mode]').forEach(tab => {
        const active=tab.dataset.mode===mode;
        tab.classList.toggle('active',active);
        tab.setAttribute('aria-pressed',String(active));
      });
      const texts=introText[mode];
      document.getElementById('builder-subtitle').textContent=texts[0];
      document.getElementById('builder-heading').textContent=texts[1];
      document.getElementById('builder-description').textContent=texts[2];
      actionStatus.textContent='';
      refresh();
      loadPrices(mode);
    });
  });
  if(initialMode==='laptop') root.querySelector('[data-mode="laptop"]').click();
  resetButton.addEventListener('click',()=>{ selections[mode]={...defaults[mode]}; actionStatus.textContent='Selections reset. Local test parts remain selectable even without prices.'; refresh(); });
  quoteButton.addEventListener('click',()=>{
    if(validate().length) return;
    const target='contact.html?configuration='+encodeURIComponent(summaryText())+'#quote-form';
    if(typeof window.tdgPreviewNavigate==='function') window.tdgPreviewNavigate(target);
    else location.href=target;
  });
  copyButton.addEventListener('click', async () => {
    const content=summaryText();
    try {
      if(navigator.clipboard && navigator.clipboard.writeText) await navigator.clipboard.writeText(content);
      else {
        const temp=document.createElement('textarea');
        temp.value=content;
        temp.style.position='fixed';temp.style.top='-1000px';
        document.body.append(temp);temp.select();
        if(!document.execCommand('copy')) throw new Error('Copy not available');
        temp.remove();
      }
      actionStatus.textContent='Parts list copied. You can paste it into an email.';
    } catch(_err) { actionStatus.textContent='Copy is unavailable in this browser. Use Request This Build to continue.'; }
  });
  if(initialMode==='desktop') { refresh(); loadPrices('desktop'); }
})();
