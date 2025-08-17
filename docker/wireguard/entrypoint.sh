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

log "WireGuard node is ready and healthy"

# Keep container running and handle signals
trap 'log "Received signal, shutting down..."; wg-quick down wg0; exit 0' SIGTERM SIGINT

# Wait for signal
while true; do
    sleep 1
done 