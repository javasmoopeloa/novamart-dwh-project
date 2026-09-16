-- NovaMart Data Warehouse
-- FULL RESET -- run this to wipe staging/core/mart_finance and start clean.
-- Safe to run any time: DROP ... CASCADE removes the schemas and everything
-- inside them, then recreates empty schemas + the 9 staging tables fresh.

DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS core CASCADE;
DROP SCHEMA IF EXISTS mart_finance CASCADE;

CREATE SCHEMA staging;
CREATE SCHEMA core;
CREATE SCHEMA mart_finance;

-- ============================================================
-- Staging tables -- raw Olist source files, every column as TEXT
-- ============================================================

CREATE TABLE staging.raw_orders (
    order_id                        TEXT,
    customer_id                     TEXT,
    order_status                    TEXT,
    order_purchase_timestamp        TEXT,
    order_approved_at               TEXT,
    order_delivered_carrier_date    TEXT,
    order_delivered_customer_date   TEXT,
    order_estimated_delivery_date   TEXT
);

CREATE TABLE staging.raw_order_items (
    order_id             TEXT,
    order_item_id        TEXT,
    product_id            TEXT,
    seller_id             TEXT,
    shipping_limit_date   TEXT,
    price                 TEXT,
    freight_value         TEXT
);

CREATE TABLE staging.raw_order_payments (
    order_id               TEXT,
    payment_sequential     TEXT,
    payment_type           TEXT,
    payment_installments   TEXT,
    payment_value          TEXT
);

CREATE TABLE staging.raw_order_reviews (
    review_id                TEXT,
    order_id                  TEXT,
    review_score               TEXT,
    review_comment_title       TEXT,
    review_comment_message     TEXT,
    review_creation_date       TEXT,
    review_answer_timestamp    TEXT
);

CREATE TABLE staging.raw_products (
    product_id                    TEXT,
    product_category_name         TEXT,
    product_name_lenght           TEXT,
    product_description_lenght    TEXT,
    product_photos_qty            TEXT,
    product_weight_g              TEXT,
    product_length_cm             TEXT,
    product_height_cm             TEXT,
    product_width_cm              TEXT
);

CREATE TABLE staging.raw_product_category_translation (
    product_category_name           TEXT,
    product_category_name_english   TEXT
);

CREATE TABLE staging.raw_sellers (
    seller_id                TEXT,
    seller_zip_code_prefix   TEXT,
    seller_city              TEXT,
    seller_state              TEXT
);

CREATE TABLE staging.raw_customers (
    customer_id                TEXT,
    customer_unique_id         TEXT,
    customer_zip_code_prefix   TEXT,
    customer_city              TEXT,
    customer_state              TEXT
);

CREATE TABLE staging.raw_geolocation (
    geolocation_zip_code_prefix   TEXT,
    geolocation_lat               TEXT,
    geolocation_lng               TEXT,
    geolocation_city              TEXT,
    geolocation_state              TEXT
);

-- Sanity check: confirm all 9 staging tables exist and are empty
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'staging'
ORDER BY table_name;
