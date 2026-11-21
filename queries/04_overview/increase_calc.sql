WITH yearly AS (
   SELECT 
	sl.year,
	round(sum(sl.revenue),2) as total_revenue,
	count(distinct sl.order_id) as number_of_orders,
	round(sum(sl.revenue) / count(distinct sl.order_id),2) as average_order_value,
	round(sum(sl.gross_profit) * 100 / sum(sl.revenue),1) as gross_margin
FROM sales_lines sl
 GROUP by sl.year
)
SELECT
    year,
    total_revenue,
    ROUND((total_revenue * 1.0 / LAG(total_revenue) OVER (ORDER BY year) - 1) * 100, 1) AS revenue_yoy,
	round((number_of_orders * 1.0 / lag(number_of_orders) OVER (ORDER by year) - 1) * 100,1) as number_of_orders_yoy,
	round((average_order_value * 1.0 / lag(average_order_value) OVER (ORDER by year) - 1) * 100,1)  as aov_yoy,
	round((gross_margin - lag(gross_margin) OVER (ORDER by year) ),1) as gross_margin_yoy
FROM yearly
ORDER BY year;