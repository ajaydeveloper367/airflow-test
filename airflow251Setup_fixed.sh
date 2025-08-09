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

# Get current user ID for volume mapping
AIRFLOW_UID=$(id -u)
AIRFLOW_GID=$(id -g)

echo "📁 Setting up Airflow directories..."
# Create directories with proper permissions
mkdir -p $AIRFLOW_HOME_DIR/{dags,logs,plugins,config}

# Create airflow.cfg to avoid permission issues
cat > $AIRFLOW_HOME_DIR/airflow.cfg << EOF
[core]
dags_folder = /opt/airflow/dags
load_examples = False
executor = LocalExecutor

[database]
sql_alchemy_conn = postgresql+psycopg2://airflow:airflow@${POSTGRES_CONTAINER_NAME}:5432/airflow

[logging]
base_log_folder = /opt/airflow/logs
logging_level = INFO

[webserver]
base_url = http://localhost:8080
web_server_host = 0.0.0.0
web_server_port = 8080
EOF

# Ensure a dedicated network exists so containers can resolve each other by name
if ! docker network inspect "$NETWORK_NAME" > /dev/null 2>&1; then
  echo "🔗 Creating Docker network..."
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
until docker exec $POSTGRES_CONTAINER_NAME pg_isready -U airflow > /dev/null 2>&1; do
  sleep 2
  echo "⏳ Waiting for DB..."
done
echo "✅ PostgreSQL is ready."

# Create a custom entrypoint script to fix permissions
cat > $AIRFLOW_HOME_DIR/entrypoint.sh << 'EOF'
#!/bin/bash
# Fix permissions for log directories
if [ ! -w /opt/airflow/logs ]; then
    echo "Fixing log directory permissions..."
    mkdir -p /opt/airflow/logs/scheduler
    chmod -R 777 /opt/airflow/logs
fi
exec "$@"
EOF
chmod +x $AIRFLOW_HOME_DIR/entrypoint.sh

echo "🛠️  Running one-time Airflow DB init and creating admin user..."
# Initialize database with proper environment
docker run --rm \
  --name airflow-init-$AIRFLOW_VERSION \
  --network $NETWORK_NAME \
  -e AIRFLOW_UID=$AIRFLOW_UID \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW__CORE__EXECUTOR=LocalExecutor \
  -e _AIRFLOW_DB_UPGRADE=true \
  -e _AIRFLOW_WWW_USER_CREATE=true \
  -e _AIRFLOW_WWW_USER_USERNAME=admin \
  -e _AIRFLOW_WWW_USER_PASSWORD=admin \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  -v $AIRFLOW_HOME_DIR/airflow.cfg:/opt/airflow/airflow.cfg \
  -v $AIRFLOW_HOME_DIR/entrypoint.sh:/entrypoint.sh \
  --entrypoint /entrypoint.sh \
  $AIRFLOW_IMAGE bash -c "
    airflow db init && \
    airflow users create \
      --username admin \
      --password admin \
      --firstname Admin \
      --lastname User \
      --role Admin \
      --email admin@example.com || true
  "

echo "🚀 Starting Airflow scheduler..."
# Recreate container if it already exists
docker rm -f "$SCHEDULER_CONTAINER_NAME" > /dev/null 2>&1 || true

docker run -d \
  --name $SCHEDULER_CONTAINER_NAME \
  --network $NETWORK_NAME \
  -e AIRFLOW_UID=$AIRFLOW_UID \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW__CORE__EXECUTOR=LocalExecutor \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  -v $AIRFLOW_HOME_DIR/airflow.cfg:/opt/airflow/airflow.cfg \
  -v $AIRFLOW_HOME_DIR/entrypoint.sh:/entrypoint.sh \
  --entrypoint /entrypoint.sh \
  $AIRFLOW_IMAGE scheduler

echo "🌐 Starting Airflow webserver..."
# Recreate container if it already exists
docker rm -f "$WEBSERVER_CONTAINER_NAME" > /dev/null 2>&1 || true

docker run -d \
  --name $WEBSERVER_CONTAINER_NAME \
  --network $NETWORK_NAME \
  -p 8080:8080 \
  -e AIRFLOW_UID=$AIRFLOW_UID \
  -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:airflow@$POSTGRES_CONTAINER_NAME:5432/airflow" \
  -e AIRFLOW__CORE__LOAD_EXAMPLES=False \
  -e AIRFLOW__CORE__EXECUTOR=LocalExecutor \
  -v $AIRFLOW_HOME_DIR/dags:/opt/airflow/dags \
  -v $AIRFLOW_HOME_DIR/logs:/opt/airflow/logs \
  -v $AIRFLOW_HOME_DIR/plugins:/opt/airflow/plugins \
  -v $AIRFLOW_HOME_DIR/airflow.cfg:/opt/airflow/airflow.cfg \
  -v $AIRFLOW_HOME_DIR/entrypoint.sh:/entrypoint.sh \
  --entrypoint /entrypoint.sh \
  $AIRFLOW_IMAGE webserver

echo ""
echo "✅ Airflow $AIRFLOW_VERSION is running!"
echo "🌐 Web UI: http://localhost:8080"
echo "👤 Username: admin"
echo "🔑 Password: admin"
echo ""
echo "📁 DAGs directory: $AIRFLOW_HOME_DIR/dags"
echo "📊 Logs directory: $AIRFLOW_HOME_DIR/logs"
echo ""
echo "🛑 To stop Airflow, run:"
echo "   docker stop $WEBSERVER_CONTAINER_NAME $SCHEDULER_CONTAINER_NAME $POSTGRES_CONTAINER_NAME"
echo ""
echo "🗑️  To remove containers, run:"
echo "   docker rm -f $WEBSERVER_CONTAINER_NAME $SCHEDULER_CONTAINER_NAME $POSTGRES_CONTAINER_NAME"