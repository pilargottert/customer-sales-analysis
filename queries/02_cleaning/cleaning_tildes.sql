WITH normalized AS (
	SELECT
		customer_id,
		customer_name,
		LOWER(TRIM(REPLACE(
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
				customer_name,
				'Á', 'á'), 'É', 'é'), 'Í', 'í'), 'Ó', 'ó'), 'Ú', 'ú'), 'Ñ', 'ñ'),
			'.', ''))) AS clean_name
	FROM customers
)
SELECT
	a.customer_id AS id_1, a.customer_name AS name_1,
	b.customer_id AS id_2, b.customer_name AS name_2
FROM normalized a
JOIN normalized b
	ON a.clean_name = b.clean_name
	AND a.customer_id < b.customer_id
ORDER BY a.customer_id;