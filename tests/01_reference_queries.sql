/*==============================================================================
01_reference_queries.sql - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Independent ground truth for all five questions.

These are hand-written against the base tables and the analytic views. They do
NOT go through a semantic view, so they cannot inherit the semantic layer's
assumptions. If the agent and these queries disagree, these queries win until
proven otherwise.

Run as a role with broad entitlement. Expected values are recorded in
docs/EXPECTED_RESULTS.md and are valid only for RELEASE_ID
'backstage-v1-seed-8831'.
==============================================================================*/

USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

/*------------------------------------------------------------------------------
Q0. Ambiguity check, which must run before any question that names a title.

'Neon Orchard' is held by three different recordings on three different labels. A
question naming the title alone is underspecified; the ISRC or the artist is what
makes it answerable.
------------------------------------------------------------------------------*/

SELECT 'Q0 ambiguity' AS check_name, TRACK_TITLE, RECORDING_COUNT, ARTISTS, ISRCS
FROM V_TRACK_TITLE_AMBIGUITY
WHERE TRACK_TITLE = 'Neon Orchard';

/*------------------------------------------------------------------------------
Q1. Revenue concentration.

"What percentage of our 2025 Amazon revenue came from <track>?"

Numerator and denominator share one scope: same calendar year, same Amazon
family, same revenue basis, same released-period gate, and the same entitlement
filter, because both sides read the same policy-protected fact. Only the
numerator narrows to the recording.

The denominator is "Amazon revenue visible to the caller," not "all Amazon
revenue." Those differ for a scoped user and the label on the answer must say so.

There are TWO separate unanswerable cases and neither is zero percent:

  1. The denominator is zero or absent. Nothing to divide by. DIV0NULL returns
     NULL rather than inventing a zero.

  2. The recording is not present in the caller's visible data at all. This is the
     dangerous one, because the denominator is perfectly healthy and the numerator
     sums to zero, so a naive query returns a confident "0.00%". For a user scoped
     away from that recording's label, 0% is a false statement: it asserts the
     track earned nothing when the truth is that the caller cannot see it. The
     target line count is therefore returned alongside the ratio, and the verdict
     column refuses rather than reporting a percentage.
------------------------------------------------------------------------------*/

WITH scoped AS (
    SELECT TRACK_KEY, ISRC, LABEL_NET_USD
    FROM V_LABEL_REVENUE
    WHERE DSP_FAMILY = 'Amazon'
      AND IS_RELEASED
      AND STATEMENT_MONTH >= '2025-01-01'::DATE
      AND STATEMENT_MONTH <  '2026-01-01'::DATE
)
SELECT
    'Q1 concentration' AS check_name,
    'QZSYN2400001'     AS target_isrc,
    COUNT_IF(ISRC = 'QZSYN2400001')                                              AS target_lines_visible,
    ROUND(SUM(CASE WHEN ISRC = 'QZSYN2400001' THEN LABEL_NET_USD ELSE 0 END), 2) AS track_revenue_usd,
    ROUND(SUM(LABEL_NET_USD), 2)                                                 AS amazon_revenue_visible_usd,
    ROUND(
        100 * DIV0NULL(
            SUM(CASE WHEN ISRC = 'QZSYN2400001' THEN LABEL_NET_USD ELSE 0 END),
            SUM(LABEL_NET_USD)
        ), 2)                                                                    AS pct_of_visible_amazon_2025,
    CASE
        WHEN COALESCE(SUM(LABEL_NET_USD), 0) = 0
            THEN 'UNANSWERABLE: no Amazon revenue visible to you in 2025, so there is nothing to divide by'
        WHEN COUNT_IF(ISRC = 'QZSYN2400001') = 0
            THEN 'UNANSWERABLE: that recording does not appear in the data visible to you. This is NOT zero percent.'
        ELSE 'ANSWERABLE'
    END                                                                          AS verdict,
    COUNT(*)                                                                     AS statement_lines_in_scope
FROM scoped;

/*------------------------------------------------------------------------------
Q2. Label prioritization by month-over-month revenue increase.

Ranked by ABSOLUTE increase, not percentage. The two orderings genuinely differ
in this data, which is the point: a label can post the largest percentage jump
and still be a small absolute mover.

Periods are the two newest RELEASED months. 2026-08 exists in the data with
IS_RELEASED = FALSE and is excluded, so the comparison is 2026-07 against
2026-06.

Three distinct cases are kept apart:
  - prior month absent entirely  -> NULL prior, change is NULL, reported as
                                    NO PRIOR PERIOD. Missing is not zero.
  - prior month present and zero -> reported as NEW, never as infinite growth.
  - prior month present, nonzero -> a real percentage.

Only labels that actually INCREASED are returned. A request for "the top 50" does
not license padding the list with decliners to reach 50; if fewer than 50 labels
grew, the honest answer is a shorter list plus the count. The companion query
below reports how many labels grew, so the length of the list is explained rather
than left to be inferred.
------------------------------------------------------------------------------*/

