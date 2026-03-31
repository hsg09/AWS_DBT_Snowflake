# 🚀 Technical Walkthrough: Pipeline Stabilization & Fixes

This walkthrough documents the critical engineering fixes and optimizations applied to the Snowflake ELT pipeline to ensure production-readiness, type-safety, and historical accuracy.

---

## 🛠️ Summary of Key Fixes

### 1. Dynamic Ingestion & Type Stabilization
**Issue:** The automated Python ingestion procedure was inferring numeric columns (like `DISCOUNT_PCT`) as high-precision decimals, but the dbt staging models were using `TRY_CAST` which failed on already-numeric types in Snowflake.
**Fix:** 
- Standardized the staging layer to use explicit `CAST` instead of `TRY_CAST` since schemas are now pre-validated by the ingestion layer.
- Widened column precision for `DISCOUNT_PCT` from `NUMBER(5,4)` to `NUMBER(5,2)` to prevent overflow errors from values like `55.00`.

### 2. SQL Compilation & Incremental Logic
**Issue:** The `stg_raw__orders` model failed during incremental runs due to a correlated subquery aggregate bug (`MAX(_loaded_at)`).
**Fix:** Renamed the internal reference to `_raw_loaded_at` to match the target table's schema, resolving the "Subquery containing correlated aggregate function" compilation error.

### 3. Snowflake Optimization (Post-Hook Fix)
**Issue:** The `marts` layer failed because of a legacy `ANALYZE TABLE` post-hook. Snowflake manages statistics automatically and does not support this syntax.
**Fix:** Removed the `ANALYZE` post-hooks from `dbt_project.yml` to align with Snowflake's cloud-native architecture.

### 4. SCD Type 2 Implementation
**Feature:** Implemented `snapshots/snap_customers.sql` to track historical changes to customer segments and loyalty status.
**Result:** Verified that `dbt snapshot` correctly manages `dbt_valid_to` and `dbt_valid_from` columns, enabling downstream point-in-time analysis.

---

## ✅ Final Validation Results

### dbt Test Suite
Executed a full suite of **68 data tests** covering:
- **Unique/Not Null**: 100% compliance on primary keys.
- **Referential Integrity**: 100% join success between Facts and Dimensions.
- **Data Logic**: Gross margin and revenue totals cross-verified successfully.

### Pipeline Execution Status
| Phase | Status | Command |
|:---|:---|:---|
| **Seeds** | ✅ Pass | `dbt seed` |
| **Staging** | ✅ Pass | `dbt run --select tag:staging` |
| **Snapshots** | ✅ Pass | `dbt snapshot` |
| **Marts** | ✅ Pass | `dbt run --select tag:marts` |
| **Tests** | ✅ Pass | `dbt test` |

---

## 📂 Documentation Links
- [**Data Transformation Journey**](../DATA_TRANSFORMATION_JOURNEY.md): See the life of a record from S3 to Marts.
- [**Execution Guide**](./EXECUTION_GUIDE.md): Step-by-step setup instructions.
