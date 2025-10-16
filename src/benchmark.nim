## Benchmarking module for CUDA miner
## Provides comprehensive performance metrics collection and reporting

import std/[json, times, strformat, math, algorithm, sequtils, strutils]

type
  MiningAttempt* = object
    blockId*: int
    startTime*: float
    endTime*: float
    duration*: float
    hashesComputed*: uint64
    hashRate*: float
    difficulty*: float
    found*: bool
    nonce*: uint32
    batchCount*: int

  MiningSession* = object
    sessionId*: string
    startTime*: float
    endTime*: float
    totalDuration*: float
    attempts*: seq[MiningAttempt]
    blocksFound*: int
    totalHashes*: uint64
    averageHashRate*: float
    peakHashRate*: float
    minHashRate*: float
    difficulty*: float
    hashRateHistory*: seq[tuple[timestamp: float, hashRate: float]]
    gpuConfig*: GPUConfig
    
  GPUConfig* = object
    blocks*: uint
    threads*: uint
    itersPerThread*: uint
    architecture*: string

  BenchmarkStats* = object
    sessionStats*: MiningSession
    detailedAttempts*: seq[MiningAttempt]
    hashRateHistory*: seq[tuple[timestamp: float, hashRate: float]]
    efficiencyMetrics*: EfficiencyMetrics

  EfficiencyMetrics* = object
    hashesPerSecond*: float
    hashesPerWatt*: float  # If power monitoring available
    timeToSolution*: float  # Average time to find a block
    successRate*: float     # Percentage of successful attempts
    staleRate*: float       # Percentage of stale blocks

var currentSession*: MiningSession
var allAttempts*: seq[MiningAttempt]
var isSessionActive*: bool = false

proc initBenchmarkSession*(sessionId: string, gpuConfig: GPUConfig) =
  ## Initialize a new benchmarking session
  currentSession = MiningSession(
    sessionId: sessionId,
    startTime: epochTime(),
    attempts: @[],
    blocksFound: 0,
    totalHashes: 0,
    hashRateHistory: @[],
    gpuConfig: gpuConfig
  )
  allAttempts = @[]
  isSessionActive = true
  echo fmt"🚀 Benchmark session '{sessionId}' started"

proc recordMiningAttempt*(blockId: int, startTime: float, endTime: float, 
                         hashesComputed: uint64, difficulty: float, 
                         found: bool, nonce: uint32 = 0, batchCount: int = 0) =
  ## Record a single mining attempt
  if not isSessionActive:
    return
    
  let duration = endTime - startTime
  let hashRate = if duration > 0: float(hashesComputed) / duration else: 0.0
  
  let attempt = MiningAttempt(
    blockId: blockId,
    startTime: startTime,
    endTime: endTime,
    duration: duration,
    hashesComputed: hashesComputed,
    hashRate: hashRate,
    difficulty: difficulty,
    found: found,
    nonce: nonce,
    batchCount: batchCount
  )
  
  currentSession.attempts.add(attempt)
  allAttempts.add(attempt)
  currentSession.totalHashes += hashesComputed
  
  if found:
    currentSession.blocksFound += 1
    echo fmt"⛏️  Block found! Hash rate: {hashRate/1_000_000:.2f} MH/s"
  
  # Update hash rate history (keep last 100 entries for performance)
  currentSession.hashRateHistory.add((epochTime(), hashRate))
  if currentSession.hashRateHistory.len > 100:
    currentSession.hashRateHistory.delete(0)

proc finalizeBenchmarkSession*() =
  ## Finalize the current benchmarking session
  if not isSessionActive:
    return
    
  currentSession.endTime = epochTime()
  currentSession.totalDuration = currentSession.endTime - currentSession.startTime
  
  # Calculate statistics
  if currentSession.attempts.len > 0:
    let hashRates = currentSession.attempts.mapIt(it.hashRate)
    currentSession.averageHashRate = hashRates.foldl(a + b) / float(hashRates.len)
    currentSession.peakHashRate = hashRates.max()
    currentSession.minHashRate = hashRates.min()
    
    # Set difficulty from last attempt
    if currentSession.attempts.len > 0:
      currentSession.difficulty = currentSession.attempts[^1].difficulty
  
  isSessionActive = false
  echo fmt"📊 Benchmark session completed. Duration: {currentSession.totalDuration:.2f}s"

