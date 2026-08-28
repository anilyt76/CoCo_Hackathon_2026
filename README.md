# Customer 360 for Insurance — Snowflake Cortex Hackathon Project

An AI-powered Customer 360 application for an insurance carrier, built entirely on Snowflake: Cortex AI functions for unstructured/structured enrichment, a Semantic View + Cortex Agent for natural-language Q&A, Dynamic Tables for always-fresh derived metrics, and a Streamlit-in-Snowflake (SiS) frontend running on Snowpark Container Services (SPCS).

**Live app:** https://app.snowflake.com/UPCVNWX/mq84114/#/streamlit-apps/INSURANCE_360.AI.CUSTOMER_360_APP
> Requires a login to the Snowflake account `UPCVNWX-MQ84114`. See "Sharing with judges / non-account users" below if you don't have access.

---

## The Problem

Insurance carriers sit on siloed data — policies, claims, payments, and call transcripts — with no unified view of a customer. Retention teams react to churn after it happens instead of catching it early, and there's no fast way to ask "what should we do about this customer?" and get a grounded answer.

## What It Does

- **Portfolio Dashboard** — KPIs (total customers, revenue, avg premium, % at churn risk), churn-risk breakdown, segment/state cuts, and a ranked "Customers Needing Attention" list driven by a computed priority score.
- **Customer 360 View** — a single customer's full profile: policies, claims, payment history, sentiment/churn signals from call transcripts, and a precomputed AI **Next Best Action** with rationale.
- **AI Chat** — a Cortex Agent that answers natural-language questions by combining structured data (via Cortex Analyst / Semantic View) and unstructured call-transcript search (via Cortex Search), then synthesizes a recommended action.
- **Demo Mode** — one-click jump to curated demo customers for a live walkthrough.

---

## Why It's Not "Just Another Synthetic Demo"

There's no public, granular, PII-free insurance policy/claims dataset, so the underlying customer records are synthetically generated. But every **dollar figure** is statistically anchored to a real, published source instead of an arbitrary random range:

| Line of business | Grounded in |
|---|---|
| Auto premium | Real 2021 NAIC average auto expenditure by state (via Insurance Information Institute Facts+Statistics) |
| Home premium | Real 2021 NAIC average homeowners premium by state |
| Auto claims | Real ISO/Verisk claim frequency & severity by coverage type |
| Home claims | Real ISO/Verisk claim frequency & severity by cause of loss |
| Health premium/claims | Bootstrap-sampled from the real, individual-level "Medical Cost Personal Dataset" (1,338 records: age/sex/bmi/children/smoker/region → charges), age-matched to each synthetic customer |
| Life premium/claims | Illustrative age-scaled mortality-curve approximation (not tied to a specific published table — flagged as illustrative) |

This means portfolio-level statistics (avg premium, claim frequency, loss ratios) track real national/state benchmarks even though individual customer records are synthetic.

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │        Streamlit app (SPCS/SiS)          │
                        │  streamlit/streamlit_app.py               │
                        └───────────────┬───────────────────────────┘
                                         │
                 ┌───────────────────────┼────────────────────────┐
                 │                       │                        │
         Cortex Agent            Semantic View            Dynamic Tables
   INSURANCE_360.AI.        INSURANCE_360.AI.         INSURANCE_360.CURATED.*
   CUSTOMER_360_AGENT       CUSTOMER_360_MODEL
       │        │
       │        └── CustomerDataTool (Cortex Analyst text-to-SQL over semantic view)
       └── InteractionSearchTool (Cortex Search over call transcripts)

