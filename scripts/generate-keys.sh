#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if wireguard-tools is installed
if ! command -v wg &> /dev/null; then
    error "WireGuard tools not found. Please install wireguard-tools first."
    exit 1
fi

# Create config directories if they don't exist
mkdir -p config/node-a config/node-b

log "Generating WireGuard key pairs for Node A and Node B..."

# Generate keys for Node A
log "Generating keys for Node A..."
wg genkey | tee config/node-a/private.key | wg pubkey > config/node-a/public.key
NODE_A_PRIVATE=$(cat config/node-a/private.key)
NODE_A_PUBLIC=$(cat config/node-a/public.key)

# Generate keys for Node B
log "Generating keys for Node B..."
wg genkey | tee config/node-b/private.key | wg pubkey > config/node-b/public.key
NODE_B_PRIVATE=$(cat config/node-b/private.key)
NODE_B_PUBLIC=$(cat config/node-b/public.key)

log "Keys generated successfully!"

# Create WireGuard configuration for Node A
log "Creating WireGuard configuration for Node A..."
cat > config/node-a/wg0.conf << EOF
[Interface]
PrivateKey = ${NODE_A_PRIVATE}
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = ${NODE_B_PUBLIC}
AllowedIPs = 10.0.0.2/32
Endpoint = node-b:51820
PersistentKeepalive = 25
EOF

# Create WireGuard configuration for Node B
log "Creating WireGuard configuration for Node B..."
cat > config/node-b/wg0.conf << EOF
[Interface]
PrivateKey = ${NODE_B_PRIVATE}
Address = 10.0.0.2/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = ${NODE_A_PUBLIC}
AllowedIPs = 10.0.0.1/32
Endpoint = node-a:51820
PersistentKeepalive = 25
EOF

log "WireGuard configurations created:"
log "  - Node A: config/node-a/wg0.conf"
log "  - Node B: config/node-b/wg0.conf"

# Set proper permissions
chmod 600 config/node-a/private.key config/node-b/private.key
chmod 644 config/node-a/public.key config/node-b/public.key
chmod 600 config/node-a/wg0.conf config/node-b/wg0.conf

log "Key generation complete!"
log "You can now start the WireGuard containers using docker-compose up" 