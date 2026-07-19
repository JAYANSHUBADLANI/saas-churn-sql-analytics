-- Q1: cohort retention curve
-- Cohort = signup month (accounts.signup_date, truncated to month).
-- An account is "retained" at a given horizon if it has not yet hit its
-- first churn event by signup_date + N months. Reactivations after a first
-- churn are not treated as un-churning the retention curve, this measures
-- "still on its original run" at each horizon, which is the standard
-- definition for a retention curve.
-- Cohorts that haven't reached a horizon yet (given the dataset's latest
-- signup date) are excluded from that horizon's denominator so young
-- cohorts don't drag down the 12-month numbers with zero real observations.

-- >>> overall
WITH first_churn AS (
    SELECT account_id, MIN(churn_date) AS first_churn_date
    FROM churn_events
    GROUP BY account_id
),
cohort AS (
    SELECT
        a.account_id,
        a.signup_date,
        fc.first_churn_date
    FROM accounts a
    LEFT JOIN first_churn fc ON fc.account_id = a.account_id
),
horizons AS (
    SELECT * FROM (VALUES (1), (3), (6), (12)) AS h(months_out)
),
flagged AS (
    SELECT
        h.months_out,
        c.account_id,
        CASE
            WHEN c.first_churn_date IS NULL THEN 1
            WHEN c.first_churn_date > c.signup_date + INTERVAL (h.months_out) MONTH THEN 1
            ELSE 0
        END AS is_retained,
        CASE
            WHEN c.signup_date + INTERVAL (h.months_out) MONTH <= (SELECT MAX(signup_date) FROM accounts)
            THEN 1 ELSE 0
        END AS eligible
    FROM cohort c
    CROSS JOIN horizons h
)
SELECT
    months_out,
    COUNT(*) FILTER (WHERE eligible = 1) AS eligible_accounts,
    SUM(is_retained) FILTER (WHERE eligible = 1) AS retained_accounts,
    ROUND(100.0 * SUM(is_retained) FILTER (WHERE eligible = 1) / NULLIF(COUNT(*) FILTER (WHERE eligible = 1), 0), 1) AS retention_pct
FROM flagged
GROUP BY months_out
ORDER BY months_out;

-- >>> by_cohort
WITH first_churn AS (
    SELECT account_id, MIN(churn_date) AS first_churn_date
    FROM churn_events
    GROUP BY account_id
),
cohort AS (
    SELECT
        a.account_id,
        DATE_TRUNC('month', a.signup_date) AS cohort_month,
        a.signup_date,
        fc.first_churn_date
    FROM accounts a
    LEFT JOIN first_churn fc ON fc.account_id = a.account_id
),
horizons AS (
    SELECT * FROM (VALUES (1), (3), (6), (12)) AS h(months_out)
),
flagged AS (
    SELECT
        c.cohort_month,
        h.months_out,
        c.account_id,
        CASE
            WHEN c.first_churn_date IS NULL THEN 1
            WHEN c.first_churn_date > c.signup_date + INTERVAL (h.months_out) MONTH THEN 1
            ELSE 0
        END AS is_retained,
        CASE
            WHEN c.signup_date + INTERVAL (h.months_out) MONTH <= (SELECT MAX(signup_date) FROM accounts)
            THEN 1 ELSE 0
        END AS eligible
    FROM cohort c
    CROSS JOIN horizons h
)
SELECT
    cohort_month,
    months_out,
    COUNT(*) FILTER (WHERE eligible = 1) AS eligible_accounts,
    SUM(is_retained) FILTER (WHERE eligible = 1) AS retained_accounts,
    ROUND(100.0 * SUM(is_retained) FILTER (WHERE eligible = 1) / NULLIF(COUNT(*) FILTER (WHERE eligible = 1), 0), 1) AS retention_pct
FROM flagged
GROUP BY cohort_month, months_out
ORDER BY cohort_month, months_out;
