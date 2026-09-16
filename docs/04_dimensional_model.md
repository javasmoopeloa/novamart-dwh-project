# Phase 4 — Dimensional Model: NovaMart Sales

## Step 1: Business Process
**Sales.** This is NovaMart's most critical, most available process (per Ch. 4 §5
Step 1) and the recommended starting point per the brief.

## Step 2: Grain
**One row per order line** (i.e. one row per record in the source `order_items`
file: one product, purchased by one customer, fulfilled by one seller/store, at
one price, within one order).

This is the atomic grain (Ch. 3 §3.3) — it is the lowest level of detail the
source data actually provides. We deliberately do NOT grain at "one row per
order," because a single order can contain multiple products from multiple
sellers, and collapsing to order-level would force us to either lose that
detail or invent an aggregation rule prematurely. Starting atomic means every
business question in Phase 1 (profitability by product, by channel, etc.) can
be answered by aggregating up, without ever needing to reload history at a
finer grain later.

## Step 3: Dimensions

| Dimension | Natural Key (source) | Surrogate Key | Notes |
|---|---|---|---|
| Dim_Date | date (YYYYMMDD) | `date_id` (INT, YYYYMMDD) | Exception to the surrogate-key rule (Ch. 4 §7.4) — the natural, meaningful integer *is* the key. |
| Dim_Customer | `customer_id` | `customer_pk` (SERIAL) | One row per customer_id as it appears in the source (note: Olist's `customer_unique_id` represents the *person*, `customer_id` represents one *order-instance* of that person — kept as reference column, not used as the dimension grain, to stay simple for v1). |
| Dim_Product | `product_id` | `product_pk` (SERIAL) | Includes category name (raw + English translation), weight/dimensions. |
| Dim_Store | `seller_id` | `store_pk` (SERIAL) | Olist "sellers" re-themed as NovaMart pop-up stores/vendors (per our S3 `pos/` folder mapping). |

**Channel note:** NovaMart's business scenario describes three channels
(website, app, pop-up stores), but the Olist dataset is entirely e-commerce
order data — it does not distinguish website vs. app orders. For this project,
every row is treated as **Channel = "Website"** at the fact level (a
degenerate attribute, not a full dimension, since it never varies in this
dataset). `Dim_Store` carries the "which vendor/pop-up fulfilled this" angle
instead. Document this assumption explicitly in your data dictionary.

## Step 4: Facts

| Fact | Grain-level meaning | Additivity (Ch. 4 §1) |
|---|---|---|
| `quantity` | Always 1 per order-item row in this dataset (Olist doesn't split quantity — a qty-2 purchase appears as 2 line rows) | **Additive** — sum across any dimension to get total units sold |
| `price` | Line-item price paid | **Additive** — sums to total sales revenue |
| `freight_value` | Shipping cost for that line | **Additive** — sums to total freight cost |
| `unit_price` | price / quantity | **Non-additive** — never sum this; recompute on demand as SUM(price)/SUM(quantity) whenever "average price" is needed |
| `sales_amount` | = price (quantity is always 1, so this equals price) | **Additive** |
| `product_cost` *(assumption)* | Estimated cost of goods sold. Olist provides no cost data, so we assume **product_cost = 0.65 × price** (65% COGS ratio) — documented explicitly as an estimation, not real data | **Additive** |
| `profit` | = sales_amount − product_cost | **Additive** (built from two additive components, so it's safe to sum, but per Ch. 4 §3 we still don't pre-store MTD/YTD rollups of it — those get calculated in the BI tool in Phase 7) |

**Important:** `product_cost` and `profit` are clearly flagged in the data
dictionary as *estimated*, not sourced. This is worth calling out directly to
your marker rather than hiding it — real DWH projects run into exactly this
kind of gap, and documenting the assumption honestly is the correct move,
not a weakness.

## Surrogate Keys & Dummy Key Strategy (Ch. 4 §7, §2.4)

Every dimension except `Dim_Date` gets an auto-incrementing integer surrogate
key (`SERIAL` in Postgres). Natural keys (`customer_id`, `product_id`,
`seller_id`) are kept as reference columns, never used as join keys in the
fact table.

For any fact row where the source `product_id`, `seller_id`, or `customer_id`
doesn't match anything in the corresponding staging table (see Phase 3's
orphaned-FK checks), we substitute a **dummy key of -1**, and each dimension
gets one extra row:

```
INSERT INTO core.dim_customer (customer_pk, customer_id, customer_city, customer_state)
VALUES (-1, 'UNKNOWN', 'Unknown', 'Unknown');
```

(same pattern for `dim_product` = -1 "Unknown Product", `dim_store` = -1
"Unknown Store"). `Dim_Date` gets a dummy row too, using `19000101` as the
"not applicable / unknown date" key, since -1 isn't a valid YYYYMMDD integer.

## Stretch Task: Snowflaking Dim_Product

The raw data already gives us a natural snowflake candidate: the
`product_category_name_translation` file. Rather than flattening the English
category name directly into `Dim_Product`, we could split it into a separate
`Dim_Product_Category` lookup table (`category_pk`, `category_name_pt`,
`category_name_english`), referenced from `Dim_Product` via `category_fk`.

**Recommendation: keep it as a star (denormalized), not a snowflake, for
NovaMart's actual use case.** The category list is small (~71 rows) and
rarely changes, so the storage/normalization benefit is negligible, while a
flattened `Dim_Product` keeps every BI query a single join instead of two —
directly serving the Ch. 3 §7 criterion that query simplicity usually wins
when a dimension is small and low-churn. We snowflake only where a dimension
is large and volatile enough that duplication becomes a real cost — that's
not the case here.
