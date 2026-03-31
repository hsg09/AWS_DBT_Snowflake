-- =============================================================================
-- Model: stg_raw__products.sql  (proper product staging model)
-- Layer:  Staging
-- Source: RAW.ECOMMERCE.PRODUCTS
-- =============================================================================



WITH source AS (
    SELECT *
    FROM RAW.ECOMMERCE.products

    
    WHERE _LOADED_AT >= (
        SELECT DATEADD('day', -3,
                       COALESCE(MAX(_raw_loaded_at), '1970-01-01'::TIMESTAMP_NTZ))
        FROM ANALYTICS.DEV_LOCAL_staging.stg_raw__products
    )
    
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

        
    -- Pipeline audit columns injected into every model
    -- Tracks when dbt processed the row, separate from raw load time
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ  AS _dbt_updated_at,
    '7207e3e0-227f-4c5b-a3d5-e28cb827c133'               AS _dbt_invocation_id,
    'DEV_LOCAL_staging'                 AS _dbt_schema,
    'stg_raw__products'                   AS _dbt_model_name

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