
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.dbt_expectations_expect_column_7c143075e0699c94d2dee527c76979f4
    
      
    ) dbt_internal_test