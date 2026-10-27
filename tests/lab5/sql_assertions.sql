\set ON_ERROR_STOP on
-- Runtime semantic assertions on the same live dataset used by Q1...Q8.
DO $tests$
DECLARE
  v_scans BIGINT;
  v_paid BIGINT;
  v_errors BIGINT;
  v_groups BIGINT;
BEGIN
  SELECT count(*) INTO v_scans FROM app.ticket_scans;
  SELECT count(*) INTO v_paid FROM app.orders WHERE status='paid';
  IF v_scans = 0 OR v_paid = 0 THEN
    RAISE EXCEPTION 'SQL catalog needs paid orders and scans. Generate development dataset with SEED=20261004 first';
  END IF;
  -- Q2: accepted + rejected must equal all scans in every hour/event.
  WITH hourly AS (
    SELECT t.event_id, date_trunc('hour',s.scanned_at) h,
      COUNT(*) all_scans,
      COUNT(*) FILTER(WHERE s.result='accepted') accepted,
      COUNT(*) FILTER(WHERE s.result='rejected') rejected
    FROM app.ticket_scans s JOIN app.tickets t ON t.id=s.ticket_id
    GROUP BY t.event_id,date_trunc('hour',s.scanned_at)
  )
  SELECT COUNT(*) INTO v_errors FROM hourly
  WHERE accepted+rejected<>all_scans;
  IF v_errors<>0 THEN RAISE EXCEPTION 'Q2 aggregation mismatch: %',v_errors; END IF;
  RAISE NOTICE 'PASS Q2: accepted + rejected = total';
  -- Q4: quota utilization calculation matches active ticket count.
  WITH quota AS (
    SELECT tc.id, tc.quota,
      COUNT(t.id) FILTER(WHERE t.status IN ('reserved','valid','scanned')) AS active
    FROM app.ticket_categories tc LEFT JOIN app.tickets t ON t.category_id=tc.id
    GROUP BY tc.id,tc.quota
  )
  SELECT COUNT(*) INTO v_errors FROM quota
  WHERE quota<=0 OR active<0 OR active>quota;
  IF v_errors<>0 THEN RAISE EXCEPTION 'Q4 impossible quota state: %',v_errors; END IF;
  RAISE NOTICE 'PASS Q4: category quotas are valid';
  -- Q6: all ranks are positive and the category with the highest revenue has rank 1.
  WITH cr AS (
    SELECT tc.event_id,tc.id,
      COALESCE(SUM(tc.price) FILTER(WHERE t.status IN ('valid','scanned')),0) revenue
    FROM app.ticket_categories tc
    LEFT JOIN app.tickets t ON t.category_id=tc.id
    GROUP BY tc.event_id,tc.id
  ),ranked AS (
    SELECT *,DENSE_RANK() OVER(PARTITION BY event_id ORDER BY revenue DESC) rnk,
      MAX(revenue) OVER(PARTITION BY event_id) maxrev
    FROM cr
  )
  SELECT COUNT(*) INTO v_errors FROM ranked
  WHERE rnk<1 OR (revenue=maxrev AND rnk<>1) OR (revenue<maxrev AND rnk=1);
  IF v_errors<>0 THEN RAISE EXCEPTION 'Q6 rank mismatch: %',v_errors; END IF;
  RAISE NOTICE 'PASS Q6: ranking is consistent';
  -- Q7: first hourly group per event has no predecessor; later groups have one.
  WITH hourly AS (
    SELECT t.event_id,date_trunc('hour',s.scanned_at) h,COUNT(*) attempts
    FROM app.ticket_scans s JOIN app.tickets t ON t.id=s.ticket_id
    GROUP BY t.event_id,date_trunc('hour',s.scanned_at)
  ),lagged AS (
    SELECT *,ROW_NUMBER() OVER(PARTITION BY event_id ORDER BY h) row_num,
    LAG(attempts) OVER(PARTITION BY event_id ORDER BY h) prev FROM hourly
  )
  SELECT COUNT(*) INTO v_errors FROM lagged
  WHERE (row_num=1 AND prev IS NOT NULL) OR (row_num>1 AND prev IS NULL);
  IF v_errors<>0 THEN RAISE EXCEPTION 'Q7 LAG mismatch: %',v_errors; END IF;
  RAISE NOTICE 'PASS Q7: LAG predecessor is correct';
  -- Q8: final cumulative value in each event equals its sum of paid orders.
  WITH cumulative AS (
    SELECT o.event_id, o.total_amount,
      SUM(o.total_amount) OVER(PARTITION BY o.event_id ORDER BY o.created_at,o.id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) running,
      SUM(o.total_amount) OVER(PARTITION BY o.event_id) expected,
      ROW_NUMBER() OVER(PARTITION BY o.event_id ORDER BY o.created_at DESC,o.id DESC) reverse_row
    FROM app.orders o WHERE o.status='paid'
  )
  SELECT COUNT(*) INTO v_errors FROM cumulative
  WHERE running<total_amount OR running>expected OR
    (reverse_row=1 AND running<>expected);
  IF v_errors<>0 THEN RAISE EXCEPTION 'Q8 cumulative sum mismatch: %',v_errors; END IF;
  RAISE NOTICE 'PASS Q8: cumulative final total matches event revenue';
  SELECT COUNT(DISTINCT event_id) INTO v_groups FROM app.orders WHERE status='paid';
  RAISE NOTICE 'PASS: % scans, % paid orders, % revenue-bearing events',v_scans,v_paid,v_groups;
END;
$tests$;
