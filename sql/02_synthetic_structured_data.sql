-- ============================================================
-- Synthetic structured data: customers, policies, claims, payments
-- ============================================================
USE DATABASE INSURANCE_360;
USE SCHEMA RAW;
USE WAREHOUSE INSURANCE_360_WH;

-- ---------- CUSTOMERS ----------
CREATE OR REPLACE TABLE CUSTOMERS AS
WITH first_names AS (
  SELECT ARRAY_CONSTRUCT('James','Mary','Robert','Patricia','John','Jennifer','Michael','Linda','David','Elizabeth',
    'William','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Charles','Karen',
    'Christopher','Nancy','Daniel','Lisa','Matthew','Betty','Anthony','Margaret','Mark','Sandra',
    'Donald','Ashley','Steven','Kimberly','Paul','Emily','Andrew','Donna','Joshua','Michelle',
    'Kenneth','Carol','Kevin','Amanda','Brian','Melissa','George','Deborah','Timothy','Stephanie') AS arr
),
last_names AS (
  SELECT ARRAY_CONSTRUCT('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
    'Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
    'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson',
    'Walker','Young','Allen','King','Wright','Scott','Torres','Nguyen','Hill','Flores',
    'Green','Adams','Nelson','Baker','Hall','Rivera','Campbell','Mitchell','Carter','Roberts') AS arr
),
cities AS (
  SELECT ARRAY_CONSTRUCT_COMPACT(
    OBJECT_CONSTRUCT('city','Columbus','state','OH'), OBJECT_CONSTRUCT('city','Cleveland','state','OH'),
    OBJECT_CONSTRUCT('city','Cincinnati','state','OH'), OBJECT_CONSTRUCT('city','Chicago','state','IL'),
    OBJECT_CONSTRUCT('city','Indianapolis','state','IN'), OBJECT_CONSTRUCT('city','Pittsburgh','state','PA'),
    OBJECT_CONSTRUCT('city','Detroit','state','MI'), OBJECT_CONSTRUCT('city','Louisville','state','KY'),
    OBJECT_CONSTRUCT('city','Nashville','state','TN'), OBJECT_CONSTRUCT('city','Charlotte','state','NC'),
    OBJECT_CONSTRUCT('city','Atlanta','state','GA'), OBJECT_CONSTRUCT('city','Denver','state','CO'),
    OBJECT_CONSTRUCT('city','Phoenix','state','AZ'), OBJECT_CONSTRUCT('city','Austin','state','TX'),
    OBJECT_CONSTRUCT('city','Dallas','state','TX'), OBJECT_CONSTRUCT('city','Orlando','state','FL'),
    OBJECT_CONSTRUCT('city','Tampa','state','FL'), OBJECT_CONSTRUCT('city','Sacramento','state','CA'),
    OBJECT_CONSTRUCT('city','Portland','state','OR'), OBJECT_CONSTRUCT('city','Seattle','state','WA')
  ) AS arr
),
base AS (
  SELECT SEQ4() AS rn
  FROM TABLE(GENERATOR(ROWCOUNT => 800))
)
SELECT
  'CUST' || LPAD(rn + 1, 6, '0')                                   AS CUSTOMER_ID,
  GET(fn.arr, UNIFORM(0, 49, RANDOM()))::STRING                    AS FIRST_NAME,
  GET(ln.arr, UNIFORM(0, 49, RANDOM()))::STRING                    AS LAST_NAME,
  LOWER(GET(fn.arr, UNIFORM(0, 49, RANDOM()))::STRING || '.' ||
        GET(ln.arr, UNIFORM(0, 49, RANDOM()))::STRING || rn || '@example.com') AS EMAIL,
  '+1-' || LPAD(UNIFORM(200, 999, RANDOM()), 3, '0') || '-' || LPAD(UNIFORM(200, 999, RANDOM()), 3, '0') || '-' || LPAD(UNIFORM(1000, 9999, RANDOM()), 4, '0') AS PHONE,
  DATEADD(YEAR, -UNIFORM(23, 78, RANDOM()), DATEADD(DAY, -UNIFORM(0, 365, RANDOM()), CURRENT_DATE())) AS DATE_OF_BIRTH,
  CASE WHEN UNIFORM(0, 1, RANDOM()) = 0 THEN 'M' ELSE 'F' END      AS GENDER,
  GET(c.arr, UNIFORM(0, 19, RANDOM())):city::STRING                AS CITY,
  GET(c.arr, UNIFORM(0, 19, RANDOM())):state::STRING                AS STATE,
  LPAD(UNIFORM(10000, 99999, RANDOM()), 5, '0')                    AS ZIP,
  DATEADD(DAY, -UNIFORM(30, 5475, RANDOM()), CURRENT_DATE())        AS CUSTOMER_SINCE,
  CASE UNIFORM(0, 4, RANDOM())
    WHEN 0 THEN 'Agent' WHEN 1 THEN 'Online' WHEN 2 THEN 'Referral' WHEN 3 THEN 'Call Center' ELSE 'Broker' END AS CHANNEL_ACQUIRED,
  CASE
    WHEN UNIFORM(0, 99, RANDOM()) < 15 THEN 'High-Value'
    WHEN UNIFORM(0, 99, RANDOM()) < 55 THEN 'Preferred'
    ELSE 'Standard'
  END AS CUSTOMER_SEGMENT,
  CASE UNIFORM(0, 3, RANDOM())
    WHEN 0 THEN 'Excellent (750+)' WHEN 1 THEN 'Good (700-749)' WHEN 2 THEN 'Fair (650-699)' ELSE 'Poor (<650)' END AS CREDIT_SCORE_BAND,
  CASE UNIFORM(0, 3, RANDOM())
    WHEN 0 THEN 'Single' WHEN 1 THEN 'Married' WHEN 2 THEN 'Divorced' ELSE 'Widowed' END AS MARITAL_STATUS,
  CASE UNIFORM(0, 3, RANDOM())
    WHEN 0 THEN '<$50K' WHEN 1 THEN '$50K-$100K' WHEN 2 THEN '$100K-$150K' ELSE '$150K+' END AS HOUSEHOLD_INCOME_BAND
