# End-to-End Execution Guide

Complete step-by-step instructions to get the pipeline running from scratch.

---

## Overview

```
PHASE 1 — AWS Setup         (S3 bucket + IAM role)
PHASE 2 — Snowflake Setup   (run SQL scripts 00 → 05)
PHASE 3 — Local dbt Setup   (env vars + profiles)
PHASE 4 — Run dbt Pipeline  (deps → seed → snapshot → run → test)
PHASE 5 — Verify Results    (query Snowflake tables)
PHASE 6 — Airflow (optional)
PHASE 7 — CI/CD (optional)
```

---

## PHASE 1 — AWS Setup

### Step 1.1 — Create S3 Bucket

Go to **AWS Console → S3 → Create Bucket**

```
Bucket name:   your-data-lake-bucket          ← replace throughout
Region:        us-east-1  (match Snowflake account region)
Versioning:    Disabled (COPY INTO handles idempotency)
Encryption:    SSE-S3 (minimum) or SSE-KMS
Block public access: ✅ ON (all 4 options)
```

Create this folder structure inside the bucket:

```
s3://your-data-lake-bucket/
└── raw/
    └── ecommerce/
        ├── orders/
        ├── customers/
        ├── order_items/
        └── products/
```

> [!TIP]
> In the AWS Console: after creating the bucket, click **Create folder** four times for each entity path above.

---

### Step 1.2 — Upload Sample Data Files

```bash
# From your project directory
cd /path/to/AWS_DBT_Snowflake/sample_data

BUCKET="your-data-lake-bucket"

aws s3 cp orders.csv      s3://${BUCKET}/raw/ecommerce/orders/orders_2024_01.csv
aws s3 cp customers.json  s3://${BUCKET}/raw/ecommerce/customers/customers_2024_01.json
aws s3 cp order_items.csv s3://${BUCKET}/raw/ecommerce/order_items/order_items_2024_01.csv
aws s3 cp products.csv    s3://${BUCKET}/raw/ecommerce/products/products_2024_01.csv
```

---

### Step 1.3 — Create IAM Role for Snowflake

Go to **AWS Console → IAM → Roles → Create Role**

**Step A: Choose trusted entity**
- Select: `AWS account`
- Account ID: `your own AWS account ID` (you'll update this after Snowflake generates a trust policy)
- Tick: `Require external ID` → put a placeholder like `0000` (updated in Step 2.4)

**Step B: Attach permissions policy — create a new inline policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::your-data-lake-bucket",
        "arn:aws:s3:::your-data-lake-bucket/raw/*"
      ]
    }
  ]
}
```

**Step C: Name the role**
```
Role name: snowflake-s3-reader-role
```

Copy the **Role ARN** — you'll need it in the next step. Format:
```
arn:aws:iam::123456789012:role/snowflake-s3-reader-role
```

---

## PHASE 2 — Snowflake Setup

> [!IMPORTANT]
> Run all scripts in the **Snowflake Worksheet** (or SnowSQL). Run each file **in order 00 → 05**.

### Step 2.1 — Edit placeholders before running

Open [`snowflake/01_file_formats_and_stages.sql`](./snowflake/01_file_formats_and_stages.sql) and replace:

```sql
-- Line ~30: replace with your IAM role ARN
STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake-s3-reader-role'

-- Line ~33: replace with your bucket
STORAGE_ALLOWED_LOCATIONS = ('s3://your-data-lake-bucket/raw/')

