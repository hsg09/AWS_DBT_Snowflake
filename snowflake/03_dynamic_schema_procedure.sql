-- =============================================================================
-- File: 03_dynamic_schema_procedure.sql
-- Purpose: Snowpark Python stored procedure that:
--          1. Lists files in an S3 stage path
--          2. Infers schema from the first file (INFER_SCHEMA)
--          3. Creates target table dynamically if it doesn't exist
--          4. Handles schema drift: adds new columns via ALTER TABLE
--          5. Logs all activity to AUDIT.CONTROL tables
-- Run as: SYSADMIN (deploy); call as: LOADER
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE ADMIN_WH;
USE DATABASE RAW;
USE SCHEMA ECOMMERCE;

-- ---------------------------------------------------------------------------
-- Grant Snowpark execution privilege
-- ---------------------------------------------------------------------------
GRANT USAGE ON WAREHOUSE LOADER_WH     TO ROLE LOADER;
GRANT EXECUTE TASK                     ON ACCOUNT TO ROLE LOADER;

-- ---------------------------------------------------------------------------
-- The core procedure: INFER_AND_CREATE_TABLE
--
-- Parameters:
--   entity_name    : logical entity (e.g. 'orders') — determines target table name
--   stage_path     : stage name + sub-path (e.g. '@RAW.ECOMMERCE.S3_ORDERS_STAGE')
--   file_format_name : qualified file format name
--   target_db      : target database (default: RAW)
--   target_schema  : target schema (default: ECOMMERCE)
--   run_id         : caller-supplied run identifier for tracing
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE RAW.ECOMMERCE.INFER_AND_CREATE_TABLE(
    ENTITY_NAME        VARCHAR,
    STAGE_PATH         VARCHAR,
    FILE_FORMAT_NAME   VARCHAR,
    TARGET_DB          VARCHAR DEFAULT 'RAW',
    TARGET_SCHEMA      VARCHAR DEFAULT 'ECOMMERCE',
    RUN_ID             VARCHAR DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'infer_and_create_table'
EXECUTE AS CALLER   -- uses caller's privileges; switch to OWNER for tighter control
AS
$$
import json
from datetime import datetime, timezone
from snowflake.snowpark import Session
from snowflake.snowpark.exceptions import SnowparkSQLException

def infer_and_create_table(
    session: Session,
    entity_name: str,
    stage_path: str,
    file_format_name: str,
    target_db: str = 'RAW',
    target_schema: str = 'ECOMMERCE',
    run_id: str = None,
) -> dict:
    """
    Infer schema from S3 file, create or evolve target table, and log outcome.
    Returns a dict with status and details for Task / Airflow to act on.
    """
    result = {
        "entity_name": entity_name,
        "stage_path": stage_path,
        "target_table": f"{target_db}.{target_schema}.{entity_name.upper()}",
        "run_id": run_id or f"manual_{datetime.now(timezone.utc).isoformat()}",
        "columns_added": [],
        "table_created": False,
        "status": "SUCCESS",
        "error": None,
    }

    try:
        target_table_fqn = f"{target_db}.{target_schema}.{entity_name.upper()}"

        # ------------------------------------------------------------------
        # Step 1: Infer schema from the file in the stage
        #         INFER_SCHEMA reads column names and types directly from the
        #         file metadata — works for CSV (with header), JSON, Parquet.
        # ------------------------------------------------------------------
        infer_sql = f"""
            SELECT COLUMN_NAME, TYPE
            FROM TABLE(
                INFER_SCHEMA(
                    LOCATION      => '{stage_path}',
                    FILE_FORMAT   => '{file_format_name}',
                    MAX_RECORDS_PER_FILE => 1000
                )
            )
            ORDER BY ORDER_ID
        """
        inferred_cols = session.sql(infer_sql).collect()

        if not inferred_cols:
            raise ValueError(f"No columns inferred from stage: {stage_path}. "
                             "Ensure files exist and the file format matches.")

        # ------------------------------------------------------------------
        # Step 2: Build column definitions map  {col_name: snowflake_type}
        # ------------------------------------------------------------------
        inferred_map = {row['COLUMN_NAME'].upper(): row['TYPE'] for row in inferred_cols}

        # Always add pipeline metadata columns (idempotent — only if not present)
        pipeline_cols = {
            "_LOADED_AT":         "TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()",
            "_SOURCE_FILE":       "VARCHAR(2000)",
            "_INGESTION_RUN_ID":  "VARCHAR(200)",
        }

        # ------------------------------------------------------------------
        # Step 3: Check if target table already exists
        # ------------------------------------------------------------------
        table_exists_sql = f"""
            SELECT COUNT(*) AS cnt
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_CATALOG  = '{target_db.upper()}'
              AND TABLE_SCHEMA   = '{target_schema.upper()}'
              AND TABLE_NAME     = '{entity_name.upper()}'
        """
        exists_count = session.sql(table_exists_sql).collect()[0]['CNT']

        if exists_count == 0:
            # ---------------------------------------------------------------
            # Step 3a: CREATE TABLE (first-time)
            # ---------------------------------------------------------------
            col_defs = ",\n    ".join(
                f'"{col}" {dtype}' for col, dtype in inferred_map.items()
            )
            # Append pipeline metadata cols
            pipeline_defs = ",\n    ".join(
                f'"{col}" {dtype}' for col, dtype in pipeline_cols.items()
            )
            create_sql = f"""
                CREATE TABLE IF NOT EXISTS {target_table_fqn} (
                    {col_defs},
                    {pipeline_defs}
                )
                CLUSTER BY (_LOADED_AT::DATE)
                COMMENT = 'Raw table for {entity_name}. Created dynamically by INFER_AND_CREATE_TABLE.'
            """
            session.sql(create_sql).collect()
            result["table_created"] = True

            # Log all columns to schema registry
            _upsert_schema_registry(session, target_db, target_schema,
                                    entity_name.upper(), inferred_map, stage_path)

        else:
            # ---------------------------------------------------------------
            # Step 3b: Schema drift detection — compare inferred vs existing
            # ---------------------------------------------------------------
            existing_cols_sql = f"""
                SELECT UPPER(COLUMN_NAME) AS COLUMN_NAME, DATA_TYPE
                FROM {target_db}.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = '{target_schema.upper()}'
                  AND TABLE_NAME   = '{entity_name.upper()}'
            """
            existing_cols = {
                row['COLUMN_NAME']: row['DATA_TYPE']
                for row in session.sql(existing_cols_sql).collect()
            }

            new_cols = {
                col: dtype
                for col, dtype in inferred_map.items()
                if col not in existing_cols
            }

            for col, dtype in new_cols.items():
                # Map inferred type to a safe Snowflake type string
                safe_type = _map_to_snowflake_type(dtype)
                alter_sql = f"""
                    ALTER TABLE {target_table_fqn}
                    ADD COLUMN "{col}" {safe_type}
                    COMMENT 'Added dynamically via schema drift detection'
                """
                session.sql(alter_sql).collect()
                result["columns_added"].append({"column": col, "type": safe_type})

            # Update schema registry with new columns
            if new_cols:
                _upsert_schema_registry(session, target_db, target_schema,
                                        entity_name.upper(), new_cols, stage_path)

    except SnowparkSQLException as e:
        result["status"] = "FAILED"
        result["error"] = str(e)
        # Log failure to task execution log
        _log_task_error(session, "INFER_AND_CREATE_TABLE", str(e))

    except Exception as e:
        result["status"] = "FAILED"
        result["error"] = str(e)
        _log_task_error(session, "INFER_AND_CREATE_TABLE", str(e))

    return result


def _map_to_snowflake_type(inferred_type: str) -> str:
    """
    Map INFER_SCHEMA output types to safe Snowflake column types.
    Default to VARCHAR(16777216) for unknown types — never reject a column.
    """
    type_upper = inferred_type.upper()
    mapping = {
        "TEXT":           "VARCHAR(16777216)",
        "FIXED":          "NUMBER(38,10)",
        "REAL":           "FLOAT",
        "BOOLEAN":        "BOOLEAN",
        "DATE":           "DATE",
        "TIMESTAMP_NTZ":  "TIMESTAMP_NTZ",
        "TIMESTAMP_LTZ":  "TIMESTAMP_LTZ",
        "TIMESTAMP_TZ":   "TIMESTAMP_TZ",
        "VARIANT":        "VARIANT",
        "OBJECT":         "OBJECT",
        "ARRAY":          "ARRAY",
        "BINARY":         "BINARY",
    }
    for key, sf_type in mapping.items():
        if key in type_upper:
            return sf_type
    return "VARCHAR(16777216)"  # safe fallback


def _upsert_schema_registry(session, db, schema, table, col_map, source_file):
    """Insert or update columns in AUDIT.CONTROL.SCHEMA_REGISTRY."""
    for col, dtype in col_map.items():
        upsert_sql = f"""
            MERGE INTO AUDIT.CONTROL.SCHEMA_REGISTRY AS tgt
            USING (
                SELECT
                    '{db}'          AS target_database,
                    '{schema}'      AS target_schema,
                    '{table}'       AS target_table,
                    '{col}'         AS column_name,
                    '{dtype}'       AS column_data_type,
                    TRUE            AS is_active,
                    '{source_file}' AS added_via_file
            ) AS src
            ON  tgt.target_database = src.target_database
            AND tgt.target_schema   = src.target_schema
            AND tgt.target_table    = src.target_table
            AND tgt.column_name     = src.column_name
            WHEN MATCHED THEN UPDATE SET
                tgt.last_seen_at     = CURRENT_TIMESTAMP(),
                tgt.is_active        = TRUE
            WHEN NOT MATCHED THEN INSERT (
                target_database, target_schema, target_table,
                column_name, column_data_type, is_active,
                first_seen_at, last_seen_at, added_via_file
            ) VALUES (
                src.target_database, src.target_schema, src.target_table,
                src.column_name, src.column_data_type, src.is_active,
                CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), src.added_via_file
            )
        """
        session.sql(upsert_sql).collect()


def _log_task_error(session, task_name, error_msg):
    """Best-effort error logging — don't raise on failure."""
    try:
        escaped_error = error_msg.replace("'", "''")
        session.sql(f"""
            INSERT INTO AUDIT.CONTROL.TASK_EXECUTION_LOG
                (task_name, task_schema, task_database, status, error_message)
            VALUES ('{task_name}', 'ECOMMERCE', 'RAW', 'FAILED',
                    '{escaped_error}')
        """).collect()
    except Exception:
        pass  # never mask the original exception
$$;

-- Grant execute to LOADER role
GRANT USAGE ON PROCEDURE RAW.ECOMMERCE.INFER_AND_CREATE_TABLE(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR
) TO ROLE LOADER;

-- ---------------------------------------------------------------------------
-- Test call (run manually after deploying the procedure and placing a CSV in S3)
-- ---------------------------------------------------------------------------
-- CALL RAW.ECOMMERCE.INFER_AND_CREATE_TABLE(
--     'orders',
--     '@RAW.ECOMMERCE.S3_ORDERS_STAGE',
--     'RAW.ECOMMERCE.FF_CSV',
--     'RAW',
--     'ECOMMERCE',
--     'manual_test_001'
-- );
