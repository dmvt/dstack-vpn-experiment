#!/bin/bash

# Test script for Phala Cloud VPN deployment
# This script verifies that the deployment is working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to test deployment
test_deployment() {
    print_status "Testing Phala Cloud VPN deployment..."
    
    # Get the latest CVMs
    print_status "Getting CVM list..."
    CVM_LIST=$(npx phala cvms list --json)
    
    if [[ -z "$CVM_LIST" ]]; then
        print_error "No CVMs found"
        return 1
    fi
    
    # Parse CVM information
    CVM_COUNT=$(echo "$CVM_LIST" | jq '. | length')
    print_status "Found $CVM_COUNT CVMs"
    
    if [[ "$CVM_COUNT" -lt 2 ]]; then
        print_warning "Expected 2 CVMs (node-1 and node-2), found $CVM_COUNT"
    fi
    
    # Test each CVM
    for i in $(seq 0 $((CVM_COUNT - 1))); do
        CVM_INFO=$(echo "$CVM_LIST" | jq ".[$i]")
        CVM_NAME=$(echo "$CVM_INFO" | jq -r '.name')
        CVM_APP_ID=$(echo "$CVM_INFO" | jq -r '.hosted.app_id')
        CVM_STATUS=$(echo "$CVM_INFO" | jq -r '.hosted.status')
        
        print_status "Testing CVM: $CVM_NAME (ID: $CVM_APP_ID, Status: $CVM_STATUS)"
        
        if [[ "$CVM_STATUS" != "Running" ]]; then
            print_warning "CVM $CVM_NAME is not running (status: $CVM_STATUS)"
            continue
        fi
        
        # Get CVM details
        print_status "Getting details for $CVM_NAME..."
        npx phala cvms get "$CVM_APP_ID"
        
        # Test network connectivity
        print_status "Testing network for $CVM_NAME..."
        npx phala cvms network "$CVM_APP_ID"
        
        # Check if this is node-1 (should have nginx) or node-2 (should have client)
        if [[ "$CVM_NAME" == *"node-1"* ]]; then
            print_status "This appears to be node-1 (server node)"
            print_status "Expected services: wireguard-vpn, mullvad-proxy, nginx-server"
        elif [[ "$CVM_NAME" == *"node-2"* ]]; then
            print_status "This appears to be node-2 (client node)"
            print_status "Expected services: wireguard-vpn, mullvad-proxy, test-client"
        else
            print_warning "Unknown node type: $CVM_NAME"
        fi
        
        echo ""
    done
    
    print_success "Deployment testing complete"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  test        Test the deployed VPN system"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 test"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        test)
            COMMAND="test"
            shift
            ;;
        help|--help|-h)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_status "Starting Phala Cloud VPN deployment testing..."
    
    case ${COMMAND:-test} in
        test)
            test_deployment
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 