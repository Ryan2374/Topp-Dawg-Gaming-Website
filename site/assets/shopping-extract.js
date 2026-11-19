(() => {
  // Executed inside a temporary, isolated Edge/Chrome browser tab via CDP.
  // It only reads public shopping SEARCH RESULTS, never retailer product pages.
  const page = String(location.hostname || '').toLowerCase();
  const source = page.includes('google.') ? 'Google Shopping' : (page.includes('bing.') ? 'Bing Shopping' : 'Unknown search');
  const searchUrl = location.href;
  const preview = String(document.body?.innerText || document.body?.textContent || '').slice(0, 5000);
  const blocked = /unusual traffic|automated queries|verify (that )?you are human|prove you('re| are) human|captcha|access denied|this request looks automated/i.test(preview);
  const consent = /before you continue to (google|search)|consent to cookies|privacy and terms/i.test(preview.slice(0, 1100));
  const stores = [
    ['Newegg', /\bnew\s*egg(?:\.com)?\b/i, /(?:^|\.)newegg\.com$/i],
    ['B&H Photo', /\bb\s*&\s*h\b|\bbhphotovideo(?:\.com)?\b|\bb\s+and\s+h\b/i, /(?:^|\.)bhphotovideo\.com$/i],
    ['Micro Center', /\bmicro\s*center(?:\.com)?\b/i, /(?:^|\.)microcenter\.com$/i],
    ['Best Buy', /\bbest\s*buy(?:\.com)?\b/i, /(?:^|\.)bestbuy\.com$/i]
  ];
  const pricePattern = /(?:US\s*)?\$\s*((?:\d{1,3}(?:,\d{3})+|\d{1,6})(?:\.\d{2})?)/g;
  const productLinks = el => Array.from(el.querySelectorAll('a[href]')).slice(0, 20);
  const text = el => String(el?.innerText || el?.textContent || '').replace(/\s+/g, ' ').trim();
  const cost = raw => {
    const value = Number(String(raw).replace(/,/g, ''));
    return Number.isFinite(value) && value >= 10 && value <= 15000 ? value : null;
  };
  const listedPrice = s => {
    const matches = Array.from(String(s).matchAll(pricePattern));
    return matches.map(m => cost(m[1])).find(v => v !== null) ?? null;
  };
  const domainFor = href => {
    try { return new URL(href).hostname.toLowerCase(); } catch (_) { return ''; }
  };
  const candidates = [];
  const seen = new Set();
  // Common Google/Bing shopping card patterns plus semantic fallback.
  const css = '[data-docid],[data-oid],[data-offer-id],.sh-dgr__grid-result,.sh-dlr__list-result,.pla-unit,[role="listitem"],article,li,div';
  const nodes = Array.from(document.querySelectorAll(css)).slice(0, 9000);
  for (const el of nodes) {
    const body = text(el);
    if (body.length < 25 || body.length > 650 || !body.includes('$')) continue;
    const price = listedPrice(body);
    if (price === null) continue;
    const links = productLinks(el);
    let vendorName = null, vendorDomain = null, productUrl = null;
    for (const [name, vendorText, vendorHost] of stores) {
      const direct = links.find(a => vendorHost.test(domainFor(a.href)));
      if (direct || vendorText.test(body)) {
        vendorName = name;
        vendorDomain = vendorHost;
        productUrl = direct ? direct.href : null;
        break;
      }
    }
    if (!vendorName) continue;
    const headings = Array.from(el.querySelectorAll('h3,h4,[role="heading"]')).map(text).filter(v => v.length >= 11 && v.length <= 200);
    const anchorNames = links.map(a => text(a) || a.getAttribute('aria-label') || '').filter(v => v.length >= 16 && v.length <= 190 && !/^visit|shop|buy|compare|view deal/i.test(v));
    let title = headings[0] || anchorNames[0] || '';
    if (!title) {
      const pieces = String(el.innerText || el.textContent || '').split('\n').map(x => x.trim()).filter(Boolean);
      title = pieces.find(x => x.length >= 16 && x.length <= 190 && !x.includes('$') && !stores.some(([nm,rx])=>rx.test(x) && x.length < 35)) || '';
    }
    if (!title || /^\$|^shop|^visit|^view|^offers/i.test(title)) continue;
    title = title.slice(0, 200);
    const identity = `${vendorName}|${title.toLowerCase()}|${price.toFixed(2)}`;
    if (seen.has(identity)) continue;
    seen.add(identity);
    const stock = /\bout of stock\b|\bsold out\b/i.test(body) ? 'out_of_stock' : 'unknown';
    candidates.push({ vendor: vendorName, title, price, availability: stock, productUrl, searchUrl, engine: source, evidence: 'visible_shopping_card' });
  }
  // Prefer the smallest matching card; large ancestor text is more likely to mix different offers.
  // Avoid duplicate parent/child candidates: keep shortest card for each vendor + price.
  const byOffer = new Map();
  for (const item of candidates) {
    const key = `${item.vendor}|${item.price}`;
    const prior = byOffer.get(key);
    if (!prior || item.title.length > prior.title.length) byOffer.set(key, item);
  }
  const offers = Array.from(byOffer.values()).slice(0, 32);
  return { source, searchUrl, blocked, consent, offers, pageTitle: document.title, visibleCharacters: preview.length };
})()
