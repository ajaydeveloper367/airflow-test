#!/bin/bash

set -euo pipefail

AIRFLOW_VERSION=2.5.1
POSTGRES_CONTAINER_NAME="pg-airflow-$AIRFLOW_VERSION"
WEBSERVER_CONTAINER_NAME="airflow-webserver-$AIRFLOW_VERSION"
SCHEDULER_CONTAINER_NAME="airflow-scheduler-$AIRFLOW_VERSION"
NETWORK_NAME="airflow-net-$AIRFLOW_VERSION"
AIRFLOW_HOME_DIR="$HOME/airflow_$AIRFLOW_VERSION"

echo "🧹 Stopping and removing Airflow containers..."

# Stop and remove containers
docker rm -f "$WEBSERVER_CONTAINER_NAME" > /dev/null 2>&1 || true
docker rm -f "$SCHEDULER_CONTAINER_NAME" > /dev/null 2>&1 || true
docker rm -f "$POSTGRES_CONTAINER_NAME" > /dev/null 2>&1 || true

echo "🗑️  Removing Docker network..."
docker network rm "$NETWORK_NAME" > /dev/null 2>&1 || true

echo "📁 Airflow data directory preserved at: $AIRFLOW_HOME_DIR"
echo "   To completely remove data, run: rm -rf $AIRFLOW_HOME_DIR"

echo "✅ Cleanup completed!"