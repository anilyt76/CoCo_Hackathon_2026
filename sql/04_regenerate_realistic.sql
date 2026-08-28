-- ============================================================
-- Regenerate POLICIES / CLAIMS / PAYMENTS so premiums and claim
-- amounts are anchored to the real reference data loaded in
-- 03_ground_in_real_data.sql, instead of flat UNIFORM() ranges.
--
--   Auto premium  -> real 2021 NAIC state auto expenditure
--   Home premium  -> real 2021 NAIC state homeowners premium
--   Health premium/claims -> bootstrap-sampled real individual
--                             health charges (age-matched)
--   Life premium  -> age-based mortality-curve approximation
--                     (illustrative actuarial model, not tied to
--                     a specific published dataset)
--   Auto claims   -> real ISO claim frequency/severity by coverage
--   Home claims   -> real ISO claim frequency/severity by cause
--   Life claims   -> illustrative age-scaled mortality assumption
--   Health claims -> bootstrap-sampled real charges (age-matched)
-- ============================================================
USE DATABASE INSURANCE_360;
USE SCHEMA RAW;
USE WAREHOUSE INSURANCE_360_WH;

-- ---------- POLICIES ----------
CREATE OR REPLACE TABLE POLICIES AS
WITH policy_counts AS (
  SELECT CUSTOMER_ID, UNIFORM(1, 3, RANDOM()) AS NUM_POLICIES
  FROM CUSTOMERS
),
expanded AS (
  SELECT c.CUSTOMER_ID, c.STATE, c.CUSTOMER_SEGMENT, c.CREDIT_SCORE_BAND, c.CUSTOMER_SINCE,
         DATEDIFF(YEAR, c.DATE_OF_BIRTH, CURRENT_DATE()) AS AGE,
         seq.SEQ AS POLICY_SEQ
  FROM policy_counts pc
  JOIN CUSTOMERS c ON c.CUSTOMER_ID = pc.CUSTOMER_ID,
       (SELECT SEQ4() + 1 AS SEQ FROM TABLE(GENERATOR(ROWCOUNT => 3))) seq
  WHERE seq.SEQ <= pc.NUM_POLICIES
),
lob_assigned AS (
  SELECT e.*,
    CASE UNIFORM(0, 3, RANDOM()) WHEN 0 THEN 'Auto' WHEN 1 THEN 'Home' WHEN 2 THEN 'Life' ELSE 'Health' END AS LINE_OF_BUSINESS
  FROM expanded e
),
factored AS (
  SELECT la.*,
    CASE CUSTOMER_SEGMENT WHEN 'High-Value' THEN 1.35 WHEN 'Preferred' THEN 1.05 ELSE 0.85 END AS SEGMENT_FACTOR,
    CASE CREDIT_SCORE_BAND WHEN 'Excellent (750+)' THEN 0.90 WHEN 'Good (700-749)' THEN 1.00
         WHEN 'Fair (650-699)' THEN 1.15 ELSE 1.35 END AS CREDIT_FACTOR,
    ra.AVG_AUTO_EXPENDITURE AS STATE_AUTO_BENCHMARK,
    rh.AVG_HOME_PREMIUM AS STATE_HOME_BENCHMARK,
    h.CHARGES AS HEALTH_SAMPLE_CHARGES
  FROM lob_assigned la
  LEFT JOIN REF_STATE_AUTO_PREMIUM ra ON ra.STATE = la.STATE
  LEFT JOIN REF_STATE_HOME_PREMIUM rh ON rh.STATE = la.STATE
  LEFT JOIN REF_HEALTH_COST_SAMPLE h ON h.AGE BETWEEN GREATEST(la.AGE - 5, 18) AND LEAST(la.AGE + 5, 64)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY la.CUSTOMER_ID, la.POLICY_SEQ ORDER BY RANDOM()) = 1
),
priced AS (
  SELECT *,
    CASE LINE_OF_BUSINESS
      WHEN 'Auto' THEN ROUND(COALESCE(STATE_AUTO_BENCHMARK, 1061.54) * SEGMENT_FACTOR * CREDIT_FACTOR
                              * (0.80 + UNIFORM(0::FLOAT, 0.40::FLOAT, RANDOM())), 2)
      WHEN 'Home' THEN ROUND(COALESCE(STATE_HOME_BENCHMARK, 1411.00) * SEGMENT_FACTOR * CREDIT_FACTOR
                              * (0.80 + UNIFORM(0::FLOAT, 0.40::FLOAT, RANDOM())), 2)
      WHEN 'Health' THEN ROUND(COALESCE(HEALTH_SAMPLE_CHARGES, 13270.42) * 0.22 * SEGMENT_FACTOR
                              * (0.85 + UNIFORM(0::FLOAT, 0.30::FLOAT, RANDOM())), 2)
      ELSE ROUND(60 * EXP(0.055 * (AGE - 25)) * SEGMENT_FACTOR
                              * (0.85 + UNIFORM(0::FLOAT, 0.30::FLOAT, RANDOM())), 2)
    END AS ANNUAL_PREMIUM
  FROM factored
)
SELECT
  'POL' || LPAD(ROW_NUMBER() OVER (ORDER BY CUSTOMER_ID, POLICY_SEQ), 7, '0') AS POLICY_ID,
  CUSTOMER_ID,
  LINE_OF_BUSINESS,
  'PN-' || UNIFORM(100000, 999999, RANDOM()) AS POLICY_NUMBER,
  DATEADD(DAY, FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * GREATEST(DATEDIFF(DAY, CUSTOMER_SINCE, CURRENT_DATE()),1)), CUSTOMER_SINCE) AS EFFECTIVE_DATE,
  CASE
    WHEN UNIFORM(0, 99, RANDOM()) < 70 THEN 'Active'
    WHEN UNIFORM(0, 99, RANDOM()) < 85 THEN 'Pending Renewal'
    WHEN UNIFORM(0, 99, RANDOM()) < 95 THEN 'Lapsed'
    ELSE 'Cancelled'
  END AS STATUS,
  GREATEST(ANNUAL_PREMIUM, 120) AS ANNUAL_PREMIUM,
  CASE LINE_OF_BUSINESS
    WHEN 'Home' THEN ROUND(UNIFORM(150000, 750000, RANDOM()), 0)
    WHEN 'Life' THEN ROUND(UNIFORM(100000, 1000000, RANDOM()), 0)
    ELSE ROUND(UNIFORM(50000, 300000, RANDOM()), 0)
  END AS COVERAGE_AMOUNT,
  CASE UNIFORM(0, 3, RANDOM()) WHEN 0 THEN 250 WHEN 1 THEN 500 WHEN 2 THEN 1000 ELSE 2500 END AS DEDUCTIBLE,
  CUSTOMER_SEGMENT
