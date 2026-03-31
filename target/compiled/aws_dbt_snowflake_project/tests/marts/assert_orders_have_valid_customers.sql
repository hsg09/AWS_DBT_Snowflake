

-- =============================================================================
-- Test: assert_orders_have_valid_customers.sql
-- Type: Singular (custom) test
-- Purpose:
--   Ensure every order in fct_orders has a matching, valid customer in dim_customers.
--   Flags orphaned orders (customer_id not found in dimension = data quality failure).
--
-- Expectation: returns 0 rows (all orders have valid customers)
-- Severity: error (blocks deployment if orphans exist in prod)
-- =============================================================================

WITH orphaned_orders AS (
    SELECT
        fo.order_id,
        fo.customer_id,
        fo.order_date_day,
        fo.order_status
    FROM ANALYTICS.DEV_LOCAL_marts.fct_orders AS fo
    LEFT JOIN ANALYTICS.DEV_LOCAL_marts.dim_customers AS dc
        ON fo.customer_sk = dc.customer_sk
    WHERE dc.customer_sk IS NULL
      -- Exclude very recent orders where customer dim may not yet be refreshed
      AND fo.order_date_day < DATEADD('hour', -6, CURRENT_DATE())
)

SELECT * FROM orphaned_orders