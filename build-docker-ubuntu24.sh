#!/usr/bin/env bash

# Build script for Open WebUI Docker image on Ubuntu 24.04
# This script builds a Docker image from your fork using Ubuntu 24.04 as the base

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
IMAGE_NAME="open-webui"
IMAGE_TAG="ubuntu24"
USE_CUDA=false
USE_OLLAMA=false
USE_SLIM=false
USE_PERMISSION_HARDENING=false
USE_CUDA_VER="cu128"
USE_EMBEDDING_MODEL="sentence-transformers/all-MiniLM-L6-v2"
USE_RERANKING_MODEL=""
USE_AUXILIARY_EMBEDDING_MODEL="TaylorAI/bge-micro-v2"
BUILD_HASH="dev-build"
NO_CACHE=false
PUSH_IMAGE=false

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Open WebUI Docker image for Ubuntu 24.04

OPTIONS:
    -n, --name NAME          Image name (default: open-webui)
    -t, --tag TAG           Image tag (default: ubuntu24)
    -c, --cuda              Enable CUDA support
    -o, --ollama            Include Ollama in the image
    -s, --slim              Build slim version (skip model downloads)
    -p, --permission-hardening  Enable permission hardening for OpenShift
    --cuda-ver VERSION      CUDA version (default: cu128)
    --embedding-model MODEL Embedding model (default: sentence-transformers/all-MiniLM-L6-v2)
    --reranking-model MODEL Reranking model (default: empty)
    --auxiliary-model MODEL Auxiliary embedding model (default: TaylorAI/bge-micro-v2)
    --build-hash HASH       Build hash/version (default: dev-build)
    --no-cache              Build without using cache
    --push                  Push image to registry after build
    -h, --help              Show this help message

EXAMPLES:
    # Basic build
    $0

    # Build with CUDA support
    $0 --cuda

    # Build with custom name and tag
    $0 --name my-webui --tag v1.0

    # Build and push to registry
    $0 --push

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -c|--cuda)
            USE_CUDA=true
            shift
            ;;
        -o|--ollama)
            USE_OLLAMA=true
            shift
            ;;
        -s|--slim)
            USE_SLIM=true
            shift
            ;;
        -p|--permission-hardening)
            USE_PERMISSION_HARDENING=true
            shift
            ;;
        --cuda-ver)
            USE_CUDA_VER="$2"
            shift 2
            ;;
        --embedding-model)
            USE_EMBEDDING_MODEL="$2"
            shift 2
            ;;
        --reranking-model)
            USE_RERANKING_MODEL="$2"
            shift 2
            ;;
        --auxiliary-model)
            USE_AUXILIARY_EMBEDDING_MODEL="$2"
            shift 2
            ;;
        --build-hash)
            BUILD_HASH="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --push)
            PUSH_IMAGE=true
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

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    exit 1
fi

# Get git commit hash if in a git repository
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
    GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    if [ "$BUILD_HASH" = "dev-build" ]; then
        BUILD_HASH="dev-build-${GIT_COMMIT}"
    fi
    echo -e "${GREEN}Git commit: ${GIT_COMMIT}${NC}"
fi

# Build the Docker image
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Building Open WebUI Docker Image${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Image: ${YELLOW}${FULL_IMAGE_NAME}${NC}"
echo -e "Dockerfile: ${YELLOW}Dockerfile${NC}"
echo -e "Build Hash: ${YELLOW}${BUILD_HASH}${NC}"
echo -e "CUDA: ${YELLOW}${USE_CUDA}${NC}"
echo -e "Ollama: ${YELLOW}${USE_OLLAMA}${NC}"
echo -e "Slim: ${YELLOW}${USE_SLIM}${NC}"
echo -e "Permission Hardening: ${YELLOW}${USE_PERMISSION_HARDENING}${NC}"
echo -e "No Cache: ${YELLOW}${NO_CACHE}${NC}"
echo ""

# Build command
BUILD_CMD="docker build"

if [ "$NO_CACHE" = true ]; then
    BUILD_CMD="$BUILD_CMD --no-cache"
fi

BUILD_CMD="$BUILD_CMD -f Dockerfile"
BUILD_CMD="$BUILD_CMD --build-arg USE_CUDA=${USE_CUDA}"
BUILD_CMD="$BUILD_CMD --build-arg USE_OLLAMA=${USE_OLLAMA}"
BUILD_CMD="$BUILD_CMD --build-arg USE_SLIM=${USE_SLIM}"
BUILD_CMD="$BUILD_CMD --build-arg USE_PERMISSION_HARDENING=${USE_PERMISSION_HARDENING}"
BUILD_CMD="$BUILD_CMD --build-arg USE_CUDA_VER=${USE_CUDA_VER}"
BUILD_CMD="$BUILD_CMD --build-arg USE_EMBEDDING_MODEL=${USE_EMBEDDING_MODEL}"
BUILD_CMD="$BUILD_CMD --build-arg USE_RERANKING_MODEL=${USE_RERANKING_MODEL}"
BUILD_CMD="$BUILD_CMD --build-arg USE_AUXILIARY_EMBEDDING_MODEL=${USE_AUXILIARY_EMBEDDING_MODEL}"
BUILD_CMD="$BUILD_CMD --build-arg BUILD_HASH=${BUILD_HASH}"
BUILD_CMD="$BUILD_CMD -t ${FULL_IMAGE_NAME}"
BUILD_CMD="$BUILD_CMD ."

echo -e "${YELLOW}Building image... This may take a while.${NC}"
echo ""

# Execute build
if eval "$BUILD_CMD"; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Image: ${YELLOW}${FULL_IMAGE_NAME}${NC}"
    echo ""
    
    # Show image info
    echo -e "${GREEN}Image information:${NC}"
    docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    echo ""
    
    # Push if requested
    if [ "$PUSH_IMAGE" = true ]; then
        echo -e "${YELLOW}Pushing image to registry...${NC}"
        if docker push "${FULL_IMAGE_NAME}"; then
            echo -e "${GREEN}Image pushed successfully!${NC}"
        else
            echo -e "${RED}Failed to push image${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}To run the container:${NC}"
        echo -e "  ${YELLOW}docker run -d -p 3000:8080 ${FULL_IMAGE_NAME}${NC}"
        echo ""
        echo -e "${GREEN}To push the image:${NC}"
        echo -e "  ${YELLOW}docker push ${FULL_IMAGE_NAME}${NC}"
    fi
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Build failed!${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