proc calculateEfficiencyMetrics*(): EfficiencyMetrics =
  ## Calculate efficiency metrics from current session
  result = EfficiencyMetrics()
  
  if currentSession.attempts.len == 0:
    return
    
  let totalTime = currentSession.totalDuration
  let totalHashes = currentSession.totalHashes
  let successfulAttempts = currentSession.attempts.filterIt(it.found).len
  # let staleAttempts = 0  # Would need to track this separately - placeholder for future
  
  result.hashesPerSecond = if totalTime > 0: float(totalHashes) / totalTime else: 0.0
  result.successRate = if currentSession.attempts.len > 0: 
    float(successfulAttempts) / float(currentSession.attempts.len) * 100.0 
  else: 0.0
  result.staleRate = 0.0  # Placeholder - would need separate tracking
  
  # Calculate average time to solution for successful attempts
  let successfulDurations = currentSession.attempts.filterIt(it.found).mapIt(it.duration)
  result.timeToSolution = if successfulDurations.len > 0:
    successfulDurations.foldl(a + b) / float(successfulDurations.len)
  else: 0.0

proc generateJsonReport*(outputPath: string): bool =
  ## Generate detailed JSON benchmark report
  try:
    let metrics = calculateEfficiencyMetrics()
    let stats = BenchmarkStats(
      sessionStats: currentSession,
      detailedAttempts: allAttempts,
      hashRateHistory: currentSession.hashRateHistory,
      efficiencyMetrics: metrics
    )
    
    let jsonReport = %*{
      "benchmark_report": {
        "metadata": {
          "session_id": stats.sessionStats.sessionId,
          "generated_at": $now(),
          "miner_version": "CUDA Miner v1.0",
          "report_format_version": "1.0"
        },
        "session_summary": {
          "start_time": stats.sessionStats.startTime,
          "end_time": stats.sessionStats.endTime,
          "total_duration_seconds": stats.sessionStats.totalDuration,
          "blocks_found": stats.sessionStats.blocksFound,
          "total_attempts": stats.sessionStats.attempts.len,
          "total_hashes": stats.sessionStats.totalHashes,
          "average_hash_rate_hs": stats.sessionStats.averageHashRate,
          "peak_hash_rate_hs": stats.sessionStats.peakHashRate,
          "min_hash_rate_hs": stats.sessionStats.minHashRate,
          "difficulty": stats.sessionStats.difficulty
        },
        "gpu_configuration": {
          "cuda_blocks": stats.sessionStats.gpuConfig.blocks,
          "threads_per_block": stats.sessionStats.gpuConfig.threads,
          "iterations_per_thread": stats.sessionStats.gpuConfig.itersPerThread,
          "gpu_architecture": stats.sessionStats.gpuConfig.architecture
        },
        "efficiency_metrics": {
          "hashes_per_second": stats.efficiencyMetrics.hashesPerSecond,
          "success_rate_percent": stats.efficiencyMetrics.successRate,
          "average_time_to_solution_seconds": stats.efficiencyMetrics.timeToSolution,
          "stale_rate_percent": stats.efficiencyMetrics.staleRate
        },
        "hash_rate_history": stats.hashRateHistory.mapIt(%*{
          "timestamp": it.timestamp,
          "hash_rate_hs": it.hashRate
        }),
        "detailed_attempts": stats.detailedAttempts.mapIt(%*{
          "block_id": it.blockId,
          "start_time": it.startTime,
          "end_time": it.endTime,
          "duration_seconds": it.duration,
          "hashes_computed": it.hashesComputed,
          "hash_rate_hs": it.hashRate,
          "difficulty": it.difficulty,
          "block_found": it.found,
          "nonce": if it.found: it.nonce else: 0,
          "batch_count": it.batchCount
        })
      }
    }
    
    writeFile(outputPath, jsonReport.pretty())
    echo fmt"📄 JSON benchmark report saved to: {outputPath}"
    return true
  except Exception as e:
    echo fmt"❌ Error generating JSON report: {e.msg}"
    return false

