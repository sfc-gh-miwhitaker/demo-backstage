/*==============================================================================
02_data.sql - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Deterministic synthetic data. Every value is derived by hashing a stable key
string, so this script produces byte-identical output on every run regardless of
the calendar date. No RANDOM(), no UNIFORM(), no CURRENT_DATE().

All labels, artists, and tracks are fictional.

The two fact tables are generated INDEPENDENTLY and are deliberately not
reconciled to each other. They represent two different source systems: a monthly
royalty statement feed and a daily DSP activity feed. Streams multiplied by any
rate will not equal revenue, because real statements carry deductions and lag.
This is why the two grains must never be joined.
==============================================================================*/

USE ROLE SYSADMIN;
USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

/*==============================================================================
DIM_LABEL - 75 fictional labels, some with a parent for hierarchy.

The count is 75 rather than 60 so that a "top 50 labels" question is a genuine
selection. With 60 labels and a realistic share of decliners, the top 50 would be
very nearly the entire list, which makes the ranking look impressive and mean
almost nothing.
==============================================================================*/

CREATE OR REPLACE TABLE DIM_LABEL (
    LABEL_ID        NUMBER(5)    NOT NULL,
    LABEL_NAME      VARCHAR(100) NOT NULL,
    PARENT_LABEL_ID NUMBER(5)             COMMENT 'NULL for top-level labels',
    LABEL_TIER      VARCHAR(20)  NOT NULL COMMENT 'Flagship, Core, or Long tail',
    RELEASE_ID      VARCHAR(50)  NOT NULL,
    SYNTHETIC       BOOLEAN      NOT NULL,
    CONSTRAINT PK_DIM_LABEL PRIMARY KEY (LABEL_ID)
)
COMMENT = 'DEMO: Fictional record labels. (Expires: 2026-10-22)';

INSERT INTO DIM_LABEL (LABEL_ID, LABEL_NAME, PARENT_LABEL_ID, LABEL_TIER, RELEASE_ID, SYNTHETIC)
SELECT
    t.label_id,
    t.label_name,
    t.parent_label_id,
    CASE
        WHEN t.label_id = 1 THEN 'Flagship'
        WHEN t.label_id <= 20 THEN 'Core'
        ELSE 'Long tail'
    END,
    c.RELEASE_ID,
    TRUE
