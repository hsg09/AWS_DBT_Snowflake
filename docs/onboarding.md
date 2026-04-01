# 🚀 Project Onboarding: Total Setup Guide

Welcome to the **AWS-dbt-Snowflake** platform. As a **Principal Data Engineer**, follow this linear track to initialize your cloud and local environments from scratch.

---

## 🏗️ Step 1: Cloud Foundation & Handshake

Before touching any code, the secondary cloud infrastructure must be provisioned and authorized.

### 1-A. AWS Infrastructure
1. Follow the [**AWS Setup Guide**](./aws_setup.md) to create your S3 bucket and IAM roles.
2. Ensure "Block all public access" is **ENABLED**.

### 1-B. Snowflake Foundations (RBAC)
Run the first two scripts in Snowflake as **ACCOUNTADMIN**:
1. `snowflake/00_rbac_setup.sql`: Establishes roles (`LOADER`, `TRANSFORMER`, `ANALYST`) and databases (`RAW`, `ANALYTICS`).
2. `snowflake/01_file_formats_and_stages.sql`: Executes the `STORAGE_AWS_IAM_USER_ARN` integration.

> [!IMPORTANT]
> **Complete the Handshake**: Follow the `DESCRIBE INTEGRATION` instructions in [**aws_setup.md Step 4**](./aws_setup.md#4-the-cloud-handshake-critical) before proceeding.

---

## 🛠️ Step 2: Local Environment Setup

We use **uv** for high-performance python dependency management. Ensure Python 3.12+ is installed.

```bash
# 1. Initialize environment & Install dependencies
uv sync

# 2. Activate virtual environment
source .venv/bin/activate

# 3. Create secrets local hydration file
cp .env.example .env
```

### 🔑 Secret Configuration:
Open `.env` and provide your Snowflake credentials. Ensure `SNOWFLAKE_ACCOUNT` is correctly formatted (e.g., `xy12345.us-east-1`).

---

## 🧊 Step 3: dbt Initialization

dbt sits at the core of our transformation layer. 

1. **Install dbt Packages**:
   ```bash
   dbt deps
   ```
2. **Connectivity Benchmark**:
   ```bash
   dbt debug
   ```
   > [!NOTE]
   > **How to verify**: All checks (Profile, Connection, etc.) must show **OK**.

---

## 💧 Step 4: Data Hydration (Initial Load)

Populate the "Bronze" layer by moving sample data into S3.

```bash
# 1. Use AWS CLI to move local sample data to your S3 prefix
BUCKET="your-company-datalake"
aws s3 cp sample_data/orders.csv      s3://${BUCKET}/raw/ecommerce/orders/
aws s3 cp sample_data/customers.json  s3://${BUCKET}/raw/ecommerce/customers/
aws s3 cp sample_data/order_items.csv s3://${BUCKET}/raw/ecommerce/order_items/
aws s3 cp sample_data/products.csv    s3://${BUCKET}/raw/ecommerce/products/

# 2. Verify Snowflake can see the files
# SQL Role: SYSADMIN
LS @RAW.ECOMMERCE.S3_RAW_STAGE;
```

---

## ✅ Step 5: Full SQL Pipeline Implementation

Execute the remaining **logic layer** scripts in Snowflake in this exact order:

| Step | Script | Functional Responsibility |
| :--- | :--- | :--- |
| **3** | `snowflake/02_metadata_and_control_tables.sql`| Audit logs & ingestion control tables. |
| **4** | `snowflake/03_dynamic_schema_procedure.sql`| Snowpark Python (DDL inference engine). |
| **5** | `snowflake/04_streams_and_tasks.sql` | CDC Streams & Root Ingestion Tasks. |
| **6** | `snowflake/05_data_masking.sql` | PII Dynamic Redaction Policies. |

> [!CAUTION]
> **Activation Step**: Snowflake tasks are created in a `SUSPENDED` state. To start the automation, you must run:
> `ALTER TASK RAW.ECOMMERCE.TASK_INFER_SCHEMA RESUME;`

---

## 📅 Step 6: Airflow Orchestration

Finally, launch the "Control Plane" of the architecture.

```bash
# 1. Start Airflow 3 with stability overrides
./start_airflow.sh
```

### ⚙️ UI Setup Connection:
1. Navigate to `http://localhost:8081`. 
2. Go to **Admin** → **Connections** → Edit `snowflake_default`.
3. Provide your Snowflake parameters for Role, Warehouse, and Database.

---

## 🚦 Troubleshooting & FAQ

| Issue | Resolution |
| :--- | :--- |
| **dbt Connection Error**| Ensure your `.env` variables match your Snowflake credentials and role permissions. |
| **Access Denied in S3** | Re-run `DESC INTEGRATION` and confirm the `External ID` in the AWS IAM Role Trust Policy. |
| **Profile Not Found** | Ensure `profiles.yml` is correctly referenced in the project root or passed via `-p`. |

---

## ✅ Final Delivery Checklist
- [x] Snowflake Warehouses & Roles created.
- [x] AWS-Snowflake Handshake successful (`LS @STAGE` works).
- [x] `dbt debug` shows green connectivity.
- [x] `TASK_INFER_SCHEMA` is in `STARTED` state.
