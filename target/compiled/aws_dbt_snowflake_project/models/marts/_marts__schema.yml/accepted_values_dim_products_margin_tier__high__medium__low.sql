
    
    

with all_values as (

    select
        margin_tier as value_field,
        count(*) as n_records

    from ANALYTICS.DEV_LOCAL_marts.dim_products
    group by margin_tier

)

select *
from all_values
where value_field not in (
    'high','medium','low'
)


