
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select order_status
from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__orders
where order_status is null



  
  
      
    ) dbt_internal_test