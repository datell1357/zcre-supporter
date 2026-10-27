#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
# 웹 배포에는 별도 스토어 후보의 프로파일·권한 설정을 섞지 않는다.
unset SIGN_ENTITLEMENTS_FILE EMBEDDED_PROVISIONING_PROFILE
# 분류: 로컬 패키지와 Apple 공증 배포를 명시적으로 구분한다.
MODE="${1:-}"
case "$MODE" in
    --local) export SIGN_IDENTITY=-; NOTARIZED=false; LABEL=local ;;
    --notarize)
        : "${SIGN_IDENTITY:?Developer ID Application 서명 ID를 지정하세요.}"
        : "${NOTARY_PROFILE:?notarytool에 저장한 Keychain 프로필 이름을 지정하세요.}"
        if [ "$SIGN_IDENTITY" = "-" ]; then printf '공증에는 Developer ID Application 인증서가 필요합니다.\n' >&2; exit 1; fi
        # 빌드 전에 신뢰 가능한 배포 인증서가 있는지 확인해 로컬 서명을 배포로 오인하지 않는다.
        IDENTITIES="$(security find-identity -v -p codesigning)"
        if ! printf '%s\n' "$IDENTITIES" | grep -F 'Developer ID Application:' | grep -Fq -- "$SIGN_IDENTITY"; then
            printf '유효한 Developer ID Application 인증서를 찾을 수 없습니다. 배포자 인증서를 준비한 뒤 다시 실행하세요.\n' >&2
            exit 1
        fi
        NOTARIZED=true; LABEL=notarized ;;
    *) printf '사용법: bash scripts/release.sh --local | --notarize\n' >&2; exit 1 ;;
esac
export ARCHS="${ARCHS:-universal}"
export DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"
if pgrep -x ZCREBunny >/dev/null; then
    printf 'ZCRE 서포터를 완전히 종료한 뒤 실행하세요.\n' >&2; exit 1
else
    PROCESS_STATUS=$?
    if [ "$PROCESS_STATUS" -ne 1 ]; then exit 1; fi
fi
# 검증 실패한 코드를 패키징하지 않는다. 테스트는 모의 서버 응답만 사용한다.
mkdir -p "$PROJECT_ROOT/.build/release-checks"
TEST_LOG="$PROJECT_ROOT/.build/release-checks/tests.log"
if ! bash scripts/test.sh > "$TEST_LOG" 2>&1; then
    printf '회귀 검증 실패로 배포를 중단합니다. 기록: %s\n' "$TEST_LOG" >&2
    exit 1
fi
bash scripts/build.sh
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)"
APP="$DIST_DIR/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
NAME="ZCRE-Supporter-$VERSION-$ARCHS-$LABEL"
WORK="$(mktemp -d "$DIST_DIR/.release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# 분류: 공증. 사용자 지정 Keychain 프로필을 사용하며 인증서나 비밀값을 소스에 저장하지 않는다.
if [ "$MODE" = "--notarize" ]; then
    SIGNATURE="$(codesign --display --verbose=4 "$APP" 2>&1)"
    if [[ "$SIGNATURE" != *"Authority=Developer ID Application:"* ]]; then
        printf 'Developer ID Application 서명이 아닙니다. 공증을 중단합니다.\n' >&2
        exit 1
    fi
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/submission.zip"
    mkdir -p "$PROJECT_ROOT/.build/notarization"
    REPORT="$PROJECT_ROOT/.build/notarization/$VERSION-$BUILD.json"
    xcrun notarytool submit "$WORK/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$REPORT"
    STATUS="$(plutil -extract status raw -o - "$REPORT")"
    if [ "$STATUS" != Accepted ]; then
        printf 'Apple 공증이 승인되지 않았습니다. 기록: %s\n' "$REPORT" >&2
        exit 1
    fi
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi
CHECK_CHANNEL=local
if [ "$MODE" = "--notarize" ]; then CHECK_CHANNEL=developer-id; fi
python3 scripts/preflight.py "$APP" --channel "$CHECK_CHANNEL" --architectures "$ARCHS" --output "$WORK/$NAME.preflight.json"
cp "$TEST_LOG" "$WORK/$NAME.tests.log"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$NAME.zip"
codesign --verify --deep --strict "$APP"
# 서명·공증 성공 이후에만 최종 배포 파일을 출력 위치로 이동한다.
# 분류: 전달 검증. 버전·아키텍처·서명 정보와 압축 파일의 SHA-256을 기록한다.
python3 - "$APP" "$WORK/$NAME.zip" "$WORK/$NAME.json" "$NOTARIZED" <<'PY'
import hashlib, json, pathlib, plistlib, subprocess, sys
app, archive, destination = map(pathlib.Path, sys.argv[1:4])
with (app / 'Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
digest = hashlib.sha256()
with archive.open('rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
sha = digest.hexdigest()
architectures = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/ZCREBunny')], text=True).strip().split()
report = dict(name=info['CFBundleDisplayName'], version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
              bundleIdentifier=info['CFBundleIdentifier'], minimumMacOS=info['LSMinimumSystemVersion'],
              architectures=architectures, notarized=sys.argv[4] == 'true', hardenedRuntime=True,
              signing='Developer ID Application' if sys.argv[4] == 'true' else 'ad hoc',
              archive=archive.name, sha256=sha, functionalTests='scripts/test.sh passed; live account and OS notification delivery not covered')
destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
archive.with_suffix('.sha256').write_text(f'{sha}  {archive.name}\n')
PY
for extension in zip json sha256 preflight.json tests.log; do mv "$WORK/$NAME.$extension" "$DIST_DIR/$NAME.$extension"; done
printf '\n패키지: %s/%s.zip\n' "$DIST_DIR" "$NAME"
