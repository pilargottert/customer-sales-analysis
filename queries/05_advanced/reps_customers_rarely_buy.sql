SELECT
	qs.customer_name, qs.rep_name,
	COUNT(*) AS quotes,
	ROUND(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 1) AS win_rate
FROM quote_summary qs
WHERE qs.customer_name IN (
	'Desarrollos Molle Coop. Ltda.',
	'Industrias Jarilla S.R.L.',
	'Petróleo Coirón S.A.',
	'Lácteos Cardón S.A.',
	'Hídrica Las Tunas S.A.'
)
GROUP BY qs.customer_name, qs.rep_name
ORDER BY qs.customer_name, quotes DESC;