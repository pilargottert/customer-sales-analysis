SELECT 
	sl.year,
	round(sum(sl.revenue),2) as total_revenue,
	count(distinct sl.order_id) as number_of_orders,
	round(sum(sl.revenue) / count(distinct sl.order_id),2) as average_order_value,
	round(sum(sl.gross_profit) * 100 / sum(sl.revenue),1) as gross_margin
FROM sales_lines sl
 GROUP by sl.year ORDER by sl.year