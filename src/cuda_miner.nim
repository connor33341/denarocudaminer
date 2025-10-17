# MIT License
#
# Copyright (c) 2025 Connor33341 (https://github.com/Connor33341) and The-Sycorax (https://github.com/The-Sycorax)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

## Integrated CUDA miner for Denaro/Stellaris blockchain in Nim
## 
## Usage: ./cuda_miner <node_url> <address> [options]
## 
## This is a complete rewrite of the Python cuda_miner_standalone.py in Nim,
## providing the same functionality with better performance and integration.
## 
## Base58 decoding is handled by calling Python's base58 package for reliability.

import std/[httpclient, json, strformat, times, math, strutils, os, parseopt, algorithm, osproc, random]
import nimcrypto
import cuda_wrapper
import benchmark

const
  WORKER_REFRESH_SECONDS = 190
  DEFAULT_NODE_URL = "https://stellaris-node.connor33341.dev/"
  DEFAULT_POOL_URL = "https://stellaris-pool.connor33341.dev" # Remove the end / or err
  
  STATUS_PENDING = 0
  STATUS_SUCCESS = 1
  STATUS_STALE = 2
  STATUS_FAILED = 3
  
    # Developer fee configuration
  DEFAULT_DEVELOPER_ADDRESS = "DWMVFcRTZ8UMaWr2vsb7XkTmh7zaA57BQaDRGiAKB6qX6"  # Replace with actual developer address
  DEFAULT_DEVELOPER_FEE_PERCENTAGE = 5.0  # 5% default

type
  MiningMode = enum
    ModeStandalone
    ModePool

  MinerConfig = object
    mode: MiningMode
    nodeUrl: string
    poolUrl: string
    address: string
    workerName: string
    minerId: string
    maxBlocks: int
    blocks: uint
    threads: uint
    itersPerThread: uint
    gpuArch: string
    enableBenchmark: bool
    benchmarkOutput: string
    developerAddress: string
    developerFeePercentage: float

  Block = object
    hash: string
    id: int

  MiningInfo = object
    lastBlock: Block
    difficulty: float
    pendingTransactions: seq[string]
    merkleRoot: string
  
  PoolWork = object
    blockHeight: int
    difficulty: float
    previousHash: string
    merkleRoot: string
    timestamp: int
    nonceStart: uint32
    nonceEnd: uint32
    poolAddress: string
    transactions: seq[string]

proc base58DecodePython(input: string): seq[byte] =
  ## Base58 decoder using Python base58 package (reliable implementation)
  let currentDir = getCurrentDir()
  
  # Try multiple possible paths for the Python script
  var pythonScript = ""
  let possiblePaths = [
    currentDir / "src" / "base58_decoder.py",           # From project root
    currentDir / ".." / "src" / "base58_decoder.py",    # From benchmarks subdirectory
    currentDir / "base58_decoder.py"                    # Direct path
  ]
  
  for path in possiblePaths:
    if fileExists(path):
      pythonScript = path
      break
  
  if pythonScript == "":
    raise newException(ValueError, "Could not find base58_decoder.py script")
  
  # Call Python script to decode base58
  let (output, exitCode) = execCmdEx(fmt"python3 {pythonScript} {input}")
  
  if exitCode != 0:
    raise newException(ValueError, fmt"Python base58 decode failed: {output}")
  
  # Parse hex output from Python script
  let hexResult = output.strip()
  try:
    result = cast[seq[byte]](hexResult.parseHexStr())
  except:
    raise newException(ValueError, fmt"Failed to parse Python base58 decode result: {hexResult}")

proc stringToBytes(address: string): seq[byte] =
  ## Convert address (hex or base58) to bytes
  try:
    # First try hex decode
    result = cast[seq[byte]](address.parseHexStr())
  except:
    try:
      # If hex fails, try base58 decode using Python
      result = base58DecodePython(address)
    except:
      raise newException(ValueError, "Failed to decode address as hex or base58")

proc buildPrefix(lastBlockHashHex: string, addressBytes: seq[byte], merkleRootHex: string, difficulty: float): seq[byte] =
  ## Build constant block prefix (no nonce). Matches Python miner exactly.
  let lastBlockHash = cast[seq[byte]](lastBlockHashHex.parseHexStr())
  let merkleRoot = cast[seq[byte]](merkleRootHex.parseHexStr())
  let difficultyScaled = uint16(difficulty * 10)
  let timestamp = uint32(epochTime())
  
  # Build base prefix
  result = lastBlockHash & 
           addressBytes & 
           merkleRoot & 
           cast[seq[byte]](@[
             byte(timestamp and 0xFF),
             byte((timestamp shr 8) and 0xFF), 
             byte((timestamp shr 16) and 0xFF),
             byte((timestamp shr 24) and 0xFF)
           ]) &
           cast[seq[byte]](@[
             byte(difficultyScaled and 0xFF),
             byte((difficultyScaled shr 8) and 0xFF)
           ])
  
  # Add leading byte if address is 33 bytes (compressed public key)
  if addressBytes.len == 33:
    result = @[byte(2)] & result

