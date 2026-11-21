DROP VIEW IF EXISTS order_items_clean;
CREATE VIEW order_items_clean AS
SELECT DISTINCT *
FROM order_items;