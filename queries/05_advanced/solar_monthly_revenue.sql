SELECT 
	/* min(sl.order_date) as launch_date */
	sl.month,
	sum(revenue) as solar_revenue,
	count(distinct sl.order_id) as order_count
FROM sales_lines sl
WHERE sl.category = 'Solar Pumping'
GROUP by sl.month