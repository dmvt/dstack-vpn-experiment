# DStack Integration Plan: NFT Access Control & Peer Registry

**Date:** 2025-01-06 15:15  
**Task:** Implement DStack integration with NFT-based access control and peer registry  
**Branch:** `feature/dstack-peer-registry`

## Current State Analysis

### Existing Infrastructure
- ✅ Basic WireGuard VPN setup working (2 nodes, nginx server, test client)
- ✅ Docker containers with proper networking (10.0.0.0/24 VPN subnet)
- ✅ Key generation and configuration management
- ✅ Health checks and connectivity testing

### Contract Implementation (from @rchuqiao)
- ✅ **DstackAccessNFT.sol** deployed on Base mainnet: `0x37d2106bADB01dd5bE1926e45D172Cb4203C4186`
- ✅ ERC721 NFT with WireGuard public key storage
- ✅ Node access control with `hasNodeAccess(address, nodeId)` verification
- ✅ Public key authentication and transfer support
- ✅ Owner-controlled minting and revocation

## Implementation Plan

### Phase 1: Smart Contract Integration

#### 1.1 Contract Interface & Configuration
```solidity
// Integration points with existing contract
interface IDstackAccessNFT {
    function hasNodeAccess(address user, string memory nodeId) external view returns (bool);
    function getPublicKeyByOwner(address owner) external view returns (string memory);
    function getNodeAccess(uint256 tokenId) external view returns (string, string, uint256, bool);
    function getTokenIdByNodeId(string memory nodeId) external view returns (uint256);
}
```

**Files to create:**
- `contracts/interfaces/IDstackAccessNFT.sol`
- `config/contract-config.json` (Base mainnet contract address)
- `scripts/contract-interaction.js` (Web3 integration)

#### 1.2 Node Registration System
```javascript
// Node registration flow
1. Generate WireGuard key pair for new DStack node
2. Call contract.mintNodeAccess(nodeAddress, nodeId, publicKey, tokenURI)
3. Store private key securely in DStack instance
4. Update peer registry with new node information
```

**Files to create:**
- `scripts/register-node.js`
- `scripts/verify-access.js`
- `config/node-registry.json`

### Phase 2: DStack Integration Layer

