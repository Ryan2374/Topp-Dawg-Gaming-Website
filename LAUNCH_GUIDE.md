# Topp Dawg Gaming: Colorado + U.S. Nationwide Launch Guide

Updated November 19, 2026. This is an execution checklist, not a claim that a domain, mailbox, business registration, or online listing is already active.

## What the site now says

- Topp Dawg Gaming welcomes customers in **Colorado**.
- Buyers in the **United States** may request individualized shipping quotes for custom gaming desktops and configured gaming laptops.
- It does not advertise a public storefront, automatically promise local pickup, claim guaranteed shipping costs, promise turnaround dates, or list unverified component stock or warranties.
- Quote inquiries collect **state, 5-digit ZIP code, and desired fulfillment method** so shipping and Colorado handoff options can be estimated separately.
- The quote form currently opens the customer's own email client. **It does not transmit a request automatically** until a tested online forms service is connected.

## Phase 1 — name, domain, and business foundation

1. Search the proposed name **Topp Dawg Gaming** and similar spellings in the Colorado Secretary of State business database and the USPTO trademark search. A domain's availability does not establish the right to use a brand.
2. Check the availability of **toppdawggaming.com** with your chosen registrar. It is a suggestion, **not a confirmed available or owned domain**. If you choose another, change `website_url`, `domain`, and contact addresses in `site-settings.json`.
3. Decide on business structure, register your company or trade name as required, and check municipal and Colorado sales-tax licensing. Sales of computers are retail tangible goods. See https://tax.colorado.gov/new-businesses and https://tax.colorado.gov/sales-tax-guide.
4. Establish a business bank account, bookkeeping, actual supplier sources, and written quote, payment, warranty, return, cancellation, repair/support, and shipping-damage terms before taking deposits or orders.

## Phase 2 — company email (Google Workspace recommended)

You can operate initially with **one paid user** and multiple addresses that arrive in that mailbox, where aliasing is supported. Suggested configuration:

- Main mailbox: `sales@toppdawggaming.com` (paid Google Workspace user)
- Alias: `quotes@toppdawggaming.com` → main sales mailbox
- Alias: `support@toppdawggaming.com` → main sales mailbox

Use a separate mailbox for support later if volume justifies it. Other services are possible; do not buy multiple paid users purely to receive three aliases unless separate logins are needed.

Setup:

1. Register/control the actual domain and decide which address will be the main mailbox.
2. At https://workspace.google.com/pricing choose a plan such as **Business Starter**; review current price and terms (standard listed annual-commitment price on 2026-11-19 was **$7/user/month before tax**, subject to changes and promotions).
3. In Google Admin, choose **verify domain ownership**, then add the unique verification **TXT record** that Google gives you to your DNS provider.
4. Create the paid `sales@` user.
5. Follow Google Admin's Gmail setup wizard to add your actual **MX record(s)**; **do not copy guessed MX values**. Keep only those required by your chosen mail provider. Note that using Cloudflare Email Routing on the same domain can conflict with Google Workspace MX records.
6. Configure **one SPF TXT record**, the Google-generated **DKIM** record, and a **DMARC** record. Google/Cloudflare guides: https://developers.cloudflare.com/dns/manage-dns-records/how-to/set-up-google-workspace/ . If other services send domain email, adapt SPF accordingly rather than adding another SPF record.
7. In Admin > Directory > Users > main user > Alternate email addresses, add the **quotes** and **support** aliases. Verify how to send from an alias if customers need replies to display `quotes@` rather than `sales@`.
8. Turn on two-step verification. Test messages to/from every address with an outside email account. Confirm **SPF, DKIM, and DMARC** are passing using message headers or a testing service.
9. Update `site-settings.json` with confirmed working addresses; run `python build.py` and deploy again. Until these addresses work, don't publish them as active business contact methods.

Google source: https://knowledge.workspace.google.com/admin/gmail/activate-gmail-with-google-workspace-your-company ; aliases: https://support.google.com/a/answer/33327

## Phase 3 — publish Cloudflare Pages

1. Open the project folder and edit `site-settings.json`:
   - `website_url` must be the final https://domain **without a trailing slash**.
   - `domain` must match the actual domain.
   - `sales_email`, `support_email`, `quote_email` must refer to working addresses.
   - `form_endpoint` should stay blank unless you have selected, configured, and tested a supported JSON POST form service.
2. Run `python build.py` with Python 3. This regenerates all **nine** HTML pages, `robots.txt`, and `sitemap.xml`.
3. Preview at local URL by opening `site/index.html` or running `cd site && python -m http.server 8000` and visiting http://localhost:8000.
4. In https://dash.cloudflare.com/ go to **Workers & Pages**, create a **Pages Direct Upload** project, and upload the **contents of the `site/` folder** or the provided `DEPLOY.zip`.
5. Test the auto-generated `*.pages.dev` staging link. Note that Direct Upload projects **cannot later be converted to Git-integrated projects**: a new project would be required for that migration.
6. Open project > **Custom domains** and register your owned domain. For an apex custom domain (e.g., `example.com`), Cloudflare requires a Cloudflare zone and correct nameservers. Follow the wizard; don't just make a blind CNAME.
7. Set `www` to redirect to the chosen canonical domain (or vice versa) to avoid duplicate variants; consider redirecting `*.pages.dev` to the domain as well.
8. Check every page and form, especially `https://YOUR_DOMAIN/sitemap.xml`, `/robots.txt`, and `/shipping.html`. Confirm HTTPS is valid.