-- How many labels grew at all. This bounds what a "top 50" can honestly contain.
WITH released AS (
    SELECT STATEMENT_MONTH
    FROM DIM_STATEMENT_MONTH
    WHERE IS_RELEASED
    QUALIFY ROW_NUMBER() OVER (ORDER BY STATEMENT_MONTH DESC) <= 2
),
bounds AS (
    SELECT MAX(STATEMENT_MONTH) AS current_month, MIN(STATEMENT_MONTH) AS prior_month FROM released
),
label_month AS (
    SELECT r.LABEL_ID, r.STATEMENT_MONTH, SUM(r.LABEL_NET_USD) AS revenue_usd
    FROM V_LABEL_REVENUE r
    JOIN released rel ON rel.STATEMENT_MONTH = r.STATEMENT_MONTH
    WHERE r.IS_RELEASED
    GROUP BY r.LABEL_ID, r.STATEMENT_MONTH
),
paired AS (
    SELECT
        lm.LABEL_ID,
        MAX(CASE WHEN lm.STATEMENT_MONTH = b.current_month THEN lm.revenue_usd END) AS current_usd,
        MAX(CASE WHEN lm.STATEMENT_MONTH = b.prior_month   THEN lm.revenue_usd END) AS prior_usd
    FROM label_month lm CROSS JOIN bounds b
    GROUP BY lm.LABEL_ID
)
SELECT
    'Q2 growth population' AS check_name,
    (SELECT current_month FROM bounds) AS current_month,
    (SELECT prior_month   FROM bounds) AS prior_month,
    COUNT(*)                                                     AS labels_with_current_revenue,
    COUNT_IF(current_usd > prior_usd)                            AS labels_increased,
    COUNT_IF(current_usd <= prior_usd)                           AS labels_declined_or_flat,
    COUNT_IF(prior_usd IS NULL)                                  AS labels_no_prior_period
FROM paired
WHERE current_usd IS NOT NULL;

/*------------------------------------------------------------------------------
Q2 ranking, increases only, ordered by absolute change.
------------------------------------------------------------------------------*/

WITH released AS (
    SELECT STATEMENT_MONTH
    FROM DIM_STATEMENT_MONTH
    WHERE IS_RELEASED
    QUALIFY ROW_NUMBER() OVER (ORDER BY STATEMENT_MONTH DESC) <= 2
),
bounds AS (
    SELECT MAX(STATEMENT_MONTH) AS current_month, MIN(STATEMENT_MONTH) AS prior_month
    FROM released
),
label_month AS (
    SELECT r.LABEL_ID, r.LABEL_NAME, r.STATEMENT_MONTH, SUM(r.LABEL_NET_USD) AS revenue_usd
    FROM V_LABEL_REVENUE r
    JOIN released rel ON rel.STATEMENT_MONTH = r.STATEMENT_MONTH
    WHERE r.IS_RELEASED
    GROUP BY r.LABEL_ID, r.LABEL_NAME, r.STATEMENT_MONTH
),
paired AS (
    SELECT
        lm.LABEL_ID,
        MAX(lm.LABEL_NAME) AS label_name,
        MAX(CASE WHEN lm.STATEMENT_MONTH = b.current_month THEN lm.revenue_usd END) AS current_usd,
        MAX(CASE WHEN lm.STATEMENT_MONTH = b.prior_month   THEN lm.revenue_usd END) AS prior_usd
    FROM label_month lm
    CROSS JOIN bounds b
    GROUP BY lm.LABEL_ID
)
SELECT
    'Q2 label growth' AS check_name,
    ROW_NUMBER() OVER (ORDER BY (current_usd - prior_usd) DESC NULLS LAST) AS rank_by_absolute,
    label_name,
    ROUND(prior_usd, 2)                    AS prior_month_usd,
    ROUND(current_usd, 2)                  AS current_month_usd,
    ROUND(current_usd - prior_usd, 2)      AS absolute_change_usd,
    CASE
        WHEN prior_usd IS NULL THEN 'NO PRIOR PERIOD'
        WHEN prior_usd = 0     THEN 'NEW'
        ELSE TO_VARCHAR(ROUND(100 * (current_usd - prior_usd) / prior_usd, 1)) || '%'
    END                                    AS percent_change
FROM paired
WHERE current_usd IS NOT NULL
  -- Increases only. See the population query above for the total that grew.
  AND (prior_usd IS NULL OR current_usd > prior_usd)
ORDER BY rank_by_absolute
LIMIT 50;

/*------------------------------------------------------------------------------
Q3. Cross-DSP August trend for one recording.

Returns one row per family per observed day. Days with no observation are simply
absent: no zero-fill, no densification against a calendar, no interpolation. A
chart drawn from this must break where the data breaks.

The companion coverage query below is what makes the gap legible instead of
looking like a decline.
------------------------------------------------------------------------------*/

SELECT
    'Q3 daily trend' AS check_name,
    ACTIVITY_DATE,
    DSP_FAMILY,
    SUM(STREAMS) AS streams
FROM V_DAILY_STREAMS
WHERE ISRC = 'QZSYN2400001'
  AND ACTIVITY_DATE >= '2026-08-01'::DATE
  AND ACTIVITY_DATE <  '2026-09-01'::DATE
