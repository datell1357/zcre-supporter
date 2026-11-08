# macOS 업데이트

설정 → 업데이트에서 자동 감지 여부, 확인 결과와 새 버전 다운로드를 제공한다. 이 구현은 macOS 개발본용이며 기존 배포 파일이나 App Store 심사 빌드를 자동 교체하지 않는다.

- 직접 배포본: 시작 시와 12시간마다 공개 GitHub `releases/latest` JSON을 확인한다. ZCRE 계정·작업·잔액은 전송하지 않는다. 작업 5초/크레딧 60초 감시와 독립적이다.
- 정식 숫자 버전만 비교하고 시험판·같은 버전·낮은 버전은 업데이트로 취급하지 않는다. 같은 태그의 DMG 재업로드만으로는 감지하지 않으므로 다음 변경은 새 버전 태그로 배포해야 한다.
- 새 버전은 현황판 배너와 설정에 표시한다. 다운로드는 사용자가 버튼을 누를 때만 수행한다.
- 해당 저장소의 HTTPS macOS DMG 중 아키텍처가 맞고 GitHub SHA-256 digest가 있는 파일만 허용한다. 파일 크기·다운로드 출처·SHA-256을 대조한 뒤 임시 설치 파일을 열 수 있다. 실패하면 기존 앱은 유지한다.
- 현재는 설치 파일을 열어 Applications에서 교체하는 안내형 업데이트다. 실행 중 앱의 무인 교체·자동 재실행은 구현하지 않는다. OS 보안 검증·공증을 우회하지 않는다.
- App Store 빌드는 `ZCREDistribution=app-store`로 표시한다. 영수증이 아직 없는 심사/샌드박스 후보도 GitHub 업데이트를 실행하지 않는다. 설정에는 App Store 업데이트 열기만 제공한다.
- 잠자기 시 확인 타이머와 다운로드를 취소하며 깨운 후 확인 간격을 유지한다. 오프라인에는 확인하지 않는다. 확인 버튼은 최소 60초 제한, 성공 후 12시간, GitHub 403/429 후 최소 1시간 재시도 대기를 유지한다.

검증: 숫자 버전·시험판/다운그레이드 제외, 저장소·HTTPS·아키텍처·해시 형식 제한, App Store 외부 조회 차단 테스트. 공식 릴리즈 DMG 실제 다운로드·SHA-256·macOS 격리 출처 속성도 검증했으며 테스트 파일은 삭제했다. 앱 교체·재실행은 수행하지 않았다. 실제 새 버전 교체는 다음 릴리즈 설치 파일로 별도 검증해야 한다.

명시적 다운로드 검증: `ZCRE_LIVE_UPDATE_TEST=1 swift test --disable-sandbox --filter AppUpdateTests` (약 54MiB 다운로드, 설치/실행 없음). 일반 테스트에서는 이 네트워크 검사를 건너뛴다.

참고: [GitHub release API](https://docs.github.com/en/rest/releases/releases), [Apple macOS 배포 경로](https://developer.apple.com/macos/distribution/).