Cloudflare sources: https://developers.cloudflare.com/pages/get-started/direct-upload/ and https://developers.cloudflare.com/pages/configuration/custom-domains/

## Phase 4 — SEO for two kinds of searches

**Colorado search intent:**
- Home page and `colorado.html`: "custom gaming PC Colorado," "Colorado custom gaming desktop," "gaming laptop Colorado."
- Don't add a city address or create city landing pages for Boulder, Denver, Longmont, etc. unless you genuinely serve those markets and have useful local content. Don't invent a physical storefront.

**U.S. nationwide search intent:**
- `desktops.html`: "custom gaming desktop," "made-to-order gaming PC," "gaming and streaming PC."
- `laptops.html`: "custom-configured gaming laptop," "gaming laptop configuration."
- `shipping.html`: "custom gaming PC shipping USA," "gaming computer shipping quote."

**After publication:**

1. Add a **Domain property** for the owned domain in https://search.google.com/search-console . Add Google's own DNS TXT verification value; do not copy an example token.
2. Submit `https://YOUR_DOMAIN/sitemap.xml` under **Sitemaps**. Use URL Inspection on the homepage, desktop, laptop, Colorado, shipping, and contact pages.
3. Visit https://www.bing.com/webmasters/ and **import your Google Search Console site** or verify separately. Confirm the imported/submitted sitemap.
4. Watch **Indexing**, **Performance (queries and pages)**, crawl errors, and actual quote inquiries. SEO can help discovery but **cannot guarantee** indexing or specific rankings.
5. Add authentic photos of delivered systems (with customer permission), original project breakdowns, documented benchmarks with game/version/settings/hardware, specific build stories, and genuine feedback. Build a consistent business identity on relevant social channels rather than fake reviews or keyword-stuffed location pages.
6. Only create a **Google Business Profile** if the company truly meets Google's **in-person customer-contact eligibility criteria** during stated business hours. Nationwide shipping by itself does **not** qualify. If there is no eligible face-to-face contact, focus on organic search and Search Console instead. Do not set all of the United States as a local Google Business Profile service area.

Official sources: https://developers.google.com/search/docs/fundamentals/seo-starter-guide ; https://support.google.com/business/answer/13763036 ; https://www2.bing.com/webmasters/help/add-and-verify-site-12184f8b

## Phase 5 — shipping, taxes and buyer protections before accepting orders

- Write a real **shipping policy**: eligible destinations (continental U.S., Alaska/Hawaii, and territorial addresses if offered), carrier methods, packing and component protection approach, shipping fees, signature requirements, transit insurance/declared value terms, risk of loss, tracking, damaged-on-arrival handling, and return-shipping rules.
- For **desktop towers**, decide how heavy graphics cards, coolers, glass panels and monitors are safely handled in transit. Test the packaging workflow. Do not assume every carrier offers identical coverage.
- For **laptops with lithium-ion batteries**, check the current carrier and **USPS Publication 52** battery rules for installed batteries, package markings and allowable services: https://pe.usps.com/text/pub52/pub52c6_005.htm . Verify actual battery specifications before selecting a carrier.
- Confirm expected component/assembly timeline separately from transit time. The **FTC Mail, Internet, or Telephone Order Merchandise Rule** imposes shipping-date and delay-notice requirements once online/phone orders are solicited; avoid claiming guaranteed ship dates without support: https://www.ftc.gov/legal-library/browse/rules/mail-internet-or-telephone-order-merchandise-rule
- **Colorado** retail sales tax generally uses destination sourcing for shipped goods. Tax rates may vary by address, and local home-rule jurisdictions can have separate requirements. For customers in other states, check whether economic-nexus and other registration obligations apply. Obtain professional tax advice or appropriate ecommerce tax software before accepting paid nationwide orders: https://tax.colorado.gov/sales-tax-guide
- A quote-first site is not a substitute for written final sale/warranty/return/cancellation policies or checkout tools.

## Before launch: quality-control checklist

- [ ] Name cleared; registration/trade name reviewed
- [ ] Domain owned and attached to host
- [ ] Google Workspace user and aliases receiving mail
- [ ] SPF, DKIM, DMARC verified; 2FA enabled
- [ ] Real business address *kept private* unless authorized for publication; no fabricated city, store, hours or phone
- [ ] Confirmed laptop platforms/suppliers and accurate desktop capability
- [ ] Written sales, returns, cancellations, warranty, privacy, and shipping terms reviewed
- [ ] Colorado registration / tax licensing reviewed; interstate tax obligations reviewed
- [ ] Quote form successfully tested (either email client or connected service)
- [ ] HTTPS, canonical domains, mobile layout and navigation working
- [ ] Sitemap submitted to Google and Bing
- [ ] First authentic completed-build photos and product use cases added

## Limitations of this package

This is a nine-page **static, quote-first website**, not a live online store. There is no checkout, product stock system, server-side form handling, paid shipping label system, payments, customer reviews feed, or business email provisioning. Existing files include conceptual visual illustrations in place of genuine product photography. Nothing is live until **you** deploy it, claim a domain, and configure email.
