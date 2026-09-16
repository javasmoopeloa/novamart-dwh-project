-- NovaMart Data Warehouse
-- Phase 3: Investigate & Document Data Quality Issues (Ch. 1 §11, Ch. 4 §2)
-- FINAL VERSION -- includes empty-string checks discovered during profiling.
-- Run each query individually (Ctrl+Enter), not as a full script, so you can
-- read each result before moving to the next.

-- ============================================================
-- SECTION 1: ROW COUNTS & DUPLICATES
-- ============================================================

-- 1a. Duplicate order_ids in raw_orders  [CONFIRMED CLEAN: no duplicates]
SELECT order_id, COUNT(*) AS n
FROM staging.raw_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- 1b. Duplicate reviews per order (skip -- raw_order_reviews load deferred)
-- 1c. Exact full-row duplicates in raw_order_reviews (skip -- same reason)

-- 1d. Duplicate customer_id in raw_customers  [CONFIRMED CLEAN: no duplicates]
SELECT customer_id, COUNT(*) AS n
FROM staging.raw_customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- 1e. Duplicate product_id in raw_products  [CONFIRMED CLEAN: no duplicates]
SELECT product_id, COUNT(*) AS n
FROM staging.raw_products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- ============================================================
-- SECTION 2: NULLS PER COLUMN (true SQL NULL only)
-- ============================================================

-- 2a. raw_orders  [CONFIRMED: 0 true NULLs anywhere -- see Section 2X for why]
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_id,
    COUNT(*) FILTER (WHERE order_status IS NULL) AS null_status,
    COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL) AS null_purchase_ts,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL) AS null_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL) AS null_carrier_date,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS null_delivered_date,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL) AS null_estimated_date
FROM staging.raw_orders;

-- 2b. raw_order_items -- NULLs in price/freight
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS null_product_id,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS null_seller_id,
    COUNT(*) FILTER (WHERE price IS NULL) AS null_price,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS null_freight
FROM staging.raw_order_items;

-- 2d. raw_products -- category name and physical dimensions
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS null_category,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS null_weight,
    COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS null_length,
    COUNT(*) FILTER (WHERE product_height_cm IS NULL) AS null_height,
    COUNT(*) FILTER (WHERE product_width_cm IS NULL) AS null_width
FROM staging.raw_products;

-- 2e. raw_customers -- geography fields
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE customer_city IS NULL) AS null_city,
    COUNT(*) FILTER (WHERE customer_state IS NULL) AS null_state,
    COUNT(*) FILTER (WHERE customer_zip_code_prefix IS NULL) AS null_zip
FROM staging.raw_customers;

-- ============================================================
-- SECTION 2X: EMPTY STRINGS masquerading as "no NULLs"
-- [CONFIRMED ISSUE: 2,965 empty strings in order_delivered_customer_date
--  where IS NULL check showed 0 -- this is why Section 2 looked "too clean"]
-- ============================================================

-- 2x-1. Confirm empty-string counts across all 3 "may not have happened yet"
--       date columns in raw_orders
SELECT
    COUNT(*) FILTER (WHERE order_approved_at = '') AS empty_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date = '') AS empty_carrier_date,
    COUNT(*) FILTER (WHERE order_delivered_customer_date = '') AS empty_delivered_date
FROM staging.raw_orders;

-- 2x-2. Same check on order_items price/freight (these matter more --
--       feed the Sales fact directly as measures)
SELECT
    COUNT(*) FILTER (WHERE price = '') AS empty_price,
    COUNT(*) FILTER (WHERE freight_value = '') AS empty_freight
FROM staging.raw_order_items;

-- 2x-3. Same check on product physical dimensions
SELECT
    COUNT(*) FILTER (WHERE product_category_name = '') AS empty_category,
    COUNT(*) FILTER (WHERE product_weight_g = '') AS empty_weight
FROM staging.raw_products;

-- ============================================================
-- SECTION 3: ORPHANED FOREIGN KEYS (Ch. 4 §2.4)
-- ============================================================

-- 3a. order_items pointing to a product_id that doesn't exist in raw_products
SELECT oi.product_id, COUNT(*) AS n
FROM staging.raw_order_items oi
LEFT JOIN staging.raw_products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL
GROUP BY oi.product_id;

-- 3b. order_items pointing to a seller_id that doesn't exist in raw_sellers
SELECT oi.seller_id, COUNT(*) AS n
FROM staging.raw_order_items oi
LEFT JOIN staging.raw_sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL
GROUP BY oi.seller_id;

-- 3c. orders pointing to a customer_id that doesn't exist in raw_customers
SELECT o.customer_id, COUNT(*) AS n
FROM staging.raw_orders o
LEFT JOIN staging.raw_customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
GROUP BY o.customer_id;

-- 3d. products pointing to a category not in the translation table
SELECT p.product_category_name, COUNT(*) AS n
FROM staging.raw_products p
LEFT JOIN staging.raw_product_category_translation t
       ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL
GROUP BY p.product_category_name;

-- ============================================================
-- SECTION 4: FORMAT / CONSISTENCY ISSUES
-- ============================================================

-- 4a. Inconsistent casing in city names
SELECT customer_city, COUNT(*) AS n
FROM staging.raw_customers
GROUP BY customer_city
HAVING customer_city <> INITCAP(customer_city)
   AND customer_city <> UPPER(customer_city)
ORDER BY n DESC
LIMIT 20;

-- 4b. Leading/trailing whitespace on city values
SELECT customer_city, COUNT(*) AS n
FROM staging.raw_customers
WHERE customer_city <> TRIM(customer_city)
GROUP BY customer_city;

-- 4d. Values in price that don't look like plain numbers
SELECT price
FROM staging.raw_order_items
WHERE price !~ '^\d+(\.\d+)?$' AND price <> ''
LIMIT 20;

-- 4e. order_status values -- every distinct status that exists
SELECT order_status, COUNT(*) AS n
FROM staging.raw_orders
GROUP BY order_status
ORDER BY n DESC;

-- 4f. Timestamp format sanity check
SELECT order_purchase_timestamp
FROM staging.raw_orders
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp <> ''
  AND order_purchase_timestamp !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
LIMIT 20;
