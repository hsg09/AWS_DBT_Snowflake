
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select ORDER_ITEM_ID
from RAW.ECOMMERCE.order_items
where ORDER_ITEM_ID is null



  
  
      
    ) dbt_internal_test