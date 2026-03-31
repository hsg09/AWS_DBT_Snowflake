
    
    

select
    customer_id as unique_field,
    count(*) as n_records

from ANALYTICS.DEV_LOCAL_staging.stg_raw__customers
where customer_id is not null
group by customer_id
having count(*) > 1


