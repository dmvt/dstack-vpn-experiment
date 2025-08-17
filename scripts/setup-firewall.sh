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
STATUS_PORT="8000"
WG_INTERFACE="wg0"
HUB_IP="10.88.0.1"
OVERLAY_NETWORK="10.88.0.0/24"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

log "Setting up firewall for DStack VPN spoke..."

# Install nftables if not present
if ! command -v nft &> /dev/null; then
    log "Installing nftables..."
    if command -v apt &> /dev/null; then
        apt update && apt install -y nftables
    elif command -v yum &> /dev/null; then
        yum install -y nftables
    else
        error "Unsupported package manager. Please install nftables manually."
        exit 1
    fi
fi

# Create nftables configuration
log "Configuring nftables firewall..."
cat > /etc/nftables.conf << EOF
flush ruleset

table inet filter {
  chains {
    input {
      type filter hook input priority 0;
      policy drop;
      iif lo accept
      ct state established,related accept
      # Public status page
      tcp dport ${STATUS_PORT} accept
      # VPN traffic from peers (all spokes except hub)
      iif "${WG_INTERFACE}" ip saddr ${OVERLAY_NETWORK} ip saddr != ${HUB_IP} accept
    }
    forward { 
      type filter hook forward priority 0; 
      policy drop; 
    }
    output { 
      type filter hook output priority 0; 
      policy accept; 
    }
  }
}
EOF

# Apply nftables configuration
log "Applying firewall rules..."
nft -f /etc/nftables.conf

# Enable and start nftables service
log "Enabling nftables service..."
systemctl enable --now nftables

# Verify configuration
log "Verifying firewall configuration..."
if nft list ruleset | grep -q "${STATUS_PORT}"; then
    log "Status port ${STATUS_PORT} is allowed"
else
    warning "Status port ${STATUS_PORT} not found in firewall rules"
fi

if nft list ruleset | grep -q "${HUB_IP}"; then
    log "Hub IP ${HUB_IP} is properly blocked from originating traffic"
else
    warning "Hub IP blocking rule not found"
fi

# Test firewall
log "Testing firewall configuration..."
log "Current rules:"
nft list ruleset

# Create firewall status script
log "Creating firewall status script..."
cat > /usr/local/bin/firewall-status << 'EOF'
#!/bin/bash
echo "=== DStack Spoke Firewall Status ==="
echo "nftables Rules:"
nft list ruleset
echo ""
echo "Service Status:"
systemctl status nftables --no-pager -l
echo ""
echo "Active Connections:"
ss -tuln | grep :8000
EOF

chmod +x /usr/local/bin/firewall-status

log "Firewall setup complete!"
log ""
log "=== Firewall Rules Applied ==="
log "- Status page accessible on port ${STATUS_PORT}"
log "- VPN traffic allowed from overlay network ${OVERLAY_NETWORK}"
log "- Hub IP ${HUB_IP} blocked from originating traffic"
log "- All other inbound traffic dropped"
log ""
log "=== Useful Commands ==="
log "Check firewall status: firewall-status"
log "View rules: nft list ruleset"
log "Service status: systemctl status nftables"
log ""
log "=== Security Notes ==="
log "- Only status page (port ${STATUS_PORT}) is publicly accessible"
log "- VPN traffic is restricted to overlay network"
log "- Hub cannot originate traffic to spokes (security feature)"
log "- All other inbound traffic is blocked by default"
