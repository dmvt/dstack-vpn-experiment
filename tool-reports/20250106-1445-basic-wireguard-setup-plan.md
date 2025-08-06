# Basic WireGuard Setup - Implementation Plan

**Date:** 2025-01-06 14:45  
**Task:** Phase 1, Step 1 - Basic WireGuard Setup  
**Branch:** feature/basic-wireguard-setup  

## Task Overview

Implement the foundational WireGuard VPN setup for the DStack VPN experiment. This is the first step in the MVP that will enable basic peer-to-peer connectivity between DStack instances.

## Mini-Spec

### Requirements
- Set up WireGuard containers in Docker
- Configure basic peer-to-peer connection between two nodes
- Test connectivity between two local instances
- Integrate Mullvad UDP-to-TCP proxy for tunneling support
- Create Docker Compose setup for easy local testing

### Success Criteria
- Two WireGuard containers can establish a VPN connection
- Containers can ping each other over the VPN network
- Basic network isolation and routing works
- Mullvad proxy handles UDP-to-TCP tunneling
- Configuration is persistent and restartable

## Implementation Plan

### 1. Project Structure
```
dstack-vpn-experiment/
├── docker/
│   ├── wireguard/
│   │   ├── Dockerfile
│   │   ├── wg0.conf.template
│   │   └── entrypoint.sh
│   └── mullvad-proxy/
│       └── Dockerfile
├── config/
│   ├── node-a/
│   │   └── wg0.conf
│   └── node-b/
│       └── wg0.conf
├── docker-compose.yml
├── scripts/
│   ├── generate-keys.sh
│   └── setup-network.sh
└── README.md
```

### 2. Key Components

#### WireGuard Container
- Alpine Linux base image for minimal footprint
- WireGuard kernel module and tools
- Custom entrypoint script for configuration
- Network namespace setup for isolation

#### Mullvad UDP-to-TCP Proxy
- Standalone container for tunneling
- UDP-to-TCP and TCP-to-UDP support
- Integration with WireGuard containers

#### Configuration Management
- Template-based WireGuard configs
- Key generation scripts
- IP address assignment (10.0.0.1, 10.0.0.2)
- Network CIDR: 10.0.0.0/24

### 3. Pseudocode for Key Logic

#### Key Generation Script
```bash
# Generate WireGuard key pair
wg genkey | tee privatekey | wg pubkey > publickey
# Store keys in config directory
# Update WireGuard config template
```

#### WireGuard Configuration Template
```ini
[Interface]
PrivateKey = {{PRIVATE_KEY}}
Address = {{IP_ADDRESS}}/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = {{PEER_PUBLIC_KEY}}
AllowedIPs = {{PEER_IP}}/32
Endpoint = {{PEER_ENDPOINT}}:51820
PersistentKeepalive = 25
```

#### Docker Compose Network Setup
```yaml
networks:
  vpn-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
  wireguard-network:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.0.0/24
```

### 4. Testing Strategy

#### Local Testing
1. Start two WireGuard containers
2. Verify containers can ping each other
3. Test Mullvad proxy connectivity
4. Verify network isolation
5. Test container restart persistence

#### Integration Testing
1. Deploy nginx container on one node
2. Deploy client container on other node
3. Verify HTTP connectivity over VPN
4. Test network performance

### 5. Files to Create

1. **docker/wireguard/Dockerfile** - WireGuard container image
2. **docker/wireguard/entrypoint.sh** - Container startup script
3. **docker/wireguard/wg0.conf.template** - Configuration template
4. **docker/mullvad-proxy/Dockerfile** - Mullvad proxy container
5. **scripts/generate-keys.sh** - Key generation utility
6. **scripts/setup-network.sh** - Network setup script
7. **docker-compose.yml** - Local development setup
8. **config/node-a/wg0.conf** - Node A configuration
9. **config/node-b/wg0.conf** - Node B configuration
10. **README.md** - Setup and usage instructions

### 6. Implementation Order

1. Create Docker images and configurations
2. Implement key generation scripts
3. Set up Docker Compose for local testing
4. Test basic connectivity
5. Integrate Mullvad proxy
6. Document setup process
7. Create comprehensive README

## Risk Mitigation

- **Network conflicts**: Use isolated Docker networks
- **Key management**: Store keys securely in config files
- **Container networking**: Use bridge mode for proper isolation
- **UDP tunneling**: Mullvad proxy handles compatibility

## Next Steps

After completing this task:
1. Commit all changes with descriptive messages
2. Test the setup thoroughly
3. Document any issues or improvements needed
4. Move to Phase 1, Step 2: DStack Integration 