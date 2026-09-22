---
name: demo-backstage
description: Governed music-label conversational analytics demo. Two semantic views over separate revenue and daily-streaming grains, one Cortex Agent in CoWork, and label-scoped entitlements enforced by a row access policy. Use when working on demo-backstage, Backstage label analytics, SV_BACKSTAGE_REVENUE, SV_BACKSTAGE_DAILY_STREAMS, BACKSTAGE_ANALYTICS_AGENT, label entitlement scoping, royalty statement month versus streaming activity date, revenue concentration questions, month-over-month label growth ranking, or DSP family rollup.
---

# demo-backstage — Backstage Label Analytics

## Purpose

Prove that a conversational analytics agent can answer music-label revenue and
streaming questions while never returning a row the asking user is not entitled
to see. The governance is the point; the five questions are the vehicle.

## Architecture

Two fact grains that are never joined:

| Fact | Grain | Measure | Gate |
|---|---|---|---|
| `FACT_ROYALTY_MONTH` | statement month x label x track x DSP service | `LABEL_NET_USD` | `IS_RELEASED` |
| `FACT_STREAM_DAY` | activity date x track x DSP service | `STREAMS` | `IS_COMPLETE` |

75 labels, 600 tracks, 7 DSP services in 4 families. Royalty months 2024-01 to
2026-08 (93,403 rows); activity days 2024-01-01 to 2026-09-21 (213,661 rows).
Generation is `HASH()`-seeded against a pinned `DEMO_AS_OF` in `DEMO_CONFIG`.

`ENTITLEMENT(PRINCIPAL, PERMISSION, LABEL_ID)` plus three row access policies: one
per permission on the facts, and one accepting either permission on the lookup
dimensions. One agent exposes both grains as two Cortex Analyst tools plus
`data_to_chart`. CoWork is the chat surface and supplies real end-user identity.

## Key Files

| File | Contents |
|---|---|
| `deploy_all.sql` | Self-contained deployment; sources every `sql/` module in order |
| `sql/01_setup.sql` | Infrastructure and `DEMO_CONFIG` (`DEMO_AS_OF`, `RELEASE_ID`) |
| `sql/02_data.sql` | Deterministic synthetic dimensions and both facts |
| `sql/03_governance.sql` | `ENTITLEMENT`, row access policy, persona roles, lookup views |
| `sql/04_semantic_views.sql` | The two semantic views |
| `sql/05_agent.sql` | `BACKSTAGE_ANALYTICS_AGENT` |
| `sql/06_grants.sql` | Persona grants, including `REFERENCES` on both views |
| `tests/01_reference_queries.sql` | Independent ground truth for all five questions |
| `tests/02_access_tests.sql` | Eight access assertions; the expected-failure test is last on purpose |
| `tools/run_tests.sh` | Runs both suites, once per persona, exits non-zero on failure |
| `docs/RUNBOOK.md` | Presenter walkthrough |
| `docs/EXPECTED_RESULTS.md` | Pinned expected values; invalid if `DEMO_AS_OF` or the seed changes |
| `docs/TEST_EVIDENCE.md` | Measured results, latency, and every defect found during verification |

## Extension Playbook: add a sixth question

Worked example — adding "streams by territory," which the current model cannot
answer because there is no territory dimension.

1. **Decide the grain.** Territory belongs on daily activity, so it extends
   `FACT_STREAM_DAY`, not the royalty fact. Adding it to both would invite a
   cross-grain join.
2. **Extend the dimension.** In `sql/02_data.sql`, add `DIM_TERRITORY` and a
   `TERRITORY_ID` column on `FACT_STREAM_DAY`. Seed it with `HASH()` against
   `DEMO_AS_OF` — never `RANDOM()`. Row count rises by the territory cardinality,
   so update the manifest counts in `deploy_all.sql`.
3. **Re-check the policy.** The row access policy keys on `LABEL_ID`, which is
   unchanged, so entitlements still hold. Confirm by re-running
   `tests/02_access_tests.sql` under all three persona roles. If you had keyed the
   new dimension to a different grain you would need a second policy.
4. **Write the reference query first.** Add the expected answer to
   `tests/01_reference_queries.sql` and `docs/EXPECTED_RESULTS.md` before
   touching the semantic view, so ground truth is independent of the model.
5. **Extend the semantic view.** Add the logical table, the relationship, and a
   `territory` dimension with `SAMPLE_VALUES` then `IS_ENUM` to
   `SV_BACKSTAGE_DAILY_STREAMS`. Keep clause order.
