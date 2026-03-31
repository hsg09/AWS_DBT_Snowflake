# 📥 Ingestion Architecture & Strategy

## 📑 Strategy: Non-Destructive Dynamic Loading
To minimize manual ETL maintenance, we leverage **Snowpark Python** for zero-DDL ingestion. Instead of hard-coding schemas, our pipeline automatically infers the data structure at runtime from the S3 source.

---

## ⚡ Technical Implementation: Snowpark `INFER_AND_CREATE_TABLE`
A dedicated Python Stored Procedure (`RAW.ECOMMERCE.INFER_AND_CREATE_TABLE`) acts as the gatekeeper for all landed data.

### Functionality:
1. **Schema Inference**: Scans files in the `@RAW.ECOMMERCE.S3_STAGE` using Snowflake's native `INFER_SCHEMA` function.
2. **Dynamic DDL Creation**: Generates and executes `CREATE TABLE IF NOT EXISTS` commands with appropriate Snowflake data types (`NUMBER`, `VARCHAR`, `TIMESTAMP_NTZ`).
3. **Audit Injection**: Appends metadata columns to every landed record:
    - `_LOADED_AT`: Processing timestamp.
    - `_SOURCE_FILE`: Origin S3 object path (Used for lineage and backfills).
    - `_INGESTION_RUN_ID`: UUID for full-load traceability.

---

##  S3 Landing Zone & External Stages
Our **Bronze (Raw)** layer is physically decoupled from Snowflake via S3 Stages.

| Entity | S3 Path | Snowflake Stage | Format |
| :--- | :--- | :--- | :--- |
| **Orders** | `s3://.../raw/ecommerce/orders/` | `@RAW.ECOMMERCE.S3_ORDERS_STAGE` | CSV (Gzip) |
| **Customers**| `s3://.../raw/ecommerce/customers/`| `@RAW.ECOMMERCE.S3_CUSTOMERS_STAGE`| JSON |
| **Products** | `s3://.../raw/ecommerce/products/` | `@RAW.ECOMMERCE.S3_PRODUCTS_STAGE` | CSV |

---

## 📋 Sample Input Data (Raw / Bronze)

To ensure system reliability, engineers must understand the physical structure of the landing files.

### 1. Raw Orders (CSV)
| ORDER_ID | CUSTOMER_ID | ORDER_STATUS | ORDER_AMOUNT | ORDER_DATE | _LOADED_AT |
| :--- | :--- | :--- | :--- | :--- | :--- |
| ORD-101 | CUST-005 | completed | 249.99 | 2024-03-10 | 2024-03-31 22:00:00 |
| ORD-102 | CUST-006 | shipped | 89.50 | 2024-03-11 | 2024-03-31 22:05:00 |

### 2. Raw Customers (JSON)
```json
{
  "customer_id": "CUST-005",
  "email": "liam.jones@example.com.au",
  "phone": "+61-2-555-0505",
  "customer_segment": "gold",
  "updated_at": "2024-01-10T10:00:00Z"
}
```

---

## 🛡️ Data Reliability: Idempotency & CDC
To prevent duplicate loading and partial-file errors, we implement a two-step reliability check:

### 1. File Ingestion Tracking
Every S3 object processed is logged in `AUDIT.CONTROL.FILE_INGESTION_LOG`. The `LOAD_ENTITY_FROM_STAGE` procedure checks this log before executing `COPY INTO`.

### 2. Last-Write-Wins Deduplication
Upstream microservices may re-deliver the same primary key (e.g., `order_id`) with updated timestamps. All Bronze-layer models use a **qualify row_number()** pattern:
```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY primary_key 
    ORDER BY _LOADED_AT DESC
) = 1
```

---

## 🚦 Schema Evolution Policy
1. **Additive Changes**: New columns detected by Snowpark are automatically appended to the target Raw table.
2. **Incompatible Changes**: If a column type changes (e.g., `INT` to `STRING`), the Snowpark procedure will log a failure to `AUDIT.CONTROL.TASK_EXECUTION_LOG`, requiring manual administrative review to prevent downstream data corruption.
