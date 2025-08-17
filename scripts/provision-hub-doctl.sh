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

# Check if doctl is installed
if ! command -v doctl &> /dev/null; then
    error "doctl CLI tool not found. Please install it first:"
    error "  macOS: brew install doctl"
    error "  Linux: Download from https://github.com/digitalocean/doctl/releases"
    error "  Then run: doctl auth init"
    exit 1
fi

# Check if authenticated
if ! doctl account get &> /dev/null; then
    error "Not authenticated with DigitalOcean. Run: doctl auth init"
    exit 1
fi

# Check if WireGuard configs exist
if [[ ! -f "config/hub/server.key" ]] || [[ ! -f "config/hub/server.pub" ]]; then
    error "WireGuard keys not found. Please run the key generation script first:"
    error "  ./scripts/generate-keys.sh"
    exit 1
fi

log "Starting automated DStack VPN Hub provisioning with DigitalOcean CLI..."

## Step 1: Create SSH Key
log "Step 1: Setting up SSH key..."

# Check if SSH key already exists
if ! doctl compute ssh-key list --format Name | grep -q "^${SSH_KEY_NAME}$"; then
    log "Creating new SSH key: ${SSH_KEY_NAME}"
    
    # Check if user has an SSH key
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        error "No SSH public key found at ~/.ssh/id_rsa.pub"
        error "Please generate an SSH key first: ssh-keygen -t rsa -b 4096"
        exit 1
    fi
    
    # Import SSH key to DigitalOcean
    doctl compute ssh-key import ${SSH_KEY_NAME} --public-key-file ~/.ssh/id_rsa.pub
    log "SSH key imported successfully"
else
    log "SSH key ${SSH_KEY_NAME} already exists"
fi

# Get SSH key ID
SSH_KEY_ID=$(doctl compute ssh-key list --format ID,Name | grep "${SSH_KEY_NAME}" | awk '{print $1}')
log "Using SSH key ID: ${SSH_KEY_ID}"

## Step 2: Create Firewall
log "Step 2: Setting up firewall..."

# Check if firewall already exists
if ! doctl compute firewall list --format Name | grep -q "^${FIREWALL_NAME}$"; then
    log "Creating firewall: ${FIREWALL_NAME}"
    
    # Create firewall with rules
    doctl compute firewall create \
        --name ${FIREWALL_NAME} \
        --inbound-rules "protocol:tcp,ports:22,source:0.0.0.0/0 protocol:udp,ports:51820,source:0.0.0.0/0" \
        --outbound-rules "protocol:tcp,ports:all,destination:0.0.0.0/0 protocol:udp,ports:all,destination:0.0.0.0/0 protocol:icmp,destination:0.0.0.0/0"
    
    log "Firewall created successfully"
else
    log "Firewall ${FIREWALL_NAME} already exists"
fi

# Get firewall ID
FIREWALL_ID=$(doctl compute firewall list --format ID,Name | grep "${FIREWALL_NAME}" | awk '{print $1}')
log "Using firewall ID: ${FIREWALL_ID}"

## Step 3: Create Droplet
log "Step 3: Creating DigitalOcean droplet..."

# Check if droplet already exists
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
        goto_step_4=true
    fi
fi

if [[ "$goto_step_4" != "true" ]]; then
    log "Creating new droplet: ${DROPLET_NAME}"
    log "  Size: ${DROPLET_SIZE}"
    log "  Region: ${DROPLET_REGION}"
    log "  Image: ${DROPLET_IMAGE}"
    
    # Create droplet
    doctl compute droplet create ${DROPLET_NAME} \
        --size ${DROPLET_SIZE} \
        --region ${DROPLET_REGION} \
        --image ${DROPLET_IMAGE} \
        --ssh-keys ${SSH_KEY_ID} \
        --wait
    
    # Get droplet ID and IP
    DROPLET_ID=$(doctl compute droplet list --format ID,Name | grep "${DROPLET_NAME}" | awk '{print $1}')
    DROPLET_IP=$(doctl compute droplet get ${DROPLET_ID} --format PublicIPv4 --no-header)
    
    log "Droplet created successfully!"
    log "  ID: ${DROPLET_ID}"
    log "  IP: ${DROPLET_IP}"
    
    # Wait for droplet to be ready
    log "Waiting for droplet to be ready..."
    sleep 30
    
    # Apply firewall to droplet
    log "Applying firewall to droplet..."
    doctl compute firewall add-droplets ${FIREWALL_ID} --droplet-ids ${DROPLET_ID}
