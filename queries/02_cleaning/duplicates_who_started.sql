SELECT customer_id, rep_id, MIN(quote_date) AS first_quote
FROM quotes
WHERE customer_id IN (121, 122, 123, 124)
GROUP BY customer_id, rep_id
ORDER BY customer_id, first_quote;