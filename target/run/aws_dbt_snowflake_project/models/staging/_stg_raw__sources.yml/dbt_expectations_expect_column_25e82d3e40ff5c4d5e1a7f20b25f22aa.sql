
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.dbt_expectations_expect_column_25e82d3e40ff5c4d5e1a7f20b25f22aa
    
      
    ) dbt_internal_test