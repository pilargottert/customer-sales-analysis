SELECT COUNT(*) FROM customers_clean;                           -- should be 121
SELECT region, COUNT(*) FROM customers_clean GROUP BY region;   -- should be 5 regions
SELECT industry, COUNT(*) FROM customers_clean GROUP BY industry;
SELECT LOWER(REPLACE(customer_name, '.', '')) AS n, COUNT(*)
FROM customers_clean GROUP BY n HAVING COUNT(*) > 1;  