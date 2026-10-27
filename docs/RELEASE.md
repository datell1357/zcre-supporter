# 0.2.20 출시 준비

현재 버전 0.2.20 (23), 로컬 출시 준비 후보다. 정식 배포 승인·서명·공증 완료를 뜻하지 않는다.
2026-10-26 현재 유효한 코드 서명 인증서는 0개다. 브랜드·서비스 연동 승인은 사용자로부터 받았다고 확인했으며, 제출 시 증빙과 사용 범위를 보관한다.

## 재현 가능한 검증·패키징

앱을 완전히 종료한 뒤 실행한다. 실행 중인 앱은 자동 강제 종료하지 않는다.

```sh
bash scripts/test.sh
python3 scripts/preflight.py 'dist/ZCRE 서포터.app' --channel local
bash scripts/release.sh --local
```

release.sh는 회귀 테스트 → Universal 빌드 → 서명 무결성·번들 사전 검사 → ZIP·SHA-256·메타데이터 순서로 진행한다.
실패하면 해당 단계에서 중단한다. 결과에는 `.tests.log`와 `.preflight.json`이 함께 포함된다.
`local` 검사는 로컬 후보의 구조만 확인하며 공개 배포 가능 판정이 아니다.

## 공식 웹 직접 배포

Developer ID Application 인증서와 개인 키, notarytool Keychain 프로필이 필요하다.
자격 증명은 사용자가 Keychain에 설정하며 소스·로그에 적지 않는다.

```sh
SIGN_IDENTITY='Developer ID Application: 배포자 이름 (TEAMID)' \
NOTARY_PROFILE='zcre-notary' \
bash scripts/release.sh --notarize
```

이 명령은 Apple 공증 서버에 앱을 제출한다. 공증 Accepted·티켓 첨부·Gatekeeper 평가를 모두 통과한 뒤에만 notarized 패키지를 만든다.
배포 전 실제 다운로드한 사본을 별도 Mac에서 처음 열고 재실행까지 확인한다. SIP/Gatekeeper 해제나 격리 속성 삭제를 설치 절차로 사용하지 않는다.

## Mac App Store

직접 배포용 공증 경로와 별개다. App Sandbox, 배포 인증서·프로비저닝 프로파일, 스토어 업로드 검증이 필요하다.
기본 앱은 직접 배포용이다. 별도 샌드박스 후보는 최소 권한으로 빌드했으나 실제 계정·파일 저장·설정 이관의 런타임 검증은 아직 수행하지 않았다.

```sh
python3 scripts/preflight.py 'dist/ZCRE 서포터.app' --channel mac-app-store
```

이 검사는 샌드박스·스토어 서명·프로파일이 없으면 실패한다. 통과해도 Apple 업로드 검증·심사를 대신하지 않는다.
세부 준비 자료는 `store/2026-10-26/`에 있다. 스크린샷은 이전 버전 촬영 후보이므로 최종 제출 UI 대조가 필요하다.

## 설정·설치 호환성

Bundle ID `kr.co.zcre.bunny.prototype`과 실행 파일명 `ZCREBunny`는 기존 로그인·설정·알림 권한의 연속성을 위해 유지한다.
공식 배포자 Team ID와 이 식별자의 등록 가능 여부를 확인한 후 확정한다. 임의로 변경하지 않는다.
같은 배포 주체의 새 앱으로 교체하기 전 기존 앱을 완전히 종료한다. 계정·캐시를 삭제하지 않는다.
App Sandbox 전환은 WebKit·설정·알림 이력의 컨테이너 변경을 별도로 검증한다.
자동 업데이트는 구현하지 않았으므로 초기 직접 배포는 버전·체크섬을 제공하는 수동 교체 방식이다.

## 현재 검증과 남은 승인

`docs/PRODUCTION-0.2.20.md`에 테스트, 트래픽 모의 검사, 실제 실행 결과와 미검증 항목을 구분했다.
유료 생성, 외부 게시, Apple 제출, Developer 계정 가입·약관 동의는 이번 자동 점검에 포함하지 않는다.
개인정보 공개 URL·지원 URL·운영자 정보와 심사 계정은 실제 값을 확정해야 한다.

## 스토어 전용 후보 만들기

```sh
# 기존 앱을 종료한 뒤 별도 폴더에 로컬 샌드박스 후보만 생성
bash scripts/store-build.sh --local-sandbox

# 인증서와 프로파일 준비 후 서명된 업로드 후보 PKG 생성
APP_STORE_IDENTITY='Apple Distribution: 배포자 이름 (TEAMID)' \
APP_STORE_INSTALLER_IDENTITY='3rd Party Mac Developer Installer: 배포자 이름 (TEAMID)' \
APP_STORE_PROFILE='/절대/경로/AppStore.provisionprofile' \
bash scripts/store-build.sh --package
```

최소 권한은 App Sandbox, 외부 네트워크 클라이언트, 사용자가 선택한 파일의 읽기/쓰기다.
프로파일의 만료·개발/기기 한정 용도·App ID·Team 일치를 검사하고 서명 결과의 Team과 비교한다.
사용자 프로파일을 소스에 복사하지 않는다. 프로파일 해독 임시 파일은 0700 작업 폴더에서 처리 후 정리한다.
`dist/sandbox-test/`는 ad hoc 실험 후보, `dist/mac-app-store/`는 실제 인증서가 준비됐을 때 생성되는 PKG 경로다.
동일 Bundle ID이므로 기존 앱과 동시에 실행하지 않는다. 샌드박스 전환은 별도 테스트 계정/사용자 환경에서 먼저 검증한다.
`--package`는 업로드를 수행하지 않는다. 이후 Transporter/App Store Connect 업로드 검증과 TestFlight 실기기 확인이 필요하다.
