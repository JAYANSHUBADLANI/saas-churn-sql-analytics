-- Q2: MRR trend and month-over-month growth, broken out by plan tier
-- A subscription is "active" in a given month if its start_date falls on or
-- before the month's last day and its end_date (if any) falls on or after
-- the month's first day. GROUPING SETS gives both the per-tier rows and an
-- "All" total row in one pass, LAG() over each tier's own time series gives
-- the month-over-month growth percentage.

WITH months AS (
    SELECT CAST(m AS DATE) AS month_start
    FROM generate_series(DATE '2023-01-01', DATE '2024-12-01', INTERVAL '1 month') AS t(m)
),
active_subs AS (
    SELECT
        mo.month_start,
        s.plan_tier,
        s.mrr_amount
    FROM months mo
    JOIN subscriptions s
      ON s.start_date <= mo.month_start + INTERVAL '1 month' - INTERVAL '1 day'
     AND (s.end_date IS NULL OR s.end_date >= mo.month_start)
),
monthly_mrr AS (
    SELECT month_start, COALESCE(plan_tier, 'All') AS plan_tier, SUM(mrr_amount) AS mrr
    FROM active_subs
    GROUP BY GROUPING SETS ((month_start, plan_tier), (month_start))
)
SELECT
    month_start,
    plan_tier,
    mrr,
    ROUND(
        100.0 * (mrr - LAG(mrr) OVER (PARTITION BY plan_tier ORDER BY month_start))
        / NULLIF(LAG(mrr) OVER (PARTITION BY plan_tier ORDER BY month_start), 0),
        2
    ) AS mom_growth_pct
FROM monthly_mrr
ORDER BY plan_tier, month_start;