proc calculateDeveloperFeeFrequency(percentage: float): int =
  ## Calculate the frequency from percentage (e.g., 5% = every 20th block)
  if percentage <= 0.0:
    return 0  # No developer fees
  elif percentage >= 100.0:
    return 1  # Every block is a developer fee
  else:
    return int(ceil(100.0 / percentage))

proc isDeveloperFeeBlock(blockId: int, frequency: int): bool =
  ## Check if the given block ID should be mined to the developer address
  if frequency <= 0:
    return false
  return (blockId + 1) mod frequency == 0

proc getMiningAddress(config: MinerConfig, nextBlockId: int): string =
  ## Get the address to use for mining the next block
  let frequency = calculateDeveloperFeeFrequency(config.developerFeePercentage)
  if isDeveloperFeeBlock(nextBlockId, frequency):
    result = config.developerAddress
    echo fmt"Block {nextBlockId + 1} will be mined to developer address ({config.developerFeePercentage}% fee, every {frequency} blocks)"
  else:
    result = config.address

proc computeFractionalCharset(difficulty: float): (uint, string) =
  ## Returns (idiff, allowed_charset_lower)
  let decimal = difficulty mod 1.0
  let idiff = uint(difficulty)
  let charset = if decimal > 0:
    let count = int(ceil(16.0 * (1.0 - decimal)))
    "0123456789abcdef"[0..<count]
  else:
    "0123456789abcdef"
  (idiff, charset)

proc makeLastBlockChunk(lastBlockHashHex: string, idiff: uint): string =
  ## Returns the suffix of last_block_hash with length idiff (lowercase hex)
  if idiff > 0:
    result = lastBlockHashHex[^int(idiff)..^1].toLower()
  else:
    result = ""

proc fetchMiningInfo(client: HttpClient, nodeUrl: string): MiningInfo =
  ## Fetch mining information from the node
  try:
    let response = client.getContent(fmt"{nodeUrl}get_mining_info")
    let jsonData = parseJson(response)
    let resultData = jsonData["result"]
    
    result.lastBlock.hash = resultData["last_block"]["hash"].getStr()
    result.lastBlock.id = resultData["last_block"]["id"].getInt()
    result.difficulty = resultData["difficulty"].getFloat()
    result.pendingTransactions = @[]
    for tx in resultData["pending_transactions_hashes"]:
      result.pendingTransactions.add(tx.getStr())
    result.merkleRoot = resultData["merkle_root"].getStr()
  except Exception as e:
    echo "ERROR in fetchMiningInfo: ", e.msg
    raise e

proc submitBlock(client: HttpClient, nodeUrl: string, lastBlockId: int, txs: seq[string], blockContent: seq[byte]): int =
  ## Submit a candidate block to the node and return a STATUS_* code
  try:
    let payload = %*{
      "block_content": toHex(blockContent).toLower(),
      "txs": txs,
      "id": lastBlockId + 1
    }
    
    client.headers["Content-Type"] = "application/json"
    
    let response = client.postContent(fmt"{nodeUrl}push_block", $payload)
    let jsonResponse = parseJson(response)
    
    if jsonResponse.hasKey("ok") and jsonResponse["ok"].getBool():
      echo "Node Response: BLOCK MINED SUCCESSFULLY!"
      return STATUS_SUCCESS
    else:
      let errorMessage = jsonResponse.getOrDefault("message").getStr("").toLower()
      if "stale" in errorMessage or "already in chain" in errorMessage:
        echo "Node Response: Block was stale. Another miner was faster."
        return STATUS_STALE
      else:
        echo fmt"Node Response: Block rejected: {jsonResponse}"
        return STATUS_FAILED
        
  except:
    echo fmt"Error submitting block: {getCurrentExceptionMsg()}"
    return STATUS_FAILED

proc registerWithPool(client: HttpClient, poolUrl: string, minerId: string, walletAddress: string, workerName: string): bool =
  ## Register with the mining pool
  try:
    let payload = %*{
      "miner_id": minerId,
      "wallet_address": walletAddress,
      "worker_name": workerName
    }
    
    client.headers["Content-Type"] = "application/json"
    let response = client.postContent(fmt"{poolUrl}/api/register", $payload)
    let jsonResponse = parseJson(response)
    
    if jsonResponse.hasKey("success") and jsonResponse["success"].getBool():
      echo fmt"✅ Registered with pool: {minerId}"
      return true
    else:
      echo fmt"❌ Registration failed: {jsonResponse}"
      return false
  except Exception as e:
    echo fmt"❌ Registration error: {e.msg}"
    return false

