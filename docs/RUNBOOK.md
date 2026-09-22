# Presenter Runbook

Everything needed to run this demo without having built it. Read the Pre-flight
section before you are in the room.

All data is synthetic. Every label, artist, and recording is fictional.

## Pre-flight, 10 minutes before

1. **Confirm the demo is deployed.** In a Snowsight worksheet:

   ```sql
   USE ROLE SYSADMIN;
   USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;
   SELECT COUNT(*) FROM SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.FACT_ROYALTY_MONTH;
   ```

   Expect **93,403**. If it is 0, your role holds no entitlements — check you are
   on `SYSADMIN` and not `SECURITYADMIN`. If the object does not exist, redeploy:
   paste `deploy_all.sql` and Run All, about 45 seconds.

2. **Confirm the agent is in CoWork.** AI & ML, then Agents, then
   `BACKSTAGE_ANALYTICS_AGENT`, then Add to CoWork. Ask the first question once to
   warm the warehouse. A cold XSMALL adds a few seconds to the first call.

3. **Verify the role switch, which is the one thing that can break the governance
   segment.** In Snowsight, switch your role to `BACKSTAGE_LABEL_LIMITED` and ask
   CoWork the concentration question. You should get a refusal, not 9.31%.

   If you get 9.31% under the limited role, CoWork is not honoring the role
   switch. Do not improvise. Use the worksheet fallback in the Governance segment
   below and say plainly that you are showing it in a worksheet.

## The 9-minute walkthrough

Copy the prompts exactly. These are the wordings that were rehearsed and
measured. Expected values are in `docs/EXPECTED_RESULTS.md`.

### 1. Concentration — 90 seconds

> What percentage of our 2025 Amazon revenue came from the recording QZSYN2400001?

Expect **9.31%**, numerator **$2,664,931.35**, denominator **$28,609,484.50**.
About 15 seconds.

What to point at: it returns all three numbers, not just the percentage. And it
calls the denominator "Amazon revenue visible to you," not a company total. That
wording is doing real work — for a scoped user those are different numbers.

Worth mentioning: Amazon is three separate services in the feed. The answer rolls
them up. Filtering on one service would undercount the denominator and inflate the
share, and nothing on screen would look wrong.

### 2. Label growth — 2 minutes

> Which 50 labels had the largest month-over-month revenue increases?

Expect **Foxglove Audio** first at **+$11,827.46 (4.4%)**, then Ironwood Audio
+$9,498.57, then Larkspur Sound +$7,662.21. About 25 seconds, and it draws a
chart.

What to point at: ranked by **absolute** change, and it shows prior, current,
absolute, and percentage side by side. Foxglove and Brambleway Sound both grew
4.4%; Foxglove is first and Brambleway is 21st, because 4.4% of $268K is not 4.4%
of $71K. A percentage ranking would have put a rounding error at the top of a
partner-prioritisation list.

If someone asks about the biggest label: Cypress Grove Records is the largest at
about $961K a month and grew 0.2%, ranking 27th. That is the honest picture.

### 3. Cross-DSP daily trend — 2 minutes

> Show August 2026 streams for the recording QZSYN2400001 on Spotify, Apple Music, YouTube and Amazon

Expect Spotify 785,354 (28 of 31 days), Amazon 510,320 (31 of 31), YouTube 415,874
(**24 of 31**), Apple Music 374,808 (30 of 31). About 40 seconds with a chart.

What to point at — this is the strongest moment in the demo. YouTube is missing
**2026-08-05 through 2026-08-11**, seven consecutive days. The chart shows a break
in the line, and the agent says the gaps are missing deliveries, not zeros.

Say why that matters: zero-filling would show a collapse to zero and a recovery,
which is a false event. Interpolating would hide a real delivery failure. Either
one produces a chart someone would act on. The gap plus the coverage count is the
only honest rendering.

### 4. Follow-up in the same conversation — 1 minute

Stay in the thread and ask:

> Which of those platforms had the weakest coverage, and does that explain the ranking?

Point at what carries over: same recording, same month, same definitions, and it
connects YouTube's lower total to its missing days rather than treating it as lower
demand.

### 5. Governance — 2 minutes, the part people remember

Switch your Snowsight role to `BACKSTAGE_LABEL_LIMITED` and ask the **same**
concentration question from step 1.

Expect a refusal. The denominator is a healthy **$1,037,109.85** for the three
labels this persona can see, and the recording contributes **zero rows**, so the
answer is "not visible to you," **not 0.00%**.

Make the point explicitly: the arithmetic would happily produce 0.00% there. That
number is a lie — it says the recording earned nothing when the truth is this user
cannot see it. Nothing would have looked broken.

Then say where the control lives. Not in the prompt, and not in the agent. A row
access policy on the tables, resolving the person asking against an entitlement
table of principal plus permission plus allowed label. The agent sits above it and
cannot widen it. Same semantic view, same question, different answer.

If asked whether an admin can bypass it: no. `SYSADMIN` sees all 75 labels because
it holds entitlement rows, not because the policy exempts it.

**Fallback if CoWork does not honor the role switch.** Run this in a worksheet and
say you are showing it in a worksheet:

