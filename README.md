# Customer 360 for Insurance — Snowflake Cortex Hackathon Project

An AI-powered Customer 360 application for an insurance carrier, built entirely on Snowflake Cortex.

**🔗 Live app:** https://app.snowflake.com/UPCVNWX/mq84114/#/streamlit-apps/INSURANCE_360.AI.CUSTOMER_360_APP
> Requires a Snowflake login scoped to account `UPCVNWX-MQ84114`. If you're judging this and don't have access, see [Judge Access](#judge-access) below — we're happy to set you up, do a live walkthrough, or share a recording.

---

## The Problem

Insurance carriers sit on siloed data — policies, claims, payments, and call transcripts — with no unified view of a customer. Retention teams react to churn *after* it happens instead of catching it early, and there's no fast way to ask "what should we do about this customer?" and get a grounded, actionable answer.

## What We Built

- **📊 Portfolio Dashboard** — KPIs (total customers, revenue, avg premium, % at churn risk), churn-risk breakdowns by segment/state, and a ranked "Customers Needing Attention" list, prioritized by a computed risk/revenue score.
- **👤 Customer 360 View** — a single customer's full profile: policies, claims, payment history, sentiment/churn signals pulled from call transcripts, and a precomputed **AI Next-Best-Action** with a grounded rationale.
- **💬 AI Chat** — a Cortex Agent that answers natural-language questions by combining structured data (Cortex Analyst over a Semantic View) with unstructured call-transcript search (Cortex Search), then synthesizes a recommendation — not just a lookup.
- **🎯 Demo Mode** — one-click jump to curated customers for a fast, guided walkthrough.

## Why This Isn't "Just Another Synthetic Demo"

There's no public, PII-free, granular insurance dataset to build on, so customer records are synthetically generated. But rather than pulling numbers from arbitrary random ranges, **every dollar figure is statistically anchored to a real, published industry source**:

| Line of business | Grounded in |
|---|---|
| Auto premiums | Real 2021 NAIC average auto expenditure by state |
| Home premiums | Real 2021 NAIC average homeowners premium by state |
| Auto claims | Real ISO/Verisk claim frequency & severity by coverage type |
| Home claims | Real ISO/Verisk claim frequency & severity by cause of loss |
| Health premiums/claims | Bootstrap-sampled from a real, individual-level 1,338-record health-cost dataset, age-matched to each customer |

The result: portfolio-level statistics (average premium, claim frequency, loss ratios) track real national/state benchmarks, even though individual customer records are synthetic. That's a meaningfully more credible foundation than flat random-number generation.

---

## Architecture at a Glance

```
                     Streamlit App (Snowpark Container Services)
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
        Cortex Agent          Semantic View           Dynamic Tables
   (orchestrates tools)   (Cortex Analyst text-to-SQL)   (auto-refreshing,
        │        │                                        AI-enriched)
        │        └─ Cortex Search (call transcripts)
        └─ Cortex Analyst (structured policy/claims data)

              Raw Data (customers, policies, claims, payments,
                 call transcripts + real NAIC/ISO/health benchmarks)
```

**Tech stack:** Snowflake Dynamic Tables (incremental AI refresh) · Cortex `AI_SENTIMENT` / `AI_CLASSIFY` / `AI_COMPLETE` · Cortex Semantic View + Cortex Analyst · Cortex Search · Cortex Agent · Streamlit-in-Snowflake on SPCS

A full technical breakdown (object inventory, setup steps, deployment notes) is in the [Developer Guide](docs/DEVELOPER_GUIDE.md).

---

## Status

- ✅ Fully deployed and live in Snowflake
- ✅ Data pipeline, dynamic tables, semantic view, agent, and Streamlit app all working end-to-end
- ✅ Real-data grounding completed across all lines of business
- ⏳ In progress: judge-facing demo video, expanded feature set

---

## Judge Access

The live app link only works with a login scoped to our Snowflake account. If you're evaluating this project and don't have one, pick whichever works best for you:

1. **Get a login** — tell us and we'll provision a read-only account for you in a couple minutes.
2. **Live walkthrough** — we can screen-share and demo it directly.
3. **Recorded demo** — a short video walking through Portfolio → Customer 360 → AI Chat (coming soon).

---

## Team

Built for the Snowflake Cortex Hackathon. See [Developer Guide](docs/DEVELOPER_GUIDE.md) for setup instructions, architecture details, and how to extend the data pipeline.
