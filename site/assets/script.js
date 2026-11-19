(function(){
  const menu=document.querySelector('[data-menu-toggle]');
  const nav=document.querySelector('[data-nav]');
  if(menu&&nav){menu.addEventListener('click',()=>{const open=nav.classList.toggle('is-open');menu.setAttribute('aria-expanded',String(open));menu.textContent=open?'Close ✕':'Menu ☰';});}
  const form=document.querySelector('#quote-form');
  if(!form)return;
  // A parts selection is carried to the request form through an ordinary URL parameter.
  // This does not transmit anything until a customer sends the resulting email/form.
  const imported=new URLSearchParams(location.search).get('configuration') || window.__tdgPreviewImported;
  if(imported){
    const notes=form.querySelector('#notes');
    if(notes){notes.value=imported.slice(0,notes.maxLength || 2000);}
    const system=form.querySelector('#system');
    if(system && imported.includes('System: Custom-configured gaming laptop'))
      system.value='Custom-configured gaming laptop';
    else if(system && imported.includes('System: Custom gaming desktop'))
      system.value='Custom gaming desktop';
    const notice=document.getElementById('imported-build-message');
    if(notice){notice.hidden=false;notice.textContent='Your selected component list has been added to Additional details below. Complete the remaining fields, review the details, then send your inquiry.';}
  }
  const message=document.querySelector('#form-message');
  const cfg={email:form.dataset.email,endpoint:form.dataset.endpoint};
  function quoteText(data){return [
    'Topp Dawg Gaming — Custom Quote Request','',
    'Name: '+data.name,'Email: '+data.email,'Phone: '+(data.phone||'Not provided'),
    'System: '+data.system,'Budget: '+data.budget,'Gaming target: '+data.resolution,
    'Primary use: '+data.primary,'Timing: '+data.timing,
    'Fulfillment preference: '+data.delivery,'Destination state: '+data.state,'Destination ZIP: '+data.zip,
    'Location notes: '+(data.locationnotes||'Not provided'),
    'Games / applications: '+(data.games||'Not specified'),
    'Additional details: '+(data.notes||'Not specified'),'',
    'Please reply with suggested configuration, availability, pricing, and next steps.'
  ].join('\n');}
  form.addEventListener('submit',async (event)=>{
    event.preventDefault();if(!form.reportValidity())return;
    const data=Object.fromEntries(new FormData(form).entries());
    const text=quoteText(data);
    if(cfg.endpoint){
      try{
        message.textContent='Sending your request…';
        const res=await fetch(cfg.endpoint,{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({...data,message:text})});
        if(!res.ok)throw new Error('Request failed');
        message.textContent='Request received. We will respond by email.';
        form.reset();
      }catch(err){message.textContent='The online form is unavailable. Please email '+cfg.email+' directly.';}
    }else{
      const mailto='mailto:'+cfg.email+'?subject='+encodeURIComponent('Custom Gaming PC Quote — '+data.name)+'&body='+encodeURIComponent(text);
      message.textContent='Your email application should open with the quote details. Review and click Send to finish.';
      window.location.href=mailto;
    }
  });
  const copy=document.querySelector('#copy-quote');
  if(copy)copy.addEventListener('click',async()=>{
    if(!form.reportValidity())return;
    const text=quoteText(Object.fromEntries(new FormData(form).entries()));
    try{await navigator.clipboard.writeText(text);message.textContent='Quote details copied. Paste into an email to '+cfg.email+'.';}
    catch(err){message.textContent='Copy is not available in this browser. Use the email button instead.';}
  });
})();
