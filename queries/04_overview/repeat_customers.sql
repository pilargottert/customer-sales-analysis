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
	CASE WHEN number_of_orders > 1 THEN 'Repeat' ELSE 'One-time' END as customer_type,
	count(*) as customer, 
	sum(revenue) as total_revenue,
	ROUND(SUM(revenue) * 100.0 / (SELECT SUM(revenue) FROM customer_summary), 2) AS share_of_revenue
FROM customer_summary
GROUP by customer_type