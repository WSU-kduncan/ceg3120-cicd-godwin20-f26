#!/bin/bash

CONTAINER_NAME="ceg3120-site"
IMAGE_NAME="hayden445/ceg3120-project6:latest"

echo "Stopping existing container (if running)..."
docker stop $CONTAINER_NAME 2>/dev/null || true

echo "Removing existing container (if present)..."
docker rm $CONTAINER_NAME 2>/dev/null || true

echo "Pulling latest image from DockerHub..."
docker pull $IMAGE_NAME

echo "Starting new detached container with restart policy..."
docker run -d \
    --name $CONTAINER_NAME \
    --restart unless-stopped \
    -p 80:80 \
    $IMAGE_NAME

echo "Container refresh complete!"