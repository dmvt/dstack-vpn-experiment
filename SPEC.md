# VPN Functionality Specification for DStack Applications - V2

## Overview

This specification defines a VPN functionality system for DStack applications that enables secure, private communication between DStack instances using WireGuard. The system provides a quality-of-life improvement for developers by simplifying TLS connections and creating a private network between DStack instances, with NFT-based access control and integration with distributed database infrastructure.

## Core Concept

The VPN system serves as a developer experience improvement that:
- Simplifies connecting to different DStack nodes
- Manages TLS connections through VPN service
- Creates a private network between DStack instances
- Provides persistent peer registry and configuration management
- Enables token-gated access control via NFT ownership
- Integrates with distributed PostgreSQL for timeline data storage

## Technology Choice

**WireGuard** has been selected as the VPN solution based on:
- Works well in Docker containers
- Lightweight configuration
- 5+ years of production experience from team members
- UDP-based protocol (with TCP tunneling support via Mullvad UDP-to-TCP proxy)

## MVP Scope (Super Simple)

The MVP focuses on proving basic connectivity works with minimal complexity:

### MVP Requirements
- Two DStack instances connecting to VPN
- One instance runs nginx server, other runs client
- Simple hello world web page accessible over VPN
- Prove basic connectivity works
- Keep it really straightforward - no complicated features
- Basic NFT-based access control demonstration

### Success Criteria
- Can access web page from one DStack instance to another via VPN
- VPN configuration persists across machine restarts/migrations
- Basic peer registry functionality works
- NFT ownership grants VPN access
- Mullvad UDP-to-TCP proxy handles tunneling

## System Architecture

### High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   DStack Node A │    │   DStack Node B │
│                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │
│  │ WireGuard │  │    │  │ WireGuard │  │
│  │ Container │  │    │  │ Container │  │
│  └───────────┘  │    │  └───────────┘  │
│                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │
│  │   nginx   │  │    │  │  Website  │  │
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
                    │
         ┌─────────────────────┐
         │   NFT Access        │
         │   Control           │
         └─────────────────────┘
