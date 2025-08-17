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

# Validate required environment variables
log "Validating environment variables..."

if [ -z "$NODE_ID" ]; then
    handle_error "NODE_ID is required"
fi

if [ -z "$NODE_IP" ]; then
    handle_error "NODE_IP is required"
fi

if [ -z "$HUB_PUBLIC_IP" ]; then
    handle_error "HUB_PUBLIC_IP is required"
fi

if [ -z "$HUB_PUBLIC_KEY" ]; then
    handle_error "HUB_PUBLIC_KEY is required"
fi

if [ -z "$WIREGUARD_PRIVATE_KEY" ]; then
    handle_error "WIREGUARD_PRIVATE_KEY is required"
fi

log "Environment variables validated successfully"

# Create WireGuard configuration directory
mkdir -p /etc/wireguard

# Generate WireGuard private key if not provided
if [ "$WIREGUARD_PRIVATE_KEY" = "generate" ]; then
    log "Generating new WireGuard private key..."
    WIREGUARD_PRIVATE_KEY=$(wg genkey)
fi

# Create WireGuard configuration file
log "Creating WireGuard configuration..."
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${NODE_IP}/32
PrivateKey = ${WIREGUARD_PRIVATE_KEY}
ListenPort = 51820

[Peer]
# Hub (DigitalOcean NYC)
PublicKey = ${HUB_PUBLIC_KEY}
Endpoint = ${HUB_PUBLIC_IP}:51820
AllowedIPs = 10.88.0.0/24
PersistentKeepalive = 25
EOF

# Set proper permissions
chmod 600 /etc/wireguard/wg0.conf

log "WireGuard configuration created successfully"

# Load WireGuard kernel module if not already loaded
if ! lsmod | grep -q wireguard; then
    log "Loading WireGuard kernel module..."
    modprobe wireguard || log "Warning: Could not load WireGuard kernel module"
fi

log "WireGuard environment initialization completed" 