-- =============================================================================
-- Model: int_orders__enriched.sql
-- Layer:  Intermediate
-- Purpose:
--   Join orders + customers + order_items to create a complete order record.
--   Computes order-level totals, validates referential integrity, and prepares
--   the dataset for mart-level aggregation and fact table population.
--
-- Materialization: ephemeral in dev, view in prod (see dbt_project.yml)
-- =============================================================================



WITH orders AS (
    SELECT * FROM ANALYTICS.DEV_LOCAL_staging.stg_raw__orders
    WHERE NOT is_date_anomaly          -- exclude rows with data quality flags
),

customers AS (
    SELECT
        customer_id,
        country_code,
        customer_segment,
        acquisition_channel,
        customer_created_at
    FROM ANALYTICS.DEV_LOCAL_staging.stg_raw__customers
),

order_items_agg AS (
    -- Aggregate line items to order level for efficient joining
    SELECT
        order_id,
        COUNT(*)                        AS line_item_count,
        SUM(quantity)                   AS total_quantity,
        SUM(line_total_usd)             AS items_total_usd,
        SUM(CASE WHEN discount_pct > 0 THEN line_total_usd END)
                                        AS discounted_items_total_usd,
        AVG(discount_pct)               AS avg_discount_pct,
        MAX(unit_price_usd)             AS max_unit_price_usd,
        COUNT(DISTINCT product_id)      AS distinct_product_count
    FROM ANALYTICS.DEV_LOCAL_staging.stg_raw__order_items
    GROUP BY 1
),

enriched AS (
    SELECT
        -- Order identifiers
        o.order_id,
        o.customer_id,

        -- Customer context (denormalized for analytical convenience)
        c.country_code,
        c.customer_segment,
        c.acquisition_channel,

        -- Order attributes
        o.order_status,
        o.order_date,
        o.shipped_date,
        o.payment_method,
        o.billing_country_code,
        o.is_completed,

        -- Date dimensions (for mart partitioning)
        DATE_TRUNC('month', o.order_date)    AS order_month,
        DATE_TRUNC('year',  o.order_date)    AS order_year,
        DAYOFWEEK(o.order_date)              AS order_day_of_week,
        QUARTER(o.order_date)                AS order_quarter,

        -- Financial
        o.order_amount_usd,
        oi.items_total_usd,
        oi.discounted_items_total_usd,
        oi.avg_discount_pct,
        -- Revenue = use items_total if available (more detailed), else header amount
        COALESCE(oi.items_total_usd, o.order_amount_usd)  AS revenue_usd,

        -- Order composition
        oi.line_item_count,
        oi.total_quantity,
        oi.distinct_product_count,
        oi.max_unit_price_usd,

        -- Fulfillment metrics
        CASE
            WHEN o.order_date IS NOT NULL AND o.shipped_date IS NOT NULL
            THEN DATEDIFF('day', o.order_date, o.shipped_date)
            ELSE NULL
        END                                  AS days_to_ship,

        -- Is customer new vs returning (relative to this order_date)
        CASE
            WHEN c.customer_created_at::DATE = o.order_date
            THEN 'new'
            ELSE 'returning'
        END                                  AS customer_type_at_order,

        -- Data provenance
        o._raw_loaded_at,
        o._source_file,
        o._dbt_updated_at
    FROM orders AS o
    LEFT JOIN customers AS c USING (customer_id)
    LEFT JOIN order_items_agg AS oi USING (order_id)
)

SELECT * FROM enriched