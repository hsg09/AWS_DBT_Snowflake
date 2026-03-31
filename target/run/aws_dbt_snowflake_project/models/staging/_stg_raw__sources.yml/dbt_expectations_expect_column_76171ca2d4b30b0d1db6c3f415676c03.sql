
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.dbt_expectations_expect_column_76171ca2d4b30b0d1db6c3f415676c03
    
      
    ) dbt_internal_test