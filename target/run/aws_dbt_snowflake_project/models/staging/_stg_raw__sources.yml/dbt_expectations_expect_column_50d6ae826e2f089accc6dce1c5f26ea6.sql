
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.dbt_expectations_expect_column_50d6ae826e2f089accc6dce1c5f26ea6
    
      
    ) dbt_internal_test