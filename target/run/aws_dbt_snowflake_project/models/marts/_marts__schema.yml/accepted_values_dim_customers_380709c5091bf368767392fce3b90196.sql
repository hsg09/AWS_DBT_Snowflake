
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        rfm_segment as value_field,
        count(*) as n_records

    from ANALYTICS.DEV_HARNEKSINGH_marts.dim_customers
    group by rfm_segment

)

select *
from all_values
where value_field not in (
    'champions','loyal','new_customer','at_risk','cant_lose','lost','potential_loyalist'
)



  
  
      
    ) dbt_internal_test