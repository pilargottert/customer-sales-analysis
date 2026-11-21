DROP VIEW IF EXISTS orders_clean;
CREATE VIEW orders_clean AS
SELECT
    o.order_id,
    o.quote_id,
    m.master_customer_id AS customer_id,
    o.rep_id,
    o.order_date
FROM orders o
JOIN customer_map m ON o.customer_id = m.customer_id;