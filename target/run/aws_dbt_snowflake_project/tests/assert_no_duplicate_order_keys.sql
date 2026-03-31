
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  -- =============================================================================
-- Test: assert_no_duplicate_order_keys.sql
-- Type: Singular (custom) test
-- Purpose:
--   Detect duplicate order_sk values in fct_orders.
--   Duplicates indicate a bug in surrogate key generation or incremental merge logic.
--   Should return 0 rows in a healthy pipeline.
-- =============================================================================

WITH order_counts AS (
    SELECT
        order_sk,
        COUNT(*) AS row_count
    FROM ANALYTICS.DEV_HARNEKSINGH_marts.fct_orders
    GROUP BY 1
    HAVING COUNT(*) > 1
)

SELECT
    order_sk,
    row_count
FROM order_counts
  
  
      
    ) dbt_internal_test