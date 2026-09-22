/*==============================================================================
04_semantic_views.sql - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Two semantic views, one per fact grain.

There is deliberately NO relationship between them and no view that spans them.
A statement month is a reporting period; an activity date is when a stream
happened. Joining the two would multiply revenue by the number of matching days
and produce a number that looks plausible and is wrong.

Clause order is significant: TABLES, RELATIONSHIPS, FACTS, DIMENSIONS, METRICS,
COMMENT, then the AI_* clauses. Within a dimension, SAMPLE_VALUES must precede
IS_ENUM.

Both views read policy-protected tables, so every answer is already scoped to the
caller's entitlements. Nothing in the semantic layer enforces access; nothing in
the semantic layer can bypass it either.
==============================================================================*/

USE ROLE SYSADMIN;
USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS;

/*==============================================================================
SV_BACKSTAGE_REVENUE - monthly royalty statement grain
==============================================================================*/

CREATE OR REPLACE SEMANTIC VIEW SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_REVENUE

  TABLES (
    revenue AS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.V_LABEL_REVENUE
      WITH SYNONYMS = ('royalties', 'revenue', 'statements', 'earnings', 'label revenue')
      COMMENT = 'Monthly royalty statement lines: net revenue to the label by month, label, recording and DSP service.'
  )

  FACTS (
    revenue.net_revenue AS LABEL_NET_USD
      COMMENT = 'Net revenue to the label in USD on a single statement line, after deductions',
    revenue.billable_units AS UNITS
      COMMENT = 'Billable units reported on the statement line'
  )

  DIMENSIONS (
    revenue.statement_month AS STATEMENT_MONTH
      WITH SYNONYMS = ('month', 'period', 'statement period', 'reporting month')
      COMMENT = 'Reporting period, always the first day of the month. This is NOT the date streams occurred.',
    revenue.statement_year AS YEAR(STATEMENT_MONTH)
      WITH SYNONYMS = ('year', 'calendar year')
      COMMENT = 'Calendar year of the reporting period',
    revenue.is_released AS IS_RELEASED
      WITH SYNONYMS = ('released', 'closed period', 'final', 'comparable period')
      COMMENT = 'TRUE when the statement period is closed. Filter to TRUE for any user-facing answer; open periods are incomplete.',
    revenue.label_name AS LABEL_NAME
      WITH SYNONYMS = ('label', 'imprint', 'partner')
      COMMENT = 'Name of the record label'
      SAMPLE_VALUES ('Cypress Grove Records', 'Foxglove Audio', 'Fernhollow Music', 'Inkwell Records', 'Larkspur Sound'),
    revenue.label_tier AS LABEL_TIER
      COMMENT = 'Relative size band of the label'
      SAMPLE_VALUES ('Flagship', 'Core', 'Long tail')
      IS_ENUM,
    revenue.track_title AS TRACK_TITLE
      WITH SYNONYMS = ('track', 'song', 'title', 'recording')
      COMMENT = 'Title of the recording. Titles are NOT unique; several titles are held by more than one recording. A bare name in a question is most often a track title rather than a label.'
      SAMPLE_VALUES ('Neon Orchard', 'Copper Highway', 'Midnight Alibi', 'Velvet Undertow', 'Paper Lantern'),
    revenue.artist_name AS ARTIST_NAME
      WITH SYNONYMS = ('artist', 'performer', 'act')
      COMMENT = 'Performing artist'
      SAMPLE_VALUES ('Marisol Vane', 'Dez Nkemdi', 'Lorne Delacroix', 'Kiona Rhodes'),
    revenue.isrc AS ISRC
      WITH SYNONYMS = ('recording id', 'canonical track id')
      COMMENT = 'Canonical recording identifier. Use this to disambiguate a title held by more than one recording.',
    revenue.dsp_family AS DSP_FAMILY
      WITH SYNONYMS = ('dsp', 'platform', 'service family', 'store')
      COMMENT = 'Canonical DSP. Use this for any question naming a platform. Amazon spans three underlying services and YouTube spans two.'
      SAMPLE_VALUES ('Spotify', 'Apple Music', 'Amazon', 'YouTube')
      IS_ENUM,
    revenue.service_name AS SERVICE_NAME
      WITH SYNONYMS = ('service', 'raw service', 'tier')
      COMMENT = 'Raw service string as delivered by the DSP. Narrower than dsp_family; filtering on this undercounts a platform.'
      SAMPLE_VALUES ('Spotify', 'Apple Music', 'YouTube Music', 'YouTube Content ID', 'Amazon Unlimited', 'Amazon Prime', 'Amazon Ad-Supported')
      IS_ENUM
  )

  METRICS (
    revenue.total_revenue AS SUM(revenue.net_revenue)
      WITH SYNONYMS = ('revenue', 'total revenue', 'net revenue', 'royalties', 'earnings')
      COMMENT = 'Total net revenue to the label in USD',
    revenue.total_units AS SUM(revenue.billable_units)
      WITH SYNONYMS = ('units', 'billable units')
      COMMENT = 'Total billable units',
    revenue.statement_lines AS COUNT(*)
      WITH SYNONYMS = ('lines', 'statement lines', 'row count')
      COMMENT = 'Number of statement lines contributing to the result',
    revenue.labels_reporting AS COUNT(DISTINCT revenue.label_name)
      WITH SYNONYMS = ('label count', 'number of labels')
      COMMENT = 'Distinct labels contributing to the result',
    revenue.recordings_reporting AS COUNT(DISTINCT revenue.isrc)
      WITH SYNONYMS = ('track count', 'number of recordings')
      COMMENT = 'Distinct recordings contributing to the result'
  )

  COMMENT = 'Monthly label royalty revenue. Revenue basis is LABEL_NET_USD, net to the label, in USD only. Statement month is a reporting period and is NOT an activity date. Contains no daily streaming data. All data synthetic.'

  AI_SQL_GENERATION
    'Revenue always means the sum of net_revenue, in USD. There is exactly one revenue basis and no currency conversion.

     Always aggregate through the METRICS clause, for example revenue.total_revenue. Do NOT request the raw fact
     revenue.net_revenue alongside a set of dimensions and then sum it yourself. A fact requested at a dimension grain is
     returned at that grain rather than per statement line, so summing it collapses the multiple services inside a DSP
     family and silently understates both a numerator and a denominator.

     ALWAYS filter is_released = TRUE. Open periods are incomplete and must never appear in a user-facing answer or in a
     period comparison. The newest released month is not the newest month present in the data.

     For any question naming a platform such as Amazon, Spotify, Apple or YouTube, filter on dsp_family, never on
     service_name. Amazon spans three services and YouTube spans two; filtering on a single service silently undercounts.

     For share or concentration questions, compute the numerator and the denominator over the identical scope: same year,
     same dsp_family filter, same is_released filter. Only the numerator narrows to the recording. Return the numerator,
     the denominator and the percentage, never the percentage alone.

     Before reporting any share, count how many rows the target recording actually contributed. There are two distinct
     unanswerable cases and NEITHER of them is zero percent:
       - The denominator is zero or absent. Use DIV0NULL so this returns NULL instead of a fabricated zero.
       - The denominator is healthy but the target recording contributed no rows at all. This happens when the caller is
         not entitled to that recording label. A naive ratio returns a confident 0.00% here, which is a false statement:
         it asserts the recording earned nothing when the truth is the caller cannot see it. Always return the target row
         count alongside the ratio and refuse when it is zero.

     Describe the denominator as revenue visible to the current user, not as total revenue. Results are already filtered to
     the labels this user is entitled to see, so the denominator is a scoped total.

     For month-over-month growth questions, rank by the ABSOLUTE change in revenue, not by percentage, unless the user
     explicitly asks for percentage. Return the prior total, the current total, the absolute change and the percentage
     change together. Compare the two most recent adjacent RELEASED months.
     A label with no prior-period row has NULL change and must be reported as no prior period; missing is not zero.
     A label whose prior revenue is zero must be reported as new, never as infinite or undefined growth.
     If fewer labels increased than the user asked for, return the shorter list and say how many increased. Never pad a
     requested top-N list with labels that declined.

     ENTITY RESOLUTION. When a question names something without saying what kind of thing it is, resolve it before you
     answer or conclude it is absent. Names in this catalog are most often RECORDINGS. Check track_title first, then
     artist_name, then label_name. Do not assume a bare name is a label. Do not report a zero or an absence until you have
     checked all three, because an unmatched name looks identical to a genuine zero and is not the same thing.
     If the name matches more than one recording, do not choose one: list each candidate with its artist and isrc and ask
     which was meant.

     ENTITY RESOLUTION. When a question names something without saying what kind of thing it is, resolve it before you
     answer or conclude it is absent. Names in this catalog are most often RECORDINGS. Check track_title first, then
     artist_name, then label_name. Do not assume a bare name is a label. Do not report a zero or an absence until you have
     checked all three, because an unmatched name looks identical to a genuine zero and is not the same thing.

     Track titles are not unique. If a question names a title that maps to more than one isrc, do not pick one. List the
     candidate recordings with their artist and isrc and ask which was meant.

     This model contains NO daily streaming data and NO activity dates. If asked about daily streams, a specific day,
     a streaming peak, or a date range shorter than a month, say that this belongs to the daily streaming model.

     Round currency to two decimal places. Use CASE WHEN for conditionals, never ternary syntax.
     For a calendar year use statement_month >= the first of January and < the first of the following January, rather than
     wrapping the column in YEAR().'

  AI_QUESTION_CATEGORIZATION
    'This model reports monthly label royalty revenue for a fictional catalog. Every answer is already restricted to the
     labels the asking user is entitled to see.

     If a question names a track title that matches more than one recording, treat it as unclear and ask which recording,
     offering the artist and isrc of each candidate.

     If a question asks for daily streams, a single day, a streaming peak or a window shorter than one month, it belongs to
     the daily streaming model rather than this one. Say so plainly instead of answering from monthly revenue.

     If a question asks for a per-stream payout rate, a forecast, a projection, or a comparison to an external industry
     benchmark, decline. None of those are in this model. Do not estimate them.'

  AI_VERIFIED_QUERIES (
    amazon_concentration_2025 AS (
      QUESTION 'What percentage of our 2025 Amazon revenue came from the recording QZSYN2400001?'
      VERIFIED_AT 1790000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = backstage_demo)'
      SQL 'WITH scoped AS (
             SELECT isrc, total_revenue
             FROM SEMANTIC_VIEW(
               SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_REVENUE
               METRICS revenue.total_revenue
               DIMENSIONS revenue.isrc, revenue.dsp_family, revenue.statement_month, revenue.is_released
             )
             WHERE dsp_family = ''Amazon''
               AND is_released
               AND statement_month >= ''2025-01-01''::DATE
               AND statement_month < ''2026-01-01''::DATE
           )
           SELECT
             COUNT_IF(isrc = ''QZSYN2400001'') AS target_rows_visible,
             ROUND(SUM(CASE WHEN isrc = ''QZSYN2400001'' THEN total_revenue ELSE 0 END), 2) AS track_revenue_usd,
             ROUND(SUM(total_revenue), 2) AS amazon_revenue_visible_usd,
             ROUND(100 * DIV0NULL(SUM(CASE WHEN isrc = ''QZSYN2400001'' THEN total_revenue ELSE 0 END), SUM(total_revenue)), 2) AS pct_of_visible_amazon,
             CASE
               WHEN COALESCE(SUM(total_revenue), 0) = 0
                 THEN ''UNANSWERABLE: no Amazon revenue visible to you in 2025''
               WHEN COUNT_IF(isrc = ''QZSYN2400001'') = 0
                 THEN ''UNANSWERABLE: that recording is not in the data visible to you. This is NOT zero percent.''
               ELSE ''ANSWERABLE''
             END AS verdict
           FROM scoped'
    ),
    label_growth_latest_released AS (
      QUESTION 'Which 50 labels had the largest month-over-month revenue increases?'
      VERIFIED_AT 1790000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = backstage_demo)'
      SQL 'WITH monthly AS (
             SELECT label_name, statement_month, total_revenue
             FROM SEMANTIC_VIEW(
               SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_REVENUE
               METRICS revenue.total_revenue
               DIMENSIONS revenue.label_name, revenue.statement_month, revenue.is_released
             )
             WHERE is_released
           ),
           periods AS (
             SELECT MAX(statement_month) AS current_month,
                    MAX(statement_month) - INTERVAL ''1 month'' AS prior_month
             FROM monthly
           ),
           paired AS (
             SELECT m.label_name,
                    MAX(CASE WHEN m.statement_month = p.current_month THEN m.total_revenue END) AS current_usd,
                    MAX(CASE WHEN m.statement_month = p.prior_month   THEN m.total_revenue END) AS prior_usd
             FROM monthly m CROSS JOIN periods p
             GROUP BY m.label_name
           )
           SELECT label_name,
                  ROUND(prior_usd, 2) AS prior_month_usd,
                  ROUND(current_usd, 2) AS current_month_usd,
                  ROUND(current_usd - prior_usd, 2) AS absolute_change_usd,
                  CASE WHEN prior_usd IS NULL THEN ''NO PRIOR PERIOD''
                       WHEN prior_usd = 0 THEN ''NEW''
                       ELSE TO_VARCHAR(ROUND(100 * (current_usd - prior_usd) / prior_usd, 1)) || ''%'' END AS percent_change
           FROM paired
           WHERE current_usd IS NOT NULL
             AND (prior_usd IS NULL OR current_usd > prior_usd)
           ORDER BY (current_usd - prior_usd) DESC NULLS LAST
           LIMIT 50'
    )
  );

