
    
    

with child as (
    select customer_id as from_field
    from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__orders
    where customer_id is not null
),

parent as (
    select customer_id as to_field
    from ANALYTICS.DEV_HARNEKSINGH_staging.stg_raw__customers
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null


