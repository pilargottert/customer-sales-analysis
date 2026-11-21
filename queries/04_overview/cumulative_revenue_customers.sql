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