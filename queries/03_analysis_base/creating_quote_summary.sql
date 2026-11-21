DROP VIEW IF EXISTS quote_summary;
CREATE VIEW quote_summary as
SELECT
	qi.quote_id, q.quote_date, (julianday(q.decided_date) - julianday(q.quote_date)) as days_to_decide,
	c.customer_name, c.region, s.rep_name, q.status, 
	sum(qi.quantity * qi.quoted_price) as total_quotes_value,
	SUM(qi.quantity * CASE WHEN q.quote_date >= '2025-03-01' THEN p.list_price * 1.126 ELSE p.list_price END) AS total_listed_value,
	(100 - (SUM(qi.quantity * qi.quoted_price) * 100 / SUM(qi.quantity * CASE WHEN q.quote_date >= '2025-03-01' THEN p.list_price * 1.126 ELSE p.list_price END))) AS discount,
	max(case when p.category = 'Solar Pumping' THEN 1 ELSE 0 END) as has_solar_pumping
FROM quote_items qi
JOIN quotes_clean q on qi.quote_id = q.quote_id
JOIN customers_clean c on q.customer_id = c.customer_id
JOIN sales_reps s on q.rep_id = s.rep_id
JOIN products p on qi.product_id = p.product_id
GROUP by qi.quote_id, q.quote_date, c.customer_name, c.region, s.rep_name, q.status, q.decided_date