RAW layer (source-of-truth tables)          CURATED layer (derived, AI-enriched)
────────────────────────────────           ─────────────────────────────────────
CUSTOMERS            (800 rows)             INTERACTIONS_ENRICHED   (dynamic table,
POLICIES              (~1.6K)                 AI_SENTIMENT + AI_CLASSIFY x2,
CLAIMS                 (~440)                  target_lag = 15 min)
PAYMENTS              (~19K)               CUSTOMER_METRICS_SUMMARY (dynamic table,
INTERACTIONS          (2,175 call transcripts)  rollups + AI_COMPLETE Next Best Action,
INTERACTIONS_SEED     (2,165 scenario seeds)     target_lag = 30 min)
REF_STATE_AUTO_PREMIUM         (51 rows, real NAIC data)
REF_STATE_HOME_PREMIUM         (51 rows, real NAIC data)
REF_AUTO_CLAIM_BENCHMARKS       (4 rows,  real ISO/Verisk data)
REF_HOME_CLAIM_BENCHMARKS       (5 rows,  real ISO/Verisk data)
REF_HEALTH_COST_SAMPLE      (1,338 rows, real "Medical Cost Personal Dataset")
```

Both dynamic tables use `REFRESH_MODE = INCREMENTAL`, so `AI_COMPLETE` / `AI_SENTIMENT` / `AI_CLASSIFY` only re-run on **new or changed rows**, not the whole table on every refresh — this keeps AI Functions cost bounded as data grows.

---

## Snowflake Objects

| Object | Type | Purpose |
|---|---|---|
| `INSURANCE_360.RAW.*` | Tables | Source-of-truth structured + reference data |
| `INSURANCE_360.CURATED.INTERACTIONS_ENRICHED` | Dynamic Table (15 min lag) | Sentiment, churn-risk classification, intent classification per call transcript, via `AI_SENTIMENT` + `AI_CLASSIFY` |
| `INSURANCE_360.CURATED.CUSTOMER_METRICS_SUMMARY` | Dynamic Table (30 min lag) | Per-customer rollups (premium, claims, missed payments), `REVENUE_AT_RISK`, `PRIORITY_SCORE`, and a precomputed `NEXT_BEST_ACTION` + rationale via `AI_COMPLETE` |
| `INSURANCE_360.AI.INTERACTIONS_SEARCH` | Cortex Search Service | Semantic search over call transcripts |
| `INSURANCE_360.AI.CUSTOMER_360_MODEL` | Semantic View | Business-friendly model over CUSTOMERS/POLICIES/CLAIMS for Cortex Analyst text-to-SQL |
| `INSURANCE_360.AI.CUSTOMER_360_AGENT` | Cortex Agent | Orchestrates `CustomerDataTool` (Cortex Analyst) + `InteractionSearchTool` (Cortex Search) into a single conversational assistant |
| `INSURANCE_360.AI.CUSTOMER_360_APP` | Streamlit (SPCS runtime) | The frontend |

---

## Tech Stack

- **Data layer:** Raw + curated schemas in Snowflake; Dynamic Tables with `REFRESH_MODE=INCREMENTAL`
- **AI enrichment:** `AI_SENTIMENT` + `AI_CLASSIFY` on call transcripts (churn risk, intent), `AI_COMPLETE` for Next-Best-Action generation
- **Semantic layer:** Cortex Semantic View + Cortex Analyst (text-to-SQL)
- **Search:** Cortex Search over call transcripts
- **Orchestration:** Cortex Agent combining structured + unstructured tools into one conversational assistant
- **Frontend:** Streamlit-in-Snowflake (Altair for charts — Plotly requires an External Access Integration that trial accounts can't provision), deployed on Snowpark Container Services (SPCS)

---

## Repo Layout

```
sql/
  01_setup.sql                    Database/schema/warehouse setup
  02_synthetic_structured_data.sql  Original flat-random data generator (superseded by 04)
  03_ground_in_real_data.sql      Loads real NAIC/ISO/health-cost reference tables
  04_regenerate_realistic.sql     Regenerates CUSTOMERS/POLICIES/CLAIMS/PAYMENTS anchored
                                   to the reference data in 03
  05_curated_insights.sql         Creates CUSTOMER_METRICS_SUMMARY dynamic table (NBA, priority score)
  data/health_insurance_costs.csv Real health-cost reference dataset (loaded via PUT + COPY INTO)