FROM (
    SELECT column1 AS label_id, column2 AS label_name, column3 AS parent_label_id
    FROM VALUES
        ( 1, 'Cypress Grove Records',   NULL), ( 2, 'Harbor Nine Sound',      NULL),
        ( 3, 'Tallow Street Music',     NULL), ( 4, 'Wren & Wilder',          NULL),
        ( 5, 'Foxglove Audio',         NULL), ( 6, 'Marrowfield Records',     4),
        ( 7, 'Pale Tiger Collective',  NULL), ( 8, 'Ninth Ward Tapes',       NULL),
        ( 9, 'Saltmarsh Sound',         5), (10, 'Bright Anvil Records',     NULL),
        (11, 'Juniper Ash',            NULL), (12, 'Kestrel Lane Music',     NULL),
        (13, 'Copper Kettle Audio',    NULL), (14, 'Lowland Echo',            10),
        (15, 'Verdigris Records',      NULL), (16, 'Sable Coast Music',      NULL),
        (17, 'Hollowpine Sound',       NULL), (18, 'Amberlight Tapes',         2),
        (19, 'Quarry Road Records',    NULL), (20, 'Thistledown Audio',      NULL),
        (21, 'Ember Row Music',        NULL), (22, 'Glasswing Records',      NULL),
        (23, 'Northgate Sound',        NULL), (24, 'Pitch Pine Audio',        17),
        (25, 'Riverbend Tapes',        NULL), (26, 'Slate Harbor Music',     NULL),
        (27, 'Tumbleweed Records',     NULL), (28, 'Umberfield Sound',       NULL),
        (29, 'Violet Mile Audio',      NULL), (30, 'Wayfarer Tapes',          25),
        (31, 'Yarrow & Sons',          NULL), (32, 'Zephyr Court Records',   NULL),
        (33, 'Alder Fen Music',        NULL), (34, 'Brambleway Sound',       NULL),
        (35, 'Cinder Lake Audio',      NULL), (36, 'Dovetail Records',        33),
        (37, 'Elmswood Tapes',         NULL), (38, 'Fernhollow Music',       NULL),
        (39, 'Gilded Crow Sound',      NULL), (40, 'Hawthorn Reach',         NULL),
        (41, 'Ironwood Audio',         NULL), (42, 'Jackdaw Records',         39),
        (43, 'Kilnbrook Music',        NULL), (44, 'Larkspur Sound',         NULL),
        (45, 'Moss & Meridian',        NULL), (46, 'Nettlebed Tapes',        NULL),
        (47, 'Oxbow Audio',            NULL), (48, 'Plumbline Records',       44),
        (49, 'Quillfeather Music',     NULL), (50, 'Rookery Sound',          NULL),
        (51, 'Stonecrop Audio',        NULL), (52, 'Tidewater Tapes',        NULL),
        (53, 'Underhill Records',      NULL), (54, 'Vesper Field Music',      51),
        (55, 'Windrow Sound',          NULL), (56, 'Yewbank Audio',          NULL),
        (57, 'Ashgrove Tapes',         NULL), (58, 'Bellweather Records',    NULL),
        (59, 'Chalkhill Music',        NULL), (60, 'Drifthouse Sound',        58),
        (61, 'Emberglass Records',     NULL), (62, 'Fallowmere Sound',       NULL),
        (63, 'Greyling Audio',         NULL), (64, 'Hearthstone Tapes',       61),
        (65, 'Inkwell Records',        NULL), (66, 'Jessamine Sound',        NULL),
        (67, 'Kingfisher Audio',       NULL), (68, 'Loamfield Music',         65),
        (69, 'Mistral Row Records',    NULL), (70, 'Nightjar Sound',         NULL),
        (71, 'Orrery Audio',           NULL), (72, 'Pennywort Tapes',         69),
        (73, 'Rushlight Records',      NULL), (74, 'Sorrel Bay Music',       NULL),
        (75, 'Thornfield Sound',       NULL)
) AS t
CROSS JOIN DEMO_CONFIG c;

/*==============================================================================
DIM_DSP_SERVICE - 7 raw service strings rolling up to 4 DSP families.

Amazon intentionally spans three raw services and YouTube spans two. Any question
about "Amazon revenue" must roll up the family; filtering on a single raw service
silently undercounts. This is the detail that makes the concentration question
non-trivial.
==============================================================================*/

CREATE OR REPLACE TABLE DIM_DSP_SERVICE (
    DSP_SERVICE_ID  NUMBER(4)    NOT NULL,
    SERVICE_NAME    VARCHAR(50)  NOT NULL COMMENT 'Raw service string as delivered by the DSP',
    DSP_FAMILY      VARCHAR(30)  NOT NULL COMMENT 'Canonical DSP the service belongs to',
    SERVICE_MODEL   VARCHAR(30)  NOT NULL,
    RELEASE_ID      VARCHAR(50)  NOT NULL,
    SYNTHETIC       BOOLEAN      NOT NULL,
    CONSTRAINT PK_DIM_DSP_SERVICE PRIMARY KEY (DSP_SERVICE_ID)
)
COMMENT = 'DEMO: DSP services and their family rollup. (Expires: 2026-10-22)';

INSERT INTO DIM_DSP_SERVICE (DSP_SERVICE_ID, SERVICE_NAME, DSP_FAMILY, SERVICE_MODEL, RELEASE_ID, SYNTHETIC)
SELECT t.*, c.RELEASE_ID, TRUE
FROM (
    SELECT column1, column2, column3, column4
    FROM VALUES
        (1, 'Spotify',             'Spotify',     'Subscription'),
        (2, 'Apple Music',         'Apple Music', 'Subscription'),
        (3, 'YouTube Music',       'YouTube',     'Subscription'),
        (4, 'YouTube Content ID',  'YouTube',     'Ad-Supported'),
        (5, 'Amazon Unlimited',    'Amazon',      'Subscription'),
        (6, 'Amazon Prime',        'Amazon',      'Bundled'),
        (7, 'Amazon Ad-Supported', 'Amazon',      'Ad-Supported')
) AS t
CROSS JOIN DEMO_CONFIG c;