FROM base, first_names fn, last_names ln, cities c;

-- ---------- POLICIES ----------
CREATE OR REPLACE TABLE POLICIES AS
WITH policy_counts AS (
  SELECT CUSTOMER_ID, UNIFORM(1, 3, RANDOM()) AS NUM_POLICIES
  FROM CUSTOMERS
),
expanded AS (
  SELECT c.CUSTOMER_ID, c.CUSTOMER_SEGMENT, c.CUSTOMER_SINCE, seq.SEQ AS POLICY_SEQ
  FROM policy_counts c,
       TABLE(GENERATOR(ROWCOUNT => 3)) g,
       (SELECT SEQ4() + 1 AS SEQ FROM TABLE(GENERATOR(ROWCOUNT => 3))) seq
  WHERE seq.SEQ <= c.NUM_POLICIES
)
SELECT
  'POL' || LPAD(ROW_NUMBER() OVER (ORDER BY CUSTOMER_ID, POLICY_SEQ), 7, '0') AS POLICY_ID,
  CUSTOMER_ID,
  CASE UNIFORM(0, 3, RANDOM())
    WHEN 0 THEN 'Auto' WHEN 1 THEN 'Home' WHEN 2 THEN 'Life' ELSE 'Health' END AS LINE_OF_BUSINESS,
  'PN-' || UNIFORM(100000, 999999, RANDOM())                        AS POLICY_NUMBER,
  DATEADD(DAY, FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) * GREATEST(DATEDIFF(DAY, CUSTOMER_SINCE, CURRENT_DATE()),1)), CUSTOMER_SINCE) AS EFFECTIVE_DATE,
  CASE
    WHEN UNIFORM(0, 99, RANDOM()) < 70 THEN 'Active'
    WHEN UNIFORM(0, 99, RANDOM()) < 85 THEN 'Pending Renewal'
    WHEN UNIFORM(0, 99, RANDOM()) < 95 THEN 'Lapsed'
    ELSE 'Cancelled'
  END AS STATUS,
  ROUND(UNIFORM(400, 4500, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2) AS ANNUAL_PREMIUM,
  ROUND(UNIFORM(50000, 750000, RANDOM()), 0)                        AS COVERAGE_AMOUNT,
  CASE UNIFORM(0, 3, RANDOM()) WHEN 0 THEN 250 WHEN 1 THEN 500 WHEN 2 THEN 1000 ELSE 2500 END AS DEDUCTIBLE,
  CUSTOMER_SEGMENT
FROM expanded;

-- backfill renewal date = effective_date + 1 year, drop placeholder
CREATE OR REPLACE TABLE POLICIES AS
SELECT
  POLICY_ID, CUSTOMER_ID, LINE_OF_BUSINESS, POLICY_NUMBER, EFFECTIVE_DATE,
  DATEADD(YEAR, 1, EFFECTIVE_DATE) AS RENEWAL_DATE,
  STATUS, ANNUAL_PREMIUM, COVERAGE_AMOUNT, DEDUCTIBLE, CUSTOMER_SEGMENT
FROM POLICIES;

-- ---------- CLAIMS (roughly 35% of policies have at least one claim) ----------
CREATE OR REPLACE TABLE CLAIMS AS
WITH claim_candidates AS (
  SELECT POLICY_ID, CUSTOMER_ID, LINE_OF_BUSINESS, EFFECTIVE_DATE
  FROM POLICIES
  WHERE UNIFORM(0, 99, RANDOM()) < 35
),
claim_lines AS (
  SELECT cc.*, seq.SEQ AS CLAIM_SEQ, UNIFORM(1, 2, RANDOM()) AS NUM_CLAIMS
  FROM claim_candidates cc,
       (SELECT SEQ4() + 1 AS SEQ FROM TABLE(GENERATOR(ROWCOUNT => 2))) seq
  QUALIFY seq.SEQ <= NUM_CLAIMS
)
SELECT
  'CLM' || LPAD(ROW_NUMBER() OVER (ORDER BY POLICY_ID, CLAIM_SEQ), 7, '0') AS CLAIM_ID,
  POLICY_ID,
  CUSTOMER_ID,
  CASE LINE_OF_BUSINESS
    WHEN 'Auto' THEN (CASE UNIFORM(0,2,RANDOM()) WHEN 0 THEN 'Collision' WHEN 1 THEN 'Theft' ELSE 'Windshield Damage' END)
    WHEN 'Home' THEN (CASE UNIFORM(0,2,RANDOM()) WHEN 0 THEN 'Water Damage' WHEN 1 THEN 'Fire Damage' ELSE 'Storm Damage' END)
    WHEN 'Life' THEN 'Death Benefit'
    ELSE (CASE UNIFORM(0,2,RANDOM()) WHEN 0 THEN 'Hospitalization' WHEN 1 THEN 'Outpatient Procedure' ELSE 'Prescription Claim' END)
  END AS CLAIM_TYPE,
  DATEADD(DAY, UNIFORM(30, GREATEST(DATEDIFF(DAY, EFFECTIVE_DATE, CURRENT_DATE()),31), RANDOM()), EFFECTIVE_DATE) AS CLAIM_DATE,
  ROUND(UNIFORM(200, 45000, RANDOM()) + UNIFORM(0,99,RANDOM())/100.0, 2) AS CLAIM_AMOUNT,
  CASE UNIFORM(0, 4, RANDOM())
    WHEN 0 THEN 'Filed' WHEN 1 THEN 'Under Review' WHEN 2 THEN 'Approved' WHEN 3 THEN 'Paid' ELSE 'Denied' END AS STATUS,
  UNIFORM(2, 45, RANDOM()) AS RESOLUTION_DAYS
FROM claim_lines;

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
SELECT 'CUSTOMERS' AS TBL, COUNT(*) FROM CUSTOMERS
UNION ALL SELECT 'POLICIES', COUNT(*) FROM POLICIES
UNION ALL SELECT 'CLAIMS', COUNT(*) FROM CLAIMS
UNION ALL SELECT 'PAYMENTS', COUNT(*) FROM PAYMENTS;
