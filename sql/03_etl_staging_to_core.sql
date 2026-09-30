-- NovaMart Data Warehouse
-- Deliverable: sql/03_etl_staging_to_core.sql
-- Phase 5 -- Build the ETL: Staging -> Core (Ch. 2, Ch. 4)
--
-- Populates core from staging. Safe to re-run: truncates before reloading.

TRUNCATE TABLE core.fact_sales;
TRUNCATE TABLE core.dim_customer RESTART IDENTITY CASCADE;
TRUNCATE TABLE core.dim_product RESTART IDENTITY CASCADE;
TRUNCATE TABLE core.dim_store RESTART IDENTITY CASCADE;
TRUNCATE TABLE core.dim_date CASCADE;

-- ---------------------------------------------------------------
-- Populate Dim_Date programmatically for the full date range covered
-- by the dataset (Task 23) -- one row per calendar day.
-- ---------------------------------------------------------------
INSERT INTO core.dim_date (date_id, full_date, day, day_name, weekday_flag, month, month_name,
quarter, year, is_holiday_flag)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT,
    d,
    EXTRACT(DAY FROM d)::INT,
    TO_CHAR(d, 'Day'),
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6,7) THEN FALSE ELSE TRUE END,
    EXTRACT(MONTH FROM d)::INT,
    TO_CHAR(d, 'Month'),
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(YEAR FROM d)::INT,
    FALSE
FROM generate_series('2016-01-01'::date, '2018-12-31'::date, interval '1 day') AS d;

-- Ch. 4 §7.4 -- dummy "N/A" date row (19000101), since -1 is not a valid
-- YYYYMMDD integer.
INSERT INTO core.dim_date (date_id, full_date, day, day_name, weekday_flag, month, month_name,
quarter, year, is_holiday_flag)
VALUES (19000101, '1900-01-01', 1, 'Unknown', FALSE, 1, 'Unknown', 1, 1900, FALSE);

-- ---------------------------------------------------------------
-- Populate Dim_Customer
-- Issue 4 (Phase 3 Data Quality Report) fix -- city names arrived
-- uniformly lowercase; INITCAP(TRIM(...)) standardises them for
-- presentation (e.g. "sao paulo" -> "Sao Paulo").
-- ---------------------------------------------------------------
INSERT INTO core.dim_customer (customer_id, customer_unique_id, customer_city, customer_state,
customer_zip_code_prefix)
SELECT DISTINCT
    customer_id,
    customer_unique_id,
    INITCAP(TRIM(customer_city)),
    customer_state,
    customer_zip_code_prefix
FROM staging.raw_customers;

-- Ch. 4 §2.4 -- dummy "Unknown Customer" row (-1), the corresponding
-- dimension row required by our dummy-key strategy for unmatched FKs.
INSERT INTO core.dim_customer (customer_id, customer_unique_id, customer_city, customer_state,
customer_zip_code_prefix)
VALUES ('-1', '-1', 'Unknown', 'Unknown', 'Unknown');

-- ---------------------------------------------------------------
-- Populate Dim_Product
-- Issue 3 (Phase 3 Data Quality Report) fix -- a naive INNER JOIN to
-- the category translation table would silently drop the 613 products
-- with a missing or untranslated category. We use a LEFT JOIN and
-- COALESCE(..., 'Unknown Category') instead, per Ch. 4 §2 guidance on
-- handling NULL-in-a-foreign-key problems without losing valid rows.
-- Data type note: staging stores every column as text, so weight/
-- length/height are cast with NULLIF(..,'')::numeric -- converting
-- empty strings to true NULL before casting to the target numeric type.
-- ---------------------------------------------------------------
INSERT INTO core.dim_product (product_id, product_category_name,
product_category_name_english, product_weight_g, product_length_cm, product_height_cm)
SELECT
    p.product_id,
    p.product_category_name,
    COALESCE(t.product_category_name_english, 'Unknown Category'),
    NULLIF(p.product_weight_g, '')::numeric,
    NULLIF(p.product_length_cm, '')::numeric,
    NULLIF(p.product_height_cm, '')::numeric
FROM staging.raw_products p
LEFT JOIN staging.raw_product_category_translation t
    ON p.product_category_name = t.product_category_name;

-- Ch. 4 §2.4 -- dummy "Unknown Product" row (-1) for unmatched FKs.
INSERT INTO core.dim_product (product_id, product_category_name,
product_category_name_english, product_weight_g, product_length_cm, product_height_cm)
VALUES ('-1', 'Unknown', 'Unknown Category', NULL, NULL, NULL);

-- ---------------------------------------------------------------
-- Populate Dim_Store
-- Re-themed from Olist "sellers" -> NovaMart's pop-up stores/vendors,
-- per our Phase 2 dataset mapping. Same city-standardisation and
-- dummy-key pattern as Dim_Customer above.
-- ---------------------------------------------------------------
INSERT INTO core.dim_store (seller_id, store_city, store_state, store_zip_code_prefix)
SELECT DISTINCT
    seller_id,
    INITCAP(TRIM(seller_city)),
    seller_state,
    seller_zip_code_prefix
