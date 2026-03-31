-- =============================================================================
-- File: 01_file_formats_and_stages.sql
-- Purpose: Create file formats (CSV, JSON, Parquet) and named external S3 stage
--          using a Snowflake Storage Integration for secure, credential-free access.
-- Run as: SYSADMIN (after 00_rbac_setup.sql)
--
-- Design Notes:
--   • Storage Integration (not storage credentials) is used so IAM credentials
--     are never stored inside Snowflake. Snowflake assumes an IAM role via
--     trust relationship — best practice for production.
--   • One stage per logical source to allow format-specific configuration and
--     independent IAM scoping.
--   • COPY INTO and Snowpipe trade-offs are documented inline.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE ADMIN_WH;
USE DATABASE RAW;
USE SCHEMA ECOMMERCE;

-- ---------------------------------------------------------------------------
-- 1. Storage Integration (run as ACCOUNTADMIN, then grant to SYSADMIN)
--    After creation, run DESCRIBE INTEGRATION S3_INT and add the
--    STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID to the IAM trust policy.
-- ---------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
--DROP STORAGE INTEGRATION  S3_ECOMMERCE_INT;
CREATE STORAGE INTEGRATION S3_ECOMMERCE_INT
    TYPE                       = EXTERNAL_STAGE
    STORAGE_PROVIDER           = 'S3'
    ENABLED                    = TRUE
    STORAGE_AWS_ROLE_ARN       = 'arn:aws:iam::584856877055:role/snowflake-s3-reader-role'  -- replace
    STORAGE_ALLOWED_LOCATIONS  = ('s3://harnek-test-s3-bucket/raw/')  -- replace with actual bucket
    COMMENT = 'Secure S3 integration — uses IAM role assumption, no stored credentials';

GRANT USAGE ON INTEGRATION S3_ECOMMERCE_INT TO ROLE SYSADMIN;

-- Check: copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from here
-- and add them to the IAM role trust policy in AWS console.
DESCRIBE INTEGRATION S3_ECOMMERCE_INT;

USE ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- 2. File Formats
-- ---------------------------------------------------------------------------

-- CSV: flexible enough for most sources
CREATE OR REPLACE FILE FORMAT RAW.ECOMMERCE.FF_CSV
    TYPE                  = 'CSV'
    FIELD_DELIMITER       = ','
    RECORD_DELIMITER      = '\n'
    PARSE_HEADER          = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF               = ('NULL', 'null', '', 'NA', 'N/A')
    EMPTY_FIELD_AS_NULL   = TRUE
    TRIM_SPACE            = TRUE
    DATE_FORMAT           = 'AUTO'
    TIMESTAMP_FORMAT      = 'AUTO'
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE  -- Allows schema-evolved files
    COMMENT = 'Standard CSV with header. Tolerates schema drift (extra/missing columns).';

-- JSON: load as VARIANT for maximum flexibility; flatten in DBT staging layer
CREATE OR REPLACE FILE FORMAT RAW.ECOMMERCE.FF_JSON
    TYPE              = 'JSON'
    STRIP_OUTER_ARRAY = TRUE    -- handles array-wrapped JSON: [{...},{...}]
    STRIP_NULL_VALUES = FALSE   -- preserve nulls; let dbt handle them
    IGNORE_UTF8_ERRORS = TRUE
    COMMENT = 'JSON loaded as VARIANT. Strip outer array for array-wrapped payloads.';

-- Parquet: columnar, schema-embedded — preferred for large-volume sources
CREATE OR REPLACE FILE FORMAT RAW.ECOMMERCE.FF_PARQUET
    TYPE              = 'PARQUET'
    SNAPPY_COMPRESSION = TRUE   -- most common compression in data lakes
    BINARY_AS_TEXT    = FALSE
    COMMENT = 'Parquet with Snappy compression. Schema inferred from file metadata on load.';

-- ---------------------------------------------------------------------------
-- 3. External Stages (one per source entity for IAM scoping & monitoring)
-- ---------------------------------------------------------------------------

-- Master stage: points to root of raw landing zone
CREATE OR REPLACE STAGE RAW.ECOMMERCE.S3_RAW_STAGE
    STORAGE_INTEGRATION = S3_ECOMMERCE_INT
    URL                 = 's3://harnek-test-s3-bucket/raw/ecommerce/'  -- replace
    DIRECTORY           = (ENABLE = TRUE AUTO_REFRESH = TRUE)  -- enables LIST @stage
    COMMENT             = 'Root stage for all e-commerce raw data. Sub-paths per entity.';