/*==============================================================================
SV_BACKSTAGE_DAILY_STREAMS - daily activity grain
==============================================================================*/

CREATE OR REPLACE SEMANTIC VIEW SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_DAILY_STREAMS

  TABLES (
    streams AS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.V_DAILY_STREAMS
      WITH SYNONYMS = ('streams', 'daily streams', 'plays', 'streaming activity')
      COMMENT = 'Daily stream counts by activity date, recording and DSP service. Days with no delivery are absent, not zero.'
  )

  FACTS (
    streams.stream_count AS STREAMS
      COMMENT = 'Streams recorded on one activity date for one recording on one service',
    streams.listener_count AS LISTENERS
      COMMENT = 'Distinct listeners on that line'
  )

  DIMENSIONS (
    streams.activity_date AS ACTIVITY_DATE
      WITH SYNONYMS = ('date', 'day', 'stream date', 'activity day')
      COMMENT = 'The date the streams actually occurred. This is NOT a royalty statement period.',
    streams.activity_month AS DATE_TRUNC('month', ACTIVITY_DATE)
      WITH SYNONYMS = ('month', 'activity month')
      COMMENT = 'Month of activity, derived from the activity date',
    streams.is_complete AS IS_COMPLETE
      WITH SYNONYMS = ('complete', 'complete day', 'settled', 'final')
      COMMENT = 'TRUE when the day has finished landing. The most recent days are FALSE and must be excluded from any complete-period answer.',
    streams.track_title AS TRACK_TITLE
      WITH SYNONYMS = ('track', 'song', 'title', 'recording')
      COMMENT = 'Title of the recording. Titles are NOT unique; several titles are held by more than one recording. A bare name in a question is most often a track title rather than a label.'
      SAMPLE_VALUES ('Neon Orchard', 'Copper Highway', 'Midnight Alibi', 'Velvet Undertow', 'Paper Lantern'),
    streams.artist_name AS ARTIST_NAME
      WITH SYNONYMS = ('artist', 'performer', 'act')
      COMMENT = 'Performing artist'
      SAMPLE_VALUES ('Marisol Vane', 'Dez Nkemdi', 'Lorne Delacroix', 'Kiona Rhodes'),
    streams.isrc AS ISRC
      WITH SYNONYMS = ('recording id', 'canonical track id')
      COMMENT = 'Canonical recording identifier. Use this to disambiguate a title held by more than one recording.',
    streams.label_name AS LABEL_NAME
      WITH SYNONYMS = ('label', 'imprint', 'partner')
      COMMENT = 'Name of the record label that owns the recording'
      SAMPLE_VALUES ('Cypress Grove Records', 'Foxglove Audio', 'Fernhollow Music', 'Inkwell Records'),
    streams.dsp_family AS DSP_FAMILY
      WITH SYNONYMS = ('dsp', 'platform', 'service family', 'store')
      COMMENT = 'Canonical DSP. Use this for any question naming a platform. Amazon spans three underlying services and YouTube spans two.'
      SAMPLE_VALUES ('Spotify', 'Apple Music', 'Amazon', 'YouTube')
      IS_ENUM,
    streams.service_name AS SERVICE_NAME
      WITH SYNONYMS = ('service', 'raw service', 'tier')
      COMMENT = 'Raw service string as delivered by the DSP. Narrower than dsp_family; filtering on this undercounts a platform.'
      SAMPLE_VALUES ('Spotify', 'Apple Music', 'YouTube Music', 'YouTube Content ID', 'Amazon Unlimited', 'Amazon Prime', 'Amazon Ad-Supported')
      IS_ENUM
  )

  METRICS (
    streams.total_streams AS SUM(streams.stream_count)
      WITH SYNONYMS = ('streams', 'total streams', 'plays', 'stream count')
      COMMENT = 'Total streams',
    streams.total_listeners AS SUM(streams.listener_count)
      WITH SYNONYMS = ('listeners', 'total listeners')
      COMMENT = 'Total listeners',
    streams.days_observed AS COUNT(DISTINCT streams.activity_date)
      WITH SYNONYMS = ('days with data', 'days reported', 'coverage days')
      COMMENT = 'Number of distinct activity dates actually present. Compare this to the days in the requested window to detect gaps.',
    streams.first_observed_date AS MIN(streams.activity_date)
      WITH SYNONYMS = ('earliest date', 'coverage start', 'history start')
      COMMENT = 'Earliest activity date present in the result scope',
    streams.last_observed_date AS MAX(streams.activity_date)
      WITH SYNONYMS = ('latest date', 'coverage end', 'history end')
      COMMENT = 'Latest activity date present in the result scope'
  )

  COMMENT = 'Daily DSP streaming activity. Activity date is an event date and is NOT a royalty statement period. Contains no revenue. Missing days are genuinely absent and must not be zero-filled. All data synthetic.'

  AI_SQL_GENERATION
    'This model counts streams. It contains NO revenue, NO currency and NO payout rates. If asked what streams are worth,
     say that revenue lives in the monthly revenue model and do not multiply streams by any rate.

     Days with no delivery are ABSENT from the data. Never generate a calendar spine, never LEFT JOIN to a date series,
     never COALESCE a missing day to zero and never interpolate across a gap. A gap means the DSP did not deliver; showing
     it as zero invents a collapse in activity that did not happen.

     Whenever you return a daily trend, also return days_observed alongside the number of days in the requested window so
     the reader can see whether the series is complete. If they differ, say which dates are missing.

     For any question naming a platform, filter on dsp_family, never on service_name. Amazon spans three services and
     YouTube spans two.

     For a request for the latest N complete days, filter is_complete = TRUE and take the N most recent such dates. Do not
     use the maximum activity_date present, because the most recent days are still landing. Always state the exact start
     and end date of the window you used.

     When you report a total alongside a breakdown, both must come from the SAME query result, and the total must equal the
     sum of the parts you displayed. Do not state a headline total that you did not compute in that result, and do not
     estimate or round one into existence. If the total and the breakdown disagree, the breakdown is what you actually
     queried; recompute rather than publishing both.

     For a highest or lowest day question, aggregate to the recording-and-day level first, then rank with RANK so that ties
     all appear. Never use ROW_NUMBER for a peak, because it discards ties and presents an arbitrary row as the answer.
     Report the result as the highest within available history, and return first_observed_date and last_observed_date so
     the bound on that claim is visible.

     Track titles are not unique. If a question names a title that maps to more than one isrc, do not pick one. List the
     candidate recordings with their artist and isrc and ask which was meant.

     Use CASE WHEN for conditionals, never ternary syntax.'

  AI_QUESTION_CATEGORIZATION
    'This model reports daily streaming activity for a fictional catalog. Every answer is already restricted to the labels
     the asking user is entitled to view streaming data for. A user may hold revenue access to a label without holding
     streaming access to it, so this model can legitimately return nothing for a label that appears in the revenue model.

     If a question names a track title that matches more than one recording, treat it as unclear and ask which recording,
     offering the artist and isrc of each candidate.

     If a question asks about revenue, royalties, earnings, currency or per-stream rates, it belongs to the monthly revenue
     model rather than this one. Say so plainly rather than answering from stream counts.

     If a question asks for a forecast, a projection, or a causal claim that some event caused a change in streams, decline.
     This model shows what happened, not why.'

  AI_VERIFIED_QUERIES (
    august_streams_by_dsp AS (
      QUESTION 'Show August 2026 streams for the recording QZSYN2400001 on Spotify, Apple Music, YouTube and Amazon.'
      VERIFIED_AT 1790000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = backstage_demo)'
      SQL 'SELECT activity_date, dsp_family, total_streams
           FROM SEMANTIC_VIEW(
             SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_DAILY_STREAMS
             METRICS streams.total_streams
             DIMENSIONS streams.activity_date, streams.dsp_family, streams.isrc
           )
           WHERE isrc = ''QZSYN2400001''
             AND activity_date >= ''2026-08-01''::DATE
             AND activity_date < ''2026-09-01''::DATE
           ORDER BY activity_date, dsp_family'
    ),
    august_coverage_by_dsp AS (
      QUESTION 'How many days of August 2026 did each DSP actually report for QZSYN2400001?'
      VERIFIED_AT 1790000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = backstage_demo)'
      SQL 'SELECT dsp_family, days_observed, 31 - days_observed AS days_missing, total_streams
           FROM SEMANTIC_VIEW(
             SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_DAILY_STREAMS
             METRICS streams.days_observed, streams.total_streams
             DIMENSIONS streams.dsp_family, streams.isrc, streams.activity_month
           )
           WHERE isrc = ''QZSYN2400001''
             AND activity_month = ''2026-08-01''::DATE
           ORDER BY total_streams DESC NULLS LAST'
    ),
    latest_seven_complete_days AS (
      QUESTION 'Give me a snapshot of the latest seven complete days for the recording QZSYN2400001.'
      VERIFIED_AT 1790000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = backstage_demo)'
      SQL 'WITH days AS (
             SELECT activity_date
             FROM SEMANTIC_VIEW(
               SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_DAILY_STREAMS
               METRICS streams.total_streams
               DIMENSIONS streams.activity_date, streams.is_complete
             )
             WHERE is_complete
             GROUP BY activity_date
             QUALIFY ROW_NUMBER() OVER (ORDER BY activity_date DESC) <= 7
           ),
           detail AS (
             SELECT activity_date, dsp_family, total_streams
             FROM SEMANTIC_VIEW(
               SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_DAILY_STREAMS
               METRICS streams.total_streams
               DIMENSIONS streams.activity_date, streams.dsp_family, streams.isrc
             )
             WHERE isrc = ''QZSYN2400001''
           )
           SELECT
             (SELECT MIN(activity_date) FROM days) AS window_start,
             (SELECT MAX(activity_date) FROM days) AS window_end,
             d.dsp_family,
             COUNT(DISTINCT d.activity_date) AS days_reported,
             SUM(d.total_streams) AS family_streams,
             SUM(SUM(d.total_streams)) OVER () AS total_streams_all_families
           FROM detail d
           JOIN days w ON w.activity_date = d.activity_date
           GROUP BY d.dsp_family
           ORDER BY family_streams DESC NULLS LAST'
    ),
    apple_peak_day AS (      QUESTION 'What was our highest streaming day for a song on Apple Music?'
      VERIFIED_AT 1790000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = backstage_demo)'
      SQL 'WITH song_day AS (
             SELECT track_title, artist_name, isrc, activity_date, total_streams
             FROM SEMANTIC_VIEW(
               SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_DAILY_STREAMS
               METRICS streams.total_streams
               DIMENSIONS streams.track_title, streams.artist_name, streams.isrc, streams.activity_date,
                          streams.dsp_family, streams.is_complete
             )
             WHERE dsp_family = ''Apple Music'' AND is_complete
           )
           SELECT track_title, artist_name, isrc, activity_date AS peak_date, total_streams AS peak_streams
           FROM song_day
           QUALIFY RANK() OVER (ORDER BY total_streams DESC) = 1
           ORDER BY activity_date'
    )
  );
