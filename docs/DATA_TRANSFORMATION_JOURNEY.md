# 🛤️ The Data Transformation Journey: From S3 to Analytics Marts

This document tracks the "Life of a Record" through our ELT pipeline, showing exactly how raw data from AWS S3 is transformed into high-value analytical insights in Snowflake using dbt.

---

## 📂 Phase 1: Raw Data in AWS S3
Data arrives in various formats (CSV, JSON) inside our `s3://your-data-lake-bucket/raw/` directory. This is the **Bronze** layer—unstructured files waiting to be processed.

### 📄 Raw Orders (`orders.csv`)
| ORDER_ID | CUSTOMER_ID | ORDER_STATUS | ORDER_AMOUNT | ORDER_DATE | SHIPPED_DATE | PAYMENT_METHOD | BILLING_COUNTRY |
|:---|:---|:---|:---|:---|:---|:---|:---|
| ORD-00001 | CUST-001 | completed | 249.99 | 2024-01-05 | 2024-01-07 | credit_card | US |
| ORD-00002 | CUST-002 | completed | 89.50 | 2024-01-06 | 2024-01-08 | paypal | GB |
| ORD-00125 | CUST-005 | completed | 120.00 | 2024-02-15 | 2024-02-17 | credit_card | AU |

### 📄 Raw Customers (`customers.json`)
*Note: Represented as a table for clarity, though records arrive as JSON objects.*
| customer_id | email | first_name | last_name | country | customer_segment | created_at |
|:---|:---|:---|:---|:---|:---|:---|
| CUST-001 | james.wilson@example.com | James | Wilson | US | silver | 2022-06-15T10:23:00Z |
| CUST-005 | liam.jones@example.com.au | Liam | Jones | AU | gold | 2022-01-05T08:20:00Z |

---

## ⚡ Phase 2: Dynamic Ingestion (Snowflake Raw Layer)
**Description:** Our Snowpark Python procedure (`INFER_AND_CREATE_TABLE`) acts as a dynamic gateway. It detects the file schema on S3 and auto-creates Snowflake tables in the `RAW.ECOMMERCE` schema without manual DDL.

**Key Actions:**
- **Schema Inference:** Automatically detects column names and native data types.
- **Audit Tracking:** Injects metadata columns like `_LOADED_AT` and `_SOURCE_FILE`.

### 🔍 Preview: `RAW.ECOMMERCE.ORDERS` (Snowflake Table)
| ORDER_ID | CUSTOMER_ID | ... | _LOADED_AT | _SOURCE_FILE |
|:---|:---|:---|:---|:---|
| ORD-00001 | CUST-001 | ... | 2024-03-31 08:15:00 | orders_2024_01.csv |
| ORD-00125 | CUST-005 | ... | 2024-03-31 08:20:00 | orders_2024_02.csv |

---

## 🥉 Phase 3: Staging Layer (dbt Bronze)
**Description:** This phase standardizes the data. We take raw tables and turn them into a reliable source. Here, we flatten JSON, protect PII, and enforce type safety.

**Key Actions:**
- **JSON Flattening:** Extracts keys from the `RAW_PAYLOAD` variant column (for Customers).
- **PII Protection:** Email and phone numbers are masked for unauthorized roles (e.g., `j****@example.com`).
- **Type Safety:** Explicitly casts strings to native types (e.g., `NUMBER(18,2)`, `DATE`).

### 🔍 Preview: `STG_RAW__CUSTOMERS`
| customer_id | email (Masked) | country_code | customer_segment | customer_updated_at |
|:---|:---|:---|:---|:---|
| CUST-001 | j****@example.com | US | SILVER | 2024-01-10 08:05:00 |
| CUST-005 | l****@example.com.au | AU | GOLD | 2024-01-10 10:00:00 |

---

## 🕰️ Phase 4: Snapshot Layer (SCD Type 2)
**Description:** This is where we track historical changes. If a customer's `customer_segment` changes, we don't overwrite the old value. Instead, we "close" the old record and "open" a new one.

**Key Actions:**
- **SCD Type 2 Modeling**: Uses the `timestamp` strategy on the `customer_updated_at` field.
- **Valid To/From Tracking**: Automatically manages `dbt_valid_from` and `dbt_valid_to` columns.

### 🔍 History Tracking: `SNAP_CUSTOMERS`
In this example, Customer `CUST-001` starts as a "Silver" member and is later upgraded to "Gold".
| customer_id | customer_segment | dbt_valid_from | dbt_valid_to | is_current |
|:---|:---|:---|:---|:---|
| CUST-001 | SILVER | 2022-06-15 10:23:00 | 2024-03-10 14:00:00 | FALSE |
| **CUST-001** | **GOLD** | **2024-03-10 14:00:00** | **NULL** | **TRUE** |

*Note: `is_current` is calculated by checking if `dbt_valid_to` is NULL.*

---

## 🥈 Phase 5: Intermediate Layer (dbt Silver)
**Description:** Here we combine staging tables and snapshots to build complex aggregates and business-ready logic.

**Key Actions:**
- **Customer LTV**: Summing order history for each customer.
- **Order Enrichment**: Calculating total items and gross margins per order.

### 🔍 Preview: `INT_CUSTOMERS__LIFETIME_VALUE`
| customer_id | total_orders | total_revenue_usd | latest_order_date |
|:---|:---|:---|:---|
| CUST-001 | 42 | 5240.25 | 2024-03-15 |
| CUST-005 | 12 | 1150.00 | 2024-02-15 |

---

## 🥇 Phase 6: Marts Layer (dbt Gold)
**Description:** The final Star Schema used by BI tools (Tableau, Looker, etc.).

**Key Actions:**
- **Surrogate Keys**: Uses hashes (e.g., `customer_sk`) for fast, stable joins.
- **Analytical Grain**: One row per analytical unit (e.g., one row per order in `fct_orders`).

### 🔍 Preview: `DIM_CUSTOMERS` (Dimension Table)
Includes LTV, segment history, and performance clustering.
| customer_sk | customer_id | lifetime_value_usd | current_segment | is_active |
|:---|:---|:---|:---|:---|
| a1b2c3... | CUST-001 | 5240.25 | GOLD | TRUE |

### 🔍 Preview: `FCT_ORDERS` (Fact Table)
| order_sk | customer_sk | revenue_usd | margin_usd | order_date_day |
|:---|:---|:---|:---|:---|
| z9y8x7... | a1b2c3... | 249.99 | 150.00 | 2024-01-05 |

---

## ✅ Quality Assurance & Verification
At every step of this journey, dbt runs automated tests to ensure:
- **68/68 Tests Passing** across the entire pipeline.
- **Referential Integrity**: Every order is linked to a valid customer.
- **Data Freshness**: Source data is verified for recent arrival.
- **Logic Validation**: Order header totals are cross-checked against item sums.
