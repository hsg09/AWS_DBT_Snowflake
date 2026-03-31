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

{{
  config(
    materialized     = 'table',
    cluster_by       = ['customer_id', 'country_code'],
    tags             = ['dimension', 'customers', 'marts'],
    meta             = {
      'owner':          'data-engineering',
      'contains_pii':   false,
      'business_owner': 'customer-analytics'
    }
  )
}}

WITH customer_snapshot AS (
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
    FROM {{ ref('snap_customers') }}
),

-- Only current records (for the main dim table)
current_customers AS (
    SELECT * FROM customer_snapshot WHERE is_current = TRUE
),

-- Join with LTV / behavioural metrics from intermediate layer
ltv AS (
    SELECT * FROM {{ ref('int_customers__lifetime_value') }}
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