fi

## Step 4: Configure WireGuard
log "Step 4: Configuring WireGuard on droplet..."

# Wait for SSH to be available
log "Waiting for SSH to become available..."
for i in {1..30}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${DROPLET_IP} "echo 'SSH ready'" 2>/dev/null; then
        log "SSH connection established"
        break
    fi
    if [[ $i -eq 30 ]]; then
        error "SSH connection failed after 30 attempts"
        exit 1
    fi
    sleep 10
done

# Copy WireGuard configuration
log "Copying WireGuard configuration to droplet..."
scp -o StrictHostKeyChecking=no config/hub/server.key root@${DROPLET_IP}:/etc/wireguard/
scp -o StrictHostKeyChecking=no config/hub/server.pub root@${DROPLET_IP}:/etc/wireguard/
scp -o StrictHostKeyChecking=no config/hub/wg0.conf root@${DROPLET_IP}:/etc/wireguard/

# Copy provisioning script
scp -o StrictHostKeyChecking=no scripts/provision-hub.sh root@${DROPLET_IP}:/root/

# Run provisioning script on droplet
log "Running WireGuard provisioning on droplet..."
ssh -o StrictHostKeyChecking=no root@${DROPLET_IP} << 'EOF'
chmod +x /root/provision-hub.sh
./provision-hub.sh
EOF

## Step 5: Update Environment Configuration
log "Step 5: Updating environment configuration..."

# Update .env.template with actual IP
if [[ -f ".env.template" ]]; then
    log "Updating .env.template with droplet IP: ${DROPLET_IP}"
    sed -i.bak "s/HUB_PUBLIC_IP=.*/HUB_PUBLIC_IP=${DROPLET_IP}/" .env.template
    log "Environment template updated"
fi

## Step 6: Verification
log "Step 6: Verifying hub configuration..."

# Test WireGuard status
log "Testing WireGuard connectivity..."
ssh -o StrictHostKeyChecking=no root@${DROPLET_IP} "wg show"

# Test firewall
log "Testing firewall configuration..."
ssh -o StrictHostKeyChecking=no root@${DROPLET_IP} "nft list ruleset"

## Summary
log ""
log "🎉 DStack VPN Hub provisioning complete!"
log ""
log "=== Hub Details ==="
log "Name: ${DROPLET_NAME}"
log "IP: ${DROPLET_IP}"
log "Region: ${DROPLET_REGION}"
log "Size: ${DROPLET_SIZE}"
log ""
log "=== Next Steps ==="
log "1. Update your .env file with HUB_PUBLIC_IP=${DROPLET_IP}"
log "2. Copy spoke configurations to your DStack nodes"
log "3. Update spoke configs with hub IP: ${DROPLET_IP}"
log "4. Test VPN connectivity between nodes"
log ""
log "=== Useful Commands ==="
log "SSH to hub: ssh root@${DROPLET_IP}"
log "Check hub status: ssh root@${DROPLET_IP} 'vpn-status'"
log "View WireGuard: ssh root@${DROPLET_IP} 'wg show'"
log "Check firewall: ssh root@${DROPLET_IP} 'nft list ruleset'"
log ""
log "=== Security Notes ==="
log "- SSH access restricted to your public key"
log "- Only ports 22 (SSH) and 51820 (WireGuard) are open"
log "- Firewall rules automatically applied"
log "- Hub isolated from originating traffic to spokes"
