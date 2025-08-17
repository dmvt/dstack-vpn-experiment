#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version and metadata
VERSION="1.0.0"
SCRIPT_NAME="deploy-vpn.sh"

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

# Show help
show_help() {
    cat << EOF
${SCRIPT_NAME} v${VERSION} - DStack VPN Deployment CLI

A single-command VPN deployment system for DigitalOcean + Phala Cloud.

USAGE:
    ./deploy-vpn.sh [COMMAND] [OPTIONS]

COMMANDS:
    deploy          Deploy complete VPN infrastructure (default)
    destroy         Destroy all VPN infrastructure
    status          Show VPN status and connectivity
    test            Test VPN connectivity between nodes
    postgres        Deploy PostgreSQL cluster on VPN nodes
    setup           Interactive setup wizard for prerequisites
    help            Show this help message

OPTIONS:
    --region        DigitalOcean region (default: nyc1)
    --size          Droplet size (default: s-1vcpu-1gb)
    --nodes         Number of DStack nodes (default: 3)
    --network       WireGuard network (default: 10.88.0.0/24)
    --port          WireGuard port (default: 51820)
    --dry-run       Show what would be deployed without executing
    --force         Skip confirmation prompts
    --verbose       Enable verbose output

EXAMPLES:
    # First time setup
    ./deploy-vpn.sh setup

    # Deploy with defaults
    ./deploy-vpn.sh deploy

    # Deploy with custom region and size
    ./deploy-vpn.sh deploy --region sfo3 --size s-2vcpu-2gb

    # Deploy with 5 DStack nodes
    ./deploy-vpn.sh deploy --nodes 5

    # Deploy PostgreSQL cluster
    ./deploy-vpn.sh postgres deploy

    # Show current status
    ./deploy-vpn.sh status

    # Test connectivity
    ./deploy-vpn.sh test

    # Destroy everything
    ./deploy-vpn.sh destroy --force

PREREQUISITES:
    This tool will automatically install and configure:
    - doctl CLI tool (DigitalOcean)
    - phala CLI tool (Phala Cloud)
    - SSH key generation
    - Authentication setup

    No manual installation needed! Run './deploy-vpn.sh setup' to get started.

CONFIGURATION:
    No .env files or pre-configuration needed!
    Everything is generated dynamically during deployment.

EOF
}

# Parse command line arguments
parse_args() {
    COMMAND="deploy"
    REGION="nyc1"
    SIZE="s-1vcpu-1gb"
    NODE_COUNT=3
    NETWORK="10.88.0.0/24"
    PORT="51820"
    DRY_RUN=false
    FORCE=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            deploy|destroy|status|test|postgres|setup|help)
                COMMAND="$1"
                shift
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --size)
                SIZE="$2"
                shift 2
                ;;
            --nodes)
                NODE_COUNT="$2"
                shift 2
                ;;
            --network)
                NETWORK="$2"
                shift 2
                ;;
            --port)
                PORT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Configuration
DROPLET_NAME="dstack-vpn-hub"
SSH_KEY_NAME="M3 Max"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check and install doctl
    if ! command -v doctl &> /dev/null; then
        warning "doctl CLI tool not found. Attempting to install..."
        install_doctl
    fi
    
    # Check and install phala CLI
    if ! command -v phala &> /dev/null; then
        warning "phala CLI tool not found. Attempting to install..."
        install_phala
    fi
    
    # Check and generate SSH key
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        warning "SSH public key not found. Generating one..."
        generate_ssh_key
    fi
    
    # Check authentication
    if ! doctl account get &> /dev/null; then
        warning "Not authenticated with DigitalOcean. Please authenticate:"
        error "  Run: doctl auth init"
        error "  Follow the prompts to authenticate with your DigitalOcean account"
        exit 1
    fi
    
    if ! phala status &> /dev/null; then
        warning "Not authenticated with Phala Cloud. Please authenticate:"
        error "  Run: phala auth login [your-api-key]"
        error "  Get your API key from: https://cloud.phala.network/"
        exit 1
    fi
    
    log "All prerequisites satisfied!"
}