proc getPoolWork(client: HttpClient, poolUrl: string, minerId: string): PoolWork =
  ## Request work from the mining pool
  try:
    let payload = %*{
      "miner_id": minerId
    }
    
    client.headers["Content-Type"] = "application/json"
    let response = client.postContent(fmt"{poolUrl}/api/work", $payload)
    let jsonData = parseJson(response)
    
    result.blockHeight = jsonData["block_height"].getInt()
    result.difficulty = jsonData["difficulty"].getFloat()
    result.previousHash = jsonData["previous_hash"].getStr()
    result.merkleRoot = jsonData["merkle_root"].getStr()
    result.timestamp = jsonData["timestamp"].getInt()
    result.nonceStart = uint32(jsonData["nonce_start"].getBiggestInt())
    result.nonceEnd = uint32(jsonData["nonce_end"].getBiggestInt())
    result.poolAddress = jsonData["pool_address"].getStr()
    result.transactions = @[]
    for tx in jsonData["transactions"]:
      result.transactions.add(tx.getStr())
    
  except Exception as e:
    echo fmt"❌ Error getting work: {e.msg}"
    raise e

proc submitShare(client: HttpClient, poolUrl: string, minerId: string, blockHeight: int,
                 nonce: uint32, blockContentHex: string, blockHash: string, isValidBlock: bool): bool =
  ## Submit a valid block to the pool
  try:
    let payload = %*{
      "miner_id": minerId,
      "block_height": blockHeight,
      "nonce": nonce,
      "block_content_hex": blockContentHex,
      "block_hash": blockHash,
      "is_valid_block": isValidBlock
    }
    
    client.headers["Content-Type"] = "application/json"
    let response = client.postContent(fmt"{poolUrl}/api/share", $payload)
    let jsonResponse = parseJson(response)
    
    if jsonResponse.hasKey("block_found") and jsonResponse["block_found"].getBool():
      echo "🎉🎉🎉 BLOCK FOUND! 🎉🎉🎉"
      return true
    return false
    
  except Exception as e:
    echo fmt"❌ Error submitting share: {e.msg}"
    return false

proc submitWorkProof(client: HttpClient, poolUrl: string, minerId: string, blockHeight: int,
                     nonceStart: uint32, nonceEnd: uint32, bestNonce: uint32,
                     bestHash: string, hashesComputed: uint64): bool =
  ## Submit proof that work was completed
  try:
    let payload = %*{
      "miner_id": minerId,
      "block_height": blockHeight,
      "nonce_start": nonceStart,
      "nonce_end": nonceEnd,
      "best_nonce": bestNonce,
      "best_hash": bestHash,
      "hashes_computed": int(hashesComputed)
    }
    
    client.headers["Content-Type"] = "application/json"
    let response = client.postContent(fmt"{poolUrl}/api/work_proof", $payload)
    let jsonResponse = parseJson(response)
    
    if jsonResponse.hasKey("success") and jsonResponse["success"].getBool():
      let workUnits = jsonResponse.getOrDefault("work_units").getInt(0)
      echo fmt"✅ Work proof accepted ({workUnits} work units this round)"
      return true
    else:
      echo fmt"❌ Work proof rejected: {jsonResponse}"
      return false
      
  except Exception as e:
    echo fmt"❌ Error submitting work proof: {e.msg}"
    return false

