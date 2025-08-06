# DStack VPN Experiment

A WireGuard-based VPN system for DStack applications that enables secure, private communication between DStack instances with NFT-based access control.

## Overview

This project implements the MVP (Minimum Viable Product) for the DStack VPN functionality specification. It provides:

- WireGuard VPN containers for secure peer-to-peer communication
- **NFT-based access control** using blockchain smart contracts
- **Automated node registration** with WireGuard key generation
- **Real-time access verification** with sub-second latency
- Mullvad UDP-to-TCP proxy for tunneling support
- Docker Compose setup for easy local testing
- Integration with distributed PostgreSQL (stretch goal)

## 🚀 Quick Start

### Local Development

#### Prerequisites

- Docker and Docker Compose
- Node.js 18+ and npm
- WireGuard tools (for key generation)
- Linux kernel with WireGuard support (or Docker with privileged containers)

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd dstack-vpn-experiment
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Generate WireGuard keys**
   ```bash
   ./scripts/generate-keys.sh
   ```
   This creates:
   - `config/node-a/wg0.conf` - Node A WireGuard configuration
   - `config/node-b/wg0.conf` - Node B WireGuard configuration
   - Private and public keys for both nodes

4. **Start the VPN network**
   ```bash
   docker-compose up -d
   ```

5. **Verify connectivity**
   ```bash
   # Check container status
   docker-compose ps
   
   # Test connectivity between nodes
   docker exec wireguard-node-a ping -c 3 10.0.0.2
   docker exec wireguard-node-b ping -c 3 10.0.0.1
   
   # Test HTTP connectivity
   docker exec test-client wget -qO- http://nginx-server:80
   ```

6. **Test NFT access control**
   ```bash
   # Run comprehensive test suite
   npm test
   
   # Test contract integration
   npm run test:contract
   ```

### 🏗️ Phala Cloud Deployment

#### Prerequisites

- Phala Cloud account and API key
- Node.js 18+ and npm
- WireGuard tools (for key generation)
- `jq` for JSON parsing (optional, for advanced testing)

#### Setup

1. **Authenticate with Phala Cloud**
   ```bash
   npx phala auth login
   # Enter your API key when prompted
   ```

2. **Configure deployment environment**
   ```bash
   # Copy and edit the environment configuration
   cp config/phala-cloud.env config/phala-cloud.env.local
   # Edit with your contract details
   ```

3. **Run deployment setup**
   ```bash
   ./scripts/deploy-phala.sh setup
   ```

4. **Deploy to Phala Cloud TEE**
   ```bash
   ./scripts/deploy-phala.sh deploy
   ```

5. **Test the deployment**
   ```bash
   ./scripts/phala-test.sh all
   ```

#### Demo and Documentation

- **Interactive Demo**: `./scripts/phala-demo.sh`
- **Deployment Guide**: See `docs/phala-deployment.md`
- **Troubleshooting**: Comprehensive guide in documentation

#### Key Features

- **TEE Security**: All data encrypted in trusted execution environment
- **Automated Deployment**: One-command deployment and testing
- **Health Monitoring**: Built-in health checks and metrics
- **Scalable Architecture**: Ready for multi-node deployment
- **Cross-Platform**: Works on macOS, Linux, and Windows

## 🔐 NFT-Based Access Control

### Overview

The system uses **NFTs (Non-Fungible Tokens)** on the Base blockchain to control VPN access. Each NFT represents access to a specific DStack node and contains the WireGuard public key for secure authentication.

### Key Features

- **Blockchain-based permissions** - Access control managed by smart contracts
- **Public key authentication** - WireGuard keys stored on-chain for verification
- **Transferable access** - NFTs can be transferred between addresses
- **Revocable access** - Contract owner can revoke access at any time
- **Real-time verification** - Sub-second access verification latency

### Smart Contract

The system integrates with the `DstackAccessNFT` contract deployed on Base mainnet:
- **Contract Address**: `0x37d2106bADB01dd5bE1926e45D172Cb4203C4186`
- **Network**: Base mainnet (Chain ID: 8453)
- **Standard**: ERC721 with WireGuard public key storage

### Access Control Flow

1. **Node Registration**: Contract owner mints NFT for user address
2. **Public Key Storage**: WireGuard public key stored in NFT metadata
3. **Access Verification**: System checks NFT ownership for VPN access
4. **Real-time Updates**: Access changes immediately when NFT is transferred/revoked

## 🛠️ Node Registration & Management

### CLI Tool

