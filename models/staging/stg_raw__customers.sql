-- =============================================================================
-- Model: stg_raw__customers.sql
-- Layer:  Staging
-- Source: RAW.ECOMMERCE.CUSTOMERS (JSON loaded as VARIANT)
-- Purpose:
--   - Flatten VARIANT (JSON) columns to typed scalars
--   - Apply masking (PII columns — email, phone)
--   - Deduplicate per customer_id
--   - Schema-evolution-safe (new JSON keys land in VARIANT, parsed explicitly)
-- =============================================================================

{{
  config(
    materialized  = 'incremental',
    unique_key    = 'customer_id',
    incremental_strategy = 'merge',
    on_schema_change = 'append_new_columns',
    tags          = ['staging', 'customers', 'pii'],
    meta          = {
      'owner': 'data-engineering',
      'contains_pii': true,
      'masking_applied': true,
      'sla': '2 hours after raw load'
    }
  )
}}

WITH source AS (
    SELECT *
    FROM {{ source('raw_ecommerce', 'customers') }}

    {% if is_incremental() %}
    WHERE _LOADED_AT >= (
        SELECT DATEADD('day', -{{ var('incremental_lookback_days', 3) }},
                       COALESCE(MAX(_raw_loaded_at), '1970-01-01'::TIMESTAMP_NTZ))
        FROM {{ this }}
    )
    {% endif %}
),

-- Flatten JSON VARIANT. Use coalesce to handle both:
--   a) direct columns (if schema was inferred)
--   b) nested keys in RAW_PAYLOAD (VARIANT)
flattened AS (
    SELECT
        -- PK: try direct column first, fall back to JSON key
        COALESCE(
            CUSTOMER_ID::VARCHAR(100),
            RAW_PAYLOAD['customer_id']::VARCHAR(100)
        )                                           AS customer_id,

        -- PII columns (masking policy applied at Snowflake table level)
        -- dbt accesses the masked version automatically based on role
        COALESCE(
            EMAIL::VARCHAR(500),
            RAW_PAYLOAD['email']::VARCHAR(500)
        )                                           AS email,

        COALESCE(
            PHONE::VARCHAR(50),
            RAW_PAYLOAD['phone']::VARCHAR(50)
        )                                           AS phone,

        -- Demographics
        UPPER(COALESCE(
            COUNTRY::VARCHAR(100),
            RAW_PAYLOAD['country']::VARCHAR(100)
        ))                                          AS country_code,

        -- Profile attributes from JSON
        RAW_PAYLOAD['first_name']::VARCHAR(200)     AS first_name,
        RAW_PAYLOAD['last_name']::VARCHAR(200)      AS last_name,
        RAW_PAYLOAD['date_of_birth']::DATE          AS date_of_birth,
        RAW_PAYLOAD['customer_segment']::VARCHAR(50) AS customer_segment,
        RAW_PAYLOAD['acquisition_channel']::VARCHAR(100) AS acquisition_channel,
        RAW_PAYLOAD['is_email_verified']::BOOLEAN   AS is_email_verified,

        -- Timestamps
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(CREATED_AT::VARCHAR),
            TRY_TO_TIMESTAMP_NTZ(RAW_PAYLOAD['created_at']::VARCHAR)
        )                                           AS customer_created_at,

        TRY_TO_TIMESTAMP_NTZ(
            RAW_PAYLOAD['updated_at']::VARCHAR
        )                                           AS customer_updated_at,

        -- Pipeline metadata
        _LOADED_AT                                  AS _raw_loaded_at,
        _SOURCE_FILE                                AS _source_file,
        _INGESTION_RUN_ID                           AS _ingestion_run_id,

        {{ add_audit_columns() }}
    FROM source
),

deduped AS (
    SELECT *
    FROM flattened
    WHERE customer_id IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY customer_updated_at DESC NULLS LAST,
                 _raw_loaded_at DESC
    ) = 1
)

SELECT * FROM deduped
