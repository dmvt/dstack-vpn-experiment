#!/bin/bash

# Phala Cloud VPN Deployment Script
# This script deploys the VPN system to Phala Cloud TEE

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
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.phala.yml"
ENV_FILE="$CONFIG_DIR/phala-cloud.env"

# Default values
CVM_NAME="dstack-vpn-experiment"
TEEPOD_ID=8
IMAGE_VERSION="dstack-0.3.6"
VCPU=2
MEMORY=4096
DISK_SIZE=40

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
    print_status "Checking prerequisites..."
    
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
    
    # Check if required files exist
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        print_error "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        exit 1
    fi
    
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Environment file not found: $ENV_FILE"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to generate WireGuard keys
generate_wireguard_keys() {
    print_status "Generating WireGuard keys..."
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR/phala"
    
    # Generate private key
    if [[ ! -f "$CONFIG_DIR/phala/private.key" ]]; then
        wg genkey > "$CONFIG_DIR/phala/private.key"
        print_success "Generated WireGuard private key"
    else
        print_warning "WireGuard private key already exists"
    fi
    
    # Generate public key
    if [[ ! -f "$CONFIG_DIR/phala/public.key" ]]; then
        wg pubkey < "$CONFIG_DIR/phala/private.key" > "$CONFIG_DIR/phala/public.key"
        print_success "Generated WireGuard public key"
    else
        print_warning "WireGuard public key already exists"
    fi
    
    # Set proper permissions
    chmod 600 "$CONFIG_DIR/phala/private.key"
    chmod 644 "$CONFIG_DIR/phala/public.key"
    
    # Update environment file with the private key
    PRIVATE_KEY=$(cat "$CONFIG_DIR/phala/private.key")
    # Use awk for better compatibility across platforms
    awk -v key="$PRIVATE_KEY" '/^WIREGUARD_PRIVATE_KEY=$/ { print "WIREGUARD_PRIVATE_KEY=" key; next } { print }' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
    
    print_success "WireGuard keys configured"
}

# Function to validate environment
validate_environment() {
    print_status "Validating environment configuration..."
    
    # Source the environment file
    source "$ENV_FILE"
    
    # Check required variables
    local missing_vars=()
    
    if [[ -z "$CONTRACT_ADDRESS" ]]; then
        missing_vars+=("CONTRACT_ADDRESS")
    fi
    
    if [[ -z "$RPC_URL" ]]; then
        missing_vars+=("RPC_URL")
    fi
    
    if [[ -z "$CONTRACT_PRIVATE_KEY" ]]; then
        missing_vars+=("CONTRACT_PRIVATE_KEY")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_warning "The following environment variables are not set:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Please set these variables in $ENV_FILE before deployment."
        echo "You can use the following commands to set them:"
        echo ""
        echo "  export CONTRACT_ADDRESS='your_contract_address'"
        echo "  export RPC_URL='your_rpc_url'"
        echo "  export CONTRACT_PRIVATE_KEY='your_private_key'"
        echo ""
        echo "Then update $ENV_FILE with these values."
        return 1
    fi
    
    print_success "Environment validation passed"
}

# Function to deploy to Phala Cloud
deploy_to_phala() {
    print_status "Deploying to Phala Cloud..."
    
    # Get the current timestamp for the deployment
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    DEPLOYMENT_NAME="${CVM_NAME}-${TIMESTAMP}"
    
    print_status "Deployment name: $DEPLOYMENT_NAME"
    print_status "TEEPod ID: $TEEPOD_ID"
    print_status "Image version: $IMAGE_VERSION"
    print_status "Resources: ${VCPU}vCPU, ${MEMORY}MB RAM, ${DISK_SIZE}GB disk"
    
    # Deploy using Phala CLI
    print_status "Creating CVM on Phala Cloud..."
    
    npx phala cvms create \
        --name "$DEPLOYMENT_NAME" \
        --compose "$DOCKER_COMPOSE_FILE" \
        --vcpu "$VCPU" \
        --memory "$MEMORY" \
        --disk-size "$DISK_SIZE" \
        --teepod-id "$TEEPOD_ID" \
        --image "$IMAGE_VERSION" \
        --env-file "$ENV_FILE" \
        --debug
    
    print_success "Deployment initiated successfully"
}

# Function to monitor deployment
monitor_deployment() {
    print_status "Monitoring deployment status..."
    
    # List CVMs to find our deployment
    print_status "Checking CVM status..."
    npx phala cvms list
    
    print_success "Deployment monitoring complete"
}

# Function to test deployment
test_deployment() {
    print_status "Testing deployment..."
    
    # Get the latest CVM
    CVM_APP_ID=$(npx phala cvms list --json | jq -r '.[0].hosted.app_id')
    
    if [[ -z "$CVM_APP_ID" || "$CVM_APP_ID" == "null" ]]; then
        print_error "No CVM found for testing"
        return 1
    fi
    
    print_status "Testing CVM: $CVM_APP_ID"
    
    # Get CVM details
    print_status "Getting CVM details..."
    npx phala cvms get "$CVM_APP_ID"
    
    # Test network connectivity
    print_status "Testing network connectivity..."
    npx phala cvms network "$CVM_APP_ID"
    
    print_success "Deployment testing complete"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  deploy      Deploy the VPN system to Phala Cloud"
    echo "  test        Test the deployed VPN system"
    echo "  monitor     Monitor deployment status"
    echo "  setup       Setup prerequisites and configuration"
    echo "  help        Show this help message"
    echo ""
    echo "Options:"
    echo "  --name NAME         CVM name (default: dstack-vpn-experiment)"
    echo "  --teepod-id ID      TEEPod ID (default: 8)"
    echo "  --image VERSION     Image version (default: dstack-0.3.6)"
    echo "  --vcpu CPU          Number of vCPUs (default: 2)"
    echo "  --memory MB         Memory in MB (default: 4096)"
    echo "  --disk-size GB      Disk size in GB (default: 40)"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 deploy"
    echo "  $0 deploy --name my-vpn --teepod-id 6"
    echo "  $0 test"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            CVM_NAME="$2"
            shift 2
            ;;
        --teepod-id)
            TEEPOD_ID="$2"
            shift 2
            ;;
        --image)
            IMAGE_VERSION="$2"
            shift 2
            ;;
        --vcpu)
            VCPU="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --disk-size)
            DISK_SIZE="$2"
            shift 2
            ;;
        deploy)
            COMMAND="deploy"
            shift
            ;;
        test)
            COMMAND="test"
            shift
            ;;
        monitor)
            COMMAND="monitor"
            shift
            ;;
        setup)
            COMMAND="setup"
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
    print_status "Starting Phala Cloud VPN deployment..."
    print_status "Project root: $PROJECT_ROOT"
    
    case ${COMMAND:-deploy} in
        setup)
            check_prerequisites
            generate_wireguard_keys
            validate_environment
            print_success "Setup completed successfully"
            ;;
        deploy)
            check_prerequisites
            generate_wireguard_keys
            validate_environment
            deploy_to_phala
            monitor_deployment
            print_success "Deployment completed successfully"
            ;;
        test)
            test_deployment
            ;;
        monitor)
            monitor_deployment
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