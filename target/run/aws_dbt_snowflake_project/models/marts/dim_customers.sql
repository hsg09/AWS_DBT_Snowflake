
  
    

create or replace transient table ANALYTICS.DEV_LOCAL_marts.dim_customers
    
    
    
    as (select * from (
            -- =============================================================================
-- Model: dim_customers.sql
-- Layer:  Marts (Dimension)
-- Purpose:
--   Customer conformed dimension combining profile data (from staging)
--   with computed behavioural metrics (from intermediate LTV model).
--   SCD Type 2 handled via snapshot (snap_customers) — this model reads the
--   latest snapshot record per customer for the "current" view.
--
-- Grain: one row per customer (current state)
-- SCD Type 2: is_current / valid_from / valid_to via snapshot reference
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
),  __dbt__cte__int_customers__lifetime_value as (
-- =============================================================================
-- Model: int_customers__lifetime_value.sql
-- Layer:  Intermediate
-- Purpose:
--   Compute per-customer lifetime value (LTV), order history, and RFM metrics.
--   RFM = Recency, Frequency, Monetary (classic e-commerce customer scoring).
--   Used by dim_customers mart as the analytical backbone.
-- =============================================================================



WITH orders AS (
    SELECT
        customer_id,
        order_id,
        order_date,
        order_status,
        revenue_usd,
        days_to_ship,
        is_completed
    FROM __dbt__cte__int_orders__enriched
    WHERE order_date BETWEEN '2020-01-01'::DATE
                         AND '2099-12-31'::DATE
),

customer_metrics AS (
    SELECT
        customer_id,

        -- Order volume
        COUNT(order_id)                                         AS total_orders,
        COUNT(CASE WHEN is_completed THEN 1 END)                AS completed_orders,
        COUNT(CASE WHEN order_status = 'cancelled' THEN 1 END)  AS cancelled_orders,

        -- Monetary value
        SUM(CASE WHEN is_completed THEN revenue_usd ELSE 0 END) AS lifetime_value_usd,
        AVG(CASE WHEN is_completed THEN revenue_usd END)        AS avg_order_value_usd,
        MAX(revenue_usd)                                        AS max_order_value_usd,

        -- Recency & Frequency
        MIN(order_date)                                         AS first_order_date,
        MAX(order_date)                                         AS last_order_date,
        DATEDIFF('day', MIN(order_date), MAX(order_date))       AS customer_tenure_days,
        DATEDIFF('day', MAX(order_date), CURRENT_DATE())        AS days_since_last_order,

        -- Fulfillment quality
        AVG(days_to_ship)                                       AS avg_days_to_ship

    FROM orders
    GROUP BY 1
),

rfm_scored AS (
    SELECT
        *,

        -- Recency score: 5 = ordered very recently, 1 = long ago
        NTILE(5) OVER (ORDER BY days_since_last_order ASC)  AS recency_score,

        -- Frequency score: 5 = very frequent buyer
        NTILE(5) OVER (ORDER BY total_orders DESC)          AS frequency_score,

        -- Monetary score: 5 = highest LTV
        NTILE(5) OVER (ORDER BY lifetime_value_usd DESC)    AS monetary_score

    FROM customer_metrics
),

rfm_segmented AS (
    SELECT
        *,
        (recency_score + frequency_score + monetary_score)  AS rfm_score,
        CASE
            WHEN recency_score >= 4 AND frequency_score >= 4 AND monetary_score >= 4
                THEN 'champions'
            WHEN recency_score >= 3 AND frequency_score >= 3
                THEN 'loyal'
            WHEN recency_score >= 4 AND frequency_score <= 2
                THEN 'new_customer'
            WHEN recency_score <= 2 AND frequency_score >= 3
                THEN 'at_risk'
            WHEN recency_score <= 2 AND monetary_score >= 4
                THEN 'cant_lose'
            WHEN recency_score <= 1
                THEN 'lost'
            ELSE 'potential_loyalist'
        END                                                  AS rfm_segment,

        -- Cancellation rate
        ROUND(cancelled_orders / NULLIF(total_orders, 0) * 100, 2) AS cancellation_rate_pct

    FROM rfm_scored
)

SELECT * FROM rfm_segmented
), customer_snapshot AS (
    -- Read from SCD Type 2 snapshot (see snapshots/snap_customers.sql)
    -- DBT_VALID_TO IS NULL = current record
    SELECT
        MD5(customer_id)        AS customer_sk,     -- surrogate key from snapshot
        customer_id,
        email,
        first_name,
        last_name,
        country_code,
        customer_segment,
        acquisition_channel,
        is_email_verified,
        customer_created_at,
        dbt_valid_from          AS valid_from,
        dbt_valid_to            AS valid_to,
        dbt_valid_to IS NULL    AS is_current,
        dbt_updated_at          AS snapshot_updated_at
    FROM ANALYTICS.snapshots.snap_customers
),

-- Only current records (for the main dim table)
current_customers AS (
    SELECT * FROM customer_snapshot WHERE is_current = TRUE
),

-- Join with LTV / behavioural metrics from intermediate layer
ltv AS (
    SELECT * FROM __dbt__cte__int_customers__lifetime_value
),

dim AS (
    SELECT
        -- Surrogate key
        c.customer_sk,

        -- Business key
        c.customer_id,

        -- Profile (PII masked at source — safe to pass through)
        c.email,
        c.first_name,
        c.last_name,
        c.country_code,
        c.customer_segment,
        c.acquisition_channel,
        c.is_email_verified,
        c.customer_created_at,

        -- SCD Type 2 metadata
        c.valid_from,
        c.valid_to,
        c.is_current,

        -- Behavioural metrics (from LTV intermediate model)
        COALESCE(l.total_orders,          0)         AS total_orders,
        COALESCE(l.completed_orders,      0)         AS completed_orders,
        COALESCE(l.cancelled_orders,      0)         AS cancelled_orders,
        COALESCE(l.lifetime_value_usd,    0)         AS lifetime_value_usd,
        l.avg_order_value_usd,
        l.max_order_value_usd,
        l.first_order_date,
        l.last_order_date,
        l.customer_tenure_days,
        l.days_since_last_order,
        l.avg_days_to_ship,
        l.cancellation_rate_pct,

        -- RFM segmentation
        l.rfm_score,
        l.rfm_segment,
        l.recency_score,
        l.frequency_score,
        l.monetary_score,

        -- Derived flags
        CASE
            WHEN l.total_orders > 0 THEN TRUE ELSE FALSE
        END                                          AS has_placed_order,

        CASE
            WHEN l.days_since_last_order <= 90 THEN TRUE ELSE FALSE
        END                                          AS is_active,

        -- Audit
        CURRENT_TIMESTAMP()                          AS _dbt_updated_at

    FROM current_customers AS c
    LEFT JOIN ltv AS l USING (customer_id)
)

SELECT * FROM dim
        )
        order by (
            customer_id, country_code
        )
    )
;

alter table ANALYTICS.DEV_LOCAL_marts.dim_customers cluster by (customer_id, country_code);
  