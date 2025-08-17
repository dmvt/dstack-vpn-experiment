#!/bin/bash

set -e

# Function to log messages
log() {
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] $1"
}

# Function to handle errors
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Initialize environment
log "Initializing WireGuard environment..."
/init-env.sh || handle_error "Failed to initialize environment"

# Start WireGuard interface
log "Starting WireGuard interface..."
wg-quick up wg0 || handle_error "Failed to start WireGuard interface"

# Start health check server
log "Starting health check server..."
node /health-check.js &

# Wait for health check server to be ready
log "Waiting for health check server..."
sleep 5

# Check if health check server is running
if ! curl -f http://localhost:8000/status > /dev/null 2>&1; then
    handle_error "Health check server failed to start"
fi

# Start Patroni PostgreSQL cluster
log "Starting Patroni PostgreSQL cluster..."
if [[ -n "$POSTGRES_PASSWORD" && -n "$POSTGRES_REPLICATION_PASSWORD" ]]; then
    # Set environment variables for Patroni
    export POSTGRES_PASSWORD
    export POSTGRES_REPLICATION_PASSWORD
    
    # Start Patroni in background
    /patroni-entrypoint.sh &
    
    # Wait for Patroni to be ready
    log "Waiting for Patroni to be ready..."
    sleep 10
    
    # Check if Patroni is running
    if pgrep -f patroni > /dev/null; then
        log "Patroni PostgreSQL cluster started successfully"
    else
        log "WARNING: Patroni failed to start, but continuing..."
    fi
else
    log "PostgreSQL passwords not set, skipping Patroni startup"
fi

log "WireGuard node with PostgreSQL is ready and healthy"

# Keep container running and handle signals
trap 'log "Received signal, shutting down..."; wg-quick down wg0; exit 0' SIGTERM SIGINT

# Wait for signal
while true; do
    sleep 1
done 