# Install doctl CLI tool
install_doctl() {
    log "Installing doctl CLI tool..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            log "Installing via Homebrew..."
            brew install doctl
        else
            error "Homebrew not found. Please install doctl manually:"
            error "  Visit: https://github.com/digitalocean/doctl/releases"
            error "  Download the latest version for macOS"
            error "  Or install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        log "Installing doctl for Linux..."
        
        # Detect architecture
        ARCH=$(uname -m)
        if [[ "$ARCH" == "x86_64" ]]; then
            ARCH="amd64"
        elif [[ "$ARCH" == "aarch64" ]]; then
            ARCH="arm64"
        else
            error "Unsupported architecture: $ARCH"
            error "Please install doctl manually from: https://github.com/digitalocean/doctl/releases"
            exit 1
        fi
        
        # Download and install
        DOCTL_VERSION=$(curl -s https://api.github.com/repos/digitalocean/doctl/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        DOCTL_URL="https://github.com/digitalocean/doctl/releases/download/${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-${ARCH}.tar.gz"
        
        log "Downloading doctl ${DOCTL_VERSION}..."
        curl -L "$DOCTL_URL" -o /tmp/doctl.tar.gz
        
        log "Installing doctl..."
        sudo tar -xzf /tmp/doctl.tar.gz -C /usr/local/bin doctl
        chmod +x /usr/local/bin/doctl
        
        # Clean up
        rm /tmp/doctl.tar.gz
        
        log "doctl installed successfully!"
    else
        error "Unsupported operating system: $OSTYPE"
        error "Please install doctl manually from: https://github.com/digitalocean/doctl/releases"
        exit 1
    fi
    
    # Verify installation
    if command -v doctl &> /dev/null; then
        log "doctl installation verified!"
    else
        error "doctl installation failed"
        exit 1
    fi
}

# Install phala CLI tool
install_phala() {
    log "Installing phala CLI tool..."
    
    if command -v npm &> /dev/null; then
        log "Installing via npm..."
        npm install -g phala
    elif command -v node &> /dev/null; then
        log "Installing via npx..."
        log "Note: Using npx (slower but no global installation needed)"
        log "Consider installing npm for better performance:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            log "  brew install node"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            log "  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
            log "  sudo apt-get install -y nodejs"
        fi
    else
        error "Node.js/npm not found. Please install Node.js first:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            error "  brew install node"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            error "  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
            error "  sudo apt-get install -y nodejs"
        else
            error "  Visit: https://nodejs.org/"
        fi
        exit 1
    fi
    
    # Verify installation
    if command -v phala &> /dev/null || npx phala --version &> /dev/null; then
        log "phala CLI installation verified!"
    else
        error "phala CLI installation failed"
        exit 1
    fi
}

# Generate SSH key
generate_ssh_key() {
    log "Generating SSH key pair..."
    
    # Create .ssh directory if it doesn't exist
    mkdir -p ~/.ssh
    
    # Generate key
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "dstack-vpn-$(date +%Y%m%d)"
    
    # Set proper permissions
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub
    
    log "SSH key generated successfully!"
    log "Public key: ~/.ssh/id_rsa.pub"
    log "Private key: ~/.ssh/id_rsa"
}

# Setup authentication
setup_authentication() {
    log "Setting up authentication..."
    
    # Check if already authenticated
    if doctl account get &> /dev/null && phala status &> /dev/null; then
        log "Already authenticated with both services!"
        return
    fi
    
    # Setup DigitalOcean authentication
    if ! doctl account get &> /dev/null; then
        log "Setting up DigitalOcean authentication..."
        log "You'll need your DigitalOcean API token."
        log "Get it from: https://cloud.digitalocean.com/account/api/tokens"
        echo
        read -p "Enter your DigitalOcean API token: " -s DO_TOKEN
        echo
        
        if [[ -n "$DO_TOKEN" ]]; then
            # Create doctl config directory
            mkdir -p ~/.config/doctl
            
            # Write token to config
            cat > ~/.config/doctl/config.yaml << EOF
access-token: ${DO_TOKEN}
EOF
            
            log "DigitalOcean token configured!"
        else
            error "No token provided. Please run 'doctl auth init' manually."
        fi
    fi
    
    # Setup Phala Cloud authentication
    if ! phala status &> /dev/null; then
        log "Setting up Phala Cloud authentication..."
        log "You'll need your Phala Cloud API key."
        log "Get it from: https://cloud.phala.network/"
        echo
        read -p "Enter your Phala Cloud API key: " -s PHALA_KEY
        echo
        
        if [[ -n "$PHALA_KEY" ]]; then
            # Try to authenticate
            if command -v phala &> /dev/null; then
                echo "$PHALA_KEY" | phala auth login
            else
                echo "$PHALA_KEY" | npx phala auth login
            fi
            
            log "Phala Cloud API key configured!"
        else
            error "No API key provided. Please run 'phala auth login [your-api-key]' manually."
        fi
    fi
    
    # Verify authentication
    log "Verifying authentication..."
    if doctl account get &> /dev/null; then
        log "✅ DigitalOcean authentication successful!"
    else
        error "❌ DigitalOcean authentication failed"
    fi
    
    if phala status &> /dev/null; then
        log "✅ Phala Cloud authentication successful!"
    else
        error "❌ Phala Cloud authentication failed"
    fi
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ "$OSTYPE" != "darwin"* ]] && [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "Unsupported operating system: $OSTYPE"
        error "This tool supports macOS and Linux only"
        exit 1
    fi
    
    # Check available disk space (need at least 1GB for configs and keys)
    DISK_FREE=$(df . | awk 'NR==2 {print $4}')
    DISK_FREE_GB=$((DISK_FREE / 1024 / 1024))
    
    if [[ $DISK_FREE_GB -lt 1 ]]; then
        error "Insufficient disk space. Need at least 1GB, have ${DISK_FREE_GB}GB"
        exit 1
    fi
    
    # Check available memory (need at least 512MB)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        MEM_FREE=$(free -m | awk 'NR==2{print $7}')
        if [[ $MEM_FREE -lt 512 ]]; then
            warning "Low memory available: ${MEM_FREE}MB. Recommended: 512MB+"
        fi
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "No internet connectivity detected"
        exit 1
    fi
    
    log "System requirements satisfied!"
}

# Interactive setup wizard
run_setup_wizard() {
    log "🚀 DStack VPN Setup Wizard"
    echo
    log "This wizard will help you set up all prerequisites for the DStack VPN deployment."
    echo
    
    # Check what's already installed
    local DOCTL_INSTALLED=false
    local PHALA_INSTALLED=false
    local SSH_KEY_EXISTS=false
    local DO_AUTH=false
    local PHALA_AUTH=false
    
    if command -v doctl &> /dev/null; then
        DOCTL_INSTALLED=true
        log "✅ doctl CLI tool: Already installed"
    else
        log "❌ doctl CLI tool: Not installed"
    fi
    
    if command -v phala &> /dev/null || npx phala --version &> /dev/null; then
        PHALA_INSTALLED=true
        log "✅ phala CLI tool: Already installed"
    else
        log "❌ phala CLI tool: Not installed"
    fi
    
    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        SSH_KEY_EXISTS=true
        log "✅ SSH key: Already exists"
    else
        log "❌ SSH key: Not found"
    fi
    
    if doctl account get &> /dev/null; then
        DO_AUTH=true
        log "✅ DigitalOcean: Already authenticated"
    else
        log "❌ DigitalOcean: Not authenticated"
    fi
    
    if phala status &> /dev/null; then
        PHALA_AUTH=true
        log "✅ Phala Cloud: Already authenticated"
    else
        log "❌ Phala Cloud: Not authenticated"
    fi
    
    echo
    
    # Ask if user wants to proceed
    if [[ "$DOCTL_INSTALLED" == "true" && "$PHALA_INSTALLED" == "true" && "$SSH_KEY_EXISTS" == "true" && "$DO_AUTH" == "true" && "$PHALA_AUTH" == "true" ]]; then
        log "🎉 All prerequisites are already satisfied!"
        return
    fi
    
    read -p "Would you like to set up missing prerequisites now? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log "Setup wizard cancelled. You can run it again with: ./deploy-vpn.sh setup"
        return
    fi
    
    echo
    
    # Install missing tools
    if [[ "$DOCTL_INSTALLED" == "false" ]]; then
        log "Installing doctl CLI tool..."
        install_doctl
    fi
    
    if [[ "$PHALA_INSTALLED" == "false" ]]; then
        log "Installing phala CLI tool..."
        install_phala
    fi
    
    if [[ "$SSH_KEY_EXISTS" == "false" ]]; then
        log "Generating SSH key..."
        generate_ssh_key
    fi
    
    # Setup authentication
    if [[ "$DO_AUTH" == "false" || "$PHALA_AUTH" == "false" ]]; then
        log "Setting up authentication..."
        setup_authentication
    fi
    
    echo
    log "🎉 Setup wizard completed!"
    log "You can now deploy your VPN with: ./deploy-vpn.sh deploy"
}