proc minePoolRange(config: MinerConfig, prefixBytes: seq[byte], lastChunkLc: string,
                   idiff: uint, allowedCharset: string, nonceStart: uint32, nonceEnd: uint32,
                   blockHeight: int): tuple[found: bool, nonce: uint32, bestNonce: uint32, bestHash: string, hashesComputed: uint64] =
  ## Mine a specific nonce range for pool mining
  ## Returns: (found, nonce, bestNonce, bestHash, hashesComputed)
  
  let startTime = epochTime()
  var foundNonce: uint32 = uint32(0xFFFFFFFF)
  var totalHashes: uint64 = 0
  var bestNonce = nonceStart
  var bestHash = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  
  # Calculate total nonces in range
  let totalNonces = uint64(nonceEnd - nonceStart)
  let hashesPerBatch = uint64(config.blocks * config.threads * config.itersPerThread)
  
  # Calculate the base offset to shift CUDA kernel search into our assigned range
  # The CUDA kernel calculates: nonce = start_offset + tid + base_offset
  # We want it to search [nonceStart, nonceEnd), so we set base_offset accordingly
  let kernelBaseOffset = uint32(nonceStart)
  
  # Calculate number of batches needed to cover the range
  var batchIdx = 0
  const TIMEOUT_SECONDS = 280  # Match pool_miner timeout
  const HASHRATE_CHECK = 5_000_000  # Report every 5M hashes
  const SAMPLE_INTERVAL = 100_000  # Sample best hash every 100k hashes
  
  var lastSampleHashes: uint64 = 0
  
  while foundNonce == uint32(0xFFFFFFFF) and (epochTime() - startTime) < TIMEOUT_SECONDS:
    # Calculate current nonce offset within our range
    let currentOffset = uint64(batchIdx) * hashesPerBatch
    if currentOffset >= totalNonces:
      # Exhausted the range
      break
    
    # Adjust the batch offset for CUDA - it needs to know how many iterations
    # from the start of our range (nonceStart) we are
    # CUDA calculates: base_offset + (batch_offset * iters_per_thread * global_step)
    # But base_offset is added in the kernel, so we pass batchIdx for the iteration count
    
    # Mine this batch - CUDA kernel searches for valid blocks
    # Note: The CUDA kernel uses: nonce = start_offset + tid + base_offset + (batch_offset * iters * global_step)
    # Since base_offset in CUDA is set to batch_offset * iters * global_step,
    # we need to calculate the starting nonce for this batch correctly
    let nonce = mineNonces(
      cast[seq[uint8]](prefixBytes),
      lastChunkLc,
      idiff,
      allowedCharset,
      config.blocks,
      config.threads,
      config.itersPerThread,
      uint(batchIdx) + uint(kernelBaseOffset div hashesPerBatch)  # Shift into our assigned range
    )
    
    totalHashes += hashesPerBatch
    
    # Check if we found a valid block (meets full network difficulty)
    if nonce != uint32(0xFFFFFFFF):
      # Verify the nonce is actually in our assigned range
      if nonce >= nonceStart and nonce < nonceEnd:
        foundNonce = nonce
        # Calculate hash for the found nonce
        let nonceBytes = cast[seq[byte]](@[
          byte(nonce and 0xFF),
          byte((nonce shr 8) and 0xFF),
          byte((nonce shr 16) and 0xFF),
          byte((nonce shr 24) and 0xFF)
        ])
        let blockContent = prefixBytes & nonceBytes
        bestHash = ($sha256.digest(blockContent)).toLower()
        bestNonce = nonce
        break
      else:
        # Nonce outside our range, ignore it (shouldn't happen but be safe)
        echo fmt"Warning: Found nonce {nonce} outside assigned range [{nonceStart}, {nonceEnd})"
    
    # Periodically sample hashes to find the "best" (lowest) hash for proof of work
    # This shows we actually did the work even if we didn't find a valid block
    if totalHashes - lastSampleHashes >= SAMPLE_INTERVAL:
      # Sample a few nonces from the range we just mined
      let sampleStart = nonceStart + uint32(currentOffset)
      let sampleEnd = min(sampleStart + 10, nonceEnd)  # Sample 10 nonces
      
      for sampleNonce in sampleStart..<sampleEnd:
        let nonceBytes = cast[seq[byte]](@[
          byte(sampleNonce and 0xFF),
          byte((sampleNonce shr 8) and 0xFF),
          byte((sampleNonce shr 16) and 0xFF),
          byte((sampleNonce shr 24) and 0xFF)
        ])
        let blockContent = prefixBytes & nonceBytes
        let hash = ($sha256.digest(blockContent)).toLower()
        
        # Keep track of lowest (best) hash
        if hash < bestHash:
          bestHash = hash
          bestNonce = sampleNonce
      
      lastSampleHashes = totalHashes
    
    inc batchIdx
    
    # Print hashrate periodically
    if totalHashes > 0 and totalHashes mod HASHRATE_CHECK == 0:
      let elapsed = epochTime() - startTime
      if elapsed > 0:
        let hashrate = float(totalHashes) / elapsed / 1000.0
        let progress = (float(currentOffset) / float(totalNonces)) * 100.0
        echo fmt"Mining: {hashrate:.1f} kH/s ({progress:.1f}% of range, best: {bestHash[0..15]}...)"
      if elapsed > 0:
        let hashrate = float(totalHashes) / elapsed / 1000.0
        let progress = (float(currentOffset) / float(totalNonces)) * 100.0
        echo fmt"Mining: {hashrate:.1f} kH/s ({progress:.1f}% of range, best: {bestHash[0..15]}...)"
  
  # Final sample if we didn't find a block
  if foundNonce == uint32(0xFFFFFFFF):
    # Sample the last nonces we mined
    let finalSampleStart = nonceStart + uint32(min(totalHashes, totalNonces) - 10)
    let finalSampleEnd = min(finalSampleStart + 10, nonceEnd)
    
    for sampleNonce in finalSampleStart..<finalSampleEnd:
      let nonceBytes = cast[seq[byte]](@[
        byte(sampleNonce and 0xFF),
        byte((sampleNonce shr 8) and 0xFF),
        byte((sampleNonce shr 16) and 0xFF),
        byte((sampleNonce shr 24) and 0xFF)
      ])
      let blockContent = prefixBytes & nonceBytes
      let hash = ($sha256.digest(blockContent)).toLower()
      
      if hash < bestHash:
        bestHash = hash
        bestNonce = sampleNonce
  
  let elapsed = epochTime() - startTime
  let hashrate = if elapsed > 0: float(totalHashes) / elapsed / 1000.0 else: 0.0
  
  if foundNonce != uint32(0xFFFFFFFF):
    echo fmt"🎉 VALID BLOCK FOUND! Nonce: {foundNonce}, Hash: {bestHash[0..16]}..., Hashrate: {hashrate:.1f} kH/s"
    result = (true, foundNonce, bestNonce, bestHash, totalHashes)
  else:
    echo fmt"Range completed: {hashrate:.1f} kH/s, {totalHashes} hashes, Best hash: {bestHash[0..15]}..."
    result = (false, foundNonce, bestNonce, bestHash, totalHashes)

