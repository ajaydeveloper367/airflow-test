#!/bin/bash

set -euo pipefail

AIRFLOW_VERSION=2.5.1
AIRFLOW_IMAGE="apache/airflow:$AIRFLOW_VERSION"
POSTGRES_CONTAINER_NAME="pg-airflow-$AIRFLOW_VERSION"
WEBSERVER_CONTAINER_NAME="airflow-webserver-$AIRFLOW_VERSION"
SCHEDULER_CONTAINER_NAME="airflow-scheduler-$AIRFLOW_VERSION"
POSTGRES_PASSWORD="airflow"
AIRFLOW_HOME_DIR="$HOME/airflow_$AIRFLOW_VERSION"
POSTGRES_PORT=5433
NETWORK_NAME="airflow-net-$AIRFLOW_VERSION"

# Airflow runs as user airflow (uid=50000, gid=0) in the container
AIRFLOW_UID=50000
AIRFLOW_GID=0

echo "📁 Creating Airflow directories..."
mkdir -p $AIRFLOW_HOME_DIR/{dags,logs,plugins,config}

# Fix ownership and permissions for the directories
echo "🔧 Setting up proper permissions..."
sudo chown -R $AIRFLOW_UID:$AIRFLOW_GID $AIRFLOW_HOME_DIR
sudo chmod -R 755 $AIRFLOW_HOME_DIR

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
  -v $AIRFLOW_HOME_DIR/db:/var/lib/postgresql/data \
  postgres:12

echo "⏳ Waiting for PostgreSQL to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
until docker exec $POSTGRES_CONTAINER_NAME pg_isready -U airflow > /dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ ERROR: PostgreSQL failed to start after $MAX_RETRIES attempts"
    exit 1
  fi
  sleep 2
  echo "⏳ Waiting for DB... (attempt $RETRY_COUNT/$MAX_RETRIES)"
done
echo "✅ PostgreSQL is ready."

echo "🛠️  Running one-time Airflow DB init and creating admin user..."
# Use the user-defined network and correct connection section (database).
# Run with proper user and additional environment variables for permissions
docker run --rm \
  --name airflow-init-$AIRFLOW_VERSION \
  --network $NETWORK_NAME \
  --user "$AIRFLOW_UID:$AIRFLOW_GID" \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags \
  -e AIRFLOW__LOGGING__BASE_LOG_FOLDER=/opt/airflow/logs \
  -e AIRFLOW__CORE__EXECUTOR=LocalExecutor \
  -e AIRFLOW__WEBSERVER__EXPOSE_CONFIG=True \
  -e _AIRFLOW_DB_UPGRADE=True \
  -e _AIRFLOW_WWW_USER_CREATE=True \
  -e _AIRFLOW_WWW_USER_USERNAME=admin \
  -e _AIRFLOW_WWW_USER_PASSWORD=admin \
  -e _AIRFLOW_WWW_USER_EMAIL=admin@example.com \
  -e _AIRFLOW_WWW_USER_FIRSTNAME=Admin \
  -e _AIRFLOW_WWW_USER_LASTNAME=User \
  -e _AIRFLOW_WWW_USER_ROLE=Admin \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  $AIRFLOW_IMAGE bash -c "
    # Ensure log directories exist with proper permissions
    mkdir -p /opt/airflow/logs/scheduler /opt/airflow/logs/dag_processor_manager
    chmod -R 755 /opt/airflow/logs
    
    # Initialize database and create user
    airflow db init
    if ! airflow users list | grep -q 'admin'; then
      airflow users create \
        --username admin \
        --password admin \
        --firstname Admin \
        --lastname User \
        --role Admin \
        --email admin@example.com
    fi
  "

# Verify the initialization was successful
echo "🔍 Verifying Airflow initialization..."
docker run --rm \
  --network $NETWORK_NAME \
  --user "$AIRFLOW_UID:$AIRFLOW_GID" \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  $AIRFLOW_IMAGE airflow db check

echo "📅 Starting Airflow scheduler..."
# Recreate container if it already exists
docker rm -f "$SCHEDULER_CONTAINER_NAME" > /dev/null 2>&1 || true

docker run -d \
  --name $SCHEDULER_CONTAINER_NAME \
  --network $NETWORK_NAME \
  --user "$AIRFLOW_UID:$AIRFLOW_GID" \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags \
  -e AIRFLOW__LOGGING__BASE_LOG_FOLDER=/opt/airflow/logs \
  -e AIRFLOW__CORE__EXECUTOR=LocalExecutor \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  $AIRFLOW_IMAGE scheduler

echo "🌐 Starting Airflow webserver..."
# Recreate container if it already exists
docker rm -f "$WEBSERVER_CONTAINER_NAME" > /dev/null 2>&1 || true

docker run -d \
  --name $WEBSERVER_CONTAINER_NAME \
  --network $NETWORK_NAME \
  --user "$AIRFLOW_UID:$AIRFLOW_GID" \
  -p 8080:8080 \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags \
  -e AIRFLOW__LOGGING__BASE_LOG_FOLDER=/opt/airflow/logs \
  -e AIRFLOW__CORE__EXECUTOR=LocalExecutor \
  -e AIRFLOW__WEBSERVER__EXPOSE_CONFIG=True \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  $AIRFLOW_IMAGE webserver

echo "✅ Airflow $AIRFLOW_VERSION is running at http://localhost:8080"
echo "🔑 Login with username: admin, password: admin"
echo "📊 Containers running:"
echo "  - PostgreSQL: $POSTGRES_CONTAINER_NAME"
echo "  - Scheduler: $SCHEDULER_CONTAINER_NAME" 
echo "  - Webserver: $WEBSERVER_CONTAINER_NAME"
