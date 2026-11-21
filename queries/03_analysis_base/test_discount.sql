SELECT strftime('%Y', quote_date) AS year, AVG(discount), COUNT(*)
FROM quote_summary
GROUP BY year;