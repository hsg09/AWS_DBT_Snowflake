
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select country_code
from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__customers
where country_code is null



  
  
      
    ) dbt_internal_test