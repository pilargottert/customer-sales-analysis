# Findings

## Step 2: Table grain

| Table | One row = one ___ | Check | Result |
|---|---|---|---|
| customers | customer | `COUNT(*)` vs `COUNT(DISTINCT customer_id)` | 124 / 124, confirmed |
| orders | order | `COUNT(*)` vs `COUNT(DISTINCT order_id)` | Match, confirmed |
| order_items | product within an order (one order line) | `COUNT(*)` vs distinct `order_id + product_id` | 2832 / 2818, see data quality note |
| products | product | `COUNT(*)` vs `COUNT(DISTINCT product_id)` | 24 / 24, confirmed |
| quotes | quote | `COUNT(*)` vs `COUNT(DISTINCT quote_id)` | Match, confirmed |
| quote_items | product within a quote (one quote line) | `COUNT(*)` vs distinct `quote_id + product_id` | Match, confirmed |
| sales_rep | sales rep | `COUNT(*)` vs `COUNT(DISTINCT rep_id)` | Match, confirmed |

## Step 3: Relationships (ERD)

| From | To | Key |
|---|---|---|
| customers | orders | `customer_id` |
| orders | order_items | `order_id` |
| products | order_items | `product_id` |
| quotes | quote_items | `quote_id` |
| products | quote_items | `product_id` |
| quotes | orders | `quote_id` (not every quote becomes an order) |
| sales_rep | orders | `rep_id` |
| sales_rep | quotes | `rep_id` |
| customers | sales_rep | `region` (shared attribute, not a key; see note) |

- 1 quote can have several products; 1 order can have several products.
- Price is in order_items; cost is in products.
- **Region is not a reliable join between customers and reps:** AMBA and Centro each have two reps, so a customer can't be assigned to a single rep from region alone. Rep attribution should come from `rep_id` on orders/quotes.

## Step 4: Date ranges

| Table | First date | Last date |
|---|---|---|
| orders | 2023-02-02 | 2026-06-30 |
| quotes | 2023-01-05 | 2026-06-30 |

## Step 5: Distinct values

- **quotes.status:** won, lost, pending
- **products.category:** Fans & Blowers, Ducting, Filtration, Pumps, Controls & Sensors, Services, Solar Pumping
- **customers.industry:** Manufacturing, Oil & Gas, Water Utilities, Mining, Construction, Food & Beverage, Agriculture, **NULL** (see data quality issues)
- **customers.region:** inconsistent labels (see data quality issues). sales_rep uses Norte, not NOA or NEA.

## Step 6: Quotes by status

```sql
SELECT status, COUNT(*) AS num_quotes
FROM quotes
GROUP BY status
ORDER BY num_quotes DESC;
```

| Status | Quotes | Share |
|---|---|---|
| lost | 2,255 | 59.0% |
| won | 1,467 | 38.4% |
| pending | 100 | 2.6% |
| **Total** | **3,822** | 100% |

## Data quality issues

### order_items: 14 exact duplicate rows
- 2832 total rows, but only 2818 distinct `order_id + product_id` pairs.
- Inspecting the duplicated pairs showed every column was identical.
- `SELECT COUNT(*) FROM (SELECT DISTINCT * FROM order_items)` returned 2818, so all 14 extra rows are exact copies.
- **Impact:** if left in, quantities and revenue for the affected orders would be double counted.
- **Action:** remove duplicates (e.g. work from `SELECT DISTINCT *`) before any analysis.

### customers.region: inconsistent labels
- **AMBA:** appears as "AMBA", "amba", "AMBA " (possible trailing space) and "Buenos Aires (AMBA)"
- **Centro:** "Centro", "CENTRO", "centro", "Centro " (possible trailing space)
- **Patagonia:** "Patagonia", "patagonia", "Patagonia " (possible trailing space)
- **Cuyo:** "Cuyo", "cuyo"
- **Norte vs NOA:** NOA is technically a sub-region of the north; sales_rep only uses Norte, so NOA was mapped to Norte
- Check spacing with `SELECT DISTINCT region, LENGTH(region) FROM customers;`
- **Action:** standardize to one label per region (trim spaces, fix case, merge variants) before grouping by region.

### customers.industry: NULL values
- Some customers have no industry.
- **Action:** labeled as "Unknown" in customers_clean (`COALESCE(industry, 'Unknown')`), so they stay visible in industry breakdowns.

---

# Phase 2: Cleaning

All fixes are built as views or helper tables on top of the raw data; the original tables are never edited. Queries are saved in `queries/00_cleaning.sql`, and every view starts with `DROP VIEW IF EXISTS` so the whole file can be rerun from scratch.

## Step 1: Inconsistent text

| Column | Result | Fix |
|---|---|---|
| customers.region | Case, spacing and label variants (see Phase 1 notes) | `CASE WHEN LOWER(TRIM(region)) ...` in customers_clean → 5 clean regions: AMBA, Centro, Cuyo, Norte, Patagonia |
| customers.industry | NULL values | `COALESCE(industry, 'Unknown')` |
| customers.customer_name | Punctuation, case and accent variants ("s.a." vs "sa", "Hídricos" vs "HÍDRICOS") revealed duplicate customers | See step 4 |
| sales_rep.region | Checked, clean | None |
| products.category | Checked, clean | None |
| quotes.status | Checked, clean | None |

**customers_clean:** trims text columns, standardizes region, fills NULL industry, and excludes the four duplicate customer IDs (121, 122, 123, 124).

## Step 2: NULL values

- **customers.industry:** the only column with NULLs; labeled "Unknown" in customers_clean.
- **All other columns** in the clean views were checked with `SUM(column IS NULL)`: no NULLs found.

## Step 3: Duplicate rows (order_items)

- 14 exact duplicate rows in order_items (2832 raw vs 2818 distinct).
- **Revenue impact:** left in, they would overstate revenue (`quantity * unit_price`) by **0.39%**.
- **Fix:** order_items_clean built from `SELECT DISTINCT * FROM order_items`.

## Step 4: Duplicate entities (customers)

Normalizing names (`LOWER(TRIM(REPLACE(customer_name, '.', '')))`) revealed three companies stored under two IDs each. A fourth (5/124) was found later, in Phase 6 (see note below):

| Kept ID | Duplicate ID | Orders (kept / dup) | Quotes (kept / dup) | Kept ID active | Duplicate ID active |
|---|---|---|---|---|---|
| 24 | 121 | 37 / 21 | 91 / 54 | 2023-01-05 to 2026-06-22 | 2024-06-20 to 2026-06-23 |
| 35 | 123 | 14 / 3 | 30 / 13 | 2023-02-23 to 2026-05-02 | 2025-01-31 to 2026-05-25 |
| 71 | 122 | 13 / 6 | 33 / 18 | 2023-01-18 to 2025-12-31 | 2024-09-17 to 2026-06-17 |
| 5 | 124 | 16 / 6 | 33 / 16 | 2023-01-31 to 2026-06-16 | 2024-10-14 to 2026-04-22 |

**Rule:** keep the original (lower) ID, which in every pair also has most of the activity.

**What happened:**
- Every duplicate ID was created well after its original (mid-2024 to early 2025), and both IDs were then used in parallel. For 71/122 the team eventually moved fully to the new record.
- The first three duplicates appeared after rep 4 started quoting (2024-03-04). Rep 4 created two of them (122, 123) and rep 3 created one (121); both reps then quoted under both IDs.
- **The fourth (124) was created by rep 5 in Cuyo**, who handled both IDs alone. So duplicates aren't limited to the two reps sharing Centro.
- **For 5/124, orders moved to the new record:** the last order under ID 5 was 2025-05-27, while 124 kept receiving orders until 2026-02-26 (quotes continued under both IDs).
- This points to a process gap rather than one person's error: nothing stops a rep from creating a customer that already exists.
- **Impact:** without merging, these customers' activity is split across two records. For 24/121, about a third of the company's orders and quotes sit under the duplicate ID.
- **Recommendation:** check for an existing customer before creating a new one.

**Fix:** a `customer_map(customer_id, master_customer_id)` table with one row for every customer (124 rows); the four duplicates map to their original ID and all others map to themselves. Later views and queries join through it, so orders and quotes from duplicate IDs are attributed to the original customer.

**Why 5/124 was missed at first:** SQLite's `LOWER()` only converts plain A–Z letters, so accented capitals stay uppercase (`SELECT LOWER('HÍDRICOS')` returns `hÍdricos`). The names "Servicios Hídricos Quebracho Coop. Ltda." and "SERVICIOS HÍDRICOS QUEBRACHO COOP. LTDA." therefore didn't match after normalizing.
- **Fix:** reran the check with the accented capitals replaced first (`REPLACE(name, 'Í', 'í')` and the same for Á, É, Ó, Ú, Ñ), then `LOWER`, `TRIM` and dot removal, using a self-join on the normalized name (`a.customer_id < b.customer_id` to list each pair once).
- **Result:** exactly 4 pairs: the original three plus 5/124. No other duplicates.
- **Lesson:** with Spanish text, `LOWER()` alone isn't a reliable way to compare names in SQLite.

---

# Phase 3: Analysis base

Two wide views that combine the clean tables, so later queries don't repeat the joins. They are also the data sources for the Power BI dashboard.

## Step 1: sales_lines (one row = one order line)

| From | To | Key | Join |
|---|---|---|---|
| order_items_clean | orders_clean | `order_id` | INNER |
| orders_clean | customers_clean | `customer_id` (master ID) | INNER |
| order_items_clean | products | `product_id` | INNER |
| orders_clean | sales_reps | `rep_id` | INNER |

- **Columns:** order ID, order date, year (`strftime('%Y')`), month (`strftime('%Y-%m')`), customer ID and name, industry, region, rep name, product, category, quantity, unit price, plus **revenue** (`quantity * unit_price`), **cost** (`quantity * standard_cost`) and **gross profit** (revenue − cost).
- **Reps joined through `orders.rep_id`, not region:** AMBA and Centro have two reps each, so joining on region would duplicate rows. `rep_id` is also the rep who actually handled the order.
- **Duplicate customers:** checked that IDs 121, 122 and 123 have no rows in orders_clean (already remapped to their master IDs), so joining on `customer_id` loses nothing.

## Step 2: quote_summary (one row = one quote)

- **Joins:** quote_items → quotes_clean (`quote_id`), customers_clean (`customer_id`), sales_reps (`rep_id`), products (`product_id`). All INNER, then `GROUP BY` quote.
- **Columns:** quote ID, quote date, days to decide, customer, region, rep, status, total quoted value, total value at list price, discount %, Solar Pumping flag.
- **Days to decide:** `julianday(decided_date) - julianday(quote_date)`.
- **Totals:** `SUM(quantity * price)` across the quote's lines.
- **Discount %:** `100 - (total quoted × 100 / total list)`, calculated from the summed totals, not by adding up per-line discounts.
- **Solar Pumping flag:** `MAX(CASE WHEN category = 'Solar Pumping' THEN 1 ELSE 0 END)` gives 1 if any line in the quote is a Solar Pumping product (product IDs 22–24).
  - **Check:** 226 quotes flagged, matching `COUNT(DISTINCT quote_id)` from quote_items where `product_id IN (22, 23, 24)`.
- **Note:** there is no quote_items_clean; quote_items was used directly (grain already confirmed in Phase 1).

## Step 3: Price-list change (the detective work)

The README warns that `list_price` is the price at the start of 2023, so I checked whether it stayed valid.

**Method:** averaged `quoted_price * 1.0 / list_price` by month (`* 1.0` avoids integer division).

**What I saw:**
- **Jan 2023 – Feb 2025:** the average ratio stays flat at about 0.87–0.90.
- **Mar 2025 onward:** it jumps to about 0.99–1.01 and stays there through June 2026.
- It's a permanent step, not noise (218 lines in March 2025, 182 in April), so the **price list changed**; salesperson behaviour didn't.

**Measuring it:** grouped every line as before / after 2025-03-01 with `CASE WHEN`.

| Period | Avg quoted ÷ list | Lines |
|---|---|---|
| Before 2025-03-01 | 0.8867 | 4,112 |
| From 2025-03-01 | 0.9986 | 3,168 |

- **Factor:** 0.9986 / 0.8867 = **1.126**, so list prices rose about **12.6% in March 2025**.
- **Fix:** list value uses `CASE WHEN quote_date >= '2025-03-01' THEN list_price * 1.126 ELSE list_price END`, in both total list value and discount.

**Check after the correction (average discount by year):**

| Year | Avg discount | Quotes |
|---|---|---|
| 2023 | 11.8% | 928 |
| 2024 | 11.1% | 1,100 |
| 2025 | 11.2% | 1,195 |
| 2026 | 11.2% | 599 |

- **Impact if not fixed:** 2025–26 discounts would have looked like ~0%, a false finding that discounting had stopped.
- **Insight:** reps kept giving the same ~11% discount; they applied it to a higher price list.

## Step 4: Reconciliation

| View | Check | View | Source | Result |
|---|---|---|---|---|
| sales_lines | Rows | 2,818 | 2,818 (order_items_clean) | Match |
| sales_lines | Revenue | $30,771,551.71 | $30,771,551.71 (order_items_clean) | Match |
| quote_summary | Quotes | 3,822 | 3,822 (quotes_clean) | Match |

**Why INNER JOIN everywhere:** an INNER JOIN silently drops rows with no match. Row counts and revenue are identical to the source tables, so every line matched an order, customer, product and rep, and every quote has at least one line. No rows were dropped or duplicated.

---

# Phase 4: Overview

Queries are saved in `queries/01_overview.sql`.

## Q1: Headline KPIs, overall and by year

**Overall (Feb 2023 – Jun 2026)**

| Revenue | Orders | Avg order value | Gross margin |
|---|---|---|---|
| $30,771,551.71 | 1,467 | $20,975.84 | 33.3% |

**By year, with year-over-year change**

| Year | Revenue | Orders | AOV | Gross margin | Revenue YoY | Orders YoY | AOV YoY | Margin change |
|---|---|---|---|---|---|---|---|---|
| 2023 | $6,609,687.17 | 348 | $18,993.35 | 30.2% | | | | |
| 2024 | $8,793,508.73 | 455 | $19,326.39 | 29.2% | +33.0% | +30.7% | +1.8% | −1.0 pp |
| 2025 | $9,684,207.26 | 443 | $21,860.51 | 36.4% | +10.1% | −2.6% | +13.1% | +7.2 pp |
| 2026* | $5,684,148.55 | 221 | $25,720.13 | 38.0% | n/a | n/a | +17.7% | +1.6 pp |

