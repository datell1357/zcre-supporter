# ZCRE 서포터 0.2.20 (23) 출시 준비 결과

기준일: 2026-10-26. 웹 직접 배포와 Mac App Store 두 경로를 준비한다.
**현재는 검증된 로컬 후보이며 공개 배포·스토어 제출 완료 상태가 아니다.**

## 완료

- 자동 검사 150개: Swift Testing 55+38, XCTest 9, 웹 브리지 43, 스토어 프로파일 Python 5.
- 배포 절차가 테스트 실패 시 패키징을 중단하도록 변경. 아키텍처·서명 무결성·Hardened Runtime·필수 리소스·매니페스트·위험한 서명 예외를 번들에서 검사한다.
- 웹용 로컬 Universal ZIP, SHA-256, JSON, preflight 결과, 테스트 로그 생성.
- 별도 App Sandbox 후보 빌드: 네트워크 클라이언트·사용자 선택 파일 읽기/쓰기만 추가. 기본 앱의 로그인 데이터·설정은 변경하지 않았다.
- 스토어 앱/설치 인증서·프로파일 검증 후 PKG 생성하는 스크립트 준비. 만료·개발용·다른 App ID·Team 불일치 프로파일을 거절한다.
- README·배포 안내·개인정보 초안·스토어 메타데이터를 현재 버전으로 갱신.
- ZCRE 팀의 승인 여부는 사용자 확인을 반영. 제출할 증빙의 범위는 별도 보관 필요.

## 서비스 부하 확인

실서버에 작업을 생성하지 않고 모의 응답으로 검증했다. 정상 1시간은 작업 조회 720회(5초), 크레딧 조회 60회(60초)였다.
초기 1,000개 초과 기록은 작업 목록 20회+잔액 1회, 최근 목록 밖 미완료 3개는 한 주기에 작업 요청 4회였다.
이 결과는 WebKit 로그인/사이트 자체 통신과 공개 서비스 상태 요청을 포함한 총 트래픽 또는 서버 수용량 보증이 아니다.

## 산출물

- `dist/ZCRE-Supporter-0.2.20-universal-local.zip`
- 같은 접두사의 `.json`, `.sha256`, `.preflight.json`, `.tests.log`
- `dist/sandbox-test/ZCRE 서포터.app` 및 `preflight.json`, `tests.log`
- `scripts/release.sh --notarize`: 인증서 준비 후 직접 배포용 공증
- `scripts/store-build.sh --package`: 스토어 인증서·프로파일 준비 후 PKG

샌드박스 후보는 정적 검증만 통과했다. 기존 사용자 앱과 같은 식별자이므로 이 Mac의 로그인 환경에서 임의 실행하지 않았다.

## 출시를 막는 항목

1. 유효한 서명 인증서 0개. Apple Developer 팀 등록, Developer ID Application, 스토어 앱/설치 인증서와 프로파일 필요.
2. 공개 개인정보 정책·지원 URL, 운영자/판매자 명의·문의처, 가격·배포 지역 확정 필요. 문서의 미확정 값은 임의로 채우지 않았다.
3. App Sandbox의 로그인·설정/알림 이관·다운로드·자동 실행·CoreAudio 상태 조회를 최종 서명 후보에서 확인해야 한다.
4. Apple Silicon/Intel, macOS 14 및 최신 OS에서 신규 설치·업데이트·잠자기 복귀·오프라인·계정 전환 검증 필요.
5. 실제 완료/실패 알림 전달과 결과 재생·저장, 작업별 알림/집중 모드 종단 간 확인 필요. 자동 모의 검사를 실계정 검증으로 계산하지 않는다.
6. 웹 배포: 공증 승인·티켓·Gatekeeper·다운로드한 사본 최초 실행. 스토어: 업로드 validation·TestFlight·심사.
7. 스토어 스크린샷·영상 후보는 이전 0.2.16 촬영 기반. 최종 UI와 맞춰 갱신해야 한다. 기존 홍보영상은 변경하지 않았다.

## 개인정보와 심사

네이티브 자동 분석 서버는 없으나 ZCRE 로그인 WebView와 미디어 서버의 처리는 개인정보 라벨에서 별도 확인해야 한다.
'수집 없음'으로 임의 확정하지 않았다. 심사 계정은 소유자의 개인 계정 대신 전용 테스트 계정을 App Store Connect의 보안 입력란에 제공한다.
디버그 코드 메뉴는 심사 노트에 공개되어 있다. 코드 잠금은 보안 경계가 아니다.

## 실행 장애와 구분

이전 Finder/새 앱 실행 장애는 재시동 뒤 같은 앱으로 복구됐고, NoMachine 업데이트 후 재시작 루프도 관찰되지 않았다.
이 결과는 배포 인증서·공증 요구를 대체하지 않으며 다른 Mac의 장시간 안정성을 입증하지 않는다.

공식 참고:
- https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution
- https://developer.apple.com/developer-id/
- https://developer.apple.com/app-store/app-privacy-details/
