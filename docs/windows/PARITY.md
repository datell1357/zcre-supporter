# Windows 기능 일치 및 검증표

기준: macOS 0.2.20 (23), 소스 커밋 3ca8093. 이 문서는 요구사항이며 구현 또는 검증 완료 증거가 아닙니다.
각 행은 Windows 구현 파일, 자동 검사 결과, 실제 화면/실행 결과, 미검증 사유를 함께 기록해야 합니다.

| ID | 요구사항 | macOS 근거 | 통과 조건 |
|---|---|---|---|
| W01 | 단일 실행, 트레이, 종료·재실행 | App.swift | 두 번째 실행 시 중복 펫/폴링 없음; 기존 앱 종료 후 새 바이너리 실행 |
| W02 | 로그인·계정 전환·연결 해제 | WebSession.swift, ObserveSession.js | 실제 로그인 후 잔액 조회; 이전 계정 데이터 미노출; 해제 시 기록 삭제 |
| W03 | 세션 경계 | PendingWebSnapshot.swift, WebSession.swift | 외부 출처의 메시지 거절; 계정 전환 중 늦은 응답 폐기; 토큰은 웹 내부 유지 |
| W04 | 5초 작업 감시 | RefreshPolicy.swift, ReadSnapshot.js | 대기 중에도 조회; 느린 응답 중첩 금지; 수동 갱신 동일 제한 |
| W05 | 크레딧 정산 | ReadSnapshot.js | 60초 조회; 작업 변경 직후 및 15초 후속 감시; 실패 시 잔액 갱신 지연 표시 |
| W06 | 재시도·잠자기·오프라인 | RefreshPolicy.swift, CompanionStore.swift | 지수 지연 최대 300초; Retry-After 준수; 복귀 분산; 중복 루프 없음 |
| W07 | 누락 없는 작업 추적 | Monitor.swift, ReadSnapshot.js | 첫 페이지 밖 미완료 ID 추적; 동일 작업 수의 작업 교체 감지; 조회 실패를 작업 실패로 오인하지 않음 |
| W08 | 완료·실패·크레딧 알림 | Monitor.swift, NotificationService.swift | 최초 기준선 과거 작업 알림 금지; 이후 전이별 1회; 모델·매체·시작 시각 표시 |
| W09 | 알림 저장·계정 격리 | AlertHistoryArchive.swift, CompanionAlert.swift | 최신 10개, 상세 최대 30개; 계정 격리; 전체 지우기 후 과거 기록 재등장 방지 |
| W10 | 작업별 알림·집중 모드 | Preferences.swift, AlertPreferencesTests.swift | 이미지/영상/업스케일/오디오/기타 필터; 밤을 넘는 일정 및 동일 시작/종료 시각 처리 |
| W11 | 기본 현황 3열 | ActiveJobsView.swift, MenuBarView.swift, ServiceStatusView.swift | 진행 목록·크레딧/알림·서비스 상태 일치; 창 중복 없음 |
| W12 | 서비스 상태 | ServiceStatusStore.swift, PublicStatusSchedule | 열린 동안 60초; 재개방 캐시; 수동 최소 5초; ETag/304; 오래된 상태는 확인 중 |
| W13 | 결과 보기·저장 | JobOutputs.swift, JobResultView.swift, ReadOutputs.js | 일반 생성/업스케일/이미지/영상/오디오; HTTPS URL 검증; 사용자 저장 대화상자; 실패 표시 |
| W14 | 펫 모션 | ZicSprites.swift, RabbitView.swift | 기존 PNG/JSON 그대로; 대기/8방향/좌우 잡힘/작업/완료/울기/손 흔들기 |
| W15 | 이동·드래그·방향 | PetController.swift, PetGeometry.swift | 무작위 8방향; 목덜미 앵커; 작업 중 산책 정지; 화면 중앙 바라봄; DPI별 떨림 없음 |
| W16 | 원형 메뉴·간단 현황 | PetQuickMenu.swift, PetQuickMenuLayout.swift | 펫·작업 글씨 보호; 가장자리 재배치; 56pt 메뉴 긴 이름 두 줄; 전 도구 URL 일치 |
| W17 | 숨김·배율·표시 | Preferences.swift, PetController.swift | 숨김 시 모션/음향 중지, 데이터 유지; 70~150%; 크레딧 표시 설정 |
| W18 | 작업 표시줄 트레이 | MenuBarActivityIcon.swift | 작업 중 네 발 달리기; 상태 종료 후 정지; Windows 트레이 제약에 맞는 잔액 표시 |
| W19 | 효과음 공존 | PetSoundController.swift, OtherAudioActivity.swift | 드래그 1회; 타자 1초/휴식 5초; 타 앱 재생·통화 시 억제; 음량 0~100%; 장치 설정 불변 |
| W20 | 설정·자동 시작 | SettingsView.swift, LoginItemController.swift | 활성 토글 색상; 설정 유지; 시작 프로그램 기본 꺼짐; 사용자 변경 반영 |
| W21 | 디버그·데모 | MotionTestView.swift, PetActionTest.swift | zcrenext로 실행 중 활성화; 8방향 2초, 작업 6초; 실계정/알림 변화 없음; 종료 후 비활성 |
| W22 | 진단 내보내기 | DiagnosticsExporter.swift | 토큰/잔액/계정/작업ID/프롬프트/결과URL 제외; 자동 전송 없음 |
| W23 | Windows 환경 | Windows 실기기 | DPI 100/125/150/200%, 다중 화면, 음수 좌표, 절전 복귀, 재시작, 설치·업데이트·제거 |
| W24 | 권한·패키징 | Windows 실기기 | 일반 사용자 실행; 인증정보 없는 ZIP/설치 파일; 서명/SmartScreen 상태 정직하게 표시 |

## 증거의 구분

1. 컴파일 성공은 UI·네트워크·계정 기능 통과가 아닙니다.
2. 모의 응답 테스트와 실제 계정 전이는 따로 기록합니다.
3. 사용자의 로그인 없이 실계정 확인을 통과 처리하지 않습니다. 유료 생성은 별도 승인 없이 수행하지 않습니다.
4. 스크린샷에 실제 계정·잔액·작업 내용이 있으면 공개 저장소에 업로드하지 않습니다.
5. Windows 트레이는 macOS 메뉴 바와 달리 아이콘 옆 임의 텍스트를 기본 지원하지 않습니다. 툴팁/현황판으로의 대응과 차이를 명시하며, 임의 축소 구현을 기능 동등성 완료로 처리하지 않습니다.
6. 실패한 항목은 원인과 재현 절차를 남기며 '버그 없음'이라는 결론을 내리지 않습니다.
