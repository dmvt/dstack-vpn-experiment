#!/bin/bash
set -e

# Start the status service in the background
echo "Starting status service..."
NODE_ID="${NODE_ID:-node}"
NODE_IP="${NODE_IP:-10.88.0.11}"
export NODE_ID NODE_IP

/usr/local/bin/dstack-status &
STATUS_PID=$!

# Configure WireGuard
echo "Configuring WireGuard..."

# If WireGuard config is provided via volume, use it
if [ -f /etc/wireguard/wg0.conf ]; then
    echo "Using existing WireGuard configuration"
else
    # Generate config from environment variables
    echo "Generating WireGuard configuration from environment..."
    
    if [ -z "$WIREGUARD_PRIVATE_KEY" ] || [ -z "$HUB_PUBLIC_KEY" ] || [ -z "$HUB_PUBLIC_IP" ]; then
        echo "Error: Required environment variables not set"
        echo "Need: WIREGUARD_PRIVATE_KEY, HUB_PUBLIC_KEY, HUB_PUBLIC_IP"
        exit 1
    fi
    
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${NODE_IP}/32
PrivateKey = ${WIREGUARD_PRIVATE_KEY}
ListenPort = 51820

[Peer]
# Hub
PublicKey = ${HUB_PUBLIC_KEY}
Endpoint = ${HUB_PUBLIC_IP}:51820
AllowedIPs = 10.88.0.0/24
PersistentKeepalive = 25
EOF
fi

# Set permissions
chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Start WireGuard
echo "Starting WireGuard..."
wg-quick up wg0

# Log WireGuard status
echo "WireGuard status:"
wg show

# Keep container running and handle shutdown
trap "wg-quick down wg0; kill $STATUS_PID" SIGTERM SIGINT

# Wait for either process to exit
wait $STATUS_PID
