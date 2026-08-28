-- ============================================================
-- Extend CUSTOMER_METRICS_SUMMARY with a precomputed, incrementally
-- refreshed Next Best Action + rationale (via AI_COMPLETE), plus
-- REVENUE_AT_RISK and a PRIORITY_SCORE used to rank customers on
-- the Portfolio dashboard. Precomputing the NBA means the Streamlit
-- app never has to wait on a live agent call to show a recommendation.
-- ============================================================
USE DATABASE INSURANCE_360;
USE SCHEMA CURATED;
USE WAREHOUSE INSURANCE_360_WH;

CREATE OR REPLACE DYNAMIC TABLE CUSTOMER_METRICS_SUMMARY
  LAG = '30 minutes' REFRESH_MODE = 'INCREMENTAL' INITIALIZE = 'ON_CREATE' WAREHOUSE = INSURANCE_360_BATCH_WH AS
WITH policy_agg AS (
  SELECT CUSTOMER_ID,
    SUM(CASE WHEN STATUS = 'Active' THEN ANNUAL_PREMIUM ELSE 0 END) AS TOTAL_ANNUAL_PREMIUM,
    COUNT(CASE WHEN STATUS = 'Active' THEN 1 END) AS ACTIVE_POLICY_COUNT
  FROM INSURANCE_360.RAW.POLICIES
  GROUP BY CUSTOMER_ID
),
claim_agg AS (
  SELECT CUSTOMER_ID,
    COUNT(*) AS CLAIM_COUNT,
    SUM(CLAIM_AMOUNT) AS TOTAL_CLAIM_AMOUNT
  FROM INSURANCE_360.RAW.CLAIMS
  GROUP BY CUSTOMER_ID
),
payment_agg AS (
  SELECT CUSTOMER_ID,
    COUNT(CASE WHEN STATUS = 'Missed' THEN 1 END) AS MISSED_PAYMENT_COUNT
  FROM INSURANCE_360.RAW.PAYMENTS
  GROUP BY CUSTOMER_ID
),
latest_interaction AS (
  SELECT CUSTOMER_ID, CHURN_RISK_LEVEL, SENTIMENT_OVERALL, INTERACTION_DATE,
    ROW_NUMBER() OVER (PARTITION BY CUSTOMER_ID ORDER BY INTERACTION_DATE DESC) AS RN
  FROM INSURANCE_360.CURATED.INTERACTIONS_ENRICHED
),
base AS (
  SELECT
    c.CUSTOMER_ID,
    c.CUSTOMER_SEGMENT,
    COALESCE(p.TOTAL_ANNUAL_PREMIUM, 0) AS TOTAL_ANNUAL_PREMIUM,
    COALESCE(p.ACTIVE_POLICY_COUNT, 0) AS ACTIVE_POLICY_COUNT,
    COALESCE(cl.CLAIM_COUNT, 0) AS CLAIM_COUNT,
    COALESCE(cl.TOTAL_CLAIM_AMOUNT, 0) AS TOTAL_CLAIM_AMOUNT,
    COALESCE(pay.MISSED_PAYMENT_COUNT, 0) AS MISSED_PAYMENT_COUNT,
    li.CHURN_RISK_LEVEL AS LATEST_CHURN_RISK,
    li.SENTIMENT_OVERALL AS LATEST_SENTIMENT,
    li.INTERACTION_DATE AS LAST_INTERACTION_DATE
  FROM INSURANCE_360.RAW.CUSTOMERS c
  LEFT JOIN policy_agg p ON c.CUSTOMER_ID = p.CUSTOMER_ID
  LEFT JOIN claim_agg cl ON c.CUSTOMER_ID = cl.CUSTOMER_ID
  LEFT JOIN payment_agg pay ON c.CUSTOMER_ID = pay.CUSTOMER_ID
  LEFT JOIN latest_interaction li ON c.CUSTOMER_ID = li.CUSTOMER_ID AND li.RN = 1
),
scored AS (
  SELECT *,
    ROUND(
      CASE LATEST_CHURN_RISK
        WHEN 'High Churn Risk' THEN TOTAL_ANNUAL_PREMIUM
        WHEN 'Medium Churn Risk' THEN TOTAL_ANNUAL_PREMIUM * 0.4
        ELSE 0
      END, 2) AS REVENUE_AT_RISK,
    ROUND(
      CASE LATEST_CHURN_RISK WHEN 'High Churn Risk' THEN 50 WHEN 'Medium Churn Risk' THEN 20 ELSE 0 END
      + LEAST(TOTAL_ANNUAL_PREMIUM / 50.0, 40)
      + MISSED_PAYMENT_COUNT * 5
      + LEAST(CLAIM_COUNT * 3, 15)
    , 1) AS PRIORITY_SCORE
  FROM base
),
nba AS (
  SELECT *,
    AI_COMPLETE(
      model => 'llama3.3-70b',
      prompt => 'You are a senior insurance retention and underwriting strategist. Based on this ' ||
        'customer profile, recommend ONE specific next best action a relationship manager should ' ||
        'take this week, and a one-sentence rationale grounded in the profile below.\nProfile: ' ||
        'Segment=' || COALESCE(CUSTOMER_SEGMENT, 'Unknown') ||
        '; Active policies=' || TO_VARCHAR(ACTIVE_POLICY_COUNT) ||
        '; Total annual premium=$' || TO_VARCHAR(ROUND(TOTAL_ANNUAL_PREMIUM, 0)) ||
        '; Claims=' || TO_VARCHAR(CLAIM_COUNT) || ' totaling $' || TO_VARCHAR(ROUND(TOTAL_CLAIM_AMOUNT, 0)) ||
        '; Missed payments (12mo)=' || TO_VARCHAR(MISSED_PAYMENT_COUNT) ||
        '; Latest churn risk=' || COALESCE(LATEST_CHURN_RISK, 'Unknown') ||
        '; Latest sentiment=' || COALESCE(LATEST_SENTIMENT, 'Unknown') || '.',
      response_format => TYPE OBJECT(next_best_action STRING, rationale STRING)
    ) AS NBA_OBJ
  FROM scored
)
SELECT
  CUSTOMER_ID, TOTAL_ANNUAL_PREMIUM, ACTIVE_POLICY_COUNT, CLAIM_COUNT, TOTAL_CLAIM_AMOUNT,
  MISSED_PAYMENT_COUNT, LATEST_CHURN_RISK, LATEST_SENTIMENT, LAST_INTERACTION_DATE,
  REVENUE_AT_RISK, PRIORITY_SCORE,
  NBA_OBJ:next_best_action::STRING AS NEXT_BEST_ACTION,
  NBA_OBJ:rationale::STRING AS NBA_RATIONALE
FROM nba;
