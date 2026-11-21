DROP TABLE IF EXISTS customer_map;
CREATE TABLE customer_map AS
SELECT customer_id,
       CASE customer_id
           WHEN 123 THEN 35
           WHEN 121 THEN 24
           WHEN 122 THEN 71
		   WHEN 124 THEN 5
           ELSE customer_id
       END AS master_customer_id
FROM customers;