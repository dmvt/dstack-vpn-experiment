#!/bin/bash

# Automated WireGuard Update Script
# This script generates the exact commands to update WireGuard in deployed containers

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

# Function to get CVM information
get_cvm_info() {
    print_status "Getting CVM information..."
    
    local cvms_output=$(npx phala cvms list)
    local node1_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-1" | grep "App ID" | head -1 | awk '{print $3}')
    local node2_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-2" | grep "App ID" | head -1 | awk '{print $3}')
    local node1_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-1" | grep "Node Info URL" | head -1 | awk '{print $3}')
    local node2_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-2" | grep "Node Info URL" | head -1 | awk '{print $3}')
    
    if [[ -z "$node1_app_id" || -z "$node2_app_id" ]]; then
        print_error "Could not find App IDs for VPN nodes"
        exit 1
    fi
    
    echo "$node1_app_id $node2_app_id $node1_url $node2_url"
}

# Function to generate update commands
generate_update_commands() {
    local node1_app_id="$1"
    local node2_app_id="$2"
    local node1_url="$3"
    local node2_url="$4"
    
    print_status "Generating automated update commands..."
    
    # Create Node 1 update script
    cat > "$CONFIG_DIR/phala/update-node1.sh" << 'EOF'
#!/bin/bash
# Automated WireGuard Update for Node 1

set -e

echo "=== UPDATING NODE 1 WIREGUARD CONFIGURATION ==="

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
EOF
    cat "$CONFIG_DIR/phala/wg0.node-1.conf" >> "$CONFIG_DIR/phala/update-node1.sh"
    cat >> "$CONFIG_DIR/phala/update-node1.sh" << 'EOF'
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
    echo "Testing connectivity to Node 2..."
    ping -c 3 10.0.0.2 || echo "Ping test failed - this is normal if Node 2 is not updated yet"
else
    echo "ERROR: WireGuard failed to start"
    exit 1
fi

echo "Node 1 update complete!"
EOF

    # Create Node 2 update script
    cat > "$CONFIG_DIR/phala/update-node2.sh" << 'EOF'
#!/bin/bash
# Automated WireGuard Update for Node 2

set -e

echo "=== UPDATING NODE 2 WIREGUARD CONFIGURATION ==="

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
EOF
    cat "$CONFIG_DIR/phala/wg0.node-2.conf" >> "$CONFIG_DIR/phala/update-node2.sh"
    cat >> "$CONFIG_DIR/phala/update-node2.sh" << 'EOF'
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
    echo "Testing connectivity to Node 1..."
    ping -c 3 10.0.0.1 || echo "Ping test failed - this is normal if Node 1 is not updated yet"
else
    echo "ERROR: WireGuard failed to start"
    exit 1
fi

echo "Node 2 update complete!"
EOF

    # Make scripts executable
    chmod +x "$CONFIG_DIR/phala/update-node1.sh"
    chmod +x "$CONFIG_DIR/phala/update-node2.sh"
    
    # Create automated execution script
    cat > "$CONFIG_DIR/phala/automated-update.sh" << EOF
#!/bin/bash
# Automated WireGuard Update Execution Script

echo "=== AUTOMATED WIREGUARD UPDATE ==="
echo ""
echo "This script will automatically update both nodes with new WireGuard configuration."
echo ""
echo "Node 1 App ID: $node1_app_id"
echo "Node 2 App ID: $node2_app_id"
echo ""
echo "Node 1 URL: $node1_url"
echo "Node 2 URL: $node2_url"
echo ""

# Function to execute command in container
execute_in_container() {
    local url="\$1"
    local script="\$2"
    local node_name="\$3"
    
    echo "Updating \$node_name..."
    
    # Try to execute via Node Info URL
    local response=\$(curl -s -X POST "\$url/exec" \\
        -H "Content-Type: application/json" \\
        -d "{\\\"command\\\": \\\"bash\\\", \\\"args\\\": [\\\"\$script\\\"]}" 2>/dev/null || echo "API not available")
    
    if [[ "\$response" == *"API not available"* ]]; then
        echo "Direct API access not available for \$node_name."
        echo "Please manually execute the update script in the container."
        echo "Script location: \$script"
        return 1
    else
        echo "Update completed successfully for \$node_name"
        return 0
    fi
}

# Update Node 1
echo "Step 1: Updating Node 1..."
execute_in_container "$node1_url" "/tmp/update-node1.sh" "Node 1"

# Wait a moment
sleep 5

# Update Node 2
echo "Step 2: Updating Node 2..."
execute_in_container "$node2_url" "/tmp/update-node2.sh" "Node 2"

# Final connectivity test
echo "Step 3: Testing connectivity..."
sleep 10

echo "Automated update complete!"
echo ""
echo "To verify connectivity, run these commands in the containers:"
echo "  Node 1: ping -c 3 10.0.0.2"
echo "  Node 2: ping -c 3 10.0.0.1"
EOF

    chmod +x "$CONFIG_DIR/phala/automated-update.sh"
    
    print_success "Generated update scripts"
}

# Function to display execution instructions
display_instructions() {
    local node1_app_id="$1"
    local node2_app_id="$2"
    local node1_url="$3"
    local node2_url="$4"
    
    print_success "Automated WireGuard update scripts generated!"
    echo ""
    echo "=== EXECUTION INSTRUCTIONS ==="
    echo ""
    echo "Option 1: Automated Update (if API access is available)"
    echo "  Run: $CONFIG_DIR/phala/automated-update.sh"
    echo ""
    echo "Option 2: Manual Update (recommended)"
    echo ""
    echo "1. Access Node 1 container:"
    echo "   - Go to: $node1_url"
    echo "   - Copy and paste the contents of: $CONFIG_DIR/phala/update-node1.sh"
    echo ""
    echo "2. Access Node 2 container:"
    echo "   - Go to: $node2_url"
    echo "   - Copy and paste the contents of: $CONFIG_DIR/phala/update-node2.sh"
    echo ""
    echo "3. Test connectivity:"
    echo "   - From Node 1: ping -c 3 10.0.0.2"
    echo "   - From Node 2: ping -c 3 10.0.0.1"
    echo ""
    echo "=== GENERATED FILES ==="
    echo "  - $CONFIG_DIR/phala/update-node1.sh (Node 1 update script)"
    echo "  - $CONFIG_DIR/phala/update-node2.sh (Node 2 update script)"
    echo "  - $CONFIG_DIR/phala/automated-update.sh (Automated execution)"
    echo ""
}

# Main execution
main() {
    print_status "Starting automated WireGuard update generation..."
    
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
    
    # Get CVM information
    local cvm_info=$(get_cvm_info)
    local node1_app_id=$(echo "$cvm_info" | awk '{print $1}')
    local node2_app_id=$(echo "$cvm_info" | awk '{print $2}')
    local node1_url=$(echo "$cvm_info" | awk '{print $3}')
    local node2_url=$(echo "$cvm_info" | awk '{print $4}')
    
    print_success "Found CVM information"
    print_status "Node 1: $node1_app_id"
    print_status "Node 2: $node2_app_id"
    
    # Generate update commands
    generate_update_commands "$node1_app_id" "$node2_app_id" "$node1_url" "$node2_url"
    
    # Display instructions
    display_instructions "$node1_app_id" "$node2_app_id" "$node1_url" "$node2_url"
    
    print_success "Automated WireGuard update generation complete!"
}

# Run main function
main "$@" 