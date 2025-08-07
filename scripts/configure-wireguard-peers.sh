#!/bin/bash

# WireGuard Peer Configuration Script
# This script configures WireGuard peers after deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get CVM URLs
get_cvm_urls() {
    print_status "Getting CVM URLs from Phala Cloud..."
    
    # Get the list of CVMs and extract our VPN nodes
    local cvms_output=$(npx phala cvms list)
    
    # Extract Node Info URLs for our VPN nodes
    local node1_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-1" | grep "Node Info URL" | head -1 | awk '{print $3}')
    local node2_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-2" | grep "Node Info URL" | head -1 | awk '{print $3}')
    
    if [[ -z "$node1_url" || -z "$node2_url" ]]; then
        print_error "Could not find Node Info URLs for VPN nodes"
        exit 1
    fi
    
    # Extract the hostname part for port 8000
    local node1_host=$(echo "$node1_url" | sed 's|https://\([^:]*\):.*|\1|')
    local node2_host=$(echo "$node2_url" | sed 's|https://\([^:]*\):.*|\1|')
    
    print_success "Retrieved CVM URLs"
    print_status "Node 1 URL: $node1_url"
    print_status "Node 2 URL: $node2_url"
    print_status "Node 1 Host: $node1_host"
    print_status "Node 2 Host: $node2_host"
    
    # Return the hostnames
    echo "$node1_host $node2_host"
}

# Function to generate WireGuard configuration with peers
generate_wireguard_config() {
    local node1_host="$1"
    local node2_host="$2"
    
    print_status "Generating WireGuard configuration with peers..."
    
    # Read WireGuard keys
    local node1_private_key=$(cat "$CONFIG_DIR/phala/private.node-1.key")
    local node2_private_key=$(cat "$CONFIG_DIR/phala/private.node-2.key")
    local node1_public_key=$(cat "$CONFIG_DIR/phala/public.node-1.key")
    local node2_public_key=$(cat "$CONFIG_DIR/phala/public.node-2.key")
    
    # Generate Node 1 configuration
    cat > "$CONFIG_DIR/phala/wg0.node-1.conf" << EOF
[Interface]
PrivateKey = $node1_private_key
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $node2_public_key
AllowedIPs = 10.0.0.2/32
Endpoint = $node2_host:8000
PersistentKeepalive = 25
EOF

    # Generate Node 2 configuration
    cat > "$CONFIG_DIR/phala/wg0.node-2.conf" << EOF
[Interface]
PrivateKey = $node2_private_key
Address = 10.0.0.2/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $node1_public_key
AllowedIPs = 10.0.0.1/32
Endpoint = $node1_host:8000
PersistentKeepalive = 25
EOF

    print_success "Generated WireGuard configurations"
}

# Function to update deployed containers
update_deployed_containers() {
    local node1_host="$1"
    local node2_host="$2"
    
    print_status "Updating deployed containers with new WireGuard configuration..."
    
    # Get CVM App IDs
    local cvms_output=$(npx phala cvms list)
    local node1_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-1" | grep "App ID" | head -1 | awk '{print $3}')
    local node2_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-2" | grep "App ID" | head -1 | awk '{print $3}')
    
    if [[ -z "$node1_app_id" || -z "$node2_app_id" ]]; then
        print_error "Could not find App IDs for VPN nodes"
        exit 1
    fi
    
    print_status "Found App IDs: $node1_app_id, $node2_app_id"
    
    # For now, we'll create a script that can be run manually
    # since Phala Cloud doesn't support direct container updates
    cat > "$CONFIG_DIR/phala/update-wireguard-config.sh" << EOF
#!/bin/bash
# Manual update script for WireGuard configuration

echo "To update WireGuard configuration on deployed containers:"
echo ""
echo "1. Node 1 ($node1_app_id):"
echo "   - Copy $CONFIG_DIR/phala/wg0.node-1.conf to /etc/wireguard/wg0.conf"
echo "   - Restart WireGuard: wg-quick down wg0 && wg-quick up wg0"
echo ""
echo "2. Node 2 ($node2_app_id):"
echo "   - Copy $CONFIG_DIR/phala/wg0.node-2.conf to /etc/wireguard/wg0.conf"
echo "   - Restart WireGuard: wg-quick down wg0 && wg-quick up wg0"
echo ""
echo "3. Test connectivity:"
echo "   - From Node 1: ping 10.0.0.2"
echo "   - From Node 2: ping 10.0.0.1"
EOF

    chmod +x "$CONFIG_DIR/phala/update-wireguard-config.sh"
    
    print_success "Created update script: $CONFIG_DIR/phala/update-wireguard-config.sh"
}

# Main execution
main() {
    print_status "Starting WireGuard peer configuration..."
    
    # Check prerequisites
    if ! command -v npx &> /dev/null; then
        print_error "npx is not installed"
        exit 1
    fi
    
    if ! npx phala auth status &> /dev/null; then
        print_error "Not authenticated with Phala Cloud"
        exit 1
    fi
    
    # Get CVM URLs
    local hosts=$(get_cvm_urls)
    local node1_host=$(echo "$hosts" | awk '{print $1}')
    local node2_host=$(echo "$hosts" | awk '{print $2}')
    
    # Generate WireGuard configuration
    generate_wireguard_config "$node1_host" "$node2_host"
    
    # Update deployed containers
    update_deployed_containers "$node1_host" "$node2_host"
    
    print_success "WireGuard peer configuration complete!"
    print_status "Run: $CONFIG_DIR/phala/update-wireguard-config.sh for manual update instructions"
}

# Run main function
main "$@" 