"""
=============================================================================
Airflow DAG: elt_pipeline_dag.py
Purpose:  Orchestrate the full ELT pipeline:
          1. Trigger Snowflake schema inference + ingestion tasks
          2. Run dbt snapshots (SCD Type 2)
          3. Run dbt staging models
          4. Run dbt intermediate models
          5. Run dbt marts models
          6. Run dbt tests (staging → marts)
          7. Notify on failure (Slack / PagerDuty)

Schedule: Every 15 minutes (matches Snowflake Task interval)
SLAs:     Raw → Staging < 30 min | Raw → Marts < 90 min

Design decisions:
  - dag_id uses dated suffix for easy backfill identification
  - Each dbt layer is a separate task group for clear observability
  - SnowflakeOperator used for Task resume/execution trigger
  - KubernetesPodOperator / BashOperator for dbt (choose based on infra)
  - On-failure callback sends alert to Slack
=============================================================================
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
from airflow.utils.task_group import TaskGroup
from airflow.utils.trigger_rule import TriggerRule

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DBT_PROJECT_DIR = Variable.get("DBT_PROJECT_DIR", "/opt/airflow/dbt/aws_dbt_snowflake_project")
DBT_PROFILES_DIR = Variable.get("DBT_PROFILES_DIR", "/opt/airflow/dbt")
DBT_TARGET = Variable.get("DBT_TARGET", "prod")
DBT_THREADS = Variable.get("DBT_THREADS", "8")
SNOWFLAKE_CONN_ID = "snowflake_default"

# Common dbt command prefix
DBT = (
    f"cd {DBT_PROJECT_DIR} && "
    f"dbt --no-use-colors "
    f"--profiles-dir {DBT_PROFILES_DIR} "
    f"--target {DBT_TARGET} "
)

# Failure callback: send Slack alert (configure SlackWebhookOperator or use callbacks)
def on_failure_callback(context):
    """Send alert on task failure. Extend with Slack/PagerDuty as needed."""
    dag_id  = context["dag"].dag_id
    task_id = context["task_instance"].task_id
    exec_dt = context["execution_date"]
    log_url = context["task_instance"].log_url
    print(f"ALERT: {dag_id}.{task_id} failed at {exec_dt}. Log: {log_url}")
    # Example Slack notification (requires airflow-slack provider):
    # SlackWebhookHook(http_conn_id='slack_alerts').send(
    #     text=f":red_circle: *{dag_id}.{task_id}* failed.\nLog: {log_url}"
    # )


# ---------------------------------------------------------------------------
# Default args (applied to all tasks)
# ---------------------------------------------------------------------------
DEFAULT_ARGS = {
    "owner":            "data-engineering",
    "depends_on_past":  False,
    "start_date":       datetime(2024, 1, 1),
    "email_on_failure": False,
    "email_on_retry":   False,
    "retries":          2,
    "retry_delay":      timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "on_failure_callback": on_failure_callback,
    "execution_timeout": timedelta(hours=2),  # never let a task hang indefinitely
}

# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
with DAG(
    dag_id="elt_pipeline",
    description="E-commerce ELT: S3 → Snowflake Raw → DBT Staging → Marts",
    default_args=DEFAULT_ARGS,
    schedule_interval="*/15 * * * *",   # every 15 minutes
    catchup=False,                       # don't backfill historical runs
    max_active_runs=1,                   # prevent concurrent pipeline runs
    tags=["elt", "snowflake", "dbt", "ecommerce"],
    doc_md=__doc__,
) as dag:

    # -----------------------------------------------------------------------
    # Start sentinel
    # -----------------------------------------------------------------------
    start = EmptyOperator(task_id="start")

    # -----------------------------------------------------------------------
    # 1. Snowflake: trigger schema inference and ingestion tasks
    # -----------------------------------------------------------------------
    with TaskGroup("snowflake_ingestion", tooltip="Trigger Snowflake ingestion tasks") as sf_group:

        # Execute the root Snowflake task tree (which calls child tasks for each entity)
        # Using EXECUTE TASK instead of RESUME to trigger a single run
        trigger_infer_schema = SnowflakeOperator(
            task_id="trigger_infer_schema",
            snowflake_conn_id=SNOWFLAKE_CONN_ID,
            sql="""
                EXECUTE TASK RAW.ECOMMERCE.TASK_INFER_SCHEMA;
                -- Wait briefly before checking status
                CALL SYSTEM$WAIT(30);
            """,
            warehouse="LOADER_WH",
            database="RAW",
            schema="ECOMMERCE",
        )

        # Poll until ingestion tasks complete (simple approach: wait 2 minutes)
        # Production: replace with sensor polling TASK_HISTORY view
        wait_for_ingestion = BashOperator(
            task_id="wait_for_ingestion_tasks",
            bash_command=(
                "sleep 120 && echo 'Snowflake ingestion tasks assumed complete'"
            ),
        )

        trigger_infer_schema >> wait_for_ingestion

    # -----------------------------------------------------------------------
    # 2. dbt: install dependencies (run once per deployment, not per schedule)
    #    In production this is baked into the Docker image — not run in the DAG.
    #    Included here for completeness.
    # -----------------------------------------------------------------------
    # dbt_deps = BashOperator(
    #     task_id="dbt_deps",
    #     bash_command=f"{DBT} deps",
    # )

    # -----------------------------------------------------------------------
    # 3. dbt: snapshots (SCD Type 2 — must run before staging reads the snap)
    # -----------------------------------------------------------------------
    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=f"{DBT} snapshot",
        pool="dbt_pool",                 # throttle parallel dbt runs
    )

    # -----------------------------------------------------------------------
    # 4. dbt: staging layer
    # -----------------------------------------------------------------------
    with TaskGroup("dbt_staging", tooltip="dbt staging layer models") as staging_group:

        run_staging = BashOperator(
            task_id="dbt_run_staging",
            bash_command=(
                f"{DBT} run "
                f"--select tag:staging "
                f"--threads {DBT_THREADS} "
                f"--fail-fast"
            ),
            pool="dbt_pool",
        )

        test_staging = BashOperator(
            task_id="dbt_test_staging",
            bash_command=(
                f"{DBT} test "
                f"--select tag:staging "
                f"--store-failures "
                f"--threads {DBT_THREADS}"
            ),
            pool="dbt_pool",
        )

        run_staging >> test_staging

    # -----------------------------------------------------------------------
    # 5. dbt: intermediate layer
    # -----------------------------------------------------------------------
    with TaskGroup("dbt_intermediate", tooltip="dbt intermediate layer") as int_group:

        run_intermediate = BashOperator(
            task_id="dbt_run_intermediate",
            bash_command=(
                f"{DBT} run "
                f"--select tag:intermediate "
                f"--threads {DBT_THREADS}"
            ),
            pool="dbt_pool",
        )

    # -----------------------------------------------------------------------
    # 6. dbt: marts layer
    # -----------------------------------------------------------------------
    with TaskGroup("dbt_marts", tooltip="dbt marts layer") as marts_group:

        run_marts = BashOperator(
            task_id="dbt_run_marts",
            bash_command=(
                f"{DBT} run "
                f"--select tag:marts "
                f"--threads {DBT_THREADS} "
                f"--fail-fast"
            ),
            pool="dbt_pool",
        )

        test_marts = BashOperator(
            task_id="dbt_test_marts",
            bash_command=(
                f"{DBT} test "
                f"--select tag:marts "
                f"--store-failures "
                f"--threads {DBT_THREADS}"
            ),
            pool="dbt_pool",
        )

        run_marts >> test_marts

    # -----------------------------------------------------------------------
    # 7. dbt: source freshness check (runs independently — informational)
    # -----------------------------------------------------------------------
    source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=f"{DBT} source freshness",
        trigger_rule=TriggerRule.ALL_DONE,  # run even if models fail
    )

    # -----------------------------------------------------------------------
    # 8. End sentinel
    # -----------------------------------------------------------------------
    end = EmptyOperator(
        task_id="end",
        trigger_rule=TriggerRule.ALL_DONE,
    )

    # -----------------------------------------------------------------------
    # Task dependencies (DAG topology)
    # -----------------------------------------------------------------------
    #
    #  start
    #    └─ sf_group (infer schema + ingest)
    #         └─ dbt_snapshot
    #              └─ staging_group (run → test)
    #                   └─ int_group (run)
    #                        └─ marts_group (run → test)
    #                             └─ source_freshness
    #                                  └─ end
    #
    (
        start
        >> sf_group
        >> dbt_snapshot
        >> staging_group
        >> int_group
        >> marts_group
        >> source_freshness
        >> end
    )
