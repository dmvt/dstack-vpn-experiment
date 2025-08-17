#!/bin/bash

# Patroni health check script
# Returns 0 if healthy, 1 if unhealthy

# Check if Patroni is running
if ! pgrep -f patroni > /dev/null; then
    echo "Patroni is not running"
    exit 1
fi

# Check if PostgreSQL is accepting connections
if ! pg_isready -U postgres -d dstack > /dev/null 2>&1; then
    echo "PostgreSQL is not ready"
    exit 1
fi

# Check Patroni API health
if ! curl -s http://localhost:8008/health | grep -q "healthy"; then
    echo "Patroni API is not healthy"
    exit 1
fi

# Check cluster status
CLUSTER_STATUS=$(curl -s http://localhost:8008/cluster | jq -r '.state' 2>/dev/null || echo "unknown")

if [[ "$CLUSTER_STATUS" == "running" ]]; then
    echo "Patroni cluster is healthy (state: $CLUSTER_STATUS)"
    exit 0
else
    echo "Patroni cluster is not healthy (state: $CLUSTER_STATUS)"
    exit 1
fi
