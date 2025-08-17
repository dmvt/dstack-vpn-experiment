#!/bin/bash
set -e

# Source the original entrypoint functions
source /usr/local/bin/docker-entrypoint.sh

# Function to determine node role based on IP
determine_role() {
    local overlay_ip=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' || echo "")
    
    if [[ "$overlay_ip" == "10.88.0.11" ]]; then
        echo "primary"
    elif [[ "$overlay_ip" == "10.88.0.12" ]] || [[ "$overlay_ip" == "10.88.0.13" ]]; then
        echo "replica"
    else
        echo "Error: Unable to determine role from IP $overlay_ip" >&2
        exit 1
    fi
}

# Setup primary node
setup_primary() {
    echo "Setting up PostgreSQL primary node..."
    
    # Use primary configuration
    cp /etc/postgresql/postgresql.conf.primary "$PGDATA/postgresql.conf"
    cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
    
    # Create replication user if not exists
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'replicator') THEN
                CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '${POSTGRES_REPLICATION_PASSWORD}';
            END IF;
        END
        \$\$;
        
        -- Create replication slots for replicas
        SELECT pg_create_physical_replication_slot('replica_slot_12', true) 
        WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'replica_slot_12');
        
        SELECT pg_create_physical_replication_slot('replica_slot_13', true)
        WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'replica_slot_13');
EOSQL
    
    # Initialize pgBackRest repository
    if [[ ! -f /var/lib/pgbackrest/backup/db/backup.info ]]; then
        echo "Initializing pgBackRest repository..."
        pgbackrest --stanza=db stanza-create
    fi
}

# Setup replica node
setup_replica() {
    echo "Setting up PostgreSQL replica node..."
    
    local primary_host="10.88.0.11"
    local slot_name=""
    
    # Determine replication slot based on IP
    local overlay_ip=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' || echo "")
    if [[ "$overlay_ip" == "10.88.0.12" ]]; then
        slot_name="replica_slot_12"
    elif [[ "$overlay_ip" == "10.88.0.13" ]]; then
        slot_name="replica_slot_13"
    fi
    
    # Wait for primary to be ready
    echo "Waiting for primary at $primary_host..."
    until PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" psql -h "$primary_host" -U replicator -d postgres -c '\q' 2>/dev/null; do
        echo "Primary not ready, waiting..."
        sleep 5
    done
    
    # If data directory is empty, perform base backup
    if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
        echo "Performing base backup from primary..."
        PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" pg_basebackup \
            -h "$primary_host" \
            -D "$PGDATA" \
            -U replicator \
            -v -P -w \
            -S "$slot_name" \
            -X stream
        
        # Use replica configuration
        cp /etc/postgresql/postgresql.conf.replica "$PGDATA/postgresql.conf"
        cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"
        
        # Update configuration with actual slot name and overlay IP
        sed -i "s/replica_slot_overlay_ip/$slot_name/g" "$PGDATA/postgresql.conf"
        sed -i "s/replica_overlay_ip/replica_$overlay_ip/g" "$PGDATA/postgresql.conf"
        
        # Create standby signal file
        touch "$PGDATA/standby.signal"
    fi
}

# Main entrypoint logic
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
    
    # Determine role
    POSTGRES_REPLICATION_MODE=${POSTGRES_REPLICATION_MODE:-$(determine_role)}
    export POSTGRES_REPLICATION_MODE
    
    echo "Node role: $POSTGRES_REPLICATION_MODE"
    
    # Initialize database if needed
    if [[ "$POSTGRES_REPLICATION_MODE" == "primary" ]]; then
        # Run original initialization for primary
        docker_setup_env
        docker_create_db_directories
        
        if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
            docker_verify_minimum_env
            docker_init_database_dir
            pg_setup_hba_conf
            
            docker_temp_server_start "$@"
            docker_setup_db
            setup_primary
            docker_temp_server_stop
        else
            docker_temp_server_start "$@"
            setup_primary
            docker_temp_server_stop
        fi
    else
        # For replica, just setup
        docker_setup_env
        docker_create_db_directories
        setup_replica
    fi
    
    # Execute PostgreSQL
    exec docker_entrypoint postgres "$@"
}

# Run main function
main "$@"
