-- =============================================================================
-- Model: fct_orders.sql
-- Layer:  Marts (Fact)
-- Purpose:
--   Production fact table for orders — the primary analytical grain.
--   One row per order (order_id is the grain).
--   Uses surrogate key, incremental merge strategy, and clustering.
--
-- Surrogate key: SHA2 hash of order_id (deterministic, collision-resistant)
-- Grain: one row per order_id
-- Relationships: FK to dim_customers, dim_products (via order_items)
-- =============================================================================

{{
  config(
    materialized         = 'incremental',
    unique_key           = 'order_sk',
    incremental_strategy = 'merge',
    cluster_by           = ['order_date_day', 'customer_sk'],
    on_schema_change     = 'append_new_columns',
    tags                 = ['fact', 'orders', 'marts'],
    post_hook            = [
      "COMMENT ON TABLE {{ this }} IS 'Fact table: one row per order. Grain = order_id. Incremental merge on order_sk.'"
    ],
    meta = {
      'owner':       'data-engineering',
      'sla':         '4 hours after raw load',
      'business_owner': 'revenue-analytics'
    }
  )
}}

WITH enriched AS (
    SELECT *
    FROM {{ ref('int_orders__enriched') }}

    {% if is_incremental() %}
    WHERE _raw_loaded_at >= (
        SELECT DATEADD('day', -{{ var('incremental_lookback_days', 3) }},
                       COALESCE(MAX(_raw_loaded_at), '1970-01-01'::TIMESTAMP_NTZ))
        FROM {{ this }}
    )
    {% endif %}
),

customers AS (
    SELECT customer_id, customer_sk
    FROM {{ ref('dim_customers') }}
    WHERE is_current = TRUE  -- SCD Type 2: only join to current record
),

final AS (
    SELECT
        -- Surrogate key (deterministic hash — safe for incremental merge)
        {{ generate_surrogate_key(['e.order_id']) }}     AS order_sk,

        -- Business keys (preserved for debugging and joins)
        e.order_id,
        e.customer_id,

        -- Foreign key to dim_customers
        c.customer_sk,

        -- Date dimensions (integer keys for star schema compatibility)
        e.order_date                                     AS order_date_day,
        TO_CHAR(e.order_date, 'YYYYMMDD')::INTEGER       AS order_date_key,
        e.order_month,
        e.order_year,
        e.order_quarter,
        e.order_day_of_week,

        -- Order attributes
        e.order_status,
        e.payment_method,
        e.billing_country_code,
        e.country_code                                   AS customer_country_code,
        e.customer_segment,
        e.acquisition_channel,
        e.customer_type_at_order,                        -- 'new' or 'returning'
        e.is_completed,

        -- Financial measures
        e.order_amount_usd,
        e.revenue_usd,
        e.items_total_usd,
        e.discounted_items_total_usd,
        e.avg_discount_pct,

        -- Derived measures
        COALESCE(e.revenue_usd, 0) - COALESCE(e.discounted_items_total_usd, 0)
                                                         AS gross_margin_usd,

        -- Order composition measures
        e.line_item_count,
        e.total_quantity,
        e.distinct_product_count,
        e.max_unit_price_usd,

        -- Fulfillment measures
        e.days_to_ship,
        e.shipped_date,

        -- Flags
        CASE WHEN e.order_status = 'cancelled' THEN 1 ELSE 0 END  AS is_cancelled,
        CASE WHEN e.order_status = 'refunded'  THEN 1 ELSE 0 END  AS is_refunded,

        -- Audit
        e._raw_loaded_at,
        CURRENT_TIMESTAMP()                              AS _dbt_updated_at

    FROM enriched AS e
    LEFT JOIN customers AS c USING (customer_id)
)

SELECT * FROM final
