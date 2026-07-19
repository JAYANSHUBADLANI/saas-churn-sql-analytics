-- Q6: revenue and LTV by referral channel, and the monthly revenue trend per channel
-- Block 1 computes a simple LTV proxy per account: for every subscription,
-- mrr_amount times the number of months it ran (open subscriptions are
-- valued through the dataset's latest observed date, 2024-12-31), summed to
-- the account and then averaged per referral_source, alongside churn rate.
-- Block 2 is the same monthly-active-MRR logic as Q2 but grouped by
-- referral_source instead of plan_tier, to see the revenue trend per channel.

-- >>> ltv_and_churn_by_channel
WITH sub_rev AS (
    SELECT
        s.account_id,
        s.mrr_amount,
        GREATEST(DATE_DIFF('month', s.start_date, COALESCE(s.end_date, DATE '2024-12-31')), 1) AS months_active
    FROM subscriptions s
),
sub_rev2 AS (
    SELECT account_id, mrr_amount * months_active AS revenue
    FROM sub_rev
),
acct_rev AS (
    SELECT a.account_id, a.referral_source, a.churn_flag, SUM(sr.revenue) AS total_revenue
    FROM accounts a
    JOIN sub_rev2 sr ON sr.account_id = a.account_id
    GROUP BY a.account_id, a.referral_source, a.churn_flag
)
SELECT
    referral_source,
    COUNT(*) AS accounts,
    ROUND(AVG(total_revenue), 0) AS avg_revenue_per_account,
    ROUND(SUM(total_revenue), 0) AS total_revenue,
    SUM(CASE WHEN churn_flag THEN 1 ELSE 0 END) AS churned_accounts,
    ROUND(100.0 * SUM(CASE WHEN churn_flag THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_rate_pct
FROM acct_rev
GROUP BY referral_source
ORDER BY avg_revenue_per_account DESC;

-- >>> monthly_revenue_by_channel
WITH months AS (
    SELECT CAST(m AS DATE) AS month_start
    FROM generate_series(DATE '2023-01-01', DATE '2024-12-01', INTERVAL '1 month') AS t(m)
),
active_subs AS (
    SELECT mo.month_start, a.referral_source, s.mrr_amount
    FROM months mo
    JOIN subscriptions s
      ON s.start_date <= mo.month_start + INTERVAL '1 month' - INTERVAL '1 day'
     AND (s.end_date IS NULL OR s.end_date >= mo.month_start)
    JOIN accounts a ON a.account_id = s.account_id
)
SELECT month_start, referral_source, SUM(mrr_amount) AS mrr
FROM active_subs
GROUP BY month_start, referral_source
ORDER BY referral_source, month_start;
