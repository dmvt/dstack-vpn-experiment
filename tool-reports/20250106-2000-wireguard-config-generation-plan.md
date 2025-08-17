# WireGuard Configuration Generation and Hub Provisioning Plan

**Date:** 2025-01-06 20:00  
**Task:** Implement WireGuard configuration generation and hub provisioning scripts  
**Priority:** High (foundational for VPN functionality)

## Current State Analysis

The project has:
- ✅ Docker Compose setup with 3 WireGuard nodes
- ✅ Container infrastructure and health checking
- ✅ Key generation scripts
- ❌ **Missing:** WireGuard configuration files (config/ directory empty)
- ❌ **Missing:** Hub provisioning scripts for DigitalOcean
- ❌ **Missing:** Status service implementation
- ❌ **Missing:** Firewall configuration

## Implementation Plan

### Phase 1: WireGuard Configuration Generation
1. **Enhance key generation script** to create proper WireGuard configs
2. **Generate hub configuration** (`wg0.conf`) with L3 forwarding
3. **Generate spoke configurations** for all three nodes
4. **Create config validation** to ensure proper IP addressing

### Phase 2: Hub Provisioning Scripts
1. **DigitalOcean hub setup script** with Ubuntu 24.04 LTS
2. **WireGuard server installation** and configuration
3. **Firewall setup** (nftables) with proper rules
4. **L3 forwarding configuration** for inter-spoke routing

### Phase 3: Status Service Implementation
1. **Go binary** for status monitoring (as specified in spec)
2. **Systemd service** configuration
3. **Health endpoints** for each spoke

## Mini-Spec: WireGuard Configuration

### Hub Configuration (`/etc/wireguard/wg0.conf`)
```ini
[Interface]
Address = 10.88.0.1/24
ListenPort = 51820
PrivateKey = <hub_private_key>
PostUp = sysctl -w net.ipv4.ip_forward=1; \
        iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT; \
        iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
PostDown = sysctl -w net.ipv4.ip_forward=0; \
          iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT; \
          iptables -D FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

[Peer]
# Spoke A
PublicKey = <spokeA_public_key>
AllowedIPs = 10.88.0.11/32
PersistentKeepalive = 25

[Peer]
# Spoke B
PublicKey = <spokeB_public_key>
AllowedIPs = 10.88.0.12/32
PersistentKeepalive = 25

[Peer]
# Spoke C
PublicKey = <spokeC_public_key>
AllowedIPs = 10.88.0.13/32
PersistentKeepalive = 25
```

### Spoke Configuration (example for Node A)
```ini
[Interface]
Address = 10.88.0.11/32
PrivateKey = <spokeA_private_key>

[Peer]
# Hub (NYC)
PublicKey = <hub_public_key>
Endpoint = <hub_public_ip>:51820
AllowedIPs = 10.88.0.0/24
PersistentKeepalive = 25
```

## Pseudocode for Key Components

### 1. Enhanced Key Generation Script
```bash
#!/bin/bash
# generate-keys.sh enhancement

# Generate hub keys
wg genkey | tee config/hub/server.key | wg pubkey > config/hub/server.pub

# Generate spoke keys
for node in a b c; do
  wg genkey | tee config/node-${node}/spoke${node}.key | wg pubkey > config/node-${node}/spoke${node}.pub
done

# Generate WireGuard configs
generate_hub_config
generate_spoke_configs
validate_configs
```

### 2. Hub Provisioning Script
```bash
#!/bin/bash
# provision-hub.sh

# Install dependencies
apt update && apt install -y wireguard qrencode nftables

# Configure WireGuard
setup_wireguard_interface
configure_firewall
enable_services

# Test configuration
test_vpn_connectivity
```

### 3. Status Service (Go)
```go
// status.go - as specified in SPEC.md Appendix A
package main

func main() {
  // HTTP server on :8000
  // /status endpoint with JSON response
  // WireGuard peer monitoring
  // Disk space monitoring
}
```

## Success Criteria

1. **WireGuard configs generated** and placed in `config/` directory
2. **Hub provisioning script** creates working DigitalOcean droplet
3. **Status service** responds on each spoke's port 8000
4. **VPN connectivity** established between all nodes
5. **Firewall rules** properly isolate traffic as specified

## Files to Create/Modify

- `config/hub/wg0.conf` - Hub WireGuard configuration
- `config/node-a/wg0.conf` - Node A configuration  
- `config/node-b/wg0.conf` - Node B configuration
- `config/node-c/wg0.conf` - Node C configuration
- `scripts/provision-hub.sh` - DigitalOcean hub setup
- `scripts/setup-firewall.sh` - Firewall configuration
- `docker/status-service/` - Status service implementation
- `docker/status-service/Dockerfile` - Status service container
- `docker/status-service/status.go` - Go status service

## Next Steps

1. Implement WireGuard configuration generation
2. Create hub provisioning scripts
3. Implement status service
4. Test end-to-end VPN connectivity
5. Document deployment process