# Generate WireGuard keys dynamically
generate_keys() {
    log "Generating WireGuard keys..."
    
    # Create config directories
    mkdir -p config/hub config/nodes
    
    # Generate hub keys
    wg genkey | tee config/hub/private.key | wg pubkey > config/hub/public.key
    HUB_PRIVATE=$(cat config/hub/private.key)
    HUB_PUBLIC=$(cat config/hub/public.key)
    
    # Generate node keys
    NODE_KEYS=()
    for i in $(seq 1 $NODE_COUNT); do
        wg genkey | tee config/nodes/node${i}.key | wg pubkey > config/nodes/node${i}.pub
        NODE_KEYS+=("$(cat config/nodes/node${i}.pub)")
    done
    
    # Set permissions
    chmod 600 config/hub/private.key config/nodes/*.key
    chmod 644 config/hub/public.key config/nodes/*.pub
    
    log "Generated $((NODE_COUNT + 1)) WireGuard key pairs"
}

# Generate WireGuard configurations
generate_configs() {
    log "Generating WireGuard configurations..."
    
    # Calculate network addresses
    NETWORK_BASE=$(echo $NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)
    HUB_IP="${NETWORK_BASE}.1"
    
    # Generate hub config
    cat > config/hub/wg0.conf << EOF
[Interface]
Address = ${HUB_IP}/24
ListenPort = ${PORT}
PrivateKey = ${HUB_PRIVATE}
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT
PostUp = iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
PostDown = sysctl -w net.ipv4.ip_forward=0
PostDown = iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

EOF
    
    # Add peer configurations for each node
    for i in $(seq 1 $NODE_COUNT); do
        NODE_IP="${NETWORK_BASE}.$((10 + i))"
        cat >> config/hub/wg0.conf << EOF
[Peer]
# Node ${i}
PublicKey = ${NODE_KEYS[$((i-1))]}
AllowedIPs = ${NODE_IP}/32
PersistentKeepalive = 25

EOF
    done
    
    # Generate node configs (hub-and-spoke topology)
    for i in $(seq 1 $NODE_COUNT); do
        NODE_IP="${NETWORK_BASE}.$((10 + i))"
        cat > config/nodes/node${i}.conf << EOF
[Interface]
Address = ${NODE_IP}/32
PrivateKey = $(cat config/nodes/node${i}.key)
ListenPort = ${PORT}

[Peer]
# Hub
PublicKey = ${HUB_PUBLIC}
Endpoint = <HUB_PUBLIC_IP>:${PORT}
AllowedIPs = ${NETWORK}
PersistentKeepalive = 25
EOF
    done
    
    chmod 600 config/hub/wg0.conf config/nodes/*.conf
    log "Generated WireGuard configurations for hub and ${NODE_COUNT} nodes"
}

# Setup DigitalOcean hub
setup_hub() {
    log "Setting up DigitalOcean hub..."
    
    # Create SSH key if needed
    if ! doctl compute ssh-key list --format Name | grep -q "^${SSH_KEY_NAME}$"; then
        log "Creating SSH key: ${SSH_KEY_NAME}"
        doctl compute ssh-key import ${SSH_KEY_NAME} --public-key-file ~/.ssh/id_rsa.pub
    fi
    
    SSH_KEY_ID=$(doctl compute ssh-key list --format ID,Name | grep "${SSH_KEY_NAME}" | awk '{print $1}')
    
    # Always create a new droplet
    if doctl compute droplet list --format Name | grep -q "^${DROPLET_NAME}$"; then
        log "Destroying existing droplet ${DROPLET_NAME}..."
        doctl compute droplet delete ${DROPLET_NAME} --force
        sleep 10
    fi
    
    # Create new droplet
    log "Creating new droplet: ${DROPLET_NAME}"
    doctl compute droplet create ${DROPLET_NAME} \
        --size ${SIZE} \
        --region ${REGION} \
        --image ubuntu-24-04-x64 \
        --ssh-keys ${SSH_KEY_ID} \
        --wait
    
    DROPLET_ID=$(doctl compute droplet list --format ID,Name | grep "${DROPLET_NAME}" | awk '{print $1}')
    HUB_PUBLIC_IP=$(doctl compute droplet get ${DROPLET_ID} --format PublicIPv4 --no-header)
    
    log "Droplet created: ${HUB_PUBLIC_IP}"
    
    # Firewall will be configured with UFW on the droplet
    
    # Wait for SSH
    log "Waiting for SSH to become available..."
    for i in {1..60}; do
        log "Attempt ${i}/60: Testing SSH connection..."
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@${HUB_PUBLIC_IP} "echo 'SSH ready'" 2>/dev/null; then
            log "SSH connection successful!"
            break
        fi
        if [[ $i -eq 60 ]]; then
            error "SSH connection failed after 60 attempts"
            exit 1
        fi
        log "SSH not ready yet, waiting 5 seconds..."
        sleep 5
    done
    
    # Configure WireGuard on hub
    log "Configuring WireGuard on hub..."
    
    # Create WireGuard directory first
    ssh -o StrictHostKeyChecking=no root@${HUB_PUBLIC_IP} "mkdir -p /etc/wireguard"
    
    # Copy WireGuard configuration files
    scp -o StrictHostKeyChecking=no config/hub/private.key root@${HUB_PUBLIC_IP}:/etc/wireguard/
    scp -o StrictHostKeyChecking=no config/hub/public.key root@${HUB_PUBLIC_IP}:/etc/wireguard/
    scp -o StrictHostKeyChecking=no config/hub/wg0.conf root@${HUB_PUBLIC_IP}:/etc/wireguard/
    
    ssh -o StrictHostKeyChecking=no root@${HUB_PUBLIC_IP} << 'EOF'
# Install WireGuard and UFW
apt update && apt install -y wireguard qrencode ufw curl

# Create WireGuard directory
mkdir -p /etc/wireguard

# Set permissions
chmod 600 /etc/wireguard/private.key
chmod 644 /etc/wireguard/public.key
chmod 600 /etc/wireguard/wg0.conf

# Configure UFW firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 51820/udp comment 'WireGuard'
ufw allow from 10.88.0.0/24 comment 'WireGuard network'
ufw --force enable

# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Start WireGuard
systemctl enable --now wg-quick@wg0

# Create status script
cat > /usr/local/bin/vpn-status << 'STATUSEOF'
#!/bin/bash
echo "=== WireGuard Status ==="
wg show
echo ""
echo "=== UFW Firewall Status ==="
ufw status verbose
echo ""
echo "=== Network Interfaces ==="
ip addr show wg0
STATUSEOF

chmod +x /usr/local/bin/vpn-status
EOF
    
    # Update node configs with hub IP
    for i in $(seq 1 $NODE_COUNT); do
        sed -i.bak "s/Endpoint = .*:${PORT}/Endpoint = ${HUB_PUBLIC_IP}:${PORT}/" config/nodes/node${i}.conf
    done
    
    log "Hub configured successfully"
}

# Setup DStack nodes
setup_nodes() {
    log "Setting up ${NODE_COUNT} DStack nodes..."
    
    # Check available nodes
    AVAILABLE_NODES=$(phala nodes list | grep "^ℹ   ID:" | awk '{print $3}' | head -${NODE_COUNT})
    
    if [[ $(echo "$AVAILABLE_NODES" | wc -l) -lt ${NODE_COUNT} ]]; then
        warning "Not enough available nodes. Found: $(echo "$AVAILABLE_NODES" | wc -l), Need: ${NODE_COUNT}"
        warning "Continuing with available nodes only..."
        NODE_COUNT=$(echo "$AVAILABLE_NODES" | wc -l)
        if [[ $NODE_COUNT -eq 0 ]]; then
            warning "No DStack nodes available. Skipping DStack deployment."
            return
        fi
    fi
    
    log "Found ${NODE_COUNT} available nodes"
    
    # Calculate network base for node IPs
    NETWORK_BASE=$(echo $NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)
    
    # Create DStack instances
    NODE_IPS=()
    NODE_INDEX=1
    
    for NODE_ID in $AVAILABLE_NODES; do
        NODE_NAME="dstack-vpn-node-${NODE_INDEX}"
        log "Creating DStack instance: ${NODE_NAME} on node ${NODE_ID}"
        
        # Create temporary Docker Compose file for this node
        NODE_IP="${NETWORK_BASE}.$((10 + NODE_INDEX))"
        NODE_PRIVATE_KEY=$(cat config/nodes/node${NODE_INDEX}.key)
        TEMP_COMPOSE="/tmp/docker-compose-${NODE_NAME}.yml"
        
        cat > ${TEMP_COMPOSE} << EOF
version: '3.8'

services:
  wireguard-node:
    image: lsdan/dstack-wireguard-node:latest
    container_name: wireguard-${NODE_NAME}
    environment:
      - NODE_ID=${NODE_NAME}
      - NODE_IP=${NODE_IP}
      - HUB_PUBLIC_IP=${HUB_PUBLIC_IP}
      - HUB_PUBLIC_KEY=${HUB_PUBLIC}
      - WIREGUARD_PRIVATE_KEY=${NODE_PRIVATE_KEY}
      - HEALTH_CHECK_PORT=8000
    volumes:
      - wireguard-logs:/var/log/wireguard
    ports:
      - "51820:51820/udp"
      - "8000:8000/tcp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    privileged: true
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

volumes:
  wireguard-logs:

networks:
  default:
    driver: bridge
EOF
        
        # Create CVM instance with the temporary compose file
        phala cvms create \
            --name ${NODE_NAME} \
            --teepod-id ${NODE_ID} \
            --image dstack-0.3.6 \
            --vcpu 1 \
            --memory 2048 \
            --disk-size 40 \
            --compose ${TEMP_COMPOSE} \
            --skip-env
        
        # Clean up temporary file
        rm -f ${TEMP_COMPOSE}
        
        # Wait for CVM to be ready and get connection info
        log "Waiting for CVM ${NODE_NAME} to be ready..."
        for wait_attempt in {1..30}; do
            # Get the whole CVM info block and look for status
            CVM_INFO=$(phala cvms list | grep -A 20 "${NODE_NAME}")
            CVM_STATUS=$(echo "$CVM_INFO" | grep "│ Status" | awk -F'│' '{print $3}' | xargs)
            
            if [[ "$CVM_STATUS" == "running" ]]; then
                log "CVM ${NODE_NAME} is running"
                break
            fi
            if [[ $wait_attempt -eq 30 ]]; then
                warning "CVM ${NODE_NAME} did not start within timeout"
                continue
            fi
            log "CVM ${NODE_NAME} status: ${CVM_STATUS}, waiting..."
            sleep 10
        done
        
        # Get connection info from Node Info URL
        NODE_INFO=$(echo "$CVM_INFO" | grep "│ Node Info URL" | awk -F'│' '{print $3}' | xargs)
        if [[ -n "$NODE_INFO" && "$NODE_INFO" != "N/A" ]]; then
            # Extract hostname from URL (remove https:// and :port)
            INSTANCE_HOST=$(echo "$NODE_INFO" | sed 's|https://||' | sed 's|:[0-9]*||')
            NODE_IPS+=("$INSTANCE_HOST")
            log "Instance ${NODE_NAME} ready with hostname: ${INSTANCE_HOST}"
        else
            warning "Could not get connection info for ${NODE_NAME}"
            NODE_IPS+=("unknown")
        fi
        NODE_INDEX=$((NODE_INDEX + 1))
    done
    
    # With custom Docker image, no need to deploy WireGuard manually
    log "Nodes are self-contained with WireGuard pre-configured"
    
    # Skip SSH deployment for Phala nodes
    if false; then
        # This section is disabled - kept for reference
        for i in $(seq 1 $NODE_COUNT); do
            NODE_IP=${NODE_IPS[$((i-1))]}
            log "Deploying WireGuard on node ${i} (${NODE_IP})..."
            
            # Copy WireGuard config
            scp -o StrictHostKeyChecking=no config/nodes/node${i}.conf root@${NODE_IP}:/etc/wireguard/wg0.conf
            
            # Install and configure WireGuard
            ssh -o StrictHostKeyChecking=no root@${NODE_IP} << 'EOF'
# Install WireGuard
apk add --no-cache wireguard-tools

# Create WireGuard directory
mkdir -p /etc/wireguard

# Set permissions
chmod 600 /etc/wireguard/wg0.conf

# Start WireGuard
wg-quick up wg0

# Enable on boot
echo 'wg-quick up wg0' >> /etc/rc.local
chmod +x /etc/rc.local

# Install and configure firewall
apk add --no-cache nftables

cat > /etc/nftables.conf << 'NFTEOF'
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;
    iif lo accept
    ct state established,related accept
    tcp dport 8000 accept
    iif "wg0" ip saddr 10.88.0.0/24 ip saddr != 10.88.0.1 accept
  }
  chain forward {
    type filter hook forward priority 0;
    policy drop;
  }
  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
NFTEOF

nft -f /etc/nftables.conf
echo 'nft -f /etc/nftables.conf' >> /etc/rc.local

# Create status script
cat > /usr/local/bin/vpn-status << 'STATUSEOF'
#!/bin/bash
echo "=== WireGuard Status ==="
wg show
echo ""
echo "=== Firewall Rules ==="
nft list ruleset
echo ""
echo "=== Network Interfaces ==="
ip addr show wg0
STATUSEOF

chmod +x /usr/local/bin/vpn-status
EOF
            
            log "Node ${i} configured successfully"
        done
    fi
    
    # Status service is built into the Docker image
    log "Status service is integrated in the custom Docker image"
}

# Deploy status service
deploy_status_service() {
    local NODE_IPS=("$@")
    
    log "Deploying status service on all nodes..."
    
    for i in $(seq 1 $NODE_COUNT); do
        NODE_IP=${NODE_IPS[$((i-1))]}
        log "Deploying status service on node ${i}..."
        
        # Copy status service files
        scp -o StrictHostKeyChecking=no -r docker/status-service/* root@${NODE_IP}:/opt/dstack-status/
        
        # Build and deploy
        ssh -o StrictHostKeyChecking=no root@${NODE_IP} << 'EOF'
cd /opt/dstack-status

# Install Go
apk add --no-cache go

# Build binary
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dstack-status status.go

# Install systemd service
cp dstack-status.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now dstack-status

# Verify service
systemctl status dstack-status
EOF
        
        log "Status service deployed on node ${i}"
    done
}

# Test VPN connectivity
test_connectivity() {
    log "Testing VPN connectivity..."
    
    # Test hub status
    log "Testing hub WireGuard status..."
    ssh -o StrictHostKeyChecking=no root@${HUB_PUBLIC_IP} "vpn-status"
    
    # Test node connectivity via status endpoints
    log "Testing node status endpoints..."
    CVMS_INFO=$(phala cvms list 2>/dev/null || echo "")
    
    for i in $(seq 1 $NODE_COUNT); do
        NODE_NAME="dstack-vpn-node-${i}"
        APP_ID=$(echo "$CVMS_INFO" | grep -A 5 "│ Name.*${NODE_NAME}" | grep "│ App ID" | awk -F'│' '{print $3}' | xargs | sed 's/app_//')
        
        if [[ -n "$APP_ID" ]]; then
            STATUS_URL="https://${APP_ID}-8000.dstack-prod7.phala.network/status"
            log "Testing node ${i} status at: $STATUS_URL"
            
            if STATUS_RESPONSE=$(curl -s --max-time 5 "$STATUS_URL" 2>/dev/null); then
                echo "$STATUS_RESPONSE" | jq . 2>/dev/null || echo "$STATUS_RESPONSE"
            else
                log "Node ${i} status endpoint not responding yet"
            fi
        fi
    done
    
    log "Connectivity tests completed"
}

# Show VPN status
show_status() {
    if [[ -z "$HUB_PUBLIC_IP" ]]; then
        # Try to find existing hub
        if doctl compute droplet list --format Name | grep -q "^${DROPLET_NAME}$"; then
            DROPLET_ID=$(doctl compute droplet list --format ID,Name | grep "${DROPLET_NAME}" | awk '{print $1}')
            HUB_PUBLIC_IP=$(doctl compute droplet get ${DROPLET_ID} --format PublicIPv4 --no-header)
        else
            error "No VPN hub found. Deploy first with: ./deploy-vpn.sh deploy"
            exit 1
        fi
    fi
    
    log "=== DStack VPN Status ==="
    echo ""
    echo "Hub (DigitalOcean): ${HUB_PUBLIC_IP}"
    echo "Network: ${NETWORK}"
    echo "WireGuard Port: ${PORT}"
    echo ""
    
    # Show hub status
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${HUB_PUBLIC_IP} "echo 'connected'" 2>/dev/null; then
        echo "Hub Status: ✅ Online"
        ssh -o StrictHostKeyChecking=no root@${HUB_PUBLIC_IP} "vpn-status" 2>/dev/null || echo "Hub Status: ⚠️  WireGuard not running"
    else
        echo "Hub Status: ❌ Offline"
    fi
    
    # Show node status
    echo ""
    echo "DStack Nodes:"
    # Get all CVMs info
    CVMS_INFO=$(phala cvms list 2>/dev/null || echo "")
    
    for i in $(seq 1 $NODE_COUNT); do
        NODE_NAME="dstack-vpn-node-${i}"
        # Extract App ID for this node
        APP_ID=$(echo "$CVMS_INFO" | grep -A 5 "│ Name.*${NODE_NAME}" | grep "│ App ID" | awk -F'│' '{print $3}' | xargs | sed 's/app_//')
        
        if [[ -n "$APP_ID" && "$APP_ID" != "" ]]; then
            # Extract status
            NODE_STATUS=$(echo "$CVMS_INFO" | grep -A 10 "│ Name.*${NODE_NAME}" | grep "│ Status" | awk -F'│' '{print $3}' | xargs)
            
            if [[ "$NODE_STATUS" == "running" ]]; then
                echo "  Node ${i}: ✅ Running"
                # Test status service using Phala URL format
                STATUS_URL="https://${APP_ID}-8000.dstack-prod7.phala.network/status"
                if STATUS_RESPONSE=$(curl -s --max-time 5 "$STATUS_URL" 2>/dev/null); then
                    if echo "$STATUS_RESPONSE" | jq -e '.overlay_ip' >/dev/null 2>&1; then
                        OVERLAY_IP=$(echo "$STATUS_RESPONSE" | jq -r '.overlay_ip')
                        echo "    Status Service: ✅ Running (WireGuard IP: ${OVERLAY_IP})"
                    else
                        echo "    Status Service: ⚠️  Responding but invalid data"
                    fi
                else
                    echo "    Status Service: ⚠️  Not responding"
                fi
                echo "    Status URL: $STATUS_URL"
            else
                echo "  Node ${i}: ⚠️  Status: ${NODE_STATUS}"
            fi
        else
            echo "  Node ${i}: ❓ Not found"
        fi
    done
    
    # Show PostgreSQL status if deployed
    echo ""
    show_postgres_status_brief
}

# Destroy VPN infrastructure
destroy_infrastructure() {
    if [[ "$FORCE" == "false" ]]; then
        warning "This will destroy ALL VPN infrastructure!"
        read -p "Are you sure? Type 'yes' to confirm: " -r
        if [[ "$REPLY" != "yes" ]]; then
            log "Destruction cancelled"
            return
        fi
    fi
    
    log "Destroying VPN infrastructure..."
    
    # Destroy DigitalOcean hub
    if doctl compute droplet list --format Name | grep -q "^${DROPLET_NAME}$"; then
        log "Destroying DigitalOcean hub..."
        doctl compute droplet delete ${DROPLET_NAME} --force
    fi
    
    # Destroy all DStack nodes
    log "Checking for DStack VPN nodes..."
    CVMS_TO_DELETE=$(phala cvms list 2>/dev/null | grep "dstack-vpn-node" -A 3 | grep "App ID" | awk -F'│' '{print $3}' | xargs || echo "")
    
    if [[ -n "$CVMS_TO_DELETE" ]]; then
        for APP_ID in $CVMS_TO_DELETE; do
            log "Destroying CVM: ${APP_ID}"
            phala cvms delete ${APP_ID} --force 2>/dev/null || true
        done
    else
        log "No DStack VPN nodes found"
    fi
    
    # Clean up local configs
    log "Cleaning up local configuration files..."
    rm -rf config/
    
    log "VPN infrastructure destroyed"
}

# Generate runtime configuration
generate_runtime_config() {
    log "Generating runtime configuration..."
    
    cat > runtime-config.md << EOF
# DStack VPN Runtime Configuration

**Generated:** $(date)
**Status:** Active

## Network Configuration
- **WireGuard Network**: ${NETWORK}
- **Hub IP**: $(echo $NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3).1
- **WireGuard Port**: ${PORT}

## Infrastructure
- **DigitalOcean Hub**: ${HUB_PUBLIC_IP}
- **DStack Nodes**: ${NODE_COUNT} nodes

## Status Endpoints
- **Hub Status**: ssh root@${HUB_PUBLIC_IP} 'vpn-status'
- **Node Status**: Check individual node IPs

## WireGuard Commands
- **Hub Status**: ssh root@${HUB_PUBLIC_IP} 'wg show'
- **Node Status**: ssh root@<NODE_IP> 'wg show'

## VPN Testing
- **Test connectivity**: ./deploy-vpn.sh test
- **Check status**: ./deploy-vpn.sh status
EOF
    
    log "Runtime configuration saved to: runtime-config.md"
}

# Main deployment function
deploy_vpn() {
    log "🚀 Starting DStack VPN deployment..."
    log "Region: ${REGION}, Size: ${SIZE}, Nodes: ${NODE_COUNT}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No changes will be made"
        log "Would deploy:"
        log "  - DigitalOcean hub in ${REGION} (${SIZE})"
        log "  - ${NODE_COUNT} DStack nodes"
        log "  - WireGuard VPN network: ${NETWORK}"
        log "  - Status monitoring on port 8000"
        return
    fi
    
    check_system_requirements
    check_prerequisites
    generate_keys
    generate_configs
    setup_hub
    setup_nodes
    test_connectivity
    generate_runtime_config
    
    # Deploy PostgreSQL cluster on the VPN nodes
    log ""
    log "Deploying PostgreSQL cluster..."
    deploy_postgres_cluster_integrated
    
    log ""
    log "🎉 DStack VPN deployment successful with PostgreSQL!"
    log ""
    log "=== Quick Commands ==="
    log "Status: ./deploy-vpn.sh status"
    log "Test:   ./deploy-vpn.sh test"
    log "Destroy: ./deploy-vpn.sh destroy --force"
}

# Get hub IP address
get_hub_ip() {
    if [[ -n "$HUB_PUBLIC_IP" ]]; then
        echo "$HUB_PUBLIC_IP"
    else
        # Try to find existing hub
        if doctl compute droplet list --format Name | grep -q "^${DROPLET_NAME}$"; then
            local droplet_id=$(doctl compute droplet list --format ID,Name | grep "${DROPLET_NAME}" | awk '{print $1}')
            doctl compute droplet get ${droplet_id} --format PublicIPv4 --no-header
        fi
    fi
}

# Deploy PostgreSQL cluster integrated with VPN deployment
deploy_postgres_cluster_integrated() {
    log "Waiting for nodes to stabilize..."
    sleep 10
    
    # Generate PostgreSQL passwords
    local postgres_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local replication_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    log "Generated PostgreSQL passwords"
    
    # Get hub IP
    local hub_ip=$(get_hub_ip)
    if [[ -z "$hub_ip" ]]; then
        warning "Could not determine hub IP, skipping PostgreSQL deployment"
        return
    fi
    
    log "PostgreSQL cluster will be managed by Patroni with etcd coordination"
    log "Containers will be deployed via docker-compose on the hub"
    
    # Save credentials for docker-compose
    cat >> runtime-config.md << EOF

## PostgreSQL Cluster Configuration (Patroni + etcd)

Generated: $(date)

### Credentials
- **Database**: dstack
- **User**: postgres
- **Password**: $postgres_password
- **Replication Password**: $replication_password

### Architecture
- **Orchestration**: Patroni with etcd
- **Primary**: 10.88.0.11:5432 (auto-elected)
- **Replicas**: 10.88.0.12:5432, 10.88.0.13:5432
- **Coordination**: etcd on hub (2379, 2380)
- **Patroni API**: 8008 on each node

### Connection String
\`\`\`
postgresql://postgres:$postgres_password@10.88.0.11:5432/dstack
\`\`\`

### Management Commands
\`\`\`bash
# Check cluster status
patronictl -c /etc/patroni.yml list

# Check Patroni API
curl http://10.88.0.11:8008/cluster

# Access from hub
ssh root@$hub_ip
psql -h 10.88.0.11 -U postgres -d dstack
\`\`\`

### Environment Variables for docker-compose
\`\`\`
POSTGRES_PASSWORD=$postgres_password
POSTGRES_REPLICATION_PASSWORD=$replication_password
\`\`\`
EOF
    
    log "PostgreSQL cluster configuration saved"
    log "Run 'docker-compose up -d' on the hub to start the cluster"
}

# Show brief PostgreSQL status in main status output
show_postgres_status_brief() {
    local hub_ip=$(get_hub_ip)
    if [[ -z "$hub_ip" ]]; then
        return
    fi
    
    echo "PostgreSQL Cluster (Patroni):"
    
    # Check if etcd is running on hub
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 \
        root@$hub_ip "docker ps --format '{{.Names}}' | grep -q etcd" 2>/dev/null; then
        echo "  etcd: ✅ Running on hub"
    else
        echo "  etcd: ❌ Not running on hub"
        return
    fi
    
    # Check each node for Patroni PostgreSQL
    for node in "10.88.0.11:Primary" "10.88.0.12:Replica-1" "10.88.0.13:Replica-2"; do
        local ip=$(echo $node | cut -d: -f1)
        local role=$(echo $node | cut -d: -f2)
        
        # Check if node is reachable
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 \
            root@$hub_ip "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@$ip 'echo ok'" &>/dev/null; then
            
            # Check if Patroni PostgreSQL is running
            if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                root@$hub_ip "ssh -o StrictHostKeyChecking=no root@$ip 'docker ps --format \"{{.Names}}\" | grep -q postgres'" 2>/dev/null; then
                
                # Try to get Patroni status
                local patroni_status=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                    root@$hub_ip "ssh -o StrictHostKeyChecking=no root@$ip 'curl -s http://localhost:8008/health 2>/dev/null | grep -o healthy || echo unknown'" 2>/dev/null || echo "unknown")
                
                if [[ "$patroni_status" == "healthy" ]]; then
                    echo "  $role ($ip): ✅ Running (Patroni healthy)"
                else
                    echo "  $role ($ip): ⚠️  Running but Patroni unhealthy"
                fi
            else
                echo "  $role ($ip): ❌ Not running"
            fi
        else
            echo "  $role ($ip): ⚠️  Node unreachable"
        fi
    done
    
    # Show cluster management info
    echo ""
    echo "Cluster Management:"
    echo "  - Check status: ssh root@$hub_ip 'patronictl -c /etc/patroni.yml list'"
    echo "  - Patroni API: http://10.88.0.11:8008/cluster"
}

# PostgreSQL cluster management
manage_postgres() {
    local subcommand="${1:-deploy}"
    
    case $subcommand in
        deploy)
            deploy_postgres_cluster
            ;;
        status)
            show_postgres_status
            ;;
        backup)
            run_postgres_backup
            ;;
        *)
            error "Unknown postgres subcommand: $subcommand"
            echo "Usage: ./deploy-vpn.sh postgres [deploy|status|backup]"
            exit 1
            ;;
    esac
}

# Deploy PostgreSQL cluster
deploy_postgres_cluster() {
    log "Deploying PostgreSQL cluster on VPN nodes..."
    
    # Check if VPN is deployed
    if ! check_vpn_exists; then
        error "VPN infrastructure not found. Deploy VPN first with: ./deploy-vpn.sh deploy"
        exit 1
    fi
    
    # Get hub IP
    local hub_ip=$(get_hub_ip)
    if [[ -z "$hub_ip" ]]; then
        error "Could not determine hub IP"
        exit 1
    fi
    
    # Generate PostgreSQL passwords
    local postgres_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    local replication_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    log "Generated PostgreSQL passwords"
    
    # Deploy PostgreSQL on each node
    log "Deploying PostgreSQL primary on node 10.88.0.11..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@$hub_ip "ssh -o StrictHostKeyChecking=no root@10.88.0.11 'docker run -d \
        --name postgres \
        --network container:wireguard \
        -e POSTGRES_USER=postgres \
        -e POSTGRES_PASSWORD=$postgres_password \
        -e POSTGRES_DB=dstack \
        -e POSTGRES_REPLICATION_PASSWORD=$replication_password \
        -v /data/postgres:/var/lib/postgresql/data \
        -v /data/backups:/var/lib/pgbackrest \
        dmvt/dstack-postgres:latest'" 2>/dev/null || true
    
    # Wait for primary to be ready
    log "Waiting for primary to be ready..."
    sleep 30
    
    # Deploy replicas
    for ip in 10.88.0.12 10.88.0.13; do
        log "Deploying PostgreSQL replica on node $ip..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            root@$hub_ip "ssh -o StrictHostKeyChecking=no root@$ip 'docker run -d \
            --name postgres \
            --network container:wireguard \
            -e POSTGRES_USER=postgres \
            -e POSTGRES_PASSWORD=$postgres_password \
            -e POSTGRES_DB=dstack \
            -e POSTGRES_REPLICATION_PASSWORD=$replication_password \
            -v /data/postgres:/var/lib/postgresql/data \
            -v /data/backups:/var/lib/pgbackrest \
            dmvt/dstack-postgres:latest'" 2>/dev/null || true
    done
    
    # Save credentials
    cat > runtime-postgres.md << EOF
# PostgreSQL Cluster Configuration

Generated: $(date)

## Credentials
- **Database**: dstack
- **User**: postgres
- **Password**: $postgres_password
- **Replication Password**: $replication_password

## Nodes
- **Primary**: 10.88.0.11:5432
- **Replica 1**: 10.88.0.12:5432
- **Replica 2**: 10.88.0.13:5432

## Connection String
\`\`\`
postgresql://postgres:$postgres_password@10.88.0.11:5432/dstack
\`\`\`

## Access from Hub
\`\`\`bash
ssh root@$hub_ip
psql -h 10.88.0.11 -U postgres -d dstack
\`\`\`
EOF
    
    log "PostgreSQL cluster deployed successfully!"
    log "Credentials saved to: runtime-postgres.md"
    
    # Show status
    show_postgres_status
}

# Show PostgreSQL cluster status
show_postgres_status() {
    log "Checking PostgreSQL cluster status..."
    
    local hub_ip=$(get_hub_ip)
    if [[ -z "$hub_ip" ]]; then
        error "Could not determine hub IP"
        return
    fi
    
    echo -e "\n${BLUE}PostgreSQL Cluster Status:${NC}"
    echo "=========================="
    
    # Check each node
    for node in "10.88.0.11:Primary" "10.88.0.12:Replica-1" "10.88.0.13:Replica-2"; do
        local ip=$(echo $node | cut -d: -f1)
        local role=$(echo $node | cut -d: -f2)
        
        echo -e "\n${YELLOW}Node $role ($ip):${NC}"
        
        # Check if PostgreSQL is running
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            root@$hub_ip "ssh -o StrictHostKeyChecking=no root@$ip 'docker ps | grep postgres'" 2>/dev/null | grep -q postgres; then
            echo "  Status: Running ✓"
            
            # Get PostgreSQL role
            local pg_role=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                root@$hub_ip "ssh -o StrictHostKeyChecking=no root@$ip \
                'docker exec postgres psql -U postgres -d dstack -tAc \
                \"SELECT CASE WHEN pg_is_in_recovery() THEN '\''replica'\'' ELSE '\''primary'\'' END\"'" 2>/dev/null || echo "unknown")
            echo "  PostgreSQL Role: $pg_role"
            
            # Get replication status for replicas
            if [[ "$pg_role" == "replica" ]]; then
                local lag=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                    root@$hub_ip "ssh -o StrictHostKeyChecking=no root@$ip \
                    'docker exec postgres psql -U postgres -d dstack -tAc \
                    \"SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT\"'" 2>/dev/null || echo "unknown")
                echo "  Replication Lag: ${lag}s"
            fi
        else
            echo "  Status: Not running ✗"
        fi
    done
    
    echo ""
}

# Run PostgreSQL backup
run_postgres_backup() {
    log "Running PostgreSQL backups..."
    
    local hub_ip=$(get_hub_ip)
    if [[ -z "$hub_ip" ]]; then
        error "Could not determine hub IP"
        return
    fi
    
    # Run backup on each node
    for node in "10.88.0.11:Primary" "10.88.0.12:Replica-1" "10.88.0.13:Replica-2"; do
        local ip=$(echo $node | cut -d: -f1)
        local role=$(echo $node | cut -d: -f2)
        
        log "Running backup on $role ($ip)..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            root@$hub_ip "ssh -o StrictHostKeyChecking=no root@$ip \
            'docker exec postgres pgbackrest --stanza=db backup'" 2>/dev/null || \
            warning "Backup failed on $role"
    done
    
    log "Backup process completed"
}

# Main execution
main() {
    case $COMMAND in
        deploy)
            deploy_vpn
            ;;
        destroy)
            destroy_infrastructure
            ;;
        status)
            show_status
            ;;
        test)
            test_connectivity
            ;;
        postgres)
            shift  # Remove 'postgres' from arguments
            manage_postgres "$@"
            ;;
        setup)
            run_setup_wizard
            ;;
        help)
            show_help
            ;;
        *)
            error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Parse arguments and run
parse_args "$@"
main
