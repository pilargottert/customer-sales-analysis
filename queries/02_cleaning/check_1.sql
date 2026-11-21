SELECT COUNT(*) FROM order_items_clean;
SELECT (SELECT COUNT(*) FROM orders), (SELECT COUNT(*) FROM orders_clean);
SELECT (SELECT COUNT(*) FROM quotes), (SELECT COUNT(*) FROM quotes_clean);