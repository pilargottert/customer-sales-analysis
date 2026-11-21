DROP VIEW IF EXISTS customers_clean;
CREATE VIEW customers_clean AS
SELECT
    customer_id,
    RIM(customer_name) AS customer_name,
    coalesce(industry,'Unknown') as industry ,
    CASE
	WHEN LOWER(TRIM(region)) = 'cuyo' THEN 'Cuyo'
	WHEN lower(trim(region)) = 'centro' then 'Centro'
	when lower(trim(region)) = 'patagonia' then 'Patagonia'
	when lower(trim(region)) = 'amba' then 'AMBA'
	when lower(trim(region)) = 'buenos aires (amba)' then 'AMBA'
	when lower(trim(region)) = 'noa' then 'Norte'
	ELSE TRIM(region)
	END AS region
from customers 
WHERE customer_id NOT IN (121, 122, 123); 