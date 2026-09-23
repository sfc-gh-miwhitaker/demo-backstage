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

This file is the only part of the deployment that is pasted in by hand. It
connects the account to the public Git repository, then hands off to
sql/deploy.sql at a pinned commit; everything after that runs from source inside
Snowflake.

IMPORTANT: this deploys what is PUSHED to the repository's main branch, not what
is on your laptop. Local edits that have not been pushed will not appear in the
account. Redeploying replaces the agent, which resets its version history.

The first deployment in a fresh account needs ACCOUNTADMIN once, to create the
API integration. Every later deployment runs as SYSADMIN, because teardown
preserves the integration and the repository clone.

To remove everything, run teardown_all.sql.
==============================================================================*/

/*------------------------------------------------------------------------------
ACCOUNTADMIN is needed only for the API integration -- CREATE INTEGRATION is an
account-level privilege. The file drops back to SYSADMIN as soon as that is
done, and every object the demo owns is created as SYSADMIN.
------------------------------------------------------------------------------*/

USE ROLE ACCOUNTADMIN;

/*------------------------------------------------------------------------------
Outbound access to exactly one repository. The prefix allowlist is the security
boundary: this integration cannot be reused to fetch code from anywhere else.

ALLOWED_AUTHENTICATION_SECRETS = NONE states that the source is public and no
credential is involved, so nothing here can leak one.
------------------------------------------------------------------------------*/

CREATE API INTEGRATION IF NOT EXISTS SFE_BACKSTAGE_ANALYTICS_GIT_API
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-miwhitaker/demo-backstage.git')
  ALLOWED_AUTHENTICATION_SECRETS = NONE
  ENABLED = TRUE
  COMMENT = 'DEMO: Public Backstage label analytics source (Expires: 2026-10-22)';

GRANT USAGE ON INTEGRATION SFE_BACKSTAGE_ANALYTICS_GIT_API TO ROLE SYSADMIN;

/*------------------------------------------------------------------------------
Everything from here holds no privilege it does not need.
------------------------------------------------------------------------------*/

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE
  COMMENT = 'Shared database for SE demo projects';

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS
  COMMENT = 'Shared schema for Git repository clones across SE demo projects';

/*------------------------------------------------------------------------------
The repository clone lives outside the project schema on purpose, so teardown
can remove the demo without removing the source it came from -- and a
redeployment does not have to re-fetch from GitHub or rebuild the integration.
------------------------------------------------------------------------------*/

CREATE GIT REPOSITORY IF NOT EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS.BACKSTAGE_ANALYTICS_REPO
  API_INTEGRATION = SFE_BACKSTAGE_ANALYTICS_GIT_API
  ORIGIN = 'https://github.com/sfc-gh-miwhitaker/demo-backstage.git'
  COMMENT = 'DEMO: Backstage label analytics source; preserved on teardown (Expires: 2026-10-22)';

/*------------------------------------------------------------------------------
Created here as well as in sql/01_setup.sql because the Git fetch and the
deployment script itself need compute before 01_setup.sql runs. The definition is
identical in both places, and CREATE IF NOT EXISTS makes the second one a no-op.
------------------------------------------------------------------------------*/

CREATE WAREHOUSE IF NOT EXISTS SFE_BACKSTAGE_ANALYTICS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 600
  COMMENT = 'DEMO: Backstage label analytics compute (Expires: 2026-10-22)';

USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;

-- Pull the current state of the remote into the clone.
ALTER GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.BACKSTAGE_ANALYTICS_REPO FETCH;

/*------------------------------------------------------------------------------
Resolve main to a commit hash, then run the deployment from that commit.

Why pin at all: /branches/main is a moving pointer. Reading it once and then
deploying from /commits/<hash> means all six SQL modules come from a single
revision, and the revision is echoed back to the operator. A deployment that
took two minutes cannot straddle two versions of the source, and the account's
contents can always be traced to one commit.

No Jinja templating is involved. sql/deploy.sql reaches its modules with relative
paths, which resolve against the parent file's directory -- so they come from
this same pinned commit automatically.
------------------------------------------------------------------------------*/

EXECUTE IMMEDIATE $$
DECLARE
  revision VARCHAR;
  statement VARCHAR;
  invalid_revision EXCEPTION (-20002, 'Expected one main branch with a full Git commit hash. Confirm the repository is public and main has been pushed.');
BEGIN
  -- SHOW has no WHERE clause, so its output is filtered through RESULT_SCAN.
  SHOW GIT BRANCHES LIKE 'main' IN GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.BACKSTAGE_ANALYTICS_REPO;
  -- LIKE is a pattern, so it can match more than one branch name; MAX plus the
  -- exact-name predicate collapses that to a single deterministic value. The
  -- double-quoted column names are required: SHOW returns lowercase identifiers.
  SELECT MAX("commit_hash") INTO :revision FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = 'main';
  -- Validate the shape before interpolating it. The revision is about to be
  -- concatenated into an executed statement, so requiring 40 hex characters is
  -- what keeps that concatenation from being an injection point.
  IF (revision IS NULL OR NOT REGEXP_LIKE(revision, '[0-9a-f]{40}')) THEN
    RAISE invalid_revision;
  END IF;
  -- The statement is built dynamically because a stage path cannot be
  -- parameterised. A top-level EXECUTE IMMEDIATE FROM requires an absolute path;
  -- only nested calls inside a file may use relative paths.
  statement := 'EXECUTE IMMEDIATE FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.BACKSTAGE_ANALYTICS_REPO/commits/'
    || revision || '/sql/deploy.sql';
  EXECUTE IMMEDIATE :statement;
  RETURN 'Deployed Backstage Label Analytics from commit ' || revision
    || '. Next: AI & ML > Agents > BACKSTAGE_ANALYTICS_AGENT > Add to CoWork.'
    || ' All data synthetic. See docs/RUNBOOK.md before presenting.';
END;
$$;

/*==============================================================================
Expiration check (informational -- warns but does not block deployment).

Demo objects should not outlive their review date. This final select makes the
expiry visible in the deployment output rather than leaving it buried in object
comments, so a stale demo announces itself when redeployed.
==============================================================================*/

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
