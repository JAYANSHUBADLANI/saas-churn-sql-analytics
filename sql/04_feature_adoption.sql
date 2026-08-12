-- Q4: feature adoption, overall ranking and trend by industry/plan tier
-- Block 1 ranks all 40 features by total usage_count with RANK().
-- Block 2 joins feature_usage up through subscriptions to accounts to get
-- industry and plan_tier, buckets usage into quarters, and uses RANK()
-- partitioned by industry/plan_tier/quarter to find each segment's top 3
-- features per quarter, which is what an adoption trend actually needs
-- (not just a single overall ranking).

-- >>> overall_ranking
SELECT
    feature_name,
    COUNT(*) AS usage_events,
    SUM(usage_count) AS total_usage_count,
    ROUND(AVG(usage_duration_secs), 1) AS avg_duration_secs,
    SUM(error_count) AS total_errors,
    ROUND(100.0 * SUM(error_count) / NULLIF(SUM(usage_count), 0), 2) AS error_rate_pct,
    RANK() OVER (ORDER BY SUM(usage_count) DESC) AS usage_rank
FROM feature_usage
GROUP BY feature_name
ORDER BY usage_rank, feature_name;

-- >>> top_features_by_segment_quarter
WITH usage_joined AS (
    SELECT
        f.feature_name,
        f.usage_count,
        f.usage_date,
        a.industry,
        s.plan_tier
    FROM feature_usage f
    JOIN subscriptions s ON f.subscription_id = s.subscription_id
    JOIN accounts a ON s.account_id = a.account_id
),
quarterly AS (
    SELECT
        industry,
        plan_tier,
        DATE_TRUNC('quarter', usage_date) AS quarter,
        feature_name,
        SUM(usage_count) AS total_usage
    FROM usage_joined
    GROUP BY industry, plan_tier, quarter, feature_name
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY industry, plan_tier, quarter ORDER BY total_usage DESC) AS feature_rank
    FROM quarterly
)
SELECT industry, plan_tier, quarter, feature_name, total_usage, feature_rank
FROM ranked
WHERE feature_rank <= 3
ORDER BY industry, plan_tier, quarter, feature_rank, feature_name;
