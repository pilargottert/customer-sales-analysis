DROP VIEW IF EXISTS quotes_clean;
CREATE VIEW quotes_clean AS
SELECT
    q.quote_id,
    m.master_customer_id AS customer_id,
    q.rep_id,
    q.quote_date,
    q.status,
	q.decided_date
FROM quotes q
JOIN customer_map m ON q.customer_id = m.customer_id;