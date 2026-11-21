WITH customer_quotes as (
SELECT
	qs.customer_name, 
	count(distinct qs.quote_id) as quote_count,
	sum(qs.status = 'won') as quotes_won,
	round((100.0 * (sum(qs.status = 'won')) / (SUM(qs.status IN ('won', 'lost')))),1) as win_rate,
	qs.region
FROM quote_summary qs
GROUP by qs.customer_name, qs.region
), customer_revenue as (
SELECT
	sl.customer_name,
	sum(sl.revenue) as total_revenue
FROM sales_lines sl
GROUP by sl.customer_name
)
/* SELECT
	ROUND(AVG(quote_count), 1) AS avg_quotes,
	MIN(quote_count) AS min_quotes,
	MAX(quote_count) AS max_quotes,
	ROUND(AVG(win_rate), 1) AS avg_win_rate,
	MIN(win_rate) AS min_win_rate,
	MAX(win_rate) AS max_win_rate
FROM customer_quotes */
SELECT 
	cq.*, cr.total_revenue
FROM customer_quotes cq
LEFT JOIN customer_revenue cr ON cq.customer_name = cr.customer_name
WHERE quote_count >= 50 AND win_rate <= 20
ORDER by quote_count DESC