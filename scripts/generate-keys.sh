#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if wireguard-tools is installed
if ! command -v wg &> /dev/null; then
    error "WireGuard tools not found. Please install wireguard-tools first."
    exit 1
fi

# Create config directories if they don't exist
mkdir -p config/hub config/node-a config/node-b config/node-c

log "Generating WireGuard key pairs for hub and three DStack nodes..."

# Generate keys for Hub
log "Generating keys for Hub..."
wg genkey | tee config/hub/server.key | wg pubkey > config/hub/server.pub
HUB_PRIVATE=$(cat config/hub/server.key)
HUB_PUBLIC=$(cat config/hub/server.pub)

log "Generating keys for three DStack nodes..."

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

# Generate keys for Node C
log "Generating keys for Node C..."
wg genkey | tee config/node-c/private.key | wg pubkey > config/node-c/public.key
NODE_C_PRIVATE=$(cat config/node-c/private.key)
NODE_C_PUBLIC=$(cat config/node-c/public.key)

log "Keys generated successfully!"

# Display public keys for configuration
echo ""
info "=== PUBLIC KEYS ==="
info "Hub Public Key: ${HUB_PUBLIC}"
info "Node A Public Key: ${NODE_A_PUBLIC}"
info "Node B Public Key: ${NODE_B_PUBLIC}"
info "Node C Public Key: ${NODE_C_PUBLIC}"
echo ""

# Create WireGuard configuration for Node A
log "Creating WireGuard configuration for Node A..."
cat > config/node-a/wg0.conf << EOF
[Interface]
Address = 10.88.0.11/32
PrivateKey = ${NODE_A_PRIVATE}
ListenPort = 51820

[Peer]
# Hub (DigitalOcean NYC)
PublicKey = ${HUB_PUBLIC}
Endpoint = <HUB_PUBLIC_IP>:51820
AllowedIPs = 10.88.0.0/24
PersistentKeepalive = 25
EOF

# Create WireGuard configuration for Node B
log "Creating WireGuard configuration for Node B..."
cat > config/node-b/wg0.conf << EOF
[Interface]
Address = 10.88.0.12/32
PrivateKey = ${NODE_B_PRIVATE}
ListenPort = 51820

[Peer]
# Hub (DigitalOcean NYC)
PublicKey = ${HUB_PUBLIC}
Endpoint = <HUB_PUBLIC_IP>:51820
AllowedIPs = 10.88.0.0/24
PersistentKeepalive = 25
EOF

# Create WireGuard configuration for Node C
log "Creating WireGuard configuration for Node C..."
cat > config/node-c/wg0.conf << EOF
[Interface]
Address = 10.88.0.13/32
PrivateKey = ${NODE_C_PRIVATE}
ListenPort = 51820

[Peer]
# Hub (DigitalOcean NYC)
PublicKey = ${HUB_PUBLIC}
Endpoint = <HUB_PUBLIC_IP>:51820
AllowedIPs = 10.88.0/24
PersistentKeepalive = 25
EOF

# Create WireGuard configuration for Hub
log "Creating WireGuard configuration for Hub..."
cat > config/hub/wg0.conf << EOF
[Interface]
Address = 10.88.0.1/24
ListenPort = 51820
PrivateKey = ${HUB_PRIVATE}
# Enable L3 forwarding between spokes (no NAT)
PostUp = sysctl -w net.ipv4.ip_forward=1; \\
        iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT; \\
        iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
PostDown = sysctl -w net.ipv4.ip_forward=0; \\
          iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT; \\
          iptables -D FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

[Peer]
# Spoke A
PublicKey = ${NODE_A_PUBLIC}
AllowedIPs = 10.88.0.11/32
PersistentKeepalive = 25

[Peer]
# Spoke B
PublicKey = ${NODE_B_PUBLIC}
AllowedIPs = 10.88.0.12/32
PersistentKeepalive = 25

[Peer]
# Spoke C
PublicKey = ${NODE_C_PUBLIC}
AllowedIPs = 10.88.0.13/32
PersistentKeepalive = 25
EOF

log "WireGuard configurations created:"
log "  - Hub: config/hub/wg0.conf (IP: 10.88.0.1)"
log "  - Node A: config/node-a/wg0.conf (IP: 10.88.0.11)"
log "  - Node B: config/node-b/wg0.conf (IP: 10.88.0.12)"
log "  - Node C: config/node-c/wg0.conf (IP: 10.88.0.13)"

# Set proper permissions
chmod 600 config/hub/server.key config/node-a/private.key config/node-b/private.key config/node-c/private.key
chmod 644 config/hub/server.pub config/node-a/public.key config/node-b/public.key config/node-c/public.key
chmod 600 config/hub/wg0.conf config/node-a/wg0.conf config/node-b/wg0.conf config/node-c/wg0.conf

# Create .env template
log "Creating .env template..."
cat > .env.template << EOF
# DStack VPN Environment Configuration
# Copy this file to .env and fill in your values

# WireGuard Configuration
WIREGUARD_PRIVATE_KEY_A=${NODE_A_PRIVATE}
WIREGUARD_PRIVATE_KEY_B=${NODE_B_PRIVATE}
WIREGUARD_PRIVATE_KEY_C=${NODE_C_PRIVATE}

# Hub Configuration (DigitalOcean NYC)
HUB_PUBLIC_IP=your_digitalocean_hub_ip_here
HUB_PUBLIC_KEY=${HUB_PUBLIC}

# Node Configuration
NODE_A_IP=10.88.0.11
NODE_B_IP=10.88.0.12
NODE_C_IP=10.88.0.13

# Health Check Configuration
HEALTH_CHECK_PORT=8000
EOF

log "Key generation complete!"
log "Next steps:"
log "1. Copy .env.template to .env"
log "2. Fill in HUB_PUBLIC_IP and HUB_PUBLIC_KEY in .env"
log "3. Run: ./scripts/deploy-docker.sh deploy" 