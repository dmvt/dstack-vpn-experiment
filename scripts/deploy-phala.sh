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
NODE_COUNT=2  # Deploy 2 nodes as per MVP spec

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

# Function to generate Ethereum private key and wallet address for a specific node
generate_ethereum_key() {
    local node_id="$1"
    print_status "Generating Ethereum private key for VPN node $node_id..."
    print_warning "SECURITY: Private keys are stored in config/phala/ and should never be shared or committed to version control"
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR/phala"
    
    # Generate Ethereum private key using openssl
    if [[ ! -f "$CONFIG_DIR/phala/ethereum.key.$node_id" ]]; then
        # Generate 32 random bytes and convert to hex
        ETH_PRIVATE_KEY=$(openssl rand -hex 32)
        echo "$ETH_PRIVATE_KEY" > "$CONFIG_DIR/phala/ethereum.key.$node_id"
        print_success "Generated Ethereum private key for node $node_id"
    else
        ETH_PRIVATE_KEY=$(cat "$CONFIG_DIR/phala/ethereum.key.$node_id")
        print_warning "Ethereum private key for node $node_id already exists"
    fi
    
    # Set proper permissions
    chmod 600 "$CONFIG_DIR/phala/ethereum.key.$node_id"
    
    # Generate wallet address from private key
    WALLET_ADDRESS=$(node -e "
        const { ethers } = require('ethers');
        const wallet = new ethers.Wallet('0x$ETH_PRIVATE_KEY');
        console.log(wallet.address);
    ")
    
    # Store wallet address for later use
    echo "$WALLET_ADDRESS" > "$CONFIG_DIR/phala/wallet.address.$node_id"
    chmod 644 "$CONFIG_DIR/phala/wallet.address.$node_id"
    
    print_success "Ethereum private key generated and configured securely for node $node_id"
    print_status "Wallet address for node $node_id: $WALLET_ADDRESS"
    print_warning "An admin needs to grant NFT access to this wallet for node $node_id"
    
    # Return the wallet address for use by caller
    echo "$WALLET_ADDRESS"
}

# Function to generate keys for all nodes
generate_all_ethereum_keys() {
    print_status "Generating Ethereum keys for all $NODE_COUNT nodes..."
    
    local wallet_addresses=()
    
    for i in $(seq 1 $NODE_COUNT); do
        local node_id="node-$i"
        generate_ethereum_key "$node_id" > /dev/null 2>&1
        local wallet_address=$(cat "$CONFIG_DIR/phala/wallet.address.$node_id")
        wallet_addresses+=("$wallet_address")
    done
    
    # Store all wallet addresses in a file for easy access
    printf "%s\n" "${wallet_addresses[@]}" > "$CONFIG_DIR/phala/all_wallets.txt"
    chmod 644 "$CONFIG_DIR/phala/all_wallets.txt"
    
    print_success "Generated keys for all $NODE_COUNT nodes"
    print_status "Wallet addresses:"
    for i in "${!wallet_addresses[@]}"; do
        print_status "  Node $((i+1)): ${wallet_addresses[$i]}"
    done
}

# Function to check if wallet has NFT access
check_nft_access() {
    local wallet_address="$1"
    local node_id="$2"
    
    print_status "Checking NFT access for wallet on Base mainnet..."
    print_status "Wallet: $wallet_address"
    print_status "Node ID: $node_id"
    
    # Check NFT access using ethers.js
    local has_access=$(node -e "
        const { ethers } = require('ethers');
        const provider = new ethers.JsonRpcProvider('https://mainnet.base.org');
        
        // Contract ABI for hasNodeAccess function
        const abi = ['function hasNodeAccess(address user, string nodeId) external view returns (bool)'];
        const contractAddress = '0x37d2106bADB01dd5bE1926e45D172Cb4203C4186';
        const contract = new ethers.Contract(contractAddress, abi, provider);
        
        contract.hasNodeAccess('$wallet_address', '$node_id')
            .then(hasAccess => {
                console.log(hasAccess);
            })
            .catch(error => {
                console.error('Error:', error.message);
                process.exit(1);
            });
    ")
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to check NFT access"
        return 1
    fi
    
    if [[ "$has_access" == "true" ]]; then
        print_success "Wallet has NFT access for node $node_id"
        return 0
    else
        print_warning "No NFT access found. Admin needs to grant access to wallet $wallet_address for node $node_id"
        return 1
    fi
}

# Function to display NFT minting instructions
display_nft_minting_instructions() {
    print_status "=== NFT MINTING INSTRUCTIONS ==="
    print_status "An admin needs to mint NFTs for the following nodes:"
    print_status "Contract Address: 0x37d2106bADB01dd5bE1926e45D172Cb4203C4186"
    print_status "Network: Base mainnet (Chain ID: 8453)"
    print_status ""
    
    for i in $(seq 1 $NODE_COUNT); do
        local node_id="node-$i"
        local wallet_address=$(cat "$CONFIG_DIR/phala/wallet.address.$node_id" 2>/dev/null || echo "")
        local wireguard_public_key=$(cat "$CONFIG_DIR/phala/public.$node_id.key" 2>/dev/null || echo "")
        
        if [[ -n "$wallet_address" && -n "$wireguard_public_key" ]]; then
            print_status "Node $i ($node_id):"
            print_status "  Wallet Address: $wallet_address"
            print_status "  WireGuard Public Key: $wireguard_public_key"
            print_status "  Token URI: https://raw.githubusercontent.com/dmvt/dstack-vpn-experiment/refs/heads/main/nft-metadata/$node_id.json"
            print_status ""
            print_status "  Call mintNodeAccess with these parameters:"
            print_status "    to: $wallet_address"
            print_status "    nodeId: $node_id"
            print_status "    wireguardPublicKey: $wireguard_public_key"
            print_status "    tokenURI: https://raw.githubusercontent.com/dmvt/dstack-vpn-experiment/refs/heads/main/nft-metadata/$node_id.json"
            print_status ""
        fi
    done
    
    print_status "=== END NFT MINTING INSTRUCTIONS ==="
    print_status ""
    
    # Generate minting script for admin
    generate_minting_script
}

# Function to generate a minting script for the admin
generate_minting_script() {
    local script_path="$CONFIG_DIR/phala/mint-nfts.js"
    
    print_status "Generating minting script for admin: $script_path"
    
    cat > "$script_path" << 'EOF'
#!/usr/bin/env node

// NFT Minting Script for DStack VPN Nodes
// Run this script with: node config/phala/mint-nfts.js
// Requires: npm install ethers

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Configuration
const CONTRACT_ADDRESS = '0x37d2106bADB01dd5bE1926e45D172Cb4203C4186';
const RPC_URL = 'https://mainnet.base.org';
const CONFIG_DIR = path.join(__dirname, '..');

// Contract ABI for mintNodeAccess function
const ABI = [
    'function mintNodeAccess(address to, string nodeId, string wireguardPublicKey, string tokenURI) external returns (uint256)'
];

async function mintNFTs() {
    try {
        // Check if private key is provided
        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey) {
            console.error('❌ PRIVATE_KEY environment variable not set');
            console.error('Please set your admin private key: export PRIVATE_KEY=your_private_key_here');
            process.exit(1);
        }

        // Setup provider and signer
        const provider = new ethers.JsonRpcProvider(RPC_URL);
        const signer = new ethers.Wallet(privateKey, provider);
        const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, signer);

        console.log('🔗 Connected to Base mainnet');
        console.log('📝 Contract:', CONTRACT_ADDRESS);
        console.log('👤 Admin address:', signer.address);
        console.log('');

        // Read wallet addresses
        const walletsFile = path.join(CONFIG_DIR, 'phala', 'all_wallets.txt');
        if (!fs.existsSync(walletsFile)) {
            console.error('❌ Wallet addresses file not found:', walletsFile);
            console.error('Run ./scripts/deploy-phala.sh setup first');
            process.exit(1);
        }

        const walletAddresses = fs.readFileSync(walletsFile, 'utf8')
            .trim()
            .split('\n')
            .filter(line => line.trim());

        console.log('🎯 Minting NFTs for', walletAddresses.length, 'nodes...');
        console.log('');

        // Mint NFTs for each node
        for (let i = 0; i < walletAddresses.length; i++) {
            const walletAddress = walletAddresses[i];
            const nodeId = `node-${i + 1}`;
            const tokenURI = `https://raw.githubusercontent.com/dmvt/dstack-vpn-experiment/refs/heads/main/nft-metadata/${nodeId}.json`;

            // Read WireGuard public key for this specific node
            const publicKeyFile = path.join(CONFIG_DIR, 'phala', `public.${nodeId}.key`);
            if (!fs.existsSync(publicKeyFile)) {
                console.error(`❌ WireGuard public key not found for ${nodeId}:`, publicKeyFile);
                console.error('Run ./scripts/deploy-phala.sh setup first');
                process.exit(1);
            }

            const wireguardPublicKey = fs.readFileSync(publicKeyFile, 'utf8').trim();

            console.log(`📦 Minting NFT for ${nodeId}...`);
            console.log(`   Wallet: ${walletAddress}`);
            console.log(`   Node ID: ${nodeId}`);
            console.log(`   WireGuard Public Key: ${wireguardPublicKey}`);
            console.log(`   Token URI: ${tokenURI}`);

            try {
                const tx = await contract.mintNodeAccess(
                    walletAddress,
                    nodeId,
                    wireguardPublicKey,
                    tokenURI
                );

                console.log(`   ⏳ Transaction hash: ${tx.hash}`);
                console.log(`   🔄 Waiting for confirmation...`);

                const receipt = await tx.wait();
                console.log(`   ✅ NFT minted successfully! Token ID: ${receipt.logs[0].topics[1]}`);
                console.log('');

            } catch (error) {
                console.error(`   ❌ Failed to mint NFT for ${nodeId}:`, error.message);
                console.log('');
            }
        }

        console.log('🎉 NFT minting process completed!');
        console.log('You can now run: ./scripts/deploy-phala.sh deploy');

    } catch (error) {
        console.error('❌ Error:', error.message);
        process.exit(1);
    }
}

// Run the script
mintNFTs();
EOF

    chmod +x "$script_path"
    print_success "Minting script generated: $script_path"
    print_status "Admin can run: node $script_path"
    print_status "Make sure to set PRIVATE_KEY environment variable first"
    print_status ""
}

