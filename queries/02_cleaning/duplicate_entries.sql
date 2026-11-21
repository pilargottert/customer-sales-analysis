SELECT customer_id, rep_id, MIN(quote_date), MAX(quote_date), COUNT(*)
FROM quotes
WHERE customer_id IN (35, 123, 24, 121, 71, 122, 5, 124)
GROUP BY customer_id, rep_id