# 🚀 CI/CD & Development Lifecycle: `GitHub Actions`

## 📑 Strategy: High-Velocity Data Engineering
To maintain a high quality-bar while ensuring fast delivery, we use a **Continuous Integration (CI)** pipeline powered by **GitHub Actions** and **dbt Slim CI**.

---

## 🏗️ Automated Workflows

### 1. Pull Request (PR) CI/CD
Triggered on every submission to a release branch.
- **Goal**: Verify that new code compiles and doesn't break downstream dependencies.
- **Slim CI**: Uses `dbt --select state:modified+` to build and test **only** the models that have changed, plus their first-degree children.
- **Dry-Run**: Ingests sample data into a transient `PR_CHECK` schema to verify SQL validity.

### 2. Production Merge
Triggered on merge to `main`.
- **Goal**: Full-load verification of the environment.
- **CD**: Updates all dbt model versions in the `PROD` database and executes the full 68-test suite.

---

## 🛠️ Environment Isolation Configuration

| Environment | Purpose | Target Database |
| :--- | :--- | :--- |
| **Local Dev** | Feature engineering. | `ANALYTICS.DEV_{USER}` |
| **Slim CI** | PR verification. | `ANALYTICS.PR_CHECK` |
| **Production** | Strategic reporting. | `ANALYTICS.MARTS` |

---

## ⚙️ Technical Implementation: `state:modified`
Our CI pipeline is designed for **Minimal Compute Waste**. By generating a `manifest.json` on every production run, we can compare the incoming PR code and only execute the delta:

```bash
# Example CI command
dbt run --select state:modified+ --defer --state ./target-manifest
```
> [!TIP]
> **Deferral**: The `--defer` flag allows CI runs to reference production tables for non-modified models, significantly reducing PR build times.

---

## 🚦 Deployment Controls & Checkpoints
- **Pull Request Approval**: Minimum 1 peer review from a **Senior Data Engineer**.
- **Automated Blockers**: Merges are blocked if:
    - Any dbt test fails.
    - SQLFluff linting rules are violated.
    - Code coverage for a new model is < 80%.
- **Versioning**: All dbt runs are tagged with the GitHub Commit SHA for end-to-end traceability from the Snowflake query back to the code change.
