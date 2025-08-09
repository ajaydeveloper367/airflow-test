#!/bin/bash

set -euo pipefail

AIRFLOW_VERSION=2.5.1
AIRFLOW_IMAGE="apache/airflow:$AIRFLOW_VERSION"
POSTGRES_CONTAINER_NAME="pg-airflow-$AIRFLOW_VERSION"
WEBSERVER_CONTAINER_NAME="airflow-webserver-$AIRFLOW_VERSION"
POSTGRES_PASSWORD="airflow"
AIRFLOW_HOME_DIR="$HOME/airflow_$AIRFLOW_VERSION"
POSTGRES_PORT=5433
NETWORK_NAME="airflow-net-$AIRFLOW_VERSION"

# Detect current host user/group to avoid permission issues with mounted volumes
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"

mkdir -p "$AIRFLOW_HOME_DIR"/{dags,logs,plugins}
# Ensure subdirs exist that Airflow may write into during init
mkdir -p "$AIRFLOW_HOME_DIR/logs/scheduler" "$AIRFLOW_HOME_DIR/logs/webserver"

# Make local Airflow dirs permissive so container user (UID 50000 or mapped UID) can write
chmod -R a+rwX "$AIRFLOW_HOME_DIR" 2>/dev/null || true

# Ensure a dedicated network exists so containers can resolve each other by name
if ! docker network inspect "$NETWORK_NAME" > /dev/null 2>&1; then
  docker network create "$NETWORK_NAME"
fi

echo "🐘 Starting PostgreSQL 12..."
# Recreate container if it already exists
docker rm -f "$POSTGRES_CONTAINER_NAME" > /dev/null 2>&1 || true
docker run -d \
  --name $POSTGRES_CONTAINER_NAME \
  --network $NETWORK_NAME \
  -e POSTGRES_USER=airflow \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e POSTGRES_DB=airflow \
  -p $POSTGRES_PORT:5432 \
  -v "$AIRFLOW_HOME_DIR/db:/var/lib/postgresql/data" \
  postgres:12

echo "⏳ Waiting for PostgreSQL to be ready..."
until docker exec $POSTGRES_CONTAINER_NAME pg_isready -U airflow > /dev/null 2>&1; do
  sleep 2
  echo "⏳ Waiting for DB..."
done
echo "✅ PostgreSQL is ready."

echo "🛠️  Running one-time Airflow DB init and creating admin user..."
# Use the user-defined network and correct connection section (database).
docker run --rm \
  --name airflow-init-$AIRFLOW_VERSION \
  --network $NETWORK_NAME \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW_UID="$CURRENT_UID" \
  -v "$AIRFLOW_HOME_DIR/dags:/opt/airflow/dags" \
  -v "$AIRFLOW_HOME_DIR/logs:/opt/airflow/logs" \
  -v "$AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins" \
  $AIRFLOW_IMAGE bash -c "airflow db init && airflow users create --username admin --password admin --firstname Admin --lastname User --role Admin --email admin@example.com || true"

echo "🌐 Starting Airflow webserver..."
# Recreate container if it already exists
docker rm -f "$WEBSERVER_CONTAINER_NAME" > /dev/null 2>&1 || true

docker run -d \
  --name $WEBSERVER_CONTAINER_NAME \
  --network $NETWORK_NAME \
  --shm-size=512m \
  -p 8080:8080 \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW_UID="$CURRENT_UID" \
  -e AIRFLOW__WEBSERVER__WORKERS=1 \
  -e AIRFLOW__WEBSERVER__WEB_SERVER_WORKER_TIMEOUT=120 \
  -e GUNICORN_CMD_ARGS="--workers 1 --timeout 120 --worker-class sync --worker-tmp-dir /dev/shm" \
  -v "$AIRFLOW_HOME_DIR/dags:/opt/airflow/dags" \
  -v "$AIRFLOW_HOME_DIR/logs:/opt/airflow/logs" \
  -v "$AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins" \
  $AIRFLOW_IMAGE webserver

echo "✅ Airflow $AIRFLOW_VERSION is running at http://localhost:8080"