```

### Components

1. **WireGuard Containers**: Run in each DStack instance
2. **Peer Registry**: Contract-managed configuration store
3. **NFT Access Control**: Token-gated VPN access
4. **Mullvad UDP-to-TCP Proxy**: Handles UDP tunneling over TCP
5. **DStack Integration**: Host environment, contract based deployment
6. **Docker Networking**: Container-to-container communication

## Technical Requirements

> **⚠️ Implementation Note**: The technical complexity of integrating WireGuard with smart contract keys should be investigated by the implementor to find the least complex approach. What follows below is a best guess but should not be treated as a set-in-stone specification.

### 1. Configuration Management

#### Persistent Peer Registry
- Store public keys and IP addresses for each node
- Contract-managed configuration using DStack's contracts
- Each node gets its own WireGuard key pair
- Keys must persist beyond machine up/down or migration
- Integration with existing DStack infrastructure

#### NFT-Based Access Control
- NFT ownership grants VPN access rights
- Smart contract maps Ethereum address to WireGuard public key
- Transfer of NFT revokes access from previous owner
- Signed messages with WireGuard public key for authentication
- ENS integration for public key management

#### Configuration Structure
```json
{
  "peers": [
    {
      "node_id": "node_a",
      "public_key": "base64_encoded_wireguard_public_key",
      "ip_address": "10.0.0.1",
      "hostname": "node-a.vpn.dstack",
      "instance_id": "dstack_instance_id",
      "nft_owner": "0x1234...",
      "access_granted": true
    }
  ],
  "network": {
    "cidr": "10.0.0.0/24",
    "dns_server": "10.0.0.1"
  },
  "nft_contract": "0x5678...",
  "access_control": {
    "enabled": true,
    "nft_required": true
  }
}
```

### 2. Docker Integration

#### Container Setup
- WireGuard runs in dedicated container per DStack instance
- Mullvad UDP-to-TCP proxy for tunneling support
- Handle UDP/TCP tunneling considerations
- Container networking setup with bridge mode

#### Mullvad UDP-to-TCP Proxy
- Use existing Mullvad UDP-to-TCP tool for compatibility
- Support both directions (UDP-to-TCP and TCP-to-UDP)
- Integration with DStack DevNet tunnel functionality
- Fallback to socat if Mullvad tool unavailable

### 3. Network Architecture

#### IP Address Management
- Private IP range: 10.0.0.0/24
- Each DStack instance gets unique IP from range
- Hostname resolution within VPN network
- DNS server running on primary node

#### WireGuard Configuration
```ini
[Interface]
PrivateKey = <base64_private_key>
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <peer_public_key>
AllowedIPs = 10.0.0.2/32
Endpoint = <peer_endpoint>:51820
PersistentKeepalive = 25
```


## Stretch Goal: Distributed PostgreSQL with Patroni

### Overview
This stretch goal replaces the simple nginx/website architecture with a distributed PostgreSQL cluster using Patroni for high availability. The system would consist of 3 DStack instances with one acting as the leader, demonstrating fault tolerance by continuing operation when the leader node is taken offline.

### Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DStack Node A │    │   DStack Node B │    │   DStack Node C │
│   (Leader)      │    │   (Replica)     │    │   (Replica)     │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ WireGuard │  │    │  │ WireGuard │  │    │  │ WireGuard │  │
│  │ Container │  │    │  │ Container │  │    │  │ Container │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │ PostgreSQL│  │    │  │ PostgreSQL│  │    │  │ PostgreSQL│  │
│  │ + Patroni │  │    │  │ + Patroni │  │    │  │ + Patroni │  │
│  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
         ┌─────────────────────┐
         │   Peer Registry     │
         │   (Contract)        │
         └─────────────────────┘
                                 │
         ┌─────────────────────┐
         │   NFT Access        │
         │   Control           │
         └─────────────────────┘
```

### Success Criteria
- **Global Test**: System continues operating when leader node is taken offline
- Automatic failover to one of the replica nodes
- Data consistency maintained across the cluster
- VPN connectivity preserved during failover

