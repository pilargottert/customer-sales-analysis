WITH growth as (
WITH revenue_growth as (
SELECT
	sl.month,
	sum(sl.revenue) as total_revenue,
	COUNT(DISTINCT sl.order_id) AS order_count
FROM sales_lines sl
GROUP by sl.month
)
SELECT 
	month, total_revenue, order_count,
	lag(total_revenue, 1) OVER (ORDER BY month) as previous_month,
	lag(total_revenue, 12) OVER (ORDER BY month) as same_month_last_year
FROM revenue_growth
)
SELECT
	month, total_revenue, previous_month, same_month_last_year,
	round(100*((total_revenue / previous_month)-1),1) as mom_growth,
	round(100*((total_revenue / same_month_last_year)-1),1) as yoy_growth,
	order_count
FROM growth
