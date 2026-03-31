# 🛠️ Transformation Architecture: `dbt` Core

## 📑 Strategy: Modular Data-as-Code
We utilize **dbt (data build tool)** to transform raw ingested data into an analytical Kimball Star Schema. Our coding standards prioritize **Idempotency**, **Dry (Don't Repeat Yourself)** principles, and strict **Test-Driven Development (TDD)**.

---

## ⚡ Technical Implementation: Medallion Modeling

### 1. Staging (Bronze)
- **Materialization**: `view` (Default).
- **Core Function**: Cast raw strings to native types, apply PII masking, and normalize naming.
- **Deduplication**: Every model uses a `QUALIFY` row-level window function to ensure one record per business key.

#### 📋 Bronze Layer Preview (Transformation)
| Source Field | Staging (Masked) | Logic Applied |
| :--- | :--- | :--- |
| `liam.jones@example.com.au` | `l****@example.com.au` | Dynamic PII Masking |
| `+61-2-555-0505` | `+61-2-***-0505` | Phone Hashing/Masking |
| `gold` | `GOLD` | Upper-case Normalization |

### 2. Intermediate (Silver)
- **Materialization**: `table`.
- **Core Function**: Pre-calculate cross-model business metrics (LTV, RFM).
- **Join Strategy**: We avoid large joins at report-time by consolidating metrics into wide intermediate tables.

#### 📋 Silver Layer Preview (Aggregates)
| customer_id | total_orders | total_revenue_usd | rfm_segment |
| :--- | :--- | :--- | :--- |
| CUST-005 | 12 | 2490.50 | Champions |
| CUST-006 | 2 | 150.00 | At Risk |

### 3. Marts (Gold)
- **Materialization**: `incremental` (Fact tables) / `table` (Dims).
- **Core Function**: Presentation of dimensional surrogate keys (SKs).

---

## 🕰️ Historical Tracking: SCD Type 2 Snapshots
We use dbt snapshots (`snapshots/snap_customers.sql`) to track slowly changing dimensions.

| Strategy | `timestamp` |
| :--- | :--- |
| **Unique Key** | `customer_id` |
| **Updated Column** | `customer_updated_at` |
| **Metadata Columns**| `dbt_valid_from`, `dbt_valid_to` |

### Snapshot Rule:
Always run `dbt snapshot` **after** staging but **before** marts to ensure the `DIM_CUSTOMERS` mart reads the current active state.

---

## 📈 Incremental Strategy: Optimized Merging
For our largest high-volume tables (e.g., `fct_orders`), we use the `incremental` materialization to minimize Snowflake compute costs.

### Merge Strategy:
- **Unique Key**: `order_id`
- **CDC Column**: `_raw_loaded_at` (Referenced via a 3-day lookback window).
- **Dynamic Adaptability**: `on_schema_change = 'append_new_columns'` ensures dbt doesn't crash on new raw fields.

```sql
-- Pattern for incremental lookback
{% if is_incremental() %}
    WHERE _LOADED_AT >= (
        SELECT DATEADD('day', -3, MAX(_raw_loaded_at)) FROM {{ this }}
    )
{% endif %}
```

---

## 🛠️ Specialized Custom Macros
Located in `macros/*.sql`, these dbt functions standardize critical logic:

- `{{ generate_surrogate_key(['col1', 'col2']) }}`: Uses MD5 hashing to create stable business keys.
- `{{ add_audit_columns() }}`: Appends consistent `_dbt_updated_at` and `_dbt_run_id` fields to every model.
- `{{ mask_pii('email') }}`: Dynamically applies masking based on the session role.
