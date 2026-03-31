
    
    

with all_values as (

    select
        customer_segment as value_field,
        count(*) as n_records

    from ANALYTICS.DEV_HARNEKSINGH_marts.dim_customers
    group by customer_segment

)

select *
from all_values
where value_field not in (
    'bronze','silver','gold','platinum','vip'
)


