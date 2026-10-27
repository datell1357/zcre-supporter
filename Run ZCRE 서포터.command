#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)"
APP="$PWD/dist/$APP_NAME.app"
if [ ! -d "$APP" ]; then
  bash scripts/build.sh
fi
# 정상 실행 오류를 숨기거나 별도 프로세스로 우회하지 않는다.
if ! open "$APP"; then
  printf 'macOS에서 앱을 열지 못했습니다. 오류를 확인하고 남은 프로세스를 정리한 뒤 다시 시도하세요.\n' >&2
  exit 1
fi
