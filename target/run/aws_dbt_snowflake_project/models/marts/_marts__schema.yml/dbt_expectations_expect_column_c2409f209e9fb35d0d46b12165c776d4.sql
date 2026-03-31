
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.dbt_expectations_expect_column_c2409f209e9fb35d0d46b12165c776d4
    
      
    ) dbt_internal_test