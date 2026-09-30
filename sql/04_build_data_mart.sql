-- ======================================================================
-- NovaMart Data Warehouse
-- Deliverable: sql/04_build_data_mart.sql (Part 1 of 2 -- DDL)
-- Phase 6 -- Build the Data Mart (Ch. 2 §3, Ch. 3 §5)
--
-- mart_finance is a narrower, pre-joined/aggregated view of core,
-- scoped to a specific business need: "Finance wants revenue, cost,
-- and profit by product, store/channel, and month" (Ch. 2 §3.2 --
-- usability + performance argument for building a purpose-built mart
-- rather than pointing BI tools directly at the wider core schema).
-- ======================================================================
CREATE SCHEMA IF NOT EXISTS mart_finance;

-- ---------------------------------------------------------------
-- Dim_Month -- a coarser grain than core.dim_date, since this mart's
-- primary fact table (below) is deliberately pre-aggregated to the
-- month level. Surrogate key uses the natural YYYYMM integer, the
-- same Ch. 4 §7.4 pattern used for core.dim_date.
-- ---------------------------------------------------------------
CREATE TABLE mart_finance.dim_month (
    month_id    INT PRIMARY KEY,      -- YYYYMM, e.g. 201801
    month_name  VARCHAR(10),
    quarter     INT,
    year        INT
);

-- ---------------------------------------------------------------
-- Dim_Product (mart-scoped) -- a narrower copy of core.dim_product,
-- carrying only the attributes Finance actually queries on. Narrower
-- dimensions are part of what makes a mart faster and simpler to use
-- than querying core directly (Ch. 2 §3.2).
-- ---------------------------------------------------------------
CREATE TABLE mart_finance.dim_product (
    product_pk                     INT PRIMARY KEY,   -- reuses core.dim_product's surrogate key
    product_category_name_english  VARCHAR(100)
);

-- ---------------------------------------------------------------
-- Dim_Store (mart-scoped) -- narrower copy of core.dim_store.
-- ---------------------------------------------------------------
CREATE TABLE mart_finance.dim_store (
    store_pk    INT PRIMARY KEY,      -- reuses core.dim_store's surrogate key
    store_city  VARCHAR(100),
    store_state VARCHAR(10)
);

-- ---------------------------------------------------------------
-- Fact_Revenue_By_Month -- the mart's primary fact table.
-- Grain: one row per product + store + month combination.
-- This is a periodic-snapshot-style aggregation, pre-summarised from
-- the atomic-grain core.fact_sales, built specifically for fast
-- trend/reporting queries in the BI tool (Ch. 2 §3.2).
--
-- Ch. 4 §3 -- deliberately NO Year-to-Date or Month-to-Date column
-- stored here. YTD/MTD is calculated in the BI tool at query time
-- (Phase 7), since a stored running total would need to be
-- recalculated on every new load and breaks if historical data is
-- corrected -- storing it here would violate the additive-fact
-- principle this table otherwise relies on.
-- ---------------------------------------------------------------
CREATE TABLE mart_finance.fact_revenue_by_month (
    revenue_fact_pk SERIAL PRIMARY KEY,
    month_fk    INT NOT NULL REFERENCES mart_finance.dim_month(month_id),
    product_fk  INT NOT NULL REFERENCES mart_finance.dim_product(product_pk),
    store_fk    INT NOT NULL REFERENCES mart_finance.dim_store(store_pk),
    quantity    INT NOT NULL,                  -- additive
    revenue     NUMERIC(12,2) NOT NULL,        -- additive (sum of sales_amount)
    cost        NUMERIC(12,2) NOT NULL,        -- additive (sum of product_cost)
    profit      NUMERIC(12,2) NOT NULL         -- additive (sum of profit)
);

