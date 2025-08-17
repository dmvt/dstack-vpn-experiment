#!/bin/bash
set -e

# DStack VPN Docker Deployment Script
# This script sets up and deploys the VPN system

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate WireGuard keys
generate_wireguard_keys() {
    local node_name=$1
    local key_dir="./config/${node_name}"
    
    mkdir -p "$key_dir"
    
    if [ ! -f "$key_dir/private.key" ]; then
        log "Generating WireGuard keys for $node_name..."
        wg genkey > "$key_dir/private.key"
        wg pubkey < "$key_dir/private.key" > "$key_dir/public.key"
        chmod 600 "$key_dir/private.key"
        chmod 644 "$key_dir/public.key"
        success "Generated WireGuard keys for $node_name"
    else
        log "WireGuard keys already exist for $node_name"
    fi
}

# Function to validate environment
validate_environment() {
    log "Validating environment..."
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "wg")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error "$cmd is not installed"
            exit 1
        fi
    done
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        error ".env file not found. Please copy env.example to .env and configure it."
        exit 1
    fi
    
    # Load environment variables
    source .env
    
    # Validate required environment variables
    local required_vars=(
        "HUB_PUBLIC_IP"
        "HUB_PUBLIC_KEY"
        "WIREGUARD_PRIVATE_KEY_A"
        "WIREGUARD_PRIVATE_KEY_B"
        "WIREGUARD_PRIVATE_KEY_C"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "$var is not set in .env file"
            exit 1
        fi
    done
    
    success "Environment validation passed"
}

# Function to setup configuration
setup_configuration() {
    log "Setting up configuration..."
    
    # Create config directories
    mkdir -p ./config/node-a
    mkdir -p ./config/node-b
    mkdir -p ./config/node-c
    
    # Generate WireGuard keys for each node
    generate_wireguard_keys "node-a"
    generate_wireguard_keys "node-b"
    generate_wireguard_keys "node-c"
    
    success "Configuration setup completed"
}

# Function to build and deploy
deploy() {
    log "Building and deploying VPN system..."
    
    # Build Docker images
    log "Building Docker images..."
    docker-compose build
    
    # Start services
    log "Starting services..."
    docker-compose up -d
    
    success "Deployment completed successfully"
}

# Function to check health
check_health() {
    log "Checking system health..."
    
    # Wait for services to be ready
    log "Waiting for services to be ready..."
    sleep 30
    
    # Check each node's health
    local nodes=("node-a" "node-b" "node-c")
    local ports=(8000 8001 8002)
    
    for i in "${!nodes[@]}"; do
        local node=${nodes[$i]}
        local port=${ports[$i]}
        
        log "Checking health of $node..."
        if curl -f "http://localhost:$port/status" > /dev/null 2>&1; then
            success "$node is healthy"
        else
            warning "$node health check failed"
        fi
    done
    
    success "Health check completed"
}

# Function to show status
show_status() {
    log "VPN System Status:"
    echo "=================="
    
    # Show running containers
    docker-compose ps
    
    echo ""
    
    # Show WireGuard interfaces
    log "WireGuard Interface Status:"
    for node in "node-a" "node-b" "node-c"; do
        echo "--- $node ---"
        docker exec "wireguard-$node" wg show 2>/dev/null || echo "Interface not available"
        echo ""
    done
}

# Function to cleanup
cleanup() {
    log "Cleaning up..."
    docker-compose down -v
    success "Cleanup completed"
}

# Main execution
main() {
    log "Starting DStack VPN deployment..."
    
    case "${1:-deploy}" in
        "deploy")
            validate_environment
            setup_configuration
            deploy
            check_health
            show_status
            ;;
        "status")
            show_status
            ;;
        "health")
            check_health
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [deploy|status|health|cleanup|help]"
            echo "  deploy  - Deploy the VPN system (default)"
            echo "  status  - Show system status"
            echo "  health  - Check system health"
            echo "  cleanup - Clean up all containers and volumes"
            echo "  help    - Show this help message"
            ;;
        *)
            error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 