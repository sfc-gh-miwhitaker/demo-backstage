/*==============================================================================
02_access_tests.sql - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Access assertions. Every test FAILS LOUDLY rather than returning a report, so a
regression cannot be skimmed past.

IMPORTANT: this file proves nothing unless it runs under a persona role. Run it
three times, once per persona, and always with secondary roles disabled:

  snow sql -c <conn> --role BACKSTAGE_LABEL_BROAD   --secondary-roles NONE -f tests/02_access_tests.sql
  snow sql -c <conn> --role BACKSTAGE_LABEL_LIMITED --secondary-roles NONE -f tests/02_access_tests.sql
  snow sql -c <conn> --role BACKSTAGE_LABEL_NONE    --secondary-roles NONE -f tests/02_access_tests.sql

tools/run_tests.sh does exactly that. Running this as SYSADMIN passes trivially
and demonstrates nothing, because SYSADMIN holds entitlements on every label.

Expected scope:
  BROAD   - 75 labels, both permissions
  LIMITED - labels 5, 12 and 23 for revenue; labels 5 and 12 only for streams
  NONE    - no labels
==============================================================================*/

USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

/*------------------------------------------------------------------------------
Test 1. Allowed access.

Every persona with any revenue entitlement must be able to read revenue for a
label it is entitled to. LIMITED is entitled to label 5, so it must see rows.
NONE must see none. The assertion is expressed per role so one file covers all
three.
------------------------------------------------------------------------------*/

SELECT
    'T1 allowed access' AS test_name,
    CURRENT_ROLE()      AS acting_role,
    COUNT(*)            AS rows_visible,
    CASE
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_NONE' AND COUNT(*) = 0 THEN 'PASS'
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_NONE'                  THEN 'FAIL: no-access persona sees rows'
        WHEN COUNT(*) > 0                                             THEN 'PASS'
        ELSE 'FAIL: entitled persona sees no rows for a label it should see'
    END                 AS result
FROM FACT_ROYALTY_MONTH
WHERE LABEL_ID = 5;

/*------------------------------------------------------------------------------
Test 2. Another label's data is not readable.

Label 1 (Cypress Grove Records) owns the flagship recording. Only BROAD is
entitled to it. This is the assertion that the whole demo rests on.
------------------------------------------------------------------------------*/

SELECT
    'T2 other label denied' AS test_name,
    CURRENT_ROLE()          AS acting_role,
    COUNT(*)                AS rows_visible,
    CASE
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_BROAD' AND COUNT(*) > 0 THEN 'PASS'
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_BROAD'                  THEN 'FAIL: broad persona cannot see label 1'
        WHEN COUNT(*) = 0                                              THEN 'PASS'
        ELSE 'FAIL: scoped persona can read a label it is not entitled to'
    END                     AS result
FROM FACT_ROYALTY_MONTH
WHERE LABEL_ID = 1;

/*------------------------------------------------------------------------------
Test 3. No-access persona sees nothing anywhere.

Note that BACKSTAGE_LABEL_NONE holds exactly the same object grants as the other
personas. Its emptiness must come from the entitlement model, not from a missing
GRANT. A persona that fails with "insufficient privileges" would prove nothing
about row-level scoping, so this test asserts zero rows rather than an error.
------------------------------------------------------------------------------*/

SELECT
    'T3 no-access persona' AS test_name,
    CURRENT_ROLE()         AS acting_role,
    (SELECT COUNT(*) FROM FACT_ROYALTY_MONTH) AS revenue_rows,
    (SELECT COUNT(*) FROM FACT_STREAM_DAY)    AS stream_rows,
    CASE
        WHEN CURRENT_ROLE() <> 'BACKSTAGE_LABEL_NONE' THEN 'SKIP: not the no-access persona'
        WHEN (SELECT COUNT(*) FROM FACT_ROYALTY_MONTH) = 0
         AND (SELECT COUNT(*) FROM FACT_STREAM_DAY)    = 0 THEN 'PASS'
        ELSE 'FAIL: no-access persona can read fact data'
    END                    AS result;

