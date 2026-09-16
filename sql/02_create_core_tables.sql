-- NovaMart Data Warehouse
-- Phase 4: Design the Dimensional Model (Ch. 3, Ch. 4)
-- Creates the star schema in the core schema: Dim_Date, Dim_Customer,
-- Dim_Product, Dim_Store, and Fact_Sales at grain = one row per order line.

-- ============================================================
-- Dim_Date -- exception to the surrogate-key rule (Ch. 4 §7.4):
-- date_id itself (YYYYMMDD) is the primary key, not a generated sequence.
-- ============================================================
CREATE TABLE IF NOT EXISTS core.dim_date (
    date_id         INT PRIMARY KEY,        -- e.g. 20260915
    full_date        DATE NOT NULL,
    day              INT NOT NULL,
    day_name         VARCHAR(10) NOT NULL,
    weekday_flag     BOOLEAN NOT NULL,       -- true = Mon-Fri
    month            INT NOT NULL,
    month_name       VARCHAR(10) NOT NULL,
    quarter          INT NOT NULL,
    year             INT NOT NULL,
    is_holiday_flag  BOOLEAN NOT NULL DEFAULT FALSE
);

-- ============================================================
-- Dim_Customer
-- ============================================================
CREATE TABLE IF NOT EXISTS core.dim_customer (
    customer_pk               SERIAL PRIMARY KEY,
    customer_id                VARCHAR(64) NOT NULL,   -- natural key (reference only)
    customer_unique_id         VARCHAR(64),
    customer_city               VARCHAR(100),
    customer_state               VARCHAR(10),
    customer_zip_code_prefix      VARCHAR(10)
);

-- ============================================================
-- Dim_Product
-- ============================================================
CREATE TABLE IF NOT EXISTS core.dim_product (
    product_pk                   SERIAL PRIMARY KEY,
    product_id                    VARCHAR(64) NOT NULL,   -- natural key (reference only)
    product_category_name          VARCHAR(100),
    product_category_name_english   VARCHAR(100),
    product_weight_g                 NUMERIC,
    product_length_cm                NUMERIC,
    product_height_cm                NUMERIC,
    product_width_cm                  NUMERIC
);

-- ============================================================
-- Dim_Store -- Olist "sellers" re-themed as NovaMart pop-up stores
-- ============================================================
CREATE TABLE IF NOT EXISTS core.dim_store (
    store_pk                 SERIAL PRIMARY KEY,
    seller_id                 VARCHAR(64) NOT NULL,   -- natural key (reference only)
    store_city                 VARCHAR(100),
    store_state                  VARCHAR(10),
    store_zip_code_prefix          VARCHAR(10)
);

-- ============================================================
-- Fact_Sales -- grain: one row per order line (order_item)
-- ============================================================
CREATE TABLE IF NOT EXISTS core.fact_sales (
    sales_fact_pk        SERIAL PRIMARY KEY,
    order_id               VARCHAR(64) NOT NULL,   -- degenerate dimension: no Dim_Order table, kept for traceability
    order_item_id           INT NOT NULL,
    date_fk                   INT NOT NULL REFERENCES core.dim_date(date_id),
    customer_fk                 INT NOT NULL REFERENCES core.dim_customer(customer_pk),
    product_fk                    INT NOT NULL REFERENCES core.dim_product(product_pk),
    store_fk                        INT NOT NULL REFERENCES core.dim_store(store_pk),
    channel                           VARCHAR(20) NOT NULL DEFAULT 'Website',  -- degenerate: constant in this dataset
    order_status                       VARCHAR(30),                             -- degenerate dimension
    quantity                             INT NOT NULL DEFAULT 1,                -- additive
    price                                  NUMERIC(10,2) NOT NULL,              -- additive
    freight_value                           NUMERIC(10,2) NOT NULL DEFAULT 0,   -- additive
    sales_amount                              NUMERIC(10,2) NOT NULL,           -- additive (= price here, qty always 1)
    product_cost                                NUMERIC(10,2) NOT NULL,         -- additive; ESTIMATED as 0.65 * price, not sourced
    profit                                        NUMERIC(10,2) NOT NULL        -- additive (sales_amount - product_cost)
);

-- ============================================================
-- Dummy rows for unmatched foreign keys (Ch. 4 §2.4)
-- ============================================================
INSERT INTO core.dim_date (date_id, full_date, day, day_name, weekday_flag, month, month_name, quarter, year, is_holiday_flag)
VALUES (19000101, '1900-01-01', 1, 'Unknown', FALSE, 1, 'Unknown', 1, 1900, FALSE)
ON CONFLICT (date_id) DO NOTHING;

INSERT INTO core.dim_customer (customer_pk, customer_id, customer_unique_id, customer_city, customer_state, customer_zip_code_prefix)
OVERRIDING SYSTEM VALUE
VALUES (-1, 'UNKNOWN', 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown')
ON CONFLICT (customer_pk) DO NOTHING;

INSERT INTO core.dim_product (product_pk, product_id, product_category_name, product_category_name_english)
OVERRIDING SYSTEM VALUE
VALUES (-1, 'UNKNOWN', 'Unknown', 'Unknown')
ON CONFLICT (product_pk) DO NOTHING;

INSERT INTO core.dim_store (store_pk, seller_id, store_city, store_state)
OVERRIDING SYSTEM VALUE
VALUES (-1, 'UNKNOWN', 'Unknown', 'Unknown')
ON CONFLICT (store_pk) DO NOTHING;

-- ============================================================
-- Sanity check: confirm all 5 core tables exist
-- ============================================================
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'core'
ORDER BY table_name;
