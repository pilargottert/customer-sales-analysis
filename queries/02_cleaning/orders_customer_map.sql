SELECT o.order_id,
       m.master_customer_id AS customer_id
FROM orders o
JOIN customer_map m ON o.customer_id = m.customer_id;