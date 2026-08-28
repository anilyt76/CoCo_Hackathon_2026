-- ============================================================
-- Insurance/Lending 360 Customer View - Setup
-- ============================================================
CREATE DATABASE IF NOT EXISTS INSURANCE_360;

CREATE SCHEMA IF NOT EXISTS INSURANCE_360.RAW;       -- synthetic source data
CREATE SCHEMA IF NOT EXISTS INSURANCE_360.CURATED;   -- enriched / AI-derived data
CREATE SCHEMA IF NOT EXISTS INSURANCE_360.AI;        -- search services, semantic views, agents

CREATE WAREHOUSE IF NOT EXISTS INSURANCE_360_WH
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE INSURANCE_360_WH;
USE DATABASE INSURANCE_360;
