#!/bin/bash

# Run script for Integrated Nim CUDA Miner
# Usage: ./run_integrated.sh <node_url> <address> [additional_options]

if [ $# -lt 2 ]; then
    echo "Usage: $0 <node_url> <address> [additional_options]"
    echo "Example: $0 https://stellaris-node.connor33341.dev/ Dn7FpuuLTkAXTbSDuQALMSQVzy4Mp1RWc69ZnddciNa7o"
    exit 1
fi

NODE_URL="$1"
ADDRESS="$2"
shift 2
ADDITIONAL_OPTIONS="$@"

# Add library path for CUDA shared library
export LD_LIBRARY_PATH="./build:$LD_LIBRARY_PATH"

echo "Starting Integrated Nim CUDA Miner..."
echo "Node URL: $NODE_URL"
echo "Address: $ADDRESS"
echo "Additional options: $ADDITIONAL_OPTIONS"
echo ""

# Run the integrated miner
./build/cuda_miner --node="$NODE_URL" --address="$ADDRESS" $ADDITIONAL_OPTIONS