cortex_project/
  cortex-project.yaml              Cortex project config
  CUSTOMER_360_MODEL.sv.yaml       Semantic view YAML (source of truth; reflect + deploy from here)
streamlit/
  streamlit_app.py                 Main Streamlit application
  snowflake.yml                    SiS/SPCS deployment config
  pyproject.toml                   Pins streamlit>=1.50.0 (required by SPCS container runtime)
```

> Note: `INTERACTIONS` / `INTERACTIONS_SEED` (call-transcript source data), the `INTERACTIONS_ENRICHED` dynamic table, the Cortex Search service, and the Cortex Agent were created directly in Snowflake during the build and are **not yet captured as local SQL files**. See "Bringing In More Data" below for what's needed to reproduce them from scratch.

---

## Setup From Scratch

```bash
# 1. Connection
cortex connections set Hackathon

# 2. Schema, warehouse
snow sql -f sql/01_setup.sql -c Hackathon

# 3. Load real reference data (upload CSV first)
snow sql -q "PUT file://sql/data/health_insurance_costs.csv @INSURANCE_360.RAW.REF_DATA_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE" -c Hackathon
snow sql -f sql/03_ground_in_real_data.sql -c Hackathon

# 4. Generate customers/policies/claims/payments grounded in real benchmarks
snow sql -f sql/04_regenerate_realistic.sql -c Hackathon

# 5. Build curated dynamic table (NBA, priority score, revenue at risk)
snow sql -f sql/05_curated_insights.sql -c Hackathon

# 6. Deploy/validate the semantic view
cortex reflect cortex_project/CUSTOMER_360_MODEL.sv.yaml --target-schema INSURANCE_360.AI

# 7. Deploy the Streamlit app
cd streamlit
snow streamlit deploy --connection Hackathon --replace --prune
# then commit + force a fresh container (see "Deployment Gotchas" below)
```

You'll also need to separately create (not yet scripted):
- `RAW.INTERACTIONS` / `RAW.INTERACTIONS_SEED` (call transcript source data)
- `CURATED.INTERACTIONS_ENRICHED` dynamic table (sentiment/churn/intent via `AI_SENTIMENT`/`AI_CLASSIFY`)
- `AI.INTERACTIONS_SEARCH` Cortex Search service
- `AI.CUSTOMER_360_AGENT` Cortex Agent

### Deployment Gotchas

- **Trial accounts can't create an External Access Integration**, so PyPI packages beyond the Snowflake Anaconda channel (e.g. Plotly) aren't installable. This app uses **Altair** for charts instead, and attaches `snowflake.snowpark.pypi_shared_repository` as the artifact repository so `pyproject.toml`'s `streamlit>=1.50.0` constraint can resolve without EAI:
  ```sql
  ALTER STREAMLIT INSURANCE_360.AI.CUSTOMER_360_APP
    SET ARTIFACT_REPOSITORY = 'snowflake.snowpark.pypi_shared_repository';
  ```
- **`snow streamlit deploy` alone does not refresh the live app.** The SPCS container caches old code. Reliable update sequence:
  ```bash
  snow streamlit deploy --connection Hackathon --replace --prune
  # SQL: ALTER STREAMLIT INSURANCE_360.AI.CUSTOMER_360_APP COMMIT
  # SQL: ALTER COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU SUSPEND   -- forces a fresh container on next load
  ```
- **Widget state mutation**: Streamlit forbids writing to a widget's `session_state` key after that widget has run in the current script pass. Use a "pending key" pattern — write to a non-widget key (e.g. `_pending_customer`), `st.rerun()`, then apply it to the real widget key at the top of the script before the widget is instantiated.

---

## Bringing In More Data

If you want to extend this beyond the current 800 synthetic customers (e.g. more lines of business, more real benchmark sources, or a genuinely larger book of business), here's what needs to be touched, in order:

1. **Add/refresh reference data** (`sql/03_ground_in_real_data.sql`)
   - New real benchmark table → `CREATE TABLE RAW.REF_<NAME>` + `INSERT`/`COPY INTO`
   - CSV sources go through the `REF_DATA_STAGE` stage: `PUT file://<path> @REF_DATA_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE`

