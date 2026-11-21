SELECT
	qs.rep_name,
	CASE WHEN qs.quote_date < '2025-03-01' THEN 'Before' ELSE 'After' END AS period,
	COUNT(*) AS quotes,
	COUNT(DISTINCT qs.customer_name) AS customers,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) AS win_rate
FROM quote_summary qs
WHERE qs.rep_name IN ('Diego Arrieta', 'Valentina Sosa')
GROUP BY qs.rep_name, period;