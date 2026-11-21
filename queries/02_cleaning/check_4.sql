SELECT
    SUM(order_id IS NULL)    AS order_id_nulls,
    SUM(customer_id IS NULL) AS customer_id_nulls,
    SUM(rep_id IS NULL)      AS rep_id_nulls,
    SUM(order_date IS NULL)  AS order_date_nulls
FROM orders_clean;