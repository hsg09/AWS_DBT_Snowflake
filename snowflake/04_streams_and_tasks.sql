-- =============================================================================
-- File: 04_streams_and_tasks.sql
-- Purpose: Define Snowflake Streams (CDC capture) on raw tables and Tasks to
--          orchestrate ingestion and propagation. Implements a CDC-style
--          incremental pattern without external orchestration dependency.
-- Run as: SYSADMIN
--
-- Architecture:
--   [S3 Stage] → COPY INTO raw Tables
--              → Streams (capture INSERTs)
--              → Tasks (propagate to staging layer pre-materialization)
--   dbt handles staging → intermediate → marts on top of the raw tables.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE ADMIN_WH;
USE DATABASE RAW;
USE SCHEMA ECOMMERCE;

-- ---------------------------------------------------------------------------
-- Pre-requisite: ensure raw tables exist (created by dynamic procedure)
-- These DDLs are fallback / bootstrap — the real creation is dynamic.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW.ECOMMERCE.ORDERS (
    ORDER_ID            VARCHAR(100),
    CUSTOMER_ID         VARCHAR(100),
    ORDER_STATUS        VARCHAR(50),
    ORDER_AMOUNT        NUMBER(18, 2),
    ORDER_DATE          DATE,
    SHIPPED_DATE        DATE,
    PAYMENT_METHOD      VARCHAR(50),
    BILLING_COUNTRY     VARCHAR(100),
    -- Schema drift columns added automatically by procedure
    _LOADED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE        VARCHAR(2000),
    _INGESTION_RUN_ID   VARCHAR(200)
)
CLUSTER BY (_LOADED_AT::DATE)
COMMENT = 'Raw orders. DO NOT modify manually — managed by INFER_AND_CREATE_TABLE.';

CREATE TABLE IF NOT EXISTS RAW.ECOMMERCE.CUSTOMERS (
    CUSTOMER_ID         VARCHAR(100),
    RAW_PAYLOAD         VARIANT,        -- JSON loaded as VARIANT
    EMAIL               VARCHAR(500),
    PHONE               VARCHAR(50),
    COUNTRY             VARCHAR(100),
    CREATED_AT          TIMESTAMP_NTZ,
    _LOADED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE        VARCHAR(2000),
    _INGESTION_RUN_ID   VARCHAR(200)
)
COMMENT = 'Raw customers — JSON stored as VARIANT for flexible schema evolution.';

CREATE TABLE IF NOT EXISTS RAW.ECOMMERCE.ORDER_ITEMS (
    ORDER_ITEM_ID       VARCHAR(100),
    ORDER_ID            VARCHAR(100),
    PRODUCT_ID          VARCHAR(100),
    QUANTITY            NUMBER(10),
    UNIT_PRICE          NUMBER(18, 4),
    DISCOUNT_PCT        NUMBER(5, 2),
    _LOADED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE        VARCHAR(2000),
    _INGESTION_RUN_ID   VARCHAR(200)
)
CLUSTER BY (_LOADED_AT::DATE)
COMMENT = 'Raw order line items.';

CREATE TABLE IF NOT EXISTS RAW.ECOMMERCE.PRODUCTS (
    PRODUCT_ID          VARCHAR(100),
    PRODUCT_NAME        VARCHAR(1000),
    CATEGORY            VARCHAR(200),
    BRAND               VARCHAR(200),
    UNIT_COST           NUMBER(18, 4),
    LIST_PRICE          NUMBER(18, 4),
    IS_ACTIVE           BOOLEAN,
    _LOADED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE        VARCHAR(2000),
    _INGESTION_RUN_ID   VARCHAR(200)
)
COMMENT = 'Raw products catalog.';

