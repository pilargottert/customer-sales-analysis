DROP VIEW IF EXISTS quotes_clean;

CREATE VIEW quotes_clean AS
SELECT
    quote_id,
    CASE
        WHEN customer_id = 123 THEN 35
        WHEN customer_id = 121 THEN 24
        WHEN customer_id = 122 THEN 71
        ELSE customer_id
    END AS customer_id,
    rep_id, quote_date, status, decided_date
FROM quotes;