DROP VIEW IF EXISTS orders_clean;
CREATE VIEW orders_clean AS
SELECT
    order_id,
    CASE
        WHEN customer_id = 123 THEN 35
        WHEN customer_id = 121 THEN 24
        WHEN customer_id = 122 THEN 71
        ELSE customer_id
    END AS customer_id,
    trim(quote_id), trim(rep_id), trim(order_date)
FROM orders;