GROUP BY ACTIVITY_DATE, DSP_FAMILY
ORDER BY ACTIVITY_DATE, DSP_FAMILY;

-- Q3 coverage. 31 calendar days in August 2026; anything short of that is a gap.
SELECT
    'Q3 coverage' AS check_name,
    DSP_FAMILY,
    COUNT(DISTINCT ACTIVITY_DATE)      AS days_observed,
    31 - COUNT(DISTINCT ACTIVITY_DATE) AS days_missing,
    MIN(ACTIVITY_DATE)                 AS first_observed,
    MAX(ACTIVITY_DATE)                 AS last_observed,
    SUM(STREAMS)                       AS streams_in_month
FROM V_DAILY_STREAMS
WHERE ISRC = 'QZSYN2400001'
  AND ACTIVITY_DATE >= '2026-08-01'::DATE
  AND ACTIVITY_DATE <  '2026-09-01'::DATE
GROUP BY DSP_FAMILY
ORDER BY streams_in_month DESC;

/*------------------------------------------------------------------------------
Q4. Snapshot of the latest seven COMPLETE days.

The window is anchored to IS_COMPLETE, not to the newest row present. The six
most recent days are still landing and are deliberately excluded. The exact dates
are returned so the reader can see the window rather than trust the phrase
"latest seven days."
------------------------------------------------------------------------------*/

WITH window_days AS (
    SELECT ACTIVITY_DATE
    FROM DIM_ACTIVITY_DAY
    WHERE IS_COMPLETE
    QUALIFY ROW_NUMBER() OVER (ORDER BY ACTIVITY_DATE DESC) <= 7
)
SELECT
    'Q4 seven complete days' AS check_name,
    MIN(w.ACTIVITY_DATE)            AS window_start,
    MAX(w.ACTIVITY_DATE)            AS window_end,
    COUNT(DISTINCT w.ACTIVITY_DATE) AS days_in_window,
    SUM(s.STREAMS)                  AS total_streams,
    ROUND(AVG(daily.day_streams), 1) AS avg_streams_per_day
FROM window_days w
LEFT JOIN V_DAILY_STREAMS s
       ON s.ACTIVITY_DATE = w.ACTIVITY_DATE AND s.ISRC = 'QZSYN2400001'
LEFT JOIN (
    SELECT ACTIVITY_DATE, SUM(STREAMS) AS day_streams
    FROM V_DAILY_STREAMS
    WHERE ISRC = 'QZSYN2400001'
    GROUP BY ACTIVITY_DATE
) daily ON daily.ACTIVITY_DATE = w.ACTIVITY_DATE;

-- Q4 detail: the per-day, per-family breakdown inside that window.
WITH window_days AS (
    SELECT ACTIVITY_DATE
    FROM DIM_ACTIVITY_DAY
    WHERE IS_COMPLETE
    QUALIFY ROW_NUMBER() OVER (ORDER BY ACTIVITY_DATE DESC) <= 7
)
SELECT
    'Q4 detail' AS check_name,
    s.ACTIVITY_DATE,
    s.DSP_FAMILY,
    SUM(s.STREAMS) AS streams
FROM V_DAILY_STREAMS s
JOIN window_days w ON w.ACTIVITY_DATE = s.ACTIVITY_DATE
WHERE s.ISRC = 'QZSYN2400001'
GROUP BY s.ACTIVITY_DATE, s.DSP_FAMILY
ORDER BY s.ACTIVITY_DATE, s.DSP_FAMILY;

/*------------------------------------------------------------------------------
Q5. Highest single streaming day for a song on Apple Music.

RANK, not ROW_NUMBER, so a tie returns every tied row rather than an arbitrary
winner. This data contains a deliberate two-way tie.

The claim is bounded: highest in AVAILABLE history. The coverage query below
states what that history is, so the bound is a fact on the screen rather than a
verbal hedge.
------------------------------------------------------------------------------*/

WITH song_day AS (
    SELECT TRACK_KEY, TRACK_TITLE, ARTIST_NAME, ISRC, ACTIVITY_DATE, SUM(STREAMS) AS streams
    FROM V_DAILY_STREAMS
    WHERE DSP_FAMILY = 'Apple Music'
      AND IS_COMPLETE
    GROUP BY TRACK_KEY, TRACK_TITLE, ARTIST_NAME, ISRC, ACTIVITY_DATE
)
SELECT
    'Q5 historical peak' AS check_name,
    TRACK_TITLE,
    ARTIST_NAME,
    ISRC,
    ACTIVITY_DATE AS peak_date,
    streams       AS peak_streams
FROM song_day
QUALIFY RANK() OVER (ORDER BY streams DESC) = 1
ORDER BY ACTIVITY_DATE;

-- Q5 coverage: the boundaries of "available history" for Apple Music.
SELECT
    'Q5 coverage' AS check_name,
    MIN(ACTIVITY_DATE)            AS history_start,
    MAX(ACTIVITY_DATE)            AS history_end,
    COUNT(DISTINCT ACTIVITY_DATE) AS complete_days_observed
FROM V_DAILY_STREAMS
WHERE DSP_FAMILY = 'Apple Music'
  AND IS_COMPLETE;
