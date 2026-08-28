# Developer Guide

Technical reference for contributors: repo layout, setup from scratch, deployment gotchas, cost notes, and how to extend the data pipeline. For the project overview and demo, see the main [README](../README.md).

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

Both dynamic tables use `REFRESH_MODE = INCREMENTAL`, so `AI_COMPLETE` / `AI_SENTIMENT` / `AI_CLASSIFY` only re-run on **new or changed rows**, not the whole table on every refresh — this keeps AI Functions cost bounded as data grows.

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

---

## Deployment Gotchas

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

## Granting Access to New Users

Streamlit-in-Snowflake apps run with the viewer's own privileges (caller's rights), so any new user needs a role with the right grants. The `HACKATHON_TEAM` role already covers this:

```sql
GRANT ROLE HACKATHON_TEAM TO USER <new_user>;
```

`HACKATHON_TEAM` has `USAGE`/`SELECT` on the database, warehouse, semantic view, Cortex Search service, Cortex Agent, and the Streamlit app itself — read-only, no write access to pipeline objects.
