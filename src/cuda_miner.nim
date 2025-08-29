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

import std/[httpclient, json, strformat, times, math, strutils, os, parseopt, algorithm, osproc]
import nimcrypto
import cuda_wrapper

const
  WORKER_REFRESH_SECONDS = 190
  DEFAULT_NODE_URL = "https://stellaris-node.connor33341.dev/"
  
  STATUS_PENDING = 0
  STATUS_SUCCESS = 1
  STATUS_STALE = 2
  STATUS_FAILED = 3

type
  MinerConfig = object
    nodeUrl: string
    address: string
    maxBlocks: int
    blocks: uint
    threads: uint
    itersPerThread: uint
    gpuArch: string

  Block = object
    hash: string
    id: int

  MiningInfo = object
    lastBlock: Block
    difficulty: float
    pendingTransactions: seq[string]
    merkleRoot: string

proc base58DecodePython(input: string): seq[byte] =
  ## Base58 decoder using Python base58 package (reliable implementation)
  let currentDir = getCurrentDir()
  let pythonScript = currentDir / "src" / "base58_decoder.py"
  
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

proc parseArgs(): MinerConfig =
  ## Parse command line arguments
  result = MinerConfig(
    nodeUrl: DEFAULT_NODE_URL,
    address: "",
    maxBlocks: 0,
    blocks: 1024,
    threads: 512,
    itersPerThread: 20000,
    gpuArch: "sm_89"
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
      of "m", "max-blocks":
        result.maxBlocks = parseInt(p.val)
      of "blocks":
        result.blocks = uint(parseInt(p.val))
      of "threads":
        result.threads = uint(parseInt(p.val))
      of "iters-per-thread":
        result.itersPerThread = uint(parseInt(p.val))
      of "gpu-arch":
        result.gpuArch = p.val
      of "h", "help":
        echo """
Integrated CUDA miner for Denaro/Stellaris blockchain

Usage: cuda_miner [options]

Options:
  -a, --address <ADDRESS>      Mining address to receive rewards (required)
  -n, --node <URL>             URL of the node API (default: http://127.0.0.1:3006/)
  -m, --max-blocks <N>         Max number of blocks to mine before exit
  --blocks <N>                 CUDA grid blocks per launch (default: 1024)
  --threads <N>                CUDA threads per block (default: 512)
  --iters-per-thread <N>       Iterations per thread per kernel batch (default: 20000)
  --gpu-arch <ARCH>            GPU architecture for compilation (default: sm_89)
  -h, --help                   Show this help message
"""
        quit(0)
    of cmdArgument:
      # Ignore positional arguments when using flags
      discard
  
  if result.address == "":
    echo "Error: Mining address is required. Use -a <address> or --address <address>"
    quit(1)

proc main() =
  let config = parseArgs()
  
  echo fmt"Starting CUDA miner for address: {config.address}"
  echo fmt"Connecting to node: {config.nodeUrl}"
  echo fmt"GPU launch dims: blocks={config.blocks}, threads={config.threads}, iters_per_thread={config.itersPerThread}"
  echo fmt"GPU architecture: {config.gpuArch}"
  if config.maxBlocks > 0:
    echo fmt"Will stop after mining {config.maxBlocks} block(s)."
  
  # Initialize CUDA
  echo "Initializing CUDA..."
  if not initCudaMiner():
    echo "Failed to initialize CUDA miner"
    quit(1)
  echo "CUDA initialized successfully!"
  
  let client = newHttpClient()
  var minedBlocksCount = 0
  var currentBlockId = -1  # Track current block being mined
  var batchIdx = 0         # Persist batch index across mining info refreshes
  
  while true:
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
    
    # Reset batch index if we're starting to mine a new block
    if currentBlockId != lastBlockId:
      currentBlockId = lastBlockId
      batchIdx = 0
      echo fmt"Starting work on new block {lastBlockId + 1}"
    
    var addressBytes: seq[byte]
    try:
      addressBytes = stringToBytes(config.address)
    except Exception as e:
      echo "ERROR converting address: ", e.msg
      continue
    
    echo fmt"Difficulty: {difficulty}"
    echo fmt"New Block Number: {lastBlockId + 1}"
    echo fmt"Confirming {txs.len} transactions"
    echo fmt"Using Merkle Root provided by node: {merkleRootHex}"
    
    let prefixBytes = buildPrefix(lastBlockHashHex, addressBytes, merkleRootHex, difficulty)
    let (idiff, allowedCharset) = computeFractionalCharset(difficulty)
    let lastChunkLc = makeLastBlockChunk(lastBlockHashHex, idiff)
    
    # Search parameters for single worker
    let startTime = epochTime()
    var foundNonce: uint32 = uint32(0xFFFFFFFF)
    
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
      
      if nonce != uint32(0xFFFFFFFF):
        foundNonce = nonce
        break
      
      inc batchIdx
    
    if foundNonce == uint32(0xFFFFFFFF):
      echo "No solution in this window. Refreshing mining info..."
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

when isMainModule:
  try:
    main()
  except CatchableError:
    echo ""
    echo "Exiting miner."
    quit(0)