- AOV = total revenue ÷ distinct orders (not the average of line revenue); gross margin = total gross profit ÷ total revenue.
- YoY change calculated with `LAG() OVER (ORDER BY year)` on a CTE of the yearly query. Margin change is in percentage points, not %.
- Check: yearly revenue and orders add up exactly to the overall totals.
- **Partial years:** orders start on 2023-02-02 (no January) and 2026 covers January–June only. *2026 revenue and order counts can't be compared with full years; only ratios (AOV, margin) can.

**Findings**

- **2023 → 2024:** revenue grew 33%, driven almost entirely by volume: orders rose 31% while AOV was nearly flat (+1.8%).
- **2024 → 2025:** orders fell slightly (−2.6%) but revenue grew 10.1%, because AOV rose 13.1%. This closely matches the 12.6% list-price increase in March 2025 (Phase 3, Step 3), so growth came from higher prices rather than more orders or larger quantities. Since product costs stayed the same, gross margin rose 7.2 percentage points (29.2% → 36.4%).
- **2025 → 2026:** because the price increase started in March, 2025 mixes old prices (January–February) with new ones; 2026 is the first year fully at the new price list. That remaining effect (about 12.6% × 2/12 ≈ 2%) accounts for the margin increase (+1.6 pp), but not for the full AOV rise (+17.7%), which suggests orders got larger for another reason. **Open question, to investigate in Q3.**

## Q2: Revenue by month

**Method:** pivoted `sales_lines` to one row per year and one column per month, using `SUM(CASE WHEN substr(month, 6, 2) = '01' THEN revenue END)` for each month, plus a total column as a check.

**Data limits:** same partial years as Q1 (no January 2023, nothing after June 2026), so December appears in only three years.

**Summary:** February is the weakest month and December the strongest every year; the other months show no consistent seasonal pattern.

- **February was low every year** compared to the other months, with the lowest revenue in 2023 and 2026 and among the lowest three months in 2024 and 2025. This could be because February is summer in Argentina, so many people (sales reps as well as customers) are likely off on holiday.
- **December was high every year**, with the highest revenue in 2024 and 2025 and the third highest in 2023. This could be because the calendar year was ending and clients might have had room left in their budgets to buy before the reset in January.
- **The other months don't follow a consistent pattern**, so February and December are the only clear seasonal effects in the data.

## Q3: Revenue by category and product

**Method:**
- **By category:** `SUM(revenue)` grouped by `category`, sorted descending. Share of total = category revenue × 100 ÷ total revenue, with the total from a subquery (`SELECT SUM(revenue) FROM sales_lines`) so it isn't affected by the `GROUP BY`. Rounded to 2 decimals.
- **By product:** `SUM(revenue)` grouped by `product_name, category` (every non-aggregated column in the `GROUP BY`), sorted descending, `LIMIT 10`.

**Top categories**

| Rank | Category | Share of revenue |
|---|---|---|
| 1–2 | Fans & Blowers | ~20% |
| 1–2 | Ducting | ~20% |
| 3 | Services | 16.5% |

**Top products**

| Rank | Product | Category | Share of revenue |
|---|---|---|---|
| 1 | Annual Maintenance | Services | ~15% |
| 2 | Motorized Damper MD-200 | Ducting | ~12% |
| 3 | Centrifugal Fan CF-1200 | Fans & Blowers | ~11% |
| | **Top 3 combined** | | **~38%** |

**Findings**

- **Fans & Blowers and Ducting lead**, each bringing in about a fifth of total revenue.
- **Revenue is concentrated in a few products:** the top 3 products alone make up about 38% of total revenue.
- **The damper and fan belong to the two leading categories**, so a few flagship products drive those categories' lead.
- **The top product is a service:** Annual Maintenance is the single biggest earner, ahead of any physical product. Its category, Services, ranks only 3rd (16.5%), so the category view alone would hide it.
- **Each top category depends on one product:** Annual Maintenance (~15%) is roughly 90% of Services (16.5%); the damper (~12%) and fan (~11%) each appear to be more than half of their categories (~20%). **To confirm with exact category totals.**

## Q4: Quotes and win rate by year

**Method:** one row per year (`strftime('%Y', quote_date)`) from `quote_summary`. Counts use `SUM(status = 'won')` and shares use `100 * AVG(status = 'won')`; in SQLite a true comparison counts as 1, so `SUM` gives the count and `AVG` gives the share.

```sql
SELECT
	strftime('%Y', qs.quote_date) AS year,
	COUNT(qs.quote_id) AS number_of_quotes,
	SUM(qs.status = 'won') AS won,
	ROUND(100 * AVG(qs.status = 'won'), 2) AS pct_won,
	SUM(qs.status = 'lost') AS lost,
	ROUND(100 * AVG(qs.status = 'lost'), 2) AS pct_lost,
	SUM(qs.status = 'pending') AS pending,
	ROUND(100 * AVG(qs.status = 'pending'), 2) AS pct_pending,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) AS win_rate
FROM quote_summary qs
GROUP BY year;
```

- **Share vs win rate:** `pct_won` is won ÷ all quotes; `win_rate` is won ÷ decided quotes (won + lost). Pending quotes aren't losses, so they're left out of the win rate; otherwise recent years would look worse just because their quotes haven't been decided yet.
- **Check:** won + lost + pending = total quotes each year, and the three shares add up to 100%.

**Findings**

- **Quote volume grew every full year:** 928 (2023) → 1,100 (2024) → 1,195 (2025). 2026 has 599 quotes for January–June.
- **Win rate rose ~2 pp from 2023 to 2024, fell ~6 pp from 2024 to 2025, and stayed similar in 2026.**
- **The drop coincides with the March 2025 list-price increase** (~12.6%, Phase 3, Step 3): win rate fell from 42.2% to 35.5% after it (see check below). Reps kept the same ~11% average discount on the higher prices, so customers faced higher net prices, which may explain why fewer quotes converted.
- **The price increase was a trade-off that paid off:** despite the lower win rate, 2025 revenue grew 10.1% and gross margin rose 7.2 pp (Q1). Fewer deals were won, but at higher prices.
- **More quotes, fewer wins:** quotes rose from 1,100 to 1,195 in 2025, while orders fell slightly from 455 to 443 (Q1), consistent with the lower win rate.
- **Pending quotes only appear in 2026**, as expected for a year still in progress. The 2026 win rate is based on decided quotes only, so it may shift as those quotes close.

**Check: win rate before and after the price change**

2025 includes January–February at the old prices, so the year-level comparison blurs the timing. Split quotes at 2025-03-01 with `CASE WHEN` (same approach as Phase 3, Step 3):

```sql
SELECT
	CASE WHEN qs.quote_date < '2025-03-01' THEN 'Before price change'
	     ELSE 'After price change' END AS period,
	COUNT(qs.quote_id) AS number_of_quotes,
	SUM(qs.status IN ('won', 'lost')) AS decided,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) AS win_rate
FROM quote_summary qs
GROUP BY period
ORDER BY MIN(qs.quote_date);
```

| Period | Quotes | Decided | Win rate |
|---|---|---|---|
| Before 2025-03-01 | 2,170 | 2,170 | 42.21% |
| From 2025-03-01 | 1,652 | 1,552 | 35.50% |

- **Confirmed:** the win rate fell **6.7 pp (42.2% → 35.5%)** right at the price change, a relative drop of about 16% (roughly 1 in 6 deals that would have been won before were lost).
- The yearly view slightly understated the drop (~6 pp) because 2025 mixes two months of old prices.
- **Check:** the 100-quote gap between quotes and decided in the "after" period is exactly the 100 pending quotes, so they were correctly excluded.

---

# Phase 5: Customers, reps and pricing

Queries are saved in `queries/02_customers.sql`, `queries/03_reps_and_pipeline.sql` and `queries/04_pricing_and_margin.sql`.

## Q5: Top 10 customers by revenue

**Method:** revenue per customer from `sales_lines` (master customer IDs), grouped by `customer_id` and name. Share of total uses a subquery for the grand total. The query is wrapped in a CTE so the outer query can add a running total with a window function, `SUM(share_of_total) OVER (ORDER BY total_revenue DESC)`, which gives the cumulative share of the top 3 and top 10 in one result.

```sql
WITH customer_revenue AS (
	SELECT
		sl.customer_name,
		sl.customer_id,
		SUM(sl.revenue) AS total_revenue,
		ROUND(SUM(sl.revenue) * 100.0 / (SELECT SUM(revenue) FROM sales_lines), 2) AS share_of_total
	FROM sales_lines sl
	GROUP BY sl.customer_name, sl.customer_id
)
SELECT
	customer_name,
	customer_id,
	total_revenue,
	share_of_total,
	ROUND(SUM(share_of_total) OVER (ORDER BY total_revenue DESC), 2) AS cumulative_share
FROM customer_revenue
ORDER BY total_revenue DESC
LIMIT 10;
```

| Rank | Customer | ID | Revenue | Share | Cumulative |
|---|---|---|---|---|---|
| 1 | Semillas Los Álamos S.A. | 49 | $2,544,450.86 | 8.27% | 8.27% |
| 2 | Servicios Petroleros Coirón Coop. Ltda. | 10 | $2,406,497.28 | 7.82% | 16.09% |
| 3 | Minera Tala S.A. | 81 | $2,208,317.50 | 7.18% | 23.27% |
| 4 | Alimentos Pehuén S.R.L. | 24 | $1,735,795.06 | 5.64% | 28.91% |
| 5 | Constructora Piedra Negra S.A. | 78 | $1,406,520.21 | 4.57% | 33.48% |
| 6 | Gas Salinas S.A. | 75 | $1,340,624.40 | 4.36% | 37.84% |
| 7 | Minerales Espinillo S.A. | 33 | $1,017,653.59 | 3.31% | 41.15% |
| 8 | Agropecuaria Colorado S.A. | 66 | $660,492.61 | 2.15% | 43.30% |
| 9 | Alimentos Ñandú S.R.L. | 57 | $550,657.69 | 1.79% | 45.09% |
| 10 | Lácteos Cerro Chato S.A. | 109 | $546,662.42 | 1.78% | 46.87% |

**Comparison: raw data (no cleaning)**

Same ranking built from the raw tables (`orders`, `customers`, `order_items`), so it includes both the 14 duplicate order lines and the duplicate customer IDs.

```sql
SELECT
	customer_name, o.customer_id,
	SUM(oi.quantity * oi.unit_price) AS total_revenue
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY customer_name, o.customer_id
ORDER BY total_revenue DESC
LIMIT 10;
```

| Rank | Customer | ID | Revenue (raw) |
|---|---|---|---|
| 1 | Semillas Los Álamos S.A. | 49 | $2,544,450.86 |
| 2 | Servicios Petroleros Coirón Coop. Ltda. | 10 | $2,406,497.28 |
| 3 | Minera Tala S.A. | 81 | $2,208,317.50 |
| 4 | Constructora Piedra Negra S.A. | 78 | $1,406,520.21 |
| 5 | Gas Salinas S.A. | 75 | $1,340,624.40 |
| 6 | Minerales Espinillo S.A. | 33 | $1,024,259.59 |
| 7 | Alimentos Pehuén S.R.L. | 24 | $943,984.99 |
| 8 | Alimentos Pehuén SRL | 121 | $798,377.45 |
| 9 | Agropecuaria Colorado S.A. | 66 | $669,326.97 |
| 10 | Alimentos Ñandú S.R.L. | 57 | $550,657.69 |

**Findings**