proc parseArgs(): MinerConfig =
  ## Parse command line arguments
  result = MinerConfig(
    mode: ModeStandalone,
    nodeUrl: DEFAULT_NODE_URL,
    poolUrl: "",
    address: "",
    workerName: "",
    minerId: "",
    maxBlocks: 0,
    blocks: 1024,
    threads: 512,
    itersPerThread: 20000,
    gpuArch: "sm_89",
    enableBenchmark: false,
    benchmarkOutput: "benchmark",
    developerAddress: DEFAULT_DEVELOPER_ADDRESS,
    developerFeePercentage: DEFAULT_DEVELOPER_FEE_PERCENTAGE
  )
  
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "a", "address":
        result.address = p.val
      of "n", "node":
        result.nodeUrl = p.val
        if not result.nodeUrl.endsWith("/"):
          result.nodeUrl.add("/")
      of "pool":
        if p.val == "":
          result.poolUrl = DEFAULT_POOL_URL
        else:
          result.poolUrl = p.val
          if not result.poolUrl.endsWith("/"):
            result.poolUrl.add("/")
        result.mode = ModePool
      of "worker-name":
        result.workerName = p.val
      of "m", "max-blocks":
        if p.val == "":
          raise newException(ValueError, fmt"Value required for --max-blocks option")
        result.maxBlocks = parseInt(p.val)
      of "blocks":
        if p.val == "":
          raise newException(ValueError, fmt"Value required for --blocks option")
        result.blocks = uint(parseInt(p.val))
      of "threads":
        if p.val == "":
          raise newException(ValueError, fmt"Value required for --threads option")
        result.threads = uint(parseInt(p.val))
      of "iters-per-thread":
        if p.val == "":
          raise newException(ValueError, fmt"Value required for --iters-per-thread option")
        result.itersPerThread = uint(parseInt(p.val))
      of "gpu-arch":
        result.gpuArch = p.val
      of "benchmark":
        result.enableBenchmark = true
        if p.val != "":
          result.benchmarkOutput = p.val
      of "benchmark-output":
        result.benchmarkOutput = p.val
      of "developer-address":
        result.developerAddress = p.val
      of "developer-fee-percentage":
        if p.val == "":
          raise newException(ValueError, fmt"Value required for --developer-fee-percentage option")
        result.developerFeePercentage = parseFloat(p.val)
      of "h", "help":
        echo """
Integrated CUDA miner for Denaro/Stellaris blockchain

Usage: cuda_miner [options]

Options:
  -a, --address <ADDRESS>      Mining address to receive rewards (required)
  -n, --node <URL>             URL of the node API (default: http://127.0.0.1:3006/)
  --pool [URL]                 Enable pool mining mode (default: https://stellaris-pool.connor33341.dev/)
  --worker-name <NAME>         Worker name for pool mining (optional)
  -m, --max-blocks <N>         Max number of blocks to mine before exit
  --blocks <N>                 CUDA grid blocks per launch (default: 1024)
  --threads <N>                CUDA threads per block (default: 512)
  --iters-per-thread <N>       Iterations per thread per kernel batch (default: 20000)
  --gpu-arch <ARCH>            GPU architecture for compilation (default: sm_89)
  --benchmark [NAME]           Enable benchmarking with optional session name
  --benchmark-output <PATH>    Set output path for benchmark reports (default: benchmark)
  --developer-address <ADDR>   Developer address for fee blocks (default: built-in)
  --developer-fee-percentage <PCT> Developer fee percentage (default: 5.0, means every 20th block)
  -h, --help                   Show this help message
"""
        quit(0)
    of cmdArgument:
      # Ignore positional arguments when using flags
      discard
  
  if result.address == "":
    echo "Error: Mining address is required. Use -a <address> or --address <address>"
    quit(1)
  
  # Generate worker name and miner ID for pool mode
  if result.mode == ModePool:
    if result.workerName == "":
      # Generate random worker name
      randomize()
      result.workerName = fmt"cuda-worker-{rand(99999999):08x}"
    
    # Generate miner ID (first 12 chars of address + worker name)
    result.minerId = result.address[0..min(11, result.address.len-1)] & "_" & result.workerName

