SELECT 
	sl.industry,
	sum(revenue) as solar_revenue,
	round(sum(sl.revenue) * 100.0 / (SELECT sum(revenue) FROM sales_lines WHERE category = 'Solar Pumping'), 2) as share_of_solar
FROM sales_lines sl
WHERE sl.category = 'Solar Pumping'
GROUP by sl.industry