# Function to wait for NFT access for all nodes
wait_for_all_nft_access() {
    local max_wait_time=3600  # 1 hour
    local check_interval=30   # 30 seconds
    local elapsed=0
    
    # Display minting instructions first
    display_nft_minting_instructions
    
    print_status "Waiting for NFT access for all $NODE_COUNT nodes..."
    print_status "Press Ctrl+C to cancel and deploy anyway"
    
    while [[ $elapsed -lt $max_wait_time ]]; do
        local all_granted=true
        
        for i in $(seq 1 $NODE_COUNT); do
            local node_id="node-$i"
            local wallet_address=$(cat "$CONFIG_DIR/phala/wallet.address.$node_id" 2>/dev/null || echo "")
            
            if [[ -n "$wallet_address" ]]; then
                if ! check_nft_access "$wallet_address" "$node_id"; then
                    all_granted=false
                    break
                fi
            else
                print_error "Wallet address for node $node_id not found"
                return 1
            fi
        done
        
        if [[ "$all_granted" == "true" ]]; then
            print_success "NFT access granted for all nodes! Proceeding with deployment..."
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        
        local remaining=$((max_wait_time - elapsed))
        print_status "Still waiting... ($(($remaining / 60))m $(($remaining % 60))s remaining)"
    done
    
    print_warning "Timeout waiting for NFT access. You can still deploy, but the VPN may fail to start."
    read -p "Continue with deployment anyway? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        print_error "Deployment cancelled"
        exit 1
    fi
}

