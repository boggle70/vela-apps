# Examples

Example enclave applications for the Vela/Keystone platform.

## Prerequisites

| Requirement | Notes |
|---|---|
| CMake ≥ 3.10 | |
| `riscv64-unknown-linux-gnu-gcc` | Must be on `PATH` |
| `makeself` | Used to create self-extracting packages |
| Keystone SDK | Built and installed from `../sdk` |
| Keystone Runtime | Source from `../runtime` |

## Environment Variables

| Variable | Description |
|---|---|
| `KEYSTONE_SDK_DIR` | Path to the installed SDK (output of `make install` in `../sdk`) |
| `KEYSTONE_RUNTIME` | Path to the runtime source directory (e.g., `../runtime`) |

## Build

```bash
cd examples
mkdir build && cd build

cmake .. \
  -DKEYSTONE_SDK_DIR=$KEYSTONE_SDK_DIR \
  -DKEYSTONE_RUNTIME=$KEYSTONE_RUNTIME

make
```

Or equivalently with environment variables already exported:

```bash
export KEYSTONE_SDK_DIR=/path/to/sdk/install
export KEYSTONE_RUNTIME=/path/to/vela-apps/runtime

mkdir build && cd build
cmake ..
make
```

Build outputs are placed under `build/<example-name>/`.

## Available Examples

| Example | Package | Description |
|---|---|---|---|
| `hello` | `hello.vela` | Minimal enclave that enters and returns |
| `attestation` | `attestor.vela` | Remote attestation with SM verification |
| `ros` | `ros.vela` | Two enclaves communicating via shared memory |


## Running

Each build output is a self-extracting `makeself` archive. Copy the package to the target board and run:

```bash
./hello.vela
```

The package extracts itself and executes the runner (e.g., `hello-runner hello eyrie-rt loader.bin`).
