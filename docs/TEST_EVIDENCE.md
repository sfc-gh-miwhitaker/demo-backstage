# Test Evidence

Recorded 2026-09-22 against `RELEASE_ID` `backstage-v1-seed-8831` on the SE demo
account. Every figure below was measured, not estimated. Nothing here is a
projection, a benchmark, or an ROI claim.

## Deployment

| Check | Result |
|---|---|
| Full teardown, then clean deploy from scratch | Pass, 46 seconds, exit 0 |
| Deploy re-run over an existing deployment | Pass, idempotent |
| Row count manifest, 8 objects | 8 of 8 `OK` |
| Determinism: identical counts after full rebuild | Pass |
| Teardown leaves shared objects intact | Pass — `SNOWFLAKE_EXAMPLE`, its `SEMANTIC_MODELS` schema, and every unrelated sibling schema in the database all present after teardown |

## Correctness suite

`bash tools/run_tests.sh --connection <conn>` — all checks passed.

Eight value spot checks against `docs/EXPECTED_RESULTS.md`:

| Check | Result |
|---|---|
| Q1 concentration 9.31% of $28,609,484.50 | Pass |
| Q1 verdict `ANSWERABLE` under broad scope | Pass |
| Q2 population: 75 labels, 69 increased, 6 declined | Pass |
| Q2 top mover Foxglove Audio +$11,827.46 (4.4%) | Pass |
| Q3 YouTube coverage 24 of 31 days | Pass |
| Q4 window 2026-09-09 to 2026-09-15, 7 days | Pass |
| Q5 peak tie 2025-06-14 at 98,750 | Pass |
| Q5 peak tie 2026-02-21 at 98,750 | Pass |

## Access suite

Eight assertions, run three times under each persona role with
`--secondary-roles NONE`. Skips are expected: several tests target one specific
persona.

| Persona | Passed | Skipped | Failed |
|---|---|---|---|
| `BACKSTAGE_LABEL_BROAD` | 5 | 2 | 0 |
| `BACKSTAGE_LABEL_LIMITED` | 6 | 1 | 0 |
| `BACKSTAGE_LABEL_NONE` | 6 | 1 | 0 |

The six required access cases, and what was measured:

| Case | Evidence |
|---|---|
| Allowed access | `LIMITED` reads label 5 revenue; `NONE` reads nothing |
| Another label's data denied | `LIMITED` sees 0 rows for label 1; `BROAD` sees rows |
| No access | `NONE` sees 0 revenue rows and 0 stream rows with identical object grants to the other personas, so the emptiness comes from entitlements, not a missing GRANT |
| Permission withheld on a label the user can otherwise see | `LIMITED` sees 1,251 revenue rows for label 23 and **0** stream rows for the same label, because it holds `VIEW_LABEL_REVENUE` but not `VIEW_LABEL_STREAMS` on it |
| Protected lookups | `BROAD` 75 labels / 600 tracks; `LIMITED` 3 labels / 24 tracks; `NONE` 0 / 0 |
| Cross-persona isolation of the shared semantic view | `BROAD` $63,944,186.85 Amazon revenue; `LIMITED` a strict subset; `NONE` NULL — same semantic view object, three different answers |

Two additional assertions beyond the required six:

| Case | Evidence |
|---|---|
| A persona cannot read its own authorization | `SELECT` on `ENTITLEMENT` raises insufficient privileges for all three personas |
| No false zero percent | Under `LIMITED`, the concentration query returns a healthy $1,037,109.85 denominator with 0 target rows and refuses with `UNANSWERABLE`, rather than computing a confident `0.00%` |

There is no admin bypass in the policy. `SYSADMIN` sees all 75 labels because it
holds 150 rows in `ENTITLEMENT`, not because the policy exempts it. This was
demonstrated accidentally and usefully during the build: a deploy step that ended
as `SECURITYADMIN` reported every policy-protected table as empty, because
`SECURITYADMIN` holds no entitlements.

## Agent behavior and measured latency

