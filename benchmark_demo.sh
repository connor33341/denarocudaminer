#!/bin/bash

# Demo script for CUDA Miner Benchmarking
# This script demonstrates the benchmarking capabilities

echo "🚀 CUDA Miner Benchmarking Demo"
echo "================================"
echo ""

# Check if miner is compiled
if [ ! -f "build/cuda_miner" ]; then
    echo "❌ CUDA miner not found. Please compile first with:"
    echo "   bash compile.sh"
    exit 1
fi

echo "📊 Running miner with benchmarking enabled..."
echo "This will mine for 60 seconds and generate benchmark reports"
echo ""

# Run miner with benchmarking using the enhanced run.sh script
# Note: Replace with your actual address and node
bash run.sh \
    "https://stellaris-node.connor33341.dev/" \
    "Dn7FpuuLTkAXTbSDuQALMSQVzy4Mp1RWc69ZnddciNa7o" \
    --benchmark-only 60 \
    --benchmark "demo_session" \
    --benchmark-output "demo_benchmark" \
    --blocks 512 \
    --threads 256 \
    --iters-per-thread 10000

echo ""
echo "📄 Generated benchmark reports:"
echo "================================"

# Check in benchmarks directory since run.sh creates it
cd benchmarks 2>/dev/null || true

if [ -f "demo_benchmark.json" ]; then
    echo "✅ JSON Report: demo_benchmark.json"
    echo "   Size: $(du -h demo_benchmark.json | cut -f1)"
    echo ""
    echo "📋 Quick stats from JSON:"
    echo "   $(grep -o '"total_hashes":[^,]*' demo_benchmark.json | cut -d: -f2) total hashes computed"
    echo "   $(grep -o '"blocks_found":[^,]*' demo_benchmark.json | cut -d: -f2) blocks found"
    echo "   $(grep -o '"total_attempts":[^,]*' demo_benchmark.json | cut -d: -f2) mining attempts"
else
    echo "❌ JSON report not found"
fi

echo ""

if [ -f "demo_benchmark.html" ]; then
    echo "✅ HTML Report: demo_benchmark.html"
    echo "   Size: $(du -h demo_benchmark.html | cut -f1)"
    echo ""
    echo "🌐 Open HTML report in browser:"
    echo "   file://$(pwd)/demo_benchmark.html"
    echo ""
    echo "   Or if you have Python installed:"
    echo "   python3 -m http.server 8000"
    echo "   Then visit: http://localhost:8000/demo_benchmark.html"
else
    echo "❌ HTML report not found"
fi

echo ""
echo "🎯 Benchmark Features Demonstrated:"
echo "   ✓ Real-time hash rate monitoring"
echo "   ✓ Performance metrics collection"  
echo "   ✓ GPU configuration tracking"
echo "   ✓ Mining attempt logging"
echo "   ✓ JSON data export"
echo "   ✓ Interactive HTML dashboard"
echo "   ✓ Chart.js visualizations"
echo ""
echo "📚 Usage Examples with run.sh:"
echo "   # Basic mining"
echo "   bash run.sh NODE_URL YOUR_ADDRESS"
echo ""
echo "   # Basic benchmarking"
echo "   bash run.sh NODE_URL YOUR_ADDRESS --benchmark"
echo ""
echo "   # Custom benchmark session"
echo "   bash run.sh NODE_URL YOUR_ADDRESS --benchmark my_test"
echo ""
echo "   # 5-minute benchmark test"
echo "   bash run.sh NODE_URL YOUR_ADDRESS --benchmark-only 300"
echo ""
echo "   # Performance tuning with benchmarking"
echo "   bash run.sh NODE_URL YOUR_ADDRESS --benchmark --blocks 2048 --threads 256"
echo ""
echo "✨ Demo completed!"
