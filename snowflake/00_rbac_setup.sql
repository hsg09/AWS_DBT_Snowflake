-- =============================================================================
-- File: 00_rbac_setup.sql
-- Purpose: Establish all Snowflake roles, warehouses, databases, schemas, and grants
--          following the principle of least privilege.
-- Run as: ACCOUNTADMIN (one-time setup)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------------
-- 1. Warehouses  (one per workload type to avoid contention + cost isolation)
-- ---------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS LOADER_WH
    WAREHOUSE_SIZE        = 'X-SMALL'
    AUTO_SUSPEND          = 60          -- seconds; aggressive suspend for cost
    AUTO_RESUME           = TRUE
    INITIALLY_SUSPENDED   = TRUE
    COMMENT               = 'Used by ingestion jobs (Snowpipe / Tasks) to COPY INTO raw tables';

CREATE WAREHOUSE IF NOT EXISTS TRANSFORMER_WH
    WAREHOUSE_SIZE        = 'SMALL'
    AUTO_SUSPEND          = 120
    AUTO_RESUME           = TRUE
    INITIALLY_SUSPENDED   = TRUE
    COMMENT               = 'Used by dbt transformations (staging → intermediate → marts)';

CREATE WAREHOUSE IF NOT EXISTS ANALYST_WH
    WAREHOUSE_SIZE        = 'X-SMALL'
    AUTO_SUSPEND          = 300
    AUTO_RESUME           = TRUE
    INITIALLY_SUSPENDED   = TRUE
    COMMENT               = 'Used by BI tools and ad-hoc analyst queries';

CREATE WAREHOUSE IF NOT EXISTS ADMIN_WH
    WAREHOUSE_SIZE        = 'X-SMALL'
    AUTO_SUSPEND          = 60
    AUTO_RESUME           = TRUE
    INITIALLY_SUSPENDED   = TRUE
    COMMENT               = 'Used for admin / DDL operations';

-- ---------------------------------------------------------------------------
-- 2. Databases & Schemas
--    RAW         -> landing zone, mirrors S3 structure
--    ANALYTICS   -> dbt-managed: STAGING, INTERMEDIATE, MARTS
--    AUDIT       -> metadata, file ingestion logs, data quality results
-- ---------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS RAW         COMMENT = 'Landing zone: mirrors S3 raw files';
CREATE DATABASE IF NOT EXISTS ANALYTICS   COMMENT = 'dbt-managed transformation layers';
CREATE DATABASE IF NOT EXISTS AUDIT       COMMENT = 'Ingestion metadata, quality checks, governance';

-- Source-specific schemas inside RAW
CREATE SCHEMA IF NOT EXISTS RAW.ECOMMERCE   COMMENT = 'E-commerce raw tables';
CREATE SCHEMA IF NOT EXISTS RAW.EXTERNAL    COMMENT = 'Third-party / partner raw feeds';

-- dbt layer schemas inside ANALYTICS
CREATE SCHEMA IF NOT EXISTS ANALYTICS.STAGING       COMMENT = 'dbt staging layer';
CREATE SCHEMA IF NOT EXISTS ANALYTICS.INTERMEDIATE  COMMENT = 'dbt intermediate layer';
CREATE SCHEMA IF NOT EXISTS ANALYTICS.MARTS         COMMENT = 'dbt marts layer (business-facing)';

-- Control tables
CREATE SCHEMA IF NOT EXISTS AUDIT.CONTROL COMMENT = 'Ingestion control and metadata';

-- ---------------------------------------------------------------------------
-- 3. Roles  (role hierarchy: SYSADMIN → LOADER / TRANSFORMER / ANALYST)
-- ---------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS LOADER         COMMENT = 'Ingests raw data from S3 into RAW database';
CREATE ROLE IF NOT EXISTS TRANSFORMER    COMMENT = 'Runs dbt transformations; reads RAW, writes ANALYTICS';
CREATE ROLE IF NOT EXISTS ANALYST        COMMENT = 'Read-only access to ANALYTICS.MARTS';
CREATE ROLE IF NOT EXISTS DATA_ENGINEER  COMMENT = 'Full access to RAW + ANALYTICS for development';

-- Role hierarchy
GRANT ROLE LOADER        TO ROLE SYSADMIN;
GRANT ROLE TRANSFORMER   TO ROLE SYSADMIN;
GRANT ROLE ANALYST       TO ROLE SYSADMIN;
GRANT ROLE DATA_ENGINEER TO ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- 4. Service accounts (users)
-- ---------------------------------------------------------------------------
CREATE USER IF NOT EXISTS SVC_LOADER
    DEFAULT_ROLE      = LOADER
    DEFAULT_WAREHOUSE = LOADER_WH
    COMMENT           = 'Service account for ingestion pipeline (Airflow / Snowpipe)';

CREATE USER IF NOT EXISTS SVC_TRANSFORMER
    DEFAULT_ROLE      = TRANSFORMER
    DEFAULT_WAREHOUSE = TRANSFORMER_WH
    COMMENT           = 'Service account for dbt runs (Airflow / CI/CD)';

GRANT ROLE LOADER       TO USER SVC_LOADER;
GRANT ROLE TRANSFORMER  TO USER SVC_TRANSFORMER;

