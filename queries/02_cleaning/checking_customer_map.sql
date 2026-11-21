SELECT COUNT(*) FROM customer_map;
SELECT * FROM customer_map WHERE customer_id <> master_customer_id; --expect 4 rows, including 124