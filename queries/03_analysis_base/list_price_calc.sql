SELECT
    CASE WHEN q.quote_date >= '2025-03-01' THEN 'after' ELSE 'before' END AS period,
    AVG(qi.quoted_price * 1.0 / p.list_price) AS avg_ratio,
    COUNT(*) AS lines
FROM quote_items qi
JOIN quotes_clean q ON qi.quote_id = q.quote_id
JOIN products p ON qi.product_id = p.product_id
GROUP BY period;