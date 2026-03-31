
  
    

create or replace transient table ANALYTICS.DEV_HARNEKSINGH_marts.fct_orders
    
    
    
    as (select * from (
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



WITH  __dbt__cte__int_orders__enriched as (
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
    SELECT * FROM ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__orders
    WHERE NOT is_date_anomaly          -- exclude rows with data quality flags
),

customers AS (
    SELECT
        customer_id,
        country_code,
        customer_segment,
        acquisition_channel,
        customer_created_at
    FROM ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__customers
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
    FROM ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__order_items
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
), enriched AS (
    SELECT *
    FROM __dbt__cte__int_orders__enriched

    
),

customers AS (
    SELECT customer_id, customer_sk
    FROM ANALYTICS.DEV_HARNEKSINGH_marts.dim_customers
    WHERE is_current = TRUE  -- SCD Type 2: only join to current record
),

final AS (
    SELECT
        -- Surrogate key (deterministic hash — safe for incremental merge)
        SHA2(
        CONCAT_WS('||', UPPER(TRIM(COALESCE(CAST(e.order_id AS VARCHAR), '_null_')))),
        256
    )
     AS order_sk,

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
        )
        order by (
            order_date_day, customer_sk
        )
    )
;

alter table ANALYTICS.DEV_HARNEKSINGH_marts.fct_orders cluster by (order_date_day, customer_sk);
  