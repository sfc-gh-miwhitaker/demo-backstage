/*==============================================================================
01_setup.sql - Backstage Label Analytics
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22

Infrastructure and the deterministic configuration constants that every
downstream expected value depends on.
==============================================================================*/

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE
  COMMENT = 'Shared database for SE demo projects';

CREATE WAREHOUSE IF NOT EXISTS SFE_BACKSTAGE_ANALYTICS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 600
  COMMENT = 'DEMO: Backstage label analytics compute (Expires: 2026-10-22)';

USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS
  COMMENT = 'Shared schema for semantic views across SE demo projects';

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS
  COMMENT = 'DEMO: Governed music-label conversational analytics. All data synthetic. (Expires: 2026-10-22)';

USE SCHEMA SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS;

/*------------------------------------------------------------------------------
DEMO_CONFIG - the single source of determinism.

DEMO_AS_OF is pinned, not CURRENT_DATE(). Every fact value is derived by hashing
against it, so redeploying on a different calendar day produces byte-identical
data and the expected values in docs/EXPECTED_RESULTS.md stay valid.

Changing DEMO_AS_OF invalidates every expected value. Do not change it without
regenerating docs/EXPECTED_RESULTS.md.
------------------------------------------------------------------------------*/

CREATE OR REPLACE TABLE DEMO_CONFIG (
    RELEASE_ID          VARCHAR(50)  NOT NULL,
    DEMO_AS_OF          DATE         NOT NULL COMMENT 'Pinned "today" for the dataset',
    HISTORY_START       DATE         NOT NULL COMMENT 'First activity date and first statement month',
    LAST_RELEASED_MONTH DATE         NOT NULL COMMENT 'Newest statement month with IS_RELEASED = TRUE',
    LAST_COMPLETE_DAY   DATE         NOT NULL COMMENT 'Newest activity date with IS_COMPLETE = TRUE',
    SYNTHETIC           BOOLEAN      NOT NULL,
    CONSTRAINT PK_DEMO_CONFIG PRIMARY KEY (RELEASE_ID)
)
COMMENT = 'DEMO: Deterministic generation constants. (Expires: 2026-10-22)';

INSERT INTO DEMO_CONFIG
    (RELEASE_ID, DEMO_AS_OF, HISTORY_START, LAST_RELEASED_MONTH, LAST_COMPLETE_DAY, SYNTHETIC)
VALUES
    ('backstage-v1-seed-8831', '2026-09-22', '2024-01-01', '2026-07-01', '2026-09-15', TRUE);

/*
 Coverage shape and why each boundary exists:

 - Statement months run 2024-01 through 2026-08. 2026-08 is present but
   IS_RELEASED = FALSE, so "comparable released periods" excludes it and the
   newest released month is 2026-07. Question 2 compares 2026-07 against 2026-06.
 - Calendar 2025 is fully released, so question 1's denominator is stable.
 - Activity dates run 2024-01-01 through 2026-09-21. The last six days
   (2026-09-16 .. 2026-09-21) are IS_COMPLETE = FALSE, so question 4's "latest
   seven complete days" resolves to 2026-09-09 .. 2026-09-15 and the incomplete
   tail is visible rather than silently included.
*/