-- ---------------------------------------------------------------------------
-- 5. Warehouse grants
-- ---------------------------------------------------------------------------
GRANT USAGE ON WAREHOUSE LOADER_WH      TO ROLE LOADER;
GRANT USAGE ON WAREHOUSE TRANSFORMER_WH TO ROLE TRANSFORMER;
GRANT USAGE ON WAREHOUSE ANALYST_WH     TO ROLE ANALYST;
GRANT USAGE ON WAREHOUSE TRANSFORMER_WH TO ROLE DATA_ENGINEER;
GRANT USAGE ON WAREHOUSE ADMIN_WH       TO ROLE DATA_ENGINEER;

-- ---------------------------------------------------------------------------
-- 6. Database / schema grants
-- ---------------------------------------------------------------------------
-- LOADER: write to RAW only
GRANT USAGE  ON DATABASE RAW                    TO ROLE LOADER;
GRANT USAGE  ON ALL SCHEMAS IN DATABASE RAW     TO ROLE LOADER;
GRANT CREATE TABLE, CREATE STAGE, CREATE STREAM
             ON SCHEMA RAW.ECOMMERCE            TO ROLE LOADER;
GRANT INSERT, UPDATE, TRUNCATE
             ON ALL TABLES IN SCHEMA RAW.ECOMMERCE TO ROLE LOADER;
GRANT USAGE  ON DATABASE AUDIT                  TO ROLE LOADER;
GRANT USAGE  ON SCHEMA AUDIT.CONTROL            TO ROLE LOADER;
GRANT INSERT, UPDATE, SELECT
             ON ALL TABLES IN SCHEMA AUDIT.CONTROL TO ROLE LOADER;

-- TRANSFORMER: read RAW, write ANALYTICS
GRANT USAGE  ON DATABASE RAW                        TO ROLE TRANSFORMER;
GRANT USAGE  ON ALL SCHEMAS IN DATABASE RAW         TO ROLE TRANSFORMER;
GRANT SELECT ON ALL TABLES   IN DATABASE RAW        TO ROLE TRANSFORMER;
GRANT SELECT ON FUTURE TABLES IN DATABASE RAW       TO ROLE TRANSFORMER;
GRANT USAGE  ON DATABASE ANALYTICS                  TO ROLE TRANSFORMER;
GRANT USAGE  ON ALL SCHEMAS  IN DATABASE ANALYTICS  TO ROLE TRANSFORMER;
GRANT ALL    ON ALL SCHEMAS  IN DATABASE ANALYTICS  TO ROLE TRANSFORMER;
GRANT CREATE SCHEMA
             ON DATABASE ANALYTICS                  TO ROLE TRANSFORMER;
GRANT CREATE TABLE, CREATE VIEW
             ON ALL SCHEMAS IN DATABASE ANALYTICS   TO ROLE TRANSFORMER;
GRANT USAGE  ON DATABASE AUDIT                      TO ROLE TRANSFORMER;
GRANT SELECT ON ALL TABLES IN SCHEMA AUDIT.CONTROL  TO ROLE TRANSFORMER;

-- ANALYST: read-only on marts
GRANT USAGE  ON DATABASE ANALYTICS                      TO ROLE ANALYST;
GRANT USAGE  ON SCHEMA ANALYTICS.MARTS                  TO ROLE ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA ANALYTICS.MARTS    TO ROLE ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ANALYTICS.MARTS TO ROLE ANALYST;

-- DATA_ENGINEER: full access everywhere
GRANT ALL ON DATABASE RAW       TO ROLE DATA_ENGINEER;
GRANT ALL ON DATABASE ANALYTICS TO ROLE DATA_ENGINEER;
GRANT ALL ON DATABASE AUDIT     TO ROLE DATA_ENGINEER;

-- ---------------------------------------------------------------------------
-- 7. Future grants (important: applies to objects created later)
-- ---------------------------------------------------------------------------
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW.ECOMMERCE       TO ROLE TRANSFORMER;
GRANT INSERT, UPDATE ON FUTURE TABLES IN SCHEMA RAW.ECOMMERCE TO ROLE LOADER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ANALYTICS.MARTS     TO ROLE ANALYST;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA ANALYTICS.MARTS     TO ROLE ANALYST;

-- ---------------------------------------------------------------------------
-- 8. Transfer ownership of all databases & schemas to SYSADMIN
--
--    WHY THIS IS NEEDED:
--    All objects above were created as ACCOUNTADMIN, so ACCOUNTADMIN owns them.
--    Subsequent scripts (01_file_formats_and_stages.sql, 03_dynamic_schema_procedure.sql,
--    etc.) run as SYSADMIN. Without ownership transfer, SYSADMIN cannot CREATE FILE
--    FORMAT, CREATE STAGE, CREATE PROCEDURE, etc. inside these schemas.
--
--    COPY CURRENT GRANTS preserves the privilege grants we set above (USAGE, SELECT,
--    CREATE TABLE, etc.) so they are not lost when ownership changes.
-- ---------------------------------------------------------------------------
GRANT OWNERSHIP ON DATABASE RAW       TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE ANALYTICS TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE AUDIT     TO ROLE SYSADMIN COPY CURRENT GRANTS;

GRANT OWNERSHIP ON SCHEMA RAW.ECOMMERCE            TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA RAW.EXTERNAL             TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA ANALYTICS.STAGING        TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA ANALYTICS.INTERMEDIATE   TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA ANALYTICS.MARTS          TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA AUDIT.CONTROL            TO ROLE SYSADMIN COPY CURRENT GRANTS;

