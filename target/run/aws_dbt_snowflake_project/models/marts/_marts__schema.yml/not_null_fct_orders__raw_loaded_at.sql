
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select _raw_loaded_at
from ANALYTICS.DEV_HARNEKSINGH_marts.fct_orders
where _raw_loaded_at is null



  
  
      
    ) dbt_internal_test