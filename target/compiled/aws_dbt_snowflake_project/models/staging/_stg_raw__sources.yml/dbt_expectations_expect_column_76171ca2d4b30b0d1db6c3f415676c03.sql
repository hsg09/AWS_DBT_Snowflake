






    with grouped_expression as (
    select
        
        
    
  
( 1=1 and line_total_usd >= 0
)
 as expression


    from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__order_items
    

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







