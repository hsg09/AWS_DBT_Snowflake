
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
        select *
        from ANALYTICS.DEV_LOCAL_dbt_test__audit.relationships_fct_orders_cb05eadd0457a15ce90d0fa08cd5296c
    
      
    ) dbt_internal_test