The system includes a comprehensive CLI tool for node management:

```bash
# Register a new node for an address
node scripts/register-node.js register 0x1234...abcd

# Register with custom node ID
node scripts/register-node.js register 0x1234...abcd my-node-id

# Verify access for an address
node scripts/register-node.js verify 0x1234...abcd node-a

# Get node information
node scripts/register-node.js info node-a

# List all registered nodes
node scripts/register-node.js list

# Revoke access (requires private key)
node scripts/register-node.js revoke <tokenId>
```

### Automated Features

- **Key Generation**: Automatic WireGuard key pair generation
- **IP Assignment**: Automatic IP address assignment from 10.0.0.0/24
- **Registry Management**: Local JSON registry with contract synchronization
- **Error Handling**: Comprehensive error handling with retry logic

### Security Features

- **Private Key Security**: Never stored on-chain, only public keys
- **Environment Variables**: Private keys managed via environment variables
- **Cryptographic Security**: Using `crypto.randomBytes()` for key generation
- **Access Control**: Owner-controlled minting and revocation

## 📊 Testing & Validation

### Test Suite

The system includes comprehensive testing:

```bash
# Run all tests
npm test

# Run contract tests only
npm run test:contract

# Run specific test categories
node scripts/test-contract-integration.js
```

### Test Coverage

- **Contract Integration**: Web3.js connectivity and contract calls
- **Node Registration**: CLI functionality and key generation
- **Write Operations**: NFT minting and revocation (with private key)
- **Error Handling**: Rate limiting, network failures, invalid inputs
- **Performance**: Caching, latency, and throughput testing

### Performance Metrics

- **Access Verification**: <1 second latency
- **VPN Connectivity**: 0.4-0.6ms latency, 0% packet loss
- **Rate Limiting**: Exponential backoff with retry logic
- **Caching**: 30-second cache for frequently accessed data

## 🔧 Configuration

### Contract Configuration

The system uses `config/contract-config.json` for blockchain settings:

```json
{
  "networks": {
    "base": {
      "chainId": 8453,
      "rpcUrl": "https://mainnet.base.org",
      "contractAddress": "0x37d2106bADB01dd5bE1926e45D172Cb4203C4186"
    }
  },
  "defaultNetwork": "base",
  "ownerAddress": "0x003268b214719bB1A6C1E873D996c077DbD1BC7E"
}
```

### Environment Variables

```bash
# Required for write operations (NFT minting/revocation)
export PRIVATE_KEY=your_private_key_here

# Optional: Override default network
export DSTACK_NETWORK=base
```

### Node Registry

The system maintains a local registry in `config/node-registry.json`:

```json
{
  "peers": [
    {
      "node_id": "node-a",
      "public_key": "base64_wireguard_public_key",
      "ip_address": "10.0.0.1",
      "nft_owner": "0x1234...",
      "access_granted": true,
      "token_id": 1
    }
  ],
  "contract_address": "0x37d2106bADB01dd5bE1926e45D172Cb4203C4186",
  "network": {
    "cidr": "10.0.0.0/24",
    "dns_server": "10.0.0.1"
  }
}
```

## 🏗️ Architecture

### Local Development Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Node A        │    │   Node B        │
│                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │
│  │ WireGuard │  │    │  │ WireGuard │  │
│  │ Container │  │    │  │ Container │  │
│  └───────────┘  │    │  └───────────┘  │
│                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │
│  │   nginx   │  │    │  │  Test     │  │
│  │ Container │  │    │  │  Client   │  │
│  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┘
                    │
         ┌─────────────────────┐
         │   Docker Network    │
         │   (172.20.0.0/16)   │
         └─────────────────────┘
                    │
         ┌─────────────────────┐
         │   Base Blockchain   │
         │   (NFT Access)      │
         └─────────────────────┘
```

### Phala Cloud TEE Architecture

```
┌─────────────────────────────────┐
│        Phala Cloud TEE          │
│                                 │
│  ┌─────────────────────────────┐ │
│  │    WireGuard Container      │ │
│  │  ┌─────────────────────────┐ │ │
│  │  │   Contract Bridge       │ │ │ │
│  │  │  ┌─────────────────────┐ │ │ │ │
│  │  │  │   Access Control    │ │ │ │ │
│  │  │  │   Peer Registry     │ │ │ │ │
│  │  │  └─────────────────────┘ │ │ │ │
│  │  └─────────────────────────┘ │ │ │
│  │  ┌─────────────────────────┐ │ │ │
│  │  │   Health Monitoring     │ │ │ │
│  │  └─────────────────────────┘ │ │ │
│  └─────────────────────────────┘ │ │
│                                 │ │
│  ┌─────────────────────────────┐ │ │
│  │   Mullvad Proxy Container   │ │ │
│  └─────────────────────────────┘ │ │
└─────────────────────────────────┘ │
                                    │
