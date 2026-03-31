# 📈 Observability & Monitoring Strategy

## 📑 Strategy: Holistic System Visibility
Our pipeline is designed with **Deep Observability** as a first-class citizen. We monitor not just the "Up/Down" state of tasks, but the actual health, performance, and freshness of the data moving through the system.

---

## 🏗️ Technical Implementation: `AUDIT.CONTROL` Schema
Every Snowflake task and dbt run is tracked in a centralized `AUDIT.CONTROL` schema.

| Table | High-Level Purpose |
| :--- | :--- |
| `FILE_INGESTION_LOG` | Tracks every S3 object processed (ID, Filename, Row Count). |
| `TASK_EXECUTION_LOG` | Logs Snowpark Python procedure success/failures. |
| `DQ_RESULTS` | Captures every dbt test failure for historical quality auditing. |
| `V_FILE_INGESTION_LATEST`| A critical monitoring view for alerting on data stall. |

---

## ⌚ Data SLAs: Freshness & Accuracy
The system is governed by three primary Service Level Agreements (SLAs):

### 1. Ingestion Freshness (< 30 Minutes)
- **Target**: Row-available in `RAW.ECOMMERCE.STAGING` within 30 minutes of S3 arrival.
- **Monitoring**: dbt source freshness checks against `_LOADED_AT` metadata.

### 2. Marts Readiness (< 90 Minutes)
- **Target**: Complete materialization of `FCT_ORDERS` within 90 minutes of S3 arrival.
- **Monitoring**: Airflow TaskGroup duration tracking.

### 3. Data Accuracy (100% threshold)
- **Target**: Zero critical data quality failures in the Gold layer.
- **Monitoring**: dbt test suite execution on every 15-minute heartbeat.

---

## 🚨 Alerting & Error Management
All failures are handled via the **Airflow `on_failure_callback`**.

### Callout Logic:
1. **Critical Failures** (Staging/Snapshots): Pipeline is immediately halted to prevent data corruption.
2. **Warn Failures** (Marts): Pipeline continues, but a high-priority alert is dispatched via the callback.
3. **Log Visibility**: Every task provides a deep link to its Snowflake `QUERY_ID` and Airflow log for one-click troubleshooting.

---

## 🚦 Performance Observability
We monitor Snowflake **Warehouse Load** and **Pruning** efficiency:
- **Pruning Check**: We track `partition_total` vs `partition_scanned` to ensure our clustering keys on `order_date` are correctly filtering data.
- **Warehouse Spillage**: Monitoring for "Remote Spillage" on the `TRANSFORMER_WH`, which triggers an automated recommendation for warehouse resizing.