-- Lines ~56–78: replace stage URLs with your bucket
URL = 's3://your-data-lake-bucket/raw/ecommerce/orders/'
-- ... (same for customers, order_items, products stages)
```

---

### Step 2.2 — Run `00_rbac_setup.sql`

```
Role required: ACCOUNTADMIN
```

Open Snowflake Worksheet → paste entire content of [`snowflake/00_rbac_setup.sql`](./snowflake/00_rbac_setup.sql) → **Run All**

This creates:
- ✅ Warehouses: `LOADER_WH`, `TRANSFORMER_WH`, `ANALYST_WH`, `ADMIN_WH`
- ✅ Databases: `RAW`, `ANALYTICS`, `AUDIT`
- ✅ Schemas: `RAW.ECOMMERCE`, `ANALYTICS.STAGING/INTERMEDIATE/MARTS`, `AUDIT.CONTROL`
- ✅ Roles: `LOADER`, `TRANSFORMER`, `ANALYST`, `DATA_ENGINEER`
- ✅ Service accounts: `SVC_LOADER`, `SVC_TRANSFORMER`

---

### Step 2.3 — Run `01_file_formats_and_stages.sql`

```
Role required: ACCOUNTADMIN (for storage integration), then SYSADMIN
```

**Run All** → this creates the `S3_ECOMMERCE_INT` storage integration.

After running, execute this to get the Snowflake IAM identity:

```sql
DESCRIBE INTEGRATION S3_ECOMMERCE_INT;
```

Copy two values from the output:
| Field | Example Value |
|---|---|
| `STORAGE_AWS_IAM_USER_ARN` | `arn:aws:iam::123412341234:user/abc-xyz` |
| `STORAGE_AWS_EXTERNAL_ID` | `ABC12345_SFCRole=2_Xy...` |

---

### Step 2.4 — Update the IAM Role Trust Policy (back in AWS)

Go to **AWS Console → IAM → Roles → `snowflake-s3-reader-role` → Trust relationships → Edit**

Replace the trust policy with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123412341234:user/abc-xyz"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "ABC12345_SFCRole=2_Xy..."
        }
      }
    }
  ]
}
```

> Fill in the exact `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` values you copied above.

---

### Step 2.5 — Verify S3 connectivity from Snowflake

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE ADMIN_WH;

-- Should list your uploaded files (no error = S3 trust works ✅)
LIST @RAW.ECOMMERCE.S3_ORDERS_STAGE;
LIST @RAW.ECOMMERCE.S3_CUSTOMERS_STAGE;
LIST @RAW.ECOMMERCE.S3_ORDER_ITEMS_STAGE;
LIST @RAW.ECOMMERCE.S3_PRODUCTS_STAGE;
```

Expected output: 1 file listed per stage.

---

### Step 2.6 — Run `02_metadata_and_control_tables.sql`

```
Role required: SYSADMIN
```

**Run All** → Creates:
- ✅ `AUDIT.CONTROL.FILE_INGESTION_LOG`
- ✅ `AUDIT.CONTROL.SCHEMA_REGISTRY`
- ✅ `AUDIT.CONTROL.TASK_EXECUTION_LOG`
- ✅ `AUDIT.CONTROL.DQ_RESULTS`
- ✅ Helper views (`V_FILE_INGESTION_LATEST`, `V_FILES_PENDING_RETRY`)

---

### Step 2.7 — Run `03_dynamic_schema_procedure.sql`

```
Role required: SYSADMIN
```

**Run All** → Deploys the `INFER_AND_CREATE_TABLE` Snowpark Python stored procedure.

**Test it manually** (optional but recommended):

```sql
USE ROLE LOADER;
USE WAREHOUSE LOADER_WH;

-- Infer schema from orders CSV and create the raw table
CALL RAW.ECOMMERCE.INFER_AND_CREATE_TABLE(
    'orders',
    '@RAW.ECOMMERCE.S3_ORDERS_STAGE',
    'RAW.ECOMMERCE.FF_CSV',
    'RAW',
    'ECOMMERCE',
    'manual_test_001'
);

-- Check the table was created
SHOW TABLES IN SCHEMA RAW.ECOMMERCE;
DESCRIBE TABLE RAW.ECOMMERCE.ORDERS;
```

---

### Step 2.8 — Run `04_streams_and_tasks.sql`

```
Role required: SYSADMIN
```

**Run All** → Creates raw tables (bootstrap DDLs), Streams, Tasks, and `LOAD_ENTITY_FROM_STAGE` procedure.

**Load sample data now** using COPY INTO:

```sql
USE ROLE LOADER;
USE WAREHOUSE LOADER_WH;