### Implementation Reference
This stretch goal should be implemented using the patterns and examples from the [dstack-examples database branch](https://github.com/amiller/dstack-examples/tree/database), which provides working examples of distributed database implementations on DStack.

### Technical Requirements
- Use Patroni for leader election and failover
- Zookeeper or ETCD for coordination
- Timeline data storage for TEE-collected information
- Row-level security and user management
- VPN-secured network isolation

### Database Architecture
```yaml
# Patroni configuration
scope: dstack-vpn
namespace: /dstack/
name: node-1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.0.0.1:8008

etcd:
  host: 10.0.0.1:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 100
        shared_buffers: 256MB
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_segments: 8
```

## Implementation Roadmap

### Phase 1 (MVP)
1. **Basic WireGuard Setup**
   - Set up WireGuard containers in Docker
   - Configure basic peer-to-peer connection
   - Test connectivity between two local instances
   - Integrate Mullvad UDP-to-TCP proxy

2. **DStack Integration**
   - VPN peer registry
   - Implement key generation and management
   - Basic configuration distribution
   - NFT access control smart contract

3. **Simple Demo**
   - Deploy nginx and simple web server
   - Prove VPN connectivity works
   - Demonstrate NFT-based access control
   - Document basic usage

### Phase 2: Production Features
1. **Enhanced Configuration Management**
   - Automated key rotation
   - Dynamic peer discovery
   - Health monitoring
   - NFT transfer handling

2. **Security Enhancements**
   - Access control through IP assignment
   - Audit logging
   - Security incident triage capabilities
   - ENS integration for public keys

3. **Developer Experience**
   - CLI tools for VPN management
   - Integration with DStack CLI
   - Documentation and examples
   - NFT minting and distribution tools

### Phase 3: Advanced Features (Optional)
1. **Enhanced Monitoring**
   - Health monitoring and alerting
   - Performance optimization
   - Multi-region deployment considerations
   - Load balancing strategies

2. **Developer Experience**
   - CLI tools for VPN management
   - Integration with DStack CLI
   - Documentation and examples
   - NFT minting and distribution tools

## Technical Considerations

### UDP vs TCP Tunneling
- WireGuard uses UDP by default
- Mullvad UDP-to-TCP proxy for compatibility

### Key Management
- Each node generates unique WireGuard key pair
- Public keys stored in contract-managed registry
- Private keys stored securely in DStack instance
- Keys persist across machine restarts/migrations
- NFT ownership controls access to key registration

### Network Addressing
- Private IP range: 10.0.0.0/24
- Each instance gets unique IP from range
- Hostname resolution: `node-{id}.vpn.dstack`
- DNS server for internal name resolution

### Security Model
- IP-based access control
- Public key authentication
- NFT-based authorization
- No shared secrets between peers
- Contract-managed peer registry ensures authenticity

### Smart Contract Integration
```solidity
// Simplified NFT access control contract
contract VPNAccessControl {
    mapping(uint256 => address) public tokenOwner;
    mapping(address => bytes32) public wireguardKeys;
    mapping(address => bool) public hasAccess;
    
    function registerKey(bytes32 publicKey) external {
        require(hasAccess[msg.sender], "No access");
        wireguardKeys[msg.sender] = publicKey;
    }
    
    function grantAccess(uint256 tokenId, address user) external {
        require(tokenOwner[tokenId] == msg.sender, "Not owner");
        hasAccess[user] = true;
    }
    
    function revokeAccess(address user) external {
        hasAccess[user] = false;
        delete wireguardKeys[user];
    }
}
```

## Future Use Cases (Not MVP)

### End User Access
- End user access with assigned IP addresses
- Lateral movement prevention
- Additional security layer beyond TLS
- Timeline data collection and storage

### Database Services
- Shared DStack database service
- Phala-hosted distributed PostgreSQL
- Multi-tenant database isolation
- Automated backup and recovery

## Monitoring and Observability

### Metrics
- VPN connection status
- Peer connectivity health
- Network throughput
- Configuration sync status
- NFT access control events

### Logging
- WireGuard connection logs
- Configuration changes
- Security events
- Performance metrics

## Documentation Requirements

### Developer Documentation
- Setup and installation guide
- Configuration reference
- Troubleshooting guide
- API documentation
- NFT integration guide

### User Documentation
- VPN client setup
- Network access guide
- Security best practices
- FAQ and common issues

## Risk Assessment

### Technical Risks
- **UDP tunneling complexity**: Mitigated by Mullvad UDP-to-TCP proxy
- **Key management**: Mitigated by contract-based registry
- **Network conflicts**: Mitigated by private IP range

### Security Risks
- **Key compromise**: Mitigated by per-node keys and rotation
- **Configuration tampering**: Mitigated by contract-based registry
- **Network isolation**: Mitigated by IP-based access control
- **NFT theft**: Mitigated by transfer restrictions and monitoring

### Operational Risks
- **Dependency on external tools**: Mitigated by multiple fallback options
- **Smart contract bugs**: Mitigated by thorough testing and audits
- **Database failure**: Mitigated by Patroni failover mechanisms

## Conclusion

This V2 VPN functionality specification provides a comprehensive foundation for secure, private communication between DStack instances with NFT-based access control and distributed database integration. The MVP approach ensures we can prove the concept works before adding complexity, while the roadmap provides a clear path for future enhancements.

The system leverages existing DStack infrastructure, WireGuard's proven technology, and blockchain-based access control to deliver a developer-friendly VPN solution that enhances security, simplifies networking between DStack instances, and provides a foundation for distributed data storage.

Key improvements in V2:
- NFT-based access control for VPN membership
- Mullvad UDP-to-TCP proxy for improved tunneling
- Smart contract integration for key management
- Enhanced security model with token-gated access 