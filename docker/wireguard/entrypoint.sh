#!/bin/bash
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to wait for bridge to be ready
wait_for_bridge_ready() {
    local max_attempts=30
    local attempt=0
    
    log "Waiting for bridge to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:8080/ready > /dev/null 2>&1; then
            log "Bridge is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log "Bridge not ready yet, attempt $attempt/$max_attempts"
        sleep 2
    done
    
    log "ERROR: Bridge failed to become ready within timeout"
    return 1
}

# Function to check WireGuard interface health
check_wireguard_health() {
    if ! wg show wg0 >/dev/null 2>&1; then
        log "WireGuard interface down, restarting..."
        wg-quick down wg0 2>/dev/null || true
        wg-quick up wg0
        log "WireGuard interface restarted"
    fi
}

# Initialize environment
log "Initializing environment..."
source /app/init-env.sh

# Start health check server in background
log "Starting health check server..."
node /app/health-check.js &
HEALTH_CHECK_PID=$!

# Wait for health check server to start
sleep 3

# Start WireGuard Contract Bridge in background
log "Starting WireGuard Contract Bridge..."
node /app/start-bridge.js &
BRIDGE_PID=$!

# Wait for bridge to be ready
if ! wait_for_bridge_ready; then
    log "ERROR: Failed to start bridge"
    exit 1
fi

# Load WireGuard module if not already loaded
if ! lsmod | grep -q wireguard; then
    log "Loading WireGuard kernel module..."
    modprobe wireguard || log "Warning: Could not load WireGuard kernel module"
fi

# Start WireGuard interface
log "Starting WireGuard interface..."
wg-quick up wg0

# Show initial status
log "WireGuard interface status:"
wg show

log "Network interfaces:"
ip addr show

# Monitor health and restart if needed
log "Starting health monitoring..."
trap 'log "Shutting down..."; wg-quick down wg0; kill $BRIDGE_PID $HEALTH_CHECK_PID 2>/dev/null; exit 0' SIGTERM SIGINT

while true; do
    # Check if bridge process is still running
    if ! kill -0 $BRIDGE_PID 2>/dev/null; then
        log "Bridge process died, restarting..."
        node /app/start-bridge.js &
        BRIDGE_PID=$!
        
        # Wait for bridge to be ready again
        if ! wait_for_bridge_ready; then
            log "ERROR: Failed to restart bridge"
            exit 1
        fi
    fi
    
    # Check if health check server is still running
    if ! kill -0 $HEALTH_CHECK_PID 2>/dev/null; then
        log "Health check server died, restarting..."
        node /app/health-check.js &
        HEALTH_CHECK_PID=$!
    fi
    
    # Check WireGuard interface health
    check_wireguard_health
    
    # Log status every 5 minutes
    if [ $((SECONDS % 300)) -eq 0 ]; then
        log "Health check - Bridge PID: $BRIDGE_PID, Health Check PID: $HEALTH_CHECK_PID"
        
        # Get bridge health status
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            log "Bridge health check passed"
        else
            log "Warning: Bridge health check failed"
        fi
    fi
    
    sleep 30
done 