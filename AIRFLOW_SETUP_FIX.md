# Airflow Setup Fix

## Problem
The original Airflow setup script was failing with permission errors when trying to create log directories:
```
PermissionError: [Errno 13] Permission denied: '/opt/airflow/logs/scheduler'
```

## Root Cause
The Airflow container runs as a non-root user (airflow user with UID 50000), but the mounted volumes from the host system have different ownership, causing permission conflicts.

## Solutions

### Solution 1: Updated Original Script (airflow251Setup.sh)
The original script has been updated with the following fixes:
1. Added `chmod -R 777` for the logs directory to make it writable
2. Added LocalExecutor configuration to ensure proper database connections
3. Added a scheduler container for running DAGs
4. Removed user specifications that were causing conflicts

### Solution 2: Alternative Script (airflow251Setup_fixed.sh)
A more robust alternative script that:
1. Uses current user's UID/GID for better permission handling
2. Creates a custom entrypoint script to fix permissions dynamically
3. Includes a pre-configured airflow.cfg file
4. Provides better error handling and user feedback

## Usage

### Using the Updated Original Script:
```bash
./airflow251Setup.sh
```

### Using the Alternative Script:
```bash
./airflow251Setup_fixed.sh
```

## What Gets Created
- PostgreSQL database container on port 5433
- Airflow webserver on port 8080
- Airflow scheduler for DAG execution
- Directory structure: `~/airflow_2.5.1/{dags,logs,plugins,db}`

## Access Airflow
- URL: http://localhost:8080
- Username: admin
- Password: admin

## Managing Containers

### Stop Airflow:
```bash
docker stop airflow-webserver-2.5.1 airflow-scheduler-2.5.1 pg-airflow-2.5.1
```

### Remove Containers:
```bash
docker rm -f airflow-webserver-2.5.1 airflow-scheduler-2.5.1 pg-airflow-2.5.1
```

### Check Container Logs:
```bash
docker logs airflow-webserver-2.5.1
docker logs airflow-scheduler-2.5.1
```

## Troubleshooting

If you still encounter permission issues:
1. Make sure Docker is running
2. Clear old volumes: `rm -rf ~/airflow_2.5.1`
3. Use the alternative script which handles permissions more robustly
4. Check Docker logs for specific error messages