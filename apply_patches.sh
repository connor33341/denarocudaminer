#!/bin/bash

# Apply developer fee patches to stellaris submodule
# This script applies patches to the stellaris submodule without modifying the submodule directly

set -e

echo "Applying developer fee patches to stellaris submodule..."

# Check if we're in the right directory
if [ ! -d "stellaris" ]; then
    echo "Error: stellaris directory not found. Please run this script from the denarocudaminer root directory."
    exit 1
fi

# Check if patches directory exists
if [ ! -d "patches" ]; then
    echo "Error: patches directory not found."
    exit 1
fi

# Apply the miner patch
if [ -f "patches/developer_fee_miner.patch" ]; then
    echo "Applying developer fee patch to stellaris/miner/miner.py..."
    cd stellaris
    patch -p1 < ../patches/developer_fee_miner.patch
    cd ..
    echo "✓ Applied developer fee patch to miner.py"
else
    echo "Warning: developer_fee_miner.patch not found"
fi

echo "All patches applied successfully!"
echo ""
echo "To revert the patches, you can run:"
echo "  cd stellaris && patch -p1 -R < ../patches/developer_fee_miner.patch && cd .."
