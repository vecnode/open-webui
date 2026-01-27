#!/usr/bin/env bash

# Run script for Open WebUI Docker container (Ubuntu 24.04)
# This script runs the Docker container built with build-docker-ubuntu24.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
IMAGE_NAME="open-webui"
IMAGE_TAG="ubuntu24"
CONTAINER_NAME="open-webui-ubuntu24"
HOST_PORT=3000
CONTAINER_PORT=8080
DATA_VOLUME="open-webui-data"
OLLAMA_BASE_URL=""
WEBUI_SECRET_KEY=""
RESTART_POLICY="unless-stopped"
REMOVE_EXISTING=true

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run Open WebUI Docker container

OPTIONS:
    -i, --image IMAGE        Image name (default: open-webui)
    -t, --tag TAG           Image tag (default: ubuntu24)
    -n, --name NAME         Container name (default: open-webui-ubuntu24)
    -p, --port PORT         Host port (default: 3000)
    -v, --volume NAME       Data volume name (default: open-webui-data)
    -o, --ollama-url URL    Ollama base URL (default: empty, uses /ollama)
    -s, --secret-key KEY    WebUI secret key (default: auto-generated)
    --no-restart            Don't set restart policy
    --keep-existing         Don't remove existing container
    -h, --help              Show this help message

EXAMPLES:
    # Basic run
    $0

    # Run on different port
    $0 --port 8080

    # Run with Ollama URL
    $0 --ollama-url http://ollama:11434

    # Run with custom container name
    $0 --name my-webui

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -p|--port)
            HOST_PORT="$2"
            shift 2
            ;;
        -v|--volume)
            DATA_VOLUME="$2"
            shift 2
            ;;
        -o|--ollama-url)
            OLLAMA_BASE_URL="$2"
            shift 2
            ;;
        -s|--secret-key)
            WEBUI_SECRET_KEY="$2"
            shift 2
            ;;
        --no-restart)
            RESTART_POLICY="no"
            shift
            ;;
        --keep-existing)
            REMOVE_EXISTING=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Get the script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    exit 1
fi

# Check if image exists
if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${FULL_IMAGE_NAME}$"; then
    echo -e "${YELLOW}Warning: Image ${FULL_IMAGE_NAME} not found.${NC}"
    echo -e "${YELLOW}You may need to build it first with: ./build-docker-ubuntu24.sh${NC}"
    read -p "Do you want to build it now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./build-docker-ubuntu24.sh --name "$IMAGE_NAME" --tag "$IMAGE_TAG"
    else
        echo -e "${RED}Aborted. Please build the image first.${NC}"
        exit 1
    fi
fi

# Stop and remove existing container if requested
if [ "$REMOVE_EXISTING" = true ]; then
    if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${YELLOW}Stopping existing container: ${CONTAINER_NAME}${NC}"
        docker stop "$CONTAINER_NAME" &>/dev/null || true
        echo -e "${YELLOW}Removing existing container: ${CONTAINER_NAME}${NC}"
        docker rm "$CONTAINER_NAME" &>/dev/null || true
    fi
fi

# Build docker run command
RUN_CMD="docker run -d"

# Port mapping
RUN_CMD="$RUN_CMD -p ${HOST_PORT}:${CONTAINER_PORT}"

# Container name
RUN_CMD="$RUN_CMD --name ${CONTAINER_NAME}"

# Restart policy
if [ "$RESTART_POLICY" != "no" ]; then
    RUN_CMD="$RUN_CMD --restart ${RESTART_POLICY}"
fi

# Volume for data persistence
RUN_CMD="$RUN_CMD -v ${DATA_VOLUME}:/app/backend/data"

# Add host.docker.internal for host access
RUN_CMD="$RUN_CMD --add-host=host.docker.internal:host-gateway"

# Environment variables
if [ -n "$OLLAMA_BASE_URL" ]; then
    RUN_CMD="$RUN_CMD -e OLLAMA_BASE_URL=${OLLAMA_BASE_URL}"
fi

if [ -n "$WEBUI_SECRET_KEY" ]; then
    RUN_CMD="$RUN_CMD -e WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}"
fi

# Image name
RUN_CMD="$RUN_CMD ${FULL_IMAGE_NAME}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Starting Open WebUI Container${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Image: ${YELLOW}${FULL_IMAGE_NAME}${NC}"
echo -e "Container: ${YELLOW}${CONTAINER_NAME}${NC}"
echo -e "Port: ${YELLOW}${HOST_PORT} -> ${CONTAINER_PORT}${NC}"
echo -e "Volume: ${YELLOW}${DATA_VOLUME}${NC}"
echo -e "Restart: ${YELLOW}${RESTART_POLICY}${NC}"
echo ""

# Run the container
if eval "$RUN_CMD"; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Container started successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Access Open WebUI at:${NC}"
    echo -e "  ${YELLOW}http://localhost:${HOST_PORT}${NC}"
    echo ""
    echo -e "${BLUE}Useful commands:${NC}"
    echo -e "  View logs:     ${YELLOW}docker logs -f ${CONTAINER_NAME}${NC}"
    echo -e "  Stop:          ${YELLOW}docker stop ${CONTAINER_NAME}${NC}"
    echo -e "  Start:         ${YELLOW}docker start ${CONTAINER_NAME}${NC}"
    echo -e "  Restart:       ${YELLOW}docker restart ${CONTAINER_NAME}${NC}"
    echo -e "  Remove:        ${YELLOW}docker rm -f ${CONTAINER_NAME}${NC}"
    echo -e "  Shell access:  ${YELLOW}docker exec -it ${CONTAINER_NAME} bash${NC}"
    echo ""
    
    # Show container status
    echo -e "${BLUE}Container status:${NC}"
    docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    # Show logs
    echo -e "${BLUE}Showing recent logs (Ctrl+C to exit):${NC}"
    sleep 2
    docker logs --tail 20 -f "$CONTAINER_NAME"
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Failed to start container!${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