-- ---------------------------------------------------------------------------
-- 1. COPY INTO Stored Procedure (batch load + idempotency check)
--    Called by the root ingestion Task.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE(
    ENTITY_NAME      VARCHAR,
    STAGE_PATH       VARCHAR,
    FILE_FORMAT_NAME VARCHAR,
    RUN_ID           VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'load_entity'
EXECUTE AS CALLER
AS
$$
import json
from datetime import datetime, timezone
from snowflake.snowpark import Session

def load_entity(
    session: Session,
    entity_name: str,
    stage_path: str,
    file_format_name: str,
    run_id: str
) -> dict:
    """
    1. List files in stage
    2. Filter out already-processed files (idempotency)
    3. Run COPY INTO for new files
    4. Log outcome to FILE_INGESTION_LOG
    """
    result = {"entity": entity_name, "files_processed": 0,
              "rows_loaded": 0, "errors": [], "status": "SUCCESS"}

    target_table = f"RAW.ECOMMERCE.{entity_name.upper()}"

    # Get all files currently in the stage
    files_sql = f"LIST {stage_path}"
    all_files = session.sql(files_sql).collect()

    # Get already-successfully-loaded files from audit log
    loaded_sql = f"""
        SELECT file_path FROM AUDIT.CONTROL.FILE_INGESTION_LOG
        WHERE target_table = '{target_table}'
          AND load_status  = 'SUCCESS'
    """
    loaded_files = {row['FILE_PATH'] for row in session.sql(loaded_sql).collect()}

    new_files = [
        row['name'] for row in all_files
        if row['name'] not in loaded_files
    ]

    if not new_files:
        result["status"] = "NO_NEW_FILES"
        return result

    for file_path in new_files:
        file_name = file_path.split('/')[-1]
        # Log as IN_PROGRESS
        session.sql(f"""
            INSERT INTO AUDIT.CONTROL.FILE_INGESTION_LOG
                (file_name, file_path, source_schema, target_table,
                 load_status, started_at, run_id)
            VALUES ('{file_name}', '{file_path}', 'ECOMMERCE', '{target_table}',
                    'IN_PROGRESS', CURRENT_TIMESTAMP(), '{run_id}')
        """).collect()

        try:
            copy_result = session.sql(f"""
                COPY INTO {target_table}
                FROM '{stage_path}{file_name}'
                FILE_FORMAT = (FORMAT_NAME = '{file_format_name}')
                ON_ERROR = 'CONTINUE'
                MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
                PURGE = FALSE   -- keep files in S3 for replay/audit
                FORCE = FALSE   -- skip already-loaded files (Snowflake internal tracking)
            """).collect()

            rows_loaded = sum(int(r.as_dict().get('rows_loaded', 0)) for r in copy_result)
            rows_rejected = sum(int(r.as_dict().get('rows_rejected_with_errors', 0)) for r in copy_result)

            session.sql(f"""
                UPDATE AUDIT.CONTROL.FILE_INGESTION_LOG
                SET load_status  = 'SUCCESS',
                    rows_loaded  = {rows_loaded},
                    rows_rejected= {rows_rejected},
                    completed_at = CURRENT_TIMESTAMP(),
                    _updated_at  = CURRENT_TIMESTAMP()
                WHERE file_path  = '{file_path}'
                  AND run_id     = '{run_id}'
                  AND load_status= 'IN_PROGRESS'
            """).collect()

            result["files_processed"] += 1
            result["rows_loaded"] += rows_loaded

        except Exception as e:
            escaped_error = str(e)[:3900].replace("'", "''")
            session.sql(f"""
                UPDATE AUDIT.CONTROL.FILE_INGESTION_LOG
                SET load_status   = 'FAILED',
                    error_message = '{escaped_error}',
                    completed_at  = CURRENT_TIMESTAMP()
                WHERE file_path   = '{file_path}'
                  AND run_id      = '{run_id}'
                  AND load_status = 'IN_PROGRESS'
            """).collect()
            result["errors"].append({"file": file_name, "error": str(e)[:500]})
            result["status"] = "PARTIAL_FAILURE"

    return result
$$;

GRANT USAGE ON PROCEDURE RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR
) TO ROLE LOADER;

-- ---------------------------------------------------------------------------
-- 2. Streams on raw tables (append-only; captures INSERTs only — new rows)
--    APPEND_ONLY = TRUE is more efficient when we only ever INSERT into raw.
-- ---------------------------------------------------------------------------
CREATE STREAM IF NOT EXISTS RAW.ECOMMERCE.STREAM_ORDERS
    ON TABLE RAW.ECOMMERCE.ORDERS
    APPEND_ONLY = TRUE
    COMMENT = 'CDC stream on raw ORDERS. Consumed by dbt incremental models.';

CREATE STREAM IF NOT EXISTS RAW.ECOMMERCE.STREAM_CUSTOMERS
    ON TABLE RAW.ECOMMERCE.CUSTOMERS
    APPEND_ONLY = TRUE
    COMMENT = 'CDC stream on raw CUSTOMERS.';

CREATE STREAM IF NOT EXISTS RAW.ECOMMERCE.STREAM_ORDER_ITEMS
    ON TABLE RAW.ECOMMERCE.ORDER_ITEMS
    APPEND_ONLY = TRUE
    COMMENT = 'CDC stream on raw ORDER_ITEMS.';

CREATE STREAM IF NOT EXISTS RAW.ECOMMERCE.STREAM_PRODUCTS
    ON TABLE RAW.ECOMMERCE.PRODUCTS
    APPEND_ONLY = TRUE
    COMMENT = 'CDC stream on raw PRODUCTS.';

-- ---------------------------------------------------------------------------
-- 3. Snowflake Tasks: orchestrated ingestion pipeline
--
--    Task DAG:
--      TASK_INFER_SCHEMA (manual/scheduled)
--          → TASK_LOAD_ORDERS
--          → TASK_LOAD_CUSTOMERS
--          → TASK_LOAD_ORDER_ITEMS
--          → TASK_LOAD_PRODUCTS
--          → TASK_TRIGGER_DBT_STAGING  (calls dbt via Airflow webhook or shell)
--
--    EVERY 15 MINUTES chosen as default; Airflow overrides this (see DAG).
-- ---------------------------------------------------------------------------

