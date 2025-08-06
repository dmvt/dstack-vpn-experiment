#!/bin/bash
set -e

# DStack VPN Docker Deployment Script
# This script sets up and deploys the VPN system with contract integration

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
        "CONTRACT_ADDRESS"
        "RPC_URL"
        "CONTRACT_PRIVATE_KEY_A"
        "CONTRACT_PRIVATE_KEY_B"
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
    mkdir -p ./docker/monitoring
    
    # Generate WireGuard keys
    generate_wireguard_keys "node-a"
    generate_wireguard_keys "node-b"
    
    # Load environment variables
    source .env
    
    # Create initial WireGuard configurations
    for node in "node-a" "node-b"; do
        local config_file="./config/${node}/wg0.conf"
        local private_key_file="./config/${node}/private.key"
        
        if [ ! -f "$config_file" ]; then
            log "Creating initial WireGuard configuration for $node..."
            cat > "$config_file" << EOF
[Interface]
PrivateKey = $(cat "$private_key_file")
Address = 10.0.0.$(if [ "$node" = "node-a" ]; then echo "1"; else echo "2"; fi)/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Peers will be added dynamically by the bridge
EOF
            success "Created WireGuard configuration for $node"
        fi
    done
    
    success "Configuration setup complete"
}

# Function to build and deploy
deploy() {
    log "Building and deploying VPN system..."
    
    # Stop existing containers
    log "Stopping existing containers..."
    docker-compose down --remove-orphans
    
    # Build images
    log "Building Docker images..."
    docker-compose build --no-cache
    
    # Start services
    log "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    log "Waiting for services to be ready..."
    sleep 30
    
    # Check service health
    log "Checking service health..."
    docker-compose ps
    
    success "Deployment complete"
}

# Function to show status
show_status() {
    log "Checking service status..."
    
    echo ""
    echo "=== Service Status ==="
    docker-compose ps
    
    echo ""
    echo "=== Health Checks ==="
    
    # Check Node A health
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        success "Node A health check: OK"
    else
        error "Node A health check: FAILED"
    fi
    
    # Check Node B health
    if curl -s http://localhost:8081/health > /dev/null 2>&1; then
        success "Node B health check: OK"
    else
        error "Node B health check: FAILED"
    fi
    
    echo ""
    echo "=== Access URLs ==="
    echo "Monitoring Dashboard: http://localhost:8082"
    echo "Node A Health: http://localhost:8080/health"
    echo "Node B Health: http://localhost:8081/health"
    echo "Node A Stats: http://localhost:8080/stats"
    echo "Node B Stats: http://localhost:8081/stats"
}

# Function to show logs
show_logs() {
    log "Showing recent logs..."
    docker-compose logs --tail=50
}

# Function to cleanup
cleanup() {
    log "Cleaning up..."
    docker-compose down --volumes --remove-orphans
    success "Cleanup complete"
}

# Main script
main() {
    case "${1:-deploy}" in
        "deploy")
            validate_environment
            setup_configuration
            deploy
            show_status
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "cleanup")
            cleanup
            ;;
        "setup")
            validate_environment
            setup_configuration
            ;;
        "build")
            docker-compose build --no-cache
            ;;
        "start")
            docker-compose up -d
            ;;
        "stop")
            docker-compose down
            ;;
        "restart")
            docker-compose restart
            ;;
        *)
            echo "Usage: $0 {deploy|status|logs|cleanup|setup|build|start|stop|restart}"
            echo ""
            echo "Commands:"
            echo "  deploy   - Full deployment (default)"
            echo "  status   - Show service status"
            echo "  logs     - Show recent logs"
            echo "  cleanup  - Stop and remove all containers/volumes"
            echo "  setup    - Setup configuration only"
            echo "  build    - Build Docker images"
            echo "  start    - Start services"
            echo "  stop     - Stop services"
            echo "  restart  - Restart services"
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 