-- Q8: churn reason breakdown, and whether churn was preceded by a plan change
-- preceding_upgrade_flag / preceding_downgrade_flag are already computed in
-- the source data as "had an upgrade/downgrade within 90 days before
-- churning", so this reports the reason_code distribution alongside those
-- rates rather than recomputing the 90-day window from subscriptions.
-- Block 2 gives the overall split regardless of reason.

-- >>> reason_breakdown
SELECT
    reason_code,
    COUNT(*) AS churn_events,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_churns,
    ROUND(AVG(refund_amount_usd), 2) AS avg_refund_usd,
    ROUND(100.0 * AVG(CASE WHEN preceding_upgrade_flag THEN 1 ELSE 0 END), 1) AS pct_preceded_by_upgrade,
    ROUND(100.0 * AVG(CASE WHEN preceding_downgrade_flag THEN 1 ELSE 0 END), 1) AS pct_preceded_by_downgrade,
    ROUND(100.0 * AVG(CASE WHEN is_reactivation THEN 1 ELSE 0 END), 1) AS pct_reactivations
FROM churn_events
GROUP BY reason_code
ORDER BY churn_events DESC;

-- >>> overall_preceding_change_split
SELECT
    SUM(CASE WHEN preceding_upgrade_flag THEN 1 ELSE 0 END) AS preceded_by_upgrade,
    SUM(CASE WHEN preceding_downgrade_flag THEN 1 ELSE 0 END) AS preceded_by_downgrade,
    SUM(CASE WHEN NOT preceding_upgrade_flag AND NOT preceding_downgrade_flag THEN 1 ELSE 0 END) AS no_preceding_change,
    COUNT(*) AS total_churn_events
FROM churn_events;
