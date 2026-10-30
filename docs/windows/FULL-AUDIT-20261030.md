# Windows와 macOS 전체 기능 비교 · 2026-10-30 KST

Windows는 핵심 계정·작업·결과 어댑터와 주요 데스크톱 동작 검사를 통과했다. 이번 비교에서 원형 메뉴의 연결 전 진입점과 캐시된 크레딧의 지연 표시 누락을 재현해 수정했다. **모든 기능의 실제 동작과 macOS 동등성을 완료한 상태는 아니다.** 실제 서버 완료·실패 전이, 일부 포인터 경로, 설치·Windows 11·다중 DPI 환경은 아래처럼 미검증으로 남긴다.

## 기준과 증거 수준

- Windows 최종 소스: `72bbeba636cd901861506c398e761af05d090775`, `feature/windows-port`. 시작 시 작업 트리는 깨끗했고 실행 중인 ZCRE는 없었다.
- macOS 최신 main: [fa3afe6d7b1f30c3c54eb8c5b2db96e58ce8e572](https://github.com/datell1357/zcre-supporter/commit/fa3afe6d7b1f30c3c54eb8c5b2db96e58ce8e572). GitHub 연결 도구로 이번에 다시 확인했다. 원격 브랜치를 병합하거나 로컬 macOS 파일을 수정하지 않았다.
- 로컬 macOS 원본 3ca8093에서 최신 main까지 14개 커밋의 비교 결과, `Sources` 변경은 PetQuickMenu.swift와 PetQuickMenuLayout.swift 두 파일이다. 최신 원형 메뉴 소스는 원격에서 읽었고, 나머지 공통 소스·리소스는 원본과의 동일성을 대조했다. 캔버스·홈 6개/50 DIP 배치는 Windows에 이미 반영돼 있다.
- 실제 장치: Windows 10 IoT Enterprise LTSC, 10.0.19044, x64. 실제 화면 1024×768, 작업 영역 1024×728, 100% 배율. 현재 토큰은 관리자 승격 상태가 아니었다. macOS 앱 실행·Swift 테스트는 Windows에서 수행하지 않았다.

표의 **소스**는 구현 대조, **자동**은 합성 입력의 정책·브리지 검사, **네이티브**는 실제 Windows API/WPF/WebView2 실행, **화면·입력**은 실제 창과 도구 입력 후 관측을 뜻한다. 네이티브 이벤트나 런타임 상태를 모든 물리적 입력·픽셀·실계정 전이의 증거로 바꾸어 표시하지 않는다.

## 기능별 비교

| ID | 영역·macOS 근거 | Windows 구현과 이번 증거 | 차이·남은 범위 |
| --- | --- | --- | --- |
| W01 | 시작·단일 실행·종료 — App.swift | App.xaml.cs의 Mutex/이벤트. 실제 데모 PID 51528 실행 중 두 번째 PID 42832는 종료 코드 0으로 끝났고 기존 프로세스 하나만 남았다. Ctrl+Q로 설정·모션 창과 본체를 정상 종료했다. 최종 패키지도 별도 실행·정상 종료했다. | 사용자 로그인 직후 자동 실행·OS 재부팅은 미검증. |
| W02 | 로그인·계정 — WebSession.swift, CompanionStore.swift | WebSession.cs. 보존된 앱 전용 세션에서 실제 크레딧·작업과 기존 완료 결과 메타데이터를 다시 읽었다. 이번 검사는 CompanionStore를 만들지 않아 설정·알림 파일을 쓰지 않는다. 조회 전후 바이트 일치 확인. | 신규 OAuth 로그인·로그아웃·계정 전환 UI는 이번에 반복하지 않았다. 이전 수동 로그인/계정 일치 검사는 LAYOUT-20261030.md 참조. 인증값·계정값은 공개하지 않았다. |
| W03 | 세션 신뢰 경계 — PendingWebSnapshot.swift, WebSession.swift | 공통 JS와 WebSession.cs, BridgeEpoch. 출처·세대·ACK·늦은 응답·계정 변경·혼합 데이터 거절 자동 검사 통과. 토큰은 페이지 안에서 사용하며 네이티브 스냅샷으로 전달하지 않는다. | 실제 사용자 계정 전환 중 경합을 새로 유발하지 않았다. 전체 침투 테스트나 의존성 취약점 전수 감사는 아니다. |
| W04 | 작업 5초 — RefreshPolicy.swift, ReadSnapshot.js | 동일 JS 사용. C# AccountSchedule의 최소 5초·느린 요청 중첩 방지와 JS의 정상/대기 조회·동일 작업 수의 교체 감지 검사 통과. | 이번 실계정 세션을 65초 이상 패킷 추적해 실제 전송 간격을 재측정하지 않았다. |
| W05 | 크레딧 60초·정산 15초 — ReadSnapshot.js | 동일 JS의 60초 재조회·상태 변경 직후·15초 후속 확인·잔액 실패 시 작업 최신 유지·계정별 캐시 검사 통과. 실계정의 유효 잔액 스냅샷도 확인. | 실제 결제·유료 생성 후 정산 전이는 만들지 않았다. |
| W06 | 재시도·절전·오프라인 — RefreshPolicy.swift, CompanionStore.swift | 최대 300초 지수 지연·Retry-After·재개 분산 자동 검사. 실제 WebView2 초기화 실패 후 재시도, 공유 중복 초기화 방지 네이티브 검사 통과. Windows 전원·세션 이벤트 연결은 소스 확인. | 실제 네트워크 차단·절전·잠금/해제·브라우저 프로세스 강제 충돌 복구는 미검증. 네이티브 Store.Sleep 호출은 실제 OS 절전이 아니다. |
| W07 | 작업 추적 — Monitor.swift | Monitor.cs 및 공통 JS. 첫 페이지 밖 미완료 ID, 페이지 중복, 삭제/미상 상태, 이전 완료 기준선, 동일 작업 수의 교체, 계정 격리의 공통 fixture/자동 검사 통과. | 실제 장시간 대량 작업 부하·실시간 서버 전이는 미검증. |
| W08 | 완료·실패·크레딧 알림 — Monitor.swift, NotificationService.swift | Monitor/AlertPolicy/App/TrayIcon. 전이별 1회·첫 조회 기준선·작업 정보·필터 정책 자동 검사. Windows Shell이 로컬 무음 알림 요청을 수락했다. 실제 숨김 데모의 로컬 테스트 배너와 집중 모드의 테스트 억제를 화면에서 확인. | 실제 서버 완료/실패 → 시스템 배너/소리/클릭까지 종단 간 검증은 미완료. Shell 수락은 실제 배너 표시 보증이 아니다. |
| W09 | 알림 이력 — AlertHistoryArchive.swift | History/CompanionStore/Dashboard. 최근 10개·상세 최대 30개, 원시 ID 대신 해시, 계정 격리, 지운 과거 기록 재등장 방지 자동 검사 통과. 실계정 기록은 보존했다. | 실사용 이력 지우기·연결 해제는 실행하지 않았다. |
| W10 | 종류별 알림·집중 — Preferences.swift | Policies/AlertPolicy. 이미지·영상·업스케일·오디오·기타, 대소문자, 자정 넘는 일정·동일 시작/종료·끝 시각 제외 검사 통과. 실제 UI에서 집중을 켜면 로컬 테스트가 억제되고 안내가 보임. | 실제 시간 경계까지 대기하거나 업무 중 시스템 알림을 발생시키지는 않았다. |
| W11 | 현황판 — MenuBarView.swift, ActiveJobsView.swift | 기본 980×600, 31/35/34 열 비율. 실제 상단 3열 화면 확보. 네이티브 980→720→640→496→980 DIP 재배치·글자·제목 정렬·마지막 동작 도달 검사 통과. 800 DIP 미만은 한 열. | Windows의 작은 창 한 열은 추가 대응이다. 실제 전체 현황판 캡처는 확보하지 못했다. Mac과 픽셀 단위 일치를 주장하지 않는다. |
| W12 | 서비스 상태 — ServiceStatusStore/View.swift | ServiceStatus.cs: 열린 동안 60초, 재개방 캐시·수동 최소 5초·조건부 요청·오래된 상태 확인 중 처리. 실제 API 200, 21개 모델, stale=false, 스키마 검사 통과. 실제 현황판에 서비스 행이 보였다. | 이번 응답은 ETag/Last-Modified가 없어 실제 304는 미검증. Mac의 상태 개수 요약·개별 새로고침과 Windows의 큰 카드·전역 새로고침은 UX 차이다. |
| W13 | 결과 재생·저장 — JobOutputs/JobResultView.swift | MediaPreview/DashboardWindow. 실제 보존 세션의 HTTPS 결과 메타데이터 조회 통과. 기존에 저장된 영상의 바이트 동일 복사본 94,393,682바이트를 WebView2에서 720×1282로 디코딩, 음소거 재생 시간 진행(약 1.47초) 확인. CSP·문서 전환 차단·종료 후 늦은 메시지 무시도 통과. | 이번에는 서버 미디어를 새로 저장하지 않았다. 실제 저장 대화상자 완료·모든 이미지/오디오/업스케일 형식 재생·만료 링크 실패 UI는 미검증. Mac은 네이티브 미디어, Windows는 격리 WebView2를 사용한다. |
| W14 | 지크 모션 — ZicSprites.swift, RabbitView.swift | 원본 리소스 32개 바이트 동일, 13종 로드. 실제 UI 버튼으로 8방향·대기·좌우 잡힘·작업·완료·실패·손 흔들기 상태 확인. 네이티브 프레임 간 변환 객체 재사용 검사 통과. | 각 프레임의 시각·타이밍·감속 모션을 모두 촬영한 것은 아니다. 완료/울기는 디버그 동작이며 실제 서버 알림 증거가 아니다. |
| W15 | 드래그·이동 — PetController.swift, PetGeometry.swift | 실제 몸체 포인터 드래그 전후 위치 변화와 저장 좌표 (100,240)→(198,261)를 확인. 이동 후 몸체 클릭으로 홈 메뉴도 열렸다. 방향·목덜미 앵커·산책 중지·프레임 배치는 소스/자동 검사. | 연속 드래그 동안 떨림·커서와 매 프레임 일치·실제 모든 모니터 경계·무작위 장시간 산책은 미검증. |
| W16 | 원형 메뉴·목적지 — 최신 PetQuickMenu.swift, PetQuickMenuLayout.swift | 홈 6·이미지 8·영상 6개, 아이콘·두 줄 제목·접근성 이름·호버/포커스. 네이티브 20개 버튼·13개 공식 경로·뒤로/닫기·요약 갱신·외부 활성화 닫힘 통과. 실제 홈 클릭·화면 확인. 연결 전 버튼과 지연 표시는 이번에 수정. | 하위 메뉴의 실제 포인터·시각 검증은 여전히 미완료. Windows에 Mac의 원호 장식은 없다. SF Symbols와 Windows 벡터 그림·폰트는 다르다. |
| W17 | 숨김·크기·표시 — Preferences.swift, PetController.swift | 실제 설정 클릭으로 지크가 사라졌다가 다시 표시됨. 숨김 시 오디오 중지 자동 검사. 70/100/150% 실제 WPF 메뉴 프레임 18경우 통과. | 실제 슬라이더 모든 값의 시각·실제 Windows 배율 전환은 미검증. |
| W18 | 트레이 — MenuBarActivityIcon.swift | TrayIcon/TrayPopupHost. Shell 아이콘 사각형과 아래 작업표시줄 실제 HWND 배치, 프레임·작업표시줄 버튼 부재, 외부 활성화 닫힘 네이티브 검사 통과. 정상 대기/작업 애니메이션 전환 소스 확인. | 물리적 트레이 클릭·탐색기 재시작·자동 숨김·상단/측면 작업표시줄은 미검증. 잔액은 Mac의 아이콘 옆 글자 대신 Windows 툴팁/현황판에 표시한다. |
| W19 | 효과음·다른 소리 — PetSoundController.swift, OtherAudioActivity.swift | PetAudio/PetSoundSchedule. 잡힘 1회·타자 1초 후 5초 휴식·0~100%·숨김 억제 자동 검사. 실제 별도 WAV 프로세스 피크를 감지해 타자 명령을 억제하고 종료 후 재개함. 오디오 내용 캡처·장치 음량 변경 없음. | 실제 통화 앱·모든 출력 장치·음량 체감·청취 검증은 미완료. Mac Core Audio와 Windows 세션/피크 API 차이. |
| W20 | 설정·자동 시작 — SettingsView.swift, LoginItemController.swift | 설정 저장·복원·오류 표시/회복·입력 정렬·스크롤·최대화 작업 영역·접근성 검사 통과. 실제 포인터 스크롤 및 일부 토글 확인. 시작 프로그램 기본 꺼짐·확인 대화상자·HKCU Run 구현은 소스 확인. | HKCU Run 변경·실제 로그인 자동 실행은 하지 않았다. Mac의 SMAppService와 Windows Registry 방식은 플랫폼 차이다. |
| W21 | 디버그·데모 — MotionTestView.swift, PetActionTest.swift | 실제 UI에서 로컬 디버그 활성화 및 모션 버튼 동작 확인. 가상 작업만 사용했고 실제 계정 앱은 실행하지 않았다. DebugEnabled는 실행 메모리에만 존재한다. | 데모 모션을 실계정 상태 전이로 세지 않는다. 새 실행에서 디버그가 꺼지는 것은 소스 확인이며 재시작 화면의 별도 캡처는 없다. |
| W22 | 진단 내보내기 — DiagnosticsExporter.swift | CompanionStore.Diagnostics/ExportDiagnostics: 버전·OS·연결 여부·개수·표시 설정만 내보내며 계정·잔액·ID·프롬프트·결과 URL·토큰을 포함하지 않는다. 자동 전송 경로 없음. | 실제 저장 대화상자를 완료하지 않았다. 기능 명세/소스 검토이며 전체 개인정보 감사 완료를 뜻하지 않는다. |
| W23 | 화면·배율·OS — PetGeometry/PopoverPlacement.swift | 실제 100% 작업 영역 안의 창, 360×480 설정과 496 DIP 현황판, 최대화/복원 검사. 합성 100/125/150/200%·음수 좌표·작은 화면·작업표시줄 방향 배치 검사 통과. | Windows 11, 실제 다중 모니터·혼합 DPI 이동·OS 배율 변경·절전 복귀는 미검증. 합성 좌표를 실제 하드웨어 검증으로 세지 않는다. |
| W24 | 패키지·설치·보안 — macOS build/release scripts | 새 self-contained win-x64 폴더 publish·격리 smoke·일반 토큰 실행 통과. 사용자 데이터 파일명 검사 0개, 원본 리소스 일치, 해시 기록. WebView2는 별도 런타임 필요. | Windows 설치/업데이트/제거 프로그램·서명·SmartScreen 평판은 제공하지 않는 개발 빌드다. 최종 exe는 NotSigned. Mac DMG 설치/실행도 Windows에서 검사하지 않았다. |

## 목적지 HTTP 확인의 범위

13개 경로는 최신 macOS와 같으며 네이티브 메뉴가 정확히 전달했다. 비인증 GET에서 HTML을 최대 1024바이트만 읽은 결과 전부 HTTPS 동일 호스트의 200에 도달했다. `/studio/audio`, `/studio/canvas`는 `/sign-in`으로 이동했다. 이는 로그인 후의 도구 사용 성공이나 해당 기능의 가용성을 증명하지 않는다. Accept 헤더 없이 추가 요청한 첫 경로는 404였고, 같은 HTML Accept 헤더로 다시 요청하면 로그인 이동을 확인했다. 이 차이는 두 플랫폼에 공통인 웹 응답 관측이며 Windows 경로를 임의로 바꾸지 않았다.

## 이번에 고친 결함과 남은 구현 차이

1. **연결 전 원형 메뉴에 연결 동작 없음.** Mac PetStatusView에는 연결 버튼이 있지만 Windows는 잔액 대시와 0개만 보였다. 실제 WPF 검사에서 `Disconnected radial summary omitted its account connection action.`을 재현했다. 요약의 예약 높이 104 DIP 안에 연결 버튼을 넣고, 검증된 스냅샷을 받으면 기존 창에서 숨기도록 했다. 연결 버튼을 실제 계정 로그인까지 클릭해 검사하지는 않았다.
2. **지연된 원형 메뉴 크레딧이 정상 값처럼 보임.** 실제 Store.Sleep 상태에서 `Paused radial summary presented its cached credits as fresh.`를 재현했다. 잔액 지연·절전·오프라인·연결 오류 시 주황색 ‘갱신 지연’으로 표시하고 회복 시 정상 문구로 돌린다. 회귀 검사 통과. 실제 OS 절전/네트워크 장애의 종단 간 시험은 별개다.
3. **조회 검사 자체의 이력 갱신 방지.** 기존 계정 검사가 CompanionStore를 거치던 것을 세션 어댑터 조회로 바꿨다. 실제 조회 성공과 전후 설정·알림 바이트 일치를 확인했다. 제품 계정 처리나 저장 형식은 바꾸지 않았다.

남은 차이 중 플랫폼상 대응은 Cmd/Ctrl, 메뉴바/작업표시줄 위치, 잔액 툴팁, 시스템 알림 API, 자동 시작 API, 네이티브 미디어/WebView2다. 다음은 플랫폼이 강제하는 차이로 포장하지 않는다: 원형 메뉴 원호 장식 부재, 요약의 카운터 아이콘·문자 구성 차이, 서비스 상태 개수 요약·개별 새로고침·카드 밀도 차이, Windows에서 지연/오류 증가를 모두 주황색으로 표시하는 차이. 기능 경로는 있어도 Mac과 시각적으로 같지 않다.

Windows의 알림 권한 직접 조회·승인 상태 표시는 Mac UNUserNotificationCenter와 동등하지 않다. 현재는 시스템 설정 링크와 전달 요청 수락/실패 안내를 제공한다. Windows 설치·업데이트·제거·서명 부재는 배포 준비의 미완료 사항이다. 원형 하위 메뉴·실제 서버 알림·저장 UI·다중 DPI를 미검증인 채로 기능 동등성 완료 처리하지 않는다.

로컬 커밋: `1466b12` 원형 요약 수정과 직접 회귀 검사, `72bbeba` 실계정 조회 검사에서 이력 보존. 공개 푸시·배포·main 병합·macOS 변경은 없다.

## 검사와 실행 증거

- 핵심 **963 assertions 통과**. 공통 디코더/모니터 fixture, 정밀 잔액·세션 경계·알림/집중·음향·좌표 행렬을 포함한다.
- 원본 JavaScript 브리지 **43 tests 통과**. 원격 main과 공통 JS가 변경되지 않았음을 대조했다.
- 실제 네이티브 **9개 검사 그룹**: 기본 OS/설정 저장, 메뉴, 트레이, 초기화·저장 오류 복구, 레이아웃, 미디어 문서 경계, 소리 공존, 보존 세션 조회, 저장된 영상 디코딩. 원형 요약 수정 후 메뉴와 레이아웃을 다시 통과했다.
- 최종 빌드 경고 0, 오류 0. 첫 core 명령은 저장소 인자를 빠뜨려 fixture 경로에서 시작 실패했고 올바른 절대경로 인자로 다시 실행했다. 수정 중의 임시 컴파일 오류와 회귀 실패는 최종 통과로 덮어 숨기지 않고 비공개 로그에 보존했다.
- 실제 UI 모션은 동/북동/북/북서/서/남서/남/남동, 대기, 잡힘 좌우, 작업·완료·실패·인사·중지를 관측했다. ‘서’가 처음 ‘북서’에 잘못 매칭된 자동화 선택은 정확한 라벨로 다시 실행했고 walk-side/왼쪽을 확인했다. 각 프레임이나 연속 이동 전부의 시각 검증은 아니다.

주요 비공개 증거는 `windows/.local/full-audit-20261030/`의 `native-results.json`, `summary-baseline.log`, `summary-v3.log`, `summary-final.log`, `build-final.log`, `layout-final.log`, `account-media-results.json`, `account-read.log`, `saved-media.log`, `service-live.json`, `tool-routes-http.json`, `tool-route-redirects.json`, `single-instance.json`, `motion-ui.json`, `environment.json`, `package-final.json`, `captures.json`이다. 핵심/브리지 로그는 상위 `.local/full-audit-core-v2-20261030.log`, `full-audit-bridge-20261030.log`에 있다. 계정값·미디어 내용이 포함될 수 있는 실행 프로필과 기존 영상은 공유하거나 Git에 넣지 않았다.

## 실제 캡처

Orca computer-use Windows provider 1.0.0으로 실제 창 영역을 촬영했다. 입력 성공은 `synthetic_input / unverified` 응답만으로 판정하지 않고 전후 화면·현재 UI 상태·격리 프로필의 저장 좌표를 함께 확인했다. 초기 위치만 설정 파일로 준비했고, 드래그 후 변화는 실제 포인터 입력 결과다.

투명 지크·메뉴·팝업은 선택 가능한 일반 창 목록에 나타나지 않는다. 같은 격리 앱의 설정 창 경계를 사용해 위에 겹친 실제 화면을 캡처했고, 일반 모션 창은 직접 캡처했다. 07은 1008×550 경계의 **현황판 상단 부분**이다. 전체 현황판이나 하위 메뉴 캡처로 주장하지 않는다. 오른쪽 아래 기존 알림이 포함되는 후보는 제외했다. 합성·덧칠·후처리 자르기·WPF RenderTargetBitmap 대체 없이 원본 PNG를 그대로 복사했다.

비공개 원본: `windows/.local/full-audit-20261030/captures/`.

| 파일명 접두어: zcre-windows-20261030-full-audit- | 크기 | 바이트 | SHA-256 |
| --- | --- | ---: | --- |
| 01-before-drag.png | 620×712 | 43,580 | `fe2dd0b29cb78b4f6ca5f5732488ba762007528c50365acf9e7bf0815a09f37d` |
| 02-after-drag.png | 620×712 | 44,143 | `42194e8992e3fb1d43a75873c94b940d251885a3a311892ee659c4d3fe9c13d6` |
| 03-home-after-drag.png | 620×712 | 52,295 | `183ac7fd5d2916111a0577a658c8b793a04276b2dbe6ef364cd64d4ece019a79` |
| 04-pet-hidden.png | 620×712 | 22,780 | `a29ae0941f33fc38222f11918b9414726eddf73e1c63b7c4e418bb0e14e0f383` |
| 05-local-demo-banner.png | 1008×550 | 20,146 | `9d2143187eea2a4db21371b6b82082166c12a17407d7339f4dc3e4201e94a191` |
| 06-focus-blocked.png | 1008×550 | 16,466 | `d438f7c07694930d2e911e7464838789ccfa18a2d83e5c01f2b4e6bbefc26bfd` |
| 07-dashboard-upper-partial.png | 1008×550 | 39,252 | `30a042e5518ae247f7042785e1ccc48b8168ecb3a4d7df83ca70956fed5ac74b` |
| 08-motion-working.png | 560×350 | 38,480 | `93ec17fae5d4b34d4e56a252a9341fa22eafc4f0ddd9ba2cf3ef4001863593c0` |

개인정보 없는 위 8장은 기존 사용자 Mac Studio로 Taildrop 전송했고 CLI 종료 코드 0을 확인했다. 이 보고서도 같은 경로로 전달한다. Mac에서의 최종 저장 위치·열기는 Windows에서 확인하지 않았다. 외부 공개 호스팅이나 저장소 이미지 추가는 하지 않는다.

## 최종 패키지와 보존 상태

패키지: `windows/artifacts/ZcreSupporter-full-audit-20261030/`. self-contained win-x64이며 WebView2 런타임은 별도 필요하다. 격리 smoke PID 3420, 종료 코드 0, 13종 스프라이트, 원본 리소스 32개 바이트 일치. Authenticode 상태는 **NotSigned**다.

| 파일 | SHA-256 |
| --- | --- |
| ZcreSupporter.exe | `0a3201bfc5806bd88aa3b2d4c8b6d83ce1f3f4b0ebbb9a4d616c54d112fe7020` |
| ZcreSupporter.dll | `7e9bb2bbd029b9717f02ad3e710b72f30036f3f779a78e3cfd5cbd1f26d99982` |
| ZcreSupporter.Core.dll | `3ccc68c67a6a85ca7b916bda38da2a2195aed0ba817d56d6bccc464e5779b0fc` |

패키지에서 Cookies, Login Data, Secure Preferences, preferences.json, RecentAlerts.json 파일명 검출은 0개였다. 이는 해당 파일 검사 결과이며 바이너리 전체에 대한 포렌식 인증이 아니다. 기존·신규 로그인 프로필은 남아 있고 설정·알림 파일은 각 보존본과 바이트 단위로 일치한다. 브라우저 SDK의 정상 세션 갱신까지 불변이라고 주장하지 않는다.

이번 데모 PID 51528과 smoke는 모두 정상 종료했다. 마지막 검사 시 ZCRE 프로세스는 0개다. 원본·사용자 계정·설정 삭제, 권한·보안 설정 변경, 유료 생성, 외부 발송, 공개 배포, main 병합은 하지 않았다. Taildrop은 사용자가 요청한 개인정보 없는 증거의 자기 기기 전달 범위에 한한다.
