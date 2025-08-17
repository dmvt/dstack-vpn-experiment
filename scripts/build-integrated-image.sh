#!/bin/bash
set -e

# Build integrated WireGuard + Patroni Docker image for DStack VPN

echo "Building integrated WireGuard + Patroni image..."

# Build the integrated image
docker build -t lsdan/dstack-wireguard-node:latest -f docker/wireguard/Dockerfile .

echo "Image built successfully:"
echo "  - lsdan/dstack-wireguard-node:latest"

# Optional: Push to registry
if [[ "$1" == "--push" ]]; then
    echo "Pushing image to registry..."
    docker push lsdan/dstack-wireguard-node:latest
    echo "Image pushed successfully"
fi

echo "Done!"
