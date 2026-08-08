# vela-apps

Application-layer components of the [riscv-vela](https://github.com/riscv-vela/)
project, installed on the [Vela](https://github.com/riscv-vela/vela) and running on top of the [Q-Vela](https://github.com/riscv-vela/q-vela)
emulation platform. Two subsystems live here:

| Subsystem | Contents |
|-----------|----------|
| **TEE** (Keystone) | Host-side SDK, in-enclave Eyrie runtime, and example enclave applications. Enclave isolation is enforced with **RISC-V WorldGuard** instead of Keystone's original PMP-based scheme. |
| **RAS** (RERI) | RERI register specification tool |

---

## Repository Structure

```
vela-apps/
│   # TEE (Keystone)
├── sdk/                       # Host-side SDK: host, edge, verifier, eapp libraries
├── runtime/                   # Eyrie — in-enclave S-mode runtime
├── examples/                  # Example enclaves (hello, attestation, ros)
│
│   # RAS (RERI)
└── reri register generator/   # RERI register specification tool (Excel-based)
```

---

## TEE — Building the Keystone Applications

### Prerequisites

```bash
sudo apt install cmake makeself
```

A RISC-V cross toolchain with the **`riscv64-unknown-linux-gnu-`** prefix must
be on `PATH`.

### 1. Build and install the SDK

The SDK provides the libraries and CMake macros the examples depend on, so it
must be built first. `KEYSTONE_SDK_DIR` is the install location and must be an
absolute path.

```bash
cd sdk
mkdir -p build && cd build
export KEYSTONE_SDK_DIR=$PWD
cmake ..
make -j$(nproc)
make install
cd ../..
```

### 2. Build the examples

| Variable | Points to |
|----------|-----------|
| `KEYSTONE_SDK_DIR` | SDK install directory from step 1 |
| `KEYSTONE_RUNTIME` | `runtime/` — the Eyrie sources, built per example |
| `FW_BIN` | `fw_jump.bin` from [vela-fws](https://github.com/riscv-vela/vela-fws), measured by the attestation example |

```bash
export KEYSTONE_SDK_DIR=$(pwd)/sdk/build
export KEYSTONE_RUNTIME=$(pwd)/runtime
export FW_BIN=<path-to>/vela-fws/opensbi/build/platform/generic/firmware/fw_jump.bin

cd examples
mkdir -p build && cd build
cmake ..
make examples -j$(nproc)
cd ../..
```

### Build Output

Each example is packaged as a self-extracting `.vela` archive bundling the
enclave application, the Eyrie runtime, the loader, and the host runner:

| File | Description |
|------|-------------|
| `examples/build/hello/hello.vela` | Minimal enclave — the quickest end-to-end check |
| `examples/build/attestation/attestor.vela` | Remote attestation |
| `examples/build/ros/ros.vela` | Two enclaves communicating over shared memory |

### Running

Copy a package into the Q-Vela guest, load the Keystone driver from
[vela-linux](https://github.com/riscv-vela/vela-linux), and run it:

```bash
insmod keystone-driver.ko      # creates /dev/keystone_enclave
./hello.vela
```

---

## RAS — RERI Register Generator

`reri register generator/` contains the Excel-based RERI register specification
tool.

> TODO: build and usage instructions.
