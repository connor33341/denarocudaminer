# CUDA Miner Benchmarking Guide

## Overview

The CUDA miner now includes comprehensive benchmarking capabilities that generate beautiful JSON and HTML reports with detailed performance metrics, real-time charts, and efficiency analysis.

## Features

✅ **Real-time Performance Monitoring**
- Hash rate tracking over time
- GPU utilization metrics
- Mining attempt logging

✅ **Comprehensive Reports**
- JSON data export for analysis
- Interactive HTML dashboard
- Chart.js visualizations

✅ **Detailed Metrics**
- Total hashes computed
- Success/failure rates
- Time to solution analysis
- GPU configuration tracking

## Quick Start

### Basic Benchmarking

```bash
# Enable benchmarking with auto-generated session name
bash run.sh https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark

# Custom benchmark session name
bash run.sh https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark "my_mining_test"
```

### Benchmark Testing (Timed)

```bash
# Run a 5-minute benchmark test
bash run.sh https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark-only 300

# Run a 1-hour performance test
bash run.sh https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark-only 3600
```

### Performance Tuning with Benchmarking

```bash
# Test different GPU configurations
bash run.sh NODE_URL ADDRESS --benchmark "test_1024_512" --blocks 1024 --threads 512
bash run.sh NODE_URL ADDRESS --benchmark "test_2048_256" --blocks 2048 --threads 256
bash run.sh NODE_URL ADDRESS --benchmark "test_512_1024" --blocks 512 --threads 1024
```

## Command Line Options

### Benchmarking Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--benchmark` | Enable benchmarking with auto session name | `--benchmark` |
| `--benchmark <name>` | Enable benchmarking with custom session | `--benchmark "performance_test"` |
| `--benchmark-output <path>` | Set custom output path | `--benchmark-output "my_results"` |
| `--benchmark-only <seconds>` | Run benchmark for X seconds then exit | `--benchmark-only 300` |

### Mining Configuration

| Flag | Description | Default | Example |
|------|-------------|---------|---------|
| `--blocks <N>` | CUDA grid blocks per launch | 1024 | `--blocks 2048` |
| `--threads <N>` | CUDA threads per block | 512 | `--threads 256` |
| `--iters-per-thread <N>` | Iterations per thread per batch | 20000 | `--iters-per-thread 10000` |
| `--gpu-arch <arch>` | GPU architecture | sm_89 | `--gpu-arch sm_75` |
| `--max-blocks <N>` | Stop after mining N blocks | unlimited | `--max-blocks 5` |

## Generated Reports

### JSON Report (`benchmark_TIMESTAMP.json`)

Contains detailed machine-readable data:

```json
{
  "benchmark_report": {
    "metadata": {
      "session_id": "performance_test_2025-08-29_14-30-15",
      "generated_at": "2025-08-29T14:35:22Z",
      "miner_version": "CUDA Miner v1.0"
    },
    "session_summary": {
      "total_duration_seconds": 300.45,
      "blocks_found": 2,
      "total_attempts": 156,
      "total_hashes": 15734567890,
      "average_hash_rate_hs": 52448926.3,
      "peak_hash_rate_hs": 67234521.7
    },
    "efficiency_metrics": {
      "hashes_per_second": 52448926.3,
      "success_rate_percent": 1.28,
      "average_time_to_solution_seconds": 147.2
    }
  }
}
```

### HTML Report (`benchmark_TIMESTAMP.html`)

Interactive dashboard featuring:

🎯 **Performance Overview Cards**
- Total mining time
- Blocks found
- Average/peak hash rates
- Success rate

📊 **Real-time Charts**
- Hash rate over time (Chart.js)
- Interactive timeline
- Responsive design

⚙️ **Configuration Details**
- GPU settings used
- Mining parameters
- Environment info

📋 **Detailed Attempt Log**
- Recent mining attempts
- Success/failure status
- Performance per attempt

## Usage Examples

### 1. Quick Performance Check

```bash
# Run a 2-minute benchmark to check current performance
bash run.sh https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark-only 120
```

### 2. Overnight Mining with Benchmarking

```bash
# Mine normally but collect performance data
bash run.sh https://stellaris-node.connor33341.dev/ YOUR_ADDRESS --benchmark "overnight_session"
```

### 3. GPU Configuration Testing

```bash
# Test different configurations and compare results
bash run.sh NODE_URL ADDRESS --benchmark-only 300 --benchmark "config_1" --blocks 1024 --threads 512
bash run.sh NODE_URL ADDRESS --benchmark-only 300 --benchmark "config_2" --blocks 2048 --threads 256
bash run.sh NODE_URL ADDRESS --benchmark-only 300 --benchmark "config_3" --blocks 512 --threads 1024

# Compare the generated HTML reports to find optimal settings
```

