
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        order_status as value_field,
        count(*) as n_records

    from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__orders
    group by order_status

)

select *
from all_values
where value_field not in (
    'pending','processing','shipped','delivered','completed','cancelled','refunded'
)



  
  
      
    ) dbt_internal_test