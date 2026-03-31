
      
  
    

create or replace transient table ANALYTICS.snapshots.snap_customers
    
    
    
    as (
    

    select *,
        md5(coalesce(cast(customer_id as varchar ), '')
         || '|' || coalesce(cast(customer_updated_at as varchar ), '')
        ) as dbt_scd_id,
        customer_updated_at as dbt_updated_at,
        customer_updated_at as dbt_valid_from,
        
  
  coalesce(nullif(customer_updated_at, customer_updated_at), null)
  as dbt_valid_to
from (
        



-- =============================================================================
-- Snapshot: snap_customers
-- Type: SCD Type 2 (timestamp strategy)
-- Purpose:
--   Capture historical changes to customer profile attributes.
--   DBT adds: dbt_scd_id, dbt_updated_at, dbt_valid_from, dbt_valid_to.
--   dbt_valid_to IS NULL = current record.
--
-- The updated_at field is 'customer_updated_at' from the staging model.
-- If source doesn't have a reliable updated_at, switch to 'check' strategy
-- and list the columns that, when changed, should trigger a new snapshot row.
-- =============================================================================

SELECT
    customer_id,
    email,
    first_name,
    last_name,
    country_code,
    customer_segment,
    acquisition_channel,
    is_email_verified,
    customer_created_at,
    customer_updated_at    -- must be reliable/monotonic for timestamp strategy
FROM ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__customers

    ) sbq



    )
;


  
  