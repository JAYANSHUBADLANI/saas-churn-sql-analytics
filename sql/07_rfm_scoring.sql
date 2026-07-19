-- Q7: RFM account scoring in SQL
-- Recency: days between an account's last feature_usage event and the
-- dataset's latest observed date (2024-12-31), lower is better.
-- Frequency: total count of feature_usage events for the account.
-- Monetary: mrr_amount of the account's most recent subscription (its
-- current run rate, not a historical sum).
-- Each dimension is scored into quintiles with NTILE(5), oriented so 5 is
-- always "best" (most recent, most frequent, highest paying). Accounts with
-- no usage history or no subscription are excluded since they cannot be
-- scored on all three dimensions.
-- Block 2 pulls out the accounts that are high value and high frequency but
-- have gone quiet recently (monetary and frequency quintile 4+, recency
-- quintile 1-2), the classic "high value, at risk" RFM segment.

-- >>> rfm_scores
WITH latest_sub AS (
    SELECT
        account_id,
        mrr_amount,
        ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY start_date DESC) AS rn
    FROM subscriptions
),
usage_agg AS (
    SELECT
        s.account_id,
        MAX(f.usage_date) AS last_usage_date,
        COUNT(*) AS frequency
    FROM feature_usage f
    JOIN subscriptions s ON f.subscription_id = s.subscription_id
    GROUP BY s.account_id
),
rfm_base AS (
    SELECT
        a.account_id,
        a.industry,
        a.plan_tier,
        a.churn_flag,
        ls.mrr_amount AS monetary,
        DATE_DIFF('day', ua.last_usage_date, DATE '2024-12-31') AS recency_days,
        ua.frequency AS frequency
    FROM accounts a
    LEFT JOIN latest_sub ls ON ls.account_id = a.account_id AND ls.rn = 1
    LEFT JOIN usage_agg ua ON ua.account_id = a.account_id
    WHERE ua.last_usage_date IS NOT NULL AND ls.mrr_amount IS NOT NULL
)
SELECT
    account_id,
    industry,
    plan_tier,
    churn_flag,
    monetary,
    recency_days,
    frequency,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS recency_score,
    NTILE(5) OVER (ORDER BY frequency ASC) AS frequency_score,
    NTILE(5) OVER (ORDER BY monetary ASC) AS monetary_score
FROM rfm_base;

-- >>> high_value_at_risk_accounts
WITH latest_sub AS (
    SELECT
        account_id,
        mrr_amount,
        ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY start_date DESC) AS rn
    FROM subscriptions
),
usage_agg AS (
    SELECT
        s.account_id,
        MAX(f.usage_date) AS last_usage_date,
        COUNT(*) AS frequency
    FROM feature_usage f
    JOIN subscriptions s ON f.subscription_id = s.subscription_id
    GROUP BY s.account_id
),
rfm_base AS (
    SELECT
        a.account_id,
        a.industry,
        a.plan_tier,
        a.churn_flag,
        ls.mrr_amount AS monetary,
        DATE_DIFF('day', ua.last_usage_date, DATE '2024-12-31') AS recency_days,
        ua.frequency AS frequency
    FROM accounts a
    LEFT JOIN latest_sub ls ON ls.account_id = a.account_id AND ls.rn = 1
    LEFT JOIN usage_agg ua ON ua.account_id = a.account_id
    WHERE ua.last_usage_date IS NOT NULL AND ls.mrr_amount IS NOT NULL
),
scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS recency_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS monetary_score
    FROM rfm_base
)
SELECT
    account_id,
    industry,
    plan_tier,
    churn_flag,
    monetary,
    recency_days,
    frequency,
    recency_score,
    frequency_score,
    monetary_score,
    (recency_score + frequency_score + monetary_score) AS rfm_total,
    (CAST(recency_score AS VARCHAR) || CAST(frequency_score AS VARCHAR) || CAST(monetary_score AS VARCHAR)) AS rfm_code
FROM scored
WHERE monetary_score >= 4 AND frequency_score >= 4 AND recency_score <= 2
ORDER BY monetary DESC;
