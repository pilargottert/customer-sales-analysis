SELECT customer_id, customer_name, industry, region
FROM customers_clean
WHERE region = 'Cuyo' AND industry = 'Unknown';