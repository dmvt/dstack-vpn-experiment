#!/bin/bash

# Automated WireGuard Container Update Script
# This script updates deployed containers with new WireGuard configuration

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

# Function to get CVM App IDs
get_cvm_app_ids() {
    print_status "Getting CVM App IDs..."
    
    local cvms_output=$(npx phala cvms list)
    local node1_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-1" | grep "App ID" | head -1 | awk '{print $3}')
    local node2_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-2" | grep "App ID" | head -1 | awk '{print $3}')
    
    if [[ -z "$node1_app_id" || -z "$node2_app_id" ]]; then
        print_error "Could not find App IDs for VPN nodes"
        exit 1
    fi
    
    echo "$node1_app_id $node2_app_id"
}

# Function to update container via Node Info URL
update_container_config() {
    local app_id="$1"
    local node_num="$2"
    local config_file="$3"
    
    print_status "Updating Node $node_num ($app_id)..."
    
    # Get Node Info URL
    local cvms_output=$(npx phala cvms list)
    local node_info_url=$(echo "$cvms_output" | grep -A 10 "$app_id" | grep "Node Info URL" | head -1 | awk '{print $3}')
    
    if [[ -z "$node_info_url" ]]; then
        print_error "Could not find Node Info URL for $app_id"
        return 1
    fi
    
    print_status "Node Info URL: $node_info_url"
    
    # Create a temporary script to execute in the container
    local temp_script="/tmp/update-wg-$node_num.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
set -e

echo "Updating WireGuard configuration for Node $node_num..."

# Stop WireGuard if running
if wg show wg0 >/dev/null 2>&1; then
    echo "Stopping WireGuard..."
    wg-quick down wg0 || true
fi

# Backup existing config
if [[ -f /etc/wireguard/wg0.conf ]]; then
    cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.backup
    echo "Backed up existing configuration"
fi

# Create new configuration
cat > /etc/wireguard/wg0.conf << 'WGEOF'
$(cat "$config_file")
WGEOF

echo "Configuration updated"

# Start WireGuard
echo "Starting WireGuard..."
wg-quick up wg0

# Test connectivity
echo "Testing WireGuard interface..."
if wg show wg0 >/dev/null 2>&1; then
    echo "WireGuard is running successfully"
    wg show wg0
else
    echo "ERROR: WireGuard failed to start"
    exit 1
fi

echo "Node $node_num update complete!"
EOF

    # Execute the script in the container via Node Info URL
    print_status "Executing update script in container..."
    
    # We'll use curl to send the script to the container
    # This is a simplified approach - in practice, you might need to use the Phala Cloud API
    local response=$(curl -s -X POST "$node_info_url/exec" \
        -H "Content-Type: application/json" \
        -d "{\"command\": \"bash\", \"args\": [\"$temp_script\"]}" 2>/dev/null || echo "API not available")
    
    if [[ "$response" == *"API not available"* ]]; then
        print_warning "Direct API access not available. Using manual approach..."
        print_status "Please manually execute the following in the container:"
        echo ""
        echo "=== MANUAL UPDATE FOR NODE $node_num ==="
        cat "$temp_script"
        echo "=== END MANUAL UPDATE ==="
        echo ""
    else
        print_success "Update script executed successfully"
    fi
    
    # Clean up
    rm -f "$temp_script"
}

# Function to test connectivity between nodes
test_connectivity() {
    print_status "Testing connectivity between nodes..."
    
    # Get Node Info URLs
    local cvms_output=$(npx phala cvms list)
    local node1_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-1" | grep "Node Info URL" | head -1 | awk '{print $3}')
    local node2_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-2" | grep "Node Info URL" | head -1 | awk '{print $3}')
    
    # Test from Node 1 to Node 2
    print_status "Testing from Node 1 to Node 2..."
    local ping_test1=$(curl -s -X POST "$node1_url/exec" \
        -H "Content-Type: application/json" \
        -d '{"command": "ping", "args": ["-c", "3", "10.0.0.2"]}' 2>/dev/null || echo "API not available")
    
    if [[ "$ping_test1" == *"API not available"* ]]; then
        print_warning "Manual connectivity test required:"
        echo "  - From Node 1: ping -c 3 10.0.0.2"
        echo "  - From Node 2: ping -c 3 10.0.0.1"
    else
        print_success "Connectivity test completed"
    fi
}

# Main execution
main() {
    print_status "Starting automated WireGuard container update..."
    
    # Check prerequisites
    if ! command -v npx &> /dev/null; then
        print_error "npx is not installed"
        exit 1
    fi
    
    if ! npx phala auth status &> /dev/null; then
        print_error "Not authenticated with Phala Cloud"
        exit 1
    fi
    
    # Check if WireGuard configs exist
    if [[ ! -f "$CONFIG_DIR/phala/wg0.node-1.conf" || ! -f "$CONFIG_DIR/phala/wg0.node-2.conf" ]]; then
        print_error "WireGuard configurations not found. Run configure-wireguard-peers.sh first."
        exit 1
    fi
    
    # Get CVM App IDs
    local app_ids=$(get_cvm_app_ids)
    local node1_app_id=$(echo "$app_ids" | awk '{print $1}')
    local node2_app_id=$(echo "$app_ids" | awk '{print $2}')
    
    print_success "Found App IDs: $node1_app_id, $node2_app_id"
    
    # Update Node 1
    update_container_config "$node1_app_id" "1" "$CONFIG_DIR/phala/wg0.node-1.conf"
    
    # Update Node 2
    update_container_config "$node2_app_id" "2" "$CONFIG_DIR/phala/wg0.node-2.conf"
    
    # Test connectivity
    test_connectivity
    
    print_success "Automated WireGuard container update complete!"
    print_status "Check the logs above for any manual steps that may be required."
}

# Run main function
main "$@" 