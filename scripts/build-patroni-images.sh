#!/bin/bash
set -e

# Build and push Patroni-based PostgreSQL Docker images for DStack VPN

echo "Building Patroni-based PostgreSQL images..."

# Build etcd image
echo "Building etcd image..."
docker build -t dmvt/dstack-etcd:latest -f docker/etcd/Dockerfile docker/etcd/

# Build Patroni PostgreSQL image
echo "Building Patroni PostgreSQL image..."
docker build -t dmvt/dstack-postgres-patroni:latest -f docker/postgres-patroni/Dockerfile docker/postgres-patroni/

echo "Images built successfully:"
echo "  - dmvt/dstack-etcd:latest"
echo "  - dmvt/dstack-postgres-patroni:latest"

# Optional: Push to registry
if [[ "$1" == "--push" ]]; then
    echo "Pushing images to registry..."
    docker push dmvt/dstack-etcd:latest
    docker push dmvt/dstack-postgres-patroni:latest
    echo "Images pushed successfully"
fi

echo "Done!"
