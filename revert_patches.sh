#!/bin/bash

# Revert developer fee patches from stellaris submodule
# This script reverts the patches applied to the stellaris submodule

set -e

echo "Reverting developer fee patches from stellaris submodule..."

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

# Revert the miner patch
if [ -f "patches/developer_fee_miner.patch" ]; then
    echo "Reverting developer fee patch from stellaris/miner/miner.py..."
    cd stellaris
    patch -p1 -R < ../patches/developer_fee_miner.patch
    cd ..
    echo "✓ Reverted developer fee patch from miner.py"
else
    echo "Warning: developer_fee_miner.patch not found"
fi

echo "All patches reverted successfully!"
