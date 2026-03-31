-- =============================================================================
-- Model: stg_raw__order_items.sql
-- Layer:  Staging
-- Source: RAW.ECOMMERCE.ORDER_ITEMS
-- Purpose:
--   - Clean and standardise raw order items
--   - Deduplicate using last-write-wins (ordered by _loaded_at)
--   - Cast columns to correct data types
--
-- Materialization:
--   - Configured in dbt_project.yml (view in dev, table in prod)
-- =============================================================================



WITH source AS (
    SELECT *
    FROM RAW.ECOMMERCE.order_items

    
    WHERE _LOADED_AT >= (
        SELECT DATEADD('day', -3,
                       COALESCE(MAX(_raw_loaded_at), '1970-01-01'::TIMESTAMP_NTZ))
        FROM ANALYTICS.DEV_LOCAL_staging.stg_raw__order_items
    )
    
),

deduped AS (
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ORDER_ITEM_ID
        ORDER BY _LOADED_AT DESC
    ) = 1
),

renamed AS (
    SELECT
        -- Primary key
        ORDER_ITEM_ID::VARCHAR(100)                     AS order_item_id,

        -- Foreign keys
        ORDER_ID::VARCHAR(100)                          AS order_id,
        PRODUCT_ID::VARCHAR(100)                        AS product_id,

        -- Metrics
        CAST(QUANTITY AS INTEGER)                       AS quantity,
        (CAST(QUANTITY AS INTEGER) * CAST(UNIT_PRICE AS NUMBER(18, 2))) AS line_total_usd,
        CAST(DISCOUNT_PCT AS NUMBER(5, 2))              AS discount_pct,
        CAST(UNIT_PRICE AS NUMBER(18, 2))               AS unit_price_usd,

        -- Pipeline audit columns
        _LOADED_AT                                      AS _raw_loaded_at
    FROM deduped
    WHERE ORDER_ITEM_ID IS NOT NULL
)

SELECT * FROM renamed