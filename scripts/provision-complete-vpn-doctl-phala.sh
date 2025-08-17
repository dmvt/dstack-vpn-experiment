#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration
DROPLET_NAME="dstack-vpn-hub"
DROPLET_SIZE="s-1vcpu-1gb"
DROPLET_REGION="nyc1"
DROPLET_IMAGE="ubuntu-24-04-x64"
SSH_KEY_NAME="dstack-vpn-key"
FIREWALL_NAME="dstack-vpn-firewall"
PHALA_NODE_COUNT=3
PHALA_NODE_NAMES=("dstack-vpn-spoke-a" "dstack-vpn-spoke-b" "dstack-vpn-spoke-c")

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check doctl
    if ! command -v doctl &> /dev/null; then
        error "doctl CLI tool not found. Please install it first:"
        error "  macOS: brew install doctl"
        error "  Linux: Download from https://github.com/digitalocean/doctl/releases"
        error "  Then run: doctl auth init"
        exit 1
    fi
    
    # Check phala CLI
    if ! command -v phala &> /dev/null; then
        error "phala CLI tool not found. Please install it first:"
        error "  npm install -g phala"
        error "  OR use: npx phala"
        error "  Then run: phala auth login [your-api-key]"
        exit 1
    fi
    
    # Check authentication
    if ! doctl account get &> /dev/null; then
        error "Not authenticated with DigitalOcean. Run: doctl auth init"
        exit 1
    fi
    
    if ! phala status &> /dev/null; then
        error "Not authenticated with Phala Cloud. Run: phala auth login [your-api-key]"
        exit 1
    fi
    
    # Check WireGuard configs
    if [[ ! -f "config/hub/server.key" ]] || [[ ! -f "config/hub/server.pub" ]]; then
        error "WireGuard keys not found. Please run the key generation script first:"
        error "  ./scripts/generate-keys.sh"
        exit 1
    fi
    
    log "All prerequisites satisfied!"
}

# Step 1: Setup DigitalOcean Hub
setup_digitalocean_hub() {
    log "Step 1: Setting up DigitalOcean Hub..."
    
    # Create SSH key if needed
    if ! doctl compute ssh-key list --format Name | grep -q "^${SSH_KEY_NAME}$"; then
        log "Creating SSH key: ${SSH_KEY_NAME}"
        if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
            error "No SSH public key found. Please generate one: ssh-keygen -t rsa -b 4096"
            exit 1
        fi
        doctl compute ssh-key import ${SSH_KEY_NAME} --public-key-file ~/.ssh/id_rsa.pub
    fi
    
    SSH_KEY_ID=$(doctl compute ssh-key list --format ID,Name | grep "${SSH_KEY_NAME}" | awk '{print $1}')
    
    # Create firewall if needed
    if ! doctl compute firewall list --format Name | grep -q "^${FIREWALL_NAME}$"; then
        log "Creating firewall: ${FIREWALL_NAME}"
        doctl compute firewall create \
            --name ${FIREWALL_NAME} \
            --inbound-rules "protocol:tcp,ports:22,source:0.0.0.0/0 protocol:udp,ports:51820,source:0.0.0.0/0" \
            --outbound-rules "protocol:tcp,ports:all,destination:0.0.0.0/0 protocol:udp,ports:all,destination:0.0.0.0/0 protocol:icmp,destination:0.0.0.0/0"
    fi
    
    FIREWALL_ID=$(doctl compute firewall list --format ID,Name | grep "${FIREWALL_NAME}" | awk '{print $1}')
    
    # Create or reuse droplet
    if doctl compute droplet list --format Name | grep -q "^${DROPLET_NAME}$"; then
        warning "Droplet ${DROPLET_NAME} already exists"
        read -p "Do you want to destroy and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Destroying existing droplet..."
            doctl compute droplet delete ${DROPLET_NAME} --force
            sleep 10
        else
            log "Using existing droplet"
            DROPLET_ID=$(doctl compute droplet list --format ID,Name | grep "${DROPLET_NAME}" | awk '{print $1}')
            DROPLET_IP=$(doctl compute droplet get ${DROPLET_ID} --format PublicIPv4 --no-header)
            log "Existing droplet IP: ${DROPLET_IP}"
            return
        fi
    fi
    
    # Create new droplet
    log "Creating new droplet: ${DROPLET_NAME}"
    doctl compute droplet create ${DROPLET_NAME} \
        --size ${DROPLET_SIZE} \
        --region ${DROPLET_REGION} \
        --image ${DROPLET_IMAGE} \
        --ssh-keys ${SSH_KEY_ID} \
        --wait
    
    DROPLET_ID=$(doctl compute droplet list --format ID,Name | grep "${DROPLET_NAME}" | awk '{print $1}')
    DROPLET_IP=$(doctl compute droplet get ${DROPLET_ID} --format PublicIPv4 --no-header)
    
    log "Droplet created: ${DROPLET_IP}"
    
    # Apply firewall
    doctl compute firewall add-droplets ${FIREWALL_ID} --droplet-ids ${DROPLET_IP}
    
    # Wait for SSH
    log "Waiting for SSH to become available..."
    for i in {1..30}; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${DROPLET_IP} "echo 'SSH ready'" 2>/dev/null; then
            break
        fi
        if [[ $i -eq 30 ]]; then
            error "SSH connection failed"
            exit 1
        fi
        sleep 10
    done
    
    # Configure WireGuard on hub
    log "Configuring WireGuard on hub..."
    scp -o StrictHostKeyChecking=no config/hub/server.key root@${DROPLET_IP}:/etc/wireguard/
    scp -o StrictHostKeyChecking=no config/hub/server.pub root@${DROPLET_IP}:/etc/wireguard/
    scp -o StrictHostKeyChecking=no config/hub/wg0.conf root@${DROPLET_IP}:/etc/wireguard/
    scp -o StrictHostKeyChecking=no scripts/provision-hub.sh root@${DROPLET_IP}:/root/
    
    ssh -o StrictHostKeyChecking=no root@${DROPLET_IP} << 'EOF'
chmod +x /root/provision-hub.sh
./provision-hub.sh
EOF
}

