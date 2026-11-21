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
	ROUND(((total_revenue / region_total) * 100),2) AS percentage_total
FROM customer_ranks
WHERE region_rank <= 3