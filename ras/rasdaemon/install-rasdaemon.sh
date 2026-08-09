#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# install-rasdaemon.sh - build, install and enable rasdaemon on a Vela guest.
#
# Run on the Ubuntu guest, not on the host: the binary must be native RISC-V.
#
#
# Why not "apt install rasdaemon"
# -------------------------------
# Ubuntu 24.04 ships 0.8.0-2, and rasdaemon decides at configure time which
# events it can handle. --enable-non-standard is off by default and is not
# guaranteed in the distro build. On this platform ras:non_standard_event is
# the only event produced, so a build without it runs cleanly and records
# nothing at all.
#
# --enable-reri is deliberately left off. rasdaemon 0.8.5 has the option and
# subscribes to ras:reri_event, but that tracepoint does not exist in the
# vela-linux kernel. Enabling it only makes the build look supported.
#
#
# Why the systemd unit is installed by hand
# -----------------------------------------
# Upstream generates misc/rasdaemon.service from a template (Makefile.am
# all-local) but has no install rule for it - distro packaging has always
# done that step. A source build therefore leaves you with a binary and no
# service, which is how "rasdaemon -f -r &" ends up in people's notes.

set -eu

RASDAEMON_VERSION=${RASDAEMON_VERSION:-v0.8.5}
RASDAEMON_REPO=${RASDAEMON_REPO:-https://github.com/mchehab/rasdaemon}
WORKDIR=${WORKDIR:-$HOME/rasdaemon-build}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 1)}
NO_START=0

SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
    cat <<'EOF'
Usage: install-rasdaemon.sh [-d DIR] [-j N] [-V VERSION] [-n] [-h]

  -d DIR        build directory        (default $HOME/rasdaemon-build)
  -j N          parallel make jobs     (default nproc)
  -V VERSION    git tag to build       (default v0.8.5)
  -n            install but do not start the service
  -h            this help

Needs network access for apt and git.
EOF
}

while getopts 'd:j:V:nh' opt; do
    case "$opt" in
        d) WORKDIR=$OPTARG ;;
        j) JOBS=$OPTARG ;;
        V) RASDAEMON_VERSION=$OPTARG ;;
        n) NO_START=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO=sudo
else
    SUDO=
fi

echo "==> rasdaemon $RASDAEMON_VERSION -> $WORKDIR"

echo "==> build dependencies"
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool pkg-config git patch \
    libtraceevent-dev libsqlite3-dev

# ras-mc-ctl is Perl and reads the record database through DBD::SQLite. It is
# not needed to build or to run the daemon, only to read what it collected,
# so a missing DBI only shows up later as "Can't locate DBI.pm in @INC".
$SUDO apt-get install -y --no-install-recommends libdbd-sqlite3-perl

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ -d rasdaemon/.git ]; then
    echo "==> reusing checkout, resetting to $RASDAEMON_VERSION"
    cd rasdaemon
    git fetch --tags --depth 1 origin "$RASDAEMON_VERSION"
    git checkout -f "$RASDAEMON_VERSION"
    git clean -fdx
else
    echo "==> cloning $RASDAEMON_REPO"
    git clone --depth 1 --branch "$RASDAEMON_VERSION" "$RASDAEMON_REPO"
    cd rasdaemon
fi
BUILD_TREE=$PWD

echo "==> adding the RISC-V generic processor error decoder"
cp "$SRC_DIR/riscv-decoder/non-standard-riscv.c" "$BUILD_TREE/"
cp "$SRC_DIR/riscv-decoder/non-standard-riscv.h" "$BUILD_TREE/"
patch -p1 --forward --batch \
      < "$SRC_DIR/riscv-decoder/0001-build-add-riscv-ns-decoder.patch"

echo "==> autoreconf"
autoreconf -vfi

echo "==> configure"
./configure \
    --prefix=/usr/local \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --enable-non-standard \
    --enable-riscv-ns-decode \
    --enable-sqlite3

# Both of these are the reason for building from source. Without the first,
# the handler for ras:non_standard_event is not compiled in and the daemon
# records nothing. Without the second, it records 192 bytes of hex.
for def in HAVE_NON_STANDARD HAVE_RISCV_NS_DECODE; do
    if ! grep -q "^#define $def 1" config.h; then
        echo "error: $def is not set in config.h after configure" >&2
        echo "       see config.log" >&2
        exit 1
    fi
    echo "    $def confirmed"
done

echo "==> build"
make -j"$JOBS"

echo "==> install"
$SUDO make install

# make install generates misc/rasdaemon.service but never installs it.
if [ ! -f misc/rasdaemon.service ]; then
    echo "error: misc/rasdaemon.service was not generated" >&2
    exit 1
fi

# The unit carries EnvironmentFile= with no leading dash, so a missing file
# is a hard start failure. install-data-local normally puts it in place;
# check for it here rather than discover it from a failed systemctl start.
ENVFILE=$(sed -n 's/^EnvironmentFile=-\{0,1\}//p' misc/rasdaemon.service)
if [ -n "$ENVFILE" ] && [ ! -f "$ENVFILE" ]; then
    echo "==> $ENVFILE is missing, installing it"
    $SUDO install -D -m 0644 misc/rasdaemon.env "$ENVFILE"
fi

echo "==> installing the systemd unit"
$SUDO install -D -m 0644 misc/rasdaemon.service \
      /etc/systemd/system/rasdaemon.service
$SUDO install -D -m 0644 "$SRC_DIR/systemd/10-vela.conf" \
      /etc/systemd/system/rasdaemon.service.d/10-vela.conf

$SUDO systemctl daemon-reload

if [ "$NO_START" -eq 1 ]; then
    echo
    echo "Installed but not started. Start it with:"
    echo "    sudo systemctl enable --now rasdaemon"
    exit 0
fi

echo "==> enabling and starting"
$SUDO systemctl enable --now rasdaemon

sleep 2
if $SUDO systemctl is-active --quiet rasdaemon; then
    echo
    echo "rasdaemon is running:"
    $SUDO systemctl --no-pager --lines=0 status rasdaemon || true
else
    echo >&2
    echo "error: rasdaemon did not stay running." >&2
    $SUDO journalctl -u rasdaemon --no-pager --lines=30 >&2 || true
    exit 1
fi

cat <<'EOF'

It is now a real service: it survives your shell exiting, restarts if it
dies, and comes back after a reboot.

    systemctl status rasdaemon
    journalctl -u rasdaemon -f
    ras-mc-ctl --errors

Records go to /var/lib/rasdaemon/ras-mc_event.db.
EOF