# Step 2: Setup Phala Cloud DStack Spokes
setup_phala_spokes() {
    log "Step 2: Setting up Phala Cloud DStack Spokes..."
    
    # Check available nodes
    log "Checking available Phala Cloud nodes..."
    AVAILABLE_NODES=$(phala nodes --json | jq -r '.nodes[] | select(.status == "available") | .id' | head -${PHALA_NODE_COUNT})
    
    if [[ $(echo "$AVAILABLE_NODES" | wc -l) -lt ${PHALA_NODE_COUNT} ]]; then
        error "Not enough available nodes. Found: $(echo "$AVAILABLE_NODES" | wc -l), Need: ${PHALA_NODE_COUNT}"
        exit 1
    fi
    
    log "Found ${PHALA_NODE_COUNT} available nodes"
    
    # Create DStack instances
    SPOKE_IPS=()
    NODE_INDEX=0
    
    for NODE_ID in $AVAILABLE_NODES; do
        NODE_NAME=${PHALA_NODE_NAMES[$NODE_INDEX]}
        log "Creating DStack instance: ${NODE_NAME} on node ${NODE_ID}"
        
        # Create DStack instance
        phala dstack create \
            --name ${NODE_NAME} \
            --node ${NODE_ID} \
            --image alpine:3.19 \
            --env-file .env.template \
            --port 8000:8000 \
            --wait
        
        # Get instance IP
        INSTANCE_IP=$(phala dstack list --json | jq -r ".instances[] | select(.name == \"${NODE_NAME}\") | .ip")
        SPOKE_IPS+=($INSTANCE_IP)
        
        log "Instance ${NODE_NAME} created with IP: ${INSTANCE_IP}"
        NODE_INDEX=$((NODE_INDEX + 1))
    done
    
    # Update spoke configurations with hub IP
    log "Updating spoke configurations..."
    for i in {0..2}; do
        NODE_NAME=${PHALA_NODE_NAMES[$i]}
        SPOKE_IP=${SPOKE_IPS[$i]}
        
        # Update WireGuard config with hub IP
        sed -i.bak "s/Endpoint = .*:51820/Endpoint = ${DROPLET_IP}:51820/" config/node-${chr(97+i)}/wg0.conf
        
        log "Updated ${NODE_NAME} config with hub IP: ${DROPLET_IP}"
    done
}

# Step 3: Deploy WireGuard on Spokes
deploy_wireguard_on_spokes() {
    log "Step 3: Deploying WireGuard on DStack spokes..."
    
    for i in {0..2}; do
        NODE_NAME=${PHALA_NODE_NAMES[$i]}
        SPOKE_IP=${SPOKE_IPS[$i]}
        
        log "Deploying WireGuard on ${NODE_NAME} (${SPOKE_IP})..."
        
        # Copy WireGuard config
        scp -o StrictHostKeyChecking=no config/node-${chr(97+i)}/wg0.conf root@${SPOKE_IP}:/etc/wireguard/
        
        # Install and configure WireGuard
        ssh -o StrictHostKeyChecking=no root@${SPOKE_IP} << 'EOF'
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
EOF
        
        log "WireGuard deployed on ${NODE_NAME}"
    done
}

