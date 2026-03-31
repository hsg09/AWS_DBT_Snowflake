{% macro add_audit_columns() %}
    -- Pipeline audit columns injected into every model
    -- Tracks when dbt processed the row, separate from raw load time
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ  AS _dbt_updated_at,
    '{{ invocation_id }}'               AS _dbt_invocation_id,
    '{{ this.schema }}'                 AS _dbt_schema,
    '{{ this.name }}'                   AS _dbt_model_name
{% endmacro %}
