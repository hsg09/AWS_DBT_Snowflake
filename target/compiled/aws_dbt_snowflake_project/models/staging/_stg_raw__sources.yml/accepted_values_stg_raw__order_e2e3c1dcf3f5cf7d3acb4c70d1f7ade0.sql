
    
    

with all_values as (

    select
        order_status as value_field,
        count(*) as n_records

    from ANALYTICS.DEV_LOCAL_staging.stg_raw__orders
    group by order_status

)

select *
from all_values
where value_field not in (
    'pending','processing','shipped','delivered','completed','cancelled','refunded'
)


