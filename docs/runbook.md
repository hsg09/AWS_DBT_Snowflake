# 🛠️ Operational Runbook: Disaster Recovery & Maintenance

## 📑 Strategy: High-Availability Operations
This document establishes the standardized recovery procedures for the **`elt_pipeline`**. Every data engineer on-call must follow these steps to ensure data consistency following a system failure.

---

## 🚨 Incident Response: Common Failures

### 1. Ingestion Failure (`snowflake_ingestion`)
- **Symptoms**: `TASK_HISTORY` shows `FAILED` or `SKIPPED`.
- **Root Cause**: Malformed S3 file (Invalid JSON/CSV), or IAM permission change.
- **Resolution**:
    1. Check `AUDIT.CONTROL.FILE_INGESTION_LOG` for the specific filename.
    2. Inspect file structure in S3.
    3. Once fixed, manually trigger the task: `EXECUTE TASK RAW.ECOMMERCE.LOAD_ORDERS_TASK`.

### 2. dbt Package Corruption (`dbt_deps`)
- **Symptoms**: `dbt run` fails with `Compilation Error: dbt found X package(s)... but only Y installed`.
- **Resolution**:
    1. Navigate to the project root on the Airflow worker.
    2. Execute: `dbt clean && dbt deps`.
    3. Retry the Airflow task.

### 3. Incremental Model Gap
- **Symptoms**: Missing data in `fct_orders` for specific historical dates.
- **Resolution**:
    1. Identify the missing range.
    2. Perform a **Full Refresh** for that model: `dbt run --select fct_orders --full-refresh`.
    > [!CAUTION]
    > **Full-Refresh Risk**: Rebuilding multi-million row tables can incur high Snowflake costs. Only use if the 3-day lookback window is insufficient.

---

## 🔄 Backfill & Replay Strategy
When a logic bug is identified and requires historical data to be re-processed:

### Method: Variable Overriding
1. Identify the `_loaded_at` starting point.
2. Trigger the DAG with a manual configuration:
```json
{ "lookback_window": 30 }
```
3. The dbt model logic will pick up this variable and extend the `WHERE` clause filter to catch the re-processed data.

---

## 🚦 System Maintenance & Health Checks
- **Daily**: Review `AUDIT.CONTROL.V_FILE_INGESTION_LATEST` for landing stalls.
- **Weekly**: Monitor Snowflake **Query Profile** for spillage on large joins; adjust warehouse size if necessary.
- **Monthly**: Review dbt package upgrades and Snowflake **Account Usage** for cost anomalies.
