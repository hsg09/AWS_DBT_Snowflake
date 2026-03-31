-- =============================================================================
-- Model: int_customers__lifetime_value.sql
-- Layer:  Intermediate
-- Purpose:
--   Compute per-customer lifetime value (LTV), order history, and RFM metrics.
--   RFM = Recency, Frequency, Monetary (classic e-commerce customer scoring).
--   Used by dim_customers mart as the analytical backbone.
-- =============================================================================

{{
  config(
    tags = ['intermediate', 'customers'],
    meta = {'owner': 'data-engineering'}
  )
}}

WITH orders AS (
    SELECT
        customer_id,
        order_id,
        order_date,
        order_status,
        revenue_usd,
        days_to_ship,
        is_completed
    FROM {{ ref('int_orders__enriched') }}
    WHERE order_date BETWEEN '{{ var("start_date") }}'::DATE
                         AND '{{ var("end_date") }}'::DATE
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
