SELECT
	CASE 
	WHEN qs.discount < 5 THEN '0-5%' 
	WHEN qs.discount < 10 THEN '5-10%' 
	WHEN qs.discount < 15 THEN '10-15%' 
	WHEN qs.discount < 20 THEN '15-20%'
	ELSE '20%+' END as discount_band,
	count(*) as number_of_quotes, SUM(qs.status IN ('won', 'lost')) AS decided,
	round(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) as win_rate,
	ROUND(100.0 * SUM(qs.status = 'won' AND qs.quote_date < '2025-03-01')
        / SUM(qs.status IN ('won', 'lost') AND qs.quote_date < '2025-03-01'), 2) AS win_rate_before,
	ROUND(100.0 * SUM(qs.status = 'won' AND qs.quote_date >= '2025-03-01')
         / SUM(qs.status IN ('won', 'lost') AND qs.quote_date >='2025-03-01'), 2) AS win_rate_after
FROM quote_summary qs
GROUP by discount_band
ORDER by min(qs.discount)
