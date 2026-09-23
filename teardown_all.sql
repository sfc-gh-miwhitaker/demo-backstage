/*==============================================================================
TEARDOWN ALL - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Removes everything this demo created, and nothing else.

USAGE
  Snowsight: open a new worksheet, run the SET below, paste this file, Run All.
  Terminal:  snow sql -c <connection> -f teardown_all.sql

  SET BACKSTAGE_CONFIRM = 'TEARDOWN';

That word is deliberately not DEPLOY: deployment requires no confirmation because
it is additive and idempotent, while this script drops a schema and three
account-level roles. One setting must never be able to run both scripts.

DELIBERATELY NOT DROPPED -- these are shared across SE demo projects:
  SNOWFLAKE_EXAMPLE                     database
  SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS     schema (only this project's views inside it)
  SNOWFLAKE_EXAMPLE.GIT_REPOS           schema

DELIBERATELY NOT DROPPED -- the deployment source, not the deployment:
  SFE_BACKSTAGE_ANALYTICS_GIT_API                        API integration
  SNOWFLAKE_EXAMPLE.GIT_REPOS.BACKSTAGE_ANALYTICS_REPO   Git repository clone

  Keeping those two means a redeployment does not have to re-fetch from GitHub and
  does not need ACCOUNTADMIN again -- only the first deployment in an account ever
  needs it. To remove them as well, after this script:

    USE ROLE SYSADMIN;
    DROP GIT REPOSITORY IF EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS.BACKSTAGE_ANALYTICS_REPO;
    USE ROLE ACCOUNTADMIN;
    DROP INTEGRATION IF EXISTS SFE_BACKSTAGE_ANALYTICS_GIT_API;

Every drop below names one object. There is no DROP DATABASE and no CASCADE. The
project schema is dropped with RESTRICT so that an unexpected dependency raises an
error instead of silently taking something else with it.

Every statement is IF EXISTS, so a partial deployment tears down cleanly and the
script is safe to re-run.
==============================================================================*/

USE ROLE SYSADMIN;

/*------------------------------------------------------------------------------
Confirmation gate. Teardown is the irreversible half of this project, and the
names it drops are account-level, so it asks for one deliberate word. Deployment
asks for nothing.
------------------------------------------------------------------------------*/

EXECUTE IMMEDIATE $$
DECLARE
  invalid_confirmation EXCEPTION (-20005, 'Set BACKSTAGE_CONFIRM to TEARDOWN before removing the demo:  SET BACKSTAGE_CONFIRM = ''TEARDOWN'';');
  forbidden_target EXCEPTION (-20003, 'Refusing to run: this account is never a demo target.');
BEGIN
  IF (CURRENT_ACCOUNT_NAME() ILIKE '%SNOWHOUSE%') THEN
    RAISE forbidden_target;
  END IF;
  -- GETVARIABLE returns NULL for a variable that was never SET, rather than
  -- raising, so one comparison covers both "unset" and "set to the wrong word".
  -- IS DISTINCT FROM is the NULL-safe comparison: a plain <> against NULL yields
  -- NULL, which is not TRUE, and the gate would fall open.
  IF (GETVARIABLE('BACKSTAGE_CONFIRM') IS DISTINCT FROM 'TEARDOWN') THEN
    RAISE invalid_confirmation;
  END IF;
END;
$$;

-- 1. Agent first: it references the semantic views.
DROP AGENT IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.BACKSTAGE_ANALYTICS_AGENT;

-- 2. Semantic views, which live in the shared SEMANTIC_MODELS schema.
DROP SEMANTIC VIEW IF EXISTS SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_REVENUE;
DROP SEMANTIC VIEW IF EXISTS SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_DAILY_STREAMS;

-- 3. Detach row access policies before dropping them. A policy attached to a
--    table cannot be dropped, and DROP ALL ROW ACCESS POLICIES succeeds even when
--    nothing is attached, so this is safe on a partially deployed schema.
ALTER TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.FACT_ROYALTY_MONTH DROP ALL ROW ACCESS POLICIES;
ALTER TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.FACT_STREAM_DAY    DROP ALL ROW ACCESS POLICIES;
ALTER TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DIM_LABEL          DROP ALL ROW ACCESS POLICIES;
ALTER TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DIM_TRACK          DROP ALL ROW ACCESS POLICIES;

DROP ROW ACCESS POLICY IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.LABEL_REVENUE_POLICY;
DROP ROW ACCESS POLICY IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.LABEL_STREAMS_POLICY;
DROP ROW ACCESS POLICY IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.LABEL_LOOKUP_POLICY;

-- 4. Analytic views.
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.V_TRACK_TITLE_AMBIGUITY;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.V_STREAM_COVERAGE;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.V_DAILY_STREAMS;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.V_LABEL_REVENUE;

-- 5. Facts, dimensions, and configuration.
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.FACT_STREAM_DAY;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.FACT_ROYALTY_MONTH;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.ENTITLEMENT;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DIM_ACTIVITY_DAY;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DIM_STATEMENT_MONTH;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DIM_TRACK;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DIM_DSP_SERVICE;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DIM_LABEL;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.DEMO_CONFIG;

-- 6. Project schema. RESTRICT, never CASCADE.
DROP SCHEMA IF EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS RESTRICT;

-- 7. Warehouse.
DROP WAREHOUSE IF EXISTS SFE_BACKSTAGE_ANALYTICS_WH;

-- 8. Persona roles.
USE ROLE USERADMIN;
DROP ROLE IF EXISTS BACKSTAGE_LABEL_BROAD;
DROP ROLE IF EXISTS BACKSTAGE_LABEL_LIMITED;
DROP ROLE IF EXISTS BACKSTAGE_LABEL_NONE;

USE ROLE SYSADMIN;

SELECT 'Backstage Label Analytics removed.' AS status,
       'SNOWFLAKE_EXAMPLE, SEMANTIC_MODELS and GIT_REPOS were preserved.' AS note,
       'The API integration and Git repository clone were preserved, so redeploy needs no ACCOUNTADMIN.' AS source_note;
