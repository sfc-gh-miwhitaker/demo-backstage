/*==============================================================================
DEPLOY ALL - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Governed music-label conversational analytics. Two semantic views over separate
revenue and daily-streaming grains, one Cortex Agent for CoWork, and label-scoped
entitlements enforced by row access policies.

All data is synthetic. All labels, artists, and tracks are fictional.

USAGE
  Snowsight: open a new worksheet, paste this file, click Run All (about 2 min).
  Terminal:  snow sql -c <connection> -f deploy_all.sql

Self-contained. No Git repository, API integration, stage, or external file.
Re-running is safe: every step is idempotent.

To remove everything, run teardown_all.sql.
==============================================================================*/

-- Expiration check (informational -- warns but does not block deployment)
SELECT
    '2026-10-22'::DATE AS expiration_date,
    CURRENT_DATE() AS current_date,
    DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) AS days_remaining,
    CASE
        WHEN DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) < 0
        THEN 'EXPIRED - Code may use outdated syntax. Remove expiration banner to continue.'
        WHEN DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) <= 7
        THEN 'EXPIRING SOON - ' || DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) || ' days remaining'
        ELSE 'ACTIVE - ' || DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) || ' days remaining'
    END AS demo_status;

-- 1. Infrastructure and deterministic configuration
!source sql/01_setup.sql

-- 2. Synthetic dimensions and both fact grains
!source sql/02_data.sql

-- 3. Entitlements, row access policies, persona roles, analytic views
--    Must run after 02, because CREATE OR REPLACE TABLE drops policy attachments.
!source sql/03_governance.sql

-- 4. The two semantic views
!source sql/04_semantic_views.sql

-- 5. The Cortex Agent
!source sql/05_agent.sql

-- 6. Persona grants. Runs last: it grants on the semantic views and the agent,
--    which must already exist.
!source sql/06_grants.sql

/*==============================================================================
Row count manifest.

These counts are fixed by the deterministic generator. A mismatch means the data
did not build as expected, and every expected value in docs/EXPECTED_RESULTS.md
should be treated as invalid until it is resolved.

The role matters here. Four of these tables carry row access policies, so this
must run as a role that holds entitlements. SYSADMIN does, via rows in
ENTITLEMENT rather than any policy exemption. A role such as SECURITYADMIN holds
none and would report every protected table as empty.
==============================================================================*/

USE ROLE SYSADMIN;
USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

SELECT
    object_name,
    expected_rows,
    actual_rows,
    CASE WHEN actual_rows = expected_rows THEN 'OK' ELSE 'MISMATCH - stop and review' END AS status
FROM (
    SELECT 'DIM_LABEL'           AS object_name,  75 AS expected_rows, (SELECT COUNT(*) FROM DIM_LABEL)           AS actual_rows
    UNION ALL SELECT 'DIM_TRACK',                600, (SELECT COUNT(*) FROM DIM_TRACK)
    UNION ALL SELECT 'DIM_DSP_SERVICE',            7, (SELECT COUNT(*) FROM DIM_DSP_SERVICE)
    UNION ALL SELECT 'DIM_STATEMENT_MONTH',       32, (SELECT COUNT(*) FROM DIM_STATEMENT_MONTH)
    UNION ALL SELECT 'DIM_ACTIVITY_DAY',         995, (SELECT COUNT(*) FROM DIM_ACTIVITY_DAY)
    UNION ALL SELECT 'FACT_ROYALTY_MONTH',     93403, (SELECT COUNT(*) FROM FACT_ROYALTY_MONTH)
    UNION ALL SELECT 'FACT_STREAM_DAY',       213661, (SELECT COUNT(*) FROM FACT_STREAM_DAY)
    UNION ALL SELECT 'ENTITLEMENT',              305, (SELECT COUNT(*) FROM ENTITLEMENT)
)
ORDER BY object_name;

/*==============================================================================
Deployment summary
==============================================================================*/

SELECT
    'Backstage Label Analytics' AS demo,
    'SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS' AS schema_name,
    'BACKSTAGE_ANALYTICS_AGENT' AS agent,
    'SV_BACKSTAGE_REVENUE, SV_BACKSTAGE_DAILY_STREAMS' AS semantic_views,
    'BACKSTAGE_LABEL_BROAD, BACKSTAGE_LABEL_LIMITED, BACKSTAGE_LABEL_NONE' AS persona_roles,
    'AI & ML > Agents > BACKSTAGE_ANALYTICS_AGENT > Add to CoWork' AS next_step,
    'All data synthetic. See docs/RUNBOOK.md before presenting.' AS note;