proc generateHtmlReport*(outputPath: string): bool =
  ## Generate pretty HTML benchmark report
  try:
    let metrics = calculateEfficiencyMetrics()
    
    # Format hash rates in user-friendly units
    proc formatHashRate(rate: float): string =
      if rate >= 1_000_000_000:
        return fmt"{rate/1_000_000_000:.2f} GH/s"
      elif rate >= 1_000_000:
        return fmt"{rate/1_000_000:.2f} MH/s"
      elif rate >= 1_000:
        return fmt"{rate/1_000:.2f} KH/s"
      else:
        return fmt"{rate:.2f} H/s"
    
    proc formatDuration(seconds: float): string =
      let hours = int(seconds / 3600)
      let minutes = int((seconds mod 3600) / 60)
      let secs = int(seconds mod 60)
      return fmt"{hours:02d}:{minutes:02d}:{secs:02d}"
    
    # Generate hash rate chart data for Chart.js
    let chartData = currentSession.hashRateHistory.mapIt(
      fmt"{{x: {it.timestamp * 1000}, y: {it.hashRate/1_000_000:.2f}}}"
    ).join(", ")
    
    var htmlContent = fmt"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CUDA Miner Benchmark Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
        }}
        
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            overflow: hidden;
        }}
        
        .header {{
            background: linear-gradient(135deg, #4CAF50 0%, #45a049 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }}
        
        .header h1 {{
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }}
        
        .header p {{
            margin: 10px 0 0 0;
            opacity: 0.9;
            font-size: 1.1em;
        }}
        
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            padding: 30px;
        }}
        
        .stat-card {{
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            border-left: 4px solid #4CAF50;
            transition: transform 0.2s;
        }}
        
        .stat-card:hover {{
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }}
        
        .stat-value {{
            font-size: 2em;
            font-weight: bold;
            color: #2c3e50;
        }}
        
        .stat-label {{
            color: #7f8c8d;
            font-size: 0.9em;
            margin-top: 5px;
        }}
        
        .chart-container {{
            padding: 30px;
            background: #f8f9fa;
        }}
        
        .chart-title {{
            text-align: center;
            margin-bottom: 20px;
            font-size: 1.5em;
            color: #2c3e50;
        }}
        
        .config-section, .attempts-section {{
            padding: 30px;
        }}
        
        .section-title {{
            font-size: 1.5em;
            color: #2c3e50;
            margin-bottom: 20px;
            border-bottom: 2px solid #4CAF50;
            padding-bottom: 10px;
        }}
        
        .config-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }}
        
        .config-item {{
            background: #ecf0f1;
            padding: 15px;
            border-radius: 8px;
        }}
        
        .attempts-table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }}
        
        .attempts-table th, .attempts-table td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}
        
        .attempts-table th {{
            background: #4CAF50;
            color: white;
            font-weight: 500;
        }}
        
        .attempts-table tr:nth-child(even) {{
            background: #f9f9f9;
        }}
        
        .success {{
            color: #27ae60;
            font-weight: bold;
        }}
        
        .failed {{
            color: #e74c3c;
        }}
        
        .footer {{
            text-align: center;
            padding: 20px;
            background: #ecf0f1;
            color: #7f8c8d;
        }}
        
        @media (max-width: 768px) {{
            .stats-grid {{
                grid-template-columns: 1fr;
            }}
            
            .config-grid {{
                grid-template-columns: 1fr;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚡ CUDA Miner Benchmark Report</h1>
            <p>Session: {currentSession.sessionId} | Generated: {$now()}</p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value">{formatDuration(currentSession.totalDuration)}</div>
                <div class="stat-label">Total Mining Time</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{currentSession.blocksFound}</div>
                <div class="stat-label">Blocks Found</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{formatHashRate(currentSession.averageHashRate)}</div>
                <div class="stat-label">Average Hash Rate</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{formatHashRate(currentSession.peakHashRate)}</div>
                <div class="stat-label">Peak Hash Rate</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{currentSession.attempts.len}</div>
                <div class="stat-label">Total Attempts</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{metrics.successRate:.2f}%</div>
                <div class="stat-label">Success Rate</div>
            </div>
        </div>
        
        <div class="chart-container">
            <div class="chart-title">Hash Rate Over Time</div>
            <canvas id="hashRateChart" width="400" height="200"></canvas>
        </div>
        
        <div class="config-section">
            <div class="section-title">GPU Configuration</div>
            <div class="config-grid">
                <div class="config-item">
                    <strong>CUDA Blocks:</strong> {currentSession.gpuConfig.blocks}
                </div>
                <div class="config-item">
                    <strong>Threads per Block:</strong> {currentSession.gpuConfig.threads}
                </div>
                <div class="config-item">
                    <strong>Iterations per Thread:</strong> {currentSession.gpuConfig.itersPerThread}
                </div>
                <div class="config-item">
                    <strong>GPU Architecture:</strong> {currentSession.gpuConfig.architecture}
                </div>
            </div>
        </div>
        
        <div class="attempts-section">
            <div class="section-title">Recent Mining Attempts (Last 20)</div>
            <table class="attempts-table">
                <thead>
                    <tr>
                        <th>Block ID</th>
                        <th>Duration</th>
                        <th>Hash Rate</th>
                        <th>Difficulty</th>
                        <th>Result</th>
                        <th>Batch Count</th>
                    </tr>
                </thead>
                <tbody>
"""
    
    # Add last 20 attempts to table
    let recentAttempts = if allAttempts.len > 20: allAttempts[^20..^1] else: allAttempts
    for attempt in recentAttempts.reversed():
      let resultClass = if attempt.found: "success" else: "failed"
      let resultText = if attempt.found: "✅ Block Found" else: "❌ No Solution"
      htmlContent.add(fmt"""
                    <tr>
                        <td>{attempt.blockId}</td>
                        <td>{formatDuration(attempt.duration)}</td>
                        <td>{formatHashRate(attempt.hashRate)}</td>
                        <td>{attempt.difficulty:.2f}</td>
                        <td class="{resultClass}">{resultText}</td>
                        <td>{attempt.batchCount}</td>
                    </tr>
""")
    
    htmlContent.add(fmt"""
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>Report generated by CUDA Miner Benchmarking System</p>
        </div>
    </div>
    
    <script>
        const ctx = document.getElementById('hashRateChart').getContext('2d');
        const chart = new Chart(ctx, {{
            type: 'line',
            data: {{
                datasets: [{{
                    label: 'Hash Rate (MH/s)',
                    data: [{chartData}],
                    borderColor: '#4CAF50',
                    backgroundColor: 'rgba(76, 175, 80, 0.1)',
                    tension: 0.4,
                    fill: true
                }}]
            }},
            options: {{
                responsive: true,
                scales: {{
                    x: {{
                        type: 'time',
                        time: {{
                            unit: 'minute',
                            displayFormats: {{
                                minute: 'HH:mm'
                            }}
                        }},
                        title: {{
                            display: true,
                            text: 'Time'
                        }}
                    }},
                    y: {{
                        title: {{
                            display: true,
                            text: 'Hash Rate (MH/s)'
                        }},
                        beginAtZero: true
                    }}
                }},
                plugins: {{
                    legend: {{
                        display: true,
                        position: 'top'
                    }},
                    title: {{
                        display: true,
                        text: 'Real-time Hash Rate Performance'
                    }}
                }}
            }}
        }});
    </script>
</body>
</html>
""")
    
    writeFile(outputPath, htmlContent)
    echo fmt"🌐 HTML benchmark report saved to: {outputPath}"
    return true
  except Exception as e:
    echo fmt"❌ Error generating HTML report: {e.msg}"
    return false

proc saveBenchmarkReports*(baseFilename: string = ""): tuple[jsonPath: string, htmlPath: string] =
  ## Save both JSON and HTML benchmark reports
  let currentTime = now()
  let timestamp = $currentTime.year & "-" & ($currentTime.month.int).align(2, '0') & "-" & ($currentTime.monthday).align(2, '0') & "_" & ($currentTime.hour).align(2, '0') & "-" & ($currentTime.minute).align(2, '0') & "-" & ($currentTime.second).align(2, '0')
  let baseName = if baseFilename != "": baseFilename else: "benchmark_" & timestamp
  
  let jsonPath = fmt"{baseName}.json"
  let htmlPath = fmt"{baseName}.html"
  
  discard generateJsonReport(jsonPath)
  discard generateHtmlReport(htmlPath)
  
  result = (jsonPath, htmlPath)

proc printBenchmarkSummary*() =
  ## Print a quick summary to console
  if currentSession.attempts.len == 0:
    echo "No benchmark data available"
    return
    
  let metrics = calculateEfficiencyMetrics()
  
  echo "\n" & "=".repeat(60)
  echo "📊 BENCHMARK SUMMARY"
  echo "=".repeat(60)
  echo fmt"Session Duration:     {currentSession.totalDuration:.2f} seconds"
  echo fmt"Blocks Found:         {currentSession.blocksFound}"
  echo fmt"Total Attempts:       {currentSession.attempts.len}"
  echo fmt"Average Hash Rate:    {currentSession.averageHashRate/1_000_000:.2f} MH/s"
  echo fmt"Peak Hash Rate:       {currentSession.peakHashRate/1_000_000:.2f} MH/s"
  echo fmt"Success Rate:         {metrics.successRate:.2f}%"
  echo fmt"Total Hashes:         {currentSession.totalHashes}"
  echo "=".repeat(60)
