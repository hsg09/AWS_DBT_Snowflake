
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select _LOADED_AT
from RAW.ECOMMERCE.products
where _LOADED_AT is null



  
  
      
    ) dbt_internal_test