2. **Regenerate structured data** (`sql/04_regenerate_realistic.sql`)
   - `CUSTOMERS` — increase `GENERATOR(ROWCOUNT => N)` to grow the customer base
   - `POLICIES` — add a new `LINE_OF_BUSINESS` branch in the `CASE` pricing logic, join in any new reference table
   - `CLAIMS` — add a matching claim-generation CTE (frequency/severity anchored to the new reference table), `UNION ALL` it into `unioned`
   - `PAYMENTS` — no changes usually needed; it derives from `POLICIES`

3. **Rebuild curated dynamic tables** (`sql/05_curated_insights.sql`)
   - `CREATE OR REPLACE DYNAMIC TABLE` picks up new base-table columns automatically as long as the `SELECT` in `base`/`scored` references them
   - If you add a wholly new metric, add it to the `scored` CTE and the final `SELECT`

4. **Update the semantic view** (`cortex_project/CUSTOMER_360_MODEL.sv.yaml`)
   - Add new dimensions/facts/metrics for any new columns so Cortex Analyst can answer questions about them
   - Validate with `cortex reflect cortex_project/CUSTOMER_360_MODEL.sv.yaml --target-schema INSURANCE_360.AI` before deploying

5. **Update the agent** (if new question types are needed)
   - `CUSTOMER_360_AGENT`'s `sample_questions` and `instructions` may need updating to reflect new capabilities
   - No changes needed if you're only adding data, not new question categories

6. **Update the Streamlit app** (`streamlit/streamlit_app.py`)
   - Add UI for any new KPIs/breakdowns (e.g. a new line-of-business filter)
   - Redeploy using the sequence in "Deployment Gotchas" above

7. **For call-transcript / unstructured data growth**
   - Insert new rows into `RAW.INTERACTIONS` — `INTERACTIONS_ENRICHED` (dynamic table, 15 min lag) will incrementally pick them up and run `AI_SENTIMENT`/`AI_CLASSIFY` automatically
   - Re-sync the Cortex Search service if its refresh isn't automatic for your configuration

**Cost consideration:** because both dynamic tables are `REFRESH_MODE = INCREMENTAL`, AI Function cost scales with *new* rows added, not the full table size — bringing in more data is safe to do incrementally without re-processing everything.

---

## Cost Notes

- All warehouses (`COMPUTE_WH`, `INSURANCE_360_WH`, `INSURANCE_360_BATCH_WH`, etc.) have `AUTO_SUSPEND` set (60–300s) — no manual suspension needed, they stop billing once idle.
- `SYSTEM_COMPUTE_POOL_CPU` (hosts the Streamlit app's SPCS container) auto-suspends after 300s idle. Suspend it manually if you want to stop billing immediately after a demo:
  ```sql
  ALTER COMPUTE POOL SYSTEM_COMPUTE_POOL_CPU SUSPEND;
  ```
- Biggest cost driver so far: **Cortex AI Functions** (`AI_COMPLETE`/`AI_SENTIMENT`/`AI_CLASSIFY` in the two dynamic tables), bounded by incremental refresh so cost scales with *new* data, not total data volume.

---

## Sharing With Judges / Non-Account Users

The Snowsight link only works for users with a login to account `UPCVNWX-MQ84114`. Streamlit-in-Snowflake apps aren't publicly shareable links — access requires a real login scoped to that account. Options if judges don't already have one:

1. **Create judges as users** in the account (a dedicated read-only role, e.g. the `HACKATHON_TEAM` role used for teammates, scoped to `USAGE`/`SELECT` on the app and underlying objects — no write access).
2. **Live demo / screen share** during judging — no account access needed on their end.
3. **Record a short demo video** walking through Portfolio → Customer 360 → AI Chat, and link it alongside this repo.

This README is meant to stand on its own for anyone who can't log in — it documents the architecture, real-data grounding, and design decisions even without live access.
