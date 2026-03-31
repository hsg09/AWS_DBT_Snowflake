






    with grouped_expression as (
    select
        
        
    
  
( 1=1 and unit_cost_usd >= 0
)
 as expression


    from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__products
    

),
validation_errors as (

    select
        *
    from
        grouped_expression
    where
        not(expression = true)

)

select *
from validation_errors







