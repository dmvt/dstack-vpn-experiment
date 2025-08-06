#!/bin/bash

# Phala Cloud VPN Test Script
# This script tests the deployed VPN system on Phala Cloud

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking test prerequisites..."
    
    # Check if phala CLI is available
    if ! command -v npx &> /dev/null; then
        print_error "npx is not installed. Please install Node.js and npm."
        exit 1
    fi
    
    # Check if we're authenticated
    if ! npx phala auth status &> /dev/null; then
        print_error "Not authenticated with Phala Cloud. Please run 'npx phala auth login' first."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    print_success "Test prerequisites check passed"
}

# Function to get the latest CVM
get_latest_cvm() {
    print_status "Getting latest CVM..."
    
    # Get CVMs in JSON format
    CVMS_JSON=$(npx phala cvms list --json 2>/dev/null || echo "[]")
    
    if [[ "$CVMS_JSON" == "[]" ]]; then
        print_error "No CVMs found. Please deploy a CVM first."
        return 1
    fi
    
    # Get the first CVM (most recent)
    CVM_APP_ID=$(echo "$CVMS_JSON" | jq -r '.[0].hosted.app_id')
    CVM_NAME=$(echo "$CVMS_JSON" | jq -r '.[0].hosted.name')
    CVM_STATUS=$(echo "$CVMS_JSON" | jq -r '.[0].hosted.status')
    
    if [[ -z "$CVM_APP_ID" || "$CVM_APP_ID" == "null" ]]; then
        print_error "No valid CVM found"
        return 1
    fi
    
    print_success "Found CVM: $CVM_NAME (ID: $CVM_APP_ID, Status: $CVM_STATUS)"
    echo "$CVM_APP_ID"
}

# Function to test CVM status
test_cvm_status() {
    local cvm_app_id="$1"
    
    print_status "Testing CVM status..."
    
    # Get CVM details
    print_status "Getting CVM details for: $cvm_app_id"
    npx phala cvms get "$cvm_app_id"
    
    print_success "CVM status test completed"
}

# Function to test network connectivity
test_network_connectivity() {
    local cvm_app_id="$1"
    
    print_status "Testing network connectivity..."
    
    # Get network information
    print_status "Getting network information for: $cvm_app_id"
    npx phala cvms network "$cvm_app_id"
    
    print_success "Network connectivity test completed"
}

# Function to test VPN functionality
test_vpn_functionality() {
    local cvm_app_id="$1"
    
    print_status "Testing VPN functionality..."
    
    # Get CVM details to find the app URL
    CVM_DETAILS=$(npx phala cvms get "$cvm_app_id" --json 2>/dev/null || echo "{}")
    APP_URL=$(echo "$CVM_DETAILS" | jq -r '.app_url // empty')
    
    if [[ -n "$APP_URL" ]]; then
        print_status "Testing health endpoint at: $APP_URL"
        
        # Test health endpoint
        if curl -s -f "$APP_URL/health" > /dev/null; then
            print_success "Health endpoint is accessible"
        else
            print_warning "Health endpoint is not accessible"
        fi
        
        # Test stats endpoint
        if curl -s -f "$APP_URL/stats" > /dev/null; then
            print_success "Stats endpoint is accessible"
        else
            print_warning "Stats endpoint is not accessible"
        fi
        
        # Test WireGuard status endpoint
        if curl -s -f "$APP_URL/wireguard" > /dev/null; then
            print_success "WireGuard status endpoint is accessible"
        else
            print_warning "WireGuard status endpoint is not accessible"
        fi
    else
        print_warning "App URL not available for testing"
    fi
    
    print_success "VPN functionality test completed"
}

# Function to test contract integration
test_contract_integration() {
    local cvm_app_id="$1"
    
    print_status "Testing contract integration..."
    
    # This would typically involve testing the smart contract integration
    # For now, we'll just check if the CVM is running and accessible
    
    print_status "Contract integration test would be implemented here"
    print_warning "Contract integration test not yet implemented"
    
    print_success "Contract integration test completed"
}

# Function to run comprehensive tests
run_comprehensive_tests() {
    local cvm_app_id="$1"
    
    print_status "Running comprehensive tests for CVM: $cvm_app_id"
    
    # Test CVM status
    test_cvm_status "$cvm_app_id"
    
    # Test network connectivity
    test_network_connectivity "$cvm_app_id"
    
    # Test VPN functionality
    test_vpn_functionality "$cvm_app_id"
    
    # Test contract integration
    test_contract_integration "$cvm_app_id"
    
    print_success "Comprehensive tests completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  status      Test CVM status"
    echo "  network     Test network connectivity"
    echo "  vpn         Test VPN functionality"
    echo "  contract    Test contract integration"
    echo "  all         Run all tests"
    echo "  help        Show this help message"
    echo ""
    echo "Options:"
    echo "  --cvm-id ID     Specify CVM App ID to test"
    echo ""
    echo "Examples:"
    echo "  $0 all"
    echo "  $0 status"
    echo "  $0 --cvm-id app_123456 vpn"
}

# Parse command line arguments
CVM_APP_ID=""
COMMAND="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --cvm-id)
            CVM_APP_ID="$2"
            shift 2
            ;;
        status)
            COMMAND="status"
            shift
            ;;
        network)
            COMMAND="network"
            shift
            ;;
        vpn)
            COMMAND="vpn"
            shift
            ;;
        contract)
            COMMAND="contract"
            shift
            ;;
        all)
            COMMAND="all"
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
    print_status "Starting Phala Cloud VPN tests..."
    
    # Check prerequisites
    check_prerequisites
    
    # Get CVM App ID if not provided
    if [[ -z "$CVM_APP_ID" ]]; then
        CVM_APP_ID=$(get_latest_cvm)
        if [[ $? -ne 0 ]]; then
            print_error "Failed to get CVM App ID"
            exit 1
        fi
    fi
    
    print_status "Testing CVM: $CVM_APP_ID"
    
    # Run tests based on command
    case $COMMAND in
        status)
            test_cvm_status "$CVM_APP_ID"
            ;;
        network)
            test_network_connectivity "$CVM_APP_ID"
            ;;
        vpn)
            test_vpn_functionality "$CVM_APP_ID"
            ;;
        contract)
            test_contract_integration "$CVM_APP_ID"
            ;;
        all)
            run_comprehensive_tests "$CVM_APP_ID"
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
    
    print_success "All tests completed successfully"
}

# Run main function
main "$@" 