/*==============================================================================
DIM_TRACK - 600 fictional tracks, 8 per label.

Titles are drawn deterministically from a bounded vocabulary, so some titles
collide across labels exactly as they do in a real catalog. Track 1 is forced to
the title 'Neon Orchard' and track 301 is forced to match it; a third recording
lands on the same title naturally from the vocabulary. The result is a three-way
collision across three labels with three artists and three ISRCs, so any question
naming that title must resolve the ambiguity rather than silently pick one.
==============================================================================*/

CREATE OR REPLACE TABLE DIM_TRACK (
    TRACK_KEY        NUMBER(6)    NOT NULL,
    TRACK_TITLE      VARCHAR(120) NOT NULL,
    ARTIST_NAME      VARCHAR(100) NOT NULL,
    LABEL_ID         NUMBER(5)    NOT NULL,
    ISRC             VARCHAR(12)  NOT NULL COMMENT 'Synthetic ISRC, canonical recording identifier',
    RELEASE_DATE     DATE         NOT NULL,
    POPULARITY_TIER  NUMBER(1)    NOT NULL COMMENT '1 is the largest earner, 5 the smallest',
    IS_DAILY_TRACKED BOOLEAN      NOT NULL COMMENT 'TRUE if the track appears in the daily activity feed',
    RELEASE_ID       VARCHAR(50)  NOT NULL,
    SYNTHETIC        BOOLEAN      NOT NULL,
    CONSTRAINT PK_DIM_TRACK PRIMARY KEY (TRACK_KEY)
)
COMMENT = 'DEMO: Fictional recordings. (Expires: 2026-10-22)';

