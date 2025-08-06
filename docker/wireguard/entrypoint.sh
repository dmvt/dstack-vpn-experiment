#!/bin/bash
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check if WireGuard config exists
if [ ! -f /etc/wireguard/wg0.conf ]; then
    log "ERROR: WireGuard configuration not found at /etc/wireguard/wg0.conf"
    exit 1
fi

log "Starting WireGuard VPN..."

# Load WireGuard module if not already loaded
if ! lsmod | grep -q wireguard; then
    log "Loading WireGuard kernel module..."
    modprobe wireguard || log "Warning: Could not load WireGuard kernel module"
fi

# Start WireGuard interface
log "Starting WireGuard interface..."
wg-quick up wg0

# Show interface status
log "WireGuard interface status:"
wg show

# Show network interfaces
log "Network interfaces:"
ip addr show

# Keep container running
log "WireGuard is running. Press Ctrl+C to stop."
trap 'log "Shutting down WireGuard..."; wg-quick down wg0; exit 0' SIGTERM SIGINT

# Wait for signals
while true; do
    sleep 1
done 