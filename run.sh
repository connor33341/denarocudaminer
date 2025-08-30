#!/bin/bash

# Run script for Integrated Nim CUDA Miner
# Usage: ./run.sh <node_url> <address> [options]

# Function to show help
show_help() {
    echo "CUDA Miner Runner Script"
    echo "========================"
    echo ""
    echo "Usage: $0 <node_url> <address> [options]"
    echo ""
    echo "Required Arguments:"
    echo "  <node_url>     URL of the Stellaris node (e.g., https://stellaris-node.connor33341.dev/)"
    echo "  <address>      Your mining address to receive rewards"
    echo ""
    echo "Benchmarking Options:"
    echo "  --benchmark                    Enable benchmarking with auto-generated session name"
    echo "  --benchmark <session_name>     Enable benchmarking with custom session name"
    echo "  --benchmark-output <path>      Set custom output path for benchmark reports"
    echo "  --benchmark-only <duration>    Run benchmark for specified seconds then exit"
    echo ""
    echo "Mining Options:"
    echo "  --max-blocks <N>              Stop after mining N blocks"
    echo "  --blocks <N>                  CUDA grid blocks per launch (default: 1024)"
    echo "  --threads <N>                 CUDA threads per block (default: 512)"
    echo "  --iters-per-thread <N>        Iterations per thread per batch (default: 20000)"
    echo "  --gpu-arch <arch>             GPU architecture (default: sm_89)"
    echo ""
    echo "Examples:"
    echo "  # Basic mining"
    echo "  $0 https://stellaris-node.connor33341.dev/ YOUR_ADDRESS"
    echo ""
    echo "  # Mining with benchmarking"
    echo "  $0 https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark"
    echo ""
    echo "  # Custom benchmark session"
    echo "  $0 https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark my_test_session"
    echo ""
    echo "  # 5-minute benchmark test"
    echo "  $0 https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark-only 300"
    echo ""
    echo "  # Performance tuning with benchmarking"
    echo "  $0 https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark --blocks 2048 --threads 256"
    echo ""
}

# Parse arguments
if [ $# -lt 2 ]; then
    show_help
    exit 1
fi

# Check for help flag
for arg in "$@"; do
    if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
        show_help
        exit 0
    fi
done

NODE_URL="$1"
ADDRESS="$2"
shift 2

# Parse additional options
BENCHMARK_ENABLED=false
BENCHMARK_SESSION=""
BENCHMARK_OUTPUT=""
BENCHMARK_DURATION=""
ADDITIONAL_OPTIONS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --benchmark)
            BENCHMARK_ENABLED=true
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                BENCHMARK_SESSION="$2"
                shift
            fi
            shift
            ;;
        --benchmark-output)
            BENCHMARK_OUTPUT="$2"
            shift 2
            ;;
        --benchmark-only)
            BENCHMARK_ENABLED=true
            BENCHMARK_DURATION="$2"
            shift 2
            ;;
        *)
            ADDITIONAL_OPTIONS="$ADDITIONAL_OPTIONS $1"
            shift
            ;;
    esac
done

# Add library path for CUDA shared library
export LD_LIBRARY_PATH="./build:$LD_LIBRARY_PATH"

# Check if miner executable exists
if [ ! -f "./build/cuda_miner" ]; then
    echo "❌ CUDA miner executable not found at ./build/cuda_miner"
    echo "Please compile the miner first:"
    echo "  bash compile.sh"
    exit 1
fi

echo "🚀 Starting Integrated Nim CUDA Miner..."
echo "Node URL: $NODE_URL"
echo "Address: $ADDRESS"

# Build command with benchmarking options
MINER_CMD="./build/cuda_miner --node=\"$NODE_URL\" --address=\"$ADDRESS\""

if [ "$BENCHMARK_ENABLED" = true ]; then
    echo "📊 Benchmarking: ENABLED"
    
    if [ -n "$BENCHMARK_SESSION" ]; then
        MINER_CMD="$MINER_CMD --benchmark \"$BENCHMARK_SESSION\""
        echo "📋 Session Name: $BENCHMARK_SESSION"
    else
        MINER_CMD="$MINER_CMD --benchmark"
        echo "📋 Session Name: Auto-generated"
    fi
    
    if [ -n "$BENCHMARK_OUTPUT" ]; then
        MINER_CMD="$MINER_CMD --benchmark-output \"$BENCHMARK_OUTPUT\""
        echo "💾 Output Path: $BENCHMARK_OUTPUT"
    fi
    
    # Create benchmarks directory and update library path
    mkdir -p benchmarks
    cd benchmarks
    MINER_CMD="../$MINER_CMD"
    export LD_LIBRARY_PATH="../build:$LD_LIBRARY_PATH"
    echo "📁 Working Directory: $(pwd)"
fi

if [ -n "$ADDITIONAL_OPTIONS" ]; then
    echo "⚙️  Additional Options: $ADDITIONAL_OPTIONS"
    MINER_CMD="$MINER_CMD $ADDITIONAL_OPTIONS"
fi

echo ""

# Handle benchmark-only mode (run for specified duration then exit)
if [ -n "$BENCHMARK_DURATION" ]; then
    echo "⏱️  Running benchmark for $BENCHMARK_DURATION seconds..."
    echo "Command: timeout $BENCHMARK_DURATION $MINER_CMD"
    echo ""
    
    timeout "$BENCHMARK_DURATION" bash -c "$MINER_CMD"
    exit_code=$?
    
    echo ""
    if [ $exit_code -eq 124 ]; then
        echo "✅ Benchmark completed successfully (timed out as expected)"
    else
        echo "⚠️  Benchmark ended with exit code: $exit_code"
    fi
    
    # Show generated reports
    if [ "$BENCHMARK_ENABLED" = true ]; then
        echo ""
        echo "📊 Generated benchmark reports:"
        ls -la *.json *.html 2>/dev/null | head -10
        
        if [ -f *.html ]; then
            echo ""
            echo "🌐 Open HTML report in browser:"
            echo "  file://$(pwd)/$(ls *.html | head -1)"
        fi
    fi
else
    # Normal mining mode
    echo "Command: $MINER_CMD"
    echo ""
    
    # Run the integrated miner
    bash -c "$MINER_CMD"
fi
