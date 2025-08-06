# Phala Cloud Deployment Guide

This guide explains how to deploy the DStack VPN experiment to Phala Cloud using their TEE (Trusted Execution Environment) infrastructure.

## Overview

The VPN system can be deployed to Phala Cloud's secure TEE environment, providing:
- **Enhanced Security**: TEE isolation and encryption
- **Scalability**: Cloud-based infrastructure
- **Reliability**: Managed environment with automatic failover
- **Performance**: Optimized for TEE execution

## Prerequisites

### 1. Phala Cloud Account
- Sign up at [Phala Cloud](https://cloud.phala.network/)
- Get your API key from the dashboard
- Ensure you have sufficient credits for deployment

### 2. Local Environment
- Node.js and npm installed
- WireGuard tools installed (`wg` command)
- `jq` for JSON parsing
- Git for version control

### 3. Contract Configuration
- Deployed smart contract address
- RPC endpoint URL
- Contract private key for transactions

## Installation

### 1. Install Phala CLI
```bash
# The CLI is available via npx
npx phala --help
```

### 2. Authenticate with Phala Cloud
```bash
npx phala auth login
# Enter your API key when prompted
```

### 3. Verify Authentication
```bash
npx phala auth status
```

## Configuration

### 1. Environment Setup
Copy the example environment file and configure it:

```bash
cp config/phala-cloud.env config/phala-cloud.env.local
```

Edit `config/phala-cloud.env.local` with your settings:

```bash
# Contract Configuration
CONTRACT_ADDRESS=0x1234...  # Your deployed contract address
RPC_URL=https://...         # Your RPC endpoint
CONTRACT_PRIVATE_KEY=0x...  # Your private key

# Phala Cloud Settings
PHALA_TEEPOD_ID=8           # Available TEEPod ID
PHALA_IMAGE_VERSION=dstack-0.3.6
PHALA_VCPU=2
PHALA_MEMORY=4096
PHALA_DISK_SIZE=40
```

### 2. Generate WireGuard Keys
The deployment script will automatically generate WireGuard keys, or you can generate them manually:

```bash
# Generate private key
wg genkey > config/phala/private.key

# Generate public key
wg pubkey < config/phala/private.key > config/phala/public.key

# Set proper permissions
chmod 600 config/phala/private.key
chmod 644 config/phala/public.key
```

## Deployment

### 1. Setup Phase
Run the setup command to prepare the deployment:

```bash
./scripts/deploy-phala.sh setup
```

This will:
- Check prerequisites
- Generate WireGuard keys
- Validate environment configuration

### 2. Deploy to Phala Cloud
Deploy the VPN system:

```bash
./scripts/deploy-phala.sh deploy
```

Or with custom parameters:

```bash
./scripts/deploy-phala.sh deploy \
  --name my-vpn-deployment \
  --teepod-id 8 \
  --image dstack-0.3.6 \
  --vcpu 2 \
  --memory 4096 \
  --disk-size 40
```

### 3. Monitor Deployment
Check the deployment status:

```bash
./scripts/deploy-phala.sh monitor
```

Or use the Phala CLI directly:

```bash
npx phala cvms list
```

## Testing

### 1. Run Comprehensive Tests
Test the deployed VPN system:

```bash
./scripts/phala-test.sh all
```

### 2. Individual Test Components
Test specific components:

```bash
# Test CVM status
./scripts/phala-test.sh status

# Test network connectivity
./scripts/phala-test.sh network

# Test VPN functionality
./scripts/phala-test.sh vpn

# Test contract integration
./scripts/phala-test.sh contract
```

### 3. Test Specific CVM
Test a specific CVM by ID:

```bash
./scripts/phala-test.sh --cvm-id app_123456 all
```

## Architecture

### Single Node Deployment
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

### Multi-Node Deployment (Future)
```
┌─────────────────┐    ┌─────────────────┐
│  Phala TEE A    │    │  Phala TEE B    │
│                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │
│  │ WireGuard │  │    │  │ WireGuard │  │
│  │ Container │  │    │  │ Container │  │
│  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┘
                    │
         ┌─────────────────────┐
         │   Peer Registry     │
         │   (Contract)        │
         └─────────────────────┘
```

## Configuration Files

### Docker Compose (`docker-compose.phala.yml`)
Optimized for Phala Cloud TEE environment with:
- TEE-specific environment variables
- Optimized resource allocation
- Health checks and monitoring
- Network configuration

### Environment Configuration (`config/phala-cloud.env`)
Contains all necessary environment variables:
- Phala Cloud settings
- Contract configuration
- WireGuard settings
- Security parameters

## Monitoring and Management

### 1. CVM Management
```bash
# List all CVMs
npx phala cvms list

# Get CVM details
npx phala cvms get <app-id>

# Start CVM
npx phala cvms start <app-id>

# Stop CVM
npx phala cvms stop <app-id>

# Restart CVM
npx phala cvms restart <app-id>

# Delete CVM
npx phala cvms delete <app-id>
```

### 2. Network Information
```bash
# Get network details
npx phala cvms network <app-id>
```

### 3. Health Monitoring
The deployed VPN system provides health endpoints:
- `/health` - Overall health status
- `/stats` - Performance statistics
- `/wireguard` - WireGuard interface status
- `/config` - Configuration information

## Troubleshooting

### Common Issues

#### 1. Authentication Errors
```bash
# Re-authenticate
npx phala auth login
```

#### 2. Resource Allocation Errors
- Check available TEEPod resources
- Reduce vCPU, memory, or disk size
- Try a different TEEPod ID

#### 3. Deployment Failures
- Verify environment variables are set
- Check contract address and RPC URL
- Ensure WireGuard keys are generated

#### 4. Network Connectivity Issues
- Verify Mullvad proxy is running
- Check WireGuard interface status
- Test health endpoints

### Debug Commands
```bash
# Enable debug mode
npx phala cvms create --debug ...

# Check CVM logs
npx phala cvms get <app-id> --json

# Test network connectivity
npx phala cvms network <app-id>
```

## Security Considerations

### TEE Security
- All data is encrypted in the TEE
- Private keys remain secure
- No unauthorized access to VPN network

### Access Control
- NFT-based access control
- Smart contract integration
- Audit logging enabled

### Network Security
- WireGuard encryption
- Private IP addressing
- Mullvad proxy for tunneling

## Performance Optimization

### Resource Allocation
- **vCPU**: 2 cores recommended
- **Memory**: 4GB minimum
- **Disk**: 40GB for logs and data

### Network Optimization
- WireGuard MTU: 1420
- Persistent keepalive: 25 seconds
- UDP-to-TCP proxy for compatibility

## Cost Management

### Resource Costs
- vCPU: ~$0.10/hour per core
- Memory: ~$0.05/hour per GB
- Disk: ~$0.01/hour per GB

### Optimization Tips
- Use appropriate resource allocation
- Monitor usage with health endpoints
- Scale down when not in use

## Support and Resources

### Documentation
- [Phala Cloud Documentation](https://docs.phala.network/)
- [Phala Cloud CLI Reference](https://github.com/Phala-Network/phala-cloud-cli)

### Community
- [Phala Discord](https://discord.gg/phala)
- [Phala Forum](https://forum.phala.network/)

### Support
- [Phala Cloud Dashboard](https://cloud.phala.network/dashboard/)
- [GitHub Issues](https://github.com/Phala-Network/phala-cloud-cli/issues)

## Next Steps

### Immediate
1. Deploy to test environment
2. Run comprehensive tests
3. Validate all functionality

### Short-term
1. Multi-node deployment
2. Enhanced monitoring
3. Performance optimization

### Long-term
1. Production deployment
2. Advanced security features
3. Integration with DStack ecosystem 