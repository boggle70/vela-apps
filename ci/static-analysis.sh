#!/usr/bin/env bash
# ci/static-analysis.sh — 정적분석: ci/ 아래 셸 스크립트를 shellcheck 로 검사한다.
#
# 범위
#   현재는 CI 스크립트(ci/*.sh)만 검사한다.
#   C/C++ 소스 검사(clang-format 등)는 기존 코드가 sdk/runtime 의 .clang-format 을 다수 위반하고 있어
#   적용 범위가 정해진 뒤 추가한다.
#
# 필요 도구: shellcheck (GitHub ubuntu-24.04 runner 에 기본 설치, 로컬은 apt/brew 로 설치)
#
# 로컬 실행: ci/static-analysis.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck 가 없다. apt install shellcheck 또는 brew install shellcheck 로 설치한다." >&2
  exit 1
fi

shellcheck --version | sed -n 2p
shellcheck ci/*.sh
echo "shellcheck: ci/*.sh 통과"
