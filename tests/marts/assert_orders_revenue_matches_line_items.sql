{{ config(tags=['marts']) }}

-- =============================================================================
-- Test: assert_orders_revenue_matches_line_items.sql
-- Type: Singular (custom) test
-- Purpose:
--   Cross-check: the sum of line item totals for completed orders should
--   be within 5% tolerance of the order header revenue_usd.
--   Large discrepancies indicate data corruption or calculation errors.
-- =============================================================================

WITH order_header AS (
    SELECT
        order_id,
        revenue_usd             AS header_revenue_usd
    FROM {{ ref('fct_orders') }}
    WHERE is_completed = TRUE
),

order_item_totals AS (
    SELECT
        order_id,
        SUM(line_total_usd)     AS computed_revenue_usd
    FROM {{ ref('stg_raw__order_items') }}
    GROUP BY 1
),

discrepancies AS (
    SELECT
        h.order_id,
        h.header_revenue_usd,
        t.computed_revenue_usd,
        ABS(h.header_revenue_usd - COALESCE(t.computed_revenue_usd, 0)) AS abs_diff,
        CASE
            WHEN h.header_revenue_usd > 0
            THEN ABS(h.header_revenue_usd - COALESCE(t.computed_revenue_usd, 0))
                 / h.header_revenue_usd * 100
            ELSE 0
        END AS pct_diff
    FROM order_header AS h
    LEFT JOIN order_item_totals AS t USING (order_id)
    WHERE pct_diff > 5   -- flag orders with >5% mismatch
      AND abs_diff > 1   -- ignore rounding noise (< $1 diff)
)

SELECT * FROM discrepancies