#### 2.1 Peer Registry Contract Integration
```javascript
// Peer registry structure
{
  "peers": [
    {
      "node_id": "node-a",
      "public_key": "base64_wireguard_public_key",
      "ip_address": "10.0.0.1",
      "hostname": "node-a.vpn.dstack",
      "instance_id": "dstack_instance_id",
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

#### 2.2 Access Control Middleware
```javascript
// Access verification flow
1. WireGuard connection attempt
2. Extract public key from connection
3. Query contract for node access
4. Verify NFT ownership and active status
5. Grant/deny VPN access
```

**Files to create:**
- `src/access-control.js`
- `src/peer-registry.js`
- `src/contract-client.js`

### Phase 3: Enhanced Docker Integration

#### 3.1 Contract-Aware WireGuard Container
```dockerfile
# Enhanced WireGuard container with contract integration
FROM alpine:3.19
RUN apk add --no-cache wireguard-tools nodejs npm
COPY src/ /app/
COPY config/ /app/config/
RUN npm install
CMD ["node", "/app/wireguard-contract-bridge.js"]
```

#### 3.2 Configuration Management
```javascript
// Dynamic configuration updates
1. Monitor contract events for access changes
2. Update WireGuard peer configurations
3. Restart VPN connections when needed
4. Log access control events
```

**Files to create:**
- `docker/wireguard-contract/Dockerfile`
- `docker/wireguard-contract/entrypoint.sh`
- `src/config-manager.js`

### Phase 4: Testing & Validation

#### 4.1 NFT Access Control Tests
```javascript
// Test scenarios
1. Mint NFT for test user
2. Verify VPN access granted
3. Transfer NFT to new owner
4. Verify access transferred
5. Revoke NFT access
6. Verify VPN access denied
```

#### 4.2 Integration Tests
```javascript
// End-to-end testing
1. Deploy test nodes with NFT access
2. Establish VPN connections
3. Test nginx server access
4. Verify contract state consistency
5. Test NFT transfer scenarios
```

**Files to create:**
- `test/nft-access-control.test.js`
- `test/integration.test.js`
- `scripts/test-setup.js`

## Implementation Steps

### Step 1: Contract Integration Setup
1. Install Web3.js and contract dependencies
2. Create contract interface and configuration
3. Implement basic contract interaction functions
4. Test contract connectivity

### Step 2: Node Registration System
1. Create node registration scripts
2. Implement key generation and storage
3. Add contract minting functionality
4. Test node registration flow

### Step 3: Access Control Implementation
1. Create access verification middleware
2. Integrate with WireGuard authentication
3. Implement peer registry updates
4. Test access control scenarios

### Step 4: Docker Integration
1. Update WireGuard containers with contract integration
2. Create configuration management system
3. Implement dynamic peer updates
4. Test container integration

### Step 5: Testing & Documentation
1. Create comprehensive test suite
2. Document integration procedures
3. Create user guides
4. Validate end-to-end functionality

## Technical Architecture

### Smart Contract Layer
```
DstackAccessNFT (Base mainnet)
├── Node access control
├── Public key storage
├── NFT ownership management
└── Access verification
```

### DStack Integration Layer
```
DStack Instance
├── WireGuard Container
│   ├── Contract Bridge
│   ├── Access Control
│   └── Peer Registry
├── Application Container
└── Configuration Manager
```

### Network Architecture
```
┌─────────────────┐    ┌─────────────────┐
│   DStack Node A │    │   DStack Node B │
│   (NFT Owner)   │    │   (NFT Owner)   │
│                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │
│  │ WireGuard │  │    │  │ WireGuard │  │
│  │ + Contract│  │    │  │ + Contract│  │
│  │   Bridge  │  │    │  │   Bridge  │  │
│  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┘
                    │
         ┌─────────────────────┐
         │   DstackAccessNFT   │
         │   (Base Mainnet)    │
         └─────────────────────┘
```

## Success Criteria

### Functional Requirements
- ✅ NFT ownership grants VPN access to specific nodes
- ✅ Public key authentication works with contract verification
- ✅ NFT transfers automatically update access rights
- ✅ Contract revocation immediately denies VPN access
- ✅ Peer registry stays synchronized with contract state

### Technical Requirements
- ✅ Sub-second access verification latency
- ✅ Zero-downtime configuration updates
- ✅ Secure private key storage in DStack instances
- ✅ Comprehensive logging and monitoring
- ✅ Automated testing coverage >90%

### Integration Requirements
- ✅ Seamless integration with existing WireGuard setup
- ✅ Backward compatibility with current Docker configuration
- ✅ Clear documentation for developers
- ✅ Production-ready security measures

## Risk Mitigation

### Security Risks
- **Private key exposure**: Use DStack's secure key management
- **Contract vulnerabilities**: Thorough testing and audit
- **Access control bypass**: Multiple verification layers

### Technical Risks
- **Contract RPC latency**: Implement caching and fallbacks
- **Configuration drift**: Automated synchronization
- **Network failures**: Graceful degradation

### Operational Risks
- **NFT transfer complexity**: Clear user documentation
- **Contract upgrade process**: Versioned integration
- **Monitoring gaps**: Comprehensive logging

## Next Steps

1. **Immediate**: Set up contract integration environment
2. **Week 1**: Implement basic contract interaction
3. **Week 2**: Create node registration system
4. **Week 3**: Integrate with WireGuard containers
5. **Week 4**: Comprehensive testing and documentation

---

*This plan leverages the existing DstackAccessNFT contract from @rchuqiao and integrates it with our working WireGuard VPN infrastructure to create a complete NFT-based access control system for DStack nodes.* 