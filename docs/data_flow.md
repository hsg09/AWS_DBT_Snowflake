# 🛤️ Data Flow Narrative: The "Life of a Record"

This document traces the end-to-end transformation of our core e-commerce entities (**Orders** and **Customers**) as they move from raw external storage into curated analytical marts.

---

## 🏗️ Phase 1: Raw Data (S3 / Source Systems)
**Description**: Data arrives in our AWS S3 Landing Zone as disparate CSV and JSON files from the upstream e-commerce application.

### 📋 Input Data (S3 External Files)
**Orders (S3 CSV)**
| order_id | customer_id | status | amount | date |
| :--- | :--- | :--- | :--- | :--- |
| ORD-101 | CUST-005 | completed | 249.99 | 2024-03-10 |

**Customers (S3 JSON)**
```json
{
  "customer_id": "CUST-005",
  "email": "liam.jones@example.com.au",
  "phone": "+61-2-555-0505",
  "customer_segment": "gold"
}
```

---

## 📥 Phase 2: Ingestion (Raw Layer / Snowflake)
**Description**: Our **Snowpark Python** stored procedure infers the schema and loads data into Snowflake RAW tables, injecting audit metadata.

### 🔄 Key Transformations:
- **Schema Inference**: Automated creation of the `RAW.ECOMMERCE.ORDERS` table.
- **Audit Injection**: Addition of `_LOADED_AT` and `_SOURCE_FILE`.

### 📋 Transformed Output (Snowflake Raw)
| ORDER_ID | CUSTOMER_ID | STATUS | AMOUNT | DATE | _LOADED_AT |
| :--- | :--- | :--- | :--- | :--- | :--- |
| ORD-101 | CUST-005 | completed | 249.99 | 2024-03-10 | 2024-03-31 22:00:00 |

---

## 🥉 Phase 3: Staging (Bronze)
**Description**: dbt normalizes the raw data, applies PII masking, and enforces type safety.

### 🔄 Key Transformations:
- **PII Masking**: Hiding the customer's email for non-privileged roles.
- **Normalization**: Converting `status` to uppercase `STATUS`.

### 📋 Transformed Output (`STG_RAW__CUSTOMERS`)
| customer_id | email (Masked) | segment | country_code |
| :--- | :--- | :--- | :--- |
| CUST-005 | l****@example.com.au | GOLD | AU |

---

## 🕰️ Phase 4: Snapshot (SCD Type 2)
**Description**: dbt Snapshots capture historical state changes for dimension attributes.

### 🔄 Key Transformations:
- **State tracking**: Creation of `dbt_valid_from` and `dbt_valid_to`.

### 📋 Transformed Output (`SNAP_CUSTOMERS`)
| customer_id | segment | dbt_valid_from | dbt_valid_to | is_current |
| :--- | :--- | :--- | :--- | :--- |
| CUST-005 | SILVER | 2022-01-01 10:00:00 | 2024-03-10 14:00:00 | FALSE |
| **CUST-005** | **GOLD** | **2024-03-10 14:00:00** | **NULL** | **TRUE** |

---

## 🥈 Phase 5: Intermediate (Silver)
**Description**: Calculated metrics (LTV, RFM) are computed using window functions and joins.

### 🔄 Key Transformations:
- **Aggregate Calculation**: Summing historical revenue for `CUST-005`.
- **Incremental Logic**: Using a 3-day lookback window to minimize compute.

### 📋 Transformed Output (`INT_CUSTOMERS__LIFETIME_VALUE`)
| customer_id | total_revenue_usd | total_orders | rfm_segment |
| :--- | :--- | :--- | :--- |
| CUST-005 | 2490.50 | 12 | Champions |

---

## 🥇 Phase 6: Marts (Gold / Star Schema)
**Description**: The final Star Schema with surrogate keys, optimized for high-performance BI reporting.

### 🔄 Key Transformations:
- **Surrogate Key Generation**: MD5 hashing for stable IDs.
- **Dimensional Join**: Bringing LTV and Segments into the Fact Grain.

### 📋 Transformed Output (`FCT_ORDERS`)
| order_sk (MD5) | customer_sk (MD5) | revenue_usd | margin_usd | order_date |
| :--- | :--- | :--- | :--- | :--- |
| z9y8x7... | a1b2c3... | 249.99 | 150.00 | 2024-03-10 |

---

## ⚙️ Technical Landmarks Review
- **Idempotency**: All phases can be re-run safely without creating duplicate records.
- **Lineage**: Every record can be traced back to its S3 `_SOURCE_FILE`.
- **Integrity**: 68+ tests validate these transitions in every Airflow heartbeat.