-- ======================================================================
-- Secondary fact table: Order_Fulfilment_Snapshot (Ch. 4 §4)
-- Type: ACCUMULATING SNAPSHOT -- chosen over a periodic snapshot
-- because Olist's order data provides a genuine multi-stage timeline
-- per order (purchase -> approved -> shipped -> delivered), which is
-- exactly the process an accumulating snapshot is designed to track.
-- A periodic snapshot (e.g. daily_channel_sales) was considered but
-- rejected -- our channel is a constant ('Website') for every row in
-- this dataset, so a channel-based snapshot would carry almost
-- no analytical value over fact_sales itself.
--
-- Grain: one row per order (not per order line) -- this fact table
-- tracks the order's fulfilment lifecycle, not its contents.
--
-- Role-playing Date dimension (Ch. 3 §4.4) -- the same core.dim_date
-- table is joined four times under four different aliases/roles, one
-- for each milestone in the order's journey.
-- ======================================================================
CREATE TABLE mart_finance.order_fulfilment_snapshot (
    fulfilment_fact_pk SERIAL PRIMARY KEY,
    order_id            VARCHAR(50) NOT NULL,   -- degenerate dimension, kept for traceability
    customer_fk         INT NOT NULL,           -- references core.dim_customer(customer_pk)
    order_date_fk       INT NOT NULL,           -- role-playing core.dim_date: when the order was placed
    approved_date_fk    INT NOT NULL,           -- role-playing core.dim_date: when payment was approved
    shipped_date_fk      INT NOT NULL,          -- role-playing core.dim_date: when handed to carrier
    delivered_date_fk    INT NOT NULL,          -- role-playing core.dim_date: when customer received it
    order_status          VARCHAR(30),
    days_to_approve       INT,   -- non-additive; recomputed on demand from the date FKs,
                                  -- kept here for convenience
    days_to_ship           INT,  -- non-additive
    days_to_deliver          INT -- non-additive
);


-- ======================================================================
-- sql/04_build_data_mart.sql (continued)
-- Phase 6 deliverable -- Part 2: ETL (populate mart_finance from core).
--
-- Populates mart_finance from core. Run Part 1 (DDL) once first, then
-- this part. Safe to re-run: truncates before reloading.
-- ======================================================================

TRUNCATE TABLE mart_finance.fact_revenue_by_month, mart_finance.order_fulfilment_snapshot,
              mart_finance.dim_month, mart_finance.dim_product, mart_finance.dim_store
CASCADE;

-- ---------------------------------------------------------------
-- Dim_Month -- one row per calendar month covered by core.dim_date
-- ---------------------------------------------------------------
INSERT INTO mart_finance.dim_month (month_id, month_name, quarter, year)
SELECT DISTINCT
    (year * 100) + month AS month_id,
    TRIM(month_name),
    quarter,
    year
FROM core.dim_date
WHERE date_id <> 19000101;   -- exclude the dummy "N/A" date row

-- ---------------------------------------------------------------
-- Dim_Product (mart-scoped) -- narrowed copy of core.dim_product
-- ---------------------------------------------------------------
INSERT INTO mart_finance.dim_product (product_pk, product_category_name_english)
SELECT product_pk, product_category_name_english
FROM core.dim_product;

-- ---------------------------------------------------------------
-- Dim_Store (mart-scoped) -- narrowed copy of core.dim_store
-- ---------------------------------------------------------------
INSERT INTO mart_finance.dim_store (store_pk, store_city, store_state)
SELECT store_pk, store_city, store_state
FROM core.dim_store;

-- ---------------------------------------------------------------
-- Fact_Revenue_By_Month -- aggregated from core.fact_sales
-- Rolls the atomic order-line grain up to product + store + month,
-- summing the additive measures (Ch. 4 §1). This is the
-- "usability + performance" trade-off from Ch. 2 §3.2: the BI tool
-- queries far fewer, pre-summed rows instead of scanning 112k+
-- transactional rows for every dashboard refresh.
-- ---------------------------------------------------------------
INSERT INTO mart_finance.fact_revenue_by_month (month_fk, product_fk, store_fk, quantity,
revenue, cost, profit)
SELECT
    (dd.year * 100) + dd.month AS month_fk,
    f.product_fk,
    f.store_fk,
    SUM(f.quantity)       AS quantity,
    SUM(f.sales_amount)   AS revenue,
    SUM(f.product_cost)   AS cost,
    SUM(f.profit)         AS profit
