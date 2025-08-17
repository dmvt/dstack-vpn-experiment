# DStack VPN Runtime Configuration

**Generated:** Sun Aug 17 14:46:45 EDT 2025
**Status:** Active

## Network Configuration
- **WireGuard Network**: 10.88.0.0/24
- **Hub IP**: 10.88.0.1
- **WireGuard Port**: 51820

## Infrastructure
- **DigitalOcean Hub**: 143.244.171.208
- **DStack Nodes**:        2 nodes

## Status Endpoints
- **Hub Status**: ssh root@143.244.171.208 'vpn-status'
- **Node Status**: Check individual node IPs

## WireGuard Commands
- **Hub Status**: ssh root@143.244.171.208 'wg show'
- **Node Status**: ssh root@<NODE_IP> 'wg show'

## VPN Testing
- **Test connectivity**: ./deploy-vpn.sh test
- **Check status**: ./deploy-vpn.sh status
