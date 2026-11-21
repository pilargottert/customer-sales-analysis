SELECT
	customer_name, o.customer_id,
	sum(oi.quantity * oi.unit_price) as total_revenue
FROM  orders o
JOIN customers c on o.customer_id = c.customer_id
JOIN order_items oi on o.order_id = oi.order_id
GROUP by customer_name, o.customer_id
ORDER by total_revenue DESC LIMIT 10