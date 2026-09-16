# Phase 3 — Data Quality Report

Profiling conducted on the staged Olist data in `staging` before any
transformation, per Ch. 1 §11 and Ch. 4 §2. Each issue below is classified as
a **NULL-in-a-measure** problem, a **NULL-in-a-foreign-key** problem, or a
**formatting/consistency** issue, with the fix that will be applied in the
Phase 5 staging → core ETL.

---

## Issue 1: Missing dates stored as empty strings, not NULL

**Table/column:** `staging.raw_orders.order_approved_at`,
`order_delivered_carrier_date`, `order_delivered_customer_date`

**What we found:** A standard `IS NULL` check on these columns returned 0 for
every row, which looked suspiciously clean. Investigating further showed the
"missing" values are stored as empty strings (`''`), not true SQL `NULL`s —
2,965 rows have `order_delivered_customer_date = ''`, all orders that were
either cancelled or never confirmed as delivered. Because staging types
everything as `TEXT` (Ch. 2 §2.1's "as little touching as possible" rule),
the CSV's blank fields loaded as `''` rather than `NULL`.

**Classification:** Not strictly a "measure," but the same underlying
principle as Ch. 4 §2.2 — a value representing "this hasn't happened yet"
needs consistent representation, or downstream `IS NULL` logic (and later,
`is_holiday_flag`-style boolean logic in the fact table) will silently
misbehave.

**Fix (Phase 5):** Cast with `NULLIF(column, '')::date` when moving from
staging to core, converting empty strings to true NULLs before typing.

---

## Issue 2 (verified clean): order_items pricing and referential integrity

**Tables/columns checked:** `staging.raw_order_items.price` / `freight_value`
(NULLs and empty strings), plus foreign-key joins from `raw_order_items` to
`raw_products`, `raw_sellers`, and from `raw_orders` to `raw_customers`.

**What we found:** All checks came back completely clean — 0 NULLs and 0
empty strings across 112,650 rows in `price`/`freight_value`, and every
`product_id`, `seller_id`, and `customer_id` referenced by a child table
resolves to a real row in its parent table. No orphaned foreign keys, no
missing measures.

**Why this belongs in the report:** Ch. 1 §11 profiling isn't only about
finding defects — confirming a checked assumption holds is itself a
documented finding. It means Phase 5's ETL doesn't need dummy-key
substitution logic for these three relationships, which is a real design
decision worth recording, not an accident.

---

## Issue 3: Products with missing or untranslated category

**Table/column:** `staging.raw_products.product_category_name` →
`staging.raw_product_category_translation`

**What we found:** 613 products fail to resolve an English category name
when left-joined to the translation table:
- **610 products** have a completely blank `product_category_name`
- **10 products** use category `portateis_cozinha_e_preparadores_de_alimentos`,
  not present in the 71-row translation table
- **3 products** use category `pc_gamer`, also not present in the
  translation table

**Classification:** **NULL-in-a-foreign-key problem** (Ch. 4 §2.4) — these
products are real, valid rows, but a naive inner join to the translation
table would silently drop their category attribute (or drop the row
entirely, if joined incorrectly to the fact table).

**Fix (Phase 5):** Use a `LEFT JOIN` (never `INNER JOIN`) from
`raw_products` to the translation table when building `core.dim_product`,
and wrap the result in `COALESCE(category_name_english, 'Unknown Category')`.
This is a dummy *value* fix within an otherwise-real dimension row — distinct
from the dummy *row* (`-1`) pattern used for completely unmatched foreign
keys in the fact table.

---

## Issue 4: City names stored as raw, unstandardized lowercase text

**Table/column:** `staging.raw_customers.customer_city`

**What we found:** Every one of the 99,441 city values is lowercase exactly
as it arrived from the source (e.g. `sao paulo`, `rio de janeiro`,
`belo horizonte`) — not a mix of inconsistent casings, but uniformly raw,
unformatted text. This is expected under Ch. 2 §2.1's "as little touching as
possible" staging principle, but it isn't presentation-ready for a dimension
table or a BI dashboard.

**Classification:** Formatting/consistency issue (not a NULL problem).

**Fix (Phase 5):** Apply `INITCAP(TRIM(customer_city))` when loading into
`core.dim_customer`, producing "Sao Paulo" instead of "sao paulo."

---

## Issue 5: CSV import tool limitation on multi-line quoted fields

**Table/column:** `staging.raw_order_reviews` (entire table)

**What happened:** The first import attempt silently corrupted rows — review
text was misparsed into the `order_id` column, inflating the row count to
158,240 against an expected ~99,224. Investigation traced this to
DBeaver's CSV import wizard being unable to correctly handle quoted fields
that span multiple physical lines (customers occasionally hit Enter while
typing a review). The source file itself was verified valid RFC4180 CSV using
Python's csv parser (99,224 rows, zero parse errors) — the issue was
tool-specific, not a data quality defect in the source.

**Classification:** Not a NULL problem — a data *loading* integrity issue.
Worth documenting because it demonstrates the Ch. 1 §11 principle that
profiling must happen before trusting any load, even a load that appears to
"succeed" without an error message.

**Fix applied:** Regenerated the CSV with embedded newlines stripped from
free-text fields so every record occupies exactly one physical line,
eliminating the ambiguity. (Full reviews load deferred past this milestone
since `raw_order_reviews` isn't required for the core Sales fact grain.)

---

## Summary table

| # | Issue | Table.Column | Type | Fix |
|---|---|---|---|---|
| 1 | Empty strings instead of NULL | raw_orders (3 date cols) | Consistency / NULL-adjacent | `NULLIF(col,'')::date` |
| 2 | Verified clean: pricing + 3 FK relationships | raw_order_items, raw_orders | N/A — confirmed no issue | No fix needed; documented as a checked assumption |
| 3 | 613 products with missing/untranslated category | raw_products → raw_product_category_translation | NULL-in-a-foreign-key | `LEFT JOIN` + `COALESCE(...,'Unknown Category')` |
| 4 | Unstandardized lowercase city names | raw_customers.customer_city | Formatting | `INITCAP(TRIM(col))` |
| 5 | Import tool corrupted multi-line CSV rows | raw_order_reviews | Load integrity | Regenerated source file |

All 5 issues are now fully documented with real numbers from the actual
staged data, ready to carry into the Phase 5 ETL script and the final
presentation.
