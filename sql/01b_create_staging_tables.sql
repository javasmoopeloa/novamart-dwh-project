-- NovaMart Data Warehouse
-- Phase 2: Cloud Architecture Setup (continued)
-- Creates staging tables for the raw Olist source files (Ch. 2 §2.1: load "as-is",
-- minimal touching -- every column is TEXT so messy/inconsistent raw values load
-- without failing on type conversion. Cleansing/typing happens in Phase 5.
--
-- Source system mapping (folders in S3 bucket novamart-raw-data-jabu):
--   website/  -> orders, order_items, order_payments, products,
--                product_category_name_translation
--   pos/      -> sellers (re-themed as NovaMart pop-up stores), geolocation
--   crm/      -> customers, order_reviews

-- ============================================================
-- website/ -- orders (core sales fact source)
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_orders (
    order_id                        TEXT,
    customer_id                     TEXT,
    order_status                    TEXT,
    order_purchase_timestamp        TEXT,
    order_approved_at               TEXT,
    order_delivered_carrier_date    TEXT,
    order_delivered_customer_date   TEXT,
    order_estimated_delivery_date   TEXT
);

-- ============================================================
-- website/ -- order_items (grain source for the Sales fact: one row per order line)
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_order_items (
    order_id            TEXT,
    order_item_id        TEXT,
    product_id           TEXT,
    seller_id            TEXT,
    shipping_limit_date  TEXT,
    price                TEXT,
    freight_value        TEXT
);

-- ============================================================
-- website/ -- order_payments
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_order_payments (
    order_id              TEXT,
    payment_sequential    TEXT,
    payment_type          TEXT,
    payment_installments  TEXT,
    payment_value         TEXT
);

-- ============================================================
-- crm/ -- order_reviews (optional / stretch use)
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_order_reviews (
    review_id               TEXT,
    order_id                TEXT,
    review_score             TEXT,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TEXT,
    review_answer_timestamp  TEXT
);

-- ============================================================
-- website/ -- products
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_products (
    product_id                   TEXT,
    product_category_name        TEXT,
    product_name_lenght          TEXT,
    product_description_lenght   TEXT,
    product_photos_qty           TEXT,
    product_weight_g             TEXT,
    product_length_cm            TEXT,
    product_height_cm            TEXT,
    product_width_cm             TEXT
);

-- ============================================================
-- website/ -- product_category_name_translation (EN category names)
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_product_category_translation (
    product_category_name          TEXT,
    product_category_name_english  TEXT
);

-- ============================================================
-- pos/ -- sellers (re-themed: NovaMart pop-up stores, 3 city regions)
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_sellers (
    seller_id               TEXT,
    seller_zip_code_prefix  TEXT,
    seller_city             TEXT,
    seller_state             TEXT
);

-- ============================================================
-- crm/ -- customers
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_customers (
    customer_id               TEXT,
    customer_unique_id        TEXT,
    customer_zip_code_prefix  TEXT,
    customer_city             TEXT,
    customer_state             TEXT
);

-- ============================================================
-- pos/ -- geolocation (zip-code lookup, used for both customers and stores)
-- ============================================================
CREATE TABLE IF NOT EXISTS staging.raw_geolocation (
    geolocation_zip_code_prefix  TEXT,
    geolocation_lat              TEXT,
    geolocation_lng              TEXT,
    geolocation_city             TEXT,
    geolocation_state             TEXT
);

-- ============================================================
-- Sanity check: confirm all 9 staging tables exist
-- ============================================================
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'staging'
ORDER BY table_name;
