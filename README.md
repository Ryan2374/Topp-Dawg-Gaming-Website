# Topp Dawg Gaming — Colorado + Nationwide Site v2

This package contains a nine-page responsive, SEO-ready, quote-first website for Topp Dawg Gaming. It highlights **Colorado customer service** and **U.S. nationwide shipping by individualized quote**, without promising unverified storefronts, local pickup, shipping prices or warranties.

## Your two files
- **FULL_PROJECT.zip** (provided separately): contains this project, editable settings, a Python build script, the 9-page `site/` folder, and the detailed `LAUNCH_GUIDE.md`.
- **DEPLOY.zip** (provided separately): includes the ready-to-upload *contents* of `site/` with the current proposed-domain configuration. Check settings first.

## Pages

- `site/index.html` — home, Colorado/nationwide service positioning
- `site/desktops.html` — gaming desktops
- `site/laptops.html` — configurable gaming laptops
- `site/colorado.html` — Colorado custom PC landing page
- `site/shipping.html` — U.S. shipping quote information
- `site/how-it-works.html` — quote-to-fulfillment process
- `site/faq.html` — buying/shipping FAQ
- `site/contact.html` — customer quote request, including location/delivery data
- `site/privacy.html` — draft privacy notice, subject to business review

## Edit and rebuild

1. Open `site-settings.json` in Notepad, VS Code or similar.
2. Enter the real owned `website_url`, `domain`, and actual working email addresses.
3. In the project folder run `python build.py` (Python 3; no external packages).
4. Preview `site/index.html` locally or serve `site/` via `python -m http.server`.
5. Upload the **contents** of `site/` to your static host. If changing settings, create a **new** deploy ZIP from the rebuilt `site/` folder.

## CRITICAL: quote form

Without a `form_endpoint`, the quote form creates a `mailto:` link; a visitor must have a configured email app, review the text, then click **Send**. No automatic form email is transmitted or received. If you enable a provider endpoint, it must accept JSON POST, handle spam prevention and privacy appropriately, and be tested with an outside customer browser. Don't claim the quote request works automatically without doing that integration.

## CRITICAL: domain and email

`toppdawggaming.com`, `sales@toppdawggaming.com`, `quotes@toppdawggaming.com` and `support@toppdawggaming.com` are **proposed only**. Domain ownership, availability, email delivery, and search indexing are **not verified**. Configure them before publicly launching.

## Launch steps, email setup, SEO and shipping

**Read `LAUNCH_GUIDE.md`** for step-by-step email setup with Google Workspace and DNS, Cloudflare deployment, Google/Bing indexing, local-business eligibility, tax and shipping considerations, and a launch checklist.
