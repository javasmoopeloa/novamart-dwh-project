-- NovaMart Data Warehouse
-- Phase 2: Cloud Architecture Setup
-- Creates the three-layer schema structure (Ch. 2): staging -> core -> mart
-- Run this against your AWS RDS PostgreSQL instance via DBeaver.

-- 1. Staging: raw, minimally-touched data, loaded as close to source format as possible
CREATE SCHEMA IF NOT EXISTS staging;

-- 2. Core: the integrated, cleaned single source of truth
CREATE SCHEMA IF NOT EXISTS core;

-- 3. Data marts: purpose-built star schema(s) for reporting
CREATE SCHEMA IF NOT EXISTS mart_finance;
-- Optional second mart if your group wants one for operations:
-- CREATE SCHEMA IF NOT EXISTS mart_ops;

-- Quick sanity check: list all schemas you now have
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('staging', 'core', 'mart_finance', 'mart_ops')
ORDER BY schema_name;