FROM priced;

-- backfill renewal date = effective_date + 1 year
CREATE OR REPLACE TABLE POLICIES AS
SELECT
  POLICY_ID, CUSTOMER_ID, LINE_OF_BUSINESS, POLICY_NUMBER, EFFECTIVE_DATE,
  DATEADD(YEAR, 1, EFFECTIVE_DATE) AS RENEWAL_DATE,
  STATUS, ANNUAL_PREMIUM, COVERAGE_AMOUNT, DEDUCTIBLE, CUSTOMER_SEGMENT
FROM POLICIES;

-- ---------- CLAIMS ----------
CREATE OR REPLACE TABLE CLAIMS AS
WITH base AS (
  SELECT p.POLICY_ID, p.CUSTOMER_ID, p.LINE_OF_BUSINESS, p.EFFECTIVE_DATE, p.COVERAGE_AMOUNT,
         GREATEST(DATEDIFF(DAY, p.EFFECTIVE_DATE, CURRENT_DATE()), 30) / 365.0 AS POLICY_YEARS,
         DATEDIFF(YEAR, c.DATE_OF_BIRTH, CURRENT_DATE()) AS AGE
  FROM POLICIES p
  JOIN CUSTOMERS c ON c.CUSTOMER_ID = p.CUSTOMER_ID
),
-- Auto: one candidate claim per real coverage-type benchmark, kept with
-- probability 1-(1-freq)^years so multi-year tenure raises cumulative odds
-- while the underlying annual rate matches the real ISO/NAIC figure.
auto_claims AS (
  SELECT b.POLICY_ID, b.CUSTOMER_ID, b.LINE_OF_BUSINESS, r.CLAIM_TYPE AS CLAIM_TYPE,
         b.EFFECTIVE_DATE, b.POLICY_YEARS,
         ROUND(r.CLAIM_SEVERITY * (0.4 + UNIFORM(0::FLOAT, 2.1::FLOAT, RANDOM())), 2) AS CLAIM_AMOUNT
  FROM base b
  JOIN REF_AUTO_CLAIM_BENCHMARKS r ON b.LINE_OF_BUSINESS = 'Auto'
  WHERE UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < (1 - POWER(1 - r.CLAIM_FREQUENCY_PCT/100.0, b.POLICY_YEARS))
),
home_claims AS (
  SELECT b.POLICY_ID, b.CUSTOMER_ID, b.LINE_OF_BUSINESS, r.CAUSE_OF_LOSS AS CLAIM_TYPE,
         b.EFFECTIVE_DATE, b.POLICY_YEARS,
         ROUND(r.CLAIM_SEVERITY * (0.4 + UNIFORM(0::FLOAT, 2.1::FLOAT, RANDOM())), 2) AS CLAIM_AMOUNT
  FROM base b
  JOIN REF_HOME_CLAIM_BENCHMARKS r ON b.LINE_OF_BUSINESS = 'Home'
  WHERE UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < (1 - POWER(1 - r.CLAIM_FREQUENCY_PCT/100.0, b.POLICY_YEARS))
),
-- Health: bootstrap one real charges record close to the customer's age per
-- policy, then apply an illustrative ~45%/yr utilization assumption.
health_sample AS (
  SELECT b.POLICY_ID, b.CUSTOMER_ID, b.LINE_OF_BUSINESS, b.EFFECTIVE_DATE, b.POLICY_YEARS, h.CHARGES
  FROM base b
  JOIN REF_HEALTH_COST_SAMPLE h ON h.AGE BETWEEN GREATEST(b.AGE - 5, 18) AND LEAST(b.AGE + 5, 64)
  WHERE b.LINE_OF_BUSINESS = 'Health'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY b.POLICY_ID ORDER BY RANDOM()) = 1
),
health_claims AS (
  SELECT POLICY_ID, CUSTOMER_ID, LINE_OF_BUSINESS, 'Hospitalization/Outpatient Care' AS CLAIM_TYPE,
         EFFECTIVE_DATE, POLICY_YEARS, ROUND(CHARGES, 2) AS CLAIM_AMOUNT
  FROM health_sample
  WHERE UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < (1 - POWER(1 - 0.45, POLICY_YEARS))
),
-- Life: rare death-benefit claim, age-scaled illustrative mortality assumption.
life_claims AS (
  SELECT b.POLICY_ID, b.CUSTOMER_ID, b.LINE_OF_BUSINESS, 'Death Benefit' AS CLAIM_TYPE,
         b.EFFECTIVE_DATE, b.POLICY_YEARS,
         b.COVERAGE_AMOUNT AS CLAIM_AMOUNT
  FROM base b
  WHERE b.LINE_OF_BUSINESS = 'Life'
    AND UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < (1 - POWER(1 - (0.001 * GREATEST(b.AGE - 20, 1) / 40.0), b.POLICY_YEARS))
),
unioned AS (
  SELECT * FROM auto_claims
  UNION ALL SELECT * FROM home_claims
  UNION ALL SELECT * FROM health_claims
  UNION ALL SELECT * FROM life_claims
)
SELECT
  'CLM' || LPAD(ROW_NUMBER() OVER (ORDER BY POLICY_ID, CLAIM_TYPE), 7, '0') AS CLAIM_ID,
  POLICY_ID,
  CUSTOMER_ID,
  CLAIM_TYPE,
  DATEADD(DAY, 30 + MOD(ABS(RANDOM()), GREATEST(DATEDIFF(DAY, EFFECTIVE_DATE, CURRENT_DATE()) - 30, 1)), EFFECTIVE_DATE) AS CLAIM_DATE,
  CLAIM_AMOUNT,
  CASE UNIFORM(0, 4, RANDOM())
    WHEN 0 THEN 'Filed' WHEN 1 THEN 'Under Review' WHEN 2 THEN 'Approved' WHEN 3 THEN 'Paid' ELSE 'Denied' END AS STATUS,
  UNIFORM(2, 45, RANDOM()) AS RESOLUTION_DAYS
