WITH customer_summary as (
SELECT
	sl.customer_id, sl.customer_name,
	count(distinct sl.order_id) as number_of_orders,
	min(sl.order_date) as first_order,
	max(sl.order_date) as last_order,
	sum(sl.revenue) as revenue 
FROM sales_lines sl
GROUP by sl.customer_id, sl.customer_name 
)
SELECT
	CASE WHEN number_of_orders = 1 THEN '1 order'
	WHEN number_of_orders BETWEEN 2 AND 5 THEN '2–5 orders'
	WHEN number_of_orders BETWEEN 6 AND 15 THEN '6–15 orders'
	ELSE '16+ orders' END as customer_type,
	count(*) as customer, 
	sum(revenue) as total_revenue,
	ROUND(SUM(revenue) * 100.0 / (SELECT SUM(revenue) FROM customer_summary), 2) AS share_of_revenue,
	ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM customer_summary), 1) AS share_of_customers
FROM customer_summary
GROUP by customer_type
ORDER by min(number_of_orders)