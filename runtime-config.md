# DStack VPN Runtime Configuration

**Generated:** Sun Aug 17 15:46:47 EDT 2025
**Status:** Active

## Network Configuration
- **WireGuard Network**: 10.88.0.0/24
- **Hub IP**: 10.88.0.1
- **WireGuard Port**: 51820

## Infrastructure
- **DigitalOcean Hub**: 159.89.48.29
- **DStack Nodes**:        2 nodes

## Status Endpoints
- **Hub Status**: ssh root@159.89.48.29 'vpn-status'
- **Node Status**: Check individual node IPs

## WireGuard Commands
- **Hub Status**: ssh root@159.89.48.29 'wg show'
- **Node Status**: ssh root@<NODE_IP> 'wg show'

## VPN Testing
- **Test connectivity**: ./deploy-vpn.sh test
- **Check status**: ./deploy-vpn.sh status

## PostgreSQL Cluster Configuration

Generated: Sun Aug 17 15:47:40 EDT 2025

### Credentials
- **Database**: dstack
- **User**: postgres
- **Password**: dcj5lmu1Dry8O3LaNBrMekmtx
- **Replication Password**: YpMDe2gAF31pf5cVKz9QRMGOl

### Nodes
- **Primary**: 10.88.0.11:5432
- **Replica 1**: 10.88.0.12:5432
- **Replica 2**: 10.88.0.13:5432

### Connection String
```
postgresql://postgres:dcj5lmu1Dry8O3LaNBrMekmtx@10.88.0.11:5432/dstack
```

### Access from Hub
```bash
ssh root@159.89.48.29
psql -h 10.88.0.11 -U postgres -d dstack
```
