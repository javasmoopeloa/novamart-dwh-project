# NovaMart Data Warehouse — Phase 7: Reporting Layer

**Milestone 4 — Phase 7 (Reporting Layer)**
**Tool used:** AWS QuickSight, connected directly to the `mart_finance` schema on our RDS PostgreSQL warehouse (`novamart-dwh2`).

**Team:**
- Moopeloa Jabulane — 22350028
- Asande Akhona Dlamini — 22367136
- Sibahle Magubane — 22271233
- Senamile Nxumalo — 22302052

---

## 1. Overview

This deliverable is the reporting layer built on top of the `mart_finance` data mart produced in Phase 6. The dashboard was built in AWS QuickSight and connects live to:

- `mart_finance.fact_revenue_by_month` — joined to `dim_month`, `dim_product`, and `dim_store` (one dataset). A calculated column, `month_start_date`, is added in the QuickSight dataset to convert the integer `month_id` (YYYYMM) into a real date for time-based calculations.
- `mart_finance.order_fulfilment_snapshot` — used on its own, since it sits at a different grain (one row per order, not per product/store/month)

All 6 visuals below live on a single dashboard sheet, titled **"NovaMart Finance Dashboard — Reporting Layer."**

> Dashboard link: https://us-east-1.quicksight.aws.amazon.com/sn/account/JABU/dashboards/15660871-8eb6-4e34-96ac-03feeb769d14/views/b3e98aff-cd4f-4549-b89f-fde6a0ad9cf5

---

## 2. Business questions this dashboard answers

Phase 1 originally proposed five business questions. Two of them (month-to-date revenue by channel, and channel growth year-over-year) turned out not to be answerable once we reached the reporting layer, because our Phase 1 dataset-mapping note had already flagged that the Olist source data has no native channel split, and Phase 5's ETL hardcodes `channel = 'Website'` for every row as a documented assumption rather than deriving it. Rather than publish two visuals that can't actually show what they claim to, we reframed the dashboard around the five business questions our data *can* answer, drawn from the same underlying grain (revenue, profit, product, location, fulfilment time) as the original set.

The five questions this dashboard answers (plus a sixth visual, Year-to-Date Revenue, which supports Q4 and demonstrates the Ch. 4 §3 principle):

1. Which products are most profitable, and which product categories should we invest in or cut?
2. Which store locations ("regions") generate the most revenue?
3. What is the overall profit margin, and how is it trending month to month?
4. How is revenue and profit trending over time — are we growing?
5. How long does order fulfilment take on average, and is it fast enough to be competitive?

### Visual 1 — Monthly Revenue & Profit Trend
**Chart type:** Line chart (`month_id` on X-axis, `revenue` and `profit` as values)
**Answers:** Q4 — *how is revenue and profit trending over time — are we growing?*
Gives Finance the month-over-month trend line needed to see growth or decline at a glance, with revenue and profit plotted together so margin compression is visible even when revenue is flat or rising.

### Visual 2 — Profit Margin %
**Chart type:** KPI card with trend sparkline
**Calculation:** `sum(profit) / sum(revenue)` — a calculated field, non-additive by design
**Answers:** Q3 — *what is the overall profit margin, and how is it trending month to month?*
This is the required non-additive/semi-additive ratio measure for this milestone. It is deliberately calculated in the BI layer rather than stored in the warehouse (Ch. 4 §3 — a ratio like this cannot be summed across rows the way revenue or profit can; it must be recalculated at the aggregation level shown).

### Visual 3 — Revenue by Product Category
**Chart type:** Vertical bar chart (`product_category_name_english` on X-axis, `revenue` as value), sorted descending
**Answers:** Q1 — *which products are most profitable, and which categories should we invest in or cut?*
Identifies top and bottom performing product categories.

### Visual 4 — Revenue by Store City
**Chart type:** Horizontal bar chart (`store_city` on Y-axis, `revenue` as value), sorted descending
**Answers:** Q2 — *which store locations generate the most revenue?*
`store_city` is our closest available proxy for "region," since `mart_finance` does not carry a separate customer-region dimension. Combined with Visual 3, this gives a product-and-location view of where revenue concentrates.

### Visual 5 — Average Days to Deliver
**Chart type:** KPI card
**Source:** `order_fulfilment_snapshot` (accumulating snapshot fact table)
**Calculation:** `avg(days_to_deliver)` — explicitly averaged, not summed, since this measure is flagged non-additive in our Phase 6 design notes
**Answers:** Q5 — *how long does order fulfilment take on average, and is it fast enough to be competitive?*
This is the required visual built on the accumulating snapshot fact table.

### Visual 6 — Year-to-Date Revenue
**Chart type:** Line chart, one panel per year (`month_start_date` by Month on X-axis, `year` as small multiples, `ytd_revenue` as value)
**Calculation:** `runningSum(sum({revenue}), [{month_start_date} ASC], [{year}])` — a calculated field in the QuickSight analysis, restarting at zero each year
**Answers:** Q4 — *how is revenue growing within each year?*
This is the required Year-to-Date calculation built in the BI tool. No YTD or MTD column exists anywhere in the warehouse (Ch. 4 §3): a cumulative total depends on which period the viewer picks, so it is calculated on demand from the additive `revenue` measure. QuickSight's built-in `periodToDateSum` function measures from the current date, which does not work for our 2016–2018 data, so a running sum partitioned by year is used instead.

---

## 3. Dashboard screenshots

### Visual 1 — Monthly Revenue & Profit Trend
**Question answered:** How is revenue and profit trending over time — are we growing?

![Revenue and Profit Trend](screenshots/5_revenue_profit_trend.png)

### Visual 2 — Profit Margin %
**Question answered:** What is the overall profit margin, and how is it trending month to month?

![Profit Margins](screenshots/2_profit_margins.png)

### Visual 3 — Revenue by Product Category
**Question answered:** Which products are most profitable, and which product categories should we invest in or cut?

![Revenue by Product Category](screenshots/4_revenue_by_product_category.png)

### Visual 4 — Revenue by Store City
**Question answered:** Which store locations ("regions") generate the most revenue?

![Revenue by Store City](screenshots/3_revenue_by_store_city.png)

### Visual 5 — Average Days to Deliver
**Question answered:** How long does order fulfilment take on average, and is it fast enough to be competitive?

![Average Days to Deliver](screenshots/1_days_to_deliver.png)

### Visual 6 — Year-to-Date Revenue
**Question answered:** How is revenue accumulating within each year?

![Year-to-Date Revenue](screenshots/6_ytd_revenue.png)

---

## 4. Notes on reading the dashboard

- Several charts have scroll bars or range sliders. These only change which part of the data is visible and do not filter it. The total revenue across the full dataset is 13,591,643.7.
- The last month in the data (Sep 2018) shows a sharp drop to near zero in the monthly trend chart. This appears to be a partial month in the source Olist data rather than a real collapse in sales.
