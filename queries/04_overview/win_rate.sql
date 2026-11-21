SELECT
	strftime('%Y', qs.quote_date) as year,
	count(qs.quote_id) as number_of_quotes,
	sum(qs.status = 'won') as won, round((100 * avg(qs.status = 'won')),2) as pct_won,
	sum(qs.status = 'lost' ) as lost, round((100 * avg(qs.status = 'lost')),2) as pct_lost,
	sum(qs.status = 'pending') as pending, round((100 * avg(qs.status = 'pending')),2) as pct_pending,
	round(100.0 * SUM(qs.status = 'won') / SUM(qs.status IN ('won', 'lost')), 2) as win_rate
FROM quote_summary qs
GROUP by year
