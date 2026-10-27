# 한국어 소스 안내

기준: ZCRE 서포터 0.2.9 (11), 2026-10-26. 기능·함수별 한국어 주석과 큰 파일의 책임별 MARK 구역을 추가했다. 원래 식별자·공개 모델 형식은 유지했다.

## 읽는 순서

| 기능 | 주요 파일 | 책임 |
| --- | --- | --- |
| 실행·창·메뉴 | Sources/ZCREBunny/App.swift | 앱 생명주기, 단일 현황판, 설정 관찰, 잠자기 |
| 데이터 상태 | Sources/ZCREBunny/CompanionStore.swift | 모든 화면의 동일 스냅샷, 5초 스케줄, 알림 이력 |
| 웹 인증 | Sources/ZCREBunny/WebSession.swift, PendingWebSnapshot.swift | WebKit 로그인, 취소·시간 제한, 계정 전환 |
| 실제 API 읽기 | Sources/ZCREBunny/Resources/ReadSnapshot.js, ObserveSession.js | 허용 출처·GET 경로, 페이지 조회, 잔액 캐시, 세션 관찰 |
| 공통 데이터 | Sources/ZCRECore/Models.swift, Monitor.swift | 엄격한 응답 검증, Decimal 잔액, 상태 전이와 중복 알림 방지 |
| 조회 일정 | Sources/ZCRECore/RefreshPolicy.swift | 계정 5초·공개 상태 60초 캐시·수동 최소 간격·재시도 시각 |
| 공개 상태 | Sources/ZCREBunny/ServiceStatusStore.swift, ServiceStatusView.swift; Sources/ZCRECore/ServiceStatus.swift | 계정과 독립된 공개 상태 조회와 집계 신선도 |
| 지크 이동 | Sources/ZCREBunny/PetController.swift; Sources/ZCRECore/PetGeometry.swift | 화면 좌표 드래그, 8방향 산책, 작업 중 이동 정지 |
| 모션 렌더링 | Sources/ZCREBunny/RabbitView.swift, ZicSprites.swift; Sources/ZCRECore/SpriteTiming.swift | 모션 우선순위, 프레임 캐시, 신장·목덜이 기준점 |
| 효과음 | Sources/ZCREBunny/PetSoundController.swift, OtherAudioActivity.swift, Resources/Sounds/ | 붙잡힘 단발, 짧은 타자, 다른 오디오 감지 시 중단 |
| 설정·테스트 UI | Sources/ZCREBunny/Preferences.swift, SettingsView.swift, PetActionTest.swift, MotionTestView.swift | 설정 저장, 디버그 UI, 로컬 모션 재생 |
| 현황 표시 | Sources/ZCREBunny/PetStatusView.swift, MenuBarView.swift, DashboardView.swift, RecentAlertsView.swift | 약식 현황, 최근 10개, 보관 전체 30개 |
| 알림·저장 | Sources/ZCREBunny/NotificationService.swift, CompanionAlert.swift, AlertHistoryArchive.swift, MenuBarAlertController.swift | macOS 권한, 로컬 이력, 숨김 시 배너 |
| 진단·자동 실행 | Sources/ZCREBunny/DiagnosticsExporter.swift, LoginItemController.swift | 허용 항목만 로컬 내보내기, macOS 로그인 항목 |
| 빌드·검증 | scripts/, Tests/, Package.swift | 리소스 번들, 서명·공증, 모의 응답 기반 테스트 |

## 데이터 흐름

`WebSession → ReadSnapshot.js → SnapshotDecoder → CompanionStore → Monitor → 화면/알림`

크레딧은 Decimal, 진행 개수는 공통 API 작업 목록을 사용한다. 웹 DOM에서는 동시 생성의 요금제 한도만 사용한다. 지크를 숨겨도 데이터 감시는 계속되며 렌더링·이동·효과음만 멈춘다.

공개 서비스 상태는 별도 `ServiceStatusStore`가 담당한다. 현황판이 열린 동안 60초 간격이며, 재개방 캐시·수동 5초 간격·Retry-After를 `RefreshPolicy.swift`와 공유한다. 반영한 최적화는 `OPTIMIZATION-0.2.9.md`에 정리했다.

## 효과음

`PetController → ZicMotion.resolve → PetSoundController → 번들 WAV`

- 홍보영상 음악 없는 효과음 트랙에서 붙잡힘 0.6초, 타자 4초를 추출했다. 출처·SHA-256·구간·피크는 `Sources/ZCREBunny/Resources/Sounds/provenance.json`에 있다.
- 기본값은 사용·35%이며 `설정 → 지크 효과음`에서 즉시 변경하고 로컬에 저장한다. macOS 알림 소리와 별개다.
- 표시 모션을 기준으로 짧은 타자를 재생하므로 드래그·완료·실패가 우선할 때 멈춘다. 남은 작업이 있으면 재개한다. 디버그의 좌우 붙잡힘·작업 모션에도 적용한다.
- 지크 컨트롤러 하나가 재생을 소유한다. 설정 창의 작은 지크, 메뉴 막대 아이콘, 여러 뷰에서 중복 재생하지 않는다.
- 웹 요청 없이 작업 모션 중에만 재생을 예약한다. 약 1초 재생 후 5초 쉬며, 재생 중 다른 오디오는 0.5초 간격으로 확인한다. `OtherAudioActivity.swift`는 CoreAudio의 실행 여부만 조회하고 오디오 캡처·장치 설정 변경은 하지 않는다.
- `scripts/extract-pet-sounds.py`는 원본 효과음 WAV가 있을 때만 재추출에 사용한다. 빌드에는 포함된 WAV만 있으면 된다. 전달용 소스 ZIP에는 홍보영상 원본을 넣지 않는다.

## 실행과 검증

```sh
bash scripts/test.sh
node scripts/review-traffic.mjs
bash scripts/build.sh
# Apple Silicon·Intel 로컬 배포 패키지
bash scripts/release.sh --local
```

빌드 전에 실행 중인 ZCRE 서포터를 종료해야 한다. 배포 스크립트는 실행 중인 앱이나 실행 상태를 확인할 수 없는 앱을 덮어쓰지 않는다. 테스트는 실제 계정 생성·결제·삭제 요청을 보내지 않는다. 음향 상태 테스트는 무음 대역을 사용하며 실제 스피커 청취를 대체하지 않는다.

0.2.8의 주석·효과음 작업 이후 0.2.9에서 실제 조회 일정을 최적화했다. 한국어 주석을 유지했으며 변경 사항과 남은 서버 계약은 `OPTIMIZATION-0.2.9.md`, 모션·오디오 동작은 `MOTION-AUDIO-0.2.9.md`를 따른다.
