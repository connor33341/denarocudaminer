/*
MIT License

Copyright (c) 2025 The-Sycorax (https://github.com/The-Sycorax)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

// SHA-256 implementation for CUDA
#define ROTRIGHT(a,b) (((a) >> (b)) | ((a) << (32-(b))))
#define CH(x,y,z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTRIGHT(x,2) ^ ROTRIGHT(x,13) ^ ROTRIGHT(x,22))
#define EP1(x) (ROTRIGHT(x,6) ^ ROTRIGHT(x,11) ^ ROTRIGHT(x,25))
#define SIG0(x) (ROTRIGHT(x,7) ^ ROTRIGHT(x,18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT(x,17) ^ ROTRIGHT(x,19) ^ ((x) >> 10))

typedef unsigned char BYTE;
typedef uint32_t WORD;

typedef struct {
    BYTE data[64];
    WORD datalen;
    unsigned long long bitlen;
    WORD state[8];
} SHA256_CTX;

__constant__ WORD dev_k[64];

static const WORD host_k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

__device__ __forceinline__ void sha256_transform(SHA256_CTX* ctx, const BYTE data[])
{
    WORD a, b, c, d, e, f, g, h, i, j, t1, t2, m[64];

    #pragma unroll 16
    for (i = 0, j = 0; i < 16; ++i, j += 4)
        m[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | (data[j + 3]);

    #pragma unroll 64
    for (; i < 64; ++i)
        m[i] = SIG1(m[i - 2]) + m[i - 7] + SIG0(m[i - 15]) + m[i - 16];

    a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
    e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];

    #pragma unroll 64
    for (i = 0; i < 64; ++i) {
        t1 = h + EP1(e) + CH(e, f, g) + dev_k[i] + m[i];
        t2 = EP0(a) + MAJ(a, b, c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }

    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

__device__ __forceinline__ void sha256_init(SHA256_CTX* ctx)
{
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

__device__ __forceinline__ void sha256_update(SHA256_CTX* ctx, const BYTE data[], size_t len)
{
    for (size_t i = 0; i < len; ++i) {
        ctx->data[ctx->datalen] = data[i];
        if (++ctx->datalen == 64) {
            sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

__device__ __forceinline__ void sha256_final(SHA256_CTX* ctx, BYTE hash[])
{
    WORD i = ctx->datalen;

    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        sha256_transform(ctx, ctx->data);
        for (i = 0; i < 56; ++i) ctx->data[i] = 0x00;
    }

    ctx->bitlen += ctx->datalen * 8;
    ctx->data[63] = ctx->bitlen;
    ctx->data[62] = ctx->bitlen >> 8;
    ctx->data[61] = ctx->bitlen >> 16;
    ctx->data[60] = ctx->bitlen >> 24;
    ctx->data[59] = ctx->bitlen >> 32;
    ctx->data[58] = ctx->bitlen >> 40;
    ctx->data[57] = ctx->bitlen >> 48;
    ctx->data[56] = ctx->bitlen >> 56;
    sha256_transform(ctx, ctx->data);

    for (i = 0; i < 4; ++i) {
        hash[i     ] = (ctx->state[0] >> (24 - i * 8)) & 0x000000ff;
        hash[i +  4] = (ctx->state[1] >> (24 - i * 8)) & 0x000000ff;
        hash[i +  8] = (ctx->state[2] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 12] = (ctx->state[3] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 16] = (ctx->state[4] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 20] = (ctx->state[5] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 24] = (ctx->state[6] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 28] = (ctx->state[7] >> (24 - i * 8)) & 0x000000ff;
    }
}

__device__ __forceinline__ void sha256_to_hex_lc(const unsigned char* data, char* out64)
{
    const char hex[16] = { '0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f' };
    #pragma unroll
    for (int i = 0; i < 32; ++i) {
        out64[i * 2    ] = hex[(data[i] >> 4) & 0xF];
        out64[i * 2 + 1] = hex[(data[i]     ) & 0xF];
    }
}

__device__ __forceinline__ bool nibble_prefix_match(const char* hh, const unsigned char* chunk, unsigned len)
{
    #pragma unroll
    for (unsigned i = 0; i < len; ++i) { 
        if (hh[i] != (char)chunk[i]) return false; 
    }
    return true;
}

__device__ __forceinline__ bool bytes_contains_lc(const unsigned char* arr, size_t n, unsigned char v)
{
    #pragma unroll
    for (size_t i = 0; i < n; ++i) { 
        if (arr[i] == v) return true; 
    }
    return false;
}

__global__ void miner_kernel(
    const unsigned char* __restrict__ hash_prefix,
    size_t prefix_len,
    const unsigned char* __restrict__ last_chunk,
    unsigned idiff,
    const unsigned char* __restrict__ charset,
    unsigned charset_len,
    unsigned int* __restrict__ result,
    uint32_t start_offset,
    uint32_t global_step,
    uint32_t base_offset,
    uint32_t iters_per_thread
) {
    uint32_t tid = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t i = start_offset + tid + base_offset;

    const size_t temp_size = prefix_len + 4;
    unsigned char temp[320];
    unsigned char digest[32];
    char hexhash[64];

    for (size_t k = 0; k < prefix_len; ++k) temp[k] = hash_prefix[k];
    unsigned char* nonce_ptr = temp + prefix_len;

    for (uint32_t it = 0; it < iters_per_thread; ++it) {
        if (*result != 0xFFFFFFFFu) return; // another thread found a result

        // Write nonce in little endian format
        nonce_ptr[0] = (i      ) & 0xFF;
        nonce_ptr[1] = (i >>  8) & 0xFF;
        nonce_ptr[2] = (i >> 16) & 0xFF;
        nonce_ptr[3] = (i >> 24) & 0xFF;

        SHA256_CTX ctx;
        sha256_init(&ctx);
        sha256_update(&ctx, temp, temp_size);
        sha256_final(&ctx, digest);

        sha256_to_hex_lc(digest, hexhash);

        if ((idiff == 0 || nibble_prefix_match(hexhash, last_chunk, idiff)) &&
            (charset_len == 16 || bytes_contains_lc(charset, charset_len, (unsigned char)hexhash[idiff])))
        {
            atomicCAS(result, 0xFFFFFFFFu, i);
            return;
        }

        i += global_step;
    }
}

// C interface for Nim
extern "C" {
    
    cudaError_t cuda_miner_init() {
        return cudaMemcpyToSymbol(dev_k, host_k, sizeof(host_k), 0, cudaMemcpyHostToDevice);
    }

    cudaError_t cuda_mine_nonces(
        const unsigned char* hash_prefix,
        size_t prefix_len,
        const char* last_chunk_str,
        unsigned idiff,
        const char* charset_str,
        unsigned charset_len,
        unsigned int* result,
        uint32_t blocks,
        uint32_t threads,
        uint32_t iters_per_thread,
        uint32_t batch_offset
    ) {
        // Device memory allocation
        unsigned char* d_prefix = nullptr;
        unsigned char* d_last_chunk = nullptr;
        unsigned char* d_charset = nullptr;
        unsigned int* d_result = nullptr;

        cudaError_t err;

        // Initialize variables before any goto statements
        unsigned int init_result = 0xFFFFFFFFu;
        uint32_t start_offset = 0;
        uint32_t global_step = blocks * threads;
        uint32_t base_offset = batch_offset * iters_per_thread * global_step;

        // Allocate device memory
        err = cudaMalloc(&d_prefix, prefix_len);
        if (err != cudaSuccess) return err;

        err = cudaMalloc(&d_last_chunk, idiff > 0 ? idiff : 1);
        if (err != cudaSuccess) { cudaFree(d_prefix); return err; }

        err = cudaMalloc(&d_charset, charset_len);
        if (err != cudaSuccess) { cudaFree(d_prefix); cudaFree(d_last_chunk); return err; }

        err = cudaMalloc(&d_result, sizeof(unsigned int));
        if (err != cudaSuccess) { 
            cudaFree(d_prefix); cudaFree(d_last_chunk); cudaFree(d_charset); 
            return err; 
        }

        // Copy data to device
        err = cudaMemcpy(d_prefix, hash_prefix, prefix_len, cudaMemcpyHostToDevice);
        if (err != cudaSuccess) goto cleanup;

        if (idiff > 0) {
            err = cudaMemcpy(d_last_chunk, last_chunk_str, idiff, cudaMemcpyHostToDevice);
            if (err != cudaSuccess) goto cleanup;
        }

        err = cudaMemcpy(d_charset, charset_str, charset_len, cudaMemcpyHostToDevice);
        if (err != cudaSuccess) goto cleanup;

        err = cudaMemcpy(d_result, &init_result, sizeof(unsigned int), cudaMemcpyHostToDevice);
        if (err != cudaSuccess) goto cleanup;

        // Launch kernel
        miner_kernel<<<blocks, threads>>>(
            d_prefix,
            prefix_len,
            d_last_chunk,
            idiff,
            d_charset,
            charset_len,
            d_result,
            start_offset,
            global_step,
            base_offset,
            iters_per_thread
        );

        err = cudaGetLastError();
        if (err != cudaSuccess) goto cleanup;

        err = cudaDeviceSynchronize();
        if (err != cudaSuccess) goto cleanup;

        // Copy result back
        err = cudaMemcpy(result, d_result, sizeof(unsigned int), cudaMemcpyDeviceToHost);

    cleanup:
        if (d_prefix) cudaFree(d_prefix);
        if (d_last_chunk) cudaFree(d_last_chunk);
        if (d_charset) cudaFree(d_charset);
        if (d_result) cudaFree(d_result);

        return err;
    }
}
