#!/bin/bash

# Compilation script for Denaro CUDA Miner
set -e

echo "Starting compilation of Denaro CUDA Miner..."

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

# Create build directory if it doesn't exist
mkdir -p build

echo "Compiling CUDA miner..."
# Compile CUDA kernel
nvcc -o build/cuda_miner src/cuda_miner/kernel.cu -lcuda -arch=sm_50 -O3

# Check if CUDA compilation was successful
if [ $? -eq 0 ]; then
    echo "CUDA miner compiled successfully!"
else
    echo "Error: CUDA compilation failed!"
    exit 1
fi

echo "Compiling Nim manager..."
# Compile Nim manager
# Ensure nimble and required Nim packages are installed
if command -v nimble &> /dev/null; then
    echo "Installing nim dependencies (nimcrypto)..."
    # install nimcrypto non-interactively; if it fails we'll continue so nim c can report errors
    nimble install -y nimcrypto || echo "Warning: nimble install failed or was skipped. If compilation still fails, install nimcrypto manually (nimble install nimcrypto)."
else
    echo "nimble not found; skipping automatic nim package installation. If you get missing module errors, install nimble and run: nimble install nimcrypto"
fi

nim c -d:release -d:ssl -o:build/manager src/manager.nim

# Check if Nim compilation was successful
if [ $? -eq 0 ]; then
    echo "Nim manager compiled successfully!"
else
    echo "Error: Nim compilation failed!"
    exit 1
fi

echo "Compilation completed successfully!"
echo "Executables are in the build/ directory:"
echo "  - build/cuda_miner (CUDA mining kernel)"
echo "  - build/manager (Nim manager)"