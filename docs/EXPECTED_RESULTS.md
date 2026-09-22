# Expected Results

Independently computed by `tests/01_reference_queries.sql`, hand-written against
the base tables. These values are **only** valid for `RELEASE_ID`
`backstage-v1-seed-8831` with `DEMO_AS_OF = 2026-09-22`, run under a role with
broad entitlement.

All data is synthetic. All labels, artists, and tracks are fictional.

Captured 2026-09-22.

## Dataset shape

| Object | Rows |
|---|---|
| `DIM_LABEL` | 75 |
| `DIM_TRACK` | 600 (41 with `IS_DAILY_TRACKED`) |
| `DIM_DSP_SERVICE` | 7 raw services, 4 families |
| `DIM_STATEMENT_MONTH` | 32 (2024-01 through 2026-08; 2026-08 unreleased) |
| `DIM_ACTIVITY_DAY` | 995 (2024-01-01 through 2026-09-21; last 6 incomplete) |
| `FACT_ROYALTY_MONTH` | 93,403 |
| `FACT_STREAM_DAY` | 213,661 |

## Q0 — Ambiguity, which must be resolved before Q1, Q3, Q4, or Q5

`Neon Orchard` is three different recordings:

| Track key | Artist | ISRC | Label |
|---|---|---|---|
| 1 | Marisol Vane | `QZSYN2400001` | Cypress Grove Records |
| 301 | Dez Nkemdi | `QZSYN2400301` | Fernhollow Music |
| 513 | Lorne Delacroix | `QZSYN2500513` | Inkwell Records |

A question that names only the title is underspecified. The correct behavior is to
ask which recording, or to state which one was assumed. Every expected value below
uses **`QZSYN2400001`**, the Marisol Vane recording on Cypress Grove Records.

## Q1 — Revenue concentration

"What percentage of our 2025 Amazon revenue came from `Neon Orchard`?"

| Field | Value |
|---|---|
| Target recording rows visible | 18 |
| Track revenue (2025, Amazon family) | **$2,664,931.35** |
| Amazon revenue visible to the caller (2025) | **$28,609,484.50** |
| Share | **9.31%** |
| Verdict | `ANSWERABLE` |
| Statement lines in scope | 18,593 |

Scope applied identically to both sides: calendar 2025, `DSP_FAMILY = 'Amazon'`
(all three Amazon services), `IS_RELEASED = TRUE`, `LABEL_NET_USD` basis, USD, and
the caller's entitlement.

### Three ways to get this wrong, all of which return a plausible number

- **Filtering on a single Amazon service** instead of the family. Undercounts the
  denominator and inflates the share.
- **Labeling the denominator "all Amazon revenue"** rather than "Amazon revenue
  visible to you." For a scoped user those differ.
- **Reporting 0.00% when the recording is not visible.** This is the worst of the
  three, because nothing looks broken. Under `BACKSTAGE_LABEL_LIMITED` the
  denominator is a healthy **$1,037,109.85** and the numerator sums to **$0.00**,
  so the arithmetic yields a confident `0.00%`. That is a false statement: it
  asserts the recording earned nothing on Amazon in 2025, when the truth is the
  caller is not entitled to see it. `DIV0NULL` does not catch this, because the
  denominator is not zero. The fix is to count the target recording's contributing
  rows and refuse when that count is zero.

Expected under each persona:

| Persona | Target rows visible | Denominator | Correct answer |
|---|---|---|---|
| `BACKSTAGE_LABEL_BROAD` | 18 | $28,609,484.50 | 9.31% |
| `BACKSTAGE_LABEL_LIMITED` | 0 | $1,037,109.85 | `UNANSWERABLE` — not visible to you |
| `BACKSTAGE_LABEL_NONE` | 0 | NULL | `UNANSWERABLE` — nothing visible at all |

## Q2 — Labels by month-over-month revenue increase

Periods are the two newest **released** months: **2026-07** against **2026-06**.
2026-08 exists in the data with `IS_RELEASED = FALSE` and is excluded.

| Field | Value |
|---|---|
| Labels with current-month revenue | 75 |
| Labels that increased | **69** |
| Labels that declined or were flat | 6 |
| Labels with no prior period | 0 |

Because 69 labels grew, a top-50 list can be filled honestly. It must **not** be
padded with decliners to reach 50.

Top ten by absolute increase:

