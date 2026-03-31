
      begin;
    merge into "ANALYTICS"."SNAPSHOTS"."SNAP_CUSTOMERS" as DBT_INTERNAL_DEST
    using "ANALYTICS"."SNAPSHOTS"."SNAP_CUSTOMERS__dbt_tmp" as DBT_INTERNAL_SOURCE
    on DBT_INTERNAL_SOURCE.dbt_scd_id = DBT_INTERNAL_DEST.dbt_scd_id

    when matched
     
       and DBT_INTERNAL_DEST.dbt_valid_to is null
     
     and DBT_INTERNAL_SOURCE.dbt_change_type in ('update', 'delete')
        then update
        set dbt_valid_to = DBT_INTERNAL_SOURCE.dbt_valid_to

    when not matched
     and DBT_INTERNAL_SOURCE.dbt_change_type = 'insert'
        then insert ("CUSTOMER_ID", "EMAIL", "FIRST_NAME", "LAST_NAME", "COUNTRY_CODE", "CUSTOMER_SEGMENT", "ACQUISITION_CHANNEL", "IS_EMAIL_VERIFIED", "CUSTOMER_CREATED_AT", "CUSTOMER_UPDATED_AT", "DBT_UPDATED_AT", "DBT_VALID_FROM", "DBT_VALID_TO", "DBT_SCD_ID")
        values ("CUSTOMER_ID", "EMAIL", "FIRST_NAME", "LAST_NAME", "COUNTRY_CODE", "CUSTOMER_SEGMENT", "ACQUISITION_CHANNEL", "IS_EMAIL_VERIFIED", "CUSTOMER_CREATED_AT", "CUSTOMER_UPDATED_AT", "DBT_UPDATED_AT", "DBT_VALID_FROM", "DBT_VALID_TO", "DBT_SCD_ID")

;
    commit;
  