-- =============================================================================
-- Macro: generate_surrogate_key
-- Purpose:
--   Wraps dbt_utils.generate_surrogate_key with production-safe defaults.
--   - Uppercases all inputs for case-consistency across sources
--   - Trims whitespace before hashing
--   - Falls back to SHA2-256 (Snowflake native) if dbt_utils not installed
--
-- Usage:
--   {{ generate_surrogate_key(['order_id']) }}
--   {{ generate_surrogate_key(['order_id', 'product_id']) }}
-- =============================================================================

{% macro generate_surrogate_key(column_list) %}
    {%- if column_list is string -%}
        {%- set column_list = [column_list] -%}
    {%- endif -%}

    {%- set coalesced_cols = [] -%}
    {%- for col in column_list -%}
        {%- do coalesced_cols.append("UPPER(TRIM(COALESCE(CAST(" ~ col ~ " AS VARCHAR), '_null_')))" ) -%}
    {%- endfor -%}

    SHA2(
        CONCAT_WS('||', {{ coalesced_cols | join(', ') }}),
        256
    )
{% endmacro %}
