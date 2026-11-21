SELECT
	CASE WHEN qs.quote_date < '2025-03-01' THEN 'Before price change'
	     ELSE 'After price change' END AS period,
	COUNT(qs.quote_id) AS number_of_quotes,
	SUM(qs.status IN ('won', 'lost')) AS decided,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) AS win_rate
FROM quote_summary qs
GROUP BY period
ORDER BY MIN(qs.quote_date);