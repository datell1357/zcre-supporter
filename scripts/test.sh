#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
# 분류: 로컬 회귀 검증. Swift 상태·좌표·리소스 테스트 후 모의 응답 기반 브리지 테스트를 실행한다.
swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
node --test Tests/BridgeTests/*.test.mjs
python3 -m unittest discover -s Tests/ReleaseTests -v