┌─────────────────────────────────┐ │
│      Local Development          │ │
│  ┌─────────────────────────────┐ │ │
│  │   VPN Client Container      │ │ │
│  └─────────────────────────────┘ │ │
└─────────────────────────────────┘ │
                                    │
         ┌─────────────────────────┘
         │
┌─────────────────────────────────┐
│      Blockchain Network         │
│  ┌─────────────────────────────┐ │
│  │   Access Control Contract   │ │
│  └─────────────────────────────┘ │
└─────────────────────────────────┘
```

### Smart Contract Integration

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DStack App    │    │  Contract       │    │   Base          │
│                 │    │  Client         │    │   Blockchain    │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ Node      │──┼───▶│  Web3.js    │──┼───▶│  DstackAccess│  │
│  │ Registry  │  │    │  Integration│  │    │  NFT Contract │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ CLI       │──┼───▶│  Caching    │  │    │  │ Event      │  │
│  │ Tools     │  │    │  & Retry    │  │    │  │ Monitoring │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Network Configuration

- **VPN Network**: 10.0.0.0/24
- **Node A IP**: 10.0.0.1
- **Node B IP**: 10.0.0.2
- **WireGuard Port**: 51820/UDP
- **Docker Network**: 172.20.0.0/16
- **Blockchain Network**: Base mainnet (Chain ID: 8453)

## Services

### Local Development Services

- **node-a**: WireGuard VPN container for Node A
- **node-b**: WireGuard VPN container for Node B
- **nginx-server**: Test web server on Node A
- **test-client**: Test client on Node B

### Optional Services

- **mullvad-proxy**: UDP-to-TCP proxy for tunneling support

### Phala Cloud Services

- **wireguard-vpn**: TEE-optimized WireGuard container with contract integration
- **mullvad-proxy**: UDP-to-TCP proxy for tunneling support
- **nginx-server**: Test web server for connectivity verification
- **test-client**: Test client for validation
- **Health Monitoring**: Built-in health checks and metrics endpoints

## Testing

### Basic Connectivity Test

```bash
# Test ping between nodes
docker exec wireguard-node-a ping -c 3 10.0.0.2
docker exec wireguard-node-b ping -c 3 10.0.0.1
```

### HTTP Connectivity Test

```bash
# Test HTTP access from Node B to Node A
docker exec test-client wget -qO- http://nginx-server:80
```

### NFT Access Control Test

```bash
# Test contract integration
npm run test:contract

# Test node registration
node scripts/register-node.js list

# Test access verification
node scripts/register-node.js verify 0x1234...abcd node-a
```

### Phala Cloud Deployment Test

```bash
# Test deployment setup
./scripts/deploy-phala.sh setup

# Test deployment (with real contract config)
./scripts/deploy-phala.sh deploy

# Test deployed system
./scripts/phala-test.sh all

# Test specific components
./scripts/phala-test.sh status
./scripts/phala-test.sh network
./scripts/phala-test.sh vpn
```

### WireGuard Status

```bash
# Check WireGuard interface status
docker exec wireguard-node-a wg show
docker exec wireguard-node-b wg show
```

### Network Diagnostics

```bash
# Check network interfaces
docker exec wireguard-node-a ip addr show
docker exec wireguard-node-b ip addr show

# Check routing table
docker exec wireguard-node-a ip route show
docker exec wireguard-node-b ip route show
```

## Configuration

### WireGuard Configuration

The WireGuard configurations are automatically generated by the `generate-keys.sh` script. Each node gets:

- Unique private/public key pair
- Static IP address in the 10.0.0.0/24 range
- Peer configuration for the other node
- iptables rules for NAT and forwarding

### Docker Configuration

The Docker Compose file sets up:

- Privileged containers with NET_ADMIN and SYS_MODULE capabilities
- Volume mounts for WireGuard configurations
- Health checks for connectivity monitoring
- Network isolation with bridge networking

### Phala Cloud Configuration

#### Environment Configuration

The system uses `config/phala-cloud.env` for Phala Cloud deployment:

```bash
# Phala Cloud specific settings
PHALA_NETWORK=base
PHALA_TEEPOD_ID=8
PHALA_IMAGE_VERSION=dstack-0.3.6
PHALA_VCPU=2
PHALA_MEMORY=4096
PHALA_DISK_SIZE=40

