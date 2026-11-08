#!/bin/bash
# 기능 분류: 설치 창 생성 · Developer ID 서명 · DMG 공증. 앱 번들은 변경하지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
MODE="${1:---preview}"
case "$MODE" in
    --preview) LABEL=preview ;;
    --notarize) LABEL=notarized; : "${SIGN_IDENTITY:?Developer ID Application 서명 ID를 지정하세요.}" ;;
    *) printf '사용법: bash scripts/package-dmg.sh --preview|--notarize [앱 경로] [DMG 경로]\n' >&2; exit 1 ;;
esac
APP="${2:-$PROJECT_ROOT/dist/ZCRE 서포터.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DESTINATION="${3:-$PROJECT_ROOT/dist/ZCRE-Supporter-$VERSION-macOS-universal-$LABEL.dmg}"
DMG_PYTHON="${DMG_PYTHON:-$PROJECT_ROOT/.build/dmg-design-tools/bin/python}"
if [ ! -x "$DMG_PYTHON" ]; then
    printf '먼저 가상환경에 scripts/requirements-dmg.txt를 설치하세요.\n' >&2; exit 1
fi
# 배경의 서명·공증 문구와 실제 포함 앱의 상태가 일치해야 한다.
codesign --verify --deep --strict "$APP"
SIGNATURE="$(codesign --display --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNATURE" != *"Authority=Developer ID Application:"* ]]; then
    printf '이 설치 디자인에는 Developer ID 서명된 앱이 필요합니다.\n' >&2; exit 1
fi
xcrun stapler validate "$APP"
"$DMG_PYTHON" scripts/make-dmg-background.py
/usr/bin/tiffutil -cathidpicheck Resources/Installer/background.png Resources/Installer/background@2x.png -out Resources/Installer/background.tiff
mkdir -p "$(dirname "$DESTINATION")" "$PROJECT_ROOT/.build/dmg-reports"
"$DMG_PYTHON" -m dmgbuild -s scripts/dmg-settings.py -D "root=$PROJECT_ROOT" -D "app=$APP" 'ZCRE 서포터 설치' "$DESTINATION"
if [ "$MODE" = --notarize ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DESTINATION"
    REPORT="$PROJECT_ROOT/.build/dmg-reports/$VERSION-$(date +%Y%m%d-%H%M%S).json"
    xcrun notarytool submit "$DESTINATION" --keychain-profile "${NOTARY_PROFILE:-zcre-notary}" --wait --output-format json > "$REPORT"
    if [ "$(plutil -extract status raw -o - "$REPORT")" != Accepted ]; then
        printf 'DMG 공증 실패. 결과: %s\n' "$REPORT" >&2; exit 1
    fi
    xcrun stapler staple "$DESTINATION"
    xcrun stapler validate "$DESTINATION"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DESTINATION"
fi
printf '\n설치 파일 생성: %s\n' "$DESTINATION"
