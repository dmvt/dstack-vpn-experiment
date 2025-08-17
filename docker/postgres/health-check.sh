#!/bin/bash

# PostgreSQL health check script
# Returns 0 if healthy, 1 if unhealthy

# Check if PostgreSQL is accepting connections
if ! pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; then
    echo "PostgreSQL is not ready"
    exit 1
fi

# Check replication status based on role
ROLE=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END")

if [[ "$ROLE" == "primary" ]]; then
    # For primary, check if replication slots are active
    INACTIVE_SLOTS=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT COUNT(*) FROM pg_replication_slots WHERE NOT active")
    if [[ $INACTIVE_SLOTS -gt 0 ]]; then
        echo "Warning: $INACTIVE_SLOTS inactive replication slots"
    fi
elif [[ "$ROLE" == "replica" ]]; then
    # For replica, check replication lag
    LAG=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT")
    if [[ $LAG -gt 300 ]]; then
        echo "Replication lag too high: ${LAG}s"
        exit 1
    fi
fi

echo "PostgreSQL is healthy (role: $ROLE)"
exit 0