- **Revenue is concentrated in a few customers:** the top 3 bring in 23.3% of revenue and the top 10 bring in 46.9%, from 116 customers who placed at least one order (120 customers after cleaning, 4 of whom never ordered; see Q8). About 8.6% of buying customers make up almost half the revenue. This mirrors the product concentration in Q3 (top 3 products = ~38%).
- **Cleaning changed the ranking:** before cleaning, Alimentos Pehuén appeared as two separate accounts (IDs 24 and 121) ranked 7th and 8th. Merged, it is the **4th-largest customer** ($1.74M), so the raw data hid one of the company's most important relationships.
- **Knock-on effect:** the duplicate ID took a top-10 spot, pushing Lácteos Cerro Chato (#10 after cleaning) out of the raw top 10.
- **Duplicate order lines also inflated some totals** in the raw version (e.g. Minerales Espinillo +$6,606, Agropecuaria Colorado +$8,834, Pehuén +$6,567), small amounts, but enough to show that both cleaning steps matter.

## Q6: Revenue by region and industry

**Method:** revenue and share of total from `sales_lines`, grouped by region, by industry, and by both (`GROUP BY sl.industry, sl.region`). Share of total uses a subquery for the grand total.

```sql
SELECT
	sl.industry, sl.region,
	SUM(sl.revenue) AS total_revenue,
	ROUND(SUM(sl.revenue) * 100.0 / (SELECT SUM(revenue) FROM sales_lines), 2) AS share_of_total
FROM sales_lines sl
GROUP BY sl.industry, sl.region
ORDER BY total_revenue DESC;
```

**By region**

| Region | Revenue | Share |
|---|---|---|
| Centro | $9,531,499.05 | 30.98% |
| AMBA | $7,046,243.14 | 22.90% |
| Patagonia | $6,886,942.19 | 22.38% |
| Norte | $3,970,248.87 | 12.90% |
| Cuyo | $3,336,618.46 | 10.84% |

**By industry**

| Industry | Revenue | Share |
|---|---|---|
| Oil & Gas | $6,096,605.60 | 19.81% |
| Mining | $5,714,910.66 | 18.57% |
| Food & Beverage | $5,092,608.15 | 16.55% |
| Agriculture | $5,034,571.47 | 16.36% |
| Construction | $3,152,328.81 | 10.24% |
| Manufacturing | $2,852,592.93 | 9.27% |
| Unknown | $1,450,943.41 | 4.72% |
| Water Utilities | $1,376,990.68 | 4.47% |

**Region × industry: top combinations**

| Industry | Region | Revenue | Share |
|---|---|---|---|
| Agriculture | Centro | $3,712,601.73 | 12.07% |
| Oil & Gas | Patagonia | $2,715,506.77 | 8.82% |
| Food & Beverage | Centro | $2,540,454.14 | 8.26% |
| Oil & Gas | AMBA | $2,406,497.28 | 7.82% |
| Mining | Norte | $2,370,987.70 | 7.71% |
| Mining | Patagonia | $1,987,912.80 | 6.46% |
| Construction | Patagonia | $1,759,471.67 | 5.72% |

- 31 of the 40 possible region × industry combinations have revenue (e.g. no Water Utilities in Patagonia or Norte).

**Findings**

- **Industry revenue is spread out at the top:** Oil & Gas, Mining, Food & Beverage and Agriculture each bring in 16–20% (71% together). Unlike customers and products, no single industry dominates.
- **Centro leads regions (31%), and Centro, AMBA and Patagonia together make up 76%.** Patagonia matches AMBA's revenue with one rep instead of two (to revisit in Q7).
- **Regional revenue follows each region's economy:**
  - **Centro** is driven by Agriculture: Agriculture × Centro is the largest single combination (12.1%), and about three quarters of all Agriculture revenue comes from Centro.
  - **Patagonia** is almost entirely Oil & Gas, Mining and Construction (~21% of its 22.4%).
  - **Norte** is mostly Mining (7.7% of its 12.9%).
- **…except where one large customer distorts the picture:** Oil & Gas × AMBA ($2,406,497.28) is exactly the revenue of Servicios Petroleros Coirón (customer 10, #2 overall), so AMBA's Oil & Gas revenue is a single account, not a cluster of oil customers.

**Customers with no industry ("Unknown")**

| Region | Share of total revenue |
|---|---|
| Cuyo | 2.15% |
| AMBA | 1.32% |
| Patagonia | 1.18% |
| Norte | 0.07% |
| Centro | none |

- "Unknown" is 4.7% of revenue ($1.45M), more than Water Utilities.
- **A top-10 customer has no industry recorded:** Unknown × Cuyo ($660,492.61) is entirely Agropecuaria Colorado (customer 66, #8 overall). Confirmed with `SELECT … FROM customers_clean WHERE region = 'Cuyo' AND industry = 'Unknown'`, which returns only this customer. Its name ("Agropecuaria") points to Agriculture.
- **Kept as "Unknown"** in the analysis: reassigning it would be a guess, not the data.
- **Recommendation:** make industry a required field when a customer is created and correct this record at the source, the same kind of process gap as the duplicate customers (Phase 2, Step 4).

## Q7: Sales rep performance

**Method:** one row per rep from `quote_summary`, joined to `sales_reps` for region and hire date. Win rate uses decided quotes only (as in Q4). `avg_days` skips pending quotes automatically, because they have no decision date (checked: pending = 100 quotes, 0 with `days_to_decide`). To separate rep performance from the March 2025 price change, the win rate and average discount are also split before and after 2025-03-01, using conditions inside `SUM` and `AVG(CASE WHEN … END)`.

```sql
SELECT
	qs.rep_name, sr.region, sr.hire_date,
	COUNT(qs.quote_id) AS quotes_handled,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) AS win_rate,
	ROUND(AVG(qs.days_to_decide), 1) AS avg_days,
	ROUND(AVG(qs.discount), 2) AS avg_discount,
	ROUND(100 * AVG(qs.quote_date >= '2025-03-01'), 1) AS pct_after_price_change,
	ROUND(100.0 * SUM(qs.status = 'won' AND qs.quote_date < '2025-03-01')
	            / SUM(qs.status IN ('won', 'lost') AND qs.quote_date < '2025-03-01'), 2) AS win_rate_before,
	ROUND(100.0 * SUM(qs.status = 'won' AND qs.quote_date >= '2025-03-01')
	            / SUM(qs.status IN ('won', 'lost') AND qs.quote_date >= '2025-03-01'), 2) AS win_rate_after,
	ROUND(AVG(CASE WHEN qs.quote_date < '2025-03-01' THEN qs.discount END), 2) AS discount_before,
	ROUND(AVG(CASE WHEN qs.quote_date >= '2025-03-01' THEN qs.discount END), 2) AS discount_after
FROM quote_summary qs
JOIN sales_reps sr ON qs.rep_name = sr.rep_name
GROUP BY qs.rep_name, sr.region, sr.hire_date
ORDER BY quotes_handled DESC;
```

| Rep | Region | Hired | Quotes | Win rate | Avg days | Avg discount | % quotes after change |
|---|---|---|---|---|---|---|---|
| Tomás Lescano | Patagonia | 2019-11-04 | 842 | 34.87% | 21.3 | 8.48% | 46.8% |
| Diego Arrieta | Centro | 2018-02-05 | 770 | 43.33% | 26.2 | 14.08% | 32.1% |
| Camila Ortiz | Norte | 2022-01-10 | 481 | 38.19% | 23.9 | 15.03% | 42.6% |
| Martín Ferreyra | AMBA | 2019-04-01 | 458 | 44.25% | 17.5 | 8.84% | 40.0% |
| Lucía Benítez | AMBA | 2021-08-16 | 426 | 39.00% | 23.1 | 11.15% | 43.2% |
| Valentina Sosa | Centro | 2024-03-04 | 425 | 33.17% | 30.4 | 12.15% | 57.4% |
| Nicolás Quiroga | Cuyo | 2020-06-01 | 420 | 44.06% | 39.8 | 10.05% | 46.4% |

**Before vs after the price change**

| Rep | Win rate before | Win rate after | Change | Discount before | Discount after |
|---|---|---|---|---|---|
| Diego Arrieta | 42.64% | 44.93% | **+2.3 pp** | 14.09% | 14.06% |
| Lucía Benítez | 40.50% | 36.93% | −3.6 pp | 11.08% | 11.23% |
| Tomás Lescano | 37.50% | 31.73% | −5.8 pp | 8.10% | 8.90% |
| Martín Ferreyra | 46.55% | 40.68% | −5.9 pp | 9.05% | 8.53% |
| Nicolás Quiroga | 48.00% | 39.11% | −8.9 pp | 10.07% | 10.02% |
| Camila Ortiz | 42.03% | 32.83% | −9.2 pp | 14.69% | 15.48% |
| Valentina Sosa | 41.44% | 26.36% | **−15.1 pp** | 12.06% | 12.21% |

**Findings**

- **The overall table is misleading on its own:** reps with more quotes after March 2025 look worse simply because everyone won less after the price increase (Q4). The before/after split compares reps within the same pricing period.
- **Valentina Sosa (lowest overall win rate) is the newest rep and the most exposed to the price change** (57.4% of her quotes came after it). Before the change she won at a normal rate (41.4%), but after it she dropped 15.1 pp, far more than anyone else.
- **Diego Arrieta is the only rep whose win rate rose after the price change (+2.3 pp)**, while the other Centro rep, Valentina, fell the most.
- **Discounting doesn't explain the differences:** every rep's average discount stayed within about 1 pp before and after (Diego: 14.09% → 14.06%). This confirms Phase 3 at rep level: no rep offset the higher prices with bigger discounts.
- **High discounts didn't protect win rates:** Camila Ortiz gives the highest discount (~15%) but her win rate still fell 9.2 pp (see Q10).
- **Tomás Lescano is below average in both periods** (37.5% → 31.7%), so his low win rate isn't about timing. As Patagonia's only rep, with the most quotes, workload or a harder market (Oil & Gas, Mining) are possible explanations. Not tested.
- **Martín Ferreyra and Nicolás Quiroga are strong in both periods.** Nicolás had the highest win rate before the change (48.0%) but is by far the slowest to close (39.8 days); Martín is the fastest (17.5 days).

**Diego vs Valentina (Centro)**

```sql
SELECT
	qs.rep_name,
	CASE WHEN qs.quote_date < '2025-03-01' THEN 'Before' ELSE 'After' END AS period,
	COUNT(*) AS quotes,
	COUNT(DISTINCT qs.customer_name) AS customers,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) AS win_rate
FROM quote_summary qs
WHERE qs.rep_name IN ('Diego Arrieta', 'Valentina Sosa')
GROUP BY qs.rep_name, period;
```

| Rep | Period | Months | Quotes | Quotes/month | Customers | Win rate |
|---|---|---|---|---|---|---|
| Diego Arrieta | Before | 26 | 523 | ~20 | 28 | 42.64% |
| Diego Arrieta | After | 16 | 247 | ~15 | 31 | 44.93% |
| Valentina Sosa | Before | 12 | 181 | ~15 | 28 | 41.44% |
| Valentina Sosa | After | 16 | 244 | ~15 | 34 | 26.36% |

- **Raw counts are misleading because the periods differ in length** (Diego's "before" is 26 months; Valentina's is 12, since she was hired in March 2024). Per month, **Valentina's volume stayed flat (~15) while Diego's fell by about a quarter (~20 → ~15).**
- **Both reps quote roughly the same number of customers (~30)**, so Centro's customers don't appear to have been divided between them.
- **Most likely reading:** after the price change, Diego quoted less and won more, becoming more selective, while Valentina kept the same pace and her win rate dropped. This is an interpretation, not proven.

**Before calling anyone a weak performer:** timing (hire date and exposure to the price change) explains part of the differences, so the before/after split is the fairer comparison.

## Q8: Repeat buyers

**Method:** a CTE, `customer_summary`, builds one row per customer from `sales_lines`: number of orders, first order, last order and revenue. Orders use `COUNT(DISTINCT order_id)` because `sales_lines` has one row per order line, so a plain `COUNT` would count a multi-product order several times. The outer query groups customers into order-frequency bands with `CASE WHEN` and calculates each band's share of customers and revenue. The CTE will be reused in Phase 6.

```sql
WITH customer_summary AS (
	SELECT
		sl.customer_id, sl.customer_name,
		COUNT(DISTINCT sl.order_id) AS number_of_orders,
		MIN(sl.order_date) AS first_order,
		MAX(sl.order_date) AS last_order,
		SUM(sl.revenue) AS revenue
	FROM sales_lines sl
	GROUP BY sl.customer_id, sl.customer_name
)
SELECT
	CASE WHEN number_of_orders = 1 THEN '1 order'
	     WHEN number_of_orders BETWEEN 2 AND 5 THEN '2–5 orders'
	     WHEN number_of_orders BETWEEN 6 AND 15 THEN '6–15 orders'
	     ELSE '16+ orders' END AS customer_type,
	COUNT(*) AS customers,
	SUM(revenue) AS total_revenue,
	ROUND(SUM(revenue) * 100.0 / (SELECT SUM(revenue) FROM customer_summary), 2) AS share_of_revenue,
	ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM customer_summary), 1) AS share_of_customers
FROM customer_summary
GROUP BY customer_type
ORDER BY MIN(number_of_orders);
```

**Repeat vs one-time**

| Type | Customers | Revenue | Share of revenue |
|---|---|---|---|
| One-time (1 order) | 6 | $84,329.85 | 0.27% |
| Repeat (2+ orders) | 110 | $30,687,221.86 | 99.73% |

**By order frequency**

| Orders | Customers | Share of customers | Revenue | Share of revenue |
|---|---|---|---|---|
| 1 | 6 | 5.2% | $84,329.85 | 0.27% |
| 2–5 | 25 | 21.6% | $1,361,389.65 | 4.42% |
| 6–15 | 56 | 48.3% | $8,454,025.20 | 27.47% |
| 16+ | 29 | 25.0% | $20,871,807.01 | **67.83%** |

- **Customer base:** 116 customers placed at least one order (120 in customers_clean, so 4 never ordered).
- **Updated after merging customer 124 into 5** (Phase 6, Q11): customer 5 now has 22 orders, so it stays in the 16+ band and the 6–15 band loses one customer (57 → 56).

**Findings**

- **Almost every customer is a repeat buyer:** 110 of 116 (95%), bringing in 99.7% of revenue. This is typical for B2B industrial equipment over 3.5 years (parts, expansions and maintenance contracts; Annual Maintenance is the #1 product in Q3), so "repeat vs one-time" alone doesn't separate customers much.
- **Revenue follows buying frequency:** the 29 customers who ordered 16+ times (a quarter of customers) bring in **two thirds of revenue (67.8%)**, while the 31 customers with 5 orders or fewer (27%) bring in under 5% combined.
- **Connects to Q5:** revenue is concentrated in a small group of frequent, high-value customers, which makes keeping them a priority.

## Q9: Gross margin by category

**Method:** revenue, gross profit and gross margin (total gross profit ÷ total revenue) per category from `sales_lines`. Three `RANK()` window functions rank each category by revenue, profit and margin, so the three lists can be compared in one row per category.

```sql
SELECT
	sl.category,
	SUM(sl.revenue) AS total_revenue,
	SUM(sl.gross_profit) AS total_profit,
	ROUND(SUM(sl.gross_profit) * 100.0 / SUM(sl.revenue), 2) AS gross_margin,
	RANK() OVER (ORDER BY SUM(sl.revenue) DESC) AS revenue_rank,
	RANK() OVER (ORDER BY SUM(sl.gross_profit) DESC) AS profit_rank,
	RANK() OVER (ORDER BY SUM(sl.gross_profit) * 1.0 / SUM(sl.revenue) DESC) AS margin_rank
FROM sales_lines sl
GROUP BY sl.category
ORDER BY total_revenue DESC;
```

| Category | Revenue | Gross profit | Margin | Revenue rank | Profit rank | Margin rank | Share of revenue | Share of profit |
|---|---|---|---|---|---|---|---|---|
| Fans & Blowers | $6,342,273.96 | $1,911,553.96 | 30.14% | 1 | 2 | 6 | 20.6% | 18.6% |
| Ducting | $6,279,202.38 | $1,502,316.38 | 23.93% | 2 | 3 | 7 | 20.4% | 14.7% |
| Services | $5,077,495.39 | $2,610,955.39 | 51.42% | 3 | 1 | 1 | 16.5% | 25.5% |
| Controls & Sensors | $3,961,363.39 | $1,408,363.39 | 35.55% | 4 | 4 | 2 | 12.9% | 13.7% |
| Pumps | $3,843,265.39 | $1,179,885.39 | 30.70% | 5 | 5 | 4 | 12.5% | 11.5% |
| Filtration | $3,521,202.41 | $1,065,522.41 | 30.26% | 6 | 6 | 5 | 11.4% | 10.4% |
| Solar Pumping | $1,746,748.79 | $571,148.79 | 32.70% | 7 | 7 | 3 | 5.7% | 5.6% |

- Shares of revenue and profit calculated from the totals ($30,771,551.71 revenue, $10,249,745.71 gross profit).
- **Check:** $10.25M profit ÷ $30.77M revenue = 33.3%, matching the overall gross margin in Q1.

**Findings**

- **The top revenue category is not the most profitable.** Services ranks 3rd by revenue but 1st by both profit and margin (51.4%): it earns **a quarter of all gross profit on a sixth of revenue**. About 90% of Services is the Annual Maintenance contract (Q3), so one product line is the company's main profit engine.
- **The two largest categories by revenue have the two lowest margins:** Fans & Blowers (30.1%, rank 6) and Ducting (23.9%, rank 7). Their volume keeps them in the top 3 by profit, but each dollar of their sales earns less than in any other category.
- **Ducting is the clearest mismatch:** 20.4% of revenue but only 14.7% of profit.
- **Controls & Sensors has the 2nd-highest margin (35.6%) but ranks 4th by revenue**, the clearest opportunity to grow profit without relying on volume.
- **Solar Pumping is the smallest category but 3rd by margin (32.7%):** a small but reasonably profitable niche.

## Q10: Discount and win rate

**Method:** quotes grouped into discount bands with `CASE WHEN` (each `WHEN` gives only the upper limit, since conditions are checked in order). Win rate uses decided quotes only (as in Q4), and `decided` shows the sample behind each win rate. Bands are sorted with `ORDER BY MIN(discount)`. Minimum discount is 0.0%, so no quotes were priced above list.

```sql
SELECT
	CASE
		WHEN qs.discount < 5 THEN '0-5%'
		WHEN qs.discount < 10 THEN '5-10%'
		WHEN qs.discount < 15 THEN '10-15%'
		WHEN qs.discount < 20 THEN '15-20%'
		ELSE '20%+' END AS discount_band,
	COUNT(*) AS number_of_quotes,
	SUM(qs.status IN ('won', 'lost')) AS decided,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) AS win_rate
FROM quote_summary qs
GROUP BY discount_band
ORDER BY MIN(qs.discount);
```

| Discount band | Quotes | Decided | Win rate |
|---|---|---|---|
| 0–5% | 313 | 308 | 30.52% |
| 5–10% | 1,208 | 1,176 | 35.80% |
| 10–15% | 1,462 | 1,420 | 39.15% |
| 15–20% | 711 | 693 | 49.06% |
| 20%+ | 128 | 125 | 44.80% |

- The 100 pending quotes are spread across all bands (5 / 32 / 42 / 18 / 3), so none is noticeably affected.

**Findings**

- **Higher discounts are associated with higher win rates:** the win rate rises steadily from 30.5% at 0–5% to 49.1% at 15–20%, almost 19 pp. Above 15% discount, roughly 45–49% of quotes are won.
- **The win rate stops rising after about 15%.** The 20%+ band (44.8%) is slightly below 15–20%, but it has only 125 decided quotes, so a gap that size could easily be chance (roughly ±8–9 pp). Going beyond 20% doesn't appear to win more deals.
- **Association, not cause:** this seems to contradict Q7, where Camila Ortiz gave the highest discounts (~15%) and her win rate still fell 9.2 pp after the price change. Both can be true: across all quotes, bigger discounts go with more wins, but a rep who discounts heavily isn't necessarily a better closer, and large discounts may cluster in deals that are easier to win anyway (e.g. bigger orders or certain categories).
- **There's a trade-off between volume and margin:** a bigger discount wins more often but earns less per deal. Moving from the 10–15% band to 15–20% raises the win rate by about 10 pp but gives up about 5 pp of price on every deal.

**Check: before and after the price change**

Added `win_rate_before` and `win_rate_after` columns (same formula as Q7, with the date condition inside each `SUM`):

| Discount band | Win rate before | Win rate after | Change |
|---|---|---|---|
| 0–5% | 32.63% | 27.12% | −5.5 pp |
| 5–10% | 38.43% | 32.27% | −6.2 pp |
| 10–15% | 42.28% | 34.84% | −7.4 pp |
| 15–20% | 50.74% | 46.71% | −4.0 pp |
| 20%+ | 53.16% | 30.43% | −22.7 pp* |

- **The pattern holds in both periods:** from 0% to 20% discount, the win rate rises steadily before and after the price change, so the link between discount and winning isn't a side effect of timing.
- **The win rate fell in every band after the price change**, consistent with Q4.
- **Before the change, 20%+ was the best band (53.2%)**; the dip in the combined result comes from the after period.
- **15–20% was the most resilient band** (−4.0 pp).
- *The 20%+ band has only 125 decided quotes in total, so its after-period win rate rests on a very small sample and isn't reliable.

---

# Phase 6: Advanced analysis

Queries are saved in `queries/05_advanced.sql`.

## Q11: Top 3 customers in each region

**Method:** a CTE, `customer_ranks`, builds one row per customer from `sales_lines` with their total revenue. Two window functions are added on top of the `GROUP BY`:
- `RANK() OVER (PARTITION BY region ORDER BY SUM(revenue) DESC)` ranks customers within their own region, restarting at 1 for each region.
- `SUM(SUM(revenue)) OVER (PARTITION BY region)` puts the region's total revenue on every row. The inner `SUM` is each customer's total from the `GROUP BY`; the outer `SUM ... OVER` adds those up across the region.

The outer query keeps ranks 1–3 and calculates each customer's share of their region's revenue.

- **Why a CTE:** SQL calculates `WHERE` before window functions, so `region_rank` doesn't exist yet when `WHERE` runs in the same query. The CTE builds the ranks first, then the outer query filters them.
- **Why not `LIMIT 3`:** `LIMIT` cuts the whole result after 3 rows (top 3 overall, all from one region), not 3 per region.
- **Why `ORDER BY SUM(revenue)` and not `total_revenue`:** the alias isn't available yet inside the same `SELECT`.
- **Check:** each `customer_id` appears in only one region, so no customer is split across regions. Region totals match Q6.

```sql
WITH customer_ranks AS (
	SELECT
		sl.region, sl.customer_name, sl.customer_id,
		SUM(sl.revenue) AS total_revenue,
		RANK() OVER (PARTITION BY sl.region ORDER BY SUM(sl.revenue) DESC) AS region_rank,
		SUM(SUM(sl.revenue)) OVER (PARTITION BY sl.region) AS region_total
	FROM sales_lines sl
	GROUP BY sl.region, sl.customer_name, sl.customer_id
)
SELECT *,
	ROUND((total_revenue / region_total) * 100, 2) AS percentage_total
FROM customer_ranks
WHERE region_rank <= 3;
```

| Region | Rank | Customer | ID | Revenue | Share of region |
|---|---|---|---|---|---|
| AMBA | 1 | Servicios Petroleros Coirón Coop. Ltda. | 10 | $2,406,497.28 | 34.15% |
| AMBA | 2 | Estructuras Las Tunas S.R.L. | 14 | $466,985.49 | 6.63% |
| AMBA | 3 | Metales Espinillo S.A. | 38 | $285,400.11 | 4.05% |
| Centro | 1 | Semillas Los Álamos S.A. | 49 | $2,544,450.86 | 26.70% |
| Centro | 2 | Alimentos Pehuén S.R.L. | 24 | $1,735,795.06 | 18.21% |
| Centro | 3 | Bodegas Algarrobo S.A. | 11 | $544,593.73 | 5.71% |
| Cuyo | 1 | Agropecuaria Colorado S.A. | 66 | $660,492.61 | 19.80% |
| Cuyo | 2 | Lácteos Cerro Chato S.A. | 109 | $546,662.42 | 16.38% |
| Cuyo | 3 | Servicios Hídricos Quebracho Coop. Ltda. | 5 | $397,851.20 | 11.92% |
| Norte | 1 | Minera Tala S.A. | 81 | $2,208,317.50 | 55.62% |
| Norte | 2 | Alimentos Ñandú S.R.L. | 57 | $550,657.69 | 13.87% |
| Norte | 3 | Agropecuaria Coirón S.A. | 73 | $387,463.86 | 9.76% |
| Patagonia | 1 | Constructora Piedra Negra S.A. | 78 | $1,406,520.21 | 20.42% |
| Patagonia | 2 | Gas Salinas S.A. | 75 | $1,340,624.40 | 19.47% |
| Patagonia | 3 | Minerales Espinillo S.A. | 33 | $1,017,653.59 | 14.78% |

**Concentration by region**

| Region | Region revenue | #1 customer share | Top 3 combined share |
|---|---|---|---|
| Norte | $3,970,248.87 | 55.6% | 79.3% |
| AMBA | $7,046,243.14 | 34.2% | 44.8% |
| Centro | $9,531,499.05 | 26.7% | 50.6% |
| Patagonia | $6,886,942.19 | 20.4% | 54.7% |
| Cuyo | $3,336,618.46 | 19.8% | 48.1% |

**Findings**

**Norte and AMBA depend heavily on a single customer: Minera Tala generates ~56% of Norte's revenue and Servicios Petroleros Coirón ~34% of AMBA's, so losing either account would cause a major revenue drop. Cuyo and Patagonia are more balanced, with no customer above ~20%.**

- **Norte is the most exposed region:** one customer is more than half of its revenue, and the top 3 together are almost 80%.
- **AMBA:** the #1 customer brings in about 5× the revenue of the #2 and about 3× the #2 and #3 combined. This is the same account that makes up all of AMBA's Oil & Gas revenue (Q6).
- **Centro:** the #1 customer brings in slightly more than the #2 and #3 combined, but Centro's top 2 are both large ($2.5M and $1.7M), so its dependence is spread across two accounts rather than one.
- **Cuyo:** the #1 customer brings in about 1.7× the revenue of the #3. Before merging the duplicate customer (see data quality note below), Bodegas Espinillo appeared as #3.
- **Patagonia:** the #1 and #2 customers are nearly equal; the #3 is about 70% of the #1. No single customer dominates.
- **Across all regions,** the top 3 customers account for about 45–79% of their region's revenue.
- **Connects to Q5 and Q8:** revenue is concentrated in a few large, frequent customers overall, and this query shows that concentration is much stronger in some regions than others.

**Data quality: a fourth duplicate customer, found through this query**

- Customer 5 ("Servicios Hídricos Quebracho Coop. Ltda.") and customer 124 ("SERVICIOS HÍDRICOS QUEBRACHO COOP. LTDA.") are the same company, both in Cuyo. The pair was missed in Phase 2, Step 4 and spotted in the first run of this query, where they appeared as #4 ($316,084.00) and #13 ($81,767.20) in Cuyo.
- **Why it was missed:** SQLite's `LOWER()` only converts plain A–Z letters, so accented capitals stay uppercase (`SELECT LOWER('HÍDRICOS')` returns `hÍdricos`), and the normalized names didn't match. Details in Phase 2, Step 4.
- **Fixed in the cleaning step:** 124 now maps to 5 in `customer_map` and is excluded from `customers_clean`.
- **Checks after the fix:** `sales_lines` shows one row for customer 5 with 22 orders (16 + 6) and $397,851.20; `quote_summary` shows 49 quotes (33 + 16) and no separate row for 124.
- **Impact:** merged, customer 5 is **#3 in Cuyo (11.9%)**, pushing Bodegas Espinillo ($321,910.04) to #4, and Cuyo's top 3 share rises from 45.8% to 48.1%. The table above uses the merged data.
- **Other results rechecked:** Q5 top 10 unchanged (customer 5 is below #10); Q6 unchanged (both IDs are Water Utilities in Cuyo); Q8 customer counts updated (116 buying customers).

## Q12: Month-over-month and year-over-year revenue growth

**Method:** two CTEs on `sales_lines`, one nested inside the other.
- `revenue_growth`: one row per month (`GROUP BY month`) with revenue and number of orders (`COUNT(DISTINCT order_id)`, because `sales_lines` has one row per order line).
- `growth`: adds last month's revenue with `LAG(total_revenue, 1) OVER (ORDER BY month)` and the same month last year with `LAG(total_revenue, 12) OVER (ORDER BY month)`. No `PARTITION BY`, since this is one continuous timeline.
- The final query turns them into growth %: this month ÷ previous value − 1, × 100 (same formula as Q1).
- Each CTE only passes on the columns its `SELECT` lists, so `order_count` has to appear in every step.

**Check: no missing months.** `LAG` counts rows, not dates, so a missing month would shift the 12-row offset. The CTE returns 41 rows, exactly February 2023 to June 2026 (11 + 12 + 12 + 6 months), so "12 rows back" is always the same month last year. Spot check: February 2024's previous-year value is $191,286.01, which is February 2023's revenue.

```sql
WITH growth AS (
	WITH revenue_growth AS (
		SELECT
			sl.month,
			SUM(sl.revenue) AS total_revenue,
			COUNT(DISTINCT sl.order_id) AS order_count
		FROM sales_lines sl
		GROUP BY sl.month
	)
	SELECT
		month, total_revenue, order_count,
		LAG(total_revenue, 1) OVER (ORDER BY month) AS previous_month,
		LAG(total_revenue, 12) OVER (ORDER BY month) AS same_month_last_year
	FROM revenue_growth
)
SELECT
	month, total_revenue, previous_month, same_month_last_year,
	ROUND(100 * ((total_revenue / previous_month) - 1), 1) AS mom_growth,
	ROUND(100 * ((total_revenue / same_month_last_year) - 1), 1) AS yoy_growth,
	order_count
FROM growth;
```

| Month | Revenue | Orders | MoM | YoY |
|---|---|---|---|---|
| 2023-02 | $191,286.01 | 13 | | |
| 2023-03 | $343,611.46 | 19 | +79.6% | |
| 2023-04 | $670,510.45 | 29 | +95.1% | |
| 2023-05 | $764,813.63 | 39 | +14.1% | |
| 2023-06 | $726,761.29 | 29 | −5.0% | |
| 2023-07 | $309,472.59 | 22 | −57.4% | |
| 2023-08 | $833,356.12 | 42 | +169.3% | |
| 2023-09 | $574,845.17 | 42 | −31.0% | |
| 2023-10 | $510,314.80 | 32 | −11.2% | |
| 2023-11 | $870,272.00 | 43 | +70.5% | |
| 2023-12 | $814,443.65 | 38 | −6.4% | |
| 2024-01 | $530,128.36 | 29 | −34.9% | |
| 2024-02 | $388,344.96 | 22 | −26.7% | +103.0% |
| 2024-03 | $699,284.06 | 31 | +80.1% | +103.5% |
| 2024-04 | $567,675.49 | 32 | −18.8% | −15.3% |
| 2024-05 | $790,285.02 | 44 | +39.2% | +3.3% |
| 2024-06 | $362,515.38 | 21 | −54.1% | −50.1% |
| 2024-07 | $853,557.76 | 42 | +135.5% | +175.8% |
| 2024-08 | $815,278.34 | 37 | −4.5% | −2.2% |
| 2024-09 | $858,146.65 | 41 | +5.3% | +49.3% |
| 2024-10 | $999,830.21 | 52 | +16.5% | +95.9% |
| 2024-11 | $797,787.84 | 49 | −20.2% | −8.3% |
| 2024-12 | $1,130,674.66 | 55 | +41.7% | +38.8% |
| 2025-01 | $1,156,465.95 | 46 | +2.3% | +118.1% |
| 2025-02 | $582,005.40 | 33 | −49.7% | +49.9% |
| 2025-03 | $828,478.55 | 36 | +42.3% | +18.5% |
| 2025-04 | $629,766.07 | 30 | −24.0% | +10.9% |
| 2025-05 | $719,788.71 | 35 | +14.3% | −8.9% |
| 2025-06 | $688,918.26 | 33 | −4.3% | +90.0% |
| 2025-07 | $792,226.02 | 29 | +15.0% | −7.2% |
| 2025-08 | $349,138.36 | 21 | −55.9% | −57.2% |
| 2025-09 | $578,636.04 | 29 | +65.7% | −32.6% |
| 2025-10 | $911,301.39 | 45 | +57.5% | −8.9% |
| 2025-11 | $796,420.06 | 45 | −12.6% | −0.2% |
| 2025-12 | $1,651,062.45 | 61 | +107.3% | +46.0% |
| 2026-01 | $799,493.51 | 37 | −51.6% | −30.9% |
| 2026-02 | $558,782.88 | 25 | −30.1% | −4.0% |
| 2026-03 | $1,302,707.02 | 41 | +133.1% | +57.2% |
| 2026-04 | $909,299.54 | 35 | −30.2% | +44.4% |
| 2026-05 | $980,018.00 | 43 | +7.8% | +36.2% |
| 2026-06 | $1,133,847.60 | 40 | +15.7% | +64.6% |

- The first month has no MoM and the first 12 have no YoY, since there's nothing to compare with. January 2024 also has no YoY because the data starts in February 2023.

**Was the change from more orders or bigger orders?** Two periods compared with the same months a year earlier (sums of the monthly rows above; average order value = revenue ÷ orders):

| Period | Revenue | Orders | Avg order value |
|---|---|---|---|
| Jul–Nov 2024 | $4,324,600.80 | 221 | $19,568 |
| Jul–Nov 2025 | $3,427,721.87 | 169 | $20,282 |
| **Change** | **−20.7%** | **−23.5%** | **+3.6%** |
| Mar–Jun 2025 | $2,866,951.59 | 134 | $21,395 |
| Mar–Jun 2026 | $4,325,872.16 | 159 | $27,207 |
| **Change** | **+50.9%** | **+18.7%** | **+27.2%** |

**Findings**

**Month-over-month changes are dominated by seasonality and large one-off orders, so year-over-year is the better growth measure. Year over year, revenue grew from December 2024 to April 2025, fell from July to November 2025 (−21%) because of about a quarter fewer orders, possibly a delayed effect of the March 2025 price change, and has grown strongly from March to June 2026 (+51%), from both more orders (+19%) and larger orders (+27%).**

- **MoM is too noisy to judge the business:** it swings from −57% to +169%. In a B2B business, one or two large orders can move a whole month.
- **YoY removes seasonality:** February 2025 looks like a collapse month over month (−49.7%), but it actually grew 49.9% compared with February 2024. February is always low (Q2), so MoM mostly measures the time of year.
- **Single-month YoY still jumps around,** so the useful signal is runs of several months in the same direction.
- **Dec 2024 – Apr 2025, growth:** continues the strong 2024 (+33% revenue, Q1) and runs across the March 2025 price change.
- **Jul – Nov 2025, decline:** order size was roughly flat (+3.6%), but there were 23.5% fewer orders. This fits the drop in win rate after the price increase (42.2% → 35.5%, Q4), showing up in revenue a few months later. A second possible factor: Jul–Oct 2024 was unusually strong (YoY of +49% to +176%), so 2025 is compared with a high base. This query can't separate the two; Q18 will test the price-change effect directly.
- **Mar – Jun 2026, strong growth:** both more orders and larger orders. The larger order size answers part of the open question in Q1 (2026 average order value +17.7%, more than the price change explains); what makes orders larger is still to investigate (e.g. product mix, Solar Pumping in Q19).

## Q13: Cumulative revenue through each year

**Method:** one row per month from `sales_lines` (`GROUP BY year, month`), plus a running total that restarts each year:

- `SUM(SUM(revenue)) OVER (PARTITION BY year ORDER BY month)`. The inner `SUM` is each month's total from the `GROUP BY`; the outer `SUM ... OVER` adds up those monthly totals. Window functions run after `GROUP BY`, so the window works on monthly rows, not order lines.
- `PARTITION BY year` restarts the total every January; `ORDER BY month` turns the `SUM` into a running total (this month plus all earlier months of the same year). Without `ORDER BY`, every row would show the full-year total, as with `region_total` in Q11.
- **First attempt:** `SUM(revenue) OVER (...)` without the inner `SUM` gave small, random-looking numbers, because after grouping a bare `revenue` refers to a single order line, not the month's total.

**Checks:**
- Each year's first value equals that month's revenue (e.g. 2024-01, 2025-01, 2026-01).
- Each December equals the year's total in Q1: 2023 $6,609,687.17; 2024 $8,793,508.73; 2025 $9,684,207.26. June 2026 ($5,684,148.55) equals 2026's half-year total.

```sql
SELECT
	sl.year, sl.month,
	SUM(revenue) AS monthly_revenue,
	SUM(SUM(revenue)) OVER (PARTITION BY sl.year ORDER BY sl.month) AS cumulative_revenue
FROM sales_lines sl
GROUP BY sl.year, sl.month;
```

**Cumulative revenue by month (one column per year)**

| Month | 2023 | 2024 | 2025 | 2026 |
|---|---|---|---|---|
| Jan | | $530,128.36 | $1,156,465.95 | $799,493.51 |
| Feb | $191,286.01 | $918,473.32 | $1,738,471.35 | $1,358,276.39 |
| Mar | $534,897.47 | $1,617,757.38 | $2,566,949.90 | $2,660,983.41 |
| Apr | $1,205,407.92 | $2,185,432.87 | $3,196,715.97 | $3,570,282.95 |
| May | $1,970,221.55 | $2,975,717.89 | $3,916,504.68 | $4,550,300.95 |
| Jun | $2,696,982.84 | $3,338,233.27 | $4,605,422.94 | $5,684,148.55 |
| Jul | $3,006,455.43 | $4,191,791.03 | $5,397,648.96 | |
| Aug | $3,839,811.55 | $5,007,069.37 | $5,746,787.32 | |
| Sep | $4,414,656.72 | $5,865,216.02 | $6,325,423.36 | |
| Oct | $4,924,971.52 | $6,865,046.23 | $7,236,724.75 | |
| Nov | $5,795,243.52 | $7,662,834.07 | $8,033,144.81 | |
| Dec | $6,609,687.17 | $8,793,508.73 | $9,684,207.26 | |

**2025 vs 2024: how far ahead 2025 was**

| Month | 2025 cumulative | 2024 cumulative | 2025 ahead by |
|---|---|---|---|
| June | $4,605,422.94 | $3,338,233.27 | $1,267,189.67 |
| November | $8,033,144.81 | $7,662,834.07 | $370,310.74 |
| December | $9,684,207.26 | $8,793,508.73 | $890,698.53 |

- **Cross-check with Q12:** the lead shrank by $896,878.93 between June and November, exactly the gap between Jul–Nov 2024 and Jul–Nov 2025 revenue in Q12.

**Findings**

**January–June 2026 was the strongest first half of any year: $5.7M, 23% ahead of 2025, well beyond what the price change explains. 2026 started behind 2025 but overtook it in March. 2025 was ahead of 2024 all year, but its lead shrank from $1.27M in June to $0.37M in November, because 2024 earned more in July–November; a strong December 2025 brought the year to +10%.**

- **First half of each year:** $2.7M (2023), $3.3M (2024), $4.6M (2025), $5.7M (2026). Each year has been ahead of the one before by June.
- **Not just the price change:** January–June 2025 already included four months at the new price list (March–June), so the price increase explains only about 4% of 2026's 23% lead. The rest comes from more and larger orders (Q12).
- **2026 behind in January–February:** partly because January 2025 was unusually large ($1.16M).
- **Weak second half of 2025:** the same July–November dip found in Q12 (fewer orders after the price change), seen here as 2025's lead over 2024 shrinking.
- **Dashboard:** plot one line per year (month on the x-axis, year in the Legend) to show at a glance which year was ahead at any point.

*Data starts in February 2023 (no January) and ends in June 2026, so the 2023 line starts one month behind and the 2026 line covers January–June only.*

## Q14: Share of revenue from the top 20% of customers

**Method:** a CTE, `customer_quintile`, builds one row per customer from `sales_lines` with their total revenue, and `NTILE(5) OVER (ORDER BY SUM(revenue) DESC)` splits customers into five groups of roughly equal size, from highest revenue (1) to lowest (5). The outer query groups by quintile and calculates each group's customers, revenue and share of total revenue (grand total from a subquery on the CTE, as in Q8).

- **116 buying customers don't divide evenly by 5,** so `NTILE` gives the extra customer to the first group: 24 in quintile 1, 23 in each of the others.
- **First attempt:** `ORDER BY sl.revenue` (without `SUM`) inside the `OVER` sorted customers by a single order line instead of their total, so the groups looked random (the #1 customer landed in quintile 3). Ordering by `SUM(sl.revenue)` fixed it.
- **Checks:** customers add up to 116, revenue to $30,771,551.71 and shares to 100%. Sorted by revenue, the quintile numbers never mix (all 1s, then all 2s, and so on).

```sql
WITH customer_quintile AS (
	SELECT
		sl.customer_id, sl.customer_name,
		SUM(sl.revenue) AS total_revenue,
		NTILE(5) OVER (ORDER BY SUM(sl.revenue) DESC) AS quintile
	FROM sales_lines sl
	GROUP BY sl.customer_id, sl.customer_name
)
SELECT
	quintile, COUNT(*) AS number_of_customers,
	SUM(total_revenue) AS quintile_revenue,
	ROUND(((SUM(total_revenue) * 100) / (SELECT SUM(total_revenue) FROM customer_quintile)), 2) AS share_of_total
FROM customer_quintile
GROUP BY quintile
ORDER BY quintile;
```

| Quintile | Customers | Revenue | Share of revenue |
|---|---|---|---|
| 1 (top 20%) | 24 | $19,729,177.45 | **64.11%** |
| 2 | 23 | $5,290,702.62 | 17.19% |
| 3 | 23 | $3,027,003.72 | 9.84% |
| 4 | 23 | $2,057,293.20 | 6.69% |
| 5 (bottom 20%) | 23 | $667,374.72 | 2.17% |
| **Total** | **116** | **$30,771,551.71** | **100%** |

**Findings**

**The top 20% of customers (24 of 116) bring in 64% of revenue, while the bottom 40% (46 customers) bring in less than 9%. Revenue is heavily concentrated, a little below the common "80/20" pattern, so keeping the largest accounts, and reducing dependence on them, matters more than adding small ones.**

- **Top vs bottom:** the top 20% bring in about 30 times the revenue of the bottom 20% ($19.7M vs $0.67M), and about 7 times the revenue of the bottom 40% combined.
- **Concentration within the top group:** the top 10 customers alone bring in 46.9% (Q5). The other 14 customers in quintile 1 bring in 17.2%, about the same as all 23 customers in quintile 2 (17.2%).
- **Risk as well as opportunity:** at regional level the dependence is even sharper; in Norte a single customer is 56% of revenue (Q11). Losing one or two top accounts would hit revenue hard.
- **Suggested focus for sales:** protect the top 24 accounts with dedicated attention, and grow promising quintile 2 customers into the top group to spread the risk.
- **Open question:** the bottom 46 customers bring in under 9% of revenue. Whether they take a disproportionate share of the reps' time is tested in Q16 (customers who ask for many quotes but rarely buy).

## Q15: Customers who used to buy regularly but have gone quiet

**Definition of "gone quiet":** a customer is flagged when the time since their last order is much longer than their own usual gap between orders.

- **Usual gap (`avg_gap`):** (last order − first order) ÷ (number of orders − 1). There is one fewer gap than orders (3 orders have 2 gaps between them).
- **Days since last order:** measured from the end of the data (2026-06-30), not from today; otherwise every customer would look quiet.
- **Ratio:** days since last order ÷ usual gap. A ratio of 1 means the next order is just due; 2 means they've skipped about one expected order; 3 or more means two or more skipped orders, hard to explain as normal variation.

**Rules, and why:**
- **At least 5 orders,** so the customer has a real buying pattern and isn't a one-off. With fewer orders, the usual gap rests on one or two intervals and the ratio is meaningless (e.g. Minerales Jarilla: ratio 27.6 from 2 orders 8 days apart).
- **Ratio of 3 or more.** Chosen by counting customers in each ratio band (5+ orders only):

| Ratio | Customers |
|---|---|
| under 1.5 | 64 |
| 1.5–2 | 10 |
| 2–3 | 7 |
| 3–5 | 3 |
| 5+ | 7 |

No customer has a ratio between about 2.8 and 4.5, so a threshold of 3 is a natural break: nobody is "just over the line," and the 10 customers above it are clearly different from the rest. The 7 customers between 2 and 3 have skipped about one expected order and could serve as an early-warning watch list.

**Method:** a CTE, `customer_activity`, builds one row per customer from `sales_lines` with region, revenue, orders (`COUNT(DISTINCT order_id)`), first and last order, usual gap, days since last order and ratio. Dates are converted with `julianday()`, because SQLite stores dates as text and subtracting them directly gives wrong results. The ratio band query used to choose the threshold is kept in the file as a comment.

```sql
WITH customer_activity AS (
	SELECT
		sl.customer_id, sl.customer_name, sl.region,
		SUM(sl.revenue) AS total_revenue,
		COUNT(DISTINCT sl.order_id) AS order_count,
		MIN(sl.order_date) AS first_order,
		MAX(sl.order_date) AS last_order,
		ROUND(((julianday(MAX(sl.order_date)) - julianday(MIN(sl.order_date))) / (COUNT(DISTINCT sl.order_id) - 1)), 0) AS avg_gap,
		(julianday('2026-06-30') - julianday(MAX(sl.order_date))) AS days_since_last,
		ROUND(((julianday('2026-06-30') - julianday(MAX(sl.order_date))) /
			((julianday(MAX(sl.order_date)) - julianday(MIN(sl.order_date))) / (COUNT(DISTINCT sl.order_id) - 1))), 1) AS ratio
	FROM sales_lines sl
	GROUP BY sl.customer_id, sl.customer_name, sl.region
)
SELECT *
FROM customer_activity
WHERE order_count >= 5 AND ratio >= 3
ORDER BY ratio DESC;
```

| Customer | ID | Region | Revenue | Orders | Last order | Usual gap (days) | Days silent | Ratio |
|---|---|---|---|---|---|---|---|---|
| Energía Los Álamos S.A. | 47 | Centro | $386,901.78 | 19 | 2025-02-16 | 36 | 499 | 13.9 |
| Recursos Mineros Jarilla S.R.L. | 95 | Patagonia | $274,791.90 | 15 | 2025-03-02 | 47 | 485 | 10.4 |
| Metales Arroyo Seco S.R.L. | 87 | AMBA | $35,410.48 | 6 | 2024-05-18 | 91 | 773 | 8.5 |
| Constructora Viento Sur S.A. | 105 | AMBA | $193,620.84 | 10 | 2024-12-04 | 70 | 573 | 8.2 |
| Riego Tres Cerros S.R.L. | 77 | Centro | $99,431.35 | 8 | 2024-09-29 | 84 | 639 | 7.6 |
| Plásticos Molle S.R.L. | 1 | AMBA | $129,879.00 | 11 | 2025-06-12 | 65 | 383 | 5.9 |
| Servicios Petroleros Viento Sur S.R.L. | 17 | Patagonia | $108,240.60 | 9 | 2025-03-11 | 85 | 476 | 5.6 |
| Riego Piedra Negra Coop. Ltda. | 56 | Centro | $68,915.29 | 6 | 2025-02-28 | 104 | 487 | 4.7 |
| Minerales Viento Sur Coop. Ltda. | 100 | Cuyo | $235,454.80 | 15 | 2025-10-16 | 55 | 257 | 4.7 |
| Metalúrgica El Ceibo S.A. | 55 | AMBA | $78,686.24 | 7 | 2025-01-21 | 116 | 525 | 4.5 |
| **Total** | | | **$1,611,332.28** | | | | | |

**Checks:**
- **Duplicates:** none of the 10 is part of the four duplicate pairs from Phase 2, and the accent-safe name check found no other pairs, so none of them is still buying under another ID. (Before the merge, customer 5 would have looked silent for about 400 days, because its recent orders sat under ID 124.)
- **Revenue total:** 5.24% of all revenue.

**Follow-up: did they keep asking for quotes after the price change?** Quotes from these 10 customers dated from 2025-03-01, by status (`quote_summary`, filtered by name):

| Customer | Won | Lost | Pending |
|---|---|---|---|
| Energía Los Álamos S.A. | 0 | 5 | 0 |
| Plásticos Molle S.R.L. | 1 | 5 | 1 |
| Minerales Viento Sur Coop. Ltda. | 5 | 3 | 0 |
| Recursos Mineros Jarilla S.R.L. | 0 | 1 | 0 |
| Riego Piedra Negra Coop. Ltda. | 0 | 1 | 0 |
| Metales Arroyo Seco, Constructora Viento Sur, Riego Tres Cerros, Servicios Petroleros Viento Sur, Metalúrgica El Ceibo | no quotes | | |

**The 10 customers fall into three groups:**

| Group | Customers | Revenue |
|---|---|---|
| Kept asking for quotes but lost them | Energía Los Álamos, Plásticos Molle, Recursos Mineros Jarilla, Riego Piedra Negra | $860,487.97 |
| Stopped asking for quotes altogether | Metales Arroyo Seco, Constructora Viento Sur, Riego Tres Cerros, Servicios Petroleros Viento Sur, Metalúrgica El Ceibo | $515,389.51 |
| Kept buying after the price change, quiet since | Minerales Viento Sur | $235,454.80 |

**Findings**

**Ten regular customers (5+ orders) have gone quiet, silent for at least three times their usual gap between orders. Together they brought in $1.6M (5.2% of revenue). Six of them stopped buying in the three months around the March 2025 price change and never ordered at the new prices, and the most valuable, Energía Los Álamos ($387k, one of the top 20% of customers), has asked for 5 quotes since then and lost every one, which points to price as the likely reason.**

- **Timing:** 6 of the 10 placed their last order between December 2024 and March 2025, just before or as the new price list took effect (the two March orders were most likely quoted in February at the old prices). Two stopped well before (May and September 2024) and two after (June and October 2025).
- **Energía Los Álamos is the clearest case:** it used to order every 36 days and has been silent for 499. All 5 quotes since March 2025 were lost, so it is still interested but not buying.
- **Plásticos Molle also points to price:** 5 of its 7 quotes since March 2025 were lost (1 won, 1 still pending). The pending quote is an immediate chance to win it back.
- **Recursos Mineros Jarilla and Riego Piedra Negra** each lost one quote after March 2025. This fits the price explanation, but one quote is too little to be sure.
- **Five customers stopped asking for quotes altogether.** Two of them stopped in 2024, before the price change, so something else is behind those. For the other three, which stopped around the price change, the reason can't be seen in the data; they may have seen the new prices and not asked, but that is a guess.
- **Minerales Viento Sur is a different case:** it kept buying after the price change (5 quotes won, 3 lost) and only went quiet after October 2025, so the price change doesn't explain it.
- **Region:** spread out (AMBA 4, Centro 3, Patagonia 2, Cuyo 1), roughly in line with each region's number of customers, so no single territory stands out.
- **Suggested action for sales:** contact Energía Los Álamos and Plásticos Molle first (price-sensitive and still quoting), follow up the pending Plásticos Molle quote, and reach out to the five customers who stopped quoting to find out why.

## Q16: Customers who ask for many quotes but rarely buy

**Definition:** a customer with many quotes (a large share of the reps' work) and a low win rate (few of those quotes become orders).

- **Quote count:** all of the customer's quotes, including pending ones, because every quote takes rep time.
- **Win rate:** won ÷ decided quotes (won + lost), as in Q4, so pending quotes don't count as losses.

**Thresholds: at least 50 quotes and a win rate of 20% or less.** Chosen from the customer averages:

| | Average | Min | Max |
|---|---|---|---|
| Quotes per customer | 31.9 | 2 | 190 |
| Win rate | 38.5% | 0.0% | 66.7% |

- 50 quotes is about 1.6× the average customer; 20% is about half the average win rate.
- **The list is stable:** it stays the same 5 customers for any threshold between 30 and 50 quotes and between 20% and 35% win rate. It only changes at 80 quotes (1 customer left) or a 40% win rate (9 customers), so it doesn't depend on the exact cut-off.

**Method:** two CTEs, each with one row per customer, joined at the end.
- `customer_quotes` (from `quote_summary`): quote count, quotes won, win rate and region.
- `customer_revenue` (from `sales_lines`): total revenue.
- `LEFT JOIN` on customer name, so customers who quoted but never bought would still appear (with no revenue).
- **First attempt:** joining `quote_summary` directly to `sales_lines` before grouping paired every quote with every sales line of the same customer (e.g. 3 quotes × 4 sales lines = 12 rows). Wins and revenue were multiplied: more wins than quotes, and $22M revenue for a $208k customer. Aggregating each table separately first, then joining one row to one row, fixed it.
- **Rep is checked in a separate query:** in AMBA and Centro a customer can be quoted by two reps, so grouping the main query by rep split those customers across rows (Industrias Jarilla dropped from 78 to 51 quotes and Hídrica Las Tunas fell off the list).

```sql
WITH customer_quotes AS (
	SELECT
		qs.customer_name,
		COUNT(DISTINCT qs.quote_id) AS quote_count,
		SUM(qs.status = 'won') AS quotes_won,
		ROUND((100.0 * (SUM(qs.status = 'won')) / (SUM(qs.status IN ('won', 'lost')))), 1) AS win_rate,
		qs.region
	FROM quote_summary qs
	GROUP BY qs.customer_name, qs.region
),
customer_revenue AS (
	SELECT
		sl.customer_name,
		SUM(sl.revenue) AS total_revenue
	FROM sales_lines sl
	GROUP BY sl.customer_name
)
SELECT
	cq.*, cr.total_revenue
FROM customer_quotes cq
LEFT JOIN customer_revenue cr ON cq.customer_name = cr.customer_name
WHERE quote_count >= 50 AND win_rate <= 20
ORDER BY quote_count DESC;
```

| Customer | Region | Quotes | Won | Win rate | Revenue |
|---|---|---|---|---|---|
| Desarrollos Molle Coop. Ltda. | Patagonia | 108 | 14 | 13.3% | $208,017.06 |
| Industrias Jarilla S.R.L. | Centro | 78 | 10 | 13.3% | $98,707.57 |
| Petróleo Coirón S.A. | Patagonia | 73 | 9 | 12.5% | $125,025.43 |
| Lácteos Cardón S.A. | Norte | 70 | 9 | 12.9% | $125,931.85 |
| Hídrica Las Tunas S.A. | Centro | 64 | 11 | 18.3% | $155,095.31 |
| **Total** | | **393** | **53** | | **$712,777.22** |

**Share of rep work vs share of revenue**

| | These 5 customers | All customers | Share |
|---|---|---|---|
| Quotes | 393 | 3,822 | **10.3%** |
| Revenue | $712,777.22 | $30,771,551.71 | **2.3%** |
| Revenue per quote | ≈ $1,800 | ≈ $8,050 | about a quarter |

**By rep**

```sql
SELECT
	qs.customer_name, qs.rep_name,
	COUNT(*) AS quotes,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 1) AS win_rate
FROM quote_summary qs
WHERE qs.customer_name IN (
	'Desarrollos Molle Coop. Ltda.', 'Industrias Jarilla S.R.L.', 'Petróleo Coirón S.A.',
	'Lácteos Cardón S.A.', 'Hídrica Las Tunas S.A.'
)
GROUP BY qs.customer_name, qs.rep_name
ORDER BY qs.customer_name, quotes DESC;
```

| Customer | Rep | Quotes | Win rate |
|---|---|---|---|
| Desarrollos Molle Coop. Ltda. | Tomás Lescano | 108 | 13.3% |
| Petróleo Coirón S.A. | Tomás Lescano | 73 | 12.5% |
| Lácteos Cardón S.A. | Camila Ortiz | 70 | 12.9% |
| Industrias Jarilla S.R.L. | Diego Arrieta | 51 | 12.0% |
| Industrias Jarilla S.R.L. | Valentina Sosa | 27 | 16.0% |
| Hídrica Las Tunas S.A. | Diego Arrieta | 35 | 25.0% |
| Hídrica Las Tunas S.A. | Valentina Sosa | 29 | 10.7% |

- **Check:** the rep rows add up to each customer's total (Industrias Jarilla 51 + 27 = 78; Hídrica Las Tunas 35 + 29 = 64).

**Findings**

**Five customers ask for many quotes but rarely buy: they account for about 1 in 10 quotes the reps prepare (393 of 3,822) but only 2.3% of revenue, and win just 12–18% of the time, against an average of 38.5%. Each quote for them is worth about a quarter of an average quote, so reps should spend less time sending them repeated quotes and focus that time on higher-value quotes and customers who buy more often.**

- **Workload, not just win rate:** each of these customers asked for 64–108 quotes, two to three times the average customer (31.9).
- **Tomás Lescano carries most of the burden:** two of the five customers are his (Desarrollos Molle and Petróleo Coirón), 181 quotes, about 21% of all his quotes, with win rates of 12–13%. This supports the idea from Q7 that workload helps explain his below-average win rate (34.9%).
- **Diego vs Valentina:** they share two of these customers. At Hídrica Las Tunas, Diego wins far more often (25.0% vs 10.7%); at Industrias Jarilla, Diego sends almost twice as many quotes but Valentina wins slightly more often (16.0% vs 12.0%). Quoting more doesn't mean winning more, and who does better depends on the customer.
- **Suggested action for sales:** set a limit or a qualification step before re-quoting these customers (e.g. check the request is serious and large enough), and move the time saved to larger quotes and customers with higher win rates.
- **Not tested:** whether these customers' quotes were mostly after the March 2025 price change, when every customer's win rate fell (Q4). If so, part of their low win rate is the price change rather than the customer.

## Q17: Customer segmentation by recency, frequency and value (RFM)

**What RFM is:** a standard way to segment customers by three questions, each scored from 1 (worst) to 5 (best):

| Letter | Measure | Column |
|---|---|---|
| **R**ecency | Days since last order, measured from the end of the data (2026-06-30), not from today | `days_since_last` |
| **F**requency | Number of orders | `order_count` |
| **M**onetary | Total revenue | `total_revenue` |

**Method:** three chained CTEs.
- `customer_activity`: one row per customer from `sales_lines` with the three measures (same calculations as Q15, without the gap and ratio).
- `rfm_scores`: three `NTILE(5)` scores. `NTILE` gives 1 to the rows that come first, so each measure is sorted from worst to best. For F and M, small is worst (ascending). For R, a **large** number of days is worst, so it is sorted `DESC`.
- `rfm_segments`: names each customer's segment with `CASE WHEN`. Conditions are checked in order and the first match wins, so Champions comes first (a Champion also meets the Loyal rule).
- The final query groups by segment.
- **First attempt:** R was sorted ascending, so the most recent buyers got R = 1 (Minera Tala, 0 days) and the longest-silent got R = 5 (Minerales Cerro Chato, 841 days). Adding `DESC` fixed it.

**Segment rules**

| Segment | Rule | Meaning |
|---|---|---|
| Champions | R ≥ 4, F ≥ 4, M ≥ 4 | Buy often, spend a lot, bought recently |
| Loyal | R ≥ 3, F ≥ 4 | Regular buyers, still active, spend less than Champions |
| At Risk | R ≤ 2, F ≥ 3 | Used to buy regularly, but not recently |
| Recent | R ≥ 4, F ≤ 2 | Bought recently, but only a few times |
| Lost | R ≤ 2, F ≤ 2 | Bought rarely, and not recently |
| Others | everything else | In the middle (e.g. R = 3, F = 3) |

- Scores of 4–5 mean the top 40% of customers on that measure; 1–2 mean the bottom 40%. These are common starting rules, not fixed ones.
- **"Recent" instead of "New":** this group includes customers who have bought since 2023 but rarely (e.g. Industrias Colorado, Hídrica Colorado). RFM can't tell new customers from long-standing small ones, so "Recent" is the more accurate label.
- In days, R ≤ 2 means no order for at least 104 days.

```sql
WITH customer_activity AS (
	SELECT
		sl.customer_id, sl.customer_name,
		(julianday('2026-06-30') - julianday(MAX(sl.order_date))) AS days_since_last,
		COUNT(DISTINCT sl.order_id) AS order_count,
		SUM(sl.revenue) AS total_revenue
	FROM sales_lines sl
	GROUP BY sl.customer_id, sl.customer_name
),
rfm_scores AS (
	SELECT
		customer_id, customer_name, days_since_last, order_count, total_revenue,
		NTILE(5) OVER (ORDER BY days_since_last DESC) AS r_score,
		NTILE(5) OVER (ORDER BY order_count) AS f_score,
		NTILE(5) OVER (ORDER BY total_revenue) AS m_score
	FROM customer_activity
),
rfm_segments AS (
	SELECT *,
		CASE
			WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
			WHEN r_score >= 3 AND f_score >= 4 THEN 'Loyal'
			WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
			WHEN r_score >= 4 AND f_score <= 2 THEN 'Recent'
			WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
			ELSE 'Others'
		END AS segment
	FROM rfm_scores
)
SELECT
	segment,
	COUNT(*) AS customers,
	SUM(total_revenue) AS segment_revenue,
	ROUND(SUM(total_revenue) * 100.0 / (SELECT SUM(total_revenue) FROM rfm_segments), 2) AS share_of_revenue
FROM rfm_segments
GROUP BY segment
ORDER BY segment_revenue DESC;
```

| Segment | Customers | Share of customers | Revenue | Share of revenue |
|---|---|---|---|---|
| Champions | 26 | 22.4% | $19,116,170.86 | **62.12%** |
| At Risk | 21 | 18.1% | $3,732,135.05 | 12.13% |
| Loyal | 10 | 8.6% | $3,232,446.69 | 10.50% |
| Others | 19 | 16.4% | $2,135,518.11 | 6.94% |
| Lost | 26 | 22.4% | $1,315,238.68 | 4.27% |
| Recent | 14 | 12.1% | $1,240,042.32 | 4.03% |
| **Total** | **116** | 100% | **$30,771,551.71** | 100% |

**Checks:**
- Customers add up to 116 and revenue to $30,771,551.71.
- Each score has 23–24 customers, as in Q14.
- Sorted by days since last order, R scores never mix (all 5s, then all 4s, and so on).

**Findings**

**About a fifth of customers (26 Champions) bring in 62% of revenue and are the accounts to protect. The next priority is the 21 At Risk customers: they used to buy regularly but haven't ordered in at least 104 days, and they are worth $3.7M (12% of revenue), more than the Loyal group. The 40 Lost and Recent customers, a third of the customer base, bring in only 8% of revenue.**

- **Champions match Q14's top group:** 22% of customers bring in 62% of revenue, close to the top 20% bringing in 64%.
- **At Risk is worth more than Loyal** ($3.7M vs $3.2M), so winning back lapsed regulars is worth more than any other group except keeping the Champions.
- **At Risk is broader than Q15's "gone quiet" list** ($3.7M across 21 customers vs $1.6M across 10). Q15 compared each customer with their own buying rhythm (silent for 3× their usual gap); RFM compares customers with each other (anyone in the bottom 40% for recency, i.e. 104+ days without an order). So RFM also catches customers at an earlier stage of slowing down.
- **The two methods mostly agree:** 7 of Q15's 10 quiet customers are At Risk, including Energía Los Álamos (scores 1 / 5 / 5). The other 3 (Metalúrgica El Ceibo, Riego Piedra Negra, Metales Arroyo Seco) are Lost, because with 6–7 orders they rank low on frequency compared with other customers.
- **Merged duplicate:** customer 5 (Servicios Hídricos Quebracho) is At Risk (R = 2, F = 5); this only shows up correctly because of the Phase 2 merge.
- **Lost and Recent (40 customers, 8.3% of revenue)** are a normal long tail of small, occasional buyers, consistent with Q8 (customers with 5 orders or fewer bring in under 5% of revenue).
- **Suggested action for sales:** protect the Champions; contact the At Risk group first to win them back; keep the Loyal customers buying regularly; and spend time on Recent and Lost customers only if there is capacity left.

## Q18: How the business changed after the March 2025 price-list change

**Periods compared:** the 12 months before the change (March 2024 – February 2025) and the 12 months after it (March 2025 – February 2026). Each period contains exactly one of every month, so seasonal effects (weak February, strong December; Q2) cancel out and the difference reflects the price change, not the time of year.

**Method:** two separate queries, because quotes and orders live in different tables with different dates. Joining them would multiply rows (Q16).
- **Quotes** from `quote_summary`, labelled by `quote_date`: number of quotes and win rate (decided quotes only, as in Q4).
- **Orders** from `sales_lines`, labelled by `order_date`: orders (`COUNT(DISTINCT order_id)`), revenue, average order value and gross margin (as in Q1).
- `CASE WHEN` labels each row Before or After from its date. Rows outside both periods get no label and appear as a separate blank row, which is ignored (adding a `WHERE` on the date range would remove it).

```sql
SELECT
	CASE WHEN qs.quote_date >= '2024-03-01' AND qs.quote_date < '2025-03-01' THEN 'Before'
	     WHEN qs.quote_date >= '2025-03-01' AND qs.quote_date < '2026-03-01' THEN 'After'
	END AS period,
	COUNT(DISTINCT qs.quote_id) AS quote_count,
	ROUND((100.0 * (SUM(qs.status = 'won')) / (SUM(qs.status IN ('won', 'lost')))), 1) AS win_rate
FROM quote_summary qs
GROUP BY period;

SELECT
	CASE WHEN sl.order_date >= '2024-03-01' AND sl.order_date < '2025-03-01' THEN 'Before'
	     WHEN sl.order_date >= '2025-03-01' AND sl.order_date < '2026-03-01' THEN 'After'
	END AS period,
	COUNT(DISTINCT sl.order_id) AS order_count,
	SUM(revenue) AS total_revenue,
	ROUND(SUM(sl.revenue) / COUNT(DISTINCT sl.order_id), 2) AS average_order_value,
	ROUND(SUM(sl.gross_profit) * 100 / SUM(sl.revenue), 1) AS gross_margin
FROM sales_lines sl
GROUP BY period;
```

**Checks:** including the blank (outside both periods) row, quotes add up to 3,822, orders to 1,467 and revenue to $30,771,551.71, matching the totals.

| Measure | Before (Mar 2024 – Feb 2025) | After (Mar 2025 – Feb 2026) | Change |
|---|---|---|---|
| Quotes | 1,134 | 1,204 | +6.2% |
| Win rate | 43.4% | 36.0% | −7.4 pp |
| Orders | 483 | 426 | −11.8% |
| Quotes per order | 2.35 | 2.83 | +20% |
| Revenue | $9,613,506.76 | $9,304,012.30 | −3.2% |
| Average order value | $19,903.74 | $21,840.40 | +9.7% |
| Gross margin | 30.0% | 37.5% | +7.5 pp |
| Gross profit (revenue × margin) | ≈ $2.88M | ≈ $3.49M | ≈ +21% |

- Gross profit is approximate, calculated from the rounded margins; adding `SUM(sl.gross_profit)` to the query would give the exact figures.

**Findings**

**In the year after the 12.6% price increase, the business won fewer deals but earned much more on each one. Orders fell 12% and revenue slipped 3%, but gross margin rose from 30% to 37.5%, so gross profit grew by about a fifth. The cost was more work and some lost customers: reps needed about 20% more quotes for each order they won.**

- **Fewer wins, more work:** quotes rose 6% while orders fell 12%, because the win rate dropped from 43.4% to 36.0%. Reps sent 2.83 quotes per order won, up from 2.35, so each order took about 20% more quoting effort. Focusing that effort on quotes most likely to win (see Q16) would help offset it.
- **Overall the change helped:** product costs stayed the same, so the higher prices went straight to margin. Despite 57 fewer orders, the business earned about $0.6M more gross profit.
- **Customers bought slightly less per order:** prices rose 12.6% and discounts stayed at about 11% (Phase 3), but average order value rose only 9.7%. That means each order contained about 2.5% less in quantity than before.
- **Where the lost orders went:** 6 of the 10 customers who went quiet (Q15) stopped buying in the months around the change and never ordered at the new prices; the most valuable, Energía Los Álamos, lost all 5 quotes since. The drop in orders also shows up as the weak July–November 2025 in Q12, when revenue fell 21% year over year because of fewer orders, not smaller ones.
- **Caveat:** this compares one year with the next, so other changes in that time (market conditions, new rep Valentina Sosa ramping up, Solar Pumping) may also play a part. The timing, the drop in win rate at every discount level (Q10) and across almost every rep (Q7) all point to the price change as the main driver.

## Q19: How the Solar Pumping line is doing

Four parts: revenue since launch, margin compared with other categories, win rate for quotes with and without solar products, and which industries buy it. All queries filter `sales_lines` with `WHERE sl.category = 'Solar Pumping'` or use the `has_solar_pumping` flag in `quote_summary` (Phase 3).

### 1. Revenue since launch

**Launch:** first solar quote on 2024-07-02 and first solar order on 2024-08-16 (`MIN(quote_date)` / `MIN(order_date)`), about six weeks from first quote to first sale.

```sql
SELECT
	sl.month,
	SUM(revenue) AS solar_revenue,
	COUNT(DISTINCT sl.order_id) AS order_count
FROM sales_lines sl
WHERE sl.category = 'Solar Pumping'
GROUP BY sl.month;
```

| Month | Revenue | Orders |
|---|---|---|
| 2024-08 | $14,686.95 | 1 |
| 2024-09 | $32,916.32 | 2 |
| 2024-10 | $30,965.26 | 1 |
| 2024-11 | $964.29 | 1 |
| 2024-12 | $145,897.59 | 7 |
| 2025-01 | $70,404.05 | 5 |
| 2025-03 | $73,474.80 | 5 |
| 2025-05 | $138,480.27 | 8 |
| 2025-06 | $37,987.47 | 4 |
| 2025-07 | $101,336.00 | 5 |
| 2025-08 | $28,623.88 | 2 |
| 2025-09 | $33,041.00 | 2 |
| 2025-10 | $44,500.98 | 3 |
| 2025-11 | $88,636.93 | 8 |
| 2025-12 | $130,769.78 | 6 |
| 2026-01 | $56,470.31 | 5 |
| 2026-02 | $101,779.00 | 4 |
| 2026-03 | $327,284.03 | 12 |
| 2026-04 | $99,952.83 | 3 |
| 2026-05 | $59,977.80 | 3 |
| 2026-06 | $128,599.25 | 9 |

- No solar sales in February or April 2025, so those months don't appear.
- **Check:** the months add up to $1,746,748.79, the Solar Pumping total in Q9.

Single months are noisy (one large order can move a whole month), so revenue is summed by half-year:

| Period | Revenue | Orders | Revenue per order | Share of all revenue |
|---|---|---|---|---|
| Aug – Dec 2024 (5 months) | $225,430.41 | 12 | | |
| Jan – Jun 2025 | $320,346.59 | 22 | $14,561 | 7.0% |
| Jul – Dec 2025 | $426,908.57 | 26 | | |
| Jan – Jun 2026 | $774,063.22 | 36 | $21,502 | 13.6% |

### 2. Margin compared with other categories

From Q9 (no new query): Solar Pumping has a **32.7% gross margin, 3rd of 7 categories**. That is just below the company's overall 33.3%, which is pulled up by Services (51.4%), but among physical products only Controls & Sensors (35.6%) earns a higher margin. It is the smallest category, 5.7% of total revenue and 5.6% of gross profit.

### 3. Win rate for quotes with and without solar products

```sql
SELECT
	qs.has_solar_pumping,
	COUNT(DISTINCT qs.quote_id) AS quote_count,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 1) AS win_rate
FROM quote_summary qs
WHERE qs.quote_date >= '2024-07-02'
GROUP BY qs.has_solar_pumping;
```

| Quotes | All dates | | Since first solar quote (2024-07-02) | |
|---|---|---|---|---|
| | Quotes | Win rate | Quotes | Win rate |
| Without solar | 3,596 | 39.0% | 2,209 | 37.7% |
| With solar | 226 | 47.1% | 226 | 47.1% |

- **Why filter by date:** solar only exists from July 2024, but without the filter the "without solar" row includes 2023 to early 2025, when every win rate was higher (before the price change, Q4). Limiting both rows to the same period makes the comparison fair. The gap widened from 8.1 to 9.4 pp.
- **Check (all dates):** 3,596 + 226 = 3,822 quotes; 226 matches the solar flag check in Phase 3.

### 4. Which industries buy it

```sql
SELECT
	sl.industry,
	SUM(revenue) AS solar_revenue,
	ROUND(SUM(sl.revenue) * 100.0 / (SELECT SUM(revenue) FROM sales_lines WHERE category = 'Solar Pumping'), 2) AS share_of_solar
FROM sales_lines sl
WHERE sl.category = 'Solar Pumping'
GROUP BY sl.industry
ORDER BY solar_revenue DESC;
```

| Industry | Solar revenue | Share of solar |
|---|---|---|
| Agriculture | $1,334,778.76 | 76.42% |
| Unknown | $252,819.37 | 14.47% |
| Water Utilities | $159,150.66 | 9.11% |

- The total in the subquery is filtered to Solar Pumping too, so shares are of solar revenue, not of all revenue.
- **Who "Unknown" is:** Agropecuaria Colorado ($209,279.07), the top-10 customer with no industry recorded whose name points to Agriculture (Q6), and Saneamiento Ombú ($43,540.30), a sanitation company, closest to Water Utilities.
- Counting them that way, **about 88% of solar revenue comes from agriculture** and about 12% from water and sanitation. No Mining, Oil & Gas, Construction, Manufacturing or Food & Beverage customer has bought solar products.

**Findings**

**Solar Pumping is small but growing fast and worth pushing. Since its launch in August 2024, revenue has grown every half-year: the first half of 2026 ($774k) already beat all of 2025 ($747k) and is 2.4 times the same months a year earlier, doubling its share of total revenue to 13.6%. It earns a 32.7% margin, the second highest among physical products, and quotes that include solar products are won 47% of the time, against 38% for quotes without. Almost all of it (about 88%) is bought by agricultural customers.**

- **Growth from more and bigger orders:** January–June 2026 had 36 solar orders, against 22 a year earlier (+64%), and each order brought in about 48% more ($21,502 vs $14,561).
- **A large part of 2026's growth:** solar revenue rose by $453,717 from January–June 2025 to January–June 2026, about 42% of the company's total revenue increase in that period ($1,078,726, Q13). This helps answer the open question in Q1 and Q12 about why 2026 orders are larger.
- **Easier to win:** quotes with solar products are won 9.4 pp more often since launch (47.1% vs 37.7%), about 25% more likely to close.
- **A narrow customer base:** about 88% agriculture and 12% water and sanitation. Solar pumping suits customers who move water in remote places, such as irrigation on farms.
- **Suggested action for sales:** offer solar products to more agricultural customers, starting with Centro, where about three quarters of all Agriculture revenue comes from (Q6), and test whether water utilities and other industries that pump water could also be buyers.
- **Caveat:** the line is less than two years old and has 96 orders in total, so single months swing a lot and the trend rests on a fairly small number of orders.

---

# Phase 7: Insights

Five findings chosen from Phases 4–6 using three tests: surprising, money attached, and someone could act on it. Two overlapping findings were merged (the price-change trade-off and the customers lost around it). The discount finding (Q10) was left out because it shows an association, not a cause, so it can't support a clear recommendation. It stays in Q10 as supporting context.

| # | Finding | Evidence (number) | Why it matters | Recommendation |
|---|---|---|---|---|
| 1 | Revenue depends on a few customers | Top 20% of customers = 64.1% of revenue; in Norte one customer = 55.6% | Losing one top account would cause a large revenue drop, especially in Norte and AMBA | Give each top account a named owner; grow quintile-2 customers to reduce dependence |
| 2 | Solar Pumping is small, growing fast, and easier to win | H1 2026 $774k > all of 2025 ($747k); win rate 47.1% vs 37.7% | It drove 42% of the company's H1 2026 revenue growth, at a 32.7% margin | Offer solar products to agricultural customers, starting in Centro; test with water utilities |
| 3 | The price increase raised profit but lost customers | Win rate 43.4% → 36.0%; gross margin 30.0% → 37.5%; 6 regular customers stopped buying around the change | Profit rose about 21%, but price-sensitive customers left and each order now takes 20% more quotes | Keep the new prices; run a win-back on the lapsed customers who are still asking for quotes |
| 4 | Services earns a quarter of all profit | Services: 16.5% of revenue, 25.5% of profit, 51.4% margin; Ducting: 20.4% of revenue, 14.7% of profit | Each dollar of Services earns about twice as much as a dollar of Ducting | Attach Annual Maintenance to equipment quotes; review Ducting pricing |
| 5 | Five customers take up 10% of quoting work for 2% of revenue | 393 of 3,822 quotes; $713k revenue; 12–18% win rate vs 38.5% average | Rep time goes to quotes worth about a quarter of an average quote | Add a qualification step before re-quoting these customers |

## 1. Revenue depends on a few customers

- **What:** The top 20% of customers (24 of 116) bring in **64.1% of revenue**, and the top 10 alone bring in 46.9%. The dependence is sharper in some regions: in Norte, Minera Tala is **55.6%** of the region's revenue; in AMBA, Servicios Petroleros Coirón is 34.2%.
- **So what:** Losing one top account would hit revenue hard. Minera Tala alone is $2.21M, 7.2% of the company's total. Losing it would wipe out more than half of Norte's revenue.
- **Now what:** Give each of the 24 top accounts a named owner and a yearly account plan. In Norte and AMBA, grow the next tier of customers (quintile 2 brings in 17.2% across 23 customers) so that no single account carries a region.

*Sources: Q5, Q11, Q14, Q17.*

## 2. Solar Pumping is small, growing fast, and easier to win

- **What:** Solar Pumping launched in August 2024. In January–June 2026 it brought in **$774k**, more than all of 2025 ($747k) and 2.4 times the same months of 2025. Its share of revenue doubled to 13.6%. Quotes that include solar products are won **47.1%** of the time, against 37.7% for quotes without them, and the line earns a **32.7% margin**, the second highest among physical products. About 88% of solar revenue comes from agricultural customers.
- **So what:** Solar accounted for **42% of the company's revenue growth** in the first half of 2026 ($454k of $1.08M). It is easier to win and reasonably profitable. Its customer base is narrow, which means there are many potential buyers who haven't been approached yet.
- **Now what:** Add solar products to quotes for agricultural customers, starting in Centro, which brings in about three quarters of all Agriculture revenue. Run a small test with water utilities and other customers who pump water.

*Caveat: the line is less than two years old and has 96 orders, so the trend rests on a small base. Sources: Q9, Q19.*

## 3. The price increase raised profit but lost customers

- **What:** In the 12 months after the 12.6% list-price increase (March 2025), the win rate fell from **43.4% to 36.0%** and orders fell 12%. Gross margin rose from **30.0% to 37.5%**, so gross profit grew by about **21%** (≈ +$0.6M). Over the same months, 6 of the 10 regular customers who have since gone quiet stopped buying. The most valuable of them, Energía Los Álamos ($387k, a top-20% customer), has lost all 5 quotes sent to it since the increase.
- **So what:** The increase paid off overall, but it had two costs. Reps now need **2.83 quotes for each order won, up from 2.35** (+20% effort). And some price-sensitive regular customers left: four lapsed customers worth $860k kept asking for quotes but lost them.
- **Now what:** Keep the new price list. Start a targeted win-back with the lapsed customers who are still asking for quotes, beginning with Energía Los Álamos and the pending Plásticos Molle quote. Before any future price change, estimate the effect on win rate and on key accounts first.

*Caveat: other changes in the same year (a new rep, the growth of Solar Pumping) may also contribute. The drop in win rate across every discount band and almost every rep points to price as the main driver. Sources: Q4, Q7, Q10, Q15, Q18.*

## 4. Services earns a quarter of all profit

- **What:** Services is **16.5% of revenue but 25.5% of gross profit**, with a 51.4% margin, the highest of any category. About 90% of it is a single product, the Annual Maintenance contract. At the other end, Ducting is 20.4% of revenue but only 14.7% of profit, with the lowest margin (23.9%).
- **So what:** Each dollar of Services earns about $0.51 of gross profit, against $0.24 for Ducting. Shifting the mix even slightly toward Services raises profit without needing more orders.
- **Now what:** Offer Annual Maintenance with every equipment sale, especially to buyers of Fans & Blowers and Ducting, the two largest categories. Review Ducting's pricing and costs to find out why its margin trails every other category.

*Sources: Q3, Q9.*

## 5. Five customers take up 10% of quoting work for 2% of revenue

- **What:** Five customers asked for **393 quotes (10.3% of all quotes)** but brought in only **$713k (2.3% of revenue)**. They win just 12–18% of the time, against an average of 38.5%. Each quote for them is worth about $1,800, against about $8,050 on average. Tomás Lescano handles 181 of these quotes, 21% of his total.
- **So what:** About 1 in 10 quotes goes to work that rarely pays off. This matters more since the price change, now that every order takes 20% more quoting effort (finding 3).
- **Now what:** Add a qualification step before re-quoting these customers, such as checking that the request is serious and large enough. Move the time saved to larger quotes and higher-win customers, starting with Tomás's territory.

*Caveat: not yet tested whether these quotes cluster after March 2025, when every win rate fell. Sources: Q7, Q16.*

## Answer key check

Each planted pattern marked as found, partly found or missed. Figures in the key are approximate.

### Data-quality problems

| Planted problem | Status | My result vs the key |
|---|---|---|
| Inconsistent region labels | ✅ Found | All variants standardized to 5 regions, including `Buenos Aires (AMBA)` and `NOA` → Norte |
| Missing industry (8 customers) | ✅ Found | Labelled "Unknown"; count of affected customers not recorded (key: 8) |
| 4 duplicate customers | ✅ Found | All 4 pairs merged, including the accent case (5/124) that `LOWER()` missed at first |
| ~70% of new quotes went to the duplicate ID after the cutoff | 🟡 Partly | Found the parallel use of both IDs and that 5/124 moved fully to the new record; didn't measure the share |
| Customer 5 looks churned but isn't | ✅ Found | Noted in Q15: before the merge it would have looked silent for ~400 days |
| 14 duplicate order lines (~$121K) | ✅ Found | 14 lines, 0.39% of revenue ≈ $120K, matches |

### Business patterns

| # | Planted pattern | Status | My result vs the key |
|---|---|---|---|
| 1 | Seasonality (orders: weak February, strong December) | ✅ Found | Q2 |
| 1 | Seasonality in **quote** dates (slow January, July dip, Q4 push) and 2–6 week lag from quote to order | ❌ Missed | Only order dates were analyzed by month |
| 2 | Yearly growth and H1 comparison | ✅ Found | Q1, Q13: same figures, and 2026 compared with 2025 H1 |
| 2 | 2024 growth driven by new customer acquisition | 🟡 Partly | Found it was volume-driven (orders +31%, AOV flat), but didn't test whether the extra orders came from new customers |
| 3 | Price increase on 1 March 2025 | ✅ Found | Found the exact date. Measured +12.6% vs the key's 12%; the gap comes from averaging quoted ÷ list ratios, not from an error |
| 3 | Win rate drop and margin rise | ✅ Found | 42.2% → 35.5% and 43.4% → 36.0%; margin 29.2% → 36.4% |
| 3 | Win rate only partly recovered (~35% → ~37%) | 🟡 Partly | Noted 2026 was "similar" to 2025, but didn't look at the trend by half-year after the change |
| 4 | Discount vs win rate (~32% → ~49%) | ✅ Found | Q10: 30.5% → 49.1% |
| 5 | Top 20% ≈ 63% of revenue | ✅ Found | Q14: 64.1% |
| 6 | 9 churned customers (17, 47, 55, 56, 67, 77, 87, 95, 105) | 🟡 Partly | 8 of 9 found in Q15. **Missed 67.** Flagged 2 the key doesn't list (1 Plásticos Molle, 100 Minerales Viento Sur) |
| 7 | 5 quote hoarders | ✅ Found | Q16: exactly the same 5 |
| 8 | Martín fastest, Nicolás slowest but good win rate, Camila heaviest discounter | ✅ Found | Q7: same figures |
| 8 | Valentina's low win rate is a new-hire ramp-up | 🟡 Different reading | I attributed it to the price change: she won 41.4% before and 26.4% after. The two explanations overlap in time, so this needs a test (see below) |
| 8 | Hoarders affect rep win rates | ✅ Found | Q16: Tomás handles 2 of the 5 |
| 9 | Services highest margin, Ducting lowest | ✅ Found | Q9: 51.4% and 23.9% |
| 10 | Solar Pumping growth, higher win rate, Agriculture buyers, ~$250K from missing industry | ✅ Found | Q19: all four, including the $252,819 from "Unknown" |

**Score:** 17 found, 5 partly found or read differently, 1 missed (quote seasonality and lag).

### Still to check myself

- **Customer 67:** why didn't Q15 flag it? Check its row in `customer_activity` (orders, last order, ratio) against the two rules (5+ orders, ratio ≥ 3).
- **Quote seasonality and lag:** quotes by month of `quote_date`, and the average days from quote to order (orders have `quote_id`).
- **2024 growth from new customers:** count customers by the year of their first order, and how much 2024 revenue came from customers whose first order was in 2024.
- **Win rate recovery:** win rate by half-year from 2024 H2 to 2026 H1.
- **Valentina, ramp-up or price:** her win rate by month since hire. A ramp-up would show low early and improving; the price-change reading would show normal and then dropping in March 2025.
- **Plásticos Molle and Minerales Viento Sur:** not planted churn, so likely normal variation in the data. If so, finding 3's win-back recommendation should lead with Energía Los Álamos and treat Plásticos Molle as secondary.
- **Energía Los Álamos, "still asking for quotes":** the key says churned customers stopped quoting by June 2025. Check the date of its last quote; if it's mid-2025, finding 3 should say it *kept* asking for a while, not that it still is.

### Found beyond the key

- **SQLite's `LOWER()` doesn't convert accented capitals**, which hid the fourth duplicate customer.
- **Duplicate customers point to a process gap:** created by reps after rep 4 started quoting, then used in parallel.
- **A top-10 customer (Agropecuaria Colorado) has no industry recorded.**
- **Regional dependence on single customers:** Minera Tala is 56% of Norte; AMBA's Oil & Gas revenue is one account.
- **Reps kept the same ~11% discount after the price change**, so customers paid the full increase.
- **Each order took 20% more quotes after the price change** (2.35 → 2.83 quotes per order won).
- **Diego Arrieta was the only rep whose win rate rose after the price change** (+2.3 pp), while quoting about a quarter less per month.
- **Services earns a quarter of all gross profit**, and about 90% of it is one product (Annual Maintenance).
- **The July–November 2025 dip came from fewer orders, not smaller ones.**
- **Solar Pumping drove 42% of H1 2026 revenue growth** and explains part of 2026's larger orders.
- **RFM At Risk segment ($3.7M) is worth more than the Loyal segment.**
- **Customers bought about 2.5% less quantity per order** after the price change.

## Limitations

The data is synthetic, and some things a real company would track are missing. Three that limit this analysis:

| Missing data | What it would tell us | What I would do with it |
|---|---|---|
| **Time spent preparing each quote** | How much rep time goes into quotes that are lost, especially for the five high-quote, low-win customers (finding 5) and the extra quoting after the price change (finding 3) | Put a cost on lost quotes, i.e. the profit that time could have earned on other customers, and use it to set the qualification rule for re-quoting |
| **Why quotes were lost and why customers stopped asking for quotes** | Whether customers left because of price, a competitor, service problems or their own economic situation. Today the link to the price change is only timing (finding 3) | Respond to each reason. If price, offer targeted discounts to the lapsed customers worth winning back. If the customers' own business slowed down, focus rep time on the customers who are still buying instead of chasing those who can't |
| **Competitors' prices** | Whether the company is priced above the market, and on which products | Adjust prices where the gap is costing deals. This would mostly affect the many smaller customers: most revenue comes from a few large accounts (finding 1), where the relationship and service matter more than price, so they need account management rather than price matching |
