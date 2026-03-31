
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select order_amount_usd
from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__orders
where order_amount_usd is null



  
  
      
    ) dbt_internal_test