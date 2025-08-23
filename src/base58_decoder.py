#!/usr/bin/env python3
"""
Simple base58 decoder script for use with the Nim CUDA miner.
Reads a base58 string from command line argument and outputs the hex-encoded result.
"""
import sys
import base58

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 base58_decoder.py <base58_string>", file=sys.stderr)
        sys.exit(1)
    
    try:
        base58_string = sys.argv[1]
        decoded_bytes = base58.b58decode(base58_string)
        hex_result = decoded_bytes.hex()
        print(hex_result)
    except Exception as e:
        print(f"Error decoding base58: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