proc minePool(config: MinerConfig) =
  ## Pool mining mode
  echo "🌊 Pool Mining Mode"
  echo fmt"Pool URL: {config.poolUrl}"
  echo fmt"Miner ID: {config.minerId}"
  echo fmt"Worker: {config.workerName}"
  echo fmt"Wallet: {config.address}"
  
  # Initialize CUDA
  echo "Initializing CUDA..."
  if not initCudaMiner():
    echo "Failed to initialize CUDA miner"
    quit(1)
  echo "CUDA initialized successfully!"
  
  var client = newHttpClient(timeout = 30000)  # 30 second timeout
  
  # Register with pool
  echo "Registering with pool..."
  if not registerWithPool(client, config.poolUrl, config.minerId, config.address, config.workerName):
    echo "Failed to register with pool. Exiting."
    quit(1)
  
  echo "🚀 Starting pool mining..."
  
  var lastBlockHeight = -1  # Track last block we worked on
  
  while true:
    try:
      # Get work from pool
      echo "Requesting work from pool..."
      let work = getPoolWork(client, config.poolUrl, config.minerId)
      
      echo fmt"📦 Mining block #{work.blockHeight}"
      echo fmt"   Difficulty: {work.difficulty}"
      echo fmt"   Nonce range: {work.nonceStart} - {work.nonceEnd}"
      echo fmt"   Transactions: {work.transactions.len}"
      
      # Validate nonce range
      if work.nonceStart < 0 or work.nonceEnd < 0:
        echo "❌ Invalid nonce range (negative values)"
        sleep(5000)
        continue
      
      if work.nonceEnd > uint32.high:
        echo fmt"❌ Nonce range exceeds 32-bit limit"
        sleep(5000)
        continue
      
      # Prepare mining
      var addressBytes: seq[byte]
      try:
        addressBytes = stringToBytes(work.poolAddress)
      except Exception as e:
        echo fmt"ERROR converting pool address: {e.msg}"
        sleep(5000)
        continue
      
      # Build prefix with pool's timestamp
      let lastBlockHash = cast[seq[byte]](work.previousHash.parseHexStr())
      let merkleRoot = cast[seq[byte]](work.merkleRoot.parseHexStr())
      let difficultyScaled = uint16(work.difficulty * 10)
      let timestamp = uint32(work.timestamp)
      
      # Build base prefix
      var prefixBytes = lastBlockHash & 
                        addressBytes & 
                        merkleRoot & 
                        cast[seq[byte]](@[
                          byte(timestamp and 0xFF),
                          byte((timestamp shr 8) and 0xFF), 
                          byte((timestamp shr 16) and 0xFF),
                          byte((timestamp shr 24) and 0xFF)
                        ]) &
                        cast[seq[byte]](@[
                          byte(difficultyScaled and 0xFF),
                          byte((difficultyScaled shr 8) and 0xFF)
                        ])
      
      # Add leading byte if address is 33 bytes (compressed public key)
      if addressBytes.len == 33:
        prefixBytes = @[byte(2)] & prefixBytes
      
      let (idiff, allowedCharset) = computeFractionalCharset(work.difficulty)
      let lastChunkLc = makeLastBlockChunk(work.previousHash, idiff)
      
      # Mine the assigned range
      let result = minePoolRange(
        config,
        prefixBytes,
        lastChunkLc,
        idiff,
        allowedCharset,
        work.nonceStart,
        work.nonceEnd,
        work.blockHeight
      )
      
      if result.found:
        # Valid block found!
        let nonceBytes = cast[seq[byte]](@[
          byte(result.nonce and 0xFF),
          byte((result.nonce shr 8) and 0xFF),
          byte((result.nonce shr 16) and 0xFF),
          byte((result.nonce shr 24) and 0xFF)
        ])
        let blockContent = prefixBytes & nonceBytes
        let blockContentHex = toHex(blockContent).toLower()
        
        let blockFound = submitShare(
          client,
          config.poolUrl,
          config.minerId,
          work.blockHeight,
          result.nonce,
          blockContentHex,
          result.bestHash,
          true  # is_valid_block
        )
        
        # If block was actually found and accepted, wait a bit for the network to process it
        if blockFound:
          lastBlockHeight = work.blockHeight
          echo "⏳ Waiting for network to process block..."
          sleep(5000)  # Wait 5 seconds before requesting new work
      else:
        # Range completed, submit work proof
        let proofAccepted = submitWorkProof(
          client,
          config.poolUrl,
          config.minerId,
          work.blockHeight,
          work.nonceStart,
          work.nonceEnd,
          result.bestNonce,
          result.bestHash,
          result.hashesComputed
        )
      
    except Exception as e:
      echo fmt"❌ Error: {e.msg}"
      echo "   Retrying in 5 seconds..."
      sleep(5000)
      sleep(5000)

