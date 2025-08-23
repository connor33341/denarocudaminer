# denarocudaminer

This project provides a CUDA-based miner and a small Nim integration. The only supported build/run entrypoints described here are the repo scripts `compile.sh` and `run.sh`.

## Requirements

- NVIDIA CUDA toolkit (nvcc) available on PATH
- Nim compiler (nim) on PATH
- A working C/C++ toolchain (gcc/g++)

## Build (use the repository script)

Run the provided build script with its defaults:

```bash
./compile.sh
```

What `compile.sh` does (summary of defaults):
- Verifies `nvcc` and `nim` are available
- Creates `build/` if needed
- Compiles the CUDA source into `build/libcuda_miner.so` using nvcc (shared, PIC, `-arch=sm_86` by default in script)
- Builds the Nim-based executable and places it at `build/cuda_miner`

After a successful run you should have at least:
- `build/libcuda_miner.so`
- `build/cuda_miner`

The script prints an example usage when finished, for example:

```text
Usage: ./build/cuda_miner --address <your_address> --node <node_url>
Example: ./build/cuda_miner --address Dn7FpuuLTkAXTbSDuQALMSQVzy4Mp1RWc69ZnddciNa7o --node https://stellaris-node.connor33341.dev/
```

## Run (use the repository script)

Run the provided run script with the required positional parameters (it uses exactly the CLI arguments shown in the example above):

```bash
./run.sh <node_url> <address> [additional_options]
```

Notes about `run.sh` defaults and behavior:
- It expects at least two arguments: `node_url` and `address`.
- It forwards any `[additional_options]` to the `build/cuda_miner` executable.
- It sets `LD_LIBRARY_PATH=./build:$LD_LIBRARY_PATH` so the miner can load `libcuda_miner.so` from the `build/` folder.

Example:

```bash
./run.sh https://stellaris-node.connor33341.dev/ Dn7FpuuLTkAXTbSDuQALMSQVzy4Mp1RWc69ZnddciNa7o
```

## Minimal repository structure (files you will interact with)

- `compile.sh`  — build script (run without args)
- `run.sh`      — run script (requires `<node_url>` and `<address>`)
- `src/`        — source code (CUDA and Nim sources)
- `build/`      — build artifacts (`libcuda_miner.so`, `cuda_miner`)
- `denarocudaminer.nimble` — Nim package manifest
- `LICENSE`     — license

## Troubleshooting

- nvcc not found: install CUDA toolkit and ensure `nvcc` is on PATH.
- nim not found: install Nim and `nimble` if you need dependency installation.
- Library load errors: ensure `LD_LIBRARY_PATH` includes `./build` (the run script sets this automatically). If calling the binary directly, run:

```bash
export LD_LIBRARY_PATH="$PWD/build:$LD_LIBRARY_PATH"
./build/cuda_miner --node <node_url> --address <address>
```

## Repository structure

- build/
	- cuda_miner (native binary)
	- cuda_miner.exe (Windows build artifact)
	- libcuda_miner.so (shared library)
	- manager (helper binaries)
- src/
	- cuda_miner_lib.cu         (CUDA source implementing the miner core)
	- cuda_miner.nim            (Nim wrapper / executable)
	- cuda_wrapper.nim          (Nim <-> C/C++ glue)
- stellaris/
	- build.sh                  (build helpers for the stellaris demo)
	- Dockerfile
	- docker-compose.yml
	- run_node.py               (node runner)
	- run.sh
	- test.py
	- miner/                    (mini projects and Dockerfile for miner container)
	- stellaris/                (python package with node and manager code)
		- manager.py
		- database.py
		- node/                   (node code and nodes manager)
		- scripts/                (setup scripts like setup_db.sh)
		- svm/                    (small VM and exceptions used by the node)
		- transactions/           (transaction models)
		- utils/                  (helper utilities)

Files of interest:
- `compile.sh` and `run.sh` — convenience scripts.
- `denarocudaminer.nimble` — Nim package manifest.

## License

See `LICENSE` in the repository root for license terms.