# Function to generate WireGuard keys for all nodes
generate_wireguard_keys() {
    print_status "Generating WireGuard keys for all $NODE_COUNT nodes..."
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR/phala"
    
    for i in $(seq 1 $NODE_COUNT); do
        local node_id="node-$i"
        print_status "Generating WireGuard keys for $node_id..."
        
        # Generate private key for this node
        if [[ ! -f "$CONFIG_DIR/phala/private.$node_id.key" ]]; then
            wg genkey > "$CONFIG_DIR/phala/private.$node_id.key"
            print_success "Generated WireGuard private key for $node_id"
        else
            print_warning "WireGuard private key for $node_id already exists"
        fi
        
        # Generate public key for this node
        if [[ ! -f "$CONFIG_DIR/phala/public.$node_id.key" ]]; then
            wg pubkey < "$CONFIG_DIR/phala/private.$node_id.key" > "$CONFIG_DIR/phala/public.$node_id.key"
            print_success "Generated WireGuard public key for $node_id"
        else
            print_warning "WireGuard public key for $node_id already exists"
        fi
        
        # Set proper permissions
        chmod 600 "$CONFIG_DIR/phala/private.$node_id.key"
        chmod 644 "$CONFIG_DIR/phala/public.$node_id.key"
    done
    
    # For backward compatibility, also create a default key pair (using node-1)
    if [[ ! -f "$CONFIG_DIR/phala/private.key" ]]; then
        cp "$CONFIG_DIR/phala/private.node-1.key" "$CONFIG_DIR/phala/private.key"
        cp "$CONFIG_DIR/phala/public.node-1.key" "$CONFIG_DIR/phala/public.key"
        chmod 600 "$CONFIG_DIR/phala/private.key"
        chmod 644 "$CONFIG_DIR/phala/public.key"
    fi
    
    # Update environment file with the default private key
    PRIVATE_KEY=$(cat "$CONFIG_DIR/phala/private.key")
    # Use awk for better compatibility across platforms
    awk -v key="$PRIVATE_KEY" '/^WIREGUARD_PRIVATE_KEY=$/ { print "WIREGUARD_PRIVATE_KEY=" key; next } { print }' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
    
    print_success "WireGuard keys configured for all $NODE_COUNT nodes"
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
    
    # Note: CONTRACT_PRIVATE_KEY will be auto-generated if not set
    
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
        echo ""
        echo "Note: CONTRACT_PRIVATE_KEY will be automatically generated during deployment."
        echo "Then update $ENV_FILE with these values."
        return 1
    fi
    
    print_success "Environment validation passed"
}

