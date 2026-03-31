
  
    

create or replace transient table ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__orders
    
    
    
    as (-- =============================================================================
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



WITH source AS (
    SELECT *
    FROM RAW.ECOMMERCE.orders

    
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
        
    -- Pipeline audit columns injected into every model
    -- Tracks when dbt processed the row, separate from raw load time
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ  AS _dbt_updated_at,
    '7b2625f1-7f51-4f59-afdb-785cf6bf02ae'               AS _dbt_invocation_id,
    'DEV_HARNEKSINGH_staging'                 AS _dbt_schema,
    'stg_raw__orders'                   AS _dbt_model_name

    FROM deduped
    WHERE ORDER_ID IS NOT NULL  -- reject rows with null PK
)

SELECT * FROM renamed
    )
;


  