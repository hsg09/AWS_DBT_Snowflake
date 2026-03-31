
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select order_sk
from ANALYTICS.DEV_HARNEKSINGH_marts.fct_orders
where order_sk is null



  
  
      
    ) dbt_internal_test