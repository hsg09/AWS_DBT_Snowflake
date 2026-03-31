-- =============================================================================
-- Model: stg_raw__orders.sql
-- Layer:  Staging
-- Source: RAW.ECOMMERCE.ORDERS  (loaded via dynamic COPY INTO procedure)
-- Purpose:
--   - Cast raw varchar columns to proper types
--   - Deduplicate (last write wins per order_id, ordered by _loaded_at)
--   - Standardize column names and null handling
--   - Apply incremental load (only process new rows from the stream)
--
-- Materialization:
--   - View in dev (fast, no storage cost)
--   - Table in prod (materialised for downstream joins, easier to test freshness)
-- =============================================================================

{{
  config(
    materialized  = 'incremental',
    unique_key    = 'order_id',
    incremental_strategy = 'merge',
    on_schema_change = 'append_new_columns',
    tags          = ['staging', 'orders'],
    meta          = {
      'owner': 'data-engineering',
      'contains_pii': false,
      'sla': '2 hours after raw load'
    }
  )
}}

WITH source AS (
    SELECT *
    FROM {{ source('raw_ecommerce', 'orders') }}

    {% if is_incremental() %}
    -- Only process rows newer than the latest record in this model
    -- Use lookback window to catch late-arriving records
    WHERE _LOADED_AT >= (
        SELECT DATEADD('day', -{{ var('incremental_lookback_days', 3) }},
                       COALESCE(MAX(_raw_loaded_at), '1970-01-01'::TIMESTAMP_NTZ))
        FROM {{ this }}
    )
    {% endif %}
),

-- Deduplication: keep the latest version of each order_id
-- Real-world scenario: same order file may be re-delivered; keep last-write-wins.
deduped AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ORDER_ID
        ORDER BY _LOADED_AT DESC
    ) = 1
),

renamed AS (
    SELECT
        -- Primary key (preserved as-is; surrogate key generated in marts layer)
        ORDER_ID::VARCHAR(100)          AS order_id,

        -- Foreign keys
        CUSTOMER_ID::VARCHAR(100)       AS customer_id,

        -- Status: normalize to lowercase
        LOWER(TRIM(ORDER_STATUS))       AS order_status,

        -- Financials
        CAST(ORDER_AMOUNT AS NUMBER(18, 2)) AS order_amount_usd,

        -- Dates: use TRY_TO_DATE to avoid hard failures on malformed values
        TRY_TO_DATE(ORDER_DATE)         AS order_date,
        TRY_TO_DATE(SHIPPED_DATE)       AS shipped_date,

        -- Categorical
        LOWER(TRIM(PAYMENT_METHOD))                     AS payment_method,
        UPPER(TRIM(BILLING_COUNTRY))                    AS billing_country_code,

        -- Derived flags
        CASE
            WHEN LOWER(TRIM(ORDER_STATUS)) IN ('delivered', 'completed')
            THEN TRUE ELSE FALSE
        END                                             AS is_completed,

        CASE
            WHEN SHIPPED_DATE IS NOT NULL
             AND TRY_TO_DATE(SHIPPED_DATE) < TRY_TO_DATE(ORDER_DATE)
            THEN TRUE ELSE FALSE
        END                                             AS is_date_anomaly,

        -- Pipeline audit columns
        _LOADED_AT                                      AS _raw_loaded_at,
        _SOURCE_FILE                                    AS _source_file,
        _INGESTION_RUN_ID                               AS _ingestion_run_id,

        -- dbt audit columns (macro-generated)
        {{ add_audit_columns() }}
    FROM deduped
    WHERE ORDER_ID IS NOT NULL  -- reject rows with null PK
)

SELECT * FROM renamed
