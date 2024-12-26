#!/bin/bash

# Exit on any error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Version file
VERSION_FILE=".version"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

if [ ! -f "$VERSION_FILE" ]; then
    echo -e "${RED}No version file found${NC}"
    exit 1
fi

CURRENT_VERSION=$(cat "$VERSION_FILE")

if [ "$CURRENT_VERSION" -le 1 ]; then
    echo -e "${RED}Already at oldest version, cannot rollback${NC}"
    exit 1
fi

PREVIOUS_VERSION=$((CURRENT_VERSION - 1))

# Export required environment variables
export APP_VERSION="v${PREVIOUS_VERSION}"
export DEPLOY_TIMESTAMP=$(date +%s)
export JWT_SECRET=$(openssl rand -hex 32)
export ADMIN_PASSWORD="where'dtheyallgo?"
export CHECKOUT_PASSWORD="chromebooks@51"

echo -e "${YELLOW}Rolling back to version ${APP_VERSION}...${NC}"

# Update version file
echo $PREVIOUS_VERSION > "$VERSION_FILE"

# Perform rollback
if docker-compose up -d; then
    echo -e "${GREEN}Successfully rolled back to version ${APP_VERSION}${NC}"
    echo -e "${GREEN}The application is running at http://localhost${NC}"
    
    # Clean up old images
    echo -e "${YELLOW}Cleaning up old images...${NC}"
    docker image prune -f
else
    echo -e "${RED}Rollback failed!${NC}"
    exit 1
fi