| Rank | Label | Prior (USD) | Current (USD) | Absolute change | Percent |
|---|---|---|---|---|---|
| 1 | Foxglove Audio | 268,867.40 | 280,694.86 | **11,827.46** | 4.4% |
| 2 | Ironwood Audio | 318,995.39 | 328,493.96 | 9,498.57 | 3.0% |
| 3 | Larkspur Sound | 387,035.23 | 394,697.44 | 7,662.21 | 2.0% |
| 4 | Rookery Sound | 202,531.20 | 210,012.99 | 7,481.79 | 3.7% |
| 5 | Kingfisher Audio | 197,469.57 | 204,902.30 | 7,432.73 | 3.8% |
| 6 | Fallowmere Sound | 522,078.86 | 529,472.98 | 7,394.12 | 1.4% |
| 7 | Glasswing Records | 184,158.30 | 191,448.18 | 7,289.88 | 4.0% |
| 8 | Underhill Records | 315,340.79 | 322,210.92 | 6,870.13 | 2.2% |
| 9 | Slate Harbor Music | 158,404.49 | 164,074.64 | 5,670.15 | 3.6% |
| 10 | Wren & Wilder | 193,460.97 | 199,020.20 | 5,559.23 | 2.9% |

Absolute and percentage rankings genuinely disagree here, which is the whole reason
the question specifies absolute:

- Foxglove Audio and Brambleway Sound both grew **4.4%**. Foxglove ranks 1st with
  +$11,827.46 on a $268,867.40 base; Brambleway ranks 21st with +$3,141.53 on a
  $71,124.10 base. Identical percentage, four times the absolute impact.
- Cypress Grove Records is the largest label at **$960,854.63** prior-month revenue
  but grew only **0.2%**, adding $2,121.57 and ranking 27th. A percentage ranking
  would bury the group's biggest label near the bottom; an absolute ranking places
  it mid-list, which is the truthful picture of its contribution.

The `NO PRIOR PERIOD` and `NEW` cases do not occur in this window — every label was
already earning in 2026-06. The guards are still correct and are exercised
separately: comparing **2024-04 against 2024-03** yields 5 labels with no prior
period, because their first tracks had not been released yet.

## Q3 — August 2026 streams by DSP family

Track `QZSYN2400001`, 2026-08-01 through 2026-08-31. August has 31 calendar days.

| DSP family | Days observed | Days missing | Streams |
|---|---|---|---|
| Spotify | 28 | 3 | 785,354 |
| Amazon | 31 | 0 | 510,320 |
| YouTube | **24** | **7** | 415,874 |
| Apple Music | 30 | 1 | 374,808 |

YouTube's 7 missing days are a contiguous delivery outage, **2026-08-05 through
2026-08-11**. Spotify's and Apple Music's are scattered single-day misses.

A chart of this must break where the data breaks. Zero-filling the YouTube outage
would show a collapse to zero and recovery, which is a false event. Interpolating
across it would hide a real data-quality problem. The correct rendering is a gap,
with the coverage table alongside it.

## Q4 — Latest seven complete days

| Field | Value |
|---|---|
| Window | **2026-09-09 through 2026-09-15** |
| Days in window | 7 |
| Total streams (`QZSYN2400001`, all families) | **512,267** |

The window is anchored to `IS_COMPLETE`, not to the newest row present. Rows exist
through 2026-09-21, but 2026-09-16 through 2026-09-21 are still landing and are
excluded. An answer that silently used the six incomplete days would understate
recent activity and look like a decline.

## Q5 — Highest single Apple Music streaming day

There is a **two-way tie**:

| Recording | ISRC | Date | Streams |
|---|---|---|---|
| Neon Orchard / Marisol Vane | `QZSYN2400001` | 2025-06-14 | **98,750** |
| Neon Orchard / Marisol Vane | `QZSYN2400001` | 2026-02-21 | **98,750** |

Both dates must be returned. `RANK` returns ties; `ROW_NUMBER` would silently pick
one and present an arbitrary choice as the answer.

Available Apple Music history:

| Field | Value |
|---|---|
| History start | 2024-01-01 |
| History end | 2026-09-15 (latest complete day) |
| Complete days observed | 988 |

The claim is "highest in available history," bounded by the coverage above. It is
not "highest ever," because the dataset does not begin at the start of the
catalog's life.

## Reconciliation note

`FACT_ROYALTY_MONTH` and `FACT_STREAM_DAY` are generated independently and are
deliberately **not** reconciled. Streams multiplied by any per-stream rate will not
equal revenue. That is the intended behavior: they represent two different source
systems with different periods, different coverage, and deductions applied to
revenue. It is also why the two grains must never be joined.

If someone in the room asks why the numbers do not tie, that is the answer, and it
is the same answer a real label back office would give.
