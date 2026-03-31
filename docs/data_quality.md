# ✅ Data Quality Framework: `dbt-expectations`

## 📑 Strategy: Continuous Data Validation
Data quality is enforced as **Code** within our transformation layers. No data reaches the analytical Marts without passing **68+ automated integrity checks**.

---

## 🏗️ Multi-Layered Testing Taxonomy

### 1. Schema & Integrity (dbt Core)
- **Primary Keys**: Mandatory `unique` and `not_null` tests on every business identifier (e.g., `order_id`).
- **Referential Integrity**: Every `fct_orders` record is validated for a parent in `dim_customers`.
- **Domain Constraint**: `order_status` is restricted to known, business-approved states (e.g., `shipped`, `delivered`).

### 2. Industry-Standard Checks (`dbt-expectations`)
We leverage the `dbt-expectations` package for advanced data science validation:
- **`expect_column_values_to_be_between`**: Ensures non-zero order quantities and list prices.
- **`expect_table_row_count_to_be_between`**: Monitors for suspicious row drops (e.g., ingestion failures).
- **`expect_column_pair_values_A_to_be_greater_than_B`**: Validates list price is always >= unit cost.

### 3. Singular Business Tests (Custom SQL)
Located in `tests/*.sql`, these tests catch complex logical anomalies:
- **Revenue Reconciliation**: Cross-checks total order revenue in `fct_orders` against the sum of individual line items in `stg_raw__order_items`.
- **Date Anomaly Detection**: Identifies orders where `shipped_date` predates `order_date`.

---

## ⌚ Freshness & Lineage Monitoring

### 1. Source Freshness
We use Snowflake's `_LOADED_AT` metadata column to periodically monitor landing zones:
- **SLA**: Warning at 2 hours, Error at 12 hours of total data stall.
```bash
dbt source freshness --profiles-dir ~/.dbt --target dev
```

### 2. Audit Traceability
Every table in the `ANALYTICS` database contains macro-generated audit columns:
- `_dbt_updated_at`: Snowflake timestamp of the last dbt materialization.
- `_dbt_run_id`: UUID mapped back to the Airflow task execution log.

---

## 🛠️ Testing Operations: `store-failures`
To facilitate rapid debugging, all tests are executed with the `--store-failures` flag:
```bash
dbt test --select tag:marts --store-failures
```
This materializes failing records in the `ANALYTICS.DBT_TEST__AUDIT` schema, allowing analysts to query the **exact records** that violated a business constraint.
