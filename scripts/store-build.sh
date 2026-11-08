#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
MODE="${1:-}"
case "$MODE" in
    --local-sandbox|--package) ;;
    *) printf '사용법: bash scripts/store-build.sh --local-sandbox | --package\n' >&2; exit 1 ;;
esac
# 동일 식별자의 실행 앱이 있으면 빌드·검증을 시작하지 않는다.
if pgrep -x ZCREBunny >/dev/null; then
    printf 'ZCRE 서포터를 완전히 종료한 뒤 실행하세요.\n' >&2; exit 1
else
    PROCESS_STATUS=$?
    if [ "$PROCESS_STATUS" -ne 1 ]; then exit 1; fi
fi
umask 077
mkdir -p "$PROJECT_ROOT/.build"
WORK="$(mktemp -d "$PROJECT_ROOT/.build/store-package.XXXXXX")"
PACKAGE_STAGE=""
trap 'rm -rf "$WORK"; if [ -n "$PACKAGE_STAGE" ]; then rm -rf "$PACKAGE_STAGE"; fi' EXIT
export ARCHS=universal
export DISTRIBUTION_CHANNEL=app-store
unset EMBEDDED_PROVISIONING_PROFILE
export SIGN_ENTITLEMENTS_FILE="$PROJECT_ROOT/Resources/AppStore.entitlements"
if [ "$MODE" = --package ]; then
    : "${APP_STORE_IDENTITY:?스토어 앱 서명 인증서를 지정하세요.}"
    : "${APP_STORE_INSTALLER_IDENTITY:?스토어 설치 패키지 서명 인증서를 지정하세요.}"
    : "${APP_STORE_PROFILE:?Mac App Store 프로비저닝 프로파일을 지정하세요.}"
    IDENTITIES="$(security find-identity -v)"
    if ! printf '%s\n' "$IDENTITIES" | grep -E 'Apple Distribution:|3rd Party Mac Developer Application:' | grep -Fq -- "$APP_STORE_IDENTITY"; then
        printf '유효한 스토어 앱 서명 인증서가 없습니다.\n' >&2; exit 1
    fi
    if ! printf '%s\n' "$IDENTITIES" | grep -F '3rd Party Mac Developer Installer:' | grep -Fq -- "$APP_STORE_INSTALLER_IDENTITY"; then
        printf '유효한 스토어 설치 패키지 인증서가 없습니다.\n' >&2; exit 1
    fi
    security cms -D -i "$APP_STORE_PROFILE" > "$WORK/profile.plist"
    python3 scripts/store_profile.py "$WORK/profile.plist" Resources/Info.plist Resources/AppStore.entitlements "$WORK/store.entitlements"
    export SIGN_IDENTITY="$APP_STORE_IDENTITY"
    export EMBEDDED_PROVISIONING_PROFILE="$APP_STORE_PROFILE"
    export SIGN_ENTITLEMENTS_FILE="$WORK/store.entitlements"
    export DIST_DIR="$PROJECT_ROOT/dist/mac-app-store"
    CHANNEL=mac-app-store
else
    export SIGN_IDENTITY=-
    export DIST_DIR="$PROJECT_ROOT/dist/sandbox-test"
    CHANNEL=sandbox-test
fi
bash scripts/test.sh > "$WORK/tests.log" 2>&1
bash scripts/build.sh
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)"
APP="$DIST_DIR/$APP_NAME.app"
python3 scripts/preflight.py "$APP" --channel "$CHANNEL" --output "$DIST_DIR/preflight.json"
cp "$WORK/tests.log" "$DIST_DIR/tests.log"
if [ "$MODE" = --package ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
    PKG="ZCRE-Supporter-$VERSION-MacAppStore.pkg"
    # productbuild가 경로 처리 오류에도 빈 페이로드로 성공할 수 있어 영문 임시 경로에서 묶는다.
    PACKAGE_STAGE="$(mktemp -d /private/tmp/zcre-store-package.XXXXXX)"
    PACKAGE_APP="$PACKAGE_STAGE/ZCRE Supporter.app"
    ditto --norsrc --noextattr "$APP" "$PACKAGE_APP"
    # 개인 키와 작업 폴더는 0700/0600을 유지하되 설치될 앱은 모든 사용자가 읽을 수 있어야 한다.
    python3 - "$PACKAGE_APP" <<'PY'
import sys
from pathlib import Path
app = Path(sys.argv[1])
for item in [app, *app.rglob('*')]:
    if not item.is_symlink():
        item.chmod(0o755 if item.is_dir() or item.stat().st_mode & 0o111 else 0o644)
PY
    # Apple이 발급한 다운로드 프로파일의 격리 메타데이터도 업로드 번들에는 허용되지 않는다.
    xattr -lr "$PACKAGE_APP" > "$WORK/attributes.txt"
    if grep -Fq 'com.apple.quarantine' "$WORK/attributes.txt"; then
        xattr -dr com.apple.quarantine "$PACKAGE_APP"
    fi
    codesign --verify --deep --strict "$PACKAGE_APP"
    productbuild --component "$PACKAGE_APP" /Applications --sign "$APP_STORE_INSTALLER_IDENTITY" "$WORK/$PKG"
    pkgutil --payload-files "$WORK/$PKG" > "$WORK/payload.txt"
    if ! grep -Fxq './ZCRE Supporter.app/Contents/MacOS/ZCREBunny' "$WORK/payload.txt"; then
        printf '앱 실행 파일이 패키지에 포함되지 않아 배포를 중단합니다.\n' >&2; exit 1
    fi
    pkgutil --check-signature "$WORK/$PKG"
    mv "$WORK/$PKG" "$DIST_DIR/$PKG"
    (cd "$DIST_DIR" && shasum -a 256 "$PKG" > "$PKG.sha256")
    printf '스토어 업로드 후보: %s/%s\nApple 업로드 검증과 심사는 별도입니다.\n' "$DIST_DIR" "$PKG"
else
    printf '샌드박스 로컬 후보: %s\n공개 배포·스토어 제출용이 아니며 기존 앱 데이터 이관을 아직 검증하지 않았습니다.\n' "$APP"
fi
