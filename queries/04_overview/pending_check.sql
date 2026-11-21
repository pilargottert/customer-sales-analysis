   SELECT status, COUNT(*), COUNT(days_to_decide)
   FROM quote_summary
   GROUP BY status;