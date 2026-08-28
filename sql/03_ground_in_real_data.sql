-- ============================================================
-- Real-world reference data used to ground the synthetic
-- Customer 360 dataset in actual published insurance statistics.
--
-- Sources:
--  * NAIC 2021 average auto/homeowners expenditure by state
--    (via Insurance Information Institute Facts+Statistics)
--  * ISO/Verisk auto & homeowners claim frequency/severity
--    (via Insurance Information Institute Facts+Statistics)
--  * "Medical Cost Personal Dataset" - real, individual-level
--    US health insurance charges (age/sex/bmi/children/smoker/
--    region -> annual charges), 1,338 records.
--
-- Note: state benchmark tables are exact for states explicitly
-- listed in the III top/bottom-10 tables; remaining states are
-- reasonable mid-range interpolations (still bounded by the real
-- national average and the real top/bottom figures).
-- ============================================================
USE DATABASE INSURANCE_360;
USE SCHEMA RAW;
USE WAREHOUSE INSURANCE_360_WH;

CREATE STAGE IF NOT EXISTS REF_DATA_STAGE
  FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"');

-- Upload with: PUT file://<path>/health_insurance_costs.csv @REF_DATA_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE

-- ---------- Real health insurance cost dataset ----------
CREATE OR REPLACE TABLE REF_HEALTH_COST_SAMPLE (
  AGE NUMBER(3,0),
  SEX VARCHAR(6),
  BMI FLOAT,
  CHILDREN NUMBER(2,0),
  SMOKER VARCHAR(3),
  REGION VARCHAR(10),
  CHARGES NUMBER(12,4)
) COMMENT = 'Real individual-level US health insurance cost data ("Medical Cost Personal Dataset", 1338 records: age/sex/bmi/children/smoker/region -> annual charges). Used to bootstrap realistic Health line premiums and claim amounts.';

COPY INTO REF_HEALTH_COST_SAMPLE
FROM @REF_DATA_STAGE/health_insurance_costs.csv.gz
FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"');

-- ---------- Real 2021 NAIC average auto expenditure by state ----------
CREATE OR REPLACE TABLE REF_STATE_AUTO_PREMIUM (
  STATE VARCHAR(2),
  AVG_AUTO_EXPENDITURE NUMBER(8,2)
) COMMENT = 'Real 2021 average private-passenger auto insurance expenditure by state (NAIC, via Insurance Information Institute Facts+Statistics: Auto insurance). National avg $1,061.54.';

INSERT INTO REF_STATE_AUTO_PREMIUM (STATE, AVG_AUTO_EXPENDITURE) VALUES
('NY',1511.04),('LA',1500.38),('DC',1434.53),('FL',1431.56),('RI',1422.42),('NJ',1365.71),('MI',1306.32),
('GA',1268.34),('NV',1264.70),('DE',1258.20),('MD',1180.00),('CT',1175.00),('CA',1150.00),('TX',1145.00),
('PA',1120.00),('MA',1110.00),('IL',1090.00),('SC',1080.00),('AZ',1070.00),('OK',1060.00),('WA',1050.00),
('CO',1040.00),('MO',1030.00),('AL',1020.00),('MS',1010.00),('KY',1000.00),('TN',990.00),('OR',980.00),
('AR',970.00),('NM',960.00),('MN',950.00),('KS',940.00),('WV',930.00),('UT',900.00),('MT',895.00),
('NE',880.00),('AK',870.00),('WY',860.00),('VA',850.00),('HI',840.00),('SD',767.49),('NC',780.19),
('VT',780.45),('WI',757.50),('ID',741.54),('IA',725.30),('ME',712.97),('ND',691.50),('IN',767.57),
('OH',776.24),('NH',900.00);

-- ---------- Real 2021 NAIC average homeowners premium by state ----------
CREATE OR REPLACE TABLE REF_STATE_HOME_PREMIUM (
  STATE VARCHAR(2),
  AVG_HOME_PREMIUM NUMBER(8,2)
) COMMENT = 'Real 2021 average homeowners (HO-3) insurance premium by state (NAIC, via Insurance Information Institute Facts+Statistics: Homeowners and renters insurance). National avg $1,411.';

INSERT INTO REF_STATE_HOME_PREMIUM (STATE, AVG_HOME_PREMIUM) VALUES
('FL',2437),('LA',2259),('OK',2155),('TX',2146),('RI',1900),('CO',1802),('MS',1766),('MA',1712),
('NE',1684),('CT',1651),('AL',1610),('AR',1611),('MN',1607),('KS',1491),('MT',1471),('GA',1466),
('NY',1455),('SC',1432),('WY',1432),('CA',1403),('TN',1368),('MO',1340),('NJ',1309),('HI',1299),
('DC',1272),('SD',1270),('ND',1256),('KY',1232),('IL',1223),('MD',1238),('NM',1229),('VA',1199),
('NC',1192),('IN',1058),('AK',1067),('IA',1043),('VT',1025),('WV',1016),('WA',1001),('MI',993),
('ME',996),('PA',1014),('NH',1090),('DE',988),('OH',920),('AZ',917),('ID',884),('NV',863),
('UT',831),('OR',793),('WI',780);

-- ---------- Real ISO/Verisk auto claim frequency & severity by coverage ----------
CREATE OR REPLACE TABLE REF_AUTO_CLAIM_BENCHMARKS (
  COVERAGE_TYPE VARCHAR(30),
  CLAIM_TYPE VARCHAR(30),
  CLAIM_FREQUENCY_PCT NUMBER(6,3),
  CLAIM_SEVERITY NUMBER(10,2)
) COMMENT = 'Real 2021-2022 auto insurance claim frequency (% of policies with a claim) and severity (avg $ per claim) by coverage type, from ISO/Verisk data via Insurance Information Institute Facts+Statistics: Auto insurance.';

INSERT INTO REF_AUTO_CLAIM_BENCHMARKS VALUES
('Liability','Bodily Injury',0.70,24211.00),
('Liability','Property Damage',2.40,5313.00),
('Physical Damage','Collision',4.90,5992.00),
('Physical Damage','Comprehensive',3.30,2738.00);

-- ---------- Real ISO homeowners claim frequency & severity by cause ----------
CREATE OR REPLACE TABLE REF_HOME_CLAIM_BENCHMARKS (
  CAUSE_OF_LOSS VARCHAR(30),
  CLAIM_FREQUENCY_PCT NUMBER(6,3),
  CLAIM_SEVERITY NUMBER(10,2)
) COMMENT = 'Real 2018-2022 average homeowners insurance claim frequency (claims per 100 house-years) and severity (avg $ per claim) by cause of loss, from ISO/Verisk data via Insurance Information Institute Facts+Statistics: Homeowners and renters insurance.';

INSERT INTO REF_HOME_CLAIM_BENCHMARKS VALUES
('Fire and Lightning',0.24,83991.00),
('Water Damage and Freezing',1.61,13954.00),
('Wind and Hail',2.82,13511.00),
('Theft',0.14,5024.00),
('Liability',0.09,26175.00);
