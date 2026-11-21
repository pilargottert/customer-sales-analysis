SELECT status, COUNT(*) AS num_quotes
FROM quotes
GROUP BY status
ORDER BY num_quotes DESC