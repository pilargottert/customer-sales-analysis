DROP VIEW IF EXISTS customer_summary;
CREATE VIEW customer_summary AS
WITH customer_activity AS (
	SELECT
		customer_id,
		SUM(revenue) AS total_revenue,
		SUM(gross_profit) AS gross_profit,
		COUNT(DISTINCT order_id) AS order_count,
		MIN(order_date) AS first_order,
		MAX(order_date) AS last_order,
		julianday('2026-06-30') - julianday(MAX(order_date)) AS days_since_last,
		(julianday(MAX(order_date)) - julianday(MIN(order_date))) / NULLIF(COUNT(DISTINCT order_id) - 1, 0) AS avg_gap
	FROM sales_lines
	GROUP BY customer_id
), rfm_scores AS (
	SELECT *,
		NTILE(5) OVER (ORDER BY days_since_last DESC) AS r_score,
		NTILE(5) OVER (ORDER BY order_count) AS f_score,
		NTILE(5) OVER (ORDER BY total_revenue) AS m_score
	FROM customer_activity
), customer_quotes AS (
	SELECT
		customer_name,
		COUNT(DISTINCT quote_id) AS quote_count,
		ROUND(100.0 * SUM(status = 'won') / SUM(status IN ('won', 'lost')), 1) AS win_rate
	FROM quote_summary
	GROUP BY customer_name
)
SELECT
	c.customer_id, c.customer_name, c.industry, c.region,
	ROUND(r.total_revenue, 0) AS total_revenue,
	ROUND(r.gross_profit, 0) AS gross_profit,
	r.order_count, r.first_order, r.last_order,
	r.days_since_last,
	ROUND(r.avg_gap, 0) AS avg_gap,
	ROUND(r.days_since_last / r.avg_gap, 1) AS gap_ratio,
	r.r_score, r.f_score, r.m_score,
	CASE
		WHEN r.customer_id IS NULL THEN 'No orders'
		WHEN r.r_score >= 4 AND r.f_score >= 4 AND r.m_score >= 4 THEN 'Champions'
		WHEN r.r_score >= 3 AND r.f_score >= 4 THEN 'Loyal'
		WHEN r.r_score <= 2 AND r.f_score >= 3 THEN 'At Risk'
		WHEN r.r_score >= 4 AND r.f_score <= 2 THEN 'Recent'
		WHEN r.r_score <= 2 AND r.f_score <= 2 THEN 'Lost'
		ELSE 'Others'
	END AS segment,
	CASE WHEN r.order_count >= 5 AND r.days_since_last / r.avg_gap >= 3 THEN 1 ELSE 0 END AS gone_quiet,
	q.quote_count, q.win_rate,
	CASE WHEN q.quote_count >= 50 AND q.win_rate <= 20 THEN 1 ELSE 0 END AS many_quotes_low_win
FROM customers_clean c
LEFT JOIN rfm_scores r ON r.customer_id = c.customer_id
LEFT JOIN customer_quotes q ON q.customer_name = c.customer_name
ORDER BY total_revenue DESC;