FROM core.fact_sales f
JOIN core.dim_date dd ON f.date_fk = dd.date_id
WHERE f.date_fk <> 19000101    -- exclude fact rows with no resolvable date
GROUP BY (dd.year * 100) + dd.month, f.product_fk, f.store_fk;

-- ---------------------------------------------------------------
-- Order_Fulfilment_Snapshot -- accumulating snapshot, one row per order
-- Ch. 3 §4.4 role-playing Date dimension: core.dim_date is joined four
-- separate times, once per fulfilment milestone.
--
-- Same staging fixes as Phase 5: source timestamp columns are TEXT
-- with legitimate blanks for orders not yet at a given stage (e.g. an
-- order with no delivered_customer_date simply hasn't been delivered
-- yet) -- NULLIF(...,'') converts the blank to a true NULL, and
-- COALESCE(...,19000101) substitutes the Dim_Date dummy key so the
-- FK is never left NULL, consistent with our Ch. 4 §2.4 strategy.
--
-- days_to_* are calculated once at load time for BI convenience, but
-- are flagged non-additive -- they should not be summed across
-- orders, only averaged or recalculated on demand.
-- ---------------------------------------------------------------
INSERT INTO mart_finance.order_fulfilment_snapshot (
    order_id, customer_fk, order_date_fk, approved_date_fk, shipped_date_fk,
    delivered_date_fk, order_status, days_to_approve, days_to_ship, days_to_deliver
)
SELECT
    o.order_id,
    COALESCE(dc.customer_pk, -1),
    COALESCE(TO_CHAR(NULLIF(o.order_purchase_timestamp, '')::date, 'YYYYMMDD')::INT, 19000101),
    COALESCE(TO_CHAR(NULLIF(o.order_approved_at, '')::date, 'YYYYMMDD')::INT, 19000101),
    COALESCE(TO_CHAR(NULLIF(o.order_delivered_carrier_date, '')::date, 'YYYYMMDD')::INT, 19000101),
    COALESCE(TO_CHAR(NULLIF(o.order_delivered_customer_date, '')::date, 'YYYYMMDD')::INT, 19000101),
    o.order_status,
    (NULLIF(o.order_approved_at, '')::date - NULLIF(o.order_purchase_timestamp, '')::date),
    (NULLIF(o.order_delivered_carrier_date, '')::date - NULLIF(o.order_approved_at, '')::date),
    (NULLIF(o.order_delivered_customer_date, '')::date - NULLIF(o.order_delivered_carrier_date, '')::date)
FROM staging.raw_orders o
LEFT JOIN core.dim_customer dc ON o.customer_id = dc.customer_id;

-- ======================================================================
-- VALIDATION
-- ======================================================================
SELECT 'dim_month' AS tbl, COUNT(*) FROM mart_finance.dim_month
UNION ALL SELECT 'dim_product', COUNT(*) FROM mart_finance.dim_product
UNION ALL SELECT 'dim_store', COUNT(*) FROM mart_finance.dim_store
UNION ALL SELECT 'fact_revenue_by_month', COUNT(*) FROM mart_finance.fact_revenue_by_month
UNION ALL SELECT 'order_fulfilment_snapshot', COUNT(*) FROM mart_finance.order_fulfilment_snapshot;

-- Sanity check: total revenue in the mart should equal total sales_amount in core
SELECT SUM(revenue) AS mart_total_revenue FROM mart_finance.fact_revenue_by_month;
SELECT SUM(sales_amount) AS core_total_sales FROM core.fact_sales WHERE date_fk <> 19000101;

-- Confirmed: mart_total_revenue (13,591,643.7) matched core_total_sales
-- exactly -- no revenue was lost or duplicated in the monthly rollup.
-- See docs/Phase5_Evidence.pdf, Meeting 4 minutes, for the recorded check.
