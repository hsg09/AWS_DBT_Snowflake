-- =============================================================================
-- Model: stg_raw__products.sql  (proper product staging model)
-- Layer:  Staging
-- Source: RAW.ECOMMERCE.PRODUCTS
-- =============================================================================

{{
  config(
    materialized  = 'incremental',
    unique_key    = 'product_id',
    incremental_strategy = 'merge',
    on_schema_change = 'append_new_columns',
    tags          = ['staging', 'products']
  )
}}

WITH source AS (
    SELECT *
    FROM {{ source('raw_ecommerce', 'products') }}

    {% if is_incremental() %}
    WHERE _LOADED_AT >= (
        SELECT DATEADD('day', -{{ var('incremental_lookback_days', 3) }},
                       COALESCE(MAX(_raw_loaded_at), '1970-01-01'::TIMESTAMP_NTZ))
        FROM {{ this }}
    )
    {% endif %}
),

cleaned AS (
    SELECT
        PRODUCT_ID::VARCHAR(100)                        AS product_id,
        TRIM(PRODUCT_NAME::VARCHAR(1000))               AS product_name,
        UPPER(TRIM(CATEGORY::VARCHAR(200)))             AS category,
        UPPER(TRIM(BRAND::VARCHAR(200)))                AS brand,
        CAST(UNIT_COST AS NUMBER(18, 4))            AS unit_cost_usd,
        CAST(LIST_PRICE AS NUMBER(18, 4))           AS list_price_usd,

        -- Derived: margin percentage
        CASE
            WHEN CAST(LIST_PRICE AS NUMBER(18, 4)) > 0
            THEN ROUND(
                (CAST(LIST_PRICE AS NUMBER(18, 4)) - CAST(UNIT_COST AS NUMBER(18, 4)))
                / CAST(LIST_PRICE AS NUMBER(18, 4)) * 100, 2
            )
            ELSE NULL
        END                                             AS margin_pct,

        COALESCE(TRY_CAST(IS_ACTIVE AS BOOLEAN), TRUE)  AS is_active,

        _LOADED_AT                                      AS _raw_loaded_at,
        _SOURCE_FILE                                    AS _source_file,
        _INGESTION_RUN_ID                               AS _ingestion_run_id,

        {{ add_audit_columns() }}
    FROM source
    WHERE PRODUCT_ID IS NOT NULL
),

deduped AS (
    SELECT *
    FROM cleaned
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY product_id
        ORDER BY _raw_loaded_at DESC
    ) = 1
)

SELECT * FROM deduped
