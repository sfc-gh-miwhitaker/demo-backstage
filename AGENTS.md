# Backstage Label Analytics — Project Instructions

<!-- Global rules apply via ~/.claude/CLAUDE.md and rules/. Do not duplicate them here. -->

## Architecture

Two fact grains, never joined:

- `FACT_ROYALTY_MONTH` — monthly statement grain. Keys: `STATEMENT_MONTH`,
  `LABEL_ID`, `TRACK_KEY`, `DSP_SERVICE_ID`. Measure: `LABEL_NET_USD`.
- `FACT_STREAM_DAY` — daily activity grain. Keys: `ACTIVITY_DATE`, `TRACK_KEY`,
  `DSP_SERVICE_ID`. Measure: `STREAMS`.

One semantic view per grain, one agent over both. A row access policy on both
facts resolves the caller against `ENTITLEMENT(PRINCIPAL, PERMISSION, LABEL_ID)`.

## Conventions

- **Determinism is a correctness requirement.** All synthetic data is seeded with
  `HASH()` against `DEMO_AS_OF` in `DEMO_CONFIG`. Never introduce `RANDOM()`,
  `UNIFORM(..., RANDOM())`, or `CURRENT_DATE()` into fact generation — expected
  results in `docs/EXPECTED_RESULTS.md` would silently drift on redeploy.
- **Never add a relationship between the two facts** in either semantic view, and
  never write a query that joins them. A statement month is not an activity date.
- Reference queries in `tests/` are the ground truth. They are hand-written
  against base tables and must not be rewritten to route through a semantic view.
- Every fact and dimension carries `SYNTHETIC` and `RELEASE_ID` provenance
  columns. Preflight and teardown depend on them.
- `IS_RELEASED` gates revenue answers; `IS_COMPLETE` gates daily answers. Both
  live in `DIM_PERIOD`.
- Fictional entities only. No real label, artist, or track names in any tracked
  file, including comments and sample values.

## Key Commands

```bash
# Deploy: paste deploy_all.sql into Snowsight and Run All, or:
snow sql -c <connection> -f deploy_all.sql

# Tests
bash tools/run_tests.sh --connection <connection>

# Teardown (requires the confirmation variable)
snow sql -c <connection> -q "SET BACKSTAGE_CONFIRM = 'TEARDOWN';" -f teardown_all.sql
```

Deployment runs from Git, not from disk. `deploy_all.sql` creates the API
integration and repository clone, resolves `main` to a commit hash, and executes
`sql/deploy.sql` from `@...BACKSTAGE_ANALYTICS_REPO/commits/<hash>/sql/`. **Local
edits do not deploy until they are pushed.** When iterating on a module, push
first or run that module directly with `snow sql -f sql/0N_....sql`.

## Snowflake Objects

| Object | Name |
|---|---|
| Database | `SNOWFLAKE_EXAMPLE` (shared — never drop) |
| Schema | `SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS` |
| Semantic views | `SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_REVENUE`, `SV_BACKSTAGE_DAILY_STREAMS` |
| Warehouse | `SFE_BACKSTAGE_ANALYTICS_WH` |
| Agent | `SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.BACKSTAGE_ANALYTICS_AGENT` |
| Persona roles | `BACKSTAGE_LABEL_BROAD`, `BACKSTAGE_LABEL_LIMITED`, `BACKSTAGE_LABEL_NONE` |
| API integration | `SFE_BACKSTAGE_ANALYTICS_GIT_API` (preserved on teardown) |
| Git repository | `SNOWFLAKE_EXAMPLE.GIT_REPOS.BACKSTAGE_ANALYTICS_REPO` (preserved on teardown) |

`SNOWFLAKE_EXAMPLE`, `SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS`, and
`SNOWFLAKE_EXAMPLE.GIT_REPOS` are shared across SE projects. Teardown drops the
project schema with `RESTRICT`, the two `SV_BACKSTAGE_*` views, the warehouse, and
the three persona roles — nothing else. The API integration and the repository
clone survive on purpose, so redeployment needs neither a re-fetch nor
ACCOUNTADMIN.

## Gotchas

- Deployment is **commit-pinned from the pushed remote**. A module edited locally
  and not pushed will not appear in the account, and the deployment will still
  report success — from the previous commit.
- `EXECUTE IMMEDIATE FROM` returns only the **last statement's** result, which is
  why the row count manifest in `sql/deploy.sql` raises on mismatch instead of
  returning a status column. A status column would be invisible through the Git
  handoff. Never convert it back to a plain `SELECT`.
- A relative path in `EXECUTE IMMEDIATE FROM` is legal only **inside** an
  executing file, and resolves against that file's directory. `sql/deploy.sql`
  depends on this to keep every module on the pinned commit; the top-level call in
  `deploy_all.sql` must stay absolute.
- No module may contain `{{`, `{%`, or `{#`. Nothing is Jinja-rendered today, but
  adding a `USING` clause to any `EXECUTE IMMEDIATE FROM` would turn that file
  into a template and those sequences into syntax errors. Files in a Git
  repository also cannot be loaded from inside a Jinja template, so prefer nested
  `EXECUTE IMMEDIATE FROM` over Jinja `include`.
- An agent needs **both** `SELECT` and `REFERENCES` on a semantic view it does
  not own. `SELECT` alone lets you query the view directly but fails through the
  agent, and the error does not point at the missing grant.
- Semantic view clause order is significant: `TABLES`, `RELATIONSHIPS`, `FACTS`,
  `DIMENSIONS`, `METRICS`, `COMMENT`, then `AI_*` clauses. Reordering is a syntax
  error. Within a dimension, `SAMPLE_VALUES` must precede `IS_ENUM`.
- Row access policies apply to the role that owns the query, so deployment and
  verification under `SYSADMIN` see everything. Access tests must run under the
  persona roles or they prove nothing.
