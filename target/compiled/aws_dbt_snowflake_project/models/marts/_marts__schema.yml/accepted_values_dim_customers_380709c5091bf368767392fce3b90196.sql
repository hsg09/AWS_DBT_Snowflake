
    
    

with all_values as (

    select
        rfm_segment as value_field,
        count(*) as n_records

    from ANALYTICS.DEV_LOCAL_marts.dim_customers
    group by rfm_segment

)

select *
from all_values
where value_field not in (
    'champions','loyal','new_customer','at_risk','cant_lose','lost','potential_loyalist'
)


