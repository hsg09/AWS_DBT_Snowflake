{% snapshot snap_customers %}

{{
  config(
    target_schema  = 'snapshots',
    unique_key     = 'customer_id',
    strategy       = 'timestamp',
    updated_at     = 'customer_updated_at',
    invalidate_hard_deletes = True,
    meta = {
      'owner': 'data-engineering',
      'contains_pii': true,
      'scd_type': 2
    }
  )
}}

-- =============================================================================
-- Snapshot: snap_customers
-- Type: SCD Type 2 (timestamp strategy)
-- Purpose:
--   Capture historical changes to customer profile attributes.
--   DBT adds: dbt_scd_id, dbt_updated_at, dbt_valid_from, dbt_valid_to.
--   dbt_valid_to IS NULL = current record.
--
-- The updated_at field is 'customer_updated_at' from the staging model.
-- If source doesn't have a reliable updated_at, switch to 'check' strategy
-- and list the columns that, when changed, should trigger a new snapshot row.
-- =============================================================================

SELECT
    customer_id,
    email,
    first_name,
    last_name,
    country_code,
    customer_segment,
    acquisition_channel,
    is_email_verified,
    customer_created_at,
    customer_updated_at    -- must be reliable/monotonic for timestamp strategy
FROM {{ ref('stg_raw__customers') }}

{% endsnapshot %}
