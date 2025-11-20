#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="${HOME}/.local/bin"
BINARY_NAME="jarvis"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if moon build system is available
if ! command -v moon &> /dev/null; then
    echo -e "${RED}Error: moon build system not found${NC}"
    echo "Please install moon from: https://www.moonbitlang.com/"
    exit 1
fi

# Build the project
echo -e "${YELLOW}Building jarvis...${NC}"
cd "${SCRIPT_DIR}"
if ! moon build; then
    echo -e "${RED}Error: Build failed${NC}"
    exit 1
fi

# Find the built binary
BINARY_PATH="${SCRIPT_DIR}/target/native/release/build/jarvis/jarvis.exe"
if [[ ! -f "${BINARY_PATH}" ]]; then
    echo -e "${RED}Error: Binary not found at ${BINARY_PATH}${NC}"
    exit 1
fi

# Create installation directory if it doesn't exist
if [[ ! -d "${INSTALL_DIR}" ]]; then
    echo -e "${YELLOW}Creating directory ${INSTALL_DIR}${NC}"
    mkdir -p "${INSTALL_DIR}"
fi

# Copy binary to installation directory
echo -e "${YELLOW}Installing jarvis to ${INSTALL_DIR}${NC}"
cp "${BINARY_PATH}" "${INSTALL_DIR}/${BINARY_NAME}"
chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

# Check if ~/.local/bin is in PATH
if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    echo -e "${YELLOW}Warning: ${INSTALL_DIR} is not in your PATH${NC}"
    echo "Add the following line to your ~/.bashrc or ~/.zshrc:"
    echo -e "${GREEN}export PATH=\"\${HOME}/.local/bin:\${PATH}\"${NC}"
fi

echo -e "${GREEN}✓ Installation complete!${NC}"
echo "Run 'jarvis' to start the AI assistant"