-- Entity-specific sub-stages for granular control and monitoring
CREATE OR REPLACE STAGE RAW.ECOMMERCE.S3_ORDERS_STAGE
    STORAGE_INTEGRATION = S3_ECOMMERCE_INT
    URL                 = 's3://harnek-test-s3-bucket/raw/ecommerce/orders/'
    FILE_FORMAT         = RAW.ECOMMERCE.FF_CSV
    DIRECTORY           = (ENABLE = TRUE AUTO_REFRESH = TRUE)
    COMMENT             = 'Orders entity raw CSV files';

CREATE OR REPLACE STAGE RAW.ECOMMERCE.S3_CUSTOMERS_STAGE
    STORAGE_INTEGRATION = S3_ECOMMERCE_INT
    URL                 = 's3://harnek-test-s3-bucket/raw/ecommerce/customers/'
    FILE_FORMAT         = RAW.ECOMMERCE.FF_JSON
    DIRECTORY           = (ENABLE = TRUE AUTO_REFRESH = TRUE)
    COMMENT             = 'Customers entity raw JSON files (PII — restrict access)';

CREATE OR REPLACE STAGE RAW.ECOMMERCE.S3_ORDER_ITEMS_STAGE
    STORAGE_INTEGRATION = S3_ECOMMERCE_INT
    URL                 = 's3://harnek-test-s3-bucket/raw/ecommerce/order_items/'
    FILE_FORMAT         = RAW.ECOMMERCE.FF_CSV
    DIRECTORY           = (ENABLE = TRUE AUTO_REFRESH = TRUE)
    COMMENT             = 'Order line items raw CSV files';

CREATE OR REPLACE STAGE RAW.ECOMMERCE.S3_PRODUCTS_STAGE
    STORAGE_INTEGRATION = S3_ECOMMERCE_INT
    URL                 = 's3://harnek-test-s3-bucket/raw/ecommerce/products/'
    FILE_FORMAT         = RAW.ECOMMERCE.FF_CSV
    DIRECTORY           = (ENABLE = TRUE AUTO_REFRESH = TRUE)
    COMMENT             = 'Products catalog raw CSV files';

-- ---------------------------------------------------------------------------
-- 4. Verify stage connectivity
--    Run these after setup to confirm S3 access:
-- ---------------------------------------------------------------------------
-- LIST @RAW.ECOMMERCE.S3_ORDERS_STAGE;
-- SELECT * FROM DIRECTORY(@RAW.ECOMMERCE.S3_ORDERS_STAGE);

-- ---------------------------------------------------------------------------
-- 5. COPY INTO vs Snowpipe — Trade-offs & Recommendation
-- ---------------------------------------------------------------------------
-- COPY INTO (used in Tasks — see 04_streams_and_tasks.sql):
--   ✅ Explicit control over load timing and batching
--   ✅ Easy error recovery: FILES= parameter for targeted re-load
--   ✅ Integrates directly with Streams for CDC pattern
--   ✅ Simpler backfill: just re-run the Task or call the procedure
--   ❌ Latency = Task schedule (minimum 1 min, typically 5–15 min)
--
-- Snowpipe (event-driven via SQS notification):
--   ✅ Near-real-time (<1 min latency after S3 PUT)
--   ✅ Fully serverless — no warehouse needed for ingestion
--   ✅ Lower cost for high-throughput micro-batch scenarios
--   ❌ Less control over ordering and error handling
--   ❌ Cannot easily use Streams for CDC (Snowpipe doesn't block Streams)
--   ❌ Harder to backfill — must use REST API with file listings
--
-- RECOMMENDATION:
--   Use Streams + Tasks (this project) when:
--     - You need controlled batching with guaranteed ordering
--     - CDC downstream transforms are required
--     - Batch latency of 5–15 min is acceptable
--   Switch to Snowpipe when:
--     - Near-real-time (<1 min) ingestion is a hard requirement
--     - Volume is very high (millions of files/day)
--     - Downstream is simple COPY without CDC needs
-- ---------------------------------------------------------------------------
