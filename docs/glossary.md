# 📖 Project Glossary & Terminology

## 📑 Strategy: Shared Context & Unified Language
To ensure seamless collaboration across engineering, analytics, and business platform teams, we use a **Standardized Lexicon**. All documentation and code comments should adhere to these definitions.

---

## 🏗️ Architectural Terms

### **ELT (Extract, Load, Transform)**
The architectural paradigm where data is "Landed" in its rawest state (Load) before any "Transformation" logic is applied.

### **Medallion Architecture**
Our data lifecycle framework:
- **Bronze (Stone)**: Raw staging area for data landing and normalization.
- **Silver (Silver)**: Intermediate layer where business logic and metrics are applied.
- **Gold (Gold)**: Final presentation layer (Analytical Marts) optimized for BI.

### **Idempotency**
The system's ability to produce the same predictable result even if a job is executed multiple times (crucial for failure recovery and backfills).

---

## 🛠️ dbt-Specific Terms

### **Model**
A single SQL file that represents a business concept (e.g., `fct_orders`).

### **Snapshot**
A specific type of dbt model that tracks historical changes (SCD Type 2) using `valid_from` and `valid_to` timestamps.

### **Materialization**
The way dbt persists a model in Snowflake. Our primary strategies are:
- **View**: A virtual table (minimal compute).
- **Table**: A physical table (high-performance scans).
- **Incremental**: A performance-optimized merge strategy that only processes new delta records.

### **Surrogate Key (SK)**
An internal, stable identifier (usually an MD5 hash) used for Joining models, decoupling them from upstream business keys.

---

## ❄️ Snowflake-Specific Terms

### **Warehouse**
Compute resources in Snowflake (measured in Sizes: X-Small, Small, etc.).

### **Micro-Partition**
Snowflake's physical storage unit (usually 50–500MB). Our **Pruning** strategies are designed to skip as many of these as possible during queries.

### **Clustering**
The physical sorting of data on disk. We cluster by `order_date` to optimize time-based reporting.

### **RBAC (Role-Based Access Control)**
The security model where permissions are granted to Roles (e.g., `LOADER`, `ANALYST`) and then roles are granted to Users.