INSERT INTO DIM_TRACK
WITH seq AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS track_key
    FROM TABLE(GENERATOR(ROWCOUNT => 600))
),
title_words AS (
    SELECT column1 AS idx, column2 AS word FROM VALUES
        (0,'Neon'),(1,'Copper'),(2,'Midnight'),(3,'Paper'),(4,'Velvet'),(5,'Amber'),
        (6,'Hollow'),(7,'Silver'),(8,'Crimson'),(9,'Quiet'),(10,'Wild'),(11,'Golden'),
        (12,'Salt'),(13,'Glass'),(14,'Iron'),(15,'Harbor'),(16,'Winter'),(17,'Static'),
        (18,'Lantern'),(19,'Marble'),(20,'Feather'),(21,'Thunder'),(22,'Rosewood'),(23,'Cobalt')
),
title_nouns AS (
    SELECT column1 AS idx, column2 AS word FROM VALUES
        (0,'Orchard'),(1,'Highway'),(2,'Lantern'),(3,'Harbor'),(4,'Rooms'),(5,'Weather'),
        (6,'Signal'),(7,'Alibi'),(8,'Daughter'),(9,'Machine'),(10,'Sunday'),(11,'Window'),
        (12,'Chorus'),(13,'Anchor'),(14,'Fever'),(15,'Letters'),(16,'Garden'),(17,'Mirror'),
        (18,'Parade'),(19,'Undertow')
),
first_names AS (
    SELECT column1 AS idx, column2 AS word FROM VALUES
        (0,'Marisol'),(1,'Dez'),(2,'Kiona'),(3,'Rafe'),(4,'Imani'),(5,'Soren'),
        (6,'Tabitha'),(7,'Odell'),(8,'Nadira'),(9,'Cassius'),(10,'Lorne'),(11,'Sierra')
),
last_names AS (
    SELECT column1 AS idx, column2 AS word FROM VALUES
        (0,'Vane'),(1,'Okafor'),(2,'Rhodes'),(3,'Delacroix'),(4,'Ashby'),(5,'Mercier'),
        (6,'Solano'),(7,'Whitlock'),(8,'Bexley'),(9,'Caldera'),(10,'Ferris'),(11,'Nkemdi')
),
built AS (
    SELECT
        s.track_key,
        -- Track 1 and track 301 are forced to the same title on different labels.
        CASE
            WHEN s.track_key IN (1, 301) THEN 'Neon Orchard'
            ELSE tw.word || ' ' || tn.word
        END AS track_title,
        fn.word || ' ' || ln.word AS artist_name,
        FLOOR((s.track_key - 1) / 8) + 1 AS label_id,
        -- Popularity: track 1 is the flagship earner; the rest skew to the tail.
        CASE
            WHEN s.track_key = 1 THEN 1
            WHEN ABS(HASH(s.track_key || 'pop-8831')) % 100 < 4  THEN 2
            WHEN ABS(HASH(s.track_key || 'pop-8831')) % 100 < 16 THEN 3
            WHEN ABS(HASH(s.track_key || 'pop-8831')) % 100 < 45 THEN 4
            ELSE 5
        END AS popularity_tier,
        -- Releases spread across the first 15 months of history so later months
        -- contain genuinely new tracks with no prior-period revenue.
        DATEADD('day', ABS(HASH(s.track_key || 'rel-8831')) % 450, c.HISTORY_START) AS release_date,
        c.RELEASE_ID
    FROM seq s
    CROSS JOIN DEMO_CONFIG c
    JOIN title_words tw ON tw.idx = ABS(HASH(s.track_key || 'tw-8831')) % 24
    JOIN title_nouns tn ON tn.idx = ABS(HASH(s.track_key || 'tn-8831')) % 20
    JOIN first_names fn ON fn.idx = ABS(HASH(s.track_key || 'fn-8831')) % 12
    JOIN last_names  ln ON ln.idx = ABS(HASH(s.track_key || 'ln-8831')) % 12
)
SELECT
    track_key,
    track_title,
    -- The flagship recording gets a stable artist so the runbook can name it.
    CASE WHEN track_key = 1 THEN 'Marisol Vane' ELSE artist_name END AS artist_name,
    label_id,
    'QZSYN' || TO_VARCHAR(YEAR(release_date) % 100, 'FM00') || LPAD(track_key::VARCHAR, 5, '0') AS isrc,
    -- The flagship must exist for all of calendar 2025, so pin it to day one.
    CASE WHEN track_key = 1 THEN '2024-01-01'::DATE ELSE release_date END AS release_date,
    popularity_tier,
    -- 40 tracks carry daily activity: the flagship, plus a deterministic sample.
    (track_key = 1 OR ABS(HASH(track_key || 'daily-8831')) % 600 < 39) AS is_daily_tracked,
    release_id,
    TRUE
FROM built;

/*==============================================================================
DIM_PERIOD - statement months with release status, and activity days with
completeness. Both gates live here so a query never has to guess.
==============================================================================*/

CREATE OR REPLACE TABLE DIM_STATEMENT_MONTH (
    STATEMENT_MONTH DATE        NOT NULL,
    IS_RELEASED     BOOLEAN     NOT NULL COMMENT 'FALSE means the period is still open; exclude from user-facing answers',
    RELEASE_ID      VARCHAR(50) NOT NULL,
    SYNTHETIC       BOOLEAN     NOT NULL,
    CONSTRAINT PK_DIM_STATEMENT_MONTH PRIMARY KEY (STATEMENT_MONTH)
)
COMMENT = 'DEMO: Royalty statement periods. (Expires: 2026-10-22)';

INSERT INTO DIM_STATEMENT_MONTH
SELECT
    m.statement_month,
    m.statement_month <= c.LAST_RELEASED_MONTH,
    c.RELEASE_ID,
    TRUE
