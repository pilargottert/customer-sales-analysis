SELECT
	sl.year, sl.month,
	sum(revenue) as monthly_revenue,
	sum(sum(revenue)) OVER (PARTITION by sl.year ORDER by sl.month) as cumulative_revenue
FROM sales_lines sl
GROUP by sl.year, sl.month