```sql
USE ROLE BACKSTAGE_LABEL_LIMITED;
USE WAREHOUSE SFE_BACKSTAGE_ANALYTICS_WH;

WITH scoped AS (
  SELECT ISRC, LABEL_NET_USD
  FROM SNOWFLAKE_EXAMPLE.BACKSTAGE_ANALYTICS.V_LABEL_REVENUE
  WHERE DSP_FAMILY = 'Amazon' AND IS_RELEASED
    AND STATEMENT_MONTH >= '2025-01-01'::DATE AND STATEMENT_MONTH < '2026-01-01'::DATE
)
SELECT COUNT_IF(ISRC = 'QZSYN2400001') AS target_rows_visible,
       ROUND(SUM(LABEL_NET_USD), 2)    AS denominator_visible,
       CASE WHEN COUNT_IF(ISRC = 'QZSYN2400001') = 0
            THEN 'UNANSWERABLE: recording not visible to you. NOT zero percent.'
            ELSE 'ANSWERABLE' END      AS verdict
FROM scoped;
```

Then `USE ROLE SYSADMIN;` to restore.

### 6. Optional extensions, if time allows

> Give me a snapshot of the latest seven complete days for the recording QZSYN2400001

Expect **512,267** streams over **2026-09-09 through 2026-09-15**. Point out the
window is anchored to complete days: rows exist through 2026-09-21, but those six
days are still landing and would have understated recent activity and looked like a
decline.

> What was our highest streaming day for a song on Apple Music?

Expect **98,750** for Neon Orchard by Marisol Vane on **two** dates, 2025-06-14
and 2026-02-21. Point out it returns both. `ROW_NUMBER` would have picked one and
presented an arbitrary choice as the answer.

## Two questions worth provoking

Both were rehearsed and both behave well.

**Ambiguity.** Ask with the title only:

> What percentage of our 2025 Amazon revenue came from Neon Orchard?

It refuses and lists three recordings with that title, each with a different
artist and ISRC. This is the right behavior: picking one silently would have
produced a confident, wrong, unfalsifiable number.

**Cross-grain.** Ask for something the data cannot support:

> How much revenue did QZSYN2400001 earn per stream in August 2026?

It declines and explains why: revenue is monthly statements, streams are daily
activity, the two are not reconciled, and dividing one by the other manufactures a
rate that exists in neither system. Then it offers both figures separately.

## Likely questions

**"Why don't streams times a rate equal the revenue?"** Because they are two
source systems with different periods, different coverage, and deductions applied
to revenue. A real label back office would give the same answer. It is also why the
two models are kept separate.

**"Could someone talk the agent into showing more?"** No, because the instructions
are not the control. The row access policy is, and it is evaluated on the tables
for whoever is asking. Prompt wording cannot change it.

**"How do we know the numbers are right?"** There is an independent reference query
per question, hand-written against the base tables and authored before the semantic
views existed. `bash tools/run_tests.sh --connection <conn>` checks the agent's
headline values against it. During the build this caught four defects that each
looked entirely plausible — see `docs/TEST_EVIDENCE.md`.

**"Is this connected to Backstage?"** No. CoWork is the chat surface here. The
agent is callable from an application over the Cortex Agent REST endpoint with the
caller's identity determining scope, which is the embed path. No Backstage user
interface was built. `docs/BOUNDARIES.md` has the detail.

**"Is this production-ready?"** No, and the gaps are specific: end-user identity
mapping and revocation, no shared service identity, thread and cache scoping, and
audit. `docs/BOUNDARIES.md` lists all four.

## Recorded-results fallback

**Live mode is the default.** If an agent call fails, say so. Do not read expected
numbers aloud as though the system produced them.

If the account or the agent is unavailable, `docs/EXPECTED_RESULTS.md` holds every
value and can be shown directly — but introduce it as recorded results from a prior
verified run, not as live output. A failed call honestly described costs far less
than a substituted answer that someone later discovers was not live.

## Reset

The demo is stateless; nothing is consumed by presenting it.

```bash
# Full rebuild, about 45 seconds. Deterministic: identical data every time.
snow sql -c <connection> -f teardown_all.sql
snow sql -c <connection> -f deploy_all.sql

# Verify
bash tools/run_tests.sh --connection <connection>
```

If you switched roles in Snowsight, switch back to `SYSADMIN`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Every table looks empty | Your role holds no entitlements. `SECURITYADMIN` and `USERADMIN` hold none. | `USE ROLE SYSADMIN;` |
| Agent errors on a semantic view | Missing `REFERENCES`. `SELECT` alone works for direct queries and fails through an agent, and the error does not say so. | Re-run `sql/06_grants.sql` |
| Agent not listed in CoWork | Not added yet, or the role lacks `USAGE ON AGENT` | Add to CoWork; re-run `sql/06_grants.sql` |
| First question is slow | Cold XSMALL warehouse | Ask one throwaway question during pre-flight |
| Limited persona still sees everything | CoWork is not honoring the role switch | Use the worksheet fallback in the Governance segment and say it is a worksheet |
| Numbers differ from this runbook | Data was rebuilt with a changed `DEMO_AS_OF` or seed | Re-run `tools/run_tests.sh`; if it fails, redeploy from a clean teardown |
| Row count manifest shows `MISMATCH` | Data did not build as expected | Treat every expected value as invalid, teardown and redeploy, and re-run the tests before presenting |

## Known presenter risks

- **CoWork role switching is the single dependency worth checking first.** It was
  not verifiable from the command line, because `cortex agents run` has no role
  flag. Everything else was measured. Pre-flight step 3 exists for this.
- **Agent phrasing.** The prompts above are the exact wordings that were rehearsed.
  Verified queries raise the floor but do not guarantee that a reworded question
  routes identically. If an improvised question misroutes, say so and fall back to
  a rehearsed one.
- **Q4 and Q5 are extensions.** Both verified and both correct, but they were
  scoped as optional. Drop them for time without apology.
- **Multi-user thread and cache isolation is untested.** If asked, say it is
  untested rather than assuming it holds.
