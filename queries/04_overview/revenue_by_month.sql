SELECT
	sl.year, 
	ROUND(SUM(CASE WHEN substr(sl.month,6,2) = '01' THEN sl.revenue END), 2) AS ene,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '02' THEN sl.revenue END), 2) AS feb,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '03' THEN sl.revenue END), 2) AS mar,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '04' THEN sl.revenue END), 2) AS abr,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '05' THEN sl.revenue END), 2) AS may,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '06' THEN sl.revenue END), 2) AS jun,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '07' THEN sl.revenue END), 2) AS jul,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '08' THEN sl.revenue END), 2) AS ago,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '09' THEN sl.revenue END), 2) AS sep,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '10' THEN sl.revenue END), 2) AS oct,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '11' THEN sl.revenue END), 2) AS nov,
	ROUND(SUM(CASE WHEN substr(sl.month, 6, 2) = '12' THEN sl.revenue END), 2) AS dic,
	ROUND(SUM(sl.revenue),2) AS total_rev
FROM sales_lines sl
GROUP by sl.year
ORDER by sl.year