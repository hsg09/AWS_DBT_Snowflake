
    
    

select
    product_id as unique_field,
    count(*) as n_records

from ANALYTICS.DEV_LOCAL_staging.stg_raw__products
where product_id is not null
group by product_id
having count(*) > 1


