WITH customer_activity as (
SELECT
	sl.customer_id, sl.customer_name,
	(julianday('2026-06-30') - julianday(max(sl.order_date))) as days_since_last,
	count(DISTINCT sl.order_id) as order_count,
	sum(sl.revenue) as total_revenue
FROM sales_lines sl
GROUP by sl.customer_id, sl.customer_name
), rfm_scores as (
    SELECT
        customer_id, customer_name, days_since_last, order_count, total_revenue,
        ntile(5) OVER (ORDER by days_since_last DESC) as r_score,
        ntile(5) OVER (ORDER by order_count) as f_score,
        ntile(5) OVER (ORDER by total_revenue) as m_score
    FROM customer_activity
), rfm_segments as (
SELECT *,
	CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
				WHEN r_score >= 3 AND f_score >= 4 THEN 'Loyal'
				WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
				WHEN r_score >= 4 AND f_score <= 2 THEN 'Recent'
				WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
				ELSE 'Others'
	END as segment
FROM rfm_scores
ORDER by r_score DESC, f_score DESC, m_score DESC
)
SELECT
	segment,
	count(*) as customer_count,
	sum(total_revenue) as segment_revenue,
	round(sum(total_revenue) * 100.0 / (SELECT sum(total_revenue) FROM rfm_segments),2) as share_of_revenue
FROM rfm_segments
GROUP by segment
ORDER by segment_revenue DESC