# Function to deploy a single node to Phala Cloud
deploy_single_node() {
    local node_id="$1"
    local wallet_address="$2"
    local timestamp="$3"
    
    print_status "Deploying node $node_id to Phala Cloud..."
    
    # Create node-specific deployment name
    local deployment_name="${CVM_NAME}-${node_id}-${timestamp}"
    
    print_status "Deployment name: $deployment_name"
    print_status "TEEPod ID: $TEEPOD_ID"
    print_status "Image version: $IMAGE_VERSION"
    print_status "Resources: ${VCPU}vCPU, ${MEMORY}MB RAM, ${DISK_SIZE}GB disk"
    
    # Create node-specific environment file
    local node_env_file="$CONFIG_DIR/phala-cloud-${node_id}.env"
    cp "$ENV_FILE" "$node_env_file"
    
    # Update node-specific environment variables
    local eth_private_key=$(cat "$CONFIG_DIR/phala/ethereum.key.$node_id")
    sed -i.bak "s/^NODE_ID=.*/NODE_ID=$node_id/" "$node_env_file"
    sed -i.bak "s/^CONTRACT_PRIVATE_KEY=.*/CONTRACT_PRIVATE_KEY=0x$eth_private_key/" "$node_env_file"
    
    # Deploy using Phala CLI
    print_status "Creating CVM for node $node_id on Phala Cloud..."
    
    npx phala cvms create \
        --name "$deployment_name" \
        --compose "$DOCKER_COMPOSE_FILE" \
        --vcpu "$VCPU" \
        --memory "$MEMORY" \
        --disk-size "$DISK_SIZE" \
        --teepod-id "$TEEPOD_ID" \
        --image "$IMAGE_VERSION" \
        --env-file "$node_env_file" \
        --debug
    
    print_success "Deployment initiated for node $node_id"
}

# Function to deploy all nodes to Phala Cloud
deploy_to_phala() {
    print_status "Deploying $NODE_COUNT nodes to Phala Cloud..."
    
    # Get the current timestamp for the deployment
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    for i in $(seq 1 $NODE_COUNT); do
        local node_id="node-$i"
        local wallet_address=$(cat "$CONFIG_DIR/phala/wallet.address.$node_id" 2>/dev/null || echo "")
        
        if [[ -n "$wallet_address" ]]; then
            deploy_single_node "$node_id" "$wallet_address" "$timestamp"
        else
            print_error "Wallet address for node $node_id not found"
            exit 1
        fi
    done
    
    print_success "All $NODE_COUNT nodes deployed successfully"
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
            generate_all_ethereum_keys
            generate_wireguard_keys
            validate_environment
            print_success "Setup completed successfully for all $NODE_COUNT nodes"
            print_status ""
            display_nft_minting_instructions
            generate_minting_script
            print_success "Ready for NFT minting by admin"
            ;;
        deploy)
            check_prerequisites
            generate_all_ethereum_keys
            generate_wireguard_keys
            validate_environment
            
            # Wait for NFT access for all nodes
            wait_for_all_nft_access
            
            deploy_to_phala
            monitor_deployment
            print_success "Deployment completed successfully for all $NODE_COUNT nodes"
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