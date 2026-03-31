
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.accepted_values_dim_products_margin_tier__high__medium__low
    
      
    ) dbt_internal_test