/*==============================================================================
03_governance.sql - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Entitlements and enforcement.

Two design decisions worth stating plainly:

1. Entitlements are modeled as principal + permission + allowed label. Not a role
   alone, and not "every label some role could reach." A principal can hold
   revenue access to a label without holding streaming access to it, which is how
   application-level permissions actually behave.

2. There is no admin bypass. SYSADMIN sees all 60 labels because it holds 60
   entitlement rows, not because the policy exempts it. That makes the claim
   "the agent cannot see what the asker cannot see" literally true instead of
   true-except-for-one-role. The cost is that an empty ENTITLEMENT table makes
   every fact query return nothing, which the access tests catch immediately.
==============================================================================*/

USE ROLE SYSADMIN;
USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

/*==============================================================================
Persona roles
==============================================================================*/

USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS BACKSTAGE_LABEL_BROAD
  COMMENT = 'DEMO: Persona with revenue and streaming access to all labels (Expires: 2026-10-22)';
CREATE ROLE IF NOT EXISTS BACKSTAGE_LABEL_LIMITED
  COMMENT = 'DEMO: Persona scoped to three labels, with streaming withheld on one (Expires: 2026-10-22)';
CREATE ROLE IF NOT EXISTS BACKSTAGE_LABEL_NONE
  COMMENT = 'DEMO: Persona with no label entitlements (Expires: 2026-10-22)';

USE ROLE SECURITYADMIN;

-- The operator running the demo needs to be able to switch into each persona.
GRANT ROLE BACKSTAGE_LABEL_BROAD   TO ROLE SYSADMIN;
GRANT ROLE BACKSTAGE_LABEL_LIMITED TO ROLE SYSADMIN;
GRANT ROLE BACKSTAGE_LABEL_NONE    TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

/*==============================================================================
Detach any policies left by a previous deployment.

CREATE OR REPLACE ROW ACCESS POLICY fails while the policy is attached to a
table, so a redeploy must detach first. DROP ALL ROW ACCESS POLICIES succeeds
even when nothing is attached, which makes this safe on a first run.
==============================================================================*/

ALTER TABLE FACT_ROYALTY_MONTH DROP ALL ROW ACCESS POLICIES;
ALTER TABLE FACT_STREAM_DAY    DROP ALL ROW ACCESS POLICIES;
ALTER TABLE DIM_LABEL          DROP ALL ROW ACCESS POLICIES;
ALTER TABLE DIM_TRACK          DROP ALL ROW ACCESS POLICIES;

/*==============================================================================
ENTITLEMENT - the authorization source of truth.

Never granted to persona roles. The row access policies read it under the policy
owner's rights, so a persona is scoped by it without being able to read it.
==============================================================================*/

CREATE OR REPLACE TABLE ENTITLEMENT (
    PRINCIPAL   VARCHAR(100) NOT NULL COMMENT 'Role name in this demo; an end-user identity in production',
    PERMISSION  VARCHAR(50)  NOT NULL COMMENT 'VIEW_LABEL_REVENUE or VIEW_LABEL_STREAMS',
    LABEL_ID    NUMBER(5)    NOT NULL,
    RELEASE_ID  VARCHAR(50)  NOT NULL,
    SYNTHETIC   BOOLEAN      NOT NULL,
    CONSTRAINT PK_ENTITLEMENT PRIMARY KEY (PRINCIPAL, PERMISSION, LABEL_ID)
)
COMMENT = 'DEMO: principal + permission + allowed label. (Expires: 2026-10-22)';

-- Broad persona and the deploying role: both permissions on every label.
--
-- The label list is generated rather than read from DIM_LABEL on purpose. On a
-- redeploy the lookup policy is already attached to DIM_LABEL while ENTITLEMENT
-- has just been emptied by CREATE OR REPLACE, so reading DIM_LABEL here would
-- return zero rows and lock every principal out of every table.
INSERT INTO ENTITLEMENT (PRINCIPAL, PERMISSION, LABEL_ID, RELEASE_ID, SYNTHETIC)
SELECT p.principal, perm.permission, l.label_id, c.RELEASE_ID, TRUE
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS label_id
    FROM TABLE(GENERATOR(ROWCOUNT => 75))
) l
CROSS JOIN DEMO_CONFIG c
CROSS JOIN (SELECT 'BACKSTAGE_LABEL_BROAD' AS principal UNION ALL SELECT 'SYSADMIN') p
CROSS JOIN (SELECT 'VIEW_LABEL_REVENUE' AS permission UNION ALL SELECT 'VIEW_LABEL_STREAMS') perm;