-- Root task: schema inference + table creation (runs once on schedule)
CREATE OR REPLACE TASK RAW.ECOMMERCE.TASK_INFER_SCHEMA
    WAREHOUSE  = LOADER_WH
    SCHEDULE   = '15 MINUTES'
    COMMENT    = 'Root task: infers schema and creates/evolves raw tables'
AS
BEGIN
    CALL RAW.ECOMMERCE.INFER_AND_CREATE_TABLE('orders',     '@RAW.ECOMMERCE.S3_ORDERS_STAGE',     'RAW.ECOMMERCE.FF_CSV',     'RAW', 'ECOMMERCE', 'task_infer_schema');
    CALL RAW.ECOMMERCE.INFER_AND_CREATE_TABLE('customers',  '@RAW.ECOMMERCE.S3_CUSTOMERS_STAGE',  'RAW.ECOMMERCE.FF_JSON',    'RAW', 'ECOMMERCE', 'task_infer_schema');
    CALL RAW.ECOMMERCE.INFER_AND_CREATE_TABLE('order_items','@RAW.ECOMMERCE.S3_ORDER_ITEMS_STAGE','RAW.ECOMMERCE.FF_CSV',     'RAW', 'ECOMMERCE', 'task_infer_schema');
    CALL RAW.ECOMMERCE.INFER_AND_CREATE_TABLE('products',   '@RAW.ECOMMERCE.S3_PRODUCTS_STAGE',   'RAW.ECOMMERCE.FF_CSV',     'RAW', 'ECOMMERCE', 'task_infer_schema');
END;

-- Child tasks: entity-level COPY INTO (run after root completes)
CREATE OR REPLACE TASK RAW.ECOMMERCE.TASK_LOAD_ORDERS
    WAREHOUSE   = LOADER_WH
    COMMENT     = 'Load new orders CSV files from S3 into RAW.ECOMMERCE.ORDERS'
    AFTER       RAW.ECOMMERCE.TASK_INFER_SCHEMA
AS
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE(
    'orders',
    '@RAW.ECOMMERCE.S3_ORDERS_STAGE/',
    'RAW.ECOMMERCE.FF_CSV',
    CONCAT('task_load_orders_', TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS'))
);

CREATE OR REPLACE TASK RAW.ECOMMERCE.TASK_LOAD_CUSTOMERS
    WAREHOUSE   = LOADER_WH
    COMMENT     = 'Load new customers JSON files from S3 into RAW.ECOMMERCE.CUSTOMERS'
    AFTER       RAW.ECOMMERCE.TASK_INFER_SCHEMA
AS
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE(
    'customers',
    '@RAW.ECOMMERCE.S3_CUSTOMERS_STAGE/',
    'RAW.ECOMMERCE.FF_JSON',
    CONCAT('task_load_customers_', TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS'))
);

CREATE OR REPLACE TASK RAW.ECOMMERCE.TASK_LOAD_ORDER_ITEMS
    WAREHOUSE   = LOADER_WH
    AFTER       RAW.ECOMMERCE.TASK_INFER_SCHEMA
AS
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE(
    'order_items',
    '@RAW.ECOMMERCE.S3_ORDER_ITEMS_STAGE/',
    'RAW.ECOMMERCE.FF_CSV',
    CONCAT('task_load_order_items_', TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS'))
);

CREATE OR REPLACE TASK RAW.ECOMMERCE.TASK_LOAD_PRODUCTS
    WAREHOUSE   = LOADER_WH
    AFTER       RAW.ECOMMERCE.TASK_INFER_SCHEMA
AS
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE(
    'products',
    '@RAW.ECOMMERCE.S3_PRODUCTS_STAGE/',
    'RAW.ECOMMERCE.FF_CSV',
    CONCAT('task_load_products_', TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS'))
);

-- ---------------------------------------------------------------------------
-- 4. Resume tasks (tasks are created SUSPENDED by default)
--    NOTE: In production, Airflow controls execution. Only resume the root
--    task here if you want Snowflake Tasks to run autonomously (no Airflow).
-- ---------------------------------------------------------------------------
-- ALTER TASK RAW.ECOMMERCE.TASK_LOAD_PRODUCTS    RESUME;
-- ALTER TASK RAW.ECOMMERCE.TASK_LOAD_ORDER_ITEMS RESUME;
-- ALTER TASK RAW.ECOMMERCE.TASK_LOAD_CUSTOMERS   RESUME;
-- ALTER TASK RAW.ECOMMERCE.TASK_LOAD_ORDERS      RESUME;
-- ALTER TASK RAW.ECOMMERCE.TASK_INFER_SCHEMA     RESUME;  -- LAST: starts the DAG

-- ---------------------------------------------------------------------------
-- 5. Monitoring queries
-- ---------------------------------------------------------------------------
-- Task execution history (last 24h):
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
--     SCHEDULED_TIME_RANGE_START => DATEADD('hour', -24, CURRENT_TIMESTAMP()),
--     TASK_NAME => 'TASK_INFER_SCHEMA'
-- )) ORDER BY SCHEDULED_TIME DESC;

-- Stream lag monitoring (how many bytes still pending in each stream):
-- SHOW STREAMS IN SCHEMA RAW.ECOMMERCE;