-- Load all 4 entities from S3
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE('orders',     '@RAW.ECOMMERCE.S3_ORDERS_STAGE/',     'RAW.ECOMMERCE.FF_CSV',  'manual_load_001');
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE('customers',  '@RAW.ECOMMERCE.S3_CUSTOMERS_STAGE/',  'RAW.ECOMMERCE.FF_JSON', 'manual_load_001');
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE('order_items','@RAW.ECOMMERCE.S3_ORDER_ITEMS_STAGE/','RAW.ECOMMERCE.FF_CSV',  'manual_load_001');
CALL RAW.ECOMMERCE.LOAD_ENTITY_FROM_STAGE('products',   '@RAW.ECOMMERCE.S3_PRODUCTS_STAGE/',   'RAW.ECOMMERCE.FF_CSV',  'manual_load_001');
```

**Verify rows loaded:**

```sql
SELECT 'orders'      AS entity, COUNT(*) AS rows_count FROM RAW.ECOMMERCE.ORDERS      UNION ALL
SELECT 'customers'   AS entity, COUNT(*) AS rows_count FROM RAW.ECOMMERCE.CUSTOMERS    UNION ALL
SELECT 'order_items' AS entity, COUNT(*) AS rows_count FROM RAW.ECOMMERCE.ORDER_ITEMS  UNION ALL
SELECT 'products'    AS entity, COUNT(*) AS rows_count FROM RAW.ECOMMERCE.PRODUCTS;
-- Expected: 30 | 26 | 52 | 30
```

---

### Step 2.9 — Run `05_data_masking.sql`

```
Role required: ACCOUNTADMIN
```

**Run All** → Applies masking policies to `CUSTOMERS.EMAIL` and `CUSTOMERS.PHONE`.

Test masking:
```sql
USE ROLE ANALYST;
SELECT CUSTOMER_ID, EMAIL, PHONE FROM RAW.ECOMMERCE.CUSTOMERS LIMIT 3;
-- EMAIL should show: ****@example.com  | PHONE: ***-***-0101

USE ROLE TRANSFORMER;
SELECT CUSTOMER_ID, EMAIL, PHONE FROM RAW.ECOMMERCE.CUSTOMERS LIMIT 3;
-- Should show full values ✅
```

---

## PHASE 3 — Local dbt Setup

### Step 3.1 — Activate virtual environment

```bash
cd /path/to/AWS_DBT_Snowflake
source .venv/bin/activate

# Verify dbt is available
dbt --version
# Expected: dbt Core: 1.11.x | Installed: dbt-snowflake 1.11.x
```

---

### Step 3.2 — Set environment variables

Add these to your `~/.zshrc` (or set in terminal session for testing):

```bash
export SNOWFLAKE_ACCOUNT="xy12345.us-east-1"     # from Snowflake Admin → Account URL
export SNOWFLAKE_USER="your_username"              # your personal Snowflake user
export SNOWFLAKE_PASSWORD="MySuperSecretPassword123!" # replace with your actual password
export SNOWFLAKE_ROLE="DATA_ENGINEER"
export SNOWFLAKE_WAREHOUSE="TRANSFORMER_WH"
export SNOWFLAKE_DATABASE="ANALYTICS"
export DBT_DEV_USER="yourname"                    # creates DEV_YOURNAME schema in Snowflake
```

> [!TIP]
> Find your `SNOWFLAKE_ACCOUNT` in Snowflake UI: bottom-left corner → hover over your account name → copy the **Account Identifier** (format: `orgname-accountname` or `xy12345.us-east-1`). Do **not** include `.snowflakecomputing.com`.

---

### Step 3.3 — Copy profiles.yml and test connection

```bash
mkdir -p ~/.dbt
cp profiles.yml ~/.dbt/profiles.yml

# Test the connection
dbt debug --profiles-dir ~/.dbt --target dev
```

Expected output:
```
  Connection test: OK
  Connection:
    account: xy12345.us-east-1
    role: DATA_ENGINEER
    database: ANALYTICS
    schema: DEV_YOURNAME
    warehouse: TRANSFORMER_WH
