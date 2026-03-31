# 🛡️ Data Security & Governance Strategy

## 📑 Strategy: Principle of Least Privilege (PoLP)
Our global security model is designed to enforce the **Principle of Least Privilege (PoLP)** while maintaining maximum visibility for data engineering and platform teams across the Snowflake ecosystem.

---

## 🏗️ Snowflake RBAC Hierarchy
Access is strictly segmented via functional roles to prevent cross-database contamination and unauthorized PII exposure.

| Role | Target Database | Access Level | Responsibilities |
| :--- | :--- | :--- | :--- |
| **LOADER** | `RAW` | `Usage`, `Create` | Snowpark execution, S3 file ingestion. |
| **TRANSFORMER** | `RAW`, `ANALYTICS` | `Select`, `Materialize` | dbt modeling, snapshot generation. |
| **ANALYST** | `ANALYTICS` (Marts Only)| `Select` | BI visualization, SQL discovery (PII Masked). |
| **DATA_ENGINEER**| All | `Full` | Infrastructure maintenance, DDL, testing. |

### Compute Isolation:
Each role is assigned a **dedicated warehouse** (e.g., `LOADER_WH`, `TRANSFORMER_WH`) to ensure data loading tasks do not compete for resources with heavy analytical queries.

---

## 🔒 Dynamic Data Masking: PII Protection
Personal Identifiable Information (PII) is protected using **Snowflake Dynamic Data Masking**. This ensures data is masked at the query level for unauthorized roles.

### Implementation Logic:
- **Policy**: `DYNAMIC_MASK_STRING`
- **Target Fields**: `email`, `phone` in `STG_RAW__CUSTOMERS` and `DIM_CUSTOMERS`.
- **Logic**: Privileged roles (`TRANSFORMER`, `DATA_ENGINEER`) see the full value; all other roles (`ANALYST`, `PUBLIC`) see a redacted version.

**Redaction Example (Analyst View):**
| Original | Masked |
| :--- | :--- |
| `james.wilson@example.com` | `j****@example.com` |
| `555-123-4567` | `***-***-4567` |

---

## 🔑 Credential Lifecycle Management
Credentials (e.g., `SNOWFLAKE_PASSWORD`) are never committed to the repository. They are managed via:
1. **GitHub Secrets**: For automated CI/CD pipeline execution.
2. **Local `.env`**: For development-mode hydration, ignored via `.gitignore`.
3. **IAM Role Trust**: All AWS-to-Snowflake connectivity is handled via IAM roles with time-bounded external IDs, preventing the need for fixed AWS Access Keys.

---

## 🚦 Security Constraints & Compliance
1. **Network Policy**: Access to the Snowflake instance is whitelist-restricted to corporate VPN ranges.
2. **Storage Integration**: All S3 stages use an `IDENTITY_ROLE` that only allows `GET` operations on specific `raw/` prefixes.
3. **Lineage Privacy**: dbt metadata and `dbt docs` are hosted on internal-only servers to prevent external exposure of our internal schema architecture.