### 4. Custom Output Location

```bash
# Save reports to specific directory
mkdir -p performance_tests
bash run.sh NODE_URL ADDRESS --benchmark "test_run" --benchmark-output "performance_tests/test_$(date +%Y%m%d)"
```

## Demo Script

Run the included demo to see benchmarking in action:

```bash
bash benchmark_demo.sh
```

This will:
- Run a 60-second benchmark test
- Generate sample JSON and HTML reports
- Show example statistics
- Provide usage examples

## Viewing Reports

### HTML Reports

1. **Direct File Access:**
   ```bash
   # Open in default browser (if available)
   xdg-open benchmark_TIMESTAMP.html
   ```

2. **Local Web Server:**
   ```bash
   # Serve reports with Python
   cd benchmarks
   python3 -m http.server 8000
   # Visit: http://localhost:8000/benchmark_TIMESTAMP.html
   ```

### JSON Reports

```bash
# View summary with jq (if available)
jq '.benchmark_report.session_summary' benchmark_TIMESTAMP.json

# Extract specific metrics
jq '.benchmark_report.efficiency_metrics.hashes_per_second' benchmark_TIMESTAMP.json
```

## Performance Optimization

Use benchmarking to find optimal settings for your GPU:

### Step 1: Baseline Test
```bash
bash run.sh NODE_URL ADDRESS --benchmark-only 300 --benchmark "baseline"
```

### Step 2: Test Variations
```bash
# Test higher block count
bash run.sh NODE_URL ADDRESS --benchmark-only 300 --benchmark "high_blocks" --blocks 2048

# Test higher thread count  
bash run.sh NODE_URL ADDRESS --benchmark-only 300 --benchmark "high_threads" --threads 1024

# Test different iterations
bash run.sh NODE_URL ADDRESS --benchmark-only 300 --benchmark "low_iters" --iters-per-thread 10000
```

### Step 3: Compare Results
Open the generated HTML reports and compare:
- Average hash rates
- Peak performance
- Consistency (low variance)
- GPU utilization

### Step 4: Apply Best Settings
Use the configuration that provides the highest stable hash rate for your actual mining sessions.

## Troubleshooting

### Reports Not Generated
- Ensure benchmarking is enabled with `--benchmark`
- Check that the miner runs for at least a few seconds
- Verify write permissions in the output directory

### HTML Report Not Loading
- Check that the HTML file is complete (not truncated)
- Try serving via Python web server instead of direct file access
- Ensure Chart.js CDN is accessible

### JSON Report Issues
- Validate JSON syntax with `jq` or online validator
- Check for special characters in session names
- Ensure sufficient disk space for report generation

## Advanced Usage

### Automated Testing Script

```bash
#!/bin/bash
# Performance testing automation

CONFIGS=(
    "1024 512 20000"
    "2048 256 20000"  
    "512 1024 20000"
    "1024 512 10000"
    "1024 512 40000"
)

for config in "${CONFIGS[@]}"; do
    read blocks threads iters <<< "$config"
    echo "Testing configuration: blocks=$blocks, threads=$threads, iters=$iters"
    
    bash run.sh NODE_URL ADDRESS \
        --benchmark-only 180 \
        --benchmark "test_${blocks}_${threads}_${iters}" \
        --blocks $blocks \
        --threads $threads \
        --iters-per-thread $iters
        
    sleep 10  # Cool down between tests
done

echo "All tests completed. Check benchmarks/ directory for results."
```

### Data Analysis

Extract data from JSON reports for further analysis:

```python
import json
import pandas as pd
import matplotlib.pyplot as plt

# Load benchmark data
with open('benchmark_session.json') as f:
    data = json.load(f)

# Extract hash rate history
history = data['benchmark_report']['hash_rate_history']
df = pd.DataFrame(history)
df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')

# Plot hash rate over time
plt.figure(figsize=(12, 6))
plt.plot(df['timestamp'], df['hash_rate_hs'] / 1e6)
plt.title('Hash Rate Over Time')
plt.xlabel('Time')
plt.ylabel('Hash Rate (MH/s)')
plt.grid(True)
plt.show()
```

## Support

For issues or questions about benchmarking:

1. Check the console output for error messages
2. Verify your GPU configuration is supported
3. Ensure sufficient system resources (RAM, disk space)
4. Report issues with sample benchmark reports attached

---

*Happy mining and optimizing! 🚀*
