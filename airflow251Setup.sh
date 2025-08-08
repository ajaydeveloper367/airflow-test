#!/bin/bash

set -e

AIRFLOW_VERSION=2.5.1
AIRFLOW_IMAGE="apache/airflow:$AIRFLOW_VERSION"
POSTGRES_CONTAINER_NAME="pg-airflow-$AIRFLOW_VERSION"
WEBSERVER_CONTAINER_NAME="airflow-webserver-$AIRFLOW_VERSION"
POSTGRES_PASSWORD="airflow"
AIRFLOW_HOME_DIR="$HOME/airflow_$AIRFLOW_VERSION"
POSTGRES_PORT=5433

mkdir -p $AIRFLOW_HOME_DIR/{dags,logs,plugins}

echo "🐘 Starting PostgreSQL 12..."
docker run -d \
  --name $POSTGRES_CONTAINER_NAME \
  -e POSTGRES_USER=airflow \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e POSTGRES_DB=airflow \
  -p $POSTGRES_PORT:5432 \
  -v $AIRFLOW_HOME_DIR/db:/var/lib/postgresql/data \
  postgres:12

echo "⏳ Waiting for PostgreSQL to be ready..."
until docker exec $POSTGRES_CONTAINER_NAME pg_isready -U airflow > /dev/null 2>&1; do
  sleep 2
  echo "⏳ Waiting for DB..."
done
echo "✅ PostgreSQL is ready."

echo "🛠️  Running one-time Airflow DB init..."
docker run --rm \
  --name airflow-init-$AIRFLOW_VERSION \
  -e AIRFLOW__CORE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  --network container:$POSTGRES_CONTAINER_NAME \
  $AIRFLOW_IMAGE db init

echo "🌐 Starting Airflow webserver..."
docker run -d \
  --name $WEBSERVER_CONTAINER_NAME \
  -p 8080:8080 \
  -e AIRFLOW__CORE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  --network container:$POSTGRES_CONTAINER_NAME \
  $AIRFLOW_IMAGE webserver

echo "✅ Airflow $AIRFLOW_VERSION is running at http://localhost:8080"
