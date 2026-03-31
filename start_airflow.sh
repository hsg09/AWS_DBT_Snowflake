#!/bin/bash
# ---------------------------------------------------------------------------
# Script to start Airflow 3 with stable environment and port mapping
# ---------------------------------------------------------------------------

# 1. Set Airflow Home
export AIRFLOW_HOME="$(pwd)/airflow"

# 2. Source Snowflake credentials from .env
if [ -f .env ]; then
    echo "Loading Snowflake credentials from .env..."
    export $(grep -v '^#' .env | xargs)
else
    echo "WARNING: .env file not found."
fi

# 3. Activate Virtual Environment
if [ -d .venv ]; then
    echo "Activating virtual environment (.venv)..."
    source .venv/bin/activate
else
    echo "WARNING: .venv not found. Ensure your virtualenv is set up."
fi

# 4. Airflow 3 / macOS Stability Overrides
# ---------------------------------------------------------------------------
export AIRFLOW__WEBSERVER__WEB_SERVER_PORT=8081
export AIRFLOW__CORE__PARALLELISM=4
export AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG=4

# [KEY FIX 1] Ensure workers talk to the correct Execution API port (8081)
export AIRFLOW__CORE__EXECUTION_API_SERVER_URL="http://localhost:8081/execution/"

# [KEY FIX 2] Fix macOS fork crashes (disables fork safety initialized check)
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

# [KEY FIX 3] Use fresh processes instead of forks to avoid state issues
export AIRFLOW__CORE__EXECUTE_TASKS_NEW_PYTHON_INTERPRETER=True

# [KEY FIX 4] Prevent macOS from querying network/proxy settings during fork
export NO_PROXY="*"
export PYTHON_NO_USERSITE=1

# [KEY FIX 5] Enable better crash tracebacks
export PYTHONFAULTHANDLER=true
# ---------------------------------------------------------------------------

# 5. Start Airflow Standalone
echo "Starting Airflow 3 on port 8081 with Stability Fixes..."
airflow standalone
