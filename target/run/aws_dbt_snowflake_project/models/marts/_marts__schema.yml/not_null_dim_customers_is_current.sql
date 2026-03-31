
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select is_current
from ANALYTICS.DEV_HARNEKSINGH_marts.dim_customers
where is_current is null



  
  
      
    ) dbt_internal_test