# Step 4: Deploy Status Service
deploy_status_service() {
    log "Step 4: Deploying status service on spokes..."
    
    for i in {0..2}; do
        NODE_NAME=${PHALA_NODE_NAMES[$i]}
        SPOKE_IP=${SPOKE_IPS[$i]}
        
        log "Deploying status service on ${NODE_NAME}..."
        
        # Copy status service files
        scp -o StrictHostKeyChecking=no -r docker/status-service/* root@${SPOKE_IP}:/opt/dstack-status/
        
        # Build and deploy
        ssh -o StrictHostKeyChecking=no root@${SPOKE_IP} << 'EOF'
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
        
        log "Status service deployed on ${NODE_NAME}"
    done
}

# Step 5: Configure Firewall on Spokes
configure_spoke_firewalls() {
    log "Step 5: Configuring firewalls on DStack spokes..."
    
    for i in {0..2}; do
        NODE_NAME=${PHALA_NODE_NAMES[$i]}
        SPOKE_IP=${SPOKE_IPS[$i]}
        
        log "Configuring firewall on ${NODE_NAME}..."
        
        # Copy and run firewall script
        scp -o StrictHostKeyChecking=no scripts/setup-firewall.sh root@${SPOKE_IP}:/tmp/
        
        ssh -o StrictHostKeyChecking=no root@${SPOKE_IP} << 'EOF'
chmod +x /tmp/setup-firewall.sh
/tmp/setup-firewall.sh
EOF
        
        log "Firewall configured on ${NODE_NAME}"
    done
}

# Step 6: Test VPN Connectivity
test_vpn_connectivity() {
    log "Step 6: Testing VPN connectivity..."
    
    # Test hub status
    log "Testing hub WireGuard status..."
    ssh -o StrictHostKeyChecking=no root@${DROPLET_IP} "wg show"
    
    # Test spoke connectivity
    for i in {0..2}; do
        NODE_NAME=${PHALA_NODE_NAMES[$i]}
        SPOKE_IP=${SPOKE_IPS[$i]}
        
        log "Testing ${NODE_NAME} connectivity..."
        
        # Test WireGuard status
        ssh -o StrictHostKeyChecking=no root@${SPOKE_IP} "wg show"
        
        # Test status service
        curl -s "http://${SPOKE_IP}:8000/status" | jq .
        
        # Test ping to other spokes
        for j in {0..2}; do
            if [[ $i -ne $j ]]; then
                OTHER_SPOKE_IP=${SPOKE_IPS[$j]}
                log "Testing ping from ${NODE_NAME} to ${PHALA_NODE_NAMES[$j]}..."
                ssh -o StrictHostKeyChecking=no root@${SPOKE_IP} "ping -c 3 ${OTHER_SPOKE_IP}"
            fi
        done
    done
}

# Step 7: Update Environment Configuration
update_environment() {
    log "Step 7: Updating environment configuration..."
    
    # Update .env.template with actual IPs
    if [[ -f ".env.template" ]]; then
        sed -i.bak "s/HUB_PUBLIC_IP=.*/HUB_PUBLIC_IP=${DROPLET_IP}/" .env.template
        
        # Add spoke IPs
        echo "" >> .env.template
        echo "# DStack Spoke IPs (auto-generated)" >> .env.template
        for i in {0..2}; do
            NODE_NAME=${PHALA_NODE_NAMES[$i]}
            SPOKE_IP=${SPOKE_IPS[$i]}
            echo "${NODE_NAME^^}_IP=${SPOKE_IP}" >> .env.template
        done
        
        log "Environment configuration updated"
    fi
}

# Main execution
main() {
    log "🚀 Starting complete DStack VPN automation with DigitalOcean + Phala Cloud..."
    
    check_prerequisites
    setup_digitalocean_hub
    setup_phala_spokes
    deploy_wireguard_on_spokes
    deploy_status_service
    configure_spoke_firewalls
    test_vpn_connectivity
    update_environment
    
    # Final summary
    log ""
    log "🎉 Complete DStack VPN deployment successful!"
    log ""
    log "=== Infrastructure Summary ==="
    log "DigitalOcean Hub: ${DROPLET_IP}"
    log "DStack Spokes:"
    for i in {0..2}; do
        log "  ${PHALA_NODE_NAMES[$i]}: ${SPOKE_IPS[$i]}"
    done
    log ""
    log "=== VPN Network ==="
    log "Hub IP: 10.88.0.1"
    log "Spoke A: 10.88.0.11"
    log "Spoke B: 10.88.0.12"
    log "Spoke C: 10.88.0.13"
    log ""
    log "=== Status Endpoints ==="
    for i in {0..2}; do
        log "  ${PHALA_NODE_NAMES[$i]}: http://${SPOKE_IPS[$i]}:8000/status"
    done
    log ""
    log "=== Next Steps ==="
    log "1. Test VPN connectivity: ping 10.88.0.11 from 10.88.0.12"
    log "2. Monitor status endpoints for health"
    log "3. Configure PostgreSQL cluster on spokes"
    log "4. Set up monitoring and alerting"
    log ""
    log "=== Useful Commands ==="
    log "Hub SSH: ssh root@${DROPLET_IP}"
    log "Hub status: ssh root@${DROPLET_IP} 'vpn-status'"
    log "Spoke status: curl http://${SPOKE_IPS[0]}:8000/status"
    log "VPN status: ssh root@${DROPLET_IP} 'wg show'"
}

# Run main function
main "$@"
