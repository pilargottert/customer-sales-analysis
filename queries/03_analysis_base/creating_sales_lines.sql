DROP VIEW IF EXISTS sales_lines;
CREATE VIEW sales_lines as
SELECT
	oi.order_id, o.order_date, strftime('%Y', o.order_date) as year, strftime('%Y-%m', o.order_date) as month,
	c.customer_id, c.customer_name, c.industry, c.region,
	s.rep_name, p.product_name, p.category, oi.quantity, oi.unit_price,
	(oi.quantity * oi.unit_price) as revenue,
	(oi.quantity * p.standard_cost) as cost,
	((oi.quantity * oi.unit_price) - (oi.quantity * p.standard_cost)) as gross_profit
FROM order_items_clean oi
JOIN orders_clean o on oi.order_id = o.order_id
JOIN customers_clean c on o.customer_id = c.customer_id
JOIN products p on oi.product_id = p.product_id
JOIN sales_reps s on o.rep_id = s.rep_id