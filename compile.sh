#!/bin/bash

# Compilation script for Integrated Nim CUDA Miner
set -e

echo "Starting compilation of Integrated Nim CUDA Miner..."

# Check if nvcc is available
if ! command -v nvcc &> /dev/null; then
    echo "Error: nvcc (NVIDIA CUDA Compiler) not found. Please install CUDA toolkit."
    exit 1
fi

# Check if nim is available
if ! command -v nim &> /dev/null; then
    echo "Error: nim compiler not found. Please install Nim."
    exit 1
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found. Please install Python 3."
    exit 1
fi

# Install Python requirements
echo "Installing Python requirements..."
if [ -f "requirements.txt" ]; then
    python3 -m pip install -r requirements.txt
    if [ $? -eq 0 ]; then
        echo "Python requirements installed successfully!"
    else
        echo "Warning: Failed to install some Python requirements. The base58 decoder may not work."
    fi
else
    echo "Warning: requirements.txt not found. Skipping Python package installation."
fi

# Create build directory if it doesn't exist
mkdir -p build

echo "Compiling CUDA library..."
# Compile CUDA library as shared library for Nim FFI
nvcc -shared -Xcompiler -fPIC -o build/libcuda_miner.so src/cuda_miner_lib.cu -lcuda -lcudart -arch=sm_86 -O3

# Check if CUDA compilation was successful
if [ $? -eq 0 ]; then
    echo "CUDA library compiled successfully!"
else
    echo "Error: CUDA compilation failed!"
    exit 1
fi

echo "Compiling Nim CUDA miner..."
# Ensure nimble and required Nim packages are installed
if command -v nimble &> /dev/null; then
    echo "Installing nim dependencies (nimcrypto)..."
    # install nimcrypto non-interactively; if it fails we'll continue so nim c can report errors
    nimble install -y nimcrypto || echo "Warning: nimble install failed or was skipped. If compilation still fails, install nimcrypto manually (nimble install nimcrypto)."
else
    echo "nimble not found; skipping automatic nim package installation. If you get missing module errors, install nimble and run: nimble install nimcrypto"
fi

# Compile Nim miner with CUDA library linking
nim c -d:release -d:ssl --passL:"-L./build -lcuda_miner -L/usr/local/cuda/lib64 -lcudart" -o:build/cuda_miner src/cuda_miner.nim

# Check if Nim compilation was successful
if [ $? -eq 0 ]; then
    echo "Nim CUDA miner compiled successfully!"
else
    echo "Error: Nim compilation failed!"
    exit 1
fi

echo "Compilation completed successfully!"
echo "Executable is in the build/ directory:"
echo "  - build/cuda_miner (Integrated Nim CUDA miner)"
echo ""
echo "Usage: ./build/cuda_miner --address <your_address> --node <node_url>"
echo "Example: ./build/cuda_miner --address Dn7FpuuLTkAXTbSDuQALMSQVzy4Mp1RWc69ZnddciNa7o --node https://stellaris-node.connor33341.dev/"
