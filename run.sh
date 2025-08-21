#!/bin/bash

# Run script for Denaro CUDA Miner
set -e

# Check if build directory exists
if [ ! -d "build" ]; then
    echo "Error: build directory not found. Please run compile.sh first."
    exit 1
fi

# Check if executables exist
if [ ! -f "build/manager" ]; then
    echo "Error: manager executable not found. Please run compile.sh first."
    exit 1
fi

if [ ! -f "build/cuda_miner" ]; then
    echo "Error: cuda_miner executable not found. Please run compile.sh first."
    exit 1
fi

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <node_url> <wallet_address>"
    echo "Example: $0 http://localhost:8080 denaro1abc123..."
    exit 1
fi

NODE_URL="$1"
WALLET_ADDRESS="$2"

echo "Starting Denaro CUDA Miner..."
echo "Node URL: $NODE_URL"
echo "Wallet Address: $WALLET_ADDRESS"
echo ""

# Change to build directory and create symlink for cuda_miner.exe if it doesn't exist
cd build
if [ ! -f "cuda_miner.exe" ] && [ ! -L "cuda_miner.exe" ]; then
    ln -s cuda_miner cuda_miner.exe
    echo "Created symlink cuda_miner.exe -> cuda_miner"
fi

# Run the manager with the provided arguments
./manager "$NODE_URL" "$WALLET_ADDRESS"