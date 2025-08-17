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

# Configuration
HUB_IP="10.88.0.1"
WG_PORT="51820"
SSH_PORT="22"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

log "Starting DStack VPN Hub provisioning on DigitalOcean..."

# Update system
log "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
log "Installing WireGuard and dependencies..."
apt install -y wireguard qrencode nftables curl

# Create WireGuard directory
log "Setting up WireGuard..."
mkdir -p /etc/wireguard
cd /etc/wireguard

# Check if keys already exist
if [[ ! -f "server.key" ]] || [[ ! -f "server.pub" ]]; then
    error "WireGuard keys not found. Please run the key generation script first."
    error "Expected files: /etc/wireguard/server.key and /etc/wireguard/server.pub"
    exit 1
fi

# Set proper permissions
chmod 600 server.key
chmod 644 server.pub

# Create WireGuard configuration
log "Creating WireGuard configuration..."
cat > wg0.conf << EOF
[Interface]
Address = ${HUB_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = $(cat server.key)
# Enable L3 forwarding between spokes (no NAT)
PostUp = sysctl -w net.ipv4.ip_forward=1; \\
        iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT; \\
        iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
PostDown = sysctl -w net.ipv4.ip_forward=0; \\
          iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT; \\
          iptables -D FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
EOF

# Check if peer configs exist and add them
if [[ -f "/tmp/spoke_a.pub" ]]; then
    log "Adding Spoke A peer..."
    cat >> wg0.conf << EOF

[Peer]
# Spoke A
PublicKey = $(cat /tmp/spoke_a.pub)
AllowedIPs = 10.88.0.11/32
PersistentKeepalive = 25
EOF
fi

if [[ -f "/tmp/spoke_b.pub" ]]; then
    log "Adding Spoke B peer..."
    cat >> wg0.conf << EOF

[Peer]
# Spoke B
PublicKey = $(cat /tmp/spoke_b.pub)
AllowedIPs = 10.88.0.12/32
PersistentKeepalive = 25
EOF
fi

if [[ -f "/tmp/spoke_c.pub" ]]; then
    log "Adding Spoke C peer..."
    cat >> wg0.conf << EOF

[Peer]
# Spoke C
PublicKey = $(cat /tmp/spoke_c.pub)
AllowedIPs = 10.88.0.13/32
PersistentKeepalive = 25
EOF
fi

# Set proper permissions
chmod 600 wg0.conf

# Configure firewall (nftables)
log "Configuring firewall..."
cat > /etc/nftables.conf << EOF
flush ruleset

table inet filter {
  chains {
    input { 
      type filter hook input priority 0; 
      policy drop;
      iif lo accept
      ct state established,related accept
      tcp dport ${SSH_PORT} accept
      udp dport ${WG_PORT} accept
    }
    forward { 
      type filter hook forward priority 0; 
      policy drop;
      iif "wg0" oif "wg0" accept
    }
    output { 
      type filter hook output priority 0; 
      policy accept;
      oif "wg0" ip daddr 10.88.0.0/24 drop
    }
  }
}
EOF

# Enable and start nftables
systemctl enable --now nftables
nft -f /etc/nftables.conf

# Enable IP forwarding
log "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Enable and start WireGuard
log "Starting WireGuard service..."
systemctl enable --now wg-quick@wg0

# Wait for service to start
sleep 5

# Check WireGuard status
log "Checking WireGuard status..."
if systemctl is-active --quiet wg-quick@wg0; then
    log "WireGuard service is running"
    wg show
else
    error "WireGuard service failed to start"
    journalctl -u wg-quick@wg0 --no-pager -n 20
    exit 1
fi

# Test connectivity
log "Testing VPN connectivity..."
if ip link show wg0 > /dev/null 2>&1; then
    log "WireGuard interface wg0 is up"
    log "Hub IP: $(ip addr show wg0 | grep 'inet ' | awk '{print $2}')"
else
    error "WireGuard interface wg0 is not up"
    exit 1
fi

# Create status check script
log "Creating status check script..."
cat > /usr/local/bin/vpn-status << 'EOF'
#!/bin/bash
echo "=== DStack VPN Hub Status ==="
echo "WireGuard Interface:"
wg show
echo ""
echo "Network Interfaces:"
ip addr show wg0
echo ""
echo "Firewall Rules:"
nft list ruleset
echo ""
echo "IP Forwarding:"
sysctl net.ipv4.ip_forward
EOF

chmod +x /usr/local/bin/vpn-status

# Create systemd service for WireGuard
log "Creating WireGuard systemd service..."
cat > /etc/systemd/system/wg-quick@wg0.service.d/override.conf << EOF
[Service]
Restart=always
RestartSec=5
EOF

systemctl daemon-reload

log "Hub provisioning complete!"
log ""
log "=== Next Steps ==="
log "1. Copy the hub's public key to your DStack nodes"
log "2. Configure your DStack nodes with the hub's public key"
log "3. Test connectivity: ping 10.88.0.11 from 10.88.0.12"
log ""
log "=== Useful Commands ==="
log "Check status: vpn-status"
log "WireGuard status: wg show"
log "Service status: systemctl status wg-quick@wg0"
log "Firewall status: nft list ruleset"
log ""
log "=== Security Notes ==="
log "- SSH access is restricted to port ${SSH_PORT}"
log "- WireGuard listens on port ${WG_PORT}/UDP"
log "- IP forwarding is enabled for inter-spoke routing"
log "- Hub cannot originate traffic to spokes (security feature)"
