# vela-apps

Application-layer components of the [riscv-vela](https://github.com/riscv-vela/)
project, installed on the [Vela](https://github.com/riscv-vela/vela) and running on top of the [Q-Vela](https://github.com/riscv-vela/q-vela)
emulation platform. 

Two subsystems live here:

| Subsystem | Contents |
|-----------|----------|
| **TEE** (Keystone) | Host-side SDK, in-enclave Eyrie runtime, and example enclave applications. Enclave isolation is enforced with **RISC-V WorldGuard** instead of Keystone's original PMP-based scheme. |
| **RAS** (RERI) | rasdaemon packaging for the guest, RERI error-injection scripts, and the RERI register specification tool. |

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
├── ras/                       # rasdaemon packaging + RERI error-injection scripts
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

## RAS — Error Injection and Collection

Two user-space tools make up the RAS workflow on a Q-Vela guest:

| Tool | Role | Where it comes from |
|------|------|---------------------|
| **rasdaemon** | Subscribes to the kernel RAS tracepoints and records the events | Built for the guest — see [`ras/README.md`](ras/README.md) |
| **devmem** | Writes RERI registers directly to inject an error | Already in the guest — busybox built-in |

### First check: mount tracefs, then look for the RAS events

Nothing mounts tracefs on a minimal guest, and `/sys/kernel/tracing` is an empty
mount point until you do. After that, `events/ras/` tells you whether the kernel
was built with `CONFIG_RAS=y` — without it rasdaemon collects **nothing**, even
though `dmesg` still prints `[Hardware Error]`.

```bash
mount -t tracefs nodev /sys/kernel/tracing
ls /sys/kernel/tracing/events/ras/     # must contain non_standard_event/
```

### Smoke test — no rasdaemon needed

On the buildroot `rootfs.cpio` guest, busybox already has `devmem`, and that is
enough to prove the whole path end to end:

```bash
echo 1 > /sys/kernel/tracing/events/ras/non_standard_event/enable
cat /sys/kernel/tracing/trace_pipe &

devmem 0x4010040 32 0x2a1        # arm
devmem 0x4010048 32 0x9001404    # describe a TLB error
devmem 0x4010044 8 1             # fire
```

### Collecting errors — Ubuntu guest

Build rasdaemon v0.8.5 from source — the distro package is too old and gives no
guarantee of `--enable-non-standard`, which is the only event this platform
produces. Then:

```bash
sudo rasdaemon -f -r &

devmem 0x4010040 32 0x2a1          # arm
devmem 0x4010048 32 0x11001702     # RERI error code 17, correctable
devmem 0x4010044 8  1              # fire

ras-mc-ctl --errors
```

The full walkthrough — register map, error-code table, troubleshooting, and why
rasdaemon needs `--enable-non-standard` rather than `--enable-reri` — is in
**[`ras/README.md`](ras/README.md)**.

### RERI Register Generator

`reri register generator/` holds the Excel-based tool for working out the
register bit fields, along with
[its own notes](reri%20register%20generator/readme.md) on `devmem` usage.

> One correction to those notes: the Status register formula
> `Error bank + 72*(i+1)` is right for record 0 only. Error records are 64 bytes
> apart, so use `control_i + 8`. See [`ras/README.md`](ras/README.md).
