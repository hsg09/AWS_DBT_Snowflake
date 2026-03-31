-- =============================================================================
-- Model: dim_products.sql
-- Layer:  Marts (Dimension)
-- Purpose:
--   Conformed product dimension with enriched attributes from seeds.
--   Full-refresh (products catalog is small; no complex SCD needed).
-- =============================================================================



WITH products AS (
    SELECT * FROM ANALYTICS.DEV_LOCAL_staging.stg_raw__products
),

-- Enrich with reference data from seed
categories AS (
    SELECT
        category_name,
        parent_category
    FROM ANALYTICS.DEV_LOCAL_seeds.product_categories
),

dim AS (
    SELECT
        -- Surrogate key
        SHA2(
        CONCAT_WS('||', UPPER(TRIM(COALESCE(CAST(product_id AS VARCHAR), '_null_')))),
        256
    )
  AS product_sk,

        -- Business key
        p.product_id,

        -- Product attributes
        p.product_name,
        p.category,
        p.brand,
        COALESCE(c.parent_category, 'Uncategorized')  AS parent_category,

        -- Pricing
        p.unit_cost_usd,
        p.list_price_usd,
        p.margin_pct,
        CASE
            WHEN p.margin_pct >= 50 THEN 'high'
            WHEN p.margin_pct >= 25 THEN 'medium'
            ELSE 'low'
        END                                           AS margin_tier,

        -- Flags
        p.is_active,

        -- Audit
        p._dbt_updated_at
    FROM products AS p
    LEFT JOIN categories AS c
        ON UPPER(TRIM(p.category)) = UPPER(TRIM(c.category_name))
)

SELECT * FROM dim