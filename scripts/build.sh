#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 분류: 빌드 설정. 아키텍처·서명 방식·출력 경로를 명시적으로 정한다.
PROJECT_ROOT="$PWD"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"
ARCHS="${ARCHS:-$(uname -m)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
BUILD_OPTIONS=(--configuration release -debug-info-format none --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)
case "$ARCHS" in
    arm64|x86_64) BUILD_OPTIONS+=(--arch "$ARCHS") ;;
    universal) BUILD_OPTIONS+=(--arch arm64 --arch x86_64) ;;
    *) printf 'ARCHS는 arm64, x86_64 또는 universal이어야 합니다.\n' >&2; exit 1 ;;
esac
# 신규 버전 테스트 전 기존 프로세스가 완전히 종료됐는지 빌드 시작 전에 확인한다.
if pgrep -x ZCREBunny >/dev/null; then
    printf '기존 ZCRE 프로세스가 남아 있습니다. 앱을 완전히 종료한 뒤 빌드하세요.\n' >&2
    exit 1
else
    PROCESS_STATUS=$?
    if [ "$PROCESS_STATUS" -ne 1 ]; then
        printf '프로세스 종료 여부를 확인할 수 없어 빌드를 시작하지 않습니다.\n' >&2
        exit 1
    fi
fi
mkdir -p "$DIST_DIR" "$PROJECT_ROOT/.build"
# 동시 패키징을 막아 서로 다른 빌드가 같은 앱 번들을 덮어쓰지 않게 한다.
LOCK="$PROJECT_ROOT/.build/package.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    printf '패키징이 이미 진행 중입니다. 실행 중인 빌드가 없다면 .build/package.lock을 확인하세요.\n' >&2
    exit 1
fi
STAGING=""
DESTINATION="$DIST_DIR/$APP_NAME.app"
# 실패하면 보관해 둔 이전 앱을 복원하고 이 실행의 임시 폴더와 잠금만 정리한다.
cleanup() {
    if [ -n "$STAGING" ] && [ ! -e "$DESTINATION" ] && [ -d "$STAGING/previous.app" ]; then
        if ! mv "$STAGING/previous.app" "$DESTINATION"; then
            printf '이전 앱을 복원하지 못했습니다. 보존 위치: %s/previous.app\n' "$STAGING" >&2
            rmdir "$LOCK"
            return
        fi
    fi
    if [ -n "$STAGING" ] && [ -d "$STAGING" ]; then rm -rf "$STAGING"; fi
    rmdir "$LOCK"
}
trap cleanup EXIT
# 분류: 컴파일과 번들 조립. 실행 파일·개인정보 선언·스프라이트 등 필수 리소스를 함께 묶는다.
swift build "${BUILD_OPTIONS[@]}"
BIN_DIR="$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"
STAGING="$(mktemp -d "$DIST_DIR/.package.XXXXXX")"
APP="$STAGING/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ZCREBunny" "$APP/Contents/MacOS/ZCREBunny"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
# 스토어 프로파일은 명시한 후보에만 포함한다. 일반 배포/기존 사용자 앱에는 적용하지 않는다.
if [ -n "${EMBEDDED_PROVISIONING_PROFILE:-}" ]; then
    cp "$EMBEDDED_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi
RESOURCE_BUNDLE="$BIN_DIR/ZCREBunny_ZCREBunny.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  printf '리소스 번들이 없습니다: %s\n' "$RESOURCE_BUNDLE" >&2
  exit 1
fi
ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/ZCREBunny_ZCREBunny.bundle"
swift scripts/make-icon.swift "$PROJECT_ROOT/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_ROOT/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
# 분류: 코드 서명. 로컬 서명과 배포용 인증서 서명을 구분한다.
if [ "$SIGN_IDENTITY" = "-" ]; then
    SIGN_OPTIONS=(--force --sign - --timestamp=none)
else
    SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY" --timestamp)
fi
# 안쪽 리소스부터 서명하며 강화된 런타임을 약화하는 권한은 추가하지 않는다.
codesign "${SIGN_OPTIONS[@]}" "$APP/Contents/Resources/ZCREBunny_ZCREBunny.bundle"
APP_SIGN_OPTIONS=()
if [ -n "${SIGN_ENTITLEMENTS_FILE:-}" ]; then
    plutil -lint "$SIGN_ENTITLEMENTS_FILE"
    APP_SIGN_OPTIONS+=(--entitlements "$SIGN_ENTITLEMENTS_FILE")
fi
codesign "${SIGN_OPTIONS[@]}" "${APP_SIGN_OPTIONS[@]}" --options runtime "$APP"
codesign --verify --deep --strict "$APP"
# 실행 중인 앱의 리소스를 교체하지 않도록 안전하게 중단한다.
if pgrep -x ZCREBunny >/dev/null; then
    printf '새 빌드는 완료했지만 실행 중인 앱을 교체하지 않았습니다. %s를 종료한 뒤 다시 빌드하세요.\n' "$APP_NAME" >&2
    exit 1
else
    PROCESS_STATUS=$?
    if [ "$PROCESS_STATUS" -ne 1 ]; then
        printf '앱 실행 상태를 확인할 수 없어 기존 앱을 교체하지 않았습니다.\n' >&2
        exit 1
    fi
fi
# 새 번들 설치가 완료될 때까지 기존 앱을 임시 보관한다.
if [ -e "$DESTINATION" ]; then mv "$DESTINATION" "$STAGING/previous.app"; fi
if ! mv "$APP" "$DESTINATION"; then
    if [ -d "$STAGING/previous.app" ]; then mv "$STAGING/previous.app" "$DESTINATION"; fi
    exit 1
fi
# dist에 같은 앱이 두 이름으로 남지 않도록 이전 제품명의 번들은 보관 위치로 옮긴다.
LEGACY_APP="$DIST_DIR/ZCRE Bunny.app"
if [ "$DESTINATION" != "$LEGACY_APP" ] && [ -d "$LEGACY_APP" ]; then
    LEGACY_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY_APP/Contents/Info.plist" 2>/dev/null || true)"
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
    if [ "$LEGACY_ID" = "$BUNDLE_ID" ]; then
        mkdir -p "$PROJECT_ROOT/.build/previous-apps"
        LEGACY_BACKUP="$(mktemp -d "$PROJECT_ROOT/.build/previous-apps/legacy.XXXXXX")"
        mv "$LEGACY_APP" "$LEGACY_BACKUP/"
    fi
fi
printf '\n빌드 완료: %s (%s)\n' "$DESTINATION" "$ARCHS"
