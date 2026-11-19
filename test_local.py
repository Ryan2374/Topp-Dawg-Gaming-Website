import importlib.util
import sys
import unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('tdg_local',Path(__file__).with_name('local_server.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class LocalRetailTest(unittest.TestCase):
 def test_markup_bounds(self):
  self.assertEqual(m.selling_price(25),30)
  self.assertEqual(m.selling_price(50),60)
  self.assertEqual(m.selling_price(500),564.47)
  self.assertEqual(m.selling_price(1000),1050)
  self.assertEqual(m.selling_price(2000),2100)
  self.assertGreater(m.markup_pct(100),m.markup_pct(200))
 def test_json_ld_instock(self):
  html='''<html><head><script type="application/ld+json">{"@context":"https://schema.org","@type":"Product","name":"Exact Intel CPU Boxed","mpn":"BX000","offers":{"@type":"Offer","price":"285.99","priceCurrency":"USD","availability":"https://schema.org/InStock"}}</script></head></html>'''
  p=m.extract_product(html);self.assertEqual(p['price'],285.99);self.assertEqual(p['availability'],'in_stock');self.assertEqual(p['title'],'Exact Intel CPU Boxed')
 def test_json_ld_outofstock(self):
  html='''<script type="application/ld+json">{"@type":"Product","name":"Product","offers":{"price":"190.50","availability":"https://schema.org/OutOfStock"}}</script>'''
  self.assertEqual(m.extract_product(html)['availability'],'out_of_stock')
 def test_meta(self):
  html='''<html><head><title>RAM</title><meta property="product:price:amount" content="174.49"><meta property="product:availability" content="in_stock"></head></html>'''
  p=m.extract_product(html);self.assertEqual(p['price'],174.49);self.assertEqual(p['extraction'],'HTML metadata (product:price:amount)')
 def test_no_listing_price(self):
  self.assertIsNone(m.extract_product('<title>Sorry, access denied</title>'))
 def test_vendor_allowlist(self):
  self.assertEqual(m.source_for_url('https://www.microcenter.com/product/123/x'),'Micro Center')
  for url in ('http://www.newegg.com/x','https://127.0.0.1/a','https://evil.com','https://newegg.com.evil.com/a','file:///etc/passwd'):
   with self.subTest(url=url):
    with self.assertRaises(ValueError):m.source_for_url(url)
 def test_compare_stock_and_freshness(self):
  now=m.utcnow()
  offers=[{'price':500,'availability':'unknown','checked_at':now},{'price':520,'availability':'in_stock','checked_at':now},{'price':300,'availability':'out_of_stock','checked_at':now}]
  self.assertEqual(m.eligible(offers)['price'],520)
  self.assertIsNone(m.eligible([{'price':100,'availability':'in_stock','checked_at':'2000-01-01T00:00:00Z'}]))
 def test_unpriced_enabled_api(self):
  prices=m.price_api('desktop')['prices'];self.assertGreater(len(prices),20)
  self.assertEqual(next(x for x in prices if x['key']=='os.none')['retailPrice'],0)

if __name__=='__main__':unittest.main()
