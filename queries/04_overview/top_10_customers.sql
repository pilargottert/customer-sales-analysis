SELECT
	sl.customer_name, sl.customer_id,
	sum(sl.revenue) as total_revenue,
	round(((sum(sl.revenue)) * 100.0 / (SELECT sum(revenue) FROM sales_lines)),2) as share_of_total
FROM sales_lines sl
GROUP by sl.customer_name, sl.customer_id ORDER by total_revenue DESC LIMIT 10