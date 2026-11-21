SELECT
	   CASE WHEN sl.order_date >= '2024-03-01' AND sl.order_date < '2025-03-01' THEN 'Before'
					WHEN sl.order_date >= '2025-03-01' AND sl.order_date < '2026-03-01' THEN 'After'
		END as period,
		count(distinct sl.order_id) as order_count,
		sum(revenue) as total_revenue,
		round(sum(sl.revenue) / count(distinct sl.order_id),2) as average_order_value,
		round(sum(sl.gross_profit) * 100 / sum(sl.revenue),1) as gross_margin
 FROM  sales_lines sl
 GROUP by period