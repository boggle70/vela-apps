#!/usr/bin/env bash
# ci/cross-build.sh — 교차빌드: sdk 를 RISC-V 툴체인으로 빌드하고 설치한다.  [미검증]
#
# 상태
#   CI 에서는 비활성이다(ci.yml 에서 cross-build-script 를 지정하지 않음).
#   RISC-V 툴체인 확보 방식이 정해지지 않았고, 이 스크립트가 성공하는 환경을 아직 확인하지 못했다.
#   Ubuntu 24.04 apt 의 gcc-riscv64-linux-gnu(GCC 13, 접두사 riscv64-linux-gnu-)에 접두사를 맞춰도
#   sdk/include/shared/sm_call.h 의 uintptr_t 미선언으로 C++ 컴파일이 실패하는 것을 확인했다.
#
# 무엇을 하나 (README.md "Build and install the SDK" 절차와 같다)
#   sdk/macros.cmake 의 use_riscv_toolchain 이 PATH 에서 riscv64-unknown-linux-gnu-gcc 를 찾는다.
#
# 제외
#   examples 는 빌드하지 않는다. examples/CMakeLists.txt 가 attestation 을 항상 포함하고,
#   attestation 은 vela-fws 의 fw_jump.bin(FW_BIN)이 필요한 레포 간 의존이라 PR CI 대상이 아니다.
#
# 필요 도구: cmake, make, riscv64-unknown-linux-gnu- 툴체인(PATH)
#
# 환경 변수
#   CI_BUILD_DIR : 빌드·설치 디렉터리(KEYSTONE_SDK_DIR). 기본값은 레포 밖이다.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v riscv64-unknown-linux-gnu-gcc >/dev/null 2>&1; then
  echo "riscv64-unknown-linux-gnu-gcc 가 PATH 에 없다." >&2
  exit 1
fi

build="${CI_BUILD_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vela-ci/cross-build}"
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

rm -rf "$build"
mkdir -p "$build"
export KEYSTONE_SDK_DIR="$build"
cmake -S sdk -B "$build"
cmake --build "$build" -j"$jobs"
cmake --install "$build"
