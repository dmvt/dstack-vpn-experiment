#!/bin/bash

# Complete WireGuard Deployment and Configuration Script
# This script automates the entire process: deploy, get URLs, configure peers, update containers

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

# Function to deploy to Phala Cloud
deploy_to_phala() {
    print_status "Step 1: Deploying to Phala Cloud..."
    
    if [[ -f "$PROJECT_ROOT/scripts/deploy-phala.sh" ]]; then
        cd "$PROJECT_ROOT"
        ./scripts/deploy-phala.sh
        print_success "Deployment completed"
    else
        print_error "Deploy script not found: $PROJECT_ROOT/scripts/deploy-phala.sh"
        exit 1
    fi
}

# Function to configure WireGuard peers
configure_wireguard_peers() {
    print_status "Step 2: Configuring WireGuard peers..."
    
    if [[ -f "$PROJECT_ROOT/scripts/configure-wireguard-peers.sh" ]]; then
        cd "$PROJECT_ROOT"
        ./scripts/configure-wireguard-peers.sh
        print_success "WireGuard peer configuration completed"
    else
        print_error "Configure script not found: $PROJECT_ROOT/scripts/configure-wireguard-peers.sh"
        exit 1
    fi
}

# Function to generate update scripts
generate_update_scripts() {
    print_status "Step 3: Generating update scripts..."
    
    if [[ -f "$PROJECT_ROOT/scripts/automated-wireguard-update.sh" ]]; then
        cd "$PROJECT_ROOT"
        ./scripts/automated-wireguard-update.sh
        print_success "Update scripts generated"
    else
        print_error "Update script not found: $PROJECT_ROOT/scripts/automated-wireguard-update.sh"
        exit 1
    fi
}

# Function to get final status and instructions
get_final_status() {
    print_status "Step 4: Getting final status and instructions..."
    
    # Get CVM information
    local cvms_output=$(npx phala cvms list)
    local node1_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-1" | grep "App ID" | head -1 | awk '{print $3}')
    local node2_app_id=$(echo "$cvms_output" | grep -A 5 "dstack-node-2" | grep "App ID" | head -1 | awk '{print $3}')
    local node1_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-1" | grep "Node Info URL" | head -1 | awk '{print $3}')
    local node2_url=$(echo "$cvms_output" | grep -A 10 "dstack-node-2" | grep "Node Info URL" | head -1 | awk '{print $3}')
    
    if [[ -z "$node1_app_id" || -z "$node2_app_id" ]]; then
        print_error "Could not find deployed nodes"
        return 1
    fi
    
    # Extract hostnames for port 8000
    local node1_host=$(echo "$node1_url" | sed 's|https://\([^:]*\):.*|\1|')
    local node2_host=$(echo "$node2_url" | sed 's|https://\([^:]*\):.*|\1|')
    
    print_success "Deployment and configuration complete!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo ""
    echo "✅ Deployed Nodes:"
    echo "  - Node 1: $node1_app_id"
    echo "  - Node 2: $node2_app_id"
    echo ""
    echo "✅ DStack URLs (Port 8000):"
    echo "  - Node 1: $node1_host:8000"
    echo "  - Node 2: $node2_host:8000"
    echo ""
    echo "✅ Generated Files:"
    echo "  - WireGuard Configs: $CONFIG_DIR/phala/wg0.node-*.conf"
    echo "  - Update Scripts: $CONFIG_DIR/phala/update-node*.sh"
    echo ""
    echo "=== NEXT STEPS ==="
    echo ""
    echo "1. Update Node 1:"
    echo "   - Go to: $node1_url"
    echo "   - Run: cat $CONFIG_DIR/phala/update-node1.sh"
    echo ""
    echo "2. Update Node 2:"
    echo "   - Go to: $node2_url"
    echo "   - Run: cat $CONFIG_DIR/phala/update-node2.sh"
    echo ""
    echo "3. Test connectivity:"
    echo "   - From Node 1: ping -c 3 10.0.0.2"
    echo "   - From Node 2: ping -c 3 10.0.0.1"
    echo ""
    echo "=== WIREGUARD CLIENT CONFIGURATION ==="
    echo ""
    echo "For external clients, use these endpoints:"
    echo "  - Node 1: $node1_host:8000"
    echo "  - Node 2: $node2_host:8000"
    echo ""
    echo "The Mullvad proxy will handle TCP-to-UDP conversion automatically."
    echo ""
}

# Function to run in dry-run mode
dry_run() {
    print_status "DRY RUN MODE - No actual deployment will occur"
    echo ""
    echo "This script would execute the following steps:"
    echo "1. Deploy to Phala Cloud using ./scripts/deploy-phala.sh"
    echo "2. Configure WireGuard peers using ./scripts/configure-wireguard-peers.sh"
    echo "3. Generate update scripts using ./scripts/automated-wireguard-update.sh"
    echo "4. Display final status and instructions"
    echo ""
    echo "To run the actual deployment, use: $0 --deploy"
    echo ""
}

# Main execution
main() {
    print_status "Starting complete WireGuard deployment and configuration..."
    
    # Check prerequisites
    if ! command -v npx &> /dev/null; then
        print_error "npx is not installed"
        exit 1
    fi
    
    if ! npx phala auth status &> /dev/null; then
        print_error "Not authenticated with Phala Cloud. Run 'npx phala auth login' first."
        exit 1
    fi
    
    # Check command line arguments
    if [[ "$1" == "--dry-run" ]]; then
        dry_run
        exit 0
    elif [[ "$1" == "--deploy" ]]; then
        print_status "Running full deployment and configuration..."
    else
        print_error "Usage: $0 [--dry-run|--deploy]"
        echo ""
        echo "Options:"
        echo "  --dry-run    Show what would be executed without running it"
        echo "  --deploy     Execute the full deployment and configuration"
        echo ""
        echo "Example:"
        echo "  $0 --dry-run    # See what would happen"
        echo "  $0 --deploy     # Actually deploy and configure"
        exit 1
    fi
    
    # Execute the deployment pipeline
    deploy_to_phala
    configure_wireguard_peers
    generate_update_scripts
    get_final_status
    
    print_success "Complete WireGuard deployment and configuration finished!"
    echo ""
    print_status "Your VPN is now ready for configuration updates."
}

# Run main function
main "$@" 