SELECT customer_id, COUNT(*) AS orders, MIN(order_date), MAX(order_date)
FROM orders
WHERE customer_id IN (5, 124)
GROUP BY customer_id;