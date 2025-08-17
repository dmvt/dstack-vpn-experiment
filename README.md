# DStack VPN Experiment

A WireGuard-based VPN system for DStack applications that enables secure, private communication between DStack instances.

## Overview

This project implements a simple WireGuard VPN system as specified in the project specification. It provides:

- **One DigitalOcean hub** (WireGuard server) in NYC
- **Three DStack spokes** as WireGuard clients that connect outbound to the hub
- **PostgreSQL cluster** runs entirely on DStack (no DB on the hub)
- **Basic firewalling** and health monitoring
- **Local backups** on each DStack spoke
- **Single-command deployment** with zero configuration files

## 🚀 Quick Start

### Prerequisites

**The CLI tool automatically handles all prerequisites!** No manual installation needed.

**What gets installed automatically:**
- **doctl CLI tool** (DigitalOcean) - Auto-detects OS and installs appropriate version
- **phala CLI tool** (Phala Cloud) - Installs via npm or uses npx
- **SSH key** - Generates secure RSA key pair automatically
- **Authentication** - Interactive setup for API tokens

**Manual setup (if preferred):**
```bash
# macOS
brew install doctl node

# Linux
# doctl: Download from https://github.com/digitalocean/doctl/releases
# node: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs

# Then authenticate
doctl auth init
npm install -g phala && phala auth login [your-api-key]
```

### Setup and Deploy VPN

**First time setup (automatic prerequisites):**
```bash
# Run the interactive setup wizard
./scripts/deploy-vpn.sh setup
```

**Deploy VPN (after setup):**
```bash
# Deploy with defaults (NYC region, 1GB droplet, 3 nodes)
./scripts/deploy-vpn.sh deploy

# Deploy with custom configuration
./scripts/deploy-vpn.sh deploy --region sfo3 --size s-2vcpu-2gb --nodes 5

# Dry run to see what would be deployed
./scripts/deploy-vpn.sh deploy --dry-run
```

### Manage VPN

```bash
# Check VPN status
./scripts/deploy-vpn.sh status

# Test connectivity
./scripts/deploy-vpn.sh test

# Destroy everything
./scripts/deploy-vpn.sh destroy --force

# Show help
./scripts/deploy-vpn.sh help
```

## 🌐 Network Topology

```
┌──────────────────────────────────────┐
│        DigitalOcean (NYC)            │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │      WireGuard Hub              │ │
│  │      (10.88.0.1)                │ │
│  │      Port 51820/UDP             │ │
│  └─────────────────────────────────┘ │
└──────────────────────────────────────┘
                    │
                    │ WireGuard UDP/51820
                    │ (outbound only)
        ┌───────────┼─────────────┐
        │           │             │
┌───────▼───┐ ┌─────▼────┐ ┌──────▼───┐
│  DStack A │ │DStack B  │ │DStack C  │
│10.88.0.11 │ │10.88.0.12│ │10.88.0.13│
└───────────┘ └──────────┘ └──────────┘
```

## 🔐 WireGuard Configuration

### Hub Setup (DigitalOcean)

The hub runs on a DigitalOcean droplet with:
- **OS**: Ubuntu 24.04 LTS
- **Resources**: Configurable (default: 1 vCPU, 1GB RAM)
- **IP**: 10.88.0.1/24
- **Port**: 51820/UDP (configurable)
- **Firewall**: Allow 22/TCP (SSH) and WireGuard port

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
  "node": "node-1",
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

## 🛠️ CLI Interface

### Commands

| Command | Description | Example |
|---------|-------------|---------|
| `setup` | Interactive setup wizard | `./deploy-vpn.sh setup` |
| `deploy` | Deploy VPN infrastructure | `./deploy-vpn.sh deploy` |
| `status` | Show VPN status | `./deploy-vpn.sh status` |
| `test` | Test connectivity | `./deploy-vpn.sh test` |
| `destroy` | Remove infrastructure | `./deploy-vpn.sh destroy --force` |
| `help` | Show help | `./deploy-vpn.sh help` |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--region` | DigitalOcean region | `nyc1` |
| `--size` | Droplet size | `s-1vcpu-1gb` |
| `--nodes` | Number of DStack nodes | `3` |
| `--network` | WireGuard network | `10.88.0.0/24` |
| `--port` | WireGuard port | `51820` |
| `--dry-run` | Show plan without executing | `false` |
| `--force` | Skip confirmation prompts | `false` |

### Examples

```bash
# First time setup
./scripts/deploy-vpn.sh setup

# Deploy with defaults
./scripts/deploy-vpn.sh deploy

# Deploy in San Francisco with larger droplet
./scripts/deploy-vpn.sh deploy --region sfo3 --size s-2vcpu-2gb

# Deploy with 5 DStack nodes
./scripts/deploy-vpn.sh deploy --nodes 5

# Deploy with custom network
./scripts/deploy-vpn.sh deploy --network 192.168.100.0/24

# Check what would be deployed
./scripts/deploy-vpn.sh deploy --dry-run

# Force destroy without prompts
./scripts/deploy-vpn.sh destroy --force
```

## 🔒 Security Features

- **Dynamic key generation** - Fresh keys for every deployment
- **Automatic IP discovery** - No manual configuration needed
- **Hub isolation** - Hub forwards between spokes only
- **Spoke restrictions** - Spokes drop traffic from hub IP
- **No external exposure** - Only status pages (8000) exposed
- **Secure key handling** - Keys generated and used immediately

## 📝 What Happens Automatically

### Setup Phase
1. **Prerequisites installed** - doctl, phala CLI tools, Node.js if needed
2. **SSH key generated** - Secure RSA key pair created automatically
3. **Authentication configured** - Interactive API token setup
4. **System requirements** - Disk space, memory, network connectivity verified

### Deployment Phase
5. **WireGuard keys generated** and stored securely
6. **DigitalOcean hub created** with discovered IP
7. **DStack nodes created** with discovered IPs
8. **Configurations generated** with real IPs
9. **VPN deployed** and tested
10. **Status monitoring** configured
11. **Runtime config** generated for reference

## 🚧 Advanced Features

### Customization

- **Variable node count** - Deploy 1-10+ nodes
- **Multiple regions** - Deploy in any DigitalOcean region
- **Custom network ranges** - Use any private IP range
- **Different droplet sizes** - Scale based on needs

### Monitoring

- **Real-time status** - Check VPN health anytime
- **Connectivity testing** - Verify inter-node communication
- **Status endpoints** - JSON health data on port 8000
- **Logging** - Comprehensive deployment logs

## 📚 Documentation

- **`SPEC.md`** - Complete project specification
- **`docker-compose.yml`** - Local development setup
- **`docker/status-service/`** - Health monitoring service
- **`scripts/deploy-vpn.sh`** - Single deployment script
- **`tool-reports/`** - Implementation documentation

## 🎯 Key Benefits

- **Zero configuration files** - No .env files needed
- **Single command deployment** - Complete automation
- **Dynamic everything** - Keys, IPs, configs generated automatically
- **Professional CLI** - Enterprise-grade deployment interface
- **Reproducible** - Consistent deployments every time
- **Secure** - Fresh keys, no secrets in files
- **Scalable** - Easy to add/remove nodes

## 🚀 Next Steps

1. **Run the setup wizard**: `./scripts/deploy-vpn.sh setup`
2. **Deploy your VPN**: `./scripts/deploy-vpn.sh deploy`
3. **Configure PostgreSQL** on the DStack nodes
4. **Set up monitoring** and alerting
5. **Customize network** configuration if needed
6. **Scale up/down** based on requirements 