FROM unioned;

-- ---------- PAYMENTS (last 12 monthly premium installments per policy) ----------
CREATE OR REPLACE TABLE PAYMENTS AS
WITH months AS (
  SELECT SEQ4() AS M FROM TABLE(GENERATOR(ROWCOUNT => 12))
)
SELECT
  'PAY' || LPAD(ROW_NUMBER() OVER (ORDER BY p.POLICY_ID, m.M), 8, '0') AS PAYMENT_ID,
  p.POLICY_ID,
  p.CUSTOMER_ID,
  DATEADD(MONTH, -m.M, DATE_TRUNC('MONTH', CURRENT_DATE())) AS DUE_DATE,
  CASE WHEN UNIFORM(0, 99, RANDOM()) < 85
       THEN DATEADD(DAY, UNIFORM(-2, 5, RANDOM()), DATEADD(MONTH, -m.M, DATE_TRUNC('MONTH', CURRENT_DATE())))
       ELSE NULL END AS PAID_DATE,
  ROUND(p.ANNUAL_PREMIUM / 12.0, 2) AS AMOUNT,
  CASE
    WHEN UNIFORM(0, 99, RANDOM()) < 80 THEN 'Paid'
    WHEN UNIFORM(0, 99, RANDOM()) < 95 THEN 'Late'
    ELSE 'Missed'
  END AS STATUS,
  CASE UNIFORM(0, 3, RANDOM())
    WHEN 0 THEN 'AutoPay' WHEN 1 THEN 'Credit Card' WHEN 2 THEN 'Bank Transfer' ELSE 'Check' END AS PAYMENT_METHOD
FROM POLICIES p, months m
WHERE p.STATUS != 'Cancelled' OR m.M >= 3;

-- ---------- Quick sanity counts ----------
SELECT 'POLICIES' AS TBL, COUNT(*) FROM POLICIES
UNION ALL SELECT 'CLAIMS', COUNT(*) FROM CLAIMS
UNION ALL SELECT 'PAYMENTS', COUNT(*) FROM PAYMENTS;
