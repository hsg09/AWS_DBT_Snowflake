-- back compat for old kwarg name
  
  begin;
    
        
            
	    
	    
            
        
    

    

    merge into ANALYTICS.DEV_LOCAL_staging.stg_raw__order_items as DBT_INTERNAL_DEST
        using ANALYTICS.DEV_LOCAL_staging.stg_raw__order_items__dbt_tmp as DBT_INTERNAL_SOURCE
        on ((DBT_INTERNAL_SOURCE.order_item_id = DBT_INTERNAL_DEST.order_item_id))

    
    when matched then update set
        "ORDER_ITEM_ID" = DBT_INTERNAL_SOURCE."ORDER_ITEM_ID","ORDER_ID" = DBT_INTERNAL_SOURCE."ORDER_ID","PRODUCT_ID" = DBT_INTERNAL_SOURCE."PRODUCT_ID","QUANTITY" = DBT_INTERNAL_SOURCE."QUANTITY","LINE_TOTAL_USD" = DBT_INTERNAL_SOURCE."LINE_TOTAL_USD","DISCOUNT_PCT" = DBT_INTERNAL_SOURCE."DISCOUNT_PCT","UNIT_PRICE_USD" = DBT_INTERNAL_SOURCE."UNIT_PRICE_USD","_RAW_LOADED_AT" = DBT_INTERNAL_SOURCE."_RAW_LOADED_AT"
    

    when not matched then insert
        ("ORDER_ITEM_ID", "ORDER_ID", "PRODUCT_ID", "QUANTITY", "LINE_TOTAL_USD", "DISCOUNT_PCT", "UNIT_PRICE_USD", "_RAW_LOADED_AT")
    values
        ("ORDER_ITEM_ID", "ORDER_ID", "PRODUCT_ID", "QUANTITY", "LINE_TOTAL_USD", "DISCOUNT_PCT", "UNIT_PRICE_USD", "_RAW_LOADED_AT")

;
    commit;