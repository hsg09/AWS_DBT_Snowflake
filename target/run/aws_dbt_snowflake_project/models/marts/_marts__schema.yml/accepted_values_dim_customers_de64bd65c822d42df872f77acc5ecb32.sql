
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.accepted_values_dim_customers_de64bd65c822d42df872f77acc5ecb32
    
      
    ) dbt_internal_test