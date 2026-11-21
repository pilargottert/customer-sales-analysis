WITH customer_activity as (
SELECT
	sl.customer_id, sl.customer_name, sl.region,
	sum(sl.revenue) as total_revenue,
	count(DISTINCT sl.order_id) as order_count,
	min(sl.order_date) as first_order,
	max(sl.order_date) as last_order,
	round(((julianday(max(sl.order_date)) - julianday(min(sl.order_date))) / (count(DISTINCT sl.order_id) -1)),0) as avg_gap,
	(julianday('2026-06-30') - julianday(max(sl.order_date))) as days_since_last,
	round(((julianday('2026-06-30') - julianday(max(sl.order_date))) / 
		((julianday(max(sl.order_date)) - julianday(min(sl.order_date))) / (count(DISTINCT sl.order_id) -1))),1) as ratio
FROM sales_lines sl
GROUP by sl.customer_id, sl.customer_name, sl.region
)
/* to determine ratio threshold
SELECT
	CASE WHEN ratio < 1.5 THEN '1: under 1.5'
	     WHEN ratio < 2 THEN '2: 1.5–2'
	     WHEN ratio < 3 THEN '3: 2–3'
	     WHEN ratio < 5 THEN '4: 3–5'
	     ELSE '5: 5+' END AS ratio_band,
	COUNT(*) AS customers
FROM customer_activity
WHERE order_count >= 5
GROUP BY ratio_band
ORDER BY ratio_band */
SELECT *
FROM customer_activity
WHERE order_count >= 5 AND ratio >= 3
ORDER by ratio DESC