/*
 Limited persona: labels 5, 12, and 23 only.

 Label 1 (Cypress Grove Records) is deliberately excluded. It owns the flagship
 recording that the concentration question asks about, so the limited persona
 asking that question is a real denial rather than a smaller number.

 Label 23 carries revenue access but not streaming access, which demonstrates
 that a permission is not implied by holding any access to the label.
*/
INSERT INTO ENTITLEMENT (PRINCIPAL, PERMISSION, LABEL_ID, RELEASE_ID, SYNTHETIC)
SELECT t.principal, t.permission, t.label_id, c.RELEASE_ID, TRUE
FROM (
    SELECT column1 AS principal, column2 AS permission, column3 AS label_id
    FROM VALUES
        ('BACKSTAGE_LABEL_LIMITED', 'VIEW_LABEL_REVENUE',  5),
        ('BACKSTAGE_LABEL_LIMITED', 'VIEW_LABEL_STREAMS',  5),
        ('BACKSTAGE_LABEL_LIMITED', 'VIEW_LABEL_REVENUE', 12),
        ('BACKSTAGE_LABEL_LIMITED', 'VIEW_LABEL_STREAMS', 12),
        ('BACKSTAGE_LABEL_LIMITED', 'VIEW_LABEL_REVENUE', 23)
) t
CROSS JOIN DEMO_CONFIG c;

-- BACKSTAGE_LABEL_NONE deliberately receives no rows.

/*==============================================================================
Row access policies.

A policy body cannot tell which table it is attached to, so the revenue and
streaming permissions need separate policies. The lookup policy accepts either
permission, because seeing a label's name is implied by holding any access to it.
==============================================================================*/

CREATE OR REPLACE ROW ACCESS POLICY LABEL_REVENUE_POLICY
  AS (label_id NUMBER) RETURNS BOOLEAN ->
    EXISTS (
        SELECT 1
        FROM SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.ENTITLEMENT e
        WHERE e.PERMISSION = 'VIEW_LABEL_REVENUE'
          AND e.LABEL_ID = label_id
          AND e.PRINCIPAL IN (CURRENT_ROLE(), CURRENT_USER())
    )
  COMMENT = 'DEMO: Restricts royalty rows to labels the caller may view revenue for (Expires: 2026-10-22)';

CREATE OR REPLACE ROW ACCESS POLICY LABEL_STREAMS_POLICY
  AS (label_id NUMBER) RETURNS BOOLEAN ->
    EXISTS (
        SELECT 1
        FROM SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.ENTITLEMENT e
        WHERE e.PERMISSION = 'VIEW_LABEL_STREAMS'
          AND e.LABEL_ID = label_id
          AND e.PRINCIPAL IN (CURRENT_ROLE(), CURRENT_USER())
    )
  COMMENT = 'DEMO: Restricts daily stream rows to labels the caller may view streams for (Expires: 2026-10-22)';

CREATE OR REPLACE ROW ACCESS POLICY LABEL_LOOKUP_POLICY
  AS (label_id NUMBER) RETURNS BOOLEAN ->
    EXISTS (
        SELECT 1
        FROM SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.ENTITLEMENT e
        WHERE e.LABEL_ID = label_id
          AND e.PRINCIPAL IN (CURRENT_ROLE(), CURRENT_USER())
    )
  COMMENT = 'DEMO: Prevents discovery of label and track names outside the caller scope (Expires: 2026-10-22)';

ALTER TABLE FACT_ROYALTY_MONTH ADD ROW ACCESS POLICY LABEL_REVENUE_POLICY ON (LABEL_ID);
ALTER TABLE FACT_STREAM_DAY    ADD ROW ACCESS POLICY LABEL_STREAMS_POLICY ON (LABEL_ID);
ALTER TABLE DIM_LABEL          ADD ROW ACCESS POLICY LABEL_LOOKUP_POLICY  ON (LABEL_ID);
ALTER TABLE DIM_TRACK          ADD ROW ACCESS POLICY LABEL_LOOKUP_POLICY  ON (LABEL_ID);

