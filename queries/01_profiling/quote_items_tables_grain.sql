SELECT COUNT(*),
       COUNT(DISTINCT quote_id || '-' || product_id)
FROM quote_items;