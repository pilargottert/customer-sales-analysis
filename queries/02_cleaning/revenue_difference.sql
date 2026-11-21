SELECT
    (SELECT SUM(quantity * unit_price) FROM order_items) AS revenue_raw,
    (SELECT SUM(quantity * unit_price) FROM (SELECT DISTINCT * FROM order_items)) AS revenue_clean,
	(SELECT SUM(quantity * unit_price) FROM order_items)
	-
	(SELECT SUM(quantity * unit_price) FROM (SELECT DISTINCT * FROM order_items)) as revenue_difference,
	(((SELECT SUM(quantity * unit_price) FROM order_items)
	-
	(SELECT SUM(quantity * unit_price) FROM (SELECT DISTINCT * FROM order_items))) * 100.0
	/ (SELECT SUM(quantity * unit_price) FROM (SELECT DISTINCT * FROM order_items))) as percentage
	