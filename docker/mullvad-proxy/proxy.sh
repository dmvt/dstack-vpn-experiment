#!/bin/bash
set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Default configuration
UDP_PORT=${UDP_PORT:-51820}
TCP_PORT=${TCP_PORT:-51820}
REMOTE_HOST=${REMOTE_HOST:-localhost}

log "Starting UDP-to-TCP proxy..."
log "UDP Port: $UDP_PORT"
log "TCP Port: $TCP_PORT"
log "Remote Host: $REMOTE_HOST"

# Start socat proxy for UDP to TCP
log "Starting UDP to TCP proxy..."
socat UDP-LISTEN:$UDP_PORT,fork TCP:$REMOTE_HOST:$TCP_PORT &

# Start socat proxy for TCP to UDP
log "Starting TCP to UDP proxy..."
socat TCP-LISTEN:$TCP_PORT,fork UDP:$REMOTE_HOST:$UDP_PORT &

# Wait for background processes
wait 