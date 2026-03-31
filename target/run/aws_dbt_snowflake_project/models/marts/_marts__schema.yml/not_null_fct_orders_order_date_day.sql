
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select order_date_day
from ANALYTICS.DEV_HARNEKSINGH_marts.fct_orders
where order_date_day is null



  
  
      
    ) dbt_internal_test