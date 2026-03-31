
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select quantity
from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__order_items
where quantity is null



  
  
      
    ) dbt_internal_test