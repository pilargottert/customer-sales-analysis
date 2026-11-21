SELECT sl.customer_name, SUM(sl.revenue) AS solar_revenue
FROM sales_lines sl
WHERE sl.category = 'Solar Pumping' AND sl.industry = 'Unknown'
GROUP BY sl.customer_name;