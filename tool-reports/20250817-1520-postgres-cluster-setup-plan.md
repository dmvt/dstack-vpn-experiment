# PostgreSQL Cluster Setup Plan for DStack VPN

**Date:** 2025-08-17 15:20  
**Task:** PostgreSQL Cluster Setup on DStack Nodes  
**Target:** Deploy PostgreSQL primary + replicas on WireGuard overlay

## Implementation Plan

### 1. Architecture Overview
- **Primary**: Node A (10.88.0.11)
- **Replica 1**: Node B (10.88.0.12)  
- **Replica 2**: Node C (10.88.0.13)
- **Replication**: Streaming replication over WireGuard overlay
- **Backups**: Local pgBackRest on each node

### 2. Components to Implement

#### 2.1 PostgreSQL Docker Image
- Base: postgres:16-alpine
- Include pgBackRest for backups
- Custom entrypoint for primary/replica detection
- Health check script

#### 2.2 Configuration Templates
- postgresql.conf for primary
- postgresql.conf for replicas
- pg_hba.conf for replication access
- pgBackRest configuration

#### 2.3 Deployment Integration
- Extend deploy-vpn.sh with postgres subcommand
- Auto-detect node roles based on IP
- Configure streaming replication
- Initialize backup repositories

#### 2.4 Status Service Extension
- Add PostgreSQL role (primary/replica)
- Add replication lag metrics
- Add backup status
- Add database connection count

### 3. Implementation Steps

1. Create PostgreSQL Docker configurations
2. Add postgres deployment to docker-compose.yml
3. Create initialization scripts
4. Extend deployment script
5. Update status service
6. Test replication and failover

### 4. Mini-Spec

#### PostgreSQL Container
```yaml
Service: postgres
Image: custom postgres:16-alpine with pgBackRest
Ports: 5432 (overlay network only)
Environment:
  - POSTGRES_REPLICATION_MODE (primary/replica)
  - POSTGRES_PRIMARY_HOST (10.88.0.11)
  - POSTGRES_OVERLAY_IP (node-specific)
Volumes:
  - /data/postgres:/var/lib/postgresql/data
  - /data/backups:/var/lib/pgbackrest
```

#### Deployment Flow
```
deploy-vpn.sh postgres deploy
├── Detect existing VPN
├── Generate postgres passwords
├── Deploy primary on 10.88.0.11
├── Wait for primary ready
├── Deploy replicas on .12/.13
├── Verify replication
└── Initialize backup repos
```

### 5. Pseudocode

```bash
# PostgreSQL deployment function
deploy_postgres() {
    # Check VPN exists
    if ! check_vpn_status(); then
        error "VPN not deployed"
    fi
    
    # Generate credentials
    POSTGRES_PASSWORD=$(generate_password)
    REPLICATION_PASSWORD=$(generate_password)
    
    # Deploy primary
    deploy_postgres_primary "10.88.0.11" "$POSTGRES_PASSWORD" "$REPLICATION_PASSWORD"
    
    # Wait for primary
    wait_for_postgres "10.88.0.11"
    
    # Deploy replicas
    for ip in "10.88.0.12" "10.88.0.13"; do
        deploy_postgres_replica "$ip" "$REPLICATION_PASSWORD"
    done
    
    # Verify cluster
    verify_postgres_cluster
}

# Docker entrypoint logic
postgres_entrypoint() {
    if [[ "$POSTGRES_REPLICATION_MODE" == "primary" ]]; then
        setup_primary
        configure_replication_slots
        initialize_backup_repo
    else
        setup_replica
        configure_streaming_replication
        wait_for_primary
    fi
    
    exec postgres
}

# Status service extension
get_postgres_status() {
    role=$(psql -At -c "SELECT pg_is_in_recovery()")
    if [[ "$role" == "f" ]]; then
        echo "primary"
        get_replication_status
    else
        echo "replica"
        get_replication_lag
    fi
    
    get_backup_status
    get_connection_count
}
```

## Expected Outcomes

1. **PostgreSQL cluster** running on overlay network
2. **Automatic failover** capability (manual promotion)
3. **Local backups** on each node
4. **Status monitoring** integrated
5. **Zero manual configuration** required

## Testing Strategy

1. Deploy PostgreSQL cluster
2. Create test database and tables
3. Verify replication is working
4. Test backup and restore
5. Simulate primary failure
6. Verify monitoring endpoints