/*==============================================================================
Analytic views.

These exist so the semantic views expose released and complete periods, DSP
families, and readable names without every question having to restate the join
and gate logic. They inherit the policies from the underlying tables.
==============================================================================*/

CREATE OR REPLACE VIEW V_LABEL_REVENUE
  COMMENT = 'DEMO: Released monthly label revenue with DSP family and names (Expires: 2026-10-22)'
AS
SELECT
    f.STATEMENT_MONTH,
    f.LABEL_ID,
    l.LABEL_NAME,
    l.LABEL_TIER,
    f.TRACK_KEY,
    t.TRACK_TITLE,
    t.ARTIST_NAME,
    t.ISRC,
    d.DSP_FAMILY,
    d.SERVICE_NAME,
    sm.IS_RELEASED,
    f.LABEL_NET_USD,
    f.UNITS
FROM FACT_ROYALTY_MONTH f
JOIN DIM_LABEL           l  ON l.LABEL_ID = f.LABEL_ID
JOIN DIM_TRACK           t  ON t.TRACK_KEY = f.TRACK_KEY
JOIN DIM_DSP_SERVICE     d  ON d.DSP_SERVICE_ID = f.DSP_SERVICE_ID
JOIN DIM_STATEMENT_MONTH sm ON sm.STATEMENT_MONTH = f.STATEMENT_MONTH;

CREATE OR REPLACE VIEW V_DAILY_STREAMS
  COMMENT = 'DEMO: Daily stream activity with DSP family, completeness, and names (Expires: 2026-10-22)'
AS
SELECT
    f.ACTIVITY_DATE,
    f.TRACK_KEY,
    t.TRACK_TITLE,
    t.ARTIST_NAME,
    t.ISRC,
    f.LABEL_ID,
    l.LABEL_NAME,
    d.DSP_FAMILY,
    d.SERVICE_NAME,
    ad.IS_COMPLETE,
    f.STREAMS,
    f.LISTENERS
FROM FACT_STREAM_DAY f
JOIN DIM_LABEL        l  ON l.LABEL_ID = f.LABEL_ID
JOIN DIM_TRACK        t  ON t.TRACK_KEY = f.TRACK_KEY
JOIN DIM_DSP_SERVICE  d  ON d.DSP_SERVICE_ID = f.DSP_SERVICE_ID
JOIN DIM_ACTIVITY_DAY ad ON ad.ACTIVITY_DATE = f.ACTIVITY_DATE;

/*
 Coverage views. These answer "what do we actually have" without widening access,
 because they read the policy-filtered facts.
*/

CREATE OR REPLACE VIEW V_STREAM_COVERAGE
  COMMENT = 'DEMO: Observed first and last activity date per track and DSP family (Expires: 2026-10-22)'
AS
SELECT
    TRACK_KEY,
    TRACK_TITLE,
    DSP_FAMILY,
    MIN(ACTIVITY_DATE) AS first_observed_date,
    MAX(ACTIVITY_DATE) AS last_observed_date,
    COUNT(DISTINCT ACTIVITY_DATE) AS days_observed
FROM V_DAILY_STREAMS
GROUP BY TRACK_KEY, TRACK_TITLE, DSP_FAMILY;

CREATE OR REPLACE VIEW V_TRACK_TITLE_AMBIGUITY
  COMMENT = 'DEMO: Titles held by more than one recording, for ambiguity resolution (Expires: 2026-10-22)'
AS
SELECT
    t.TRACK_TITLE,
    COUNT(*) AS recording_count,
    ARRAY_AGG(t.ARTIST_NAME) WITHIN GROUP (ORDER BY t.TRACK_KEY) AS artists,
    ARRAY_AGG(t.ISRC) WITHIN GROUP (ORDER BY t.TRACK_KEY) AS isrcs
FROM DIM_TRACK t
GROUP BY t.TRACK_TITLE
HAVING COUNT(*) > 1;
