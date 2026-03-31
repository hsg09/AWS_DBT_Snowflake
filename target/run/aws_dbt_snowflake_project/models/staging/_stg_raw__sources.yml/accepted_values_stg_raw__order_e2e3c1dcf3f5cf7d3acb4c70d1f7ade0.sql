
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.accepted_values_stg_raw__order_e2e3c1dcf3f5cf7d3acb4c70d1f7ade0
    
      
    ) dbt_internal_test