#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# inject_mem.sh - inject a memory error.
#
#     sudo ./inject_mem.sh -a 0x80000000
#
# A physical address is mandatory: OpenSBI only builds a CPER Memory Error
# section when addr_i is non-zero (lib/utils/ras/ghes.c). Nothing is written
# to that address, it is only reported. On the QEMU virt machine RAM starts
# at 0x80000000.
#
#
# Read this before trusting the output
# ------------------------------------
# At the OpenSBI revision vela-fws pins, reri_drv.c sets
#
#     einfo.etype = ERROR_TYPE_GENERIC_CPU;
#
# unconditionally, so a memory-class RERI code still arrives as a CPER
# Generic Processor Error with error_type 0x08, "micro-architectural error".
# Verified by injecting code 20: the record was byte for byte identical to
# code 17.
#
# Hayong Jeong (@AngryOvO) has a patch pending upstream that selects the
# memory section type for RERI codes 18-21 and fixes OpenSBI's cper_mem2_sec
# layout to match what Linux parses. With it this script produces a real
# memory error section; without it, it behaves like inject_cpu_ce.sh and
# addr_i is reported but not acted on. The address is written either way -
# harmless now, required once the patch lands.
#
# Use a corrected severity unless you mean it: an uncorrected error at a live
# address can make the kernel take the page offline once that patch is in.

set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INJECT=$DIR/reri-inject

if [ ! -x "$INJECT" ]; then
    echo "error: $INJECT is not built" >&2
    echo "       make -C '$DIR'" >&2
    exit 1
fi

case " $* " in
    *" -a "*) ;;
    *)
        echo "error: -a ADDRESS is required" >&2
        echo "       OpenSBI skips the memory section when addr_i is zero" >&2
        echo "       e.g. sudo $0 -a 0x80000000" >&2
        exit 2
        ;;
esac

# RERI code 20, system memory data error, corrected, explicit write.
exec "$INJECT" -e 20 -s ce -t 5 "$@"
