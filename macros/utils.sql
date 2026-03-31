-- =============================================================================
-- Macro: incremental_predicate
-- Purpose:
--   Centralised incremental filter predicate for all incremental models.
--   Applies a lookback window to handle late-arriving data safely.
--
-- Usage (in model WHERE clause):
--   WHERE {{ incremental_predicate('_loaded_at') }}
-- =============================================================================

{% macro incremental_predicate(timestamp_column, lookback_days=none) %}
    {%- set days = lookback_days or var('incremental_lookback_days', 3) -%}
    {%- if is_incremental() -%}
        {{ timestamp_column }} >= (
            SELECT DATEADD('day', -{{ days }},
                           COALESCE(MAX({{ timestamp_column }}), '1970-01-01'::TIMESTAMP_NTZ))
            FROM {{ this }}
        )
    {%- else -%}
        1 = 1    -- Full refresh: no filter applied
    {%- endif -%}
{% endmacro %}


-- =============================================================================
-- Macro: get_column_names
-- Purpose:
--   Returns a list of column names for a given relation (table/view).
--   Useful for dynamic SELECT *, schema evolution checks, or macro-generated SQL.
--
-- Usage:
--   {% set cols = get_column_names(ref('stg_raw__orders')) %}
--   {{ cols | join(', ') }}
-- =============================================================================

{% macro get_column_names(relation) %}
    {%- set columns = adapter.get_columns_in_relation(relation) -%}
    {%- set col_names = [] -%}
    {%- for col in columns -%}
        {%- do col_names.append(col.name) -%}
    {%- endfor -%}
    {{ return(col_names) }}
{% endmacro %}


-- =============================================================================
-- Macro: safe_cast
-- Purpose:
--   Null-safe, error-tolerant casting for unreliable source data.
--   Uses TRY_CAST (Snowflake) with a fallback default on failure.
--
-- Usage:
--   {{ safe_cast('order_amount', 'NUMBER(18,2)', 0.00) }}
--   {{ safe_cast('order_date', 'DATE') }}
-- =============================================================================

{% macro safe_cast(column, datatype, default=None) %}
    {%- if default is not none -%}
        COALESCE(TRY_CAST({{ column }} AS {{ datatype }}), {{ default }})
    {%- else -%}
        TRY_CAST({{ column }} AS {{ datatype }})
    {%- endif -%}
{% endmacro %}


-- =============================================================================
-- Macro: schema_evolution_handler
-- Purpose:
--   When unioning two relations with different schemas (e.g., after schema drift),
--   generates a UNION ALL that pads missing columns with NULL.
--   Required when dbt on_schema_change='append_new_columns' is not enough.
--
-- Usage:
--   {{ schema_evolution_handler(ref('stg_raw__orders'), ref('stg_raw__orders__v2')) }}
-- =============================================================================

{% macro schema_evolution_handler(relation_a, relation_b) %}
    {%- set cols_a = get_column_names(relation_a) -%}
    {%- set cols_b = get_column_names(relation_b) -%}
    {%- set all_cols = (cols_a + cols_b) | unique | list -%}

    SELECT
    {%- for col in all_cols %}
        {% if col in cols_a %}{{ col }}{% else %}NULL AS {{ col }}{% endif %}
        {%- if not loop.last %},{% endif %}
    {%- endfor %}
    FROM {{ relation_a }}

    UNION ALL

    SELECT
    {%- for col in all_cols %}
        {% if col in cols_b %}{{ col }}{% else %}NULL AS {{ col }}{% endif %}
        {%- if not loop.last %},{% endif %}
    {%- endfor %}
    FROM {{ relation_b }}
{% endmacro %}


-- =============================================================================
-- Macro: generate_date_surrogate_key
-- Purpose:
--   Convenience macro for date-based surrogate keys (integer YYYYMMDD format).
--   Useful for fact table date FK joins to date dimension.
-- =============================================================================

{% macro generate_date_surrogate_key(date_column) %}
    TO_CHAR({{ date_column }}, 'YYYYMMDD')::INTEGER
{% endmacro %}
