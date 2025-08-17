# DStack VPN Experiment

A WireGuard-based VPN system for DStack applications that enables secure, private communication between DStack instances.

## Overview

This project implements a simple WireGuard VPN system as specified in the project specification. It provides:

- **One DigitalOcean hub** (WireGuard server) in NYC
- **Three DStack spokes** as WireGuard clients that connect outbound to the hub
- **PostgreSQL cluster** runs entirely on DStack (no DB on the hub)
- **Basic firewalling** and health monitoring
- **Local backups** on each DStack spoke
- Docker Compose setup for easy local testing

## 🚀 Quick Start

### Local Development

#### Prerequisites

- Docker and Docker Compose
- WireGuard tools (for key generation)
- Linux kernel with WireGuard support (or Docker with privileged containers)

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd dstack-vpn-experiment
   ```

2. **Generate WireGuard keys**
   ```bash
   ./scripts/generate-keys.sh
   ```
   This creates:
   - `config/node-a/wg0.conf` - Node A WireGuard configuration (IP: 10.88.0.11)
   - `config/node-b/wg0.conf` - Node B WireGuard configuration (IP: 10.88.0.12)
   - `config/node-c/wg0.conf` - Node C WireGuard configuration (IP: 10.88.0.13)
   - Private and public keys for all three nodes
   - `.env.template` file with the generated keys

3. **Configure environment**
   ```bash
   cp .env.template .env
   # Edit .env and fill in:
   # - HUB_PUBLIC_IP: Your DigitalOcean hub IP
   # - HUB_PUBLIC_KEY: Your hub's WireGuard public key
   ```

4. **Start the VPN network**
   ```bash
   ./scripts/deploy-docker.sh deploy
   ```

5. **Verify connectivity**
   ```bash
   # Check container status
   ./scripts/deploy-docker.sh status
   
   # Check health
   ./scripts/deploy-docker.sh health
   
   # Test health endpoints
   curl http://localhost:8000/status  # Node A
   curl http://localhost:8001/status  # Node B
   curl http://localhost:8002/status  # Node C
   ```

## 🌐 Network Topology

```
┌─────────────────────────────────────┐
│        DigitalOcean (NYC)           │
│                                     │
│  ┌─────────────────────────────────┐ │
│  │      WireGuard Hub              │ │
│  │      (10.88.0.1)               │ │
│  │      Port 51820/UDP            │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
                    │
                    │ WireGuard UDP/51820
                    │ (outbound only)
        ┌───────────┼───────────┐
        │           │           │
┌───────▼──────┐ ┌─▼──────┐ ┌──▼──────┐
│  DStack A    │ │DStack B│ │DStack C│
│10.88.0.11   │ │10.88.0.12│ │10.88.0.13│
│Port 8000    │ │Port 8001│ │Port 8002│
└─────────────┘ └─────────┘ └─────────┘
```

## 🔐 WireGuard Configuration

### Hub Setup (DigitalOcean NYC)

The hub runs on a DigitalOcean droplet with:
- **OS**: Ubuntu 24.04 LTS
- **Resources**: 1 vCPU, 1GB RAM, 25GB SSD
- **IP**: 10.88.0.1/24
- **Port**: 51820/UDP
- **Firewall**: Allow 22/TCP (SSH) and 51820/UDP (WireGuard)

### Spoke Setup (DStack)

Each DStack spoke:
- **Connects outbound** to the hub (no inbound exposure)
- **Exposes status page** on port 8000 (read-only JSON)
- **Uses persistent keepalive** (25 seconds)
- **Routes all overlay traffic** via the hub

## 📊 Health Monitoring

Each node exposes a health endpoint at `/status` with:

```json
{
  "node": "node-a",
  "overlay_ip": "10.88.0.11",
  "wg": {
    "interface": "wg0",
    "peer_count": 1,
    "max_last_handshake_sec": 15
  },
  "disk_free_gb": 45.2,
  "time": "2025-01-06T20:00:00.000Z"
}
```

## 🛠️ Management

### Scripts

- **`./scripts/generate-keys.sh`** - Generate WireGuard keys and configs
- **`./scripts/deploy-docker.sh deploy`** - Deploy the VPN system
- **`./scripts/deploy-docker.sh status`** - Show system status
- **`./scripts/deploy-docker.sh health`** - Check system health
- **`./scripts/deploy-docker.sh cleanup`** - Clean up containers

### Environment Variables

Required in `.env`:
- `HUB_PUBLIC_IP` - DigitalOcean hub public IP
- `HUB_PUBLIC_KEY` - Hub's WireGuard public key
- `WIREGUARD_PRIVATE_KEY_A` - Node A private key
- `WIREGUARD_PRIVATE_KEY_B` - Node B private key
- `WIREGUARD_PRIVATE_KEY_C` - Node C private key

## 🔒 Security

- **Hub isolation**: Hub forwards between spokes only, cannot originate traffic
- **Spoke restrictions**: Spokes drop traffic from hub IP (10.88.0.1)
- **No external exposure**: Only status pages (8000-8002) exposed
- **Private keys**: Never transmitted, generated locally on each node

## 📝 Testing Checklist

1. ✅ Bring up hub; verify `wg0` and L3 forwarding
2. ✅ Join Spoke A/B/C; confirm handshakes and ping: `10.88.0.11 ↔ 10.88.0.12` via hub
3. ✅ Verify spokes cannot be reached from Internet directly except `:8000` status page
4. ✅ Curl each spoke: `curl http://<spoke>:8000/status` and verify JSON
5. ✅ Reboot nodes to confirm persistence

## 🚧 Future Enhancements

- **TCP fallback** for UDP-blocked networks
- **Split-horizon DNS** for overlay network
- **Offsite backups** for PostgreSQL data
- **Monitoring dashboard** with Prometheus metrics
- **Automated hub provisioning** scripts

## 📚 Documentation

- **`SPEC.md`** - Complete project specification
- **`docker-compose.yml`** - Service definitions
- **`docker/wireguard/`** - Container configuration
- **`scripts/`** - Deployment and management scripts 