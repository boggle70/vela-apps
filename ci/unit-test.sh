#!/usr/bin/env bash
# ci/unit-test.sh — 단위시험: runtime/test (cmocka) 를 호스트 컴파일러로 빌드하고 ctest 로 실행한다.
#
# 대상
#   프로젝트 시험 3개: test_string, test_merkle, test_pageswap
#   동봉 cmocka 가 함께 등록하는 예제 시험 6개도 같이 실행된다.
#
# 필요 도구: cmake(3.20 이상, ctest --test-dir), gcc, g++, make
#   GitHub ubuntu-24.04 runner 에는 기본 설치되어 있다.
#   runtime/test/CMakeLists.txt 의 project() 가 언어를 지정하지 않아 C++ 컴파일러도 필요하다.
#
# 로컬 실행
#   Linux : ci/unit-test.sh
#   macOS : test_merkle, test_pageswap 이 Linux 헤더(malloc.h, linux/ioctl.h)를 써서 빌드되지 않는다.
#           Docker 로 runner 와 같은 Ubuntu 24.04 에서 실행한다.
#     docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src ubuntu:24.04 bash -c \
#       'apt-get update && apt-get install -y cmake gcc g++ make && ci/unit-test.sh'
#
# 환경 변수
#   CI_BUILD_DIR : 빌드 디렉터리. 기본값은 레포 밖($RUNNER_TEMP, $TMPDIR 또는 /tmp 아래)이다.
#
# 참고
#   - 동봉 cmocka(runtime/test/cmocka/CMakeLists.txt)는 configure 때마다 소스 디렉터리에
#     compile_commands.json 심볼릭 링크를 만든다. 빌드 디렉터리(레포 밖)를 가리키므로 configure 직후 지운다.
#   - -DCMAKE_POLICY_VERSION_MINIMUM=3.5 : CMake 4.x 는 cmake_minimum_required(VERSION 3.0) 을 거부한다.
#     이 옵션으로 CMake 4.4.4 에서 configure 통과, CMake 3.28.3(Ubuntu 24.04 apt)에서 빌드·시험 통과를 확인했다.
set -euo pipefail

cd "$(dirname "$0")/.."

src=runtime/test
build="${CI_BUILD_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vela-ci/unit-test}"
link="$src/compile_commands.json"

# 이 스크립트가 만든 링크만 지운다 (사용자가 직접 만든 링크는 건드리지 않는다).
remove_cmocka_link() {
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$build/compile_commands.json" ]; then
    rm -f "$link"
  fi
}
trap remove_cmocka_link EXIT

jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

rm -rf "$build"
cmake -S "$src" -B "$build" -DCMAKE_POLICY_VERSION_MINIMUM=3.5
remove_cmocka_link
cmake --build "$build" -j"$jobs"
ctest --test-dir "$build" --output-on-failure