```

---

## PHASE 4 — Run the dbt Pipeline

Run these commands **in order** from your project directory:

### Step 4.1 — Install dbt packages

```bash
dbt deps --profiles-dir ~/.dbt
```

Downloads `dbt-utils`, `dbt-expectations`, `audit_helper`, `dbt_date` into `dbt_packages/`.

---

### Step 4.2 — Load seeds (reference tables)

```bash
dbt seed --profiles-dir ~/.dbt --target dev
```

Loads into Snowflake:
- `COUNTRY_CODES` (25 rows)
- `PRODUCT_CATEGORIES` (19 rows)

---

### Step 4.3 — Run staging layer

```bash
dbt run --profiles-dir ~/.dbt --target dev --select tag:staging
```

Creates:
- `STG_RAW__ORDERS` — 30 rows after dedup
- `STG_RAW__CUSTOMERS` — 26 rows, JSON flattened from VARIANT
- `STG_RAW__ORDER_ITEMS` — 52 rows
- `STG_RAW__PRODUCTS` — 30 rows

---

### Step 4.4 — Test staging layer

```bash
dbt test --profiles-dir ~/.dbt --target dev --select tag:staging --store-failures
```

Expected: all tests pass. If any fail, check `target/run_results.json` for details.

---

### Step 4.5 — Run SCD Snapshot (must run before marts)

```bash
dbt snapshot --profiles-dir ~/.dbt --target dev
```

Creates `ANALYTICS.SNAPSHOTS.SNAP_CUSTOMERS` with `dbt_valid_from` / `dbt_valid_to` columns.

> [!IMPORTANT]
> Always run `dbt snapshot` **after** staging and **before** `dbt run --select tag:marts`. The `dim_customers` mart reads from this snapshot!

---

### Step 4.6 — Run intermediate layer

```bash
dbt run --profiles-dir ~/.dbt --target dev --select tag:intermediate
```

Creates:
- `INT_ORDERS__ENRICHED` — orders enriched with customer + item aggregates
- `INT_CUSTOMERS__LIFETIME_VALUE` — LTV + RFM scores per customer

---

### Step 4.7 — Run marts layer

```bash
dbt run --profiles-dir ~/.dbt --target dev --select tag:marts
```

Creates:
- `FCT_ORDERS` — 30 rows, incremental fact table with surrogate key
- `DIM_CUSTOMERS` — 26 rows with LTV, RFM segment, `is_current = TRUE`
- `DIM_PRODUCTS` — 30 rows with margin tier and parent category

---

### Step 4.8 — Run all tests (including custom singular tests)

```bash
dbt test --profiles-dir ~/.dbt --target dev --store-failures
```

Runs schema tests (`unique`, `not_null`, `accepted_values`, `relationships`), `dbt_expectations` range tests, and 3 custom singular tests.

---

### Step 4.9 — Check source freshness

```bash
dbt source freshness --profiles-dir ~/.dbt --target dev
```

---

### Step 4.10 — Generate and serve docs

```bash
dbt docs generate --profiles-dir ~/.dbt --target dev
dbt docs serve --port 8080
# Open: http://localhost:8080
```

---

## PHASE 5 — Verify Results in Snowflake

Run these queries in Snowflake Worksheet:

```sql
USE ROLE DATA_ENGINEER;
USE WAREHOUSE TRANSFORMER_WH;

-- 1. Staging row counts (replace DEV_YOURNAME with your DBT_DEV_USER value)
SELECT 'stg_orders'      , COUNT(*) FROM ANALYTICS.DEV_YOURNAME_STAGING.STG_RAW__ORDERS      UNION ALL
SELECT 'stg_customers'   , COUNT(*) FROM ANALYTICS.DEV_YOURNAME_STAGING.STG_RAW__CUSTOMERS   UNION ALL
SELECT 'stg_order_items' , COUNT(*) FROM ANALYTICS.DEV_YOURNAME_STAGING.STG_RAW__ORDER_ITEMS UNION ALL
SELECT 'stg_products'    , COUNT(*) FROM ANALYTICS.DEV_YOURNAME_STAGING.STG_RAW__PRODUCTS;

-- 2. Fact table
SELECT order_sk, order_id, order_status, revenue_usd, order_date_day
FROM ANALYTICS.DEV_YOURNAME_MARTS.FCT_ORDERS
ORDER BY order_date_day
LIMIT 10;

-- 3. Customer dimension with RFM
SELECT customer_id, customer_segment, rfm_segment, lifetime_value_usd, total_orders, is_active
FROM ANALYTICS.DEV_YOURNAME_MARTS.DIM_CUSTOMERS
ORDER BY lifetime_value_usd DESC;

-- 4. Revenue by country
SELECT billing_country_code, COUNT(*) AS orders, SUM(revenue_usd) AS total_revenue
FROM ANALYTICS.DEV_YOURNAME_MARTS.FCT_ORDERS
GROUP BY 1 ORDER BY total_revenue DESC;