# VPN Node Configuration
NODE_ID=phala-vpn-node-1
NETWORK=base
SYNC_INTERVAL=30000
LOG_LEVEL=info
HEALTH_CHECK_PORT=8080

# Contract Configuration (to be set during deployment)
CONTRACT_ADDRESS=0x...
RPC_URL=https://...
CONTRACT_PRIVATE_KEY=0x...

# WireGuard Configuration (generated automatically)
WIREGUARD_PRIVATE_KEY=...
```

#### Deployment Scripts

- **`scripts/deploy-phala.sh`**: Main deployment automation
- **`scripts/phala-test.sh`**: Comprehensive testing framework
- **`scripts/phala-demo.sh`**: Interactive demonstration

#### TEE-Optimized Docker Compose

The `docker-compose.phala.yml` file is optimized for Phala Cloud TEE:

- TEE-specific environment variables
- Optimized resource allocation
- Health monitoring integration
- Cross-platform compatibility

## Security Considerations

### NFT Access Control Security

- **Private keys never stored on-chain** - Only public keys stored
- **Public key authentication** - Cryptographic verification
- **Contract-based access control** - Immutable permission system
- **Owner-controlled minting** - Centralized access management
- **Secure key generation** - Using crypto.randomBytes()

### Traditional Security

- Private keys are stored with 600 permissions
- WireGuard configurations are read-only in containers
- Network isolation prevents unauthorized access
- iptables rules provide additional security
- Environment variables for sensitive data

### Rate Limiting & Error Handling

- **Exponential backoff** - Automatic retry with increasing delays
- **Rate limit detection** - Handles Base RPC rate limits gracefully
- **Caching** - Reduces RPC calls for frequently accessed data
- **Error recovery** - Graceful degradation for network failures

## Troubleshooting

### Common Issues

1. **WireGuard module not loaded**
   ```bash
   # Check if module is loaded
   lsmod | grep wireguard
   
   # Load module manually (if needed)
   sudo modprobe wireguard
   ```

2. **Container networking issues**
   ```bash
   # Check container logs
   docker-compose logs node-a
   docker-compose logs node-b
   
   # Restart containers
   docker-compose restart node-a node-b
   ```

3. **Contract connectivity issues**
   ```bash
   # Test contract connectivity
   npm run test:contract
   
   # Check network configuration
   cat config/contract-config.json
   
   # Verify RPC endpoint
   curl -X POST https://mainnet.base.org -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

4. **Rate limiting issues**
   ```bash
   # Check for rate limit errors in logs
   docker-compose logs | grep -i "rate limit"
   
   # The system automatically handles rate limits with retry logic
   # Check cache status
   node scripts/register-node.js info node-a
   ```

5. **Key generation issues**
   ```bash
   # Ensure wireguard-tools is installed
   which wg
   
   # Regenerate keys
   rm -rf config/node-*
   ./scripts/generate-keys.sh
   ```

6. **Phala Cloud deployment issues**
   ```bash
   # Check authentication
   npx phala auth status
   
   # Verify available resources
   npx phala nodes
   
   # Test deployment setup
   ./scripts/deploy-phala.sh setup
   
   # Check deployment logs
   npx phala cvms list
   
   # Test deployed system
   ./scripts/phala-test.sh all
   ```

### Debug Commands

```bash
# Check container status
docker-compose ps

# View container logs
docker-compose logs -f node-a

# Execute commands in containers
docker exec -it wireguard-node-a sh
docker exec -it wireguard-node-b sh

# Check network connectivity
docker exec wireguard-node-a ping 10.0.0.2

# Test contract health
node -e "const client = require('./src/contract-client'); new client('base').healthCheck().then(console.log)"

# Phala Cloud debugging
npx phala cvms list
npx phala nodes
./scripts/phala-demo.sh
```

## Development

### Project Structure

