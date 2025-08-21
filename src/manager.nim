import std/[httpclient, json, strformat, times, math, strutils, osproc, os], nimcrypto


# This program starts the cuda miner giving it the informations needed to mine.
# To work properly, you need to compile the cuda miner and name it cuda_miner.exe.
# Then you need to put the cuda_miner.exe in the same folder as this program.

let args = commandLineParams()
let node = string(args[0])
let address = string(args[1])

proc getMiningInfo(client: HttpClient, node: string): JsonNode =
    parseJson(client.getContent(fmt"{node}/get_mining_info"))

proc pushBlock(client: HttpClient, block_content: seq[byte], transactions: seq[string]): string =
    var join_d = ","
    client.getContent(fmt"{node}/push_block?block_content={toHex(block_content).toLower()}&txs={join(transactions, join_d)}")

proc uint32ToBytes(x: uint32): seq[byte] =
    var y: array[4, byte]
    copyMem(y.unsafeAddr, x.unsafeAddr, 4)
    @y

proc int16ToBytes(x: int16): seq[byte] =
    var y: array[2, byte]
    copyMem(y.unsafeAddr, x.unsafeAddr, 2)
    @y

proc hexToBytesSeq(hex: string): seq[byte] =
    @(MDigest[256].fromHex(hex).data)

proc hexToBytesSeq64(hex: string): seq[byte] =
    @(MDigest[512].fromHex(hex).data)

proc getTransactionsMerkleTree(transactions: seq[string]): MDigest[256] =
    var bytes = newSeq[byte]()
    for transaction in transactions:
        bytes = bytes & hexToBytesSeq(transaction)
    sha256.digest(bytes)

type MiningCache = ref object of RootObj
    decimal*: bool
    difficulty*: int
    charset*: string
    lbh_chunk*: string

let client = newHttpClient()

proc buildCache(difficulty: float, last_block_hash: string): MiningCache =
    var decimal = difficulty mod 1
    var idifficulty = int(difficulty)
    var count: int
    if decimal > 0:
        count = int(ceil(16 * (1 - decimal)))
    else:
        count = 1
    MiningCache(decimal: decimal > 0, difficulty: idifficulty, charset: "0123456789ABCDEF"[0 ..< count], lbh_chunk: last_block_hash[^idifficulty ..< 64].toUpper())

type Block = ref object of RootObj
    hash*: string
    id*: int

type Result = ref object of RootObj
    last_block*: Block
    difficulty*: float
    pending_transactions*: seq[string]

proc run_cuda(prefix: string, difficulty: int, charset: string, lbh_chunk: string): uint32 =
    var result = execCmdEx(fmt".\cuda_miner {lbh_chunk} {charset} {prefix} {difficulty}")
    var nonce = result[0].strip()
    echo nonce
    uint32(parseUInt(nonce))

proc nrun_cuda(prefix: string, difficulty: int, charset: string, lbh_chunk: string) =
    discard execCmd(fmt".\cuda_miner {lbh_chunk} {charset} {prefix} {difficulty}")

while true:
    echo "Getting new block..."
    var mining_info = to(getMiningInfo(client, node)["result"], Result)

    var difficulty = mining_info.difficulty
    var pending_transactions = mining_info.pending_transactions
    if pending_transactions.len > 1000:
        pending_transactions = pending_transactions[0 ..< 1000]

    echo fmt"Starting mining of block {mining_info.last_block.id + 1} with difficulty {difficulty}"

    let prefix = hexToBytesSeq(mining_info.last_block.hash) & hexToBytesSeq64(address) & @(getTransactionsMerkleTree(pending_transactions).data) & uint32ToBytes(uint32(now().utc.toTime().toUnix())) & int16ToBytes(int16(difficulty * 10))
    if prefix.len() != 134:
        echo "Invalid prefix length"
        continue
    let cache = buildCache(difficulty, mining_info.last_block.hash)
    var client = newHttpClient()

    var start = epochTime()
    var nonce = run_cuda(prefix.toHex(), cache.difficulty, cache.charset, cache.lbh_chunk)
    var elapsed = epochTime() - start
    echo fmt"Approx. {(float64(nonce) / elapsed) / 1000000} MH/s"

    var result = pushBlock(client, prefix & uint32ToBytes(uint32(nonce)), pending_transactions)

    echo fmt"Block mined! ({mining_info.last_block.id + 1} {result})"