-- 5. Ingestion audit
SELECT target_table, load_status, rows_loaded, completed_at
FROM AUDIT.CONTROL.FILE_INGESTION_LOG
ORDER BY completed_at DESC;

-- 6. SCD snapshot check
SELECT customer_id, customer_segment, dbt_valid_from, dbt_valid_to, dbt_valid_to IS NULL AS is_current
FROM ANALYTICS.SNAPSHOTS.SNAP_CUSTOMERS
ORDER BY customer_id;
```

---

## PHASE 6 — Airflow Setup (Optional)

Only needed for automated 15-minute scheduling.

```bash
pip install apache-airflow apache-airflow-providers-snowflake

# Set Airflow variables
airflow variables set DBT_PROJECT_DIR /path/to/AWS_DBT_Snowflake
airflow variables set DBT_PROFILES_DIR ~/.dbt
airflow variables set DBT_TARGET prod

# Configure Snowflake connection
airflow connections add snowflake_default \
  --conn-type snowflake \
  --conn-host ${SNOWFLAKE_ACCOUNT}.snowflakecomputing.com \
  --conn-login ${SNOWFLAKE_USER} \
  --conn-password ${SNOWFLAKE_PASSWORD} \
  --conn-extra '{"role": "TRANSFORMER", "warehouse": "TRANSFORMER_WH", "database": "ANALYTICS", "schema": "STAGING"}'

# Copy DAG and trigger
cp airflow/dags/elt_pipeline_dag.py ~/airflow/dags/
airflow dags trigger elt_pipeline
```

---

## PHASE 7 — CI/CD Setup (Optional)

Configure GitHub Secrets at: **GitHub → your repo → Settings → Secrets and variables → Actions**

| Secret Name | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | `xy12345.us-east-1` |
| `SNOWFLAKE_USER` | `SVC_TRANSFORMER` |
| `SNOWFLAKE_PASSWORD` | service account password |
| `SNOWFLAKE_ROLE` | `TRANSFORMER` |
| `SNOWFLAKE_WAREHOUSE` | `TRANSFORMER_WH` |
| `SNOWFLAKE_DATABASE` | `ANALYTICS` |
| `SLACK_WEBHOOK_URL` | your Slack webhook (optional) |

The pipeline auto-triggers on every PR and every merge to `main`.

---

## Quick Reference — Full Pipeline Cheatsheet

```bash
# Full pipeline in one block (after setup is complete)
source .venv/bin/activate
dbt deps             --profiles-dir ~/.dbt --target dev
dbt seed             --profiles-dir ~/.dbt --target dev
dbt snapshot         --profiles-dir ~/.dbt --target dev
dbt run              --profiles-dir ~/.dbt --target dev --select tag:staging
dbt test             --profiles-dir ~/.dbt --target dev --select tag:staging
dbt run              --profiles-dir ~/.dbt --target dev --select tag:intermediate
dbt run              --profiles-dir ~/.dbt --target dev --select tag:marts
dbt test             --profiles-dir ~/.dbt --target dev
dbt source freshness --profiles-dir ~/.dbt --target dev
dbt docs generate    --profiles-dir ~/.dbt --target dev && dbt docs serve

# Useful debugging commands
dbt compile  --profiles-dir ~/.dbt --select stg_raw__orders
dbt run      --profiles-dir ~/.dbt --select stg_raw__orders --full-refresh
dbt test     --profiles-dir ~/.dbt --select stg_raw__orders
```

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `dbt debug` fails: "Could not connect" | Wrong `SNOWFLAKE_ACCOUNT` format | Use `orgname-accountname` — no `.snowflakecomputing.com` suffix |
| `LIST @stage` returns empty | IAM trust policy not updated | Complete Step 2.4 with correct ARN + External ID |
| `COPY INTO` 0 rows loaded | File path mismatch | Confirm file exists with `LIST @stage`, check file format |
| `dbt run` fails: "Object does not exist" | Raw tables not created | Run Step 2.7 (`INFER_AND_CREATE_TABLE`) + Step 2.8 (load data) first |
| Masking policy error on `ALTER COLUMN` | Policy already applied | Run `ALTER TABLE ... MODIFY COLUMN ... UNSET MASKING POLICY` first |
| `dbt test` fails: relationship test | Snapshot not run yet | Always run `dbt snapshot` before `dbt run --select tag:marts` |