FROM (
    SELECT DATEADD('month', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-01-01'::DATE) AS statement_month
    FROM TABLE(GENERATOR(ROWCOUNT => 32))
) m
CROSS JOIN DEMO_CONFIG c;

CREATE OR REPLACE TABLE DIM_ACTIVITY_DAY (
    ACTIVITY_DATE DATE        NOT NULL,
    IS_COMPLETE   BOOLEAN     NOT NULL COMMENT 'FALSE means the day is still landing; exclude from complete-period answers',
    RELEASE_ID    VARCHAR(50) NOT NULL,
    SYNTHETIC     BOOLEAN     NOT NULL,
    CONSTRAINT PK_DIM_ACTIVITY_DAY PRIMARY KEY (ACTIVITY_DATE)
)
COMMENT = 'DEMO: Daily activity calendar. (Expires: 2026-10-22)';

INSERT INTO DIM_ACTIVITY_DAY
SELECT
    d.activity_date,
    d.activity_date <= c.LAST_COMPLETE_DAY,
    c.RELEASE_ID,
    TRUE
FROM (
    SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-01-01'::DATE) AS activity_date
    FROM TABLE(GENERATOR(ROWCOUNT => 995))
) d
CROSS JOIN DEMO_CONFIG c
WHERE d.activity_date <= DATEADD('day', -1, c.DEMO_AS_OF);

/*==============================================================================
FACT_ROYALTY_MONTH - monthly statement grain.

Sparse by construction: a track earns only from its release month onward, and
roughly one combination in eight is absent. Absent means no statement line, which
is not the same as zero revenue. Question 2 depends on that distinction.
==============================================================================*/

CREATE OR REPLACE TABLE FACT_ROYALTY_MONTH (
    STATEMENT_MONTH DATE          NOT NULL COMMENT 'Reporting period, first of month. NOT an activity date.',
    LABEL_ID        NUMBER(5)     NOT NULL,
    TRACK_KEY       NUMBER(6)     NOT NULL,
    DSP_SERVICE_ID  NUMBER(4)     NOT NULL,
    LABEL_NET_USD   NUMBER(12,2)  NOT NULL COMMENT 'Net revenue to the label in USD after deductions',
    UNITS           NUMBER(12)    NOT NULL COMMENT 'Billable units on the statement line',
    RELEASE_ID      VARCHAR(50)   NOT NULL,
    SYNTHETIC       BOOLEAN       NOT NULL,
    CONSTRAINT PK_FACT_ROYALTY_MONTH PRIMARY KEY (STATEMENT_MONTH, LABEL_ID, TRACK_KEY, DSP_SERVICE_ID)
)
COMMENT = 'DEMO: Monthly royalty statement lines. Statement month is a reporting period. (Expires: 2026-10-22)';

INSERT INTO FACT_ROYALTY_MONTH
WITH combos AS (
    SELECT
        sm.STATEMENT_MONTH,
        t.LABEL_ID,
        t.TRACK_KEY,
        d.DSP_SERVICE_ID,
        t.POPULARITY_TIER,
        d.DSP_FAMILY,
        DATEDIFF('month', '2024-01-01'::DATE, sm.STATEMENT_MONTH) AS month_index,
        c.RELEASE_ID
    FROM DIM_STATEMENT_MONTH sm
    CROSS JOIN DIM_TRACK t
    CROSS JOIN DIM_DSP_SERVICE d
    CROSS JOIN DEMO_CONFIG c
    -- A track cannot earn before it exists.
    WHERE sm.STATEMENT_MONTH >= DATE_TRUNC('month', t.RELEASE_DATE)
      -- Deterministic sparsity: about one track-and-service pair in eight never
      -- reports at all. Sparsity is keyed on the pair and NOT on the month, on
      -- purpose. Month-varying sparsity adds or removes several percent of a
      -- label's statement lines between adjacent months, which is far larger
      -- than a label's growth rate and would make a month-over-month ranking
      -- measure noise instead of growth.
      AND ABS(HASH(t.TRACK_KEY || '-' || d.DSP_SERVICE_ID || 'sparse-8831')) % 100 >= 12
),
scaled AS (
    SELECT
        c.*,
        -- Earnings scale by popularity tier. Magnitudes are chosen so a flagship
        -- label posts roughly a million USD a month and the group's annual Amazon
        -- revenue lands in the tens of millions, which is the order of magnitude a
        -- label operator would expect to see on a statement.
        CASE POPULARITY_TIER
            WHEN 1 THEN 216000.0
            WHEN 2 THEN 31200.0
            WHEN 3 THEN 8880.0
            WHEN 4 THEN 2520.0
            ELSE 720.0
        END AS tier_base,
        -- Each DSP family carries a different share of revenue.
        CASE DSP_FAMILY
            WHEN 'Spotify'     THEN 1.00
            WHEN 'Apple Music' THEN 0.62
            WHEN 'Amazon'      THEN 0.29
            ELSE 0.18
        END AS family_weight,
        -- Catalog grows steadily over the 32 months.
        1.0 + (month_index / 31.0 * 0.38) AS trend,
        -- Each label has its own compounding monthly growth rate, spanning roughly
        -- -0.5% to +2.5%. The range is deliberately set so that a meaningful share
        -- of labels genuinely declines, giving a "largest increases" ranking real
        -- labels to exclude, while still leaving comfortably more than 50 growers
        -- so the requested top 50 can be filled without padding it with decliners.
        POWER(
            1 + (((ABS(HASH(LABEL_ID || 'grow-8831')) % 301) / 10000.0) - 0.005),
            month_index
        ) AS label_growth,
        -- Seasonality as a smooth wave with a per-label phase, rather than
        -- independent per-month noise. Independent noise swings adjacent months by
        -- more than a label's growth rate and flips the sign of the change roughly
        -- half the time, which would make a "largest increases" ranking mostly
        -- noise. The amplitude and frequency here bound the month-to-month wave
        -- delta to about 0.4 percent, so only labels whose growth rate is below
        -- that can post a decline. Roughly a sixth of labels do, which leaves the
        -- requested top 50 fillable while keeping genuine decliners in the data.
        1 + 0.010 * SIN(month_index * 0.4 + (ABS(HASH(LABEL_ID || 'phase-8831')) % 628) / 100.0) AS label_month_factor,
        -- Line-level variation, split into a persistent component and a small
        -- monthly component. The persistent part is keyed on the track and
        -- service only, so it varies across lines but cancels out of any
        -- month-over-month comparison. Only the small monthly part contributes
        -- period-to-period noise.
        (0.80 + (ABS(HASH(TRACK_KEY || '-' || DSP_SERVICE_ID || 'base-8831')) % 41) / 100.0)
        * (0.97 + (ABS(HASH(TRACK_KEY || '-' || DSP_SERVICE_ID || '-' || STATEMENT_MONTH || 'jit-8831')) % 61) / 1000.0) AS jitter
    FROM combos c
)
SELECT
    STATEMENT_MONTH,
    LABEL_ID,
    TRACK_KEY,
    DSP_SERVICE_ID,
    ROUND(tier_base * family_weight * trend * label_growth * label_month_factor * jitter, 2) AS label_net_usd,
    FLOOR(tier_base * family_weight * trend * label_growth * label_month_factor * jitter * 305)::NUMBER(12) AS units,
    RELEASE_ID,
    TRUE
FROM scaled;

/*==============================================================================
FACT_STREAM_DAY - daily activity grain.

Gaps are deliberate and are left as gaps. Two kinds:
  1. Scattered single-day misses, about 3 percent of combinations.
  2. A contiguous outage: the whole YouTube family delivers nothing for
     2026-08-05 through 2026-08-11, which is inside the August window that
     question 3 asks about. The outage spans the family rather than a single
     service, because a single-service gap disappears once the family is rolled
     up and would not be visible on the chart.

A charted line over this data must show a break, not a zero and not an
interpolated segment.
==============================================================================*/

CREATE OR REPLACE TABLE FACT_STREAM_DAY (
    ACTIVITY_DATE  DATE         NOT NULL COMMENT 'Date the streams occurred. NOT a statement month.',
    TRACK_KEY      NUMBER(6)    NOT NULL,
    LABEL_ID       NUMBER(5)    NOT NULL,
    DSP_SERVICE_ID NUMBER(4)    NOT NULL,
    STREAMS        NUMBER(12)   NOT NULL,
    LISTENERS      NUMBER(12)   NOT NULL,
    RELEASE_ID     VARCHAR(50)  NOT NULL,
    SYNTHETIC      BOOLEAN      NOT NULL,
    CONSTRAINT PK_FACT_STREAM_DAY PRIMARY KEY (ACTIVITY_DATE, TRACK_KEY, DSP_SERVICE_ID)
)
COMMENT = 'DEMO: Daily DSP stream counts. Activity date is an event date. (Expires: 2026-10-22)';

INSERT INTO FACT_STREAM_DAY
WITH combos AS (
    SELECT
        ad.ACTIVITY_DATE,
        t.TRACK_KEY,
        t.LABEL_ID,
        d.DSP_SERVICE_ID,
        d.DSP_FAMILY,
        t.POPULARITY_TIER,
        DATEDIFF('day', '2024-01-01'::DATE, ad.ACTIVITY_DATE) AS day_index,
        c.RELEASE_ID
    FROM DIM_ACTIVITY_DAY ad
    CROSS JOIN DIM_TRACK t
    CROSS JOIN DIM_DSP_SERVICE d
    CROSS JOIN DEMO_CONFIG c
    WHERE t.IS_DAILY_TRACKED
      AND ad.ACTIVITY_DATE >= t.RELEASE_DATE
      -- Scattered gaps.
      AND ABS(HASH(t.TRACK_KEY || '-' || d.DSP_SERVICE_ID || '-' || ad.ACTIVITY_DATE || 'gap-8831')) % 1000 >= 30
      -- Contiguous YouTube delivery outage inside August 2026. This covers the
      -- whole family, not a single service, so the gap survives the family
      -- rollup and is actually visible on a charted August trend.
      AND NOT (d.DSP_FAMILY = 'YouTube'
               AND ad.ACTIVITY_DATE BETWEEN '2026-08-05'::DATE AND '2026-08-11'::DATE)
),
scaled AS (
    SELECT
        c.*,
        CASE POPULARITY_TIER
            WHEN 1 THEN 21000.0
            WHEN 2 THEN 3100.0
            WHEN 3 THEN 880.0
            WHEN 4 THEN 240.0
            ELSE 70.0
        END AS tier_base,
        CASE DSP_FAMILY
            WHEN 'Spotify'     THEN 1.00
            WHEN 'Apple Music' THEN 0.44
            WHEN 'Amazon'      THEN 0.20
            ELSE 0.31
        END AS family_weight,
        1.0 + (day_index / 994.0 * 0.30) AS trend,
        -- Weekend lift.
        CASE WHEN DAYOFWEEK(ACTIVITY_DATE) IN (0, 6) THEN 1.14 ELSE 1.00 END AS dow_factor,
        0.82 + (ABS(HASH(TRACK_KEY || '-' || DSP_SERVICE_ID || '-' || ACTIVITY_DATE || 'sjit-8831')) % 37) / 100.0 AS jitter
    FROM combos c
),
computed AS (
    SELECT
        ACTIVITY_DATE,
        TRACK_KEY,
        LABEL_ID,
        DSP_SERVICE_ID,
        RELEASE_ID,
        FLOOR(tier_base * family_weight * trend * dow_factor * jitter)::NUMBER(12) AS streams
    FROM scaled
)
SELECT
    ACTIVITY_DATE,
    TRACK_KEY,
    LABEL_ID,
    DSP_SERVICE_ID,
    -- Two Apple Music rows are pinned to an identical peak so the historical-peak
    -- question has a genuine tie to disclose rather than an arbitrary winner.
    CASE
        WHEN DSP_SERVICE_ID = 2 AND TRACK_KEY = 1 AND ACTIVITY_DATE = '2025-06-14'::DATE THEN 98750
        WHEN DSP_SERVICE_ID = 2 AND TRACK_KEY = 1 AND ACTIVITY_DATE = '2026-02-21'::DATE THEN 98750
        ELSE streams
    END AS streams,
    FLOOR(
        CASE
            WHEN DSP_SERVICE_ID = 2 AND TRACK_KEY = 1
                 AND ACTIVITY_DATE IN ('2025-06-14'::DATE, '2026-02-21'::DATE) THEN 98750
            ELSE streams
        END * 0.52
    )::NUMBER(12) AS listeners,
    RELEASE_ID,
    TRUE
FROM computed;
