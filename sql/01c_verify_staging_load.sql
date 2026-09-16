-- NovaMart Data Warehouse
-- Phase 2: Cloud Architecture Setup (continued)
-- Run this AFTER loading all 9 CSVs via DBeaver's Import Wizard, to confirm
-- every staging table actually received rows. Zero rows anywhere = that
-- import didn't run/failed -- go back and re-import that one table.

SELECT 'raw_orders' AS table_name, COUNT(*) AS row_count FROM staging.raw_orders
UNION ALL
SELECT 'raw_order_items', COUNT(*) FROM staging.raw_order_items
UNION ALL
SELECT 'raw_order_payments', COUNT(*) FROM staging.raw_order_payments
UNION ALL
SELECT 'raw_order_reviews', COUNT(*) FROM staging.raw_order_reviews
UNION ALL
SELECT 'raw_products', COUNT(*) FROM staging.raw_products
UNION ALL
SELECT 'raw_product_category_translation', COUNT(*) FROM staging.raw_product_category_translation
UNION ALL
SELECT 'raw_sellers', COUNT(*) FROM staging.raw_sellers
UNION ALL
SELECT 'raw_customers', COUNT(*) FROM staging.raw_customers
UNION ALL
SELECT 'raw_geolocation', COUNT(*) FROM staging.raw_geolocation
ORDER BY table_name;

-- Quick peek at raw messiness (evidence for Phase 3's Data Quality Report) --
-- e.g. uncomment to eyeball a few raw rows before anything gets cleaned:
-- SELECT * FROM staging.raw_orders LIMIT 20;
