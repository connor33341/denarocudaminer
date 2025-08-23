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

## CUDA FFI wrapper for Nim-based Denaro/Stellaris miner

{.passL: "-lcuda -lcudart".}

type
  CudaError* = enum
    cudaSuccess = 0
    cudaErrorInvalidValue = 1
    cudaErrorMemoryAllocation = 2
    # Add more as needed

# Forward declarations for CUDA functions
proc cuda_miner_init(): CudaError {.importc: "cuda_miner_init", cdecl.}

proc cuda_mine_nonces(
  hash_prefix: ptr UncheckedArray[uint8],
  prefix_len: csize_t,
  last_chunk_str: cstring,
  idiff: cuint,
  charset_str: cstring,
  charset_len: cuint,
  result: ptr cuint,
  blocks: cuint,
  threads: cuint,
  iters_per_thread: cuint,
  batch_offset: cuint
): CudaError {.importc: "cuda_mine_nonces", cdecl.}

proc cudaGetErrorString(error: CudaError): cstring {.importc: "cudaGetErrorString", cdecl.}

# Nim-friendly wrappers
proc initCudaMiner*(): bool =
  ## Initialize CUDA miner (copy constants to device)
  let err = cuda_miner_init()
  if err != cudaSuccess:
    echo "CUDA initialization failed: ", cudaGetErrorString(err)
    return false
  return true

proc mineNonces*(
  hashPrefix: seq[uint8],
  lastChunk: string,
  idiff: uint,
  charset: string,
  blocks: uint = 1024,
  threads: uint = 512,
  itersPerThread: uint = 20000,
  batchOffset: uint = 0
): uint32 =
  ## Mine nonces using CUDA kernel
  ## Returns the found nonce or 0xFFFFFFFF if not found
  
  var cudaResult: cuint = cuint(0xFFFFFFFF)
  
  let err = cuda_mine_nonces(
    cast[ptr UncheckedArray[uint8]](hashPrefix[0].unsafeAddr),
    csize_t(hashPrefix.len),
    cstring(lastChunk),
    cuint(idiff),
    cstring(charset),
    cuint(charset.len),
    cudaResult.addr,
    cuint(blocks),
    cuint(threads),
    cuint(itersPerThread),
    cuint(batchOffset)
  )
  
  if err != cudaSuccess:
    echo "CUDA mining failed: ", cudaGetErrorString(err)
    return uint32(0xFFFFFFFF)
  
  return uint32(cudaResult)