/*------------------------------------------------------------------------------
Test 4. A permission is not implied by holding any access to the label.

LIMITED holds VIEW_LABEL_REVENUE on label 23 but NOT VIEW_LABEL_STREAMS. So it
must see revenue rows and zero stream rows for the same label. This is what
distinguishes a real permission model from "a list of labels the role can reach."
------------------------------------------------------------------------------*/

SELECT
    'T4 permission granularity' AS test_name,
    CURRENT_ROLE()              AS acting_role,
    (SELECT COUNT(*) FROM FACT_ROYALTY_MONTH WHERE LABEL_ID = 23) AS revenue_rows_label_23,
    (SELECT COUNT(*) FROM FACT_STREAM_DAY    WHERE LABEL_ID = 23) AS stream_rows_label_23,
    CASE
        WHEN CURRENT_ROLE() <> 'BACKSTAGE_LABEL_LIMITED' THEN 'SKIP: only meaningful for the limited persona'
        WHEN (SELECT COUNT(*) FROM FACT_ROYALTY_MONTH WHERE LABEL_ID = 23) > 0
         AND (SELECT COUNT(*) FROM FACT_STREAM_DAY    WHERE LABEL_ID = 23) = 0 THEN 'PASS'
        WHEN (SELECT COUNT(*) FROM FACT_ROYALTY_MONTH WHERE LABEL_ID = 23) = 0
            THEN 'FAIL: revenue permission on label 23 is not being honored'
        ELSE 'FAIL: streaming rows leaked for a label with revenue permission only'
    END                         AS result;

/*------------------------------------------------------------------------------
Test 5. Protected lookups.

A scoped persona must not be able to enumerate label or track names outside its
scope. Without a policy on the dimensions, a user could not read the numbers but
could still discover the entire roster, which is its own disclosure.
------------------------------------------------------------------------------*/

SELECT
    'T5 protected lookups' AS test_name,
    CURRENT_ROLE()         AS acting_role,
    (SELECT COUNT(*) FROM DIM_LABEL) AS labels_visible,
    (SELECT COUNT(*) FROM DIM_TRACK) AS tracks_visible,
    CASE
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_BROAD'
            THEN CASE WHEN (SELECT COUNT(*) FROM DIM_LABEL) = 75
                       AND (SELECT COUNT(*) FROM DIM_TRACK) = 600
                      THEN 'PASS' ELSE 'FAIL: broad persona cannot see the full roster' END
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_LIMITED'
            THEN CASE WHEN (SELECT COUNT(*) FROM DIM_LABEL) = 3
                       AND (SELECT COUNT(*) FROM DIM_TRACK) = 24
                      THEN 'PASS' ELSE 'FAIL: limited persona can enumerate names outside its scope' END
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_NONE'
            THEN CASE WHEN (SELECT COUNT(*) FROM DIM_LABEL) = 0
                       AND (SELECT COUNT(*) FROM DIM_TRACK) = 0
                      THEN 'PASS' ELSE 'FAIL: no-access persona can enumerate names' END
        ELSE 'SKIP: not a persona role'
    END                    AS result;

/*------------------------------------------------------------------------------
Test 6. The concentration answer refuses instead of reporting zero percent.

This is the subtle one. For a persona scoped away from the flagship recording, the
denominator is healthy and the numerator is zero, so the ratio computes cleanly to
0.00%. That number is false: it says the recording earned nothing when the caller
simply cannot see it. DIV0NULL does not help, because the denominator is not zero.

The guard is the target row count.
------------------------------------------------------------------------------*/

