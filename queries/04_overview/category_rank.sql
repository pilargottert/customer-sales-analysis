SELECT
	sl.category,
	sum(revenue) as total_revenue,
	sum(sl.gross_profit) as total_profit,
	round((sum(sl.gross_profit) * 100.0 / sum(sl.revenue)),2) as gross_margin,
	RANK() OVER (ORDER BY SUM(sl.revenue) DESC) AS revenue_rank,
	RANK() OVER (ORDER BY SUM(sl.gross_profit) DESC) AS profit_rank,
	RANK() OVER (ORDER BY SUM(sl.gross_profit) * 1.0 / SUM(sl.revenue) DESC) AS margin_rank
FROM sales_lines sl
GROUP by sl.category
ORDER by total_revenue DESC
