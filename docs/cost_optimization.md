# 💰 Cost Optimization & Performance Tuning

## 📑 Strategy: Maximizing Performance-to-Credit Ratio
As a Senior Data Architect, our global goal is to maintain a high **Performance-to-Credit ratio** by minimizing unnecessary scanning and maximizing warehouse idle-time.

---

## ⚡ Technical Implementation: Warehouse Efficiency

### 1. Auto-Suspend & Auto-Resume
All project warehouses (`LOADER_WH`, `TRANSFORMER_WH`, `ANALYST_WH`) are configured with a **60-second auto-suspend**.
- **Rationale**: Prevents credit consumption during periods of inactivity.
- **Impact**: Significant cost savings on low-frequency dev/test runs.

### 2. Multi-Cluster Scaling
Production warehouses use Snowflake's **Standard Scaling Policy** (Max: 2-clusters) to handle unpredictable BI query spikes.

---

## 🏗️ Storage Optimization & Pruning

### 1. Micro-Partition Pruning
Our pipeline is designed for **Minimal Scanning**.
- **Strategy**: 100% of analytical queries filter on `order_date` or `_dbt_updated_at`.
- **Implementation**: Snowflake leverages these column statistics to skip partitions that don't match the query filter, often reducing scan costs by 80-90%.

### 2. Clustering Strategy
Large fact tables (e.g., `fct_orders`) use automated **Clustering Keys**.
- **Clustering Column**: `order_date` (Linear correlation with typical reporting windows).
- **Maintenance**: Periodically monitored via `SYSTEM$CLUSTERING_INFORMATION`.

---

## 🛠️ Compute Optimization in dbt

### 1. Incremental Materialization
By using a **3-day lookback window** in `fct_orders`, we process only the delta records instead of rebuilding the entire table history.
```sql
-- Pattern for incremental lookback
WHERE _LOADED_AT >= (SELECT DATEADD('day', -3, MAX(_raw_loaded_at)) FROM {{ this }})
```
- **Cost Impact**: Reduces daily processing time from hours to minutes.

### 2. Deferral and Slim CI
Our CI/CD pipeline uses the `--defer` flag to point to production tables for non-modified models.
- **Resource Impact**: Prevents rebuilding and re-testing 100% of the warehouse for every small PR.

---

## ⌚ Monitoring & Alerting
We track Snowflake credit consumption via the `ACCOUNT_USAGE` schema.
- **Alert**: Triggered if daily credit spend exceeds 150% of the rolling 7-day average.
- **Audit**: Every query is tagged with a `QUERY_TAG` (Macro-generated) containing the dbt `model_name` for precise cost-attribution.
