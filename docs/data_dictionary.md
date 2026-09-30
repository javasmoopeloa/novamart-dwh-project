# NovaMart Data Warehouse — Data Dictionary

Covers every table across all three schemas: `staging`, `core`, and `mart_finance`.

---

## Schema: `staging`

Raw, minimally-touched data loaded directly from the Olist source CSVs, kept as text wherever the source was ambiguous. Persistent (not truncated between loads) — see `docs/02_architecture_diagram.png` note and Phase 1/2 documentation for the audit/recoverability justification.

| Table | Column | Data Type | Notes |
|---|---|---|---|
| `staging.raw_orders` | order_id | TEXT | Natural key |
| | customer_id | TEXT | FK to raw_customers |
| | order_status | TEXT | |
| | order_purchase_timestamp | TEXT | Arrives as text; empty string if missing |
| | order_approved_at | TEXT | Empty string (not NULL) when not yet approved |
| | order_delivered_carrier_date | TEXT | Empty string when not yet shipped |
| | order_delivered_customer_date | TEXT | Empty string when not yet delivered (2,965 rows) |
| `staging.raw_order_items` | order_id | TEXT | FK to raw_orders |
| | order_item_id | TEXT | Line number within the order |
| | product_id | TEXT | FK to raw_products |
| | seller_id | TEXT | FK to raw_sellers |
| | price | TEXT | Line-item price; verified clean (0 NULLs/blanks) |
| | freight_value | TEXT | Shipping cost; verified clean |
| `staging.raw_customers` | customer_id | TEXT | Natural key |
| | customer_unique_id | TEXT | |
| | customer_city | TEXT | Raw lowercase, e.g. "sao paulo" |
| | customer_state | TEXT | |
| | customer_zip_code_prefix | TEXT | |
| `staging.raw_products` | product_id | TEXT | Natural key |
| | product_category_name | TEXT | 610 rows blank; 13 rows use a category missing from the translation table |
| | product_weight_g | TEXT | Cast with NULLIF before use |
| | product_length_cm | TEXT | Cast with NULLIF before use |
| | product_height_cm | TEXT | Cast with NULLIF before use |
| `staging.raw_sellers` | seller_id | TEXT | Natural key; re-themed as NovaMart pop-up stores |
| | seller_city | TEXT | Raw lowercase |
| | seller_state | TEXT | |
| | seller_zip_code_prefix | TEXT | |
| `staging.raw_product_category_translation` | product_category_name | TEXT | Portuguese source key |
| | product_category_name_english | TEXT | 71 rows |
| `staging.raw_order_reviews` | (deferred) | — | Multi-line CSV import bug found and fixed (Phase 3, Issue 5); full reload deferred as not required for the Sales fact |

---

## Schema: `core`

The integrated, cleaned single source of truth. Star schema, one row per order line in the fact table.

### `core.dim_date`
Role-playing date dimension. The one dimension where the natural key (YYYYMMDD integer) is used as the surrogate key directly, per Ch. 4 §7.4.

| Column | Data Type | Notes |
|---|---|---|
| date_id | INT (PK) | YYYYMMDD, e.g. 20180115 |
| full_date | DATE | |
| day | INT | |
| day_name | TEXT | |
| weekday_flag | BOOLEAN | |
| month | INT | |
| month_name | TEXT | |
| quarter | INT | |
| year | INT | |
| is_holiday_flag | BOOLEAN | |

Dummy row: `date_id = 19000101`, "Unknown" — used when a source timestamp is missing/blank.

### `core.dim_customer`
| Column | Data Type | Notes |
|---|---|---|
| customer_pk | SERIAL (PK) | Surrogate key |
| customer_id | TEXT | Natural key, reference only |
| customer_unique_id | TEXT | |
| customer_city | TEXT | Standardised with `INITCAP(TRIM(...))` |
| customer_state | TEXT | |
| customer_zip_code_prefix | TEXT | |

Dummy row: `customer_pk = -1`, "Unknown Customer".

### `core.dim_product`
| Column | Data Type | Notes |
|---|---|---|
| product_pk | SERIAL (PK) | Surrogate key |
| product_id | TEXT | Natural key, reference only |
| product_category_name | TEXT | Raw Portuguese category |
| product_category_name_english | TEXT | `LEFT JOIN` + `COALESCE(..., 'Unknown Category')` — fixes 613 unresolved products without dropping them |
| product_weight_g | NUMERIC | `NULLIF('') ` cast from text |
| product_length_cm | NUMERIC | `NULLIF('')` cast from text |
| product_height_cm | NUMERIC | `NULLIF('')` cast from text |

Dummy row: `product_pk = -1`, "Unknown"/"Unknown Category".
Deliberately kept **denormalized (star, not snowflake)** — see Phase 4 stretch-task decision: the category list is ~71 rows and low-churn, so a snowflaked `dim_product_category` table would add a second join to every BI query for negligible storage benefit.

### `core.dim_store`
Olist's "sellers" re-themed as NovaMart's pop-up stores/vendors.

| Column | Data Type | Notes |
|---|---|---|
| store_pk | SERIAL (PK) | Surrogate key |
| seller_id | TEXT | Natural key, reference only |
| store_city | TEXT | Standardised with `INITCAP(TRIM(...))` |
| store_state | TEXT | |
| store_zip_code_prefix | TEXT | |

Dummy row: `store_pk = -1`, "Unknown".

### `core.fact_sales`
**Grain:** one row per order line (matches `staging.raw_order_items` exactly — the finest grain the source data supports, per Ch. 3 §3.3).