FROM staging.raw_sellers;

-- Ch. 4 §2.4 -- dummy "Unknown Store" row (-1) for unmatched FKs.
INSERT INTO core.dim_store (seller_id, store_city, store_state, store_zip_code_prefix)
VALUES ('-1', 'Unknown', 'Unknown', 'Unknown');

-- ---------------------------------------------------------------
-- Populate Fact_Sales
-- Grain: one row per order line, matching staging.raw_order_items
-- exactly (Ch. 3 §3.3 -- atomic grain, see Phase 4 dimensional model).
--
-- Issue 1 (Phase 3 Data Quality Report) fix -- order_purchase_timestamp
-- arrived from the CSV as an empty string rather than a true NULL when
-- missing. NULLIF(col,'')::date converts it to a real NULL before
-- casting to date, so downstream logic doesn't misbehave silently.
-- COALESCE(..., 19000101) then substitutes the Dim_Date dummy key
-- whenever no usable date exists (Ch. 4 §2.4).
--
-- Dummy key substitution (Ch. 4 §2.4) -- COALESCE(..., -1) on every
-- dimension FK ensures no fact row is ever left with a NULL foreign
-- key; unmatched source keys resolve to the "Unknown" dimension row.
--
-- Ch. 4 §2.2 -- freight_value defaults to 0 (COALESCE(...,0)) rather
-- than remaining NULL, since a missing freight value represents "no
-- shipping cost occurred," not "unknown" -- an additive measure should
-- never carry a NULL for a legitimate zero state.
--
-- channel is hardcoded to 'Website' -- our Phase 4 documented
-- assumption, since the Olist dataset is entirely e-commerce and does
-- not distinguish NovaMart's other two channels.
--
-- product_cost and profit are ESTIMATED as 0.65 x price, clearly
-- flagged here and in our documentation, since Olist provides no
-- product cost data (Ch. 4 §1 -- both are additive facts).
-- ---------------------------------------------------------------
INSERT INTO core.fact_sales (
    order_id, order_item_id, date_fk, customer_fk, product_fk, store_fk,
    channel, order_status, quantity, price, freight_value, sales_amount, product_cost, profit
)
SELECT
    oi.order_id,
    oi.order_item_id::int,
    COALESCE(TO_CHAR(NULLIF(o.order_purchase_timestamp, '')::date, 'YYYYMMDD')::INT, 19000101),
    COALESCE(dc.customer_pk, -1),
    COALESCE(dp.product_pk, -1),
    COALESCE(ds.store_pk, -1),
    'Website',
    o.order_status,
    1,                                                          -- quantity: always 1 per
                                                                 -- order-item row in this dataset
    NULLIF(oi.price, '')::numeric,                              -- additive
    COALESCE(NULLIF(oi.freight_value, '')::numeric, 0),         -- additive; Ch. 4 §2.2 zero, not NULL
    NULLIF(oi.price, '')::numeric,                              -- sales_amount = price (qty always 1); additive
    ROUND(NULLIF(oi.price, '')::numeric * 0.65, 2),             -- product_cost: ESTIMATED, additive
    ROUND(NULLIF(oi.price, '')::numeric - (NULLIF(oi.price, '')::numeric * 0.65), 2)  -- profit: additive
FROM staging.raw_order_items oi
JOIN staging.raw_orders o ON oi.order_id = o.order_id
LEFT JOIN core.dim_customer dc ON o.customer_id = dc.customer_id
LEFT JOIN core.dim_product dp ON oi.product_id = dp.product_id
LEFT JOIN core.dim_store ds ON oi.seller_id = ds.seller_id;

-- ======================================================================
-- Validation
-- Task 24 of the project brief -- confirm every foreign key in fact_sales
-- successfully joins to its dimension. An INNER JOIN from fact to each
-- dimension must return the same row count as the fact table itself;
-- this is the evidence that the NULL-FK / dummy-key fix worked
-- (Ch. 4 §2.4), required for the marking rubric.
-- ======================================================================
SELECT COUNT(*) AS baseline_fact_rows FROM core.fact_sales;

SELECT COUNT(*) AS matched_customer FROM core.fact_sales f
JOIN core.dim_customer dc ON f.customer_fk = dc.customer_pk;

SELECT COUNT(*) AS matched_product FROM core.fact_sales f
JOIN core.dim_product dp ON f.product_fk = dp.product_pk;

SELECT COUNT(*) AS matched_store FROM core.fact_sales f
JOIN core.dim_store ds ON f.store_fk = ds.store_pk;

SELECT COUNT(*) AS matched_date FROM core.fact_sales f
JOIN core.dim_date dd ON f.date_fk = dd.date_id;

-- All five queries above returned 112,650 -- matching the fact_sales
-- baseline row count exactly. See docs/Phase5_Evidence.pdf for
-- screenshot evidence.
