#!/bin/bash
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Initializing environment..."

# Validate required environment variables
required_vars=("NODE_ID" "WIREGUARD_PRIVATE_KEY" "CONTRACT_PRIVATE_KEY")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        log "ERROR: $var environment variable is required"
        exit 1
    fi
done

# Set default values
export NETWORK=${NETWORK:-base}
export SYNC_INTERVAL=${SYNC_INTERVAL:-30000}
export LOG_LEVEL=${LOG_LEVEL:-info}
export CONTRACT_ADDRESS=${CONTRACT_ADDRESS:-}
export RPC_URL=${RPC_URL:-}

# Create necessary directories
mkdir -p /etc/wireguard
mkdir -p /var/log/wireguard
mkdir -p /app/config

# Set proper permissions for WireGuard keys
if [ -f /etc/wireguard/private.key ]; then
    chmod 600 /etc/wireguard/private.key
fi
if [ -f /etc/wireguard/public.key ]; then
    chmod 644 /etc/wireguard/public.key
fi

# Generate WireGuard keys if not provided
if [ ! -f /etc/wireguard/private.key ]; then
    log "Generating WireGuard private key..."
    wg genkey > /etc/wireguard/private.key
    chmod 600 /etc/wireguard/private.key
fi

if [ ! -f /etc/wireguard/public.key ]; then
    log "Generating WireGuard public key..."
    wg pubkey < /etc/wireguard/private.key > /etc/wireguard/public.key
    chmod 644 /etc/wireguard/public.key
fi

# Create initial WireGuard configuration
if [ ! -f /etc/wireguard/wg0.conf ]; then
    log "Creating initial WireGuard configuration..."
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Peers will be added dynamically by the bridge
EOF
fi

# Create contract configuration
cat > /app/config/contract-config.json << EOF
{
  "network": "${NETWORK}",
  "contractAddress": "${CONTRACT_ADDRESS}",
  "rpcUrl": "${RPC_URL}",
  "nodeId": "${NODE_ID}",
  "syncInterval": ${SYNC_INTERVAL},
  "logLevel": "${LOG_LEVEL}"
}
EOF

log "Environment initialization complete"
log "Node ID: ${NODE_ID}"
log "Network: ${NETWORK}"
log "Sync Interval: ${SYNC_INTERVAL}ms"
log "Log Level: ${LOG_LEVEL}" 