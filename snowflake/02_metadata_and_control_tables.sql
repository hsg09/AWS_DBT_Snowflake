-- =============================================================================
-- File: 02_metadata_and_control_tables.sql
-- Purpose: Create control / metadata tables that enable:
--          - Idempotent file ingestion (no double-loading)
--          - Schema change tracking (schema registry)
--          - Task execution audit trail
--          - Data quality result capture
-- Run as: SYSADMIN
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE ADMIN_WH;
USE DATABASE AUDIT;
USE SCHEMA CONTROL;

-- ---------------------------------------------------------------------------
-- 1. File Ingestion Log
--    One row per file processed. Idempotency check: load only files not
--    present in this table (or in FAILED state for retry).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.CONTROL.FILE_INGESTION_LOG (
    log_id              NUMBER AUTOINCREMENT PRIMARY KEY,
    file_name           VARCHAR(2000)    NOT NULL,
    file_path           VARCHAR(4000)    NOT NULL,   -- full S3 path
    file_size_bytes     NUMBER,
    file_last_modified  TIMESTAMP_NTZ,
    source_schema       VARCHAR(100)     NOT NULL,   -- e.g. ECOMMERCE
    target_table        VARCHAR(200)     NOT NULL,   -- e.g. RAW.ECOMMERCE.ORDERS
    rows_loaded         NUMBER      DEFAULT 0,
    rows_rejected       NUMBER      DEFAULT 0,
    load_status         VARCHAR(20) DEFAULT 'PENDING',
    error_message       VARCHAR(4000),
    started_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    completed_at        TIMESTAMP_NTZ,
    run_id              VARCHAR(100),               -- Airflow run_id or Task name+timestamp
    _created_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _updated_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (source_schema, load_status, DATE(started_at))
COMMENT = 'Master log of every S3 file processed. Drives idempotent load logic.';

-- ---------------------------------------------------------------------------
-- 2. Schema Registry
--    Tracks column-level schema history per table. Used to detect drift
--    and generate ALTER TABLE ADD COLUMN statements automatically.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.CONTROL.SCHEMA_REGISTRY (
    registry_id         NUMBER AUTOINCREMENT PRIMARY KEY,
    target_database     VARCHAR(100)    NOT NULL,
    target_schema       VARCHAR(100)    NOT NULL,
    target_table        VARCHAR(200)    NOT NULL,
    column_name         VARCHAR(200)    NOT NULL,
    column_data_type    VARCHAR(100)    NOT NULL,
    is_active           BOOLEAN DEFAULT TRUE,
    first_seen_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    last_seen_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    added_via_file      VARCHAR(2000),              -- which file introduced this column
    UNIQUE (target_database, target_schema, target_table, column_name)
)
COMMENT = 'Column-level schema history. Drives schema drift detection and ALTER TABLE logic.';

-- ---------------------------------------------------------------------------
-- 3. Task Execution Log
--    Tracks Snowflake Task runs for observability and alerting.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.CONTROL.TASK_EXECUTION_LOG (
    execution_id        NUMBER AUTOINCREMENT PRIMARY KEY,
    task_name           VARCHAR(200)    NOT NULL,
    task_schema         VARCHAR(100)    NOT NULL,
    task_database       VARCHAR(100)    NOT NULL,
    scheduled_at        TIMESTAMP_NTZ,
    started_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    completed_at        TIMESTAMP_NTZ,
    status              VARCHAR(20) DEFAULT 'RUNNING',
    rows_processed      NUMBER DEFAULT 0,
    error_message       VARCHAR(4000),
    query_id            VARCHAR(200),               -- Snowflake query ID for debugging
    execution_seconds   NUMBER AS (DATEDIFF('second', started_at, completed_at))
)
COMMENT = 'Snowflake Task execution audit trail for monitoring and alerting.';

-- ---------------------------------------------------------------------------
-- 4. Data Quality Results
--    Captures dbt test results (or custom test outcomes) for trending.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.CONTROL.DQ_RESULTS (
    result_id           NUMBER AUTOINCREMENT PRIMARY KEY,
    run_id              VARCHAR(200)    NOT NULL,   -- dbt invocation_id or Airflow run_id
    model_name          VARCHAR(300)    NOT NULL,
    test_name           VARCHAR(300)    NOT NULL,
    test_column         VARCHAR(200),
    status              VARCHAR(20)     NOT NULL,   -- 'pass','fail','warn','error'
    failures            NUMBER DEFAULT 0,
    severity            VARCHAR(10) DEFAULT 'error',
    tested_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    environment         VARCHAR(20) DEFAULT 'dev'  -- 'dev','staging','prod'
)
COMMENT = 'dbt and custom test results. Enables data quality trending and alerting.';

-- ---------------------------------------------------------------------------
-- 5. Useful helper views
-- ---------------------------------------------------------------------------

-- Latest status per file (avoids scanning entire log for large tables)
CREATE OR REPLACE VIEW AUDIT.CONTROL.V_FILE_INGESTION_LATEST
    COMMENT = 'Latest ingestion status per file. Idempotency check view.'
AS
SELECT
    file_path,
    source_schema,
    target_table,
    load_status,
    rows_loaded,
    rows_rejected,
    completed_at,
    error_message
FROM AUDIT.CONTROL.FILE_INGESTION_LOG
QUALIFY ROW_NUMBER() OVER (PARTITION BY file_path ORDER BY log_id DESC) = 1;

-- Files pending retry (FAILED older than 1 hour, not already re-submitted)
CREATE OR REPLACE VIEW AUDIT.CONTROL.V_FILES_PENDING_RETRY
    COMMENT = 'Files in FAILED state eligible for retry after 1 hour cool-off.'
AS
SELECT * FROM AUDIT.CONTROL.V_FILE_INGESTION_LATEST
WHERE load_status = 'FAILED'
  AND DATEDIFF('hour', completed_at, CURRENT_TIMESTAMP()) >= 1;

-- Schema drift summary: columns present in registry but not yet in actual table
-- (populated by dynamic schema procedure — see 03_dynamic_schema_procedure.sql)
CREATE OR REPLACE VIEW AUDIT.CONTROL.V_SCHEMA_DRIFT_REPORT
    COMMENT = 'All columns known to the schema registry; cross-reference with IS_* views for drift.'
AS
SELECT
    target_database,
    target_schema,
    target_table,
    column_name,
    column_data_type,
    first_seen_at,
    added_via_file
FROM AUDIT.CONTROL.SCHEMA_REGISTRY
WHERE is_active = TRUE
ORDER BY target_table, first_seen_at;

-- ---------------------------------------------------------------------------
-- 6. Grants on control tables to loader and transformer roles
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA AUDIT.CONTROL TO ROLE LOADER;
GRANT SELECT                  ON ALL TABLES IN SCHEMA AUDIT.CONTROL TO ROLE TRANSFORMER;
GRANT SELECT                  ON ALL VIEWS  IN SCHEMA AUDIT.CONTROL TO ROLE TRANSFORMER;
GRANT SELECT                  ON ALL VIEWS  IN SCHEMA AUDIT.CONTROL TO ROLE ANALYST;
