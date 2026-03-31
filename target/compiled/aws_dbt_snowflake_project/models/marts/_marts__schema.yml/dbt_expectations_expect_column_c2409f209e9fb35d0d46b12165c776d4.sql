






    with grouped_expression as (
    select
        
        
    
  
( 1=1 and lifetime_value_usd >= 0
)
 as expression


    from ANALYTICS.DEV_LOCAL_marts.dim_customers
    

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







