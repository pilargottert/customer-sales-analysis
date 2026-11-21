SELECT
	sl.category, 
	sum(revenue) as total_revenue,
	round((sum (revenue) * 100.0 / (SELECT sum(revenue) FROM sales_lines)),2) as share_of_total
FROM sales_lines sl
GROUP by sl.category ORDER by total_revenue DESC