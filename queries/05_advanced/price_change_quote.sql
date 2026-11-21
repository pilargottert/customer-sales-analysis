SELECT
	   CASE WHEN qs.quote_date >= '2024-03-01' AND qs.quote_date < '2025-03-01' THEN 'Before'
					WHEN qs.quote_date >= '2025-03-01' AND qs.quote_date < '2026-03-01' THEN 'After'
		END as period,
		count(distinct qs.quote_id) as quote_count,
		round((100.0 * (sum(qs.status = 'won')) / (SUM(qs.status IN ('won', 'lost')))),1) as win_rate
 FROM  quote_summary qs
 GROUP by period