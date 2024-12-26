#!/bin/bash

# Exit on any error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Version file to track deployments
VERSION_FILE=".version"

echo -e "${GREEN}Starting deployment script...${NC}"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Create or increment version
if [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE")
    NEW_VERSION=$((CURRENT_VERSION + 1))
else
    NEW_VERSION=1
fi
echo $NEW_VERSION > "$VERSION_FILE"

# Export variables for docker-compose
export APP_VERSION="v${NEW_VERSION}"
export DEPLOY_TIMESTAMP=$(date +%s)
export JWT_SECRET=$(openssl rand -hex 32)
export ADMIN_PASSWORD="where'dtheyallgo?"
export CHECKOUT_PASSWORD="chromebooks@51"

# Update package list
echo -e "${YELLOW}Updating package list...${NC}"
apt-get update

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl start docker
    systemctl enable docker
    echo -e "${GREEN}Docker installed successfully${NC}"
else
    echo -e "${GREEN}Docker is already installed${NC}"
fi

# Install Docker Compose if not already installed
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}Installing Docker Compose...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose installed successfully${NC}"
else
    echo -e "${GREEN}Docker Compose is already installed${NC}"
fi

# Create required directories
mkdir -p data/logs
chown -R 1000:1000 data

# Function to stop and remove existing containers
cleanup_existing_containers() {
    echo -e "${YELLOW}Checking for existing containers...${NC}"
    
    # Find and stop any containers using port 80
    local existing_container=$(docker ps -q --filter "publish=80")
    if [ ! -z "$existing_container" ]; then
        echo -e "${YELLOW}Found existing container using port 80. Stopping it...${NC}"
        docker stop $existing_container
        docker rm $existing_container
        echo -e "${GREEN}Existing container removed successfully${NC}"
    fi

    # Stop and remove all containers from previous versions
    echo -e "${YELLOW}Cleaning up any previous deployment containers...${NC}"
    docker-compose down --remove-orphans || true
}

# Function to perform rollback
rollback() {
    echo -e "${RED}Error detected! Rolling back to previous version...${NC}"
    if [ -f "$VERSION_FILE" ] && [ "$CURRENT_VERSION" -gt 1 ]; then
        echo $CURRENT_VERSION > "$VERSION_FILE"
        export APP_VERSION="v${CURRENT_VERSION}"
        docker-compose up -d
        echo -e "${GREEN}Rollback completed successfully${NC}"
    else
        echo -e "${RED}No previous version available for rollback${NC}"
    fi
    exit 1
}

# Function to check container health
check_container_health() {
    local container_name="wts-device-manager-app-1"
    local max_attempts=120
    local attempt=1
    local wait_time=10

    echo -e "${YELLOW}Waiting for container health check (timeout: $((max_attempts * wait_time))s)...${NC}"

    while [ $attempt -le $max_attempts ]; do
        echo -n "Attempt $attempt of $max_attempts: "
        
        if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo "Container not found"
            sleep $wait_time
            attempt=$((attempt + 1))
            continue
        fi

        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null)
        
        case $health_status in
            healthy)
                echo "Container is healthy"
                return 0
                ;;
            unhealthy)
                echo "Container is unhealthy"
                return 1
                ;;
            starting)
                echo "Health check in progress..."
                ;;
            *)
                echo "Waiting for health check to begin..."
                ;;
        esac

        attempt=$((attempt + 1))
        sleep $wait_time
    done

    echo "Health check timed out after $((max_attempts * wait_time)) seconds"
    return 1
}

# Clean up existing containers before deployment
cleanup_existing_containers

echo -e "${YELLOW}Building and starting version ${APP_VERSION}...${NC}"
if docker-compose up -d --build; then
    if check_container_health; then
        echo -e "${GREEN}Deployment of version ${APP_VERSION} completed successfully!${NC}"
        echo -e "${GREEN}The application is running at http://localhost${NC}"
        
        # Clean up old images
        echo -e "${YELLOW}Cleaning up old images...${NC}"
        docker image prune -f
    else
        rollback
    fi
else
    rollback
fi

# Add some helpful commands
echo -e "\n${YELLOW}Useful commands:${NC}"
echo "- View logs: docker-compose logs -f"
echo "- Stop application: docker-compose down"
echo "- Restart application: docker-compose restart"
echo "- Check version: cat $VERSION_FILE"
echo "- Rollback: ./rollback.sh"