# SaaS Subscription and Churn Analytics (SQL)

A SQL first analytics case study on a synthetic SaaS subscription dataset. Every
number below comes straight out of a `.sql` file in [`sql/`](sql/), run against
a DuckDB database built from the raw CSVs, with the output written to
[`results/`](results/) as CSV. I did the actual analysis (cohorting, trend,
funnel, ranking, scoring) in SQL itself, not in pandas, since that is the
specific skill analyst round interviews test.

## Dataset

[RavenStack: Synthetic SaaS Dataset](https://www.kaggle.com/datasets/rivalytics/saas-subscription-and-churn-analytics-dataset),
created by **River @ Rivalytics** and distributed under a permissive,
MIT like license (fully synthetic, no PII). Credit to the original author,
required by the dataset's license.

Five tables, linked by foreign keys, 500 accounts, 5,000 subscriptions,
25,000 feature usage events, 2,000 support tickets, and 600 churn events:

| Table | Rows | Key columns |
|---|---|---|
| `accounts` | 500 | account_id (PK), industry, country, signup_date, referral_source, plan_tier, churn_flag |
| `subscriptions` | 5,000 | subscription_id (PK), account_id (FK), start_date, end_date, plan_tier, mrr_amount, upgrade_flag, downgrade_flag, churn_flag |
| `feature_usage` | 25,000 | usage_id (PK), subscription_id (FK), usage_date, feature_name (40 distinct), usage_count, error_count |
| `support_tickets` | 2,000 | ticket_id (PK), account_id (FK), resolution_time_hours, priority, satisfaction_score, escalation_flag |
| `churn_events` | 600 | churn_event_id (PK), account_id (FK), churn_date, reason_code, refund_amount_usd, preceding_upgrade_flag, preceding_downgrade_flag |

## How to run it

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
kaggle datasets download rivalytics/saas-subscription-and-churn-analytics-dataset --unzip -p data/raw
.venv/bin/python scripts/run_analysis.py
```

`scripts/run_analysis.py` loads the five CSVs into an in-memory DuckDB
database and runs every `.sql` file in `sql/` against it, writing each
query's real output to `results/`. There is no persisted database file
committed to the repo, running the script rebuilds everything from the CSVs
every time, so it's fully reproducible from source.

## Data notes and modeling decisions

The dataset intentionally ships with some inconsistency between tables
(the source README calls out "mid-cycle plan changes, null fields,
reactivations" as deliberate edge cases), so I had to pick a defensible
definition of "churned" for each question rather than assume one flag
answers everything:

- `accounts.churn_flag` doesn't always agree with whether that account's
  *latest* subscription is marked churned. 99 accounts have `churn_flag =
  True` at the account level but an active latest subscription (they
  churned once and came back), and 34 accounts show the opposite. This is
  consistent with reactivations, 61 of the 600 churn events are flagged
  `is_reactivation = True`.
- For **cohort retention** (Q1), I used `churn_events.churn_date` directly:
  an account is "retained" at a horizon if it hasn't hit its *first* churn
  event yet by that point. This is the standard definition for a retention
  curve and is what the question asks for (a self join against churn dates).
- For **account level comparisons** (Q5, Q6, Q7), I used `accounts.churn_flag`
  since it's the dataset's own account level label.
- For **Q3's upgrade/downgrade vs churn**, I used `subscriptions.churn_flag`
  since upgrades, downgrades, and churn are all recorded on the same
  subscription row.

## Q1: cohort retention

[`sql/01_cohort_retention.sql`](sql/01_cohort_retention.sql)

Retention curve pooled across all 24 monthly signup cohorts (young cohorts
that haven't reached a given horizon yet are excluded from that horizon,
so the 12 month number isn't dragged down by accounts that only signed up
last month):

| Months after signup | Eligible accounts | Retained | Retention % |
|---|---|---|---|
| 1 | 483 | 401 | 83.0% |
| 3 | 420 | 285 | 67.9% |
| 6 | 348 | 195 | 56.0% |
| 12 | 227 | 93 | 41.0% |

I found the steepest drop happens between months 3 and 12: retention falls
from 67.9% to 41.0%, a 27 point drop, while the first month only loses 17
points (100% to 83%). Whatever is driving churn here mostly plays out over
the second half of the first year, not immediately after signup. The
[per-cohort breakdown](results/01_cohort_retention__by_cohort.csv) shows
individual monthly cohorts swing more (some 12 month cohorts as low as 20%,
some as high as 80%), which is expected noise at roughly 20 accounts per
cohort.

## Q2: MRR trend and growth by plan tier

[`sql/02_mrr_trend.sql`](sql/02_mrr_trend.sql)

Total MRR grew from $4,684 in January 2023 to $10,734,251 in December 2024.
Growth was fastest early (over 100% month over month in the first five
months, purely a small base number effect) and settled into a steadier
18 to 24% month over month pace through most of 2024:

| Month | Plan tier | MRR | MoM growth % |
|---|---|---|---|
| 2024-07 | All | $4,541,221 | 17.83% |
| 2024-08 | All | $5,161,618 | 13.66% |
| 2024-09 | All | $6,113,247 | 18.44% |
| 2024-10 | All | $7,208,953 | 17.92% |
| 2024-11 | All | $8,647,936 | 19.96% |
| 2024-12 | All | $10,734,251 | 24.13% |

By December 2024, Enterprise carries most of the revenue ($8,020,297 of the
$10,734,251 total, 74.7%), with Pro at $2,002,385 and Basic at $711,569.
Pro is also growing fastest month over month in December (29.1% vs 23.1%
for Enterprise and 22.0% for Basic), even though it's the smallest slice by
dollar volume right now.

## Q3: plan tier upgrade funnel and churn

[`sql/03_upgrade_downgrade_funnel.sql`](sql/03_upgrade_downgrade_funnel.sql)

Of the 480 accounts whose first subscription was on Basic, 221 (46.0%) later
had a subscription on Pro, and of those, 72 (32.6%) went on to Enterprise:

| Step | Accounts | Conversion |
|---|---|---|
| Started on Basic | 480 | (baseline) |
| Basic then Pro | 221 | 46.0% |
| Basic then Pro then Enterprise | 72 | 32.6% |

Whether a subscription churns doesn't track cleanly with whether it upgraded
or downgraded:

| Upgraded | Downgraded | Subscriptions | Churn rate |
|---|---|---|---|
| No | No | 4,276 | 9.8% |
| No | Yes | 195 | 10.8% |
| Yes | No | 506 | 8.3% |
| Yes | Yes | 23 | 17.4% |

Subscriptions that only upgraded churn slightly less than the baseline (8.3%
vs 9.8%), which fits the usual story of upgrades signaling engagement. The
23 subscriptions that both upgraded and downgraded at some point churn at
17.4%, roughly double the baseline, though that's a small group (23
subscriptions) so I wouldn't read too much precision into that one number.

## Q4: feature adoption

[`sql/04_feature_adoption.sql`](sql/04_feature_adoption.sql)

Ranked all 40 features by total usage count. The most used feature
(`feature_32`, 6,686 total usage count across 659 events) only beats the
least used (`feature_23`, 5,601 total usage count across 563 events) by
about 19%, adoption is fairly even across the whole feature set rather than
following a sharp long tail:

| Rank | Feature | Usage events | Total usage count | Error rate % |
|---|---|---|---|---|
| 1 | feature_32 | 659 | 6,686 | 5.34% |
| 2 | feature_15 | 640 | 6,621 | 5.27% |
| 3 | feature_6 | 655 | 6,546 | 5.18% |
| 39 | feature_5 | 577 | 5,759 | 5.49% |
| 40 | feature_23 | 563 | 5,601 | 5.46% |

Breaking usage down by industry, plan tier, and quarter with `RANK()` shows
the top 3 features per segment shift quarter to quarter rather than staying
fixed (see [the full segment level ranking](results/04_feature_adoption__top_features_by_segment_quarter.csv),
375 rows), which suggests feature adoption here isn't dominated by one or
two "hero" features but is genuinely spread across the catalog.

## Q5: support quality vs churn

[`sql/05_support_quality_vs_churn.sql`](sql/05_support_quality_vs_churn.sql)

| Churned | Accounts | Avg tickets | Avg resolution hrs | Avg satisfaction | Avg escalations |
|---|---|---|---|---|---|
| No | 390 | 4.02 | 36.5 | 3.95 | 0.18 |
| Yes | 110 | 3.93 | 35.5 | 4.00 | 0.22 |

| Ticket count | Accounts | Churned | Churn rate |
|---|---|---|---|
| 0 | 8 | 2 | 25.0% |
| 1-2 | 104 | 26 | 25.0% |
| 3-4 | 195 | 44 | 22.6% |
| 5+ | 193 | 38 | 19.7% |

I didn't find the relationship I expected here. Churned and retained
accounts have essentially identical ticket volume, resolution time, and
satisfaction scores, and churn rate actually drifts *down* slightly as
ticket count goes up (25.0% at 1-2 tickets vs 19.7% at 5+). In this
dataset, support experience isn't a visible driver of churn on its own,
which is a real (if less exciting) finding worth stating plainly rather
than forcing a correlation that isn't there.

## Q6: revenue and LTV by referral channel

[`sql/06_referral_channel_ltv.sql`](sql/06_referral_channel_ltv.sql)

LTV proxy per account: each subscription's `mrr_amount` times the number of
months it ran, summed per account, then averaged by referral source:

| Referral source | Accounts | Avg revenue/account | Total revenue | Churn rate |
|---|---|---|---|---|
| ads | 98 | $118,407 | $11,603,871 | 23.5% |
| partner | 89 | $114,844 | $10,221,137 | 14.6% |
| organic | 114 | $113,661 | $12,957,389 | 17.5% |
| other | 103 | $102,859 | $10,594,457 | 24.3% |
| event | 96 | $93,110 | $8,938,537 | 30.2% |

`ads` brings in the highest average revenue per account, but `partner` is
the healthier channel overall: close to the top on revenue per account
($114,844) with the lowest churn rate by a wide margin (14.6%, vs 23 to 30%
everywhere else). `event` is the weakest channel on both dimensions at
once, lowest average revenue and highest churn rate.

## Q7: RFM account scoring

[`sql/07_rfm_scoring.sql`](sql/07_rfm_scoring.sql)

Recency (days since last feature usage event), frequency (count of usage
events), and monetary (current subscription's `mrr_amount`) each scored into
quintiles with `NTILE(5)`, 5 always being "best" (most recent, most
frequent, highest paying). [Full scored table](results/07_rfm_scoring__rfm_scores.csv)
covers all 500 accounts that have both a subscription and usage history.

Filtering to monetary and frequency quintile 4+ with recency quintile 1-2
(high value, high engagement historically, gone quiet recently) surfaces 16
accounts, the highest value at-risk segment:

| Account | Industry | Plan | Monthly value | Days since last use | Usage events |
|---|---|---|---|---|---|
| A-0651a4 | HealthTech | Pro | $12,935 | 15 | 69 |
| A-503d5a | FinTech | Enterprise | $11,144 | 16 | 59 |
| A-9b9fe9 | EdTech | Basic | $9,950 | 16 | 58 |
| A-86902e | HealthTech | Enterprise | $6,766 | 19 | 63 |
| A-54ecc2 | Cybersecurity | Enterprise | $5,572 | 22 | 56 |

The top account here, A-0651a4, pays $12,935 a month and had 69 usage
events historically, but hasn't logged a feature usage event in 15 days.
That's exactly the kind of account a retention team would want a proactive
check-in on before it shows up as a full churn event.

## Q8: churn reason breakdown

[`sql/08_churn_reason_breakdown.sql`](sql/08_churn_reason_breakdown.sql)

| Reason | Churn events | % of churns | Avg refund | Preceded by upgrade | Preceded by downgrade |
|---|---|---|---|---|---|
| features | 114 | 19.0% | $16.72 | 14.9% | 7.9% |
| support | 104 | 17.3% | $11.73 | 26.9% | 12.5% |
| budget | 104 | 17.3% | $12.00 | 23.1% | 5.8% |
| unknown | 95 | 15.8% | $18.34 | 20.0% | 9.5% |
| competitor | 92 | 15.3% | $13.08 | 18.5% | 13.0% |
| pricing | 91 | 15.2% | $14.65 | 19.8% | 4.4% |

Reasons are fairly evenly split (15.2% to 19.0% across all six codes),
there's no single dominant driver of churn in this dataset. Across all 600
churn events, 123 (20.5%) had a preceding upgrade in the 90 days before
churning and 53 (8.8%) had a preceding downgrade, but the large majority,
432 events (72.0%), had no preceding plan change at all. Support related
churn has the highest preceding upgrade rate (26.9%), which reads as
accounts that paid more, expecting a better experience, and left when they
didn't get one.

## Repo structure

```
sql/                  8 .sql files, one per business question above
scripts/run_analysis.py   loads the CSVs into DuckDB, runs sql/, writes results/
data/raw/              the 5 source CSVs
results/               real query output, one CSV per result block
```

## Tech stack

DuckDB (window functions, CTEs, `NTILE`, `GROUPING SETS`), Python 3.13 only
as the runner around the SQL (`duckdb` and `pandas` for I/O, not analysis),
Kaggle CLI for the data pull.

## License

MIT, see [LICENSE](LICENSE). The dataset itself is credited to River @
Rivalytics per its own license terms.
