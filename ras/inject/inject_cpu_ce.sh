#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# inject_cpu_ce.sh - inject a corrected CPU error.
#
# Named by the Vela test procedure (TSP TC.10.007), which asks for four
# corrected CPU errors twelve minutes apart under a sustained workload:
#
#     sudo ./inject_cpu_ce.sh -n 4 -i 720
#
# A thin wrapper over reri-inject so that the defaults live in one place and
# the name the test procedure refers to keeps working. Any reri-inject option
# can be appended and overrides the default, e.g. -e 12 for a hart state
# error or -v to read the code back.

set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INJECT=$DIR/reri-inject

if [ ! -x "$INJECT" ]; then
    echo "error: $INJECT is not built" >&2
    echo "       make -C '$DIR'" >&2
    exit 1
fi

# RERI code 17, internal datapath / execution unit error, corrected,
# implicit write. Arrives as CPER error_type 0x08, micro-architectural.
exec "$INJECT" -e 17 -s ce -t 7 "$@"