proc main() =
  let config = parseArgs()
  
  # Check if pool mode
  if config.mode == ModePool:
    minePool(config)
    return
  
  # Standalone mining mode
  echo fmt"Starting CUDA miner for address: {config.address}"
  echo fmt"Connecting to node: {config.nodeUrl}"
  echo fmt"GPU launch dims: blocks={config.blocks}, threads={config.threads}, iters_per_thread={config.itersPerThread}"
  echo fmt"GPU architecture: {config.gpuArch}"
  let feeFrequency = calculateDeveloperFeeFrequency(config.developerFeePercentage)
  echo fmt"Developer fee: {config.developerFeePercentage}% (every {feeFrequency} blocks to {config.developerAddress})"
  if config.maxBlocks > 0:
    echo fmt"Will stop after mining {config.maxBlocks} block(s)."
  
  # Initialize benchmarking if enabled
  if config.enableBenchmark:
    let currentTime = now()
    let sessionId = if config.benchmarkOutput == "benchmark": 
      "mining_session_" & $currentTime.year & "-" & ($currentTime.month.int).align(2, '0') & "-" & ($currentTime.monthday).align(2, '0') & "_" & ($currentTime.hour).align(2, '0') & "-" & ($currentTime.minute).align(2, '0') & "-" & ($currentTime.second).align(2, '0')
    else: 
      config.benchmarkOutput
    
    let gpuConfig = GPUConfig(
      blocks: config.blocks,
      threads: config.threads,
      itersPerThread: config.itersPerThread,
      architecture: config.gpuArch
    )
    
    initBenchmarkSession(sessionId, gpuConfig)
  
  # Initialize CUDA
  echo "Initializing CUDA..."
  if not initCudaMiner():
    echo "Failed to initialize CUDA miner"
    quit(1)
  echo "CUDA initialized successfully!"
  
  var client = newHttpClient()
  var minedBlocksCount = 0
  var currentBlockId = -1  # Track current block being mined
  var batchIdx = 0         # Persist batch index across mining info refreshes
  const MAX_BATCH_IDX = 1000  # Reset batch index after this many attempts to prevent overflow
  var clientRefreshCounter = 0
  const CLIENT_REFRESH_INTERVAL = 500  # Refresh HTTP client every N mining attempts
  
  while true:
    # Periodically refresh HTTP client to prevent connection issues
    inc clientRefreshCounter
    if clientRefreshCounter >= CLIENT_REFRESH_INTERVAL:
      client.close()
      client = newHttpClient()
      clientRefreshCounter = 0
      echo "Refreshed HTTP client connection"
    
    # Fetch mining info
    echo "Fetching mining information from node..."
    var miningInfo: MiningInfo
    try:
      miningInfo = fetchMiningInfo(client, config.nodeUrl)
    except Exception as e:
      echo fmt"Error fetching data: {e.msg}. Retrying in 5 seconds..."
      sleep(5000)
      continue
    
    # Prepare mining inputs
    let difficulty = miningInfo.difficulty
    let lastBlockHashHex = miningInfo.lastBlock.hash
    let lastBlockId = miningInfo.lastBlock.id
    let txs = miningInfo.pendingTransactions
    let merkleRootHex = miningInfo.merkleRoot
    
    # Reset batch index if we're starting to mine a new block or if it gets too large
    if currentBlockId != lastBlockId:
      currentBlockId = lastBlockId
      batchIdx = 0
      echo fmt"Starting work on new block {lastBlockId + 1}"
    elif batchIdx >= MAX_BATCH_IDX:
      echo fmt"Resetting batch index after {batchIdx} attempts to prevent performance degradation"
      batchIdx = 0
    else:
      # Add periodic progress indicator for long-running blocks
      if batchIdx > 0 and batchIdx mod 50 == 0:
        echo fmt"Mining attempt {batchIdx} on block {lastBlockId + 1}..."
    
    # Determine which address to use for this block
    let miningAddress = getMiningAddress(config, lastBlockId)
    
    var addressBytes: seq[byte]
    try:
      addressBytes = stringToBytes(miningAddress)
    except Exception as e:
      echo "ERROR converting address: ", e.msg
      continue
    
    echo fmt"Difficulty: {difficulty}"
    echo fmt"New Block Number: {lastBlockId + 1}"
    echo fmt"Confirming {txs.len} transactions"
    echo fmt"Using Merkle Root provided by node: {merkleRootHex}"
    echo fmt"Mining to address: {miningAddress}"
    
    let prefixBytes = buildPrefix(lastBlockHashHex, addressBytes, merkleRootHex, difficulty)
    let (idiff, allowedCharset) = computeFractionalCharset(difficulty)
    let lastChunkLc = makeLastBlockChunk(lastBlockHashHex, idiff)
    
    # Search parameters for single worker
    let startTime = epochTime()
    var foundNonce: uint32 = uint32(0xFFFFFFFF)
    var totalHashesThisAttempt: uint64 = 0
    
    while (epochTime() - startTime) < WORKER_REFRESH_SECONDS:
      # Launch CUDA kernel
      let nonce = mineNonces(
        cast[seq[uint8]](prefixBytes),
        lastChunkLc,
        idiff,
        allowedCharset,
        config.blocks,
        config.threads,
        config.itersPerThread,
        uint(batchIdx)
      )
      
      # Calculate hashes for this batch
      let hashesThisBatch = uint64(config.blocks * config.threads * config.itersPerThread)
      totalHashesThisAttempt += hashesThisBatch
      
      if nonce != uint32(0xFFFFFFFF):
        foundNonce = nonce
        break
      
      inc batchIdx
    
    let endTime = epochTime()
    
    # Record mining attempt for benchmarking
    if config.enableBenchmark:
      recordMiningAttempt(
        lastBlockId,
        startTime,
        endTime, 
        totalHashesThisAttempt,
        difficulty,
        foundNonce != uint32(0xFFFFFFFF),
        foundNonce,
        batchIdx
      )
    
    if foundNonce == uint32(0xFFFFFFFF):
      echo fmt"No solution in batch {batchIdx}. Refreshing mining info..."
      echo ""
      continue
    
    # Construct block content with found nonce
    let nonceBytes = cast[seq[byte]](@[
      byte(foundNonce and 0xFF),
      byte((foundNonce shr 8) and 0xFF),
      byte((foundNonce shr 16) and 0xFF),
      byte((foundNonce shr 24) and 0xFF)
    ])
    let blockContent = prefixBytes & nonceBytes
    
    echo ""
    echo "Potential block found! Submitting to node..."
    echo fmt"Block Content: {toHex(blockContent).toLower()}"
    echo "Transactions: " & txs.join(",")
    
    let status = submitBlock(client, config.nodeUrl, lastBlockId, txs, blockContent)
    
    if status == STATUS_SUCCESS:
      inc minedBlocksCount
      let maxBlocksStr = if config.maxBlocks > 0: $config.maxBlocks else: "∞"
      echo fmt"Total blocks mined: {minedBlocksCount} / {maxBlocksStr}"
      if config.maxBlocks > 0 and minedBlocksCount >= config.maxBlocks:
        echo fmt"Reached max number of blocks to mine ({config.maxBlocks}). Exiting."
        break
      echo "Preparing for next block..."
      echo ""
      sleep(2000)
    elif status == STATUS_STALE:
      echo "Block was stale (another miner was faster). Restarting with fresh data..."
      echo ""
      sleep(2000)
    else: # STATUS_FAILED
      echo "Block submission failed due to an error. Restarting with fresh data..."
      echo ""
      sleep(2000)
  
  # Finalize benchmarking session and generate reports
  if config.enableBenchmark:
    finalizeBenchmarkSession()
    printBenchmarkSummary()
    
    let (jsonPath, htmlPath) = saveBenchmarkReports(config.benchmarkOutput)
    echo fmt"💾 Benchmark reports saved:"
    echo fmt"   JSON: {jsonPath}"
    echo fmt"   HTML: {htmlPath}"

when isMainModule:
  try:
    main()
  except CatchableError as e:
    echo ""
    echo fmt"ERROR: {e.msg}"
    echo fmt"Exception type: {$e.name}"
    echo "Exiting miner."
    
    # Save benchmark reports even if exiting early
    if isSessionActive:
      finalizeBenchmarkSession()
      printBenchmarkSummary()
      let (jsonPath, htmlPath) = saveBenchmarkReports()
      echo fmt"💾 Emergency benchmark reports saved:"
      echo fmt"   JSON: {jsonPath}"
      echo fmt"   HTML: {htmlPath}"
    
    quit(0)