Seven prompts run via `cortex agents run` against the deployed agent. Latency is
wall-clock for the whole call including tool execution, measured once per prompt
on a single run, on an XSMALL warehouse. These are single observations, not a
benchmark, and not a distribution.

| Prompt | Latency | Correct | Notes |
|---|---|---|---|
| Q1 concentration | 14s | Yes | 9.31%, numerator and denominator both stated, denominator labeled as visible-to-you |
| Q2 label growth | 23s | Yes | Absolute ranking, all 50 genuinely increased, noted that none were new or no-prior |
| Q3 cross-DSP August trend | 39s | Yes | Named the missing dates, identified the 7-day YouTube outage, stated gaps are not zeros |
| Q4 seven complete days | 35s | Yes | 512,267 with a breakdown that sums exactly to it |
| Q5 Apple Music peak | 14s | Yes | Returned both tied dates |
| Ambiguous title only | 28s | Yes | Refused, listed all three candidate recordings with artist and ISRC |
| Cross-grain rate request | 20s | Yes | Refused to divide revenue by streams, explained that the two models are unreconciled, offered both figures separately |

Range 14s to 39s. The two longest both generate a chart.

## Defects found and fixed during verification

These are recorded because each one would have produced a wrong answer on stage,
and three of them looked completely fine until checked against the reference.

| Defect | How it surfaced | Fix |
|---|---|---|
| Verified query used `FACTS` instead of `METRICS`, collapsing the three Amazon service lines per month | Returned 8.39% where the reference said 9.31% | Switched to `METRICS`, plus an `AI_SQL_GENERATION` rule against summing a raw fact requested at a dimension grain |
| Agent read "Neon Orchard" as a label name, never found the three candidate recordings, and refused for the wrong reason | Ambiguity probe | Added `SAMPLE_VALUES` to title, artist and label dimensions, plus an explicit entity-resolution rule ordering track then artist then label |
| Concentration returned a confident `0.00%` for a persona scoped away from the recording | Ran the concentration query under `BACKSTAGE_LABEL_LIMITED` | Added a target-row-count guard. `DIV0NULL` does not catch this, because the denominator is not zero |
| Agent reported 500,268 streams for Q4 where ground truth is 512,267, while its own breakdown was roughly right | Compared against the reference | Added a verified query for Q4 and a rule that a headline total must come from the same result as the breakdown and equal the sum of its parts |
| Access tests 6 and 7 never ran; the suite still reported success | Assertion counts were lower than the number of tests | Moved the deliberately failing privilege test to the end of the file, since a failing statement aborts everything after it |
| Two access assertions used wrong thresholds | Fired once tests 6 and 7 actually executed | Pinned the expected total to the exact deterministic value instead of a guessed threshold |
| Deploy manifest reported all policy-protected tables as empty | Row count manifest | `06_grants.sql` ended as `SECURITYADMIN`; restored `SYSADMIN` and pinned the role before the manifest |
| `ENTITLEMENT` rebuild read `DIM_LABEL`, which carries the lookup policy, so a redeploy would have locked every principal out | Reasoned through the redeploy path, then confirmed | Generate the label list instead of reading the policy-protected dimension |

## Not verified

State these plainly rather than implying coverage that does not exist.

- **CoWork honoring a role switch.** Every enforcement result above was measured
  through `snow sql` and `cortex agents run` with the role pinned explicitly.
  `cortex agents run` has no `--role` flag, so the agent was not exercised under a
  persona role from the CLI. Whether CoWork scopes to the role selected in
  Snowsight must be confirmed in the room before presenting the limited-access
  persona. `docs/RUNBOOK.md` carries the pre-flight step and the fallback.
- **Concurrent multi-user thread and cache isolation.** Not tested. Single-session
  only.
- **Latency under concurrency.** Single sequential caller on an XSMALL warehouse.
- **Agent accuracy across phrasings.** Each prompt was run in the exact wording
  recorded in the runbook. Verified queries raise the floor; they do not guarantee
  that a reworded question routes the same way.