```
dstack-vpn-experiment/
├── contracts/
│   └── interfaces/
│       └── IDstackAccessNFT.sol
├── config/
│   ├── contract-config.json
│   ├── node-registry.json
│   ├── phala-cloud.env          # Phala Cloud production config
│   ├── phala-test.env           # Phala Cloud test config
│   ├── node-a/
│   │   └── wg0.conf
│   └── node-b/
│       └── wg0.conf
├── src/
│   └── contract-client.js
├── scripts/
│   ├── generate-keys.sh
│   ├── register-node.js
│   ├── test-contract-integration.js
│   ├── deploy-phala.sh          # Phala Cloud deployment
│   ├── phala-test.sh            # Phala Cloud testing
│   └── phala-demo.sh            # Interactive demo
├── docker/
│   ├── wireguard/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   └── mullvad-proxy/
│       ├── Dockerfile
│       └── proxy.sh
├── docs/
│   └── phala-deployment.md      # Comprehensive deployment guide
├── tool-reports/
│   ├── 20250106-1515-dstack-integration-plan.md
│   ├── 20250106-1520-phase1-implementation-summary.md
│   ├── 20250106-1525-untested-functionality-audit.md
│   ├── 20250106-1530-pull-request-summary.md
│   └── 20250106-2100-phala-cloud-deployment-task-implementation.md
├── docker-compose.yml           # Local development
├── docker-compose.phala.yml     # Phala Cloud deployment
├── package.json
├── README.md
└── SPEC.md
```

### Adding New Nodes

1. Create a new config directory: `config/node-c/`
2. Generate keys for the new node
3. Update existing node configurations to include the new peer
4. Add the new service to `docker-compose.yml`
5. Register the node using the CLI tool:
   ```bash
   node scripts/register-node.js register 0x1234...abcd node-c
   ```

### Customizing Network

To change the network configuration:

1. Modify the IP addresses in `scripts/generate-keys.sh`
2. Update the network CIDR in WireGuard configs
3. Adjust Docker network configuration in `docker-compose.yml`
4. Update the registry network configuration

### Development Workflow

1. **Local Development**
   ```bash
   # Install dependencies
   npm install
   
   # Run tests
   npm test
   
   # Start development environment
   docker-compose up -d
   ```

2. **Testing**
   ```bash
   # Run all tests
   npm test
   
   # Run specific test categories
   node scripts/test-contract-integration.js
   
   # Test with private key (for write operations)
   export PRIVATE_KEY=your_private_key_here
   npm test
   ```

3. **Contract Integration**
   ```bash
   # Test contract connectivity
   node -e "const client = require('./src/contract-client'); new client('base').healthCheck().then(console.log)"
   
   # Test node registration
   node scripts/register-node.js list
   ```

## Roadmap

### Phase 1 (Current) ✅
- [x] Basic WireGuard setup
- [x] **NFT-based access control**
- [x] **Smart contract integration**
- [x] **Automated node registration**
- [x] **Comprehensive testing suite**

### Phase 2 (Completed) ✅
- [x] **WireGuard container integration** - Embed contract client in containers
- [x] **Dynamic peer updates** - Real-time configuration management
- [x] **Enhanced error handling** - Rate limiting and network failures
- [x] **Performance optimization** - Caching and connection pooling

### Phase 3 (Completed) ✅
- [x] **Docker integration** - Complete container setup with health monitoring
- [x] **Monitoring dashboard** - Real-time status and metrics
- [x] **Deployment automation** - Scripts for easy setup and management
- [x] **Enhanced testing** - Comprehensive test coverage

### Phase 4 (Completed) ✅
- [x] **Phala Cloud deployment** - TEE-optimized cloud deployment
- [x] **Automated deployment scripts** - One-command deployment
- [x] **Comprehensive testing framework** - Cloud-specific testing
- [x] **Production documentation** - Complete deployment guide

### Phase 5 (Future)
- [ ] **Multi-node deployment** - Multiple TEE nodes
- [ ] **Distributed PostgreSQL** with Patroni
- [ ] **Advanced security features**
- [ ] **Developer experience improvements**

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly:
   ```bash
   npm test
   docker-compose up -d
   # Test your changes
   ```
5. Submit a pull request

### Development Guidelines

- **Test Coverage**: Ensure all new features have corresponding tests
- **Error Handling**: Implement comprehensive error handling with retry logic
- **Security**: Follow security best practices for private key management
- **Documentation**: Update documentation for any new features
- **Performance**: Consider rate limiting and caching for blockchain operations

## License

[Add your license information here]

## Support

For issues and questions:
- Check the troubleshooting section
- Review the logs with `docker-compose logs`
- Run the test suite: `npm test`
- Check contract connectivity: `npm run test:contract`
- Open an issue on GitHub

## Acknowledgments

- **@rchuqiao** for the DstackAccessNFT smart contract
- **Base Network** for the blockchain infrastructure
- **WireGuard** for the VPN technology
- **Docker** for the containerization platform 