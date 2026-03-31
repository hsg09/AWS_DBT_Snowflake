






    with grouped_expression as (
    select
        
        
    
  
( 1=1 and line_item_count >= 0
)
 as expression


    from ANALYTICS.DEV_HARNEKSINGH_marts.fct_orders
    

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







