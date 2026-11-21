SELECT COUNT(*) FROM orders_clean
WHERE customer_id NOT IN (SELECT customer_id FROM customers_clean);
SELECT COUNT(*) FROM quotes_clean
WHERE customer_id NOT IN (SELECT customer_id FROM customers_clean);