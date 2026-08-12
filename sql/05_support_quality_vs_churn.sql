-- Q5: does support ticket volume or quality relate to churn
-- Block 1 aggregates support metrics to one row per account (LEFT JOIN so
-- accounts with zero tickets still count) and compares the churned vs
-- retained group on ticket volume, resolution time, satisfaction, first
-- response time, and escalations.
-- Block 2 buckets accounts by ticket count and checks churn rate per bucket,
-- since a simple two-group average can hide a non-linear relationship.

-- >>> churned_vs_retained_support_metrics
WITH acct_tickets AS (
    SELECT
        a.account_id,
        a.churn_flag,
        COUNT(t.ticket_id) AS ticket_count,
        AVG(t.resolution_time_hours) AS avg_resolution_hours,
        AVG(t.satisfaction_score) AS avg_satisfaction,
        AVG(t.first_response_time_minutes) AS avg_first_response_min,
        SUM(CASE WHEN t.escalation_flag THEN 1 ELSE 0 END) AS escalations
    FROM accounts a
    LEFT JOIN support_tickets t ON t.account_id = a.account_id
    GROUP BY a.account_id, a.churn_flag
)
SELECT
    churn_flag,
    COUNT(*) AS accounts,
    ROUND(AVG(ticket_count), 2) AS avg_tickets_per_account,
    ROUND(AVG(avg_resolution_hours), 1) AS avg_resolution_hours,
    ROUND(AVG(avg_satisfaction), 2) AS avg_satisfaction_score,
    ROUND(AVG(avg_first_response_min), 1) AS avg_first_response_min,
    ROUND(AVG(escalations), 2) AS avg_escalations_per_account
FROM acct_tickets
GROUP BY churn_flag
ORDER BY churn_flag;

-- >>> churn_rate_by_ticket_count_bucket
WITH acct_tickets AS (
    SELECT a.account_id, a.churn_flag, COUNT(t.ticket_id) AS ticket_count
    FROM accounts a
    LEFT JOIN support_tickets t ON t.account_id = a.account_id
    GROUP BY a.account_id, a.churn_flag
),
bucketed AS (
    SELECT
        account_id,
        churn_flag,
        CASE
            WHEN ticket_count = 0 THEN '0'
            WHEN ticket_count <= 2 THEN '1-2'
            WHEN ticket_count <= 4 THEN '3-4'
            ELSE '5+'
        END AS ticket_bucket
    FROM acct_tickets
)
SELECT
    ticket_bucket,
    COUNT(*) AS accounts,
    SUM(CASE WHEN churn_flag THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN churn_flag THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_rate_pct
FROM bucketed
GROUP BY ticket_bucket
ORDER BY CASE ticket_bucket WHEN '0' THEN 0 WHEN '1-2' THEN 1 WHEN '3-4' THEN 2 ELSE 3 END;
