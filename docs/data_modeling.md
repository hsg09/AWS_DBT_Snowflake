# 📐 Data Modeling: Kimball Star Schema

## 📑 Strategy: High-Performance Analytical Grain
Our warehouse is modeled using the **Kimball Star Schema** methodology, designed to minimize join complexity for BI tools while maximizing query performance through **micro-partition pruning**.

---

## 🏗️ The Dimensional Model (Gold Layer)

### 1. Fact Tables (`fct_orders`)
- **Grain**: One row per analytical unit (e.g., one row per customer order).
- **Materialization**: `incremental` for scalability.
- **Attributes**: Numeric, additive measures (revenue, cost, tax).
- **Foreign Keys**: Joined to Dimensions via stable Surrogate Keys (SK).

### 2. Dimension Tables (`dim_customers`, `dim_products`)
- **Grain**: One row per unique business entity.
- **Materialization**: `table`.
- **Attributes**: Categorical, descriptive fields (segment, category, brand).

---

## 📋 Sample Output Data (Gold / BI Ready)

The following tables represent the final analytical state available to BI tools and business analysts.

### 1. Final Fact Table (`FCT_ORDERS`)
| order_sk | customer_sk | revenue_usd | margin_usd | order_date |
| :--- | :--- | :--- | :--- | :--- |
| z9y8x7... | a1b2c3... | 249.99 | 150.00 | 2024-03-10 |
| y8x7w6... | b2c3d4... | 89.50 | 45.00 | 2024-03-11 |

### 2. Final Dimension Table (`DIM_CUSTOMERS`)
| customer_id | ltv_usd | rfm_segment | is_active |
| :--- | :--- | :--- | :--- |
| CUST-005 | 2490.50 | Champions | TRUE |
| CUST-006 | 150.00 | At Risk | TRUE |

---

## 🔑 Surrogate Key (SK) Strategy: MD5 Hashing
We avoid using raw business keys (e.g., `order_id`) directly in analytical joins. Instead, all tables generate an internal **Surrogate Key** using MD5 hashing via the `generate_surrogate_key` macro.

### Rationale:
1. **Stability**: SKs remain consistent across schema restarts and data re-runs.
2. **Performance**: Snowflake processes Fixed-length hashes efficiently during join operations.
3. **Cross-Sourcing**: Easily handle entities coming from multiple upstream sources.

**Example SK generation:**
```sql
{{ generate_surrogate_key(['order_id', 'customer_id']) }} AS order_sk
```

---

## 🕰️ Slowly Changing Dimensions (SCD) Type 2
For core entities (Customers), we track historical state changes. This enables "As-Of" reporting (e.g., "What was this customer's loyalty segment on the day they placed this order?").

### Implementation via `snap_customers`:
- **Current View**: `dim_customers` filters the snapshot for `is_current = TRUE` (where `dbt_valid_to` is NULL).
- **Historical View**: Analysts can join the snapshot to `fct_orders` based on `order_date` falling between `dbt_valid_from` and `dbt_valid_to`.

---

## ✅ Modeling Guidelines & Constraints
1. **No Circular Dependencies**: dbt's DAG is audited to prevent recursive referencing.
2. **Nullable Dimensions**: All dimensions are joined via `LEFT JOIN` in our marts to prevent dropping records with missing dimensional attributes.
3. **Auditability**: Every model must include `_dbt_updated_at` (Macro-generated) for lineage and freshness tracking.
