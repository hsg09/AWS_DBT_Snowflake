






    with grouped_expression as (
    select
        
        
    
  
( 1=1 and order_amount_usd >= 0
)
 as expression


    from ANALYTICS.DEV_LOCAL_staging.stg_raw__orders
    

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







