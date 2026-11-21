SELECT customer_name, status, COUNT(*) AS quote_count
FROM quote_summary
WHERE quote_date >= '2025-03-01'
  AND customer_name IN (
	'Energía Los Álamos S.A.',
	'Recursos Mineros Jarilla S.R.L.',
	'Metales Arroyo Seco S.R.L.',
	'Constructora Viento Sur S.A.',
	'Riego Tres Cerros S.R.L.',
	'Plásticos Molle S.R.L.',
	'Servicios Petroleros Viento Sur S.R.L.',
	'Riego Piedra Negra Coop. Ltda.',
	'Minerales Viento Sur Coop. Ltda.',
	'Metalúrgica El Ceibo S.A.'
  )
GROUP BY customer_name, status