| Column | Data Type | Additivity | Notes |
|---|---|---|---|
| sales_fact_pk | SERIAL (PK) | — | Surrogate key |
| order_id | TEXT | — | Degenerate dimension, kept for traceability |
| order_item_id | INT | — | Line number within the order |
| date_fk | INT | — | FK to `dim_date`; dummy `19000101` if unresolved |
| customer_fk | INT | — | FK to `dim_customer`; dummy `-1` if unresolved |
| product_fk | INT | — | FK to `dim_product`; dummy `-1` if unresolved |
| store_fk | INT | — | FK to `dim_store`; dummy `-1` if unresolved |
| channel | TEXT | — | Hardcoded `'Website'` for every row — documented Phase 1/4 assumption; Olist has no native channel split |
| order_status | TEXT | — | |
| quantity | INT | **Additive** | Always 1 per row in this dataset |
| price | NUMERIC(12,2) | **Additive** | |
| freight_value | NUMERIC(12,2) | **Additive** | `COALESCE(..., 0)` — a missing freight value means "no shipping cost occurred," never NULL (Ch. 4 §2.2) |
| sales_amount | NUMERIC(12,2) | **Additive** | = price (quantity always 1) |
| product_cost | NUMERIC(12,2) | **Additive** | **Estimated** as 0.65 × price — Olist does not provide real cost data; flagged explicitly rather than hidden |
| profit | NUMERIC(12,2) | **Additive** | = sales_amount − product_cost |
| *(derived, not stored)* unit_price | — | **Non-additive** | = price / quantity; recomputed on demand, never stored |

FK validation: an `INNER JOIN` from `fact_sales` to each dimension returns the same row count (112,650) as the fact table itself, per Task 24 — confirming the dummy-key strategy leaves no orphaned or NULL foreign keys.

---

## Schema: `mart_finance`

A narrower, pre-aggregated star scoped to Finance's stated need: "revenue, cost, and profit by product, store, and month" (Ch. 2 §3.2).

### `mart_finance.dim_month`
| Column | Data Type | Notes |
|---|---|---|
| month_id | INT (PK) | YYYYMM, e.g. 201801 |
| month_name | VARCHAR(10) | |
| quarter | INT | |
| year | INT | |

### `mart_finance.dim_product` (mart-scoped)
| Column | Data Type | Notes |
|---|---|---|
| product_pk | INT (PK) | Reuses `core.dim_product`'s surrogate key |
| product_category_name_english | VARCHAR(100) | Narrower copy — only the attribute Finance queries on |

### `mart_finance.dim_store` (mart-scoped)
| Column | Data Type | Notes |
|---|---|---|
| store_pk | INT (PK) | Reuses `core.dim_store`'s surrogate key |
| store_city | VARCHAR(100) | |
| store_state | VARCHAR(10) | |

### `mart_finance.fact_revenue_by_month`
**Grain:** one row per product + store + month (periodic-aggregation, pre-summarised from `core.fact_sales` for fast BI queries — Ch. 2 §3.2 usability/performance trade-off).

| Column | Data Type | Additivity | Notes |
|---|---|---|---|
| revenue_fact_pk | SERIAL (PK) | — | |
| month_fk | INT | — | FK to `dim_month` |
| product_fk | INT | — | FK to `dim_product` |
| store_fk | INT | — | FK to `dim_store` |
| quantity | INT | **Additive** | |
| revenue | NUMERIC(12,2) | **Additive** | `SUM(sales_amount)` from core |
| cost | NUMERIC(12,2) | **Additive** | `SUM(product_cost)` from core |
| profit | NUMERIC(12,2) | **Additive** | `SUM(profit)` from core |
| *(derived, not stored)* profit_margin_% | — | **Non-additive (ratio)** | = `SUM(profit) / SUM(revenue)`, calculated live in the BI tool — required non-additive measure for Phase 7; never stored, per Ch. 4 §3 |

No YTD/MTD column is stored here or anywhere in the warehouse — calculated live in the BI tool (QuickSight) at query time, per Ch. 4 §3: a stored running total would need constant recalculation on every load and would break if historical data were corrected.

### `mart_finance.order_fulfilment_snapshot`
**Type: Accumulating snapshot** — chosen over a periodic snapshot because Olist's order data genuinely supports a multi-stage timeline (purchase → approved → shipped → delivered), and the periodic-snapshot alternative's natural grouping column (channel) is a constant in this dataset and would add no analytical value. Full justification in `docs/05_fact_table_type_justification.md`.

**Grain:** one row per order (coarser than `fact_sales`, by design — tracks the order's fulfilment lifecycle, not its contents).

| Column | Data Type | Additivity | Notes |
|---|---|---|---|
| fulfilment_fact_pk | SERIAL (PK) | — | |
| order_id | VARCHAR(50) | — | Degenerate dimension, kept for traceability |
| customer_fk | INT | — | References `core.dim_customer` |
| order_date_fk | INT | — | Role-playing `core.dim_date`: when the order was placed |
| approved_date_fk | INT | — | Role-playing `core.dim_date`: when payment was approved |
| shipped_date_fk | INT | — | Role-playing `core.dim_date`: when handed to carrier |
| delivered_date_fk | INT | — | Role-playing `core.dim_date`: when customer received it |
| order_status | VARCHAR(30) | — | |
| days_to_approve | INT | **Non-additive** | Computed once at load for BI convenience; must be averaged/recalculated on demand, never summed |
| days_to_ship | INT | **Non-additive** | Same as above |
| days_to_deliver | INT | **Non-additive** | Same as above — this is the measure the Phase 7 KPI visual averages |

NULL handling: source timestamp columns arrive as empty strings when a stage hasn't happened yet (or the order was cancelled). `NULLIF(column,'')` converts these to true NULLs before casting to `date`, and `COALESCE(..., 19000101)` substitutes the `dim_date` dummy key so no foreign key is ever left NULL (Ch. 4 §2.4).
