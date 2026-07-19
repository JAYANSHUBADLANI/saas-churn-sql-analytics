-- Q3: plan tier upgrade funnel, and how upgrade/downgrade flags relate to churn
-- Funnel definition: for each account, find the earliest start_date it ever
-- had a subscription on Basic, on Pro, and on Enterprise. An account "moved"
-- Basic -> Pro if its first Pro date is later than its first Basic date, and
-- similarly Pro -> Enterprise. This is more robust than just checking "ever
-- had a Pro row" because some accounts downgrade too, so ordering matters.

-- >>> tier_upgrade_funnel
WITH per_account_tier_dates AS (
    SELECT
        account_id,
        MIN(CASE WHEN plan_tier = 'Basic' THEN start_date END) AS first_basic_date,
        MIN(CASE WHEN plan_tier = 'Pro' THEN start_date END) AS first_pro_date,
        MIN(CASE WHEN plan_tier = 'Enterprise' THEN start_date END) AS first_enterprise_date
    FROM subscriptions
    GROUP BY account_id
)
SELECT
    COUNT(*) FILTER (WHERE first_basic_date IS NOT NULL) AS ever_basic,
    COUNT(*) FILTER (
        WHERE first_basic_date IS NOT NULL AND first_pro_date IS NOT NULL
        AND first_pro_date > first_basic_date
    ) AS basic_then_pro,
    COUNT(*) FILTER (
        WHERE first_basic_date IS NOT NULL AND first_pro_date IS NOT NULL AND first_pro_date > first_basic_date
        AND first_enterprise_date IS NOT NULL AND first_enterprise_date > first_pro_date
    ) AS basic_then_pro_then_enterprise,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE first_basic_date IS NOT NULL AND first_pro_date IS NOT NULL AND first_pro_date > first_basic_date
        ) / NULLIF(COUNT(*) FILTER (WHERE first_basic_date IS NOT NULL), 0), 1
    ) AS basic_to_pro_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE first_basic_date IS NOT NULL AND first_pro_date IS NOT NULL AND first_pro_date > first_basic_date
            AND first_enterprise_date IS NOT NULL AND first_enterprise_date > first_pro_date
        ) / NULLIF(COUNT(*) FILTER (
            WHERE first_basic_date IS NOT NULL AND first_pro_date IS NOT NULL AND first_pro_date > first_basic_date
        ), 0), 1
    ) AS pro_to_enterprise_pct
FROM per_account_tier_dates;

-- >>> upgrade_downgrade_vs_churn
SELECT
    upgrade_flag,
    downgrade_flag,
    COUNT(*) AS subscriptions,
    SUM(CASE WHEN churn_flag THEN 1 ELSE 0 END) AS churned,
    ROUND(100.0 * SUM(CASE WHEN churn_flag THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_rate_pct
FROM subscriptions
GROUP BY upgrade_flag, downgrade_flag
ORDER BY upgrade_flag, downgrade_flag;
