
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.relationships_stg_raw__orders_dfa7c8d881bee3b33da33bade2739507
    
      
    ) dbt_internal_test