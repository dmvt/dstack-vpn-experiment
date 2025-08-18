# DStack VPN Runtime Configuration

**Generated:** Sun Aug 17 16:17:24 EDT 2025
**Status:** Active

## Network Configuration
- **WireGuard Network**: 10.88.0.0/24
- **Hub IP**: 10.88.0.1
- **WireGuard Port**: 51820

## Infrastructure
- **DigitalOcean Hub**: 142.93.197.13
- **DStack Nodes**:        2 nodes

## Status Endpoints
- **Hub Status**: ssh root@142.93.197.13 'vpn-status'
- **Node Status**: Check individual node IPs

## WireGuard Commands
- **Hub Status**: ssh root@142.93.197.13 'wg show'
- **Node Status**: ssh root@<NODE_IP> 'wg show'

## VPN Testing
- **Test connectivity**: ./deploy-vpn.sh test
- **Check status**: ./deploy-vpn.sh status

## PostgreSQL Cluster Configuration (Patroni + etcd)

Generated: Sun Aug 17 16:17:34 EDT 2025

### Credentials
- **Database**: dstack
- **User**: postgres
- **Password**: wMmMnB2AUuG1dHY0HRlVCsDjH
- **Replication Password**: t9CuwUvg7XA9fCAU8e2tixgar

### Architecture
- **Orchestration**: Patroni with etcd
- **Primary**: 10.88.0.11:5432 (auto-elected)
- **Replicas**: 10.88.0.12:5432, 10.88.0.13:5432
- **Coordination**: etcd on hub (2379, 2380)
- **Patroni API**: 8008 on each node

### Connection String
```
postgresql://postgres:wMmMnB2AUuG1dHY0HRlVCsDjH@10.88.0.11:5432/dstack
```

### Management Commands
```bash
# Check cluster status
patronictl -c /etc/patroni.yml list

# Check Patroni API
curl http://10.88.0.11:8008/cluster

# Access from hub
ssh root@142.93.197.13
psql -h 10.88.0.11 -U postgres -d dstack
```

### Environment Variables for docker-compose
```
POSTGRES_PASSWORD=wMmMnB2AUuG1dHY0HRlVCsDjH
POSTGRES_REPLICATION_PASSWORD=t9CuwUvg7XA9fCAU8e2tixgar
```
