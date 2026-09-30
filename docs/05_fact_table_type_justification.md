# Phase 6 — Build the Data Mart: Fact Table Type Justification

## 1. Business Context

`mart_finance` is a narrower, purpose-built data mart derived from core, scoped to a specific reporting need: "Finance wants revenue, cost, and profit by product, store, and month" (Ch. 2 §3.2). Alongside the primary revenue fact table, the brief requires a second fact table that demonstrates a different fact table type than our main transactional Sales fact (Ch. 4 §4).

## 2. The Two Options Considered

### Option A — Periodic Snapshot (e.g. `daily_channel_sales_snapshot`)

A periodic snapshot would capture one row per channel per day, summarising that day's sales for fast trend dashboards. We rejected this option for NovaMart's actual data: our Phase 4 dimensional model documents that `channel` is a constant value (`'Website'`) across every single row in the Olist dataset, since Olist is purely e-commerce data and does not distinguish NovaMart's other two channels (app, pop-up stores). A daily-channel snapshot built on a column that never varies would carry almost no analytical value over simply querying `fact_sales` directly — it would not demonstrate the periodic snapshot's real strength, which is tracking a measure that changes meaningfully across a repeating dimension.

### Option B — Accumulating Snapshot (`order_fulfilment_snapshot`) — CHOSEN

An accumulating snapshot captures one row per order, with foreign keys for each milestone in a process that unfolds over time — here, `order_date`, `approved_date`, `shipped_date`, and `delivered_date`, using a role-playing Date dimension (Ch. 3 §4.4). We chose this option because Olist's raw order data genuinely provides this multi-stage timeline: `order_purchase_timestamp`, `order_approved_at`, `order_delivered_carrier_date`, and `order_delivered_customer_date` are all present in the source data. This is exactly the business process an accumulating snapshot is designed to track: one row that is progressively updated as an order moves through its lifecycle, rather than a new row being created at each stage.

## 3. Why the Accumulating Snapshot Fits Better

- Olist's data genuinely supports it: all four fulfilment milestones exist as real, populated (or legitimately blank) columns in `staging.raw_orders` — nothing had to be invented or approximated.
- It answers a real business question the brief requires: "how long does order fulfilment take?" (Phase 1, business question) is answered directly by this table's `days_to_approve`, `days_to_ship`, and `days_to_deliver` fields.
- It demonstrates the role-playing Date dimension technique (Ch. 3 §4.4) explicitly, since `core.dim_date` is joined four times under four different roles — a modelling concept the periodic snapshot option would not have exercised.
- The periodic snapshot's natural grouping column (`channel`) is constant in this dataset, so it would not showcase the fact table type meaningfully, whereas the accumulating snapshot's grain (one row per order, updated across its lifecycle) directly matches data we actually have.

## 4. Design Notes

**Grain:** one row per order (not per order line) — this table tracks the order's fulfilment lifecycle, not its contents, so it sits at a coarser grain than `fact_sales` by design.

**NULL handling:** `order_approved_at`, `order_delivered_carrier_date`, and `order_delivered_customer_date` arrive from the source as empty strings when an order has not yet reached that stage (or was cancelled). Following the same fix applied in Phase 5 (Issue 1 of our Data Quality Report), `NULLIF(column,'')` converts these to true NULLs before casting to date, and `COALESCE(...,19000101)` substitutes the Dim_Date dummy key so no foreign key is ever left NULL (Ch. 4 §2.4).

**Non-additive facts:** `days_to_approve`, `days_to_ship`, and `days_to_deliver` are calculated once at load time for BI convenience, but are documented as non-additive (Ch. 4 §1) — they must be averaged or recalculated on demand, never summed across orders.

## 5. Conclusion

The accumulating snapshot (`order_fulfilment_snapshot`) was chosen over the periodic snapshot alternative because it is the fact table type genuinely supported by NovaMart's underlying data, and because it directly answers one of our Phase 1 business questions on order fulfilment time — rather than being chosen simply to satisfy the brief's requirement for a second fact table type.
