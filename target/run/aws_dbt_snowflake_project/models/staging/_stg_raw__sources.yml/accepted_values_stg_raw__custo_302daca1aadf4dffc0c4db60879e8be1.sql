
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.accepted_values_stg_raw__custo_302daca1aadf4dffc0c4db60879e8be1
    
      
    ) dbt_internal_test