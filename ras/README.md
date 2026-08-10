# RAS — Error Injection and Collection

Tools for exercising the RAS path on a Q-Vela guest: **inject** a hardware error
into the emulated RERI registers, then **watch** the kernel detect it and
**collect** it into a log.

```
    devmem                    kernel                    rasdaemon
  inject an error   ────►   detects, reports   ────►   collects, logs
```

Every step here is a command you can paste. Wrapper scripts
(`build-rasdaemon.sh`, `inject/`) are being added separately — see
[riscv-vela/vela-apps#2](https://github.com/riscv-vela/vela-apps/issues/2).

---

## Which guest do I use?

Q-Vela can boot two different guests, and they have different jobs.

| Guest | Good for | rasdaemon? |
|-------|----------|------------|
| **buildroot `rootfs.cpio`** | Quick smoke test — is the RERI path alive? | No. `devmem` and `dmesg` are enough, and busybox already ships `devmem`. |
| **Ubuntu 24.04** | The real thing — collection, logging, ROS 2 workloads | Yes. Build it from source, below. |

If you just want to confirm the hardware path works, stay on `rootfs.cpio` and
skip to [Smoke test](#smoke-test-no-rasdaemon-needed). If you need error records
in a file, you want the Ubuntu guest.

---

## Before you start

### 1. Mount tracefs

Nothing does this for you on the buildroot guest. `/sys/kernel/tracing` exists as
an empty mount point until you mount it — so the directory looks like it is
there, but everything inside is missing.

```bash
mount -t tracefs nodev /sys/kernel/tracing
```

On the Ubuntu guest systemd normally mounts it at boot, so it may already be
done. Running the command again is harmless.

### 2. Check that the kernel has `CONFIG_RAS=y`

**Without it, rasdaemon collects nothing** — not because it is misconfigured,
but because the tracepoint it listens on is not compiled into the kernel.

`dmesg` will still print `[Hardware Error]`, which makes this easy to miss. The
kernel log and the tracepoint are two separate paths.

```bash
ls /sys/kernel/tracing/events/ras/
```

| You see | Meaning |
|---------|---------|
| `non_standard_event/` | Good. Carry on. |
| `events/` is there, but no `ras/` | `CONFIG_RAS=n`. Stop here — fix the kernel first, see [vela-linux](https://github.com/riscv-vela/vela-linux). |
| `No such file or directory` | tracefs is not mounted. Go back to step 1. |

---

## Smoke test (no rasdaemon needed)

This proves the whole chain — QEMU → OpenSBI → GHES → kernel tracepoint — using
nothing but busybox. Run it on either guest.

```bash
# 0. tracefs must be mounted (see above)
mount -t tracefs nodev /sys/kernel/tracing

# 1. turn the tracepoint on and watch it
echo 1 > /sys/kernel/tracing/events/ras/non_standard_event/enable
cat /sys/kernel/tracing/trace_pipe &

# 2. inject a TLB error
devmem 0x4010040 32 0x2a1        # arm the error record
devmem 0x4010048 32 0x9001404    # describe the error
devmem 0x4010044 8 1             # fire

# 3. check the kernel's own report
dmesg | grep -A15 'Hardware Error'
```

### What a successful run looks like

Two things should appear. First the kernel's own report:

```
{1}[Hardware Error]: Hardware error from APEI Generic Hardware Error Source: 1
{1}[Hardware Error]: event severity: recoverable
{1}[Hardware Error]:  Error 0, type: recoverable
{1}[Hardware Error]:   section_type: general processor error
{1}[Hardware Error]:   processor_type: 3, RISCV
{1}[Hardware Error]:   processor_isa: 6, RISCV64
{1}[Hardware Error]:   error_type: 0x02
{1}[Hardware Error]:   TLB error
{1}[Hardware Error]:   operation: 1, data read
{1}[Hardware Error]:   target_address: 0x0000000000000000
```

And then the tracepoint — this is the one rasdaemon reads:

```
devmem-153 [000] dnh.. 414.591022: non_standard_event: severity: 2;
  sec type:adcc7698-b447-db4b-b65e-16f193c4f3db;
  FRU: 00000000-0000-0000-0000-000000000000 ; data len:192;
  raw data:0f 02 00 00 00 00 00 00 03 06 02 01 00 00 00 00 00 00 ... (192 bytes)
```

Reading that record against the kernel's own structures:

| Field | Value | Means |
|-------|-------|-------|
| `severity` | 2 | `GHES_SEV_RECOVERABLE` |
| `sec type` | `adcc7698-b447-…` | `CPER_SEC_PROC_GENERIC` — the bytes are printed little-endian, so it is the `0x9876CCAD-47B4-4bdb-…` GUID from `include/linux/cper.h` |
| raw byte 8 | `03` | `proc_type` — RISCV |
| raw byte 9 | `06` | `proc_isa` — RISCV64 |
| raw byte 10 | `02` | `proc_error_type` — TLB error |
| raw byte 11 | `01` | `operation` — data read |

`target_address` is zero because we never wrote `addr_i`; it reports whatever the
injector put there.

Note the record arrives as **undecoded raw bytes**. That is expected here — see
[Known limitations](#known-limitations).

### If it does not work

| What you see | What it means |
|--------------|---------------|
| `dmesg` shows the error, `trace_pipe` stays silent | The kernel lacks `CONFIG_RAS`. Go back to [Before you start](#before-you-start). |
| Neither appears | The injection did not fire. Check that you wrote `0x4010044` **last**, and that QEMU was started with `-M virt,reri=true`. |

---

## Installing rasdaemon (Ubuntu guest)

Build **v0.8.5 from source**. Do not use `apt install rasdaemon`: the Ubuntu
package is 0.8.0-2, and rasdaemon decides at configure time which events it can
handle — the distro build gives no guarantee of `--enable-non-standard`, which is
the only event this platform produces.

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool pkg-config git \
    libtraceevent-dev libsqlite3-dev

git clone --depth 1 --branch v0.8.5 https://github.com/mchehab/rasdaemon
cd rasdaemon
autoreconf -vfi

# --enable-reri is deliberately left out; see "Before you start" above.
./configure --enable-non-standard --enable-sqlite3

make -j"$(nproc)"
sudo make install
```

Then start it:

```bash
sudo mount -t tracefs nodev /sys/kernel/tracing   # rasdaemon needs this
sudo rasdaemon -f -r                              # foreground, and record to disk
```

rasdaemon finds the tracepoints by scanning `/proc/mounts`: it looks for a
**tracefs** mount first, then falls back to a **debugfs** mount plus `/tracing`.
If neither is mounted it exits with `Can't locate a mounted debugfs`.

---

## Injecting errors

Three writes, and the order matters — the third one is the trigger.

```bash
devmem 0x4010040 32 0x2a1          # arm the error record
devmem 0x4010048 32 0x11001702     # describe the error (table below)
devmem 0x4010044 8  1              # fire
```

Only the middle value changes between error types. On the Ubuntu guest `devmem`
may only be reachable as a busybox applet — use `busybox devmem` there.

Repeating on a schedule is a shell loop. The availability test in the test plan
(TC.10.007) asks for four injections twelve minutes apart:

```bash
for i in 1 2 3 4; do
    sleep 720
    devmem 0x4010040 32 0x2a1
    devmem 0x4010048 32 0x11001702
    devmem 0x4010044 8  1
    echo "[$(date '+%H:%M:%S')] injection $i/4"
done
```

### Available error types

| Name | RERI code | Severity | Register value | What the kernel reports | Observed? |
|------|-----------|----------|----------------|-------------------------|-----------|
| `tlb` | 9 — TLB/page-walk cache data | deferred | `0x09001404` | `error_type: 0x02` TLB error, `operation: 1, data read`, **recoverable** | **yes** |
| `exec-unit` | 17 — execution unit / datapath | corrected | `0x11001702` | `error_type: 0x08` micro-architectural error, `operation: 2, data write`, **corrected** | **yes** |
| `mem-data` | 20 — system memory data | corrected | `0x14001702` | identical to `exec-unit` — see below | **yes** |
| `hart` | 12 — hart state error | corrected | `0x0C001702` | identical to `exec-unit` | q-vela `docs/ras.md` |
| `watchdog` | 16 — internal watchdog | corrected | `0x10001702` | expected: identical to `exec-unit` | not yet |

### ⚠️ The RERI error code does not survive into the log

Codes 12, 17 and 20 were each injected and each produced a **byte-identical**
CPER record — same `error_type: 0x08`, same `operation: 2`, same raw payload
`… 03 06 08 02 …`. Nine more codes fold into the same bucket. This is not a bug
in the injection; it is where the firmware translates RERI into CPER.

CPER's processor error type is a 4-bit mask (`cper.c`, `cper_proc_error_type_strs`),
and `opensbi/lib/utils/ras/reri_drv.c:373-405` folds all 21 RERI codes onto it:

| CPER `error_type` | Meaning | RERI codes folded into it |
|-------------------|---------|---------------------------|
| `0x01` | cache error | 3, 4, 5, 6 |
| `0x02` | TLB error | 9, 10, 11 |
| `0x04` | bus error | 18 |
| `0x08` | micro-architectural error | **12, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25** |
| `0x00` | (none set) | everything else — 0, 1, 2, 7, 8, 13, 26, 27, … |

Two consequences worth knowing before you design a test around this:

- **You cannot tell "code 17" from "code 12" by reading `dmesg` or the rasdaemon
  record.** Twelve codes share `0x08`. Verified: injecting 12, 17 and 20 gave
  three indistinguishable records.
- **Memory errors do not look like memory errors.** Code 20 (system memory data)
  folds into `0x08` as well, so it is reported as a *micro-architectural
  processor* error. Verified by injection.

> **The memory half of this has a fix pending.** Hayong Jeong (@AngryOvO) traced
> it to two firmware issues — `reri_drv.c` never selects the memory section type,
> and OpenSBI's `cper_mem2_sec` struct does not match the UEFI layout Linux parses
> — and submitted `opensbi_mem_cper.patch` upstream. With it, RERI codes 18–21
> become proper CPER Memory Error sections with distinct error types. Codes 12 and
> 17 are unaffected: they are not memory-class, so they stay folded together.
> vela-fws does not carry the patch yet.

**Workaround — read the register back.** QEMU clears only the valid bit when the
error is consumed (`riscv_reri_helper.c:152` sets `status_i.v = 0`), so the `ec`
field survives:

```bash
devmem 0x4010048 32          # bits 31:24 are the RERI error code
```

That distinguishes all codes, but it reads hardware state rather than the log —
it proves what you injected, not what was recorded.

### Severity mapping

`reri_drv.c:335-342` maps the RERI severity bits to CPER severity:

| RERI bit | CPER severity | `dmesg` shows |
|----------|---------------|---------------|
| `ce` | 2 | corrected |
| `de` | 0 | recoverable |
| `ue` | 1 | fatal |
| none | 3 | informational |

Both observations above match this.

---

## Checking the result

```bash
ras-mc-ctl --errors          # decoded summary
ls -l /var/log/ras/          # rasdaemon's own record
dmesg | grep -A15 'Hardware Error'
```

Paste the raw output into the issue or PR — a summary is not evidence.

### Closing the loop

Once it works, boot a kernel **without** `CONFIG_RAS` and inject again. You
should get zero events. That is what turns "we saw some records" into "these
records came from our injection".

---

## RERI register reference

Each hart gets a 4 KiB error bank. Hart 0 starts at `0x0401_0000`, hart 1 at
`0x0401_1000`, and so on.

Inside a bank there is a 64-byte header, then 64-byte error records:

```
record[i].control_i = bank_base + 64 * (i + 1)
record[i].status_i  = control_i + 8
```

So for hart 0, record 0:

| Address | Register | What you write |
|---------|----------|----------------|
| `0x4010040` | `control_i` | `0x2a1` — enable logging, pick the notification mode |
| `0x4010048` | `status_i` | the error description (see encoding below) |
| `0x4010050` | `addr_i` | a physical address — only needed for memory-class errors |
| `0x4010044` | `control_i + 4` (`eid`) | `1` — **this is the trigger, write it last** |

`addr_i` is optional today: every error currently becomes a processor error,
where the address is reported but not acted on. Once the pending memory-section
patch lands it becomes **required** for memory-class codes — `ghes.c:370` only
builds a memory section when the physical address is non-zero.

> ⚠️ The formula in
> [`reri register generator/readme.md`](../reri%20register%20generator/readme.md)
> gives the Status address as `bank + 72*(i+1)`. That happens to be right for
> record 0 (72 = 0x48) but is wrong from record 1 onward — records are 64 bytes
> apart, not 72. Use `control_i + 8`.

### `status_i` encoding

| Bits | Field | Notes |
|------|-------|-------|
| 31:24 | `ec` | RERI error code — the number the test plan refers to |
| 15:12 | `at` | address type |
| 10:8 | `tt` | transaction type: 4 = explicit read, 5 = explicit write, 6 = implicit read, 7 = implicit write |
| 3 | `ue` | uncorrected |
| 2 | `de` | deferred |
| 1 | `ce` | corrected |
| 0 | `v` | valid — hardware sets this; leave it 0 when injecting |

Read `0x0C001702` back with that table: `ec` = 0x0C = 12 (hart state error),
`at` = 1, `tt` = 7 (implicit write), `ce` = 1 (corrected).

The error code numbers come from `RERI_EC_*` in
`qemu/include/hw/riscv/riscv_reri_regs.h`, and they are the **same numbering the
test plan uses** when it says "RERI Error Code 17".

---

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `ls /sys/kernel/tracing/events/ras/` → `No such file or directory` | tracefs is not mounted. `/sys/kernel/tracing` is only an empty mount point until you run `mount -t tracefs nodev /sys/kernel/tracing`. This is the usual first stumble on a minimal guest. |
| `events/` exists but there is no `ras/` in it | Kernel built without `CONFIG_RAS`. |
| `dmesg` shows the error but `trace_pipe` stays silent | Also `CONFIG_RAS` — the kernel log path works without it, the tracepoint does not. |
| rasdaemon exits with `Can't locate a mounted debugfs` | Neither tracefs nor debugfs is mounted. Mount tracefs. |
| rasdaemon runs but records nothing | Built without `--enable-non-standard`. Rebuild it, or check with `rasdaemon --version`-style output that the option was on. |
| `devmem` writes succeed, nothing happens at all | Did you write `0x4010044` (the trigger) **last**? Did you boot with `-M virt,reri=true`? |
| No `[Hardware Error]` in `dmesg` at all | The guest must boot through EDK2/ACPI. A device-tree boot produces no GHES reports. |

---

## Background — why it is built this way

<details>
<summary>Why <code>--enable-non-standard</code>, and not <code>--enable-reri</code></summary>

rasdaemon 0.8.5 does have a `--enable-reri` option, and at first glance it looks
like exactly what a RISC-V RERI platform wants. It is not usable here.

`--enable-reri` makes rasdaemon subscribe to the kernel tracepoint
`ras:reri_event`. **Our kernel does not define that tracepoint.** The tracepoints
in `include/ras/ras_event.h` are `extlog_mem_event`, `mc_event`, `arm_event`,
`non_standard_event`, `aer_event` and `memory_failure_event` — that is the whole
list. Building with `--enable-reri` would subscribe to nothing.

What actually happens to a RERI error is this:

1. OpenSBI reports it to the OS through SBI SSE, and it arrives at GHES as a
   CPER **Generic Processor Error** section.
2. `ghes_do_proc()` has branches for platform memory, PCIe, ARM and CXL sections
   — but none for generic processor errors. So it falls through to the final
   `else`, which calls `log_non_standard_event()`.
3. That function emits `ras:non_standard_event` — and it is compiled in only
   when `CONFIG_RAS=y` (`include/linux/ras.h`, `drivers/ras/Makefile`).

So `ras:non_standard_event` is the only event this platform produces, and
`--enable-non-standard` is the only way rasdaemon will listen for it. Without
that flag rasdaemon does not merely ignore the event — the handler is not
compiled in at all (`ras-events.c`, `Makefile.am`, both guarded on
`HAVE_NON_STANDARD`).

If a `ras:reri_event` tracepoint is added to the kernel later, revisit this.
</details>

<details>
<summary>Why there is no buildroot package here</summary>

The `rootfs.cpio` guest is built by buildroot, which lives in
[vela-fws](https://github.com/riscv-vela/vela-fws) — a different repository.
Shipping a buildroot package from *this* repository would mean vela-fws's build
reaching across into vela-apps for files, which is exactly the coupling the
repository split was meant to remove.

It would also not buy much. The `rootfs.cpio` guest is the smoke-test
environment, and the smoke test needs only `devmem`, which busybox already
provides. The test plan's OS is Ubuntu 24.04, and the workloads it runs (Nav2,
SLAM, AI inference) cannot run on a busybox initramfs anyway.

So: `rootfs.cpio` for the quick check, Ubuntu for collection and for the real
test runs.

If the `rootfs.cpio` guest ever does need rasdaemon, the clean way is to bump
vela-fws's buildroot submodule past `7b8892e900` (2025-12-19), which is when
buildroot gained an in-tree `package/rasdaemon`. The currently pinned commit
(`d8b0fdb71e`, 2025-11-09) predates it, which is why `BR2_PACKAGE_RASDAEMON`
does not appear in `menuconfig` today.
</details>

---

## Known limitations

**Records are stored raw, not decoded.** The section GUID that arrives here is
`adcc7698-b447-db4b-b65e-16f193c4f3db` — the CPER *Generic Processor Error*
GUID, confirmed by observation. rasdaemon's non-standard decoders are all for
vendor-specific GUIDs (HiSilicon, Ampere, NVIDIA and so on), so it has nothing
to match and stores the payload as raw bytes.

That is enough to prove detection and collection, and the bytes are readable by
hand against `struct cper_sec_proc_generic` (see the table in
[What a successful run looks like](#what-a-successful-run-looks-like)). It is not
a human-readable fault report. Producing one would mean teaching rasdaemon to
decode this GUID.

**Memory errors go through the hart bank too.** QEMU declares a separate DRAM
error bank at `0x4000000`, but no device is actually created for it — it exists
only as a device-tree node, and this platform boots via ACPI, so nothing is
listening there. Memory-class error codes are therefore written into a hart error
record, the same way CPU ones are.

**EDAC counters are not populated — and a CPU error can never populate them.**
`ce_count` belongs to a *memory controller*, and there is exactly one path to it:

```
ghes_do_proc()   if (guid_equal(sec_type, &CPER_SEC_PLATFORM_MEM))
  → ghes_report_chain → ghes_edac_report_mem_error() → edac_raw_mc_handle_error()
    → dimm->ce_count += e->error_count
```

Two things follow. Today no Platform Memory Error section is produced at all, so
`mc0` never appears — the pending firmware patch above fixes that for codes
18–21. But even then, a CPU-class code such as 17 will never reach this path,
because it is not a memory error. Any test that injects code 17 and expects
`ce_count` to increment is asking for two incompatible things.

**The recorded event cannot identify which RERI code was injected.** See
[the warning above](#-the-reri-error-code-does-not-survive-into-the-log). Any
test whose pass criterion is "the log contains N records of RERI error code X"
needs either a firmware change to carry the code into CPER, or a criterion
rewritten around what the record actually holds.

---

## See also

- [q-vela `docs/ras.md`](https://github.com/riscv-vela/q-vela/blob/main/docs/ras.md) — boot command and the RERI smoke test
- [vela-fws](https://github.com/riscv-vela/vela-fws) — firmware and root filesystem
- [vela-linux](https://github.com/riscv-vela/vela-linux) — kernel, including the RAS options
- [`../reri register generator/`](../reri%20register%20generator/) — spreadsheet for working out register bit fields
- [RERI specification](https://github.com/riscv-non-isa/riscv-ras-eri)
