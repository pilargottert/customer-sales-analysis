WITH customer_quintile as (
SELECT
	sl.customer_id, sl.customer_name,
	sum(sl.revenue) as total_revenue,
	ntile(5) OVER (ORDER by sum(sl.revenue) DESC) as quintile
FROM sales_lines sl
GROUP by sl.customer_id, sl.customer_name
)
SELECT
	quintile, count(*) as number_of_customers,
	sum(total_revenue) as quintile_revenue,
	round(((sum(total_revenue) * 100) / (SELECT sum(total_revenue) FROM customer_quintile)),2) as share_of_total
FROM customer_quintile
GROUP by quintile
ORDER by quintile