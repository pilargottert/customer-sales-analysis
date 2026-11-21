SELECT
	sl.category,
	sum(revenue) as total_revenue,
	sum(sl.gross_profit) as total_profit,
	round((sum(sl.gross_profit) * 100.0 / sum(sl.revenue)),2) as gross_margin
FROM sales_lines sl
GROUP by sl.category
ORDER by total_revenue DESC