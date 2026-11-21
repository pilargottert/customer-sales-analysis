SELECT
	qs.has_solar_pumping,
	count(distinct qs.quote_id) as quote_count,
	round(100.0 * sum(qs.status = 'won') / sum(qs.status in ('won', 'lost')),1) as win_rate
FROM quote_summary qs
WHERE qs.quote_date >= '2024-07-02'
GROUP by qs.has_solar_pumping 
/*SELECT MIN(qs.quote_date)
FROM quote_summary qs
WHERE qs.has_solar_pumping = 1*/