WITH scoped AS (
    SELECT ISRC, LABEL_NET_USD
    FROM V_LABEL_REVENUE
    WHERE DSP_FAMILY = 'Amazon'
      AND IS_RELEASED
      AND STATEMENT_MONTH >= '2025-01-01'::DATE
      AND STATEMENT_MONTH <  '2026-01-01'::DATE
),
computed AS (
    SELECT
        COUNT_IF(ISRC = 'QZSYN2400001')  AS target_rows,
        COALESCE(SUM(LABEL_NET_USD), 0)  AS denominator
    FROM scoped
)
SELECT
    'T6 no false zero percent' AS test_name,
    CURRENT_ROLE()             AS acting_role,
    target_rows,
    ROUND(denominator, 2)      AS denominator_visible,
    CASE
        WHEN denominator = 0 THEN 'UNANSWERABLE: nothing visible to divide by'
        WHEN target_rows = 0 THEN 'UNANSWERABLE: recording not visible to you'
        ELSE 'ANSWERABLE'
    END                        AS verdict,
    CASE
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_BROAD'
            THEN CASE WHEN COALESCE(target_rows, 0) > 0 AND denominator > 0 THEN 'PASS'
                      ELSE 'FAIL: broad persona should be able to answer' END
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_LIMITED'
            THEN CASE WHEN COALESCE(target_rows, 0) = 0 AND denominator > 0 THEN 'PASS'
                      ELSE 'FAIL: expected a visible denominator with an invisible numerator' END
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_NONE'
            THEN CASE WHEN COALESCE(target_rows, 0) = 0 AND denominator = 0 THEN 'PASS'
                      ELSE 'FAIL: no-access persona should see nothing at all' END
        ELSE 'SKIP: not a persona role'
    END                        AS result
FROM computed;

/*------------------------------------------------------------------------------
Test 7. Cross-persona isolation of the semantic layer.

The semantic view is a shared object. Two personas querying the identical
semantic view must get different totals, because enforcement lives under it in the
base tables rather than in the model. If both saw the same number, the semantic
layer would be bypassing the policy.

The broad total is pinned to an exact value rather than a threshold. Thresholds
invite guessing, and a threshold set too generously would pass even if the policy
leaked a subset it should not have.
------------------------------------------------------------------------------*/

SELECT
    'T7 semantic view is scoped' AS test_name,
    CURRENT_ROLE()               AS acting_role,
    ROUND(COALESCE(SUM(total_revenue), 0), 2) AS amazon_revenue_visible,
    CASE
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_BROAD'
            THEN CASE WHEN ROUND(SUM(total_revenue), 2) = 63944186.85 THEN 'PASS'
                      ELSE 'FAIL: broad persona total does not match the full expected Amazon total' END
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_LIMITED'
            THEN CASE WHEN SUM(total_revenue) > 0 AND SUM(total_revenue) < 63944186.85 THEN 'PASS'
                      ELSE 'FAIL: limited persona total is not a strict subset' END
        WHEN CURRENT_ROLE() = 'BACKSTAGE_LABEL_NONE'
            THEN CASE WHEN SUM(total_revenue) IS NULL THEN 'PASS'
                      ELSE 'FAIL: no-access persona reached data through the semantic view' END
        ELSE 'SKIP: not a persona role'
    END                          AS result
FROM SEMANTIC_VIEW(
    SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_REVENUE
    METRICS revenue.total_revenue
    DIMENSIONS revenue.dsp_family
)
WHERE dsp_family = 'Amazon';

/*------------------------------------------------------------------------------
Test 8. A persona cannot read or alter its own authorization.

ENTITLEMENT is never granted to a persona. The row access policies read it under
the policy owner's rights, so scoping works without the subject being able to
inspect or edit it.

THIS TEST IS LAST ON PURPOSE. It is the only statement in this file expected to
raise an error, and a failing statement aborts everything after it in the script.
When this block sat in the middle, tests 6 and 7 silently never ran and the suite
still reported success -- which is exactly the kind of quiet gap a test suite is
supposed to prevent.

A result set here is a FAIL. An "insufficient privileges" error is a PASS, and
tools/run_tests.sh checks for that error text rather than the exit code.
------------------------------------------------------------------------------*/

SELECT
    'T8 entitlement table is not readable' AS test_name,
    CURRENT_ROLE()                         AS acting_role,
    'The next statement must fail with insufficient privileges.' AS expectation;

SELECT COUNT(*) AS entitlement_rows_readable
FROM SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.ENTITLEMENT;
