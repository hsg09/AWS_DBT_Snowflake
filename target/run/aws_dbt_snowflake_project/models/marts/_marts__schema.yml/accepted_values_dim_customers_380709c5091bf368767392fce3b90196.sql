
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.accepted_values_dim_customers_380709c5091bf368767392fce3b90196
    
      
    ) dbt_internal_test