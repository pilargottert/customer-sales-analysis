DROP VIEW IF EXISTS rep_scorecard;
CREATE VIEW rep_scorecard AS
WITH rep_sales AS (
	SELECT
		rep_name,
		SUM(revenue) AS revenue,
		SUM(gross_profit) AS gross_profit,
		COUNT(DISTINCT order_id) AS orders
	FROM sales_lines
	GROUP BY rep_name
)
SELECT
	qs.rep_name, sr.region, sr.hire_date,
	ROUND(rs.revenue, 0) AS revenue,
	ROUND(rs.gross_profit, 0) AS gross_profit,
	ROUND(100.0 * rs.gross_profit / rs.revenue, 1) AS gross_margin,
	rs.orders,
	count(qs.quote_id) as quote_handled,
	round(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) as win_rate,
	round(avg(qs.days_to_decide),1) as avg_days,
	round(avg(qs.discount),2) as avg_discount,
	ROUND(100 * AVG(qs.quote_date >= '2025-03-01'), 1) AS pct_after_price_change,
	ROUND(100.0 * SUM(qs.status = 'won' AND qs.quote_date < '2025-03-01')
            / SUM(qs.status IN ('won', 'lost') AND qs.quote_date < '2025-03-01'), 2) AS win_rate_before,
			ROUND(100.0 * SUM(qs.status = 'won' AND qs.quote_date >= '2025-03-01')
            / SUM(qs.status IN ('won', 'lost') AND qs.quote_date >='2025-03-01'), 2) AS win_rate_after,
			ROUND(AVG(CASE WHEN qs.quote_date < '2025-03-01' THEN qs.discount END), 2) AS discount_before,
ROUND(AVG(CASE WHEN qs.quote_date >= '2025-03-01' THEN qs.discount END), 2) AS discount_after
FROM quote_summary qs
JOIN sales_reps sr on qs.rep_name = sr.rep_name
LEFT JOIN rep_sales rs ON rs.rep_name = qs.rep_name
GROUP by qs.rep_name
ORDER by quote_handled DESC