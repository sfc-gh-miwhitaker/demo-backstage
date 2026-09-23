/*==============================================================================
deploy.sql - deployment orchestrator, run inside Snowflake
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Purpose  Execute the whole deployment in dependency order from one Git commit, so
         every object in the account comes from the same revision of the source.
Called   By deploy_all.sql, which resolves main's commit hash and executes this
         file at @...BACKSTAGE_ANALYTICS_REPO/commits/<hash>/sql/deploy.sql.
         Not intended to be run by hand.

Order    setup -> data -> governance -> semantic views -> agent -> grants.
         Each step depends on the one before it.

           03 must follow 02, because CREATE OR REPLACE TABLE in 02 drops the
              row access policy attachments that 03 creates.
           06 is last, because GRANT fails on an object that does not yet exist,
              and it grants on both semantic views and the agent.

Paths    Relative, and deliberately so. A relative path in a nested
         EXECUTE IMMEDIATE FROM resolves against the parent file's directory --
         here /commits/<hash>/sql/ -- so all six modules come from the same
         pinned commit with no templating and no hash substitution. A top-level
         EXECUTE IMMEDIATE FROM could not do this: relative paths are legal only
         inside an executing file.
==============================================================================*/

-- 1. Infrastructure and deterministic configuration
EXECUTE IMMEDIATE FROM './01_setup.sql';

-- 2. Synthetic dimensions and both fact grains
EXECUTE IMMEDIATE FROM './02_data.sql';

-- 3. Entitlements, row access policies, persona roles, analytic views
EXECUTE IMMEDIATE FROM './03_governance.sql';

-- 4. The two semantic views
EXECUTE IMMEDIATE FROM './04_semantic_views.sql';

-- 5. The Cortex Agent
EXECUTE IMMEDIATE FROM './05_agent.sql';

-- 6. Persona grants
EXECUTE IMMEDIATE FROM './06_grants.sql';

/*==============================================================================
Row count manifest.

These counts are fixed by the deterministic generator. A mismatch means the data
did not build as expected, and every expected value in docs/EXPECTED_RESULTS.md
should be treated as invalid until it is resolved.

This RAISES on mismatch rather than returning a status column. EXECUTE IMMEDIATE
FROM returns only the result of the last statement in the file, so a manifest
that reported 'MISMATCH' in a column would be invisible to the operator running
deploy_all.sql -- and a check nobody sees is not a check. Failing loudly is the
only way this survives the Git handoff.

The role matters here. Four of these tables carry row access policies, so this
must run as a role that holds entitlements. SYSADMIN does, via rows in
ENTITLEMENT rather than any policy exemption. A role such as SECURITYADMIN holds
none and would report every protected table as empty. 06_grants.sql restores
SYSADMIN on its last line; these statements re-pin it anyway, so the manifest
cannot be thrown off by a change upstream.
==============================================================================*/

USE ROLE SYSADMIN;
USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

EXECUTE IMMEDIATE $$
DECLARE
  detail VARCHAR;
  stmt VARCHAR;
BEGIN
  -- One row per object that did not match. NULL when everything matched, because
  -- LISTAGG over zero rows returns an empty string and MAX of no rows is NULL --
  -- so the emptiness is tested explicitly below rather than assumed.
  SELECT LISTAGG(object_name || ' expected ' || expected_rows || ' got ' || actual_rows, '; ')
           WITHIN GROUP (ORDER BY object_name)
    INTO :detail
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
  WHERE actual_rows <> expected_rows;

  IF (detail IS NOT NULL AND detail <> '') THEN
    -- A Snowflake Scripting exception message is fixed when the exception is
    -- declared, so the failing counts are carried by declaring the exception
    -- inside a nested block built as a string. Without this the operator would
    -- get 'manifest mismatch' with no indication of which table was wrong.
    -- REPLACE doubles any single quote so the detail cannot break the literal.
    stmt := 'DECLARE manifest_mismatch EXCEPTION (-20010, ''Row count manifest mismatch. '
      || 'Data did not build as expected; treat docs/EXPECTED_RESULTS.md as invalid until resolved. '
      || REPLACE(detail, '''', '''''') || '''); BEGIN RAISE manifest_mismatch; END;';
    EXECUTE IMMEDIATE :stmt;
  END IF;

  RETURN 'Row count manifest: 8 of 8 OK.';
END;
$$;

/*==============================================================================
Deployment summary.

Last statement in the file, so this is what EXECUTE IMMEDIATE FROM returns to
deploy_all.sql when everything succeeded.
==============================================================================*/

SELECT
    'Backstage Label Analytics' AS demo,
    'SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS' AS schema_name,
    'BACKSTAGE_ANALYTICS_AGENT' AS agent,
    'SV_BACKSTAGE_REVENUE, SV_BACKSTAGE_DAILY_STREAMS' AS semantic_views,
    'BACKSTAGE_LABEL_BROAD, BACKSTAGE_LABEL_LIMITED, BACKSTAGE_LABEL_NONE' AS persona_roles,
    'AI & ML > Agents > BACKSTAGE_ANALYTICS_AGENT > Add to CoWork' AS next_step,
    'All data synthetic. See docs/RUNBOOK.md before presenting.' AS note;
