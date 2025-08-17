#!/bin/bash
set -e

# Function to determine node role based on IP
determine_role() {
    local overlay_ip=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' || echo "")
    
    if [[ "$overlay_ip" == "10.88.0.11" ]]; then
        echo "primary"
    elif [[ "$overlay_ip" == "10.88.0.12" ]] || [[ "$overlay_ip" == "10.88.0.13" ]]; then
        echo "replica"
    else
        echo "unknown"
    fi
}

# Function to wait for etcd
wait_for_etcd() {
    local etcd_host="${ETCD_HOST:-10.88.0.1}"
    echo "Waiting for etcd at $etcd_host..."
    
    # Wait for WireGuard interface to be ready
    while ! ip link show wg0 &>/dev/null; do
        echo "Waiting for WireGuard interface..."
        sleep 2
    done
    
    until curl -s "http://$etcd_host:2379/health" | grep -q "true"; do
        echo "etcd not ready, waiting..."
        sleep 2
    done
    echo "etcd is ready"
}

# Function to initialize cluster
initialize_cluster() {
    echo "Initializing Patroni cluster..."
    
    # Create pgpass file
    cat > /tmp/pgpass << EOF
localhost:5432:*:postgres:${POSTGRES_PASSWORD}
localhost:5432:*:replicator:${POSTGRES_REPLICATION_PASSWORD}
EOF
    chmod 600 /tmp/pgpass
    
    # Start Patroni
    exec patroni /etc/patroni.yml
}

# Function to join cluster
join_cluster() {
    echo "Joining existing Patroni cluster..."
    
    # Create pgpass file
    cat > /tmp/pgpass << EOF
localhost:5432:*:postgres:${POSTGRES_PASSWORD}
localhost:5432:*:replicator:${POSTGRES_REPLICATION_PASSWORD}
EOF
    chmod 600 /tmp/pgpass
    
    # Start Patroni
    exec patroni /etc/patroni.yml
}

# Main execution
main() {
    # Wait for WireGuard interface
    echo "Waiting for WireGuard interface..."
    timeout=30
    while [[ $timeout -gt 0 ]] && ! ip link show wg0 &>/dev/null; do
        sleep 1
        ((timeout--))
    done
    
    if [[ $timeout -eq 0 ]]; then
        echo "Error: WireGuard interface not found after 30 seconds" >&2
        exit 1
    fi
    
    # Determine node role
    NODE_ROLE=$(determine_role)
    export NODE_ROLE
    
    echo "Node role: $NODE_ROLE"
    
    # Wait for etcd
    wait_for_etcd
    
    # Initialize or join cluster
    if [[ "$NODE_ROLE" == "primary" ]]; then
        initialize_cluster
    else
        join_cluster
    fi
}

# Run main function
main "$@"
