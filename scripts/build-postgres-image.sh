#!/bin/bash
set -e

# Build and push PostgreSQL Docker image for DStack VPN

IMAGE_NAME="dmvt/dstack-postgres"
IMAGE_TAG="latest"

echo "Building PostgreSQL Docker image..."

# Build the image
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f docker/postgres/Dockerfile docker/postgres/

echo "PostgreSQL image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"

# Optional: Push to registry
if [[ "$1" == "--push" ]]; then
    echo "Pushing image to registry..."
    docker push ${IMAGE_NAME}:${IMAGE_TAG}
    echo "Image pushed successfully"
fi

echo "Done!"