6. **Extend the agent.** Update the daily-streams tool description and add a
   `sample_questions` entry. A semantic view change alone is not enough — the
   agent's routing and refusal instructions still describe the old surface, so it
   will keep declining the new question.
7. **Grant.** `GRANT SELECT, REFERENCES` is already in place on the view, so no
   new grant is needed unless you created a new object.
8. **Verify.** Redeploy, confirm the manifest row counts, run both test suites,
   then ask the question in CoWork.

Steps 5 and 6 together are the whole point: closing a capability gap takes a data
edit, a semantic edit, and an agent edit. Doing only one leaves the agent
refusing a question the data can now answer.

## Snowflake Objects

| Object | Name |
|---|---|
| Schema | `SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS` |
| Warehouse | `SFE_BACKSTAGE_ANALYTICS_WH` |
| Semantic views | `SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_BACKSTAGE_REVENUE`, `SV_BACKSTAGE_DAILY_STREAMS` |
| Agent | `SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.BACKSTAGE_ANALYTICS_AGENT` |
| Roles | `BACKSTAGE_LABEL_BROAD`, `BACKSTAGE_LABEL_LIMITED`, `BACKSTAGE_LABEL_NONE` |
| Policies | `LABEL_REVENUE_POLICY`, `LABEL_STREAMS_POLICY`, `LABEL_LOOKUP_POLICY` |

## Gotchas

Each of these was hit during the build. They are recorded because most of them
produced a plausible wrong answer rather than an error.

- **`FACTS` is not a row-level escape hatch.** Requesting a raw fact alongside
  dimensions returns it at the dimension grain, not per source row. Summing it
  collapses the multiple services inside a DSP family and silently understates
  both a numerator and a denominator. Always aggregate through `METRICS`.
- **`DIV0NULL` does not catch the dangerous divide.** A scoped user asking about a
  recording outside their entitlement gets a healthy denominator and a zero
  numerator, so the ratio computes cleanly to `0.00%`. That asserts the recording
  earned nothing when the truth is the caller cannot see it. Guard on the target
  row count, not just on the denominator.
- **A bare proper noun is read as whatever the dimensions suggest.** Without
  `SAMPLE_VALUES`, the agent read a track title as a label name, found nothing, and
  refused for the wrong reason. `SAMPLE_VALUES` on title, artist, and label plus an
  explicit resolution order fixed it.
- **A failing statement aborts the rest of a SQL script.** The deliberately failing
  privilege test sat mid-file, so the two tests after it silently never ran and the
  suite still reported success. Keep expected-failure tests last.
- **Threshold assertions hide leaks.** Two access assertions used guessed
  thresholds and were wrong in both directions. Pin expected totals to exact
  deterministic values.
- **An agent needs `SELECT` and `REFERENCES`** on a semantic view it does not own.
  `SELECT` alone works for direct queries and fails through the agent, with an
  error that does not mention the grant.
- **Semantic view clause order is significant.** `SAMPLE_VALUES` must precede
  `IS_ENUM` within a dimension.
- **There is no admin bypass, which cuts both ways.** Any role without entitlement
  rows sees every protected table as empty. A deploy step that ended as
  `SECURITYADMIN` made the row count manifest report zeros. Pin the role before
  reading protected tables.
- **`CREATE OR REPLACE ROW ACCESS POLICY` fails while the policy is attached.**
  Detach with `ALTER TABLE ... DROP ALL ROW ACCESS POLICIES` first, which succeeds
  even when nothing is attached.
- **Do not read a policy-protected dimension while rebuilding `ENTITLEMENT`.** On a
  redeploy the policy is already attached and the table has just been emptied, so
  the read returns nothing and every principal is locked out. Generate the key list
  instead.
- **`RANDOM()` or `CURRENT_DATE()` in fact generation** breaks reproducibility and
  silently invalidates every value in `docs/EXPECTED_RESULTS.md`.
- **Noise drowns the signal it is supposed to decorate.** Per-month line jitter and
  per-month sparsity both swamped a 1.7% monthly growth rate, so a
  "largest increases" ranking measured noise. Both are now structural, keyed on the
  track and service rather than the month.
- **Zero prior revenue is not infinite growth, and a missing month is not zero.**
  Preserve that distinction if you rewrite the growth query. Also do not pad a
  requested top-N with decliners to reach the count.
